import AppKit
import Foundation
@testable import MeridianCore
import XCTest

final class SidebarSpacePagerSelectionTests: XCTestCase {
    func testSpaceDragPayloadRoundTripsSpaceID() {
        let spaceID = UUID()

        XCTAssertEqual(
            SidebarSpaceDragPayload.spaceID(from: SidebarSpaceDragPayload.data(for: spaceID)),
            spaceID
        )
    }

    func testSpaceDragPayloadRejectsInvalidData() {
        XCTAssertNil(SidebarSpaceDragPayload.spaceID(from: Data("not-a-space-id".utf8)))
    }

    func testSpaceDragItemProviderRegistersSpacePayload() throws {
        let spaceID = UUID()
        let provider = SidebarSpaceDragPayload.itemProvider(for: spaceID)
        let loadedPayload = expectation(description: "Loaded space drag payload")

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(SidebarSpaceDragPayload.type.identifier))

        provider.loadDataRepresentation(forTypeIdentifier: SidebarSpaceDragPayload.type.identifier) { data, _ in
            XCTAssertEqual(data.flatMap(SidebarSpaceDragPayload.spaceID(from:)), spaceID)
            loadedPayload.fulfill()
        }
        wait(for: [loadedPayload], timeout: 1)
    }

    func testSpaceSwitcherLayoutGeneratesInsertionTargetsForEachSpaceAndTail() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()

        XCTAssertEqual(
            SidebarSpaceSwitcherLayout.insertionTargets(for: [firstID, secondID, thirdID]),
            [.before(firstID), .before(secondID), .before(thirdID), .tail]
        )
    }

    func testSpaceSwitcherLayoutTargetsInsertionSlotsFromPointerPosition() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let spaceIDs = [firstID, secondID, thirdID]

        XCTAssertEqual(
            SidebarSpaceSwitcherLayout.target(for: 0, spaceIDs: spaceIDs),
            .before(firstID)
        )
        XCTAssertEqual(
            SidebarSpaceSwitcherLayout.target(for: 50, spaceIDs: spaceIDs),
            .before(secondID)
        )
        XCTAssertEqual(
            SidebarSpaceSwitcherLayout.target(for: 90, spaceIDs: spaceIDs),
            .before(thirdID)
        )
        XCTAssertEqual(
            SidebarSpaceSwitcherLayout.target(for: 130, spaceIDs: spaceIDs),
            .tail
        )
    }

    func testSpaceSwitcherLayoutIdentifiesSpaceIconsOnly() {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let spaceIDs = [firstID, secondID, thirdID]

        XCTAssertNil(SidebarSpaceSwitcherLayout.spaceID(at: CGPoint(x: 12, y: 13), spaceIDs: spaceIDs))
        XCTAssertEqual(SidebarSpaceSwitcherLayout.spaceID(at: CGPoint(x: 32, y: 13), spaceIDs: spaceIDs), firstID)
        XCTAssertEqual(SidebarSpaceSwitcherLayout.spaceID(at: CGPoint(x: 64, y: 13), spaceIDs: spaceIDs), secondID)
        XCTAssertEqual(SidebarSpaceSwitcherLayout.spaceID(at: CGPoint(x: 96, y: 13), spaceIDs: spaceIDs), thirdID)
        XCTAssertNil(SidebarSpaceSwitcherLayout.spaceID(at: CGPoint(x: 128, y: 13), spaceIDs: spaceIDs))
        XCTAssertNil(SidebarSpaceSwitcherLayout.spaceID(at: CGPoint(x: 64, y: -1), spaceIDs: spaceIDs))
    }

    func testSpaceSwitcherLayoutIgnoresEmptyOrUnknownTargets() {
        let spaceID = UUID()

        XCTAssertNil(SidebarSpaceSwitcherLayout.target(for: 0, spaceIDs: []))
        XCTAssertNil(SidebarSpaceSwitcherLayout.indicatorX(for: .before(spaceID), spaceIDs: []))
        XCTAssertNil(SidebarSpaceSwitcherLayout.indicatorX(for: .before(UUID()), spaceIDs: [spaceID]))
    }

    func testSpaceSwitcherLayoutIndicatorPositionsAdvanceAcrossSlots() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let spaceIDs = [firstID, secondID, thirdID]

        let firstIndicatorX = try XCTUnwrap(
            SidebarSpaceSwitcherLayout.indicatorX(for: .before(firstID), spaceIDs: spaceIDs)
        )
        let secondIndicatorX = try XCTUnwrap(
            SidebarSpaceSwitcherLayout.indicatorX(for: .before(secondID), spaceIDs: spaceIDs)
        )
        let thirdIndicatorX = try XCTUnwrap(
            SidebarSpaceSwitcherLayout.indicatorX(for: .before(thirdID), spaceIDs: spaceIDs)
        )
        let tailIndicatorX = try XCTUnwrap(
            SidebarSpaceSwitcherLayout.indicatorX(for: .tail, spaceIDs: spaceIDs)
        )

        XCTAssertLessThan(firstIndicatorX, secondIndicatorX)
        XCTAssertLessThan(secondIndicatorX, thirdIndicatorX)
        XCTAssertLessThan(thirdIndicatorX, tailIndicatorX)
    }

    func testSpaceSwitcherDragStateTargetsAndClears() {
        let draggedID = UUID()
        let targetID = UUID()
        var state = SidebarSpaceSwitcherDragState()

        state.target(.before(targetID), dragging: draggedID, locationX: 64)

        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.draggedSpaceID, draggedID)
        XCTAssertEqual(state.activeTarget, .before(targetID))
        XCTAssertEqual(state.locationX, 64)

        state.clear()

        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.draggedSpaceID)
        XCTAssertNil(state.activeTarget)
        XCTAssertNil(state.locationX)
    }

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

    func testMagneticPagerKeepsCurrentPageForSmallHorizontalDrift() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 1.30,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 4
            ),
            1
        )
    }

    func testMagneticPagerAdvancesAfterDeliberateDrag() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 1.60,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 4
            ),
            2
        )
    }

    func testMagneticPagerAdvancesAfterShortFastFlick() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 1.04,
                velocityX: 1_000,
                pageWidth: 200,
                pageCount: 4
            ),
            2
        )
    }

    func testMagneticPagerCarriesFastFlickWithShortTravel() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 1.04,
                velocityX: 1_000,
                pageWidth: 200,
                pageCount: 4
            ),
            2
        )
    }

    func testMagneticPagerKeepsCurrentPageForTinyFastDrift() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 1.02,
                velocityX: 1_200,
                pageWidth: 200,
                pageCount: 4
            ),
            1
        )
    }

    func testMagneticPagerKeepsProposedTargetAsHardUpperBound() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 3.00,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 6
            ),
            2
        )
    }

    func testMagneticPagerDoesNotGiveConsequentPagesForFree() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 800,
                visibleFractionalPageIndex: 2.49,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 6
            ),
            2
        )
    }

    func testMagneticPagerAllowsConsequentPageAfterClearingMagnet() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 800,
                visibleFractionalPageIndex: 2.56,
                velocityX: 2_400,
                pageWidth: 200,
                pageCount: 6
            ),
            3
        )
    }

    func testMagneticPagerAllowsMomentumAcrossMultipleClearedMagnets() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 800,
                visibleFractionalPageIndex: 3.56,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 6
            ),
            4
        )
    }

    func testMagneticPagerDoesNotLetHighVelocityBypassConsequentMagnets() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 1_000,
                visibleFractionalPageIndex: 1.04,
                velocityX: 5_000,
                pageWidth: 200,
                pageCount: 6
            ),
            2
        )
    }

    func testMagneticPagerRetreatsByOnePage() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 0,
                visibleFractionalPageIndex: 1.44,
                velocityX: -1_100,
                pageWidth: 200,
                pageCount: 4
            ),
            1
        )
    }

    func testMagneticPagerClampsAtEdges() {
        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 0,
                proposedOffsetX: -400,
                visibleFractionalPageIndex: -1,
                velocityX: -2_000,
                pageWidth: 200,
                pageCount: 3
            ),
            0
        )

        XCTAssertEqual(
            SidebarSpacePagerMagnetism.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 900,
                visibleFractionalPageIndex: 4.50,
                velocityX: 2_000,
                pageWidth: 200,
                pageCount: 3
            ),
            2
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
            SidebarSpacePagerChrome.theme(for: .activity, in: pages),
            .standard
        )
        XCTAssertEqual(
            SidebarSpacePagerChrome.theme(for: .space(space.id), in: pages),
            SidebarChromeTheme.theme(for: space)
        )
        XCTAssertNil(
            SidebarSpacePagerChrome.theme(for: .space(UUID()), in: pages)
        )
    }

    func testActivityRelativeTimestampFormattingIsStableForFixedDates() {
        let referenceDate = Date(timeIntervalSince1970: 2_000_000)
        let date = referenceDate.addingTimeInterval(-125)
        let first = SidebarActivityRelativeTimeFormatter.string(
            for: date,
            relativeTo: referenceDate
        )
        let second = SidebarActivityRelativeTimeFormatter.string(
            for: date,
            relativeTo: referenceDate
        )

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }

    func testTabDropStateTracksActiveDragForRealtimeEmptySections() {
        var dropState = SidebarTabDropState()

        XCTAssertFalse(dropState.isDragging)

        dropState.beginDrag()
        XCTAssertTrue(dropState.isDragging)
        XCTAssertFalse(dropState.suppressTargetsUntilNextDrag)

        dropState.finishDrop()
        XCTAssertFalse(dropState.isDragging)
        XCTAssertTrue(dropState.suppressTargetsUntilNextDrag)

        dropState.beginDrag()
        XCTAssertTrue(dropState.isDragging)
        XCTAssertFalse(dropState.suppressTargetsUntilNextDrag)
    }

    func testShowsEmptyPinnedDropSectionDuringDragWhenRegularTabsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let regularTab = sidebarTabItem(title: "Regular", spaceID: space.id, profileID: profileID)
        let page = sidebarPage(space: space, regularTabs: [regularTab])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyPinnedDropSectionWhenNotDragging() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let regularTab = sidebarTabItem(title: "Regular", spaceID: space.id, profileID: profileID)
        let page = sidebarPage(space: space, regularTabs: [regularTab])

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(for: page, isDragging: false))
    }

    func testShowsEmptyFavoriteDropSectionDuringDragWhenRegularTabsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let regularTab = sidebarTabItem(title: "Regular", spaceID: space.id, profileID: profileID)
        let page = sidebarPage(space: space, regularTabs: [regularTab])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyFavoriteTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyFavoriteDropSectionWhenNotDragging() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let regularTab = sidebarTabItem(title: "Regular", spaceID: space.id, profileID: profileID)
        let page = sidebarPage(space: space, regularTabs: [regularTab])

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyFavoriteTabDropSection(for: page, isDragging: false))
    }

    func testShowsEmptyFavoriteDropSectionDuringDragWhenListEssentialsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let pinnedTab = sidebarTabItem(
            title: "Pinned",
            spaceID: space.id,
            profileID: profileID,
            isPinned: true
        )
        let page = sidebarPage(space: space, pinnedTabs: [pinnedTab])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyFavoriteTabDropSection(for: page, isDragging: true))
    }

    func testShowsEmptyPinnedDropSectionDuringDragWhenOnlyGridEssentialsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let favoriteTab = sidebarTabItem(
            title: "Favorite",
            spaceID: space.id,
            profileID: profileID,
            isFavorite: true
        )
        let page = sidebarPage(space: space, favoriteTabs: [favoriteTab])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyPinnedDropSectionForEmptySpace() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let page = sidebarPage(space: space)

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyFavoriteDropSectionForEmptySpace() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let page = sidebarPage(space: space)

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyFavoriteTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyFavoriteDropSectionWhenGridEssentialsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let favoriteTab = sidebarTabItem(
            title: "Favorite",
            spaceID: space.id,
            profileID: profileID,
            isFavorite: true
        )
        let page = sidebarPage(space: space, favoriteTabs: [favoriteTab])

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyFavoriteTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyPinnedDropSectionWhenPinnedTabsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let pinnedTab = sidebarTabItem(
            title: "Pinned",
            spaceID: space.id,
            profileID: profileID,
            isPinned: true
        )
        let page = sidebarPage(space: space, pinnedTabs: [pinnedTab])

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(for: page, isDragging: true))
    }

    func testShowsEmptyPinnedDropSectionDuringDragWhenFolderHasTabs() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let folder = BrowserFolder(name: "Folder", parentSpaceID: space.id)
        let folderTab = sidebarTabItem(
            title: "Folder Tab",
            spaceID: space.id,
            profileID: profileID,
            folderID: folder.id
        )
        let folderItem = SidebarFolderItemSnapshot(folder: folder, tabs: [folderTab], childFolders: [])
        let page = sidebarPage(space: space, folders: [folderItem])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyPinnedTabDropSection(for: page, isDragging: true))
    }

    func testSnapshotBuilderMarksOnlyLiveSessionTabs() throws {
        let profileID = UUID()
        var space = BrowserSpace(name: "Work", profileID: profileID)
        let favoriteTab = BrowserTab(
            title: "Essential",
            parentSpaceID: space.id,
            isFavorite: true,
            profileID: profileID
        )
        let regularTab = BrowserTab(
            title: "Loaded",
            parentSpaceID: space.id,
            profileID: profileID
        )
        space.favoriteTabIDs = [favoriteTab.id]
        space.regularTabIDs = [regularTab.id]

        let pages = SidebarSpacePageSnapshotBuilder.spacePages(
            activeSpaces: [space],
            folders: [],
            tabs: [favoriteTab, regularTab],
            liveSessionTabIDs: [regularTab.id]
        )
        let page = try XCTUnwrap(pages.first)

        XCTAssertEqual(page.favoriteTabs.first?.hasLiveSession, false)
        XCTAssertEqual(page.regularTabs.first?.hasLiveSession, true)
    }

    func testSnapshotBuilderKeepsTabsClosableWithoutLiveSessions() throws {
        let profileID = UUID()
        var space = BrowserSpace(name: "Work", profileID: profileID)
        var folder = BrowserFolder(name: "Tools", parentSpaceID: space.id)
        let favoriteTab = BrowserTab(
            title: "Essential",
            parentSpaceID: space.id,
            isFavorite: true,
            profileID: profileID
        )
        let pinnedPasswordTab = BrowserTab(
            title: "Passwords",
            content: .passwordManager,
            parentSpaceID: space.id,
            isPinned: true,
            profileID: profileID
        )
        let folderCustomizerTab = BrowserTab(
            title: "Customize Space",
            content: .spaceCustomization(space.id),
            parentSpaceID: space.id,
            parentFolderID: folder.id,
            profileID: profileID
        )
        let regularTab = BrowserTab(
            title: "Restored",
            parentSpaceID: space.id,
            profileID: profileID
        )

        folder.tabIDs = [folderCustomizerTab.id]
        space.favoriteTabIDs = [favoriteTab.id]
        space.pinnedTabIDs = [pinnedPasswordTab.id]
        space.folderIDs = [folder.id]
        space.regularTabIDs = [regularTab.id]

        let pages = SidebarSpacePageSnapshotBuilder.spacePages(
            activeSpaces: [space],
            folders: [folder],
            tabs: [favoriteTab, pinnedPasswordTab, folderCustomizerTab, regularTab],
            liveSessionTabIDs: []
        )
        let page = try XCTUnwrap(pages.first)

        XCTAssertEqual(page.favoriteTabs.first?.canClose, true)
        XCTAssertEqual(page.favoriteTabs.first?.hasLiveSession, false)
        XCTAssertEqual(page.pinnedTabs.first?.canClose, true)
        XCTAssertEqual(page.pinnedTabs.first?.hasLiveSession, false)
        XCTAssertEqual(page.folders.first?.tabs.first?.canClose, true)
        XCTAssertEqual(page.folders.first?.tabs.first?.hasLiveSession, false)
        XCTAssertEqual(page.regularTabs.first?.canClose, true)
        XCTAssertEqual(page.regularTabs.first?.hasLiveSession, false)
    }

    func testShowsEmptyRegularDropSectionDuringDragWhenOnlyEssentialsHaveTabs() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let favoriteTab = sidebarTabItem(
            title: "Favorite",
            spaceID: space.id,
            profileID: profileID,
            isFavorite: true
        )
        let page = sidebarPage(space: space, favoriteTabs: [favoriteTab])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyRegularTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyRegularDropSectionWhenNotDragging() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let favoriteTab = sidebarTabItem(
            title: "Favorite",
            spaceID: space.id,
            profileID: profileID,
            isFavorite: true
        )
        let page = sidebarPage(space: space, favoriteTabs: [favoriteTab])

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyRegularTabDropSection(for: page, isDragging: false))
    }

    func testHidesEmptyRegularDropSectionForEmptySpace() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let page = sidebarPage(space: space)

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyRegularTabDropSection(for: page, isDragging: true))
    }

    func testHidesEmptyRegularDropSectionWhenRegularTabsExist() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let regularTab = sidebarTabItem(title: "Regular", spaceID: space.id, profileID: profileID)
        let page = sidebarPage(space: space, regularTabs: [regularTab])

        XCTAssertFalse(SidebarSpacePageSectionVisibility.showsEmptyRegularTabDropSection(for: page, isDragging: true))
    }

    func testShowsEmptyRegularDropSectionDuringDragWhenNestedFolderHasTabs() throws {
        let profileID = UUID()
        let space = BrowserSpace(name: "Work", profileID: profileID)
        let folder = BrowserFolder(name: "Folder", parentSpaceID: space.id)
        let folderTab = sidebarTabItem(
            title: "Folder Tab",
            spaceID: space.id,
            profileID: profileID,
            folderID: folder.id
        )
        let folderItem = SidebarFolderItemSnapshot(folder: folder, tabs: [folderTab], childFolders: [])
        let page = sidebarPage(space: space, folders: [folderItem])

        XCTAssertTrue(SidebarSpacePageSectionVisibility.showsEmptyRegularTabDropSection(for: page, isDragging: true))
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

    @MainActor
    func testPresentationStateExpiresUncompletedSnapshotHandoff() async throws {
        let tabID = UUID()
        let state = BrowserContentPresentationState(snapshotHandoffExpirationNanoseconds: 1_000_000)
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: tabID)

        XCTAssertNotNil(state.beginSnapshotHandoff(to: tabID))
        XCTAssertEqual(state.snapshotHandoffTabID, tabID)

        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(state.snapshotHandoffTabID)
    }

    private func sidebarPage(
        space: BrowserSpace,
        favoriteTabs: [SidebarTabItemSnapshot] = [],
        pinnedTabs: [SidebarTabItemSnapshot] = [],
        folders: [SidebarFolderItemSnapshot] = [],
        regularTabs: [SidebarTabItemSnapshot] = []
    ) -> SidebarSpacePageSnapshot {
        SidebarSpacePageSnapshot(
            index: 0,
            space: space,
            favoriteTabs: favoriteTabs,
            pinnedTabs: pinnedTabs,
            folders: folders,
            regularTabs: regularTabs
        )
    }

    private func sidebarTabItem(
        title: String,
        spaceID: SpaceID,
        profileID: ProfileID,
        folderID: FolderID? = nil,
        isPinned: Bool = false,
        isFavorite: Bool = false
    ) -> SidebarTabItemSnapshot {
        SidebarTabItemSnapshot(
            tab: BrowserTab(
                title: title,
                parentSpaceID: spaceID,
                parentFolderID: folderID,
                isPinned: isPinned,
                isFavorite: isFavorite,
                profileID: profileID
            ),
            isSelected: false,
            canMoveUp: false,
            canMoveDown: false
        )
    }
}
