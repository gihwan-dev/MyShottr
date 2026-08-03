import Foundation
import WebKit
import XCTest
@testable import Inkbeam

@MainActor
final class EditorBundleSchemeHandlerTests: XCTestCase {
    func testServesOnlyIndexAndHashedJavaScriptAndStylesheetAssets() async throws {
        let root = try makeBundleRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let handler = EditorBundleSchemeHandler(rootURL: root, pngForDocument: { _ in nil })
        let indexTask = SchemeTask(url: editorURL("/index.html"))
        let scriptTask = SchemeTask(url: editorURL("/assets/index-AbC_12.js"))
        let stylesheetTask = SchemeTask(url: editorURL("/assets/index-AbC_12.css"))
        let completed = [indexTask, scriptTask, stylesheetTask].map { task in
            expectation(description: "\(task.request.url!.path) completes")
                .then { task.onTerminalCallback = $0 }
        }

        for task in [indexTask, scriptTask, stylesheetTask] {
            handler.webView(WKWebView(frame: .zero), start: task)
        }
        await fulfillment(of: completed)

        XCTAssertEqual(indexTask.response?.mimeType, "text/html")
        XCTAssertEqual(indexTask.data, Data("""
        <script type="module" src="./assets/index-AbC_12.js"></script>
        <link rel="stylesheet" href="./assets/index-AbC_12.css">
        """.utf8))
        XCTAssertEqual(scriptTask.response?.mimeType, "application/javascript")
        XCTAssertEqual(scriptTask.data, Data("export {};".utf8))
        XCTAssertEqual(stylesheetTask.response?.mimeType, "text/css")
        XCTAssertEqual(stylesheetTask.data, Data("main {}".utf8))
    }

    func testRejectsNonGETUnknownAssetsTraversalAndMalformedURLs() async throws {
        let root = try makeBundleRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let handler = EditorBundleSchemeHandler(rootURL: root, pngForDocument: { _ in nil })
        let invalidRequests = [
            request(url: editorURL("/assets/other.js"), method: "GET"),
            request(url: editorURL("/assets/index-Unreferenced.js"), method: "GET"),
            request(url: editorURL("/assets/index-AbC_12.js/extra"), method: "GET"),
            request(url: URL(string: "inkbeam-editor://editor/assets/%69ndex-AbC_12.js")!, method: "GET"),
            request(url: URL(string: "inkbeam-editor://editor/assets/%2E%2E/index-AbC_12.js")!, method: "GET"),
            request(url: URL(string: "inkbeam-editor://editor/index%2Ehtml")!, method: "GET"),
            request(url: editorURL("/index.html"), method: "POST"),
            request(url: URL(string: "myshottr-editor://editor/index.html")!, method: "GET"),
            request(url: URL(string: "inkbeam-editor://other/index.html")!, method: "GET"),
            request(url: editorURL("/assets/index-AbC_12.png"), method: "GET"),
        ]
        let tasks = invalidRequests.map { SchemeTask(request: $0) }
        let completed = tasks.map { task in
            expectation(description: "\(task.request.url!.absoluteString) fails")
                .then { task.onTerminalCallback = $0 }
        }

        for task in tasks {
            handler.webView(WKWebView(frame: .zero), start: task)
        }
        await fulfillment(of: completed)

        for task in tasks {
            XCTAssertNotNil(task.error)
            XCTAssertNil(task.data)
            XCTAssertEqual(task.responseCount, 0)
            XCTAssertEqual(task.didFinishCount, 0)
            XCTAssertEqual(task.failureCount, 1)
        }
    }

    func testStopDuringAttachmentCancelsWithoutAnyCallback() async throws {
        let root = try makeBundleRoot()
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let attachmentPaused = DispatchSemaphore(value: 0)
        let releaseAttachment = DispatchSemaphore(value: 0)
        let lookupReturned = expectation(description: "cancelled bundle lookup returns")
        let handler = EditorBundleSchemeHandler(
            rootURL: root,
            pngForDocument: { _ in nil },
            taskAttachmentBarrier: {
                attachmentPaused.signal()
                releaseAttachment.wait()
            },
            lookupTaskDidReturn: { lookupReturned.fulfill() }
        )
        let task = SchemeTask(url: editorURL("/index.html"))
        let webView = WKWebView(frame: .zero)

        DispatchQueue.global().async {
            attachmentPaused.wait()
            handler.webView(webView, stop: task)
            releaseAttachment.signal()
        }

        handler.webView(webView, start: task)
        await fulfillment(of: [lookupReturned])

        XCTAssertNil(task.response)
        XCTAssertNil(task.data)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.didFinishCount, 0)
        XCTAssertEqual(task.failureCount, 0)
        XCTAssertEqual(handler.pendingLookupCount, 0)
    }

    private func makeBundleRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorBundleSchemeHandlerTests-\(UUID().uuidString)/Editor", isDirectory: true)
        let assets = root.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data("""
        <script type="module" src="./assets/index-AbC_12.js"></script>
        <link rel="stylesheet" href="./assets/index-AbC_12.css">
        """.utf8).write(to: root.appendingPathComponent("index.html"))
        try Data("export {};".utf8).write(to: assets.appendingPathComponent("index-AbC_12.js"))
        try Data("main {}".utf8).write(to: assets.appendingPathComponent("index-AbC_12.css"))
        try Data("export {};".utf8).write(to: assets.appendingPathComponent("index-Unreferenced.js"))
        return root
    }

    private func editorURL(_ path: String) -> URL {
        URL(string: "inkbeam-editor://editor\(path)")!
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}

private final class SchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {
    let request: URLRequest
    var onTerminalCallback: (() -> Void)?
    private(set) var response: URLResponse?
    private(set) var data: Data?
    private(set) var error: Error?
    private(set) var responseCount = 0
    private(set) var didFinishCount = 0
    private(set) var failureCount = 0

    init(url: URL) {
        request = URLRequest(url: url)
    }

    init(request: URLRequest) {
        self.request = request
    }

    func didReceive(_ response: URLResponse) {
        responseCount += 1
        self.response = response
    }

    func didReceive(_ data: Data) {
        self.data = data
    }

    func didFinish() {
        didFinishCount += 1
        onTerminalCallback?()
    }

    func didFailWithError(_ error: Error) {
        failureCount += 1
        self.error = error
        onTerminalCallback?()
    }
}

private extension XCTestExpectation {
    func then(_ install: (@escaping () -> Void) -> Void) -> XCTestExpectation {
        install { self.fulfill() }
        return self
    }
}
