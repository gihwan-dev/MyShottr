import AppKit
import Carbon
import XCTest
@testable import MyShottr

@MainActor
final class AppDelegateLifecycleTests: XCTestCase {
    func testColdFileOpenBeforeDidFinishKeepsDocumentAndRegularPolicy() {
        let project = ProjectFixtures.project(text: "Cold Open")
        let projectURL = URL(
            fileURLWithPath: "/tmp/cold-open.myshottr"
        )
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            dependencies: AppDependencies(
                projectStore: StubProjectStore(project: project)
            ),
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { openedProject, openedURL in
                XCTAssertEqual(openedProject, project)
                XCTAssertEqual(openedURL, projectURL)
                return window
            },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.application(NSApplication.shared, open: [projectURL])
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testMenuBarColdLaunchUsesAccessoryPolicy() {
        let application = SpyApplicationLifecycle()
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(application.activationPolicies, [.accessory])
        XCTAssertEqual(application.activationCount, 0)
    }

    func testLaunchInstallsHostThenScansPendingChromeCaptures() {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let inbox = StubPendingCaptureInbox(
            pending: [
                StagedCapture(
                    id: ChromeFixtures.captureID,
                    pngURL: URL(
                        fileURLWithPath: "/inbox/\(ChromeFixtures.captureID.uuidString).png"
                    )
                ),
            ]
        )
        var events: [String] = []
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { project, projectURL in
                events.append("window")
                XCTAssertEqual(
                    project.manifest.documentId,
                    ChromeFixtures.captureID
                )
                XCTAssertNil(projectURL)
                return window
            },
            nativeMessagingHostInstaller: {
                events.append("install")
            },
            chromeCaptureCoordinatorFactory: {
                projectFactory,
                windows in
                events.append("coordinator")
                return CaptureInboxCoordinator(
                    inbox: inbox,
                    projectFactory: projectFactory,
                    windows: windows,
                    reportError: { XCTFail("Unexpected Chrome import error: \($0)") }
                )
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(events, ["install", "coordinator", "window"])
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.acknowledgedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.accessory, .regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testRegistrationFailureStillStartsPendingChromeImport() {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let inbox = StubPendingCaptureInbox(
            pending: [
                StagedCapture(
                    id: ChromeFixtures.captureID,
                    pngURL: URL(
                        fileURLWithPath: "/inbox/\(ChromeFixtures.captureID.uuidString).png"
                    )
                ),
            ]
        )
        var reportedErrors: [any Error] = []
        var events: [String] = []
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in
                events.append("window")
                return window
            },
            nativeMessagingHostInstaller: {
                events.append("install")
                throw AppDelegateLifecycleTestError.registration
            },
            chromeCaptureCoordinatorFactory: {
                projectFactory,
                windows in
                events.append("coordinator")
                return CaptureInboxCoordinator(
                    inbox: inbox,
                    projectFactory: projectFactory,
                    windows: windows,
                    reportError: { reportedErrors.append($0) }
                )
            },
            launchErrorReporter: {
                events.append("report")
                reportedErrors.append($0)
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(
            reportedErrors.first as? AppDelegateLifecycleTestError,
            .registration
        )
        XCTAssertEqual(
            events,
            ["install", "coordinator", "window", "report"]
        )
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.acknowledgedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testPresentingDocumentRetainsWindowAndActivatesRegularApp() throws {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in window }
        )

        try delegate.present(
            project: ProjectFixtures.project(text: "Capture")
        )

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testPresentationFailureDoesNotRetainOrActivateWindow() {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        window.presentationError =
            AppDelegateLifecycleTestError.presentation
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in window }
        )

        XCTAssertThrowsError(
            try delegate.present(
                project: ProjectFixtures.project(text: "Capture")
            )
        ) {
            XCTAssertEqual(
                $0 as? AppDelegateLifecycleTestError,
                .presentation
            )
        }
        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertTrue(application.activationPolicies.isEmpty)
        XCTAssertEqual(application.activationCount, 0)
    }

    func testClosingLastDocumentReturnsToAccessoryPolicy() throws {
        let application = SpyApplicationLifecycle()
        let firstWindow = SpyEditorWindowController()
        let secondWindow = SpyEditorWindowController()
        var windows: [SpyEditorWindowController] = [
            firstWindow,
            secondWindow,
        ]
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in windows.removeFirst() }
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "First")
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "Second")
        )

        firstWindow.close()

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(
            application.activationPolicies,
            [.regular, .regular]
        )

        secondWindow.close()

        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(
            application.activationPolicies,
            [.regular, .regular, .accessory]
        )
    }
}

private struct StubProjectStore: ProjectPackageStoring {
    let project: MyShottrProject

    func load(from url: URL) throws -> MyShottrProject {
        project
    }

    func save(_ project: MyShottrProject, to url: URL) throws {
        throw StubProjectStoreError.unexpectedSave
    }
}

private enum StubProjectStoreError: Error {
    case unexpectedSave
}

private enum AppDelegateLifecycleTestError: Error, Equatable {
    case presentation
    case registration
}

private func makeNoOpHotKeyAPI() -> GlobalHotKeyAPI {
    GlobalHotKeyAPI(
        installEventHandler: { _, _, outputHandler in
            outputHandler.pointee = nil
            return noErr
        },
        registerEventHotKey: { _, _, _, outputHotKey in
            outputHotKey.pointee = nil
            return noErr
        },
        unregisterEventHotKey: { _ in noErr },
        removeEventHandler: { _ in noErr }
    )
}

@MainActor
private func makeEmptyChromeCoordinator(
    projectFactory: any NewProjectCreating,
    windows: any DocumentWindowPresenting
) throws -> CaptureInboxCoordinator {
    CaptureInboxCoordinator(
        inbox: StubPendingCaptureInbox(),
        projectFactory: projectFactory,
        windows: windows,
        reportError: { XCTFail("Unexpected Chrome import error: \($0)") }
    )
}

@MainActor
private final class SpyEditorWindowController: EditorWindowControlling {
    var onClose: (() -> Void)?
    var presentationError: (any Error)?
    private(set) var presentationCount = 0

    func presentWindow() throws {
        if let presentationError {
            throw presentationError
        }
        presentationCount += 1
    }

    func close() {
        onClose?()
    }
}

@MainActor
private final class SpyApplicationLifecycle {
    private(set) var activationPolicies: [
        NSApplication.ActivationPolicy
    ] = []
    private(set) var activationCount = 0

    lazy var lifecycle = ApplicationLifecycle(
        setActivationPolicy: { [weak self] policy in
            self?.activationPolicies.append(policy)
        },
        activate: { [weak self] in
            self?.activationCount += 1
        }
    )
}
