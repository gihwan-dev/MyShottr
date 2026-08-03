import XCTest
@testable import Inkbeam

final class AppConfigurationTests: XCTestCase {
    func testInkbeamProjectPreservesOriginalPixels() {
        let project = InkbeamProject.fixture()
        XCTAssertEqual(project.originalPNG, PNGFixture.source2x)
    }

    func testProductErrorNamesInkbeam() {
        let error = InkbeamUserFacingError.wrapping(
            CaptureError.cancelled,
            context: .capture
        )
        XCTAssertEqual(error.title, "Capture Cancelled")
    }

    func testBundleDeclaresScreenCaptureReasonAndProjectType() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertFalse(try XCTUnwrap(info["NSScreenCaptureUsageDescription"] as? String).isEmpty)

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let extensions = documentTypes
            .compactMap { $0["CFBundleTypeExtensions"] as? [String] }
            .flatMap { $0 }
        XCTAssertTrue(extensions.contains("inkbeam"))
    }
}
