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
        try await waitForSourceImage(in: editor.webView)

        XCTAssertNil(editor.navigationError)
        XCTAssertTrue(session.isOpen)
        try await createRectangleWithMouseEvents(in: editor.webView)
        let snapshot = try await editor.requestAnnotationSnapshot()
        let snapshotJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: snapshot) as? [String: Any]
        )
        XCTAssertEqual((snapshotJSON["elements"] as? [[String: Any]])?.count, 1)

        let liveCanvasJSONString = try await evaluateString(
            """
                JSON.stringify((() => {
                  const stage = window.Konva?.stages?.[0];
                  const layers = stage?.getLayers() ?? [];
                  const annotationLayer = layers.find((layer) => layer.id() === 'annotationLayer');
                  const sourceLayer = layers.find((layer) => layer.id() === 'sourceLayer');
                  const annotationGroup = annotationLayer?.getChildren()?.[0];
                  const elementNodes = annotationGroup?.getChildren(
                    (node) => node.getClassName() === 'Group'
                  ) ?? [];
                  const canvas = document.querySelectorAll('canvas')[1];
                  const pixels = canvas?.getContext('2d')?.getImageData(
                    0, 0, canvas.width, canvas.height
                  )?.data ?? [];
                  let nonTransparentPixels = 0;
                  for (let index = 3; index < pixels.length; index += 4) {
                    if (pixels[index] > 0) nonTransparentPixels += 1;
                  }
                  return {
                    elementNodeCount: elementNodes.length,
                    nonTransparentPixels,
                    hitNodeClass: stage?.getIntersection({ x: 1, y: 1 })?.getClassName(),
                    sourceLayerIndex: sourceLayer?.getZIndex(),
                    annotationLayerIndex: annotationLayer?.getZIndex(),
                  };
                })())
            """,
            in: editor.webView
        )
        let liveCanvas = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(liveCanvasJSONString.utf8))
                as? [String: Any]
        )
        XCTAssertEqual(liveCanvas["elementNodeCount"] as? Int, 1)
        XCTAssertGreaterThan(liveCanvas["nonTransparentPixels"] as? Int ?? 0, 0)
        XCTAssertEqual(liveCanvas["hitNodeClass"] as? String, "Path")
        XCTAssertEqual(liveCanvas["sourceLayerIndex"] as? Int, 0)
        XCTAssertEqual(liveCanvas["annotationLayerIndex"] as? Int, 1)

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

    private func waitForSourceImage(in webView: WKWebView) async throws {
        let loaded = expectation(description: "source image is loaded into the source layer")
        let deadline = Date().addingTimeInterval(5)
        var evaluationError: Error?

        func evaluateImage() {
            webView.evaluateJavaScript("""
                (() => {
                  const image = window.Konva?.stages?.[0]?.findOne('Image')?.image();
                  return Boolean(
                    image?.complete &&
                    image.naturalWidth === 2 &&
                    image.naturalHeight === 2
                  );
                })()
                """) { result, error in
                if let error {
                    evaluationError = error
                    return
                }
                if (result as? Bool) == true {
                    loaded.fulfill()
                } else if Date() < deadline {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + .milliseconds(50),
                        execute: evaluateImage
                    )
                }
            }
        }

        evaluateImage()
        await fulfillment(of: [loaded], timeout: 5)
        XCTAssertNil(evaluationError)
    }

    private func createRectangleWithMouseEvents(in webView: WKWebView) async throws {
        _ = try await evaluateString(
            """
            (() => {
              const button = Array.from(document.querySelectorAll(
                '[aria-label="Annotation tools"] button'
              )).find((candidate) => candidate.textContent === 'Rectangle');
              if (!button) throw new Error('Rectangle tool is unavailable');
              button.click();
              return 'selected';
            })()
            """,
            in: webView
        )
        _ = try await evaluateString(
            """
            (() => {
              const canvas = document.querySelectorAll('canvas')[1];
              if (!canvas) throw new Error('Annotation canvas is unavailable');
              const bounds = canvas.getBoundingClientRect();
              const dispatch = (type, x, y, buttons) => canvas.dispatchEvent(
                new MouseEvent(type, {
                  bubbles: true,
                  cancelable: true,
                  clientX: bounds.left + x,
                  clientY: bounds.top + y,
                  buttons,
                })
              );
              dispatch('mousedown', 0.25, 0.25, 1);
              dispatch('mousemove', 1.75, 1.75, 1);
              dispatch('mouseup', 1.75, 1.75, 0);
              return 'created';
            })()
            """,
            in: webView
        )
    }

    private func evaluateString(_ script: String, in webView: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result = result as? String {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(
                        throwing: NSError(
                            domain: "MyShottr.EditorWebViewRuntimeTests",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "JavaScript did not return a string"]
                        )
                    )
                }
            }
        }
    }

    private func validProject() throws -> MyShottrProject {
        let annotationJSON = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [],
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
