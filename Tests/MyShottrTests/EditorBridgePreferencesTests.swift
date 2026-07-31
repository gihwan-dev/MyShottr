import Foundation
import XCTest
@testable import MyShottr

@MainActor
final class EditorBridgePreferencesTests: XCTestCase {
    func testInjectedPreferenceStoreSuppliesInitialTool() throws {
        let preferences = EditorPreferences(
            tool: "arrow",
            color: "#FF4D4F",
            strokeWidth: 8,
            textSize: 36,
            roughness: 2,
            opacity: 0.75,
            rectangleFillColor: nil,
            highlighterOpacity: 0.5
        )
        var outgoing: [NativeToEditorEnvelope] = []
        let bridge = EditorBridge(
            session: DocumentSession(),
            preferences: StubPreferences(preferences),
            outgoingMessageObserver: { outgoing.append($0) }
        )

        try bridge.load(project: ProjectFixtures.project(text: "Initial tool"))
        bridge.receive(data: try EditorToNativeEnvelope(
            type: .editorReady,
            payload: .object([:])
        ).encodedData())

        let load = try XCTUnwrap(outgoing.last)
        guard case let .object(payload) = load.payload else {
            return XCTFail("Expected object load payload")
        }
        XCTAssertEqual(payload["initialTool"], .string("arrow"))
        bridge.tearDown()
    }

    func testValidPreferenceMessageSavesWithoutModifyingDocumentSession() throws {
        let session = DocumentSession()
        let project = ProjectFixtures.project(text: "Unmodified document")
        try session.open(project: project)
        let preferences = RecordingPreferences(initial: .approvedDefaults)
        let bridge = EditorBridge(session: session, preferences: preferences)
        let expected = EditorPreferences(
            tool: "line",
            color: "#FADB14",
            strokeWidth: 8,
            textSize: 36,
            roughness: 2,
            opacity: 0.75,
            rectangleFillColor: nil,
            highlighterOpacity: 0.25
        )
        let message = try EditorToNativeEnvelope(
            type: .editorPreferencesChanged,
            payload: .object([
                "tool": .string(expected.tool),
                "defaults": .object([
                    "color": .string(expected.color),
                    "strokeWidth": .number(Double(expected.strokeWidth)),
                    "textSize": .number(Double(expected.textSize)),
                    "roughness": .number(Double(expected.roughness)),
                    "opacity": .number(expected.opacity),
                    "rectangleFillColor": .null,
                    "highlighterOpacity": .number(
                        expected.highlighterOpacity
                    ),
                ]),
            ])
        )

        bridge.receive(data: try message.encodedData())

        XCTAssertEqual(preferences.saved, [expected])
        XCTAssertEqual(session.project, project)
        XCTAssertFalse(session.isModified)
        XCTAssertNil(bridge.lastError)
        bridge.tearDown()
    }

    func testValidPreferenceMessageDecodesPaletteRectangleFill() throws {
        let preferences = RecordingPreferences(initial: .approvedDefaults)
        let bridge = EditorBridge(
            session: DocumentSession(),
            preferences: preferences
        )
        let expected = EditorPreferences(
            tool: "rectangle",
            color: "#FF4D4F",
            strokeWidth: 8,
            textSize: 36,
            roughness: 2,
            opacity: 0.75,
            rectangleFillColor: "#FADB14",
            highlighterOpacity: 0.5
        )
        let message = try EditorToNativeEnvelope(
            type: .editorPreferencesChanged,
            payload: .object([
                "tool": .string(expected.tool),
                "defaults": .object([
                    "color": .string(expected.color),
                    "strokeWidth": .number(Double(expected.strokeWidth)),
                    "textSize": .number(Double(expected.textSize)),
                    "roughness": .number(Double(expected.roughness)),
                    "opacity": .number(expected.opacity),
                    "rectangleFillColor": .string(
                        try XCTUnwrap(expected.rectangleFillColor)
                    ),
                    "highlighterOpacity": .number(
                        expected.highlighterOpacity
                    ),
                ]),
            ])
        )

        bridge.receive(data: try message.encodedData())

        XCTAssertEqual(preferences.saved, [expected])
        XCTAssertNil(bridge.lastError)
        bridge.tearDown()
    }
}

private final class RecordingPreferences: EditorPreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: EditorPreferences
    private var savedValues: [EditorPreferences] = []

    init(initial: EditorPreferences) {
        value = initial
    }

    var saved: [EditorPreferences] {
        lock.withLock { savedValues }
    }

    func load() -> EditorPreferences {
        lock.withLock { value }
    }

    func save(_ preferences: EditorPreferences) throws {
        lock.withLock {
            value = preferences
            savedValues.append(preferences)
        }
    }
}
