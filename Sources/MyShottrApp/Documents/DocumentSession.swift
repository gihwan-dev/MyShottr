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
    private static let supportedElementTypes: Set<String> = [
        "rectangle", "arrow", "line", "text", "freehand", "highlighter", "blur", "redaction", "numberMarker",
    ]

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
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: annotationJSON)
        } catch {
            throw DocumentSessionError.invalidDocument
        }
        guard manifest.formatVersion == ProjectManifest.currentFormatVersion,
              let document = object as? [String: Any],
              Set(document.keys) == ["schemaVersion", "sourcePixelWidth", "sourcePixelHeight", "elements", "presentation", "defaults"],
              let schemaVersion = integer(document["schemaVersion"]), schemaVersion == 2,
              let sourcePixelWidth = integer(document["sourcePixelWidth"]),
              let sourcePixelHeight = integer(document["sourcePixelHeight"]),
              sourcePixelWidth == manifest.sourcePixelWidth,
              sourcePixelHeight == manifest.sourcePixelHeight,
              let elements = document["elements"] as? [[String: Any]],
              let presentation = document["presentation"] as? [String: Any],
              Set(presentation.keys) == ["type"], presentation["type"] as? String == "none",
              let defaults = document["defaults"] as? [String: Any],
              validateDefaults(defaults)
        else {
            throw DocumentSessionError.invalidDocument
        }
        var ids = Set<String>()
        var zIndices = Set<Double>()
        guard elements.allSatisfy({ element in
            guard let id = element["id"] as? String,
                  let zIndex = number(element["zIndex"]),
                  ids.insert(id).inserted,
                  zIndices.insert(zIndex).inserted
            else { return false }
            return validateElement(element)
        }) else {
            throw DocumentSessionError.invalidDocument
        }
    }

    private static let colors: Set<String> = ["#000000", "#FF4D4F", "#1677FF", "#FADB14"]
    private static let opacities: Set<Double> = [0.25, 0.5, 0.75, 1]

    private func validateDefaults(_ defaults: [String: Any]) -> Bool {
        Set(defaults.keys) == ["color", "strokeWidth", "textSize", "roughness", "opacity"]
            && Self.colors.contains(defaults["color"] as? String ?? "")
            && [2, 4, 8].contains(integer(defaults["strokeWidth"]) ?? -1)
            && [16, 24, 36].contains(integer(defaults["textSize"]) ?? -1)
            && [0, 1, 2].contains(integer(defaults["roughness"]) ?? -1)
            && Self.opacities.contains(number(defaults["opacity"]) ?? -1)
    }

    private func validateElement(_ element: [String: Any]) -> Bool {
        guard let type = element["type"] as? String, Self.supportedElementTypes.contains(type),
              let id = element["id"] as? String, !id.isEmpty,
              ["x", "y", "rotation", "zIndex", "seed"].allSatisfy({ finite(element[$0]) }),
              let width = number(element["width"]), width >= 0,
              let height = number(element["height"]), height >= 0,
              let opacity = number(element["opacity"]), Self.opacities.contains(opacity)
        else { return false }
        let base: Set<String> = ["id", "type", "x", "y", "width", "height", "rotation", "opacity", "zIndex", "seed"]
        switch type {
        case "rectangle":
            return Set(element.keys) == base.union(["strokeColor", "strokeWidth", "fillColor", "roughness"])
                && style(element) && (element["fillColor"] is NSNull || Self.colors.contains(element["fillColor"] as? String ?? ""))
        case "arrow", "line":
            return Set(element.keys) == base.union(["points", "strokeColor", "strokeWidth", "roughness"])
                && style(element) && points(element["points"], count: 2)
        case "text":
            return Set(element.keys) == base.union(["text", "color", "fontSize"])
                && element["text"] is String && Self.colors.contains(element["color"] as? String ?? "")
                && [16, 24, 36].contains(integer(element["fontSize"]) ?? -1)
        case "freehand":
            return Set(element.keys) == base.union(["points", "color", "strokeWidth"])
                && points(element["points"], minimum: 1) && Self.colors.contains(element["color"] as? String ?? "")
                && [2, 4, 8].contains(integer(element["strokeWidth"]) ?? -1)
        case "highlighter":
            return Set(element.keys) == base.union(["points", "color", "strokeWidth"])
                && points(element["points"], minimum: 1) && Self.colors.contains(element["color"] as? String ?? "")
                && integer(element["strokeWidth"]) == 8 && [0.25, 0.5].contains(number(element["opacity"]) ?? -1)
        case "blur":
            return Set(element.keys) == base.union(["radius"])
                && integer(element["radius"]) == 12 && number(element["opacity"]) == 1 && number(element["rotation"]) == 0
        case "redaction":
            return Set(element.keys) == base.union(["color"])
                && element["color"] as? String == "#000000" && number(element["opacity"]) == 1
        case "numberMarker":
            return Set(element.keys) == base.union(["number", "color"])
                && finite(element["number"]) && Self.colors.contains(element["color"] as? String ?? "")
        default: return false
        }
    }

    private func style(_ element: [String: Any]) -> Bool {
        Self.colors.contains(element["strokeColor"] as? String ?? "")
            && [2, 4, 8].contains(integer(element["strokeWidth"]) ?? -1)
            && [0, 1, 2].contains(integer(element["roughness"]) ?? -1)
    }

    private func points(_ value: Any?, count: Int? = nil, minimum: Int = 0) -> Bool {
        guard let points = value as? [[String: Any]], points.count >= minimum, count == nil || points.count == count else { return false }
        return points.allSatisfy { Set($0.keys) == ["x", "y"] && finite($0["x"]) && finite($0["y"]) }
    }

    private func finite(_ value: Any?) -> Bool { number(value) != nil }
    private func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }
    private func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number.rounded() == number, number >= Double(Int.min), number <= Double(Int.max) else { return nil }
        return Int(number)
    }
}
