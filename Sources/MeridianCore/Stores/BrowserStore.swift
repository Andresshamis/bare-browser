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
    @Published public var lastUserMessage: String?

    public let commandRouter: CommandRouter
    public let urlSecurityPolicy: URLSecurityPolicy

    public init(
        snapshot: BrowserSessionSnapshot = SessionSnapshotFactory.initial(),
        commandRouter: CommandRouter = CommandRouter(),
        urlSecurityPolicy: URLSecurityPolicy = URLSecurityPolicy()
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
        self.lastUserMessage = nil
        self.commandRouter = commandRouter
        self.urlSecurityPolicy = urlSecurityPolicy
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
        return folder
    }

    @discardableResult
    public func createProfile(name: String, ephemeral: Bool = false) -> BrowserProfile {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = ephemeral
            ? BrowserProfile.privateBrowsing()
            : BrowserProfile(name: cleanedName.isEmpty ? "Profile \(profiles.count + 1)" : cleanedName)
        profiles.append(profile)
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
            if urlSecurityPolicy.isInsecureTransport(url) {
                lastUserMessage = "This page uses insecure HTTP."
            }
        case .requireExternalApplicationConfirmation:
            requestURLConfirmation(kind: .externalApplication, url: url)
        case .requireLocalFileConfirmation:
            requestURLConfirmation(kind: .localFile, url: url)
        case .block(let reason):
            lastUserMessage = reason
        }
    }

    public func requestURLConfirmation(
        kind: URLConfirmationRequest.Kind,
        url: URL,
        sourceURL: URL? = nil,
        date: Date = Date()
    ) {
        pendingURLConfirmation = URLConfirmationRequest(
            kind: kind,
            url: url,
            sourceURL: sourceURL,
            createdAt: date
        )
        lastUserMessage = kind.pendingMessage
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

    public func updateActiveTabFromWebView(title: String?, url: URL?, isLoading: Bool) {
        guard let selectedTabID else {
            return
        }
        updateTab(selectedTabID) { tab in
            if let title, !title.isEmpty {
                tab.title = title
            }
            tab.url = url ?? tab.url
            tab.isLoading = isLoading
            tab.restorationMetadata.lastCommittedURL = url ?? tab.restorationMetadata.lastCommittedURL
        }
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

    private static func defaultTitle(for url: URL?) -> String {
        guard let url else {
            return "New Tab"
        }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }
}
