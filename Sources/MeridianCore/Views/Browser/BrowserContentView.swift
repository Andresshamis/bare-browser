import AppKit
import OSLog
import SwiftUI

private let browserContentLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MeridianBrowser",
    category: "BrowserContent"
)

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
        webSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay(alignment: .bottomTrailing) {
            floatingStatusStack
                .padding(.trailing, 16)
                .padding(.bottom, 16)
        }
        .animation(.snappy(duration: 0.18), value: store.lastUserMessage)
        .animation(.snappy(duration: 0.18), value: store.primaryActiveDownload?.id)
        .animation(.snappy(duration: 0.18), value: store.activeDownloads.count)
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
        .task(id: store.lastUserMessage) {
            await autoDismissStatusMessageIfNeeded()
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
                    browserContentLogger.info("download confirmation dropped inactive tab")
                    completion(nil)
                    return
                }
                browserContentLogger.info(
                    "download confirmation forwarding filenameEmpty=\(request.sanitizedFilename.isEmpty, privacy: .public)"
                )
                store.requestDownloadConfirmation(request, completion: completion)
            } onDownloadStarted: { tabID, request, destinationURL, cancel in
                guard isSelected(tabID: tabID) else {
                    browserContentLogger.info("download started dropped inactive tab")
                    return
                }
                browserContentLogger.info("download started forwarded")
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

    @ViewBuilder
    private var floatingStatusStack: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let message = store.lastUserMessage {
                statusToast(message)
                    .transition(floatingStatusTransition)
            }

            if let download = store.primaryActiveDownload {
                downloadToast(download)
                    .transition(floatingStatusTransition)
            }
        }
        .frame(maxWidth: 360, alignment: .trailing)
        .allowsHitTesting(true)
    }

    private var floatingStatusTransition: AnyTransition {
        .move(edge: .bottom)
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.98, anchor: .bottomTrailing))
    }

    private func statusToast(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon(for: message))
                .foregroundStyle(statusTint(for: message))
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
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("Dismiss status message")
            .accessibilityLabel("Dismiss status message")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.14), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func downloadToast(_ download: BrowserDownload) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(downloadStatusText(for: download))
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let progress = download.progress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .frame(width: 190)
                        .accessibilityLabel("Download progress")
                        .accessibilityValue("\(download.progressPercent ?? 0) percent")
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 190)
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
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .help("Cancel download")
            .accessibilityLabel("Cancel download")
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(width: 332, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 8)
        .accessibilityElement(children: .contain)
    }

    private func statusIcon(for message: String) -> String {
        let normalizedMessage = message.lowercased()
        if normalizedMessage.contains("download finished") || normalizedMessage.contains("saved") {
            return "checkmark.circle.fill"
        }
        if normalizedMessage.contains("blocked")
            || normalizedMessage.contains("failed")
            || normalizedMessage.contains("unsafe")
            || normalizedMessage.contains("unavailable") {
            return "exclamationmark.triangle.fill"
        }

        return "info.circle.fill"
    }

    private func statusTint(for message: String) -> Color {
        switch statusIcon(for: message) {
        case "checkmark.circle.fill":
            return .green
        case "exclamationmark.triangle.fill":
            return .yellow
        default:
            return .secondary
        }
    }

    private func autoDismissStatusMessageIfNeeded() async {
        guard let message = store.lastUserMessage else {
            return
        }

        let delay = statusDismissDelay(for: message)
        try? await Task.sleep(nanoseconds: delay)
        guard !Task.isCancelled else {
            return
        }

        await MainActor.run {
            if store.lastUserMessage == message {
                store.dismissLastUserMessage()
            }
        }
    }

    private func statusDismissDelay(for message: String) -> UInt64 {
        let normalizedMessage = message.lowercased()
        let seconds: UInt64 = normalizedMessage.contains("blocked")
            || normalizedMessage.contains("failed")
            || normalizedMessage.contains("unsafe")
            || normalizedMessage.contains("unavailable")
            ? 7
            : 4

        return seconds * 1_000_000_000
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
