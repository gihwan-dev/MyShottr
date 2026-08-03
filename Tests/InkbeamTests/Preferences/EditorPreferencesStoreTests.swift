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

    func testAbsentStoredPreferencesReturnApprovedDefaults() {
        XCTAssertNil(defaults.data(forKey: EditorPreferences.storageKey))

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testMigratesValidVersionOnePreferencesAndPersistsVersionTwo() throws {
        let legacyData = try validVersionOneData()
        defaults.set(legacyData, forKey: EditorPreferences.legacyStorageKey)

        let result = store.load()

        XCTAssertEqual(result.tool, "rectangle")
        XCTAssertEqual(result.color, "#FF4D4F")
        XCTAssertEqual(result.strokeWidth, 8)
        XCTAssertEqual(result.textSize, 36)
        XCTAssertEqual(result.roughness, 2)
        XCTAssertEqual(result.opacity, 0.75)
        XCTAssertNil(result.rectangleFillColor)
        XCTAssertEqual(result.highlighterOpacity, 0.5)
        XCTAssertNotNil(defaults.data(forKey: EditorPreferences.storageKey))
        XCTAssertEqual(
            defaults.data(forKey: EditorPreferences.legacyStorageKey),
            legacyData
        )

        defaults.set(
            try JSONSerialization.data(withJSONObject: [
                "tool": "arrow",
                "color": "#1677FF",
                "strokeWidth": 2,
                "textSize": 16,
                "roughness": 0,
                "opacity": 0.25,
            ]),
            forKey: EditorPreferences.legacyStorageKey
        )
        XCTAssertEqual(store.load(), result)
    }

    func testInvalidVersionTwoDoesNotFallBackToVersionOne() throws {
        defaults.set(Data("{}".utf8), forKey: EditorPreferences.storageKey)
        defaults.set(
            try validVersionOneData(),
            forKey: EditorPreferences.legacyStorageKey
        )

        XCTAssertEqual(store.load(), .approvedDefaults)
    }

    func testVersionTwoRequiresExactJSONKeys() throws {
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

    func testVersionOneRequiresExactJSONKeys() throws {
        var invalid = try XCTUnwrap(
            JSONSerialization.jsonObject(with: validVersionOneData())
                as? [String: Any]
        )
        invalid["extra"] = true
        defaults.set(
            try JSONSerialization.data(withJSONObject: invalid),
            forKey: EditorPreferences.legacyStorageKey
        )

        XCTAssertEqual(store.load(), .approvedDefaults)
        XCTAssertNil(defaults.data(forKey: EditorPreferences.storageKey))
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
}
