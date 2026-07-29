import Foundation
import WebKit
import XCTest
@testable import MyShottr

@MainActor
final class EditorDocumentResourceSchemeHandlerTests: XCTestCase {
    func testServesOnlyTheActiveSessionPNGAtTheExactDocumentURL() async {
        let activeDocumentID = UUID()
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let terminalCallback = expectation(description: "PNG delivery finishes")
        let handler = EditorBundleSchemeHandler(
            rootURL: emptyBundleRoot,
            pngForDocument: { documentID in
                documentID == activeDocumentID ? png : nil
            }
        )
        let task = SchemeTask(
            url: resourceURL(documentID: activeDocumentID),
            onTerminalCallback: { terminalCallback.fulfill() }
        )

        handler.webView(WKWebView(frame: .zero), start: task)
        await fulfillment(of: [terminalCallback])

        XCTAssertEqual(task.response?.mimeType, "image/png")
        XCTAssertEqual(task.data, png)
        XCTAssertTrue(task.didFinishCalled)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.responseCount, 1)
        XCTAssertEqual(task.dataCount, 1)
        XCTAssertEqual(task.didFinishCount, 1)
        XCTAssertEqual(task.failureCount, 0)
        XCTAssertTrue(task.callbacksWereOnMainThread)
    }

    func testRejectsUnknownIDsExtraSegmentsNonGETAndTraversalWithoutResolvingBytes() async {
        let activeDocumentID = UUID()
        var resolveCount = 0
        let handler = EditorBundleSchemeHandler(
            rootURL: emptyBundleRoot,
            pngForDocument: { documentID in
                resolveCount += 1
                return documentID == activeDocumentID ? Data([0x89, 0x50, 0x4E, 0x47]) : nil
            }
        )
        let invalidRequests = [
            URLRequest(url: resourceURL(documentID: UUID())),
            URLRequest(url: URL(string: "myshottr-editor://editor/document/\(activeDocumentID.uuidString)/original.png/extra")!),
            URLRequest(url: URL(string: "myshottr-editor://editor/document/../original.png")!),
            URLRequest(url: URL(string: "myshottr-resource://document/\(activeDocumentID.uuidString)/original.png")!),
            request(url: resourceURL(documentID: activeDocumentID), method: "POST"),
        ]

        let terminalCallbacks = invalidRequests.indices.map {
            expectation(description: "invalid request \($0) fails")
        }
        let tasks = zip(invalidRequests, terminalCallbacks).map { request, terminalCallback in
            let task = SchemeTask(
                request: request,
                onTerminalCallback: { terminalCallback.fulfill() }
            )
            handler.webView(WKWebView(frame: .zero), start: task)
            return task
        }

        await fulfillment(of: terminalCallbacks)
        for task in tasks {
            XCTAssertNotNil(task.error)
            XCTAssertNil(task.data)
            XCTAssertEqual(task.responseCount, 0)
            XCTAssertEqual(task.dataCount, 0)
            XCTAssertEqual(task.didFinishCount, 0)
            XCTAssertEqual(task.failureCount, 1)
            XCTAssertTrue(task.callbacksWereOnMainThread)
        }
        XCTAssertEqual(resolveCount, 1)
    }

    func testStopCancelsAQueuedLookupWithoutCompletingTheSchemeTask() async {
        let lookupReturned = expectation(description: "cancelled lookup returns")
        let handler = EditorBundleSchemeHandler(
            rootURL: emptyBundleRoot,
            pngForDocument: { _ in
                XCTFail("Cancelled lookup must not read session bytes")
                return Data()
            },
            lookupTaskDidReturn: {
                lookupReturned.fulfill()
            }
        )
        let task = SchemeTask(url: resourceURL(documentID: UUID()))

        handler.webView(WKWebView(frame: .zero), start: task)
        handler.webView(WKWebView(frame: .zero), stop: task)
        await fulfillment(of: [lookupReturned])

        XCTAssertNil(task.response)
        XCTAssertNil(task.data)
        XCTAssertNil(task.error)
        XCTAssertFalse(task.didFinishCalled)
    }

    func testStopDuringTaskAttachmentLeavesNoCallbacksOrPendingLookup() async {
        let attachmentPaused = DispatchSemaphore(value: 0)
        let releaseAttachment = DispatchSemaphore(value: 0)
        let lookupReturned = expectation(description: "stopped startup task returns")
        let task = SchemeTask(url: resourceURL(documentID: UUID()))
        let handler = EditorBundleSchemeHandler(
            rootURL: emptyBundleRoot,
            pngForDocument: { _ in
                XCTFail("A startup stopped before attachment must not read session bytes")
                return Data()
            },
            taskAttachmentBarrier: {
                attachmentPaused.signal()
                releaseAttachment.wait()
            },
            lookupTaskDidReturn: {
                lookupReturned.fulfill()
            }
        )
        let webView = WKWebView(frame: .zero)

        DispatchQueue.global().async {
            attachmentPaused.wait()
            handler.webView(webView, stop: task)
            releaseAttachment.signal()
        }

        handler.webView(webView, start: task)
        await fulfillment(of: [lookupReturned])

        XCTAssertEqual(task.responseCount, 0)
        XCTAssertEqual(task.dataCount, 0)
        XCTAssertEqual(task.didFinishCount, 0)
        XCTAssertEqual(task.failureCount, 0)
        XCTAssertEqual(handler.pendingLookupCount, 0)
    }

    func testCompletionWinsBeforeStopReturnsWhenDeliveryWasAlreadyClaimed() async {
        let deliveryClaimed = DispatchSemaphore(value: 0)
        let stopStarted = DispatchSemaphore(value: 0)
        let releaseDelivery = DispatchSemaphore(value: 0)
        let task = SchemeTask(url: resourceURL(documentID: UUID()))
        let handler = EditorBundleSchemeHandler(
            rootURL: emptyBundleRoot,
            pngForDocument: { _ in Data([0x89, 0x50, 0x4E, 0x47]) },
            deliveryBarrier: {
                deliveryClaimed.signal()
                releaseDelivery.wait()
            }
        )
        let webView = WKWebView(frame: .zero)

        let stopFinished = expectation(description: "stop returns after claimed delivery")
        DispatchQueue.global().async {
            deliveryClaimed.wait()
            stopStarted.signal()
            handler.webView(webView, stop: task)
            stopFinished.fulfill()
        }
        DispatchQueue.global().async {
            stopStarted.wait()
            releaseDelivery.signal()
        }

        handler.webView(webView, start: task)
        await fulfillment(of: [stopFinished])

        XCTAssertEqual(task.response?.mimeType, "image/png")
        XCTAssertEqual(task.data, Data([0x89, 0x50, 0x4E, 0x47]))
        XCTAssertTrue(task.didFinishCalled)
        XCTAssertNil(task.error)
        XCTAssertEqual(task.responseCount, 1)
        XCTAssertEqual(task.dataCount, 1)
        XCTAssertEqual(task.didFinishCount, 1)
        XCTAssertEqual(task.failureCount, 0)
    }

    func testRegistrationExistsBeforeLookupTaskCanDeliver() async {
        let deliveryAttemptReturned = DispatchSemaphore(value: 0)
        let task = SchemeTask(url: resourceURL(documentID: UUID()))
        let handler = EditorBundleSchemeHandler(
            rootURL: emptyBundleRoot,
            pngForDocument: { _ in Data([0x89, 0x50, 0x4E, 0x47]) },
            taskAttachmentBarrier: {
                deliveryAttemptReturned.wait()
            },
            deliveryAttemptDidReturn: {
                deliveryAttemptReturned.signal()
            }
        )
        let webView = WKWebView(frame: .zero)
        let startFinished = expectation(description: "start returns after forced early delivery")

        DispatchQueue.global().async {
            handler.webView(webView, start: task)
            startFinished.fulfill()
        }

        await fulfillment(of: [startFinished])
        let pendingLookupCount = handler.pendingLookupCount
        handler.webView(webView, stop: task)

        XCTAssertEqual(task.responseCount, 1)
        XCTAssertEqual(task.dataCount, 1)
        XCTAssertEqual(task.didFinishCount, 1)
        XCTAssertEqual(task.failureCount, 0)
        XCTAssertEqual(pendingLookupCount, 0)
        XCTAssertTrue(task.callbacksWereOnMainThread)
    }

    private func resourceURL(documentID: UUID) -> URL {
        URL(string: "myshottr-editor://editor/document/\(documentID.uuidString)/original.png")!
    }

    private var emptyBundleRoot: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorDocumentResourceSchemeHandlerTests-Unused", isDirectory: true)
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
    private(set) var responseCount = 0
    private(set) var dataCount = 0
    private(set) var didFinishCount = 0
    private(set) var failureCount = 0
    private(set) var callbacksWereOnMainThread = true
    private let onTerminalCallback: (() -> Void)?

    init(url: URL, onTerminalCallback: (() -> Void)? = nil) {
        self.request = URLRequest(url: url)
        self.onTerminalCallback = onTerminalCallback
    }

    init(request: URLRequest, onTerminalCallback: (() -> Void)? = nil) {
        self.request = request
        self.onTerminalCallback = onTerminalCallback
    }

    func didReceive(_ response: URLResponse) {
        recordCallbackExecutor()
        responseCount += 1
        self.response = response
    }

    func didReceive(_ data: Data) {
        recordCallbackExecutor()
        dataCount += 1
        self.data = data
    }

    func didFinish() {
        recordCallbackExecutor()
        didFinishCount += 1
        didFinishCalled = true
        onTerminalCallback?()
    }

    func didFailWithError(_ error: Error) {
        recordCallbackExecutor()
        failureCount += 1
        self.error = error
        onTerminalCallback?()
    }

    private func recordCallbackExecutor() {
        callbacksWereOnMainThread = callbacksWereOnMainThread && Thread.isMainThread
    }
}
