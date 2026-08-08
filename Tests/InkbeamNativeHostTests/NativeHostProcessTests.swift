import Darwin
import Foundation
import XCTest

final class NativeHostProcessTests: XCTestCase {
    func testExecutableStagesOneOwnerOnlyPNGInInjectedInbox() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InkbeamNativeHostProcessTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let inboxURL = temporaryDirectory
            .appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        let appURL = try makeTestApplication(in: temporaryDirectory)

        let result = try runHost(
            inputData: HostFixtures.framed(
                try HostFixtures.protocolMessage()
            ),
            environment: [
                NativeHostTestEnvironment.inboxPathKey: inboxURL.path,
                NativeHostTestEnvironment.appPathKey: appURL.path,
                NativeHostTestEnvironment.notificationKey:
                    "dev.gihwan.inkbeam.tests.captureReady",
            ]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        let reply = try HostFixtures.decodedReply(from: result.replyData)
        XCTAssertTrue(reply.ok)
        XCTAssertNil(reply.code)
        let captureID: UUID = try XCTUnwrap(reply.captureId)
        XCTAssertTrue(result.errorData.isEmpty)

        let entries = try FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(
            entries.map(\.lastPathComponent),
            ["\(captureID.uuidString).png"]
        )
        let inboxAttributes = try FileManager.default.attributesOfItem(
            atPath: inboxURL.path
        )
        let captureAttributes = try FileManager.default.attributesOfItem(
            atPath: entries[0].path
        )
        XCTAssertEqual(
            (inboxAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o700
        )
        XCTAssertEqual(
            (captureAttributes[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )
        XCTAssertEqual(
            (captureAttributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            getuid()
        )
        XCTAssertEqual(try Data(contentsOf: entries[0]), HostFixtures.validPNG)
    }

    func testExecutableActivationFailurePreservesOneOwnerOnlyPendingPNG() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InkbeamNativeHostProcessTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let inboxURL = temporaryDirectory
            .appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let result = try runHost(
            inputData: HostFixtures.framed(
                try HostFixtures.protocolMessage()
            ),
            environment: [
                NativeHostTestEnvironment.inboxPathKey: inboxURL.path,
                NativeHostTestEnvironment.appPathKey: temporaryDirectory
                    .appendingPathComponent("Missing.app")
                    .path,
                NativeHostTestEnvironment.notificationKey:
                    "dev.gihwan.inkbeam.tests.captureReady",
            ]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        try assertExactFailureReply(
            result.replyData,
            code: .appActivationFailed
        )
        XCTAssertTrue(result.errorData.isEmpty)

        let entries = try FileManager.default.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(entries.count, 1)
        let capture = try XCTUnwrap(entries.first)
        XCTAssertTrue(
            UUID(
                uuidString: capture.deletingPathExtension().lastPathComponent
            ) != nil
        )
        XCTAssertEqual(capture.pathExtension, "png")
        let captureAttributes = try FileManager.default.attributesOfItem(
            atPath: capture.path
        )
        XCTAssertEqual(
            try XCTUnwrap(
                captureAttributes[.posixPermissions] as? NSNumber
            ).intValue & 0o777,
            0o600
        )
        XCTAssertEqual(
            (captureAttributes[.ownerAccountID] as? NSNumber)?.uint32Value,
            getuid()
        )
        XCTAssertEqual(try Data(contentsOf: capture), HostFixtures.validPNG)
    }

    func testExecutableStagingFailureLeavesNoPendingCapture() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InkbeamNativeHostProcessTests-\(UUID().uuidString)",
                isDirectory: true
            )
        let inboxURL = temporaryDirectory.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        let original = Data("not a directory".utf8)
        try original.write(to: inboxURL)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let result = try runHost(
            inputData: HostFixtures.framed(
                try HostFixtures.protocolMessage()
            ),
            environment: [
                NativeHostTestEnvironment.inboxPathKey: inboxURL.path,
                NativeHostTestEnvironment.appPathKey: temporaryDirectory
                    .appendingPathComponent("Unused.app")
                    .path,
                NativeHostTestEnvironment.notificationKey:
                    "dev.gihwan.inkbeam.tests.captureReady",
            ]
        )

        XCTAssertEqual(result.terminationStatus, 0)
        try assertExactFailureReply(
            result.replyData,
            code: .stagingFailed
        )
        XCTAssertTrue(result.errorData.isEmpty)
        XCTAssertEqual(try Data(contentsOf: inboxURL), original)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(
                atPath: temporaryDirectory.path
            ),
            ["Inbox"]
        )
    }

    func testExecutableRejectsDuplicateMemberAsInvalidMessage() throws {
        let result = try runHost(
            inputData: HostFixtures.framed(
                HostFixtures.duplicateProtocolVersionMessage(
                    captureMode: "fullPage"
                )
            )
        )

        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertEqual(
            try HostFixtures.decodedReply(from: result.replyData),
            NativeHostReply(ok: false, captureId: nil, code: .invalidMessage)
        )
        XCTAssertTrue(result.errorData.isEmpty)
    }

    func testExecutableRejectsExtremeNestingWithOneBoundedReply() throws {
        let depth = 100_000
        let message = Data(
            (
                String(repeating: "[", count: depth)
                    + "0"
                    + String(repeating: "]", count: depth)
            ).utf8
        )
        let result = try runHost(inputData: HostFixtures.framed(message))

        XCTAssertEqual(result.terminationStatus, 0)
        guard result.replyData.count >= 4 else {
            XCTFail("Expected one framed INVALID_MESSAGE reply")
            return
        }
        XCTAssertLessThan(result.replyData.count - 4, 1024 * 1024)
        XCTAssertEqual(
            try HostFixtures.decodedReply(from: result.replyData),
            NativeHostReply(ok: false, captureId: nil, code: .invalidMessage)
        )
        XCTAssertTrue(result.errorData.isEmpty)
    }

    private func assertExactFailureReply(
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

    private func runHost(
        inputData: Data,
        environment: [String: String] = [:]
    ) throws -> (
        terminationStatus: Int32,
        replyData: Data,
        errorData: Data
    ) {
        let process = Process()
        process.executableURL = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("InkbeamNativeHost")

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error
        process.environment = ProcessInfo.processInfo.environment
            .merging(environment) { _, injected in injected }

        try process.run()
        try input.fileHandleForWriting.write(contentsOf: inputData)
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let replyData = try output.fileHandleForReading.readToEnd() ?? Data()
        let errorData = try error.fileHandleForReading.readToEnd() ?? Data()
        return (
            terminationStatus: process.terminationStatus,
            replyData: replyData,
            errorData: errorData
        )
    }

    private func makeTestApplication(in root: URL) throws -> URL {
        let appURL = root.appendingPathComponent(
            "Inkbeam.app",
            isDirectory: true
        )
        let contentsURL = appURL.appendingPathComponent(
            "Contents",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: contentsURL,
            withIntermediateDirectories: true
        )
        try Data("test plist".utf8).write(
            to: contentsURL.appendingPathComponent("Info.plist")
        )
        return appURL
    }
}
