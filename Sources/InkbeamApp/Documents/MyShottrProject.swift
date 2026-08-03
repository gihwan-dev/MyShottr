import Foundation

struct MyShottrProject: Equatable, Sendable {
    var manifest: ProjectManifest
    let originalPNG: Data
    var annotationJSON: Data
}

protocol ProjectPackageStoring: Sendable {
    func load(from url: URL) throws -> MyShottrProject
    func save(_ project: MyShottrProject, to url: URL) throws
}
