import Foundation
import WebKit

enum EditorBridgeError: Error, Equatable {
    case editorNotReady
    case invalidMessage
    case invalidDocument
    case cancelled
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
    private let outgoingMessageObserver: ((NativeToEditorEnvelope) -> Void)?
    private(set) var lastError: EditorBridgeError?

    init(session: DocumentSession, outgoingMessageObserver: ((NativeToEditorEnvelope) -> Void)? = nil) {
        self.session = session
        self.outgoingMessageObserver = outgoingMessageObserver
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
        guard editorIsReady, webView != nil || outgoingMessageObserver != nil else { throw EditorBridgeError.editorNotReady }
        let requestID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            snapshotContinuations[requestID] = continuation
            do {
                try dispatchAnnotationSnapshotRequest(requestID: requestID)
            } catch {
                snapshotContinuations.removeValue(forKey: requestID)?.resume(throwing: error)
            }
        }
    }

    func requestComposite(destinationDirectory: URL? = nil) async throws -> CompositeTransfer {
        guard editorIsReady, webView != nil || outgoingMessageObserver != nil else { throw EditorBridgeError.editorNotReady }
        guard let project = session.project else { throw EditorBridgeError.invalidDocument }
        let requestID = UUID()
        if let destinationDirectory { compositeDirectories[requestID] = destinationDirectory }
        compositeDimensions[requestID] = (project.manifest.sourcePixelWidth, project.manifest.sourcePixelHeight)
        return try await withCheckedThrowingContinuation { continuation in
            compositeContinuations[requestID] = continuation
            do {
                _ = try send(
                    requestID: requestID,
                    type: .requestComposite,
                    payload: .object(["requestId": .string(requestID.uuidString)])
                )
            } catch {
                compositeDirectories.removeValue(forKey: requestID)
                compositeDimensions.removeValue(forKey: requestID)
                compositeContinuations.removeValue(forKey: requestID)?.resume(throwing: error)
            }
        }
    }

    func tearDown() {
        session.discardStaged()
        pendingProject = nil
        pendingLoadRequestID = nil
        editorIsReady = false
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
            } else if let continuation = snapshotContinuations.removeValue(forKey: message.requestId) {
                continuation.resume(throwing: EditorBridgeError.invalidDocument)
            } else if let continuation = compositeContinuations.removeValue(forKey: message.requestId) {
                compositeTransfers.removeValue(forKey: message.requestId)?.discard()
                compositeDirectories.removeValue(forKey: message.requestId)
                compositeDimensions.removeValue(forKey: message.requestId)
                continuation.resume(throwing: EditorBridgeError.invalidDocument)
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
            lastError = .invalidDocument
            return
        }
        do {
            let data = try JSONEncoder().encode(BridgeJSONValue.object(document))
            if message.requestId == pendingLoadRequestID {
                try session.commitStaged(annotationJSON: data)
                pendingProject = nil
                pendingLoadRequestID = nil
            } else if let continuation = snapshotContinuations.removeValue(forKey: message.requestId) {
                try session.install(annotationJSON: data)
                continuation.resume(returning: data)
            } else {
                lastError = .invalidMessage
            }
        } catch {
            snapshotContinuations.removeValue(forKey: message.requestId)?.resume(throwing: error)
            lastError = .invalidDocument
        }
    }

    private func sendLoadDocument(_ project: MyShottrProject) throws {
        let annotationDocument = try JSONDecoder().decode(BridgeJSONValue.self, from: project.annotationJSON)
        let payload: BridgeJSONValue = .object([
            "documentId": .string(project.manifest.documentId.uuidString),
            "sourceImageURL": .string("myshottr-resource://document/\(project.manifest.documentId.uuidString)/original.png"),
            "annotationDocument": annotationDocument,
        ])
        let requestID = try send(type: .loadDocument, payload: payload)
        pendingLoadRequestID = requestID
    }

    private func dispatchAnnotationSnapshotRequest(requestID: UUID) throws {
        guard let webView else { throw EditorBridgeError.editorNotReady }
        let payload = try JSONSerialization.data(withJSONObject: ["requestId": requestID.uuidString])
        guard let json = String(data: payload, encoding: .utf8) else { throw EditorBridgeError.invalidMessage }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('myshottr:request-annotation-snapshot', { detail: \(json) }));"
        ) { [weak self] _, error in
            guard let self, let error else { return }
            self.snapshotContinuations.removeValue(forKey: requestID)?.resume(throwing: error)
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
        } else if let continuation = snapshotContinuations.removeValue(forKey: requestID) {
            continuation.resume(throwing: error)
        } else if let continuation = compositeContinuations.removeValue(forKey: requestID) {
            compositeTransfers.removeValue(forKey: requestID)?.discard()
            compositeDirectories.removeValue(forKey: requestID)
            compositeDimensions.removeValue(forKey: requestID)
            continuation.resume(throwing: error)
        } else {
            lastError = .invalidMessage
        }
    }

    private func failCompositeRequest(_ requestID: UUID, error: Error) {
        guard let continuation = compositeContinuations.removeValue(forKey: requestID) else {
            lastError = .invalidMessage
            return
        }
        compositeTransfers.removeValue(forKey: requestID)?.discard()
        compositeDirectories.removeValue(forKey: requestID)
        compositeDimensions.removeValue(forKey: requestID)
        continuation.resume(throwing: error)
        lastError = .invalidMessage
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
