import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class EditorBridgeCompositeTransferTests: TemporaryDirectoryTestCase {
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

        await assertBridgeError(request, equals: .invalidMessage)
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

        bridge.receive(data: try EditorToNativeEnvelope(
            requestId: requestID,
            type: .annotationSnapshot,
            payload: .object([:])
        ).encodedData())
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

    private func assertBridgeError<Value>(_ task: Task<Value, Error>, equals expected: EditorBridgeError) async {
        let result = await task.result
        guard case let .failure(error) = result else { return XCTFail("Expected bridge request to fail") }
        XCTAssertEqual(error as? EditorBridgeError, expected)
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

    private func compositeCompleted(requestID: UUID) throws -> Data {
        try EditorToNativeEnvelope(
            requestId: requestID,
            type: .compositeCompleted,
            payload: .object(["requestId": .string(requestID.uuidString)])
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
            "schemaVersion": 1,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [],
            "defaults": ["color": "#1677FF", "strokeWidth": 4, "textSize": 24, "roughness": 1, "opacity": 1],
        ])
        return MyShottrProject(manifest: manifest, originalPNG: ProjectFixtures.pngData, annotationJSON: annotationJSON)
    }
}
