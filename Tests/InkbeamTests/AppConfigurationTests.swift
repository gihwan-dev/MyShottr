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

    func testBundleDeclaresStrictSparkleConfiguration() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertNil(info["SUEnableAutomaticChecks"])
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86_400)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
        XCTAssertEqual(info["SUEnableSystemProfiling"] as? Bool, false)
        XCTAssertEqual(info["SUEnableJavaScript"] as? Bool, false)
        XCTAssertEqual(info["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(info["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(
            info["SUSignedFeedFailureExpirationInterval"] as? Int,
            0
        )
        XCTAssertNotNil(info["SUPublicEDKey"] as? String)
        XCTAssertNotNil(
            URL(string: try XCTUnwrap(info["SUFeedURL"] as? String))
        )
        let channel = try XCTUnwrap(info["InkbeamReleaseChannel"] as? String)
        XCTAssertTrue(["Release Candidate", "Stable"].contains(channel))
    }
}
