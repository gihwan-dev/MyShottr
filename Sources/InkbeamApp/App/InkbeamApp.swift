import AppKit
import SwiftUI

@main
struct InkbeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {
                Button(DocumentCommandDefinition.saveProject.title) {
                    DocumentCommandDispatcher.performFromKeyWindow(
                        .saveProject
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
                    DocumentCommandDispatcher.performFromKeyWindow(
                        .copyImage
                    )
                }
                .keyboardShortcut(
                    DocumentCommandDefinition.copyImage.key,
                    modifiers: DocumentCommandDefinition
                        .copyImage.swiftUIModifiers
                )

                Button(DocumentCommandDefinition.exportPNG.title) {
                    DocumentCommandDispatcher.performFromKeyWindow(
                        .exportPNG
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
