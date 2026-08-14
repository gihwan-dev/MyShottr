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
        let userApplicationsURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Inkbeam.app", isDirectory: true)

        XCTAssertEqual(
            policy.decision(
                bundleURL: userApplicationsURL,
                isWritable: true,
                isDebugBuild: false
            ),
            .eligible
        )
    }

    func testReleaseAppInExternalApplicationsDirectoryIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath:
                        "/Volumes/External/Applications/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testReleaseAppInAnotherUsersApplicationsDirectoryIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath:
                        "/Users/other/Applications/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testApplicationsPrefixWithoutDirectoryBoundaryIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath:
                        "/ApplicationsElsewhere/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testReleaseAppOutsideApplicationsIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Users/Shared/Inkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testReleaseBundleWithWrongAppNameIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Applications/NotInkbeam.app"
                ),
                isWritable: true,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testNonWritableSystemApplicationsInstallIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath: "/Applications/Inkbeam.app"
                ),
                isWritable: false,
                isDebugBuild: false
            ),
            .moveToApplications
        )
    }

    func testNonWritableUserApplicationsInstallIsRejected() {
        let userApplicationsURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("Inkbeam.app", isDirectory: true)

        XCTAssertEqual(
            policy.decision(
                bundleURL: userApplicationsURL,
                isWritable: false,
                isDebugBuild: false
            ),
            .moveToApplications
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

    func testAppTranslocationMarkerUnderApprovedRootIsRejected() {
        XCTAssertEqual(
            policy.decision(
                bundleURL: URL(
                    fileURLWithPath:
                        "/Applications/AppTranslocation/Inkbeam.app"
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
