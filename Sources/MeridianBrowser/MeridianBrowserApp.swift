import MeridianCore
import SwiftUI

@main
struct MeridianBrowserApp: App {
    private let sessionPersistence: SQLiteSessionPersistenceStore
    private let historyPersistence: SQLiteLocalHistoryPersistenceStore
    @StateObject private var store: BrowserStore

    init() {
        let sessionPersistence = SQLiteSessionPersistenceStore()
        let historyPersistence = SQLiteLocalHistoryPersistenceStore()
        let loadResult = sessionPersistence.loadSnapshot()
        let historyResult = historyPersistence.loadHistory(profiles: loadResult.snapshot.profiles)
        self.sessionPersistence = sessionPersistence
        self.historyPersistence = historyPersistence
        _store = StateObject(
            wrappedValue: BrowserStore(
                snapshot: loadResult.snapshot,
                localHistoryStore: LocalHistoryStore(entries: historyResult.entries),
                lastUserMessage: loadResult.recoveryReason?.userMessage
                    ?? historyResult.recoveryReason?.userMessage,
                sessionPersistence: sessionPersistence,
                localHistoryPersistence: historyPersistence
            )
        )
    }

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

            CommandMenu("History") {
                Button("Clear History for This Profile") {
                    store.clearHistoryForActiveProfile()
                }
            }
        }
    }
}
