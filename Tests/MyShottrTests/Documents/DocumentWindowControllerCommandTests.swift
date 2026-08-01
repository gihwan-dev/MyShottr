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

    func testToolbarUsesExactDefaultOrderAndIconAndLabelDisplayMode()
        throws
    {
        let controller = try makeController()
        let toolbar = try XCTUnwrap(controller.window?.toolbar)

        XCTAssertEqual(toolbar.displayMode, .iconAndLabel)
        XCTAssertEqual(
            controller.toolbarDefaultItemIdentifiers(toolbar),
            [
                .copyComposite,
                .undoEditor,
                .redoEditor,
                .flexibleSpace,
                .saveProject,
                .exportComposite,
            ]
        )
        XCTAssertEqual(
            Set(controller.toolbarAllowedItemIdentifiers(toolbar)),
            Set([
                .copyComposite,
                .undoEditor,
                .redoEditor,
                .saveProject,
                .exportComposite,
                .flexibleSpace,
            ])
        )
    }

    func testToolbarItemsUseApprovedLabelsTooltipsSymbolsAndSelectors()
        throws
    {
        let controller = try makeController()
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        let cases: [(
            NSToolbarItem.Identifier,
            String,
            String,
            String,
            Selector
        )] = [
            (
                .copyComposite,
                "Copy Image",
                "Copy the annotated PNG (Command-Shift-C)",
                "doc.on.doc",
                #selector(DocumentWindowController.copyComposite(_:))
            ),
            (
                .undoEditor,
                "Undo",
                "Undo the last annotation change (Command-Z)",
                "arrow.uturn.backward",
                #selector(DocumentWindowController.undoEditor(_:))
            ),
            (
                .redoEditor,
                "Redo",
                "Redo the last annotation change (Command-Shift-Z)",
                "arrow.uturn.forward",
                #selector(DocumentWindowController.redoEditor(_:))
            ),
            (
                .saveProject,
                "Save Project",
                "Save an editable MyShottr project (Command-S)",
                "square.and.arrow.down",
                #selector(DocumentWindowController.saveProjectAction(_:))
            ),
            (
                .exportComposite,
                "Export PNG",
                "Export the annotated PNG (Command-E)",
                "square.and.arrow.up",
                #selector(DocumentWindowController.exportComposite(_:))
            ),
        ]

        for (identifier, label, toolTip, symbolName, action) in cases {
            let item = try XCTUnwrap(
                controller.toolbar(
                    toolbar,
                    itemForItemIdentifier: identifier,
                    willBeInsertedIntoToolbar: true
                )
            )
            let expectedImage = try XCTUnwrap(
                NSImage(
                    systemSymbolName: symbolName,
                    accessibilityDescription: label
                )
            )

            XCTAssertEqual(item.label, label)
            XCTAssertEqual(item.toolTip, toolTip)
            XCTAssertEqual(item.action, action)
            XCTAssertTrue(item.target === controller)
            XCTAssertEqual(
                item.image?.tiffRepresentation,
                expectedImage.tiffRepresentation
            )
        }
    }

    func testToolbarValidationFollowsReadinessAndLatestHistoryState()
        async throws
    {
        let controller = try makeController()
        let toolbar = try XCTUnwrap(controller.window?.toolbar)
        let outputItems = try [
            NSToolbarItem.Identifier.copyComposite,
            .saveProject,
            .exportComposite,
        ].map {
            try makeToolbarItem(
                identifier: $0,
                controller: controller,
                toolbar: toolbar
            )
        }
        let undoItem = try makeToolbarItem(
            identifier: .undoEditor,
            controller: controller,
            toolbar: toolbar
        )
        let redoItem = try makeToolbarItem(
            identifier: .redoEditor,
            controller: controller,
            toolbar: toolbar
        )

        for item in outputItems + [undoItem, redoItem] {
            XCTAssertFalse(controller.validateToolbarItem(item))
        }

        try await controller.waitForEditorLoad()

        for item in outputItems {
            XCTAssertTrue(controller.validateToolbarItem(item))
        }
        XCTAssertFalse(controller.validateToolbarItem(undoItem))
        XCTAssertFalse(controller.validateToolbarItem(redoItem))

        controller.receiveHistoryState(
            EditorHistoryState(canUndo: true, canRedo: false)
        )
        XCTAssertTrue(controller.validateToolbarItem(undoItem))
        XCTAssertFalse(controller.validateToolbarItem(redoItem))

        controller.receiveHistoryState(
            EditorHistoryState(canUndo: false, canRedo: true)
        )
        XCTAssertFalse(controller.validateToolbarItem(undoItem))
        XCTAssertTrue(controller.validateToolbarItem(redoItem))
    }

    func testDisabledHistorySelectorsReturnFalseBeforeEditorReadiness()
        throws
    {
        let controller = try makeController()

        XCTAssertFalse(controller.undoEditor(nil))
        XCTAssertFalse(controller.redoEditor(nil))
    }

    func testAllDocumentSelectorsRejectInactiveCommandWindow()
        async throws
    {
        var sentActions: [EditorHistoryAction] = []
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(
                text: "Inactive command window"
            ),
            projectURL: nil,
            testSession: DocumentSession(),
            historyActionSender: { sentActions.append($0) },
            commandWindowPredicate: { _ in false }
        )
        try await controller.waitForEditorLoad()
        controller.receiveHistoryState(
            EditorHistoryState(canUndo: true, canRedo: true)
        )

        XCTAssertFalse(controller.copyComposite(nil))
        XCTAssertFalse(controller.saveProjectAction(nil))
        XCTAssertFalse(controller.exportComposite(nil))
        XCTAssertFalse(controller.undoEditor(nil))
        XCTAssertFalse(controller.redoEditor(nil))
        XCTAssertTrue(sentActions.isEmpty)
    }

    func testEnabledHistorySelectorsSendOneMatchingActionAndDisabledSendsNone()
        async throws
    {
        var sentActions: [EditorHistoryAction] = []
        let controller = try DocumentWindowController(
            project: ProjectFixtures.project(
                text: "History actions"
            ),
            projectURL: nil,
            testSession: DocumentSession(),
            historyActionSender: { sentActions.append($0) },
            commandWindowPredicate: { _ in true }
        )
        try await controller.waitForEditorLoad()
        controller.receiveHistoryState(
            EditorHistoryState(canUndo: true, canRedo: false)
        )
        XCTAssertFalse(controller.redoEditor(nil))
        XCTAssertTrue(sentActions.isEmpty)
        XCTAssertTrue(controller.undoEditor(nil))
        XCTAssertEqual(sentActions, [.undo])

        controller.receiveHistoryState(
            EditorHistoryState(canUndo: false, canRedo: true)
        )
        XCTAssertTrue(controller.redoEditor(nil))
        XCTAssertEqual(sentActions, [.undo, .redo])
    }

    func testOutputInFlightDisablesOnlyOutputToolbarItems()
        async throws
    {
        let project = ProjectFixtures.project(
            text: "Suspended output"
        )
        let session = DocumentSession()
        try session.open(project: project)
        var snapshotContinuation:
            CheckedContinuation<Data, any Error>?
        let controller = try DocumentWindowController(
            project: project,
            projectURL: temporaryDirectory.appendingPathComponent(
                "Output.myshottr",
                isDirectory: true
            ),
            testSession: session,
            annotationSnapshotProvider: {
                try await withCheckedThrowingContinuation {
                    continuation in
                    snapshotContinuation = continuation
                }
            },
            commandWindowPredicate: { _ in true }
        )
        let initialWindow = try XCTUnwrap(controller.window)
        let toolbar = try XCTUnwrap(initialWindow.toolbar)
        let outputItems = try [
            NSToolbarItem.Identifier.copyComposite,
            .saveProject,
            .exportComposite,
        ].map {
            try makeToolbarItem(
                identifier: $0,
                controller: controller,
                toolbar: toolbar
            )
        }
        let undoItem = try makeToolbarItem(
            identifier: .undoEditor,
            controller: controller,
            toolbar: toolbar
        )
        let redoItem = try makeToolbarItem(
            identifier: .redoEditor,
            controller: controller,
            toolbar: toolbar
        )

        try await controller.waitForEditorLoad()
        controller.receiveHistoryState(
            EditorHistoryState(canUndo: true, canRedo: true)
        )
        XCTAssertTrue(controller.saveProjectAction(nil))
        await waitUntil { snapshotContinuation != nil }

        for item in outputItems {
            XCTAssertFalse(controller.validateToolbarItem(item))
        }
        XCTAssertTrue(controller.validateToolbarItem(undoItem))
        XCTAssertTrue(controller.validateToolbarItem(redoItem))

        snapshotContinuation?.resume(
            returning: project.annotationJSON
        )
        await waitUntil {
            outputItems.allSatisfy {
                controller.validateToolbarItem($0)
            }
        }
    }

    func testBridgeFailureUsesExistingEditorBridgePresenterPathExactlyOnce()
        throws
    {
        let presenter = SpyUserFacingErrorPresenter()
        let controller = try makeController(
            errorPresenter: presenter
        )

        controller.receiveBridgeFailure(.invalidMessage)

        XCTAssertEqual(
            presenter.presentedViewModels,
            [
                MyShottrUserFacingError.editorBridge(
                    .invalidMessage
                ).viewModel,
            ]
        )
        XCTAssertEqual(presenter.windowWasProvided, [true])
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

    func testCloseSaveRaceKeepsWindowOpenUntilLatestRevisionIsSaved()
        async throws
    {
        let initial = ProjectFixtures.project(text: "initial")
        let firstSave = ProjectFixtures.project(
            text: "first save"
        )
        let latest = ProjectFixtures.project(text: "latest")
        let session = DocumentSession()
        try session.open(project: initial)
        try session.applySnapshot(firstSave.annotationJSON)
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
            },
            operationStatusSender: { _, _ in }
        )
        let window = try XCTUnwrap(controller.window)
        try await controller.waitForEditorLoad()

        let firstResolution = await controller
            .resolvePendingChangesForTermination()
        XCTAssertFalse(firstResolution)

        let firstStoredProject = try XCTUnwrap(
            projectStore.savedProjects.first
        )
        XCTAssertEqual(
            firstStoredProject.annotationJSON,
            firstSave.annotationJSON
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            latest.annotationJSON
        )
        XCTAssertTrue(session.isModified)
        XCTAssertEqual(closeRequestCount, 0)

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

    private func makeController(
        errorPresenter: any UserFacingErrorPresenting =
            UserFacingErrorPresenter.shared
    ) throws -> DocumentWindowController {
        try DocumentWindowController(
            project: ProjectFixtures.project(
                text: "Toolbar contract"
            ),
            projectURL: nil,
            errorPresenter: errorPresenter,
            testSession: DocumentSession()
        )
    }

    private func makeToolbarItem(
        identifier: NSToolbarItem.Identifier,
        controller: DocumentWindowController,
        toolbar: NSToolbar
    ) throws -> NSToolbarItem {
        try XCTUnwrap(
            controller.toolbar(
                toolbar,
                itemForItemIdentifier: identifier,
                willBeInsertedIntoToolbar: true
            )
        )
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

    func present(
        _ error: MyShottrUserFacingError,
        from window: NSWindow?
    ) {
        presentedViewModels.append(error.viewModel)
        windowWasProvided.append(window != nil)
    }
}
