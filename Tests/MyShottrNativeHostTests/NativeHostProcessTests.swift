import Foundation
import XCTest

final class NativeHostProcessTests: XCTestCase {
    func testExecutableRejectsDuplicateMemberAsInvalidMessage() throws {
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
        try input.fileHandleForWriting.write(
            contentsOf: HostFixtures.framed(
                HostFixtures.duplicateProtocolVersionMessage(
                    captureMode: "fullPage"
                )
            )
        )
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let replyData = try XCTUnwrap(try output.fileHandleForReading.readToEnd())
        let errorData = try error.fileHandleForReading.readToEnd() ?? Data()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            try HostFixtures.decodedReply(from: replyData),
            NativeHostReply(ok: false, captureId: nil, code: .invalidMessage)
        )
        XCTAssertTrue(errorData.isEmpty)
    }
}
