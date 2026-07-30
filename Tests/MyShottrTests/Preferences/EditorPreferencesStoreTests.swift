import Foundation
import XCTest
@testable import MyShottr

final class EditorPreferencesStoreTests: XCTestCase {
    private let suiteName = "EditorPreferencesStoreTests"
    private var defaults: UserDefaults!
    private var store: UserDefaultsEditorPreferencesStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)!
        store = UserDefaultsEditorPreferencesStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testInvalidStoredPreferencesReturnApprovedDefaults() {
        defaults.set(Data("not-json".utf8), forKey: EditorPreferences.storageKey)

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testSavingInvalidPreferencesIsRejected() {
        let invalid = EditorPreferences(
            tool: "unknown",
            color: "#1677FF",
            strokeWidth: 4,
            textSize: 24,
            roughness: 1,
            opacity: 1
        )

        XCTAssertThrowsError(try store.save(invalid))
    }

    func testLinePreferencesCanBeSavedAndLoaded() throws {
        let line = EditorPreferences(
            tool: "line",
            color: "#1677FF",
            strokeWidth: 4,
            textSize: 24,
            roughness: 1,
            opacity: 1
        )

        try store.save(line)

        XCTAssertEqual(store.load(), line)
    }
}
