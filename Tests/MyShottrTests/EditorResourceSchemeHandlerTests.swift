import Foundation
import WebKit
import XCTest
@testable import MyShottr

@MainActor
final class EditorResourceSchemeHandlerTests: XCTestCase {
    func testServesOnlyTheActiveSessionPNGAtTheExactDocumentURL() async {
        let activeDocumentID = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let handler = EditorResourceSchemeHandler { documentID in
            documentID == activeDocumentID ? png : nil
        }
        let task = SchemeTask(url: resourceURL(documentID: activeDocumentID))

        handler.webView(WKWebView(frame: .zero), start: task)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(task.response?.mimeType, "image/png")
        XCTAssertEqual(task.data, png)
        XCTAssertTrue(task.didFinishCalled)
        XCTAssertNil(task.error)
    }

    func testRejectsUnknownIDsExtraSegmentsNonGETAndTraversalWithoutResolvingBytes() async {
        let activeDocumentID = UUID()
        var resolveCount = 0
        let handler = EditorResourceSchemeHandler { documentID in
            resolveCount += 1
            return documentID == activeDocumentID ? Data([0x89, 0x50, 0x4E, 0x47]) : nil
        }
        let invalidRequests = [
            URLRequest(url: resourceURL(documentID: UUID())),
            URLRequest(url: URL(string: "myshottr-resource://document/\(activeDocumentID.uuidString)/original.png/extra")!),
            URLRequest(url: URL(string: "myshottr-resource://document/../original.png")!),
            request(url: resourceURL(documentID: activeDocumentID), method: "POST"),
        ]

        for request in invalidRequests {
            let task = SchemeTask(request: request)
            handler.webView(WKWebView(frame: .zero), start: task)
            await Task.yield()
            await Task.yield()
            XCTAssertNotNil(task.error)
            XCTAssertNil(task.data)
        }
        XCTAssertEqual(resolveCount, 1)
    }

    func testStopCancelsAQueuedLookupWithoutCompletingTheSchemeTask() async {
        let handler = EditorResourceSchemeHandler { _ in
            XCTFail("Cancelled lookup must not read session bytes")
            return Data()
        }
        let task = SchemeTask(url: resourceURL(documentID: UUID()))

        handler.webView(WKWebView(frame: .zero), start: task)
        handler.webView(WKWebView(frame: .zero), stop: task)
        await Task.yield()
        await Task.yield()

        XCTAssertNil(task.response)
        XCTAssertNil(task.data)
        XCTAssertNil(task.error)
        XCTAssertFalse(task.didFinishCalled)
    }

    private func resourceURL(documentID: UUID) -> URL {
        URL(string: "myshottr-resource://document/\(documentID.uuidString)/original.png")!
    }

    private func request(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }
}

private final class SchemeTask: NSObject, WKURLSchemeTask, @unchecked Sendable {
    let request: URLRequest
    private(set) var response: URLResponse?
    private(set) var data: Data?
    private(set) var error: Error?
    private(set) var didFinishCalled = false

    init(url: URL) {
        self.request = URLRequest(url: url)
    }

    init(request: URLRequest) {
        self.request = request
    }

    func didReceive(_ response: URLResponse) {
        self.response = response
    }

    func didReceive(_ data: Data) {
        self.data = data
    }

    func didFinish() {
        didFinishCalled = true
    }

    func didFailWithError(_ error: Error) {
        self.error = error
    }
}
