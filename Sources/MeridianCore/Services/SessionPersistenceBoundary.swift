import Foundation

public enum SessionPersistenceBoundary {
    public static func persistentSnapshot(
        from snapshot: BrowserSessionSnapshot,
        fallback: BrowserSessionSnapshot
    ) -> BrowserSessionSnapshot {
        let persistentProfiles = snapshot.profiles.filter { !$0.isEphemeral }
        let persistentProfileIDs = Set(persistentProfiles.map(\.id))
        let persistentSitePermissionSettings = snapshot.sitePermissionSettings.filter { setting in
            setting.persistsBeyondSession && persistentProfileIDs.contains(setting.profileID)
        }

        var persistentSpaces = snapshot.spaces.filter { persistentProfileIDs.contains($0.profileID) }
        let persistentSpaceIDs = Set(persistentSpaces.map(\.id))

        var persistentFolders = snapshot.folders.filter { persistentSpaceIDs.contains($0.parentSpaceID) }
        let persistentFolderIDs = Set(persistentFolders.map(\.id))

        var persistentTabs = snapshot.tabs.filter { tab in
            persistentProfileIDs.contains(tab.profileID) && persistentSpaceIDs.contains(tab.parentSpaceID)
        }
        let persistentTabIDs = Set(persistentTabs.map(\.id))
        let persistentTabSpaceIDs = Dictionary(uniqueKeysWithValues: persistentTabs.map { ($0.id, $0.parentSpaceID) })
        let persistentTabIDsBySpace = Dictionary(grouping: persistentTabs, by: \.parentSpaceID)
            .mapValues { $0.map(\.id) }

        persistentFolders = persistentFolders.map { folder in
            var folder = folder
            if let parentFolderID = folder.parentFolderID, !persistentFolderIDs.contains(parentFolderID) {
                folder.parentFolderID = nil
            }
            folder.childFolderIDs = folder.childFolderIDs.filter { persistentFolderIDs.contains($0) }
            folder.tabIDs = folder.tabIDs.filter { persistentTabIDs.contains($0) }
            return folder
        }

        let persistentSplitViews = snapshot.splitViews.filter { splitView in
            splitView.tabIDs.count >= 2 && splitView.tabIDs.allSatisfy { persistentTabIDs.contains($0) }
        }
        let persistentSplitViewIDs = Set(persistentSplitViews.map(\.id))

        persistentTabs = persistentTabs.map { tab in
            var tab = tab
            if let parentFolderID = tab.parentFolderID, !persistentFolderIDs.contains(parentFolderID) {
                tab.parentFolderID = nil
            }
            if let splitViewID = tab.splitViewID, !persistentSplitViewIDs.contains(splitViewID) {
                tab.splitViewID = nil
            }
            return tab
        }

        persistentSpaces = persistentSpaces.map { space in
            var space = space
            space.favoriteTabIDs = space.favoriteTabIDs.filter { persistentTabIDs.contains($0) }
            space.pinnedTabIDs = space.pinnedTabIDs.filter { persistentTabIDs.contains($0) }
            space.regularTabIDs = space.regularTabIDs.filter { persistentTabIDs.contains($0) }
            space.folderIDs = space.folderIDs.filter { persistentFolderIDs.contains($0) }
            if let selectedTabID = space.selectedTabID,
               persistentTabSpaceIDs[selectedTabID] != space.id {
                space.selectedTabID = repairedTabID(
                    in: space,
                    tabSpaceIDs: persistentTabSpaceIDs,
                    tabIDsBySpace: persistentTabIDsBySpace
                )
            }
            return space
        }

        guard !persistentProfiles.isEmpty, !persistentSpaces.isEmpty, !persistentTabs.isEmpty else {
            return fallback
        }

        let selectedSpaceID = repairedSelectedSpaceID(
            snapshot.selectedSpaceID,
            spaces: persistentSpaces
        )
        let selectedSpace = persistentSpaces.first { $0.id == selectedSpaceID }
        let selectedTabID = repairedSelectedTabID(
            snapshot.selectedTabID,
            selectedSpace: selectedSpace,
            tabSpaceIDs: persistentTabSpaceIDs,
            tabIDsBySpace: persistentTabIDsBySpace
        )

        return BrowserSessionSnapshot(
            schemaVersion: snapshot.schemaVersion,
            profiles: persistentProfiles,
            spaces: persistentSpaces,
            folders: persistentFolders,
            tabs: persistentTabs,
            splitViews: persistentSplitViews,
            selectedSpaceID: selectedSpaceID,
            selectedTabID: selectedTabID,
            capturedAt: snapshot.capturedAt,
            sitePermissionSettings: persistentSitePermissionSettings
        )
    }

    private static func repairedSelectedSpaceID(
        _ selectedSpaceID: SpaceID?,
        spaces: [BrowserSpace]
    ) -> SpaceID? {
        if let selectedSpaceID, spaces.contains(where: { $0.id == selectedSpaceID }) {
            return selectedSpaceID
        }
        return spaces.first?.id
    }

    private static func repairedSelectedTabID(
        _ selectedTabID: TabID?,
        selectedSpace: BrowserSpace?,
        tabSpaceIDs: [TabID: SpaceID],
        tabIDsBySpace: [SpaceID: [TabID]]
    ) -> TabID? {
        if let selectedTabID, tabSpaceIDs[selectedTabID] == selectedSpace?.id {
            return selectedTabID
        }
        guard let selectedSpace else {
            return nil
        }
        return repairedTabID(
            in: selectedSpace,
            tabSpaceIDs: tabSpaceIDs,
            tabIDsBySpace: tabIDsBySpace
        )
    }

    private static func repairedTabID(
        in space: BrowserSpace,
        tabSpaceIDs: [TabID: SpaceID],
        tabIDsBySpace: [SpaceID: [TabID]]
    ) -> TabID? {
        if let selectedTabID = space.selectedTabID, tabSpaceIDs[selectedTabID] == space.id {
            return selectedTabID
        }
        return space.favoriteTabIDs.first
            ?? space.pinnedTabIDs.first
            ?? space.regularTabIDs.first
            ?? tabIDsBySpace[space.id]?.first
    }
}
