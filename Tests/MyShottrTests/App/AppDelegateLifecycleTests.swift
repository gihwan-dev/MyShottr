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
            documentWindowFactory: {
                openedProject,
                openedURL,
                isRecoveredDocument in
                XCTAssertEqual(openedProject, project)
                XCTAssertEqual(openedURL, projectURL)
                XCTAssertFalse(isRecoveredDocument)
                return window
            },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            sessionTerminationStateFactory: makeCleanTerminationState,
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
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
            sessionTerminationStateFactory: makeCleanTerminationState,
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
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
            documentWindowFactory: {
                project,
                projectURL,
                isRecoveredDocument in
                events.append("window")
                XCTAssertEqual(
                    project.manifest.documentId,
                    ChromeFixtures.captureID
                )
                XCTAssertNil(projectURL)
                XCTAssertFalse(isRecoveredDocument)
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
            sessionTerminationStateFactory: makeCleanTerminationState,
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(events, ["install", "coordinator", "window"])
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
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
            documentWindowFactory: { _, _, _ in
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
            sessionTerminationStateFactory: makeCleanTerminationState,
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
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
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testPresentingDocumentRetainsWindowAndActivatesRegularApp() throws {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _, _ in window }
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
            documentWindowFactory: { _, _, _ in window }
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
        firstWindow.representedDocumentID =
            ProjectFixtures.documentID
        secondWindow.representedDocumentID =
            RecoveryFixtures.secondDocumentID
        var windows: [SpyEditorWindowController] = [
            firstWindow,
            secondWindow,
        ]
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: {
                _, _, _ in windows.removeFirst()
            }
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "First")
        )
        try delegate.present(
            project: RecoveryFixtures.project(
                text: "Second",
                documentID: RecoveryFixtures.secondDocumentID
            )
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

    func testDuplicateDocumentIdentifierFocusesExistingWindow()
        throws
    {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        window.representedDocumentID =
            ProjectFixtures.documentID
        var factoryCalls = 0
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _, _ in
                factoryCalls += 1
                return window
            }
        )

        try delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "duplicate")
        )

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
        XCTAssertEqual(window.focusCount, 1)
        XCTAssertEqual(window.finalizeCount, 0)
    }

    func testDuplicateProjectURLWithDifferentIdentifierFocusesExisting()
        throws
    {
        let url = URL(
            fileURLWithPath: "/tmp/duplicate-url.myshottr"
        )
        let first = ProjectFixtures.project(text: "first")
        let second = RecoveryFixtures.project(
            text: "second",
            documentID: RecoveryFixtures.secondDocumentID
        )
        let store = SequentialProjectStore(
            projects: [first, second]
        )
        let window = SpyEditorWindowController()
        window.representedDocumentID = first.manifest.documentId
        window.representedProjectURL = url
        var factoryCalls = 0
        let delegate = AppDelegate(
            dependencies: AppDependencies(projectStore: store),
            documentWindowFactory: {
                project,
                projectURL,
                _ in
                factoryCalls += 1
                XCTAssertEqual(project, first)
                XCTAssertEqual(projectURL, url)
                return window
            }
        )

        delegate.application(NSApplication.shared, open: [url, url])

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(store.loadCount, 2)
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.focusCount, 1)
        XCTAssertEqual(window.finalizeCount, 0)
    }

    func testNoModifiedWindowsTerminateImmediatelyAndMarkClean()
        throws
    {
        let terminationState = SpySessionTerminationState()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            documentWindowFactory: { _, _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            sessionTerminationStateFactory: {
                terminationState
            },
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
            terminationReply: { _ in
                XCTFail("Immediate termination must not reply later")
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "clean")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            NSApplication.TerminateReply.terminateNow
        )
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(terminationState.cleanExitCount, 1)
        XCTAssertEqual(window.flushCount, 0)
        XCTAssertEqual(window.resolveCount, 0)
    }

    func testCancelQuitRepliesFalseAndDoesNotMarkCleanOrDiscard()
        async throws
    {
        let terminationState = SpySessionTerminationState()
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.resolutionResult = false
        let replyExpectation = expectation(
            description: "termination reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            sessionTerminationStateFactory: {
                terminationState
            },
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(window.flushCount, 1)
        XCTAssertEqual(window.resolveCount, 1)
        XCTAssertEqual(window.finalizeCount, 0)
        XCTAssertEqual(terminationState.cleanExitCount, 0)
    }

    func testFailedSaveCancelsQuitWithoutMarkingClean()
        async throws
    {
        let terminationState = SpySessionTerminationState()
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.resolutionResult = false
        window.resolutionLabel = "failed-save"
        let replyExpectation = expectation(
            description: "failed save reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            sessionTerminationStateFactory: {
                terminationState
            },
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(window.resolutionLabel, "failed-save")
        XCTAssertEqual(window.finalizeCount, 0)
        XCTAssertEqual(terminationState.cleanExitCount, 0)
    }

    func testMultipleModifiedWindowsFlushAllBeforeResolving()
        async throws
    {
        let terminationState = SpySessionTerminationState()
        var events: [String] = []
        let firstWindow = SpyEditorWindowController()
        firstWindow.representedDocumentID =
            ProjectFixtures.documentID
        firstWindow.hasModifiedDocument = true
        firstWindow.eventPrefix = "first"
        firstWindow.events = { events.append($0) }
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            RecoveryFixtures.secondDocumentID
        secondWindow.hasModifiedDocument = true
        secondWindow.eventPrefix = "second"
        secondWindow.events = { events.append($0) }
        var windows = [firstWindow, secondWindow]
        let replyExpectation = expectation(
            description: "multi-window reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: {
                _, _, _ in windows.removeFirst()
            },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            sessionTerminationStateFactory: {
                terminationState
            },
            recoveryStoreFactory: { SpyRecoveryStore() },
            recoveryPrompt: SpyRecoveryPrompt(),
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try delegate.present(
            project: RecoveryFixtures.project(
                text: "second",
                documentID: RecoveryFixtures.secondDocumentID
            )
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )

        XCTAssertEqual(
            events,
            [
                "first-flush",
                "second-flush",
                "first-resolve",
                "second-resolve",
                "first-finalize",
                "second-finalize",
            ]
        )
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(firstWindow.finalizeCount, 1)
        XCTAssertEqual(secondWindow.finalizeCount, 1)
        XCTAssertEqual(terminationState.cleanExitCount, 1)
    }

    func testLaterCancelDoesNotFinalizeEarlierWindow()
        async throws
    {
        let firstWindow = SpyEditorWindowController()
        firstWindow.representedDocumentID =
            ProjectFixtures.documentID
        firstWindow.hasModifiedDocument = true
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            RecoveryFixtures.secondDocumentID
        secondWindow.hasModifiedDocument = true
        secondWindow.resolutionResult = false
        var windows = [firstWindow, secondWindow]
        let replyExpectation = expectation(
            description: "cancel after earlier approval"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: {
                _, _, _ in windows.removeFirst()
            },
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            }
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try delegate.present(
            project: RecoveryFixtures.project(
                text: "second",
                documentID: RecoveryFixtures.secondDocumentID
            )
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(firstWindow.resolveCount, 1)
        XCTAssertEqual(secondWindow.resolveCount, 1)
        XCTAssertEqual(firstWindow.finalizeCount, 0)
        XCTAssertEqual(secondWindow.finalizeCount, 0)
    }

    func testRepeatedTerminateRequestStartsOneResolutionAndRepliesOnce()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.pauseFlush = true
        let replyExpectation = expectation(
            description: "single termination reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _, _ in window },
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            }
        )
        try delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await Task.yield()
        XCTAssertEqual(window.flushCount, 1)

        window.resumeFlush()
        await fulfillment(of: [replyExpectation], timeout: 1)

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateNow
        )
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(window.flushCount, 1)
        XCTAssertEqual(window.resolveCount, 1)
        XCTAssertEqual(window.finalizeCount, 1)
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

private final class SequentialProjectStore:
    ProjectPackageStoring,
    @unchecked Sendable
{
    private var projects: [MyShottrProject]
    private(set) var loadCount = 0

    init(projects: [MyShottrProject]) {
        self.projects = projects
    }

    func load(from url: URL) throws -> MyShottrProject {
        loadCount += 1
        return projects.removeFirst()
    }

    func save(_ project: MyShottrProject, to url: URL) throws {
        throw StubProjectStoreError.unexpectedSave
    }
}

private enum AppDelegateLifecycleTestError: Error, Equatable {
    case presentation
    case registration
}

private func makeCleanTerminationState()
    -> any SessionTerminationTracking
{
    StubSessionTerminationState(previousSessionWasClean: true)
}

private struct StubSessionTerminationState:
    SessionTerminationTracking
{
    let previousSessionWasClean: Bool

    func beginSession() throws -> Bool {
        previousSessionWasClean
    }

    func markCleanExit() throws {}
}

private final class SpySessionTerminationState:
    SessionTerminationTracking,
    @unchecked Sendable
{
    private(set) var beginCount = 0
    private(set) var cleanExitCount = 0

    func beginSession() throws -> Bool {
        beginCount += 1
        return true
    }

    func markCleanExit() throws {
        cleanExitCount += 1
    }
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
    var representedDocumentID = ProjectFixtures.documentID
    var representedProjectURL: URL?
    var hasModifiedDocument = false
    var resolutionResult = true
    var resolutionLabel = "approved"
    var eventPrefix = "window"
    var events: ((String) -> Void)?
    var pauseFlush = false
    private var flushContinuation:
        CheckedContinuation<Void, Never>?
    private(set) var presentationCount = 0
    private(set) var focusCount = 0
    private(set) var flushCount = 0
    private(set) var resolveCount = 0
    private(set) var finalizeCount = 0

    func presentWindow() throws {
        if let presentationError {
            throw presentationError
        }
        presentationCount += 1
    }

    func focusWindow() {
        focusCount += 1
    }

    func flushRecoveryForTermination() async throws {
        flushCount += 1
        events?("\(eventPrefix)-flush")
        if pauseFlush {
            await withCheckedContinuation {
                flushContinuation = $0
            }
        }
    }

    func resolvePendingChangesForTermination() async -> Bool {
        resolveCount += 1
        events?("\(eventPrefix)-resolve")
        return resolutionResult
    }

    func finalizePendingTermination() throws {
        finalizeCount += 1
        events?("\(eventPrefix)-finalize")
    }

    func resumeFlush() {
        pauseFlush = false
        flushContinuation?.resume()
        flushContinuation = nil
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
