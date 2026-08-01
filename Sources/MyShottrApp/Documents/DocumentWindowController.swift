import AppKit
import UniformTypeIdentifiers

enum DocumentPendingChangesDecision {
    case save
    case discard
    case cancel
}

@MainActor
final class DocumentTerminationResolutionGate {
    private var inFlight: Task<Bool, Never>?

    func resolve(
        operation:
            @escaping @MainActor () async -> Bool
    ) async -> Bool {
        if let inFlight {
            return await inFlight.value
        }
        let task = Task { @MainActor in
            await operation()
        }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}

@MainActor
final class DocumentWindowController:
    NSWindowController,
    NSWindowDelegate,
    NSToolbarDelegate,
    NSToolbarItemValidation
{
    private enum OutputOperation {
        case copy
        case save
        case export
    }

    private let session: DocumentSession
    private let editorWebView: EditorWebView
    private let editorLoadOperation: EditorLoadOperation?
    private let historyActionSender:
        @MainActor (EditorHistoryAction) -> Void
    private let commandWindowPredicate:
        @MainActor (NSWindow?) -> Bool
    private let projectStore: any ProjectPackageStoring
    private let errorPresenter: any UserFacingErrorPresenting
    let representedDocumentID: UUID
    private var projectURL: URL?
    private var closeAfterPrompt = false
    private let annotationSnapshotProvider:
        (@MainActor () async throws -> Data)?
    private let pendingChangesDecisionProvider:
        (@MainActor () async -> DocumentPendingChangesDecision)?
    private let projectSaveURLProvider:
        (@MainActor () -> URL?)?
    private let closeWindow: (@MainActor () -> Void)?
    private let terminationResolutionGate =
        DocumentTerminationResolutionGate()
    private var editorIsReady = false
    private var historyState = EditorHistoryState(
        canUndo: false,
        canRedo: false
    )
    private var outputOperation: OutputOperation?
    var onClose: (() -> Void)?

    init(
        project: MyShottrProject,
        projectURL: URL?,
        projectStore: any ProjectPackageStoring = ProjectPackageStore(),
        preferences: any EditorPreferencesStoring =
            UserDefaultsEditorPreferencesStore(),
        errorPresenter: any UserFacingErrorPresenting =
            UserFacingErrorPresenter.shared,
        testSession: DocumentSession? = nil,
        annotationSnapshotProvider:
            (@MainActor () async throws -> Data)? = nil,
        pendingChangesDecisionProvider:
            (@MainActor () async -> DocumentPendingChangesDecision)? =
                nil,
        projectSaveURLProvider:
            (@MainActor () -> URL?)? = nil,
        closeWindow: (@MainActor () -> Void)? = nil,
        historyActionSender:
            (@MainActor (EditorHistoryAction) -> Void)? = nil,
        commandWindowPredicate:
            @escaping @MainActor (NSWindow?) -> Bool = {
                $0?.isKeyWindow == true
            }
    ) throws {
        let session: DocumentSession
        if let testSession {
            session = testSession
        } else {
            session = DocumentSession()
        }
        let editorWebView = EditorWebView(
            session: session,
            preferences: preferences
        )
        let editorLoadOperation: EditorLoadOperation?
        if testSession == nil {
            if projectURL == nil {
                try session.openUnsaved(project: project)
            } else {
                try session.open(project: project)
            }
            editorLoadOperation = try editorWebView.load(
                project: project
            )
        } else {
            editorLoadOperation = nil
        }
        self.session = session
        self.editorWebView = editorWebView
        self.editorLoadOperation = editorLoadOperation
        if let historyActionSender {
            self.historyActionSender = historyActionSender
        } else {
            self.historyActionSender = { action in
                editorWebView.performHistoryAction(action)
            }
        }
        self.commandWindowPredicate = commandWindowPredicate
        self.projectStore = projectStore
        self.errorPresenter = errorPresenter
        self.annotationSnapshotProvider =
            annotationSnapshotProvider
        self.pendingChangesDecisionProvider =
            pendingChangesDecisionProvider
        self.projectSaveURLProvider =
            projectSaveURLProvider
        self.closeWindow = closeWindow
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
            ?? "Untitled MyShottr Project"
        window.contentView = editorWebView.webView
        window.delegate = self
        window.toolbar = makeToolbar()
        session.onModifiedStateChange = {
            [weak window] modified in
            window?.isDocumentEdited = modified
        }
        editorWebView.onNavigationFailure = {
            [weak self] error in
            self?.present(
                .wrapping(error, context: .editorBridge)
            )
        }
        editorWebView.onBridgeFailure = {
            [weak self] error in
            self?.receiveBridgeFailure(error)
        }
        editorWebView.onProtocolFailure = {
            [weak self] error in
            self?.present(.editorProtocol(error))
        }
        editorWebView.onHistoryStateChanged = {
            [weak self] state in
            self?.receiveHistoryState(state)
        }
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
                closeAfterPrompt = true
                if let closeWindow {
                    closeWindow()
                } else {
                    window?.performClose(nil)
                }
            }
        }
        return false
    }

    func resolvePendingChangesForTermination() async -> Bool {
        await terminationResolutionGate.resolve {
            [weak self] in
            guard let self else {
                return false
            }
            return await presentPendingChangesResolution()
        }
    }

    private func presentPendingChangesResolution() async -> Bool {
        guard session.isModified,
              let window
        else {
            return true
        }
        let decision: DocumentPendingChangesDecision
        if let pendingChangesDecisionProvider {
            decision = await pendingChangesDecisionProvider()
        } else {
            decision = await presentPendingChangesAlert(
                for: window
            )
        }
        switch decision {
        case .save:
            return await saveProject()
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func presentPendingChangesAlert(
        for window: NSWindow
    ) async -> DocumentPendingChangesDecision {
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
                response in
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: .save)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: .discard)
                default:
                    continuation.resume(returning: .cancel)
                }
            }
        }
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
        [
            .copyComposite,
            .undoEditor,
            .redoEditor,
            .saveProject,
            .exportComposite,
            .flexibleSpace,
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .copyComposite,
            .undoEditor,
            .redoEditor,
            .flexibleSpace,
            .saveProject,
            .exportComposite,
        ]
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
            item.image = NSImage(
                systemSymbolName: "doc.on.doc",
                accessibilityDescription: item.label
            )
            item.target = self
            item.action = #selector(copyComposite(_:))
        case .undoEditor:
            item.label = "Undo"
            item.toolTip =
                "Undo the last annotation change (Command-Z)"
            item.image = NSImage(
                systemSymbolName: "arrow.uturn.backward",
                accessibilityDescription: item.label
            )
            item.target = self
            item.action = #selector(undoEditor(_:))
        case .redoEditor:
            item.label = "Redo"
            item.toolTip =
                "Redo the last annotation change (Command-Shift-Z)"
            item.image = NSImage(
                systemSymbolName: "arrow.uturn.forward",
                accessibilityDescription: item.label
            )
            item.target = self
            item.action = #selector(redoEditor(_:))
        case .saveProject:
            item.label = "Save Project"
            item.toolTip = "Save an editable MyShottr project (Command-S)"
            item.image = NSImage(
                systemSymbolName: "square.and.arrow.down",
                accessibilityDescription: item.label
            )
            item.target = self
            item.action = #selector(saveProjectAction(_:))
        case .exportComposite:
            item.label = "Export PNG"
            item.toolTip = "Export the annotated PNG (Command-E)"
            item.image = NSImage(
                systemSymbolName: "square.and.arrow.up",
                accessibilityDescription: item.label
            )
            item.target = self
            item.action = #selector(exportComposite(_:))
        default:
            return nil
        }
        return item
    }

    @objc func copyComposite(_ sender: Any?) -> Bool {
        guard commandWindowPredicate(window),
              beginOutput(.copy)
        else { return false }
        Task { @MainActor in
            defer { finishOutput() }
            do {
                let transfer = try await editorWebView.requestComposite()
                defer { transfer.discard() }
                try PNGClipboardWriter().write(data: transfer.data())
            } catch {
                present(
                    .wrapping(error, context: .clipboard)
                )
            }
        }
        return true
    }

    @objc func saveProjectAction(_ sender: Any?) -> Bool {
        guard commandWindowPredicate(window),
              beginOutput(.save)
        else { return false }
        Task { @MainActor in
            defer { finishOutput() }
            _ = await saveProject()
        }
        return true
    }

    @objc func exportComposite(_ sender: Any?) -> Bool {
        guard commandWindowPredicate(window),
              beginOutput(.export)
        else { return false }
        guard let destinationURL = choosePNGExportURL() else {
            finishOutput()
            return false
        }
        Task { @MainActor in
            defer { finishOutput() }
            do {
                let transfer = try await editorWebView.requestComposite(destinationDirectory: destinationURL.deletingLastPathComponent())
                defer { transfer.discard() }
                try transfer.move(to: destinationURL)
            } catch {
                present(
                    .wrapping(error, context: .pngExport)
                )
            }
        }
        return true
    }

    @objc func undoEditor(_ sender: Any?) -> Bool {
        guard commandWindowPredicate(window),
              validateHistoryAction(.undo)
        else { return false }
        historyActionSender(.undo)
        return true
    }

    @objc func redoEditor(_ sender: Any?) -> Bool {
        guard commandWindowPredicate(window),
              validateHistoryAction(.redo)
        else { return false }
        historyActionSender(.redo)
        return true
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .copyComposite, .saveProject, .exportComposite:
            editorIsReady && outputOperation == nil
        case .undoEditor:
            editorIsReady && historyState.canUndo
        case .redoEditor:
            editorIsReady && historyState.canRedo
        default:
            true
        }
    }

    func receiveHistoryState(_ state: EditorHistoryState) {
        historyState = state
        window?.toolbar?.validateVisibleItems()
    }

    func receiveBridgeFailure(_ error: EditorBridgeError) {
        present(.editorBridge(error))
    }

    private func validateHistoryAction(
        _ action: EditorHistoryAction
    ) -> Bool {
        guard editorIsReady else { return false }
        switch action {
        case .undo:
            return historyState.canUndo
        case .redo:
            return historyState.canRedo
        }
    }

    private func beginOutput(
        _ operation: OutputOperation
    ) -> Bool {
        guard editorIsReady,
              outputOperation == nil
        else { return false }
        outputOperation = operation
        window?.toolbar?.validateVisibleItems()
        return true
    }

    private func finishOutput() {
        outputOperation = nil
        window?.toolbar?.validateVisibleItems()
    }

    private func saveProject() async -> Bool {
        do {
            let modificationRevision =
                session.modificationRevision
            let annotationJSON: Data
            if let annotationSnapshotProvider {
                annotationJSON =
                    try await annotationSnapshotProvider()
            } else {
                annotationJSON =
                    try await editorWebView
                        .requestAnnotationSnapshot()
            }
            let project = try session.projectForSave(
                annotationJSON: annotationJSON
            )
            let url: URL
            if let projectURL {
                url = projectURL
            } else {
                let selectedURL: URL?
                if let projectSaveURLProvider {
                    selectedURL =
                        projectSaveURLProvider()
                } else {
                    selectedURL = chooseProjectSaveURL()
                }
                guard let selectedURL else {
                    return false
                }
                url = selectedURL
            }
            try projectStore.save(project, to: url)
            projectURL = url
            let completion = try session.completeSave(
                project,
                expectedModificationRevision:
                    modificationRevision
            )
            window?.title = url.deletingPathExtension().lastPathComponent
            if case .savedWithNewerChanges = completion {
                return false
            }
            return true
        } catch {
            present(
                .wrapping(error, context: .projectSave)
            )
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
    func present(_ error: MyShottrUserFacingError) -> Bool {
        errorPresenter.present(
            error,
            from: window
        )
        return true
    }
}

extension NSToolbarItem.Identifier {
    static let copyComposite = NSToolbarItem.Identifier("com.myshottr.copyComposite")
    static let undoEditor = NSToolbarItem.Identifier("com.myshottr.undoEditor")
    static let redoEditor = NSToolbarItem.Identifier("com.myshottr.redoEditor")
    static let saveProject = NSToolbarItem.Identifier("com.myshottr.saveProject")
    static let exportComposite = NSToolbarItem.Identifier("com.myshottr.exportComposite")
}

@MainActor
protocol EditorWindowControlling: AnyObject {
    var onClose: (() -> Void)? { get set }
    var representedDocumentID: UUID { get }
    var representedProjectURL: URL? { get }
    var hasModifiedDocument: Bool { get }
    var modificationRevision: UInt64 { get }
    func presentWindow() throws
    func waitForEditorLoad() async throws
    func discardFailedPresentation()
    func focusWindow()
    func resolvePendingChangesForTermination() async -> Bool
}

extension DocumentWindowController: EditorWindowControlling {
    var representedProjectURL: URL? {
        projectURL
    }

    var hasModifiedDocument: Bool {
        session.isModified
    }

    var modificationRevision: UInt64 {
        session.modificationRevision
    }

    func presentWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func waitForEditorLoad() async throws {
        try await editorLoadOperation?.wait()
        editorIsReady = true
        window?.toolbar?.validateVisibleItems()
    }

    func discardFailedPresentation() {
        editorWebView.tearDown()
        session.close()
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
    }
}
