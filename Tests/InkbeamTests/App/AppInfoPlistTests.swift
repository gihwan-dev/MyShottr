import XCTest
@testable import MyShottr

final class AppInfoPlistTests: XCTestCase {
    func testBuiltAppProhibitsMultipleInstances() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "LSMultipleInstancesProhibited"
            ) as? Bool,
            true
        )
    }
}
