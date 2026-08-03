import XCTest
@testable import Inkbeam

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
