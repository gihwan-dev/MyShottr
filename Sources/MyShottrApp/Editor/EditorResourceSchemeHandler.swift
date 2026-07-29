import Foundation
import WebKit

final class EditorResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    private let pngForDocument: @MainActor (UUID) -> Data?

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

        let png = MainActor.assumeIsolated { pngForDocument(documentID) }
        guard let png else {
            reject(urlSchemeTask)
            return
        }
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

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func documentID(in url: URL) -> UUID? {
        let components = url.pathComponents
        guard components.count == 3, components[0] == "/", components[2] == "original.png" else { return nil }
        return UUID(uuidString: components[1])
    }

    private func reject(_ task: WKURLSchemeTask) {
        task.didFailWithError(NSError(domain: "MyShottr.EditorResourceScheme", code: 1))
    }
}
