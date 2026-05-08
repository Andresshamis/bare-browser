import SwiftUI

public struct BrowserWindowView: View {
    @ObservedObject private var store: BrowserStore
    @StateObject private var webViewState = WebViewState()
    private let dataStoreProvider = ProfileWebsiteDataStoreProvider()

    public init(store: BrowserStore) {
        self.store = store
    }

    public var body: some View {
        NavigationSplitView {
            if store.sidebarIsVisible {
                SidebarView(store: store)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            }
        } detail: {
            BrowserContentView(
                store: store,
                webViewState: webViewState,
                dataStoreProvider: dataStoreProvider
            )
            .overlay(alignment: .top) {
                if store.isCommandBarPresented {
                    CommandBarView(store: store)
                        .padding(.top, 24)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .animation(.snappy(duration: 0.16), value: store.isCommandBarPresented)
    }
}
