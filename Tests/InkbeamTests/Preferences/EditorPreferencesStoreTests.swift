import Foundation
import XCTest
@testable import Inkbeam

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

    func testAbsentStoredPreferencesReturnApprovedDefaults() {
        XCTAssertNil(defaults.data(forKey: EditorPreferences.storageKey))

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testPreferencesIgnorePreInkbeamStorage() throws {
        defaults.set(
            try JSONEncoder().encode(validCurrentPreferences()),
            forKey: "editorPreferences.v2"
        )
        defaults.set(
            try validVersionOneData(),
            forKey: "editorPreferences.v1"
        )

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testInvalidCurrentPreferencesDoNotFallBackToPreInkbeamStorage() throws {
        defaults.set(Data("{}".utf8), forKey: EditorPreferences.storageKey)
        defaults.set(
            try JSONEncoder().encode(validCurrentPreferences()),
            forKey: "editorPreferences.v2"
        )

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testCurrentPreferencesRequireExactJSONKeys() throws {
        let valid: [String: Any] = [
            "tool": "rectangle",
            "color": "#FF4D4F",
            "strokeWidth": 8,
            "textSize": 36,
            "roughness": 2,
            "opacity": 0.75,
            "rectangleFillColor": NSNull(),
            "highlighterOpacity": 0.25,
        ]
        var missing = valid
        missing.removeValue(forKey: "rectangleFillColor")
        var extra = valid
        extra["extra"] = true

        for object in [missing, extra] {
            defaults.set(
                try JSONSerialization.data(withJSONObject: object),
                forKey: EditorPreferences.storageKey
            )
            XCTAssertEqual(store.load(), .approvedDefaults)
        }
    }

    func testEncodingNilRectangleFillColorWritesExplicitNull() throws {
        let data = try JSONEncoder().encode(EditorPreferences.approvedDefaults)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertTrue(object.keys.contains("rectangleFillColor"))
        XCTAssertTrue(object["rectangleFillColor"] is NSNull)
    }

    func testWellFormedButSemanticallyInvalidStoredPreferencesReturnApprovedDefaults() throws {
        let invalid = EditorPreferences(
            tool: "unknown",
            color: "#1677FF",
            strokeWidth: 4,
            textSize: 24,
            roughness: 1,
            opacity: 1,
            rectangleFillColor: nil,
            highlighterOpacity: 0.5
        )
        defaults.set(try JSONEncoder().encode(invalid), forKey: EditorPreferences.storageKey)

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testSavingInvalidPreferencesIsRejected() {
        let invalid = EditorPreferences(
            tool: "unknown",
            color: "#1677FF",
            strokeWidth: 4,
            textSize: 24,
            roughness: 1,
            opacity: 1,
            rectangleFillColor: nil,
            highlighterOpacity: 0.5
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
            opacity: 1,
            rectangleFillColor: "#FADB14",
            highlighterOpacity: 0.25
        )

        try store.save(line)

        XCTAssertEqual(store.load(), line)
    }

    func testSavingInvalidFillOrHighlighterOpacityIsRejected() {
        let invalidFill = EditorPreferences(
            tool: "line",
            color: "#1677FF",
            strokeWidth: 4,
            textSize: 24,
            roughness: 1,
            opacity: 1,
            rectangleFillColor: "#FFFFFF",
            highlighterOpacity: 0.5
        )
        let invalidHighlighterOpacity = EditorPreferences(
            tool: "line",
            color: "#1677FF",
            strokeWidth: 4,
            textSize: 24,
            roughness: 1,
            opacity: 1,
            rectangleFillColor: nil,
            highlighterOpacity: 0.75
        )

        XCTAssertThrowsError(try store.save(invalidFill))
        XCTAssertThrowsError(try store.save(invalidHighlighterOpacity))
    }

    private func validVersionOneData() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "tool": "rectangle",
            "color": "#FF4D4F",
            "strokeWidth": 8,
            "textSize": 36,
            "roughness": 2,
            "opacity": 0.75,
        ])
    }

    private func validCurrentPreferences() -> EditorPreferences {
        EditorPreferences(
            tool: "rectangle",
            color: "#FF4D4F",
            strokeWidth: 8,
            textSize: 36,
            roughness: 2,
            opacity: 0.75,
            rectangleFillColor: nil,
            highlighterOpacity: 0.25
        )
    }
}
