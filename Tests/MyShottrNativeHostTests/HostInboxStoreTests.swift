import Darwin
import Foundation
import XCTest

final class HostInboxStoreTests: TemporaryDirectoryTestCase {
    private let captureID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func testCreatesInboxRootWithOwnerOnlyPermissions() throws {
        let root = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        XCTAssertEqual(chmod(root.path, 0o777), 0)
        let store = makeStore(root: root)

        _ = try store.stage(pngData: HostFixtures.validPNG)

        XCTAssertEqual(try permissions(at: root), 0o700)
    }

    func testCreatesStagedPNGWithOwnerOnlyPermissions() throws {
        let root = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        let store = makeStore(root: root)

        let result = try store.stage(pngData: HostFixtures.validPNG)

        let file = root.appendingPathComponent("\(result.uuidString).png")
        XCTAssertEqual(try permissions(at: file), 0o600)
        XCTAssertEqual(try Data(contentsOf: file), HostFixtures.validPNG)
    }

    func testUsesUUIDOnlyPNGFilename() throws {
        let root = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        let store = makeStore(root: root)

        let result = try store.stage(pngData: HostFixtures.validPNG)

        XCTAssertEqual(result, captureID)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: root.path),
            ["\(captureID.uuidString).png"]
        )
    }

    func testExclusiveCreationPreservesExistingCapture() throws {
        let root = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let destination = root.appendingPathComponent("\(captureID.uuidString).png")
        let existing = Data("existing".utf8)
        try existing.write(to: destination)
        let store = makeStore(root: root)

        XCTAssertThrowsError(try store.stage(pngData: HostFixtures.validPNG))
        XCTAssertEqual(try Data(contentsOf: destination), existing)
    }

    func testDeletesPartialFileWhenWriteFails() throws {
        let root = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        let destination = root.appendingPathComponent("\(captureID.uuidString).png")
        let store = HostInboxStore(
            rootURL: root,
            idGenerator: { self.captureID },
            writeOperation: { descriptor, data in
                let written = data.prefix(8).withUnsafeBytes {
                    Darwin.write(descriptor, $0.baseAddress, $0.count)
                }
                XCTAssertEqual(written, 8)
                throw HostTestError.partialWrite
            }
        )

        XCTAssertThrowsError(try store.stage(pngData: HostFixtures.validPNG))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSynchronizesStagedFileBeforeReturning() throws {
        let root = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        var synchronized = false
        let store = HostInboxStore(
            rootURL: root,
            idGenerator: { self.captureID },
            synchronizeOperation: { _ in
                synchronized = true
                return 0
            }
        )

        _ = try store.stage(pngData: HostFixtures.validPNG)

        XCTAssertTrue(synchronized)
    }

    func testRejectsSymbolicLinkInboxRoot() throws {
        let actualRoot = temporaryDirectory.appendingPathComponent("ActualInbox", isDirectory: true)
        try FileManager.default.createDirectory(
            at: actualRoot,
            withIntermediateDirectories: false
        )
        let linkedRoot = temporaryDirectory.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: actualRoot
        )
        let store = makeStore(root: linkedRoot)

        XCTAssertThrowsError(try store.stage(pngData: HostFixtures.validPNG))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: actualRoot.path).isEmpty)
    }

    private func makeStore(root: URL) -> HostInboxStore {
        HostInboxStore(
            rootURL: root,
            idGenerator: { self.captureID }
        )
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue & 0o777
    }
}
