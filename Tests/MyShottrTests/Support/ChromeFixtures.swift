import Foundation
@testable import MyShottr

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

    static func appBundleURL(in root: URL) -> URL {
        root.appendingPathComponent("MyShottr.app", isDirectory: true)
    }

    static func helperURL(in root: URL) -> URL {
        appBundleURL(in: root)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("MyShottrNativeHost")
    }

    static func manifestURL(in root: URL) -> URL {
        root.appendingPathComponent(
            "NativeMessagingHosts/com.myshottr.capture.json"
        )
    }
}

final class StubPendingCaptureInbox:
    PendingCaptureStoring,
    @unchecked Sendable
{
    var pending: [StagedCapture]
    var dataByID: [UUID: Data]
    private(set) var consumedIDs: [UUID] = []

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
        pending
    }

    func consume(id: UUID) throws -> Data {
        consumedIDs.append(id)
        guard let data = dataByID.removeValue(forKey: id) else {
            throw ChromeFixtureError.captureNotFound
        }
        return data
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
    ) throws -> MyShottrProject {
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

private enum ChromeFixtureError: Error {
    case captureNotFound
}
