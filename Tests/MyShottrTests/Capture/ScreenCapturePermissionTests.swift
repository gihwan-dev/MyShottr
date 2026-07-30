import XCTest
@testable import MyShottr

final class ScreenCapturePermissionTests: XCTestCase {
    func testDeniedPermissionReturnsActionableError() {
        let permission = ScreenCapturePermission(
            preflight: { false },
            request: { false },
            openSettings: {}
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
            },
            openSettings: {}
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
            },
            openSettings: {}
        )

        try permission.requireAccess()

        XCTAssertEqual(requestCount, 1)
    }

    func testDeniedPermissionOpensScreenRecordingSettings() {
        var didOpenSettings = false
        let permission = ScreenCapturePermission(
            preflight: { false },
            request: { false },
            openSettings: { didOpenSettings = true }
        )

        XCTAssertThrowsError(try permission.requireAccess())

        XCTAssertTrue(didOpenSettings)
    }
}
