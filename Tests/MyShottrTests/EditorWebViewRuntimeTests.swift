import Foundation
import AppKit
import ImageIO
import WebKit
import XCTest
@testable import MyShottr

@MainActor
final class EditorWebViewRuntimeTests: XCTestCase {
    func testBundledEditorLoadsValidProjectMountsCompositesTheSessionPNGAndSurfacesNavigationFailure() async throws {
        let session = DocumentSession()
        let editor = EditorWebView(session: session)
        let window = attach(editor.webView)
        defer {
            window.contentView = nil
            window.close()
            editor.tearDown()
        }

        try editor.load(project: validProject())
        try await waitForEditorMount(in: editor.webView)

        XCTAssertNil(editor.navigationError)
        XCTAssertTrue(session.isOpen)
        let transfer = try await editor.requestComposite()
        let png = try transfer.data()
        XCTAssertTrue(png.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 2)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 2)

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
