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
                Button("Save Project") {
                    NSApp.sendAction(
                        #selector(DocumentWindowController.saveProjectAction(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
            CommandMenu("Image") {
                Button("Copy Image") {
                    NSApp.sendAction(
                        #selector(DocumentWindowController.copyComposite(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Export PNG") {
                    NSApp.sendAction(
                        #selector(DocumentWindowController.exportComposite(_:)),
                        to: nil,
                        from: nil
                    )
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }
    }
}
