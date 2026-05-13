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
    private let localHistoryPersistence: LocalHistoryPersisting?
    private var localHistoryStore: LocalHistoryStore
    private var pendingDownloadCompletion: (@MainActor (URL?) -> Void)?

    public init(
        snapshot: BrowserSessionSnapshot = SessionSnapshotFactory.initial(),
        commandRouter: CommandRouter = CommandRouter(),
        urlSecurityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        sitePermissionSettings: [SitePermissionSetting]? = nil,
        localHistoryStore: LocalHistoryStore = LocalHistoryStore(),
        lastUserMessage: String? = nil,
        sessionPersistence: SessionSnapshotPersisting? = nil,
        localHistoryPersistence: LocalHistoryPersisting? = nil
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
        self.sitePermissionSettings = sitePermissionSettings ?? snapshot.sitePermissionSettings
        self.historyEntries = localHistoryStore.entries
        self.commandRouter = commandRouter
        self.urlSecurityPolicy = urlSecurityPolicy
        self.downloadSafetyPolicy = downloadSafetyPolicy
        self.sitePermissionPolicy = sitePermissionPolicy
        self.sessionPersistence = sessionPersistence
        self.localHistoryPersistence = localHistoryPersistence
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

    public var persistentProfiles: [BrowserProfile] {
        profiles.filter { !$0.isEphemeral }
    }

    public var activeProfileSpaces: [BrowserSpace] {
        guard let activeProfileID = activeProfile?.id else {
            return []
        }
        return spaces.filter { $0.profileID == activeProfileID }
    }

    public var suggestedPersistentProfileName: String {
        "Profile \(persistentProfiles.count + 1)"
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
            capturedAt: date,
            sitePermissionSettings: sitePermissionSettings
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
    public func createPersistentProfile(name: String) -> BrowserProfile {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = BrowserProfile(name: cleanedName.isEmpty ? suggestedPersistentProfileName : cleanedName)
        profiles.append(profile)
        selectProfileContext(profile, date: Date())
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
        favorite: Bool = false,
        pendingHTTPFallbackURL: URL? = nil
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
            restorationMetadata: TabRestorationMetadata(
                lastCommittedURL: url,
                pendingHTTPFallbackURL: pendingHTTPFallbackURL
            )
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
        refreshActivePageSecurityStatus()
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
        refreshActivePageSecurityStatus()
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
        refreshActivePageSecurityStatus()
        persistSession()
    }

    @discardableResult
    public func setTabPlacement(_ placement: BrowserTabPlacement, for tabID: TabID) -> Bool {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }

        let tab = tabs[tabIndex]
        let wasTopLevelRegular = !tab.isPinned && !tab.isFavorite && tab.parentFolderID == nil
        let wasAlreadyPlaced: Bool
        switch placement {
        case .regular:
            wasAlreadyPlaced = wasTopLevelRegular
        case .pinned:
            wasAlreadyPlaced = tab.isPinned && !tab.isFavorite && tab.parentFolderID == nil
        case .favorite:
            wasAlreadyPlaced = tab.isFavorite && !tab.isPinned && tab.parentFolderID == nil
        }

        if wasAlreadyPlaced {
            return false
        }

        updateTab(tabID) { tab in
            tab.parentFolderID = nil
            tab.isPinned = placement == .pinned
            tab.isFavorite = placement == .favorite
        }

        updateSpace(tab.parentSpaceID) { space in
            space.favoriteTabIDs.removeAll { $0 == tabID }
            space.pinnedTabIDs.removeAll { $0 == tabID }
            space.regularTabIDs.removeAll { $0 == tabID }

            switch placement {
            case .regular:
                space.regularTabIDs.append(tabID)
            case .pinned:
                space.pinnedTabIDs.append(tabID)
            case .favorite:
                space.favoriteTabIDs.append(tabID)
            }
        }

        for index in folders.indices {
            folders[index].tabIDs.removeAll { $0 == tabID }
        }

        persistSession()
        return true
    }

    public func canMoveSelectedTab(_ direction: BrowserTabReorderDirection) -> Bool {
        guard let selectedTabID else {
            return false
        }
        return canMoveTab(selectedTabID, direction)
    }

    public func canMoveTab(_ tabID: TabID, _ direction: BrowserTabReorderDirection) -> Bool {
        guard let position = tabReorderPosition(for: tabID) else {
            return false
        }
        return position.canMove(direction)
    }

    @discardableResult
    public func moveSelectedTab(_ direction: BrowserTabReorderDirection) -> Bool {
        guard let selectedTabID else {
            return false
        }
        return moveTab(selectedTabID, direction)
    }

    @discardableResult
    public func moveTab(_ tabID: TabID, _ direction: BrowserTabReorderDirection) -> Bool {
        guard let position = tabReorderPosition(for: tabID),
              position.canMove(direction) else {
            return false
        }

        var didMove = false
        switch position.container {
        case .favorites(let spaceID):
            updateSpace(spaceID) { space in
                didMove = Self.moveTabID(tabID, direction, in: &space.favoriteTabIDs)
            }
        case .pinned(let spaceID):
            updateSpace(spaceID) { space in
                didMove = Self.moveTabID(tabID, direction, in: &space.pinnedTabIDs)
            }
        case .regular(let spaceID):
            updateSpace(spaceID) { space in
                didMove = Self.moveTabID(tabID, direction, in: &space.regularTabIDs)
            }
        case .folder(let folderID):
            updateFolder(folderID) { folder in
                didMove = Self.moveTabID(tabID, direction, in: &folder.tabIDs)
            }
        }

        if didMove {
            persistSession()
        }
        return didMove
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

    public func submitCommandInput(
        _ input: String,
        browserActionHandler: ((CommandRouter.BrowserAction) -> Bool)? = nil
    ) {
        perform(commandRouter.route(input: input), browserActionHandler: browserActionHandler)
    }

    public func commandBarResults(
        for query: String,
        openTabLimit: Int = 5,
        profileLimit: Int = 5,
        historyLimit: Int = 5,
        browserActionAvailability: CommandRouter.BrowserActionAvailability? = nil
    ) -> [CommandBarResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let actionResults = browserActionAvailability.map { availability in
            commandRouter.browserActionSuggestions(for: trimmed, availability: availability)
                .map(CommandBarResult.browserAction)
        } ?? []
        let profileResults = matchingProfiles(for: trimmed, limit: profileLimit)
            .map(CommandBarResult.profile)
        let tabResults = matchingOpenTabs(for: trimmed, limit: openTabLimit)
            .map(CommandBarResult.openTab)
        let matchedHistory = historyResults(for: trimmed, limit: historyLimit)
            .map(CommandBarResult.history)

        return actionResults + profileResults + tabResults + matchedHistory
    }

    public func activateCommandBarResult(
        _ result: CommandBarResult,
        browserActionHandler: ((CommandRouter.BrowserAction) -> Bool)? = nil
    ) {
        switch result {
        case .browserAction(let action):
            perform(.browserAction(action.action), browserActionHandler: browserActionHandler)
            return
        case .profile(let profile):
            _ = switchProfile(profile.id)
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

    public func perform(
        _ command: CommandRouter.Command,
        browserActionHandler: ((CommandRouter.BrowserAction) -> Bool)? = nil
    ) {
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
        case .createProfile(let name):
            _ = createPersistentProfile(name: name)
        case .switchSpace(let id):
            selectSpace(id)
        case .switchProfile(let id):
            _ = switchProfile(id)
        case .browserAction(let action):
            if !performBrowserAction(action, handler: browserActionHandler) {
                lastUserMessage = Self.unavailableMessage(for: action)
            }
        case .noOp:
            break
        }
        hideCommandBar()
    }

    public func open(_ url: URL) {
        switch urlSecurityPolicy.decision(for: url) {
        case .allowInWebView:
            let upgradeCandidate = urlSecurityPolicy.httpsUpgradeCandidate(for: url)
            let pendingFallbackURL = upgradeCandidate == nil ? nil : url
            let navigationURL = upgradeCandidate ?? url
            _ = createTab(url: navigationURL, pendingHTTPFallbackURL: pendingFallbackURL)
            updatePageSecurityStatus(for: navigationURL)
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
        if entry != nil {
            persistHistory()
        }
        return entry
    }

    @discardableResult
    public func clearHistoryForActiveProfile() -> Int {
        guard let profileID = activeProfile?.id else {
            return 0
        }

        let removedEntries = localHistoryStore.clearEntries(profileID: profileID)
        historyEntries = localHistoryStore.entries
        if !removedEntries.isEmpty {
            persistHistory()
            lastUserMessage = "History cleared for this profile."
        } else {
            lastUserMessage = "No history to clear for this profile."
        }
        return removedEntries.count
    }

    @discardableResult
    public func deleteHistoryEntry(_ id: UUID, profileID: ProfileID? = nil) -> Bool {
        let resolvedProfileID = profileID ?? activeProfile?.id
        guard localHistoryStore.deleteEntry(id: id, profileID: resolvedProfileID) != nil else {
            return false
        }

        historyEntries = localHistoryStore.entries
        persistHistory()
        lastUserMessage = "History entry deleted."
        return true
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

        let shouldPersist: Bool
        if let setting = sitePermissionPolicy.setting(for: request, decision: decision, date: date) {
            upsertSitePermissionSetting(setting)
            shouldPersist = true
        } else {
            shouldPersist = false
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
        if shouldPersist {
            persistSession(date: date)
        }
        return evaluation
    }

    public func cancelPendingSitePermissionRequest() {
        pendingSitePermissionRequest = nil
    }

    public func sitePermissionDecision(
        for kind: SitePermissionKind,
        origin: SitePermissionOrigin?,
        profileID: ProfileID? = nil
    ) -> SitePermissionDecision? {
        guard let origin,
              let resolvedProfileID = profileID ?? activeProfile?.id else {
            return nil
        }

        if let setting = sitePermissionSettings.last(where: {
            $0.kind == kind
                && $0.origin == origin
                && $0.profileID == resolvedProfileID
        }) {
            return setting.decision
        }

        return sitePermissionPolicy.defaultDecision(for: kind)
    }

    @discardableResult
    public func setSitePermissionDecision(
        _ decision: SitePermissionDecision,
        for kind: SitePermissionKind,
        origin: SitePermissionOrigin?,
        profileID: ProfileID? = nil,
        date: Date = Date()
    ) -> Bool {
        guard let origin else {
            lastUserMessage = "Site permission setting was not changed because the site is unavailable."
            return false
        }

        let resolvedProfileID = profileID ?? activeProfile?.id
        guard let profile = profiles.first(where: { $0.id == resolvedProfileID }) else {
            lastUserMessage = "Site permission setting was not changed because its profile is unavailable."
            return false
        }

        guard sitePermissionPolicy.supportsStoredUserDecision(for: kind) else {
            switch sitePermissionPolicy.support(for: kind) {
            case .webKitConfiguration:
                lastUserMessage = "\(kind.displayTitle) is controlled by browser configuration and cannot be changed per site."
            case .unsupported:
                if case .deny(let reason) = sitePermissionPolicy.evaluation(for: .allow, kind: kind) {
                    lastUserMessage = reason
                } else {
                    lastUserMessage = "\(kind.displayTitle) is not supported by this WebKit version."
                }
            case .webKitPermissionDelegate, .webKitUIDelegate:
                break
            }
            return false
        }

        if decision == .ask {
            let didRemove = removeSitePermissionSetting(kind: kind, origin: origin, profileID: profile.id)
            lastUserMessage = sitePermissionStatusMessage(
                for: decision,
                kind: kind,
                origin: origin,
                isEphemeralProfile: profile.isEphemeral
            )
            if didRemove {
                persistSession(date: date)
            }
            return true
        }

        let request = SitePermissionRequest(
            kind: kind,
            origin: origin,
            profileID: profile.id,
            isEphemeralProfile: profile.isEphemeral,
            requestedAt: date
        )
        guard let setting = sitePermissionPolicy.setting(for: request, decision: decision, date: date) else {
            return false
        }

        upsertSitePermissionSetting(setting)
        lastUserMessage = sitePermissionStatusMessage(
            for: decision,
            kind: kind,
            origin: origin,
            isEphemeralProfile: profile.isEphemeral
        )
        persistSession(date: date)
        return true
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
            if let updatedURL = url {
                updateHTTPSUpgradeFallbackMetadata(for: &tab, committedURL: updatedURL)
            }
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
            updatePageSecurityStatus(for: statusURL)
        } else {
            clearCurrentPageSecurityStatus()
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

    @discardableResult
    public func switchProfile(_ id: ProfileID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return false
        }

        selectProfileContext(profile, date: Date())
        persistSession()
        return true
    }

    private func selectProfileContext(_ profile: BrowserProfile, date: Date) {
        if let existingSpace = spaces
            .filter({ $0.profileID == profile.id })
            .max(by: { $0.lastActiveDate < $1.lastActiveDate }) {
            selectedSpaceID = existingSpace.id
            if let tabID = selectedTabID(in: existingSpace) {
                selectedTabID = tabID
                updateSpace(existingSpace.id) { space in
                    space.selectedTabID = tabID
                    space.lastActiveDate = date
                }
                updateTab(tabID) { tab in
                    tab.lastActiveDate = date
                }
            } else {
                createStartTab(in: existingSpace.id, profileID: profile.id, date: date)
            }
        } else {
            createDefaultSpaceAndTab(for: profile, date: date)
        }
        refreshActivePageSecurityStatus()
    }

    private func selectedTabID(in space: BrowserSpace) -> TabID? {
        let candidateIDs = ([space.selectedTabID].compactMap { $0 })
            + space.favoriteTabIDs
            + space.pinnedTabIDs
            + space.regularTabIDs

        return candidateIDs.first { candidateID in
            tabs.contains { tab in
                tab.id == candidateID
                    && tab.parentSpaceID == space.id
                    && tab.profileID == space.profileID
            }
        }
    }

    private func createDefaultSpaceAndTab(for profile: BrowserProfile, date: Date) {
        var space = BrowserSpace(
            name: profile.isEphemeral ? "Private" : profile.name,
            profileID: profile.id,
            lastActiveDate: date
        )
        let tab = BrowserTab(
            title: "Start Page",
            parentSpaceID: space.id,
            profileID: profile.id,
            lastActiveDate: date
        )
        space.regularTabIDs = [tab.id]
        space.selectedTabID = tab.id

        spaces.append(space)
        tabs.append(tab)
        selectedSpaceID = space.id
        selectedTabID = tab.id
    }

    private func createStartTab(in spaceID: SpaceID, profileID: ProfileID, date: Date) {
        let tab = BrowserTab(
            title: "Start Page",
            parentSpaceID: spaceID,
            profileID: profileID,
            lastActiveDate: date
        )
        tabs.append(tab)
        selectedTabID = tab.id
        updateSpace(spaceID) { space in
            space.regularTabIDs.append(tab.id)
            space.selectedTabID = tab.id
            space.lastActiveDate = date
        }
    }

    private func performBrowserAction(
        _ action: CommandRouter.BrowserAction,
        handler: ((CommandRouter.BrowserAction) -> Bool)?
    ) -> Bool {
        switch action {
        case .closeTab:
            guard activeTab != nil else {
                return false
            }
            closeSelectedTab()
            return true
        case .pinTab:
            guard let activeTab else {
                return false
            }
            return setTabPlacement(.pinned, for: activeTab.id)
        case .addTabToEssentials:
            guard let activeTab else {
                return false
            }
            return setTabPlacement(.favorite, for: activeTab.id)
        case .moveTabToRegular:
            guard let activeTab else {
                return false
            }
            return setTabPlacement(.regular, for: activeTab.id)
        case .moveTabUp:
            return moveSelectedTab(.up)
        case .moveTabDown:
            return moveSelectedTab(.down)
        case .splitActiveTab:
            return false
        case .reload, .stopLoading, .goBack, .goForward:
            return handler?(action) ?? false
        }
    }

    private static func unavailableMessage(for action: CommandRouter.BrowserAction) -> String {
        switch action {
        case .reload:
            return "Reload is unavailable because no page is active."
        case .stopLoading:
            return "Stop is unavailable because the page is not loading."
        case .goBack:
            return "Back is unavailable for the current page."
        case .goForward:
            return "Forward is unavailable for the current page."
        case .closeTab:
            return "No tab is selected."
        case .pinTab:
            return "Tab cannot be pinned right now."
        case .addTabToEssentials:
            return "Tab cannot be added to Essentials right now."
        case .moveTabToRegular:
            return "Tab is already in Tabs."
        case .moveTabUp:
            return "Tab cannot move up in its current section."
        case .moveTabDown:
            return "Tab cannot move down in its current section."
        case .splitActiveTab:
            return "Split view is not available yet."
        }
    }

    private func refreshActivePageSecurityStatus() {
        updatePageSecurityStatus(for: activeTab?.url)
    }

    private func updatePageSecurityStatus(for url: URL?) {
        guard let url else {
            clearCurrentPageSecurityStatus()
            return
        }

        if let message = urlSecurityPolicy.securityMessage(forAllowedWebURL: url) {
            lastUserMessage = message
        } else {
            clearCurrentPageSecurityStatus()
        }
    }

    private func clearCurrentPageSecurityStatus() {
        if lastUserMessage == URLSecurityPolicy.insecureTransportMessage {
            lastUserMessage = nil
        }
    }

    private func updateHTTPSUpgradeFallbackMetadata(for tab: inout BrowserTab, committedURL: URL) {
        guard let fallbackURL = tab.restorationMetadata.pendingHTTPFallbackURL else {
            return
        }

        if committedURL == fallbackURL
            || urlSecurityPolicy.isHTTPSUpgradeCandidate(committedURL, for: fallbackURL) {
            tab.restorationMetadata.pendingHTTPFallbackURL = nil
        }
    }

    private enum TabReorderContainer {
        case favorites(SpaceID)
        case pinned(SpaceID)
        case regular(SpaceID)
        case folder(FolderID)
    }

    private struct TabReorderPosition {
        var container: TabReorderContainer
        var index: Int
        var count: Int

        func canMove(_ direction: BrowserTabReorderDirection) -> Bool {
            switch direction {
            case .up:
                return index > 0
            case .down:
                return index < count - 1
            }
        }
    }

    private func tabReorderPosition(for tabID: TabID) -> TabReorderPosition? {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            return nil
        }

        if let folderID = tab.parentFolderID {
            guard let folder = folders.first(where: { $0.id == folderID }),
                  folder.parentSpaceID == tab.parentSpaceID,
                  let index = folder.tabIDs.firstIndex(of: tabID) else {
                return nil
            }
            return TabReorderPosition(container: .folder(folderID), index: index, count: folder.tabIDs.count)
        }

        guard let space = spaces.first(where: { $0.id == tab.parentSpaceID }) else {
            return nil
        }

        if tab.isFavorite {
            guard let index = space.favoriteTabIDs.firstIndex(of: tabID) else {
                return nil
            }
            return TabReorderPosition(container: .favorites(space.id), index: index, count: space.favoriteTabIDs.count)
        }

        if tab.isPinned {
            guard let index = space.pinnedTabIDs.firstIndex(of: tabID) else {
                return nil
            }
            return TabReorderPosition(container: .pinned(space.id), index: index, count: space.pinnedTabIDs.count)
        }

        guard let index = space.regularTabIDs.firstIndex(of: tabID) else {
            return nil
        }
        return TabReorderPosition(container: .regular(space.id), index: index, count: space.regularTabIDs.count)
    }

    private static func moveTabID(
        _ tabID: TabID,
        _ direction: BrowserTabReorderDirection,
        in tabIDs: inout [TabID]
    ) -> Bool {
        guard let index = tabIDs.firstIndex(of: tabID) else {
            return false
        }

        let targetIndex: Int
        switch direction {
        case .up:
            targetIndex = index - 1
        case .down:
            targetIndex = index + 1
        }

        guard tabIDs.indices.contains(targetIndex) else {
            return false
        }

        tabIDs.swapAt(index, targetIndex)
        return true
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
        guard limit > 0,
              let activeProfileID = activeProfile?.id else {
            return []
        }
        return Array(
            tabs
                .filter { tab in
                    tab.profileID == activeProfileID
                        && (
                            tab.title.localizedCaseInsensitiveContains(query)
                                || (tab.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
                        )
                }
                .prefix(limit)
        )
    }

    private func matchingProfiles(for query: String, limit: Int) -> [BrowserProfile] {
        guard limit > 0 else {
            return []
        }
        return Array(
            persistentProfiles
                .filter { profile in
                    profile.name.localizedCaseInsensitiveContains(query)
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

    @discardableResult
    private func removeSitePermissionSetting(
        kind: SitePermissionKind,
        origin: SitePermissionOrigin,
        profileID: ProfileID
    ) -> Bool {
        let originalCount = sitePermissionSettings.count
        sitePermissionSettings.removeAll {
            $0.kind == kind
                && $0.origin == origin
                && $0.profileID == profileID
        }
        return sitePermissionSettings.count != originalCount
    }

    private func sitePermissionStatusMessage(
        for decision: SitePermissionDecision,
        kind: SitePermissionKind,
        origin: SitePermissionOrigin,
        isEphemeralProfile: Bool
    ) -> String {
        let scope = isEphemeralProfile ? " for this private session" : ""
        switch decision {
        case .allow:
            return "\(kind.displayTitle) allowed for \(origin.displayString)\(scope)."
        case .deny:
            return "\(kind.displayTitle) blocked for \(origin.displayString)\(scope)."
        case .ask:
            return "\(kind.displayTitle) will ask for \(origin.displayString)\(scope)."
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

    private func persistHistory() {
        guard let localHistoryPersistence else {
            return
        }

        do {
            try localHistoryPersistence.saveHistory(localHistoryStore.entries, profiles: profiles)
        } catch {
            lastUserMessage = "History changes could not be saved. Meridian will keep history in memory for this run."
        }
    }

    private static func defaultTitle(for url: URL?) -> String {
        guard let url else {
            return "New Tab"
        }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }
}
