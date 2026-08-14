import Foundation
import XCTest
@testable import Inkbeam

final class InstallLocationPolicyTests: XCTestCase {
    private let policy = InstallLocationPolicy()

    func testReleaseAppInSystemApplicationsIsEligible() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Applications/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .eligible
        )
    }

    func testReleaseAppInUserApplicationsIsEligible() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Users/test/Applications/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .eligible
        )
    }

    func testReleaseAppOnDMGIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Volumes/Inkbeam/Inkbeam.app"
                ),
                isWritable: false,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testTranslocatedReleaseAppIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/private/var/folders/AppTranslocation/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testDebugBuildBypassesInstallLocationGate() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Volumes/Inkbeam/Inkbeam.app"
                ),
                isWritable: false,
                isDebugBuild: true
            ),
            .eligible
        )
    }
}
