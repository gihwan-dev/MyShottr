import Foundation
import WebKit

enum EditorBridgeError: Error, Equatable {
    case editorNotReady
    case invalidMessage
    case invalidDocument
}

@MainActor
final class EditorBridge: NSObject, WKScriptMessageHandler {
    private let session: DocumentSession
    private weak var webView: WKWebView?
    private var editorIsReady = false
    private var pendingProject: MyShottrProject?
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
            try session.open(project: project)
            pendingProject = project
            if editorIsReady { try sendLoadDocument(project) }
        } catch {
            lastError = .invalidDocument
            throw EditorBridgeError.invalidDocument
        }
    }

    func requestAnnotationSnapshot() async throws -> Data {
        guard editorIsReady, let webView else { throw EditorBridgeError.editorNotReady }
        let requestID = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            snapshotContinuations[requestID] = continuation
            let script = "window.dispatchEvent(new CustomEvent('myshottr:request-annotation-snapshot', { detail: { requestId: '\(requestID.uuidString)' } }));"
            webView.evaluateJavaScript(script)
        }
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
            lastError = .invalidDocument
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
            try session.install(annotationJSON: data)
            snapshotContinuations.removeValue(forKey: message.requestId)?.resume(returning: data)
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
        try send(type: .loadDocument, payload: payload)
    }

    private func send(type: NativeToEditorMessageType, payload: BridgeJSONValue) throws {
        let envelope = try NativeToEditorEnvelope(type: type, payload: payload)
        outgoingMessageObserver?(envelope)
        guard let data = try? envelope.encodedData(),
              let json = String(data: data, encoding: .utf8)
        else {
            throw EditorBridgeError.invalidMessage
        }
        webView?.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('myshottr:native-message', { detail: \(json) }));"
        )
    }
}
