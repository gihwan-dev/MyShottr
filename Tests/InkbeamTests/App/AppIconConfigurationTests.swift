import AppKit
import XCTest
@testable import MyShottr

final class AppIconConfigurationTests: XCTestCase {
    func testBuiltAppUsesInkbeamAppIconAndStatusBarIcon() {
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            "AppIcon"
        )
        XCTAssertEqual(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
            "AppIcon"
        )
        XCTAssertNotNil(NSImage(named: "StatusBarIcon"))
    }
}
