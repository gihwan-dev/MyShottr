import Foundation
import XCTest

final class NativeHostProcessTests: XCTestCase {
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
        inputData: Data
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
