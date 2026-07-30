import Foundation
import XCTest
@testable import MyShottr

final class EditorDocumentMigratorTests: XCTestCase {
    func testMigratesSchemaOneToSchemaTwoWithPresentationNone() throws {
        let legacy = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [],
            "defaults": ProjectFixtures.editorDefaults,
        ])

        let migrated = try EditorDocumentMigrator.migrate(legacy)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migrated) as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 2)
        XCTAssertEqual(
            (object["presentation"] as? [String: Any])?["type"] as? String,
            "none"
        )
    }

    func testRejectsSchemaThreeWithoutChangingInput() throws {
        let newer = try ProjectFixtures.annotationJSON(schemaVersion: 3)
        XCTAssertThrowsError(try EditorDocumentMigrator.migrate(newer)) {
            XCTAssertEqual($0 as? EditorDocumentMigrationError, .unsupportedVersion(3))
        }
    }
}
