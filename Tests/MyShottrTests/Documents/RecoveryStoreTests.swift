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

        let recovered = try store.recoverableProjects()
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

        XCTAssertTrue(try store.recoverableProjects().isEmpty)
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

        XCTAssertThrowsError(try store.recoverableProjects()) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .invalidPackagePath(link.lastPathComponent)
            )
        }
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

        XCTAssertThrowsError(try store.recoverableProjects()) {
            guard case .invalidPackage(
                ProjectFixtures.documentID,
                .invalidMemberSet(_)
            ) = $0 as? RecoveryStoreError else {
                return XCTFail("Unexpected error: \($0)")
            }
        }
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

        XCTAssertThrowsError(try store.recoverableProjects()) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .invalidPackage(
                    ProjectFixtures.documentID,
                    .unsupportedFormatVersion(99)
                )
            )
        }
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

        XCTAssertThrowsError(try store.recoverableProjects()) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .invalidPackage(
                    ProjectFixtures.documentID,
                    .unsupportedAnnotationSchemaVersion(99)
                )
            )
        }
    }

    func testRejectsUnexpectedRecoveryPath() throws {
        let store = try RecoveryStore(root: temporaryDirectory)
        try Data().write(
            to: temporaryDirectory.appendingPathComponent("unexpected.txt")
        )

        XCTAssertThrowsError(try store.recoverableProjects()) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .invalidPackagePath("unexpected.txt")
            )
        }
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

        XCTAssertThrowsError(try store.recoverableProjects()) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .documentIdentifierMismatch(
                    path: ProjectFixtures.documentID,
                    manifest: RecoveryFixtures.secondDocumentID
                )
            )
        }
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

        let recovered = try store.recoverableProjects()

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
        XCTAssertTrue(try store.recoverableProjects().isEmpty)
    }

    private func recoveryURL(for documentID: UUID) -> URL {
        temporaryDirectory.appendingPathComponent(
            "\(documentID.uuidString).myshottr",
            isDirectory: true
        )
    }
}
