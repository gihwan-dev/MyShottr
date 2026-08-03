import XCTest
@testable import MyShottr

final class CaptureArtifactTests: XCTestCase {
    func testArtifactDerivesPixelDimensionsWithoutSourceSpecificLogic() throws {
        let artifact = try CaptureArtifact(
            id: ProjectFixtures.documentID,
            sourceKind: .chromeVisibleViewport,
            pngData: ProjectFixtures.pngData,
            scale: nil
        )

        XCTAssertEqual(artifact.pixelWidth, 2)
        XCTAssertEqual(artifact.pixelHeight, 2)
        XCTAssertNil(artifact.scale)
    }

    func testArtifactsWithTheSameCaptureContractAreEqual() throws {
        let first = try CaptureArtifact(
            id: ProjectFixtures.documentID,
            sourceKind: .chromeVisibleViewport,
            pngData: ProjectFixtures.pngData,
            scale: nil
        )
        let second = try CaptureArtifact(
            id: ProjectFixtures.documentID,
            sourceKind: .chromeVisibleViewport,
            pngData: ProjectFixtures.pngData,
            scale: nil
        )

        XCTAssertEqual(first, second)
    }

    func testSharedExtensionContractConformersAreSendable() {
        let preferences = StubPreferences(.approvedDefaults)

        requireSendable(preferences)
        requireSendable(NewProjectFactory(preferences: preferences))
    }

    private func requireSendable<Value: Sendable>(_ value: Value) {}
}
