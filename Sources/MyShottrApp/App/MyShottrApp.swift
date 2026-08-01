import AppKit
import SwiftUI

@main
struct MyShottrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {
                Button(DocumentCommandDefinition.saveProject.title) {
                    NSApp.sendAction(
                        DocumentCommandDefinition.saveProject.action,
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut(
                    DocumentCommandDefinition.saveProject.key,
                    modifiers: DocumentCommandDefinition
                        .saveProject.swiftUIModifiers
                )
            }
            CommandMenu("Image") {
                Button(DocumentCommandDefinition.copyImage.title) {
                    NSApp.sendAction(
                        DocumentCommandDefinition.copyImage.action,
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut(
                    DocumentCommandDefinition.copyImage.key,
                    modifiers: DocumentCommandDefinition
                        .copyImage.swiftUIModifiers
                )

                Button(DocumentCommandDefinition.exportPNG.title) {
                    NSApp.sendAction(
                        DocumentCommandDefinition.exportPNG.action,
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut(
                    DocumentCommandDefinition.exportPNG.key,
                    modifiers: DocumentCommandDefinition
                        .exportPNG.swiftUIModifiers
                )
            }
        }
    }
}
