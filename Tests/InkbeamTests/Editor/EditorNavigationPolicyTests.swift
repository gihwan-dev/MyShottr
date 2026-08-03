import Foundation
import WebKit
import XCTest
@testable import Inkbeam

@MainActor
final class EditorNavigationPolicyTests: XCTestCase {
    func testAllowsOnlyExactResourcesServedByTheBundledEditorScheme() throws {
        let root = try makeEditorRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let policy = EditorNavigationPolicy(editorBundleRootURL: root)
        let documentID = UUID(
            uuidString: "ABCDEF12-3456-4789-ABCD-EF1234567890"
        )!

        XCTAssertEqual(
            policy.decision(for: URL(string: "inkbeam-editor://editor/index.html")!),
            .allow
        )
        XCTAssertEqual(
            policy.decision(for: URL(string: "inkbeam-editor://editor/assets/index-AbC_12.js")!),
            .allow
        )
        XCTAssertEqual(
            policy.decision(for: URL(string: "inkbeam-editor://editor/assets/index-AbC_12.css")!),
            .allow
        )
        XCTAssertEqual(
            policy.decision(
                for: URL(
                    string: "inkbeam-editor://editor/document/\(documentID.uuidString)/original.png"
                )!
            ),
            .allow
        )

        let legacyEditorScheme = ["my", "shottr", "-editor"].joined()
        let deniedURLStrings = [
            "https://example.com",
            "http://localhost:3000",
            "data:text/html,test",
            "javascript:alert(1)",
            "blob:inkbeam-editor://editor/id",
            "about:blank",
            "file:///App/Editor/index.html",
            "\(legacyEditorScheme)://editor/index.html",
            "inkbeam-editor://other/index.html",
            "inkbeam-editor://user@editor/index.html",
            "inkbeam-editor://editor:443/index.html",
            "inkbeam-editor://editor/index.html?remote=1",
            "inkbeam-editor://editor/index.html#fragment",
            "inkbeam-editor://editor/assets/unknown.js",
            "inkbeam-editor://editor/assets/%69ndex-AbC_12.js",
            "inkbeam-editor://editor/assets/%2E%2E/index-AbC_12.js",
            "inkbeam-editor://editor/assets/index-AbC_12.js%2Fextra",
            "inkbeam-editor://editor/index%2Ehtml",
            "inkbeam-editor://editor/document/%41BCDEF12-3456-4789-ABCD-EF1234567890/original.png",
            "inkbeam-editor://editor/document/\(documentID.uuidString.lowercased())/original.png",
            "inkbeam-editor://editor/document/\(documentID.uuidString)/original.png/extra",
        ]
        let deniedURLs = try deniedURLStrings.map {
            try XCTUnwrap(URL(string: $0), "Invalid URL fixture: \($0)")
        }

        XCTAssertEqual(deniedURLs.count, deniedURLStrings.count)
        XCTAssertEqual(deniedURLs.count, 21)
        for url in deniedURLs {
            XCTAssertEqual(policy.decision(for: url), .cancel, url.absoluteString)
        }
    }

    func testNavigationAllowsOnlyExactMainDocumentInAnExistingMainFrame() throws {
        let root = try makeEditorRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let policy = EditorNavigationPolicy(editorBundleRootURL: root)
        let index = URL(string: "inkbeam-editor://editor/index.html")!
        let asset = URL(string: "inkbeam-editor://editor/assets/index-AbC_12.js")!

        XCTAssertEqual(
            policy.navigationDecision(
                for: index,
                hasTargetFrame: true,
                isMainFrame: true,
                shouldPerformDownload: false
            ),
            .allow
        )
        XCTAssertEqual(
            policy.navigationDecision(
                for: index,
                hasTargetFrame: false,
                isMainFrame: true,
                shouldPerformDownload: false
            ),
            .cancel,
            "New-window targets must be denied"
        )
        XCTAssertEqual(
            policy.navigationDecision(
                for: index,
                hasTargetFrame: true,
                isMainFrame: false,
                shouldPerformDownload: false
            ),
            .cancel,
            "Frame navigation must be denied"
        )
        XCTAssertEqual(
            policy.navigationDecision(
                for: index,
                hasTargetFrame: true,
                isMainFrame: true,
                shouldPerformDownload: true
            ),
            .cancel,
            "Downloads must be denied"
        )
        XCTAssertEqual(
            policy.navigationDecision(
                for: asset,
                hasTargetFrame: true,
                isMainFrame: true,
                shouldPerformDownload: false
            ),
            .cancel,
            "A subresource must never replace the main document"
        )
        XCTAssertEqual(
            policy.navigationDecision(
                for: nil,
                hasTargetFrame: true,
                isMainFrame: true,
                shouldPerformDownload: false
            ),
            .cancel
        )
    }

    func testResponseAllowsOnlyDisplayableExactMainDocument() throws {
        let root = try makeEditorRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let policy = EditorNavigationPolicy(editorBundleRootURL: root)
        let index = URL(string: "inkbeam-editor://editor/index.html")!

        XCTAssertEqual(
            policy.responseDecision(
                for: index,
                isForMainFrame: true,
                canShowMIMEType: true
            ),
            .allow
        )
        XCTAssertEqual(
            policy.responseDecision(
                for: index,
                isForMainFrame: true,
                canShowMIMEType: false
            ),
            .cancel
        )
        XCTAssertEqual(
            policy.responseDecision(
                for: URL(string: "https://example.com")!,
                isForMainFrame: true,
                canShowMIMEType: true
            ),
            .cancel
        )
        XCTAssertEqual(
            policy.responseDecision(
                for: index,
                isForMainFrame: false,
                canShowMIMEType: true
            ),
            .cancel
        )
    }

    func testEditorConfigurationDisablesJavaScriptWindowsAndHasNoRemoteUserScript() {
        let editor = EditorWebView(session: DocumentSession())
        defer { editor.tearDown() }
        let configuration = editor.webView.configuration

        XCTAssertFalse(
            configuration.preferences.javaScriptCanOpenWindowsAutomatically
        )
        for userScript in configuration.userContentController.userScripts {
            XCTAssertFalse(userScript.source.contains("http:"))
            XCTAssertFalse(userScript.source.contains("https:"))
        }
    }

    private func makeEditorRoot() throws -> URL {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let root = container.appendingPathComponent("Editor", isDirectory: true)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: assets,
            withIntermediateDirectories: true
        )
        try Data(
            """
            <script type="module" src="./assets/index-AbC_12.js"></script>
            <link rel="stylesheet" href="./assets/index-AbC_12.css">
            """.utf8
        ).write(to: root.appendingPathComponent("index.html"))
        try Data("export {};".utf8).write(
            to: assets.appendingPathComponent("index-AbC_12.js")
        )
        try Data("main {}".utf8).write(
            to: assets.appendingPathComponent("index-AbC_12.css")
        )
        return root
    }
}
