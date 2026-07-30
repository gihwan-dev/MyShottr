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
        XCTAssertEqual(try annotationSchemaVersion(loadedProject.annotationJSON), 2)
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

    func testRejectsDocumentWithUnsupportedSchemaVersion() throws {
        let url = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"schemaVersion\":3}".utf8).write(to: url.appendingPathComponent("document.json"))

        XCTAssertThrowsError(try ProjectPackageStore().load(from: url)) {
            XCTAssertEqual($0 as? ProjectPackageError, .invalidAnnotationJSON)
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

    func testLoadsSchemaOneAsSchemaTwoAndSavesOnlySchemaTwo() throws {
        let packageURL = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: packageURL) }
        try ProjectFixtures.annotationJSON(schemaVersion: 1)
            .write(to: packageURL.appendingPathComponent("document.json"))

        let store = ProjectPackageStore()
        let loaded = try store.load(from: packageURL)
        XCTAssertEqual(try annotationSchemaVersion(loaded.annotationJSON), 2)

        let savedURL = temporaryDirectory.appendingPathComponent("Migrated.myshottr")
        try store.save(loaded, to: savedURL)
        let saved = try Data(contentsOf: savedURL.appendingPathComponent("document.json"))
        XCTAssertEqual(try annotationSchemaVersion(saved), 2)
    }

    private func annotationSchemaVersion(_ data: Data) throws -> Int {
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(object["schemaVersion"] as? Int)
    }
}
