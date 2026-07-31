import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class EditorBridgeCompositeTransferTests: TemporaryDirectoryTestCase {
    func testLateLoadEvaluationErrorsAfterSupersessionAndSuccessAreIgnored() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        var completions: [UUID: (Error?) -> Void] = [:]
        let bridge = EditorBridge(
            session: session,
            javaScriptEvaluationObserver: { requestID, completion in
                completions[requestID] = completion
            },
            outgoingMessageObserver: { envelope in
                if envelope.type == .loadDocument { outgoing.append(envelope) }
            }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        try bridge.load(project: validProject())
        let superseded = try XCTUnwrap(outgoing.last)
        try bridge.load(project: validProject())
        let accepted = try XCTUnwrap(outgoing.last)

        try XCTUnwrap(completions[superseded.requestId])(evaluationFailure())
        await Task.yield()
        XCTAssertNil(bridge.lastError)

        bridge.receive(data: try annotationSnapshot(requestID: accepted.requestId))
        try XCTUnwrap(completions[accepted.requestId])(evaluationFailure())
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testLateSnapshotEvaluationErrorsAfterTimeoutAndCancellationAreIgnored() async throws {
        let session = DocumentSession()
        var completions: [UUID: (Error?) -> Void] = [:]
        var evaluationRequests: [UUID] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(10),
            javaScriptEvaluationObserver: { requestID, completion in
                evaluationRequests.append(requestID)
                completions[requestID] = completion
            }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let timedOut = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        let timedOutID = await nextSnapshotRequest(from: &evaluationRequests, expectedCount: 1)
        await assertBridgeError(timedOut, equals: .timedOut)
        try XCTUnwrap(completions[timedOutID])(evaluationFailure())
        await Task.yield()
        XCTAssertNil(bridge.lastError)

        let cancelled = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        let cancelledID = await nextSnapshotRequest(from: &evaluationRequests, expectedCount: 2)
        cancelled.cancel()
        await assertBridgeError(cancelled, equals: .cancelled)
        try XCTUnwrap(completions[cancelledID])(evaluationFailure())
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testLateCompositeEvaluationErrorsAfterSuccessAndTearDownAreIgnored() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var outgoing: [NativeToEditorEnvelope] = []
        var completions: [UUID: (Error?) -> Void] = [:]
        let bridge = EditorBridge(
            session: session,
            javaScriptEvaluationObserver: { requestID, completion in
                completions[requestID] = completion
            },
            outgoingMessageObserver: { envelope in
                if envelope.type == .requestComposite { outgoing.append(envelope) }
            }
        )

        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let succeeded = Task { @MainActor in try await bridge.requestComposite() }
        let succeededEnvelope = try await nextRequest(from: &outgoing, expectedCount: 1)
        bridge.receive(data: try compositeChunk(
            requestID: succeededEnvelope.requestId,
            payloadRequestID: succeededEnvelope.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        bridge.receive(data: try compositeCompleted(requestID: succeededEnvelope.requestId))
        let transfer = try await succeeded.value
        transfer.discard()
        try XCTUnwrap(completions[succeededEnvelope.requestId])(evaluationFailure())
        await Task.yield()
        XCTAssertNil(bridge.lastError)

        let tornDown = Task { @MainActor in try await bridge.requestComposite() }
        let tornDownEnvelope = try await nextRequest(from: &outgoing, expectedCount: 2)
        bridge.tearDown()
        await assertBridgeError(tornDown, equals: .cancelled)
        try XCTUnwrap(completions[tornDownEnvelope.requestId])(evaluationFailure())
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testLoadTimeoutPreservesNativeProjectAndExactRetrySucceeds()
        async throws
    {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(10),
            outgoingMessageObserver: { outgoing.append($0) }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        let failedLoad = try bridge.load(project: project)
        let failedEnvelope = try XCTUnwrap(outgoing.last)
        do {
            try await failedLoad.wait()
            XCTFail("Unacknowledged load must time out")
        } catch {
            XCTAssertEqual(
                error as? EditorBridgeError,
                .timedOut
            )
        }

        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(
            session.sourcePNG(
                for: project.manifest.documentId
            ),
            project.originalPNG
        )

        let retriedLoad = try bridge.load(project: project)
        let retryEnvelope = try XCTUnwrap(outgoing.last)
        XCTAssertNotEqual(
            retryEnvelope.requestId,
            failedEnvelope.requestId
        )
        bridge.receive(
            data: try annotationSnapshot(
                requestID: retryEnvelope.requestId
            )
        )

        try await retriedLoad.wait()
        XCTAssertEqual(
            session.project?.manifest.documentId,
            project.manifest.documentId
        )

        bridge.receive(
            data: try annotationSnapshot(
                requestID: failedEnvelope.requestId
            )
        )
        XCTAssertEqual(
            session.project?.manifest.documentId,
            project.manifest.documentId
        )
    }

    func testMalformedCorrelatedLoadAcknowledgementFailsAndPreservesNativeBytes() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            outgoingMessageObserver: { outgoing.append($0) }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        try bridge.load(project: project)
        let load = try XCTUnwrap(outgoing.last)
        bridge.receive(data: try EditorToNativeEnvelope(
            requestId: load.requestId,
            type: .annotationSnapshot,
            payload: .object([:])
        ).encodedData())
        await Task.yield()

        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(
            bridge.lastProtocolError,
            .malformedMessage
        )
    }

    func testInvalidCorrelatedLoadDocumentFailsAndPreservesNativeBytes() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            outgoingMessageObserver: { outgoing.append($0) }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        try bridge.load(project: project)
        let load = try XCTUnwrap(outgoing.last)
        bridge.receive(data: try annotationSnapshot(
            requestID: load.requestId,
            sourcePixelWidth: 3
        ))
        await Task.yield()

        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(bridge.lastError, .invalidDocument)
    }

    func testSupersedingLoadCancelsOnlyTheOldDeadlineAndTheAcceptedLoadCancelsItsOwn() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(60),
            outgoingMessageObserver: { envelope in
                if envelope.type == .loadDocument { outgoing.append(envelope) }
            }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let first = validProject()
        let second = validProject()

        try bridge.load(project: first)
        let firstLoad = try XCTUnwrap(outgoing.last)
        try await Task.sleep(for: .milliseconds(40))
        try bridge.load(project: second)
        let secondLoad = try XCTUnwrap(outgoing.last)
        bridge.receive(data: try annotationSnapshot(requestID: firstLoad.requestId))
        await Task.yield()
        XCTAssertNil(bridge.lastError)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertNil(session.sourcePNG(for: first.manifest.documentId))
        XCTAssertEqual(session.sourcePNG(for: second.manifest.documentId), second.originalPNG)
        XCTAssertNil(bridge.lastError)

        bridge.receive(data: try annotationSnapshot(requestID: secondLoad.requestId))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(session.project?.manifest.documentId, second.manifest.documentId)
        XCTAssertNil(bridge.lastError)
    }

    func testLateLoadAcknowledgementAfterTimeoutIsIgnored() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(10),
            outgoingMessageObserver: { envelope in
                if envelope.type == .loadDocument { outgoing.append(envelope) }
            }
        )
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        try bridge.load(project: project)
        let load = try XCTUnwrap(outgoing.last)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(bridge.lastError, .timedOut)

        bridge.receive(data: try annotationSnapshot(requestID: load.requestId))
        await Task.yield()
        XCTAssertEqual(bridge.lastError, .timedOut)
        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )
        bridge.tearDown()
    }

    func testTearDownCancelsLoadDeadlineAndPreservesNativeBytes() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(10),
            outgoingMessageObserver: { envelope in
                if envelope.type == .loadDocument { outgoing.append(envelope) }
            }
        )
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        let operation = try bridge.load(project: project)
        let load = try XCTUnwrap(outgoing.last)
        bridge.tearDown()
        do {
            try await operation.wait()
            XCTFail("Tear down must cancel the pending load")
        } catch {
            XCTAssertEqual(
                error as? EditorBridgeError,
                .cancelled
            )
        }
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(bridge.lastError)
        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )
        bridge.receive(data: try annotationSnapshot(requestID: load.requestId))
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testSnapshotDispatchFailureUsesTheSameCleanupPathAsOtherTerminals() async throws {
        let session = DocumentSession()
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            annotationSnapshotRequestObserver: { _ in throw EditorBridgeError.invalidMessage }
        ) { _ in }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        await assertBridgeError(
            Task { @MainActor in try await bridge.requestAnnotationSnapshot() },
            equals: .invalidMessage
        )
    }

    func testSnapshotWithoutReplyEndsAtTheConfiguredDeadline() async throws {
        let session = DocumentSession()
        var snapshotRequests: [UUID] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(10),
            annotationSnapshotRequestObserver: { snapshotRequests.append($0) }
        ) { _ in }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        _ = await nextSnapshotRequest(from: &snapshotRequests, expectedCount: 1)

        await assertBridgeError(request, equals: .timedOut)
    }

    func testMalformedCorrelatedSnapshotResumesItsRequestImmediately() async throws {
        let session = DocumentSession()
        var snapshotRequests: [UUID] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            annotationSnapshotRequestObserver: { snapshotRequests.append($0) }
        ) { _ in }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        let requestID = await nextSnapshotRequest(from: &snapshotRequests, expectedCount: 1)
        bridge.receive(data: try EditorToNativeEnvelope(
            requestId: requestID,
            type: .annotationSnapshot,
            payload: .object([:])
        ).encodedData())

        await assertProtocolError(
            request,
            equals: .malformedMessage
        )
    }

    func testSnapshotReplyUsingAnActiveCompositeIDFailsTheCompositeImmediately() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(20),
            outgoingMessageObserver: { envelope in
                if envelope.type == .requestComposite { requests.append(envelope) }
            }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestComposite() }
        let envelope = try await nextRequest(from: &requests, expectedCount: 1)
        bridge.receive(data: try annotationSnapshot(requestID: envelope.requestId))

        await assertBridgeError(
            request,
            equals: .invalidMessage
        )
    }

    func testCompositeReplyUsingAnActiveSnapshotIDFailsTheSnapshotImmediately() async throws {
        let session = DocumentSession()
        var snapshotRequests: [UUID] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(20),
            annotationSnapshotRequestObserver: { snapshotRequests.append($0) }
        ) { _ in }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        let requestID = await nextSnapshotRequest(from: &snapshotRequests, expectedCount: 1)
        bridge.receive(data: try compositeChunk(
            requestID: requestID,
            payloadRequestID: requestID,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))

        await assertBridgeError(
            request,
            equals: .invalidMessage
        )
    }

    func testCompositeReplyUsingAnActiveLoadIDFailsAndPreservesNativeBytes() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            outgoingMessageObserver: { outgoing.append($0) }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        try bridge.load(project: project)
        let load = try XCTUnwrap(outgoing.last)
        bridge.receive(data: try compositeChunk(
            requestID: load.requestId,
            payloadRequestID: load.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))

        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )
        XCTAssertEqual(bridge.lastError, .invalidMessage)
    }

    func testMalformedBridgeErrorFailsAnActiveSnapshotImmediately() async throws {
        let session = DocumentSession()
        var snapshotRequests: [UUID] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(20),
            annotationSnapshotRequestObserver: { snapshotRequests.append($0) }
        ) { _ in }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        let requestID = await nextSnapshotRequest(from: &snapshotRequests, expectedCount: 1)
        bridge.receive(data: try malformedBridgeError(requestID: requestID))

        await assertProtocolError(
            request,
            equals: .malformedMessage
        )
    }

    func testMalformedBridgeErrorFailsAnActiveCompositeImmediately() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(20),
            outgoingMessageObserver: { outgoing.append($0) }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestComposite() }
        let composite = try await nextRequest(from: &outgoing, expectedCount: 1)
        bridge.receive(data: try malformedBridgeError(requestID: composite.requestId))

        await assertProtocolError(
            request,
            equals: .malformedMessage
        )
    }

    func testMalformedBridgeErrorFailsAnActiveLoadAndUnknownIDIsIgnored() async throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { outgoing.append($0) }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let project = validProject()

        bridge.receive(data: try malformedBridgeError(requestID: UUID()))
        XCTAssertNil(bridge.lastError)
        XCTAssertEqual(
            bridge.lastProtocolError,
            .malformedMessage
        )

        try bridge.load(project: project)
        let load = try XCTUnwrap(outgoing.last)
        bridge.receive(data: try malformedBridgeError(requestID: load.requestId))

        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )
        XCTAssertEqual(
            bridge.lastProtocolError,
            .malformedMessage
        )
    }

    func testCallerCancellationResumesSnapshotRequestExactlyOnce() async throws {
        let session = DocumentSession()
        var snapshotRequests: [UUID] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            annotationSnapshotRequestObserver: { snapshotRequests.append($0) }
        ) { _ in }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestAnnotationSnapshot() }
        let requestID = await nextSnapshotRequest(from: &snapshotRequests, expectedCount: 1)
        request.cancel()
        await assertBridgeError(request, equals: .cancelled)

        bridge.receive(data: try annotationSnapshot(requestID: requestID))
        await Task.yield()
        XCTAssertNil(bridge.lastError)
        bridge.receive(data: try malformedBridgeError(requestID: requestID))
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testLateCompositeReplyAfterCancellationIsIgnored() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { envelope in
            if envelope.type == .requestComposite { requests.append(envelope) }
        }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let envelope = try await nextRequest(from: &requests, expectedCount: 1)
        request.cancel()
        await assertBridgeError(request, equals: .cancelled)

        bridge.receive(data: try compositeChunk(
            requestID: envelope.requestId,
            payloadRequestID: envelope.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testCompositeDeadlineDiscardsItsPartialTransfer() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .milliseconds(10),
            outgoingMessageObserver: { envelope in
                if envelope.type == .requestComposite { requests.append(envelope) }
            }
        )
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let request = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let envelope = try await nextRequest(from: &requests, expectedCount: 1)
        bridge.receive(data: try compositeChunk(
            requestID: envelope.requestId,
            payloadRequestID: envelope.requestId,
            index: 0,
            total: 2,
            base64: "AA=="
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path).count, 1)

        await assertBridgeError(request, equals: .timedOut)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path), [])
    }

    func testCallerCancellationAndTearDownDiscardPartialCompositeTransfers() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            requestTimeout: .seconds(1),
            outgoingMessageObserver: { envelope in
                if envelope.type == .requestComposite { requests.append(envelope) }
            }
        )
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let cancelled = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let cancelledEnvelope = try await nextRequest(from: &requests, expectedCount: 1)
        bridge.receive(data: try compositeChunk(
            requestID: cancelledEnvelope.requestId,
            payloadRequestID: cancelledEnvelope.requestId,
            index: 0,
            total: 2,
            base64: "AA=="
        ))
        cancelled.cancel()
        await assertBridgeError(cancelled, equals: .cancelled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path), [])

        let tornDown = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let tornDownEnvelope = try await nextRequest(from: &requests, expectedCount: 2)
        bridge.receive(data: try compositeChunk(
            requestID: tornDownEnvelope.requestId,
            payloadRequestID: tornDownEnvelope.requestId,
            index: 0,
            total: 2,
            base64: "AA=="
        ))
        bridge.tearDown()

        await assertBridgeError(tornDown, equals: .cancelled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path), [])
        bridge.receive(data: try compositeChunk(
            requestID: tornDownEnvelope.requestId,
            payloadRequestID: tornDownEnvelope.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        await Task.yield()
        XCTAssertNil(bridge.lastError)
    }

    func testCorrelatedMismatchedChunkFailsOnlyItsRequestAndAllowsTheNextRequest() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { envelope in
            if envelope.type == .requestComposite { requests.append(envelope) }
        }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let rejected = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let rejectedRequest = try await nextRequest(from: &requests, expectedCount: 1)
        bridge.receive(data: try compositeChunk(
            requestID: rejectedRequest.requestId,
            payloadRequestID: UUID(),
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        await assertInvalidMessage(rejected)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path), [])

        let accepted = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let acceptedRequest = try await nextRequest(from: &requests, expectedCount: 2)
        bridge.receive(data: try compositeChunk(
            requestID: acceptedRequest.requestId,
            payloadRequestID: acceptedRequest.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        bridge.receive(data: try compositeCompleted(requestID: acceptedRequest.requestId))

        let transfer = try await accepted.value
        XCTAssertEqual(try PNGMetadata.read(from: transfer.finish()), PNGMetadata(pixelWidth: 2, pixelHeight: 2))
        transfer.discard()
    }

    func testOutOfOrderOrMalformedChunkCleansUpBeforeTheNextRequest() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { envelope in
            if envelope.type == .requestComposite { requests.append(envelope) }
        }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let rejected = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let rejectedRequest = try await nextRequest(from: &requests, expectedCount: 1)
        bridge.receive(data: try compositeChunk(
            requestID: rejectedRequest.requestId,
            payloadRequestID: rejectedRequest.requestId,
            index: 0,
            total: 2,
            base64: "AA=="
        ))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path).count, 1)
        bridge.receive(data: try compositeChunk(
            requestID: rejectedRequest.requestId,
            payloadRequestID: rejectedRequest.requestId,
            index: 0,
            total: 2,
            base64: "AA=="
        ))
        await assertFailure(rejected)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path), [])

        let accepted = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let acceptedRequest = try await nextRequest(from: &requests, expectedCount: 2)
        bridge.receive(data: try compositeChunk(
            requestID: acceptedRequest.requestId,
            payloadRequestID: acceptedRequest.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        bridge.receive(data: try compositeCompleted(requestID: acceptedRequest.requestId))
        let transfer = try await accepted.value
        transfer.discard()
    }

    func testPrematureCompletionFailsThePendingRequestAndDoesNotPoisonTheNextRequest() async throws {
        let session = DocumentSession()
        try session.open(project: validProject())
        var requests: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { envelope in
            if envelope.type == .requestComposite { requests.append(envelope) }
        }
        defer { bridge.tearDown() }
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())

        let rejected = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let rejectedRequest = try await nextRequest(from: &requests, expectedCount: 1)
        bridge.receive(data: try compositeCompleted(requestID: rejectedRequest.requestId))
        await assertInvalidMessage(rejected)

        let accepted = Task { @MainActor in try await bridge.requestComposite(destinationDirectory: temporaryDirectory) }
        let acceptedRequest = try await nextRequest(from: &requests, expectedCount: 2)
        bridge.receive(data: try compositeChunk(
            requestID: acceptedRequest.requestId,
            payloadRequestID: acceptedRequest.requestId,
            index: 0,
            total: 1,
            base64: ProjectFixtures.pngData.base64EncodedString()
        ))
        bridge.receive(data: try compositeCompleted(requestID: acceptedRequest.requestId))
        let transfer = try await accepted.value
        transfer.discard()
    }

    private func nextRequest(from requests: inout [NativeToEditorEnvelope], expectedCount: Int) async throws -> NativeToEditorEnvelope {
        while requests.count < expectedCount { await Task.yield() }
        return try XCTUnwrap(requests.last)
    }

    private func nextSnapshotRequest(from requests: inout [UUID], expectedCount: Int) async -> UUID {
        while requests.count < expectedCount { await Task.yield() }
        return requests[expectedCount - 1]
    }

    private func evaluationFailure() -> Error {
        NSError(domain: "MyShottr.EditorBridgeEvaluation", code: 1)
    }

    private func assertBridgeError<Value>(_ task: Task<Value, Error>, equals expected: EditorBridgeError) async {
        let result = await task.result
        guard case let .failure(error) = result else { return XCTFail("Expected bridge request to fail") }
        XCTAssertEqual(error as? EditorBridgeError, expected)
    }

    private func assertProtocolError<Value>(
        _ task: Task<Value, Error>,
        equals expected: EditorBridgeEnvelopeError
    ) async {
        let result = await task.result
        guard case let .failure(error) = result else {
            return XCTFail(
                "Expected bridge request to fail"
            )
        }
        XCTAssertEqual(
            error as? EditorBridgeEnvelopeError,
            expected
        )
    }

    private func assertInvalidMessage(_ task: Task<CompositeTransfer, Error>) async {
        let result = await task.result
        guard case let .failure(error) = result else { return XCTFail("Expected composite request to fail") }
        XCTAssertEqual(error as? EditorBridgeError, .invalidMessage)
    }

    private func assertFailure(_ task: Task<CompositeTransfer, Error>) async {
        let result = await task.result
        guard case .failure = result else { return XCTFail("Expected composite request to fail") }
    }

    private func compositeChunk(
        requestID: UUID,
        payloadRequestID: UUID,
        index: Int,
        total: Int,
        base64: String
    ) throws -> Data {
        try EditorToNativeEnvelope(
            requestId: requestID,
            type: .compositeChunk,
            payload: .object([
                "requestId": .string(payloadRequestID.uuidString),
                "index": .number(Double(index)),
                "total": .number(Double(total)),
                "dataBase64": .string(base64),
            ])
        ).encodedData()
    }

    private func annotationSnapshot(requestID: UUID, sourcePixelWidth: Int = 2) throws -> Data {
        let project = validProject()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: project.annotationJSON) as? [String: Any]
        )
        object["sourcePixelWidth"] = sourcePixelWidth
        let document = try JSONDecoder().decode(
            BridgeJSONValue.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        return try EditorToNativeEnvelope(
            requestId: requestID,
            type: .annotationSnapshot,
            payload: .object(["document": document])
        ).encodedData()
    }

    private func compositeCompleted(requestID: UUID) throws -> Data {
        try EditorToNativeEnvelope(
            requestId: requestID,
            type: .compositeCompleted,
            payload: .object(["requestId": .string(requestID.uuidString)])
        ).encodedData()
    }

    private func malformedBridgeError(requestID: UUID) throws -> Data {
        try EditorToNativeEnvelope(
            requestId: requestID,
            type: .bridgeError,
            payload: .object([:])
        ).encodedData()
    }

    private func validProject() -> MyShottrProject {
        let manifest = ProjectManifest(
            formatVersion: 1,
            documentId: UUID(),
            createdAt: .now,
            updatedAt: .now,
            sourcePixelWidth: 2,
            sourcePixelHeight: 2,
            sourceKind: .screenRegion
        )
        let annotationJSON = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 3,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [],
            "presentation": ["type": "none"],
            "defaults": [
                "color": "#1677FF",
                "strokeWidth": 4,
                "textSize": 24,
                "roughness": 1,
                "opacity": 1,
                "rectangleFillColor": NSNull(),
                "highlighterOpacity": 0.5,
            ],
        ])
        return MyShottrProject(manifest: manifest, originalPNG: ProjectFixtures.pngData, annotationJSON: annotationJSON)
    }
}
