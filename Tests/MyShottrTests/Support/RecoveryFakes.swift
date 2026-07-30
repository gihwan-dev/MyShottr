import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class ManualRecoveryClock: RecoveryDebounceClock {
    private final class Token: RecoveryScheduledOperation {
        var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private struct Pending {
        let deadline: Duration
        let token: Token
        let operation: @MainActor @Sendable () async -> Void
    }

    private var now: Duration = .zero
    private var pending: [Pending] = []

    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any RecoveryScheduledOperation {
        let token = Token()
        pending.append(
            Pending(
                deadline: now + delay,
                token: token,
                operation: operation
            )
        )
        return token
    }

    func advance(by duration: Duration) async {
        now += duration
        let due = pending
            .filter { !$0.token.isCancelled && $0.deadline <= now }
            .sorted { $0.deadline < $1.deadline }
        pending.removeAll {
            $0.token.isCancelled || $0.deadline <= now
        }
        for item in due where !item.token.isCancelled {
            await item.operation()
        }
    }
}

final class SpyRecoveryStore: RecoveryStoring, @unchecked Sendable {
    struct Write: Equatable {
        let project: MyShottrProject
        let documentId: UUID
    }

    var writes: [Write] = []
    var removedDocumentIDs: [UUID] = []
    var removeAttempts: [UUID] = []
    var removeErrors: [RecoveryStoreError?] = []
    var removeResults: [RecoveryDiscardStageResult] = []
    var stagedDiscardBatches: [[UUID]] = []
    var attemptedDiscardBatches: [[UUID]] = []
    var projects: [RecoveredProject] = []
    var issues: [RecoveryScanIssue] = []
    var error: RecoveryStoreError?
    var scanCallCount = 0

    func write(
        _ project: MyShottrProject,
        documentId: UUID
    ) throws {
        if let error { throw error }
        writes.append(
            Write(project: project, documentId: documentId)
        )
    }

    @discardableResult
    func remove(
        documentId: UUID
    ) throws -> RecoveryDiscardStageResult {
        removeAttempts.append(documentId)
        if !removeErrors.isEmpty,
           let error = removeErrors.removeFirst() {
            throw error
        }
        if let error { throw error }
        let result = removeResults.isEmpty
            ? .committed
            : removeResults.removeFirst()
        removedDocumentIDs.append(documentId)
        projects.removeAll { $0.documentId == documentId }
        return result
    }

    @discardableResult
    func stageDiscard(
        documentIds: [UUID]
    ) throws -> RecoveryDiscardStageResult {
        attemptedDiscardBatches.append(documentIds)
        if let error { throw error }
        guard !documentIds.isEmpty else {
            return .noRecovery
        }
        stagedDiscardBatches.append(documentIds)
        removedDocumentIDs.append(contentsOf: documentIds)
        projects.removeAll {
            documentIds.contains($0.documentId)
        }
        return .committed
    }

    func recoverableProjects() throws -> [RecoveredProject] {
        scanCallCount += 1
        if let error { throw error }
        return projects
    }

    func scanRecoverableProjects() throws -> RecoveryScanResult {
        scanCallCount += 1
        if let error { throw error }
        return RecoveryScanResult(
            projects: projects,
            issues: issues
        )
    }
}

final class RecoveryCleanupAttemptSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var failuresRemaining: Int
    private(set) var attemptCount = 0

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func operation(
        documentIDs: [UUID]
    ) -> RecoveryCleanupOperation {
        RecoveryCleanupOperation(
            documentIDs: documentIDs
        ) { [self] in
            try perform()
        }
    }

    private func perform() throws {
        lock.lock()
        defer { lock.unlock() }
        attemptCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw RecoveryTestError.expected
        }
    }
}

@MainActor
final class SpyRecoveryPrompt: RecoveryPrompting {
    var decision: RecoveryPromptDecision = .cancel
    private(set) var presentedProjects: [[RecoveredProject]] = []

    func present(
        projects: [RecoveredProject]
    ) -> RecoveryPromptDecision {
        presentedProjects.append(projects)
        return decision
    }
}

enum RecoveryTestError: Error, Equatable {
    case expected
}

enum RecoveryFixtures {
    static let secondDocumentID = UUID(
        uuidString: "06A85766-0B28-4B48-8FCA-BE56DF625853"
    )!
    static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    static func project(
        text: String,
        documentID: UUID = ProjectFixtures.documentID
    ) -> MyShottrProject {
        let project = ProjectFixtures.project(text: text)
        let manifest = ProjectManifest(
            formatVersion: project.manifest.formatVersion,
            documentId: documentID,
            createdAt: project.manifest.createdAt,
            updatedAt: project.manifest.updatedAt,
            sourcePixelWidth: project.manifest.sourcePixelWidth,
            sourcePixelHeight: project.manifest.sourcePixelHeight,
            sourceKind: project.manifest.sourceKind,
            sourceScale: project.manifest.sourceScale
        )
        return MyShottrProject(
            manifest: manifest,
            originalPNG: project.originalPNG,
            annotationJSON: project.annotationJSON
        )
    }

    static func recovered(
        text: String,
        documentID: UUID,
        modifiedAt: Date
    ) -> RecoveredProject {
        RecoveredProject(
            documentId: documentID,
            modifiedAt: modifiedAt,
            project: project(text: text, documentID: documentID)
        )
    }
}
