import Foundation
import XCTest

final class NativeMessageFramingTests: XCTestCase {
    func testReadsOneFramedMessage() throws {
        let body = Data(#"{"protocolVersion":1}"#.utf8)
        let input = HostFixtures.framed(body)

        XCTAssertEqual(try NativeMessageFraming.read(from: input), body)
    }

    func testRejectsMessageAboveChromeLimitBeforeReadingBody() {
        var length = UInt32(64 * 1024 * 1024 + 1).littleEndian
        let input = Data(bytes: &length, count: 4)

        XCTAssertThrowsError(try NativeMessageFraming.read(from: input)) {
            XCTAssertEqual($0 as? NativeMessageError, .messageTooLarge)
        }
    }

    func testRejectsTruncatedLengthPrefix() {
        XCTAssertThrowsError(try NativeMessageFraming.read(from: Data([1, 0, 0]))) {
            XCTAssertEqual($0 as? NativeMessageError, .truncatedHeader)
        }
    }

    func testRejectsTruncatedMessageBody() {
        var length = UInt32(4).littleEndian
        let input = Data(bytes: &length, count: 4) + Data([1, 2, 3])

        XCTAssertThrowsError(try NativeMessageFraming.read(from: input)) {
            XCTAssertEqual($0 as? NativeMessageError, .truncatedMessage)
        }
    }

    func testFramesReplyWithFourByteLittleEndianLength() throws {
        let body = Data(#"{"ok":true}"#.utf8)

        let framed = try NativeMessageFraming.frameReply(body)

        XCTAssertEqual(Array(framed.prefix(4)), [11, 0, 0, 0])
        XCTAssertEqual(Data(framed.dropFirst(4)), body)
    }

    func testRejectsReplyAboveChromeLimit() {
        let body = Data(repeating: 0, count: 1024 * 1024 + 1)

        XCTAssertThrowsError(try NativeMessageFraming.frameReply(body)) {
            XCTAssertEqual($0 as? NativeMessageError, .replyTooLarge)
        }
    }
}
