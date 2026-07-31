import Foundation
import XCTest
@testable import MyShottr

final class EditorDocumentMigratorTests: XCTestCase {
    func testMigratesVersionOneToVersionThree() throws {
        let migrated = try EditorDocumentMigrator.migrate(
            ProjectFixtures.schemaOneAnnotationJSON()
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migrated) as? [String: Any]
        )
        let defaults = try XCTUnwrap(
            object["defaults"] as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
        XCTAssertEqual(
            (object["presentation"] as? [String: Any])?["type"] as? String,
            "none"
        )
        XCTAssertTrue(defaults["rectangleFillColor"] is NSNull)
        XCTAssertEqual(
            defaults["highlighterOpacity"] as? Double,
            0.5
        )
    }

    func testMigratesVersionTwoDefaultsToVersionThree() throws {
        let migrated = try EditorDocumentMigrator.migrate(
            ProjectFixtures.schemaTwoAnnotationJSON()
        )
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migrated) as? [String: Any]
        )
        let defaults = try XCTUnwrap(
            object["defaults"] as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, 3)
        XCTAssertTrue(defaults["rectangleFillColor"] is NSNull)
        XCTAssertEqual(
            defaults["highlighterOpacity"] as? Double,
            0.5
        )
    }

    func testPassesCurrentVersionThroughExactly() throws {
        let current = try ProjectFixtures.currentAnnotationJSON()

        XCTAssertEqual(
            try EditorDocumentMigrator.migrate(current),
            current
        )
    }

    func testRejectsVersionFour() throws {
        XCTAssertThrowsError(
            try EditorDocumentMigrator.migrate(
                ProjectFixtures.futureAnnotationJSON()
            )
        ) {
            XCTAssertEqual(
                $0 as? EditorDocumentMigrationError,
                .unsupportedVersion(4)
            )
        }
    }
}
