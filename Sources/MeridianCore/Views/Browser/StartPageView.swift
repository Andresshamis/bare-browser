import SwiftUI

public struct StartPageView: View {
    @ObservedObject private var store: BrowserStore

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Meridian Browser")
                .font(.system(size: 32, weight: .semibold))

            HStack(spacing: 10) {
                Button {
                    store.showCommandBar()
                } label: {
                    Label("Open", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("t", modifiers: [.command])

                Button {
                    _ = store.createSpace(name: "New Space")
                } label: {
                    Label("Space", systemImage: "square.grid.2x2")
                }

                Button {
                    _ = store.createFolder(name: "New Folder")
                } label: {
                    Label("Folder", systemImage: "folder")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
