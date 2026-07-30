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

    func testModificationRevisionAdvancesForEveryEditorChangeSignal()
        throws
    {
        let session = DocumentSession(
            recoveryStore: SpyRecoveryStore(),
            recoveryClock: ManualRecoveryClock()
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )

        XCTAssertEqual(session.modificationRevision, 0)

        try session.markModified()
        try session.markModified()

        XCTAssertEqual(session.modificationRevision, 2)
    }

    func testApplyingChangedSnapshotAdvancesModificationRevision()
        throws
    {
        let session = DocumentSession(
            recoveryStore: SpyRecoveryStore(),
            recoveryClock: ManualRecoveryClock()
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )

        try session.applySnapshot(
            ProjectFixtures.project(text: "changed")
                .annotationJSON
        )

        XCTAssertEqual(session.modificationRevision, 1)
    }

    func testMarkModifiedInstallsProviderResultBeforeRecoveryWrite()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        let latest = ProjectFixtures.project(text: "latest")
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        session.recoverySnapshotProvider = {
            latest.annotationJSON
        }

        try session.markModified()
        await clock.advance(by: .seconds(2))

        XCTAssertEqual(
            recoveryStore.writes.map(\.project.annotationJSON),
            [latest.annotationJSON]
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            latest.annotationJSON
        )
    }

    func testInvalidProviderResultIsRejectedWithoutRecoveryWrite()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        let initial = ProjectFixtures.project(text: "initial")
        var reportedErrors: [DocumentSessionError] = []
        try session.open(project: initial)
        session.recoverySnapshotProvider = {
            Data("invalid".utf8)
        }
        session.onRecoveryFailure = {
            if let error = $0 as? DocumentSessionError {
                reportedErrors.append(error)
            }
        }

        try session.markModified()
        await clock.advance(by: .seconds(2))

        XCTAssertEqual(reportedErrors, [.invalidDocument])
        XCTAssertTrue(recoveryStore.writes.isEmpty)
        XCTAssertEqual(session.project, initial)
    }

    func testQuitBeforeDebounceFlushesLatestAndCancelsPendingWrite()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        let latest = ProjectFixtures.project(
            text: "quit-before-debounce"
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        session.recoverySnapshotProvider = {
            latest.annotationJSON
        }
        try session.markModified()

        try await session.flushRecoveryForTermination()
        await clock.advance(by: .seconds(2))

        XCTAssertEqual(
            recoveryStore.writes.map(\.project.annotationJSON),
            [latest.annotationJSON]
        )
        XCTAssertTrue(recoveryStore.removedDocumentIDs.isEmpty)
    }

    func testQuitAfterDebounceKeepsLatestRecoveryIntact()
        async throws
    {
        let clock = ManualRecoveryClock()
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: clock
        )
        let latest = ProjectFixtures.project(
            text: "quit-after-debounce"
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        session.recoverySnapshotProvider = {
            latest.annotationJSON
        }
        try session.markModified()
        await clock.advance(by: .seconds(2))

        try await session.flushRecoveryForTermination()

        XCTAssertEqual(
            recoveryStore.writes.last?.project.annotationJSON,
            latest.annotationJSON
        )
        XCTAssertTrue(recoveryStore.removedDocumentIDs.isEmpty)
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

    func testEditDuringSaveKeepsRecoveryAndModifiedState()
        throws
    {
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: ManualRecoveryClock()
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        try session.applySnapshot(
            ProjectFixtures.project(text: "save snapshot")
                .annotationJSON
        )
        let saveRevision = session.modificationRevision
        let savedProject = try session.projectForSave()

        let latestProject = ProjectFixtures.project(
            text: "newer edit"
        )
        try session.applySnapshot(
            latestProject.annotationJSON
        )
        try session.completeSave(
            savedProject,
            expectedModificationRevision: saveRevision
        )

        XCTAssertTrue(session.isModified)
        XCTAssertEqual(
            session.modificationRevision,
            saveRevision + 1
        )
        XCTAssertTrue(
            recoveryStore.removedDocumentIDs.isEmpty
        )
        XCTAssertEqual(
            session.project?.annotationJSON,
            latestProject.annotationJSON
        )
    }

    func testRecoveryRemovalFailureKeepsSavedStateAndMarksCleanupPending()
        throws
    {
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

        let result = try session.completeSave(
            session.projectForSave()
        )

        XCTAssertEqual(
            result,
            .savedRecoveryCleanupPending
        )
        XCTAssertFalse(session.isModified)
        XCTAssertEqual(
            session.pendingRecoveryCleanupDocumentID,
            ProjectFixtures.documentID
        )

        session.close()

        XCTAssertNil(
            session.pendingRecoveryCleanupDocumentID
        )
    }

    func testPendingRecoveryCleanupRetriesTheSameRemoval() throws {
        let recoveryStore = SpyRecoveryStore()
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: ManualRecoveryClock()
        )
        try session.open(
            project: ProjectFixtures.project(text: "initial")
        )
        try session.applySnapshot(
            ProjectFixtures.project(text: "saved").annotationJSON
        )
        recoveryStore.error = .removeFailed(
            ProjectFixtures.documentID
        )
        XCTAssertEqual(
            try session.completeSave(session.projectForSave()),
            .savedRecoveryCleanupPending
        )
        recoveryStore.error = nil

        try session.retryPendingRecoveryCleanup()

        XCTAssertEqual(
            recoveryStore.removedDocumentIDs,
            [ProjectFixtures.documentID]
        )
        XCTAssertNil(session.pendingRecoveryCleanupDocumentID)
        XCTAssertFalse(session.isModified)
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
        let recoveryStore = SpyRecoveryStore()
        let recovered = ProjectFixtures.project(text: "recovered")
        recoveryStore.projects = [
            RecoveryFixtures.recovered(
                text: "recovered",
                documentID: recovered.manifest.documentId,
                modifiedAt: RecoveryFixtures.fixedNow
            ),
        ]
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: ManualRecoveryClock()
        )
        session.prepareForRecoveryRestore()

        try session.stage(project: recovered)
        try session.commitStaged(
            annotationJSON: recovered.annotationJSON
        )

        XCTAssertTrue(session.isModified)
        XCTAssertTrue(recoveryStore.removedDocumentIDs.isEmpty)
        XCTAssertEqual(recoveryStore.projects.count, 1)
    }

    func testRestoredDocumentRecoveryIsRemovedOnlyAfterSuccessfulSave()
        throws
    {
        let recoveryStore = SpyRecoveryStore()
        let recovered = RecoveryFixtures.recovered(
            text: "recovered",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        recoveryStore.projects = [recovered]
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: ManualRecoveryClock()
        )
        session.prepareForRecoveryRestore()
        try session.stage(project: recovered.project)
        try session.commitStaged(
            annotationJSON: recovered.project.annotationJSON
        )

        XCTAssertTrue(recoveryStore.removedDocumentIDs.isEmpty)

        try session.completeSave(session.projectForSave())

        XCTAssertEqual(
            recoveryStore.removedDocumentIDs,
            [ProjectFixtures.documentID]
        )
    }

    func testRestoredDocumentRecoveryIsRemovedOnlyAfterExplicitDiscard()
        throws
    {
        let recoveryStore = SpyRecoveryStore()
        let recovered = RecoveryFixtures.recovered(
            text: "recovered",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        recoveryStore.projects = [recovered]
        let session = DocumentSession(
            recoveryStore: recoveryStore,
            recoveryClock: ManualRecoveryClock()
        )
        session.prepareForRecoveryRestore()
        try session.stage(project: recovered.project)
        try session.commitStaged(
            annotationJSON: recovered.project.annotationJSON
        )

        XCTAssertTrue(recoveryStore.removedDocumentIDs.isEmpty)

        try session.discardRecovery()

        XCTAssertEqual(
            recoveryStore.removedDocumentIDs,
            [ProjectFixtures.documentID]
        )
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

        XCTAssertEqual(store.scanCallCount, 1)
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

    func testCleanRelaunchAfterCancelOffersUnresolvedRecovery()
        throws
    {
        let recovered = RecoveryFixtures.recovered(
            text: "still unresolved",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        let store = SpyRecoveryStore()
        store.projects = [recovered]
        let firstPrompt = SpyRecoveryPrompt()
        firstPrompt.decision = .cancel
        let firstCoordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: false,
            prompt: firstPrompt,
            restore: { _ in
                XCTFail("Cancel must not restore")
            }
        )
        try firstCoordinator.offerRecoveryIfNeeded()

        let cleanPrompt = SpyRecoveryPrompt()
        cleanPrompt.decision = .restore([
            ProjectFixtures.documentID,
        ])
        var restored: [RecoveredProject] = []
        let cleanCoordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: true,
            prompt: cleanPrompt,
            restore: { restored.append($0) }
        )

        try cleanCoordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(restored, [recovered])
        XCTAssertTrue(store.removedDocumentIDs.isEmpty)
        XCTAssertEqual(store.projects, [recovered])

        let afterCrashPrompt = SpyRecoveryPrompt()
        afterCrashPrompt.decision = .cancel
        let afterCrashCoordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: true,
            prompt: afterCrashPrompt,
            restore: { _ in
                XCTFail("Crash relaunch cancellation must not restore")
            }
        )

        try afterCrashCoordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(
            afterCrashPrompt.presentedProjects,
            [[recovered]]
        )
    }

    func testPartialRestoreKeepsEveryRecoveryForCrashRelaunch()
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

        let nextPrompt = SpyRecoveryPrompt()
        nextPrompt.decision = .cancel
        let nextCoordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: true,
            prompt: nextPrompt,
            restore: { _ in
                XCTFail("Cancel must not restore")
            }
        )
        try nextCoordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(
            nextPrompt.presentedProjects,
            [[first, second]]
        )
    }

    func testRestoreFailureLeavesRecoveryAvailableForCleanRelaunch()
        throws
    {
        let recovered = RecoveryFixtures.recovered(
            text: "load failure",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        let store = SpyRecoveryStore()
        store.projects = [recovered]
        let prompt = SpyRecoveryPrompt()
        prompt.decision = .restore([
            ProjectFixtures.documentID,
        ])
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: false,
            prompt: prompt,
            restore: { _ in
                throw RecoveryTestError.expected
            }
        )

        XCTAssertThrowsError(
            try coordinator.offerRecoveryIfNeeded()
        ) {
            XCTAssertEqual(
                $0 as? RecoveryCoordinatorError,
                .restoreFailed(ProjectFixtures.documentID)
            )
        }
        XCTAssertTrue(store.removedDocumentIDs.isEmpty)
        XCTAssertEqual(store.projects, [recovered])

        let relaunchPrompt = SpyRecoveryPrompt()
        relaunchPrompt.decision = .cancel
        let relaunch = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: true,
            prompt: relaunchPrompt,
            restore: { _ in
                XCTFail("Relaunch cancellation must not restore")
            }
        )
        try relaunch.offerRecoveryIfNeeded()

        XCTAssertEqual(relaunchPrompt.presentedProjects, [[recovered]])
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
        XCTAssertEqual(
            store.stagedDiscardBatches,
            [[first.documentId, second.documentId]]
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

    func testMixedScanReportsCorruptEntryAndStillPromptsValid()
        throws
    {
        let valid = RecoveryFixtures.recovered(
            text: "valid",
            documentID: ProjectFixtures.documentID,
            modifiedAt: RecoveryFixtures.fixedNow
        )
        let issue = RecoveryScanIssue(
            entryName: "corrupt.myshottr",
            error: .invalidPackagePath("corrupt.myshottr")
        )
        let store = SpyRecoveryStore()
        store.projects = [valid]
        store.issues = [issue]
        let prompt = SpyRecoveryPrompt()
        prompt.decision = .cancel
        var reportedIssues: [RecoveryScanIssue] = []
        let coordinator = RecoveryCoordinator(
            recoveryStore: store,
            previousSessionWasClean: true,
            prompt: prompt,
            reportIssue: { reportedIssues.append($0) },
            restore: { _ in
                XCTFail("Cancel must not restore")
            }
        )

        try coordinator.offerRecoveryIfNeeded()

        XCTAssertEqual(reportedIssues, [issue])
        XCTAssertEqual(prompt.presentedProjects, [[valid]])
        XCTAssertTrue(store.removedDocumentIDs.isEmpty)
    }
}
