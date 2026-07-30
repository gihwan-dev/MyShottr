import Darwin
import Foundation
import XCTest

final class NativeHostProcessTests: XCTestCase {
    func testExecutableStagesOneOwnerOnlyPNGInInjectedInbox() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MyShottrNativeHostProcessTests-\(UUID().uuidString)",
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
            .appendingPathComponent("MyShottrNativeHost")

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
}
