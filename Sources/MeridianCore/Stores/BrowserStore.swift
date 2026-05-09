import Combine
import Foundation

@MainActor
public final class BrowserStore: ObservableObject {
    @Published public var profiles: [BrowserProfile]
    @Published public var spaces: [BrowserSpace]
    @Published public var folders: [BrowserFolder]
    @Published public var tabs: [BrowserTab]
    @Published public var splitViews: [SplitViewLayout]
    @Published public var selectedSpaceID: SpaceID?
    @Published public var selectedTabID: TabID?
    @Published public var isCommandBarPresented: Bool
    @Published public var sidebarIsVisible: Bool
    @Published public var pendingURLConfirmation: URLConfirmationRequest?
    @Published public var pendingDownloadConfirmation: DownloadConfirmationRequest?
    @Published public private(set) var isChoosingDownloadDestination: Bool
    @Published public var lastUserMessage: String?
    @Published public private(set) var pendingSitePermissionRequest: SitePermissionRequest?
    @Published public private(set) var sitePermissionSettings: [SitePermissionSetting]
    @Published public private(set) var historyEntries: [BrowserHistoryEntry]

    public let commandRouter: CommandRouter
    public let urlSecurityPolicy: URLSecurityPolicy
    public let downloadSafetyPolicy: DownloadSafetyPolicy
    public let sitePermissionPolicy: SitePermissionPolicy
    private let sessionPersistence: SessionSnapshotPersisting?
    private var localHistoryStore: LocalHistoryStore
    private var pendingDownloadCompletion: (@MainActor (URL?) -> Void)?

    public init(
        snapshot: BrowserSessionSnapshot = SessionSnapshotFactory.initial(),
        commandRouter: CommandRouter = CommandRouter(),
        urlSecurityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        sitePermissionSettings: [SitePermissionSetting] = [],
        localHistoryStore: LocalHistoryStore = LocalHistoryStore(),
        lastUserMessage: String? = nil,
        sessionPersistence: SessionSnapshotPersisting? = nil
    ) {
        self.profiles = snapshot.profiles
        self.spaces = snapshot.spaces
        self.folders = snapshot.folders
        self.tabs = snapshot.tabs
        self.splitViews = snapshot.splitViews
        self.selectedSpaceID = snapshot.selectedSpaceID
        self.selectedTabID = snapshot.selectedTabID
        self.isCommandBarPresented = false
        self.sidebarIsVisible = true
        self.pendingURLConfirmation = nil
        self.pendingDownloadConfirmation = nil
        self.isChoosingDownloadDestination = false
        self.lastUserMessage = lastUserMessage
        self.pendingSitePermissionRequest = nil
        self.sitePermissionSettings = sitePermissionSettings
        self.historyEntries = localHistoryStore.entries
        self.commandRouter = commandRouter
        self.urlSecurityPolicy = urlSecurityPolicy
        self.downloadSafetyPolicy = downloadSafetyPolicy
        self.sitePermissionPolicy = sitePermissionPolicy
        self.sessionPersistence = sessionPersistence
        self.localHistoryStore = localHistoryStore
        self.pendingDownloadCompletion = nil
    }

    public var selectedSpace: BrowserSpace? {
        guard let selectedSpaceID else {
            return nil
        }
        return spaces.first { $0.id == selectedSpaceID }
    }

    public var activeTab: BrowserTab? {
        guard let selectedTabID else {
            return nil
        }
        return tabs.first { $0.id == selectedTabID }
    }

    public var activeProfile: BrowserProfile? {
        guard let profileID = activeTab?.profileID ?? selectedSpace?.profileID else {
            return profiles.first
        }
        return profiles.first { $0.id == profileID }
    }

    public func snapshot(date: Date = Date()) -> BrowserSessionSnapshot {
        BrowserSessionSnapshot(
            profiles: profiles,
            spaces: spaces,
            folders: folders,
            tabs: tabs,
            splitViews: splitViews,
            selectedSpaceID: selectedSpaceID,
            selectedTabID: selectedTabID,
            capturedAt: date
        )
    }

    public func persistentSnapshot(date: Date = Date()) -> BrowserSessionSnapshot {
        SessionPersistenceBoundary.persistentSnapshot(
            from: snapshot(date: date),
            fallback: SessionSnapshotFactory.initial(date: date)
        )
    }

    @discardableResult
    public func createSpace(name: String, profileID: ProfileID? = nil) -> BrowserSpace {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = cleanedName.isEmpty ? "Untitled Space" : cleanedName
        let profileID = profileID ?? activeProfile?.id ?? profiles[0].id
        let space = BrowserSpace(name: resolvedName, profileID: profileID)
        spaces.append(space)
        selectSpace(space.id)
        return space
    }

    @discardableResult
    public func createFolder(name: String, in spaceID: SpaceID? = nil) -> BrowserFolder? {
        guard let targetSpaceID = spaceID ?? selectedSpaceID else {
            return nil
        }

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = BrowserFolder(
            name: cleanedName.isEmpty ? "Untitled Folder" : cleanedName,
            parentSpaceID: targetSpaceID
        )
        folders.append(folder)
        updateSpace(targetSpaceID) { space in
            space.folderIDs.append(folder.id)
        }
        persistSession()
        return folder
    }

    @discardableResult
    public func createProfile(name: String, ephemeral: Bool = false) -> BrowserProfile {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ephemeral
            ? BrowserProfile.privateBrowsing()
            : BrowserProfile(name: cleanedName.isEmpty ? "Profile \(profiles.count + 1)" : cleanedName)
        profiles.append(profile)
        persistSession()
        return profile
    }

    @discardableResult
    public func createTab(
        title: String? = nil,
        url: URL? = nil,
        in spaceID: SpaceID? = nil,
        folderID: FolderID? = nil,
        pinned: Bool = false,
        favorite: Bool = false
    ) -> BrowserTab? {
        guard let targetSpaceID = spaceID ?? selectedSpaceID,
              let targetSpace = spaces.first(where: { $0.id == targetSpaceID }) else {
            return nil
        }

        let profileID = targetSpace.profileID
        let tab = BrowserTab(
            title: title ?? Self.defaultTitle(for: url),
            url: url,
            parentSpaceID: targetSpaceID,
            parentFolderID: folderID,
            isPinned: pinned,
            isFavorite: favorite,
            profileID: profileID,
            restorationMetadata: TabRestorationMetadata(lastCommittedURL: url)
        )
        tabs.append(tab)

        if let folderID {
            updateFolder(folderID) { folder in
                folder.tabIDs.append(tab.id)
            }
        } else {
            updateSpace(targetSpaceID) { space in
                if favorite {
                    space.favoriteTabIDs.append(tab.id)
                } else if pinned {
                    space.pinnedTabIDs.append(tab.id)
                } else {
                    space.regularTabIDs.append(tab.id)
                }
                space.selectedTabID = tab.id
            }
        }

        selectTab(tab.id)
        return tab
    }

    public func selectSpace(_ id: SpaceID) {
        guard let space = spaces.first(where: { $0.id == id }) else {
            return
        }
        selectedSpaceID = id
        selectedTabID = space.selectedTabID
            ?? space.favoriteTabIDs.first
            ?? space.pinnedTabIDs.first
            ?? space.regularTabIDs.first
        persistSession()
    }

    public func selectTab(_ id: TabID) {
        guard let tab = tabs.first(where: { $0.id == id }) else {
            return
        }
        selectedSpaceID = tab.parentSpaceID
        selectedTabID = id
        updateSpace(tab.parentSpaceID) { space in
            space.selectedTabID = id
            space.lastActiveDate = Date()
        }
        updateTab(id) { tab in
            tab.lastActiveDate = Date()
        }
        persistSession()
    }

    public func closeSelectedTab() {
        guard let tab = activeTab else {
            return
        }
        tabs.removeAll { $0.id == tab.id }
        updateSpace(tab.parentSpaceID) { space in
            space.favoriteTabIDs.removeAll { $0 == tab.id }
            space.pinnedTabIDs.removeAll { $0 == tab.id }
            space.regularTabIDs.removeAll { $0 == tab.id }
            if space.selectedTabID == tab.id {
                space.selectedTabID = space.favoriteTabIDs.first ?? space.pinnedTabIDs.first ?? space.regularTabIDs.first
            }
        }
        for index in folders.indices {
            folders[index].tabIDs.removeAll { $0 == tab.id }
        }
        selectedTabID = selectedSpace?.selectedTabID
        persistSession()
    }

    public func toggleSidebar() {
        sidebarIsVisible.toggle()
    }

    public func showCommandBar() {
        isCommandBarPresented = true
    }

    public func hideCommandBar() {
        isCommandBarPresented = false
    }

    public func submitCommandInput(_ input: String) {
        perform(commandRouter.route(input: input))
    }

    public func commandBarResults(
        for query: String,
        openTabLimit: Int = 5,
        historyLimit: Int = 5
    ) -> [CommandBarResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let tabResults = matchingOpenTabs(for: trimmed, limit: openTabLimit)
            .map(CommandBarResult.openTab)
        let matchedHistory = historyResults(for: trimmed, limit: historyLimit)
            .map(CommandBarResult.history)

        return tabResults + matchedHistory
    }

    public func activateCommandBarResult(_ result: CommandBarResult) {
        switch result {
        case .openTab(let tab):
            selectTab(tab.id)
        case .history(let entry):
            guard entry.profileID == activeProfile?.id else {
                lastUserMessage = "History result is unavailable for this profile."
                hideCommandBar()
                return
            }
            open(entry.url)
        }

        hideCommandBar()
    }

    public func perform(_ command: CommandRouter.Command) {
        switch command {
        case .openURL(let url):
            open(url)
        case .search(let url, _):
            open(url)
        case .createTab(let url):
            _ = createTab(url: url)
        case .createSpace(let name):
            _ = createSpace(name: name)
        case .createFolder(let name):
            _ = createFolder(name: name)
        case .switchSpace(let id):
            selectSpace(id)
        case .switchProfile(let id):
            switchToProfile(id)
        case .browserAction(.closeTab):
            closeSelectedTab()
        case .browserAction:
            lastUserMessage = "Action is not wired yet."
        case .noOp:
            break
        }
        hideCommandBar()
    }

    public func open(_ url: URL) {
        switch urlSecurityPolicy.decision(for: url) {
        case .allowInWebView:
            _ = createTab(url: url)
            publishStatusMessage(urlSecurityPolicy.securityMessage(forAllowedWebURL: url))
        case .requireExternalApplicationConfirmation:
            requestURLConfirmation(kind: .externalApplication, url: url)
        case .requireLocalFileConfirmation:
            requestURLConfirmation(kind: .localFile, url: url)
        case .block(let reason):
            lastUserMessage = reason
        }
    }

    public func historyResults(
        for query: String,
        profileID: ProfileID? = nil,
        limit: Int = 5
    ) -> [BrowserHistoryEntry] {
        guard let resolvedProfileID = profileID ?? activeProfile?.id else {
            return []
        }
        return localHistoryStore.query(query, profileID: resolvedProfileID, limit: limit)
    }

    @discardableResult
    public func recordHistoryVisit(
        title: String?,
        url: URL?,
        profileID: ProfileID? = nil,
        date: Date = Date()
    ) -> BrowserHistoryEntry? {
        guard let url,
              let resolvedProfileID = profileID ?? activeProfile?.id,
              let profile = profiles.first(where: { $0.id == resolvedProfileID }) else {
            return nil
        }

        let entry = localHistoryStore.recordVisit(
            url: url,
            title: title,
            profile: profile,
            visitedAt: date
        )
        historyEntries = localHistoryStore.entries
        return entry
    }

    @discardableResult
    public func requestSitePermission(
        kind: SitePermissionKind,
        origin: SitePermissionOrigin?,
        profileID: ProfileID? = nil,
        date: Date = Date()
    ) -> SitePermissionPolicy.Evaluation {
        guard let origin else {
            let reason = "Site permission request was blocked because its origin is unavailable."
            pendingSitePermissionRequest = nil
            lastUserMessage = reason
            return .deny(reason: reason)
        }

        let resolvedProfileID = profileID ?? activeProfile?.id
        guard let profile = profiles.first(where: { $0.id == resolvedProfileID }) else {
            let reason = "Site permission request was blocked because its profile is unavailable."
            pendingSitePermissionRequest = nil
            lastUserMessage = reason
            return .deny(reason: reason)
        }

        let request = SitePermissionRequest(
            kind: kind,
            origin: origin,
            profileID: profile.id,
            isEphemeralProfile: profile.isEphemeral,
            requestedAt: date
        )
        let evaluation = sitePermissionPolicy.evaluation(for: request, settings: sitePermissionSettings)

        switch evaluation {
        case .allow:
            pendingSitePermissionRequest = nil
            lastUserMessage = nil
        case .ask:
            pendingSitePermissionRequest = request
            lastUserMessage = request.promptMessage
        case .deny(let reason):
            pendingSitePermissionRequest = nil
            lastUserMessage = reason
        }

        return evaluation
    }

    @discardableResult
    public func resolvePendingSitePermission(
        _ decision: SitePermissionDecision,
        requestID: UUID,
        date: Date = Date()
    ) -> SitePermissionPolicy.Evaluation? {
        guard let request = pendingSitePermissionRequest,
              request.id == requestID else {
            return nil
        }

        if let setting = sitePermissionPolicy.setting(for: request, decision: decision, date: date) {
            upsertSitePermissionSetting(setting)
        }

        pendingSitePermissionRequest = nil
        let evaluation = sitePermissionPolicy.evaluation(for: decision, kind: request.kind)
        switch evaluation {
        case .allow:
            lastUserMessage = "\(request.kind.displayName.capitalized) allowed for \(request.origin.displayString)."
        case .ask:
            lastUserMessage = request.promptMessage
        case .deny(let reason):
            lastUserMessage = reason
        }
        return evaluation
    }

    public func cancelPendingSitePermissionRequest() {
        pendingSitePermissionRequest = nil
    }

    public func requestURLConfirmation(
        kind: URLConfirmationRequest.Kind,
        url: URL,
        sourceContext: URLConfirmationSourceContext = .commandBar,
        date: Date = Date()
    ) {
        pendingURLConfirmation = URLConfirmationRequest(
            kind: kind,
            url: url,
            sourceContext: sourceContext,
            createdAt: date
        )
        lastUserMessage = kind.pendingMessage
    }

    public func requestURLConfirmation(
        kind: URLConfirmationRequest.Kind,
        url: URL,
        sourceURL: URL?,
        date: Date = Date()
    ) {
        requestURLConfirmation(
            kind: kind,
            url: url,
            sourceContext: URLConfirmationSourceContext(sourceURL: sourceURL),
            date: date
        )
    }

    @discardableResult
    public func approvePendingURLConfirmation(open: (URL) -> Bool) -> Bool {
        guard let request = pendingURLConfirmation else {
            return false
        }

        guard urlSecurityPolicy.confirmationKind(for: request.url) == request.kind else {
            pendingURLConfirmation = nil
            lastUserMessage = "URL confirmation was rejected because the link no longer matches its security decision."
            return false
        }

        pendingURLConfirmation = nil
        let didOpen = open(request.url)
        lastUserMessage = didOpen ? request.kind.approvedMessage : "Unable to open confirmed link."
        return didOpen
    }

    public func cancelPendingURLConfirmation() {
        guard let request = pendingURLConfirmation else {
            return
        }

        pendingURLConfirmation = nil
        lastUserMessage = request.kind.cancelledMessage
    }

    public func requestDownloadConfirmation(
        _ request: DownloadConfirmationRequest,
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        cancelPendingDownloadCompletion(message: nil)

        switch request.risk {
        case .blocked(let reason):
            lastUserMessage = reason
            completion(nil)
        case .low, .requiresConfirmation:
            pendingDownloadConfirmation = request
            pendingDownloadCompletion = completion
            lastUserMessage = request.pendingMessage
        }
    }

    @discardableResult
    public func beginPendingDownloadDestinationSelection() -> Bool {
        guard pendingDownloadConfirmation != nil,
              pendingDownloadCompletion != nil else {
            isChoosingDownloadDestination = false
            return false
        }

        isChoosingDownloadDestination = true
        return true
    }

    public func dismissPendingDownloadConfirmationAlert() {
        guard pendingDownloadConfirmation != nil else {
            isChoosingDownloadDestination = false
            return
        }

        if isChoosingDownloadDestination {
            return
        }

        cancelPendingDownloadConfirmation()
    }

    @discardableResult
    public func approvePendingDownloadConfirmation(destination selectedURL: URL) -> Bool {
        guard let request = pendingDownloadConfirmation,
              let completion = pendingDownloadCompletion else {
            isChoosingDownloadDestination = false
            return false
        }

        guard let destinationURL = downloadSafetyPolicy.safeDestinationURL(for: selectedURL) else {
            cancelPendingDownloadCompletion(message: "Download destination is unavailable.")
            return false
        }

        let destinationRisk = downloadSafetyPolicy.risk(for: destinationURL.lastPathComponent)
        if case .blocked(let reason) = destinationRisk {
            cancelPendingDownloadCompletion(message: reason)
            return false
        }
        if case .low = request.risk,
           case .requiresConfirmation(let reason) = destinationRisk {
            cancelPendingDownloadCompletion(message: "Download destination requires confirmation. \(reason)")
            return false
        }

        pendingDownloadConfirmation = nil
        pendingDownloadCompletion = nil
        isChoosingDownloadDestination = false
        lastUserMessage = "Download will be saved as \(destinationURL.lastPathComponent)."
        completion(destinationURL)
        return true
    }

    public func cancelPendingDownloadConfirmation() {
        guard let request = pendingDownloadConfirmation else {
            isChoosingDownloadDestination = false
            return
        }

        cancelPendingDownloadCompletion(message: request.cancelledMessage)
    }

    public func updateActiveTabFromWebView(
        title: String?,
        url: URL?,
        isLoading: Bool,
        securityMessage: String? = nil
    ) {
        guard let selectedTabID else {
            return
        }
        var visitProfileID: ProfileID?
        var visitURL: URL?
        var visitTitle: String?
        updateTab(selectedTabID) { tab in
            if let title, !title.isEmpty {
                tab.title = title
            }
            tab.url = url ?? tab.url
            tab.isLoading = isLoading
            tab.restorationMetadata.lastCommittedURL = url ?? tab.restorationMetadata.lastCommittedURL
            visitProfileID = tab.profileID
            visitURL = tab.url
            visitTitle = tab.title
        }
        if !isLoading {
            recordHistoryVisit(title: visitTitle, url: visitURL, profileID: visitProfileID)
        }
        if let securityMessage {
            publishStatusMessage(securityMessage)
        } else if let statusURL = url ?? visitURL {
            publishStatusMessage(urlSecurityPolicy.securityMessage(forAllowedWebURL: statusURL))
        }
        persistSession()
    }

    public func publishStatusMessage(_ message: String?) {
        guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return
        }
        lastUserMessage = message
    }

    public func dismissLastUserMessage() {
        lastUserMessage = nil
    }

    private func switchToProfile(_ id: ProfileID) {
        guard profiles.contains(where: { $0.id == id }) else {
            return
        }
        if let space = spaces.first(where: { $0.profileID == id }) {
            selectSpace(space.id)
        } else {
            _ = createSpace(name: profiles.first(where: { $0.id == id })?.name ?? "Profile", profileID: id)
        }
    }

    private func updateSpace(_ id: SpaceID, mutate: (inout BrowserSpace) -> Void) {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&spaces[index])
    }

    private func updateFolder(_ id: FolderID, mutate: (inout BrowserFolder) -> Void) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&folders[index])
    }

    private func updateTab(_ id: TabID, mutate: (inout BrowserTab) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutate(&tabs[index])
    }

    private func matchingOpenTabs(for query: String, limit: Int) -> [BrowserTab] {
        guard limit > 0 else {
            return []
        }
        return Array(
            tabs
                .filter { tab in
                    tab.title.localizedCaseInsensitiveContains(query)
                        || (tab.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
                }
                .prefix(limit)
        )
    }

    private func upsertSitePermissionSetting(_ setting: SitePermissionSetting) {
        if let index = sitePermissionSettings.firstIndex(where: {
            $0.kind == setting.kind
                && $0.origin == setting.origin
                && $0.profileID == setting.profileID
        }) {
            sitePermissionSettings[index] = setting
        } else {
            sitePermissionSettings.append(setting)
        }
    }

    private func cancelPendingDownloadCompletion(message: String?) {
        let completion = pendingDownloadCompletion
        pendingDownloadConfirmation = nil
        pendingDownloadCompletion = nil
        isChoosingDownloadDestination = false
        if let message {
            lastUserMessage = message
        }
        completion?(nil)
    }

    private func persistSession(date: Date = Date()) {
        guard let sessionPersistence else {
            return
        }

        do {
            try sessionPersistence.saveSnapshot(
                snapshot(date: date),
                fallback: SessionSnapshotFactory.initial(date: date)
            )
        } catch {
            lastUserMessage = "Session changes could not be saved. Meridian will keep browsing state in memory for this run."
        }
    }

    private static func defaultTitle(for url: URL?) -> String {
        guard let url else {
            return "New Tab"
        }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }
}
