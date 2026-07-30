import Foundation
import XCTest
@testable import MyShottr

final class NewProjectFactoryTests: XCTestCase {
    func testFactoryUsesStoredPreferencesAndPresentationNone() throws {
        let preferences = EditorPreferences(
            tool: "arrow",
            color: "#FF4D4F",
            strokeWidth: 8,
            textSize: 36,
            roughness: 2,
            opacity: 0.75
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

        XCTAssertEqual(document["schemaVersion"] as? Int, 2)
        XCTAssertEqual((document["elements"] as? [Any])?.count, 0)
        XCTAssertEqual(
            (document["presentation"] as? [String: Any])?["type"] as? String,
            "none"
        )
        XCTAssertEqual(
            (document["defaults"] as? [String: Any])?["color"] as? String,
            "#FF4D4F"
        )
        XCTAssertEqual(project.manifest.sourceScale, 2)
    }
}
