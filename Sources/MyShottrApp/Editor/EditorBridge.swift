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
    private let requestTimeout: Duration
    private let annotationSnapshotRequestObserver: ((UUID) throws -> Void)?
    private let outgoingMessageObserver: ((NativeToEditorEnvelope) -> Void)?
    private(set) var lastError: EditorBridgeError?

    init(
        session: DocumentSession,
        requestTimeout: Duration = .seconds(10),
        annotationSnapshotRequestObserver: ((UUID) throws -> Void)? = nil,
        outgoingMessageObserver: ((NativeToEditorEnvelope) -> Void)? = nil
    ) {
        self.session = session
        self.requestTimeout = requestTimeout
        self.annotationSnapshotRequestObserver = annotationSnapshotRequestObserver
        self.outgoingMessageObserver = outgoingMessageObserver
    }

    convenience init(
        session: DocumentSession,
        outgoingMessageObserver: @escaping (NativeToEditorEnvelope) -> Void
    ) {
        self.init(
            session: session,
            requestTimeout: .seconds(10),
            annotationSnapshotRequestObserver: nil,
            outgoingMessageObserver: outgoingMessageObserver
        )
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func load(project: MyShottrProject) throws {
        do {
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
        guard editorIsReady, webView != nil || annotationSnapshotRequestObserver != nil else { throw EditorBridgeError.editorNotReady }
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
        session.discardStaged()
        pendingProject = nil
        pendingLoadRequestID = nil
        editorIsReady = false
        for task in requestDeadlineTasks.values { task.cancel() }
        requestDeadlineTasks.removeAll()
        for continuation in snapshotContinuations.values {
            continuation.resume(throwing: EditorBridgeError.cancelled)
        }
        snapshotContinuations.removeAll()
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
            if let requestID = correlatedRequestID(from: data, type: .annotationSnapshot) {
                failSnapshotRequest(requestID, error: EditorBridgeError.invalidMessage)
                return
            }
            if let requestID = correlatedCompositeRequestID(from: data) {
                failCompositeRequest(requestID, error: EditorBridgeError.invalidMessage)
                return
            }
            lastError = .invalidMessage
            return
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
        case .annotationSnapshot:
            installSnapshot(message)
        case .bridgeError:
            if message.requestId == pendingLoadRequestID {
                session.discardStaged()
                pendingProject = nil
                pendingLoadRequestID = nil
                lastError = .invalidDocument
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
                pendingProject = nil
                pendingLoadRequestID = nil
            } else if snapshotContinuations[message.requestId] != nil {
                try session.install(annotationJSON: data)
                completeSnapshotRequest(message.requestId, data: data)
            } else {
                lastError = .invalidMessage
            }
        } catch {
            failSnapshotRequest(message.requestId, error: error)
            lastError = .invalidDocument
        }
    }

    private func sendLoadDocument(_ project: MyShottrProject) throws {
        let annotationDocument = try JSONDecoder().decode(BridgeJSONValue.self, from: project.annotationJSON)
        let payload: BridgeJSONValue = .object([
            "documentId": .string(project.manifest.documentId.uuidString),
            "sourceImageURL": .string("myshottr-editor://editor/document/\(project.manifest.documentId.uuidString)/original.png"),
            "annotationDocument": annotationDocument,
        ])
        let requestID = try send(type: .loadDocument, payload: payload)
        pendingLoadRequestID = requestID
    }

    private func dispatchAnnotationSnapshotRequest(requestID: UUID) throws {
        if let annotationSnapshotRequestObserver {
            try annotationSnapshotRequestObserver(requestID)
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
            compositeContinuations.removeValue(forKey: message.requestId)?.resume(returning: transfer)
        } catch {
            failCompositeRequest(message.requestId, error: error)
        }
    }

    private func discardPendingLoad() {
        session.discardStaged()
        pendingProject = nil
        pendingLoadRequestID = nil
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
        if webView == nil, outgoingMessageObserver == nil { throw EditorBridgeError.editorNotReady }
        webView?.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('myshottr:native-message', { detail: \(json) }));"
        ) { [weak self] _, error in
            guard let self, let error else { return }
            self.failPendingRequest(requestID, error: error)
        }
        return requestID
    }

    private func failPendingRequest(_ requestID: UUID, error: Error) {
        if requestID == pendingLoadRequestID {
            discardPendingLoad()
            lastError = .invalidDocument
        } else if snapshotContinuations[requestID] != nil {
            failSnapshotRequest(requestID, error: error)
        } else if compositeContinuations[requestID] != nil {
            failCompositeRequest(requestID, error: error, recordInvalidMessage: false)
        } else {
            lastError = .invalidMessage
        }
    }

    private func completeSnapshotRequest(_ requestID: UUID, data: Data) {
        guard let continuation = snapshotContinuations.removeValue(forKey: requestID) else { return }
        cancelDeadline(for: requestID)
        continuation.resume(returning: data)
    }

    private func failSnapshotRequest(_ requestID: UUID, error: Error) {
        guard let continuation = snapshotContinuations.removeValue(forKey: requestID) else { return }
        cancelDeadline(for: requestID)
        continuation.resume(throwing: error)
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
        case snapshot
        case composite
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

    private func correlatedRequestID(from data: Data, type expectedType: EditorToNativeMessageType) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["protocolVersion"] as? Int == EditorBridgeEnvelope<EditorToNativeMessageType, BridgeJSONValue>.protocolVersion,
              let requestIDString = object["requestId"] as? String,
              let requestID = UUID(uuidString: requestIDString),
              object["type"] as? String == expectedType.rawValue
        else {
            return nil
        }
        return requestID
    }

    private func correlatedCompositeRequestID(from data: Data) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["protocolVersion"] as? Int == EditorBridgeEnvelope<EditorToNativeMessageType, BridgeJSONValue>.protocolVersion,
              let requestIDString = object["requestId"] as? String,
              let requestID = UUID(uuidString: requestIDString),
              let type = object["type"] as? String,
              type == EditorToNativeMessageType.compositeChunk.rawValue || type == EditorToNativeMessageType.compositeCompleted.rawValue
        else {
            return nil
        }
        return requestID
    }
}
