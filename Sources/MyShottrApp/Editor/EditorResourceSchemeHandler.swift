import Foundation
import WebKit

final class EditorResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let pngForDocument: @MainActor (UUID) -> Data?
    private let taskLock = NSLock()
    private var lookupTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    init(pngForDocument: @escaping @MainActor (UUID) -> Data?) {
        self.pngForDocument = pngForDocument
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
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
        let lookupTask = Task { @MainActor [weak self, pngForDocument] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            guard let png = pngForDocument(documentID) else {
                guard self?.claimCompletion(taskID) == true else { return }
                self?.reject(urlSchemeTask)
                return
            }
            guard !Task.isCancelled, self?.claimCompletion(taskID) == true else { return }
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
        taskLock.lock()
        lookupTasks[taskID] = lookupTask
        taskLock.unlock()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        taskLock.lock()
        let lookupTask = lookupTasks.removeValue(forKey: taskID)
        taskLock.unlock()
        lookupTask?.cancel()
    }

    private func documentID(in url: URL) -> UUID? {
        let components = url.pathComponents
        guard components.count == 3, components[0] == "/", components[2] == "original.png" else { return nil }
        return UUID(uuidString: components[1])
    }

    private func reject(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: "MyShottr.EditorResourceScheme", code: 1))
    }

    private func claimCompletion(_ taskID: ObjectIdentifier) -> Bool {
        taskLock.lock()
        defer { taskLock.unlock() }
        return lookupTasks.removeValue(forKey: taskID) != nil
    }
}
