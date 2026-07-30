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
final class RecoveryCleanupRetryCoordinator {
    private let operation: RecoveryCleanupOperation
    private let presenter: any UserFacingErrorPresenting
    private weak var window: NSWindow?

    init(
        operation: RecoveryCleanupOperation,
        presenter: any UserFacingErrorPresenting,
        window: NSWindow?
    ) {
        self.operation = operation
        self.presenter = presenter
        self.window = window
    }

    func present() {
        presenter.present(
            .recoveryCleanupAfterSave,
            from: window,
            retry: {
                [self] in
                retry()
            }
        )
    }

    private func retry() {
        do {
            try operation.perform()
        } catch {
            present()
        }
    }
}

@MainActor
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private let session: DocumentSession
    private let editorWebView: EditorWebView
    private let editorLoadOperation: EditorLoadOperation?
    private let projectStore: any ProjectPackageStoring
    private let errorPresenter: any UserFacingErrorPresenting
    let representedDocumentID: UUID
    private var projectURL: URL?
    private var closeAfterPrompt = false
    private var discardRecoveryOnApprovedTermination = false
    private let annotationSnapshotProvider:
        (@MainActor () async throws -> Data)?
    private let pendingChangesDecisionProvider:
        (@MainActor () async -> DocumentPendingChangesDecision)?
    private let closeWindow: (@MainActor () -> Void)?
    private let terminationResolutionGate =
        DocumentTerminationResolutionGate()
    var onClose: (() -> Void)?

    init(
        project: MyShottrProject,
        projectURL: URL?,
        projectStore: any ProjectPackageStoring = ProjectPackageStore(),
        preferences: any EditorPreferencesStoring =
            UserDefaultsEditorPreferencesStore(),
        recoveryStore: (any RecoveryStoring)? = nil,
        isRecoveredDocument: Bool = false,
        errorPresenter: any UserFacingErrorPresenting =
            UserFacingErrorPresenter.shared,
        testSession: DocumentSession? = nil,
        annotationSnapshotProvider:
            (@MainActor () async throws -> Data)? = nil,
        pendingChangesDecisionProvider:
            (@MainActor () async -> DocumentPendingChangesDecision)? =
                nil,
        closeWindow: (@MainActor () -> Void)? = nil
    ) throws {
        let session: DocumentSession
        if let testSession {
            session = testSession
        } else {
            let resolvedRecoveryStore: any RecoveryStoring
            if let recoveryStore {
                resolvedRecoveryStore = recoveryStore
            } else {
                resolvedRecoveryStore = try RecoveryStore()
            }
            session = DocumentSession(
                recoveryStore: resolvedRecoveryStore
            )
        }
        let editorWebView = EditorWebView(
            session: session,
            preferences: preferences
        )
        let editorLoadOperation: EditorLoadOperation?
        if testSession == nil {
            if isRecoveredDocument {
                session.prepareForRecoveryRestore()
            } else if projectURL == nil {
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
        self.projectStore = projectStore
        self.errorPresenter = errorPresenter
        self.annotationSnapshotProvider =
            annotationSnapshotProvider
        self.pendingChangesDecisionProvider =
            pendingChangesDecisionProvider
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
            self?.present(
                .wrapping(error, context: .recovery)
            )
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
            self?.present(
                .wrapping(error, context: .editorBridge)
            )
        }
        editorWebView.onBridgeFailure = {
            [weak self] error in
            self?.present(.editorBridge(error))
        }
        editorWebView.onProtocolFailure = {
            [weak self] error in
            self?.present(.editorProtocol(error))
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
                do {
                    try finalizePendingTermination()
                    closeAfterPrompt = true
                    if let closeWindow {
                        closeWindow()
                    } else {
                        window?.performClose(nil)
                    }
                } catch {
                    present(
                        .wrapping(error, context: .recovery)
                    )
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
        discardRecoveryOnApprovedTermination = false
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
            discardRecoveryOnApprovedTermination = true
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

    func finalizePendingTermination() throws {
        guard discardRecoveryOnApprovedTermination else {
            return
        }
        try session.discardRecovery()
        discardRecoveryOnApprovedTermination = false
    }

    func completePendingTerminationAfterDiscardStaged() {
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
                present(
                    .wrapping(error, context: .clipboard)
                )
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
                present(
                    .wrapping(error, context: .pngExport)
                )
            }
        }
        return true
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
                guard let selectedURL = chooseProjectSaveURL() else { return false }
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
            if case let .savedRecoveryCleanupPending(
                cleanupOperation
            ) = completion {
                RecoveryCleanupRetryCoordinator(
                    operation: cleanupOperation,
                    presenter: errorPresenter,
                    window: window
                ).present()
            }
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
    var modificationRevision: UInt64 { get }
    var pendingTerminationDiscardDocumentID: UUID? { get }
    func presentWindow() throws
    func waitForEditorLoad() async throws
    func discardFailedPresentation()
    func focusWindow()
    func flushRecoveryForTermination() async throws
    func resolvePendingChangesForTermination() async -> Bool
    func completePendingTerminationAfterDiscardStaged()
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

    var pendingTerminationDiscardDocumentID: UUID? {
        discardRecoveryOnApprovedTermination
            ? representedDocumentID
            : nil
    }

    func presentWindow() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func waitForEditorLoad() async throws {
        try await editorLoadOperation?.wait()
    }

    func discardFailedPresentation() {
        editorWebView.tearDown()
        session.close()
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
    }
}
