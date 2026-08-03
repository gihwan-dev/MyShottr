import Foundation
import XCTest
@testable import Inkbeam

final class NewProjectFactoryTests: XCTestCase {
    func testFactoryUsesStoredPreferencesAndPresentationNone() throws {
        let preferences = EditorPreferences(
            tool: "arrow",
            color: "#FF4D4F",
            strokeWidth: 8,
            textSize: 36,
            roughness: 2,
            opacity: 0.75,
            rectangleFillColor: nil,
            highlighterOpacity: 0.5
        )
        let factory = NewProjectFactory(preferences: StubPreferences(preferences))
        let artifact = try CaptureArtifact(
            id: ProjectFixtures.documentID,
            sourceKind: .screenRegion,
            pngData: ProjectFixtures.pngData,
            scale: 2
        )
        let project = try factory.make(
            artifact: artifact,
            now: Date(timeIntervalSince1970: 100)
        )
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: project.annotationJSON)
                as? [String: Any]
        )

        XCTAssertEqual(document["schemaVersion"] as? Int, 3)
        XCTAssertEqual((document["elements"] as? [Any])?.count, 0)
        XCTAssertEqual(
            (document["presentation"] as? [String: Any])?["type"] as? String,
            "none"
        )
        let defaults = try XCTUnwrap(
            document["defaults"] as? [String: Any]
        )
        XCTAssertEqual(
            Set(defaults.keys),
            [
                "color",
                "strokeWidth",
                "textSize",
                "roughness",
                "opacity",
                "rectangleFillColor",
                "highlighterOpacity",
            ]
        )
        XCTAssertEqual(defaults["color"] as? String, "#FF4D4F")
        XCTAssertEqual(defaults["strokeWidth"] as? Int, 8)
        XCTAssertEqual(defaults["textSize"] as? Int, 36)
        XCTAssertEqual(defaults["roughness"] as? Int, 2)
        XCTAssertEqual(defaults["opacity"] as? Double, 0.75)
        XCTAssertTrue(defaults["rectangleFillColor"] is NSNull)
        XCTAssertEqual(
            defaults["highlighterOpacity"] as? Double,
            0.5
        )
        XCTAssertNoThrow(
            try EditorDocumentValidator.validate(
                project.annotationJSON,
                expectedPixelWidth: artifact.pixelWidth,
                expectedPixelHeight: artifact.pixelHeight
            )
        )
        XCTAssertEqual(project.manifest.sourceScale, 2)
    }
}
