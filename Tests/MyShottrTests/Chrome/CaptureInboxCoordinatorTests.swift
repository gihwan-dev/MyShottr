import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class CaptureInboxCoordinatorTests: XCTestCase {
    private let captureDate = Date(timeIntervalSince1970: 1_745_678_901)

    func testConsumeBuildsChromeViewportProjectThroughSharedFactory() throws {
        let inbox = StubPendingCaptureInbox()
        let factory = SpyChromeNewProjectFactory()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: factory,
            windows: windows,
            now: { self.captureDate }
        )

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(
            factory.requests,
            [
                .init(
                    id: ChromeFixtures.captureID,
                    sourceKind: .chromeVisibleViewport,
                    scale: nil,
                    now: captureDate
                ),
            ]
        )
        let project = try XCTUnwrap(windows.presentedProjects.first)
        XCTAssertEqual(project.manifest.documentId, ChromeFixtures.captureID)
        XCTAssertEqual(project.manifest.sourceKind, .chromeVisibleViewport)
        XCTAssertNil(project.manifest.sourceScale)
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: project.annotationJSON
            ) as? [String: Any]
        )
        XCTAssertEqual(document["schemaVersion"] as? Int, 2)
        XCTAssertEqual(
            document["presentation"] as? [String: String],
            ["type": "none"]
        )
    }

    func testLaunchScanConsumesEveryPendingCaptureInOrder() throws {
        let first = StagedCapture(
            id: ChromeFixtures.secondCaptureID,
            pngURL: URL(fileURLWithPath: "/inbox/first.png")
        )
        let second = StagedCapture(
            id: ChromeFixtures.captureID,
            pngURL: URL(fileURLWithPath: "/inbox/second.png")
        )
        let inbox = StubPendingCaptureInbox(
            pending: [first, second],
            dataByID: [
                first.id: ProjectFixtures.pngData,
                second.id: ProjectFixtures.pngData,
            ]
        )
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        try coordinator.consumePendingCaptures()

        XCTAssertEqual(inbox.consumedIDs, [first.id, second.id])
        XCTAssertEqual(
            windows.presentedProjects.map(\.manifest.documentId),
            [first.id, second.id]
        )
    }

    func testCaptureReadyNotificationConsumesOnlyCanonicalUUIDObject() throws {
        let inbox = StubPendingCaptureInbox()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        coordinator.handleCaptureReadyNotification(
            Notification(
                name: CaptureInboxCoordinator.captureReadyNotification,
                object: ChromeFixtures.captureID.uuidString
            )
        )

        XCTAssertEqual(inbox.consumedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(windows.presentedProjects.count, 1)
    }

    func testCaptureReadyNotificationRejectsPathsAndUserInfo() {
        let inbox = StubPendingCaptureInbox()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        coordinator.handleCaptureReadyNotification(
            Notification(
                name: CaptureInboxCoordinator.captureReadyNotification,
                object: "/tmp/\(ChromeFixtures.captureID.uuidString).png"
            )
        )
        coordinator.handleCaptureReadyNotification(
            Notification(
                name: CaptureInboxCoordinator.captureReadyNotification,
                object: ChromeFixtures.captureID.uuidString.lowercased()
            )
        )
        coordinator.handleCaptureReadyNotification(
            Notification(
                name: CaptureInboxCoordinator.captureReadyNotification,
                object: ChromeFixtures.captureID.uuidString,
                userInfo: ["path": "/tmp/capture.png"]
            )
        )

        XCTAssertTrue(inbox.consumedIDs.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }
}
