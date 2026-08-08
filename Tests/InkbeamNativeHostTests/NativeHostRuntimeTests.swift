import Foundation
import XCTest

final class NativeHostRuntimeTests: XCTestCase {
    func testTestEnvironmentUsesOnlyExactInkbeamNames() {
        XCTAssertEqual(
            NativeHostTestEnvironment.inboxPathKey,
            "INKBEAM_NATIVE_HOST_TEST_INBOX"
        )
        XCTAssertEqual(
            NativeHostTestEnvironment.appPathKey,
            "INKBEAM_NATIVE_HOST_TEST_APP_PATH"
        )
        XCTAssertEqual(
            NativeHostTestEnvironment.notificationKey,
            "INKBEAM_NATIVE_HOST_TEST_NOTIFICATION"
        )
    }

    func testOldEnvironmentNamesDoNotCreateTestConfiguration() {
        let oldPrefix = "MY" + "SHOTTR_NATIVE_HOST_TEST_"
        XCTAssertNil(
            NativeHostRuntime.testConfiguration(
                environment: [
                    oldPrefix + "INBOX": "/tmp/legacy-inbox",
                    oldPrefix + "APP_PATH": "/tmp/Legacy.app",
                    oldPrefix + "NOTIFICATION": "legacy.captureReady",
                    "INKBEAM_NATIVE_HOST_TEST_" + "ACTIVATION_FAILURE": "1",
                ]
            )
        )
    }
}
