import Foundation
import XCTest
@testable import MyShottr

final class EditorBridgeEnvelopeTests: XCTestCase {
    func testPreferencesMessagesAcceptOnlyValidatedPayloads() throws {
        let valid = Data("""
        {
          "protocolVersion": 1,
          "requestId": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "type": "editorPreferencesChanged",
          "payload": {
            "tool": "arrow",
            "defaults": {
              "color": "#1677FF",
              "strokeWidth": 4,
              "textSize": 24,
              "roughness": 1,
              "opacity": 1
            }
          }
        }
        """.utf8)

        XCTAssertNoThrow(try EditorToNativeEnvelope.decode(from: valid))

        for payload in [
            "{\"tool\":\"unknown\",\"defaults\":{\"color\":\"#1677FF\",\"strokeWidth\":4,\"textSize\":24,\"roughness\":1,\"opacity\":1}}",
            "{\"tool\":\"arrow\",\"defaults\":{\"color\":\"#FFFFFF\",\"strokeWidth\":4,\"textSize\":24,\"roughness\":1,\"opacity\":1}}",
            "{\"tool\":\"arrow\",\"defaults\":{\"color\":\"#1677FF\",\"strokeWidth\":3,\"textSize\":24,\"roughness\":1,\"opacity\":1}}",
            "{\"tool\":\"arrow\",\"defaults\":{\"color\":\"#1677FF\",\"strokeWidth\":4,\"textSize\":12,\"roughness\":1,\"opacity\":1}}",
            "{\"tool\":\"arrow\",\"defaults\":{\"color\":\"#1677FF\",\"strokeWidth\":4,\"textSize\":24,\"roughness\":3,\"opacity\":1}}",
            "{\"tool\":\"arrow\",\"defaults\":{\"color\":\"#1677FF\",\"strokeWidth\":4,\"textSize\":24,\"roughness\":1,\"opacity\":0.6}}",
            "{\"tool\":\"arrow\",\"defaults\":{\"color\":\"#1677FF\",\"strokeWidth\":4,\"textSize\":24,\"roughness\":1,\"opacity\":1},\"extra\":true}",
        ] {
            let envelope = "{\"protocolVersion\":1,\"requestId\":\"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE\",\"type\":\"editorPreferencesChanged\",\"payload\":\(payload)}"
            XCTAssertThrowsError(try EditorToNativeEnvelope.decode(from: Data(envelope.utf8)))
        }
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
        let project = try project(annotationDocument: [
            "schemaVersion": 2,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [["type": "video"]],
            "presentation": ["type": "none"],
            "defaults": [:],
        ])

        XCTAssertThrowsError(try session.open(project: project)) {
            XCTAssertEqual($0 as? DocumentSessionError, .invalidDocument)
        }
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.project)
    }

    @MainActor
    func testRejectsDimensionMismatchWithoutInstallingAnyElements() throws {
        let session = DocumentSession()
        let project = try project(annotationDocument: [
            "schemaVersion": 2,
            "sourcePixelWidth": 3,
            "sourcePixelHeight": 2,
            "elements": [],
            "presentation": ["type": "none"],
            "defaults": [:],
        ])

        XCTAssertThrowsError(try session.open(project: project)) {
            XCTAssertEqual($0 as? DocumentSessionError, .invalidDocument)
        }
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.project)
    }

    @MainActor
    func testStagesLoadUntilItsCorrelatedSnapshotIsAccepted() throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { outgoing.append($0) }
        let project = try project(annotationDocument: validDocument())

        try bridge.load(project: project)
        XCTAssertFalse(session.isOpen)

        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let load = try XCTUnwrap(outgoing.last)
        XCTAssertEqual(load.type, .loadDocument)
        XCTAssertEqual(
            sourceImageURL(from: load),
            "myshottr-editor://editor/document/\(project.manifest.documentId.uuidString)/original.png"
        )

        let wrongSnapshot = try EditorToNativeEnvelope(
            requestId: UUID(),
            type: .annotationSnapshot,
            payload: .object(["document": try annotationValue(validDocument())])
        )
        bridge.receive(data: try wrongSnapshot.encodedData())
        XCTAssertFalse(session.isOpen)

        let acceptedSnapshot = try EditorToNativeEnvelope(
            requestId: load.requestId,
            type: .annotationSnapshot,
            payload: .object(["document": try annotationValue(validDocument())])
        )
        bridge.receive(data: try acceptedSnapshot.encodedData())
        XCTAssertTrue(session.isOpen)
    }

    @MainActor
    func testBridgeErrorForPendingLoadDiscardsTheStagedDocument() throws {
        let session = DocumentSession()
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(session: session) { outgoing.append($0) }

        try bridge.load(project: try project(annotationDocument: validDocument()))
        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        let load = try XCTUnwrap(outgoing.last)
        let error = try EditorToNativeEnvelope(
            requestId: load.requestId,
            type: .bridgeError,
            payload: .object(["code": .string("INVALID_DOCUMENT"), "message": .string("Rejected")])
        )

        bridge.receive(data: try error.encodedData())
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.sourcePNG(for: loadDocumentID(from: load)))
        XCTAssertEqual(bridge.lastError, .invalidDocument)
    }

    @MainActor
    func testDeferredLoadFailureDiscardsStagedSourceBytes() throws {
        let session = DocumentSession()
        let bridge = EditorBridge(session: session)
        var project = try project(annotationDocument: validDocument())
        project.annotationJSON = Data("not json".utf8)

        try bridge.load(project: project)
        XCTAssertEqual(session.sourcePNG(for: project.manifest.documentId), project.originalPNG)

        bridge.receive(data: try EditorToNativeEnvelope(type: .editorReady, payload: .object([:])).encodedData())
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.sourcePNG(for: project.manifest.documentId))
        XCTAssertEqual(bridge.lastError, .invalidDocument)
    }

    private func project(annotationDocument: [String: Any]) throws -> MyShottrProject {
        let documentID = UUID()
        return MyShottrProject(
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

    private func validDocument() -> [String: Any] {
        [
            "schemaVersion": 2,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [[
                "id": "rectangle-1", "type": "rectangle", "x": 0, "y": 0,
                "width": 1, "height": 1, "rotation": 0, "opacity": 1,
                "zIndex": 0, "seed": 1, "strokeColor": "#1677FF", "strokeWidth": 4,
                "fillColor": NSNull(), "roughness": 1,
            ]],
            "presentation": ["type": "none"],
            "defaults": ["color": "#1677FF", "strokeWidth": 4, "textSize": 24, "roughness": 1, "opacity": 1],
        ]
    }
}
