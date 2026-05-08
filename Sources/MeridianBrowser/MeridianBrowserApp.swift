import MeridianCore
import SwiftUI

@main
struct MeridianBrowserApp: App {
    @StateObject private var store = BrowserStore()

    var body: some Scene {
        WindowGroup("Meridian Browser") {
            BrowserWindowView(store: store)
                .frame(minWidth: 900, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") {
                    store.showCommandBar()
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button("New Space") {
                    _ = store.createSpace(name: "New Space")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("New Private Window") {
                    let profile = store.createProfile(name: "Private", ephemeral: true)
                    _ = store.createSpace(name: "Private", profileID: profile.id)
                    store.showCommandBar()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift, .option])
            }

            CommandMenu("Tabs") {
                Button("Close Tab") {
                    store.closeSelectedTab()
                }
                .keyboardShortcut("w", modifiers: [.command])

                Button("Command Bar") {
                    store.showCommandBar()
                }
                .keyboardShortcut("l", modifiers: [.command])
            }

            CommandMenu("View") {
                Button("Toggle Sidebar") {
                    store.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
