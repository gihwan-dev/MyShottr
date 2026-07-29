import Foundation
import WebKit

@MainActor
final class EditorWebView: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let editorURL: URL
    private let bridge: EditorBridge
    private let configuration: WKWebViewConfiguration
    private var didTearDown = false

    init(session: DocumentSession) {
        let bridge = EditorBridge(session: session)
        let resourceHandler = EditorResourceSchemeHandler { documentID in
            session.sourcePNG(for: documentID)
        }
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(resourceHandler, forURLScheme: "myshottr-resource")
        configuration.userContentController.add(bridge, name: "myshottr")

        guard let resourcesURL = Bundle.main.resourceURL
        else {
            preconditionFailure("Bundled editor is missing")
        }
        let editorURL = resourcesURL.appendingPathComponent("Editor/index.html", isDirectory: false)
        guard FileManager.default.fileExists(atPath: editorURL.path) else {
            preconditionFailure("Bundled editor is missing")
        }

        self.bridge = bridge
        self.configuration = configuration
        self.editorURL = editorURL
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        bridge.attach(to: webView)
        webView.loadFileURL(editorURL, allowingReadAccessTo: resourcesURL)
    }

    func tearDown() {
        guard !didTearDown else { return }
        didTearDown = true
        bridge.tearDown()
        configuration.userContentController.removeScriptMessageHandler(forName: "myshottr")
    }

    func load(project: MyShottrProject) throws {
        try bridge.load(project: project)
    }

    func requestAnnotationSnapshot() async throws -> Data {
        try await bridge.requestAnnotationSnapshot()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.request.url == editorURL else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
