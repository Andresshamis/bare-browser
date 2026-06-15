import AppKit
import Foundation
@testable import MeridianCore
import XCTest

final class SidebarSpacePagerSelectionTests: XCTestCase {
    func testDoesNotCommitNilScrollPosition() {
        let selectedID = UUID()

        XCTAssertNil(SidebarSpacePagerSelection.committedPageID(
            scrollPositionPageID: nil,
            selectedPageID: .space(selectedID),
            pageIDs: [.space(selectedID)]
        ))
    }

    func testDoesNotCommitAlreadySelectedPage() {
        let selectedID = UUID()

        XCTAssertNil(SidebarSpacePagerSelection.committedPageID(
            scrollPositionPageID: .space(selectedID),
            selectedPageID: .space(selectedID),
            pageIDs: [.space(selectedID)]
        ))
    }

    func testDoesNotCommitUnknownPage() {
        let selectedID = UUID()

        XCTAssertNil(SidebarSpacePagerSelection.committedPageID(
            scrollPositionPageID: .space(UUID()),
            selectedPageID: .space(selectedID),
            pageIDs: [.space(selectedID)]
        ))
    }

    func testCommitsDifferentKnownPage() {
        let selectedID = UUID()
        let nextID = UUID()

        XCTAssertEqual(
            SidebarSpacePagerSelection.committedPageID(
                scrollPositionPageID: .space(nextID),
                selectedPageID: .space(selectedID),
                pageIDs: [.space(selectedID), .space(nextID)]
            ),
            .space(nextID)
        )
    }

    func testCommitsActivityPageBeforeFirstSpace() {
        let selectedID = UUID()

        XCTAssertEqual(
            SidebarSpacePagerSelection.committedPageID(
                scrollPositionPageID: .activity,
                selectedPageID: .space(selectedID),
                pageIDs: [.activity, .space(selectedID)]
            ),
            .activity
        )
    }

    func testInterpolatesChromeThemeTintFromScrollFraction() throws {
        let profileID = UUID()
        let spaces = [
            BrowserSpace(name: "A", colorHex: "#000000", profileID: profileID),
            BrowserSpace(name: "B", colorHex: "#FFFFFF", profileID: profileID)
        ]

        let theme = try XCTUnwrap(SidebarChromeTheme.interpolated(
            spaces: spaces,
            fractionalIndex: 0.5
        ))

        XCTAssertEqual(theme.tintHex, "#808080")
        XCTAssertEqual(theme.spaceColorHex, "#808080")
    }

    func testInterpolatesChromeThemeGlassSettingsFromScrollFraction() throws {
        let profileID = UUID()
        let lowerBase = SidebarGlassSettings(
            glassOpacity: 0.2,
            tintOpacity: 0.1,
            colorNoiseLevel: 0.0,
            colorNoiseScale: 0.3,
            edgeOpacity: 0.4,
            shadowOpacity: 0.2,
            highlightOpacity: 0.6
        )
        let upperBase = SidebarGlassSettings(
            glassOpacity: 0.8,
            tintOpacity: 0.7,
            colorNoiseLevel: 0.4,
            colorNoiseScale: 0.9,
            edgeOpacity: 0.6,
            shadowOpacity: 1.0,
            highlightOpacity: 0.2
        )
        let lowerPinned = SidebarGlassSettings(
            glassOpacity: 0.0,
            tintOpacity: 0.2,
            edgeOpacity: 0.4,
            shadowOpacity: 0.6,
            highlightOpacity: 0.8
        )
        let upperPinned = SidebarGlassSettings(
            glassOpacity: 1.0,
            tintOpacity: 0.6,
            edgeOpacity: 0.8,
            shadowOpacity: 0.2,
            highlightOpacity: 0.0
        )
        let spaces = [
            BrowserSpace(
                name: "A",
                colorHex: "#111111",
                sidebarAppearance: SidebarAppearance(
                    tintSource: .custom,
                    tintHex: "#000000",
                    base: lowerBase,
                    pinnedOverride: lowerPinned
                ),
                profileID: profileID
            ),
            BrowserSpace(
                name: "B",
                colorHex: "#EEEEEE",
                sidebarAppearance: SidebarAppearance(
                    tintSource: .custom,
                    tintHex: "#FFFFFF",
                    base: upperBase,
                    pinnedOverride: upperPinned
                ),
                profileID: profileID
            )
        ]

        let theme = try XCTUnwrap(SidebarChromeTheme.interpolated(
            spaces: spaces,
            fractionalIndex: 0.5
        ))

        XCTAssertEqual(theme.appearance.base.glassOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.base.tintOpacity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.base.colorNoiseLevel, 0.2, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.base.colorNoiseScale, 0.6, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.base.edgeOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.base.shadowOpacity, 0.6, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.base.highlightOpacity, 0.4, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.pinnedSettings.glassOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(theme.appearance.pinnedSettings.tintOpacity, 0.4, accuracy: 0.0001)
    }

    func testChromeThemeInterpolationClampsOutsidePageRange() throws {
        let profileID = UUID()
        let spaces = [
            BrowserSpace(name: "A", colorHex: "#000000", profileID: profileID),
            BrowserSpace(name: "B", colorHex: "#FFFFFF", profileID: profileID)
        ]

        XCTAssertEqual(
            try XCTUnwrap(SidebarChromeTheme.interpolated(
                spaces: spaces,
                fractionalIndex: -4
            )).tintHex,
            "#000000"
        )
        XCTAssertEqual(
            try XCTUnwrap(SidebarChromeTheme.interpolated(
                spaces: spaces,
                fractionalIndex: 9
            )).tintHex,
            "#FFFFFF"
        )
    }

    func testActivityPageUsesStandardChromeTheme() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "A", colorHex: "#000000", profileID: profileID)
        let pages = [
            SidebarSpacePagerPageSnapshot.activity(
                SidebarActivityPageSnapshot(profiles: [], downloads: [], historyEntries: [])
            ),
            SidebarSpacePagerPageSnapshot.space(
                SidebarSpacePageSnapshot(
                    index: 0,
                    space: space,
                    favoriteTabs: [],
                    pinnedTabs: [],
                    folders: [],
                    regularTabs: []
                )
            )
        ]

        XCTAssertEqual(
            SidebarSpacePagerChrome.theme(for: pages, fractionalPageIndex: 0),
            .standard
        )
        XCTAssertEqual(
            SidebarSpacePagerChrome.theme(for: pages, fractionalPageIndex: 1),
            SidebarChromeTheme.theme(for: space)
        )
    }

    func testFocusUsesEachSpaceSelectedTabIndependently() throws {
        let profileID = UUID()
        let firstSelectedTabID = UUID()
        let secondSelectedTabID = UUID()
        let firstSpace = BrowserSpace(
            name: "A",
            profileID: profileID,
            regularTabIDs: [firstSelectedTabID],
            selectedTabID: firstSelectedTabID
        )
        let secondSpace = BrowserSpace(
            name: "B",
            profileID: profileID,
            regularTabIDs: [secondSelectedTabID],
            selectedTabID: secondSelectedTabID
        )
        let tabsByID = [
            firstSelectedTabID: BrowserTab(
                id: firstSelectedTabID,
                title: "First",
                parentSpaceID: firstSpace.id,
                profileID: profileID
            ),
            secondSelectedTabID: BrowserTab(
                id: secondSelectedTabID,
                title: "Second",
                parentSpaceID: secondSpace.id,
                profileID: profileID
            )
        ]

        XCTAssertEqual(
            SidebarSpacePagerFocus.focusedTabID(for: firstSpace, folders: [], tabsByID: tabsByID),
            firstSelectedTabID
        )
        XCTAssertEqual(
            SidebarSpacePagerFocus.focusedTabID(for: secondSpace, folders: [], tabsByID: tabsByID),
            secondSelectedTabID
        )
    }

    func testFocusCanReturnSelectedSpaceCustomizerTab() throws {
        let profileID = UUID()
        let customizerTabID = UUID()
        let space = BrowserSpace(
            name: "A",
            profileID: profileID,
            regularTabIDs: [customizerTabID],
            selectedTabID: customizerTabID
        )
        let tabsByID = [
            customizerTabID: BrowserTab(
                id: customizerTabID,
                title: "Customize Space",
                content: .spaceCustomization(space.id),
                parentSpaceID: space.id,
                profileID: profileID
            )
        ]

        XCTAssertEqual(
            SidebarSpacePagerFocus.focusedTabID(for: space, folders: [], tabsByID: tabsByID),
            customizerTabID
        )
    }

    func testFocusFallsBackToFirstVisibleTabWhenStoredSelectionIsMissing() throws {
        let profileID = UUID()
        let staleSelectedTabID = UUID()
        let fallbackTabID = UUID()
        let space = BrowserSpace(
            name: "A",
            profileID: profileID,
            favoriteTabIDs: [fallbackTabID],
            selectedTabID: staleSelectedTabID
        )
        let tabsByID = [
            fallbackTabID: BrowserTab(
                id: fallbackTabID,
                title: "Fallback",
                parentSpaceID: space.id,
                profileID: profileID
            )
        ]

        XCTAssertEqual(
            SidebarSpacePagerFocus.focusedTabID(for: space, folders: [], tabsByID: tabsByID),
            fallbackTabID
        )
    }

    func testFocusIncludesFolderTabs() throws {
        let profileID = UUID()
        let folderTabID = UUID()
        let space = BrowserSpace(
            name: "A",
            profileID: profileID,
            selectedTabID: folderTabID
        )
        let folder = BrowserFolder(
            name: "Folder",
            parentSpaceID: space.id,
            tabIDs: [folderTabID]
        )
        let tabsByID = [
            folderTabID: BrowserTab(
                id: folderTabID,
                title: "Folder Tab",
                parentSpaceID: space.id,
                parentFolderID: folder.id,
                profileID: profileID
            )
        ]

        XCTAssertEqual(
            SidebarSpacePagerFocus.focusedTabID(for: space, folders: [folder], tabsByID: tabsByID),
            folderTabID
        )
        XCTAssertTrue(SidebarSpacePagerFocus.isFocused(tabID: folderTabID, focusedTabID: folderTabID))
    }

    func testFocusedTabResolverReturnsNilWhenNoCandidateExists() {
        let profileID = UUID()
        let staleSelectedTabID = UUID()
        let space = BrowserSpace(
            name: "A",
            profileID: profileID,
            selectedTabID: staleSelectedTabID
        )

        XCTAssertNil(BrowserSpaceFocusedTabResolver.focusedTabID(for: space, folders: [], tabsByID: [:]))
    }

    func testFavoriteGridUsesExplicitFaviconURL() throws {
        let faviconURL = try XCTUnwrap(URL(string: "https://cdn.example.com/icon.png"))
        let tab = BrowserTab(
            title: "Example",
            url: URL(string: "https://example.com/page"),
            faviconURL: faviconURL,
            parentSpaceID: UUID(),
            profileID: UUID()
        )

        XCTAssertEqual(SidebarTabFaviconSource.url(for: tab), faviconURL)
    }

    func testFavoriteGridFallsBackToRootFaviconURL() throws {
        let tab = BrowserTab(
            title: "Example",
            url: try XCTUnwrap(URL(string: "https://example.com/path?q=1")),
            parentSpaceID: UUID(),
            profileID: UUID()
        )

        XCTAssertEqual(
            SidebarTabFaviconSource.url(for: tab),
            try XCTUnwrap(URL(string: "https://example.com/favicon.ico"))
        )
    }

    func testFavoriteGridDoesNotResolveNonWebFaviconURL() throws {
        let tab = BrowserTab(
            title: "Local File",
            url: try XCTUnwrap(URL(string: "file:///Users/example/index.html")),
            parentSpaceID: UUID(),
            profileID: UUID()
        )

        XCTAssertNil(SidebarTabFaviconSource.url(for: tab))
    }

    func testFavoriteGridColumnCountUsesTwoColumnMinimum() {
        XCTAssertEqual(SidebarFavoriteGridLayout.preferredColumnCount(for: 1), 2)
        XCTAssertEqual(SidebarFavoriteGridLayout.preferredColumnCount(for: 2), 2)
    }

    func testFavoriteGridColumnCountCapsAtFourColumns() {
        XCTAssertEqual(SidebarFavoriteGridLayout.preferredColumnCount(for: 4), 4)
        XCTAssertEqual(SidebarFavoriteGridLayout.preferredColumnCount(for: 12), 4)
    }

    func testFavoriteGridColumnCountRespondsToAvailableWidth() {
        let fourColumnWidth = SidebarFavoriteGridLayout.minimumWidth(forColumnCount: 4)
        let threeColumnWidth = SidebarFavoriteGridLayout.minimumWidth(forColumnCount: 3)

        XCTAssertEqual(
            SidebarFavoriteGridLayout.columnCount(forAvailableWidth: fourColumnWidth, itemCount: 8),
            4
        )
        XCTAssertEqual(
            SidebarFavoriteGridLayout.columnCount(forAvailableWidth: fourColumnWidth - 1, itemCount: 8),
            3
        )
        XCTAssertEqual(
            SidebarFavoriteGridLayout.columnCount(forAvailableWidth: threeColumnWidth - 1, itemCount: 8),
            2
        )
    }

    func testFavoriteGridRowCountVariesWithColumnCount() {
        XCTAssertEqual(SidebarFavoriteGridLayout.rowCount(for: 4, columnCount: 4), 1)
        XCTAssertEqual(SidebarFavoriteGridLayout.rowCount(for: 6, columnCount: 3), 2)
        XCTAssertEqual(SidebarFavoriteGridLayout.rowCount(for: 6, columnCount: 2), 3)
    }

    @MainActor
    func testPresentationStateCanClearPreviewAfterCommit() {
        let previewID = UUID()
        let state = BrowserContentPresentationState()

        state.setPreviewTabID(previewID)
        XCTAssertEqual(state.previewTabID, previewID)

        state.setPreviewTabID(nil)
        XCTAssertNil(state.previewTabID)
    }

    @MainActor
    func testPresentationStateCanPreviewStartPageSpace() {
        let spaceID = UUID()
        let state = BrowserContentPresentationState()

        state.setPreviewStartPageSpaceID(spaceID)
        XCTAssertEqual(state.previewStartPageSpaceID, spaceID)

        state.setPreviewStartPageSpaceID(nil)
        XCTAssertNil(state.previewStartPageSpaceID)
    }

    @MainActor
    func testPresentationStateStoresAndPrunesSnapshots() {
        let keptTabID = UUID()
        let prunedTabID = UUID()
        let state = BrowserContentPresentationState()
        let image = NSImage(size: NSSize(width: 320, height: 200))

        state.storeSnapshot(image, for: keptTabID)
        state.storeSnapshot(NSImage(size: NSSize(width: 120, height: 80)), for: prunedTabID)

        XCTAssertEqual(state.snapshot(for: keptTabID)?.size, image.size)

        state.removeSnapshots(keeping: [keptTabID])

        XCTAssertNotNil(state.snapshot(for: keptTabID))
        XCTAssertNil(state.snapshot(for: prunedTabID))
    }

    @MainActor
    func testPresentationStateStartsSnapshotHandoffOnlyForCachedTabs() {
        let cachedTabID = UUID()
        let uncachedTabID = UUID()
        let state = BrowserContentPresentationState()

        XCTAssertNil(state.beginSnapshotHandoff(to: uncachedTabID))
        XCTAssertNil(state.snapshotHandoffTabID)

        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: cachedTabID)
        XCTAssertNotNil(state.beginSnapshotHandoff(to: cachedTabID))
        XCTAssertEqual(state.snapshotHandoffTabID, cachedTabID)
    }

    @MainActor
    func testPresentationStateIgnoresStaleSnapshotHandoffCompletion() throws {
        let firstTabID = UUID()
        let secondTabID = UUID()
        let state = BrowserContentPresentationState()
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: firstTabID)
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: secondTabID)

        let staleHandoffID = try XCTUnwrap(state.beginSnapshotHandoff(to: firstTabID))
        _ = state.beginSnapshotHandoff(to: secondTabID)

        state.completeSnapshotHandoff(staleHandoffID, for: firstTabID)

        XCTAssertEqual(state.snapshotHandoffTabID, secondTabID)
    }

    @MainActor
    func testPresentationStateClearsSnapshotHandoffWhenSnapshotIsPruned() {
        let prunedTabID = UUID()
        let state = BrowserContentPresentationState()
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: prunedTabID)
        state.beginSnapshotHandoff(to: prunedTabID)

        state.removeSnapshots(keeping: [])

        XCTAssertNil(state.snapshotHandoffTabID)
    }
}
