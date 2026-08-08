import Foundation
import XCTest
@testable import Inkbeam

final class EditorBridgeEnvelopeTests: XCTestCase {
    func testPreferencesMessagesAcceptOnlyValidatedPayloads() throws {
        let makeEnvelope: ([String: Any]) throws -> Data = { payload in
            try JSONSerialization.data(withJSONObject: [
                "protocolVersion": 1,
                "requestId": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                "type": "editorPreferencesChanged",
                "payload": payload,
            ])
        }
        let validDefaults: [String: Any] = [
            "color": "#FF4D4F",
            "strokeWidth": 8,
            "textSize": 36,
            "roughness": 2,
            "opacity": 0.75,
            "rectangleFillColor": NSNull(),
            "highlighterOpacity": 0.25,
        ]
        let validPayload: [String: Any] = [
            "tool": "rectangle",
            "defaults": validDefaults,
        ]

        XCTAssertNoThrow(
            try EditorToNativeEnvelope.decode(
                from: makeEnvelope(validPayload)
            )
        )
        var linePayload = validPayload
        linePayload["tool"] = "line"
        XCTAssertNoThrow(try EditorToNativeEnvelope.decode(
            from: makeEnvelope(linePayload)
        ))

        var missingDefault = validDefaults
        missingDefault.removeValue(forKey: "rectangleFillColor")
        var extraDefault = validDefaults
        extraDefault["extra"] = true

        for defaults in [
            replacing(validDefaults, key: "color", value: "#FFFFFF"),
            replacing(validDefaults, key: "strokeWidth", value: 3),
            replacing(validDefaults, key: "textSize", value: 12),
            replacing(validDefaults, key: "roughness", value: 3),
            replacing(validDefaults, key: "opacity", value: 0.6),
            missingDefault,
            extraDefault,
            replacing(
                validDefaults,
                key: "rectangleFillColor",
                value: "#FFFFFF"
            ),
            replacing(validDefaults, key: "rectangleFillColor", value: 42),
            replacing(
                validDefaults,
                key: "highlighterOpacity",
                value: "0.5"
            ),
            replacing(validDefaults, key: "highlighterOpacity", value: 0.75),
        ] {
            XCTAssertThrowsError(
                try EditorToNativeEnvelope.decode(
                    from: makeEnvelope([
                        "tool": "rectangle",
                        "defaults": defaults,
                    ])
                )
            )
        }

        XCTAssertThrowsError(
            try EditorToNativeEnvelope.decode(
                from: makeEnvelope([
                    "tool": "unknown",
                    "defaults": validDefaults,
                ])
            )
        )
        XCTAssertThrowsError(
            try EditorToNativeEnvelope.decode(
                from: makeEnvelope([
                    "tool": "rectangle",
                    "defaults": validDefaults,
                    "extra": true,
                ])
            )
        )
    }

    @MainActor
    func testAcceptsAValidLineElement() throws {
        let session = DocumentSession()
        var document = validDocument()
        document["elements"] = [[
            "id": "line-1", "type": "line", "x": 10, "y": 20,
            "width": 80, "height": 40, "rotation": 0, "opacity": 1,
            "zIndex": 0, "seed": 99,
            "points": [["x": 10, "y": 20], ["x": 90, "y": 60]],
            "strokeColor": "#1677FF", "strokeWidth": 4, "roughness": 1,
        ]]

        XCTAssertNoThrow(try session.open(project: try project(annotationDocument: document)))
        XCTAssertTrue(session.isOpen)
    }

    func testDecodesV1EditorReadyFixture() throws {
        let fixture = Data("""
        {
          "protocolVersion": 1,
          "requestId": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "type": "editorReady",
          "payload": {}
        }
        """.utf8)

        let envelope = try EditorToNativeEnvelope.decode(from: fixture)

        XCTAssertEqual(envelope.protocolVersion, 1)
        XCTAssertEqual(envelope.requestId.uuidString, "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        XCTAssertEqual(envelope.type, .editorReady)
        XCTAssertEqual(envelope.payload, .object([:]))
    }

    func testHistoryStateChangedAcceptsOnlyExactBooleanKeys() throws {
        let valid = try bridgeEnvelopeData(
            type: "historyStateChanged",
            payload: ["canUndo": true, "canRedo": false]
        )
        let envelope = try EditorToNativeEnvelope.decode(from: valid)

        XCTAssertEqual(envelope.protocolVersion, 1)
        XCTAssertEqual(envelope.type, .historyStateChanged)
        XCTAssertEqual(
            envelope.payload,
            .object(["canUndo": .bool(true), "canRedo": .bool(false)])
        )

        for payload: [String: Any] in [
            ["canRedo": false],
            ["canUndo": true],
            ["canUndo": "true", "canRedo": false],
            ["canUndo": true, "canRedo": 0],
            ["canUndo": true, "canRedo": false, "operationId": UUID().uuidString],
        ] {
            XCTAssertThrowsError(
                try EditorToNativeEnvelope.decode(
                    from: bridgeEnvelopeData(
                        type: "historyStateChanged",
                        payload: payload
                    )
                )
            )
        }
    }

    func testPerformHistoryActionAcceptsOnlyUndoRedoWithExactKeys()
        throws
    {
        for action in ["undo", "redo"] {
            let envelope = try NativeToEditorEnvelope.decode(
                from: bridgeEnvelopeData(
                    type: "performHistoryAction",
                    payload: ["action": action]
                )
            )
            XCTAssertEqual(envelope.type, .performHistoryAction)
        }

        for payload: [String: Any] in [
            [:],
            ["action": "revert"],
            ["action": "undo", "operationId": UUID().uuidString],
        ] {
            XCTAssertThrowsError(
                try NativeToEditorEnvelope.decode(
                    from: bridgeEnvelopeData(
                        type: "performHistoryAction",
                        payload: payload
                    )
                )
            )
        }
        XCTAssertThrowsError(
            try NativeToEditorEnvelope.decode(
                from: bridgeEnvelopeData(
                    type: "performHistoryAction",
                    payload: ["action": "undo"],
                    extraEnvelopeFields: ["extra": true]
                )
            )
        )
    }

    func testPerformHistoryActionRejectsInvalidOutboundPayloadsAtConstructionAndEncoding()
        throws
    {
        for payload: [String: Any] in [
            [:],
            ["action": "revert"],
            ["action": "undo", "operationId": UUID().uuidString],
        ] {
            try assertNativeOutboundPayloadRejected(
                type: .performHistoryAction,
                payload: payload
            )
        }
    }

    func testTypedHistoryActionFactoryBuildsExactValidatedEnvelopes()
        throws
    {
        let requestIDs = [UUID(), UUID()]
        let cases: [(EditorHistoryAction, BridgeJSONValue)] = [
            (.undo, .object(["action": .string("undo")])),
            (.redo, .object(["action": .string("redo")])),
        ]

        for ((action, expectedPayload), requestID) in zip(
            cases,
            requestIDs
        ) {
            let envelope = try NativeToEditorEnvelope.historyAction(
                action,
                requestId: requestID
            )

            XCTAssertEqual(envelope.requestId, requestID)
            XCTAssertEqual(envelope.type, .performHistoryAction)
            XCTAssertEqual(envelope.payload, expectedPayload)
            let decoded = try NativeToEditorEnvelope.decode(
                from: envelope.encodedData()
            )
            XCTAssertEqual(decoded.requestId, requestID)
            XCTAssertEqual(decoded.type, .performHistoryAction)
            XCTAssertEqual(decoded.payload, expectedPayload)
        }
    }

    func testSetAppearanceAcceptsOnlyLightDarkWithExactKeys() throws {
        for colorScheme in ["light", "dark"] {
            let envelope = try NativeToEditorEnvelope.decode(
                from: bridgeEnvelopeData(
                    type: "setAppearance",
                    payload: ["colorScheme": colorScheme]
                )
            )

            XCTAssertEqual(envelope.type, .setAppearance)
            XCTAssertEqual(
                envelope.payload,
                .object(["colorScheme": .string(colorScheme)])
            )
        }

        for payload: [String: Any] in [
            [:],
            ["colorScheme": "system"],
            ["colorScheme": 1],
            ["colorScheme": "dark", "extra": true],
        ] {
            XCTAssertThrowsError(
                try NativeToEditorEnvelope.decode(
                    from: bridgeEnvelopeData(
                        type: "setAppearance",
                        payload: payload
                    )
                )
            )
        }
    }

    func testSetAppearanceRejectsInvalidOutboundPayloadsAtConstructionAndEncoding()
        throws
    {
        for payload: [String: Any] in [
            [:],
            ["colorScheme": "system"],
            ["colorScheme": 1],
            ["colorScheme": "light", "extra": true],
        ] {
            try assertNativeOutboundPayloadRejected(
                type: .setAppearance,
                payload: payload
            )
        }
    }

    func testTypedSetAppearanceFactoryBuildsExactValidatedEnvelopes()
        throws
    {
        for colorScheme in [
            EditorAppearanceColorScheme.light,
            .dark,
        ] {
            let requestID = UUID()
            let envelope = try NativeToEditorEnvelope.setAppearance(
                colorScheme,
                requestId: requestID
            )

            XCTAssertEqual(envelope.requestId, requestID)
            XCTAssertEqual(envelope.type, .setAppearance)
            XCTAssertEqual(
                envelope.payload,
                .object([
                    "colorScheme": .string(colorScheme.rawValue),
                ])
            )
            let decoded = try NativeToEditorEnvelope.decode(
                from: envelope.encodedData()
            )
            XCTAssertEqual(decoded.requestId, requestID)
            XCTAssertEqual(decoded.type, .setAppearance)
            XCTAssertEqual(decoded.payload, envelope.payload)
        }
    }

    func testOperationStatusAcceptsOnlyTheExactOperationPhaseMatrix()
        throws
    {
        let requestID = UUID()
        let validPayloads: [[String: Any]] = [
            ["operation": "save", "phase": "started"],
            ["operation": "export", "phase": "started"],
            ["operation": "save", "phase": "completed"],
            ["operation": "save", "phase": "superseded"],
            [
                "operation": "export",
                "phase": "completed",
                "displayName": "Capture.png",
            ],
            ["operation": "save", "phase": "cancelled"],
            ["operation": "export", "phase": "cancelled"],
            ["operation": "save", "phase": "failed"],
            ["operation": "export", "phase": "failed"],
        ]

        for payload in validPayloads {
            let envelope = try NativeToEditorEnvelope.decode(
                from: bridgeEnvelopeData(
                    requestID: requestID,
                    type: "operationStatus",
                    payload: payload
                )
            )
            XCTAssertEqual(envelope.requestId, requestID)
            XCTAssertEqual(envelope.type, .operationStatus)
            guard case let .object(decodedPayload) = envelope.payload else {
                return XCTFail("Expected an operation status object")
            }
            XCTAssertNil(decodedPayload["requestId"])
            XCTAssertNil(decodedPayload["operationId"])
        }

        let invalidPayloads: [[String: Any]] = [
            ["phase": "started"],
            ["operation": "save"],
            ["operation": "print", "phase": "started"],
            ["operation": "save", "phase": "queued"],
            ["operation": "export", "phase": "superseded"],
            [
                "operation": "save",
                "phase": "completed",
                "displayName": "Capture.inkbeam",
            ],
            ["operation": "export", "phase": "completed"],
            [
                "operation": "export",
                "phase": "completed",
                "displayName": 7,
            ],
            [
                "operation": "save",
                "phase": "started",
                "displayName": "Capture.inkbeam",
            ],
            [
                "operation": "export",
                "phase": "started",
                "displayName": "Capture.png",
            ],
            [
                "operation": "save",
                "phase": "cancelled",
                "displayName": "Capture.inkbeam",
            ],
            [
                "operation": "export",
                "phase": "cancelled",
                "displayName": "Capture.png",
            ],
            [
                "operation": "save",
                "phase": "failed",
                "displayName": "Capture.inkbeam",
            ],
            [
                "operation": "export",
                "phase": "failed",
                "displayName": "Capture.png",
            ],
            [
                "operation": "save",
                "phase": "started",
                "operationId": requestID.uuidString,
            ],
            [
                "operation": "export",
                "phase": "completed",
                "displayName": "Capture.png",
                "extra": true,
            ],
        ]

        for payload in invalidPayloads {
            XCTAssertThrowsError(
                try NativeToEditorEnvelope.decode(
                    from: bridgeEnvelopeData(
                        requestID: requestID,
                        type: "operationStatus",
                        payload: payload
                    )
                )
            )
        }
    }

    func testOperationStatusRejectsInvalidOutboundMatrixAtConstructionAndEncoding()
        throws
    {
        let requestID = UUID()
        let invalidPayloads: [[String: Any]] = [
            ["phase": "started"],
            ["operation": "save"],
            ["operation": "print", "phase": "started"],
            ["operation": "save", "phase": "queued"],
            ["operation": "export", "phase": "superseded"],
            [
                "operation": "save",
                "phase": "completed",
                "displayName": "Capture.inkbeam",
            ],
            ["operation": "export", "phase": "completed"],
            [
                "operation": "export",
                "phase": "completed",
                "displayName": 7,
            ],
            [
                "operation": "save",
                "phase": "started",
                "displayName": "Capture.inkbeam",
            ],
            [
                "operation": "export",
                "phase": "started",
                "displayName": "Capture.png",
            ],
            [
                "operation": "save",
                "phase": "cancelled",
                "displayName": "Capture.inkbeam",
            ],
            [
                "operation": "export",
                "phase": "cancelled",
                "displayName": "Capture.png",
            ],
            [
                "operation": "save",
                "phase": "failed",
                "displayName": "Capture.inkbeam",
            ],
            [
                "operation": "export",
                "phase": "failed",
                "displayName": "Capture.png",
            ],
            [
                "operation": "save",
                "phase": "started",
                "operationId": requestID.uuidString,
            ],
            [
                "operation": "export",
                "phase": "completed",
                "displayName": "Capture.png",
                "extra": true,
            ],
        ]

        for payload in invalidPayloads {
            try assertNativeOutboundPayloadRejected(
                type: .operationStatus,
                payload: payload
            )
        }
    }

    func testTypedOperationStatusFactoryRetainsCallerIDAndExactPayloads()
        throws
    {
        let requestID = UUID()
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

        for (status, expectedPayload) in cases {
            let envelope = try NativeToEditorEnvelope.operationStatus(
                requestId: requestID,
                status: status
            )

            XCTAssertEqual(envelope.requestId, requestID)
            XCTAssertEqual(envelope.type, .operationStatus)
            XCTAssertEqual(envelope.payload, expectedPayload)
            let decoded = try NativeToEditorEnvelope.decode(
                from: envelope.encodedData()
            )
            XCTAssertEqual(decoded.requestId, requestID)
            XCTAssertEqual(decoded.type, .operationStatus)
            XCTAssertEqual(decoded.payload, expectedPayload)
        }
    }

    func testBridgeDomainTypesExposeOnlyApprovedHistoryAndOutputStates() {
        XCTAssertEqual(
            EditorHistoryState(canUndo: true, canRedo: false),
            EditorHistoryState(canUndo: true, canRedo: false)
        )
        XCTAssertEqual(EditorHistoryAction(rawValue: "undo"), .undo)
        XCTAssertEqual(EditorHistoryAction(rawValue: "redo"), .redo)
        XCTAssertEqual(EditorOutputOperation(rawValue: "save"), .save)
        XCTAssertEqual(EditorOutputOperation(rawValue: "export"), .export)
        XCTAssertEqual(
            [
                EditorOperationStatus.started(.save),
                .started(.export),
                .saveCompleted,
                .saveSuperseded,
                .exportCompleted(displayName: "Capture.png"),
                .cancelled(.save),
                .cancelled(.export),
                .failed(.save),
                .failed(.export),
            ],
            [
                .started(.save),
                .started(.export),
                .saveCompleted,
                .saveSuperseded,
                .exportCompleted(displayName: "Capture.png"),
                .cancelled(.save),
                .cancelled(.export),
                .failed(.save),
                .failed(.export),
            ]
        )
    }

    func testRejectsUnsupportedVersionUnknownTypeMissingRequestIDAndOversizedPayload() {
        let invalidMessages = [
            "{\"protocolVersion\":2,\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"type\":\"editorReady\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"type\":\"futureMessage\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"type\":\"editorReady\",\"payload\":{}}",
            "{\"protocolVersion\":1,\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"type\":\"editorReady\",\"payload\":{},\"extra\":true}",
            "{\"protocolVersion\":1,\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"type\":\"editorReady\",\"payload\":{\"extra\":true}}",
        ]

        for message in invalidMessages {
            XCTAssertThrowsError(try EditorToNativeEnvelope.decode(from: Data(message.utf8)))
        }

        let oversized = "{\"protocolVersion\":1,\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"type\":\"editorReady\",\"payload\":{\"contents\":\"" + String(repeating: "a", count: (8 * 1024 * 1024) + 1) + "\"}}"
        XCTAssertThrowsError(try EditorToNativeEnvelope.decode(from: Data(oversized.utf8)))
    }

    @MainActor
    func testRejectsUnknownElementsWithoutOpeningTheDocument() throws {
        let session = DocumentSession()
        var document = validDocument()
        var element = try XCTUnwrap(
            (document["elements"] as? [[String: Any]])?.first
        )
        element["type"] = "video"
        document["elements"] = [element]
        let project = try project(annotationDocument: document)

        XCTAssertThrowsError(try session.open(project: project)) {
            XCTAssertEqual($0 as? DocumentSessionError, .invalidDocument)
        }
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.project)
    }

    @MainActor
    func testRejectsDimensionMismatchWithoutInstallingAnyElements() throws {
        let session = DocumentSession()
        var document = validDocument()
        document["sourcePixelWidth"] = 3
        let project = try project(annotationDocument: document)

        XCTAssertThrowsError(try session.open(project: project)) {
            XCTAssertEqual($0 as? DocumentSessionError, .invalidDocument)
        }
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.project)
    }

    func testAnnotationSnapshotUsesCurrentDocumentValidator()
        throws
    {
        let valid = validDocument()
        let validEnvelope = try EditorToNativeEnvelope(
            type: .annotationSnapshot,
            payload: .object([
                "document": try annotationValue(valid),
            ])
        ).encodedData()
        XCTAssertNoThrow(
            try EditorToNativeEnvelope.decode(from: validEnvelope)
        )

        var invalid = valid
        var defaults = try XCTUnwrap(
            invalid["defaults"] as? [String: Any]
        )
        defaults["rectangleFillColor"] = "#FFFFFF"
        invalid["defaults"] = defaults
        let invalidEnvelope = try EditorToNativeEnvelope(
            type: .annotationSnapshot,
            payload: .object([
                "document": try annotationValue(invalid),
            ])
        ).encodedData()

        XCTAssertThrowsError(
            try EditorToNativeEnvelope.decode(from: invalidEnvelope)
        )
    }

    @MainActor
    func testNativeSessionOwnsLoadBeforeItsCorrelatedSnapshotIsAccepted()
        throws
    {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { outgoing.append($0) }
        let project = try project(annotationDocument: validDocument())

        try bridge.load(project: project)
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(
            session.sourcePNG(for: project.manifest.documentId),
            project.originalPNG
        )

        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let load = try XCTUnwrap(outgoing.last)
        XCTAssertEqual(load.type, .loadDocument)
        XCTAssertEqual(
            sourceImageURL(from: load),
            "inkbeam-editor://editor/document/\(project.manifest.documentId.uuidString)/original.png"
        )

        let wrongSnapshot = try EditorToNativeEnvelope(
            requestId: UUID(),
            type: .annotationSnapshot,
            payload: .object(["document": try annotationValue(validDocument())])
        )
        bridge.receive(data: try wrongSnapshot.encodedData())
        XCTAssertTrue(session.isOpen)

        let acceptedSnapshot = try EditorToNativeEnvelope(
            requestId: load.requestId,
            type: .annotationSnapshot,
            payload: .object(["document": try annotationValue(validDocument())])
        )
        bridge.receive(data: try acceptedSnapshot.encodedData())
        XCTAssertTrue(session.isOpen)
    }

    @MainActor
    func testBridgeErrorForPendingLoadPreservesTheNativeDocument()
        async throws
    {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { outgoing.append($0) }
        let project = try project(
            annotationDocument: validDocument()
        )

        let operation = try bridge.load(project: project)
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let load = try XCTUnwrap(outgoing.last)
        let error = try EditorToNativeEnvelope(
            requestId: load.requestId,
            type: .bridgeError,
            payload: .object(["code": .string("INVALID_DOCUMENT"), "message": .string("Rejected")])
        )

        bridge.receive(data: try error.encodedData())
        do {
            try await operation.wait()
            XCTFail("Rejected editor load must fail its operation")
        } catch {
            XCTAssertEqual(
                error as? EditorBridgeError,
                .invalidDocument
            )
        }
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(
            session.sourcePNG(
                for: loadDocumentID(from: load)
            ),
            project.originalPNG
        )
    }

    @MainActor
    func testProtocolFailuresReachProductionHandlerWithoutCollapsing() {
        let bridge = EditorBridge(session: DocumentSession())
        var reportedErrors: [EditorBridgeEnvelopeError] = []
        bridge.onProtocolError = {
            reportedErrors.append($0)
        }

        bridge.receive(data: Data("{}".utf8))
        bridge.receive(
            data: Data("""
            {
              "protocolVersion": 9,
              "requestId": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
              "type": "editorReady",
              "payload": {}
            }
            """.utf8)
        )
        let oversized =
            "{\"protocolVersion\":1,"
            + "\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\","
            + "\"type\":\"editorReady\",\"payload\":{\"contents\":\""
            + String(
                repeating: "a",
                count: EditorToNativeEnvelope.maxPayloadBytes + 1
            )
            + "\"}}"
        bridge.receive(data: Data(oversized.utf8))

        XCTAssertEqual(
            reportedErrors,
            [
                .malformedMessage,
                .unsupportedProtocolVersion(9),
                .payloadTooLarge,
            ]
        )
    }

    @MainActor
    func testCorrelatedMalformedSnapshotThrowsProtocolErrorOnce()
        async throws
    {
        var requestID: UUID?
        let bridge = EditorBridge(
            session: DocumentSession(),
            annotationSnapshotRequestObserver: {
                requestID = $0
            }
        )
        var reportedErrors: [EditorBridgeEnvelopeError] = []
        bridge.onProtocolError = {
            reportedErrors.append($0)
        }
        bridge.receive(
            data: try EditorToNativeEnvelope(
                type: .editorReady,
                payload: .object([:])
            ).encodedData()
        )

        let request = Task {
            try await bridge.requestAnnotationSnapshot()
        }
        await Task.yield()
        let id = try XCTUnwrap(requestID)
        bridge.receive(
            data: Data("""
            {
              "protocolVersion": 1,
              "requestId": "\(id.uuidString)",
              "type": "annotationSnapshot",
              "payload": {}
            }
            """.utf8)
        )

        do {
            _ = try await request.value
            XCTFail("Malformed correlated reply must fail the request")
        } catch {
            XCTAssertEqual(
                error as? EditorBridgeEnvelopeError,
                .malformedMessage
            )
        }
        XCTAssertTrue(reportedErrors.isEmpty)
    }

    @MainActor
    func testDeferredLoadFailurePreservesNativeSourceBytes()
        async throws
    {
        let session = DocumentSession()
        let bridge = EditorBridge(session: session)
        var project = try project(annotationDocument: validDocument())
        project.annotationJSON = Data("not json".utf8)

        let operation = try bridge.load(project: project)
        XCTAssertEqual(session.sourcePNG(for: project.manifest.documentId), project.originalPNG)

        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        do {
            try await operation.wait()
            XCTFail("Invalid load payload must fail its operation")
        } catch {
            XCTAssertEqual(
                error as? EditorBridgeError,
                .invalidDocument
            )
        }
        XCTAssertTrue(session.isOpen)
        XCTAssertEqual(
            session.sourcePNG(
                for: project.manifest.documentId
            ),
            project.originalPNG
        )
    }

    private func project(annotationDocument: [String: Any]) throws -> InkbeamProject {
        let documentID = UUID()
        return InkbeamProject(
            manifest: ProjectManifest(
                formatVersion: 1,
                documentId: documentID,
                createdAt: .now,
                updatedAt: .now,
                sourcePixelWidth: 2,
                sourcePixelHeight: 2,
                sourceKind: .screenRegion
            ),
            originalPNG: Data([0x89, 0x50, 0x4E, 0x47]),
            annotationJSON: try JSONSerialization.data(withJSONObject: annotationDocument)
        )
    }

    private func annotationValue(_ document: [String: Any]) throws -> BridgeJSONValue {
        try JSONDecoder().decode(BridgeJSONValue.self, from: JSONSerialization.data(withJSONObject: document))
    }

    private func bridgeEnvelopeData(
        requestID: UUID = UUID(
            uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        )!,
        type: String,
        payload: [String: Any],
        extraEnvelopeFields: [String: Any] = [:]
    ) throws -> Data {
        var envelope: [String: Any] = [
            "protocolVersion": 1,
            "requestId": requestID.uuidString,
            "type": type,
            "payload": payload,
        ]
        envelope.merge(extraEnvelopeFields) { _, replacement in replacement }
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private func assertNativeOutboundPayloadRejected(
        type: NativeToEditorMessageType,
        payload: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let payloadValue = try JSONDecoder().decode(
            BridgeJSONValue.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertThrowsError(
            try NativeToEditorEnvelope(
                type: type,
                payload: payloadValue
            ),
            file: file,
            line: line
        )

        let decodedWithoutStrictBoundary = try JSONDecoder().decode(
            NativeToEditorEnvelope.self,
            from: bridgeEnvelopeData(
                type: type.rawValue,
                payload: payload
            )
        )
        XCTAssertThrowsError(
            try decodedWithoutStrictBoundary.encodedData(),
            file: file,
            line: line
        )
    }

    private func loadDocumentID(from envelope: NativeToEditorEnvelope) -> UUID {
        guard case let .object(payload) = envelope.payload,
              case let .string(documentID)? = payload["documentId"],
              let documentID = UUID(uuidString: documentID)
        else { fatalError("Invalid load fixture") }
        return documentID
    }

    private func sourceImageURL(from envelope: NativeToEditorEnvelope) -> String {
        guard case let .object(payload) = envelope.payload,
              case let .string(sourceImageURL)? = payload["sourceImageURL"]
        else { fatalError("Invalid load fixture") }
        return sourceImageURL
    }

    private func replacing(
        _ dictionary: [String: Any],
        key: String,
        value: Any
    ) -> [String: Any] {
        var result = dictionary
        result[key] = value
        return result
    }

    private func validDocument() -> [String: Any] {
        [
            "schemaVersion": 3,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [[
                "id": "rectangle-1", "type": "rectangle", "x": 0, "y": 0,
                "width": 1, "height": 1, "rotation": 0, "opacity": 1,
                "zIndex": 0, "seed": 1, "strokeColor": "#1677FF", "strokeWidth": 4,
                "fillColor": NSNull(), "roughness": 1,
            ]],
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
        ]
    }
}
