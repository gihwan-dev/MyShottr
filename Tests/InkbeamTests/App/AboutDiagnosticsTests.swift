import XCTest
@testable import Inkbeam

final class AboutDiagnosticsTests: XCTestCase {
    func testStableMetadataRendersReadOnlyVersionAndChannel() throws {
        let diagnostics = try AboutDiagnostics(
            info: [
                "CFBundleShortVersionString": "0.2.0",
                "CFBundleVersion": "4",
                "InkbeamReleaseChannel": "Stable",
            ]
        )

        XCTAssertEqual(diagnostics.channel, .stable)
        XCTAssertEqual(
            diagnostics.displayVersion,
            "0.2.0 (4) · Stable"
        )
    }

    func testBetaMetadataRendersReadOnlyVersionAndChannel() throws {
        let diagnostics = try AboutDiagnostics(
            info: [
                "CFBundleShortVersionString": "0.2.0",
                "CFBundleVersion": "2",
                "InkbeamReleaseChannel": "Release Candidate",
            ]
        )

        XCTAssertEqual(diagnostics.channel, .beta)
        XCTAssertEqual(
            diagnostics.displayVersion,
            "0.2.0 (2) · Release Candidate"
        )
    }

    func testMissingMetadataFailsClosed() {
        for key in [
            "CFBundleShortVersionString",
            "CFBundleVersion",
            "InkbeamReleaseChannel",
        ] {
            var info = validInfo
            info.removeValue(forKey: key)

            XCTAssertThrowsError(try AboutDiagnostics(info: info)) {
                error in
                XCTAssertEqual(
                    error as? AboutDiagnosticsError,
                    .missingValue(key)
                )
            }
        }
    }

    func testUnknownChannelFailsClosed() {
        var info = validInfo
        info["InkbeamReleaseChannel"] = "Nightly"

        XCTAssertThrowsError(try AboutDiagnostics(info: info)) { error in
            XCTAssertEqual(
                error as? AboutDiagnosticsError,
                .invalidChannel
            )
        }
    }

    private var validInfo: [String: Any] {
        [
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "4",
            "InkbeamReleaseChannel": "Stable",
        ]
    }
}
