import Foundation
import XCTest
@testable import MyShottr

enum ProjectFixtures {
    static let documentID = UUID(uuidString: "B0B7A25D-D451-43C6-8D6C-2E27D47C89CB")!
    static let pngData = try! Data(contentsOf: fixtureURL())
    private static var legacyEditorDefaults: [String: Any] {
        [
            "color": "#1677FF",
            "strokeWidth": 4,
            "textSize": 24,
            "roughness": 1,
            "opacity": 1,
        ]
    }
    private static var currentEditorDefaults: [String: Any] {
        var defaults = legacyEditorDefaults
        defaults["rectangleFillColor"] = NSNull()
        defaults["highlighterOpacity"] = 0.5
        return defaults
    }

    static func sampleProject() throws -> MyShottrProject {
        project(text: "Sample annotation")
    }

    static func project(text: String) -> MyShottrProject {
        let manifest = ProjectManifest(
            formatVersion: ProjectManifest.currentFormatVersion,
            documentId: documentID,
            createdAt: Date(timeIntervalSince1970: 1_720_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_720_000_000),
            sourcePixelWidth: 2,
            sourcePixelHeight: 2,
            sourceKind: .screenRegion
        )
        let annotationJSON = try! JSONSerialization.data(
            withJSONObject: editorDocument(text: text),
            options: [.sortedKeys]
        )

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
        var annotation = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: project.annotationJSON
            ) as? [String: Any]
        )
        annotation["sourcePixelWidth"] = sourcePixelWidth
        try JSONSerialization.data(
            withJSONObject: annotation,
            options: [.sortedKeys]
        ).write(
            to: packageURL.appendingPathComponent("document.json")
        )

        return packageURL
    }

    static func schemaOneAnnotationJSON() throws -> Data {
        var document = editorDocument(text: "Fixture annotation")
        document["schemaVersion"] = 1
        document.removeValue(forKey: "presentation")
        document["defaults"] = legacyEditorDefaults
        return try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
    }

    static func schemaTwoAnnotationJSON() throws -> Data {
        var document = editorDocument(text: "Fixture annotation")
        document["schemaVersion"] = 2
        document["defaults"] = legacyEditorDefaults
        return try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
    }

    static func currentAnnotationJSON() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: editorDocument(text: "Fixture annotation"),
            options: [.sortedKeys]
        )
    }

    static func futureAnnotationJSON(version: Int = 4) throws -> Data {
        var document = editorDocument(text: "Fixture annotation")
        document["schemaVersion"] = version
        return try JSONSerialization.data(
            withJSONObject: document,
            options: [.sortedKeys]
        )
    }

    private static func editorDocument(text: String) -> [String: Any] {
        [
            "schemaVersion": 3,
            "sourcePixelWidth": 2,
            "sourcePixelHeight": 2,
            "elements": [[
                "id": "text-1",
                "type": "text",
                "x": 0,
                "y": 0,
                "width": 0,
                "height": 0,
                "rotation": 0,
                "opacity": 1,
                "zIndex": 0,
                "seed": 1,
                "text": text,
                "color": "#1677FF",
                "fontSize": 24,
            ]],
            "presentation": ["type": "none"],
            "defaults": currentEditorDefaults,
        ]
    }

    private static func fixtureURL() throws -> URL {
        try XCTUnwrap(Bundle(for: TemporaryDirectoryTestCase.self).url(
            forResource: "source-2x",
            withExtension: "png"
        ))
    }
}
