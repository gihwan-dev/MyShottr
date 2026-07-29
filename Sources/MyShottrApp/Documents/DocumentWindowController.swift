import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let session: DocumentSession
    private let editorWebView: EditorWebView
    private let projectStore: any ProjectPackageStoring
    private var projectURL: URL?
    private var closeAfterPrompt = false
    var onClose: (() -> Void)?

    init(project: MyShottrProject, projectURL: URL?, projectStore: any ProjectPackageStoring = ProjectPackageStore()) throws {
        let session = DocumentSession()
        self.session = session
        self.editorWebView = EditorWebView(session: session)
        self.projectStore = projectStore
        self.projectURL = projectURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled MyShottr Project"
        window.contentView = editorWebView.webView
        window.delegate = self
        window.toolbar = makeToolbar()
        session.onModifiedStateChange = { [weak window] modified in window?.isDocumentEdited = modified }
        try editorWebView.load(project: project)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAfterPrompt || !session.isModified { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes before closing?"
        alert.informativeText = "Your annotation changes will be lost if you discard them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                Task { @MainActor in
                    if await self.saveProject() {
                        self.closeAfterPrompt = true
                        self.window?.performClose(nil)
                    }
                }
            case .alertSecondButtonReturn:
                self.session.close()
                self.closeAfterPrompt = true
                self.window?.performClose(nil)
            default:
                break
            }
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        editorWebView.tearDown()
        session.close()
        onClose?()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.copyComposite, .saveProject, .exportComposite, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.copyComposite, .flexibleSpace, .saveProject, .exportComposite]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        switch itemIdentifier {
        case .copyComposite:
            item.label = "Copy"
            item.toolTip = "Copy annotated PNG"
            item.target = self
            item.action = #selector(copyComposite(_:))
        case .saveProject:
            item.label = "Save"
            item.toolTip = "Save MyShottr project"
            item.target = self
            item.action = #selector(saveProjectAction(_:))
        case .exportComposite:
            item.label = "Export"
            item.toolTip = "Export annotated PNG"
            item.target = self
            item.action = #selector(exportComposite(_:))
        default:
            return nil
        }
        return item
    }

    @objc private func copyComposite(_ sender: Any?) {
        Task { @MainActor in
            do {
                let transfer = try await editorWebView.requestComposite()
                defer { transfer.discard() }
                try PNGClipboardWriter().write(data: transfer.data())
            } catch {
                present(error)
            }
        }
    }

    @objc private func saveProjectAction(_ sender: Any?) {
        Task { @MainActor in _ = await saveProject() }
    }

    @objc private func exportComposite(_ sender: Any?) {
        guard let destinationURL = choosePNGExportURL() else { return }
        Task { @MainActor in
            do {
                let transfer = try await editorWebView.requestComposite(destinationDirectory: destinationURL.deletingLastPathComponent())
                defer { transfer.discard() }
                try transfer.move(to: destinationURL)
            } catch {
                present(error)
            }
        }
    }

    private func saveProject() async -> Bool {
        do {
            _ = try await editorWebView.requestAnnotationSnapshot()
            let project = try session.projectForSave()
            let url: URL
            if let projectURL {
                url = projectURL
            } else {
                guard let selectedURL = chooseProjectSaveURL() else { return false }
                url = selectedURL
            }
            try projectStore.save(project, to: url)
            projectURL = url
            try session.completeSave(project)
            window?.title = url.deletingPathExtension().lastPathComponent
            return true
        } catch {
            present(error)
            return false
        }
    }

    private func chooseProjectSaveURL() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "myshottr")!]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Untitled.myshottr"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func choosePNGExportURL() -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Annotated.png"
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "MyShottrDocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        return toolbar
    }

    private func present(_ error: Error) {
        NSAlert(error: error).beginSheetModal(for: window ?? NSWindow())
    }
}

private extension NSToolbarItem.Identifier {
    static let copyComposite = NSToolbarItem.Identifier("com.myshottr.copyComposite")
    static let saveProject = NSToolbarItem.Identifier("com.myshottr.saveProject")
    static let exportComposite = NSToolbarItem.Identifier("com.myshottr.exportComposite")
}
