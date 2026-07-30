import Foundation
import WebKit

enum EditorBridgeError: Error, Equatable {
    case editorNotReady
    case invalidMessage
    case invalidDocument
    case cancelled
    case timedOut
}

@MainActor
final class EditorBridge: NSObject, WKScriptMessageHandler {
    private let session: DocumentSession
    private let preferences: any EditorPreferencesStoring
    private weak var webView: WKWebView?
    private var editorIsReady = false
    private var pendingProject: MyShottrProject?
    private var pendingLoadRequestID: UUID?
    private var snapshotContinuations: [UUID: CheckedContinuation<Data, Error>] = [:]
    private var compositeContinuations: [UUID: CheckedContinuation<CompositeTransfer, Error>] = [:]
    private var compositeTransfers: [UUID: CompositeTransfer] = [:]
    private var compositeDirectories: [UUID: URL] = [:]
    private var compositeDimensions: [UUID: (width: Int, height: Int)] = [:]
    private var requestDeadlineTasks: [UUID: Task<Void, Never>] = [:]
    private var retiredRequestIDs: Set<UUID> = []
    private let requestTimeout: Duration
    private let annotationSnapshotRequestObserver: ((UUID) throws -> Void)?
    private let javaScriptEvaluationObserver: ((UUID, @escaping (Error?) -> Void) -> Void)?
    private let outgoingMessageObserver: ((NativeToEditorEnvelope) -> Void)?
    private(set) var lastError: EditorBridgeError?

    init(
        session: DocumentSession,
        requestTimeout: Duration = .seconds(10),
        preferences: any EditorPreferencesStoring = UserDefaultsEditorPreferencesStore(),
        javaScriptEvaluationObserver: ((UUID, @escaping (Error?) -> Void) -> Void)? = nil,
        annotationSnapshotRequestObserver: ((UUID) throws -> Void)? = nil,
        outgoingMessageObserver: ((NativeToEditorEnvelope) -> Void)? = nil
    ) {
        self.session = session
        self.preferences = preferences
        self.requestTimeout = requestTimeout
        self.annotationSnapshotRequestObserver = annotationSnapshotRequestObserver
        self.javaScriptEvaluationObserver = javaScriptEvaluationObserver
        self.outgoingMessageObserver = outgoingMessageObserver
    }

    convenience init(
        session: DocumentSession,
        outgoingMessageObserver: @escaping (NativeToEditorEnvelope) -> Void
    ) {
        self.init(
            session: session,
            requestTimeout: .seconds(10),
            preferences: UserDefaultsEditorPreferencesStore(),
            javaScriptEvaluationObserver: nil,
            annotationSnapshotRequestObserver: nil,
            outgoingMessageObserver: outgoingMessageObserver
        )
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func load(project: MyShottrProject) throws {
        do {
            cancelPendingLoad()
            try session.stage(project: project)
            pendingProject = project
            if editorIsReady { try sendLoadDocument(project) }
        } catch {
            discardPendingLoad()
            lastError = .invalidDocument
            throw EditorBridgeError.invalidDocument
        }
    }

    func requestAnnotationSnapshot() async throws -> Data {
        guard editorIsReady,
              webView != nil || annotationSnapshotRequestObserver != nil || javaScriptEvaluationObserver != nil
        else { throw EditorBridgeError.editorNotReady }
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: EditorBridgeError.cancelled)
                    return
                }
                snapshotContinuations[requestID] = continuation
                scheduleDeadline(for: requestID, kind: .snapshot)
                do {
                    try dispatchAnnotationSnapshotRequest(requestID: requestID)
                } catch {
                    failSnapshotRequest(requestID, error: error)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failSnapshotRequest(requestID, error: EditorBridgeError.cancelled)
            }
        }
    }

    func requestComposite(destinationDirectory: URL? = nil) async throws -> CompositeTransfer {
        guard editorIsReady, webView != nil || outgoingMessageObserver != nil else { throw EditorBridgeError.editorNotReady }
        guard let project = session.project else { throw EditorBridgeError.invalidDocument }
        let requestID = UUID()
        if let destinationDirectory { compositeDirectories[requestID] = destinationDirectory }
        compositeDimensions[requestID] = (project.manifest.sourcePixelWidth, project.manifest.sourcePixelHeight)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    discardCompositeRequest(requestID)
                    continuation.resume(throwing: EditorBridgeError.cancelled)
                    return
                }
                compositeContinuations[requestID] = continuation
                scheduleDeadline(for: requestID, kind: .composite)
                do {
                    _ = try send(
                        requestID: requestID,
                        type: .requestComposite,
                        payload: .object(["requestId": .string(requestID.uuidString)])
                    )
                } catch {
                    failCompositeRequest(requestID, error: error, recordInvalidMessage: false)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.failCompositeRequest(
                    requestID,
                    error: EditorBridgeError.cancelled,
                    recordInvalidMessage: false
                )
            }
        }
    }

    func tearDown() {
        discardPendingLoad()
        editorIsReady = false
        for task in requestDeadlineTasks.values { task.cancel() }
        requestDeadlineTasks.removeAll()
        retiredRequestIDs.formUnion(snapshotContinuations.keys)
        for continuation in snapshotContinuations.values {
            continuation.resume(throwing: EditorBridgeError.cancelled)
        }
        snapshotContinuations.removeAll()
        retiredRequestIDs.formUnion(compositeContinuations.keys)
        for continuation in compositeContinuations.values {
            continuation.resume(throwing: EditorBridgeError.cancelled)
        }
        compositeContinuations.removeAll()
        for transfer in compositeTransfers.values { transfer.discard() }
        compositeTransfers.removeAll()
        compositeDirectories.removeAll()
        compositeDimensions.removeAll()
        webView = nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "myshottr",
              JSONSerialization.isValidJSONObject(message.body),
              let data = try? JSONSerialization.data(withJSONObject: message.body)
        else {
            lastError = .invalidMessage
            return
        }
        receive(data: data)
    }

    func receive(data: Data) {
        let message: EditorToNativeEnvelope
        do {
            message = try EditorToNativeEnvelope.decode(from: data)
        } catch {
            if let requestID = validatedRequestID(from: data) {
                failPendingRequest(requestID, error: EditorBridgeError.invalidMessage)
                return
            }
            lastError = .invalidMessage
            return
        }
        if retiredRequestIDs.contains(message.requestId) { return }
        if isCorrelatedReply(message.type) {
            guard let kind = pendingRequestKind(for: message.requestId) else { return }
            guard kind.accepts(message.type) else {
                failPendingRequest(message.requestId, error: EditorBridgeError.invalidMessage)
                return
            }
        }

        switch message.type {
        case .editorReady:
            editorIsReady = true
            if let pendingProject {
                do {
                    try sendLoadDocument(pendingProject)
                } catch {
                    discardPendingLoad()
                    lastError = .invalidDocument
                }
            }
        case .documentChanged:
            do {
                try session.markModified()
            } catch {
                lastError = .invalidDocument
            }
        case .editorPreferencesChanged:
            installPreferences(message)
        case .annotationSnapshot:
            installSnapshot(message)
        case .bridgeError:
            if message.requestId == pendingLoadRequestID {
                failLoadRequest(message.requestId, error: .invalidDocument)
            } else if snapshotContinuations[message.requestId] != nil {
                failSnapshotRequest(message.requestId, error: EditorBridgeError.invalidDocument)
            } else if compositeContinuations[message.requestId] != nil {
                failCompositeRequest(
                    message.requestId,
                    error: EditorBridgeError.invalidDocument,
                    recordInvalidMessage: false
                )
            } else {
                lastError = .invalidMessage
            }
        case .compositeChunk:
            installCompositeChunk(message)
        case .compositeCompleted:
            finishComposite(message)
        }
    }

    private func installPreferences(_ message: EditorToNativeEnvelope) {
        guard case let .object(payload) = message.payload,
              case let .string(tool)? = payload["tool"],
              case let .object(defaults)? = payload["defaults"],
              case let .string(color)? = defaults["color"],
              case let .number(strokeWidth)? = defaults["strokeWidth"],
              let strokeWidth = Int(exactly: strokeWidth),
              case let .number(textSize)? = defaults["textSize"],
              let textSize = Int(exactly: textSize),
              case let .number(roughness)? = defaults["roughness"],
              let roughness = Int(exactly: roughness),
              case let .number(opacity)? = defaults["opacity"]
        else {
            lastError = .invalidMessage
            return
        }
        do {
            try preferences.save(EditorPreferences(
                tool: tool,
                color: color,
                strokeWidth: strokeWidth,
                textSize: textSize,
                roughness: roughness,
                opacity: opacity
            ))
        } catch {
            lastError = .invalidMessage
        }
    }

    private func installSnapshot(_ message: EditorToNativeEnvelope) {
        guard case let .object(payload) = message.payload,
              case let .object(document)? = payload["document"]
        else {
            if snapshotContinuations[message.requestId] != nil {
                failSnapshotRequest(message.requestId, error: EditorBridgeError.invalidDocument)
            }
            lastError = .invalidDocument
            return
        }
        do {
            let data = try JSONEncoder().encode(BridgeJSONValue.object(document))
            if message.requestId == pendingLoadRequestID {
                try session.commitStaged(annotationJSON: data)
                cancelDeadline(for: message.requestId)
                retiredRequestIDs.insert(message.requestId)
                pendingProject = nil
                pendingLoadRequestID = nil
            } else if snapshotContinuations[message.requestId] != nil {
                try session.install(annotationJSON: data)
                completeSnapshotRequest(message.requestId, data: data)
            } else {
                lastError = .invalidMessage
            }
        } catch {
            if message.requestId == pendingLoadRequestID {
                failLoadRequest(message.requestId, error: .invalidDocument)
            } else {
                failSnapshotRequest(message.requestId, error: error)
            }
            lastError = .invalidDocument
        }
    }

    private func sendLoadDocument(_ project: MyShottrProject) throws {
        let annotationDocument = try JSONDecoder().decode(BridgeJSONValue.self, from: project.annotationJSON)
        let payload: BridgeJSONValue = .object([
            "documentId": .string(project.manifest.documentId.uuidString),
            "sourceImageURL": .string("myshottr-editor://editor/document/\(project.manifest.documentId.uuidString)/original.png"),
            "annotationDocument": annotationDocument,
            "initialTool": .string(preferences.load().tool),
        ])
        let requestID = try send(type: .loadDocument, payload: payload)
        pendingLoadRequestID = requestID
        scheduleDeadline(for: requestID, kind: .load)
    }

    private func dispatchAnnotationSnapshotRequest(requestID: UUID) throws {
        if let annotationSnapshotRequestObserver {
            try annotationSnapshotRequestObserver(requestID)
            return
        }
        if let javaScriptEvaluationObserver {
            javaScriptEvaluationObserver(requestID) { [weak self] error in
                guard let self, let error else { return }
                self.failPendingRequest(requestID, error: error)
            }
            return
        }
        guard let webView else { throw EditorBridgeError.editorNotReady }
        let payload = try JSONSerialization.data(withJSONObject: ["requestId": requestID.uuidString])
        guard let json = String(data: payload, encoding: .utf8) else { throw EditorBridgeError.invalidMessage }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('myshottr:request-annotation-snapshot', { detail: \(json) }));"
        ) { [weak self] _, error in
            guard let self, let error else { return }
            self.failSnapshotRequest(requestID, error: error)
        }
    }

    private func installCompositeChunk(_ message: EditorToNativeEnvelope) {
        guard compositeContinuations[message.requestId] != nil else {
            lastError = .invalidMessage
            return
        }
        guard
              case let .object(payload) = message.payload,
              case let .string(requestIDString)? = payload["requestId"],
              UUID(uuidString: requestIDString) == message.requestId,
              case let .number(indexNumber)? = payload["index"],
              let index = Int(exactly: indexNumber),
              case let .number(totalNumber)? = payload["total"],
              let total = Int(exactly: totalNumber),
              case let .string(base64)? = payload["dataBase64"]
        else {
            failCompositeRequest(message.requestId, error: EditorBridgeError.invalidMessage)
            return
        }
        do {
            let transfer: CompositeTransfer
            if let existing = compositeTransfers[message.requestId] {
                transfer = existing
            } else {
                transfer = try CompositeTransfer.begin(
                    requestId: message.requestId,
                    expectedChunks: total,
                    directory: compositeDirectories[message.requestId],
                    expectedPixelSize: compositeDimensions[message.requestId]
                )
                compositeTransfers[message.requestId] = transfer
            }
            try transfer.append(index: index, total: total, base64: base64)
        } catch {
            failCompositeRequest(message.requestId, error: error)
        }
    }

    private func finishComposite(_ message: EditorToNativeEnvelope) {
        guard compositeContinuations[message.requestId] != nil else {
            lastError = .invalidMessage
            return
        }
        guard case let .object(payload) = message.payload,
              case let .string(requestIDString)? = payload["requestId"],
              UUID(uuidString: requestIDString) == message.requestId,
              let transfer = compositeTransfers[message.requestId]
        else {
            failCompositeRequest(message.requestId, error: EditorBridgeError.invalidMessage)
            return
        }
        do {
            _ = try transfer.finish()
            compositeTransfers.removeValue(forKey: message.requestId)
            compositeDirectories.removeValue(forKey: message.requestId)
            compositeDimensions.removeValue(forKey: message.requestId)
            cancelDeadline(for: message.requestId)
            retiredRequestIDs.insert(message.requestId)
            compositeContinuations.removeValue(forKey: message.requestId)?.resume(returning: transfer)
        } catch {
            failCompositeRequest(message.requestId, error: error)
        }
    }

    private func discardPendingLoad() {
        if let pendingLoadRequestID {
            cancelDeadline(for: pendingLoadRequestID)
            retiredRequestIDs.insert(pendingLoadRequestID)
        }
        session.discardStaged()
        pendingProject = nil
        pendingLoadRequestID = nil
    }

    private func cancelPendingLoad() {
        guard pendingLoadRequestID != nil || pendingProject != nil else { return }
        discardPendingLoad()
    }

    @discardableResult
    private func send(requestID: UUID = UUID(), type: NativeToEditorMessageType, payload: BridgeJSONValue) throws -> UUID {
        let envelope = try NativeToEditorEnvelope(requestId: requestID, type: type, payload: payload)
        outgoingMessageObserver?(envelope)
        guard let data = try? envelope.encodedData(),
              let json = String(data: data, encoding: .utf8)
        else {
            throw EditorBridgeError.invalidMessage
        }
        if webView == nil, outgoingMessageObserver == nil, javaScriptEvaluationObserver == nil {
            throw EditorBridgeError.editorNotReady
        }
        if let javaScriptEvaluationObserver {
            javaScriptEvaluationObserver(requestID) { [weak self] error in
                guard let self, let error else { return }
                self.failPendingRequest(requestID, error: error)
            }
            return requestID
        }
        webView?.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('myshottr:native-message', { detail: \(json) }));"
        ) { [weak self] _, error in
            guard let self, let error else { return }
            self.failPendingRequest(requestID, error: error)
        }
        return requestID
    }

    private func failPendingRequest(_ requestID: UUID, error: Error) {
        if retiredRequestIDs.contains(requestID) { return }
        if requestID == pendingLoadRequestID {
            failLoadRequest(
                requestID,
                error: (error as? EditorBridgeError) ?? .invalidDocument
            )
        } else if snapshotContinuations[requestID] != nil {
            failSnapshotRequest(requestID, error: error)
        } else if compositeContinuations[requestID] != nil {
            failCompositeRequest(
                requestID,
                error: error,
                recordInvalidMessage: (error as? EditorBridgeError) == .invalidMessage
            )
        }
    }

    private func completeSnapshotRequest(_ requestID: UUID, data: Data) {
        guard let continuation = snapshotContinuations.removeValue(forKey: requestID) else { return }
        cancelDeadline(for: requestID)
        retiredRequestIDs.insert(requestID)
        continuation.resume(returning: data)
    }

    private func failSnapshotRequest(_ requestID: UUID, error: Error) {
        guard let continuation = snapshotContinuations.removeValue(forKey: requestID) else { return }
        cancelDeadline(for: requestID)
        retiredRequestIDs.insert(requestID)
        continuation.resume(throwing: error)
    }

    private func failLoadRequest(_ requestID: UUID, error: EditorBridgeError) {
        guard requestID == pendingLoadRequestID else { return }
        discardPendingLoad()
        lastError = error
    }

    private func failCompositeRequest(
        _ requestID: UUID,
        error: Error,
        recordInvalidMessage: Bool = true
    ) {
        guard let continuation = compositeContinuations.removeValue(forKey: requestID) else {
            if recordInvalidMessage { lastError = .invalidMessage }
            return
        }
        cancelDeadline(for: requestID)
        retiredRequestIDs.insert(requestID)
        discardCompositeRequest(requestID)
        continuation.resume(throwing: error)
        if recordInvalidMessage { lastError = .invalidMessage }
    }

    private func discardCompositeRequest(_ requestID: UUID) {
        compositeTransfers.removeValue(forKey: requestID)?.discard()
        compositeDirectories.removeValue(forKey: requestID)
        compositeDimensions.removeValue(forKey: requestID)
    }

    private enum PendingRequestKind {
        case load
        case snapshot
        case composite

        func accepts(_ type: EditorToNativeMessageType) -> Bool {
            switch self {
            case .load, .snapshot:
                type == .annotationSnapshot || type == .bridgeError
            case .composite:
                type == .compositeChunk || type == .compositeCompleted || type == .bridgeError
            }
        }
    }

    private func pendingRequestKind(for requestID: UUID) -> PendingRequestKind? {
        if requestID == pendingLoadRequestID { return .load }
        if snapshotContinuations[requestID] != nil { return .snapshot }
        if compositeContinuations[requestID] != nil { return .composite }
        return nil
    }

    private func isCorrelatedReply(_ type: EditorToNativeMessageType) -> Bool {
        switch type {
        case .annotationSnapshot, .compositeChunk, .compositeCompleted, .bridgeError:
            true
        case .editorReady, .documentChanged, .editorPreferencesChanged:
            false
        }
    }

    private func scheduleDeadline(for requestID: UUID, kind: PendingRequestKind) {
        let timeout = requestTimeout
        requestDeadlineTasks[requestID] = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: timeout)
            } catch {
                return
            }
            guard let self else { return }
            switch kind {
            case .load:
                self.failLoadRequest(requestID, error: .timedOut)
            case .snapshot:
                self.failSnapshotRequest(requestID, error: EditorBridgeError.timedOut)
            case .composite:
                self.failCompositeRequest(
                    requestID,
                    error: EditorBridgeError.timedOut,
                    recordInvalidMessage: false
                )
            }
        }
    }

    private func cancelDeadline(for requestID: UUID) {
        requestDeadlineTasks.removeValue(forKey: requestID)?.cancel()
    }

    private func validatedRequestID(from data: Data) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == ["protocolVersion", "requestId", "type", "payload"],
              object["protocolVersion"] as? Int == EditorBridgeEnvelope<EditorToNativeMessageType, BridgeJSONValue>.protocolVersion,
              let requestIDString = object["requestId"] as? String,
              let requestID = UUID(uuidString: requestIDString)
        else {
            return nil
        }
        return requestID
    }
}
