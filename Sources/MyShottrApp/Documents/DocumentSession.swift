import Foundation

enum DocumentSessionError: Error, Equatable {
    case invalidDocument
    case noOpenDocument
    case noStagedDocument
}

enum DocumentSaveCompletion {
    case saved
    case savedWithNewerChanges
}

@MainActor
final class DocumentSession {
    private(set) var project: MyShottrProject?
    private var stagedProject: MyShottrProject?
    private(set) var modificationRevision: UInt64 = 0
    private(set) var isModified = false {
        didSet { onModifiedStateChange?(isModified) }
    }
    var onModifiedStateChange: ((Bool) -> Void)?

    var isOpen: Bool { project != nil }

    func open(project: MyShottrProject) throws {
        try validate(annotationJSON: project.annotationJSON, for: project.manifest)
        self.project = project
        stagedProject = nil
        modificationRevision = 0
        isModified = false
    }

    func openUnsaved(
        project: MyShottrProject
    ) throws {
        try open(project: project)
        modificationRevision = 1
        isModified = true
    }

    func stage(project: MyShottrProject) throws {
        guard project.manifest.formatVersion == ProjectManifest.currentFormatVersion else {
            throw DocumentSessionError.invalidDocument
        }
        let replacesDocument =
            self.project?.manifest.documentId
                != project.manifest.documentId
        self.project = project
        stagedProject = project
        if replacesDocument {
            modificationRevision = 0
            isModified = false
        }
    }

    func commitStaged(annotationJSON: Data) throws {
        guard var stagedProject else { throw DocumentSessionError.noStagedDocument }
        try validate(annotationJSON: annotationJSON, for: stagedProject.manifest)
        let wasModified = isModified
        stagedProject.annotationJSON = annotationJSON
        project = stagedProject
        self.stagedProject = nil
        isModified = wasModified
    }

    func discardStaged() {
        stagedProject = nil
    }

    func close() {
        project = nil
        stagedProject = nil
        modificationRevision = 0
        isModified = false
    }

    func markModified() throws {
        guard project != nil else { throw DocumentSessionError.noOpenDocument }
        modificationRevision &+= 1
        isModified = true
    }

    func applySnapshot(_ annotationJSON: Data) throws {
        let changed = project?.annotationJSON
            != annotationJSON
        try install(annotationJSON: annotationJSON)
        if changed {
            modificationRevision &+= 1
        }
    }

    func install(annotationJSON: Data) throws {
        guard var project else { throw DocumentSessionError.noOpenDocument }
        try validate(annotationJSON: annotationJSON, for: project.manifest)
        let changed = project.annotationJSON != annotationJSON
        project.annotationJSON = annotationJSON
        self.project = project
        if changed { isModified = true }
    }

    func projectForSave(
        annotationJSON: Data? = nil
    ) throws -> MyShottrProject {
        guard var project else { throw DocumentSessionError.noOpenDocument }
        if let annotationJSON {
            try validate(
                annotationJSON: annotationJSON,
                for: project.manifest
            )
            project.annotationJSON = annotationJSON
        }
        project.manifest.updatedAt = .now
        return project
    }

    @discardableResult
    func completeSave(
        _ savedProject: MyShottrProject,
        expectedModificationRevision: UInt64? = nil
    ) throws -> DocumentSaveCompletion {
        try validate(annotationJSON: savedProject.annotationJSON, for: savedProject.manifest)
        if let expectedModificationRevision,
           modificationRevision
            != expectedModificationRevision
        {
            isModified = true
            return .savedWithNewerChanges
        }
        project = savedProject
        isModified = false
        return .saved
    }

    func sourcePNG(for documentID: UUID) -> Data? {
        if let project, project.manifest.documentId == documentID { return project.originalPNG }
        if let stagedProject, stagedProject.manifest.documentId == documentID { return stagedProject.originalPNG }
        return nil
    }

    private func validate(annotationJSON: Data, for manifest: ProjectManifest) throws {
        guard
            manifest.formatVersion
                == ProjectManifest.currentFormatVersion
        else {
            throw DocumentSessionError.invalidDocument
        }
        do {
            try EditorDocumentValidator.validate(
                annotationJSON,
                expectedPixelWidth: manifest.sourcePixelWidth,
                expectedPixelHeight: manifest.sourcePixelHeight
            )
        } catch {
            throw DocumentSessionError.invalidDocument
        }
    }
}
