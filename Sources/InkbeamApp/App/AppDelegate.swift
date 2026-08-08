import AppKit
import UniformTypeIdentifiers

extension UTType {
    static let inkbeamProject = UTType(
        exportedAs: "dev.gihwan.inkbeam.project",
        conformingTo: .package
    )
}

enum InkbeamProjectURLValidationError: Error {
    case invalidExtension
}

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
    static let editableProjectExtension = "inkbeam"

    typealias DocumentWindowFactory = (
        _ project: InkbeamProject,
        _ projectURL: URL?
    ) throws -> any EditorWindowControlling
    typealias NativeMessagingHostInstaller = () throws -> Void
    typealias ChromeCaptureCoordinatorFactory = (
        _ projectFactory: any NewProjectCreating,
        _ windows: any DocumentWindowPresenting
    ) throws -> CaptureInboxCoordinator
    typealias LaunchErrorReporter = (InkbeamUserFacingError) -> Void
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
    private let terminationReply: TerminationReply
    private let hotKeyAPI: GlobalHotKeyAPI
    private var documentWindows: [any EditorWindowControlling] = []
    private var captureCoordinator: RegionCaptureCoordinator?
    private var chromeCaptureCoordinator: CaptureInboxCoordinator?
    private var menuBarController: MenuBarController?
    private var hotKeyRegistrar: GlobalHotKeyRegistrar?
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
                projectURL in
                try DocumentWindowController(
                    project: project,
                    projectURL: projectURL
                )
            }
        )
    }

    init(
        dependencies: AppDependencies = AppDependencies(),
        applicationLifecycle: ApplicationLifecycle = .live,
        documentWindowFactory: @escaping DocumentWindowFactory = {
            project,
            projectURL in
            try DocumentWindowController(
                project: project,
                projectURL: projectURL
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
                UserFacingErrorPresenter.shared.present(
                    $0,
                    from: nil
                )
            },
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
        self.terminationReply = terminationReply
        self.hotKeyAPI = hotKeyAPI
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if documentWindows.isEmpty {
            applicationLifecycle.setActivationPolicy(.accessory)
        }
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
                InkbeamUserFacingError.wrapping(
                    registrationError,
                    context: .chromeRegistration
                )
            )
        }
        if let chromeStartupError {
            launchErrorReporter(
                InkbeamUserFacingError.wrapping(
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
                InkbeamUserFacingError.wrapping(
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
                InkbeamUserFacingError.wrapping(
                    error,
                    context: .globalShortcut
                )
            )
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openProject(at: url) }
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard !documentWindows.contains(
            where: \.hasActiveOutputOperation
        ) else {
            return .terminateCancel
        }

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

    func present(
        project: InkbeamProject
    ) async throws {
        let opening = try beginOpeningDocument(
            project: project,
            projectURL: nil
        )
        do {
            try await opening.controller
                .waitForEditorLoad()
        } catch {
            discardFailedOpening(opening.controller)
            throw error
        }
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
        panel.allowedContentTypes = [.inkbeamProject]
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
        guard Self.isEditableProjectURL(url) else {
            launchErrorReporter(
                InkbeamUserFacingError.wrapping(
                    InkbeamProjectURLValidationError.invalidExtension,
                    context: .projectOpen
                )
            )
            return
        }
        do {
            let project = try dependencies.projectStore.load(from: url)
            _ = try openDocument(
                project: project,
                projectURL: url
            )
        } catch {
            launchErrorReporter(
                InkbeamUserFacingError.wrapping(
                    error,
                    context: .projectOpen
                )
            )
        }
    }

    static func isEditableProjectURL(_ url: URL) -> Bool {
        url.pathExtension == editableProjectExtension
    }

    @discardableResult
    private func openDocument(
        project: InkbeamProject,
        projectURL: URL?
    ) throws -> Bool {
        let opening = try beginOpeningDocument(
            project: project,
            projectURL: projectURL
        )
        Task { @MainActor [weak self] in
            do {
                try await opening.controller
                    .waitForEditorLoad()
            } catch {
                guard let self else {
                    return
                }
                discardFailedOpening(opening.controller)
                launchErrorReporter(
                    InkbeamUserFacingError.wrapping(
                        error,
                        context: .editorBridge
                    )
                )
            }
        }
        return opening.didCreate
    }

    private func beginOpeningDocument(
        project: InkbeamProject,
        projectURL: URL?
    ) throws -> (
        controller: any EditorWindowControlling,
        didCreate: Bool
    ) {
        if let existing = existingDocumentWindow(
            documentID: project.manifest.documentId,
            projectURL: projectURL
        ) {
            existing.focusWindow()
            applicationLifecycle.setActivationPolicy(.regular)
            applicationLifecycle.activate()
            return (existing, false)
        }

        let controller = try documentWindowFactory(
            project,
            projectURL
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
        return (controller, true)
    }

    private func discardFailedOpening(
        _ controller: any EditorWindowControlling
    ) {
        guard let index = documentWindows.firstIndex(
            where: { $0 === controller }
        ) else {
            return
        }
        documentWindows.remove(at: index)
        controller.discardFailedPresentation()
        if documentWindows.isEmpty {
            applicationLifecycle.setActivationPolicy(
                .accessory
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

            var shouldRestart = false
            for window in targets {
                let identity = windowIdentity(window)
                let revision = window.modificationRevision
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
            guard !liveWindows.contains(
                where: \.hasActiveOutputOperation
            ) else {
                return false
            }
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
            return true
        }
    }

    private func windowIdentity(
        _ window: any EditorWindowControlling
    ) -> ObjectIdentifier {
        ObjectIdentifier(window)
    }
}
