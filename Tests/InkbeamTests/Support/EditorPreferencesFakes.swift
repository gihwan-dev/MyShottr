@testable import Inkbeam

struct StubPreferences: EditorPreferencesStoring {
    let value: EditorPreferences

    init(_ value: EditorPreferences) {
        self.value = value
    }

    func load() -> EditorPreferences { value }
    func save(_ preferences: EditorPreferences) throws {}
}
