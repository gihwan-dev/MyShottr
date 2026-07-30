import Foundation

struct ProjectPackageStore: ProjectPackageStoring {
    private static let memberNames = ["document.json", "manifest.json", "original.png"]

    func load(from url: URL) throws -> MyShottrProject {
        try validatePackageRoot(url)

        let members = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        let memberNames = members.map(\.lastPathComponent).sorted()
        guard memberNames == Self.memberNames else {
            throw ProjectPackageError.invalidMemberSet(memberNames)
        }

        for member in members {
            let values = try member.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw ProjectPackageError.invalidMemberSet(memberNames)
            }
        }

        let manifestURL = url.appendingPathComponent("manifest.json")
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw ProjectPackageError.invalidManifest
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest: ProjectManifest
        do {
            manifest = try decoder.decode(ProjectManifest.self, from: manifestData)
        } catch {
            throw ProjectPackageError.invalidManifest
        }
        guard manifest.formatVersion == ProjectManifest.currentFormatVersion else {
            throw ProjectPackageError.unsupportedFormatVersion(manifest.formatVersion)
        }

        let documentURL = url.appendingPathComponent("document.json")
        let storedAnnotationJSON: Data
        do {
            storedAnnotationJSON = try Data(contentsOf: documentURL)
        } catch {
            throw ProjectPackageError.invalidAnnotationJSON
        }
        let annotationJSON: Data
        do {
            annotationJSON = try EditorDocumentMigrator.migrate(storedAnnotationJSON)
        } catch {
            throw ProjectPackageError.invalidAnnotationJSON
        }
        try validateAnnotationJSON(annotationJSON)

        let png = try PNGMetadata.read(from: url.appendingPathComponent("original.png"))
        guard png.pixelWidth == manifest.sourcePixelWidth,
              png.pixelHeight == manifest.sourcePixelHeight
        else {
            throw ProjectPackageError.sourceDimensionsMismatch
        }

        return MyShottrProject(
            manifest: manifest,
            originalPNG: try Data(contentsOf: url.appendingPathComponent("original.png")),
            annotationJSON: annotationJSON
        )
    }

    func save(_ project: MyShottrProject, to url: URL) throws {
        let annotationJSON: Data
        do {
            annotationJSON = try EditorDocumentMigrator.migrate(project.annotationJSON)
        } catch {
            throw ProjectPackageError.invalidAnnotationJSON
        }
        try validateAnnotationJSON(annotationJSON)

        let fileManager = FileManager.default
        let temporaryDirectory = url.deletingLastPathComponent().appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: true
        )
        defer {
            try? fileManager.removeItem(at: temporaryDirectory)
        }

        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(project.manifest).write(to: temporaryDirectory.appendingPathComponent("manifest.json"))
        try project.originalPNG.write(to: temporaryDirectory.appendingPathComponent("original.png"))
        try annotationJSON.write(to: temporaryDirectory.appendingPathComponent("document.json"))

        _ = try load(from: temporaryDirectory)

        if fileManager.fileExists(atPath: url.path) {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporaryDirectory)
        } else {
            try fileManager.moveItem(at: temporaryDirectory, to: url)
        }
    }

    private func validatePackageRoot(_ url: URL) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw ProjectPackageError.notDirectoryPackage
        }

        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ProjectPackageError.notDirectoryPackage
        }
    }

    private func validateAnnotationJSON(_ data: Data) throws {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ProjectPackageError.invalidAnnotationJSON
        }

        guard let document = object as? [String: Any],
              Set(document.keys) == ["schemaVersion", "sourcePixelWidth", "sourcePixelHeight", "elements", "presentation", "defaults"],
              let schemaVersion = document["schemaVersion"] as? Int, schemaVersion == 2,
              let presentation = document["presentation"] as? [String: Any],
              Set(presentation.keys) == ["type"], presentation["type"] as? String == "none"
        else {
            throw ProjectPackageError.invalidAnnotationJSON
        }
    }
}
