import Darwin
import Foundation
import ImageIO
import XCTest

final class HostRunnerTests: TemporaryDirectoryTestCase {
    private let captureID = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!

    func testStagesValidatedPNGBeforeActivatingApp() async throws {
        let events = EventRecorder()
        let staging = StagingSpy(result: .success(captureID), events: events)
        let activator = ActivationSpy(events: events)
        let runner = HostRunner(staging: staging, activator: activator)

        let output = try await HostFixtures.run(
            runner,
            inputData: HostFixtures.framed(try HostFixtures.protocolMessage()),
            in: temporaryDirectory
        )

        XCTAssertEqual(
            try HostFixtures.decodedReply(from: output),
            NativeHostReply(ok: true, captureId: captureID, code: nil)
        )
        XCTAssertEqual(staging.stagedData, [HostFixtures.validPNG])
        XCTAssertEqual(events.values, ["stage", "activate"])
        XCTAssertEqual(activator.captureIDs, [captureID])
    }

    func testRejectsUnsupportedProtocolVersionWithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(protocolVersion: 2),
            code: .invalidMessage
        )
    }

    func testRejectsDuplicateJSONMemberWithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.duplicateProtocolVersionMessage(),
            code: .invalidMessage
        )
    }

    func testRejectsExcessiveJSONNestingWithoutStagingOrActivation() async throws {
        let depth = 256
        let message = Data(
            (
                String(repeating: "[", count: depth)
                    + "0"
                    + String(repeating: "]", count: depth)
            ).utf8
        )

        try await assertRejected(
            message: message,
            code: .invalidMessage
        )
    }

    func testRejectsUnexpectedMessageTypeWithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(type: "ping"),
            code: .invalidMessage
        )
    }

    func testRejectsFullPageBeforeDecodingImageData() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(
                captureMode: "fullPage",
                dataBase64: "not valid base64"
            ),
            code: .unsupportedCaptureMode
        )
    }

    func testRejectsNonPNGMIMEWithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(mimeType: "image/jpeg"),
            code: .invalidImage
        )
    }

    func testRejectsMalformedBase64WithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(dataBase64: "%%%="),
            code: .invalidImage
        )
    }

    func testRejectsNoncanonicalBase64WithoutStaging() async throws {
        let noncanonicalPNG = String(HostFixtures.validPNGBase64.dropLast(2)) + "J="

        try await assertRejected(
            message: HostFixtures.protocolMessage(dataBase64: noncanonicalPNG),
            code: .invalidImage
        )
    }

    func testRejectsDecodedImageAboveFortyFiveMiBWithoutStaging() async throws {
        let decodedByteCount = 45 * 1024 * 1024 + 1
        let base64CharacterCount = ((decodedByteCount + 2) / 3) * 4
        var oversizedBase64 = String(repeating: "A", count: base64CharacterCount)
        let paddingCount = (3 - decodedByteCount % 3) % 3
        if paddingCount > 0 {
            oversizedBase64.replaceSubrange(
                oversizedBase64.index(oversizedBase64.endIndex, offsetBy: -paddingCount)...,
                with: String(repeating: "=", count: paddingCount)
            )
        }

        try await assertRejected(
            message: HostFixtures.protocolMessage(dataBase64: oversizedBase64),
            code: .imageTooLarge
        )
    }

    func testRejectsImageWhoseImageIOTypeIsNotPNGWithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(
                dataBase64: HostFixtures.validGIFBase64
            ),
            code: .invalidImage
        )
    }

    func testRejectsHighlyCompressiblePNGWithOversizedWidthBeforeStaging() async throws {
        let png = try HostFixtures.compressibleGrayscalePNG(
            width: 100_000,
            height: 1
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(
            (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            100_000
        )
        XCTAssertLessThan(png.count, 1_024)

        try await assertRejected(
            message: HostFixtures.protocolMessage(
                dataBase64: png.base64EncodedString()
            ),
            code: .imageTooLarge
        )
    }

    func testRejectsUnexpectedMetadataFieldsWithoutStaging() async throws {
        try await assertRejected(
            message: HostFixtures.protocolMessage(
                extraFields: [
                    "url": "https://example.com",
                    "title": "Example",
                    "history": ["previous"],
                ]
            ),
            code: .invalidMessage
        )
    }

    func testReturnsBoundedInvalidMessageReplyForMalformedJSON() async throws {
        try await assertRejected(
            message: Data("not-json".utf8),
            code: .invalidMessage
        )
    }

    func testDoesNotActivateAppWhenStagingFails() async throws {
        let staging = StagingSpy(result: .failure(HostTestError.staging))
        let activator = ActivationSpy()
        let runner = HostRunner(staging: staging, activator: activator)

        let output = try await HostFixtures.run(
            runner,
            inputData: HostFixtures.framed(try HostFixtures.protocolMessage()),
            in: temporaryDirectory
        )

        XCTAssertEqual(
            try HostFixtures.decodedReply(from: output),
            NativeHostReply(ok: false, captureId: nil, code: .stagingFailed)
        )
        XCTAssertEqual(staging.stagedData, [HostFixtures.validPNG])
        XCTAssertEqual(activator.activationCount, 0)
    }

    func testStagingFailureRemovesPartialCaptureAndDoesNotActivateApp() async throws {
        let inbox = temporaryDirectory.appendingPathComponent(
            "StagingFailureInbox",
            isDirectory: true
        )
        let staging = HostInboxStore(
            rootURL: inbox,
            idGenerator: { self.captureID },
            writeOperation: { descriptor, data in
                let written = data.prefix(8).withUnsafeBytes {
                    Darwin.write(descriptor, $0.baseAddress, $0.count)
                }
                XCTAssertEqual(written, 8)
                throw HostTestError.partialWrite
            }
        )
        let activator = ActivationSpy()
        let runner = HostRunner(staging: staging, activator: activator)

        let output = try await HostFixtures.run(
            runner,
            inputData: HostFixtures.framed(try HostFixtures.protocolMessage()),
            in: temporaryDirectory
        )

        try assertExactBoundedFailure(
            output,
            code: .stagingFailed
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(
                atPath: inbox.path
            ).isEmpty
        )
        XCTAssertEqual(activator.activationCount, 0)
        XCTAssertTrue(activator.captureIDs.isEmpty)
    }

    func testActivationFailurePreservesOneOwnerOnlyPendingPNG() async throws {
        let inbox = temporaryDirectory.appendingPathComponent(
            "ActivationFailureInbox",
            isDirectory: true
        )
        let staging = HostInboxStore(
            rootURL: inbox,
            idGenerator: { self.captureID }
        )
        let activator = ActivationSpy(
            result: .failure(HostTestError.activation)
        )
        let runner = HostRunner(staging: staging, activator: activator)

        let output = try await HostFixtures.run(
            runner,
            inputData: HostFixtures.framed(try HostFixtures.protocolMessage()),
            in: temporaryDirectory
        )

        try assertExactBoundedFailure(
            output,
            code: .appActivationFailed
        )
        XCTAssertEqual(activator.activationCount, 1)
        XCTAssertEqual(activator.captureIDs, [captureID])

        let entries = try FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(
            entries.map(\.lastPathComponent),
            ["\(captureID.uuidString).png"]
        )
        let capture = try XCTUnwrap(entries.first)
        let attributes = try FileManager.default.attributesOfItem(
            atPath: capture.path
        )
        XCTAssertEqual(
            try XCTUnwrap(
                attributes[.posixPermissions] as? NSNumber
            ).intValue & 0o777,
            0o600
        )
        XCTAssertEqual(
            (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            getuid()
        )
        XCTAssertEqual(try Data(contentsOf: capture), HostFixtures.validPNG)
    }

    func testProcessesOnlyFirstFramedMessage() async throws {
        let staging = StagingSpy(result: .success(captureID))
        let activator = ActivationSpy()
        let runner = HostRunner(staging: staging, activator: activator)
        let first = HostFixtures.framed(try HostFixtures.protocolMessage())
        let second = HostFixtures.framed(try HostFixtures.protocolMessage())

        let output = try await HostFixtures.run(
            runner,
            inputData: first + second,
            in: temporaryDirectory
        )

        XCTAssertEqual(
            try HostFixtures.decodedReply(from: output),
            NativeHostReply(ok: true, captureId: captureID, code: nil)
        )
        XCTAssertEqual(staging.stagedData.count, 1)
        XCTAssertEqual(activator.activationCount, 1)
    }

    func testAppActivatorFindsAndOpensContainingApplication() async throws {
        let appURL = temporaryDirectory.appendingPathComponent("MyShottr.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let helpersURL = contentsURL.appendingPathComponent("Helpers", isDirectory: true)
        try FileManager.default.createDirectory(
            at: helpersURL,
            withIntermediateDirectories: true
        )
        try Data("plist".utf8).write(to: contentsURL.appendingPathComponent("Info.plist"))
        let executableURL = helpersURL.appendingPathComponent("MyShottrNativeHost")
        var openedURL: URL?
        var notifiedCaptureID: UUID?
        var events: [String] = []
        let otherAppURL = temporaryDirectory
            .appendingPathComponent("Other", isDirectory: true)
            .appendingPathComponent("MyShottr.app", isDirectory: true)
        let activator = AppActivator(
            executableURL: executableURL,
            runningApplicationURLs: { [otherAppURL] },
            launchApplication: {
                events.append("open")
                openedURL = $0
                return true
            },
            postCaptureReady: {
                events.append("notify")
                notifiedCaptureID = $0
            }
        )

        try await activator.activateContainingApp(captureID: captureID)

        XCTAssertEqual(openedURL, appURL)
        XCTAssertEqual(notifiedCaptureID, captureID)
        XCTAssertEqual(events, ["open", "notify"])
    }

    func testAppActivatorAwaitsAsynchronousColdLaunchBeforeNotifying() async throws {
        let appURL = temporaryDirectory.appendingPathComponent(
            "MyShottr.app",
            isDirectory: true
        )
        let contentsURL = appURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        let helpersURL = contentsURL.appendingPathComponent(
            "Helpers",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: helpersURL,
            withIntermediateDirectories: true
        )
        try Data("plist".utf8).write(
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        let executableURL = helpersURL.appendingPathComponent(
            "MyShottrNativeHost"
        )
        var launchedURL: URL?
        var notifiedCaptureID: UUID?
        var events: [String] = []
        let activator = AppActivator(
            executableURL: executableURL,
            runningApplicationURLs: {
                events.append("inspect")
                return []
            },
            launchApplication: {
                events.append("launch")
                launchedURL = $0
                await Task.yield()
                events.append("launched")
                return true
            },
            postCaptureReady: {
                events.append("notify")
                notifiedCaptureID = $0
            }
        )

        try await activator.activateContainingApp(captureID: captureID)

        XCTAssertEqual(launchedURL, appURL)
        XCTAssertEqual(notifiedCaptureID, captureID)
        XCTAssertEqual(events, ["inspect", "launch", "launched", "notify"])
    }

    func testAppActivatorNotifiesRunningContainingApplicationWithoutReopening() async throws {
        let appURL = temporaryDirectory.appendingPathComponent(
            "MyShottr.app",
            isDirectory: true
        )
        let contentsURL = appURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        let helpersURL = contentsURL.appendingPathComponent(
            "Helpers",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: helpersURL,
            withIntermediateDirectories: true
        )
        try Data("plist".utf8).write(
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        let executableURL = helpersURL.appendingPathComponent(
            "MyShottrNativeHost"
        )
        var openedURL: URL?
        var notifiedCaptureID: UUID?
        var events: [String] = []
        let otherAppURL = temporaryDirectory
            .appendingPathComponent("Other", isDirectory: true)
            .appendingPathComponent("MyShottr.app", isDirectory: true)
        let activator = AppActivator(
            executableURL: executableURL,
            runningApplicationURLs: {
                events.append("inspect")
                return [otherAppURL, appURL]
            },
            launchApplication: {
                events.append("open")
                openedURL = $0
                return true
            },
            postCaptureReady: {
                events.append("notify")
                notifiedCaptureID = $0
            }
        )

        try await activator.activateContainingApp(captureID: captureID)

        XCTAssertNil(openedURL)
        XCTAssertEqual(notifiedCaptureID, captureID)
        XCTAssertEqual(events, ["inspect", "notify"])
    }

    private func assertRejected(
        message: Data,
        code: NativeHostErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let staging = StagingSpy(result: .success(captureID))
        let activator = ActivationSpy()
        let runner = HostRunner(staging: staging, activator: activator)

        let output = try await HostFixtures.run(
            runner,
            inputData: HostFixtures.framed(message),
            in: temporaryDirectory
        )

        XCTAssertLessThan(output.count - 4, 1024 * 1024, file: file, line: line)
        XCTAssertEqual(
            try HostFixtures.decodedReply(from: output),
            NativeHostReply(ok: false, captureId: nil, code: code),
            file: file,
            line: line
        )
        XCTAssertTrue(staging.stagedData.isEmpty, file: file, line: line)
        XCTAssertEqual(activator.activationCount, 0, file: file, line: line)
    }

    private func assertExactBoundedFailure(
        _ framedReply: Data,
        code: NativeHostErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertGreaterThanOrEqual(
            framedReply.count,
            4,
            file: file,
            line: line
        )
        XCTAssertLessThan(
            framedReply.count - 4,
            NativeMessageFraming.maximumReplyLength,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try HostFixtures.decodedReply(from: framedReply),
            NativeHostReply(ok: false, captureId: nil, code: code),
            file: file,
            line: line
        )

        let body = framedReply.subdata(in: 4..<framedReply.count)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any],
            file: file,
            line: line
        )
        XCTAssertEqual(Set(object.keys), ["ok", "code"], file: file, line: line)
        XCTAssertEqual(object["ok"] as? Bool, false, file: file, line: line)
        XCTAssertEqual(
            object["code"] as? String,
            code.rawValue,
            file: file,
            line: line
        )
    }
}
