import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var documentWindows: [DocumentWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openProject(at: url) }
    }

    private func openProject(at url: URL) {
        do {
            let project = try ProjectPackageStore().load(from: url)
            let controller = try DocumentWindowController(project: project, projectURL: url)
            controller.onClose = { [weak self, weak controller] in
                guard let controller else { return }
                self?.documentWindows.removeAll { $0 === controller }
            }
            documentWindows.append(controller)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
