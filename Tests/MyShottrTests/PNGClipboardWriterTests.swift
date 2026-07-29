import AppKit
import XCTest
@testable import MyShottr

final class PNGClipboardWriterTests: XCTestCase {
    func testClipboardContainsPNG() throws {
        let pasteboard = NSPasteboard(name: .init("MyShottrTests-\(UUID().uuidString)"))
        try PNGClipboardWriter(pasteboard: pasteboard).write(data: ProjectFixtures.pngData)
        XCTAssertEqual(pasteboard.data(forType: .png), ProjectFixtures.pngData)
    }
}
