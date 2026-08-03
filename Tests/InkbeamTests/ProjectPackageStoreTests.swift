import Foundation
import XCTest
@testable import MyShottr

final class ProjectPackageStoreTests: TemporaryDirectoryTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let url = temporaryDirectory.appendingPathComponent("Sample.myshottr")
        let project = try ProjectFixtures.sampleProject()

        try ProjectPackageStore().save(project, to: url)

        let loadedProject = try ProjectPackageStore().load(from: url)
        XCTAssertEqual(loadedProject, project)
        XCTAssertEqual(try annotationSchemaVersion(loadedProject.annotationJSON), 3)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: url.path).sorted(),
            ["document.json", "manifest.json", "original.png"]
        )
    }

    func testRejectsUnsupportedFormatVersion() throws {
        let url = try ProjectFixtures.package(formatVersion: 2)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
            XCTAssertEqual($0 as? ProjectPackageError, .unsupportedFormatVersion(2))
        }
    }

    func testRejectsPNGWhoseDimensionsDoNotMatchManifest() throws {
        let url = try ProjectFixtures.package(sourcePixelWidth: 99)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
            XCTAssertEqual($0 as? ProjectPackageError, .sourceDimensionsMismatch)
        }
    }

    func testRejectsSymbolicLinkPackageRoot() throws {
        let packageURL = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let symbolicLinkURL = temporaryDirectory.appendingPathComponent("Linked.myshottr")
        try FileManager.default.createSymbolicLink(at: symbolicLinkURL, withDestinationURL: packageURL)

        XCTAssertThrowsError(try ProjectPackageStore().load(from: symbolicLinkURL)) {
            XCTAssertEqual($0 as? ProjectPackageError, .notDirectoryPackage)
        }
    }

    func testRejectsUnexpectedPackageMember() throws {
        let url = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("unexpected".utf8).write(to: url.appendingPathComponent("extra.txt"))

        XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
            guard case .invalidMemberSet = $0 as? ProjectPackageError else {
                return XCTFail("Expected invalidMemberSet, got \($0)")
            }
        }
    }

    func testLoadRejectsFutureSchemaWithExplicitUnsupportedVersionError() throws {
        let url = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: url) }
        try ProjectFixtures.futureAnnotationJSON()
            .write(to: url.appendingPathComponent("document.json"))

        XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
            XCTAssertEqual($0 as? ProjectPackageError, .unsupportedAnnotationSchemaVersion(4))
        }
    }

    func testRejectsInvalidPNG() throws {
        let url = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a PNG".utf8).write(to: url.appendingPathComponent("original.png"))

        XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
            XCTAssertEqual($0 as? ProjectPackageError, .invalidPNG)
        }
    }

    func testSaveReplacesAnExistingPackage() throws {
        let url = temporaryDirectory.appendingPathComponent("Sample.myshottr")
        let initialProject = ProjectFixtures.project(text: "Initial annotation")
        let replacementProject = ProjectFixtures.project(text: "Replacement annotation")

        try ProjectPackageStore().save(initialProject, to: url)
        try ProjectPackageStore().save(replacementProject, to: url)

        XCTAssertEqual(try ProjectPackageStore().load(from: url), replacementProject)
    }

    func testLoadMigratesSchemaOneToSchemaThreeWithoutRewritingThePackage() throws {
        let packageURL = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let schemaOne = try ProjectFixtures.schemaOneAnnotationJSON()
        try schemaOne
            .write(to: packageURL.appendingPathComponent("document.json"))

        let loaded = try ProjectPackageStore().load(from: packageURL)

        XCTAssertEqual(try annotationSchemaVersion(loaded.annotationJSON), 3)
        XCTAssertEqual(
            try Data(contentsOf: packageURL.appendingPathComponent("document.json")),
            schemaOne
        )
    }

    func testLoadMigratesSchemaTwoToSchemaThreeWithoutRewritingThePackage() throws {
        let packageURL = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        let schemaTwo = try ProjectFixtures.schemaTwoAnnotationJSON()
        try schemaTwo
            .write(to: packageURL.appendingPathComponent("document.json"))

        let loaded = try ProjectPackageStore().load(from: packageURL)

        XCTAssertEqual(try annotationSchemaVersion(loaded.annotationJSON), 3)
        XCTAssertEqual(
            try Data(contentsOf: packageURL.appendingPathComponent("document.json")),
            schemaTwo
        )
    }

    func testLoadValidatesMigratedDocumentAgainstManifestDimensions()
        throws
    {
        let packageURL = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        var schemaTwo = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: ProjectFixtures.schemaTwoAnnotationJSON()
            ) as? [String: Any]
        )
        schemaTwo["sourcePixelWidth"] = 3
        try JSONSerialization.data(
            withJSONObject: schemaTwo,
            options: [.sortedKeys]
        ).write(
            to: packageURL.appendingPathComponent("document.json")
        )

        XCTAssertThrowsError(
            try ProjectPackageStore().load(from: packageURL)
        ) {
            XCTAssertEqual(
                $0 as? ProjectPackageError,
                .invalidAnnotationJSON
            )
        }
    }

    func testSaveRejectsLegacySchemasInsteadOfMigratingThem() throws {
        for (name, annotationJSON) in [
            ("SchemaOne", try ProjectFixtures.schemaOneAnnotationJSON()),
            ("SchemaTwo", try ProjectFixtures.schemaTwoAnnotationJSON()),
        ] {
            let url = temporaryDirectory
                .appendingPathComponent("\(name).myshottr")
            var project = try ProjectFixtures.sampleProject()
            project.annotationJSON = annotationJSON

            XCTAssertThrowsError(
                try ProjectPackageStore().save(project, to: url)
            ) {
                XCTAssertEqual(
                    $0 as? ProjectPackageError,
                    .invalidAnnotationJSON
                )
            }
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: url.path)
            )
        }
    }

    func testSavePreservesExactValidatedCurrentJSON() throws {
        let url = temporaryDirectory.appendingPathComponent("Exact.myshottr")
        var project = try ProjectFixtures.sampleProject()
        let object = try JSONSerialization.jsonObject(with: project.annotationJSON)
        project.annotationJSON = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted]
        )

        try ProjectPackageStore().save(project, to: url)

        XCTAssertEqual(
            try Data(contentsOf: url.appendingPathComponent("document.json")),
            project.annotationJSON
        )
    }

    private func annotationSchemaVersion(_ data: Data) throws -> Int {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["schemaVersion"] as? Int)
    }
}
