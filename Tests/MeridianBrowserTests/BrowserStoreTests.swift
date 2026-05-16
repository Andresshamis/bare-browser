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

    func testCreatesNestedFoldersWithStableParentRelationships() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let parent = try XCTUnwrap(store.createFolder(name: "Research", in: spaceID))
        let child = try XCTUnwrap(store.createFolder(name: "Sources", in: spaceID, parentFolderID: parent.id))

        let updatedParent = try XCTUnwrap(store.folders.first { $0.id == parent.id })
        let updatedChild = try XCTUnwrap(store.folders.first { $0.id == child.id })
        let updatedSpace = try XCTUnwrap(store.spaces.first { $0.id == spaceID })

        XCTAssertEqual(updatedChild.parentSpaceID, spaceID)
        XCTAssertEqual(updatedChild.parentFolderID, parent.id)
        XCTAssertEqual(updatedParent.childFolderIDs, [child.id])
        XCTAssertFalse(updatedSpace.folderIDs.contains(child.id))
    }

    func testMoveTabIntoNestedFolderUpdatesMembershipAndOrder() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let parent = try XCTUnwrap(store.createFolder(name: "Research", in: spaceID))
        let child = try XCTUnwrap(store.createFolder(name: "Sources", in: spaceID, parentFolderID: parent.id))
        let first = try XCTUnwrap(store.createTab(title: "First", in: spaceID, folderID: child.id))
        let second = try XCTUnwrap(store.createTab(title: "Second", in: spaceID))
        let third = try XCTUnwrap(store.createTab(title: "Third", in: spaceID))

        XCTAssertTrue(store.moveTab(third.id, toFolder: child.id, before: first.id))
        XCTAssertTrue(store.moveTab(second.id, toFolder: child.id))

        let updatedChild = try XCTUnwrap(store.folders.first { $0.id == child.id })
        let updatedSecond = try XCTUnwrap(store.tabs.first { $0.id == second.id })
        let updatedThird = try XCTUnwrap(store.tabs.first { $0.id == third.id })
        let updatedSpace = try XCTUnwrap(store.spaces.first { $0.id == spaceID })

        XCTAssertEqual(updatedChild.tabIDs, [third.id, first.id, second.id])
        XCTAssertEqual(updatedSecond.parentFolderID, child.id)
        XCTAssertEqual(updatedThird.parentFolderID, child.id)
        XCTAssertFalse(updatedSpace.regularTabIDs.contains(second.id))
        XCTAssertFalse(updatedSpace.regularTabIDs.contains(third.id))
    }

    func testCreatedSpacesDefaultToDotSymbol() {
        let store = BrowserStore()

        let space = store.createSpace(name: "Work")

        XCTAssertEqual(space.symbolName, BrowserSpace.defaultSymbolName)
    }

    func testCreatedSpacesDefaultToSelectedSpaceProfile() throws {
        let store = BrowserStore()
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpace = store.createSpace(name: "Work", profileID: workProfile.id)
        store.selectSpace(workSpace.id)

        let projectSpace = store.createSpace(name: "Project")

        XCTAssertEqual(projectSpace.profileID, workProfile.id)
    }

    func testCreatedSpacesDefaultToNeutralMediumDensitySidebarTheme() throws {
        let store = BrowserStore()
        let space = store.createSpace(name: "Focus")

        XCTAssertEqual(space.sidebarAppearance.base.tintOpacity, 0, accuracy: 0.001)
        XCTAssertEqual(space.sidebarAppearance.base.glassOpacity, 0.60, accuracy: 0.001)
        XCTAssertEqual(space.sidebarAppearance.base.colorNoiseLevel, 0, accuracy: 0.001)
        XCTAssertEqual(space.sidebarAppearance.base.colorNoiseScale, 0.30, accuracy: 0.001)
    }

    func testCustomizeSpaceUpdatesNameSymbolAndColor() throws {
        let store = BrowserStore()
        let space = store.createSpace(name: "Work")

        XCTAssertTrue(store.customizeSpace(
            space.id,
            name: " Design ",
            symbolName: "paintpalette.fill",
            colorHex: "#FF375F"
        ))

        let updatedSpace = try XCTUnwrap(store.spaces.first { $0.id == space.id })
        XCTAssertEqual(updatedSpace.name, "Design")
        XCTAssertEqual(updatedSpace.symbolName, "paintpalette.fill")
        XCTAssertEqual(updatedSpace.colorHex, "#FF375F")
    }

    func testOpenSpaceCustomizerCreatesSelectedInternalTab() throws {
        let store = BrowserStore()
        let space = store.createSpace(name: "Design")

        let tab = try XCTUnwrap(store.openSpaceCustomizer(for: space.id))

        XCTAssertEqual(tab.title, "Customize Space")
        XCTAssertNil(tab.url)
        XCTAssertEqual(tab.content, .spaceCustomization(space.id))
        XCTAssertEqual(store.selectedTabID, tab.id)
        XCTAssertEqual(store.selectedSpace?.regularTabIDs.last, tab.id)
    }

    func testOpenSpaceCustomizerReusesExistingCustomizerTab() throws {
        let store = BrowserStore()
        let space = store.createSpace(name: "Design")
        let first = try XCTUnwrap(store.openSpaceCustomizer(for: space.id))
        let second = try XCTUnwrap(store.openSpaceCustomizer(for: space.id))

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.tabs.filter { $0.content == .spaceCustomization(space.id) }.count, 1)
        XCTAssertEqual(store.selectedTabID, first.id)
    }

    func testNavigatingFromSpaceCustomizerConvertsTabToWebContent() throws {
        let store = BrowserStore()
        let space = store.createSpace(name: "Design")
        let tab = try XCTUnwrap(store.openSpaceCustomizer(for: space.id))
        let url = try XCTUnwrap(URL(string: "https://example.com"))

        store.navigateActiveTab(to: url)

        let updatedTab = try XCTUnwrap(store.tabs.first { $0.id == tab.id })
        XCTAssertEqual(updatedTab.content, .web)
        XCTAssertEqual(updatedTab.url, url)
    }

    func testCustomizeSpaceUpdatesProfileAndTabs() throws {
        let store = BrowserStore()
        let space = store.createSpace(name: "Work")
        let tab = try XCTUnwrap(store.createTab(title: "Docs", in: space.id))
        let workProfile = store.createPersistentProfile(name: "Work")

        XCTAssertTrue(store.customizeSpace(
            space.id,
            name: space.name,
            symbolName: space.symbolName,
            colorHex: space.colorHex,
            profileID: workProfile.id
        ))

        XCTAssertEqual(store.spaces.first { $0.id == space.id }?.profileID, workProfile.id)
        XCTAssertEqual(store.tabs.first { $0.id == tab.id }?.profileID, workProfile.id)
        XCTAssertEqual(store.activeProfile?.id, workProfile.id)
    }

    func testCustomizeSpaceUpdatesSidebarAppearanceWithoutChangingTabsOrProfile() throws {
        let spy = BrowserStoreSessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)
        let space = store.createSpace(name: "Work")
        let tab = try XCTUnwrap(store.createTab(title: "Docs", in: space.id))
        let originalProfileID = space.profileID
        let appearance = SidebarAppearance(
            tintSource: .custom,
            tintHex: "#BF5AF2",
            base: SidebarGlassSettings(
                glassOpacity: 0.84,
                tintOpacity: 0.32,
                colorNoiseLevel: 0.46,
                colorNoiseScale: 0.62,
                edgeOpacity: 0.52,
                shadowOpacity: 0.28,
                highlightOpacity: 0.24
            ),
            pinnedOverride: SidebarGlassSettings(
                glassOpacity: 0.72,
                tintOpacity: 0.18,
                colorNoiseLevel: 0.23,
                colorNoiseScale: 0.18,
                edgeOpacity: 0.36,
                shadowOpacity: 0.06,
                highlightOpacity: 0.14
            )
        )

        XCTAssertTrue(store.customizeSpace(
            space.id,
            name: space.name,
            symbolName: space.symbolName,
            colorHex: space.colorHex,
            sidebarAppearance: appearance
        ))

        let updatedSpace = try XCTUnwrap(store.spaces.first { $0.id == space.id })
        let updatedTab = try XCTUnwrap(store.tabs.first { $0.id == tab.id })
        XCTAssertEqual(updatedSpace.sidebarAppearance, appearance)
        XCTAssertEqual(updatedSpace.profileID, originalProfileID)
        XCTAssertEqual(updatedTab.profileID, originalProfileID)
        XCTAssertEqual(spy.savedSnapshots.last?.spaces.first { $0.id == space.id }?.sidebarAppearance, appearance)
    }

    func testSidebarAppearancePinnedSettingsFallsBackToBase() {
        let base = SidebarGlassSettings(
            glassOpacity: 0.8,
            tintOpacity: 0.2,
            edgeOpacity: 0.3,
            shadowOpacity: 0.4,
            highlightOpacity: 0.5
        )
        let appearance = SidebarAppearance(base: base, pinnedOverride: nil)

        XCTAssertEqual(appearance.pinnedSettings, base)
    }

    func testLegacySpaceWithoutSidebarAppearanceDecodesDefault() throws {
        let data = Data("""
        {
          "id": "E7F390AB-B64B-4E32-944E-B2DD8BC85F2E",
          "name": "Legacy",
          "symbolName": "circle.fill",
          "colorHex": "#FF375F",
          "profileID": "A0B97C4C-0E21-4B4E-A09C-B7C8B37C2601",
          "favoriteTabIDs": [],
          "pinnedTabIDs": [],
          "folderIDs": [],
          "regularTabIDs": [],
          "selectedTabID": null,
          "lastActiveDate": 0
        }
        """.utf8)

        let space = try JSONDecoder().decode(BrowserSpace.self, from: data)

        XCTAssertEqual(space.sidebarAppearance, .standard)
    }

    func testLegacyTabWithoutContentDecodesAsWebTab() throws {
        let data = Data("""
        {
          "id": "C9C267E3-C314-4F10-A69D-C03CBA3B533F",
          "title": "Example",
          "url": "https://example.com",
          "parentSpaceID": "E7F390AB-B64B-4E32-944E-B2DD8BC85F2E",
          "isPinned": false,
          "isFavorite": false,
          "profileID": "A0B97C4C-0E21-4B4E-A09C-B7C8B37C2601",
          "lastActiveDate": 0
        }
        """.utf8)

        let tab = try JSONDecoder().decode(BrowserTab.self, from: data)

        XCTAssertEqual(tab.content, .web)
    }

    func testSidebarAppearanceRoundTripsThroughSessionSnapshot() throws {
        let profile = BrowserProfile(name: "Personal")
        let appearance = SidebarAppearance(
            tintSource: .custom,
            tintHex: "#FFB340",
            base: SidebarGlassSettings(
                glassOpacity: 0.91,
                tintOpacity: 0.27,
                colorNoiseLevel: 0.37,
                colorNoiseScale: 0.74,
                edgeOpacity: 0.48,
                shadowOpacity: 0.19,
                highlightOpacity: 0.22
            ),
            pinnedOverride: SidebarGlassSettings(
                glassOpacity: 0.82,
                tintOpacity: 0.21,
                colorNoiseLevel: 0.11,
                colorNoiseScale: 0.27,
                edgeOpacity: 0.31,
                shadowOpacity: 0.08,
                highlightOpacity: 0.18
            )
        )
        let space = BrowserSpace(
            name: "Design",
            sidebarAppearance: appearance,
            profileID: profile.id
        )
        let snapshot = BrowserSessionSnapshot(
            profiles: [profile],
            spaces: [space],
            folders: [],
            tabs: [],
            selectedSpaceID: space.id
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.spaces.first?.sidebarAppearance, appearance)
    }

    func testSetProfileRejectsPrivateProfiles() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let originalProfileID = try XCTUnwrap(store.selectedSpace?.profileID)
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)

        XCTAssertFalse(store.setProfile(privateProfile.id, forSpace: spaceID))

        XCTAssertEqual(store.selectedSpace?.profileID, originalProfileID)
    }

    func testLoadedLegacyDefaultSpaceSymbolsNormalizeToDot() throws {
        let profile = BrowserProfile(name: "Personal")
        let legacyGridSpace = BrowserSpace(
            name: "Legacy",
            symbolName: "circle.grid.2x2.fill",
            profileID: profile.id
        )
        let legacySeedSpace = BrowserSpace(
            name: "Today",
            symbolName: "sparkle.magnifyingglass",
            profileID: profile.id
        )
        let snapshot = BrowserSessionSnapshot(
            profiles: [profile],
            spaces: [legacyGridSpace, legacySeedSpace],
            folders: [],
            tabs: [],
            selectedSpaceID: legacyGridSpace.id
        )

        let store = BrowserStore(snapshot: snapshot)

        let loadedGridSpace = try XCTUnwrap(store.spaces.first { $0.id == legacyGridSpace.id })
        let loadedSeedSpace = try XCTUnwrap(store.spaces.first { $0.id == legacySeedSpace.id })
        XCTAssertEqual(loadedGridSpace.symbolName, BrowserSpace.defaultSymbolName)
        XCTAssertEqual(loadedSeedSpace.symbolName, BrowserSpace.defaultSymbolName)
    }

    func testDeleteSpaceRejectsOnlyProfileSpace() throws {
        let store = BrowserStore()
        let spaceID = try XCTUnwrap(store.selectedSpaceID)
        let tabID = try XCTUnwrap(store.selectedTabID)

        XCTAssertFalse(store.canDeleteSpace(spaceID))
        XCTAssertFalse(store.deleteSpace(spaceID))

        XCTAssertEqual(store.spaces.map(\.id), [spaceID])
        XCTAssertEqual(store.tabs.map(\.id), [tabID])
        XCTAssertEqual(store.selectedSpaceID, spaceID)
        XCTAssertEqual(store.selectedTabID, tabID)
    }

    func testDeleteSelectedSpaceRemovesOwnedTabsAndFoldersAndSelectsRemainingSpace() throws {
        let store = BrowserStore()
        let originalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let originalTabID = try XCTUnwrap(store.selectedTabID)
        let doomedSpace = store.createSpace(name: "Doomed")
        let folder = try XCTUnwrap(store.createFolder(name: "Research", in: doomedSpace.id))
        let folderTab = try XCTUnwrap(store.createTab(title: "Foldered", in: doomedSpace.id, folderID: folder.id))
        let regularTab = try XCTUnwrap(store.createTab(title: "Regular", in: doomedSpace.id))
        store.splitViews = [
            SplitViewLayout(tabIDs: [folderTab.id, regularTab.id], fractions: [0.5, 0.5])
        ]

        XCTAssertTrue(store.canDeleteSpace(doomedSpace.id))
        XCTAssertTrue(store.deleteSpace(doomedSpace.id))

        XCTAssertFalse(store.spaces.contains { $0.id == doomedSpace.id })
        XCTAssertFalse(store.tabs.contains { $0.parentSpaceID == doomedSpace.id })
        XCTAssertFalse(store.folders.contains { $0.parentSpaceID == doomedSpace.id })
        XCTAssertFalse(store.tabs.contains { $0.id == folderTab.id || $0.id == regularTab.id })
        XCTAssertTrue(store.splitViews.isEmpty)
        XCTAssertEqual(store.selectedSpaceID, originalSpaceID)
        XCTAssertEqual(store.selectedTabID, originalTabID)
    }

    func testDeleteSpaceUsesGlobalSidebarSpaceCount() throws {
        let store = BrowserStore()
        let personalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpace = store.createSpace(name: "Work", profileID: workProfile.id)

        XCTAssertTrue(store.canDeleteSpace(personalSpaceID))
        XCTAssertTrue(store.deleteSpace(personalSpaceID))

        XCTAssertFalse(store.spaces.contains { $0.id == personalSpaceID })
        XCTAssertEqual(store.selectedSpaceID, workSpace.id)
        XCTAssertFalse(store.canDeleteSpace(workSpace.id))
    }

    func testSelectAdjacentSpaceMovesWithinSidebarSpaces() throws {
        let store = BrowserStore()
        let firstSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let secondSpace = store.createSpace(name: "Second")
        let thirdSpace = store.createSpace(name: "Third")

        store.selectSpace(firstSpaceID)

        XCTAssertFalse(store.selectAdjacentSpace(.previous))
        XCTAssertEqual(store.selectedSpaceID, firstSpaceID)

        XCTAssertTrue(store.selectAdjacentSpace(.next))
        XCTAssertEqual(store.selectedSpaceID, secondSpace.id)

        XCTAssertTrue(store.selectAdjacentSpace(.next))
        XCTAssertEqual(store.selectedSpaceID, thirdSpace.id)

        XCTAssertFalse(store.selectAdjacentSpace(.next))
        XCTAssertEqual(store.selectedSpaceID, thirdSpace.id)

        XCTAssertTrue(store.selectAdjacentSpace(.previous))
        XCTAssertEqual(store.selectedSpaceID, secondSpace.id)
    }

    func testSelectAdjacentSpaceCrossesPersistentProfileBoundaries() throws {
        let store = BrowserStore()
        let firstPersonalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let secondPersonalSpace = store.createSpace(name: "Personal Research")
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpace = store.createSpace(name: "Work", profileID: workProfile.id)

        store.selectSpace(secondPersonalSpace.id)

        XCTAssertTrue(store.selectAdjacentSpace(.next))
        XCTAssertEqual(store.selectedSpaceID, workSpace.id)

        XCTAssertTrue(store.selectAdjacentSpace(.previous))
        XCTAssertEqual(store.selectedSpaceID, secondPersonalSpace.id)

        XCTAssertTrue(store.selectAdjacentSpace(.previous))
        XCTAssertEqual(store.selectedSpaceID, firstPersonalSpaceID)

        XCTAssertFalse(store.selectAdjacentSpace(.previous))
        XCTAssertEqual(store.selectedSpaceID, firstPersonalSpaceID)
    }

    func testBeginNewTabShowsCommandBarWithoutCreatingBlankTab() throws {
        let store = BrowserStore()
        let previousSelectedTabID = store.selectedTabID
        let previousTabCount = store.tabs.count
        let previousFocusRequest = store.commandBarFocusRequest

        store.beginNewTab()

        XCTAssertEqual(store.tabs.count, previousTabCount)
        XCTAssertEqual(store.selectedTabID, previousSelectedTabID)
        XCTAssertTrue(store.isCommandBarPresented)
        XCTAssertEqual(store.commandBarMode, .newTab)
        XCTAssertEqual(store.commandBarFocusRequest, previousFocusRequest + 1)

        store.beginNewTab()

        XCTAssertEqual(store.tabs.count, previousTabCount)
        XCTAssertEqual(store.selectedTabID, previousSelectedTabID)
        XCTAssertTrue(store.isCommandBarPresented)
        XCTAssertEqual(store.commandBarMode, .newTab)
        XCTAssertEqual(store.commandBarFocusRequest, previousFocusRequest + 2)
    }

    func testNewTabAddressSubmissionCreatesSelectedTab() throws {
        let store = BrowserStore()
        let previousSelectedTabID = store.selectedTabID
        let previousTabCount = store.tabs.count

        store.beginNewTab()
        store.submitAddressInput("example.com")

        XCTAssertEqual(store.tabs.count, previousTabCount + 1)
        XCTAssertNotEqual(store.selectedTabID, previousSelectedTabID)
        XCTAssertEqual(store.activeTab?.url, URL(string: "https://example.com")!)
        XCTAssertEqual(store.selectedSpace?.regularTabIDs.last, store.selectedTabID)
        XCTAssertFalse(store.isCommandBarPresented)
        XCTAssertEqual(store.commandBarMode, .address)
    }

    func testNewTabSearchSubmissionCreatesGoogleSearchTabWithoutRedirect() throws {
        let store = BrowserStore()
        let previousSelectedTabID = store.selectedTabID
        let previousTabCount = store.tabs.count

        store.beginNewTab()
        store.submitAddressInput("instagram andrescarnesrd")

        XCTAssertEqual(store.tabs.count, previousTabCount + 1)
        XCTAssertNotEqual(store.selectedTabID, previousSelectedTabID)
        let url = try XCTUnwrap(store.activeTab?.url)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(percentEncoded: false), "www.google.com")
        XCTAssertEqual(url.path(), "/search")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "instagram andrescarnesrd")
        XCTAssertNil(components.queryItems?.first(where: { $0.name == "btnI" }))
        XCTAssertFalse(store.isCommandBarPresented)
        XCTAssertEqual(store.commandBarMode, .address)
    }

    func testLoadedSessionPrunesStaleEmptyTabsWhenRestorableTabExists() throws {
        let date = Date(timeIntervalSince1970: 10)
        let profile = BrowserProfile(name: "Personal", createdAt: date)
        var space = BrowserSpace(name: "Today", profileID: profile.id, lastActiveDate: date)
        let staleEmptyTab = BrowserTab(
            title: "New Tab",
            parentSpaceID: space.id,
            profileID: profile.id,
            lastActiveDate: date.addingTimeInterval(1)
        )
        let restorableTab = BrowserTab(
            title: "Docs",
            url: URL(string: "https://docs.example.com")!,
            parentSpaceID: space.id,
            profileID: profile.id,
            lastActiveDate: date
        )
        space.regularTabIDs = [staleEmptyTab.id, restorableTab.id]
        space.selectedTabID = staleEmptyTab.id
        let snapshot = BrowserSessionSnapshot(
            profiles: [profile],
            spaces: [space],
            folders: [],
            tabs: [staleEmptyTab, restorableTab],
            selectedSpaceID: space.id,
            selectedTabID: staleEmptyTab.id,
            capturedAt: date
        )

        let store = BrowserStore(snapshot: snapshot)

        XCTAssertFalse(store.tabs.contains { $0.id == staleEmptyTab.id })
        XCTAssertEqual(store.tabs.map(\.id), [restorableTab.id])
        XCTAssertEqual(store.selectedTabID, restorableTab.id)
        XCTAssertEqual(store.selectedSpace?.regularTabIDs, [restorableTab.id])
    }

    func testLoadedSessionKeepsSpaceCustomizerTabs() throws {
        let date = Date(timeIntervalSince1970: 10)
        let profile = BrowserProfile(name: "Personal", createdAt: date)
        var space = BrowserSpace(name: "Today", profileID: profile.id, lastActiveDate: date)
        let customizerTab = BrowserTab(
            title: "Customize Space",
            content: .spaceCustomization(space.id),
            parentSpaceID: space.id,
            profileID: profile.id,
            lastActiveDate: date
        )
        space.regularTabIDs = [customizerTab.id]
        space.selectedTabID = customizerTab.id
        let snapshot = BrowserSessionSnapshot(
            profiles: [profile],
            spaces: [space],
            folders: [],
            tabs: [customizerTab],
            selectedSpaceID: space.id,
            selectedTabID: customizerTab.id,
            capturedAt: date
        )

        let store = BrowserStore(snapshot: snapshot)

        XCTAssertEqual(store.tabs.map(\.id), [customizerTab.id])
        XCTAssertEqual(store.activeTab?.content, .spaceCustomization(space.id))
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

    func testPersistentProfileCreationDoesNotCreateOrSelectSpace() throws {
        let spy = BrowserStoreSessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)
        let selectedSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let selectedTabID = try XCTUnwrap(store.selectedTabID)
        let spaceCount = store.spaces.count
        let tabCount = store.tabs.count

        let profile = store.createPersistentProfile(name: "  Work  ")

        XCTAssertEqual(profile.name, "Work")
        XCTAssertFalse(profile.isEphemeral)
        XCTAssertNotNil(profile.persistentWebsiteDataStoreID)
        XCTAssertEqual(store.selectedSpaceID, selectedSpaceID)
        XCTAssertEqual(store.selectedTabID, selectedTabID)
        XCTAssertEqual(store.spaces.count, spaceCount)
        XCTAssertEqual(store.tabs.count, tabCount)

        let savedSnapshot = try XCTUnwrap(spy.savedSnapshots.last)
        XCTAssertTrue(savedSnapshot.profiles.contains { $0.id == profile.id })
        XCTAssertEqual(savedSnapshot.spaces.count, spaceCount)
        XCTAssertEqual(savedSnapshot.tabs.count, tabCount)
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

    func testSpaceProfileKeepsHistoryAndSitePermissionsScoped() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpace = store.createSpace(name: "Work", profileID: workProfile.id)
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

        store.selectSpace(try XCTUnwrap(store.spaces.first { $0.profileID == personalProfileID }?.id))
        XCTAssertEqual(store.historyResults(for: "portal").map(\.title), ["Personal Portal"])
        XCTAssertEqual(
            store.requestSitePermission(kind: .camera, origin: origin, profileID: personalProfileID),
            .allow
        )

        store.selectSpace(workSpace.id)
        XCTAssertEqual(store.historyResults(for: "portal").map(\.title), ["Work Portal"])
        XCTAssertEqual(
            store.requestSitePermission(kind: .camera, origin: origin, profileID: workProfile.id),
            .ask
        )
    }

    func testSidebarSpacesIncludePersistentProfilesAndExcludePrivateSpaces() throws {
        let store = BrowserStore()
        let personalProfileID = try XCTUnwrap(store.activeProfile?.id)
        let personalSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let personalResearchSpace = store.createSpace(name: "Personal Research", profileID: personalProfileID)
        let privateProfile = store.createProfile(name: "Private", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private Vault", profileID: privateProfile.id)
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpace = store.createSpace(name: "Work", profileID: workProfile.id)

        XCTAssertEqual(
            Set(store.sidebarSpaces.map(\.id)),
            Set([personalSpaceID, personalResearchSpace.id, workSpace.id])
        )
        XCTAssertFalse(store.sidebarSpaces.contains { $0.id == privateSpace.id })
        XCTAssertFalse(store.sidebarSpaces.contains { $0.profileID == privateProfile.id })
    }

    func testCommandBarDoesNotReturnProfileSwitchResults() throws {
        let store = BrowserStore()
        _ = store.createPersistentProfile(name: "Work")
        _ = store.createProfile(name: "Private", ephemeral: true)

        XCTAssertTrue(store.commandBarResults(
            for: "work",
            openTabLimit: 0,
            profileLimit: 5,
            historyLimit: 0
        ).isEmpty)
        XCTAssertTrue(store.commandBarResults(
            for: "private",
            openTabLimit: 0,
            profileLimit: 5,
            historyLimit: 0
        ).isEmpty)
    }

    func testCommandBarOpenTabResultsIncludeAllSidebarSpaces() throws {
        let store = BrowserStore()
        let personalTab = try XCTUnwrap(store.createTab(
            title: "Shared Docs",
            url: URL(string: "https://personal.example/docs")
        ))
        let workProfile = store.createPersistentProfile(name: "Work")
        let workSpace = store.createSpace(name: "Work", profileID: workProfile.id)
        let workTab = try XCTUnwrap(store.createTab(
            title: "Shared Docs",
            url: URL(string: "https://work.example/docs"),
            in: workSpace.id
        ))

        let results = store.commandBarResults(
            for: "docs",
            openTabLimit: 5,
            profileLimit: 0,
            historyLimit: 0
        )

        XCTAssertEqual(
            Set(results.map(\.id)),
            Set(["tab-\(personalTab.id.uuidString)", "tab-\(workTab.id.uuidString)"])
        )
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

    func testInactiveWebViewUpdateDoesNotPublishUserFacingStatus() throws {
        let store = BrowserStore()
        let activeTabID = try XCTUnwrap(store.selectedTabID)
        let backgroundTab = try XCTUnwrap(
            store.createTab(title: "Background", url: URL(string: "https://background.example"))
        )
        store.selectTab(activeTabID)

        let backgroundURL = URL(string: "http://background.example/insecure")!
        store.updateTabFromWebView(
            tabID: backgroundTab.id,
            title: "Background HTTP",
            url: backgroundURL,
            isLoading: false,
            securityMessage: URLSecurityPolicy.insecureTransportMessage
        )

        let updatedTab = try XCTUnwrap(store.tabs.first { $0.id == backgroundTab.id })
        XCTAssertEqual(updatedTab.title, "Background HTTP")
        XCTAssertEqual(updatedTab.url, backgroundURL)
        XCTAssertFalse(updatedTab.isLoading)
        XCTAssertNil(store.lastUserMessage)
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
