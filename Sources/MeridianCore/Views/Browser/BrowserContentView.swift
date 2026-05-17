import AppKit
import SwiftUI

public struct BrowserContentView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @ObservedObject private var presentationState: BrowserContentPresentationState
    private let webViewRegistry: BrowserWebViewRegistry
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let webContentMouseExclusionRegion: WebContentMouseExclusionRegion?

    public init(
        store: BrowserStore,
        webViewState: WebViewState,
        presentationState: BrowserContentPresentationState,
        webViewRegistry: BrowserWebViewRegistry,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        webContentMouseExclusionRegion: WebContentMouseExclusionRegion? = nil
    ) {
        self.store = store
        self.webViewState = webViewState
        self.presentationState = presentationState
        self.webViewRegistry = webViewRegistry
        self.dataStoreProvider = dataStoreProvider
        self.webContentMouseExclusionRegion = webContentMouseExclusionRegion
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let message = store.lastUserMessage {
                statusRow(message)
                Divider()
            }
            if let download = store.primaryActiveDownload {
                downloadStatusRow(download)
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
        .onAppear {
            syncWebViewState()
            pruneWebViewRegistry()
            presentationState.setActiveContentTabID(store.selectedTabID)
        }
        .onChange(of: store.selectedTabID) { _, _ in
            syncWebViewState()
            presentationState.setActiveContentTabID(store.selectedTabID)
            webViewRegistry.markActive(store.selectedTabID)
        }
        .onChange(of: store.tabs.map(\.id)) { _, _ in
            pruneWebViewRegistry()
        }
        .onChange(of: tabProfileIDsByID) { oldValue, newValue in
            let changedTabIDs = Set(newValue.keys.filter { tabID in
                oldValue[tabID] != nil && oldValue[tabID] != newValue[tabID]
            })
            webViewRegistry.invalidate(tabIDs: changedTabIDs)
        }
    }

    @ViewBuilder
    private var webSurface: some View {
        ZStack {
            WebViewHost(
                state: webViewState,
                activeTab: activeWebTab,
                activeProfile: activeWebProfile,
                registry: webViewRegistry,
                dataStoreProvider: dataStoreProvider,
                securityPolicy: store.urlSecurityPolicy,
                downloadSafetyPolicy: store.downloadSafetyPolicy,
                sitePermissionPolicy: store.sitePermissionPolicy,
                mouseExclusionRegion: webContentMouseExclusionRegion
            ) { tabID, title, url, isLoading, securityMessage in
                guard isSelected(tabID: tabID) else {
                    return
                }

                store.updateTabFromWebView(
                    tabID: tabID,
                    title: title,
                    url: url,
                    isLoading: isLoading,
                    securityMessage: securityMessage
                )
            } onSecurityMessage: { tabID, message in
                guard isSelected(tabID: tabID) else {
                    return
                }
                store.publishStatusMessage(message)
            } onURLConfirmationRequired: { tabID, kind, url, sourceContext in
                guard isSelected(tabID: tabID) else {
                    return
                }
                store.requestURLConfirmation(kind: kind, url: url, sourceContext: sourceContext)
            } onDownloadConfirmationRequired: { tabID, request, completion in
                guard isSelected(tabID: tabID) else {
                    completion(nil)
                    return
                }
                store.requestDownloadConfirmation(request, completion: completion)
            } onDownloadStarted: { tabID, request, destinationURL, cancel in
                guard isSelected(tabID: tabID) else {
                    return
                }
                store.registerDownloadCancellation(request.id, cancel: cancel)
                store.updateDownloadProgress(request.id, progress: 0)
            } onDownloadProgress: { _, downloadID, progress in
                store.updateDownloadProgress(downloadID, progress: progress)
            } onDownloadFinished: { _, downloadID, destinationURL, quarantineApplied in
                store.finishDownload(
                    downloadID,
                    destinationURL: destinationURL,
                    quarantineApplied: quarantineApplied
                )
            } onDownloadFailed: { _, downloadID, message in
                store.failDownload(downloadID, message: message)
            } onSitePermissionRequest: { tabID, profileID, kind, origin in
                guard isSelected(tabID: tabID) else {
                    return .deny(reason: "Site permission request was blocked because the tab is not active.")
                }
                return store.requestSitePermission(kind: kind, origin: origin, profileID: profileID)
            } onSnapshotCaptured: { tabID, image in
                presentationState.storeSnapshot(image, for: tabID)
            }
            .opacity(activeWebTab == nil ? 0 : 1)
            .allowsHitTesting(activeWebTab != nil)

            foregroundSurface

            previewSnapshotOverlay
        }
    }

    @ViewBuilder
    private var foregroundSurface: some View {
        if let tab = store.activeTab {
            switch tab.content {
            case .spaceCustomization(let spaceID):
                if let space = store.spaces.first(where: { $0.id == spaceID }) {
                    SpaceCustomizationView(
                        store: store,
                        space: space,
                        profiles: store.persistentProfiles
                    )
                    .id(space.id)
                } else {
                    StartPageView(store: store)
                }
            case .web:
                if activeWebTab == nil {
                    StartPageView(store: store)
                }
            }
        } else {
            StartPageView(store: store)
        }
    }

    private var activeWebTab: BrowserTab? {
        guard let tab = store.activeTab,
              tab.content.isWeb,
              tab.url != nil,
              activeWebProfile != nil else {
            return nil
        }

        return tab
    }

    private var activeWebProfile: BrowserProfile? {
        guard let tab = store.activeTab,
              tab.content.isWeb else {
            return nil
        }

        return store.profiles.first { $0.id == tab.profileID }
    }

    @ViewBuilder
    private var previewSnapshotOverlay: some View {
        if let image = previewSnapshotImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
        }
    }

    private var previewSnapshotImage: NSImage? {
        guard let previewTabID = presentationState.previewTabID,
              previewTabID != store.selectedTabID,
              let previewTab = store.tabs.first(where: { $0.id == previewTabID }),
              previewTab.content.isWeb else {
            return nil
        }

        return presentationState.snapshot(for: previewTabID)
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

    private func downloadStatusRow(_ download: BrowserDownload) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(downloadStatusText(for: download))
                    .font(.callout)
                    .lineLimit(1)

                if let progress = download.progress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .accessibilityLabel("Download progress")
                        .accessibilityValue("\(download.progressPercent ?? 0) percent")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Download progress")
                }
            }

            Spacer(minLength: 0)

            if store.activeDownloads.count > 1 {
                Text("+\(store.activeDownloads.count - 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(store.activeDownloads.count - 1) additional downloads")
            }

            Button {
                cancel(download)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Cancel download")
            .accessibilityLabel("Cancel download")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private func downloadStatusText(for download: BrowserDownload) -> String {
        switch download.state {
        case .waitingForDestination:
            return "Waiting to save \(download.filename)"
        case .downloading:
            if let percent = download.progressPercent {
                return "Downloading \(download.filename) \(percent)%"
            }
            return "Downloading \(download.filename)"
        case .finished:
            return "Downloaded \(download.filename)"
        case .failed:
            return "Download failed: \(download.filename)"
        case .canceled:
            return "Download canceled: \(download.filename)"
        }
    }

    private func cancel(_ download: BrowserDownload) {
        switch download.state {
        case .waitingForDestination:
            store.cancelPendingDownloadConfirmation()
        case .downloading:
            _ = store.cancelDownload(download.id)
        case .finished, .failed, .canceled:
            break
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
        presentationState.setActiveContentTabID(store.selectedTabID)
        webViewState.title = store.activeTab?.title ?? "New Tab"
        guard store.activeTab?.content.isWeb == true else {
            webViewState.request(nil)
            webViewState.isLoading = false
            webViewState.canGoBack = false
            webViewState.canGoForward = false
            return
        }
        webViewState.request(
            store.activeTab?.url,
            pendingHTTPFallbackURL: store.activeTab?.restorationMetadata.pendingHTTPFallbackURL
        )
    }

    private func pruneWebViewRegistry() {
        webViewRegistry.prune(
            keeping: Set(store.tabs.map(\.id)),
            activeTabID: store.selectedTabID
        )
        presentationState.removeSnapshots(keeping: Set(store.tabs.map(\.id)))
    }

    private func isSelected(tabID: TabID) -> Bool {
        tabID == store.selectedTabID
    }

    private var tabProfileIDsByID: [TabID: ProfileID] {
        Dictionary(uniqueKeysWithValues: store.tabs.map { ($0.id, $0.profileID) })
    }
}
