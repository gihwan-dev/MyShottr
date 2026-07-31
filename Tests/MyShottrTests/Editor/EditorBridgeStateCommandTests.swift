import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class EditorBridgeStateCommandTests: XCTestCase {
    func testHistoryStateChangedInvokesOneTypedCallback() throws {
        let bridge = EditorBridge(session: DocumentSession())
        var received: [EditorHistoryState] = []
        bridge.onHistoryStateChanged = { received.append($0) }

        bridge.receive(
            data: try EditorToNativeEnvelope(
                type: .historyStateChanged,
                payload: .object([
                    "canUndo": .bool(true),
                    "canRedo": .bool(false),
                ])
            ).encodedData()
        )

        XCTAssertEqual(
            received,
            [EditorHistoryState(canUndo: true, canRedo: false)]
        )
        XCTAssertNil(bridge.lastError)
        XCTAssertNil(bridge.lastProtocolError)
        bridge.tearDown()
    }

    func testHistoryStateChangedDoesNotEnterPendingRequestCorrelation()
        async throws
    {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: session,
            outgoingMessageObserver: { outgoing.append($0) }
        )
        var received: [EditorHistoryState] = []
        bridge.onHistoryStateChanged = { received.append($0) }
        let project = ProjectFixtures.project(text: "History state")

        let loadOperation = try bridge.load(project: project)
        bridge.receive(
            data: try EditorToNativeEnvelope(
                type: .editorReady,
                payload: .object([:])
            ).encodedData()
        )
        let loadRequest = try XCTUnwrap(outgoing.last)

        bridge.receive(
            data: try EditorToNativeEnvelope(
                requestId: loadRequest.requestId,
                type: .historyStateChanged,
                payload: .object([
                    "canUndo": .bool(false),
                    "canRedo": .bool(true),
                ])
            ).encodedData()
        )

        XCTAssertEqual(
            received,
            [EditorHistoryState(canUndo: false, canRedo: true)]
        )
        XCTAssertNil(bridge.lastError)

        bridge.receive(
            data: try EditorToNativeEnvelope(
                requestId: loadRequest.requestId,
                type: .annotationSnapshot,
                payload: .object([
                    "document": try JSONDecoder().decode(
                        BridgeJSONValue.self,
                        from: project.annotationJSON
                    ),
                ])
            ).encodedData()
        )
        try await loadOperation.wait()

        XCTAssertTrue(session.isOpen)
        XCTAssertNil(bridge.lastError)
        bridge.tearDown()
    }
}
