import Foundation

enum CaptureSourceKind: String, Codable, Sendable {
    case screenRegion
    case chromeVisibleViewport
}

struct ProjectManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    let formatVersion: Int
    let documentId: UUID
    let createdAt: Date
    var updatedAt: Date
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
    let sourceKind: CaptureSourceKind
}
