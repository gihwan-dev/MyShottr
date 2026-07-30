import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class RecoveryCoordinatorTests: TemporaryDirectoryTestCase {
    func testChangesWithinTwoSecondsProduceOneRecoveryWrite()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )

        try session.applySnapshot(
            ProjectFixtures.project(text: "first").annotationJSON
        )
        await clock.advance(by: .seconds(1))
        try session.applySnapshot(
            ProjectFixtures.project(text: "second").annotationJSON
        )
        await clock.advance(by: .seconds(1))
        XCTAssertTrue(recoveryStore.writes.isEmpty)

        await clock.advance(by: .seconds(1))

        XCTAssertEqual(
            recoveryStore.writes.map(\.project.annotationJSON),
            [ProjectFixtures.project(text: "second").annotationJSON]
        )
        XCTAssertEqual(
            recoveryStore.writes.map(\.documentId),
            [ProjectFixtures.documentID]
        )
    }

    func testInvalidSnapshotDoesNotReplaceScheduledValidRecovery()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        let valid = ProjectFixtures.project(text: "valid").annotationJSON
        try session.applySnapshot(valid)

        XCTAssertThrowsError(
            try session.applySnapshot(Data("invalid".utf8))
        ) {
            XCTAssertEqual(
                $0 as? DocumentSessionError,
                .invalidDocument
            )
        }
        await clock.advance(by: .seconds(2))

        XCTAssertEqual(
            recoveryStore.writes.map(\.project.annotationJSON),
            [valid]
        )
    }

    func testRecoveryWriteFailureIsReportedAndDoesNotDeleteRecovery()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        recoveryStore.error = .writeFailed(
            ProjectFixtures.documentID
        )
        var errors: [RecoveryStoreError] = []
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        session.onRecoveryFailure = {
            if let error = $0 as? RecoveryStoreError {
                errors.append(error)
            }
        }
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )

        try session.applySnapshot(
            ProjectFixtures.project(text: "changed").annotationJSON
        )
        await clock.advance(by: .seconds(2))

        XCTAssertEqual(
            errors,
            [.writeFailed(ProjectFixtures.documentID)]
        )
        XCTAssertTrue(recoveryStore.removedDocumentIDs.isEmpty)
    }

    func testSuccessfulSaveRemovesRecoveryAndClearsModifiedState()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        try session.applySnapshot(
            ProjectFixtures.project(text: "changed").annotationJSON
        )
        await clock.advance(by: .seconds(2))
        let saved = try session.projectForSave()

        try session.completeSave(saved)

        XCTAssertEqual(
            recoveryStore.removedDocumentIDs,
            [ProjectFixtures.documentID]
        )
        XCTAssertFalse(session.isModified)
    }

    func testRecoveryRemovalFailureKeepsDocumentModified() throws {
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: ManualRecoveryClock()
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        try session.applySnapshot(
            ProjectFixtures.project(text: "changed").annotationJSON
        )
        recoveryStore.error = .removeFailed(
            ProjectFixtures.documentID
        )

        XCTAssertThrowsError(
            try session.completeSave(session.projectForSave())
        ) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .removeFailed(ProjectFixtures.documentID)
            )
        }
        XCTAssertTrue(session.isModified)
    }

    func testExplicitDiscardRemovesRecoveryButClosePreservesIt()
        throws
    {
        let closeStore = SpyRecoveryStore()
        let closingSession = DocumentSession(
            recoveryStore: closeStore,
            recoveryClock: ManualRecoveryClock()
        )
        try closingSession.open(
            project: ProjectFixtures.project(text: "close")
        )
        try closingSession.applySnapshot(
            ProjectFixtures.project(text: "changed").annotationJSON
        )

        closingSession.close()

        XCTAssertTrue(closeStore.removedDocumentIDs.isEmpty)

        let discardStore = SpyRecoveryStore()
        let discardingSession = DocumentSession(
            recoveryStore: discardStore,
            recoveryClock: ManualRecoveryClock()
        )
        try discardingSession.open(
            project: ProjectFixtures.project(text: "discard")
        )
        try discardingSession.applySnapshot(
            ProjectFixtures.project(text: "changed").annotationJSON
        )

        try discardingSession.discardRecovery()

        XCTAssertEqual(
            discardStore.removedDocumentIDs,
            [ProjectFixtures.documentID]
        )
    }

    func testRecoveredStagedDocumentCommitsAsModified() throws {
        let session = DocumentSession(
            recoveryStore: SpyRecoveryStore(),
            recoveryClock: ManualRecoveryClock()
        )
        let recovered = ProjectFixtures.project(text: "recovered")
        session.prepareForRecoveryRestore()

        try session.stage(project: recovered)
        try session.commitStaged(
            annotationJSON: recovered.annotationJSON
        )

        XCTAssertTrue(session.isModified)
    }

    func testFirstLaunchStartsUncleanSessionAtomically() throws {
        let state = try SessionTerminationState(
            root: temporaryDirectory
        )

        XCTAssertTrue(try state.beginSession())

        let data = try Data(
            contentsOf: temporaryDirectory
                .appendingPathComponent("session.json")
        )
        let object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "cleanExit"])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["cleanExit"] as? Bool, false)
    }

    func testUncleanThenCleanTerminationStateRoundTrip() throws {
        let first = try SessionTerminationState(
            root: temporaryDirectory
        )
        XCTAssertTrue(try first.beginSession())

        let afterCrash = try SessionTerminationState(
            root: temporaryDirectory
        )
        XCTAssertFalse(try afterCrash.beginSession())
        try afterCrash.markCleanExit()

        let afterCleanExit = try SessionTerminationState(
            root: temporaryDirectory
        )
        XCTAssertTrue(try afterCleanExit.beginSession())
    }

    func testInvalidTerminationStateIsRejectedWithoutReplacement()
        throws
    {
        let stateURL = temporaryDirectory
            .appendingPathComponent("session.json")
        let invalid = Data(#"{"schemaVersion":2,"cleanExit":true}"#.utf8)
        try invalid.write(to: stateURL)
        let state = try SessionTerminationState(
            root: temporaryDirectory
        )

        XCTAssertThrowsError(try state.beginSession()) {
            XCTAssertEqual(
                $0 as? SessionTerminationStateError,
                .invalidState
            )
        }
        XCTAssertEqual(try Data(contentsOf: stateURL), invalid)
    }

    func testCleanTerminationDoesNotOfferRecovery() throws {
        let store = SpyRecoveryStore()
        store.projects = [
            RecoveryFixtures.recovered(
                text: "stale",
                documentID: ProjectFixtures.documentID,
                modifiedAt: RecoveryFixtures.fixedNow
            ),
        ]
        let prompt = SpyRecoveryPrompt()
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: true,
            prompt: prompt,
            restore: { _ in
                XCTFail("Clean launch must not restore")
            }
        )

        XCTAssertFalse(try coordinator.shouldOfferRecovery())
        try coordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(store.recoverableProjectsCallCount, 0)
        XCTAssertTrue(prompt.presentedProjects.isEmpty)
    }

    func testUncleanLaunchPromptsOnlyOnceAndCancelPreservesData()
        throws
    {
        let store = SpyRecoveryStore()
        store.projects = [
            RecoveryFixtures.recovered(
                text: "recover",
                documentID: ProjectFixtures.documentID,
                modifiedAt: RecoveryFixtures.fixedNow
            ),
        ]
        let prompt = SpyRecoveryPrompt()
        prompt.decision = .cancel
        var restored: [RecoveredProject] = []
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: false,
            prompt: prompt,
            restore: { restored.append($0) }
        )

        XCTAssertTrue(try coordinator.shouldOfferRecovery())
        try coordinator.offerRecoveryIfNeeded()
        try coordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(prompt.presentedProjects.count, 1)
        XCTAssertTrue(restored.isEmpty)
        XCTAssertTrue(store.removedDocumentIDs.isEmpty)
    }

    func testRestoreOpensOnlySelectedProjectsWithoutDeletingThem()
        throws
    {
        let first = RecoveryFixtures.recovered(
            text: "first",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        let second = RecoveryFixtures.recovered(
            text: "second",
            documentID: RecoveryFixtures.secondDocumentID,
            modifiedAt: RecoveryFixtures.fixedNow.addingTimeInterval(-1)
        )
        let store = SpyRecoveryStore()
        store.projects = [first, second]
        let prompt = SpyRecoveryPrompt()
        prompt.decision = .restore([
            RecoveryFixtures.secondDocumentID,
        ])
        var restored: [RecoveredProject] = []
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: false,
            prompt: prompt,
            restore: { restored.append($0) }
        )

        try coordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(restored, [second])
        XCTAssertTrue(store.removedDocumentIDs.isEmpty)
    }

    func testDiscardAllExplicitlyRemovesEveryRecovery() throws {
        let first = RecoveryFixtures.recovered(
            text: "first",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        let second = RecoveryFixtures.recovered(
            text: "second",
            documentID: RecoveryFixtures.secondDocumentID,
            modifiedAt: RecoveryFixtures.fixedNow.addingTimeInterval(-1)
        )
        let store = SpyRecoveryStore()
        store.projects = [first, second]
        let prompt = SpyRecoveryPrompt()
        prompt.decision = .discardAll
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: false,
            prompt: prompt,
            restore: { _ in
                XCTFail("Discard must not restore")
            }
        )

        try coordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(
            store.removedDocumentIDs,
            [first.documentId, second.documentId]
        )
    }

    func testRecoveryEnumerationFailureIsTypedAndDoesNotPrompt()
        throws
    {
        let store = SpyRecoveryStore()
        store.error = .readFailed
        let prompt = SpyRecoveryPrompt()
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: false,
            prompt: prompt,
            restore: { _ in }
        )

        XCTAssertThrowsError(
            try coordinator.offerRecoveryIfNeeded()
        ) {
            XCTAssertEqual(
                $0 as? RecoveryStoreError,
                .readFailed
            )
        }
        XCTAssertTrue(prompt.presentedProjects.isEmpty)
        XCTAssertTrue(store.removedDocumentIDs.isEmpty)
    }
}
