import Foundation

protocol RecoveryStoring: Sendable {
    func write(
        _ project: MyShottrProject,
        documentId: UUID
    ) throws
    func remove(documentId: UUID) throws
    func scanRecoverableProjects() throws -> RecoveryScanResult
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
}

struct RecoveryScanIssue: Error, Equatable, Sendable {
    let entryName: String
    let error: RecoveryStoreError
}

struct RecoveryScanResult: Equatable, Sendable {
    let projects: [RecoveredProject]
    let issues: [RecoveryScanIssue]
}

struct RecoveryStore: RecoveryStoring {
    private let root: URL
    private let projectStore: any ProjectPackageStoring
    private let now: @Sendable () -> Date

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
        now: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.root = root.standardizedFileURL
        self.projectStore = projectStore
        self.now = now
        try Self.prepareRoot(self.root)
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
        try validateRoot()
        let destination = packageURL(for: documentId)
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
            where: { $0.lastPathComponent == destination.lastPathComponent }
        ) else {
            return
        }
        do {
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true,
                  values.isSymbolicLink != true
            else {
                throw RecoveryStoreError.invalidPackagePath(
                    entry.lastPathComponent
                )
            }
            try FileManager.default.removeItem(at: entry)
        } catch let error as RecoveryStoreError {
            throw error
        } catch {
            throw RecoveryStoreError.removeFailed(documentId)
        }
    }

    func scanRecoverableProjects() throws -> RecoveryScanResult {
        try validateRoot()
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
