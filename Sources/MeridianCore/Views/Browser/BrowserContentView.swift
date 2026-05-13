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
            if let message = store.lastUserMessage {
                statusRow(message)
                Divider()
            }
            webSurface
        }
        .background(.background)
        .alert(
            "Site Permission",
            isPresented: sitePermissionAlertIsPresented,
            presenting: store.pendingSitePermissionRequest
        ) { request in
            Button("Deny", role: .cancel) {
                _ = store.resolvePendingSitePermission(.deny, requestID: request.id)
            }
            Button("Allow") {
                _ = store.resolvePendingSitePermission(.allow, requestID: request.id)
            }
        } message: { request in
            Text(request.promptMessage)
        }
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
                downloadSafetyPolicy: store.downloadSafetyPolicy,
                sitePermissionPolicy: store.sitePermissionPolicy
            ) { title, url, isLoading in
                store.updateActiveTabFromWebView(title: title, url: url, isLoading: isLoading)
            } onSecurityMessage: { message in
                store.publishStatusMessage(message)
            } onURLConfirmationRequired: { kind, url, sourceContext in
                store.requestURLConfirmation(kind: kind, url: url, sourceContext: sourceContext)
            } onDownloadConfirmationRequired: { request, completion in
                store.requestDownloadConfirmation(request, completion: completion)
            } onSitePermissionRequest: { kind, origin in
                store.requestSitePermission(kind: kind, origin: origin, profileID: profile.id)
            }
            .id(tab.id)
        } else {
            StartPageView(store: store)
        }
    }

    private func statusRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("BrowserStatusMessage")

            Spacer(minLength: 0)

            Button {
                store.dismissLastUserMessage()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss status message")
            .accessibilityLabel("Dismiss status message")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private var sitePermissionAlertIsPresented: Binding<Bool> {
        Binding {
            store.pendingSitePermissionRequest != nil
        } set: { isPresented in
            if !isPresented {
                store.cancelPendingSitePermissionRequest()
            }
        }
    }

    private func syncWebViewState() {
        webViewState.title = store.activeTab?.title ?? "New Tab"
        webViewState.request(store.activeTab?.url)
    }
}
