import Foundation
import XCTest
@testable import MyShottr

final class RecoveryStoreTests: TemporaryDirectoryTestCase {
    func testWriteReplacesOnlySameDocumentRecovery() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        let first = RecoveryFixtures.project(
            text: "first",
            documentID: ProjectFixtures.documentID
        )
        let other = RecoveryFixtures.project(
            text: "other",
            documentID: RecoveryFixtures.secondDocumentID
        )
        let second = RecoveryFixtures.project(
            text: "second",
            documentID: ProjectFixtures.documentID
        )

        try store.write(
            first,
            documentId: ProjectFixtures.documentID
        )
        try store.write(
            other,
            documentId: RecoveryFixtures.secondDocumentID
        )
        try store.write(
            second,
            documentId: ProjectFixtures.documentID
        )

        let recovered = try store
            .scanRecoverableProjects()
            .projects
        XCTAssertEqual(recovered.count, 2)
        XCTAssertEqual(
            recovered.first {
                $0.documentId == ProjectFixtures.documentID
            }?.project,
            second
        )
        XCTAssertEqual(
            recovered.first {
                $0.documentId == RecoveryFixtures.secondDocumentID
            }?.project,
            other
        )
    }

    func testRemoveDeletesRecoveryAfterCleanSave() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(
            ProjectFixtures.sampleProject(),
            documentId: ProjectFixtures.documentID
        )

        try store.remove(documentId: ProjectFixtures.documentID)

        XCTAssertTrue(
            try store.scanRecoverableProjects().projects.isEmpty
        )
    }

    func testBatchDiscardBecomesCleanupOnlyAndIsNeverOffered()
        throws
    {
        let firstID = ProjectFixtures.documentID
        let secondID = RecoveryFixtures.secondDocumentID
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(
            RecoveryFixtures.project(
                text: "first",
                documentID: firstID
            ),
            documentId: firstID
        )
        try store.write(
            RecoveryFixtures.project(
                text: "second",
                documentID: secondID
            ),
            documentId: secondID
        )

        XCTAssertEqual(
            try store.stageDiscard(
                documentIds: [firstID, secondID]
            ),
            .committed
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recoveryURL(for: firstID).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recoveryURL(for: secondID).path
            )
        )
        let relaunched = try RecoveryStore(
            root: temporaryDirectory
        )

        XCTAssertTrue(
            try relaunched.scanRecoverableProjects()
                .projects.isEmpty
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: temporaryDirectory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testBatchDiscardFailureOnSecondMoveRollsBackEveryRecovery()
        throws
    {
        let firstID = ProjectFixtures.documentID
        let secondID = RecoveryFixtures.secondDocumentID
        let moves = FailingRecoveryMoveFileSystem()
        let store = try RecoveryStore(
            root: temporaryDirectory,
            fileSystem: moves.fileSystem
        )
        let first = RecoveryFixtures.project(
            text: "first",
            documentID: firstID
        )
        let second = RecoveryFixtures.project(
            text: "second",
            documentID: secondID
        )
        try store.write(first, documentId: firstID)
        try store.write(second, documentId: secondID)

        XCTAssertThrowsError(
            try store.stageDiscard(
                documentIds: [firstID, secondID]
            )
        ) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .discardStageFailed(firstID)
            )
        }

        let recovered = try store
            .scanRecoverableProjects()
            .projects
        XCTAssertEqual(
            Set(recovered.map(\.documentId)),
            Set([firstID, secondID])
        )
        XCTAssertEqual(
            recovered.first {
                $0.documentId == firstID
            }?.project,
            first
        )
        XCTAssertEqual(
            recovered.first {
                $0.documentId == secondID
            }?.project,
            second
        )
        XCTAssertTrue(moves.didAttemptRollback)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: temporaryDirectory,
                includingPropertiesForKeys: nil
            )
            .map(\.lastPathComponent)
            .sorted(),
            [
                "\(firstID.uuidString).myshottr",
                "\(secondID.uuidString).myshottr",
            ].sorted()
        )
    }

    func testFinalRootSyncFailureAfterCommitDoesNotRollback()
        throws
    {
        let firstID = ProjectFixtures.documentID
        let secondID = RecoveryFixtures.secondDocumentID
        let setup = try makePostCommitSyncFailingStore()

        let result = try setup.store.stageDiscard(
            documentIds: [firstID, secondID]
        )

        XCTAssertEqual(
            result,
            .committedAwaitingDurability
        )
        XCTAssertEqual(setup.fileSystem.rollbackMoveCount, 0)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recoveryURL(for: firstID).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: recoveryURL(for: secondID).path
            )
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                at: discardTransactionURL(
                    state: "committed"
                ),
                includingPropertiesForKeys: nil
            )
            .map(\.lastPathComponent)
            .sorted(),
            [
                "\(firstID.uuidString).myshottr",
                "\(secondID.uuidString).myshottr",
            ].sorted()
        )
    }

    func testRelaunchCleansCommittedBatchAfterFinalRootSyncFailure()
        throws
    {
        let firstID = ProjectFixtures.documentID
        let secondID = RecoveryFixtures.secondDocumentID
        let setup = try makePostCommitSyncFailingStore()
        XCTAssertEqual(
            try setup.store.stageDiscard(
                documentIds: [firstID, secondID]
            ),
            .committedAwaitingDurability
        )

        let relaunched = try RecoveryStore(
            root: temporaryDirectory
        )

        XCTAssertTrue(
            try relaunched.scanRecoverableProjects()
                .projects.isEmpty
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                at: temporaryDirectory,
                includingPropertiesForKeys: nil
            ).isEmpty
        )
    }

    func testRelaunchRollsBackPendingDiscardTransaction()
        throws
    {
        let firstID = ProjectFixtures.documentID
        let secondID = RecoveryFixtures.secondDocumentID
        let first = RecoveryFixtures.project(
            text: "first pending",
            documentID: firstID
        )
        let second = RecoveryFixtures.project(
            text: "second pending",
            documentID: secondID
        )
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(first, documentId: firstID)
        try store.write(second, documentId: secondID)
        let pending = discardTransactionURL(
            state: "pending"
        )
        try FileManager.default.createDirectory(
            at: pending,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        for documentID in [firstID, secondID] {
            try FileManager.default.moveItem(
                at: recoveryURL(for: documentID),
                to: pending.appendingPathComponent(
                    "\(documentID.uuidString).myshottr",
                    isDirectory: true
                )
            )
        }

        let relaunched = try RecoveryStore(
            root: temporaryDirectory
        )

        let recovered = try relaunched
            .scanRecoverableProjects()
            .projects
        XCTAssertEqual(
            Set(recovered.map(\.documentId)),
            Set([firstID, secondID])
        )
        XCTAssertEqual(
            recovered.first {
                $0.documentId == firstID
            }?.project,
            first
        )
        XCTAssertEqual(
            recovered.first {
                $0.documentId == secondID
            }?.project,
            second
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: pending.path)
        )
    }

    func testRelaunchRejectsSymlinkDiscardTransaction()
        throws
    {
        let external = temporaryDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(
                "external-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: external,
            withIntermediateDirectories: false
        )
        defer {
            try? FileManager.default.removeItem(at: external)
        }
        let pending = discardTransactionURL(
            state: "pending"
        )
        try FileManager.default.createSymbolicLink(
            at: pending,
            withDestinationURL: external
        )

        XCTAssertThrowsError(
            try RecoveryStore(root: temporaryDirectory)
        ) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .invalidDiscardTransactionPath(
                    pending.lastPathComponent
                )
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: pending.path)
        )
    }

    func testRootIsNormalizedToOwnerOnlyPermissions() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o777],
            ofItemAtPath: temporaryDirectory.path
        )

        _ = try RecoveryStore(root: temporaryDirectory)

        let attributes = try FileManager.default.attributesOfItem(
            atPath: temporaryDirectory.path
        )
        XCTAssertEqual(
            attributes[.posixPermissions] as? NSNumber,
            NSNumber(value: 0o700)
        )
    }

    func testRejectsSymbolicLinkRoot() throws {
        let actualRoot = temporaryDirectory
            .appendingPathComponent("actual", isDirectory: true)
        try FileManager.default.createDirectory(
            at: actualRoot,
            withIntermediateDirectories: false
        )
        let linkedRoot = temporaryDirectory
            .appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedRoot,
            withDestinationURL: actualRoot
        )

        XCTAssertThrowsError(
            try RecoveryStore(root: linkedRoot)
        ) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .invalidRoot
            )
        }
    }

    func testRejectsRecoveryPackageSymbolicLink() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        let package = try ProjectFixtures.package()
        defer { try? FileManager.default.removeItem(at: package) }
        let link = temporaryDirectory.appendingPathComponent(
            "\(ProjectFixtures.documentID.uuidString).myshottr"
        )
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: package
        )

        let scan = try store.scanRecoverableProjects()

        XCTAssertTrue(scan.projects.isEmpty)
        XCTAssertEqual(
            scan.issues,
            [
                RecoveryScanIssue(
                    entryName: link.lastPathComponent,
                    error: .invalidPackagePath(
                        link.lastPathComponent
                    )
                ),
            ]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: link.path)
        )
    }

    func testRejectsInvalidPackageMembers() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(
            ProjectFixtures.sampleProject(),
            documentId: ProjectFixtures.documentID
        )
        let package = recoveryURL(for: ProjectFixtures.documentID)
        try Data("unexpected".utf8).write(
            to: package.appendingPathComponent("extra.txt")
        )

        let scan = try store.scanRecoverableProjects()

        XCTAssertTrue(scan.projects.isEmpty)
        guard case .invalidPackage(
            ProjectFixtures.documentID,
            .invalidMemberSet(_)
        ) = scan.issues.first?.error else {
            return XCTFail(
                "Unexpected issues: \(scan.issues)"
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: package.path)
        )
    }

    func testRejectsUnsupportedProjectVersion() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(
            ProjectFixtures.sampleProject(),
            documentId: ProjectFixtures.documentID
        )
        let package = recoveryURL(for: ProjectFixtures.documentID)
        let current = ProjectFixtures.project(text: "newer").manifest
        let manifest = ProjectManifest(
            formatVersion: 99,
            documentId: current.documentId,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            sourcePixelWidth: current.sourcePixelWidth,
            sourcePixelHeight: current.sourcePixelHeight,
            sourceKind: current.sourceKind,
            sourceScale: current.sourceScale
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: package.appendingPathComponent("manifest.json")
        )

        let scan = try store.scanRecoverableProjects()

        XCTAssertTrue(scan.projects.isEmpty)
        XCTAssertEqual(
            scan.issues.map(\.error),
            [
                .invalidPackage(
                    ProjectFixtures.documentID,
                    .unsupportedFormatVersion(99)
                ),
            ]
        )
    }

    func testRejectsUnsupportedAnnotationSchema() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(
            ProjectFixtures.sampleProject(),
            documentId: ProjectFixtures.documentID
        )
        try ProjectFixtures.annotationJSON(schemaVersion: 99)
            .write(
                to: recoveryURL(for: ProjectFixtures.documentID)
                    .appendingPathComponent("document.json")
            )

        let scan = try store.scanRecoverableProjects()

        XCTAssertTrue(scan.projects.isEmpty)
        XCTAssertEqual(
            scan.issues.map(\.error),
            [
                .invalidPackage(
                    ProjectFixtures.documentID,
                    .unsupportedAnnotationSchemaVersion(99)
                ),
            ]
        )
    }

    func testRejectsUnexpectedRecoveryPath() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        try Data().write(
            to: temporaryDirectory.appendingPathComponent("unexpected.txt")
        )

        let scan = try store.scanRecoverableProjects()

        XCTAssertTrue(scan.projects.isEmpty)
        XCTAssertEqual(
            scan.issues,
            [
                RecoveryScanIssue(
                    entryName: "unexpected.txt",
                    error: .invalidPackagePath(
                        "unexpected.txt"
                    )
                ),
            ]
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: temporaryDirectory
                    .appendingPathComponent("unexpected.txt")
                    .path
            )
        )
    }

    func testRejectsPackageWhoseManifestUsesAnotherDocumentIdentifier()
        throws
    {
        let store = try RecoveryStore(root: temporaryDirectory)
        try store.write(
            ProjectFixtures.sampleProject(),
            documentId: ProjectFixtures.documentID
        )
        let package = recoveryURL(for: ProjectFixtures.documentID)
        let current = ProjectFixtures.project(text: "mismatch").manifest
        let manifest = ProjectManifest(
            formatVersion: current.formatVersion,
            documentId: RecoveryFixtures.secondDocumentID,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            sourcePixelWidth: current.sourcePixelWidth,
            sourcePixelHeight: current.sourcePixelHeight,
            sourceKind: current.sourceKind,
            sourceScale: current.sourceScale
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: package.appendingPathComponent("manifest.json")
        )

        let scan = try store.scanRecoverableProjects()

        XCTAssertTrue(scan.projects.isEmpty)
        XCTAssertEqual(
            scan.issues.map(\.error),
            [
                .documentIdentifierMismatch(
                    path: ProjectFixtures.documentID,
                    manifest: RecoveryFixtures.secondDocumentID
                ),
            ]
        )
    }

    func testRecoverableProjectsAreNewestFirstWithStableTieBreak()
        throws
    {
        let store = try RecoveryStore(root: temporaryDirectory)
        let firstID = ProjectFixtures.documentID
        let secondID = RecoveryFixtures.secondDocumentID
        try store.write(
            RecoveryFixtures.project(
                text: "first",
                documentID: firstID
            ),
            documentId: firstID
        )
        try store.write(
            RecoveryFixtures.project(
                text: "second",
                documentID: secondID
            ),
            documentId: secondID
        )
        let sameDate = RecoveryFixtures.fixedNow
        for id in [firstID, secondID] {
            try FileManager.default.setAttributes(
                [.modificationDate: sameDate],
                ofItemAtPath: recoveryURL(for: id).path
            )
        }

        let recovered = try store
            .scanRecoverableProjects()
            .projects

        XCTAssertEqual(
            recovered.map(\.documentId),
            [secondID, firstID].sorted {
                $0.uuidString < $1.uuidString
            }
        )
        XCTAssertEqual(recovered.map(\.modifiedAt), [sameDate, sameDate])
    }

    func testWriteRejectsDocumentIdentifierMismatch() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        let project = ProjectFixtures.project(text: "mismatch")

        XCTAssertThrowsError(
            try store.write(
                project,
                documentId: RecoveryFixtures.secondDocumentID
            )
        ) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .documentIdentifierMismatch(
                    path: RecoveryFixtures.secondDocumentID,
                    manifest: ProjectFixtures.documentID
                )
            )
        }
        XCTAssertTrue(
            try store.scanRecoverableProjects().projects.isEmpty
        )
    }

    func testMixedValidAndCorruptPackagesReturnValidProjectAndIssue()
        throws
    {
        let store = try RecoveryStore(root: temporaryDirectory)
        let valid = RecoveryFixtures.project(
            text: "valid",
            documentID: ProjectFixtures.documentID
        )
        let corrupt = RecoveryFixtures.project(
            text: "corrupt",
            documentID: RecoveryFixtures.secondDocumentID
        )
        try store.write(
            valid,
            documentId: ProjectFixtures.documentID
        )
        try store.write(
            corrupt,
            documentId: RecoveryFixtures.secondDocumentID
        )
        let corruptURL = recoveryURL(
            for: RecoveryFixtures.secondDocumentID
        )
        try Data("unexpected".utf8).write(
            to: corruptURL.appendingPathComponent("extra.txt")
        )

        let scan = try store.scanRecoverableProjects()

        XCTAssertEqual(scan.projects.map(\.project), [valid])
        XCTAssertEqual(scan.issues.count, 1)
        XCTAssertEqual(
            scan.issues[0].entryName,
            corruptURL.lastPathComponent
        )
        guard case .invalidPackage(
            RecoveryFixtures.secondDocumentID,
            .invalidMemberSet(_)
        ) = scan.issues[0].error else {
            return XCTFail(
                "Unexpected issue: \(scan.issues[0])"
            )
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: corruptURL.path)
        )
    }

    private func recoveryURL(for documentID: UUID) -> URL {
        temporaryDirectory.appendingPathComponent(
            "\(documentID.uuidString).myshottr",
            isDirectory: true
        )
    }

    private func discardTransactionURL(state: String) -> URL {
        temporaryDirectory.appendingPathComponent(
            ".discard-11111111-1111-4111-8111-111111111111.\(state)",
            isDirectory: true
        )
    }

    private func makePostCommitSyncFailingStore()
        throws -> (
            store: RecoveryStore,
            fileSystem:
                PostCommitSyncFailingRecoveryFileSystem
        )
    {
        let fileSystem =
            PostCommitSyncFailingRecoveryFileSystem(
                root: temporaryDirectory
            )
        let store = try RecoveryStore(
            root: temporaryDirectory,
            fileSystem: fileSystem.fileSystem,
            makeTransactionID: {
                UUID(
                    uuidString:
                        "11111111-1111-4111-8111-111111111111"
                )!
            }
        )
        try store.write(
            RecoveryFixtures.project(
                text: "first",
                documentID: ProjectFixtures.documentID
            ),
            documentId: ProjectFixtures.documentID
        )
        try store.write(
            RecoveryFixtures.project(
                text: "second",
                documentID: RecoveryFixtures.secondDocumentID
            ),
            documentId: RecoveryFixtures.secondDocumentID
        )
        return (store, fileSystem)
    }
}

private final class FailingRecoveryMoveFileSystem:
    @unchecked Sendable
{
    private var canonicalMoveCount = 0
    private(set) var didAttemptRollback = false

    var fileSystem: RecoveryStoreFileSystem {
        let live = RecoveryStoreFileSystem.live
        return RecoveryStoreFileSystem(
            moveItem: { [self] source, destination in
                if source.deletingLastPathComponent()
                    .lastPathComponent
                    .hasPrefix(".discard-") == false
                {
                    canonicalMoveCount += 1
                    if canonicalMoveCount == 2 {
                        throw RecoveryMoveTestError.expected
                    }
                }
                if source.deletingLastPathComponent()
                    .lastPathComponent
                    .hasSuffix(".pending")
                {
                    didAttemptRollback = true
                }
                try live.moveItem(source, destination)
            },
            synchronizeDirectory:
                live.synchronizeDirectory
        )
    }
}

private enum RecoveryMoveTestError: Error {
    case expected
}

private final class PostCommitSyncFailingRecoveryFileSystem:
    @unchecked Sendable
{
    private let root: URL
    private var didFailFinalRootSync = false
    private(set) var rollbackMoveCount = 0

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    var fileSystem: RecoveryStoreFileSystem {
        let live = RecoveryStoreFileSystem.live
        return RecoveryStoreFileSystem(
            moveItem: { [self] source, destination in
                if source.deletingLastPathComponent()
                    .lastPathComponent
                    .hasSuffix(".committed"),
                   destination.deletingLastPathComponent()
                    .standardizedFileURL == root
                {
                    rollbackMoveCount += 1
                }
                try live.moveItem(source, destination)
            },
            synchronizeDirectory: {
                [self] directory in
                if directory.standardizedFileURL == root,
                   !didFailFinalRootSync
                {
                    let entries = try FileManager.default
                        .contentsOfDirectory(
                            at: root,
                            includingPropertiesForKeys: nil
                        )
                    if entries.contains(
                        where: {
                            $0.lastPathComponent
                                .hasSuffix(".committed")
                        }
                    ) {
                        didFailFinalRootSync = true
                        throw RecoveryMoveTestError.expected
                    }
                }
                try live.synchronizeDirectory(directory)
            }
        )
    }
}
