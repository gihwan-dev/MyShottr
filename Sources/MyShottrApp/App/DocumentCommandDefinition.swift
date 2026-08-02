import AppKit
import SwiftUI

struct DocumentCommandDefinition {
    struct Shortcut: Equatable {
        enum Modifier: Hashable {
            case command
            case shift
        }

        let key: Character
        let modifiers: Set<Modifier>
    }

    let title: String
    let action: Selector
    let shortcut: Shortcut

    var key: KeyEquivalent {
        KeyEquivalent(shortcut.key)
    }

    var swiftUIModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if shortcut.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if shortcut.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    var appKitKeyEquivalent: String {
        String(shortcut.key)
    }

    var appKitModifiers: NSEvent.ModifierFlags {
        var modifiers: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if shortcut.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }

    private init(
        title: String,
        action: Selector,
        shortcut: Shortcut
    ) {
        self.title = title
        self.action = action
        self.shortcut = shortcut
    }

    static let copyImage = DocumentCommandDefinition(
        title: "Copy Image",
        action: #selector(
            DocumentWindowController.copyComposite(_:)
        ),
        shortcut: Shortcut(
            key: "c",
            modifiers: [.command, .shift]
        )
    )

    static let saveProject = DocumentCommandDefinition(
        title: "Save Project",
        action: #selector(
            DocumentWindowController.saveProjectAction(_:)
        ),
        shortcut: Shortcut(
            key: "s",
            modifiers: [.command]
        )
    )

    static let exportPNG = DocumentCommandDefinition(
        title: "Export PNG",
        action: #selector(
            DocumentWindowController.exportComposite(_:)
        ),
        shortcut: Shortcut(
            key: "e",
            modifiers: [.command]
        )
    )

    static let outputCommands = [
        copyImage,
        saveProject,
        exportPNG,
    ]
}

@MainActor
enum DocumentCommandDispatcher {
    @discardableResult
    static func performFromKeyWindow(
        _ definition: DocumentCommandDefinition
    ) -> Bool {
        perform(
            definition,
            startingAt: NSApp.keyWindow?.firstResponder
        )
    }

    @discardableResult
    static func perform(
        _ definition: DocumentCommandDefinition,
        startingAt firstResponder: NSResponder?
    ) -> Bool {
        guard let firstResponder else {
            return false
        }
        return firstResponder.tryToPerform(
            definition.action,
            with: nil
        )
    }
}
