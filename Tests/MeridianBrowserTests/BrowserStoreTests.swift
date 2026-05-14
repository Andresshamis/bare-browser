import Foundation
import MeridianCore
import XCTest

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testInitialSnapshotHasProfileSpaceAndSelectedTab() {
        let store = BrowserStore(snapshot: SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 0)))

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNotNil(store.selectedSpaceID)
        XCTAssertNotNil(store.selectedTabID)
        XCTAssertEqual(store.activeProfile?.name, "Personal")
    }

    func testSidebarRevealStateDefaultsAndUpdates() {
        let store = BrowserStore()

        XCTAssertTrue(store.sidebarIsVisible)
        XCTAssertTrue(store.sidebarIsLockedOpen)
        XCTAssertEqual(store.sidebarRevealEdge, .left)

        store.toggleSidebar()
        XCTAssertTrue(store.sidebarIsVisible)
        XCTAssertFalse(store.sidebarIsLockedOpen)

        store.hideTransientSidebar()
        XCTAssertFalse(store.sidebarIsVisible)
        XCTAssertFalse(store.sidebarIsLockedOpen)

        store.revealSidebar()
        XCTAssertTrue(store.sidebarIsVisible)
        XCTAssertFalse(store.sidebarIsLockedOpen)

        store.hideTransientSidebar()
        XCTAssertFalse(store.sidebarIsVisible)
        XCTAssertFalse(store.sidebarIsLockedOpen)

        store.toggleSidebarLock()
        XCTAssertTrue(store.sidebarIsVisible)
        XCTAssertTrue(store.sidebarIsLockedOpen)

        store.setSidebarRevealEdge(.right)
        XCTAssertEqual(store.sidebarRevealEdge, .right)
    }

    func testCreatesSpaceFolderAndTabWithStableRelationships() {
        let store = BrowserStore()
        let space = store.createSpace(name: "Work")
        let folder = store.createFolder(name: "Research", in: space.id)
        let tab = store.createTab(url: URL(string: "https://webkit.org"), in: space.id, folderID: folder?.id)

        XCTAssertEqual(store.selectedSpaceID, space.id)
        XCTAssertEqual(tab?.parentSpaceID, space.id)
        XCTAssertEqual(tab?.parentFolderID, folder?.id)
        XCTAssertEqual(store.folders.first(where: { $0.id == folder?.id })?.tabIDs, [tab?.id].compactMap { $0 })
    }

    func testTabPlacementMovesBetweenSectionsAndPreservesSelection() throws {
        let store = BrowserStore()
        let tab = try XCTUnwrap(store.createTab(title: "Docs", url: URL(string: "https://docs.example.com")!))
        let spaceID = try XCTUnwrap(store.selectedSpaceID)

        XCTAssertTrue(store.setTabPlacement(.pinned, for: tab.id))
        XCTAssertEqual(store.selectedTabID, tab.id)
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.pinnedTabIDs, [tab.id])
        XCTAssertFalse(store.spaces.first(where: { $0.id == spaceID })?.regularTabIDs.contains(tab.id) ?? true)
        XCTAssertEqual(store.tabs.first(where: { $0.id == tab.id })?.isPinned, true)
        XCTAssertEqual(store.tabs.first(where: { $0.id == tab.id })?.isFavorite, false)

        XCTAssertTrue(store.setTabPlacement(.favorite, for: tab.id))
        XCTAssertEqual(store.selectedTabID, tab.id)
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.favoriteTabIDs.last, tab.id)
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.favoriteTabIDs.filter { $0 == tab.id }.count, 1)
        XCTAssertFalse(store.spaces.first(where: { $0.id == spaceID })?.pinnedTabIDs.contains(tab.id) ?? true)
        XCTAssertEqual(store.tabs.first(where: { $0.id == tab.id })?.isPinned, false)
        XCTAssertEqual(store.tabs.first(where: { $0.id == tab.id })?.isFavorite, true)

        XCTAssertTrue(store.setTabPlacement(.regular, for: tab.id))
        XCTAssertEqual(store.selectedTabID, tab.id)
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.regularTabIDs.last, tab.id)
        XCTAssertFalse(store.spaces.first(where: { $0.id == spaceID })?.favoriteTabIDs.contains(tab.id) ?? true)
        XCTAssertEqual(store.tabs.first(where: { $0.id == tab.id })?.isPinned, false)
        XCTAssertEqual(store.tabs.first(where: { $0.id == tab.id })?.isFavorite, false)
    }

    func testCloseInactiveTabPreservesSelectedTab() throws {
        let store = BrowserStore()
        let selectedTab = try XCTUnwrap(store.createTab(title: "Selected", url: URL(string: "https://selected.example.com")!))
        let inactiveTab = try XCTUnwrap(store.createTab(title: "Inactive", url: URL(string: "https://inactive.example.com")!))
        store.selectTab(selectedTab.id)

        XCTAssertTrue(store.closeTab(inactiveTab.id))

        XCTAssertEqual(store.selectedTabID, selectedTab.id)
        XCTAssertFalse(store.tabs.contains { $0.id == inactiveTab.id })
        XCTAssertFalse(store.selectedSpace?.regularTabIDs.contains(inactiveTab.id) ?? true)
    }

    func testMoveTabReordersRegularTabs() throws {
        let store = BrowserStore()
        let first = try XCTUnwrap(store.createTab(title: "First", url: URL(string: "https://first.example.com")!))
        let second = try XCTUnwrap(store.createTab(title: "Second", url: URL(string: "https://second.example.com")!))
        let third = try XCTUnwrap(store.createTab(title: "Third", url: URL(string: "https://third.example.com")!))

        XCTAssertTrue(store.moveTab(third.id, to: .regular, before: first.id))

        let regularTabIDs = try XCTUnwrap(store.selectedSpace?.regularTabIDs)
        XCTAssertLessThan(regularTabIDs.firstIndex(of: third.id)!, regularTabIDs.firstIndex(of: first.id)!)
        XCTAssertLessThan(regularTabIDs.firstIndex(of: first.id)!, regularTabIDs.firstIndex(of: second.id)!)
    }

    func testMoveTabBetweenSections() throws {
        let store = BrowserStore()
        let tab = try XCTUnwrap(store.createTab(title: "Move Me", url: URL(string: "https://move.example.com")!))

        XCTAssertTrue(store.moveTab(tab.id, to: .pinned))

        let updatedTab = try XCTUnwrap(store.tabs.first { $0.id == tab.id })
        XCTAssertTrue(updatedTab.isPinned)
        XCTAssertFalse(updatedTab.isFavorite)
        XCTAssertEqual(store.selectedSpace?.pinnedTabIDs, [tab.id])
        XCTAssertFalse(store.selectedSpace?.regularTabIDs.contains(tab.id) ?? true)
    }

    func testSubmitAddressInputNavigatesSelectedTab() throws {
        let store = BrowserStore()
        let tabCount = store.tabs.count
        let selectedTabID = try XCTUnwrap(store.selectedTabID)

        store.submitAddressInput("example.com")

        XCTAssertEqual(store.tabs.count, tabCount)
        XCTAssertEqual(store.selectedTabID, selectedTabID)
        XCTAssertEqual(store.activeTab?.url, URL(string: "https://example.com")!)
    }

    func testPromotingFolderTabRemovesFolderMembership() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let folder = try XCTUnwrap(store.createFolder(name: "Research", in: spaceID))
        let tab = try XCTUnwrap(store.createTab(
            title: "Foldered",
            url: URL(string: "https://folder.example.com")!,
            in: spaceID,
            folderID: folder.id
        ))

        XCTAssertTrue(store.setTabPlacement(.favorite, for: tab.id))

        let updatedTab = try XCTUnwrap(store.tabs.first { $0.id == tab.id })
        let updatedSpace = try XCTUnwrap(store.spaces.first { $0.id == spaceID })
        XCTAssertNil(updatedTab.parentFolderID)
        XCTAssertTrue(updatedTab.isFavorite)
        XCTAssertFalse(updatedTab.isPinned)
        XCTAssertEqual(updatedSpace.favoriteTabIDs.last, tab.id)
        XCTAssertEqual(updatedSpace.favoriteTabIDs.filter { $0 == tab.id }.count, 1)
        XCTAssertFalse(updatedSpace.pinnedTabIDs.contains(tab.id))
        XCTAssertFalse(updatedSpace.regularTabIDs.contains(tab.id))
        XCTAssertFalse(store.folders.first(where: { $0.id == folder.id })?.tabIDs.contains(tab.id) ?? true)
    }

    func testTabPlacementRoundTripsThroughSnapshotPersistenceShape() throws {
        let store = BrowserStore()
        let tab = try XCTUnwrap(store.createTab(title: "Pinned", url: URL(string: "https://pinned.example.com")!))
        XCTAssertTrue(store.setTabPlacement(.pinned, for: tab.id))

        let data = try JSONEncoder().encode(store.persistentSnapshot(date: Date(timeIntervalSince1970: 12)))
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)
        let restored = BrowserStore(snapshot: decoded)

        let restoredTab = try XCTUnwrap(restored.tabs.first { $0.id == tab.id })
        let restoredSpace = try XCTUnwrap(restored.spaces.first { $0.id == restoredTab.parentSpaceID })
        XCTAssertTrue(restoredTab.isPinned)
        XCTAssertFalse(restoredTab.isFavorite)
        XCTAssertEqual(restoredSpace.pinnedTabIDs, [tab.id])
        XCTAssertFalse(restoredSpace.regularTabIDs.contains(tab.id))
    }

    func testTabReorderMovesWithinSidebarSectionsAndPreservesSelection() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let regularA = try XCTUnwrap(store.createTab(title: "Regular A"))
        let regularB = try XCTUnwrap(store.createTab(title: "Regular B"))
        let regularC = try XCTUnwrap(store.createTab(title: "Regular C"))
        store.selectTab(regularB.id)

        XCTAssertTrue(store.canMoveTab(regularB.id, .up))
        XCTAssertTrue(store.moveTab(regularB.id, .up))
        XCTAssertEqual(Array(try XCTUnwrap(store.spaces.first { $0.id == spaceID }).regularTabIDs.suffix(3)), [regularB.id, regularA.id, regularC.id])
        XCTAssertEqual(store.selectedTabID, regularB.id)

        XCTAssertTrue(store.moveTab(regularB.id, .down))
        XCTAssertEqual(Array(try XCTUnwrap(store.spaces.first { $0.id == spaceID }).regularTabIDs.suffix(3)), [regularA.id, regularB.id, regularC.id])

        let favoriteA = try XCTUnwrap(store.createTab(title: "Favorite A"))
        let favoriteB = try XCTUnwrap(store.createTab(title: "Favorite B"))
        XCTAssertTrue(store.setTabPlacement(.favorite, for: favoriteA.id))
        XCTAssertTrue(store.setTabPlacement(.favorite, for: favoriteB.id))
        XCTAssertTrue(store.moveTab(favoriteB.id, .up))
        XCTAssertEqual(Array(try XCTUnwrap(store.spaces.first { $0.id == spaceID }).favoriteTabIDs.suffix(2)), [favoriteB.id, favoriteA.id])

        let pinnedA = try XCTUnwrap(store.createTab(title: "Pinned A"))
        let pinnedB = try XCTUnwrap(store.createTab(title: "Pinned B"))
        XCTAssertTrue(store.setTabPlacement(.pinned, for: pinnedA.id))
        XCTAssertTrue(store.setTabPlacement(.pinned, for: pinnedB.id))
        XCTAssertTrue(store.moveTab(pinnedA.id, .down))
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.pinnedTabIDs, [pinnedB.id, pinnedA.id])
    }

    func testTabReorderMovesFolderTabsWithinFolderOnly() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let folder = try XCTUnwrap(store.createFolder(name: "Research", in: spaceID))
        let first = try XCTUnwrap(store.createTab(title: "Folder A", in: spaceID, folderID: folder.id))
        let second = try XCTUnwrap(store.createTab(title: "Folder B", in: spaceID, folderID: folder.id))
        let third = try XCTUnwrap(store.createTab(title: "Folder C", in: spaceID, folderID: folder.id))
        store.selectTab(second.id)

        XCTAssertTrue(store.moveTab(second.id, .down))
        XCTAssertEqual(store.folders.first(where: { $0.id == folder.id })?.tabIDs, [first.id, third.id, second.id])
        XCTAssertEqual(store.selectedTabID, second.id)
        XCTAssertFalse(store.spaces.first(where: { $0.id == spaceID })?.regularTabIDs.contains(second.id) ?? true)

        XCTAssertTrue(store.moveTab(second.id, .up))
        XCTAssertEqual(store.folders.first(where: { $0.id == folder.id })?.tabIDs, [first.id, second.id, third.id])
    }

    func testTabReorderRejectsEdgesAndMissingTabs() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        _ = try XCTUnwrap(store.createTab(title: "Regular A"))
        let regularB = try XCTUnwrap(store.createTab(title: "Regular B"))
        let space = try XCTUnwrap(store.spaces.first(where: { $0.id == spaceID }))
        let leadingTabID = try XCTUnwrap(space.regularTabIDs.first)

        XCTAssertFalse(store.canMoveTab(leadingTabID, .up))
        XCTAssertFalse(store.moveTab(leadingTabID, .up))
        XCTAssertFalse(store.canMoveTab(regularB.id, .down))
        XCTAssertFalse(store.moveTab(regularB.id, .down))
        XCTAssertFalse(store.moveTab(UUID(), .up))
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.regularTabIDs, space.regularTabIDs)
    }

    func testTabReorderRoundTripsThroughSnapshotPersistenceShape() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let first = try XCTUnwrap(store.createTab(title: "First"))
        let second = try XCTUnwrap(store.createTab(title: "Second"))
        let third = try XCTUnwrap(store.createTab(title: "Third"))
        XCTAssertTrue(store.moveTab(third.id, .up))
        XCTAssertTrue(store.moveTab(third.id, .up))

        let data = try JSONEncoder().encode(store.persistentSnapshot(date: Date(timeIntervalSince1970: 24)))
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)
        let restored = BrowserStore(snapshot: decoded)
        let restoredSpace = try XCTUnwrap(restored.spaces.first { $0.id == spaceID })

        XCTAssertEqual(Array(restoredSpace.regularTabIDs.suffix(3)), [third.id, first.id, second.id])
    }

    func testCommandBarPlacementActionsMoveSelectedTab() throws {
        let store = BrowserStore()
        let tab = try XCTUnwrap(store.createTab(title: "Actions", url: URL(string: "https://actions.example.com")!))
        let spaceID = try XCTUnwrap(store.selectedSpaceID)

        store.submitCommandInput("pin tab")
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.pinnedTabIDs, [tab.id])
        XCTAssertEqual(store.activeTab?.isPinned, true)

        store.submitCommandInput("add to essentials")
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.favoriteTabIDs.last, tab.id)
        XCTAssertEqual(store.activeTab?.isFavorite, true)

        store.submitCommandInput("move to tabs")
        XCTAssertEqual(store.spaces.first(where: { $0.id == spaceID })?.regularTabIDs.last, tab.id)
        XCTAssertEqual(store.activeTab?.isPinned, false)
        XCTAssertEqual(store.activeTab?.isFavorite, false)
    }

    func testCommandBarReorderActionsMoveSelectedTabWithinSection() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let first = try XCTUnwrap(store.createTab(title: "First"))
        let second = try XCTUnwrap(store.createTab(title: "Second"))
        let third = try XCTUnwrap(store.createTab(title: "Third"))
        store.selectTab(second.id)

        store.submitCommandInput("move tab up")
        XCTAssertEqual(Array(try XCTUnwrap(store.spaces.first { $0.id == spaceID }).regularTabIDs.suffix(3)), [second.id, first.id, third.id])
        XCTAssertEqual(store.selectedTabID, second.id)

        store.submitCommandInput("move tab down")
        XCTAssertEqual(Array(try XCTUnwrap(store.spaces.first { $0.id == spaceID }).regularTabIDs.suffix(3)), [first.id, second.id, third.id])
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let store = BrowserStore()
        _ = store.createTab(url: URL(string: "https://example.com"))
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://camera.example")!))
        _ = store.requestSitePermission(kind: .camera, origin: origin, profileID: profileID)
        let requestID = try XCTUnwrap(store.pendingSitePermissionRequest?.id)
        _ = store.resolvePendingSitePermission(.allow, requestID: requestID)

        let snapshot = store.snapshot(date: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.tabs.count, snapshot.tabs.count)
        XCTAssertEqual(decoded.selectedTabID, snapshot.selectedTabID)
        XCTAssertEqual(decoded.sitePermissionSettings.count, 1)
        XCTAssertEqual(decoded.sitePermissionSettings.first?.origin.serializedOrigin, "https://camera.example")

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyObject.removeValue(forKey: "sitePermissionSettings")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacyDecoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: legacyData)
        XCTAssertTrue(legacyDecoded.sitePermissionSettings.isEmpty)
    }

    func testWebViewUpdateRecordsPublicHistoryEntry() throws {
        let store = BrowserStore()
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let url = URL(string: "https://user:pass@example.com/article?view=full&token=fixture#section")!
        let normalizedURL = URL(string: "https://example.com/article?view=full")!

        store.updateActiveTabFromWebView(title: "Example Article", url: url, isLoading: false)

        let entry = try XCTUnwrap(store.historyEntries.first)
        XCTAssertEqual(entry.profileID, profileID)
        XCTAssertEqual(entry.url, normalizedURL)
        XCTAssertEqual(entry.title, "Example Article")
        XCTAssertEqual(entry.visitCount, 1)
        for sensitiveComponent in ["user", "pass", "token", "fixture", "section"] {
            XCTAssertFalse(entry.url.absoluteString.contains(sensitiveComponent))
        }
    }

    func testPrivateProfileWebViewUpdateDoesNotRecordHistory() {
        let store = BrowserStore()
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private", profileID: privateProfile.id)
        _ = store.createTab(
            title: "Private",
            url: URL(string: "https://private.example/secret?token=fixture"),
            in: privateSpace.id
        )

        store.updateActiveTabFromWebView(
            title: "Private Secret",
            url: URL(string: "https://private.example/secret?token=fixture"),
            isLoading: false
        )

        XCTAssertTrue(store.historyEntries.isEmpty)
        XCTAssertTrue(store.historyResults(for: "private").isEmpty)
    }

    func testHistoryQueriesAreScopedToActiveProfile() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let personalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let workProfile = store.createProfile(name: "Work")
        _ = store.createSpace(name: "Work", profileID: workProfile.id)

        store.recordHistoryVisit(
            title: "Personal Portal",
            url: URL(string: "https://personal.example/portal")!,
            profileID: personalProfileID,
            date: Date(timeIntervalSince1970: 10)
        )
        store.recordHistoryVisit(
            title: "Work Portal",
            url: URL(string: "https://work.example/portal")!,
            profileID: workProfile.id,
            date: Date(timeIntervalSince1970: 20)
        )

        store.selectSpace(personalSpaceID)

        XCTAssertEqual(store.historyResults(for: "portal").map(\.title), ["Personal Portal"])
        XCTAssertEqual(store.historyResults(for: "portal", profileID: workProfile.id).map(\.title), ["Work Portal"])
    }

    func testPersistentProfileCreationSelectsDefaultContextAndPersistsPublicState() throws {
        let spy = BrowserStoreSessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)

        let profile = store.createPersistentProfile(name: "  Work  ")

        XCTAssertEqual(profile.name, "Work")
        XCTAssertFalse(profile.isEphemeral)
        XCTAssertNotNil(profile.persistentWebsiteDataStoreID)
        XCTAssertEqual(store.activeProfile?.id, profile.id)

        let selectedSpace = try XCTUnwrap(store.selectedSpace)
        XCTAssertEqual(selectedSpace.name, "Work")
        XCTAssertEqual(selectedSpace.profileID, profile.id)

        let selectedTab = try XCTUnwrap(store.activeTab)
        XCTAssertEqual(selectedTab.profileID, profile.id)
        XCTAssertEqual(selectedTab.parentSpaceID, selectedSpace.id)
        XCTAssertNil(selectedTab.url)

        let savedSnapshot = try XCTUnwrap(spy.savedSnapshots.last)
        XCTAssertTrue(savedSnapshot.profiles.contains { $0.id == profile.id })
        XCTAssertTrue(savedSnapshot.spaces.contains { $0.id == selectedSpace.id })
        XCTAssertTrue(savedSnapshot.tabs.contains { $0.id == selectedTab.id })
    }

    func testPersistentSnapshotIncludesPersistentProfilesAndExcludesPrivateProfiles() throws {
        let store = BrowserStore()
        let workProfile = store.createPersistentProfile(name: "Work")
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)
        _ = store.createSpace(name: "Private", profileID: privateProfile.id)

        let persisted = store.persistentSnapshot()

        XCTAssertTrue(persisted.profiles.contains { $0.id == workProfile.id })
        XCTAssertFalse(persisted.profiles.contains { $0.id == privateProfile.id })
        XCTAssertFalse(persisted.spaces.contains { $0.profileID == privateProfile.id })
        XCTAssertFalse(persisted.tabs.contains { $0.profileID == privateProfile.id })
    }

    func testSwitchingProfilesKeepsHistoryAndSitePermissionsScoped() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let workProfile = store.createPersistentProfile(name: "Work")
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://camera.example")!))

        store.recordHistoryVisit(
            title: "Personal Portal",
            url: URL(string: "https://personal.example/portal")!,
            profileID: personalProfileID,
            date: Date(timeIntervalSince1970: 10)
        )
        store.recordHistoryVisit(
            title: "Work Portal",
            url: URL(string: "https://work.example/portal")!,
            profileID: workProfile.id,
            date: Date(timeIntervalSince1970: 20)
        )

        _ = store.requestSitePermission(kind: .camera, origin: origin, profileID: personalProfileID)
        _ = store.resolvePendingSitePermission(
            .allow,
            requestID: try XCTUnwrap(store.pendingSitePermissionRequest?.id)
        )

        XCTAssertTrue(store.switchProfile(personalProfileID))
        XCTAssertEqual(store.historyResults(for: "portal").map(\.title), ["Personal Portal"])
        XCTAssertEqual(
            store.requestSitePermission(kind: .camera, origin: origin, profileID: personalProfileID),
            .allow
        )

        XCTAssertTrue(store.switchProfile(workProfile.id))
        XCTAssertEqual(store.historyResults(for: "portal").map(\.title), ["Work Portal"])
        XCTAssertEqual(
            store.requestSitePermission(kind: .camera, origin: origin, profileID: workProfile.id),
            .ask
        )
    }

    func testActiveProfileSpacesExcludeOtherProfilesAndPrivateSpaces() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let personalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let personalResearchSpace = store.createSpace(name: "Personal Research", profileID: personalProfileID)
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private Vault", profileID: privateProfile.id)
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpaceID = try XCTUnwrap(store.selectedSpaceID)

        XCTAssertTrue(store.switchProfile(personalProfileID))

        XCTAssertEqual(
            Set(store.activeProfileSpaces.map(\.id)),
            Set([personalSpaceID, personalResearchSpace.id])
        )
        XCTAssertFalse(store.activeProfileSpaces.contains { $0.id == privateSpace.id })
        XCTAssertFalse(store.activeProfileSpaces.contains { $0.id == workSpaceID })

        XCTAssertTrue(store.switchProfile(workProfile.id))
        XCTAssertEqual(store.activeProfileSpaces.map(\.id), [workSpaceID])
        XCTAssertFalse(store.activeProfileSpaces.contains { $0.profileID == privateProfile.id })
    }

    func testCommandBarProfileResultSwitchesPersistentProfiles() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let workProfile = store.createPersistentProfile(name: "Work")
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)
        XCTAssertTrue(store.switchProfile(personalProfileID))

        let results = store.commandBarResults(
            for: "work",
            openTabLimit: 0,
            profileLimit: 5,
            historyLimit: 0
        )
        let result = try XCTUnwrap(results.first)
        guard case .profile(let matchedProfile) = result else {
            return XCTFail("Expected a profile command bar result.")
        }
        XCTAssertEqual(matchedProfile.id, workProfile.id)
        let privateResults = store.commandBarResults(
            for: "private",
            openTabLimit: 0,
            profileLimit: 5,
            historyLimit: 0
        )
        XCTAssertFalse(privateResults.contains { result in
            if case .profile(let profile) = result {
                return profile.id == privateProfile.id
            }
            return false
        })

        store.showCommandBar()
        store.activateCommandBarResult(result)

        XCTAssertEqual(store.activeProfile?.id, workProfile.id)
        XCTAssertFalse(store.isCommandBarPresented)
    }

    func testCommandBarOpenTabResultsFollowActiveProfile() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let personalTab = try XCTUnwrap(store.createTab(
            title: "Shared Docs",
            url: URL(string: "https://personal.example/docs")
        ))
        let workProfile = store.createPersistentProfile(name: "Work")
        let workTab = try XCTUnwrap(store.createTab(
            title: "Shared Docs",
            url: URL(string: "https://work.example/docs")
        ))

        XCTAssertTrue(store.switchProfile(personalProfileID))
        let personalResults = store.commandBarResults(
            for: "docs",
            openTabLimit: 5,
            profileLimit: 0,
            historyLimit: 0
        )

        XCTAssertEqual(personalResults.map(\.id), ["tab-\(personalTab.id.uuidString)"])

        XCTAssertTrue(store.switchProfile(workProfile.id))
        let workResults = store.commandBarResults(
            for: "docs",
            openTabLimit: 5,
            profileLimit: 0,
            historyLimit: 0
        )

        XCTAssertEqual(workResults.map(\.id), ["tab-\(workTab.id.uuidString)"])
    }

    func testCommandBarHistoryResultOpensThroughStoreOpenPath() throws {
        let store = BrowserStore()
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let url = URL(string: "https://user:pass@docs.example.com/guide?view=reader&token=fixture#notes")!
        let normalizedURL = URL(string: "https://docs.example.com/guide?view=reader")!
        store.recordHistoryVisit(
            title: "Docs Guide",
            url: url,
            profileID: profileID,
            date: Date(timeIntervalSince1970: 10)
        )
        store.showCommandBar()

        let result = try XCTUnwrap(store.commandBarResults(for: "guide", openTabLimit: 0).first)
        guard case .history(let entry) = result else {
            return XCTFail("Expected a history command bar result.")
        }
        let tabCount = store.tabs.count

        store.activateCommandBarResult(.history(entry))

        XCTAssertEqual(store.tabs.count, tabCount + 1)
        XCTAssertEqual(store.activeTab?.url, normalizedURL)
        XCTAssertFalse(store.isCommandBarPresented)
    }

    func testCommandBarIncludesAvailableBrowserActionResults() throws {
        let store = BrowserStore()
        _ = store.createTab(title: "Docs", url: URL(string: "https://docs.example.com")!)

        let reloadResult = try XCTUnwrap(store.commandBarResults(
            for: "reload",
            openTabLimit: 0,
            historyLimit: 0,
            browserActionAvailability: CommandRouter.BrowserActionAvailability(
                canReload: true,
                canCloseTab: true
            )
        ).first)

        XCTAssertEqual(reloadResult.title, "Reload")
        XCTAssertEqual(reloadResult.subtitle, "Current page")
        XCTAssertEqual(reloadResult.kindLabel, "Action")
        guard case .browserAction(let action) = reloadResult else {
            return XCTFail("Expected a browser action command bar result.")
        }
        XCTAssertEqual(action.action, .reload)
    }

    func testUnavailableBrowserActionsAreNotSuggested() {
        let store = BrowserStore()

        let results = store.commandBarResults(
            for: "back",
            openTabLimit: 0,
            historyLimit: 0,
            browserActionAvailability: CommandRouter.BrowserActionAvailability(canGoBack: false)
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testCommandBarCloseTabActionClosesSelectedTab() throws {
        let store = BrowserStore()
        _ = store.createTab(title: "Docs", url: URL(string: "https://docs.example.com")!)
        let selectedTabID = try XCTUnwrap(store.selectedTabID)
        let tabCount = store.tabs.count
        store.showCommandBar()

        store.submitCommandInput("close tab")

        XCTAssertEqual(store.tabs.count, tabCount - 1)
        XCTAssertFalse(store.tabs.contains { $0.id == selectedTabID })
        XCTAssertFalse(store.isCommandBarPresented)
    }

    func testUnavailableBrowserActionPublishesNonSensitiveMessage() {
        let store = BrowserStore()
        store.showCommandBar()

        store.submitCommandInput("back")

        XCTAssertEqual(store.lastUserMessage, "Back is unavailable for the current page.")
        XCTAssertFalse(store.isCommandBarPresented)
    }

    func testExplicitHTTPNavigationAttemptsHTTPSFirst() throws {
        let store = BrowserStore()
        let initialTabCount = store.tabs.count
        let url = URL(string: "http://user:pass@example.com/private?token=secret#frag")!
        let upgradedURL = URL(string: "https://user:pass@example.com/private?token=secret#frag")!

        store.open(url)

        XCTAssertEqual(store.tabs.count, initialTabCount + 1)
        XCTAssertEqual(store.activeTab?.url, upgradedURL)
        XCTAssertEqual(store.activeTab?.restorationMetadata.pendingHTTPFallbackURL, url)
        XCTAssertNil(store.lastUserMessage)
    }

    func testHTTPSUpgradeFallbackPublishesSanitizedHTTPStatusMessage() {
        let store = BrowserStore()
        let url = URL(string: "http://user:pass@example.com/private?token=secret#frag")!

        store.open(url)
        store.updateActiveTabFromWebView(title: "HTTP Page", url: url, isLoading: false)

        XCTAssertEqual(store.activeTab?.url, url)
        XCTAssertNil(store.activeTab?.restorationMetadata.pendingHTTPFallbackURL)
        XCTAssertEqual(store.lastUserMessage, URLSecurityPolicy.insecureTransportMessage)
        for sensitiveComponent in ["user", "pass", "private", "token", "secret", "frag"] {
            XCTAssertFalse(store.lastUserMessage?.contains(sensitiveComponent) ?? true, sensitiveComponent)
        }
    }

    func testHTTPSUpgradeSuccessClearsPendingFallback() {
        let store = BrowserStore()
        let httpURL = URL(string: "http://example.com/path?view=reader")!
        let httpsURL = URL(string: "https://example.com/path?view=reader")!

        store.open(httpURL)
        XCTAssertEqual(store.activeTab?.restorationMetadata.pendingHTTPFallbackURL, httpURL)

        store.updateActiveTabFromWebView(title: "Secure Page", url: httpsURL, isLoading: false)

        XCTAssertEqual(store.activeTab?.url, httpsURL)
        XCTAssertNil(store.activeTab?.restorationMetadata.pendingHTTPFallbackURL)
        XCTAssertNil(store.lastUserMessage)
    }

    func testLocalHTTPNavigationDoesNotPublishInsecureStatusMessage() {
        let store = BrowserStore()
        let url = URL(string: "http://localhost:3000")!

        store.open(url)

        XCTAssertEqual(store.activeTab?.url, url)
        XCTAssertNil(store.activeTab?.restorationMetadata.pendingHTTPFallbackURL)
        XCTAssertNil(store.lastUserMessage)
    }

    func testWebViewHTTPUpdatePublishesSameInsecureStatusMessage() {
        let store = BrowserStore()
        let url = URL(string: "http://user:pass@example.com/private?auth=secret#fragment")!

        store.updateActiveTabFromWebView(title: "HTTP Page", url: url, isLoading: false)

        XCTAssertEqual(store.lastUserMessage, URLSecurityPolicy.insecureTransportMessage)
        for sensitiveComponent in ["user", "pass", "private", "auth", "secret", "fragment"] {
            XCTAssertFalse(store.lastUserMessage?.contains(sensitiveComponent) ?? true, sensitiveComponent)
        }
    }

    func testWebViewHTTPSUpdateClearsStaleInsecureStatusMessage() {
        let store = BrowserStore()
        let httpURL = URL(string: "http://example.com")!

        store.open(httpURL)
        store.updateActiveTabFromWebView(title: "HTTP Page", url: httpURL, isLoading: false)
        XCTAssertEqual(store.lastUserMessage, URLSecurityPolicy.insecureTransportMessage)

        store.updateActiveTabFromWebView(
            title: "Secure Page",
            url: URL(string: "https://example.com")!,
            isLoading: false
        )

        XCTAssertNil(store.lastUserMessage)
    }

    func testSelectingSecureTabClearsStaleInsecureStatusMessage() throws {
        let store = BrowserStore()
        let secureTab = try XCTUnwrap(store.createTab(title: "Secure", url: URL(string: "https://example.com")!))
        let httpURL = URL(string: "http://example.com")!

        store.open(httpURL)
        store.updateActiveTabFromWebView(title: "HTTP Page", url: httpURL, isLoading: false)
        let insecureTabID = try XCTUnwrap(store.selectedTabID)
        XCTAssertEqual(store.lastUserMessage, URLSecurityPolicy.insecureTransportMessage)

        store.selectTab(secureTab.id)
        XCTAssertNil(store.lastUserMessage)

        store.selectTab(insecureTabID)
        XCTAssertEqual(store.lastUserMessage, URLSecurityPolicy.insecureTransportMessage)
    }

    func testSecurePageStatusRefreshPreservesUnrelatedUserMessage() {
        let store = BrowserStore()

        store.publishStatusMessage("Download failed.")
        store.updateActiveTabFromWebView(
            title: "Secure Page",
            url: URL(string: "https://example.com")!,
            isLoading: false
        )

        XCTAssertEqual(store.lastUserMessage, "Download failed.")
    }

    func testExplicitStatusMessagesCanBeDismissed() {
        let store = BrowserStore()

        store.publishStatusMessage("  Blocked unsafe URL scheme: javascript.  ")
        XCTAssertEqual(store.lastUserMessage, "Blocked unsafe URL scheme: javascript.")

        store.dismissLastUserMessage()

        XCTAssertNil(store.lastUserMessage)
    }

    func testRestoredHistoryEntriesAppearInCommandBarSearch() throws {
        let snapshot = SessionSnapshotFactory.initial()
        let profileID = try XCTUnwrap(snapshot.profiles.first?.id)
        let restoredEntry = BrowserHistoryEntry(
            profileID: profileID,
            url: URL(string: "https://docs.example.com/restored?view=reader")!,
            title: "Restored Docs",
            lastVisitedAt: Date(timeIntervalSince1970: 10)
        )
        let store = BrowserStore(
            snapshot: snapshot,
            localHistoryStore: LocalHistoryStore(entries: [restoredEntry])
        )

        let result = try XCTUnwrap(store.commandBarResults(for: "restored", openTabLimit: 0).first)

        guard case .history(let entry) = result else {
            return XCTFail("Expected a restored history result.")
        }
        XCTAssertEqual(entry.id, restoredEntry.id)
        XCTAssertEqual(entry.profileID, profileID)
    }

    func testHistoryMutationsPersistThroughConfiguredWriter() throws {
        let spy = LocalHistoryPersistenceSpy()
        let store = BrowserStore(localHistoryPersistence: spy)
        let profileID = try XCTUnwrap(store.activeProfile?.id)

        let entry = try XCTUnwrap(store.recordHistoryVisit(
            title: "Saved History",
            url: URL(string: "https://history.example/saved")!,
            profileID: profileID
        ))

        XCTAssertEqual(spy.savedEntries.last?.map(\.id), [entry.id])
        XCTAssertEqual(spy.savedProfiles.last?.map(\.id), store.profiles.map(\.id))

        XCTAssertTrue(store.deleteHistoryEntry(entry.id, profileID: profileID))
        XCTAssertEqual(spy.savedEntries.last, [])
    }

    func testClearHistoryOnlyRemovesActiveProfileEntries() throws {
        let spy = LocalHistoryPersistenceSpy()
        let store = BrowserStore(localHistoryPersistence: spy)
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let personalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let workProfile = store.createProfile(name: "Work")
        _ = store.createSpace(name: "Work", profileID: workProfile.id)

        let personalEntry = try XCTUnwrap(store.recordHistoryVisit(
            title: "Personal Docs",
            url: URL(string: "https://personal.example/docs")!,
            profileID: personalProfileID,
            date: Date(timeIntervalSince1970: 10)
        ))
        let workEntry = try XCTUnwrap(store.recordHistoryVisit(
            title: "Work Docs",
            url: URL(string: "https://work.example/docs")!,
            profileID: workProfile.id,
            date: Date(timeIntervalSince1970: 20)
        ))
        store.selectSpace(personalSpaceID)

        let removedCount = store.clearHistoryForActiveProfile()

        XCTAssertEqual(removedCount, 1)
        XCTAssertFalse(store.historyEntries.contains { $0.id == personalEntry.id })
        XCTAssertTrue(store.historyEntries.contains { $0.id == workEntry.id })
        XCTAssertEqual(spy.savedEntries.last?.map(\.id), [workEntry.id])
        XCTAssertEqual(store.lastUserMessage, "History cleared for this profile.")
    }

    func testSitePermissionRequestPublishesSanitizedPendingState() {
        let store = BrowserStore()
        let profileID = store.activeProfile!.id
        let origin = SitePermissionOrigin(
            url: URL(string: "https://user:pass@example.com/private/file?token=secret#frag")!
        )

        let result = store.requestSitePermission(kind: .camera, origin: origin, profileID: profileID)

        XCTAssertEqual(result, .ask)
        XCTAssertEqual(store.pendingSitePermissionRequest?.origin.displayString, "example.com")
        XCTAssertEqual(store.pendingSitePermissionRequest?.promptMessage, "example.com wants to use camera.")
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("user") ?? true)
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("token") ?? true)
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("/private") ?? true)
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("frag") ?? true)
    }

    func testResolvingSitePermissionStoresAllowDecisionForProfileOrigin() {
        let store = BrowserStore()
        let profileID = store.activeProfile!.id
        let origin = SitePermissionOrigin(url: URL(string: "https://example.com")!)!
        _ = store.requestSitePermission(kind: .popupWindow, origin: origin, profileID: profileID)
        let requestID = store.pendingSitePermissionRequest!.id

        let result = store.resolvePendingSitePermission(.allow, requestID: requestID)

        XCTAssertEqual(result, .allow)
        XCTAssertNil(store.pendingSitePermissionRequest)
        XCTAssertEqual(store.sitePermissionSettings.count, 1)
        XCTAssertEqual(store.sitePermissionSettings.first?.kind, .popupWindow)
        XCTAssertEqual(store.sitePermissionSettings.first?.origin.serializedOrigin, "https://example.com")
        XCTAssertEqual(store.sitePermissionSettings.first?.decision, .allow)
        XCTAssertEqual(store.sitePermissionSettings.first?.persistsBeyondSession, true)
        XCTAssertEqual(
            store.requestSitePermission(kind: .popupWindow, origin: origin, profileID: profileID),
            .allow
        )
    }

    func testRestoredSitePermissionSettingsAreLoadedFromSnapshot() throws {
        var snapshot = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 11))
        let profileID = try XCTUnwrap(snapshot.profiles.first?.id)
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://blocked.example")!))
        snapshot.sitePermissionSettings = [
            SitePermissionSetting(
                kind: .camera,
                origin: origin,
                profileID: profileID,
                decision: .deny,
                persistsBeyondSession: true,
                updatedAt: Date(timeIntervalSince1970: 12)
            )
        ]
        let store = BrowserStore(snapshot: snapshot)

        let result = store.requestSitePermission(kind: .camera, origin: origin, profileID: profileID)

        XCTAssertEqual(result, .deny(reason: "Camera is blocked for this site."))
        XCTAssertNil(store.pendingSitePermissionRequest)
        XCTAssertEqual(store.sitePermissionSettings, snapshot.sitePermissionSettings)
    }

    func testResolvingSitePermissionPersistsThroughConfiguredWriter() throws {
        let spy = BrowserStoreSessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://persisted.example")!))
        _ = store.requestSitePermission(kind: .popupWindow, origin: origin, profileID: profileID)
        let requestID = try XCTUnwrap(store.pendingSitePermissionRequest?.id)

        _ = store.resolvePendingSitePermission(.allow, requestID: requestID)

        let savedSettings = try XCTUnwrap(spy.savedSnapshots.last?.sitePermissionSettings)
        XCTAssertEqual(savedSettings.count, 1)
        XCTAssertEqual(savedSettings.first?.origin.serializedOrigin, "https://persisted.example")
        XCTAssertEqual(savedSettings.first?.decision, .allow)
        XCTAssertEqual(spy.fallbacks.count, spy.savedSnapshots.count)
    }

    func testUnsupportedPermissionIsDeniedWithoutPendingState() {
        let store = BrowserStore()

        let result = store.requestSitePermission(
            kind: .notifications,
            origin: SitePermissionOrigin(url: URL(string: "https://example.com")!)
        )

        XCTAssertEqual(
            result,
            .deny(reason: "Notifications permissions are not supported by Meridian on this WebKit version.")
        )
        XCTAssertNil(store.pendingSitePermissionRequest)
        XCTAssertEqual(
            store.lastUserMessage,
            "Notifications permissions are not supported by Meridian on this WebKit version."
        )
    }

    func testManualSitePermissionDecisionUpdatesStoredDecisionAndPersists() throws {
        let spy = BrowserStoreSessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://manage.example/settings")!))

        let didSet = store.setSitePermissionDecision(
            .allow,
            for: .camera,
            origin: origin,
            profileID: profileID,
            date: Date(timeIntervalSince1970: 40)
        )

        XCTAssertTrue(didSet)
        XCTAssertEqual(store.sitePermissionDecision(for: .camera, origin: origin, profileID: profileID), .allow)
        XCTAssertEqual(store.sitePermissionSettings.count, 1)
        XCTAssertEqual(store.sitePermissionSettings.first?.kind, .camera)
        XCTAssertEqual(store.sitePermissionSettings.first?.origin.serializedOrigin, "https://manage.example")
        XCTAssertEqual(store.sitePermissionSettings.first?.decision, .allow)
        XCTAssertEqual(store.sitePermissionSettings.first?.persistsBeyondSession, true)
        XCTAssertEqual(spy.savedSnapshots.last?.sitePermissionSettings.count, 1)
        XCTAssertEqual(store.lastUserMessage, "Camera allowed for manage.example.")
    }

    func testManualSitePermissionAskDecisionRemovesStoredOverride() throws {
        let spy = BrowserStoreSessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://reset.example")!))

        XCTAssertTrue(store.setSitePermissionDecision(.deny, for: .popupWindow, origin: origin, profileID: profileID))

        let didReset = store.setSitePermissionDecision(
            .ask,
            for: .popupWindow,
            origin: origin,
            profileID: profileID,
            date: Date(timeIntervalSince1970: 41)
        )

        XCTAssertTrue(didReset)
        XCTAssertEqual(store.sitePermissionDecision(for: .popupWindow, origin: origin, profileID: profileID), .ask)
        XCTAssertTrue(store.sitePermissionSettings.isEmpty)
        XCTAssertEqual(spy.savedSnapshots.last?.sitePermissionSettings.count, 0)
        XCTAssertEqual(store.lastUserMessage, "Pop-up windows will ask for reset.example.")
    }

    func testManualSitePermissionRejectsUnsupportedAndConfigurationOnlyKinds() throws {
        let store = BrowserStore()
        let profileID = try XCTUnwrap(store.activeProfile?.id)
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://unsupported.example")!))

        XCTAssertFalse(store.setSitePermissionDecision(.allow, for: .notifications, origin: origin, profileID: profileID))
        XCTAssertEqual(
            store.lastUserMessage,
            "Notifications permissions are not supported by Meridian on this WebKit version."
        )

        XCTAssertFalse(store.setSitePermissionDecision(.allow, for: .autoplay, origin: origin, profileID: profileID))
        XCTAssertEqual(
            store.lastUserMessage,
            "Autoplay is controlled by browser configuration and cannot be changed per site."
        )
        XCTAssertTrue(store.sitePermissionSettings.isEmpty)
    }

    func testManualPrivateSitePermissionDecisionIsSessionOnly() throws {
        let store = BrowserStore()
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private", profileID: privateProfile.id)
        _ = store.createTab(
            title: "Private",
            url: URL(string: "https://private-permission.example")!,
            in: privateSpace.id
        )
        let origin = try XCTUnwrap(SitePermissionOrigin(url: URL(string: "https://private-permission.example")!))

        XCTAssertTrue(store.setSitePermissionDecision(.allow, for: .microphone, origin: origin, profileID: privateProfile.id))

        let setting = try XCTUnwrap(store.sitePermissionSettings.first)
        XCTAssertEqual(setting.profileID, privateProfile.id)
        XCTAssertEqual(setting.decision, .allow)
        XCTAssertEqual(setting.persistsBeyondSession, false)
        XCTAssertTrue(store.persistentSnapshot().sitePermissionSettings.isEmpty)
        XCTAssertEqual(
            store.lastUserMessage,
            "Microphone allowed for private-permission.example for this private session."
        )
    }

    func testExternalURLCreatesPendingConfirmationInsteadOfOpeningTab() {
        let store = BrowserStore()
        let initialTabCount = store.tabs.count
        let externalURL = URL(string: "mailto:hello@example.com")!

        store.open(externalURL)

        XCTAssertEqual(store.tabs.count, initialTabCount)
        XCTAssertEqual(store.pendingURLConfirmation?.kind, .externalApplication)
        XCTAssertEqual(store.pendingURLConfirmation?.url, externalURL)
        XCTAssertEqual(store.lastUserMessage, URLConfirmationRequest.Kind.externalApplication.pendingMessage)
    }

    func testApprovingPendingConfirmationRevalidatesAndOpensURL() {
        let store = BrowserStore()
        let externalURL = URL(string: "mailto:hello@example.com")!
        var openedURL: URL?

        store.open(externalURL)
        let didOpen = store.approvePendingURLConfirmation { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(didOpen)
        XCTAssertEqual(openedURL, externalURL)
        XCTAssertNil(store.pendingURLConfirmation)
        XCTAssertEqual(store.lastUserMessage, URLConfirmationRequest.Kind.externalApplication.approvedMessage)
    }

    func testCancelingPendingConfirmationDoesNotOpenURL() {
        let store = BrowserStore()
        let fileURL = URL(fileURLWithPath: "/tmp/test.html")

        store.requestURLConfirmation(kind: .localFile, url: fileURL, sourceURL: URL(string: "https://example.com"))

        XCTAssertEqual(store.pendingURLConfirmation?.sourceDescription, "example.com")

        store.cancelPendingURLConfirmation()

        XCTAssertNil(store.pendingURLConfirmation)
        XCTAssertEqual(store.lastUserMessage, URLConfirmationRequest.Kind.localFile.cancelledMessage)
    }

    func testPendingExternalURLConfirmationStoresSanitizedSourceContext() throws {
        let store = BrowserStore()
        let externalURL = URL(string: "mailto:help@meridian.test")!
        let sourceURL = URL(string: "https://user:pass@example.com/private/start?token=fixture#frag")!

        store.requestURLConfirmation(kind: .externalApplication, url: externalURL, sourceURL: sourceURL)

        let request = try XCTUnwrap(store.pendingURLConfirmation)
        XCTAssertEqual(request.url, externalURL)
        XCTAssertEqual(request.sourceDescription, "example.com")
        for sensitiveComponent in ["user", "pass", "/private", "token", "fixture", "frag"] {
            XCTAssertFalse(request.confirmationMessage.contains(sensitiveComponent), sensitiveComponent)
            XCTAssertFalse(request.sourceDescription.contains(sensitiveComponent), sensitiveComponent)
        }
    }

    func testPendingLocalFileConfirmationPreservesTargetAndSanitizesSourceContext() throws {
        let store = BrowserStore()
        let fileURL = URL(fileURLWithPath: "/tmp/report.html")
        let sourceURL = URL(string: "https://user:pass@example.com/private/start?token=fixture#frag")!
        var openedURL: URL?

        store.requestURLConfirmation(kind: .localFile, url: fileURL, sourceURL: sourceURL)

        let request = try XCTUnwrap(store.pendingURLConfirmation)
        XCTAssertEqual(request.url, fileURL)
        XCTAssertEqual(request.sourceDescription, "example.com")

        let didOpen = store.approvePendingURLConfirmation { url in
            openedURL = url
            return true
        }

        XCTAssertTrue(didOpen)
        XCTAssertEqual(openedURL, fileURL)
        XCTAssertNil(store.pendingURLConfirmation)
    }

    func testBlockedDownloadCompletesWithoutPendingPrompt() {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "installer.pkg",
            sourceURL: URL(string: "https://example.com/installer.pkg")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }

        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(store.lastUserMessage, "Downloads ending in .pkg require a dedicated installer flow.")
    }

    func testPendingDownloadConfirmationStoresSanitizedSourceMetadata() throws {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "report.pdf",
            sourceURL: URL(string: "https://user:password@example.com/private/source-name.zip?token=secret#fragment")
        )
        var completionCalled = false

        store.requestDownloadConfirmation(request) { _ in
            completionCalled = true
        }

        let pendingRequest = try XCTUnwrap(store.pendingDownloadConfirmation)
        XCTAssertFalse(completionCalled)
        XCTAssertEqual(pendingRequest.sourceDescription, "example.com")
        XCTAssertEqual(pendingRequest.sourceMetadata.quarantineOrigin, "https://example.com")

        let exposedState = [
            pendingRequest.sourceDescription,
            pendingRequest.sourceMetadata.quarantineOrigin ?? "",
            pendingRequest.confirmationMessage
        ].joined(separator: "\n")
        XCTAssertFalse(exposedState.contains("user"))
        XCTAssertFalse(exposedState.contains("password"))
        XCTAssertFalse(exposedState.contains("private"))
        XCTAssertFalse(exposedState.contains("source-name"))
        XCTAssertFalse(exposedState.contains("token"))
        XCTAssertFalse(exposedState.contains("secret"))
        XCTAssertFalse(exposedState.contains("fragment"))
    }

    func testRiskyDownloadApprovalUsesSafeNonExistingDestination() throws {
        let store = BrowserStore()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let existingURL = temporaryDirectory.appendingPathComponent("script.sh")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data())
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "../script.sh",
            sourceURL: URL(string: "https://example.com/script.sh")
        )
        var completedURL: URL?

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }
        let didApprove = store.approvePendingDownloadConfirmation(destination: existingURL)

        XCTAssertTrue(didApprove)
        XCTAssertEqual(completedURL?.lastPathComponent, "script 2.sh")
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(store.lastUserMessage, "Download will be saved as script 2.sh.")
    }

    func testDownloadAlertDismissalDuringDestinationSelectionKeepsPendingDownload() throws {
        let store = BrowserStore()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        let selectedURL = temporaryDirectory.appendingPathComponent("archive.zip")
        var completedURL: URL?
        var completionCallCount = 0

        store.requestDownloadConfirmation(request) { destinationURL in
            completionCallCount += 1
            completedURL = destinationURL
        }

        XCTAssertTrue(store.beginPendingDownloadDestinationSelection())
        XCTAssertTrue(store.isChoosingDownloadDestination)

        store.dismissPendingDownloadConfirmationAlert()

        XCTAssertEqual(completionCallCount, 0)
        XCTAssertNotNil(store.pendingDownloadConfirmation)
        XCTAssertTrue(store.isChoosingDownloadDestination)

        let didApprove = store.approvePendingDownloadConfirmation(destination: selectedURL)

        XCTAssertTrue(didApprove)
        XCTAssertEqual(completionCallCount, 1)
        XCTAssertEqual(completedURL, selectedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertFalse(store.isChoosingDownloadDestination)
    }

    func testDownloadAlertDismissalWithoutDestinationSelectionCancelsDownload() {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }

        store.dismissPendingDownloadConfirmationAlert()

        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertFalse(store.isChoosingDownloadDestination)
        XCTAssertEqual(store.lastUserMessage, request.cancelledMessage)
    }

    func testLowRiskDownloadRejectsDestinationChangedToRiskyExtension() throws {
        let store = BrowserStore()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }
        let didApprove = store.approvePendingDownloadConfirmation(
            destination: temporaryDirectory.appendingPathComponent("renamed.sh")
        )

        XCTAssertFalse(didApprove)
        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(
            store.lastUserMessage,
            "Download destination requires confirmation. Downloads ending in .sh can execute code."
        )
    }

    func testCancelingPendingDownloadCompletesWithNilDestination() {
        let store = BrowserStore()
        let request = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "archive.zip",
            sourceURL: URL(string: "https://example.com/archive.zip")
        )
        var completedURL: URL? = URL(fileURLWithPath: "/tmp/should-not-save")

        store.requestDownloadConfirmation(request) { destinationURL in
            completedURL = destinationURL
        }
        store.cancelPendingDownloadConfirmation()

        XCTAssertNil(completedURL)
        XCTAssertNil(store.pendingDownloadConfirmation)
        XCTAssertEqual(store.lastUserMessage, request.cancelledMessage)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class LocalHistoryPersistenceSpy: LocalHistoryPersisting {
    var loadedProfiles: [[BrowserProfile]] = []
    var savedEntries: [[BrowserHistoryEntry]] = []
    var savedProfiles: [[BrowserProfile]] = []

    func loadHistory(profiles: [BrowserProfile]) -> LocalHistoryPersistenceLoadResult {
        loadedProfiles.append(profiles)
        return LocalHistoryPersistenceLoadResult(entries: [])
    }

    func saveHistory(_ entries: [BrowserHistoryEntry], profiles: [BrowserProfile]) throws {
        savedEntries.append(entries)
        savedProfiles.append(profiles)
    }
}

private final class BrowserStoreSessionPersistenceSpy: SessionSnapshotPersisting {
    var savedSnapshots: [BrowserSessionSnapshot] = []
    var fallbacks: [BrowserSessionSnapshot] = []

    func saveSnapshot(_ snapshot: BrowserSessionSnapshot, fallback: BrowserSessionSnapshot) throws {
        savedSnapshots.append(snapshot)
        fallbacks.append(fallback)
    }
}
