import XCTest
@testable import MyShottr

final class DisplayGeometryTests: XCTestCase {
    func testRetinaPointRectConvertsToPixelRect() {
        XCTAssertEqual(
            DisplayGeometry.pixelRect(for: CaptureFixtures.retinaSelection),
            CGRect(x: 200, y: 1404, width: 600, height: 400)
        )
    }

    func testRetinaPointRectConvertsToScreenCaptureLogicalRect() {
        XCTAssertEqual(
            DisplayGeometry.sourceRect(for: CaptureFixtures.retinaSelection),
            CGRect(x: 100, y: 702, width: 300, height: 200)
        )
    }

    func testGlobalRectOnNegativeOriginDisplayBecomesLocal() {
        let global = CGRect(x: -1820, y: 100, width: 500, height: 400)

        XCTAssertEqual(
            DisplayGeometry.localRect(fromGlobalAppKitRect: global, on: CaptureFixtures.leftDisplay),
            CGRect(x: 100, y: 100, width: 500, height: 400)
        )
    }

    func testClampNeverAllowsSelectionOutsideDisplay() {
        let rect = CGRect(x: -10, y: 900, width: 200, height: 200)

        XCTAssertEqual(
            DisplayGeometry.clamp(rect, to: CaptureFixtures.retinaDisplay),
            CGRect(x: 0, y: 782, width: 200, height: 200)
        )
    }

    func testPixelRectRoundsOutwardToIntegralPixels() {
        let selection = RegionSelection(
            display: CaptureFixtures.retinaDisplay,
            rectInDisplayPoints: CGRect(x: 100.25, y: 80.25, width: 300.5, height: 200.5)
        )

        XCTAssertEqual(
            DisplayGeometry.pixelRect(for: selection),
            CGRect(x: 200, y: 1402, width: 602, height: 402)
        )
    }

    func testClampBoundsOversizedSelectionToDisplay() {
        let rect = CGRect(x: -20, y: -40, width: 2_000, height: 2_000)

        XCTAssertEqual(
            DisplayGeometry.clamp(rect, to: CaptureFixtures.retinaDisplay),
            CGRect(x: 0, y: 0, width: 1512, height: 982)
        )
    }
}
