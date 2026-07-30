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
    typealias LaunchErrorReporter = (any Error) -> Void
    typealias SessionTerminationStateFactory =
        () throws -> any SessionTerminationTracking
    typealias RecoveryStoreFactory =
        () throws -> any RecoveryStoring

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
    private let hotKeyAPI: GlobalHotKeyAPI
    private var documentWindows: [any EditorWindowControlling] = []
    private var captureCoordinator: RegionCaptureCoordinator?
    private var chromeCaptureCoordinator: CaptureInboxCoordinator?
    private var menuBarController: MenuBarController?
    private var hotKeyRegistrar: GlobalHotKeyRegistrar?
    private var sessionTerminationState: (
        any SessionTerminationTracking
    )?
    private var recoveryCoordinator: RecoveryCoordinator?

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
                NSAlert(error: $0).runModal()
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
            try chromeCoordinator.start()
        } catch {
            chromeStartupError = error
        }

        if let registrationError {
            launchErrorReporter(registrationError)
        }
        if let chromeStartupError {
            launchErrorReporter(chromeStartupError)
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
            hotKeyRegistrar = try GlobalHotKeyRegistrar(
                api: hotKeyAPI
            ) { [weak self] in
                self?.captureArea()
            }
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openProject(at: url) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let sessionTerminationState else {
            return
        }
        do {
            try sessionTerminationState.markCleanExit()
        } catch {
            launchErrorReporter(error)
        }
    }

    func present(project: MyShottrProject) throws {
        try openDocument(
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
            if let error = await captureCoordinator.captureArea(),
               error as? CaptureError != .captureAlreadyInProgress {
                NSAlert(error: error).runModal()
            }
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
            try openDocument(
                project: project,
                projectURL: url,
                isRecoveredDocument: false
            )
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func openDocument(
        project: MyShottrProject,
        projectURL: URL?,
        isRecoveredDocument: Bool
    ) throws {
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
    }

    private func startRecovery() {
        do {
            let terminationState =
                try sessionTerminationStateFactory()
            let previousSessionWasClean =
                try terminationState.beginSession()
            sessionTerminationState = terminationState

            let coordinator = RecoveryCoordinator(
                recoveryStore: try recoveryStoreFactory(),
                previousSessionWasClean:
                    previousSessionWasClean,
                prompt: recoveryPrompt,
                restore: { [weak self] recovered in
                    guard let self else {
                        throw AppDelegateRecoveryError
                            .applicationUnavailable
                    }
                    try self.openDocument(
                        project: recovered.project,
                        projectURL: nil,
                        isRecoveredDocument: true
                    )
                }
            )
            recoveryCoordinator = coordinator
            try coordinator.offerRecoveryIfNeeded()
        } catch {
            launchErrorReporter(error)
        }
    }
}

private enum AppDelegateRecoveryError: Error {
    case applicationUnavailable
}
