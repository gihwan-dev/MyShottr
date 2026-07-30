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
        _ projectURL: URL?
    ) throws -> any EditorWindowControlling

    private let dependencies: AppDependencies
    private let applicationLifecycle: ApplicationLifecycle
    private let documentWindowFactory: DocumentWindowFactory
    private var documentWindows: [any EditorWindowControlling] = []
    private var captureCoordinator: RegionCaptureCoordinator?
    private var menuBarController: MenuBarController?
    private var hotKeyRegistrar: GlobalHotKeyRegistrar?

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
        }
    ) {
        self.dependencies = dependencies
        self.applicationLifecycle = applicationLifecycle
        self.documentWindowFactory = documentWindowFactory
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        applicationLifecycle.setActivationPolicy(.accessory)
        let coordinator = dependencies.makeCaptureCoordinator(
            windows: self
        )
        captureCoordinator = coordinator

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
            hotKeyRegistrar = try GlobalHotKeyRegistrar {
                [weak self] in
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

    func present(project: MyShottrProject) {
        openDocument(project: project, projectURL: nil)
    }

    private func captureArea() {
        guard let captureCoordinator else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
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
            openDocument(project: project, projectURL: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func openDocument(
        project: MyShottrProject,
        projectURL: URL?
    ) {
        do {
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
            documentWindows.append(controller)
            applicationLifecycle.setActivationPolicy(.regular)
            applicationLifecycle.activate()
            controller.presentWindow()
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
