import Foundation

protocol NewProjectCreating {
    func make(artifact: CaptureArtifact, now: Date) throws -> MyShottrProject
}

struct NewProjectFactory: NewProjectCreating {
    private let preferences: any EditorPreferencesStoring

    init(preferences: any EditorPreferencesStoring = UserDefaultsEditorPreferencesStore()) {
        self.preferences = preferences
    }

    func make(artifact: CaptureArtifact, now: Date = .now) throws -> MyShottrProject {
        let preferences = preferences.load()
        let annotationJSON = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2,
            "sourcePixelWidth": artifact.pixelWidth,
            "sourcePixelHeight": artifact.pixelHeight,
            "elements": [],
            "presentation": ["type": "none"],
            "defaults": [
                "color": preferences.color,
                "strokeWidth": preferences.strokeWidth,
                "textSize": preferences.textSize,
                "roughness": preferences.roughness,
                "opacity": preferences.opacity,
            ],
        ], options: [.sortedKeys])
        return MyShottrProject(
            manifest: ProjectManifest(
                formatVersion: ProjectManifest.currentFormatVersion,
                documentId: artifact.id,
                createdAt: now,
                updatedAt: now,
                sourcePixelWidth: artifact.pixelWidth,
                sourcePixelHeight: artifact.pixelHeight,
                sourceKind: artifact.sourceKind,
                sourceScale: artifact.scale
            ),
            originalPNG: artifact.pngData,
            annotationJSON: annotationJSON
        )
    }
}
