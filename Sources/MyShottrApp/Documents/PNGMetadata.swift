import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PNGMetadata: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int

    static func read(from url: URL) throws -> PNGMetadata {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let imageType = CGImageSourceGetType(imageSource),
              imageType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0,
              pixelHeight > 0
        else {
            throw ProjectPackageError.invalidPNG
        }

        return PNGMetadata(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
    }
}
