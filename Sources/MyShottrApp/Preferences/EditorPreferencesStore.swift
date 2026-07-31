import Foundation

struct EditorPreferences: Codable, Equatable, Sendable {
    static let storageKey = "editorPreferences.v2"
    static let legacyStorageKey = "editorPreferences.v1"
    static let approvedDefaults = EditorPreferences(
        tool: "selection",
        color: "#1677FF",
        strokeWidth: 4,
        textSize: 24,
        roughness: 1,
        opacity: 1,
        rectangleFillColor: nil,
        highlighterOpacity: 0.5
    )

    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double
    var rectangleFillColor: String?
    var highlighterOpacity: Double

    private enum CodingKeys: String, CodingKey {
        case tool
        case color
        case strokeWidth
        case textSize
        case roughness
        case opacity
        case rectangleFillColor
        case highlighterOpacity
    }

    var isValid: Bool {
        let palette = ["#000000", "#FF4D4F", "#1677FF", "#FADB14"]
        return ["selection", "rectangle", "arrow", "line", "text", "freehand", "highlighter", "blur", "redaction", "numberMarker"].contains(tool)
            && palette.contains(color)
            && [2, 4, 8].contains(strokeWidth)
            && [16, 24, 36].contains(textSize)
            && [0, 1, 2].contains(roughness)
            && [0.25, 0.5, 0.75, 1].contains(opacity)
            && (rectangleFillColor.map { palette.contains($0) } ?? true)
            && [0.25, 0.5].contains(highlighterOpacity)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tool, forKey: .tool)
        try container.encode(color, forKey: .color)
        try container.encode(strokeWidth, forKey: .strokeWidth)
        try container.encode(textSize, forKey: .textSize)
        try container.encode(roughness, forKey: .roughness)
        try container.encode(opacity, forKey: .opacity)
        if let rectangleFillColor {
            try container.encode(
                rectangleFillColor,
                forKey: .rectangleFillColor
            )
        } else {
            try container.encodeNil(forKey: .rectangleFillColor)
        }
        try container.encode(
            highlighterOpacity,
            forKey: .highlighterOpacity
        )
    }
}

private struct LegacyEditorPreferences: Codable {
    var tool: String
    var color: String
    var strokeWidth: Int
    var textSize: Int
    var roughness: Int
    var opacity: Double

    var isValid: Bool {
        ["selection", "rectangle", "arrow", "line", "text", "freehand", "highlighter", "blur", "redaction", "numberMarker"].contains(tool)
            && ["#000000", "#FF4D4F", "#1677FF", "#FADB14"].contains(color)
            && [2, 4, 8].contains(strokeWidth)
            && [16, 24, 36].contains(textSize)
            && [0, 1, 2].contains(roughness)
            && [0.25, 0.5, 0.75, 1].contains(opacity)
    }
}

protocol EditorPreferencesStoring: Sendable {
    func load() -> EditorPreferences
    func save(_ preferences: EditorPreferences) throws
}

enum EditorPreferencesStoreError: Error, Equatable {
    case invalidPreferences
}

struct UserDefaultsEditorPreferencesStore: EditorPreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EditorPreferences {
        if defaults.object(forKey: EditorPreferences.storageKey) != nil {
            guard
                let data = defaults.data(
                    forKey: EditorPreferences.storageKey
                ),
                hasExactKeys(
                    data,
                    expected: [
                        "tool",
                        "color",
                        "strokeWidth",
                        "textSize",
                        "roughness",
                        "opacity",
                        "rectangleFillColor",
                        "highlighterOpacity",
                    ]
                ),
                let preferences = try? JSONDecoder().decode(
                    EditorPreferences.self,
                    from: data
                ),
                preferences.isValid
            else {
                return .approvedDefaults
            }
            return preferences
        }

        guard
            let data = defaults.data(
                forKey: EditorPreferences.legacyStorageKey
            ),
            hasExactKeys(
                data,
                expected: [
                    "tool",
                    "color",
                    "strokeWidth",
                    "textSize",
                    "roughness",
                    "opacity",
                ]
            ),
            let legacy = try? JSONDecoder().decode(
                LegacyEditorPreferences.self,
                from: data
            ),
            legacy.isValid
        else {
            return .approvedDefaults
        }

        let migrated = EditorPreferences(
            tool: legacy.tool,
            color: legacy.color,
            strokeWidth: legacy.strokeWidth,
            textSize: legacy.textSize,
            roughness: legacy.roughness,
            opacity: legacy.opacity,
            rectangleFillColor: nil,
            highlighterOpacity: 0.5
        )
        do {
            try save(migrated)
        } catch {
            return .approvedDefaults
        }
        return migrated
    }

    func save(_ preferences: EditorPreferences) throws {
        guard preferences.isValid else { throw EditorPreferencesStoreError.invalidPreferences }
        defaults.set(try JSONEncoder().encode(preferences), forKey: EditorPreferences.storageKey)
    }

    private func hasExactKeys(
        _ data: Data,
        expected: Set<String>
    ) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return false
        }
        return Set(dictionary.keys) == expected
    }
}
