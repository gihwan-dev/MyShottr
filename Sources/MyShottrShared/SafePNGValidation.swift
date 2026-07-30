import Foundation
import ImageIO
import UniformTypeIdentifiers

enum SafePNGValidationError: Error, Equatable {
    case invalidPNG
    case imageTooLarge
}

struct SafePNGMetadata: Equatable, Sendable {
    let pixelWidth: Int
    let pixelHeight: Int
}

enum SafePNGValidationPolicy {
    static let maximumImageLength = 45 * 1024 * 1024
    static let maximumPixelDimension: UInt64 = 32_768
    static let maximumPixelCount: UInt64 = 64 * 1024 * 1024
    static let maximumDecodedImageBytes: UInt64 = 512 * 1024 * 1024
    static let worstCaseDecodedBytesPerPixel: UInt64 = 8

    static func validate(_ data: Data) throws -> SafePNGMetadata {
        guard data.count <= maximumImageLength else {
            throw SafePNGValidationError.imageTooLarge
        }
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                nil
            ),
            let sourceType = CGImageSourceGetType(source),
            sourceType as String == UTType.png.identifier,
            CGImageSourceGetCount(source) == 1,
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let widthNumber =
                properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let heightNumber =
                properties[kCGImagePropertyPixelHeight] as? NSNumber,
            widthNumber.int64Value > 0,
            heightNumber.int64Value > 0
        else {
            throw SafePNGValidationError.invalidPNG
        }

        let width = widthNumber.uint64Value
        let height = heightNumber.uint64Value
        guard
            width <= maximumPixelDimension,
            height <= maximumPixelDimension
        else {
            throw SafePNGValidationError.imageTooLarge
        }

        let pixelCount = width.multipliedReportingOverflow(by: height)
        guard
            !pixelCount.overflow,
            pixelCount.partialValue <= maximumPixelCount
        else {
            throw SafePNGValidationError.imageTooLarge
        }

        let decodedByteCount =
            pixelCount.partialValue.multipliedReportingOverflow(
                by: worstCaseDecodedBytesPerPixel
            )
        guard
            !decodedByteCount.overflow,
            decodedByteCount.partialValue <= maximumDecodedImageBytes
        else {
            throw SafePNGValidationError.imageTooLarge
        }

        guard CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw SafePNGValidationError.invalidPNG
        }

        return SafePNGMetadata(
            pixelWidth: widthNumber.intValue,
            pixelHeight: heightNumber.intValue
        )
    }
}
