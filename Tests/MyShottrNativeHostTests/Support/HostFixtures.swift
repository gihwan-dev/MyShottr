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
    case missingLength
    case unexpectedFramedLength
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
    let events: EventRecorder?
    private(set) var activationCount = 0

    init(events: EventRecorder? = nil) {
        self.events = events
    }

    func activateContainingApp() throws {
        events?.values.append("activate")
        activationCount += 1
    }
}

final class EventRecorder {
    var values: [String] = []
}

enum HostTestError: Error {
    case staging
    case partialWrite
}
