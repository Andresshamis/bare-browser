import SwiftUI

public struct BrowserContentView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider

    public init(
        store: BrowserStore,
        webViewState: WebViewState,
        dataStoreProvider: ProfileWebsiteDataStoreProvider
    ) {
        self.store = store
        self.webViewState = webViewState
        self.dataStoreProvider = dataStoreProvider
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            webSurface
        }
        .background(.background)
        .onAppear(perform: syncWebViewState)
        .onChange(of: store.selectedTabID) { _, _ in
            syncWebViewState()
        }
        .onChange(of: store.activeTab?.url) { _, _ in
            syncWebViewState()
        }
    }

    @ViewBuilder
    private var webSurface: some View {
        if let tab = store.activeTab,
           let profile = store.profiles.first(where: { $0.id == tab.profileID }),
           tab.url != nil {
            WebViewHost(
                state: webViewState,
                profile: profile,
                dataStoreProvider: dataStoreProvider,
                securityPolicy: store.urlSecurityPolicy,
                downloadSafetyPolicy: store.downloadSafetyPolicy
            ) { title, url, isLoading in
                store.updateActiveTabFromWebView(title: title, url: url, isLoading: isLoading)
            } onURLConfirmationRequired: { kind, url, sourceURL in
                store.requestURLConfirmation(kind: kind, url: url, sourceURL: sourceURL)
            } onDownloadConfirmationRequired: { request, completion in
                store.requestDownloadConfirmation(request, completion: completion)
            }
            .id(tab.id)
        } else {
            StartPageView(store: store)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                store.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("Toggle sidebar")

            Divider()
                .frame(height: 18)

            Button {
                webViewState.dispatch(.goBack)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!webViewState.canGoBack)
            .help("Back")

            Button {
                webViewState.dispatch(.goForward)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!webViewState.canGoForward)
            .help("Forward")

            Button {
                webViewState.dispatch(webViewState.isLoading ? .stopLoading : .reload)
            } label: {
                Image(systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise")
            }
            .help(webViewState.isLoading ? "Stop" : "Reload")

            Button {
                store.showCommandBar()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: siteSymbolName)
                    Text(addressText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "command")
                        .font(.caption)
                    Text("T")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open command bar")

            Button {
                _ = store.createTab()
            } label: {
                Image(systemName: "plus")
            }
            .help("New tab")

            Button {
                store.closeSelectedTab()
            } label: {
                Image(systemName: "xmark")
            }
            .disabled(store.activeTab == nil)
            .help("Close tab")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var addressText: String {
        if let url = store.activeTab?.url {
            return url.absoluteString
        }
        return "Search or enter address"
    }

    private var siteSymbolName: String {
        guard let url = store.activeTab?.url else {
            return "magnifyingglass"
        }
        return store.urlSecurityPolicy.isInsecureTransport(url) ? "exclamationmark.triangle" : "lock"
    }

    private func syncWebViewState() {
        webViewState.title = store.activeTab?.title ?? "New Tab"
        webViewState.request(store.activeTab?.url)
    }
}
