import AppKit

enum MenuBarControllerError: Error, Equatable {
    case missingStatusIcon
}

@MainActor
final class MenuBarController: NSObject {
    typealias ImageLoader = (NSImage.Name) -> NSImage?

    nonisolated(unsafe) let statusItem: NSStatusItem

    nonisolated(unsafe) private let statusBar: NSStatusBar
    private let captureArea: () -> Void
    private let openProject: () -> Void
    private let quit: () -> Void

    init(
        captureArea: @escaping () -> Void,
        openProject: @escaping () -> Void,
        quit: @escaping () -> Void,
        imageLoader: ImageLoader = NSImage.init(named:),
        statusBar: NSStatusBar = .system
    ) throws {
        guard let image = imageLoader("StatusBarIcon") else {
            throw MenuBarControllerError.missingStatusIcon
        }
        image.isTemplate = true

        self.captureArea = captureArea
        self.openProject = openProject
        self.quit = quit
        self.statusBar = statusBar
        self.statusItem = statusBar.statusItem(
            withLength: NSStatusItem.squareLength
        )
        super.init()

        statusItem.button?.image = image
        statusItem.button?.toolTip = "MyShottr"
        statusItem.menu = makeMenu()
    }

    deinit {
        statusBar.removeStatusItem(statusItem)
    }

    @objc private func captureAreaAction(_ sender: Any?) {
        captureArea()
    }

    @objc private func openProjectAction(_ sender: Any?) {
        openProject()
    }

    @objc private func quitAction(_ sender: Any?) {
        quit()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let captureItem = NSMenuItem(
            title: "Capture Area",
            action: #selector(captureAreaAction(_:)),
            keyEquivalent: "2"
        )
        captureItem.target = self
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureItem)

        let openItem = NSMenuItem(
            title: "Open Project…",
            action: #selector(openProjectAction(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MyShottr",
            action: #selector(quitAction(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }
}
