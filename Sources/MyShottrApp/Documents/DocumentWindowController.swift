import AppKit
import UniformTypeIdentifiers

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let session: DocumentSession
    private let editorWebView: EditorWebView
    private let projectStore: any ProjectPackageStoring
    let representedDocumentID: UUID
    private var projectURL: URL?
    private var closeAfterPrompt = false
    private var discardRecoveryOnApprovedTermination = false
    var onClose: (() -> Void)?

    init(
        project: MyShottrProject,
        projectURL: URL?,
        projectStore: any ProjectPackageStoring = ProjectPackageStore(),
        preferences: any EditorPreferencesStoring =
            UserDefaultsEditorPreferencesStore(),
        recoveryStore: (any RecoveryStoring)? = nil,
        isRecoveredDocument: Bool = false
    ) throws {
        let resolvedRecoveryStore: any RecoveryStoring
        if let recoveryStore {
            resolvedRecoveryStore = recoveryStore
        } else {
            resolvedRecoveryStore = try RecoveryStore()
        }
        let session = DocumentSession(
            recoveryStore: resolvedRecoveryStore
        )
        self.session = session
        self.editorWebView = EditorWebView(session: session, preferences: preferences)
        self.projectStore = projectStore
        self.representedDocumentID =
            project.manifest.documentId
        self.projectURL = projectURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        self.nextResponder = window.nextResponder
        window.nextResponder = self
        window.title = projectURL?
            .deletingPathExtension()
            .lastPathComponent
            ?? (
                isRecoveredDocument
                    ? "Recovered MyShottr Project"
                    : "Untitled MyShottr Project"
            )
        window.contentView = editorWebView.webView
        window.delegate = self
        window.toolbar = makeToolbar()
        session.onModifiedStateChange = {
            [weak window] modified in
            window?.isDocumentEdited = modified
        }
        session.onRecoveryFailure = { [weak self] error in
            self?.present(error)
        }
        session.recoverySnapshotProvider = {
            [weak editorWebView] in
            guard let editorWebView else {
                throw EditorBridgeError.cancelled
            }
            return try await editorWebView
                .requestAnnotationSnapshot()
        }
        editorWebView.onNavigationFailure = {
            [weak self] error in
            self?.present(error)
        }
        if isRecoveredDocument {
            session.prepareForRecoveryRestore()
        }
        try editorWebView.load(project: project)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if closeAfterPrompt || !session.isModified { return true }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            if await resolvePendingChangesForTermination() {
                do {
                    try finalizePendingTermination()
                    closeAfterPrompt = true
                    window?.performClose(nil)
                } catch {
                    present(error)
                }
            }
        }
        return false
    }

    func resolvePendingChangesForTermination() async -> Bool {
        discardRecoveryOnApprovedTermination = false
        guard session.isModified,
              let window
        else {
            return true
        }
        return await withCheckedContinuation {
            continuation in
            let alert = NSAlert()
            alert.messageText = "Save changes before closing?"
            alert.informativeText =
                "Your annotation changes will be lost if you discard them."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) {
                [weak self] response in
                guard let self else {
                    continuation.resume(returning: false)
                    return
                }
                switch response {
                case .alertFirstButtonReturn:
                    Task { @MainActor in
                        continuation.resume(
                            returning: await self.saveProject()
                        )
                    }
                case .alertSecondButtonReturn:
                    self.discardRecoveryOnApprovedTermination =
                        true
                    continuation.resume(returning: true)
                default:
                    continuation.resume(returning: false)
                }
            }
        }
    }

    func finalizePendingTermination() throws {
        guard discardRecoveryOnApprovedTermination else {
            return
        }
        try session.discardRecovery()
        discardRecoveryOnApprovedTermination = false
    }

    func flushRecoveryForTermination() async throws {
        try await session.flushRecoveryForTermination()
    }

    func focusWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
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
            item.label = "Copy Image"
            item.toolTip = "Copy the annotated PNG (Command-Shift-C)"
            item.target = self
            item.action = #selector(copyComposite(_:))
        case .saveProject:
            item.label = "Save Project"
            item.toolTip = "Save an editable MyShottr project (Command-S)"
            item.target = self
            item.action = #selector(saveProjectAction(_:))
        case .exportComposite:
            item.label = "Export PNG"
            item.toolTip = "Export the annotated PNG (Command-E)"
            item.target = self
            item.action = #selector(exportComposite(_:))
        default:
            return nil
        }
        return item
    }

    @objc func copyComposite(_ sender: Any?) -> Bool {
        guard window?.isKeyWindow == true else { return false }
        Task { @MainActor in
            do {
                let transfer = try await editorWebView.requestComposite()
                defer { transfer.discard() }
                try PNGClipboardWriter().write(data: transfer.data())
            } catch {
                present(error)
            }
        }
        return true
    }

    @objc func saveProjectAction(_ sender: Any?) -> Bool {
        guard window?.isKeyWindow == true else { return false }
        Task { @MainActor in _ = await saveProject() }
        return true
    }

    @objc func exportComposite(_ sender: Any?) -> Bool {
        guard window?.isKeyWindow == true, let destinationURL = choosePNGExportURL() else { return false }
        Task { @MainActor in
            do {
                let transfer = try await editorWebView.requestComposite(destinationDirectory: destinationURL.deletingLastPathComponent())
                defer { transfer.discard() }
                try transfer.move(to: destinationURL)
            } catch {
                present(error)
            }
        }
        return true
    }

    private func saveProject() async -> Bool {
        do {
            let annotationJSON =
                try await editorWebView.requestAnnotationSnapshot()
            try session.install(annotationJSON: annotationJSON)
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

    @discardableResult
    func present(_ error: Error) -> Bool {
        guard let window else { return false }
        NSAlert(error: error).beginSheetModal(for: window)
        return true
    }
}

private extension NSToolbarItem.Identifier {
    static let copyComposite = NSToolbarItem.Identifier("com.myshottr.copyComposite")
    static let saveProject = NSToolbarItem.Identifier("com.myshottr.saveProject")
    static let exportComposite = NSToolbarItem.Identifier("com.myshottr.exportComposite")
}

@MainActor
protocol EditorWindowControlling: AnyObject {
    var onClose: (() -> Void)? { get set }
    var representedDocumentID: UUID { get }
    var representedProjectURL: URL? { get }
    var hasModifiedDocument: Bool { get }
    func presentWindow() throws
    func focusWindow()
    func flushRecoveryForTermination() async throws
    func resolvePendingChangesForTermination() async -> Bool
    func finalizePendingTermination() throws
}

extension DocumentWindowController: EditorWindowControlling {
    var representedProjectURL: URL? {
        projectURL
    }

    var hasModifiedDocument: Bool {
        session.isModified
    }

    func presentWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
