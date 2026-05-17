import Combine
import Foundation

public enum SidebarRevealEdge: String, CaseIterable, Identifiable, Sendable {
    case left
    case right

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .left:
            return "Left Edge"
        case .right:
            return "Right Edge"
        }
    }
}

public enum CommandBarMode: Equatable, Sendable {
    case address
    case newTab
}

public enum SpaceNavigationDirection: Equatable, Sendable {
    case previous
    case next
}

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
    @Published public private(set) var commandBarMode: CommandBarMode
    @Published public private(set) var commandBarFocusRequest: Int
    @Published public var sidebarIsVisible: Bool
    @Published public var sidebarIsLockedOpen: Bool
    @Published public var sidebarRevealEdge: SidebarRevealEdge
    @Published public var pendingURLConfirmation: URLConfirmationRequest?
    @Published public var pendingDownloadConfirmation: DownloadConfirmationRequest?
    @Published public private(set) var isChoosingDownloadDestination: Bool
    @Published public var lastUserMessage: String?
    @Published public private(set) var pendingSitePermissionRequest: SitePermissionRequest?
    @Published public private(set) var sitePermissionSettings: [SitePermissionSetting]
    @Published public private(set) var historyEntries: [BrowserHistoryEntry]
    @Published public private(set) var downloads: [BrowserDownload]

    public let commandRouter: CommandRouter
    public let urlSecurityPolicy: URLSecurityPolicy
    public let downloadSafetyPolicy: DownloadSafetyPolicy
    public let sitePermissionPolicy: SitePermissionPolicy
    private let sessionPersistence: SessionSnapshotPersisting?
    private let localHistoryPersistence: LocalHistoryPersisting?
    private var localHistoryStore: LocalHistoryStore
    private var pendingDownloadCompletion: (@MainActor (URL?) -> Void)?
    private var downloadCancellationHandlers: [UUID: @MainActor () -> Void]
    private var scheduledSessionPersistenceTask: Task<Void, Never>?

    public init(
        snapshot: BrowserSessionSnapshot = SessionSnapshotFactory.initial(),
        commandRouter: CommandRouter = CommandRouter(),
        urlSecurityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        sitePermissionSettings: [SitePermissionSetting]? = nil,
        localHistoryStore: LocalHistoryStore = LocalHistoryStore(),
        sidebarRevealEdge: SidebarRevealEdge = .left,
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
        self.commandBarMode = .address
        self.commandBarFocusRequest = 0
        self.sidebarIsVisible = true
        self.sidebarIsLockedOpen = true
        self.sidebarRevealEdge = sidebarRevealEdge
        self.pendingURLConfirmation = nil
        self.pendingDownloadConfirmation = nil
        self.isChoosingDownloadDestination = false
        self.lastUserMessage = lastUserMessage
        self.pendingSitePermissionRequest = nil
        self.sitePermissionSettings = sitePermissionSettings ?? snapshot.sitePermissionSettings
        self.historyEntries = localHistoryStore.entries
        self.downloads = []
        self.commandRouter = commandRouter
        self.urlSecurityPolicy = urlSecurityPolicy
        self.downloadSafetyPolicy = downloadSafetyPolicy
        self.sitePermissionPolicy = sitePermissionPolicy
        self.sessionPersistence = sessionPersistence
        self.localHistoryPersistence = localHistoryPersistence
        self.localHistoryStore = localHistoryStore
        self.pendingDownloadCompletion = nil
        self.downloadCancellationHandlers = [:]

        let didNormalizeLegacySpaceSymbols = normalizeLegacySpaceSymbols()
        let didPruneStaleEmptyTabs = pruneStaleEmptyTabsFromLoadedSession()
        if didNormalizeLegacySpaceSymbols || didPruneStaleEmptyTabs {
            persistSession()
        }
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

    public var sidebarSpaces: [BrowserSpace] {
        let persistentProfileIDs = Set(persistentProfiles.map(\.id))
        return spaces.filter { persistentProfileIDs.contains($0.profileID) }
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
        let profileID = profileID ?? defaultSpaceProfileID
        let space = BrowserSpace(name: resolvedName, profileID: profileID)
        spaces.append(space)
        selectSpace(space.id)
        persistSession()
        return space
    }

    @discardableResult
    public func customizeSpace(
        _ id: SpaceID,
        name: String,
        symbolName: String,
        colorHex: String,
        profileID: ProfileID? = nil,
        sidebarAppearance: SidebarAppearance? = nil,
        persistImmediately: Bool = true
    ) -> Bool {
        guard spaces.contains(where: { $0.id == id }) else {
            return false
        }
        if let profileID,
           !persistentProfiles.contains(where: { $0.id == profileID }) {
            return false
        }

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = cleanedName.isEmpty ? "Untitled Space" : cleanedName
        let resolvedSymbolName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BrowserSpace.defaultSymbolName
            : symbolName

        updateSpace(id) { space in
            space.name = resolvedName
            space.symbolName = resolvedSymbolName
            space.colorHex = colorHex
            if let sidebarAppearance {
                space.sidebarAppearance = sidebarAppearance
            }
            if let profileID {
                space.profileID = profileID
            }
        }
        if let profileID {
            updateTabs(inSpace: id, profileID: profileID)
            refreshActivePageSecurityStatus()
        }
        if persistImmediately {
            persistSession()
        } else {
            schedulePersistSession()
        }
        return true
    }

    @discardableResult
    public func setProfile(_ profileID: ProfileID, forSpace spaceID: SpaceID) -> Bool {
        guard persistentProfiles.contains(where: { $0.id == profileID }),
              spaces.contains(where: { $0.id == spaceID }) else {
            return false
        }

        updateSpace(spaceID) { space in
            space.profileID = profileID
        }
        updateTabs(inSpace: spaceID, profileID: profileID)
        refreshActivePageSecurityStatus()
        persistSession()
        return true
    }

    public func canDeleteSpace(_ id: SpaceID) -> Bool {
        guard let space = spaces.first(where: { $0.id == id }) else {
            return false
        }
        if persistentProfiles.contains(where: { $0.id == space.profileID }) {
            return sidebarSpaces.count > 1
        }
        return true
    }

    @discardableResult
    public func deleteSpace(_ id: SpaceID, date: Date = Date()) -> Bool {
        guard spaces.contains(where: { $0.id == id }),
              canDeleteSpace(id) else {
            return false
        }

        let deletedTabIDs = Set(tabs.filter { $0.parentSpaceID == id }.map(\.id))
        let deletedFolderIDs = Set(folders.filter { $0.parentSpaceID == id }.map(\.id))

        spaces.removeAll { $0.id == id }
        tabs.removeAll { deletedTabIDs.contains($0.id) }
        folders.removeAll { deletedFolderIDs.contains($0.id) }
        splitViews.removeAll { splitView in
            splitView.tabIDs.contains { deletedTabIDs.contains($0) }
        }

        for index in spaces.indices {
            spaces[index].favoriteTabIDs.removeAll { deletedTabIDs.contains($0) }
            spaces[index].pinnedTabIDs.removeAll { deletedTabIDs.contains($0) }
            spaces[index].regularTabIDs.removeAll { deletedTabIDs.contains($0) }
            spaces[index].folderIDs.removeAll { deletedFolderIDs.contains($0) }
            if let selectedTabID = spaces[index].selectedTabID,
               deletedTabIDs.contains(selectedTabID) {
                spaces[index].selectedTabID = self.selectedTabID(in: spaces[index])
            }
        }

        if selectedSpaceID == id {
            selectReplacementSpace(date: date)
        } else if let selectedTabID,
                  deletedTabIDs.contains(selectedTabID) {
            self.selectedTabID = selectedSpace.flatMap { self.selectedTabID(in: $0) }
        }

        refreshActivePageSecurityStatus()
        persistSession(date: date)
        return true
    }

    @discardableResult
    public func createFolder(
        name: String,
        in spaceID: SpaceID? = nil,
        parentFolderID: FolderID? = nil
    ) -> BrowserFolder? {
        let parentFolder = parentFolderID.flatMap { parentID in
            folders.first { $0.id == parentID }
        }
        guard parentFolderID == nil || parentFolder != nil else {
            return nil
        }

        let targetSpaceID = parentFolder?.parentSpaceID ?? spaceID ?? selectedSpaceID
        guard let targetSpaceID else {
            return nil
        }

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = BrowserFolder(
            name: cleanedName.isEmpty ? "Untitled Folder" : cleanedName,
            parentSpaceID: targetSpaceID,
            parentFolderID: parentFolderID
        )
        folders.append(folder)
        if let parentFolderID {
            updateFolder(parentFolderID) { parent in
                parent.childFolderIDs.append(folder.id)
            }
        } else {
            updateSpace(targetSpaceID) { space in
                space.folderIDs.append(folder.id)
            }
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
        content: BrowserTabContent = .web,
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
            content: content,
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

    @discardableResult
    public func openSpaceCustomizer(for spaceID: SpaceID? = nil) -> BrowserTab? {
        guard let targetSpaceID = spaceID ?? selectedSpaceID,
              spaces.contains(where: { $0.id == targetSpaceID }) else {
            return nil
        }

        if let existingTab = tabs.first(where: { tab in
            guard tab.parentSpaceID == targetSpaceID else {
                return false
            }
            if case .spaceCustomization(let customizedSpaceID) = tab.content {
                return customizedSpaceID == targetSpaceID
            }
            return false
        }) {
            selectTab(existingTab.id)
            return existingTab
        }

        return createTab(
            title: "Customize Space",
            in: targetSpaceID,
            content: .spaceCustomization(targetSpaceID)
        )
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
        schedulePersistSession()
    }

    @discardableResult
    public func selectAdjacentSpace(_ direction: SpaceNavigationDirection) -> Bool {
        let spaces = sidebarSpaces
        guard let selectedSpaceID,
              let selectedIndex = spaces.firstIndex(where: { $0.id == selectedSpaceID }) else {
            return false
        }

        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = selectedIndex - 1
        case .next:
            targetIndex = selectedIndex + 1
        }

        guard spaces.indices.contains(targetIndex) else {
            return false
        }

        selectSpace(spaces[targetIndex].id)
        return true
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
        guard let selectedTabID else {
            return
        }
        _ = closeTab(selectedTabID)
    }

    @discardableResult
    public func closeTab(_ tabID: TabID) -> Bool {
        guard let tab = tabs.first(where: { $0.id == tabID }) else {
            return false
        }
        let wasSelected = selectedTabID == tabID

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
        if wasSelected {
            selectedTabID = selectedSpace?.selectedTabID
        }
        refreshActivePageSecurityStatus()
        persistSession()
        return true
    }

    @discardableResult
    public func moveTab(_ tabID: TabID, to placement: BrowserTabPlacement, before targetTabID: TabID? = nil) -> Bool {
        guard tabID != targetTabID,
              let targetSpaceID = selectedSpaceID,
              let targetSpace = spaces.first(where: { $0.id == targetSpaceID }),
              tabs.contains(where: { $0.id == tabID }) else {
            return false
        }

        updateTab(tabID) { tab in
            tab.parentSpaceID = targetSpaceID
            tab.parentFolderID = nil
            tab.profileID = targetSpace.profileID
            tab.isPinned = placement == .pinned
            tab.isFavorite = placement == .favorite
        }

        for index in spaces.indices {
            spaces[index].favoriteTabIDs.removeAll { $0 == tabID }
            spaces[index].pinnedTabIDs.removeAll { $0 == tabID }
            spaces[index].regularTabIDs.removeAll { $0 == tabID }
        }

        for index in folders.indices {
            folders[index].tabIDs.removeAll { $0 == tabID }
        }

        updateSpace(targetSpaceID) { space in
            var tabIDs: [TabID]
            switch placement {
            case .regular:
                tabIDs = space.regularTabIDs
            case .pinned:
                tabIDs = space.pinnedTabIDs
            case .favorite:
                tabIDs = space.favoriteTabIDs
            }

            let insertionIndex = targetTabID.flatMap { tabIDs.firstIndex(of: $0) } ?? tabIDs.endIndex
            tabIDs.insert(tabID, at: insertionIndex)

            switch placement {
            case .regular:
                space.regularTabIDs = tabIDs
            case .pinned:
                space.pinnedTabIDs = tabIDs
            case .favorite:
                space.favoriteTabIDs = tabIDs
            }

            if space.selectedTabID == nil {
                space.selectedTabID = tabID
            }
        }

        if selectedTabID == nil {
            selectedTabID = tabID
        }
        persistSession()
        return true
    }

    @discardableResult
    public func moveTab(_ tabID: TabID, toFolder folderID: FolderID, before targetTabID: TabID? = nil) -> Bool {
        guard tabID != targetTabID,
              let folder = folders.first(where: { $0.id == folderID }),
              let targetSpace = spaces.first(where: { $0.id == folder.parentSpaceID }),
              tabs.contains(where: { $0.id == tabID }) else {
            return false
        }

        if let targetTabID,
           !folder.tabIDs.contains(targetTabID) {
            return false
        }

        updateTab(tabID) { tab in
            tab.parentSpaceID = folder.parentSpaceID
            tab.parentFolderID = folderID
            tab.profileID = targetSpace.profileID
            tab.isPinned = false
            tab.isFavorite = false
        }

        for index in spaces.indices {
            spaces[index].favoriteTabIDs.removeAll { $0 == tabID }
            spaces[index].pinnedTabIDs.removeAll { $0 == tabID }
            spaces[index].regularTabIDs.removeAll { $0 == tabID }
        }

        for index in folders.indices {
            folders[index].tabIDs.removeAll { $0 == tabID }
        }

        updateFolder(folderID) { folder in
            let insertionIndex = targetTabID.flatMap { folder.tabIDs.firstIndex(of: $0) } ?? folder.tabIDs.endIndex
            folder.tabIDs.insert(tabID, at: insertionIndex)
        }

        updateSpace(targetSpace.id) { space in
            if space.selectedTabID == nil {
                space.selectedTabID = tabID
            }
        }

        if selectedTabID == nil {
            selectedTabID = tabID
        }
        persistSession()
        return true
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
        toggleSidebarLock()
    }

    public func toggleSidebarLock() {
        if sidebarIsLockedOpen {
            sidebarIsLockedOpen = false
            sidebarIsVisible = true
        } else {
            sidebarIsLockedOpen = true
            sidebarIsVisible = true
        }
    }

    public func revealSidebar() {
        if !sidebarIsLockedOpen {
            sidebarIsVisible = true
        }
    }

    public func hideTransientSidebar() {
        if !sidebarIsLockedOpen {
            sidebarIsVisible = false
        }
    }

    public func setSidebarRevealEdge(_ edge: SidebarRevealEdge) {
        sidebarRevealEdge = edge
    }

    public func showCommandBar() {
        commandBarMode = .address
        isCommandBarPresented = true
        requestCommandBarFocus()
    }

    public func hideCommandBar() {
        isCommandBarPresented = false
        commandBarMode = .address
    }

    public func beginNewTab() {
        commandBarMode = .newTab
        isCommandBarPresented = true
        requestCommandBarFocus()
    }

    public func submitCommandInput(
        _ input: String,
        browserActionHandler: ((CommandRouter.BrowserAction) -> Bool)? = nil
    ) {
        perform(commandRouter.route(input: input), browserActionHandler: browserActionHandler)
    }

    public func submitAddressInput(
        _ input: String,
        browserActionHandler: ((CommandRouter.BrowserAction) -> Bool)? = nil
    ) {
        switch commandRouter.route(input: input) {
        case .openURL(let url), .search(let url, _):
            switch commandBarMode {
            case .address:
                navigateActiveTab(to: url)
            case .newTab:
                open(url)
            }
            hideCommandBar()
        case let command:
            perform(command, browserActionHandler: browserActionHandler)
        }
    }

    public func commandBarResults(
        for query: String,
        openTabLimit: Int = 5,
        profileLimit: Int = 5,
        historyLimit: Int = 5,
        browserActionAvailability: CommandRouter.BrowserActionAvailability? = nil
    ) -> [CommandBarResult] {
        _ = profileLimit
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let actionResults = browserActionAvailability.map { availability in
            commandRouter.browserActionSuggestions(for: trimmed, availability: availability)
                .map(CommandBarResult.browserAction)
        } ?? []
        let tabResults = matchingOpenTabs(for: trimmed, limit: openTabLimit)
            .map(CommandBarResult.openTab)
        let matchedHistory = historyResults(for: trimmed, limit: historyLimit)
            .map(CommandBarResult.history)

        return actionResults + tabResults + matchedHistory
    }

    public func activateCommandBarResult(
        _ result: CommandBarResult,
        browserActionHandler: ((CommandRouter.BrowserAction) -> Bool)? = nil
    ) {
        switch result {
        case .browserAction(let action):
            perform(.browserAction(action.action), browserActionHandler: browserActionHandler)
            return
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

    public func navigateActiveTab(to url: URL) {
        switch urlSecurityPolicy.decision(for: url) {
        case .allowInWebView:
            guard let selectedTabID else {
                _ = createTab(url: url)
                updatePageSecurityStatus(for: url)
                return
            }

            updateTab(selectedTabID) { tab in
                tab.content = .web
                tab.title = Self.defaultTitle(for: url)
                tab.url = url
                tab.restorationMetadata.lastCommittedURL = url
                tab.isLoading = true
            }
            updatePageSecurityStatus(for: url)
            persistSession()
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
        date: Date = Date(),
        completion: @escaping @MainActor (URL?) -> Void
    ) {
        cancelPendingDownloadCompletion(message: nil)

        switch request.risk {
        case .blocked(let reason):
            upsertDownload(
                BrowserDownload(
                    id: request.id,
                    filename: request.sanitizedFilename,
                    sourceDescription: request.sourceDescription,
                    state: .failed,
                    startedAt: date,
                    updatedAt: date,
                    completedAt: date,
                    failureMessage: reason
                )
            )
            lastUserMessage = reason
            completion(nil)
        case .low, .requiresConfirmation:
            upsertDownload(
                BrowserDownload(
                    id: request.id,
                    filename: request.sanitizedFilename,
                    sourceDescription: request.sourceDescription,
                    state: .waitingForDestination,
                    startedAt: date,
                    updatedAt: date
                )
            )
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
        markDownloadStarted(request.id, destinationURL: destinationURL)
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

    public var activeDownloads: [BrowserDownload] {
        downloads.filter { $0.state.isActive }
    }

    public var primaryActiveDownload: BrowserDownload? {
        activeDownloads.first
    }

    public func registerDownloadCancellation(
        _ id: UUID,
        cancel: @escaping @MainActor () -> Void
    ) {
        guard downloads.contains(where: { $0.id == id }) else {
            return
        }

        downloadCancellationHandlers[id] = cancel
    }

    @discardableResult
    public func cancelDownload(_ id: UUID) -> Bool {
        guard let cancel = downloadCancellationHandlers[id] else {
            return false
        }

        cancel()
        markDownloadCanceled(id)
        return true
    }

    public func updateDownloadProgress(
        _ id: UUID,
        progress: Double?,
        date: Date = Date()
    ) {
        updateDownload(id) { download in
            if download.state == .waitingForDestination {
                download.state = .downloading
            }
            download.progress = BrowserDownload.normalizedProgress(progress)
            download.updatedAt = date
        }
    }

    public func finishDownload(
        _ id: UUID,
        destinationURL: URL?,
        quarantineApplied: Bool,
        date: Date = Date()
    ) {
        downloadCancellationHandlers[id] = nil
        updateDownload(id) { download in
            download.state = .finished
            download.destinationURL = destinationURL ?? download.destinationURL
            download.progress = 1
            download.updatedAt = date
            download.completedAt = date
            download.failureMessage = quarantineApplied ? nil : "Quarantine metadata could not be applied."
        }
    }

    public func failDownload(
        _ id: UUID,
        message: String = "Download failed.",
        date: Date = Date()
    ) {
        downloadCancellationHandlers[id] = nil
        updateDownload(id) { download in
            guard download.state != .canceled else {
                return
            }
            download.state = .failed
            download.updatedAt = date
            download.completedAt = date
            download.failureMessage = message
        }
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
        updateTabFromWebView(
            tabID: selectedTabID,
            title: title,
            url: url,
            isLoading: isLoading,
            securityMessage: securityMessage
        )
    }

    public func updateTabFromWebView(
        tabID: TabID,
        title: String?,
        url: URL?,
        isLoading: Bool,
        securityMessage: String? = nil
    ) {
        guard let tabIndex = tabs.firstIndex(where: { $0.id == tabID }) else {
            return
        }

        let currentTab = tabs[tabIndex]
        guard currentTab.content.isWeb else {
            return
        }

        var updatedTab = currentTab
        if let title, !title.isEmpty {
            updatedTab.title = title
        }
        updatedTab.url = url ?? updatedTab.url
        updatedTab.isLoading = isLoading
        updatedTab.restorationMetadata.lastCommittedURL = url ?? updatedTab.restorationMetadata.lastCommittedURL
        if let updatedURL = url {
            updateHTTPSUpgradeFallbackMetadata(for: &updatedTab, committedURL: updatedURL)
        }

        let didChangeTabState = updatedTab != currentTab
        if didChangeTabState {
            tabs[tabIndex] = updatedTab
        }

        let completedNavigation = !isLoading
            && (currentTab.isLoading || (url != nil && url != currentTab.url))
        if completedNavigation {
            recordHistoryVisit(title: updatedTab.title, url: updatedTab.url, profileID: updatedTab.profileID)
        }

        if tabID == selectedTabID {
            if let securityMessage {
                publishStatusMessage(securityMessage)
            } else if let statusURL = url ?? updatedTab.url {
                updatePageSecurityStatus(for: statusURL)
            } else {
                clearCurrentPageSecurityStatus()
            }
        }
        if didChangeTabState {
            persistSession()
        }
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

    private func selectedTabID(in space: BrowserSpace) -> TabID? {
        let folderTabIDs = folders
            .filter { $0.parentSpaceID == space.id }
            .flatMap(\.tabIDs)
        let candidateIDs = ([space.selectedTabID].compactMap { $0 })
            + space.favoriteTabIDs
            + space.pinnedTabIDs
            + space.regularTabIDs
            + folderTabIDs

        return candidateIDs.first { candidateID in
            tabs.contains { tab in
                tab.id == candidateID
                    && tab.parentSpaceID == space.id
                    && tab.profileID == space.profileID
            }
        }
    }

    private func selectReplacementSpace(date: Date) {
        guard let replacementSpace = sidebarSpaces
            .max(by: { $0.lastActiveDate < $1.lastActiveDate }) else {
            selectedSpaceID = nil
            selectedTabID = nil
            return
        }

        selectedSpaceID = replacementSpace.id
        if let tabID = selectedTabID(in: replacementSpace) {
            selectedTabID = tabID
            updateSpace(replacementSpace.id) { space in
                space.selectedTabID = tabID
                space.lastActiveDate = date
            }
            updateTab(tabID) { tab in
                tab.lastActiveDate = date
            }
        } else {
            createStartTab(in: replacementSpace.id, profileID: replacementSpace.profileID, date: date)
        }
    }

    private func normalizeLegacySpaceSymbols() -> Bool {
        var didNormalize = false
        let legacyDefaultSymbolNames = [
            BrowserSpace.legacyDefaultSymbolName,
            "sparkle.magnifyingglass"
        ]
        for index in spaces.indices where legacyDefaultSymbolNames.contains(spaces[index].symbolName) {
            spaces[index].symbolName = BrowserSpace.defaultSymbolName
            didNormalize = true
        }
        return didNormalize
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

    private func updateTabs(inSpace spaceID: SpaceID, profileID: ProfileID) {
        for index in tabs.indices where tabs[index].parentSpaceID == spaceID {
            tabs[index].profileID = profileID
        }
    }

    private var defaultSpaceProfileID: ProfileID {
        if let selectedProfileID = selectedSpace?.profileID,
           persistentProfiles.contains(where: { $0.id == selectedProfileID }) {
            return selectedProfileID
        }
        return persistentProfiles.first?.id ?? profiles[0].id
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

    private func requestCommandBarFocus() {
        commandBarFocusRequest += 1
    }

    @discardableResult
    private func pruneStaleEmptyTabsFromLoadedSession() -> Bool {
        let emptyTabIDs = Set(tabs.filter(Self.isStaleEmptyTab).map(\.id))
        guard !emptyTabIDs.isEmpty else {
            return false
        }

        var tabIDsToRemove = Set<TabID>()
        for space in spaces {
            let emptyRegularTabIDs = space.regularTabIDs.filter { emptyTabIDs.contains($0) }
            guard !emptyRegularTabIDs.isEmpty else {
                continue
            }

            let folderTabIDs = folders
                .filter { $0.parentSpaceID == space.id }
                .flatMap(\.tabIDs)
            let hasRestorableTab = (space.favoriteTabIDs + space.pinnedTabIDs + space.regularTabIDs + folderTabIDs)
                .contains { !emptyTabIDs.contains($0) }

            if hasRestorableTab {
                tabIDsToRemove.formUnion(emptyRegularTabIDs)
            } else if emptyRegularTabIDs.count > 1 {
                let newestEmptyTabID = emptyRegularTabIDs.max { lhs, rhs in
                    lastActiveDate(for: lhs) < lastActiveDate(for: rhs)
                }
                tabIDsToRemove.formUnion(emptyRegularTabIDs.filter { $0 != newestEmptyTabID })
            }
        }

        guard !tabIDsToRemove.isEmpty else {
            return false
        }

        tabs.removeAll { tabIDsToRemove.contains($0.id) }
        folders.indices.forEach { index in
            folders[index].tabIDs.removeAll { tabIDsToRemove.contains($0) }
        }
        spaces.indices.forEach { index in
            spaces[index].favoriteTabIDs.removeAll { tabIDsToRemove.contains($0) }
            spaces[index].pinnedTabIDs.removeAll { tabIDsToRemove.contains($0) }
            spaces[index].regularTabIDs.removeAll { tabIDsToRemove.contains($0) }
            if let selectedTabID = spaces[index].selectedTabID,
               tabIDsToRemove.contains(selectedTabID) {
                spaces[index].selectedTabID = self.selectedTabID(in: spaces[index])
            }
        }
        splitViews.removeAll { splitView in
            splitView.tabIDs.contains { tabIDsToRemove.contains($0) }
        }
        if let selectedTabID,
           tabIDsToRemove.contains(selectedTabID) {
            self.selectedTabID = selectedSpace.flatMap { self.selectedTabID(in: $0) }
        }
        refreshActivePageSecurityStatus()
        return true
    }

    private func lastActiveDate(for tabID: TabID) -> Date {
        tabs.first { $0.id == tabID }?.lastActiveDate ?? .distantPast
    }

    private func matchingOpenTabs(for query: String, limit: Int) -> [BrowserTab] {
        guard limit > 0 else {
            return []
        }
        let visibleSpaceIDs = Set(sidebarSpaces.map(\.id))
        return Array(
            tabs
                .filter { tab in
                    visibleSpaceIDs.contains(tab.parentSpaceID)
                        && (
                            tab.title.localizedCaseInsensitiveContains(query)
                                || (tab.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false)
                        )
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
        let canceledDownloadID = pendingDownloadConfirmation?.id
        let completion = pendingDownloadCompletion
        pendingDownloadConfirmation = nil
        pendingDownloadCompletion = nil
        isChoosingDownloadDestination = false
        if let canceledDownloadID {
            markDownloadCanceled(canceledDownloadID)
        }
        if let message {
            lastUserMessage = message
        }
        completion?(nil)
    }

    private func markDownloadStarted(
        _ id: UUID,
        destinationURL: URL,
        date: Date = Date()
    ) {
        updateDownload(id) { download in
            download.destinationURL = destinationURL
            download.filename = destinationURL.lastPathComponent
            download.state = .downloading
            download.progress = 0
            download.updatedAt = date
        }
    }

    private func markDownloadCanceled(
        _ id: UUID,
        date: Date = Date()
    ) {
        downloadCancellationHandlers[id] = nil
        updateDownload(id) { download in
            guard download.state.isActive else {
                return
            }
            download.state = .canceled
            download.updatedAt = date
            download.completedAt = date
            download.failureMessage = "Download was canceled."
        }
    }

    private func upsertDownload(_ download: BrowserDownload) {
        if let index = downloads.firstIndex(where: { $0.id == download.id }) {
            downloads[index] = download
        } else {
            downloads.insert(download, at: 0)
        }
        sortDownloads()
    }

    private func updateDownload(
        _ id: UUID,
        mutate: (inout BrowserDownload) -> Void
    ) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else {
            return
        }

        mutate(&downloads[index])
        sortDownloads()
    }

    private func sortDownloads() {
        downloads.sort { lhs, rhs in
            if lhs.state.isActive != rhs.state.isActive {
                return lhs.state.isActive
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func schedulePersistSession(date: Date = Date()) {
        guard sessionPersistence != nil else {
            return
        }

        scheduledSessionPersistenceTask?.cancel()
        scheduledSessionPersistenceTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
            } catch {
                return
            }

            guard let self, !Task.isCancelled else {
                return
            }

            self.scheduledSessionPersistenceTask = nil
            self.persistSession(date: date)
        }
    }

    public func flushScheduledSessionPersistence(date: Date = Date()) {
        guard scheduledSessionPersistenceTask != nil else {
            return
        }

        scheduledSessionPersistenceTask?.cancel()
        scheduledSessionPersistenceTask = nil
        persistSession(date: date)
    }

    private func persistSession(date: Date = Date()) {
        scheduledSessionPersistenceTask?.cancel()
        scheduledSessionPersistenceTask = nil

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

    private static func isStaleEmptyTab(_ tab: BrowserTab) -> Bool {
        tab.content.isWeb
            && tab.url == nil
            && tab.title == defaultTitle(for: nil)
            && tab.restorationMetadata.lastCommittedURL == nil
            && tab.restorationMetadata.pendingHTTPFallbackURL == nil
            && tab.restorationMetadata.backForwardListHint.isEmpty
    }
}
