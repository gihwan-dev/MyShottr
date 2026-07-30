import Darwin
import Foundation

protocol RecoveryStoring: Sendable {
    func write(
        _ project: MyShottrProject,
        documentId: UUID
    ) throws
    func remove(documentId: UUID) throws
    @discardableResult
    func stageDiscard(
        documentIds: [UUID]
    ) throws -> RecoveryDiscardStageResult
    func scanRecoverableProjects() throws -> RecoveryScanResult
}

enum RecoveryDiscardStageResult: Equatable, Sendable {
    case noRecovery
    case committed
    case committedAwaitingDurability
}

struct RecoveredProject: Equatable, Sendable {
    let documentId: UUID
    let modifiedAt: Date
    let project: MyShottrProject
}

enum RecoveryStoreError: Error, Equatable, Sendable {
    case invalidRoot
    case invalidPackagePath(String)
    case invalidPackage(UUID, ProjectPackageError)
    case documentIdentifierMismatch(path: UUID, manifest: UUID)
    case readFailed
    case writeFailed(UUID)
    case removeFailed(UUID)
    case discardStageFailed(UUID)
    case discardRollbackFailed
    case discardRollbackConflict(UUID)
    case discardCleanupFailed(String)
    case invalidDiscardTransactionPath(String)
}

struct RecoveryScanIssue: Error, Equatable, Sendable {
    let entryName: String
    let error: RecoveryStoreError
}

struct RecoveryScanResult: Equatable, Sendable {
    let projects: [RecoveredProject]
    let issues: [RecoveryScanIssue]
}

struct RecoveryStoreFileSystem: Sendable {
    let moveItem: @Sendable (URL, URL) throws -> Void
    let synchronizeDirectory: @Sendable (URL) throws -> Void

    static let live = RecoveryStoreFileSystem(
        moveItem: {
            try FileManager.default.moveItem(
                at: $0,
                to: $1
            )
        },
        synchronizeDirectory: { directory in
            let descriptor = directory.path.withCString {
                Darwin.open($0, O_RDONLY)
            }
            guard descriptor >= 0 else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno)
                )
            }
            defer { Darwin.close(descriptor) }
            guard Darwin.fsync(descriptor) == 0 else {
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(errno)
                )
            }
        }
    )
}

struct RecoveryStore: RecoveryStoring {
    private enum DiscardTransactionState: String {
        case pending
        case committed
    }

    private struct DiscardTransaction {
        let id: UUID
        let state: DiscardTransactionState
        let url: URL
    }

    private let root: URL
    private let projectStore: any ProjectPackageStoring
    private let now: @Sendable () -> Date
    private let fileSystem: RecoveryStoreFileSystem
    private let makeTransactionID: @Sendable () -> UUID

    static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/MyShottr/Recovery",
                isDirectory: true
            )
    }

    init(
        root: URL = RecoveryStore.defaultRoot,
        projectStore: any ProjectPackageStoring = ProjectPackageStore(),
        now: @escaping @Sendable () -> Date = Date.init,
        fileSystem: RecoveryStoreFileSystem = .live,
        makeTransactionID:
            @escaping @Sendable () -> UUID = UUID.init
    ) throws {
        self.root = root.standardizedFileURL
        self.projectStore = projectStore
        self.now = now
        self.fileSystem = fileSystem
        self.makeTransactionID = makeTransactionID
        try Self.prepareRoot(self.root)
        try recoverDiscardTransactions()
    }

    func write(
        _ project: MyShottrProject,
        documentId: UUID
    ) throws {
        try validateRoot()
        guard project.manifest.documentId == documentId else {
            throw RecoveryStoreError.documentIdentifierMismatch(
                path: documentId,
                manifest: project.manifest.documentId
            )
        }

        let destination = packageURL(for: documentId)
        do {
            try projectStore.save(project, to: destination)
            let validated = try projectStore.load(from: destination)
            guard validated.manifest.documentId == documentId else {
                throw RecoveryStoreError.documentIdentifierMismatch(
                    path: documentId,
                    manifest: validated.manifest.documentId
                )
            }
            try FileManager.default.setAttributes(
                [.modificationDate: now()],
                ofItemAtPath: destination.path
            )
        } catch let error as RecoveryStoreError {
            throw error
        } catch let error as ProjectPackageError {
            throw RecoveryStoreError.invalidPackage(
                documentId,
                error
            )
        } catch {
            throw RecoveryStoreError.writeFailed(documentId)
        }
    }

    func remove(documentId: UUID) throws {
        _ = try stageDiscard(documentIds: [documentId])
    }

    @discardableResult
    func stageDiscard(
        documentIds: [UUID]
    ) throws -> RecoveryDiscardStageResult {
        try validateRoot()
        let uniqueDocumentIDs = Array(Set(documentIds)).sorted {
            $0.uuidString < $1.uuidString
        }
        guard !uniqueDocumentIDs.isEmpty else {
            return .noRecovery
        }

        var entries: [(documentID: UUID, url: URL)] = []
        for documentID in uniqueDocumentIDs {
            if let entry = try recoveryEntry(
                for: documentID
            ) {
                entries.append((documentID, entry))
            }
        }
        guard !entries.isEmpty else {
            return .noRecovery
        }

        let transactionID = makeTransactionID()
        let pendingURL = discardTransactionURL(
            id: transactionID,
            state: .pending
        )
        let committedURL = discardTransactionURL(
            id: transactionID,
            state: .committed
        )
        guard !FileManager.default.fileExists(
            atPath: pendingURL.path
        ),
        !FileManager.default.fileExists(
            atPath: committedURL.path
        ) else {
            throw RecoveryStoreError.discardStageFailed(
                entries[0].documentID
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: pendingURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try fileSystem.synchronizeDirectory(root)
        } catch {
            try? FileManager.default.removeItem(at: pendingURL)
            throw RecoveryStoreError.discardStageFailed(
                entries[0].documentID
            )
        }

        var movedDocumentIDs: [UUID] = []
        var failedDocumentID = entries[0].documentID
        do {
            for entry in entries {
                failedDocumentID = entry.documentID
                try fileSystem.moveItem(
                    entry.url,
                    pendingURL.appendingPathComponent(
                        entry.url.lastPathComponent,
                        isDirectory: true
                    )
                )
                movedDocumentIDs.append(entry.documentID)
            }
            try fileSystem.synchronizeDirectory(pendingURL)
            try fileSystem.synchronizeDirectory(root)
        } catch {
            do {
                try rollbackDiscardTransaction(
                    at: pendingURL,
                    documentIDs: movedDocumentIDs
                )
            } catch {
                throw RecoveryStoreError.discardRollbackFailed
            }
            throw RecoveryStoreError.discardStageFailed(
                failedDocumentID
            )
        }

        do {
            try fileSystem.moveItem(
                pendingURL,
                committedURL
            )
        } catch {
            do {
                try rollbackDiscardTransaction(
                    at: pendingURL,
                    documentIDs: movedDocumentIDs
                )
            } catch {
                throw RecoveryStoreError.discardRollbackFailed
            }
            throw RecoveryStoreError.discardStageFailed(
                failedDocumentID
            )
        }

        do {
            try fileSystem.synchronizeDirectory(root)
            return .committed
        } catch {
            return .committedAwaitingDurability
        }
    }

    func scanRecoverableProjects() throws -> RecoveryScanResult {
        try validateRoot()
        try recoverDiscardTransactions()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw RecoveryStoreError.readFailed
        }

        var recovered: [RecoveredProject] = []
        var issues: [RecoveryScanIssue] = []
        for entry in entries {
            do {
                recovered.append(
                    try recoveredProject(from: entry)
                )
            } catch let error as RecoveryStoreError {
                issues.append(
                    RecoveryScanIssue(
                        entryName: entry.lastPathComponent,
                        error: error
                    )
                )
            } catch {
                issues.append(
                    RecoveryScanIssue(
                        entryName: entry.lastPathComponent,
                        error: .readFailed
                    )
                )
            }
        }

        let sortedProjects = recovered.sorted {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.documentId.uuidString
                < $1.documentId.uuidString
        }
        return RecoveryScanResult(
            projects: sortedProjects,
            issues: issues.sorted {
                $0.entryName < $1.entryName
            }
        )
    }

    private func recoveredProject(
        from entry: URL
    ) throws -> RecoveredProject {
        let documentId = try documentIdentifier(for: entry)
        let values: URLResourceValues
        do {
            values = try entry.resourceValues(
                forKeys: [
                    .contentModificationDateKey,
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ]
            )
        } catch {
            throw RecoveryStoreError.invalidPackagePath(
                entry.lastPathComponent
            )
        }
        guard values.isDirectory == true,
              values.isSymbolicLink != true,
              let modifiedAt = values.contentModificationDate
        else {
            throw RecoveryStoreError.invalidPackagePath(
                entry.lastPathComponent
            )
        }

        let project: MyShottrProject
        do {
            project = try projectStore.load(from: entry)
        } catch let error as ProjectPackageError {
            throw RecoveryStoreError.invalidPackage(
                documentId,
                error
            )
        } catch {
            throw RecoveryStoreError.readFailed
        }
        guard project.manifest.documentId == documentId else {
            throw RecoveryStoreError.documentIdentifierMismatch(
                path: documentId,
                manifest: project.manifest.documentId
            )
        }
        return RecoveredProject(
            documentId: documentId,
            modifiedAt: modifiedAt,
            project: project
        )
    }

    private func recoveryEntry(
        for documentID: UUID
    ) throws -> URL? {
        let destination = packageURL(for: documentID)
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw RecoveryStoreError.readFailed
        }
        guard let entry = entries.first(
            where: {
                $0.lastPathComponent
                    == destination.lastPathComponent
            }
        ) else {
            return nil
        }
        let values: URLResourceValues
        do {
            values = try entry.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ]
            )
        } catch {
            throw RecoveryStoreError.invalidPackagePath(
                entry.lastPathComponent
            )
        }
        guard values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw RecoveryStoreError.invalidPackagePath(
                entry.lastPathComponent
            )
        }
        return entry
    }

    private func recoverDiscardTransactions() throws {
        try validateRoot()
        let entries: [URL]
        do {
            entries = try FileManager.default
                .contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ],
                    options: []
                )
        } catch {
            throw RecoveryStoreError.readFailed
        }

        for entry in entries.sorted(
            by: {
                $0.lastPathComponent
                    < $1.lastPathComponent
            }
        ) {
            guard let transaction = discardTransaction(
                for: entry
            ) else {
                continue
            }
            try validateDiscardTransactionDirectory(
                transaction.url
            )
            switch transaction.state {
            case .pending:
                let documentIDs =
                    try discardTransactionDocumentIDs(
                        at: transaction.url
                    )
                try rollbackDiscardTransaction(
                    at: transaction.url,
                    documentIDs: documentIDs
                )
            case .committed:
                _ = try discardTransactionDocumentIDs(
                    at: transaction.url
                )
                do {
                    try FileManager.default.removeItem(
                        at: transaction.url
                    )
                    try fileSystem
                        .synchronizeDirectory(root)
                } catch {
                    throw RecoveryStoreError
                        .discardCleanupFailed(
                            transaction.url
                                .lastPathComponent
                        )
                }
            }
        }
    }

    private func rollbackDiscardTransaction(
        at transactionURL: URL,
        documentIDs: [UUID]
    ) throws {
        for documentID in documentIDs.reversed() {
            let source = transactionURL
                .appendingPathComponent(
                    "\(documentID.uuidString).myshottr",
                    isDirectory: true
                )
            guard FileManager.default.fileExists(
                atPath: source.path
            ) else {
                continue
            }
            let destination = packageURL(for: documentID)
            guard !FileManager.default.fileExists(
                atPath: destination.path
            ) else {
                throw RecoveryStoreError
                    .discardRollbackConflict(documentID)
            }
            try fileSystem.moveItem(source, destination)
        }
        try fileSystem.synchronizeDirectory(root)
        try FileManager.default.removeItem(at: transactionURL)
        try fileSystem.synchronizeDirectory(root)
    }

    private func validateDiscardTransactionDirectory(
        _ url: URL
    ) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                ]
            )
        } catch {
            throw RecoveryStoreError
                .invalidDiscardTransactionPath(
                    url.lastPathComponent
                )
        }
        guard values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw RecoveryStoreError
                .invalidDiscardTransactionPath(
                    url.lastPathComponent
                )
        }
    }

    private func discardTransactionDocumentIDs(
        at transactionURL: URL
    ) throws -> [UUID] {
        let entries: [URL]
        do {
            entries = try FileManager.default
                .contentsOfDirectory(
                    at: transactionURL,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ],
                    options: []
                )
        } catch {
            throw RecoveryStoreError
                .invalidDiscardTransactionPath(
                    transactionURL.lastPathComponent
                )
        }
        var documentIDs: [UUID] = []
        for entry in entries {
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ]
                )
            } catch {
                throw RecoveryStoreError
                    .invalidDiscardTransactionPath(
                        entry.lastPathComponent
                    )
            }
            guard values.isDirectory == true,
                  values.isSymbolicLink != true,
                  entry.pathExtension == "myshottr",
                  let documentID = UUID(
                    uuidString: entry
                        .deletingPathExtension()
                        .lastPathComponent
                  ),
                  documentID.uuidString
                    == entry.deletingPathExtension()
                        .lastPathComponent
                        .uppercased()
            else {
                throw RecoveryStoreError
                    .invalidDiscardTransactionPath(
                        entry.lastPathComponent
                    )
            }
            documentIDs.append(documentID)
        }
        return documentIDs.sorted {
            $0.uuidString < $1.uuidString
        }
    }

    private func discardTransaction(
        for entry: URL
    ) -> DiscardTransaction? {
        let name = entry.lastPathComponent
        guard name.hasPrefix(".discard-") else {
            return nil
        }
        for state in [
            DiscardTransactionState.pending,
            .committed,
        ] {
            let suffix = ".\(state.rawValue)"
            guard name.hasSuffix(suffix) else {
                continue
            }
            let idStart = name.index(
                name.startIndex,
                offsetBy: ".discard-".count
            )
            let idEnd = name.index(
                name.endIndex,
                offsetBy: -suffix.count
            )
            let idString = String(name[idStart..<idEnd])
            guard let id = UUID(uuidString: idString),
                  id.uuidString == idString.uppercased()
            else {
                return nil
            }
            return DiscardTransaction(
                id: id,
                state: state,
                url: entry
            )
        }
        return nil
    }

    private func discardTransactionURL(
        id: UUID,
        state: DiscardTransactionState
    ) -> URL {
        root.appendingPathComponent(
            ".discard-\(id.uuidString).\(state.rawValue)",
            isDirectory: true
        )
    }

    private func validateRoot() throws {
        let values: URLResourceValues
        do {
            values = try root.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
        } catch {
            throw RecoveryStoreError.invalidRoot
        }
        guard values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            throw RecoveryStoreError.invalidRoot
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default
                .attributesOfItem(atPath: root.path)
        } catch {
            throw RecoveryStoreError.invalidRoot
        }
        guard let permissions = attributes[.posixPermissions]
                as? NSNumber,
              permissions.intValue & 0o777 == 0o700
        else {
            throw RecoveryStoreError.invalidRoot
        }
    }

    private func documentIdentifier(for entry: URL) throws -> UUID {
        guard entry.deletingLastPathComponent().standardizedFileURL
                == root,
              entry.pathExtension == "myshottr"
        else {
            throw RecoveryStoreError.invalidPackagePath(
                entry.lastPathComponent
            )
        }
        let name = entry.deletingPathExtension().lastPathComponent
        guard let documentId = UUID(uuidString: name),
              documentId.uuidString == name.uppercased()
        else {
            throw RecoveryStoreError.invalidPackagePath(
                entry.lastPathComponent
            )
        }
        return documentId
    }

    private func packageURL(for documentId: UUID) -> URL {
        root.appendingPathComponent(
            "\(documentId.uuidString).myshottr",
            isDirectory: true
        )
    }

    private static func prepareRoot(_ root: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: root.path) {
            let values: URLResourceValues
            do {
                values = try root.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
            } catch {
                throw RecoveryStoreError.invalidRoot
            }
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw RecoveryStoreError.invalidRoot
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: root,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw RecoveryStoreError.invalidRoot
            }
        }

        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: root.path
            )
        } catch {
            throw RecoveryStoreError.invalidRoot
        }
    }
}
