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

        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.committedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
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

        XCTAssertEqual(inbox.claimedIDs, [first.id, second.id])
        XCTAssertEqual(inbox.committedIDs, [first.id, second.id])
        XCTAssertEqual(inbox.cleanedIDs, [first.id, second.id])
        XCTAssertEqual(
            windows.presentedProjects.map(\.manifest.documentId),
            [first.id, second.id]
        )
    }

    func testProjectFactoryFailureLeavesClaimUncommitted() {
        let inbox = StubPendingCaptureInbox()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: ThrowingNewProjectFactory(
                error: .projectCreation
            ),
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? CapturePipelineTestError,
                .projectCreation
            )
        }
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertTrue(inbox.commitAttempts.isEmpty)
        XCTAssertTrue(inbox.cleanupAttempts.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
        XCTAssertNotNil(inbox.dataByID[ChromeFixtures.captureID])
    }

    func testWindowPresentationFailureLeavesClaimUncommitted() {
        let inbox = StubPendingCaptureInbox()
        let windows = SpyDocumentWindowPresenter()
        windows.presentationError = CapturePipelineTestError.presentation
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? CapturePipelineTestError,
                .presentation
            )
        }
        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertTrue(inbox.commitAttempts.isEmpty)
        XCTAssertTrue(inbox.cleanupAttempts.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
        XCTAssertNotNil(inbox.dataByID[ChromeFixtures.captureID])
    }

    func testCommitFailureRetriesWithoutPresentingDuplicateWindow() throws {
        let inbox = StubPendingCaptureInbox()
        inbox.commitError = ChromeFixtureError.commit
        let factory = SpyChromeNewProjectFactory()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: factory,
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? ChromeFixtureError,
                .commit
            )
        }
        inbox.commitError = nil

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(
            inbox.commitAttempts,
            [ChromeFixtures.captureID, ChromeFixtures.captureID]
        )
        XCTAssertEqual(inbox.committedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(factory.requests.count, 1)
        XCTAssertEqual(windows.presentedProjects.count, 1)
    }

    func testCleanupFailureRetriesWithoutPresentingDuplicateWindow() throws {
        let inbox = StubPendingCaptureInbox()
        inbox.cleanupError = ChromeFixtureError.cleanup
        let factory = SpyChromeNewProjectFactory()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: factory,
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? ChromeFixtureError,
                .cleanup
            )
        }
        inbox.cleanupError = nil

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.commitAttempts, [ChromeFixtures.captureID])
        XCTAssertEqual(
            inbox.cleanupAttempts,
            [ChromeFixtures.captureID, ChromeFixtures.captureID]
        )
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(factory.requests.count, 1)
        XCTAssertEqual(windows.presentedProjects.count, 1)
    }

    func testLaunchScanCleansPresentedCaptureWithoutOpeningWindow() throws {
        let inbox = StubPendingCaptureInbox()
        inbox.cleanupOnly = [
            PresentedCapture(
                id: ChromeFixtures.captureID,
                presentedURL: URL(
                    fileURLWithPath:
                        "/inbox/\(ChromeFixtures.captureID.uuidString)."
                        + "\(ChromeFixtures.stateID.uuidString).presented"
                ),
                fileDevice: 1,
                fileInode: 2
            ),
        ]
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        try coordinator.consumePendingCaptures()

        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertTrue(inbox.claimedIDs.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
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

        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.committedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(inbox.cleanedIDs, [ChromeFixtures.captureID])
        XCTAssertEqual(windows.presentedProjects.count, 1)
    }

    func testUnknownCaptureNotificationDoesNotReportError() {
        let inbox = StubPendingCaptureInbox(dataByID: [:])
        let windows = SpyDocumentWindowPresenter()
        var reportedErrors: [any Error] = []
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: { reportedErrors.append($0) }
        )

        coordinator.handleCaptureReadyNotification(
            Notification(
                name: CaptureInboxCoordinator.captureReadyNotification,
                object: ChromeFixtures.captureID.uuidString
            )
        )

        XCTAssertEqual(inbox.claimedIDs, [ChromeFixtures.captureID])
        XCTAssertTrue(reportedErrors.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    func testGenuineCaptureNotificationFailureIsReported() {
        let inbox = StubPendingCaptureInbox()
        inbox.claimErrorByID[ChromeFixtures.captureID] =
            PendingCaptureInboxError.invalidPNG
        let windows = SpyDocumentWindowPresenter()
        var reportedErrors: [any Error] = []
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: { reportedErrors.append($0) }
        )

        coordinator.handleCaptureReadyNotification(
            Notification(
                name: CaptureInboxCoordinator.captureReadyNotification,
                object: ChromeFixtures.captureID.uuidString
            )
        )

        XCTAssertEqual(
            reportedErrors.first as? PendingCaptureInboxError,
            .invalidPNG
        )
        XCTAssertTrue(windows.presentedProjects.isEmpty)
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

        XCTAssertTrue(inbox.claimedIDs.isEmpty)
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }
}
