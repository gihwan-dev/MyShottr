import Foundation

enum ProjectPackageError: Error, Equatable {
    case notDirectoryPackage
    case invalidMemberSet([String])
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case unsupportedAnnotationSchemaVersion(Int)
    case invalidAnnotationJSON
    case invalidPNG
    case sourceDimensionsMismatch
}
