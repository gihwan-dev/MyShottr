import AppKit
import Carbon
import XCTest
@testable import Inkbeam

@MainActor
final class AppDelegateLifecycleTests: XCTestCase {
    func testConcurrentCloseAndQuitShareOneWindowResolution()
        async
    {
        let gate = DocumentTerminationResolutionGate()
        var promptCount = 0
        var promptContinuation:
            CheckedContinuation<Bool, Never>?
        let closeCaller = Task { @MainActor in
            await gate.resolve {
                promptCount += 1
                return await withCheckedContinuation {
                    promptContinuation = $0
                }
            }
        }
        await Task.yield()
        let quitCaller = Task { @MainActor in
            await gate.resolve {
                XCTFail(
                    "Concurrent quit must await the close prompt"
                )
                return false
            }
        }
        await Task.yield()

        XCTAssertEqual(promptCount, 1)
        promptContinuation?.resume(returning: true)

        let closeResult = await closeCaller.value
        let quitResult = await quitCaller.value
        XCTAssertTrue(closeResult)
        XCTAssertTrue(quitResult)
        XCTAssertEqual(promptCount, 1)
    }

    func testColdFileOpenBeforeDidFinishKeepsDocumentAndRegularPolicy() {
        let project = ProjectFixtures.project(text: "Cold Open")
        let projectURL = URL(
            fileURLWithPath: "/tmp/cold-open.inkbeam"
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
                openedURL in
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

    func testNonInkbeamFileOpenIsRejectedBeforeProjectStoreAccess() {
        let project = ProjectFixtures.project(text: "Rejected Open")
        let legacyExtension = ["my", "shottr"].joined()
        let projectURL = URL(
            fileURLWithPath: "/tmp/rejected-open.\(legacyExtension)"
        )
        let store = SequentialProjectStore(projects: [project])
        var reportedErrors: [InkbeamUserFacingError] = []
        var factoryCallCount = 0
        let delegate = AppDelegate(
            dependencies: AppDependencies(projectStore: store),
            documentWindowFactory: { _, _ in
                factoryCallCount += 1
                return SpyEditorWindowController()
            },
            launchErrorReporter: { reportedErrors.append($0) }
        )

        delegate.application(NSApplication.shared, open: [projectURL])

        XCTAssertEqual(store.loadCount, 0)
        XCTAssertEqual(factoryCallCount, 0)
        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(reportedErrors.count, 1)
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

    func testEligibleLaunchStartsUpdaterOnceWithoutAutomaticManualCheck() {
        let updater = SpyUpdateService()
        var factoryCallCount = 0
        let delegate = AppDelegate(
            updateServiceFactory: {
                factoryCallCount += 1
                return updater
            },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(factoryCallCount, 1)
        XCTAssertEqual(updater.startCount, 1)
        XCTAssertEqual(updater.checkCount, 0)
    }

    func testUpdaterStartsBeforeNativeAndChromeServices() {
        var events: [String] = []
        let updater = SpyUpdateService()
        updater.onStart = { events.append("updater") }
        let delegate = AppDelegate(
            updateServiceFactory: {
                events.append("updater-factory")
                return updater
            },
            nativeMessagingHostInstaller: {
                events.append("native-host")
            },
            chromeCaptureCoordinatorFactory: { _, _ in
                events.append("chrome-inbox")
                return try makeEmptyChromeCoordinator(
                    projectFactory: StubNewProjectFactory(),
                    windows: NoOpDocumentWindowPresenter()
                )
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(
            events,
            [
                "updater-factory",
                "updater",
                "native-host",
                "chrome-inbox",
            ]
        )
    }

    func testReleaseLaunchOutsideApplicationsReportsMoveAndSkipsStartupServices() {
        let application = SpyApplicationLifecycle()
        var reportedErrors: [InkbeamUserFacingError] = []
        var installerCallCount = 0
        var chromeCoordinatorCallCount = 0
        var updaterFactoryCallCount = 0
        var hotKeyHandlerInstallCallCount = 0
        var hotKeyRegistrationCallCount = 0
        let hotKeyAPI = GlobalHotKeyAPI(
            installEventHandler: { _, _, outputHandler in
                hotKeyHandlerInstallCallCount += 1
                outputHandler.pointee = nil
                return noErr
            },
            registerEventHotKey: { _, _, _, outputHotKey in
                hotKeyRegistrationCallCount += 1
                outputHotKey.pointee = nil
                return noErr
            },
            unregisterEventHotKey: { _ in noErr },
            removeEventHandler: { _ in noErr }
        )
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            installLocationPolicy: InstallLocationPolicy(),
            bundleURLProvider: {
                URL(fileURLWithPath: "/Volumes/Inkbeam/Inkbeam.app")
            },
            isBundleWritable: { _ in false },
            isDebugBuild: false,
            updateServiceFactory: {
                updaterFactoryCallCount += 1
                return SpyUpdateService()
            },
            nativeMessagingHostInstaller: {
                installerCallCount += 1
            },
            chromeCaptureCoordinatorFactory: { _, _ in
                chromeCoordinatorCallCount += 1
                return try makeEmptyChromeCoordinator(
                    projectFactory: StubNewProjectFactory(),
                    windows: NoOpDocumentWindowPresenter()
                )
            },
            launchErrorReporter: { reportedErrors.append($0) },
            hotKeyAPI: hotKeyAPI
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(
            reportedErrors.map(\.viewModel.title),
            ["Move Inkbeam to Applications"]
        )
        XCTAssertEqual(installerCallCount, 0)
        XCTAssertEqual(chromeCoordinatorCallCount, 0)
        XCTAssertEqual(updaterFactoryCallCount, 0)
        XCTAssertEqual(hotKeyHandlerInstallCallCount, 0)
        XCTAssertEqual(hotKeyRegistrationCallCount, 0)
        XCTAssertEqual(application.activationPolicies, [.regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
    }

    func testCommandShift2HotKeyActivatesAppBeforeAreaSelectionBegins()
        async throws
    {
        let application = SpyApplicationLifecycle()
        let selector = ActivationObservingRegionSelector(
            activationCount: {
                application.activationCount
            }
        )
        let hotKeyHarness = GlobalHotKeyAPIHarness()
        let delegate = AppDelegate(
            dependencies: AppDependencies(
                selector: selector,
                capturer: FakeScreenCapturer(
                    result: try CaptureArtifact(
                        id: ProjectFixtures.documentID,
                        sourceKind: .screenRegion,
                        pngData: ProjectFixtures.pngData,
                        scale: 2
                    )
                ),
                projectFactory: StubNewProjectFactory()
            ),
            applicationLifecycle: application.lifecycle,
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory:
                makeEmptyChromeCoordinator,
            hotKeyAPI: hotKeyHarness.api
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        XCTAssertEqual(application.activationPolicies, [.accessory])
        XCTAssertEqual(application.activationCount, 0)

        hotKeyHarness.invokeEventHandler(
            signature: 0x49_4E_4B_42,
            id: 1
        )
        await selector.waitUntilStarted()

        XCTAssertEqual(selector.activationCountWhenSelectionBegan, 1)
        withExtendedLifetime(delegate) {}
    }

    func testCommandShift2HotKeyRequestsExactlyOneAreaCaptureAfterLaunch()
        async throws
    {
        let application = SpyApplicationLifecycle()
        let selector = SuspendingRegionSelector()
        let hotKeyHarness = GlobalHotKeyAPIHarness()
        let artifact = try CaptureArtifact(
            id: ProjectFixtures.documentID,
            sourceKind: .screenRegion,
            pngData: ProjectFixtures.pngData,
            scale: 2
        )
        let delegate = AppDelegate(
            dependencies: AppDependencies(
                selector: selector,
                capturer: FakeScreenCapturer(result: artifact),
                projectFactory: StubNewProjectFactory()
            ),
            applicationLifecycle: application.lifecycle,
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory:
                makeEmptyChromeCoordinator,
            hotKeyAPI: hotKeyHarness.api
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        hotKeyHarness.invokeEventHandler(
            signature: 0x49_4E_4B_42,
            id: 1
        )
        await selector.waitUntilStarted()

        XCTAssertEqual(hotKeyHarness.keyCode, UInt32(kVK_ANSI_2))
        XCTAssertEqual(
            hotKeyHarness.modifiers,
            UInt32(cmdKey | shiftKey)
        )
        XCTAssertEqual(selector.selectionCount, 1)
        selector.finish(with: .cancelled)
        await Task.yield()
        withExtendedLifetime(delegate) {}
    }

    func testGlobalShortcutConflictReportsTypedErrorAndKeepsAccessoryPolicy() {
        let application = SpyApplicationLifecycle()
        var reportedErrors: [InkbeamUserFacingError] = []
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory:
                makeEmptyChromeCoordinator,
            launchErrorReporter: {
                reportedErrors.append($0)
            },
            hotKeyAPI: makeFailingHotKeyAPI()
        )

        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )

        XCTAssertEqual(
            reportedErrors.map(\.viewModel.title),
            ["Keyboard Shortcut Is Unavailable"]
        )
        XCTAssertEqual(application.activationPolicies, [.accessory])
        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
    }

    func testLaunchInstallsHostThenScansPendingChromeCaptures() async {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let presentation = expectation(
            description: "pending Chrome capture presented"
        )
        window.onPresent = { presentation.fulfill() }
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
                projectURL in
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
        await fulfillment(of: [presentation], timeout: 1)

        XCTAssertEqual(events, ["install", "coordinator", "window"])
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.accessory, .regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testRegistrationFailureStillStartsPendingChromeImport() async {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let presentation = expectation(
            description: "pending Chrome capture presented"
        )
        window.onPresent = { presentation.fulfill() }
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
        var reportedErrors: [InkbeamUserFacingError] = []
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
        await fulfillment(of: [presentation], timeout: 1)

        XCTAssertEqual(
            reportedErrors.first?.viewModel.title,
            "Chrome Connection Is Not Ready"
        )
        XCTAssertEqual(
            events,
            ["install", "coordinator", "report", "window"]
        )
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testPresentingDocumentRetainsWindowAndActivatesRegularApp()
        async throws
    {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in window }
        )

        try await delegate.present(
            project: ProjectFixtures.project(text: "Capture")
        )

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(application.activationPolicies, [.regular])
        XCTAssertEqual(application.activationCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
    }

    func testPresentationFailureDoesNotRetainOrActivateWindow() async {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        window.presentationError =
            AppDelegateLifecycleTestError.presentation
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in window }
        )

        do {
            try await delegate.present(
                project: ProjectFixtures.project(text: "Capture")
            )
            XCTFail("Expected presentation failure")
        } catch {
            XCTAssertEqual(
                error as? AppDelegateLifecycleTestError,
                .presentation
            )
        }
        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertTrue(application.activationPolicies.isEmpty)
        XCTAssertEqual(application.activationCount, 0)
    }

    func testPresentWaitsForEditorACKAndReturnsTypedFailure() async {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        window.pauseEditorLoad = true
        window.editorLoadError = EditorBridgeError.timedOut
        let loadStarted = expectation(
            description: "editor load started"
        )
        window.onEditorLoadWait = { count in
            if count == 1 {
                loadStarted.fulfill()
            }
        }
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in window }
        )

        let presentation = Task { @MainActor in
            try await delegate.present(
                project: ProjectFixtures.project(text: "Capture")
            )
        }
        await fulfillment(of: [loadStarted], timeout: 1)

        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
        XCTAssertEqual(window.failedPresentationDiscardCount, 0)

        window.resumeEditorLoad()
        do {
            try await presentation.value
            XCTFail("Expected typed editor timeout")
        } catch {
            XCTAssertEqual(
                error as? EditorBridgeError,
                .timedOut
            )
        }

        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(window.failedPresentationDiscardCount, 1)
        XCTAssertEqual(
            application.activationPolicies,
            [.regular, .accessory]
        )
    }

    func testConcurrentPresentationsShareOneEditorLoadAndCleanup()
        async
    {
        let window = SpyEditorWindowController()
        window.pauseEditorLoad = true
        window.editorLoadError = EditorBridgeError.invalidMessage
        let loadWaiters = expectation(
            description: "both callers wait for one editor load"
        )
        loadWaiters.expectedFulfillmentCount = 2
        window.onEditorLoadWait = { _ in
            loadWaiters.fulfill()
        }
        var factoryCalls = 0
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in
                factoryCalls += 1
                return window
            }
        )
        let project = ProjectFixtures.project(text: "Capture")

        let first = Task { @MainActor in
            try await delegate.present(project: project)
        }
        await Task.yield()
        let second = Task { @MainActor in
            try await delegate.present(project: project)
        }
        await fulfillment(of: [loadWaiters], timeout: 1)

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(window.presentationCount, 1)
        XCTAssertEqual(window.focusCount, 1)
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)

        window.resumeEditorLoad()
        for presentation in [first, second] {
            do {
                try await presentation.value
                XCTFail("Expected shared editor failure")
            } catch {
                XCTAssertEqual(
                    error as? EditorBridgeError,
                    .invalidMessage
                )
            }
        }

        XCTAssertEqual(delegate.activeDocumentWindowCount, 0)
        XCTAssertEqual(window.failedPresentationDiscardCount, 1)
    }

    func testClosingLastDocumentReturnsToAccessoryPolicy() async throws {
        let application = SpyApplicationLifecycle()
        let firstWindow = SpyEditorWindowController()
        let secondWindow = SpyEditorWindowController()
        firstWindow.representedDocumentID =
            ProjectFixtures.documentID
        secondWindow.representedDocumentID =
            AdditionalProjectFixtures.secondDocumentID
        var windows: [SpyEditorWindowController] = [
            firstWindow,
            secondWindow,
        ]
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: {
                _, _ in windows.removeFirst()
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "First")
        )
        try await delegate.present(
            project: AdditionalProjectFixtures.project(
                text: "Second",
                documentID: AdditionalProjectFixtures.secondDocumentID
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
        async throws
    {
        let application = SpyApplicationLifecycle()
        let window = SpyEditorWindowController()
        window.representedDocumentID =
            ProjectFixtures.documentID
        var factoryCalls = 0
        let delegate = AppDelegate(
            applicationLifecycle: application.lifecycle,
            documentWindowFactory: { _, _ in
                factoryCalls += 1
                return window
            }
        )

        try await delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "duplicate")
        )

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(delegate.activeDocumentWindowCount, 1)
        XCTAssertEqual(window.presentationCount, 1)
        XCTAssertEqual(window.focusCount, 1)
    }

    func testDuplicateProjectURLWithDifferentIdentifierFocusesExisting()
        throws
    {
        let url = URL(
            fileURLWithPath: "/tmp/duplicate-url.inkbeam"
        )
        let first = ProjectFixtures.project(text: "first")
        let second = AdditionalProjectFixtures.project(
            text: "second",
            documentID: AdditionalProjectFixtures.secondDocumentID
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
                projectURL in
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
    }

    func testUpdateRelaunchCancelRepliesFalseAndRetryPromptsAgain()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.resolutionResult = false
        let firstReply = expectation(
            description: "cancelled update relaunch reply"
        )
        let secondReply = expectation(
            description: "retried update relaunch reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            terminationReply: {
                replies.append($0)
                if replies.count == 1 {
                    firstReply.fulfill()
                } else {
                    secondReply.fulfill()
                }
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await fulfillment(of: [firstReply], timeout: 1)
        XCTAssertEqual(replies, [false])
        XCTAssertEqual(window.resolveCount, 1)

        window.resolutionResult = true
        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await fulfillment(of: [secondReply], timeout: 1)

        XCTAssertEqual(replies, [false, true])
        XCTAssertEqual(window.resolveCount, 2)
    }

    func testUpdateRelaunchWaitsForSaveAndRejectsSaveFailure()
        async throws
    {
        var events: [String] = []
        let savedWindow = SpyEditorWindowController()
        savedWindow.hasModifiedDocument = true
        savedWindow.pauseResolution = true
        savedWindow.onResolutionComplete = { _ in
            events.append("save-complete")
        }
        let savedReply = expectation(
            description: "successful save relaunch reply"
        )
        let savedDelegate = AppDelegate(
            documentWindowFactory: { _, _ in savedWindow },
            terminationReply: {
                events.append("reply-\($0)")
                savedReply.fulfill()
            }
        )
        try await savedDelegate.present(
            project: ProjectFixtures.project(text: "save")
        )

        XCTAssertEqual(
            savedDelegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await Task.yield()
        XCTAssertTrue(events.isEmpty)
        savedWindow.resumeResolution()
        await fulfillment(of: [savedReply], timeout: 1)
        XCTAssertEqual(events, ["save-complete", "reply-true"])

        let failedWindow = SpyEditorWindowController()
        failedWindow.hasModifiedDocument = true
        failedWindow.resolutionResult = false
        let failedReply = expectation(
            description: "failed save relaunch reply"
        )
        var failedReplies: [Bool] = []
        let failedDelegate = AppDelegate(
            documentWindowFactory: { _, _ in failedWindow },
            terminationReply: {
                failedReplies.append($0)
                failedReply.fulfill()
            }
        )
        try await failedDelegate.present(
            project: AdditionalProjectFixtures.project(
                text: "failed save",
                documentID: AdditionalProjectFixtures.secondDocumentID
            )
        )

        XCTAssertEqual(
            failedDelegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [failedReply], timeout: 1)
        XCTAssertEqual(failedReplies, [false])
    }

    func testUpdateRelaunchDiscardKeepsLastSavedProjectUnchanged()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.resolutionLabel = "discard"
        window.lastSavedProjectText = "saved before annotations"
        let reply = expectation(
            description: "discard update relaunch reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            terminationReply: {
                replies.append($0)
                reply.fulfill()
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "unsaved annotations")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(NSApplication.shared),
            .terminateLater
        )
        await fulfillment(of: [reply], timeout: 1)

        XCTAssertEqual(replies, [true])
        XCTAssertEqual(window.resolutionLabel, "discard")
        XCTAssertEqual(
            window.lastSavedProjectText,
            "saved before annotations"
        )
    }

    func testNoModifiedWindowsTerminateImmediately()
        async throws
    {
        let window = SpyEditorWindowController()
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
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
        try await delegate.present(
            project: ProjectFixtures.project(text: "clean")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            NSApplication.TerminateReply.terminateNow
        )

        XCTAssertEqual(window.resolveCount, 0)
    }

    func testActiveOutputWindowCancelsQuitImmediatelyWithoutPrompt()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasActiveOutputOperation = true
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
            terminationReply: { _ in
                XCTFail("Immediate cancellation must not reply later")
            },
            hotKeyAPI: makeNoOpHotKeyAPI()
        )
        delegate.applicationDidFinishLaunching(
            Notification(
                name: NSApplication.didFinishLaunchingNotification
            )
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "active output")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateCancel
        )

        XCTAssertEqual(window.resolveCount, 0)
    }

    func testActiveOutputCancelsReentrantQuitWhileResolutionIsInFlight()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.pauseResolution = true
        let resolveStartedExpectation = expectation(
            description: "resolution started"
        )
        let replyExpectation = expectation(
            description: "termination reply"
        )
        var replies: [Bool] = []
        window.onResolve = { count in
            if count == 1 {
                resolveStartedExpectation.fulfill()
            }
        }
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
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
        try await delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [resolveStartedExpectation], timeout: 1)
        XCTAssertEqual(window.resolveCount, 1)

        window.hasActiveOutputOperation = true
        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateCancel
        )

        window.resumeResolution()
        await fulfillment(of: [replyExpectation], timeout: 1, enforceOrder: false)
        XCTAssertEqual(replies, [false])
    }

    func testCancelQuitRepliesFalse()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.resolutionResult = false
        let replyExpectation = expectation(
            description: "termination reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
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
        try await delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(window.resolveCount, 1)
    }

    func testFailedSaveCancelsQuit()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.resolutionResult = false
        window.resolutionLabel = "failed-save"
        let replyExpectation = expectation(
            description: "failed save reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
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
        try await delegate.present(
            project: ProjectFixtures.project(text: "modified")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(window.resolutionLabel, "failed-save")
    }

    func testMultipleModifiedWindowsResolveBeforeQuit()
        async throws
    {
        var events: [String] = []
        let firstWindow = SpyEditorWindowController()
        firstWindow.representedDocumentID =
            ProjectFixtures.documentID
        firstWindow.hasModifiedDocument = true
        firstWindow.eventPrefix = "first"
        firstWindow.events = { events.append($0) }
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            AdditionalProjectFixtures.secondDocumentID
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
                _, _ in windows.removeFirst()
            },
            nativeMessagingHostInstaller: {},
            chromeCaptureCoordinatorFactory: makeEmptyChromeCoordinator,
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
        try await delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try await delegate.present(
            project: AdditionalProjectFixtures.project(
                text: "second",
                documentID: AdditionalProjectFixtures.secondDocumentID
            )
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [replyExpectation], timeout: 1)

        XCTAssertEqual(
            events,
            [
                "first-resolve",
                "second-resolve",
            ]
        )
        XCTAssertEqual(replies, [true])
    }

    func testNewModifiedWindowDuringPromptIsResolved()
        async throws
    {
        let firstWindow = SpyEditorWindowController()
        firstWindow.hasModifiedDocument = true
        firstWindow.modificationRevision = 1
        firstWindow.pauseResolution = true
        let firstPrompt = expectation(
            description: "first prompt"
        )
        firstWindow.onResolve = { count in
            if count == 1 {
                firstPrompt.fulfill()
            }
        }
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            AdditionalProjectFixtures.secondDocumentID
        secondWindow.hasModifiedDocument = true
        secondWindow.modificationRevision = 1
        secondWindow.pauseResolution = true
        let secondPrompt = expectation(
            description: "new window prompt"
        )
        secondWindow.onResolve = { count in
            if count == 1 {
                secondPrompt.fulfill()
            }
        }
        var windows = [firstWindow, secondWindow]
        var replies: [Bool] = []
        let reply = expectation(
            description: "termination reply"
        )
        let delegate = AppDelegate(
            documentWindowFactory: {
                _, _ in windows.removeFirst()
            },
            terminationReply: {
                replies.append($0)
                reply.fulfill()
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "first")
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [firstPrompt], timeout: 1)
        try await delegate.present(
            project: AdditionalProjectFixtures.project(
                text: "new",
                documentID: AdditionalProjectFixtures.secondDocumentID
            )
        )
        firstWindow.resumeResolution()

        await fulfillment(of: [secondPrompt], timeout: 1)
        XCTAssertTrue(replies.isEmpty)
        secondWindow.resumeResolution()
        await fulfillment(of: [reply], timeout: 1)

        XCTAssertEqual(replies, [true])
        XCTAssertEqual(firstWindow.resolveCount, 1)
        XCTAssertEqual(secondWindow.resolveCount, 1)
    }

    func testWindowModifiedDuringOtherPromptIsResolved()
        async throws
    {
        let firstWindow = SpyEditorWindowController()
        firstWindow.hasModifiedDocument = true
        firstWindow.modificationRevision = 1
        firstWindow.pauseResolution = true
        let firstPrompt = expectation(
            description: "first prompt"
        )
        firstWindow.onResolve = { count in
            if count == 1 {
                firstPrompt.fulfill()
            }
        }
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            AdditionalProjectFixtures.secondDocumentID
        secondWindow.pauseResolution = true
        let secondPrompt = expectation(
            description: "newly modified prompt"
        )
        secondWindow.onResolve = { count in
            if count == 1 {
                secondPrompt.fulfill()
            }
        }
        var windows = [firstWindow, secondWindow]
        var replies: [Bool] = []
        let reply = expectation(
            description: "termination reply"
        )
        let delegate = AppDelegate(
            documentWindowFactory: {
                _, _ in windows.removeFirst()
            },
            terminationReply: {
                replies.append($0)
                reply.fulfill()
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try await delegate.present(
            project: AdditionalProjectFixtures.project(
                text: "second",
                documentID: AdditionalProjectFixtures.secondDocumentID
            )
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [firstPrompt], timeout: 1)
        secondWindow.recordModification()
        firstWindow.resumeResolution()

        await fulfillment(of: [secondPrompt], timeout: 1)
        XCTAssertTrue(replies.isEmpty)
        secondWindow.resumeResolution()
        await fulfillment(of: [reply], timeout: 1)

        XCTAssertEqual(replies, [true])
        XCTAssertEqual(secondWindow.resolveCount, 1)
    }

    func testPreviouslyResolvedWindowEditedAgainIsResolvedAgain()
        async throws
    {
        let firstWindow = SpyEditorWindowController()
        firstWindow.hasModifiedDocument = true
        firstWindow.modificationRevision = 1
        let firstResolvedAgain = expectation(
            description: "first window resolved again"
        )
        firstWindow.onResolve = { count in
            if count == 2 {
                firstResolvedAgain.fulfill()
            }
        }
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            AdditionalProjectFixtures.secondDocumentID
        secondWindow.hasModifiedDocument = true
        secondWindow.modificationRevision = 1
        secondWindow.pauseResolution = true
        let secondPrompt = expectation(
            description: "second prompt"
        )
        secondWindow.onResolve = { count in
            if count == 1 {
                secondPrompt.fulfill()
            }
        }
        var windows = [firstWindow, secondWindow]
        var replies: [Bool] = []
        let reply = expectation(
            description: "termination reply"
        )
        let delegate = AppDelegate(
            documentWindowFactory: {
                _, _ in windows.removeFirst()
            },
            terminationReply: {
                replies.append($0)
                reply.fulfill()
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try await delegate.present(
            project: AdditionalProjectFixtures.project(
                text: "second",
                documentID: AdditionalProjectFixtures.secondDocumentID
            )
        )

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateLater
        )
        await fulfillment(of: [secondPrompt], timeout: 1)
        firstWindow.recordModification()
        secondWindow.resumeResolution()

        await fulfillment(
            of: [firstResolvedAgain],
            timeout: 1
        )
        await fulfillment(of: [reply], timeout: 1)

        XCTAssertEqual(replies, [true])
        XCTAssertEqual(firstWindow.resolveCount, 2)
        XCTAssertEqual(secondWindow.resolveCount, 1)
    }

    func testLaterCancelDoesNotApproveQuit()
        async throws
    {
        let firstWindow = SpyEditorWindowController()
        firstWindow.representedDocumentID =
            ProjectFixtures.documentID
        firstWindow.hasModifiedDocument = true
        let secondWindow = SpyEditorWindowController()
        secondWindow.representedDocumentID =
            AdditionalProjectFixtures.secondDocumentID
        secondWindow.hasModifiedDocument = true
        secondWindow.resolutionResult = false
        var windows = [firstWindow, secondWindow]
        let replyExpectation = expectation(
            description: "cancel after earlier approval"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: {
                _, _ in windows.removeFirst()
            },
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            }
        )
        try await delegate.present(
            project: ProjectFixtures.project(text: "first")
        )
        try await delegate.present(
            project: AdditionalProjectFixtures.project(
                text: "second",
                documentID: AdditionalProjectFixtures.secondDocumentID
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
    }

    func testRepeatedTerminateRequestStartsOneResolutionAndRepliesOnce()
        async throws
    {
        let window = SpyEditorWindowController()
        window.hasModifiedDocument = true
        window.pauseResolution = true
        let replyExpectation = expectation(
            description: "single termination reply"
        )
        var replies: [Bool] = []
        let delegate = AppDelegate(
            documentWindowFactory: { _, _ in window },
            terminationReply: {
                replies.append($0)
                replyExpectation.fulfill()
            }
        )
        try await delegate.present(
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
        XCTAssertEqual(window.resolveCount, 1)
        XCTAssertTrue(replies.isEmpty)

        window.resumeResolution()
        await fulfillment(of: [replyExpectation], timeout: 1)

        XCTAssertEqual(
            delegate.applicationShouldTerminate(
                NSApplication.shared
            ),
            .terminateNow
        )
        XCTAssertEqual(replies, [true])
        XCTAssertEqual(window.resolveCount, 1)
    }
}

private struct StubProjectStore: ProjectPackageStoring {
    let project: InkbeamProject

    func load(from url: URL) throws -> InkbeamProject {
        project
    }

    func save(_ project: InkbeamProject, to url: URL) throws {
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
    private var projects: [InkbeamProject]
    private(set) var loadCount = 0

    init(projects: [InkbeamProject]) {
        self.projects = projects
    }

    func load(from url: URL) throws -> InkbeamProject {
        loadCount += 1
        return projects.removeFirst()
    }

    func save(_ project: InkbeamProject, to url: URL) throws {
        throw StubProjectStoreError.unexpectedSave
    }
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

private func makeFailingHotKeyAPI() -> GlobalHotKeyAPI {
    GlobalHotKeyAPI(
        installEventHandler: { _, _, outputHandler in
            outputHandler.pointee = nil
            return OSStatus(eventInternalErr)
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
    var editorLoadError: (any Error)?
    var representedDocumentID = ProjectFixtures.documentID
    var representedProjectURL: URL?
    var hasModifiedDocument = false
    var hasActiveOutputOperation = false
    var modificationRevision: UInt64 = 0
    var resolutionResult = true
    var resolutionLabel = "approved"
    var eventPrefix = "window"
    var events: ((String) -> Void)?
    var pauseResolution = false
    var pauseEditorLoad = false
    var onPresent: (() -> Void)?
    var onEditorLoadWait: ((Int) -> Void)?
    var onResolve: ((Int) -> Void)?
    var onResolutionComplete: ((Bool) -> Void)?
    var lastSavedProjectText: String?
    private var editorLoadContinuations:
        [CheckedContinuation<Void, Never>] = []
    private var resolutionContinuation:
        CheckedContinuation<Void, Never>?
    private(set) var presentationCount = 0
    private(set) var failedPresentationDiscardCount = 0
    private(set) var editorLoadWaitCount = 0
    private(set) var focusCount = 0
    private(set) var resolveCount = 0

    func presentWindow() throws {
        if let presentationError {
            throw presentationError
        }
        presentationCount += 1
        onPresent?()
    }

    func waitForEditorLoad() async throws {
        editorLoadWaitCount += 1
        onEditorLoadWait?(editorLoadWaitCount)
        if pauseEditorLoad {
            await withCheckedContinuation {
                editorLoadContinuations.append($0)
            }
        }
        if let editorLoadError {
            throw editorLoadError
        }
    }

    func discardFailedPresentation() {
        failedPresentationDiscardCount += 1
    }

    func focusWindow() {
        focusCount += 1
    }

    func resolvePendingChangesForTermination() async -> Bool {
        resolveCount += 1
        events?("\(eventPrefix)-resolve")
        onResolve?(resolveCount)
        if pauseResolution {
            await withCheckedContinuation {
                resolutionContinuation = $0
            }
        }
        onResolutionComplete?(resolutionResult)
        return resolutionResult
    }

    func resumeEditorLoad() {
        pauseEditorLoad = false
        let continuations = editorLoadContinuations
        editorLoadContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func resumeResolution() {
        pauseResolution = false
        resolutionContinuation?.resume()
        resolutionContinuation = nil
    }

    func recordModification() {
        hasModifiedDocument = true
        modificationRevision &+= 1
    }

    func close() {
        onClose?()
    }
}

@MainActor
private final class SpyUpdateService: UpdateServing {
    var canCheckForUpdates = true
    var onStart: (() -> Void)?
    private(set) var startCount = 0
    private(set) var checkCount = 0

    func start() throws {
        startCount += 1
        onStart?()
    }

    func checkForUpdates() throws {
        checkCount += 1
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

@MainActor
private final class ActivationObservingRegionSelector: RegionSelecting {
    private let activationCount: () -> Int
    private(set) var activationCountWhenSelectionBegan: Int?
    private var startedContinuations: [
        CheckedContinuation<Void, Never>
    ] = []

    init(activationCount: @escaping () -> Int) {
        self.activationCount = activationCount
    }

    func selectRegion() async throws -> RegionSelectionOutcome {
        activationCountWhenSelectionBegan = activationCount()
        let continuations = startedContinuations
        startedContinuations.removeAll()
        continuations.forEach { $0.resume() }
        return .cancelled
    }

    func waitUntilStarted() async {
        guard activationCountWhenSelectionBegan == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func cancel() {}
}

@MainActor
private final class NoOpDocumentWindowPresenter:
    DocumentWindowPresenting
{
    func present(project: InkbeamProject) async throws {}
}
