import AppKit
import UniformTypeIdentifiers

@MainActor
struct ApplicationLifecycle {
    let setActivationPolicy: (
        NSApplication.ActivationPolicy
    ) -> Void
    let activate: () -> Void

    static let live = ApplicationLifecycle(
        setActivationPolicy: { policy in
            _ = NSApp.setActivationPolicy(policy)
        },
        activate: {
            NSApp.activate(ignoringOtherApps: true)
        }
    )
}

@MainActor
final class AppDelegate:
    NSObject,
    NSApplicationDelegate,
    DocumentWindowPresenting
{
    typealias DocumentWindowFactory = (
        _ project: MyShottrProject,
        _ projectURL: URL?,
        _ isRecoveredDocument: Bool
    ) throws -> any EditorWindowControlling
    typealias NativeMessagingHostInstaller = () throws -> Void
    typealias ChromeCaptureCoordinatorFactory = (
        _ projectFactory: any NewProjectCreating,
        _ windows: any DocumentWindowPresenting
    ) throws -> CaptureInboxCoordinator
    typealias LaunchErrorReporter = (MyShottrUserFacingError) -> Void
    typealias SessionTerminationStateFactory =
        () throws -> any SessionTerminationTracking
    typealias RecoveryStoreFactory =
        () throws -> any RecoveryStoring
    typealias TerminationReply = (Bool) -> Void

    private enum TerminationResolutionState: Equatable {
        case idle
        case resolving
        case approved
    }

    private let dependencies: AppDependencies
    private let applicationLifecycle: ApplicationLifecycle
    private let documentWindowFactory: DocumentWindowFactory
    private let nativeMessagingHostInstaller:
        NativeMessagingHostInstaller
    private let chromeCaptureCoordinatorFactory:
        ChromeCaptureCoordinatorFactory
    private let launchErrorReporter: LaunchErrorReporter
    private let sessionTerminationStateFactory:
        SessionTerminationStateFactory
    private let recoveryStoreFactory: RecoveryStoreFactory
    private let recoveryPrompt: any RecoveryPrompting
    private let terminationReply: TerminationReply
    private let hotKeyAPI: GlobalHotKeyAPI
    private var documentWindows: [any EditorWindowControlling] = []
    private var captureCoordinator: RegionCaptureCoordinator?
    private var chromeCaptureCoordinator: CaptureInboxCoordinator?
    private var menuBarController: MenuBarController?
    private var hotKeyRegistrar: GlobalHotKeyRegistrar?
    private var sessionTerminationState: (
        any SessionTerminationTracking
    )?
    private var terminationRecoveryStore:
        (any RecoveryStoring)?
    private var recoveryCoordinator: RecoveryCoordinator?
    private var terminationResolutionState:
        TerminationResolutionState = .idle

    var activeDocumentWindowCount: Int {
        documentWindows.count
    }

    override convenience init() {
        self.init(
            dependencies: AppDependencies(),
            applicationLifecycle: .live,
            documentWindowFactory: {
                project,
                projectURL,
                isRecoveredDocument in
                try DocumentWindowController(
                    project: project,
                    projectURL: projectURL,
                    isRecoveredDocument: isRecoveredDocument
                )
            }
        )
    }

    init(
        dependencies: AppDependencies = AppDependencies(),
        applicationLifecycle: ApplicationLifecycle = .live,
        documentWindowFactory: @escaping DocumentWindowFactory = {
            project,
            projectURL,
            isRecoveredDocument in
            try DocumentWindowController(
                project: project,
                projectURL: projectURL,
                isRecoveredDocument: isRecoveredDocument
            )
        },
        nativeMessagingHostInstaller:
            @escaping NativeMessagingHostInstaller = {
                try NativeMessagingRegistrar().install()
            },
        chromeCaptureCoordinatorFactory:
            @escaping ChromeCaptureCoordinatorFactory = {
                projectFactory,
                windows in
                CaptureInboxCoordinator(
                    inbox: try PendingCaptureInbox(),
                    projectFactory: projectFactory,
                    windows: windows
                )
            },
        launchErrorReporter:
            @escaping LaunchErrorReporter = {
                UserFacingErrorPresenter().present(
                    $0,
                    from: nil
                )
            },
        sessionTerminationStateFactory:
            @escaping SessionTerminationStateFactory = {
                try SessionTerminationState()
            },
        recoveryStoreFactory:
            @escaping RecoveryStoreFactory = {
                try RecoveryStore()
            },
        recoveryPrompt:
            any RecoveryPrompting = RecoveryAlertPrompt(),
        terminationReply:
            @escaping TerminationReply = {
                NSApp.reply(
                    toApplicationShouldTerminate: $0
                )
            },
        hotKeyAPI: GlobalHotKeyAPI = .live
    ) {
        self.dependencies = dependencies
        self.applicationLifecycle = applicationLifecycle
        self.documentWindowFactory = documentWindowFactory
        self.nativeMessagingHostInstaller =
            nativeMessagingHostInstaller
        self.chromeCaptureCoordinatorFactory =
            chromeCaptureCoordinatorFactory
        self.launchErrorReporter = launchErrorReporter
        self.sessionTerminationStateFactory =
            sessionTerminationStateFactory
        self.recoveryStoreFactory = recoveryStoreFactory
        self.recoveryPrompt = recoveryPrompt
        self.terminationReply = terminationReply
        self.hotKeyAPI = hotKeyAPI
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if documentWindows.isEmpty {
            applicationLifecycle.setActivationPolicy(.accessory)
        }
        startRecovery()
        let coordinator = dependencies.makeCaptureCoordinator(
            windows: self
        )
        captureCoordinator = coordinator

        var registrationError: (any Error)?
        do {
            try nativeMessagingHostInstaller()
        } catch {
            registrationError = error
        }

        var chromeStartupError: (any Error)?
        do {
            let chromeCoordinator = try chromeCaptureCoordinatorFactory(
                dependencies.projectFactory,
                self
            )
            chromeCaptureCoordinator = chromeCoordinator
            chromeCoordinator.start()
        } catch {
            chromeStartupError = error
        }

        if let registrationError {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    registrationError,
                    context: .chromeRegistration
                )
            )
        }
        if let chromeStartupError {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    chromeStartupError,
                    context: .chromeImport
                )
            )
        }

        do {
            menuBarController = try MenuBarController(
                captureArea: { [weak self] in
                    self?.captureArea()
                },
                openProject: { [weak self] in
                    self?.chooseProject()
                },
                quit: {
                    NSApp.terminate(nil)
                }
            )
        } catch {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    error,
                    context: .application
                )
            )
            NSApp.terminate(nil)
            return
        }

        do {
            hotKeyRegistrar = try GlobalHotKeyRegistrar(
                api: hotKeyAPI
            ) { [weak self] in
                self?.captureArea()
            }
        } catch {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    error,
                    context: .globalShortcut
                )
            )
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openProject(at: url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard terminationResolutionState == .approved,
              let sessionTerminationState
        else {
            return
        }
        do {
            try sessionTerminationState.markCleanExit()
        } catch {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    error,
                    context: .recovery
                )
            )
        }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        switch terminationResolutionState {
        case .approved:
            return .terminateNow
        case .resolving:
            return .terminateLater
        case .idle:
            break
        }

        guard documentWindows.contains(
            where: \.hasModifiedDocument
        ) else {
            terminationResolutionState = .approved
            return .terminateNow
        }

        terminationResolutionState = .resolving
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            let approved = await resolveTermination()
            terminationResolutionState =
                approved ? .approved : .idle
            terminationReply(approved)
        }
        return .terminateLater
    }

    func present(project: MyShottrProject) throws {
        _ = try openDocument(
            project: project,
            projectURL: nil,
            isRecoveredDocument: false
        )
    }

    private func captureArea() {
        guard let captureCoordinator else {
            return
        }

        Task { @MainActor in
            guard let error =
                    await captureCoordinator.captureArea()
            else {
                return
            }
            launchErrorReporter(error)
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "myshottr")!,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls {
            openProject(at: url)
        }
    }

    private func openProject(at url: URL) {
        do {
            let project = try dependencies.projectStore.load(from: url)
            _ = try openDocument(
                project: project,
                projectURL: url,
                isRecoveredDocument: false
            )
        } catch {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    error,
                    context: .projectOpen
                )
            )
        }
    }

    @discardableResult
    private func openDocument(
        project: MyShottrProject,
        projectURL: URL?,
        isRecoveredDocument: Bool
    ) throws -> Bool {
        if let existing = existingDocumentWindow(
            documentID: project.manifest.documentId,
            projectURL: projectURL
        ) {
            existing.focusWindow()
            applicationLifecycle.setActivationPolicy(.regular)
            applicationLifecycle.activate()
            return false
        }

        let controller = try documentWindowFactory(
            project,
            projectURL,
            isRecoveredDocument
        )
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else {
                return
            }
            self.documentWindows.removeAll {
                $0 === controller
            }
            if self.documentWindows.isEmpty {
                self.applicationLifecycle.setActivationPolicy(
                    .accessory
                )
            }
        }
        try controller.presentWindow()
        documentWindows.append(controller)
        applicationLifecycle.setActivationPolicy(.regular)
        applicationLifecycle.activate()
        return true
    }

    private func startRecovery() {
        do {
            let terminationState =
                try sessionTerminationStateFactory()
            let previousSessionWasClean =
                try terminationState.beginSession()
            sessionTerminationState = terminationState
            let recoveryStore = try recoveryStoreFactory()
            terminationRecoveryStore = recoveryStore

            let coordinator = RecoveryCoordinator(
                recoveryStore: recoveryStore,
                previousSessionWasClean:
                    previousSessionWasClean,
                prompt: recoveryPrompt,
                reportIssue: {
                    [launchErrorReporter] issue in
                    launchErrorReporter(
                        MyShottrUserFacingError
                            .recoveryScanIssue(issue)
                    )
                },
                restore: { [weak self] recovered in
                    guard let self else {
                        throw AppDelegateRecoveryError
                            .applicationUnavailable
                    }
                    let didOpen = try self.openDocument(
                        project: recovered.project,
                        projectURL: nil,
                        isRecoveredDocument: true
                    )
                    guard didOpen else {
                        throw AppDelegateRecoveryError
                            .documentAlreadyOpen(
                                recovered.documentId
                            )
                    }
                }
            )
            recoveryCoordinator = coordinator
            try coordinator.offerRecoveryIfNeeded()
        } catch {
            launchErrorReporter(
                MyShottrUserFacingError.wrapping(
                    error,
                    context: .recovery
                )
            )
        }
    }

    private func existingDocumentWindow(
        documentID: UUID,
        projectURL: URL?
    ) -> (any EditorWindowControlling)? {
        let normalizedURL = projectURL.map(
            normalizedProjectURL
        )
        return documentWindows.first { controller in
            if controller.representedDocumentID == documentID {
                return true
            }
            guard let normalizedURL,
                  let existingURL =
                    controller.representedProjectURL
            else {
                return false
            }
            return normalizedProjectURL(existingURL)
                == normalizedURL
        }
    }

    private func normalizedProjectURL(_ url: URL) -> URL {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private func resolveTermination() async -> Bool {
        var resolvedRevisions:
            [ObjectIdentifier: UInt64] = [:]

        while true {
            let cycleWindows = documentWindows
            let cycleIdentities = Set(
                cycleWindows.map(windowIdentity)
            )
            resolvedRevisions = resolvedRevisions.filter {
                cycleIdentities.contains($0.key)
            }
            let targets = cycleWindows.filter {
                $0.hasModifiedDocument
                    && resolvedRevisions[
                        windowIdentity($0)
                    ] != $0.modificationRevision
            }

            var flushedRevisions:
                [ObjectIdentifier: UInt64] = [:]
            var shouldRestart = false
            do {
                for window in targets {
                    let identity = windowIdentity(window)
                    let revision =
                        window.modificationRevision
                    try await window
                        .flushRecoveryForTermination()
                    guard documentWindows.contains(
                        where: {
                            windowIdentity($0) == identity
                        }
                    ),
                    window.modificationRevision == revision
                    else {
                        shouldRestart = true
                        break
                    }
                    flushedRevisions[identity] = revision
                }
            } catch {
                launchErrorReporter(
                    MyShottrUserFacingError.wrapping(
                        error,
                        context: .recovery
                    )
                )
                return false
            }
            if shouldRestart {
                continue
            }
            guard Set(
                documentWindows.map(windowIdentity)
            ) == cycleIdentities else {
                continue
            }

            for window in targets {
                let identity = windowIdentity(window)
                guard let revision =
                        flushedRevisions[identity],
                      window.modificationRevision
                        == revision
                else {
                    shouldRestart = true
                    break
                }
                guard await window
                    .resolvePendingChangesForTermination()
                else {
                    return false
                }
                guard documentWindows.contains(
                    where: {
                        windowIdentity($0) == identity
                    }
                ),
                window.modificationRevision == revision
                else {
                    shouldRestart = true
                    break
                }
                resolvedRevisions[identity] = revision
            }
            if shouldRestart {
                continue
            }

            let liveWindows = documentWindows
            guard Set(
                liveWindows.map(windowIdentity)
            ) == cycleIdentities else {
                continue
            }
            guard !liveWindows.contains(
                where: {
                    $0.hasModifiedDocument
                        && resolvedRevisions[
                            windowIdentity($0)
                        ] != $0.modificationRevision
                }
            ) else {
                continue
            }

            do {
                let discardDocumentIDs = liveWindows
                    .compactMap(
                        \.pendingTerminationDiscardDocumentID
                    )
                if !discardDocumentIDs.isEmpty {
                    let recoveryStore:
                        any RecoveryStoring
                    if let terminationRecoveryStore {
                        recoveryStore =
                            terminationRecoveryStore
                    } else {
                        recoveryStore =
                            try recoveryStoreFactory()
                        terminationRecoveryStore =
                            recoveryStore
                    }
                    _ = try recoveryStore.stageDiscard(
                        documentIds: discardDocumentIDs
                    )
                }
            } catch {
                launchErrorReporter(
                    MyShottrUserFacingError.wrapping(
                        error,
                        context: .recovery
                    )
                )
                return false
            }

            for window in liveWindows {
                window
                    .completePendingTerminationAfterDiscardStaged()
            }
            return true
        }
    }

    private func windowIdentity(
        _ window: any EditorWindowControlling
    ) -> ObjectIdentifier {
        ObjectIdentifier(window)
    }
}

private enum AppDelegateRecoveryError: Error {
    case applicationUnavailable
    case documentAlreadyOpen(UUID)
}
