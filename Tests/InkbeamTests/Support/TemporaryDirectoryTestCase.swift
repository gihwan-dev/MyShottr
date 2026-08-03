import Foundation
import XCTest

class TemporaryDirectoryTestCase: XCTestCase {
    private(set) var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyShottrTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        temporaryDirectory = directory
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try FileManager.default.removeItem(at: temporaryDirectory)
            self.temporaryDirectory = nil
        }

        try super.tearDownWithError()
    }
}
