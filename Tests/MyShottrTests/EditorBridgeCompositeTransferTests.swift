import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class EditorBridgeCompositeTransferTests: TemporaryDirectoryTestCase {
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
