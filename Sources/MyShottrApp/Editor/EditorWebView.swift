import Foundation
import WebKit

@MainActor
final class EditorWebView: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let editorURL: URL
    private let bridge: EditorBridge
    private let configuration: WKWebViewConfiguration
    private var didTearDown = false
    private(set) var navigationError: Error?
    private(set) var navigationFinished = false
    var onNavigationFinished: (() -> Void)?
    var onNavigationFailure: ((Error) -> Void)?
    var onBridgeFailure: ((EditorBridgeError) -> Void)? {
        didSet {
            bridge.onUncorrelatedError = onBridgeFailure
        }
    }

    convenience init(session: DocumentSession, preferences: any EditorPreferencesStoring = UserDefaultsEditorPreferencesStore()) {
        guard let resourcesURL = Bundle.main.resourceURL
        else {
            preconditionFailure("Bundled editor is missing")
        }
        let editorURL = resourcesURL.appendingPathComponent("Editor/index.html", isDirectory: false)
        guard FileManager.default.fileExists(atPath: editorURL.path) else {
            preconditionFailure("Bundled editor is missing")
        }

        self.init(
            session: session,
            editorBundleRootURL: editorURL.deletingLastPathComponent(),
            preferences: preferences
        )
    }

    private convenience init(session: DocumentSession, editorBundleRootURL: URL, preferences: any EditorPreferencesStoring) {
        self.init(
            session: session,
            editorURL: URL(string: "myshottr-editor://editor/index.html")!,
            editorBundleRootURL: editorBundleRootURL,
            preferences: preferences
        )
    }

    private init(session: DocumentSession, editorURL: URL, editorBundleRootURL: URL, preferences: any EditorPreferencesStoring) {
        let bridge = EditorBridge(session: session, preferences: preferences)
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            EditorBundleSchemeHandler(
                rootURL: editorBundleRootURL,
                pngForDocument: { documentID in
                    session.sourcePNG(for: documentID)
                }
            ),
            forURLScheme: "myshottr-editor"
        )
        configuration.userContentController.add(bridge, name: "myshottr")

        self.bridge = bridge
        self.configuration = configuration
        self.editorURL = editorURL
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        bridge.attach(to: webView)
        webView.load(URLRequest(url: editorURL))
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

    func requestComposite(destinationDirectory: URL? = nil) async throws -> CompositeTransfer {
        try await bridge.requestComposite(destinationDirectory: destinationDirectory)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.request.url == editorURL else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationFinished = true
        onNavigationFinished?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
        reportNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationFailure(error)
    }

    private func reportNavigationFailure(_ error: Error) {
        navigationError = error
        onNavigationFailure?(error)
    }
}
