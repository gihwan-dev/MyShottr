import Foundation
import WebKit

final class EditorBundleSchemeHandler: NSObject, WKURLSchemeHandler {
    private enum Resource {
        case bundledFile(url: URL, mimeType: String)
        case documentPNG(UUID)
    }

    private struct LookupRegistration: Equatable, Sendable {
        let token = UUID()
    }

    private struct LookupEntry {
        let registration: LookupRegistration
        var task: Task<Void, Never>?
    }

    private final class LookupRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [ObjectIdentifier: LookupEntry] = [:]

        func register(_ taskID: ObjectIdentifier) -> LookupRegistration {
            let registration = LookupRegistration()
            lock.lock()
            entries[taskID] = LookupEntry(registration: registration)
            lock.unlock()
            return registration
        }

        func isRegistered(_ taskID: ObjectIdentifier, registration: LookupRegistration) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return entries[taskID]?.registration == registration
        }

        func attach(_ task: Task<Void, Never>, to taskID: ObjectIdentifier, registration: LookupRegistration) {
            lock.lock()
            let shouldCancel = entries[taskID]?.registration != registration
            if !shouldCancel {
                entries[taskID]?.task = task
            }
            lock.unlock()
            if shouldCancel { task.cancel() }
        }

        func stop(_ taskID: ObjectIdentifier) {
            lock.lock()
            let task = entries.removeValue(forKey: taskID)?.task
            lock.unlock()
            task?.cancel()
        }

        @MainActor
        func deliver(
            _ taskID: ObjectIdentifier,
            registration: LookupRegistration,
            deliveryBarrier: (@Sendable () -> Void)?,
            callback: @MainActor () -> Void
        ) {
            lock.lock()
            defer { lock.unlock() }
            guard entries[taskID]?.registration == registration else { return }
            entries.removeValue(forKey: taskID)
            deliveryBarrier?()
            callback()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return entries.count
        }
    }

    private final class SchemeTaskCallbacks: @unchecked Sendable {
        let identity: ObjectIdentifier
        private let task: WKURLSchemeTask

        init(_ task: WKURLSchemeTask) {
            identity = ObjectIdentifier(task as AnyObject)
            self.task = task
        }

        @MainActor
        func reject() {
            task.didFailWithError(NSError(domain: "MyShottr.EditorBundle", code: 1))
        }

        @MainActor
        func finish(data: Data, responseURL: URL, mimeType: String) {
            task.didReceive(URLResponse(
                url: responseURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            ))
            task.didReceive(data)
            task.didFinish()
        }
    }

    private let rootURL: URL
    private let referencedAssets: [String: String]
    private let pngForDocument: @MainActor @Sendable (UUID) -> Data?
    private let deliveryBarrier: (@Sendable () -> Void)?
    private let taskAttachmentBarrier: (@Sendable () -> Void)?
    private let deliveryAttemptDidReturn: (@Sendable () -> Void)?
    private let lookupTaskDidReturn: (@Sendable () -> Void)?
    private let lookupRegistry = LookupRegistry()

    init(
        rootURL: URL,
        pngForDocument: @escaping @MainActor @Sendable (UUID) -> Data?,
        deliveryBarrier: (@Sendable () -> Void)? = nil,
        taskAttachmentBarrier: (@Sendable () -> Void)? = nil,
        deliveryAttemptDidReturn: (@Sendable () -> Void)? = nil,
        lookupTaskDidReturn: (@Sendable () -> Void)? = nil
    ) {
        self.rootURL = rootURL.standardizedFileURL
        self.referencedAssets = Self.referencedAssets(in: rootURL.standardizedFileURL)
        self.pngForDocument = pngForDocument
        self.deliveryBarrier = deliveryBarrier
        self.taskAttachmentBarrier = taskAttachmentBarrier
        self.deliveryAttemptDidReturn = deliveryAttemptDidReturn
        self.lookupTaskDidReturn = lookupTaskDidReturn
    }

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let callbacks = SchemeTaskCallbacks(urlSchemeTask)
        let taskID = callbacks.identity
        let registration = lookupRegistry.register(taskID)
        guard let requestURL = urlSchemeTask.request.url,
              urlSchemeTask.request.httpMethod == "GET",
              requestURL.scheme == "myshottr-editor",
              requestURL.host == "editor",
              requestURL.port == nil,
              requestURL.user == nil,
              requestURL.password == nil,
              requestURL.query == nil,
              requestURL.fragment == nil,
              let resource = resource(for: requestURL)
        else {
            let rejectionTask = Task { @MainActor [lookupRegistry, deliveryBarrier, lookupTaskDidReturn] in
                defer { lookupTaskDidReturn?() }
                guard lookupRegistry.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
                lookupRegistry.deliver(taskID, registration: registration, deliveryBarrier: deliveryBarrier) {
                    callbacks.reject()
                }
            }
            taskAttachmentBarrier?()
            lookupRegistry.attach(rejectionTask, to: taskID, registration: registration)
            return
        }

        let lookupTask = Task { @MainActor [
            pngForDocument,
            lookupRegistry,
            deliveryBarrier,
            deliveryAttemptDidReturn,
            lookupTaskDidReturn
        ] in
            defer { deliveryAttemptDidReturn?() }
            defer { lookupTaskDidReturn?() }
            guard lookupRegistry.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
            let data: Data
            let mimeType: String
            switch resource {
            case let .bundledFile(url, bundledMimeType):
                guard let bundledData = try? Data(contentsOf: url) else {
                    lookupRegistry.deliver(taskID, registration: registration, deliveryBarrier: deliveryBarrier) {
                        callbacks.reject()
                    }
                    return
                }
                data = bundledData
                mimeType = bundledMimeType
            case let .documentPNG(documentID):
                guard let png = pngForDocument(documentID) else {
                    lookupRegistry.deliver(taskID, registration: registration, deliveryBarrier: deliveryBarrier) {
                        callbacks.reject()
                    }
                    return
                }
                data = png
                mimeType = "image/png"
            }
            guard lookupRegistry.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
            lookupRegistry.deliver(taskID, registration: registration, deliveryBarrier: deliveryBarrier) {
                callbacks.finish(data: data, responseURL: requestURL, mimeType: mimeType)
            }
        }
        taskAttachmentBarrier?()
        lookupRegistry.attach(lookupTask, to: taskID, registration: registration)
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lookupRegistry.stop(ObjectIdentifier(urlSchemeTask as AnyObject))
    }

    nonisolated var pendingLookupCount: Int {
        lookupRegistry.count
    }

    private nonisolated func resource(for requestURL: URL) -> Resource? {
        guard let encodedPath = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.percentEncodedPath else { return nil }
        if encodedPath == "/index.html" {
            return .bundledFile(
                url: rootURL.appendingPathComponent("index.html"),
                mimeType: "text/html"
            )
        }
        if let documentID = documentID(in: requestURL),
           encodedPath == "/document/\(documentID.uuidString)/original.png" {
            return .documentPNG(documentID)
        }
        guard encodedPath.hasPrefix("/assets/"),
              let filename = String(encodedPath.dropFirst("/assets/".count)).removingPercentEncoding,
              let mimeType = referencedAssets[filename]
        else {
            return nil
        }
        let fileURL = rootURL.appendingPathComponent("assets", isDirectory: true).appendingPathComponent(filename).standardizedFileURL
        guard fileURL.path.hasPrefix(rootURL.path + "/") else { return nil }
        return .bundledFile(url: fileURL, mimeType: mimeType)
    }

    private nonisolated func documentID(in url: URL) -> UUID? {
        let components = url.pathComponents
        guard components.count == 4,
              components[0] == "/",
              components[1] == "document",
              components[3] == "original.png"
        else {
            return nil
        }
        return UUID(uuidString: components[2])
    }

    private static func referencedAssets(in rootURL: URL) -> [String: String] {
        guard let index = try? String(contentsOf: rootURL.appendingPathComponent("index.html"), encoding: .utf8) else { return [:] }
        let pattern = #"\./assets/(index-[A-Za-z0-9_-]+\.(js|css))"#
        let range = NSRange(index.startIndex..., in: index)
        return (try? NSRegularExpression(pattern: pattern))?.matches(in: index, range: range).reduce(into: [:]) { assets, match in
            guard let filenameRange = Range(match.range(at: 1), in: index) else { return }
            let filename = String(index[filenameRange])
            assets[filename] = filename.hasSuffix(".js") ? "application/javascript" : "text/css"
        } ?? [:]
    }
}
