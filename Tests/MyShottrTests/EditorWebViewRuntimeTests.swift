import Foundation
import AppKit
import WebKit
import XCTest
@testable import MyShottr

@MainActor
final class EditorWebViewRuntimeTests: XCTestCase {
    func testBundledEditorLoadsValidProjectMountsReactAndSurfacesNavigationFailure() async throws {
        let session = DocumentSession()
        let editor = EditorWebView(session: session)
        let window = attach(editor.webView)
        defer {
            window.contentView = nil
            window.close()
            editor.tearDown()
        }
        let navigationFinished = expectation(description: "editor index navigation finishes")
        if editor.navigationFinished {
            navigationFinished.fulfill()
        } else {
            editor.onNavigationFinished = { navigationFinished.fulfill() }
        }

        try editor.load(project: validProject())
        await fulfillment(of: [navigationFinished], timeout: 5)
        try await waitForEditorMount(in: editor.webView)

        XCTAssertNil(editor.navigationError)
        XCTAssertTrue(session.isOpen)
        let navigationFailed = expectation(description: "missing editor navigation failure is reported")
        editor.onNavigationFailure = { _ in navigationFailed.fulfill() }
        editor.webView(
            editor.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "MyShottr.EditorBundle", code: 1)
        )
        await fulfillment(of: [navigationFailed], timeout: 5)
        XCTAssertNotNil(editor.navigationError)
    }

    private func waitForEditorMount(in webView: WKWebView) async throws {
        let mounted = expectation(description: "React editor mounts with toolbar and canvas")
        let deadline = Date().addingTimeInterval(5)
        var evaluationError: Error?

        func evaluate() {
            webView.evaluateJavaScript("""
                Boolean(
                  document.getElementById('root')?.childElementCount &&
                  document.querySelector('[aria-label="Annotation tools"]') &&
                  document.querySelector('canvas')
                )
                """) { result, error in
                if let error {
                    evaluationError = error
                    return
                }
                if (result as? Bool) == true {
                    mounted.fulfill()
                } else if Date() < deadline {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: evaluate)
                }
            }
        }

        evaluate()
        await fulfillment(of: [mounted], timeout: 5)
        XCTAssertNil(evaluationError)
    }

    private func validProject() throws -> MyShottrProject {
        let annotationJSON = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [[
                "id": "rectangle-1", "type": "rectangle", "x": 0, "y": 0,
                "width": 1, "height": 1, "rotation": 0, "opacity": 1,
                "zIndex": 0, "seed": 1, "strokeColor": "#1677FF", "strokeWidth": 4,
                "fillColor": NSNull(), "roughness": 1,
            ]],
            "defaults": ["color": "#1677FF", "strokeWidth": 4, "textSize": 24, "roughness": 1, "opacity": 1],
        ])
        return MyShottrProject(
            manifest: ProjectManifest(
                formatVersion: ProjectManifest.currentFormatVersion,
                documentId: UUID(),
                createdAt: .now,
                updatedAt: .now,
                sourcePixelWidth: 2,
                sourcePixelHeight: 2,
                sourceKind: .screenRegion
            ),
            originalPNG: ProjectFixtures.pngData,
            annotationJSON: annotationJSON
        )
    }

    private func attach(_ webView: WKWebView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFrontRegardless()
        return window
    }
}
