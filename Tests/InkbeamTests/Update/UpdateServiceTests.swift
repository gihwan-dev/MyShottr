import XCTest
@testable import Inkbeam

@MainActor
final class UpdateServiceTests: XCTestCase {
    func testStartForwardsExactlyOnceAcrossRepeatedCalls() throws {
        let controller = FakeUpdaterController()
        var events: [UpdateDiagnosticEvent] = []
        let service = UpdateService(
            controller: controller,
            configuration: try stableConfiguration(),
            diagnostics: UpdateDiagnostics {
                events.append($0)
            }
        )

        try service.start()
        try service.start()

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(events, [.started(channel: .stable)])
    }

    func testManualCheckForwardsExactlyOnce() throws {
        let controller = FakeUpdaterController()
        var events: [UpdateDiagnosticEvent] = []
        let service = UpdateService(
            controller: controller,
            configuration: try stableConfiguration(),
            diagnostics: UpdateDiagnostics {
                events.append($0)
            }
        )

        try service.start()
        try service.checkForUpdates()

        XCTAssertEqual(controller.startCount, 1)
        XCTAssertEqual(controller.manualCheckCount, 1)
        XCTAssertEqual(
            events,
            [
                .started(channel: .stable),
                .manualCheckStarted(host: .githubPages),
            ]
        )
    }

    func testManualCheckRejectsBeforeSuccessfulStart() throws {
        let controller = FakeUpdaterController()
        let service = UpdateService(
            controller: controller,
            configuration: try stableConfiguration(),
            diagnostics: .silent
        )

        XCTAssertThrowsError(try service.checkForUpdates()) { error in
            XCTAssertEqual(error as? UpdateServiceError, .notStarted)
        }
        XCTAssertEqual(controller.manualCheckCount, 0)
    }

    func testCanCheckRequiresStartAndControllerReadiness() throws {
        let controller = FakeUpdaterController()
        let service = UpdateService(
            controller: controller,
            configuration: try stableConfiguration(),
            diagnostics: .silent
        )

        controller.canCheckForUpdates = true
        XCTAssertFalse(service.canCheckForUpdates)

        try service.start()
        XCTAssertTrue(service.canCheckForUpdates)

        controller.canCheckForUpdates = false
        XCTAssertFalse(service.canCheckForUpdates)
    }

    private func stableConfiguration() throws -> UpdateConfiguration {
        try UpdateConfiguration(
            info: [
                "SUFeedURL":
                    "https://gihwan-dev.github.io/inkbeam/appcast.xml",
                "SUPublicEDKey":
                    "xr1xG+wKx4sHmGeuF5bkgFjjqaZEJ6pMbAJoiHCuUUE=",
                "InkbeamReleaseChannel": "Stable",
            ]
        )
    }
}

@MainActor
private final class FakeUpdaterController: StandardUpdaterControlling {
    var canCheckForUpdates = false
    private(set) var startCount = 0
    private(set) var manualCheckCount = 0

    func startUpdater() {
        startCount += 1
    }

    func checkForUpdates(_ sender: Any?) {
        manualCheckCount += 1
    }
}
