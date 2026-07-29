import Foundation
import XCTest
@testable import MyShottr

final class CompositeTransferTests: TemporaryDirectoryTestCase {
    func testRejectsOutOfOrderCompositeChunk() throws {
        let transfer = try CompositeTransfer(requestId: UUID(), expectedChunks: 2)
        XCTAssertThrowsError(try transfer.append(index: 1, base64: "AA==")) {
            XCTAssertEqual($0 as? CompositeTransferError, .unexpectedChunk(expected: 0, received: 1))
        }
    }

    func testFinishesValidatedPNGAtItsOriginalDimensions() throws {
        let transfer = try CompositeTransfer(requestId: UUID(), expectedChunks: 1, directory: temporaryDirectory)
        try transfer.append(index: 0, base64: ProjectFixtures.pngData.base64EncodedString())

        let url = try transfer.finish()

        XCTAssertEqual(try PNGMetadata.read(from: url), PNGMetadata(pixelWidth: 2, pixelHeight: 2))
    }
}
