import Compression
import Foundation
import XCTest

enum HostFixtures {
    static let validPNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    static let validPNG = Data(base64Encoded: validPNGBase64)!
    static let validGIFBase64 =
        "R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="

    static func protocolMessage(
        protocolVersion: Int = 1,
        type: String = "capture",
        captureMode: String = "visibleViewport",
        mimeType: String = "image/png",
        dataBase64: String = validPNGBase64,
        extraFields: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
            "protocolVersion": protocolVersion,
            "type": type,
            "captureMode": captureMode,
            "mimeType": mimeType,
            "dataBase64": dataBase64,
        ]
        object.merge(extraFields) { _, replacement in replacement }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func duplicateProtocolVersionMessage(
        captureMode: String = "visibleViewport"
    ) -> Data {
        Data(
            """
            {"protocolVersion":1,"protocolVersion":1,"type":"capture","captureMode":"\(captureMode)","mimeType":"image/png","dataBase64":"\(validPNGBase64)"}
            """.utf8
        )
    }

    static func compressibleGrayscalePNG(width: Int, height: Int) throws -> Data {
        let rowByteCountResult = width.addingReportingOverflow(1)
        let rawByteCountResult = rowByteCountResult.partialValue
            .multipliedReportingOverflow(by: height)
        guard
            width > 0,
            height > 0,
            width <= Int(UInt32.max),
            height <= Int(UInt32.max),
            !rowByteCountResult.overflow,
            !rawByteCountResult.overflow
        else {
            throw FixtureError.invalidDimensions
        }

        let rawByteCount = rawByteCountResult.partialValue
        let raw = [UInt8](repeating: 0, count: rawByteCount)
        let compressedCapacity = max(
            1_024,
            rawByteCount + rawByteCount / 100 + 64
        )
        var compressed = [UInt8](repeating: 0, count: compressedCapacity)
        let compressedByteCount = raw.withUnsafeBytes { rawBytes in
            compressed.withUnsafeMutableBytes { compressedBytes in
                compression_encode_buffer(
                    compressedBytes.bindMemory(to: UInt8.self).baseAddress!,
                    compressedCapacity,
                    rawBytes.bindMemory(to: UInt8.self).baseAddress!,
                    raw.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard compressedByteCount > 0 else {
            throw FixtureError.compressionFailed
        }

        var image = Data([137, 80, 78, 71, 13, 10, 26, 10])
        var header = Data()
        header.append(bigEndian: UInt32(width))
        header.append(bigEndian: UInt32(height))
        header.append(contentsOf: [8, 0, 0, 0, 0])
        image.appendPNGChunk(type: "IHDR", payload: header)
        image.appendPNGChunk(
            type: "IDAT",
            payload: Data(compressed.prefix(compressedByteCount))
        )
        image.appendPNGChunk(type: "IEND", payload: Data())
        return image
    }

    static func framed(_ body: Data) -> Data {
        var littleEndianLength = UInt32(body.count).littleEndian
        return Data(bytes: &littleEndianLength, count: 4) + body
    }

    static func decodedReply(from framedData: Data) throws -> NativeHostReply {
        guard framedData.count >= 4 else {
            throw FixtureError.missingLength
        }

        let length = Int(
            UInt32(framedData[0])
                | UInt32(framedData[1]) << 8
                | UInt32(framedData[2]) << 16
                | UInt32(framedData[3]) << 24
        )
        guard framedData.count == 4 + length else {
            throw FixtureError.unexpectedFramedLength
        }

        return try JSONDecoder().decode(
            NativeHostReply.self,
            from: framedData.subdata(in: 4..<framedData.count)
        )
    }

    static func run(
        _ runner: HostRunner,
        inputData: Data,
        in directory: URL
    ) throws -> Data {
        let inputURL = directory.appendingPathComponent("input-\(UUID().uuidString)")
        let outputURL = directory.appendingPathComponent("output-\(UUID().uuidString)")
        try inputData.write(to: inputURL)
        XCTAssertTrue(FileManager.default.createFile(atPath: outputURL.path, contents: nil))

        let input = try FileHandle(forReadingFrom: inputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        runner.run(input: input, output: output)
        try output.synchronize()
        try input.close()
        try output.close()
        return try Data(contentsOf: outputURL)
    }
}

private enum FixtureError: Error {
    case compressionFailed
    case invalidDimensions
    case missingLength
    case unexpectedFramedLength
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) { append(contentsOf: $0) }
    }

    mutating func appendPNGChunk(type: String, payload: Data) {
        let typeData = Data(type.utf8)
        append(bigEndian: UInt32(payload.count))
        append(typeData)
        append(payload)
        append(bigEndian: Self.crc32(typeData + payload))
    }

    static func crc32(_ data: Data) -> UInt32 {
        data.reduce(UInt32.max) { crc, byte in
            var value = crc ^ UInt32(byte)
            for _ in 0..<8 {
                value = (value >> 1) ^ (value & 1 == 1 ? 0xEDB8_8320 : 0)
            }
            return value
        } ^ UInt32.max
    }
}

final class StagingSpy: HostCaptureStaging {
    var result: Result<UUID, Error>
    let events: EventRecorder?
    private(set) var stagedData: [Data] = []

    init(
        result: Result<UUID, Error>,
        events: EventRecorder? = nil
    ) {
        self.result = result
        self.events = events
    }

    func stage(pngData: Data) throws -> UUID {
        events?.values.append("stage")
        stagedData.append(pngData)
        return try result.get()
    }
}

final class ActivationSpy: AppActivating {
    var result: Result<Void, Error>
    let events: EventRecorder?
    private(set) var activationCount = 0
    private(set) var captureIDs: [UUID] = []

    init(
        result: Result<Void, Error> = .success(()),
        events: EventRecorder? = nil
    ) {
        self.result = result
        self.events = events
    }

    func activateContainingApp(captureID: UUID) throws {
        events?.values.append("activate")
        activationCount += 1
        captureIDs.append(captureID)
        try result.get()
    }
}

final class EventRecorder {
    var values: [String] = []
}

enum HostTestError: Error {
    case activation
    case staging
    case partialWrite
}
