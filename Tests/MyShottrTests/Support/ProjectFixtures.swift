import Foundation
import XCTest
@testable import MyShottr

enum ProjectFixtures {
    static let pngData = try! Data(contentsOf: fixtureURL())

    static func sampleProject() throws -> MyShottrProject {
        project(text: "Sample annotation")
    }

    static func project(text: String) -> MyShottrProject {
        let manifest = ProjectManifest(
            formatVersion: ProjectManifest.currentFormatVersion,
            documentId: UUID(uuidString: "B0B7A25D-D451-43C6-8D6C-2E27D47C89CB")!,
            createdAt: Date(timeIntervalSince1970: 1_720_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sourcePixelWidth: 2,
            sourcePixelHeight: 2,
            sourceKind: .screenRegion
        )
        let annotationJSON = try! JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "text": text,
        ])

        return MyShottrProject(
            manifest: manifest,
            originalPNG: pngData,
            annotationJSON: annotationJSON
        )
    }

    static func package(
        formatVersion: Int = 1,
        sourcePixelWidth: Int = 2
    ) throws -> URL {
        let packageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyShottrFixture-\(UUID().uuidString).myshottr", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: false)

        let project = project(text: "Fixture annotation")
        let manifest = ProjectManifest(
            formatVersion: formatVersion,
            documentId: project.manifest.documentId,
            createdAt: project.manifest.createdAt,
            updatedAt: project.manifest.updatedAt,
            sourcePixelWidth: sourcePixelWidth,
            sourcePixelHeight: project.manifest.sourcePixelHeight,
            sourceKind: project.manifest.sourceKind
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: packageURL.appendingPathComponent("manifest.json"))
        try project.originalPNG.write(to: packageURL.appendingPathComponent("original.png"))
        try project.annotationJSON.write(to: packageURL.appendingPathComponent("document.json"))

        return packageURL
    }

    private static func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: TemporaryDirectoryTestCase.self).url(
            forResource: "source-2x",
            withExtension: "png"
        ))
    }
}
