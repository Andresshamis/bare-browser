import Foundation

enum SidebarSpacePagerPageID: Hashable, Sendable {
    case activity
    case space(SpaceID)

    var spaceID: SpaceID? {
        if case .space(let id) = self {
            return id
        }
        return nil
    }
}

struct SidebarSpacePagerNavigationRequest: Equatable, Sendable {
    let id = UUID()
    let pageID: SidebarSpacePagerPageID
}

struct SidebarSpacePagerSnapshot: Equatable, Sendable {
    let selectedSpacePageID: SidebarSpacePagerPageID?
    let selectedAuxiliaryPageID: SidebarSpacePagerPageID?
    let spaceCount: Int
    let pages: [SidebarSpacePagerPageSnapshot]

    var pageCount: Int {
        pages.count
    }
}

enum SidebarSpacePagerPageSnapshot: Identifiable, Equatable, Sendable {
    case activity(SidebarActivityPageSnapshot)
    case space(SidebarSpacePageSnapshot)

    var id: SidebarSpacePagerPageID {
        switch self {
        case .activity:
            return .activity
        case .space(let page):
            return .space(page.id)
        }
    }

    var space: BrowserSpace? {
        if case .space(let page) = self {
            return page.space
        }
        return nil
    }

    var chromeTheme: SidebarChromeTheme {
        switch self {
        case .activity:
            return .standard
        case .space(let page):
            return SidebarChromeTheme.theme(for: page.space)
        }
    }
}

struct SidebarActivityPageSnapshot: Equatable, Sendable {
    let profiles: [BrowserProfile]
    let downloads: [BrowserDownload]
    let historyEntries: [BrowserHistoryEntry]
}

struct SidebarSpacePageSnapshot: Identifiable, Equatable, Sendable {
    var id: SpaceID { space.id }

    let index: Int
    let space: BrowserSpace
    let favoriteTabs: [SidebarTabItemSnapshot]
    let pinnedTabs: [SidebarTabItemSnapshot]
    let folders: [SidebarFolderItemSnapshot]
    let regularTabs: [SidebarTabItemSnapshot]
}

struct SidebarFolderItemSnapshot: Identifiable, Equatable, Sendable {
    var id: FolderID { folder.id }

    let folder: BrowserFolder
    let tabs: [SidebarTabItemSnapshot]
    let childFolders: [SidebarFolderItemSnapshot]

    static func == (lhs: SidebarFolderItemSnapshot, rhs: SidebarFolderItemSnapshot) -> Bool {
        lhs.folder == rhs.folder
            && lhs.tabs == rhs.tabs
            && lhs.childFolders == rhs.childFolders
    }
}

struct SidebarTabItemSnapshot: Identifiable, Equatable, Sendable {
    var id: TabID { tab.id }

    let tab: BrowserTab
    let isSelected: Bool
    let hasLiveSession: Bool
    let canClose: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool

    init(
        tab: BrowserTab,
        isSelected: Bool,
        hasLiveSession: Bool = false,
        canClose: Bool = true,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) {
        self.tab = tab
        self.isSelected = isSelected
        self.hasLiveSession = hasLiveSession
        self.canClose = canClose
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
    }
}

struct SidebarSpacePageSectionVisibility {
    static func showsEmptyFavoriteTabDropSection(
        for page: SidebarSpacePageSnapshot,
        isDragging: Bool
    ) -> Bool {
        isDragging && page.favoriteTabs.isEmpty && hasTabsOutsideFavorites(in: page)
    }

    static func showsEmptyPinnedTabDropSection(
        for page: SidebarSpacePageSnapshot,
        isDragging: Bool
    ) -> Bool {
        isDragging && page.pinnedTabs.isEmpty && hasTabsOutsidePinnedList(in: page)
    }

    static func showsEmptyRegularTabDropSection(
        for page: SidebarSpacePageSnapshot,
        isDragging: Bool
    ) -> Bool {
        isDragging && page.regularTabs.isEmpty && hasTabsOutsideRegular(in: page)
    }

    private static func hasTabsOutsideFavorites(in page: SidebarSpacePageSnapshot) -> Bool {
        !page.pinnedTabs.isEmpty
            || !page.regularTabs.isEmpty
            || page.folders.contains(where: folderContainsTabs)
    }

    private static func hasTabsOutsidePinnedList(in page: SidebarSpacePageSnapshot) -> Bool {
        !page.favoriteTabs.isEmpty
            || !page.regularTabs.isEmpty
            || page.folders.contains(where: folderContainsTabs)
    }

    private static func hasTabsOutsideRegular(in page: SidebarSpacePageSnapshot) -> Bool {
        !page.favoriteTabs.isEmpty
            || !page.pinnedTabs.isEmpty
            || page.folders.contains(where: folderContainsTabs)
    }

    private static func folderContainsTabs(_ folder: SidebarFolderItemSnapshot) -> Bool {
        !folder.tabs.isEmpty || folder.childFolders.contains(where: folderContainsTabs)
    }
}


struct SidebarSpacePagerFocus {
    static func focusedTabID(
        for space: BrowserSpace,
        folders: [BrowserFolder],
        tabsByID: [TabID: BrowserTab]
    ) -> TabID? {
        BrowserSpaceFocusedTabResolver.focusedTabID(for: space, folders: folders, tabsByID: tabsByID)
    }

    static func isFocused(tabID: TabID, focusedTabID: TabID?) -> Bool {
        tabID == focusedTabID
    }
}

struct SidebarSpacePageSnapshotBuilder {
    static func spacePages(
        activeSpaces: [BrowserSpace],
        folders: [BrowserFolder],
        tabs: [BrowserTab],
        liveSessionTabIDs: Set<TabID> = []
    ) -> [SidebarSpacePageSnapshot] {
        let pageSpaceIDs = Set(activeSpaces.map(\.id))
        let foldersByID = Dictionary(
            uniqueKeysWithValues: folders
                .lazy
                .filter { pageSpaceIDs.contains($0.parentSpaceID) }
                .map { ($0.id, $0) }
        )
        let foldersBySpaceID = Dictionary(grouping: foldersByID.values, by: \.parentSpaceID)
        let directTabIDs = activeSpaces.flatMap { space in
            space.favoriteTabIDs + space.pinnedTabIDs + space.regularTabIDs
        }
        let folderTabIDs = foldersByID.values.flatMap(\.tabIDs)
        let visibleTabIDs = Set(directTabIDs + folderTabIDs)
        let tabsByID = Dictionary(
            uniqueKeysWithValues: tabs
                .lazy
                .filter { visibleTabIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        return activeSpaces.indices.map { index in
            let space = activeSpaces[index]
            let focusedTabID = SidebarSpacePagerFocus.focusedTabID(
                for: space,
                folders: foldersBySpaceID[space.id, default: []],
                tabsByID: tabsByID
            )

            return SidebarSpacePageSnapshot(
                index: index,
                space: space,
                favoriteTabs: tabItems(
                    for: space.favoriteTabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                pinnedTabs: tabItems(
                    for: space.pinnedTabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                folders: folderItems(
                    for: space.folderIDs,
                    focusedTabID: focusedTabID,
                    foldersByID: foldersByID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                regularTabs: tabItems(
                    for: space.regularTabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                )
            )
        }
    }

    private static func tabItems(
        for ids: [TabID],
        focusedTabID: TabID?,
        tabsByID: [TabID: BrowserTab],
        liveSessionTabIDs: Set<TabID>
    ) -> [SidebarTabItemSnapshot] {
        let orderedTabs = ids.compactMap { tabsByID[$0] }
        return orderedTabs.enumerated().map { index, tab in
            SidebarTabItemSnapshot(
                tab: tab,
                isSelected: SidebarSpacePagerFocus.isFocused(tabID: tab.id, focusedTabID: focusedTabID),
                hasLiveSession: liveSessionTabIDs.contains(tab.id),
                canMoveUp: index > 0,
                canMoveDown: index < orderedTabs.count - 1
            )
        }
    }

    private static func folderItems(
        for ids: [FolderID],
        focusedTabID: TabID?,
        foldersByID: [FolderID: BrowserFolder],
        tabsByID: [TabID: BrowserTab],
        liveSessionTabIDs: Set<TabID>
    ) -> [SidebarFolderItemSnapshot] {
        ids.compactMap { id in
            guard let folder = foldersByID[id] else {
                return nil
            }

            return SidebarFolderItemSnapshot(
                folder: folder,
                tabs: tabItems(
                    for: folder.tabIDs,
                    focusedTabID: focusedTabID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                ),
                childFolders: folderItems(
                    for: folder.childFolderIDs,
                    focusedTabID: focusedTabID,
                    foldersByID: foldersByID,
                    tabsByID: tabsByID,
                    liveSessionTabIDs: liveSessionTabIDs
                )
            )
        }
    }
}

