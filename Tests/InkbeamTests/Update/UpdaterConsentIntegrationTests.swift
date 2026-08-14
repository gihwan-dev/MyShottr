import Foundation
import XCTest
@testable import Inkbeam

@MainActor
final class UpdaterConsentIntegrationTests: XCTestCase {
    func testApprovalOnSecondLaunchIsTheFirstTimeAutomaticFeedRequestCanOccur() {
        let profile = IsolatedUpdaterProfile()
        var currentTime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let server = RequestCountingServer()
        let harness = SparkleAutomaticCheckLifecycleHarness(
            defaults: profile.defaults,
            now: { currentTime },
            server: server
        )

        XCTAssertFalse(harness.launch())
        XCTAssertEqual(server.requests, [])

        XCTAssertTrue(harness.launch())
        XCTAssertEqual(server.requests, [])

        harness.approveAutomaticChecks()
        XCTAssertEqual(
            server.requests,
            [
                UpdaterRequestRecord(
                    method: "GET",
                    timestamp: currentTime,
                    path: "/inkbeam/appcast.xml"
                ),
            ]
        )

        XCTAssertFalse(harness.launch())
        currentTime.addTimeInterval(86_399)
        XCTAssertFalse(harness.launch())
        XCTAssertEqual(server.requests.count, 1)

        currentTime.addTimeInterval(1)
        XCTAssertFalse(harness.launch())
        XCTAssertEqual(server.requests.count, 2)
    }

    func testDecliningOnSecondLaunchKeepsAutomaticRequestsDisabledLater() {
        let profile = IsolatedUpdaterProfile()
        var currentTime = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let server = RequestCountingServer()
        let harness = SparkleAutomaticCheckLifecycleHarness(
            defaults: profile.defaults,
            now: { currentTime },
            server: server
        )

        XCTAssertFalse(harness.launch())
        XCTAssertTrue(harness.launch())
        harness.declineAutomaticChecks()

        currentTime.addTimeInterval(86_400)
        XCTAssertFalse(harness.launch())
        XCTAssertEqual(server.requests, [])
    }
}

private final class IsolatedUpdaterProfile {
    let defaults: UserDefaults
    private let suiteName = "InkbeamTests.UpdaterConsent.\(UUID().uuidString)"

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
