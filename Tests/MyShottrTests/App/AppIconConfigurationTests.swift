import AppKit
import XCTest
@testable import MyShottr

final class AppIconConfigurationTests: XCTestCase {
    func testProjectConfigUsesQuickInkAppIcon() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon"))
        XCTAssertNotNil(NSImage(named: "StatusBarIcon"))
    }
}
