import AppKit
import OSLog
import SwiftUI

private let browserContentLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MeridianBrowser",
    category: "BrowserContent"
)

private let activeTabSnapshotHandoffDelayNanoseconds: UInt64 = 90_000_000

public struct BrowserContentView: View {
    @ObservedObject private var store: BrowserStore
    @ObservedObject private var webViewState: WebViewState
    @ObservedObject private var presentationState: BrowserContentPresentationState
    @Binding private var activityPageIsSelected: Bool
    @State private var cachedSpaceOverviewPages: [SidebarSpacePageSnapshot]?
    @State private var spaceOverviewRefreshTask: Task<Void, Never>?
    private let webViewRegistry: BrowserWebViewRegistry
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let webContentMouseExclusionRegion: WebContentMouseExclusionRegion?
    private let openSidebarThemeColorPicker: (SpaceID) -> Void

    public init(
        store: BrowserStore,
        webViewState: WebViewState,
        presentationState: BrowserContentPresentationState,
        webViewRegistry: BrowserWebViewRegistry,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        activityPageIsSelected: Binding<Bool> = .constant(false),
        webContentMouseExclusionRegion: WebContentMouseExclusionRegion? = nil,
        openSidebarThemeColorPicker: @escaping (SpaceID) -> Void = { _ in }
    ) {
        self.store = store
        self.webViewState = webViewState
        self.presentationState = presentationState
        self._activityPageIsSelected = activityPageIsSelected
        self.webViewRegistry = webViewRegistry
        self.dataStoreProvider = dataStoreProvider
        self.webContentMouseExclusionRegion = webContentMouseExclusionRegion
        self.openSidebarThemeColorPicker = openSidebarThemeColorPicker
    }

    public var body: some View {
        contentLifecycle
    }

    private var contentBase: some View {
        webSurface
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
            .overlay(alignment: .bottomTrailing) {
                floatingStatusStack
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .overlay(alignment: .topTrailing) {
                if let profile = activeWebProfile,
                   activeWebTab != nil,
                   !activityPageIsSelected {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(hex: profile.colorHex))
                            .frame(width: 7, height: 7)
                        Text(profile.name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(.separator.opacity(0.35), lineWidth: 0.5)
                    }
                    .padding(12)
                    .help("Website data profile: \(profile.name)")
                    .accessibilityLabel("Website data profile \(profile.name)")
                }
            }
            .animation(.snappy(duration: 0.18), value: store.lastUserMessage)
            .animation(.snappy(duration: 0.18), value: store.primaryActiveDownload?.id)
            .animation(.snappy(duration: 0.18), value: store.activeDownloads.count)
    }

    private var contentAlerts: some View {
        contentBase
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
    }

    private var contentLifecycle: some View {
        contentAlerts
            .onAppear {
                scheduleSpaceOverviewRefresh()
                syncWebViewState()
                pruneWebViewRegistry()
            }
            .onChange(of: store.selectedTabID) { _, _ in
                if !activityPageIsSelected {
                    beginSnapshotHandoffIfNeeded(for: store.selectedTabID)
                }
                if store.selectedTabID != nil {
                    presentationState.setPreviewStartPageSpaceID(nil)
                }
                syncWebViewState()
                if !activityPageIsSelected {
                    webViewRegistry.markActive(store.selectedTabID)
                }
            }
            .onChange(of: activityPageIsSelected) { _, isSelected in
                if isSelected {
                    presentationState.setPreviewTabID(nil)
                    presentationState.setPreviewStartPageSpaceID(nil)
                    presentationState.clearSnapshotHandoff()
                } else {
                    beginSnapshotHandoffIfNeeded(for: store.selectedTabID)
                    webViewRegistry.markActive(store.selectedTabID)
                }
                syncWebViewState()
            }
            .onChange(of: store.spaces) { _, _ in
                scheduleSpaceOverviewRefresh()
            }
            .onChange(of: store.folders) { _, _ in
                scheduleSpaceOverviewRefresh()
            }
            .onChange(of: store.tabs) { _, _ in
                scheduleSpaceOverviewRefresh()
            }
            .onChange(of: store.tabs.map(\.id)) { _, _ in
                pruneWebViewRegistry()
            }
            .onChange(of: tabSessionIdentitiesByID) { oldValue, newValue in
                let changedTabIDs = Set(newValue.keys.filter { tabID in
                    oldValue[tabID] != nil && oldValue[tabID] != newValue[tabID]
                })
                webViewRegistry.invalidate(tabIDs: changedTabIDs)
                for tabID in changedTabIDs {
                    presentationState.removeSnapshot(for: tabID)
                }
            }
            .onChange(of: store.profiles.map(\.id)) { _, profileIDs in
                dataStoreProvider.releaseEphemeralWebsiteDataStores(
                    keeping: Set(profileIDs)
                )
            }
            .task(id: store.lastUserMessage) {
                await autoDismissStatusMessageIfNeeded()
            }
            .onDisappear {
                spaceOverviewRefreshTask?.cancel()
                spaceOverviewRefreshTask = nil
            }
    }

    @ViewBuilder
    private var webSurface: some View {
        ZStack {
            WebViewHost(
                state: webViewState,
                activeTab: activeWebTab,
                activeProfile: activeWebProfile,
                isActive: !activityPageIsSelected,
                passwordAutofillRevision: store.passwordCredentialAutofillRevision,
                registry: webViewRegistry,
                dataStoreProvider: dataStoreProvider,
                securityPolicy: store.urlSecurityPolicy,
                downloadSafetyPolicy: store.downloadSafetyPolicy,
                sitePermissionPolicy: store.sitePermissionPolicy,
                mouseExclusionRegion: webContentMouseExclusionRegion
            ) { identity, title, url, isLoading, securityMessage in
                guard isCurrent(identity: identity) else {
                    return
                }

                store.updateTabFromWebView(
                    tabID: identity.tabID,
                    title: title,
                    url: url,
                    isLoading: isLoading,
                    securityMessage: securityMessage
                )
            } onFaviconChange: { identity, faviconURL in
                guard isCurrent(identity: identity) else { return }
                store.updateTabFavicon(faviconURL, for: identity.tabID)
            } onSecurityMessage: { identity, message in
                guard isSelected(identity: identity) else {
                    return
                }
                store.publishStatusMessage(message)
            } onURLConfirmationRequired: { identity, kind, url, sourceContext in
                guard isSelected(identity: identity) else {
                    return
                }
                store.requestURLConfirmation(kind: kind, url: url, sourceContext: sourceContext)
            } onDownloadConfirmationRequired: { identity, request, completion in
                guard isSelected(identity: identity) else {
                    browserContentLogger.info("download confirmation dropped inactive tab")
                    completion(nil)
                    return
                }
                browserContentLogger.info(
                    "download confirmation forwarding filenameEmpty=\(request.sanitizedFilename.isEmpty, privacy: .public)"
                )
                store.requestDownloadConfirmation(
                    request,
                    profileID: identity.profileID,
                    completion: completion
                )
            } onDownloadStarted: { identity, request, destinationURL, cancel in
                guard isCurrent(identity: identity) else {
                    browserContentLogger.info("download started canceled stale identity")
                    cancel()
                    _ = store.cancelDownload(request.id)
                    return
                }
                browserContentLogger.info("download started forwarded")
                store.registerDownloadCancellation(request.id, cancel: cancel)
                store.updateDownloadProgress(request.id, progress: 0)
            } onDownloadProgress: { identity, downloadID, progress in
                guard isCurrent(identity: identity) else {
                    _ = store.cancelDownload(downloadID)
                    return
                }
                store.updateDownloadProgress(downloadID, progress: progress)
            } onDownloadFinished: { identity, downloadID, destinationURL, quarantineApplied in
                guard isCurrent(identity: identity) else {
                    _ = store.cancelDownload(downloadID)
                    return
                }
                store.finishDownload(
                    downloadID,
                    destinationURL: destinationURL,
                    quarantineApplied: quarantineApplied
                )
            } onDownloadFailed: { identity, downloadID, message in
                guard isCurrent(identity: identity) else {
                    _ = store.cancelDownload(downloadID)
                    return
                }
                store.failDownload(downloadID, message: message)
            } onSitePermissionRequest: { identity, kind, origin in
                guard isSelected(identity: identity) else {
                    return .deny(reason: "Site permission request was blocked because its profile session is no longer active.")
                }
                return store.requestSitePermission(
                    kind: kind,
                    origin: origin,
                    profileID: identity.profileID
                )
            } onPasswordCredentialCaptured: { identity, candidate in
                guard isSelected(identity: identity) else {
                    return
                }
                store.requestPasswordSave(candidate, profileID: identity.profileID)
            } onPasswordCredentialsRequested: { identity, origin in
                guard isSelected(identity: identity) else {
                    return []
                }
                return store.savedPasswordCredentials(
                    for: origin,
                    profileID: identity.profileID,
                    allowsKeychainPrompt: false
                )
            } onSnapshotCaptured: { identity, image in
                guard isCurrent(identity: identity) else { return }
                presentationState.storeSnapshot(image, for: identity)
            } onWebViewActivated: { identity in
                guard isSelected(identity: identity) else {
                    return
                }

                completeSnapshotHandoffSoon(for: identity)
            }
            .opacity(activeWebTab == nil ? 0 : 1)
            .allowsHitTesting(activeWebTab != nil && !activityPageIsSelected)

            activityOverviewSurface

            startPageSurface

            foregroundSurface

            customizationPreviewSurface

            snapshotOverlay
        }
    }

    private var activityOverviewSurface: some View {
        BrowserAllSpacesContentOverviewView(
            pages: spaceOverviewPagesForDisplay,
            isLoading: spaceOverviewIsLoading,
            usesPinnedSidebarAppearance: store.sidebarIsLockedOpen,
            profileNamesByID: Dictionary(uniqueKeysWithValues: store.profiles.map { ($0.id, $0.name) }),
            selectSpace: { selectOverviewSpace($0) },
            selectTab: { selectOverviewTab($0) },
            customizeSpace: { customizeOverviewSpace($0) }
        )
        .opacity(activityPageIsSelected ? 1 : 0)
        .allowsHitTesting(activityPageIsSelected)
        .accessibilityHidden(!activityPageIsSelected)
        .zIndex(activityPageIsSelected ? 2 : 0)
    }

    @ViewBuilder
    private var startPageSurface: some View {
        if let snapshot = mountedStartPageSurfaceSnapshot {
            StartPageSurface(snapshot: snapshot) {
                store.showCommandBar()
            } customizeSpace: {
                _ = store.openSpaceCustomizer(for: snapshot.spaceID)
            } createFolder: {
                _ = store.createFolder(name: "New Folder", in: snapshot.spaceID)
            }
            .opacity(visibleStartPageSurfaceSnapshot == nil ? 0 : 1)
            .allowsHitTesting(startPageSurfaceAllowsHitTesting)
            .accessibilityHidden(visibleStartPageSurfaceSnapshot == nil)
            .zIndex(startPageSurfaceIsPreviewing ? 3 : 2)
        }
    }

    @ViewBuilder
    private var customizationPreviewSurface: some View {
        if let context = previewCustomizationContext {
            SpaceCustomizationPreviewShell(
                space: context.space,
                profileName: store.profiles.first { $0.id == context.space.profileID }?.name
            )
            .id(context.tab.id)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(3)
        }
    }

    @ViewBuilder
    private var foregroundSurface: some View {
        if activityPageIsSelected {
            EmptyView()
        } else if let tab = store.activeTab {
            switch tab.content {
            case .spaceCustomization(let spaceID):
                if let space = store.spaces.first(where: { $0.id == spaceID }) {
                    SpaceCustomizationView(
                        store: store,
                        space: space,
                        profiles: store.persistentProfiles,
                        openThemeColorPicker: openSidebarThemeColorPicker
                    )
                    .id(space.id)
                } else {
                    EmptyView()
                }
            case .passwordManager:
                PasswordManagerView(store: store)
                    .id("password-manager")
            case .web:
                EmptyView()
            }
        } else {
            EmptyView()
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

        guard let identity = store.profileContext(for: tab.id) else {
            return nil
        }
        return store.profiles.first { $0.id == identity.profileID }
    }

    @ViewBuilder
    private var snapshotOverlay: some View {
        if let image = snapshotOverlayImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
        }
    }

    private var snapshotOverlayImage: NSImage? {
        guard !activityPageIsSelected,
              previewCustomizationContext == nil else {
            return nil
        }

        return previewSnapshotImage ?? activeTabSnapshotHandoffImage
    }

    private var previewSnapshotImage: NSImage? {
        guard let previewTabID = presentationState.previewTabID,
              previewTabID != store.selectedTabID,
              let previewTab = store.tabs.first(where: { $0.id == previewTabID }),
              previewTab.content.isWeb else {
            return nil
        }

        return presentationState.snapshot(for: store.profileContext(for: previewTabID))
    }

    private var activeTabSnapshotHandoffImage: NSImage? {
        guard let snapshotHandoffTabID = presentationState.snapshotHandoffTabID,
              snapshotHandoffTabID == store.selectedTabID,
              let snapshotHandoffTab = store.tabs.first(where: { $0.id == snapshotHandoffTabID }),
              snapshotHandoffTab.content.isWeb else {
            return nil
        }

        return presentationState.snapshot(for: store.profileContext(for: snapshotHandoffTabID))
    }

    private var mountedStartPageSurfaceSnapshot: StartPageSurfaceSnapshot? {
        visibleStartPageSurfaceSnapshot ?? startPageSnapshot(for: store.selectedSpaceID)
    }

    private var visibleStartPageSurfaceSnapshot: StartPageSurfaceSnapshot? {
        if let previewSpaceID = presentationState.previewStartPageSpaceID,
           previewSpaceID != store.selectedSpaceID,
           let snapshot = startPageSnapshot(for: previewSpaceID) {
            return snapshot
        }

        guard activeContentShowsStartPage else {
            return nil
        }

        return startPageSnapshot(for: store.selectedSpaceID)
    }

    private var startPageSurfaceAllowsHitTesting: Bool {
        guard let snapshot = visibleStartPageSurfaceSnapshot else {
            return false
        }

        return activeContentShowsStartPage && snapshot.spaceID == store.selectedSpaceID
    }

    private var startPageSurfaceIsPreviewing: Bool {
        guard let snapshot = visibleStartPageSurfaceSnapshot else {
            return false
        }

        return snapshot.spaceID != store.selectedSpaceID
    }

    private var activeContentShowsStartPage: Bool {
        guard !activityPageIsSelected else {
            return false
        }

        if let activeTab = store.activeTab,
           !activeTab.content.isWeb {
            return false
        }

        return activeWebTab == nil
    }

    private func startPageSnapshot(for spaceID: SpaceID?) -> StartPageSurfaceSnapshot? {
        guard let spaceID,
              let space = store.spaces.first(where: { $0.id == spaceID }) else {
            return nil
        }

        return StartPageSurfaceSnapshot(space: space, profiles: store.profiles)
    }

    private var previewCustomizationContext: SpaceCustomizationPreviewContext? {
        guard !activityPageIsSelected,
              let previewTabID = presentationState.previewTabID,
              previewTabID != store.selectedTabID,
              let previewTab = store.tabs.first(where: { $0.id == previewTabID }),
              case .spaceCustomization(let spaceID) = previewTab.content,
              let space = store.spaces.first(where: { $0.id == spaceID }) else {
            return nil
        }

        return SpaceCustomizationPreviewContext(tab: previewTab, space: space)
    }

    private var spaceOverviewPagesForDisplay: [SidebarSpacePageSnapshot] {
        cachedSpaceOverviewPages ?? []
    }

    private var spaceOverviewIsLoading: Bool {
        cachedSpaceOverviewPages == nil && !store.sidebarSpaces.isEmpty
    }

    private func scheduleSpaceOverviewRefresh() {
        spaceOverviewRefreshTask?.cancel()

        let activeSpaces = store.sidebarSpaces
        guard !activeSpaces.isEmpty else {
            cachedSpaceOverviewPages = []
            return
        }

        let folders = store.folders
        let tabs = store.tabs
        spaceOverviewRefreshTask = Task.detached(priority: .utility) {
            let pages = SidebarSpacePageSnapshotBuilder.spacePages(
                activeSpaces: activeSpaces,
                folders: folders,
                tabs: tabs
            )

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                cachedSpaceOverviewPages = pages
            }
        }
    }

    private func selectOverviewSpace(_ id: SpaceID) {
        presentationState.beginSnapshotHandoff(
            to: overviewPreviewTabID(for: id).flatMap(store.profileContext(for:))
        )
        withTransaction(Transaction(animation: nil)) {
            store.selectSpace(id)
        }
        activityPageIsSelected = false
    }

    private func selectOverviewTab(_ id: TabID) {
        presentationState.beginSnapshotHandoff(to: store.profileContext(for: id))
        withTransaction(Transaction(animation: nil)) {
            store.selectTab(id)
        }
        activityPageIsSelected = false
    }

    private func customizeOverviewSpace(_ id: SpaceID) {
        presentationState.clearSnapshotHandoff()
        withTransaction(Transaction(animation: nil)) {
            _ = store.openSpaceCustomizer(for: id)
        }
        activityPageIsSelected = false
    }

    private func overviewPreviewTabID(for spaceID: SpaceID?) -> TabID? {
        guard let spaceID,
              let space = store.sidebarSpaces.first(where: { $0.id == spaceID }) else {
            return nil
        }

        let folders = store.folders.filter { $0.parentSpaceID == space.id }
        let tabsByID = Dictionary(uniqueKeysWithValues: store.tabs.map { ($0.id, $0) })
        return BrowserSpaceFocusedTabResolver.focusedTabID(for: space, folders: folders, tabsByID: tabsByID)
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
        if normalizedMessage.contains("blocked")
            || normalizedMessage.contains("failed")
            || normalizedMessage.contains("unsafe")
            || normalizedMessage.contains("unavailable")
            || normalizedMessage.contains("could not") {
            return "exclamationmark.triangle.fill"
        }
        if normalizedMessage.contains("download finished")
            || (normalizedMessage.contains("saved")
                && !normalizedMessage.contains("not saved")) {
            return "checkmark.circle.fill"
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
            || normalizedMessage.contains("could not")
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

    private func beginSnapshotHandoffIfNeeded(for tabID: TabID?) {
        guard let tabID,
              store.tabs.first(where: { $0.id == tabID })?.content.isWeb == true else {
            presentationState.clearSnapshotHandoff()
            return
        }

        guard presentationState.snapshotHandoffTabID != tabID else {
            return
        }

        presentationState.beginSnapshotHandoff(to: store.profileContext(for: tabID))
    }

    private func completeSnapshotHandoffSoon(for identity: WebContentSessionIdentity) {
        guard let handoffID = presentationState.snapshotHandoffToken(for: identity) else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: activeTabSnapshotHandoffDelayNanoseconds)
            guard isSelected(identity: identity) else {
                return
            }

            presentationState.completeSnapshotHandoff(handoffID, for: identity)
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
        guard !activityPageIsSelected else {
            presentationState.setActiveContentTabID(nil)
            webViewState.title = "Activity"
            webViewState.isLoading = false
            webViewState.canGoBack = false
            webViewState.canGoForward = false
            return
        }

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
        presentationState.removeSnapshots(keeping: Set(tabSessionIdentitiesByID.values))
    }

    private func isCurrent(identity: WebContentSessionIdentity) -> Bool {
        store.isCurrentWebContentSession(identity)
    }

    private func isSelected(identity: WebContentSessionIdentity) -> Bool {
        !activityPageIsSelected
            && identity.tabID == store.selectedTabID
            && isCurrent(identity: identity)
    }

    private var tabSessionIdentitiesByID: [TabID: WebContentSessionIdentity] {
        Dictionary(uniqueKeysWithValues: store.tabs.compactMap { tab in
            store.profileContext(for: tab.id).map { (tab.id, $0) }
        })
    }
}

private struct SpaceCustomizationPreviewContext {
    let tab: BrowserTab
    let space: BrowserSpace
}

private struct BrowserAllSpacesContentOverviewView: View {
    let pages: [SidebarSpacePageSnapshot]
    let isLoading: Bool
    let usesPinnedSidebarAppearance: Bool
    let profileNamesByID: [ProfileID: String]
    let selectSpace: (SpaceID) -> Void
    let selectTab: (TabID) -> Void
    let customizeSpace: (SpaceID) -> Void

    var body: some View {
        GeometryReader { proxy in
            let columnHeight = max(proxy.size.height - 40, 1)

            Group {
                if isLoading {
                    loadingState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pages.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(pages) { page in
                                BrowserSpaceContentPreviewColumn(
                                    page: page,
                                    usesPinnedSidebarAppearance: usesPinnedSidebarAppearance,
                                    profileName: profileNamesByID[page.space.profileID] ?? "Unknown Profile",
                                    selectSpace: selectSpace,
                                    selectTab: selectTab,
                                    customizeSpace: customizeSpace
                                )
                                .frame(width: columnWidth(for: proxy.size.width), height: columnHeight)
                            }
                        }
                        .padding(20)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                    .scrollIndicators(.hidden)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(.background)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading spaces")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sidebar.leading")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("No spaces")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func columnWidth(for availableWidth: CGFloat) -> CGFloat {
        min(max((availableWidth - 68) / 3, 264), 340)
    }
}

private struct BrowserSpaceContentPreviewColumn: View {
    @Environment(\.colorScheme) private var colorScheme

    let page: SidebarSpacePageSnapshot
    let usesPinnedSidebarAppearance: Bool
    let profileName: String
    let selectSpace: (SpaceID) -> Void
    let selectTab: (TabID) -> Void
    let customizeSpace: (SpaceID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    selectSpace(page.space.id)
                } label: {
                    HStack(spacing: 10) {
                        SpaceIconGlyph(
                            symbolName: page.space.symbolName,
                            colorHex: page.space.colorHex,
                            size: 28,
                            foregroundColor: headerIconForegroundColor
                        )
                        .frame(width: 28, height: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(page.space.name)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)

                            Text("\(profileName) • \(tabCount) tabs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Switch to \(page.space.name)")

                Button {
                    customizeSpace(page.space.id)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Customize \(page.space.name)")
                .accessibilityLabel("Customize \(page.space.name)")
            }
            .padding(12)

            Divider()

            if tabCount == 0 {
                emptyColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        tabSection("Essentials", symbolName: "sparkle", tabs: page.favoriteTabs)
                        tabSection("List Essentials", symbolName: "pin.fill", tabs: page.pinnedTabs)
                        folderSection
                        tabSection(page.space.name, symbolName: "rectangle.stack", tabs: page.regularTabs)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scrollIndicators(.hidden)
            }
        }
        .background {
            columnChrome
        }
        .overlay {
            columnShape
                .stroke(.separator.opacity(sidebarSettings.edgeOpacity), lineWidth: 0.5)
        }
        .shadow(
            color: columnTint.opacity(SidebarGlassRendering.shadowOpacity(for: sidebarSettings)),
            radius: 18,
            x: 0,
            y: 8
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var columnChrome: some View {
        SidebarGlassMaterial(shape: columnShape, tintColor: columnTint, settings: sidebarSettings)
    }

    private var sidebarTheme: SidebarChromeTheme {
        SidebarChromeTheme.theme(for: page.space)
    }

    private var sidebarSettings: SidebarGlassSettings {
        usesPinnedSidebarAppearance
            ? sidebarTheme.appearance.pinnedSettings
            : sidebarTheme.appearance.base
    }

    private var columnTint: Color {
        Color(hex: sidebarTheme.tintHex)
    }

    private var columnShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var headerIconForegroundColor: Color {
        switch SidebarGlassRendering.selectedSpaceIconContrast(for: sidebarSettings, tintHex: sidebarTheme.tintHex) {
        case .adaptive:
            return colorScheme == .dark ? .white : .black
        case .dark:
            return .black
        case .light:
            return .white
        }
    }

    @ViewBuilder
    private func tabSection(_ title: String, symbolName: String, tabs: [SidebarTabItemSnapshot]) -> some View {
        if !tabs.isEmpty {
            BrowserSpaceContentPreviewSectionHeader(title: title, symbolName: symbolName)
            ForEach(tabs) { item in
                BrowserSpaceContentPreviewTabRow(item: item, depth: 0, selectTab: selectTab)
            }
        }
    }

    @ViewBuilder
    private var folderSection: some View {
        if !page.folders.isEmpty {
            BrowserSpaceContentPreviewSectionHeader(title: "Folders", symbolName: "folder")
            ForEach(page.folders) { folder in
                BrowserSpaceContentPreviewFolderRows(
                    folder: folder,
                    depth: 0,
                    selectTab: selectTab
                )
            }
        }
    }

    private var emptyColumn: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("No tabs")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var tabCount: Int {
        page.favoriteTabs.count
            + page.pinnedTabs.count
            + page.regularTabs.count
            + folderTabCount(page.folders)
    }

    private func folderTabCount(_ folders: [SidebarFolderItemSnapshot]) -> Int {
        folders.reduce(0) { count, folder in
            count + folder.tabs.count + folderTabCount(folder.childFolders)
        }
    }
}

private struct BrowserSpaceContentPreviewSectionHeader: View {
    let title: String
    let symbolName: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 15)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
    }
}

private struct BrowserSpaceContentPreviewFolderRows: View {
    let folder: SidebarFolderItemSnapshot
    let depth: Int
    let selectTab: (TabID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)

                Text(folder.folder.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 14)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)

            ForEach(folder.tabs) { item in
                BrowserSpaceContentPreviewTabRow(
                    item: item,
                    depth: depth + 1,
                    selectTab: selectTab
                )
            }

            ForEach(folder.childFolders) { childFolder in
                BrowserSpaceContentPreviewFolderRows(
                    folder: childFolder,
                    depth: depth + 1,
                    selectTab: selectTab
                )
            }
        }
    }
}

private struct BrowserSpaceContentPreviewTabRow: View {
    let item: SidebarTabItemSnapshot
    let depth: Int
    let selectTab: (TabID) -> Void

    var body: some View {
        Button {
            selectTab(item.tab.id)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: tabIconName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconStyle)
                    .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.tab.title)
                        .font(.callout)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 14)
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(item.tab.title)
    }

    private var subtitle: String? {
        switch item.tab.content {
        case .spaceCustomization:
            return "Customize Space"
        case .passwordManager:
            return "Saved Passwords"
        case .web:
            return item.tab.url?.host(percentEncoded: false)
        }
    }

    private var tabIconName: String {
        switch item.tab.content {
        case .spaceCustomization:
            return "slider.horizontal.3"
        case .passwordManager:
            return "key"
        case .web:
            break
        }
        if item.tab.isFavorite {
            return "sparkle"
        }
        if item.tab.isPinned {
            return "pin"
        }
        return "globe"
    }

    private var iconStyle: AnyShapeStyle {
        if item.isSelected {
            return AnyShapeStyle(Color.accentColor)
        }
        return AnyShapeStyle(.secondary)
    }
}
