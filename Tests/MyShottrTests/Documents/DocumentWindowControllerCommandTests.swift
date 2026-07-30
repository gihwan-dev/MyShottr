import AppKit
import XCTest
@testable import MyShottr

@MainActor
final class DocumentWindowControllerCommandTests:
    TemporaryDirectoryTestCase
{
    func testDocumentCommandsAreInstalledOnTheWindowResponderChain() throws {
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(text: "Command routing"),
            projectURL: nil
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.nextResponder === controller)
        XCTAssertTrue(controller.responds(to: #selector(DocumentWindowController.copyComposite(_:))))
        XCTAssertTrue(controller.responds(to: #selector(DocumentWindowController.saveProjectAction(_:))))
        XCTAssertTrue(controller.responds(to: #selector(DocumentWindowController.exportComposite(_:))))
        XCTAssertFalse(controller.copyComposite(nil))
        XCTAssertFalse(controller.saveProjectAction(nil))
        XCTAssertFalse(controller.exportComposite(nil))
    }

    func testErrorPresentationTerminatesWhenTheDocumentWindowIsUnavailable() throws {
        let presenter = SpyUserFacingErrorPresenter()
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(text: "Missing error window"),
            projectURL: nil,
            errorPresenter: presenter
        )
        controller.window = nil

        XCTAssertTrue(controller.present(.pngExport))
        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.pngExport.viewModel]
        )
        XCTAssertEqual(presenter.windowWasProvided, [false])
    }

    func testErrorPresentationForDocumentUsesItsExistingWindowExactlyOnce()
        throws
    {
        let presenter = SpyUserFacingErrorPresenter()
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(text: "Document error"),
            projectURL: nil,
            errorPresenter: presenter
        )

        XCTAssertTrue(controller.present(.projectSave))

        XCTAssertEqual(
            presenter.presentedViewModels,
            [MyShottrUserFacingError.projectSave.viewModel]
        )
        XCTAssertEqual(presenter.windowWasProvided, [true])
    }

    func testRecoveryCleanupRetrySurvivesWindowCloseAndRequeuesOnFailure()
        throws
    {
        let presenter = SpyUserFacingErrorPresenter()
        let cleanup = RecoveryCleanupAttemptSpy(
            failuresRemaining: 1
        )
        var operation: RecoveryCleanupOperation? =
            cleanup.operation(
                documentIDs: [
                    ProjectFixtures.documentID,
                ]
            )
        weak var releasedOperation = operation
        var window: NSWindow? = NSWindow()
        RecoveryCleanupRetryCoordinator(
            operation: try XCTUnwrap(operation),
            presenter: presenter,
            window: window
        ).present()
        operation = nil

        NotificationCenter.default.post(
            name: NSWindow.willCloseNotification,
            object: window
        )
        window = nil
        XCTAssertNotNil(releasedOperation)

        presenter.performNextRetry()

        XCTAssertEqual(
            presenter.presentedViewModels.map(\.primaryAction),
            [.retrySameOperation, .retrySameOperation]
        )
        XCTAssertEqual(presenter.windowWasProvided.count, 2)
        XCTAssertNotNil(releasedOperation)

        presenter.performNextRetry()

        XCTAssertEqual(
            cleanup.attemptCount,
            2
        )
        XCTAssertTrue(presenter.retryActions.isEmpty)
        XCTAssertNil(releasedOperation)
    }

    func testCloseSaveRaceKeepsWindowOpenUntilLatestRevisionIsSaved()
        async throws
    {
        let initial = ProjectFixtures.project(text: "initial")
        let firstSave = ProjectFixtures.project(
            text: "first save"
        )
        let latest = ProjectFixtures.project(text: "latest")
        let recoveryRoot = temporaryDirectory
            .appendingPathComponent(
                "Recovery",
                isDirectory: true
            )
        let recoveryStore = try RecoveryStore(
            root: recoveryRoot
        )
        let clock = ManualRecoveryClock()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        try session.open(project: initial)
        try session.applySnapshot(firstSave.annotationJSON)
        await clock.advance(by: .seconds(2))
        let projectStore = CapturingProjectStore()
        var snapshotRequestCount = 0
        var closeRequestCount = 0
        let controller = try DocumentWindowController(
            project: initial,
            projectURL: temporaryDirectory
                .appendingPathComponent(
                    "Race.myshottr",
                    isDirectory: true
                ),
            projectStore: projectStore,
            recoveryStore: recoveryStore,
            testSession: session,
            annotationSnapshotProvider: {
                snapshotRequestCount += 1
                if snapshotRequestCount == 1 {
                    try session.applySnapshot(
                        latest.annotationJSON
                    )
                    return firstSave.annotationJSON
                }
                return latest.annotationJSON
            },
            pendingChangesDecisionProvider: {
                .save
            },
            closeWindow: {
                closeRequestCount += 1
            }
        )
        let window = try XCTUnwrap(controller.window)

        XCTAssertFalse(
            controller.windowShouldClose(window)
        )
        await waitUntil {
            projectStore.savedProjects.count == 1
        }

        XCTAssertEqual(
            projectStore.savedProjects[0].annotationJSON,
            firstSave.annotationJSON
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            latest.annotationJSON
        )
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(closeRequestCount, 0)

        await clock.advance(by: .seconds(2))
        XCTAssertEqual(
            try recoveryStore.scanRecoverableProjects()
                .projects.first?.project.annotationJSON,
            latest.annotationJSON
        )

        XCTAssertFalse(
            controller.windowShouldClose(window)
        )
        await waitUntil {
            closeRequestCount == 1
        }

        XCTAssertEqual(
            projectStore.savedProjects.map(\.annotationJSON),
            [
                firstSave.annotationJSON,
                latest.annotationJSON,
            ]
        )
        XCTAssertFalse(session.isModified)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<1_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for async document state")
    }
}

private final class CapturingProjectStore:
    ProjectPackageStoring,
    @unchecked Sendable
{
    private(set) var savedProjects: [MyShottrProject] = []

    func load(from url: URL) throws -> MyShottrProject {
        throw CapturingProjectStoreError.unexpectedLoad
    }

    func save(
        _ project: MyShottrProject,
        to url: URL
    ) throws {
        savedProjects.append(project)
    }
}

private enum CapturingProjectStoreError: Error {
    case unexpectedLoad
}

@MainActor
private final class SpyUserFacingErrorPresenter:
    UserFacingErrorPresenting
{
    private(set) var presentedViewModels:
        [UserFacingErrorViewModel] = []
    private(set) var windowWasProvided: [Bool] = []
    private(set) var retryActions: [
        () -> Void
    ] = []

    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?
    ) {
        presentedViewModels.append(error.viewModel)
        windowWasProvided.append(window != nil)
    }

    func present(
        _ error: RetryableUserFacingError,
        from window: NSWindow?,
        retry: @escaping () -> Void
    ) {
        presentedViewModels.append(error.viewModel)
        windowWasProvided.append(window != nil)
        retryActions.append(retry)
    }

    func performNextRetry() {
        retryActions.removeFirst()()
    }
}
