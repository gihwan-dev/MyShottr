import AppKit

enum MenuBarControllerError: Error, Equatable {
    case missingStatusIcon
}

@MainActor
final class MenuBarController: NSObject, NSMenuItemValidation {
    typealias ImageLoader = (NSImage.Name) -> NSImage?

    nonisolated(unsafe) let statusItem: NSStatusItem

    nonisolated(unsafe) private let statusBar: NSStatusBar
    private let about: () -> Void
    private let captureArea: () -> Void
    private let openProject: () -> Void
    private let checkForUpdates: () -> Void
    private let canCheckForUpdates: () -> Bool
    private let quit: () -> Void

    init(
        about: @escaping () -> Void,
        captureArea: @escaping () -> Void,
        openProject: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        canCheckForUpdates: @escaping () -> Bool,
        quit: @escaping () -> Void,
        imageLoader: ImageLoader = NSImage.init(named:),
        statusBar: NSStatusBar = .system
    ) throws {
        guard let image = imageLoader("StatusBarIcon") else {
            throw MenuBarControllerError.missingStatusIcon
        }
        image.isTemplate = true

        self.about = about
        self.captureArea = captureArea
        self.openProject = openProject
        self.checkForUpdates = checkForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        self.quit = quit
        self.statusBar = statusBar
        self.statusItem = statusBar.statusItem(
            withLength: NSStatusItem.squareLength
        )
        super.init()

        statusItem.button?.image = image
        statusItem.button?.toolTip = "Inkbeam"
        statusItem.menu = makeMenu()
    }

    deinit {
        statusBar.removeStatusItem(statusItem)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdatesAction(_:)) {
            return canCheckForUpdates()
        }
        return true
    }

    @objc private func aboutAction(_ sender: Any?) {
        about()
    }

    @objc private func captureAreaAction(_ sender: Any?) {
        captureArea()
    }

    @objc private func openProjectAction(_ sender: Any?) {
        openProject()
    }

    @objc private func checkForUpdatesAction(_ sender: Any?) {
        checkForUpdates()
    }

    @objc private func quitAction(_ sender: Any?) {
        quit()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About Inkbeam",
            action: #selector(aboutAction(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

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

        let updateItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdatesAction(_:)),
            keyEquivalent: ""
        )
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Inkbeam",
            action: #selector(quitAction(_:)),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }
}
