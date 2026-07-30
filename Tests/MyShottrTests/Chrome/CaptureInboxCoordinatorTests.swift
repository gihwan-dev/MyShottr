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

        coordinator.consumePendingCaptures()

        XCTAssertEqual(inbox.claimedIDs, [first.id, second.id])
        XCTAssertEqual(inbox.committedIDs, [first.id, second.id])
        XCTAssertEqual(inbox.cleanedIDs, [first.id, second.id])
        XCTAssertEqual(
            windows.presentedProjects.map(\.manifest.documentId),
            [first.id, second.id]
        )
    }

    func testStartReportsOneBatchAfterImportingOtherValidCapture() {
        let invalid = StagedCapture(
            id: ChromeFixtures.captureID,
            pngURL: URL(fileURLWithPath: "/inbox/invalid.png")
        )
        let valid = StagedCapture(
            id: ChromeFixtures.secondCaptureID,
            pngURL: URL(fileURLWithPath: "/inbox/valid.png")
        )
        let inbox = StubPendingCaptureInbox(
            pending: [invalid, valid],
            dataByID: [
                invalid.id: ProjectFixtures.pngData,
                valid.id: ProjectFixtures.pngData,
            ]
        )
        inbox.claimErrorByID[invalid.id] =
            PendingCaptureInboxError.invalidPNG
        let windows = SpyDocumentWindowPresenter()
        var reportedErrors: [MyShottrUserFacingError] = []
        var importedCountWhenReported = 0
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: {
                importedCountWhenReported =
                    windows.presentedProjects.count
                reportedErrors.append($0)
            }
        )

        coordinator.start()
        coordinator.stop()

        XCTAssertEqual(reportedErrors.count, 1)
        XCTAssertEqual(
            reportedErrors.first?.viewModel.title,
            "Chrome Capture Import Finished with Issues"
        )
        XCTAssertEqual(
            reportedErrors.first?.viewModel.message,
            "1 capture was not imported. All other valid captures "
                + "were imported before this summary was shown."
        )
        XCTAssertEqual(importedCountWhenReported, 1)
        XCTAssertEqual(
            windows.presentedProjects.map(\.manifest.documentId),
            [valid.id]
        )
    }

    func testLaunchScanReportsOneBoundedBatchAfterAllValidImports() {
        let ids = (1...9).map {
            UUID(
                uuidString: String(
                    format:
                        "00000000-0000-4000-8000-%012d",
                    $0
                )
            )!
        }
        let staged = ids.map {
            StagedCapture(
                id: $0,
                pngURL: URL(
                    fileURLWithPath:
                        "/inbox/\($0.uuidString).png"
                )
            )
        }
        let inbox = StubPendingCaptureInbox(
            pending: staged,
            dataByID: [
                ids[0]: ProjectFixtures.pngData,
                ids[1]: ProjectFixtures.pngData,
                ids[2]: ProjectFixtures.pngData,
                ids[3]: ProjectFixtures.pngData,
                ids[4]: ProjectFixtures.pngData,
                ids[5]: ProjectFixtures.pngData,
                ids[6]: ProjectFixtures.pngData,
                ids[7]: ProjectFixtures.pngData,
                ids[8]: ProjectFixtures.pngData,
            ]
        )
        for id in ids.prefix(6) {
            inbox.claimErrorByID[id] =
                PendingCaptureInboxError.invalidPNG
        }
        inbox.commitErrorByID[ids[7]] =
            ChromeFixtureError.commit
        let windows = SpyDocumentWindowPresenter()
        var reported: [MyShottrUserFacingError] = []
        var presentedCountWhenReported = 0
        var cleanedCountWhenReported = 0
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: {
                presentedCountWhenReported =
                    windows.presentedProjects.count
                cleanedCountWhenReported =
                    inbox.cleanedIDs.count
                reported.append($0)
            }
        )

        coordinator.start()
        coordinator.stop()

        XCTAssertEqual(reported.count, 1)
        let viewModel = try? XCTUnwrap(
            reported.first?.viewModel
        )
        XCTAssertEqual(
            viewModel?.title,
            "Chrome Capture Import Finished with Issues"
        )
        XCTAssertEqual(
            viewModel?.message,
            "6 captures were not imported. 1 opened document still "
                + "needs inbox commit or cleanup. All other valid "
                + "captures were imported before this summary was shown."
        )
        XCTAssertLessThan(viewModel?.message.count ?? .max, 320)
        for id in ids {
            XCTAssertFalse(
                viewModel?.message.contains(id.uuidString)
                    ?? true
            )
        }
        XCTAssertEqual(presentedCountWhenReported, 3)
        XCTAssertEqual(cleanedCountWhenReported, 2)
        XCTAssertEqual(
            windows.presentedProjects.map(\.manifest.documentId),
            [ids[6], ids[7], ids[8]]
        )
        XCTAssertEqual(
            inbox.cleanedIDs,
            [ids[6], ids[8]]
        )
    }

    func testLaunchScanFailureClaimsOnlyDiscoveredValidImports() {
        let valid = StagedCapture(
            id: ChromeFixtures.captureID,
            pngURL: URL(
                fileURLWithPath: "/inbox/valid.png"
            )
        )
        let inbox = StubPendingCaptureInbox(
            pending: [valid]
        )
        inbox.cleanupScanError = ChromeFixtureError.cleanup
        let windows = SpyDocumentWindowPresenter()
        var reported: [MyShottrUserFacingError] = []
        var importedCountWhenReported = 0
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: {
                importedCountWhenReported =
                    windows.presentedProjects.count
                reported.append($0)
            }
        )

        coordinator.consumePendingCaptures()

        XCTAssertEqual(importedCountWhenReported, 1)
        XCTAssertEqual(reported.count, 1)
        let message = reported.first?.viewModel.message ?? ""
        XCTAssertTrue(
            message.contains(
                "1 inbox scan phase could not be completed"
            )
        )
        XCTAssertTrue(
            message.contains(
                "valid captures that were discovered"
            )
        )
        XCTAssertFalse(
            message.contains("All other valid captures")
        )
    }

    func testWindowFailureReportsNotImportedPhase() {
        let inbox = StubPendingCaptureInbox(
            pending: [
                StagedCapture(
                    id: ChromeFixtures.captureID,
                    pngURL: URL(
                        fileURLWithPath: "/inbox/capture.png"
                    )
                ),
            ]
        )
        let windows = SpyDocumentWindowPresenter()
        windows.presentationError =
            CapturePipelineTestError.presentation
        var reported: [MyShottrUserFacingError] = []
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: { reported.append($0) }
        )

        coordinator.start()
        coordinator.stop()

        XCTAssertEqual(reported.count, 1)
        guard let error = reported.first else {
            return XCTFail("Expected one presentation failure")
        }
        XCTAssertEqual(
            error.viewModel.title,
            "Chrome Capture Import Finished with Issues"
        )
        XCTAssertTrue(
            error.viewModel.message.contains(
                "1 capture was not imported"
            )
        )
        XCTAssertTrue(windows.presentedProjects.isEmpty)
    }

    func testCommitFailureReportsOpenedDocumentAndRetainedRetryState() {
        let inbox = StubPendingCaptureInbox(
            pending: [
                StagedCapture(
                    id: ChromeFixtures.captureID,
                    pngURL: URL(
                        fileURLWithPath: "/inbox/capture.png"
                    )
                ),
            ]
        )
        inbox.commitError = ChromeFixtureError.commit
        let windows = SpyDocumentWindowPresenter()
        var reported: [MyShottrUserFacingError] = []
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows,
            reportError: { reported.append($0) }
        )

        coordinator.start()
        coordinator.stop()

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertEqual(reported.count, 1)
        guard let error = reported.first else {
            return XCTFail("Expected one durable commit failure")
        }
        XCTAssertEqual(
            error.viewModel.title,
            "Chrome Capture Import Finished with Issues"
        )
        XCTAssertTrue(
            error.viewModel.message.contains(
                "1 opened document"
            )
        )
        XCTAssertTrue(
            error.viewModel.message.contains(
                "commit or cleanup"
            )
        )
        XCTAssertFalse(
            error.viewModel.message.contains("not imported")
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
                $0 as? ChromeCaptureImportError,
                .projectCreationFailed
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
                $0 as? ChromeCaptureImportError,
                .windowPresentationFailed
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
                $0 as? ChromeCaptureImportError,
                .durableCommitFailedAfterOpen
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
                $0 as? ChromeCaptureImportError,
                .cleanupFailedAfterOpen
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

        coordinator.consumePendingCaptures()

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
        var reportedErrors: [MyShottrUserFacingError] = []
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
        var reportedErrors: [MyShottrUserFacingError] = []
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
            reportedErrors.first?.viewModel.title,
            "Chrome Capture Image Is Invalid"
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
