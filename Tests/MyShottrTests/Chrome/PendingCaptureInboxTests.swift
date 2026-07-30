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

    func testClaimRenamesPendingFileAndAckDeletesIt() throws {
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID }
        )
        let staged = try inbox.stage(pngData: ProjectFixtures.pngData)

        let claim = try inbox.claim(id: ChromeFixtures.captureID)

        XCTAssertEqual(claim.id, ChromeFixtures.captureID)
        XCTAssertEqual(claim.pngData, ProjectFixtures.pngData)
        XCTAssertEqual(
            claim.processingURL.lastPathComponent,
            "\(ChromeFixtures.captureID.uuidString).processing"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.pngURL.path))
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: claim.processingURL.path
            )
        )

        try inbox.acknowledge(claim)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: claim.processingURL.path
            )
        )
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
    func testRelaunchRecoversClaimedCaptureExactlyOnce() throws {
        let firstInbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID }
        )
        _ = try firstInbox.stage(pngData: ProjectFixtures.pngData)
        let interruptedClaim = try firstInbox.claim(
            id: ChromeFixtures.captureID
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
                    pngURL: interruptedClaim.processingURL
                ),
            ]
        )

        try coordinator.consumePendingCaptures()

        XCTAssertEqual(windows.presentedProjects.count, 1)
        XCTAssertTrue(try relaunchedInbox.pendingCaptures().isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: interruptedClaim.processingURL.path
            )
        )
    }

    func testAckRejectsReplacedProcessingPathWithoutDeletingReplacement() throws {
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID }
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let claim = try inbox.claim(id: ChromeFixtures.captureID)
        try FileManager.default.removeItem(at: claim.processingURL)
        let replacement = temporaryDirectory.appendingPathComponent(
            "replacement.png"
        )
        try ProjectFixtures.pngData.write(to: replacement)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: replacement.path
        )
        try FileManager.default.moveItem(
            at: replacement,
            to: claim.processingURL
        )

        XCTAssertThrowsError(try inbox.acknowledge(claim)) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .invalidEntry
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: claim.processingURL),
            ProjectFixtures.pngData
        )
    }

    func testAckDirectorySyncFailureIsReportedAfterPresentationDataRemainsOpen() throws {
        let directorySync = DirectorySyncController()
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID },
            directorySync: directorySync.call
        )
        _ = try inbox.stage(pngData: ProjectFixtures.pngData)
        let claim = try inbox.claim(id: ChromeFixtures.captureID)
        directorySync.shouldFail = true

        XCTAssertThrowsError(try inbox.acknowledge(claim)) {
            XCTAssertEqual(
                $0 as? PendingCaptureInboxError,
                .systemCallFailed(
                    name: "fsync inbox after acknowledge",
                    code: EIO
                )
            )
        }
        XCTAssertEqual(claim.pngData, ProjectFixtures.pngData)
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
}

private final class DirectorySyncController: @unchecked Sendable {
    private let lock = NSLock()
    private var failureEnabled = false

    var shouldFail: Bool {
        get {
            lock.withLock { failureEnabled }
        }
        set {
            lock.withLock {
                failureEnabled = newValue
            }
        }
    }

    func call(_ descriptor: Int32) -> Int32 {
        if shouldFail {
            errno = EIO
            return -1
        }
        return Darwin.fsync(descriptor)
    }
}
