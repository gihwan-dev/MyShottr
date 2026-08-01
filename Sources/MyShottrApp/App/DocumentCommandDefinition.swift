import AppKit
import SwiftUI

struct DocumentCommandDefinition {
    let title: String
    let action: Selector
    let key: KeyEquivalent
    let swiftUIModifiers: EventModifiers
    let appKitKeyEquivalent: String
    let appKitModifiers: NSEvent.ModifierFlags

    static let copyImage = DocumentCommandDefinition(
        title: "Copy Image",
        action: #selector(
            DocumentWindowController.copyComposite(_:)
        ),
        key: KeyEquivalent("c"),
        swiftUIModifiers: [.command, .shift],
        appKitKeyEquivalent: "c",
        appKitModifiers: [.command, .shift]
    )

    static let saveProject = DocumentCommandDefinition(
        title: "Save Project",
        action: #selector(
            DocumentWindowController.saveProjectAction(_:)
        ),
        key: KeyEquivalent("s"),
        swiftUIModifiers: [.command],
        appKitKeyEquivalent: "s",
        appKitModifiers: [.command]
    )

    static let exportPNG = DocumentCommandDefinition(
        title: "Export PNG",
        action: #selector(
            DocumentWindowController.exportComposite(_:)
        ),
        key: KeyEquivalent("e"),
        swiftUIModifiers: [.command],
        appKitKeyEquivalent: "e",
        appKitModifiers: [.command]
    )

    static let outputCommands = [
        copyImage,
        saveProject,
        exportPNG,
    ]
}
