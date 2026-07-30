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

    func testConsumeReturnsPNGAndDeletesStagedFile() throws {
        let inbox = try PendingCaptureInbox(
            root: temporaryDirectory,
            idGenerator: { ChromeFixtures.captureID }
        )
        let staged = try inbox.stage(pngData: ProjectFixtures.pngData)

        XCTAssertEqual(
            try inbox.consume(id: ChromeFixtures.captureID),
            ProjectFixtures.pngData
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.pngURL.path))
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
            try inbox.consume(id: ChromeFixtures.captureID)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
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
            try inbox.consume(id: ChromeFixtures.captureID)
        )
        XCTAssertEqual(try Data(contentsOf: target), ProjectFixtures.pngData)
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
