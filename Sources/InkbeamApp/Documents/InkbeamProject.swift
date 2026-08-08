import Foundation

struct InkbeamProject: Equatable, Sendable {
    var manifest: ProjectManifest
    let originalPNG: Data
    var annotationJSON: Data
}

protocol ProjectPackageStoring: Sendable {
    func load(from url: URL) throws -> InkbeamProject
    func save(_ project: InkbeamProject, to url: URL) throws
}
