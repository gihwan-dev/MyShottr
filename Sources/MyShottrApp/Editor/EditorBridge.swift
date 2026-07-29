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
                _ = try send(
                    requestID: requestID,
                    type: .requestComposite,
                    payload: .object(["requestId": .string(requestID.uuidString)])
                )
            } catch {
                snapshotContinuations.removeValue(forKey: requestID)?.resume(throwing: error)
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
            } else {
                lastError = .invalidMessage
            }
        case .compositeChunk, .compositeCompleted:
            break
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
        webView?.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('myshottr:native-message', { detail: \(json) }));"
        )
        return requestID
    }
}
