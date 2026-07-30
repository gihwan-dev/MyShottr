import Foundation

struct EditorPreferences: Codable, Equatable, Sendable {
    static let storageKey = "editorPreferences.v1"
    static let approvedDefaults = EditorPreferences(
        tool: "selection",
        color: "#1677FF",
        strokeWidth: 4,
        textSize: 24,
        roughness: 1,
        opacity: 1
    )

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

protocol EditorPreferencesStoring {
    func load() -> EditorPreferences
    func save(_ preferences: EditorPreferences) throws
}

enum EditorPreferencesStoreError: Error, Equatable {
    case invalidPreferences
}

struct UserDefaultsEditorPreferencesStore: EditorPreferencesStoring {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> EditorPreferences {
        guard let data = defaults.data(forKey: EditorPreferences.storageKey),
              let preferences = try? JSONDecoder().decode(EditorPreferences.self, from: data),
              preferences.isValid
        else {
            return .approvedDefaults
        }
        return preferences
    }

    func save(_ preferences: EditorPreferences) throws {
        guard preferences.isValid else { throw EditorPreferencesStoreError.invalidPreferences }
        defaults.set(try JSONEncoder().encode(preferences), forKey: EditorPreferences.storageKey)
    }
}
