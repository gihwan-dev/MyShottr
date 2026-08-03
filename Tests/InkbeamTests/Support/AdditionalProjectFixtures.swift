import Foundation
@testable import Inkbeam

enum AdditionalProjectFixtures {
    static let secondDocumentID = UUID(
        uuidString: "06A85766-0B28-4B48-8FCA-BE56DF625853"
    )!

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
}
