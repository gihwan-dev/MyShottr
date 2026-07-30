import Foundation

enum DocumentSessionError: Error, Equatable {
    case invalidDocument
    case noOpenDocument
    case noStagedDocument
    case recoverySnapshotUnavailable
}

@MainActor
protocol RecoveryScheduledOperation: AnyObject {
    func cancel()
}

@MainActor
protocol RecoveryDebounceClock {
    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any RecoveryScheduledOperation
}

@MainActor
private final class TaskRecoveryScheduledOperation:
    RecoveryScheduledOperation
{
    var task: Task<Void, Never>?

    func cancel() {
        task?.cancel()
        task = nil
    }
}

@MainActor
final class ContinuousRecoveryClock: RecoveryDebounceClock {
    func schedule(
        after delay: Duration,
        operation: @escaping @MainActor @Sendable () async -> Void
    ) -> any RecoveryScheduledOperation {
        let scheduled = TaskRecoveryScheduledOperation()
        scheduled.task = Task { @MainActor [weak scheduled] in
            do {
                try await ContinuousClock().sleep(for: delay)
            } catch {
                return
            }
            guard let scheduled,
                  !Task.isCancelled
            else {
                return
            }
            await operation()
            scheduled.task = nil
        }
        return scheduled
    }
}

@MainActor
final class DocumentSession {
    private static let supportedElementTypes: Set<String> = [
        "rectangle", "arrow", "line", "text", "freehand", "highlighter", "blur", "redaction", "numberMarker",
    ]

    private(set) var project: MyShottrProject?
    private var stagedProject: MyShottrProject?
    private let recoveryStore: (any RecoveryStoring)?
    private let recoveryClock: any RecoveryDebounceClock
    private var recoveryTask: (
        any RecoveryScheduledOperation
    )?
    private var restoreStagedProjectAsModified = false
    private(set) var modificationRevision: UInt64 = 0
    private(set) var isModified = false {
        didSet { onModifiedStateChange?(isModified) }
    }
    var onModifiedStateChange: ((Bool) -> Void)?
    var onRecoveryFailure: ((any Error) -> Void)?
    var recoverySnapshotProvider: (
        @MainActor () async throws -> Data
    )?

    var isOpen: Bool { project != nil }

    init(
        recoveryStore: (any RecoveryStoring)? = nil,
        recoveryClock: any RecoveryDebounceClock =
            ContinuousRecoveryClock()
    ) {
        self.recoveryStore = recoveryStore
        self.recoveryClock = recoveryClock
    }

    func open(project: MyShottrProject) throws {
        try validate(annotationJSON: project.annotationJSON, for: project.manifest)
        recoveryTask?.cancel()
        recoveryTask = nil
        self.project = project
        stagedProject = nil
        restoreStagedProjectAsModified = false
        modificationRevision = 0
        isModified = false
    }

    func stage(project: MyShottrProject) throws {
        guard project.manifest.formatVersion == ProjectManifest.currentFormatVersion else {
            throw DocumentSessionError.invalidDocument
        }
        stagedProject = project
    }

    func commitStaged(annotationJSON: Data) throws {
        guard var stagedProject else { throw DocumentSessionError.noStagedDocument }
        try validate(annotationJSON: annotationJSON, for: stagedProject.manifest)
        stagedProject.annotationJSON = annotationJSON
        project = stagedProject
        self.stagedProject = nil
        let restoredAsModified =
            restoreStagedProjectAsModified
        isModified = restoredAsModified
        if restoredAsModified {
            modificationRevision &+= 1
        }
        restoreStagedProjectAsModified = false
    }

    func discardStaged() {
        stagedProject = nil
        restoreStagedProjectAsModified = false
    }

    func close() {
        recoveryTask?.cancel()
        recoveryTask = nil
        project = nil
        stagedProject = nil
        restoreStagedProjectAsModified = false
        modificationRevision = 0
        isModified = false
    }

    func markModified() throws {
        guard project != nil else { throw DocumentSessionError.noOpenDocument }
        modificationRevision &+= 1
        isModified = true
        scheduleRecovery(requestLatestSnapshot: true)
    }

    func applySnapshot(_ annotationJSON: Data) throws {
        let wasModified = isModified
        let changed = project?.annotationJSON
            != annotationJSON
        try install(annotationJSON: annotationJSON)
        if changed {
            modificationRevision &+= 1
        }
        if isModified || wasModified {
            scheduleRecovery(requestLatestSnapshot: false)
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

    func projectForSave() throws -> MyShottrProject {
        guard var project else { throw DocumentSessionError.noOpenDocument }
        project.manifest.updatedAt = .now
        return project
    }

    func completeSave(
        _ savedProject: MyShottrProject,
        expectedModificationRevision: UInt64? = nil
    ) throws {
        try validate(annotationJSON: savedProject.annotationJSON, for: savedProject.manifest)
        if let expectedModificationRevision,
           modificationRevision
            != expectedModificationRevision
        {
            isModified = true
            return
        }
        project = savedProject
        recoveryTask?.cancel()
        recoveryTask = nil
        try recoveryStore?.remove(
            documentId: savedProject.manifest.documentId
        )
        isModified = false
    }

    func discardRecovery() throws {
        guard let documentId = project?.manifest.documentId else {
            throw DocumentSessionError.noOpenDocument
        }
        recoveryTask?.cancel()
        recoveryTask = nil
        try recoveryStore?.remove(documentId: documentId)
    }

    func flushRecoveryForTermination() async throws {
        guard isModified else {
            return
        }
        recoveryTask?.cancel()
        recoveryTask = nil
        try await captureAndWriteLatestRecovery()
    }

    func prepareForRecoveryRestore() {
        restoreStagedProjectAsModified = true
    }

    func sourcePNG(for documentID: UUID) -> Data? {
        if let project, project.manifest.documentId == documentID { return project.originalPNG }
        if let stagedProject, stagedProject.manifest.documentId == documentID { return stagedProject.originalPNG }
        return nil
    }

    private func scheduleRecovery(
        requestLatestSnapshot: Bool
    ) {
        guard recoveryStore != nil,
              project != nil,
              !requestLatestSnapshot
                || recoverySnapshotProvider != nil
        else {
            return
        }
        recoveryTask?.cancel()
        recoveryTask = recoveryClock.schedule(
            after: .seconds(2)
        ) { [weak self] in
            guard let self else {
                return
            }
            do {
                if requestLatestSnapshot {
                    try await self
                        .captureAndWriteLatestRecovery()
                } else {
                    try self.writeCurrentRecovery()
                }
            } catch is CancellationError {
                return
            } catch {
                self.onRecoveryFailure?(error)
            }
        }
    }

    private func captureAndWriteLatestRecovery() async throws {
        guard let recoverySnapshotProvider else {
            throw DocumentSessionError
                .recoverySnapshotUnavailable
        }
        let annotationJSON = try await recoverySnapshotProvider()
        try Task.checkCancellation()
        try install(annotationJSON: annotationJSON)
        try writeCurrentRecovery()
    }

    private func writeCurrentRecovery() throws {
        guard let project,
              isModified,
              let recoveryStore
        else {
            return
        }
        try recoveryStore.write(
            project,
            documentId: project.manifest.documentId
        )
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
