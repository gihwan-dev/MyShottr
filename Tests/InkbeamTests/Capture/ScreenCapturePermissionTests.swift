import XCTest
@testable import Inkbeam

final class ScreenCapturePermissionTests: XCTestCase {
    func testDeniedPermissionReturnsActionableError() {
        let permission = ScreenCapturePermission(
            preflight: { false },
            request: { false }
        )

        XCTAssertThrowsError(try permission.requireAccess()) {
            XCTAssertEqual($0 as? CaptureError, .screenRecordingPermissionDenied)
        }
    }

    func testPreflightAccessSkipsPermissionRequest() throws {
        var requestCount = 0
        let permission = ScreenCapturePermission(
            preflight: { true },
            request: {
                requestCount += 1
                return false
            }
        )

        try permission.requireAccess()

        XCTAssertEqual(requestCount, 0)
    }

    func testRequireAccessRequestsPermissionOnce() throws {
        var requestCount = 0
        let permission = ScreenCapturePermission(
            preflight: { false },
            request: {
                requestCount += 1
                return true
            }
        )

        try permission.requireAccess()

        XCTAssertEqual(requestCount, 1)
    }

    func testDeniedPermissionDoesNotPerformASecondRequest() {
        var requestCount = 0
        let permission = ScreenCapturePermission(
            preflight: { false },
            request: {
                requestCount += 1
                return false
            }
        )

        XCTAssertThrowsError(try permission.requireAccess())

        XCTAssertEqual(requestCount, 1)
    }
}
