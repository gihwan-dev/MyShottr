import Foundation

enum DocumentSessionError: Error, Equatable {
    case invalidDocument
    case noOpenDocument
}

@MainActor
final class DocumentSession {
    private static let supportedElementTypes: Set<String> = [
        "rectangle", "arrow", "text", "freehand", "highlighter", "redaction", "numberMarker",
    ]

    private(set) var project: MyShottrProject?
    private(set) var isModified = false

    var isOpen: Bool { project != nil }

    func open(project: MyShottrProject) throws {
        try validate(annotationJSON: project.annotationJSON, for: project.manifest)
        self.project = project
        isModified = false
    }

    func close() {
        project = nil
        isModified = false
    }

    func markModified() throws {
        guard project != nil else { throw DocumentSessionError.noOpenDocument }
        isModified = true
    }

    func install(annotationJSON: Data) throws {
        guard var project else { throw DocumentSessionError.noOpenDocument }
        try validate(annotationJSON: annotationJSON, for: project.manifest)
        project.annotationJSON = annotationJSON
        self.project = project
        isModified = true
    }

    func sourcePNG(for documentID: UUID) -> Data? {
        guard let project, project.manifest.documentId == documentID else { return nil }
        return project.originalPNG
    }

    private func validate(annotationJSON: Data, for manifest: ProjectManifest) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: annotationJSON)
        } catch {
            throw DocumentSessionError.invalidDocument
        }
        guard let document = object as? [String: Any],
              let schemaVersion = document["schemaVersion"] as? Int,
              schemaVersion == 1,
              let sourcePixelWidth = document["sourcePixelWidth"] as? Int,
              let sourcePixelHeight = document["sourcePixelHeight"] as? Int,
              sourcePixelWidth == manifest.sourcePixelWidth,
              sourcePixelHeight == manifest.sourcePixelHeight,
              let elements = document["elements"] as? [[String: Any]],
              document["defaults"] is [String: Any]
        else {
            throw DocumentSessionError.invalidDocument
        }
        guard elements.allSatisfy({ element in
            guard let type = element["type"] as? String else { return false }
            return Self.supportedElementTypes.contains(type)
        }) else {
            throw DocumentSessionError.invalidDocument
        }
    }
}
