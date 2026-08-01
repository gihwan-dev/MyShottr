import AppKit
import SwiftUI
import XCTest
@testable import MyShottr

@MainActor
final class DocumentCommandDefinitionTests: XCTestCase {
    func testOutputRegistryBuildsExactAppKitCommandsFromSharedDefinitions() {
        let definitions = DocumentCommandDefinition.outputCommands
        let menuItems = definitions.map { definition in
            let item = NSMenuItem(
                title: definition.title,
                action: definition.action,
                keyEquivalent: definition.appKitKeyEquivalent
            )
            item.keyEquivalentModifierMask =
                definition.appKitModifiers
            return item
        }

        XCTAssertEqual(definitions.count, 3)
        XCTAssertEqual(menuItems.map(\.title), [
            "Copy Image",
            "Save Project",
            "Export PNG",
        ])
        XCTAssertEqual(menuItems.map(\.action), [
            #selector(DocumentWindowController.copyComposite(_:)),
            #selector(DocumentWindowController.saveProjectAction(_:)),
            #selector(DocumentWindowController.exportComposite(_:)),
        ])
        XCTAssertEqual(menuItems.map(\.keyEquivalent), [
            "c",
            "s",
            "e",
        ])
        XCTAssertEqual(menuItems.map(\.keyEquivalentModifierMask), [
            [.command, .shift],
            [.command],
            [.command],
        ])
        XCTAssertEqual(definitions.map(\.key), [
            KeyEquivalent("c"),
            KeyEquivalent("s"),
            KeyEquivalent("e"),
        ])
        XCTAssertEqual(definitions.map(\.swiftUIModifiers), [
            [.command, .shift],
            [.command],
            [.command],
        ])
    }
}
