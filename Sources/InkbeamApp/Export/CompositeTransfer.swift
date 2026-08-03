import Foundation
import ImageIO
import UniformTypeIdentifiers

enum CompositeTransferError: Error, Equatable {
    case temporaryFile
    case invalidBase64
    case unexpectedChunk(expected: Int, received: Int)
    case inconsistentChunkTotal(expected: Int, received: Int)
    case incomplete(expected: Int, received: Int)
    case invalidPNG
    case invalidDimensions
    case dimensionsMismatch(expectedWidth: Int, expectedHeight: Int, receivedWidth: Int, receivedHeight: Int)
    case notFinished
    case moveFailed
}

final class CompositeTransfer: @unchecked Sendable {
    let requestId: UUID
    private let fileURL: URL
    private let expectedChunks: Int
    private let expectedPixelSize: (width: Int, height: Int)?
    private var nextChunkIndex = 0
    private var fileHandle: FileHandle?
    private var finished = false

    static func begin(
        requestId: UUID,
        expectedChunks: Int,
        directory: URL? = nil,
        expectedPixelSize: (width: Int, height: Int)? = nil
    ) throws -> CompositeTransfer {
        try CompositeTransfer(requestId: requestId, expectedChunks: expectedChunks, directory: directory, expectedPixelSize: expectedPixelSize)
    }

    init(
        requestId: UUID,
        expectedChunks: Int,
        directory: URL? = nil,
        expectedPixelSize: (width: Int, height: Int)? = nil
    ) throws {
        guard expectedChunks > 0 else { throw CompositeTransferError.incomplete(expected: 1, received: 0) }
        self.requestId = requestId
        self.expectedChunks = expectedChunks
        self.expectedPixelSize = expectedPixelSize
        let parent = directory ?? FileManager.default.temporaryDirectory
        self.fileURL = parent.appendingPathComponent(".inkbeam-composite-\(requestId.uuidString).png", isDirectory: false)
        guard FileManager.default.createFile(
            atPath: fileURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CompositeTransferError.temporaryFile
        }
        do {
            fileHandle = try FileHandle(forWritingTo: fileURL)
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            throw CompositeTransferError.temporaryFile
        }
    }

    deinit {
        try? fileHandle?.close()
        if !finished { try? FileManager.default.removeItem(at: fileURL) }
    }

    func append(index: Int, base64: String) throws {
        try append(index: index, total: expectedChunks, base64: base64)
    }

    func append(index: Int, total: Int, base64: String) throws {
        guard !finished, let fileHandle else { throw CompositeTransferError.notFinished }
        guard total == expectedChunks else {
            throw CompositeTransferError.inconsistentChunkTotal(expected: expectedChunks, received: total)
        }
        guard index == nextChunkIndex else {
            throw CompositeTransferError.unexpectedChunk(expected: nextChunkIndex, received: index)
        }
        guard let data = Data(base64Encoded: base64, options: []) else {
            throw CompositeTransferError.invalidBase64
        }
        try fileHandle.write(contentsOf: data)
        nextChunkIndex += 1
    }

    func finish() throws -> URL {
        guard !finished else { return fileURL }
        guard nextChunkIndex == expectedChunks else {
            throw CompositeTransferError.incomplete(expected: expectedChunks, received: nextChunkIndex)
        }
        try fileHandle?.synchronize()
        try fileHandle?.close()
        fileHandle = nil
        try validatePNG()
        finished = true
        return fileURL
    }

    func data() throws -> Data {
        guard finished else { throw CompositeTransferError.notFinished }
        return try Data(contentsOf: fileURL)
    }

    func move(to destinationURL: URL) throws {
        guard finished else { throw CompositeTransferError.notFinished }
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: fileURL)
            } else {
                try fileManager.moveItem(at: fileURL, to: destinationURL)
            }
        } catch {
            throw CompositeTransferError.moveFailed
        }
    }

    func discard() {
        try? fileHandle?.close()
        fileHandle = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func validatePNG() throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) else {
            throw CompositeTransferError.invalidPNG
        }
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let imageType = CGImageSourceGetType(imageSource),
              imageType as String == UTType.png.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,
              height > 0
        else {
            throw CompositeTransferError.invalidDimensions
        }
        if let expectedPixelSize, (width != expectedPixelSize.width || height != expectedPixelSize.height) {
            throw CompositeTransferError.dimensionsMismatch(
                expectedWidth: expectedPixelSize.width,
                expectedHeight: expectedPixelSize.height,
                receivedWidth: width,
                receivedHeight: height
            )
        }
    }
}
