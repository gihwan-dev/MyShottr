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
}
