import XCTest
@testable import MyShottr

final class AppConfigurationTests: XCTestCase {
    func testBundleDeclaresScreenCaptureReasonAndProjectType() throws {
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        XCTAssertFalse(try XCTUnwrap(info["NSScreenCaptureUsageDescription"] as? String).isEmpty)

        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let extensions = documentTypes
            .compactMap { $0["CFBundleTypeExtensions"] as? [String] }
            .flatMap { $0 }
        XCTAssertTrue(extensions.contains("myshottr"))
    }
}
