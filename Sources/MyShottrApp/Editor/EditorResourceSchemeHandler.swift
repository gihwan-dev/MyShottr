import Foundation
import WebKit

final class EditorResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct LookupRegistration: Equatable, Sendable {
        let token = UUID()
    }

    private struct LookupEntry {
        let registration: LookupRegistration
        var task: Task<Void, Never>?
    }

    // Every access to entries is lock-protected. Entries contain only a Sendable
    // registration token and the Task handle used for cancellation.
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

        func attach(
            _ task: Task<Void, Never>,
            to taskID: ObjectIdentifier,
            registration: LookupRegistration
        ) {
            lock.lock()
            let shouldCancel = entries[taskID]?.registration != registration
            if !shouldCancel {
                entries[taskID]?.task = task
            }
            lock.unlock()
            if shouldCancel {
                task.cancel()
            }
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

    // WebKit does not declare WKURLSchemeTask Sendable. The wrapped value is
    // never exposed: its terminal callback methods are mechanically confined
    // to MainActor, while the registry shares only identity tokens and Task
    // cancellation state with other executors.
    private final class SchemeTaskCallbacks: @unchecked Sendable {
        let identity: ObjectIdentifier
        private let task: WKURLSchemeTask

        init(_ task: WKURLSchemeTask) {
            identity = ObjectIdentifier(task as AnyObject)
            self.task = task
        }

        @MainActor
        func reject() {
            task.didFailWithError(NSError(domain: "MyShottr.EditorResourceScheme", code: 1))
        }

        @MainActor
        func finish(with png: Data, responseURL: URL) {
            let response = URLResponse(
                url: responseURL,
                mimeType: "image/png",
                expectedContentLength: png.count,
                textEncodingName: nil
            )
            task.didReceive(response)
            task.didReceive(png)
            task.didFinish()
        }
    }

    private let pngForDocument: @MainActor @Sendable (UUID) -> Data?
    private let deliveryBarrier: (@Sendable () -> Void)?
    private let taskAttachmentBarrier: (@Sendable () -> Void)?
    private let deliveryAttemptDidReturn: (@Sendable () -> Void)?
    private let lookupTaskDidReturn: (@Sendable () -> Void)?
    private let lookupRegistry = LookupRegistry()

    init(
        pngForDocument: @escaping @MainActor @Sendable (UUID) -> Data?,
        deliveryBarrier: (@Sendable () -> Void)? = nil,
        taskAttachmentBarrier: (@Sendable () -> Void)? = nil,
        deliveryAttemptDidReturn: (@Sendable () -> Void)? = nil,
        lookupTaskDidReturn: (@Sendable () -> Void)? = nil
    ) {
        self.pngForDocument = pngForDocument
        self.deliveryBarrier = deliveryBarrier
        self.taskAttachmentBarrier = taskAttachmentBarrier
        self.deliveryAttemptDidReturn = deliveryAttemptDidReturn
        self.lookupTaskDidReturn = lookupTaskDidReturn
    }

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let request = urlSchemeTask.request
        let callbacks = SchemeTaskCallbacks(urlSchemeTask)
        guard let requestURL = request.url,
              request.httpMethod == "GET",
              requestURL.scheme == "myshottr-resource",
              requestURL.host == "document",
              requestURL.port == nil,
              requestURL.user == nil,
              requestURL.password == nil,
              requestURL.query == nil,
              requestURL.fragment == nil,
              let documentID = documentID(in: requestURL),
              URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.percentEncodedPath == "/\(documentID.uuidString)/original.png"
        else {
            Task { @MainActor in
                callbacks.reject()
            }
            return
        }

        let taskID = callbacks.identity
        let registration = lookupRegistry.register(taskID)

        let lookupTask = Task { @MainActor [
            pngForDocument,
            lookupRegistry,
            deliveryBarrier,
            deliveryAttemptDidReturn,
            lookupTaskDidReturn
        ] in
            defer { lookupTaskDidReturn?() }
            guard lookupRegistry.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
            guard let png = pngForDocument(documentID) else {
                lookupRegistry.deliver(
                    taskID,
                    registration: registration,
                    deliveryBarrier: deliveryBarrier
                ) {
                    callbacks.reject()
                }
                deliveryAttemptDidReturn?()
                return
            }
            guard lookupRegistry.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
            lookupRegistry.deliver(
                taskID,
                registration: registration,
                deliveryBarrier: deliveryBarrier
            ) {
                callbacks.finish(with: png, responseURL: requestURL)
            }
            deliveryAttemptDidReturn?()
        }
        taskAttachmentBarrier?()
        lookupRegistry.attach(lookupTask, to: taskID, registration: registration)
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        lookupRegistry.stop(taskID)
    }

    nonisolated var pendingLookupCount: Int {
        lookupRegistry.count
    }

    private nonisolated func documentID(in url: URL) -> UUID? {
        let components = url.pathComponents
        guard components.count == 3, components[0] == "/", components[2] == "original.png" else { return nil }
        return UUID(uuidString: components[1])
    }
}
