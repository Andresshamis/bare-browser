import Foundation

enum SessionIntegrityRepair {
    static func repair(
        _ snapshot: BrowserSessionSnapshot,
        fallback: BrowserSessionSnapshot
    ) -> SessionIntegrityRepairResult {
        var report = SessionIntegrityRepairReport()

        let persistentCandidates = snapshot.profiles.filter { !$0.isEphemeral }
        var profiles = uniqueProfilesKeepingOldest(persistentCandidates, report: &report)
        isolateSharedWebsiteDataStores(in: &profiles, report: &report)
        let profileIDs = Set(profiles.map(\.id))

        var spaces = uniqueByID(snapshot.spaces, id: \.id) { removed in
            report.duplicateSpaceIDsRemoved += removed
        }
        let originalSpaceCount = spaces.count
        spaces.removeAll { !profileIDs.contains($0.profileID) }
        report.orphanedObjectsRemoved += originalSpaceCount - spaces.count
        let spaceByID = Dictionary(uniqueKeysWithValues: spaces.map { ($0.id, $0) })
        let spaceIDs = Set(spaceByID.keys)

        var folders = uniqueByID(snapshot.folders, id: \.id) { removed in
            report.duplicateFolderIDsRemoved += removed
        }
        let originalFolderCount = folders.count
        folders.removeAll { !spaceIDs.contains($0.parentSpaceID) }
        report.orphanedObjectsRemoved += originalFolderCount - folders.count
        repairFolderParents(in: &folders, report: &report)
        var folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })

        var tabs = uniqueByID(snapshot.tabs, id: \.id) { removed in
            report.duplicateTabIDsRemoved += removed
        }
        let originalTabCount = tabs.count
        tabs.removeAll { !spaceIDs.contains($0.parentSpaceID) }
        report.orphanedObjectsRemoved += originalTabCount - tabs.count

        for index in tabs.indices {
            guard let space = spaceByID[tabs[index].parentSpaceID] else {
                continue
            }
            if tabs[index].profileID != space.profileID {
                tabs[index].profileID = space.profileID
                report.tabProfileMismatchesRepaired += 1
            }
            if let folderID = tabs[index].parentFolderID,
               folderByID[folderID]?.parentSpaceID != tabs[index].parentSpaceID {
                tabs[index].parentFolderID = nil
                report.folderRelationshipsRepaired += 1
            }
            if tabs[index].parentFolderID != nil {
                if tabs[index].isFavorite || tabs[index].isPinned {
                    report.ownershipListsRebuilt += 1
                }
                tabs[index].isFavorite = false
                tabs[index].isPinned = false
            } else if tabs[index].isFavorite && tabs[index].isPinned {
                tabs[index].isPinned = false
                report.ownershipListsRebuilt += 1
            }
        }

        rebuildFolderRelationships(folders: &folders, tabs: tabs, report: &report)
        folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        rebuildSpaceRelationships(spaces: &spaces, folders: folders, tabs: tabs, report: &report)

        guard !profiles.isEmpty, !spaces.isEmpty, !tabs.isEmpty else {
            report.fallbackWasUsed = true
            return SessionIntegrityRepairResult(snapshot: fallback, report: report)
        }

        let tabByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let originalSplitViewCount = snapshot.splitViews.count
        let splitViews = repairedSplitViews(snapshot.splitViews, tabByID: tabByID)
        report.splitViewsRemoved += originalSplitViewCount - splitViews.count
        let splitViewIDs = Set(splitViews.map(\.id))
        for index in tabs.indices {
            if let splitViewID = tabs[index].splitViewID, !splitViewIDs.contains(splitViewID) {
                tabs[index].splitViewID = nil
            }
        }

        let repairedSelectedSpaceID: SpaceID
        if let selectedSpaceID = snapshot.selectedSpaceID, spaceIDs.contains(selectedSpaceID) {
            repairedSelectedSpaceID = selectedSpaceID
        } else {
            repairedSelectedSpaceID = spaces[0].id
            report.selectionsRepaired += 1
        }
        let repairedSelectedTabID = spaces.first { $0.id == repairedSelectedSpaceID }?.selectedTabID
        if repairedSelectedTabID != snapshot.selectedTabID {
            report.selectionsRepaired += 1
        }

        let permissionSettings = repairedPermissionSettings(
            snapshot.sitePermissionSettings,
            persistentProfileIDs: profileIDs
        )
        let downloads = snapshot.downloads.compactMap { download -> BrowserDownload? in
            guard let profileID = download.profileID, profileIDs.contains(profileID) else {
                return nil
            }
            guard download.state.isActive else {
                return download
            }
            var repaired = download
            repaired.state = .failed
            repaired.updatedAt = snapshot.capturedAt
            repaired.completedAt = snapshot.capturedAt
            repaired.failureMessage = "Download was interrupted when Lumen Browser closed."
            return repaired
        }

        return SessionIntegrityRepairResult(
            snapshot: BrowserSessionSnapshot(
                schemaVersion: snapshot.schemaVersion,
                profiles: profiles,
                spaces: spaces,
                folders: folders,
                tabs: tabs,
                splitViews: splitViews,
                selectedSpaceID: repairedSelectedSpaceID,
                selectedTabID: repairedSelectedTabID,
                capturedAt: snapshot.capturedAt,
                sitePermissionSettings: permissionSettings,
                downloads: downloads
            ),
            report: report
        )
    }

    private static func uniqueProfilesKeepingOldest(
        _ profiles: [BrowserProfile],
        report: inout SessionIntegrityRepairReport
    ) -> [BrowserProfile] {
        let grouped = Dictionary(grouping: profiles, by: \.id)
        let keepers = grouped.mapValues { candidates in
            candidates.enumerated().min { lhs, rhs in
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt < rhs.element.createdAt
                }
                return lhs.offset < rhs.offset
            }!.element
        }
        report.duplicateProfileIDsRemoved += profiles.count - keepers.count
        var emitted = Set<ProfileID>()
        return profiles.compactMap { profile in
            guard !emitted.contains(profile.id), keepers[profile.id] == profile else {
                return nil
            }
            emitted.insert(profile.id)
            return profile
        }
    }

    private static func isolateSharedWebsiteDataStores(
        in profiles: inout [BrowserProfile],
        report: inout SessionIntegrityRepairReport
    ) {
        let orderedIndices = profiles.indices.sorted { lhs, rhs in
            if profiles[lhs].createdAt != profiles[rhs].createdAt {
                return profiles[lhs].createdAt < profiles[rhs].createdAt
            }
            return lhs < rhs
        }
        var seen = Set<UUID>()
        for index in orderedIndices {
            guard let storeID = profiles[index].persistentWebsiteDataStoreID else {
                continue
            }
            guard seen.insert(storeID).inserted else {
                profiles[index] = BrowserProfile(
                    id: profiles[index].id,
                    name: profiles[index].name,
                    colorHex: profiles[index].colorHex,
                    websiteDataStoreID: UUID(),
                    isEphemeral: false,
                    createdAt: profiles[index].createdAt
                )
                report.duplicateWebsiteDataStoresIsolated += 1
                continue
            }
        }
    }

    private static func repairFolderParents(
        in folders: inout [BrowserFolder],
        report: inout SessionIntegrityRepairReport
    ) {
        let rawByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        for index in folders.indices {
            guard let parentID = folders[index].parentFolderID else {
                continue
            }
            guard let parent = rawByID[parentID],
                  parent.parentSpaceID == folders[index].parentSpaceID,
                  parentID != folders[index].id else {
                folders[index].parentFolderID = nil
                report.folderRelationshipsRepaired += 1
                continue
            }
            var cursor: FolderID? = parentID
            var visited: Set<FolderID> = [folders[index].id]
            var hasCycle = false
            while let current = cursor {
                guard visited.insert(current).inserted else {
                    hasCycle = true
                    break
                }
                cursor = rawByID[current]?.parentFolderID
            }
            if hasCycle {
                folders[index].parentFolderID = nil
                report.folderRelationshipsRepaired += 1
            }
        }
    }

    private static func rebuildFolderRelationships(
        folders: inout [BrowserFolder],
        tabs: [BrowserTab],
        report: inout SessionIntegrityRepairReport
    ) {
        let folderParentByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parentFolderID) })
        let tabFolderByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.parentFolderID) })
        for index in folders.indices {
            let oldChildren = folders[index].childFolderIDs
            let expectedChildren = folders.filter { $0.parentFolderID == folders[index].id }.map(\.id)
            folders[index].childFolderIDs = mergedOrder(oldChildren, expected: expectedChildren) {
                folderParentByID[$0] == folders[index].id
            }
            let oldTabs = folders[index].tabIDs
            let expectedTabs = tabs.filter { $0.parentFolderID == folders[index].id }.map(\.id)
            folders[index].tabIDs = mergedOrder(oldTabs, expected: expectedTabs) {
                tabFolderByID[$0] == folders[index].id
            }
            if oldChildren != folders[index].childFolderIDs || oldTabs != folders[index].tabIDs {
                report.ownershipListsRebuilt += 1
            }
        }
    }

    private static func rebuildSpaceRelationships(
        spaces: inout [BrowserSpace],
        folders: [BrowserFolder],
        tabs: [BrowserTab],
        report: inout SessionIntegrityRepairReport
    ) {
        let tabByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        for index in spaces.indices {
            let spaceID = spaces[index].id
            let oldSpace = spaces[index]
            let expectedTopFolders = folders.filter {
                $0.parentSpaceID == spaceID && $0.parentFolderID == nil
            }.map(\.id)
            spaces[index].folderIDs = mergedOrder(oldSpace.folderIDs, expected: expectedTopFolders) {
                folderByID[$0]?.parentSpaceID == spaceID && folderByID[$0]?.parentFolderID == nil
            }

            let directTabs = tabs.filter { $0.parentSpaceID == spaceID && $0.parentFolderID == nil }
            let expectedFavorites = directTabs.filter(\.isFavorite).map(\.id)
            let expectedPinned = directTabs.filter { !$0.isFavorite && $0.isPinned }.map(\.id)
            let expectedRegular = directTabs.filter { !$0.isFavorite && !$0.isPinned }.map(\.id)
            spaces[index].favoriteTabIDs = mergedOrder(oldSpace.favoriteTabIDs, expected: expectedFavorites) {
                tabByID[$0]?.parentSpaceID == spaceID && tabByID[$0]?.isFavorite == true
            }
            spaces[index].pinnedTabIDs = mergedOrder(oldSpace.pinnedTabIDs, expected: expectedPinned) {
                tabByID[$0]?.parentSpaceID == spaceID
                    && tabByID[$0]?.isFavorite == false
                    && tabByID[$0]?.isPinned == true
            }
            spaces[index].regularTabIDs = mergedOrder(oldSpace.regularTabIDs, expected: expectedRegular) {
                tabByID[$0]?.parentSpaceID == spaceID
                    && tabByID[$0]?.isFavorite == false
                    && tabByID[$0]?.isPinned == false
                    && tabByID[$0]?.parentFolderID == nil
            }
            let candidateSelection = oldSpace.selectedTabID.flatMap { selectedID in
                tabByID[selectedID]?.parentSpaceID == spaceID ? selectedID : nil
            }
            spaces[index].selectedTabID = candidateSelection
                ?? spaces[index].favoriteTabIDs.first
                ?? spaces[index].pinnedTabIDs.first
                ?? spaces[index].regularTabIDs.first
                ?? folders.filter { $0.parentSpaceID == spaceID }.flatMap(\.tabIDs).first

            if oldSpace.favoriteTabIDs != spaces[index].favoriteTabIDs
                || oldSpace.pinnedTabIDs != spaces[index].pinnedTabIDs
                || oldSpace.regularTabIDs != spaces[index].regularTabIDs
                || oldSpace.folderIDs != spaces[index].folderIDs {
                report.ownershipListsRebuilt += 1
            }
            if oldSpace.selectedTabID != spaces[index].selectedTabID {
                report.selectionsRepaired += 1
            }
        }
    }

    private static func repairedSplitViews(
        _ splitViews: [SplitViewLayout],
        tabByID: [TabID: BrowserTab]
    ) -> [SplitViewLayout] {
        var seen = Set<SplitViewID>()
        return splitViews.compactMap { splitView in
            guard seen.insert(splitView.id).inserted else {
                return nil
            }
            var seenTabIDs = Set<TabID>()
            let uniqueTabIDs = splitView.tabIDs.filter { seenTabIDs.insert($0).inserted }
            guard uniqueTabIDs.count >= 2,
                  let first = uniqueTabIDs.first.flatMap({ tabByID[$0] }),
                  uniqueTabIDs.allSatisfy({
                      tabByID[$0]?.parentSpaceID == first.parentSpaceID
                          && tabByID[$0]?.profileID == first.profileID
                  }) else {
                return nil
            }
            var repaired = splitView
            repaired.tabIDs = uniqueTabIDs
            if repaired.fractions.count != uniqueTabIDs.count
                || repaired.fractions.contains(where: { !$0.isFinite || $0 <= 0 }) {
                repaired.fractions = Array(repeating: 1 / Double(uniqueTabIDs.count), count: uniqueTabIDs.count)
            } else {
                let total = repaired.fractions.reduce(0, +)
                repaired.fractions = repaired.fractions.map { $0 / total }
            }
            return repaired
        }
    }

    private static func repairedPermissionSettings(
        _ settings: [SitePermissionSetting],
        persistentProfileIDs: Set<ProfileID>
    ) -> [SitePermissionSetting] {
        let candidates = settings.filter {
            $0.persistsBeyondSession && persistentProfileIDs.contains($0.profileID)
        }
        let grouped = Dictionary(grouping: candidates) {
            "\($0.profileID.uuidString)|\($0.kind.rawValue)|\($0.origin.serializedOrigin)"
        }
        return grouped.values.compactMap { $0.max { $0.updatedAt < $1.updatedAt } }
    }

    private static func uniqueByID<Element, ID: Hashable>(
        _ elements: [Element],
        id: KeyPath<Element, ID>,
        removed: (Int) -> Void
    ) -> [Element] {
        var seen = Set<ID>()
        let result = elements.filter { seen.insert($0[keyPath: id]).inserted }
        removed(elements.count - result.count)
        return result
    }

    private static func mergedOrder<ID: Hashable>(
        _ existing: [ID],
        expected: [ID],
        isValid: (ID) -> Bool
    ) -> [ID] {
        let expectedSet = Set(expected)
        var seen = Set<ID>()
        let kept = existing.filter {
            expectedSet.contains($0) && isValid($0) && seen.insert($0).inserted
        }
        return kept + expected.filter { seen.insert($0).inserted }
    }
}
