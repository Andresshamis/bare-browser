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

            sitePermissionsMenu

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

    private var sitePermissionsMenu: some View {
        Menu {
            if let context = activeSitePermissionContext {
                Section("Site") {
                    Label(context.origin.displayString, systemImage: "globe")
                }

                Section("Permissions") {
                    ForEach(Self.manageableSitePermissionKinds, id: \.self) { kind in
                        Menu {
                            sitePermissionDecisionButton(.ask, kind: kind, context: context)
                            sitePermissionDecisionButton(.allow, kind: kind, context: context)
                            sitePermissionDecisionButton(.deny, kind: kind, context: context)
                        } label: {
                            Label(
                                "\(permissionTitle(for: kind)): \(permissionDecisionTitle(for: decision(for: kind, context: context)))",
                                systemImage: permissionSymbolName(for: kind)
                            )
                        }
                    }
                }

                Section("Limited by WebKit") {
                    disabledPermissionItem("Location: Unsupported", symbolName: "location.slash")
                    disabledPermissionItem("Notifications: Unsupported", symbolName: "bell.slash")
                    disabledPermissionItem("Autoplay: User gesture required", symbolName: "play.slash")
                }
            } else {
                disabledPermissionItem("No active site", symbolName: "globe.badge.chevron.backward")
            }
        } label: {
            Image(systemName: sitePermissionMenuSymbolName)
        }
        .help("Site permissions")
        .accessibilityLabel("Site permissions")
    }

    private func sitePermissionDecisionButton(
        _ decision: SitePermissionDecision,
        kind: SitePermissionKind,
        context: ActiveSitePermissionContext
    ) -> some View {
        Button {
            _ = store.setSitePermissionDecision(
                decision,
                for: kind,
                origin: context.origin,
                profileID: context.profileID
            )
        } label: {
            Label(
                permissionDecisionTitle(for: decision),
                systemImage: self.decision(for: kind, context: context) == decision ? "checkmark.circle.fill" : "circle"
            )
        }
        .accessibilityLabel("\(permissionTitle(for: kind)) \(permissionDecisionTitle(for: decision))")
    }

    private func disabledPermissionItem(_ title: String, symbolName: String) -> some View {
        Button {} label: {
            Label(title, systemImage: symbolName)
        }
        .disabled(true)
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

    private var sitePermissionMenuSymbolName: String {
        guard let context = activeSitePermissionContext else {
            return "shield"
        }

        let hasStoredDecision = Self.manageableSitePermissionKinds.contains { kind in
            decision(for: kind, context: context) != store.sitePermissionPolicy.defaultDecision(for: kind)
        }
        return hasStoredDecision ? "shield.lefthalf.filled" : "shield"
    }

    private var activeSitePermissionContext: ActiveSitePermissionContext? {
        guard let tab = store.activeTab,
              let url = tab.url,
              let origin = SitePermissionOrigin(url: url) else {
            return nil
        }
        return ActiveSitePermissionContext(origin: origin, profileID: tab.profileID)
    }

    private func decision(
        for kind: SitePermissionKind,
        context: ActiveSitePermissionContext
    ) -> SitePermissionDecision {
        store.sitePermissionDecision(for: kind, origin: context.origin, profileID: context.profileID)
            ?? store.sitePermissionPolicy.defaultDecision(for: kind)
    }

    private func permissionDecisionTitle(for decision: SitePermissionDecision) -> String {
        switch decision {
        case .ask:
            "Ask Every Time"
        case .allow:
            "Allow"
        case .deny:
            "Block"
        }
    }

    private func permissionTitle(for kind: SitePermissionKind) -> String {
        switch kind {
        case .camera:
            "Camera"
        case .microphone:
            "Microphone"
        case .cameraAndMicrophone:
            "Camera & Microphone"
        case .popupWindow:
            "Pop-ups"
        case .geolocation:
            "Location"
        case .notifications:
            "Notifications"
        case .autoplay:
            "Autoplay"
        }
    }

    private func permissionSymbolName(for kind: SitePermissionKind) -> String {
        switch kind {
        case .camera:
            "camera"
        case .microphone:
            "mic"
        case .cameraAndMicrophone:
            "video.badge.waveform"
        case .popupWindow:
            "macwindow.badge.plus"
        case .geolocation:
            "location"
        case .notifications:
            "bell"
        case .autoplay:
            "play"
        }
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
        webViewState.request(
            store.activeTab?.url,
            pendingHTTPFallbackURL: store.activeTab?.restorationMetadata.pendingHTTPFallbackURL
        )
    }

    private static let manageableSitePermissionKinds: [SitePermissionKind] = [
        .camera,
        .microphone,
        .cameraAndMicrophone,
        .popupWindow
    ]
}

private struct ActiveSitePermissionContext {
    var origin: SitePermissionOrigin
    var profileID: ProfileID
}
