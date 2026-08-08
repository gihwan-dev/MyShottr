import Foundation
import XCTest
@testable import Inkbeam

@MainActor
final class EditorBridgeStateCommandTests: XCTestCase {
    func testDocumentChangedInvokesOneTypedCallbackAfterSessionMutation()
        throws
    {
        let session = DocumentSession()
        try session.open(project: ProjectFixtures.project(text: "Changed"))
        let bridge = EditorBridge(session: session)
        var callbackCount = 0
        bridge.onDocumentChanged = { callbackCount += 1 }

        bridge.receive(
            data: try EditorToNativeEnvelope(
                type: .documentChanged,
                payload: .object([:])
            ).encodedData()
        )

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(session.modificationRevision, 1)
        XCTAssertTrue(session.isModified)
        XCTAssertNil(bridge.lastError)
        bridge.tearDown()
    }

    func testDocumentChangedDoesNotInvokeCallbackWhenSessionMutationFails()
        throws
    {
        let bridge = EditorBridge(session: DocumentSession())
        var callbackCount = 0
        bridge.onDocumentChanged = { callbackCount += 1 }

        bridge.receive(
            data: try EditorToNativeEnvelope(
                type: .documentChanged,
                payload: .object([:])
            ).encodedData()
        )

        XCTAssertEqual(callbackCount, 0)
        XCTAssertEqual(bridge.lastError, .invalidDocument)
        bridge.tearDown()
    }

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

    func testMalformedHistoryStateReportsOneProtocolErrorAndNoTypedCallback()
        throws
    {
        let bridge = EditorBridge(session: DocumentSession())
        var received: [EditorHistoryState] = []
        var protocolErrors: [EditorBridgeEnvelopeError] = []
        bridge.onHistoryStateChanged = { received.append($0) }
        bridge.onProtocolError = { protocolErrors.append($0) }

        bridge.receive(
            data: try EditorToNativeEnvelope(
                type: .historyStateChanged,
                payload: .object([
                    "canUndo": .bool(true),
                ])
            ).encodedData()
        )

        XCTAssertEqual(protocolErrors, [.malformedMessage])
        XCTAssertTrue(received.isEmpty)
        XCTAssertEqual(bridge.lastProtocolError, .malformedMessage)
        XCTAssertNil(bridge.lastError)
        bridge.tearDown()
    }

    func testPerformHistoryActionEmitsOneStrictEnvelopeForEachAction()
        throws
    {
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: DocumentSession(),
            outgoingMessageObserver: { outgoing.append($0) }
        )

        bridge.performHistoryAction(.undo)
        bridge.performHistoryAction(.redo)

        XCTAssertEqual(outgoing.count, 2)
        XCTAssertEqual(outgoing.map(\.type), [
            .performHistoryAction,
            .performHistoryAction,
        ])
        XCTAssertEqual(outgoing.map(\.payload), [
            .object(["action": .string("undo")]),
            .object(["action": .string("redo")]),
        ])
        for envelope in outgoing {
            XCTAssertNoThrow(
                try NativeToEditorEnvelope.decode(
                    from: envelope.encodedData()
                )
            )
        }
        bridge.tearDown()
    }

    func testSetAppearanceEmitsOneStrictEnvelopeForEachScheme() throws {
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: DocumentSession(),
            outgoingMessageObserver: { outgoing.append($0) }
        )

        bridge.setAppearance(.light)
        bridge.setAppearance(.dark)

        XCTAssertEqual(outgoing.count, 2)
        XCTAssertEqual(outgoing.map(\.type), [
            .setAppearance,
            .setAppearance,
        ])
        XCTAssertEqual(outgoing.map(\.payload), [
            .object(["colorScheme": .string("light")]),
            .object(["colorScheme": .string("dark")]),
        ])
        for envelope in outgoing {
            XCTAssertNoThrow(
                try NativeToEditorEnvelope.decode(
                    from: envelope.encodedData()
                )
            )
        }
        bridge.tearDown()
    }

    func testOperationStatusRetainsCallerIDAndExactPayloadForEveryVariant()
        throws
    {
        let requestID = UUID()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: DocumentSession(),
            outgoingMessageObserver: { outgoing.append($0) }
        )
        let cases: [(EditorOperationStatus, BridgeJSONValue)] = [
            (
                .started(.save),
                .object([
                    "operation": .string("save"),
                    "phase": .string("started"),
                ])
            ),
            (
                .started(.export),
                .object([
                    "operation": .string("export"),
                    "phase": .string("started"),
                ])
            ),
            (
                .saveCompleted,
                .object([
                    "operation": .string("save"),
                    "phase": .string("completed"),
                ])
            ),
            (
                .saveSuperseded,
                .object([
                    "operation": .string("save"),
                    "phase": .string("superseded"),
                ])
            ),
            (
                .exportCompleted(displayName: "Capture.png"),
                .object([
                    "operation": .string("export"),
                    "phase": .string("completed"),
                    "displayName": .string("Capture.png"),
                ])
            ),
            (
                .cancelled(.save),
                .object([
                    "operation": .string("save"),
                    "phase": .string("cancelled"),
                ])
            ),
            (
                .cancelled(.export),
                .object([
                    "operation": .string("export"),
                    "phase": .string("cancelled"),
                ])
            ),
            (
                .failed(.save),
                .object([
                    "operation": .string("save"),
                    "phase": .string("failed"),
                ])
            ),
            (
                .failed(.export),
                .object([
                    "operation": .string("export"),
                    "phase": .string("failed"),
                ])
            ),
        ]

        for (status, _) in cases {
            bridge.sendOperationStatus(
                requestID: requestID,
                status: status
            )
        }

        XCTAssertEqual(outgoing.count, cases.count)
        for (envelope, (_, expectedPayload)) in zip(outgoing, cases) {
            XCTAssertEqual(envelope.requestId, requestID)
            XCTAssertEqual(envelope.type, .operationStatus)
            XCTAssertEqual(envelope.payload, expectedPayload)
            XCTAssertNoThrow(
                try NativeToEditorEnvelope.decode(
                    from: envelope.encodedData()
                )
            )
        }
        bridge.tearDown()
    }

    func testFireAndForgetEncodeFailureReportsOneUncorrelatedError() {
        let bridge = EditorBridge(
            session: DocumentSession(),
            outgoingMessageObserver: { _ in }
        )
        var errors: [EditorBridgeError] = []
        bridge.onUncorrelatedError = { errors.append($0) }

        bridge.sendOperationStatus(
            requestID: UUID(),
            status: .exportCompleted(
                displayName: String(
                    repeating: "x",
                    count: 8 * 1024 * 1024
                )
            )
        )

        XCTAssertEqual(errors, [.invalidMessage])
        bridge.tearDown()
    }

    func testFireAndForgetReadinessFailureReportsOneUncorrelatedError() {
        let bridge = EditorBridge(session: DocumentSession())
        var errors: [EditorBridgeError] = []
        bridge.onUncorrelatedError = { errors.append($0) }

        bridge.performHistoryAction(.undo)

        XCTAssertEqual(errors, [.invalidMessage])
        bridge.tearDown()
    }

    func testSynchronousFireAndForgetEvaluationFailureReportsOneUncorrelatedError() {
        let bridge = EditorBridge(
            session: DocumentSession(),
            javaScriptEvaluationObserver: { _, completion in
                completion(EditorBridgeStateCommandTestError.evaluation)
            }
        )
        var errors: [EditorBridgeError] = []
        bridge.onUncorrelatedError = { errors.append($0) }

        bridge.performHistoryAction(.redo)

        XCTAssertEqual(errors, [.invalidMessage])
        bridge.tearDown()
    }

    func testAsynchronousFireAndForgetEvaluationFailureReportsOneUncorrelatedError()
        async throws
    {
        var evaluationCompletion: ((Error?) -> Void)?
        let bridge = EditorBridge(
            session: DocumentSession(),
            javaScriptEvaluationObserver: { _, completion in
                evaluationCompletion = completion
            }
        )
        var errors: [EditorBridgeError] = []
        bridge.onUncorrelatedError = { errors.append($0) }

        bridge.sendOperationStatus(
            requestID: UUID(),
            status: .started(.save)
        )
        try XCTUnwrap(evaluationCompletion)(
            EditorBridgeStateCommandTestError.evaluation
        )
        await Task.yield()

        XCTAssertEqual(errors, [.invalidMessage])
        bridge.tearDown()
    }
}

private enum EditorBridgeStateCommandTestError: Error {
    case evaluation
}
