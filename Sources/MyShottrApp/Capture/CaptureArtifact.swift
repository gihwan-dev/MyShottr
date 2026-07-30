import Foundation

struct CaptureArtifact: Equatable, Sendable {
    let id: UUID
    let sourceKind: CaptureSourceKind
    let pngData: Data
    let pixelWidth: Int
    let pixelHeight: Int
    let scale: Double?

    init(id: UUID, sourceKind: CaptureSourceKind, pngData: Data, scale: Double?) throws {
        let metadata = try PNGMetadata.read(from: pngData)
        self.id = id
        self.sourceKind = sourceKind
        self.pngData = pngData
        self.pixelWidth = metadata.pixelWidth
        self.pixelHeight = metadata.pixelHeight
        self.scale = scale
    }
}
