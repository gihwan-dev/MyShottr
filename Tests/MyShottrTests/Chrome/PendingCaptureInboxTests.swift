import Darwin
import Foundation
import XCTest
@testable import MyShottr

final class PendingCaptureInboxTests: TemporaryDirectoryTestCase {
    func testCreatesInboxRootWithOwnerOnlyPermissions() throws {
        let root = temporaryDirectory.appendingPathComponent(
            "Inbox",
            isDirectory: true
        )

        _ = try PendingCaptureInbox(root: root)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.path
        )
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
        XCTAssertEqual(
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            getuid()
        )
    }

    func testStageCreatesRegularOwnerOnlyPNG() throws {
        let root = temporaryDirectory.appendingPathComponent(
            "Inbox",
            isDirectory: true
        )
        let inbox = try PendingCaptureInbox(
            root: root,
            idGenerator: { ChromeFixtures.captureID }
        )

        let staged = try inbox.stage(pngData: ProjectFixtures.pngData)

        XCTAssertEqual(staged.id, ChromeFixtures.captureID)
        XCTAssertEqual(
            staged.pngURL.lastPathComponent,
            "\(ChromeFixtures.captureID.uuidString).png"
        )
        let attributes = try FileManager.default.attributesOfItem(
            atPath: staged.pngURL.path
        )
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            getuid()
        )
        XCTAssertEqual(try Data(contentsOf: staged.pngURL), ProjectFixtures.pngData)
    }

    func testDuplicateCaptureIDCannotOverwriteExistingFile() throws {
        let root = temporaryDirectory.appendingPathComponent(
            "Inbox",
            isDirectory: true
        )
        let inbox = try PendingCaptureInbox(
            root: root,
            idGenerator: { ChromeFixtures.captureID }
        )
        let first = try inbox.stage(pngData: ProjectFixtures.pngData)

        XCTAssertThrowsError(
            try inbox.stage(pngData: ProjectFixtures.pngData)
        )
        XCTAssertEqual(try Data(contentsOf: first.pngURL), ProjectFixtures.pngData)
    }

    func testClaimCommitAndCleanupUseUniqueDurableStates() throws {
        let stateIDs = UUIDSequence([
            ChromeFixtures.stateID,
            ChromeFixtures.secondStateID,
        ])
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: stateIDs.next
        )
        let staged = try inbox.stage(pngData: ProjectFixtures.pngData)

        let claim = try inbox.claim(id: ChromeFixtures.captureID)

        XCTAssertEqual(claim.id, ChromeFixtures.captureID)
        XCTAssertEqual(claim.pngData, ProjectFixtures.pngData)
        XCTAssertEqual(
            claim.processingURL.lastPathComponent,
            "\(ChromeFixtures.captureID.uuidString)."
                + "\(ChromeFixtures.stateID.uuidString).processing"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.pngURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: claim.processingURL.path
            )
        )

        let presented = try inbox.commitPresentation(claim)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: claim.processingURL.path
            )
        )
        XCTAssertEqual(
            presented.presentedURL.lastPathComponent,
            "\(ChromeFixtures.captureID.uuidString)."
                + "\(ChromeFixtures.stateID.uuidString).presented"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: presented.presentedURL.path
            )
        )

        XCTAssertEqual(try inbox.cleanupPresented(presented), .removed)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: presented.presentedURL.path
            )
        )
        XCTAssertTrue(try inbox.cleanupOnlyCaptures().isEmpty)
    }

    func testInvalidPNGIsDeletedAndRejected() throws {
        let inbox = try PendingCaptureInbox(root: temporaryDirectory)
        let invalidURL = temporaryDirectory.appendingPathComponent(
            "\(ChromeFixtures.captureID.uuidString).png"
        )
        try Data("not-png".utf8).write(to: invalidURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: invalidURL.path
        )

        XCTAssertThrowsError(
            try inbox.claim(id: ChromeFixtures.captureID)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: temporaryDirectory.appendingPathComponent(
                    "\(ChromeFixtures.captureID.uuidString).processing"
                ).path
            )
        )
    }

    func testInboxRejectsSymbolicLinkWithoutReadingTarget() throws {
        let inbox = try PendingCaptureInbox(root: temporaryDirectory)
        let target = temporaryDirectory.appendingPathComponent("target.png")
        try ProjectFixtures.pngData.write(to: target)
        let link = temporaryDirectory.appendingPathComponent(
            "\(ChromeFixtures.captureID.uuidString).png"
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try inbox.claim(id: ChromeFixtures.captureID)
        )
        XCTAssertEqual(try Data(contentsOf: target), ProjectFixtures.pngData)
    }

    @MainActor
    func testClaimDirectorySyncFailureRecoversProcessingOnRelaunch() throws {
        let operations = InboxFileOperationController()
        let firstInbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: { ChromeFixtures.stateID },
            directorySync: operations.syncDirectory
        )
        _ = try firstInbox.stage(pngData: ProjectFixtures.pngData)
        operations.failNextDirectorySync()

        XCTAssertThrowsError(
            try firstInbox.claim(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "fsync inbox after claim",
                    code: EIO
                )
            )
        }
        let processingURL = try XCTUnwrap(
            inboxURLs(suffix: ".processing").first
        )
        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let pending = try relaunchedInbox.pendingCaptures()
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        XCTAssertEqual(
            pending,
            [
                StagedCapture(
                    id: ChromeFixtures.captureID,
                    pngURL: processingURL
                ),
            ]
        )

        try coordinator.consumePendingCaptures()

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(try relaunchedInbox.pendingCaptures().isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: processingURL.path
            )
        )
    }

    func testClaimRenameFailurePreservesPendingPath() throws {
        let operations = InboxFileOperationController()
        operations.failNextRename(toSuffix: ".processing")
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: { ChromeFixtures.stateID },
            renameEntry: operations.renameExclusive
        )
        let staged = try inbox.stage(pngData: ProjectFixtures.pngData)

        XCTAssertThrowsError(
            try inbox.claim(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "claim pending capture",
                    code: EIO
                )
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: staged.pngURL.path)
        )
        XCTAssertTrue(inboxURLs(suffix: ".processing").isEmpty)
    }

    @MainActor
    func testPresentedRenameFailureRetriesWithoutDuplicateWindow() throws {
        let operations = InboxFileOperationController()
        operations.failNextRename(toSuffix: ".presented")
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: { ChromeFixtures.stateID },
            renameEntry: operations.renameExclusive
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "commit presented capture",
                    code: EIO
                )
            )
        }
        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertEqual(inboxURLs(suffix: ".processing").count, 1)

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(try inbox.pendingCaptures().isEmpty)
        XCTAssertTrue(try inbox.cleanupOnlyCaptures().isEmpty)
    }

    @MainActor
    func testPresentedSyncFailureIsCleanupOnlyOnRelaunch() throws {
        let operations = InboxFileOperationController()
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: { ChromeFixtures.stateID },
            directorySync: operations.syncDirectory
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        operations.failDirectorySync(atCall: 3)
        let firstWindows = SpyDocumentWindowPresenter()
        let firstCoordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: firstWindows
        )

        XCTAssertThrowsError(
            try firstCoordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "fsync inbox after presented transition",
                    code: EIO
                )
            )
        }
        XCTAssertEqual(firstWindows.presentedProjects.count, 1)
        XCTAssertEqual(inboxURLs(suffix: ".presented").count, 1)
        XCTAssertTrue(try inbox.pendingCaptures().isEmpty)

        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let relaunchedWindows = SpyDocumentWindowPresenter()
        let relaunchedCoordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: relaunchedWindows
        )

        try relaunchedCoordinator.consumePendingCaptures()

        XCTAssertTrue(relaunchedWindows.presentedProjects.isEmpty)
        XCTAssertTrue(try relaunchedInbox.cleanupOnlyCaptures().isEmpty)
    }

    @MainActor
    func testPresentedStateSuppressesSameIDProcessingOnRelaunch() throws {
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: { ChromeFixtures.stateID }
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let claim = try inbox.claim(id: ChromeFixtures.captureID)
        let presentedURL = claim.processingURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                claim.processingURL.lastPathComponent
                    .replacingOccurrences(
                        of: ".processing",
                        with: ".presented"
                    )
            )
        try FileManager.default.copyItem(
            at: claim.processingURL,
            to: presentedURL
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: presentedURL.path
        )
        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        try coordinator.consumePendingCaptures()

        XCTAssertTrue(windows.presentedProjects.isEmpty)
        XCTAssertTrue(try relaunchedInbox.pendingCaptures().isEmpty)
        XCTAssertTrue(try relaunchedInbox.cleanupOnlyCaptures().isEmpty)
    }

    @MainActor
    func testCleanupUnlinkFailureConvergesWithoutDuplicateWindow() throws {
        let operations = InboxFileOperationController()
        operations.failNextUnlink()
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: UUIDSequence([
                ChromeFixtures.stateID,
                ChromeFixtures.secondStateID,
            ]).next,
            unlinkEntry: operations.unlink
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "remove quarantined capture",
                    code: EIO
                )
            )
        }
        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertEqual(inboxURLs(suffix: ".quarantine").count, 1)

        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let relaunchedWindows = SpyDocumentWindowPresenter()
        let relaunchedCoordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: relaunchedWindows
        )

        try relaunchedCoordinator.consumePendingCaptures()

        XCTAssertTrue(relaunchedWindows.presentedProjects.isEmpty)
        XCTAssertTrue(try relaunchedInbox.cleanupOnlyCaptures().isEmpty)
    }

    @MainActor
    func testCleanupRenameFailurePreservesPresentedUntilRetry() throws {
        let operations = InboxFileOperationController()
        operations.failNextRename(toSuffix: ".quarantine")
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: UUIDSequence([
                ChromeFixtures.stateID,
                ChromeFixtures.secondStateID,
                UUID(
                    uuidString:
                        "99999999-8888-4777-8666-555555555555"
                )!,
            ]).next,
            renameEntry: operations.renameExclusive
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "quarantine capture",
                    code: EIO
                )
            )
        }
        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertEqual(inboxURLs(suffix: ".presented").count, 1)
        XCTAssertTrue(inboxURLs(suffix: ".quarantine").isEmpty)

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(try inbox.cleanupOnlyCaptures().isEmpty)
    }

    @MainActor
    func testCleanupSyncFailurePreservesQuarantineUntilRetry() throws {
        let operations = InboxFileOperationController()
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: UUIDSequence([
                ChromeFixtures.stateID,
                ChromeFixtures.secondStateID,
                UUID(
                    uuidString:
                        "99999999-8888-4777-8666-555555555555"
                )!,
            ]).next,
            directorySync: operations.syncDirectory
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        operations.failDirectorySync(atCall: 4)
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        XCTAssertThrowsError(
            try coordinator.consume(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "fsync inbox after quarantine transition",
                    code: EIO
                )
            )
        }
        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(inboxURLs(suffix: ".presented").isEmpty)
        XCTAssertEqual(inboxURLs(suffix: ".quarantine").count, 1)

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(try inbox.cleanupOnlyCaptures().isEmpty)
    }

    @MainActor
    func testPostUnlinkSyncFailureIsCommittedCleanupOnly() throws {
        let operations = InboxFileOperationController()
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: UUIDSequence([
                ChromeFixtures.stateID,
                ChromeFixtures.secondStateID,
            ]).next,
            directorySync: operations.syncDirectory
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        operations.failDirectorySync(atCall: 5)
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: inbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        try coordinator.consume(id: ChromeFixtures.captureID)

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(try inbox.pendingCaptures().isEmpty)
        XCTAssertTrue(try inbox.cleanupOnlyCaptures().isEmpty)

        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let relaunchedWindows = SpyDocumentWindowPresenter()
        let relaunchedCoordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: relaunchedWindows
        )

        try relaunchedCoordinator.consumePendingCaptures()

        XCTAssertTrue(relaunchedWindows.presentedProjects.isEmpty)
    }

    @MainActor
    func testReplacedProcessingPathIsMovedButNeverUnlinked() throws {
        let stateIDs = UUIDSequence([
            ChromeFixtures.stateID,
            ChromeFixtures.secondStateID,
        ])
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            stateIDGenerator: stateIDs.next
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let claim = try inbox.claim(id: ChromeFixtures.captureID)
        try FileManager.default.removeItem(at: claim.processingURL)
        let replacementData = try ChromeFixtures.compressibleGrayscalePNG(
            width: 2,
            height: 1
        )
        try replacementData.write(to: claim.processingURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: claim.processingURL.path
        )

        XCTAssertThrowsError(try inbox.commitPresentation(claim)) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .invalidEntry
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: claim.processingURL.path
            )
        )
        let movedReplacement = try XCTUnwrap(
            inboxURLs(suffix: ".presented").first
        )
        XCTAssertEqual(
            try Data(contentsOf: movedReplacement),
            replacementData
        )

        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        try coordinator.consumePendingCaptures()

        XCTAssertTrue(windows.presentedProjects.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: movedReplacement.path
            )
        )
    }

    @MainActor
    func testInvalidEntryCleanupMovesToQuarantineBeforeUnlink() throws {
        let operations = InboxFileOperationController()
        operations.failNextUnlink()
        let stateIDs = UUIDSequence([
            ChromeFixtures.stateID,
            ChromeFixtures.secondStateID,
        ])
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            stateIDGenerator: stateIDs.next,
            unlinkEntry: operations.unlink
        )
        let target = temporaryDirectory.appendingPathComponent("target.png")
        try ProjectFixtures.pngData.write(to: target)
        let pending = temporaryDirectory.appendingPathComponent(
            "\(ChromeFixtures.captureID.uuidString).png"
        )
        try FileManager.default.createSymbolicLink(
            at: pending,
            withDestinationURL: target
        )

        XCTAssertThrowsError(
            try inbox.claim(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "remove quarantined capture",
                    code: EIO
                )
            )
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: pending.path)
        )
        XCTAssertTrue(inboxURLs(suffix: ".processing").isEmpty)
        XCTAssertEqual(inboxURLs(suffix: ".quarantine").count, 1)
        XCTAssertEqual(try Data(contentsOf: target), ProjectFixtures.pngData)

        let relaunchedInbox = try PendingCaptureInbox(
            root: temporaryDirectory
        )
        let windows = SpyDocumentWindowPresenter()
        let coordinator = CaptureInboxCoordinator(
            inbox: relaunchedInbox,
            projectFactory: StubNewProjectFactory(),
            windows: windows
        )

        try coordinator.consumePendingCaptures()

        XCTAssertTrue(windows.presentedProjects.isEmpty)
        XCTAssertTrue(try relaunchedInbox.cleanupOnlyCaptures().isEmpty)
        XCTAssertEqual(try Data(contentsOf: target), ProjectFixtures.pngData)
    }

    func testDirectOversizedDimensionPNGIsDeletedAndRejected() throws {
        let inbox = try PendingCaptureInbox(root: temporaryDirectory)
        let oversized = try ChromeFixtures.compressibleGrayscalePNG(
            width: 32_769,
            height: 1
        )
        let pendingURL = temporaryDirectory.appendingPathComponent(
            "\(ChromeFixtures.captureID.uuidString).png"
        )
        try oversized.write(to: pendingURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: pendingURL.path
        )

        XCTAssertThrowsError(
            try inbox.claim(id: ChromeFixtures.captureID)
        ) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .imageTooLarge
            )
        }
        XCTAssertTrue(try inbox.pendingCaptures().isEmpty)
    }

    func testPendingCapturesSortOldestModificationDateFirst() throws {
        let inbox = try PendingCaptureInbox(root: temporaryDirectory)
        let newer = try stageFixture(
            id: ChromeFixtures.captureID,
            date: Date(timeIntervalSince1970: 200)
        )
        let older = try stageFixture(
            id: ChromeFixtures.secondCaptureID,
            date: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            try inbox.pendingCaptures(),
            [
                StagedCapture(
                    id: ChromeFixtures.secondCaptureID,
                    pngURL: older
                ),
                StagedCapture(
                    id: ChromeFixtures.captureID,
                    pngURL: newer
                ),
            ]
        )
    }

    func testSymbolicLinkInboxRootIsRejected() throws {
        let actualRoot = temporaryDirectory.appendingPathComponent(
            "ActualInbox",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: actualRoot,
            withIntermediateDirectories: false
        )
        let linkedRoot = temporaryDirectory.appendingPathComponent(
            "LinkedInbox",
            isDirectory: true
        )
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: actualRoot
        )

        XCTAssertThrowsError(try PendingCaptureInbox(root: linkedRoot))
    }

    private func stageFixture(id: UUID, date: Date) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(
            "\(id.uuidString).png"
        )
        try ProjectFixtures.pngData.write(to: url)
        try FileManager.default.setAttributes(
            [
                .posixPermissions: 0o600,
                .modificationDate: date,
            ],
            ofItemAtPath: url.path
        )
        return url
    }

    private func inboxURLs(suffix: String) -> [URL] {
        let names = (
            try? FileManager.default.contentsOfDirectory(
                atPath: temporaryDirectory.path
            )
        ) ?? []
        return names
            .filter { $0.hasSuffix(suffix) }
            .sorted()
            .map { temporaryDirectory.appendingPathComponent($0) }
    }
}

private final class UUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        lock.withLock {
            precondition(!values.isEmpty)
            return values.removeFirst()
        }
    }
}

private final class InboxFileOperationController: @unchecked Sendable {
    private let lock = NSLock()
    private var renameFailureSuffix: String?
    private var shouldFailUnlink = false
    private var syncCallCount = 0
    private var syncFailureCalls: Set<Int> = []

    func failNextRename(toSuffix suffix: String) {
        lock.withLock {
            renameFailureSuffix = suffix
        }
    }

    func failNextUnlink() {
        lock.withLock {
            shouldFailUnlink = true
        }
    }

    func failNextDirectorySync() {
        lock.withLock {
            syncFailureCalls.insert(syncCallCount + 1)
        }
    }

    func failDirectorySync(atCall call: Int) {
        lock.withLock {
            syncFailureCalls.insert(call)
        }
    }

    func renameExclusive(
        _ directory: Int32,
        _ source: String,
        _ destination: String
    ) -> Int32 {
        let shouldFail = lock.withLock {
            if let renameFailureSuffix,
               destination.hasSuffix(renameFailureSuffix) {
                self.renameFailureSuffix = nil
                return true
            }
            return false
        }
        if shouldFail {
            errno = EIO
            return -1
        }
        return source.withCString { sourceName in
            destination.withCString { destinationName in
                Darwin.renameatx_np(
                    directory,
                    sourceName,
                    directory,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
    }

    func unlink(_ directory: Int32, _ filename: String) -> Int32 {
        let shouldFail = lock.withLock {
            if shouldFailUnlink {
                shouldFailUnlink = false
                return true
            }
            return false
        }
        if shouldFail {
            errno = EIO
            return -1
        }
        return filename.withCString {
            Darwin.unlinkat(directory, $0, 0)
        }
    }

    func syncDirectory(_ descriptor: Int32) -> Int32 {
        let shouldFail = lock.withLock {
            syncCallCount += 1
            return syncFailureCalls.remove(syncCallCount) != nil
        }
        if shouldFail {
            errno = EIO
            return -1
        }
        return Darwin.fsync(descriptor)
    }
}
