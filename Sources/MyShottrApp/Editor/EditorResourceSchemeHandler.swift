import Foundation
import WebKit

final class EditorResourceSchemeHandler: NSObject, WKURLSchemeHandler, @unchecked Sendable {
    private final class LookupRegistration: @unchecked Sendable {
        var task: Task<Void, Never>?
    }

    private nonisolated(unsafe) let pngForDocument: @MainActor (UUID) -> Data?
    private nonisolated(unsafe) let deliveryBarrier: (() -> Void)?
    private nonisolated(unsafe) let taskAttachmentBarrier: (() -> Void)?
    private nonisolated(unsafe) let deliveryAttemptDidReturn: (() -> Void)?
    private nonisolated(unsafe) let lookupTaskDidReturn: (() -> Void)?
    private let taskLock = NSLock()
    private nonisolated(unsafe) var lookupTasks: [ObjectIdentifier: LookupRegistration] = [:]

    init(
        pngForDocument: @escaping @MainActor (UUID) -> Data?,
        deliveryBarrier: (() -> Void)? = nil,
        taskAttachmentBarrier: (() -> Void)? = nil,
        deliveryAttemptDidReturn: (() -> Void)? = nil,
        lookupTaskDidReturn: (() -> Void)? = nil
    ) {
        self.pngForDocument = pngForDocument
        self.deliveryBarrier = deliveryBarrier
        self.taskAttachmentBarrier = taskAttachmentBarrier
        self.deliveryAttemptDidReturn = deliveryAttemptDidReturn
        self.lookupTaskDidReturn = lookupTaskDidReturn
    }

    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              urlSchemeTask.request.httpMethod == "GET",
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
            reject(urlSchemeTask)
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        let registration = LookupRegistration()
        taskLock.lock()
        lookupTasks[taskID] = registration
        taskLock.unlock()

        let lookupTask = Task { @MainActor [
            weak self,
            pngForDocument,
            registration,
            lookupTaskDidReturn
        ] in
            defer { lookupTaskDidReturn?() }
            guard let self else { return }
            guard self.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
            guard let png = pngForDocument(documentID) else {
                self.deliver(taskID, registration: registration) {
                    self.reject(urlSchemeTask)
                }
                self.deliveryAttemptDidReturn?()
                return
            }
            guard self.isRegistered(taskID, registration: registration), !Task.isCancelled else { return }
            self.deliver(taskID, registration: registration) {
                let response = URLResponse(
                    url: requestURL,
                    mimeType: "image/png",
                    expectedContentLength: png.count,
                    textEncodingName: nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(png)
                urlSchemeTask.didFinish()
            }
            self.deliveryAttemptDidReturn?()
        }
        taskAttachmentBarrier?()
        taskLock.lock()
        let shouldCancel = lookupTasks[taskID] !== registration
        if !shouldCancel {
            registration.task = lookupTask
        }
        taskLock.unlock()
        if shouldCancel {
            lookupTask.cancel()
        }
    }

    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        taskLock.lock()
        let registration = lookupTasks.removeValue(forKey: taskID)
        taskLock.unlock()
        registration?.task?.cancel()
    }

    nonisolated var pendingLookupCount: Int {
        taskLock.lock()
        defer { taskLock.unlock() }
        return lookupTasks.count
    }

    private nonisolated func documentID(in url: URL) -> UUID? {
        let components = url.pathComponents
        guard components.count == 3, components[0] == "/", components[2] == "original.png" else { return nil }
        return UUID(uuidString: components[1])
    }

    private nonisolated func reject(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: "MyShottr.EditorResourceScheme", code: 1))
    }

    private nonisolated func isRegistered(
        _ taskID: ObjectIdentifier,
        registration: LookupRegistration
    ) -> Bool {
        taskLock.lock()
        defer { taskLock.unlock() }
        return lookupTasks[taskID] === registration
    }

    private nonisolated func deliver(
        _ taskID: ObjectIdentifier,
        registration: LookupRegistration,
        callback: () -> Void
    ) {
        taskLock.lock()
        defer { taskLock.unlock() }
        guard lookupTasks[taskID] === registration else { return }
        lookupTasks.removeValue(forKey: taskID)
        deliveryBarrier?()
        callback()
    }
}
