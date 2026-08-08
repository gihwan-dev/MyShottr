import Compression
import Foundation
@testable import Inkbeam

enum ChromeFixtures {
    static let extensionPublicKeyBase64 =
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3n4s11MOsMYhEHDdlD5z3XCob/5l8y46LcpGnAxjVvDsstbYxe+IG/Q3E7J5skCOCarE1KywNmdOL/pcwGoP4+/wK7zyImDsQRlqI1hkuCCwyhKo/OKc9GLjdwJofQnP0GjEGETVOJN8q1BPhJ900g1OXUF+oIxXYb3qhiYLeLCMH7nqLTTfiLouAnUBXxumRgjcQPjV3S4qKzsmp4tWrLbR/epTM4UpsFjllYZshMQknehKNf6v1AogoThJN1YOk2lZqUDuzKv0uhuyXVt4aJMTEsXUCH42tuVJqBMPwjkfH3rUGYl4OKDqoow5D8sumRAGjPpHGiVOlWID66o+NwIDAQAB"
    static let extensionID = "mcpmeggdbafgeemngbfniplmcjmigfbh"
    static let captureID = UUID(
        uuidString: "4AB93E6A-906D-4E58-93DA-EE90FA24EC47"
    )!
    static let secondCaptureID = UUID(
        uuidString: "1278A262-54A9-4D7D-9AC5-411DA020756C"
    )!
    static let stateID = UUID(
        uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    )!
    static let secondStateID = UUID(
        uuidString: "11111111-2222-4333-8444-555555555555"
    )!

    static func compressibleGrayscalePNG(
        width: Int,
        height: Int
    ) throws -> Data {
        let rowByteCount = width + 1
        let raw = [UInt8](
            repeating: 0,
            count: rowByteCount * height
        )
        let compressedCapacity = max(
            1_024,
            raw.count + raw.count / 100 + 64
        )
        var compressed = [UInt8](
            repeating: 0,
            count: compressedCapacity
        )
        let compressedByteCount = raw.withUnsafeBytes { rawBytes in
            compressed.withUnsafeMutableBytes { compressedBytes in
                compression_encode_buffer(
                    compressedBytes.bindMemory(
                        to: UInt8.self
                    ).baseAddress!,
                    compressedCapacity,
                    rawBytes.bindMemory(to: UInt8.self).baseAddress!,
                    raw.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard compressedByteCount > 0 else {
            throw ChromeFixtureError.compression
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

    static func appBundleURL(in root: URL) -> URL {
        root.appendingPathComponent("Inkbeam.app", isDirectory: true)
    }

    static func helperURL(in root: URL) -> URL {
        appBundleURL(in: root)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("InkbeamNativeHost")
    }

    static func manifestURL(in root: URL) -> URL {
        root.appendingPathComponent(
            "NativeMessagingHosts/dev.gihwan.inkbeam.capture.json"
        )
    }
}

final class StubPendingCaptureInbox:
    PendingCaptureStoring,
    @unchecked Sendable
{
    var pending: [StagedCapture]
    var cleanupOnly: [PresentedCapture] = []
    var dataByID: [UUID: Data]
    var pendingScanError: (any Error)?
    var cleanupScanError: (any Error)?
    var claimErrorByID: [UUID: any Error] = [:]
    var commitErrorByID: [UUID: any Error] = [:]
    var cleanupErrorByID: [UUID: any Error] = [:]
    var commitError: (any Error)?
    var cleanupError: (any Error)?
    private(set) var claimedIDs: [UUID] = []
    private(set) var commitAttempts: [UUID] = []
    private(set) var committedIDs: [UUID] = []
    private(set) var cleanupAttempts: [UUID] = []
    private(set) var cleanedIDs: [UUID] = []

    init(
        pending: [StagedCapture] = [],
        dataByID: [UUID: Data] = [
            ChromeFixtures.captureID: ProjectFixtures.pngData,
        ]
    ) {
        self.pending = pending
        self.dataByID = dataByID
    }

    func stage(pngData: Data) throws -> StagedCapture {
        let id = ChromeFixtures.captureID
        dataByID[id] = pngData
        return StagedCapture(
            id: id,
            pngURL: URL(fileURLWithPath: "/inbox/\(id.uuidString).png")
        )
    }

    func pendingCaptures() throws -> [StagedCapture] {
        if let pendingScanError {
            throw pendingScanError
        }
        return pending
    }

    func cleanupOnlyCaptures() throws -> [PresentedCapture] {
        if let cleanupScanError {
            throw cleanupScanError
        }
        return cleanupOnly
    }

    func claim(id: UUID) throws -> PendingCaptureClaim {
        claimedIDs.append(id)
        if let error = claimErrorByID[id] {
            throw error
        }
        guard let data = dataByID[id] else {
            throw PendingCaptureInboxError.captureNotFound
        }
        return PendingCaptureClaim(
            id: id,
            pngData: data,
            processingURL: URL(
                fileURLWithPath:
                    "/inbox/\(id.uuidString)."
                    + "\(ChromeFixtures.stateID.uuidString).processing"
            ),
            fileDevice: 1,
            fileInode: UInt64(abs(id.hashValue))
        )
    }

    func commitPresentation(
        _ claim: PendingCaptureClaim
    ) throws -> PresentedCapture {
        commitAttempts.append(claim.id)
        if let error = commitErrorByID[claim.id] {
            throw error
        }
        if let commitError {
            throw commitError
        }
        committedIDs.append(claim.id)
        return PresentedCapture(
            id: claim.id,
            presentedURL: URL(
                fileURLWithPath:
                    "/inbox/\(claim.id.uuidString)."
                    + "\(ChromeFixtures.stateID.uuidString).presented"
            ),
            fileDevice: claim.fileDevice,
            fileInode: claim.fileInode
        )
    }

    func cleanupPresented(
        _ presented: PresentedCapture
    ) throws -> PresentedCleanupResult {
        cleanupAttempts.append(presented.id)
        if let error = cleanupErrorByID[presented.id] {
            throw error
        }
        if let cleanupError {
            throw cleanupError
        }
        cleanedIDs.append(presented.id)
        dataByID.removeValue(forKey: presented.id)
        return .removed
    }
}

final class SpyChromeNewProjectFactory:
    NewProjectCreating,
    @unchecked Sendable
{
    struct Request: Equatable {
        let id: UUID
        let sourceKind: CaptureSourceKind
        let scale: Double?
        let now: Date
    }

    private(set) var requests: [Request] = []

    func make(
        artifact: CaptureArtifact,
        now: Date
    ) throws -> InkbeamProject {
        requests.append(
            Request(
                id: artifact.id,
                sourceKind: artifact.sourceKind,
                scale: artifact.scale,
                now: now
            )
        )
        return try NewProjectFactory(
            preferences: StubPreferences(.approvedDefaults)
        ).make(
            artifact: artifact,
            now: now
        )
    }
}

enum ChromeFixtureError: Error, Equatable {
    case commit
    case cleanup
    case compression
}

private extension Data {
    mutating func append(bigEndian value: UInt32) {
        var encoded = value.bigEndian
        Swift.withUnsafeBytes(of: &encoded) {
            append(contentsOf: $0)
        }
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
                value =
                    (value >> 1)
                    ^ (value & 1 == 1 ? 0xEDB8_8320 : 0)
            }
            return value
        } ^ UInt32.max
    }
}
