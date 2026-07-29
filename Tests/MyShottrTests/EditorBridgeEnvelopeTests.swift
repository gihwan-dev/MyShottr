import Foundation
import XCTest
@testable import MyShottr

final class EditorBridgeEnvelopeTests: XCTestCase {
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
            "schemaVersion": 1,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [["type": "video"]],
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
            "schemaVersion": 1,
            "sourcePixelWidth": 3,
            "sourcePixelHeight": 2,
            "elements": [],
            "defaults": [:],
        ])

        XCTAssertThrowsError(try session.open(project: project)) {
            XCTAssertEqual($0 as? DocumentSessionError, .invalidDocument)
        }
        XCTAssertFalse(session.isOpen)
        XCTAssertNil(session.project)
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
}
