import AppKit
import Combine
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

    func testPreviewsDestinationSpaceBeforePagerSettles() {
        let selectedID = UUID()
        let destinationID = UUID()

        XCTAssertEqual(
            SidebarSpacePagerPreview.spaceID(
                for: .space(destinationID),
                selectedPageID: .space(selectedID)
            ),
            destinationID
        )
    }

    func testDoesNotPreviewCurrentSpaceOrActivityPage() {
        let selectedID = UUID()

        XCTAssertNil(SidebarSpacePagerPreview.spaceID(
            for: .space(selectedID),
            selectedPageID: .space(selectedID)
        ))
        XCTAssertNil(SidebarSpacePagerPreview.spaceID(
            for: .activity,
            selectedPageID: .space(selectedID)
        ))
    }

    func testAddressMorphTracksLiveFractionBetweenAdjacentPages() throws {
        let state = try XCTUnwrap(SidebarAddressScrollMorph.state(
            at: 1.35,
            pageTexts: ["Activity", "https://one.example", "https://two.example"]
        ))

        XCTAssertEqual(state.sourceText, "https://one.example")
        XCTAssertEqual(state.destinationText, "https://two.example")
        XCTAssertEqual(state.progress, 0.35, accuracy: 0.0001)
    }

    func testAddressMorphReversesWithTheSameScrollFraction() throws {
        let forward = try XCTUnwrap(SidebarAddressScrollMorph.state(
            at: 1.2,
            pageTexts: ["Activity", "https://one.example", "https://two.example"]
        ))
        let backward = try XCTUnwrap(SidebarAddressScrollMorph.state(
            at: 1.8,
            pageTexts: ["Activity", "https://one.example", "https://two.example"]
        ))

        XCTAssertEqual(forward.progress, 0.2, accuracy: 0.0001)
        XCTAssertEqual(backward.progress, 0.8, accuracy: 0.0001)
        XCTAssertEqual(forward.sourceText, backward.sourceText)
        XCTAssertEqual(forward.destinationText, backward.destinationText)
    }

    func testAddressMorphRejectsMissingOrInvalidScrollGeometry() {
        XCTAssertNil(SidebarAddressScrollMorph.state(at: 0.5, pageTexts: []))
        XCTAssertNil(SidebarAddressScrollMorph.state(
            at: .nan,
            pageTexts: ["Activity", "https://example.com"]
        ))
    }

    func testChromeHandoffDefersExactStyleOnlyWhenPageTravelIsRequired() {
        let first = SidebarSpacePagerPageID.space(UUID())
        let second = SidebarSpacePagerPageID.space(UUID())

        XCTAssertFalse(SidebarSpacePagerChrome.shouldDeferSettledStyle(from: first, to: first))
        XCTAssertTrue(SidebarSpacePagerChrome.shouldDeferSettledStyle(from: first, to: second))
        XCTAssertTrue(SidebarSpacePagerChrome.shouldDeferSettledStyle(from: nil, to: first))
        XCTAssertFalse(SidebarSpacePagerChrome.shouldDeferSettledStyle(from: first, to: nil))
    }

    func testFixedChromeTargetsOneExactAdjacentEndpointPerGestureDirection() throws {
        let profileID = UUID()
        let firstSpace = BrowserSpace(name: "First", colorHex: "#000000", profileID: profileID)
        let secondSpace = BrowserSpace(name: "Second", colorHex: "#FFFFFF", profileID: profileID)
        let pages: [SidebarSpacePagerPageSnapshot] = [
            .activity(SidebarActivityPageSnapshot(profiles: [], downloads: [], historyEntries: [])),
            .space(sidebarPage(space: firstSpace)),
            .space(sidebarPage(space: secondSpace)),
        ]

        XCTAssertEqual(
            SidebarSpacePagerFixedChromeTarget.pageID(
                visibleFractionalPageIndex: 1.08,
                gestureStartFractionalPageIndex: 1,
                rawGestureDisplacementX: 24,
                pageWidth: 300,
                pages: pages
            ),
            .space(secondSpace.id)
        )
        XCTAssertEqual(
            SidebarSpacePagerFixedChromeTarget.pageID(
                visibleFractionalPageIndex: 0.92,
                gestureStartFractionalPageIndex: 1,
                rawGestureDisplacementX: -24,
                pageWidth: 300,
                pages: pages
            ),
            .activity
        )
    }

    func testFixedChromeKeepsOriginBelowMeaningfulDirectionThresholdAndClampsEdges() {
        let profileID = UUID()
        let space = BrowserSpace(name: "First", colorHex: "#000000", profileID: profileID)
        let pages: [SidebarSpacePagerPageSnapshot] = [
            .activity(SidebarActivityPageSnapshot(profiles: [], downloads: [], historyEntries: [])),
            .space(sidebarPage(space: space)),
        ]

        XCTAssertEqual(
            SidebarSpacePagerFixedChromeTarget.pageID(
                visibleFractionalPageIndex: 1.0005,
                gestureStartFractionalPageIndex: 1,
                rawGestureDisplacementX: 0.1,
                pageWidth: 300,
                pages: pages
            ),
            .space(space.id)
        )
        XCTAssertEqual(
            SidebarSpacePagerFixedChromeTarget.pageID(
                visibleFractionalPageIndex: -0.08,
                gestureStartFractionalPageIndex: 0,
                rawGestureDisplacementX: -24,
                pageWidth: 300,
                pages: pages
            ),
            .activity
        )
        XCTAssertNil(
            SidebarSpacePagerFixedChromeTarget.pageID(
                visibleFractionalPageIndex: 0,
                gestureStartFractionalPageIndex: 0,
                rawGestureDisplacementX: nil,
                pageWidth: 0,
                pages: pages
            )
        )
    }

    @MainActor
    func testFixedChromeControllerPublishesOnlyWhenItsEndpointChanges() {
        let controller = SidebarFixedChromeLiveStyleController()
        let firstStyle = SidebarChromeLiveStyle(theme: .standard)
        let secondStyle = SidebarChromeLiveStyle(theme: SidebarChromeTheme(
            appearance: SidebarAppearance(tintSource: .spaceColor),
            spaceColorHex: "#FFFFFF"
        ))
        var publicationCount = 0
        let observation = controller.objectWillChange.sink {
            publicationCount += 1
        }

        for _ in 0..<500 {
            controller.update(firstStyle)
        }
        XCTAssertEqual(publicationCount, 1)

        controller.update(secondStyle)
        XCTAssertEqual(publicationCount, 2)
        withExtendedLifetime(observation) {}
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

    func testPagerInputScalingChangesHorizontalDeltaBeforeDelivery() throws {
        let originalEvent = scrollEvent(horizontalDelta: 40, verticalDelta: 20)
        var state = SidebarSpacePagerScrollInputScalingState()

        let scaledEvent = try XCTUnwrap(state.scaledEvent(
            from: originalEvent,
            sensitivity: 0.35
        ))

        XCTAssertEqual(scaledEvent.scrollingDeltaX, 14, accuracy: 0.0001)
        XCTAssertEqual(scaledEvent.scrollingDeltaY, 20, accuracy: 0.0001)
        XCTAssertEqual(scaledEvent.deltaX, originalEvent.deltaX * 0.35, accuracy: 0.0001)
        XCTAssertEqual(scaledEvent.phase, originalEvent.phase)
        XCTAssertEqual(scaledEvent.momentumPhase, originalEvent.momentumPhase)
        XCTAssertEqual(
            scaledEvent.isDirectionInvertedFromDevice,
            originalEvent.isDirectionInvertedFromDevice
        )
        XCTAssertEqual(state.cumulativeRawDisplacementX, 40, accuracy: 0.0001)
    }

    func testPagerInputScalingCarriesSubpointRemaindersAcrossEvents() throws {
        var state = SidebarSpacePagerScrollInputScalingState()
        var deliveredDisplacementX: CGFloat = 0

        for _ in 0..<20 {
            let event = scrollEvent(horizontalDelta: 1)
            deliveredDisplacementX += try XCTUnwrap(state.scaledEvent(
                from: event,
                sensitivity: 0.35
            )).scrollingDeltaX
        }

        XCTAssertEqual(deliveredDisplacementX, 7, accuracy: 0.0001)
        XCTAssertEqual(state.cumulativeRawDisplacementX, 20, accuracy: 0.0001)
    }

    func testPagerInputScalingPreservesSignedReversals() throws {
        var state = SidebarSpacePagerScrollInputScalingState()
        let forward = try XCTUnwrap(state.scaledEvent(
            from: scrollEvent(horizontalDelta: 10),
            sensitivity: 0.35
        ))
        let reverse = try XCTUnwrap(state.scaledEvent(
            from: scrollEvent(horizontalDelta: -10),
            sensitivity: 0.35
        ))

        XCTAssertEqual(forward.scrollingDeltaX + reverse.scrollingDeltaX, 0, accuracy: 0.0001)
        XCTAssertEqual(state.cumulativeRawDisplacementX, 0, accuracy: 0.0001)
    }

    func testPagerInputScalingClampsSensitivityAndResets() throws {
        var state = SidebarSpacePagerScrollInputScalingState()
        XCTAssertEqual(
            try XCTUnwrap(state.scaledEvent(
                from: scrollEvent(horizontalDelta: 10),
                sensitivity: 2
            )).scrollingDeltaX,
            10,
            accuracy: 0.0001
        )

        state.reset()
        XCTAssertEqual(state.cumulativeRawDisplacementX, 0, accuracy: 0.0001)
        XCTAssertEqual(
            try XCTUnwrap(state.scaledEvent(
                from: scrollEvent(horizontalDelta: 10),
                sensitivity: -1
            )).scrollingDeltaX,
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(SidebarSpacePagerScrollInputScalingState.normalizedSensitivity(.nan), 1)
    }

    func testPagerGestureCancellationIgnoresChangesUntilNextBegin() {
        var gate = SidebarSpacePagerPhysicalGestureGate()
        XCTAssertFalse(gate.ignoresChangedEvents)

        gate.ignoreChangedEventsUntilNextGesture()
        XCTAssertTrue(gate.ignoresChangedEvents)

        gate.begin()
        XCTAssertFalse(gate.ignoresChangedEvents)

        gate.ignoreChangedEventsUntilNextGesture()
        gate.end()
        XCTAssertFalse(gate.ignoresChangedEvents)
    }

    func testPagerUsesUnscaledGestureDirectionWhenDisplayedMovementIsSubthreshold() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200,
                visibleFractionalPageIndex: 1.001,
                rawGestureDisplacementX: 1,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200,
                visibleFractionalPageIndex: 0.999,
                rawGestureDisplacementX: -1,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            0
        )
    }

    func testPagerSensitivityDoesNotChangeSlowDragDestination() throws {
        func destination(sensitivity: CGFloat) throws -> Int {
            var state = SidebarSpacePagerScrollInputScalingState()
            let scaledEvent = try XCTUnwrap(state.scaledEvent(
                from: scrollEvent(horizontalDelta: 1),
                sensitivity: sensitivity
            ))
            let displayedOffset = 200 + scaledEvent.scrollingDeltaX

            return SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200,
                visibleFractionalPageIndex: displayedOffset / 200,
                rawGestureDisplacementX: state.cumulativeRawDisplacementX,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            )
        }

        XCTAssertEqual(try destination(sensitivity: 1), 2)
        XCTAssertEqual(try destination(sensitivity: 0.35), 2)
    }

    func testPagerTinyForwardMovementAdvancesAdjacentPage() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200,
                visibleFractionalPageIndex: 1.005,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
    }

    func testPagerTinyBackwardMovementRetreatsAdjacentPage() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 1.995,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            1
        )
    }

    func testPagerUsesProposedDirectionBeforeVisibleGeometryUpdates() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 201,
                visibleFractionalPageIndex: 1,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
    }

    func testPagerNoMovementKeepsCurrentPage() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 2,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
    }

    func testPagerUsesVelocityWhenOffsetsAreStationary() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 2,
                velocityX: 1_000,
                pageWidth: 200,
                pageCount: 5
            ),
            3
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 400,
                visibleFractionalPageIndex: 2,
                velocityX: -1_000,
                pageWidth: 200,
                pageCount: 5
            ),
            1
        )
    }

    func testPagerMeaningfulReleaseVelocityWinsOverResidualVisibleDirection() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200,
                visibleFractionalPageIndex: 1.01,
                rawGestureDisplacementX: 20,
                velocityX: -5_000,
                pageWidth: 200,
                pageCount: 5
            ),
            0
        )
    }

    func testPagerProposedDirectionWinsOverConflictingFallbackSignals() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 201,
                visibleFractionalPageIndex: 0.99,
                rawGestureDisplacementX: -20,
                velocityX: -5_000,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
    }

    func testPagerNeverSkipsMoreThanOnePagePerGesture() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 1_000,
                visibleFractionalPageIndex: 4.5,
                velocityX: 5_000,
                pageWidth: 200,
                pageCount: 6
            ),
            2
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 800,
                proposedOffsetX: 0,
                visibleFractionalPageIndex: 0,
                velocityX: -5_000,
                pageWidth: 200,
                pageCount: 6
            ),
            3
        )
    }

    func testPagerVisibleOffsetFallbackNeverSkipsMoreThanOnePage() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200,
                visibleFractionalPageIndex: 4.5,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 6
            ),
            2
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 800,
                proposedOffsetX: 800,
                visibleFractionalPageIndex: 0,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 6
            ),
            3
        )
    }

    func testPagerClampsAdjacentMovementAtBothEdges() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 0,
                proposedOffsetX: -1,
                visibleFractionalPageIndex: -0.001,
                velocityX: -1,
                pageWidth: 200,
                pageCount: 5
            ),
            0
        )

        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 800,
                proposedOffsetX: 801,
                visibleFractionalPageIndex: 4.001,
                velocityX: 1,
                pageWidth: 200,
                pageCount: 5
            ),
            4
        )
    }

    func testPagerTrackerCapturesAndResetsEachGestureOrigin() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 1.75

        tracker.transition(from: .idle, to: .tracking)
        XCTAssertTrue(tracker.acceptsDirectionalSnap)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.75)
        tracker.rawGestureDisplacementX = 12

        tracker.visibleFractionalPageIndex = 1.8
        tracker.transition(from: .tracking, to: .interacting)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.75)

        tracker.transition(from: .interacting, to: .decelerating)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.75)

        tracker.transition(from: .decelerating, to: .interacting)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.8)
        XCTAssertNil(tracker.rawGestureDisplacementX)

        tracker.transition(from: .interacting, to: .idle)
        XCTAssertFalse(tracker.acceptsDirectionalSnap)
        XCTAssertNil(tracker.gestureStartFractionalPageIndex)
        XCTAssertNil(tracker.rawGestureDisplacementX)

        tracker.transition(from: .idle, to: .tracking)
        tracker.transition(from: .tracking, to: .animating)
        XCTAssertTrue(tracker.acceptsDirectionalSnap)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.8)

        tracker.transition(from: .animating, to: .idle)
        XCTAssertFalse(tracker.acceptsDirectionalSnap)
        XCTAssertNil(tracker.gestureStartFractionalPageIndex)
    }

    func testPagerPreservesGestureDirectionThroughSnapAnimation() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 2

        tracker.transition(from: .idle, to: .tracking)
        tracker.rawGestureDisplacementX = 18
        tracker.visibleFractionalPageIndex = 2.04
        tracker.transition(from: .tracking, to: .interacting)
        tracker.transition(from: .interacting, to: .animating)

        XCTAssertTrue(tracker.acceptsDirectionalSnap)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 2)
        XCTAssertEqual(tracker.rawGestureDisplacementX, 18)
    }

    func testPagerAnchorsGestureInterruptingAnimationToPreviousDestination() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 1

        tracker.transition(from: .idle, to: .tracking)
        tracker.recordResolvedTargetPageIndex(2)
        tracker.transition(from: .interacting, to: .animating)

        tracker.visibleFractionalPageIndex = 1.2
        tracker.transition(from: .animating, to: .interacting)

        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.2)
        XCTAssertEqual(tracker.gestureSourcePageIndex, 2)
        XCTAssertNil(tracker.rawGestureDisplacementX)
        XCTAssertTrue(tracker.acceptsDirectionalSnap)
    }

    func testPagerPhysicalGestureBoundaryWorksWithoutScrollPhaseTransition() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 1

        tracker.beginPhysicalGesture()
        tracker.transition(from: .idle, to: .interacting)
        tracker.recordResolvedTargetPageIndex(2)

        tracker.visibleFractionalPageIndex = 1.2
        tracker.beginPhysicalGesture()

        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 1.2)
        XCTAssertEqual(tracker.gestureSourcePageIndex, 2)
        XCTAssertTrue(tracker.acceptsDirectionalSnap)

        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 240,
                proposedOffsetX: 241,
                gestureStartFractionalPageIndex: tracker.gestureStartFractionalPageIndex,
                gestureSourcePageIndex: tracker.gestureSourcePageIndex,
                visibleFractionalPageIndex: 1.205,
                rawGestureDisplacementX: 1,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            3
        )
    }

    func testPagerTinySwipeDuringAnimationMovesFromPreviousDestination() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 240,
                proposedOffsetX: 241,
                gestureStartFractionalPageIndex: 1.2,
                gestureSourcePageIndex: 2,
                visibleFractionalPageIndex: 1.205,
                rawGestureDisplacementX: 1,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            3
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 240,
                proposedOffsetX: 239,
                gestureStartFractionalPageIndex: 1.2,
                gestureSourcePageIndex: 2,
                visibleFractionalPageIndex: 1.195,
                rawGestureDisplacementX: -1,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            1
        )
    }

    func testPagerTreatsAnimationStartingAtIdleAsProgrammatic() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 2

        tracker.transition(from: .idle, to: .animating)

        XCTAssertFalse(tracker.acceptsDirectionalSnap)
        XCTAssertNil(tracker.gestureStartFractionalPageIndex)
        XCTAssertNil(tracker.rawGestureDisplacementX)
    }

    func testPagerCanMoveInwardFromBothEdges() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 0,
                proposedOffsetX: 1,
                visibleFractionalPageIndex: 0,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            1
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 800,
                proposedOffsetX: 799,
                visibleFractionalPageIndex: 4,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            3
        )
    }

    func testPagerIgnoresSubpointDirectionalNoise() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 200.2,
                visibleFractionalPageIndex: 1.001,
                velocityX: 19,
                pageWidth: 200,
                pageCount: 5
            ),
            1
        )
    }

    func testPagerMeasuresVisibleMovementFromGestureOrigin() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 400,
                gestureStartFractionalPageIndex: 1.999,
                visibleFractionalPageIndex: 1.999,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 400,
                proposedOffsetX: 400,
                gestureStartFractionalPageIndex: 1.999,
                visibleFractionalPageIndex: 2.004,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            3
        )
    }

    func testPagerUsesGestureOriginAsSourceDuringInterruptedDeceleration() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.targetPageIndex(
                originalOffsetX: 200,
                proposedOffsetX: 360,
                gestureStartFractionalPageIndex: 1.8,
                visibleFractionalPageIndex: 1.795,
                velocityX: 0,
                pageWidth: 200,
                pageCount: 5
            ),
            1
        )
    }

    func testPagerAlignsNonGestureTargetsToNearestPage() {
        XCTAssertEqual(
            SidebarSpacePagerSnap.nearestPageIndex(
                offsetX: 399,
                pageWidth: 200,
                pageCount: 5
            ),
            2
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.nearestPageIndex(
                offsetX: 600,
                pageWidth: 200,
                pageCount: 5
            ),
            3
        )
        XCTAssertEqual(
            SidebarSpacePagerSnap.nearestPageIndex(
                offsetX: 1_200,
                pageWidth: 200,
                pageCount: 5
            ),
            4
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

    func testInterpolatesResolvedChromeColorWithoutGlassSettings() throws {
        let themes = [
            SidebarChromeTheme(
                appearance: SidebarAppearance(tintSource: .custom, tintHex: "#000000"),
                spaceColorHex: "#FF0000"
            ),
            SidebarChromeTheme(
                appearance: SidebarAppearance(tintSource: .custom, tintHex: "#FFFFFF"),
                spaceColorHex: "#00FF00"
            )
        ]

        let color = try XCTUnwrap(SidebarChromeColor.interpolated(
            themes: themes,
            fractionalIndex: 0.5
        ))

        XCTAssertEqual(color.tintHex, "#808080")
    }

    func testResolvedChromeColorInterpolationClampsOutsidePageRange() throws {
        let themes = [
            SidebarChromeTheme(
                appearance: SidebarAppearance(tintSource: .custom, tintHex: "#102030"),
                spaceColorHex: "#000000"
            ),
            SidebarChromeTheme(
                appearance: SidebarAppearance(tintSource: .custom, tintHex: "#A0B0C0"),
                spaceColorHex: "#FFFFFF"
            )
        ]

        XCTAssertEqual(
            try XCTUnwrap(SidebarChromeColor.interpolated(
                themes: themes,
                fractionalIndex: -4
            )).tintHex,
            "#102030"
        )
        XCTAssertEqual(
            try XCTUnwrap(SidebarChromeColor.interpolated(
                themes: themes,
                fractionalIndex: 9
            )).tintHex,
            "#A0B0C0"
        )
    }

    func testResolvedChromeColorInterpolationTreatsNonFiniteIndexAsFirstPage() throws {
        let themes = [
            SidebarChromeTheme(
                appearance: SidebarAppearance(tintSource: .custom, tintHex: "#123456"),
                spaceColorHex: "#000000"
            ),
            SidebarChromeTheme(
                appearance: SidebarAppearance(tintSource: .custom, tintHex: "#ABCDEF"),
                spaceColorHex: "#FFFFFF"
            )
        ]

        for index in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(
                try XCTUnwrap(SidebarChromeColor.interpolated(
                    themes: themes,
                    fractionalIndex: index
                )).tintHex,
                "#123456"
            )
        }
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
            SidebarSpacePagerChrome.color(for: .activity, in: pages),
            SidebarChromeColor(theme: .standard)
        )
        XCTAssertEqual(
            SidebarSpacePagerChrome.liveStyle(for: .activity, in: pages),
            SidebarChromeLiveStyle(theme: .standard)
        )
        XCTAssertEqual(
            SidebarSpacePagerChrome.theme(for: .space(space.id), in: pages),
            SidebarChromeTheme.theme(for: space)
        )
        XCTAssertNil(
            SidebarSpacePagerChrome.theme(for: .space(UUID()), in: pages)
        )
        XCTAssertNil(
            SidebarSpacePagerChrome.color(for: .space(UUID()), in: pages)
        )
    }

    func testPagerLiveColorUsesDisplayedFractionalPageIndex() throws {
        let profileID = UUID()
        let lowerSpace = BrowserSpace(
            name: "Lower",
            colorHex: "#000000",
            sidebarAppearance: SidebarAppearance(tintSource: .spaceColor),
            profileID: profileID
        )
        let upperSpace = BrowserSpace(
            name: "Upper",
            colorHex: "#FFFFFF",
            sidebarAppearance: SidebarAppearance(tintSource: .spaceColor),
            profileID: profileID
        )
        let pages = [lowerSpace, upperSpace].enumerated().map { index, space in
            SidebarSpacePagerPageSnapshot.space(
                SidebarSpacePageSnapshot(
                    index: index,
                    space: space,
                    favoriteTabs: [],
                    pinnedTabs: [],
                    folders: [],
                    regularTabs: []
                )
            )
        }

        XCTAssertEqual(
            try XCTUnwrap(SidebarSpacePagerChrome.liveColor(at: 0.35, in: pages)).tintHex,
            "#595959"
        )
    }

    func testPagerLiveStyleUsesActivityAwarePageIndexing() throws {
        let profileID = UUID()
        let lowerSpace = BrowserSpace(
            name: "Lower",
            colorHex: "#000000",
            sidebarAppearance: SidebarAppearance(tintSource: .spaceColor),
            profileID: profileID
        )
        let upperSpace = BrowserSpace(
            name: "Upper",
            colorHex: "#FFFFFF",
            sidebarAppearance: SidebarAppearance(tintSource: .spaceColor),
            profileID: profileID
        )
        let pages: [SidebarSpacePagerPageSnapshot] = [
            .activity(SidebarActivityPageSnapshot(profiles: [], downloads: [], historyEntries: [])),
            .space(SidebarSpacePageSnapshot(
                index: 0,
                space: lowerSpace,
                favoriteTabs: [],
                pinnedTabs: [],
                folders: [],
                regularTabs: []
            )),
            .space(SidebarSpacePageSnapshot(
                index: 1,
                space: upperSpace,
                favoriteTabs: [],
                pinnedTabs: [],
                folders: [],
                regularTabs: []
            ))
        ]

        let themes = pages.map(\.chromeTheme)
        XCTAssertEqual(
            try XCTUnwrap(SidebarSpacePagerChrome.liveStyle(at: 0, themes: themes)),
            SidebarChromeLiveStyle(theme: .standard)
        )
        XCTAssertEqual(
            try XCTUnwrap(SidebarSpacePagerChrome.liveStyle(at: 1.5, themes: themes)).color.tintHex,
            "#808080"
        )
    }

    func testLiveStyleInterpolatesCompositorTreatmentStrength() throws {
        let lower = SidebarChromeTheme(
            appearance: SidebarAppearance(
                tintSource: .custom,
                tintHex: "#000000",
                base: SidebarGlassSettings(
                    glassOpacity: 0.2,
                    tintOpacity: 0.1,
                    colorNoiseLevel: 0.2,
                    colorNoiseScale: 0.3,
                    edgeOpacity: 0.9,
                    shadowOpacity: 0.8,
                    highlightOpacity: 0.3
                ),
                pinnedOverride: SidebarGlassSettings(
                    glassOpacity: 0.1,
                    tintOpacity: 0.3,
                    colorNoiseLevel: 0.4,
                    colorNoiseScale: 0.2,
                    edgeOpacity: 0.7,
                    shadowOpacity: 0.6,
                    highlightOpacity: 0.9
                )
            ),
            spaceColorHex: "#000000"
        )
        let upper = SidebarChromeTheme(
            appearance: SidebarAppearance(
                tintSource: .custom,
                tintHex: "#FFFFFF",
                base: SidebarGlassSettings(
                    glassOpacity: 0.8,
                    tintOpacity: 0.9,
                    colorNoiseLevel: 0.6,
                    colorNoiseScale: 0.9,
                    edgeOpacity: 0.1,
                    shadowOpacity: 0.2,
                    highlightOpacity: 0.7
                ),
                pinnedOverride: SidebarGlassSettings(
                    glassOpacity: 0.9,
                    tintOpacity: 0.7,
                    colorNoiseLevel: 0.8,
                    colorNoiseScale: 0.6,
                    edgeOpacity: 0.3,
                    shadowOpacity: 0.4,
                    highlightOpacity: 0.1
                )
            ),
            spaceColorHex: "#FFFFFF"
        )

        let style = try XCTUnwrap(SidebarChromeLiveStyle.interpolated(
            themes: [lower, upper],
            fractionalIndex: 0.5
        ))
        let lowerStyle = SidebarChromeLiveStyle(theme: lower)
        let upperStyle = SidebarChromeLiveStyle(theme: upper)

        XCTAssertEqual(style.color.tintHex, "#808080")
        XCTAssertEqual(style.baseTreatment.glassOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.baseTreatment.tintOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.baseTreatment.colorNoiseLevel, 0.4, accuracy: 0.0001)
        XCTAssertEqual(style.baseTreatment.colorNoiseScale, 0.6, accuracy: 0.0001)
        XCTAssertEqual(style.baseTreatment.edgeOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.baseTreatment.shadowOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.baseTreatment.highlightOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.glassOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.tintOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.colorNoiseLevel, 0.6, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.colorNoiseScale, 0.4, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.edgeOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.shadowOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(style.pinnedTreatment.highlightOpacity, 0.5, accuracy: 0.0001)
        XCTAssertEqual(
            style.baseForeground.lightModeWhiteAmount,
            (lowerStyle.baseForeground.lightModeWhiteAmount
                + upperStyle.baseForeground.lightModeWhiteAmount) / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            style.baseForeground.darkModeWhiteAmount,
            (lowerStyle.baseForeground.darkModeWhiteAmount
                + upperStyle.baseForeground.darkModeWhiteAmount) / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            style.pinnedForeground.lightModeWhiteAmount,
            (lowerStyle.pinnedForeground.lightModeWhiteAmount
                + upperStyle.pinnedForeground.lightModeWhiteAmount) / 2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            style.pinnedForeground.darkModeWhiteAmount,
            (lowerStyle.pinnedForeground.darkModeWhiteAmount
                + upperStyle.pinnedForeground.darkModeWhiteAmount) / 2,
            accuracy: 0.0001
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
        let keptIdentity = presentationIdentity(for: keptTabID)
        let prunedIdentity = presentationIdentity(for: prunedTabID)
        let state = BrowserContentPresentationState()
        let image = NSImage(size: NSSize(width: 320, height: 200))

        state.storeSnapshot(image, for: keptIdentity)
        state.storeSnapshot(NSImage(size: NSSize(width: 120, height: 80)), for: prunedIdentity)

        XCTAssertEqual(state.snapshot(for: keptIdentity)?.size, image.size)

        state.removeSnapshots(keeping: [keptIdentity])

        XCTAssertNotNil(state.snapshot(for: keptIdentity))
        XCTAssertNil(state.snapshot(for: prunedIdentity))
    }

    @MainActor
    func testPresentationStateNeverReturnsSnapshotForPreviousProfileIdentity() {
        let tabID = UUID()
        let oldIdentity = presentationIdentity(for: tabID)
        let newIdentity = WebContentSessionIdentity(
            tabID: tabID,
            spaceID: oldIdentity.spaceID,
            profileID: UUID(),
            websiteDataStoreID: UUID()
        )
        let state = BrowserContentPresentationState()
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: oldIdentity)

        XCTAssertNil(state.snapshot(for: newIdentity))
        state.storeSnapshot(NSImage(size: NSSize(width: 640, height: 400)), for: newIdentity)
        XCTAssertNil(state.snapshot(for: oldIdentity))
        XCTAssertEqual(state.snapshot(for: newIdentity)?.size, NSSize(width: 640, height: 400))
    }

    @MainActor
    func testPresentationStateStartsSnapshotHandoffOnlyForCachedTabs() {
        let cachedTabID = UUID()
        let uncachedTabID = UUID()
        let cachedIdentity = presentationIdentity(for: cachedTabID)
        let uncachedIdentity = presentationIdentity(for: uncachedTabID)
        let state = BrowserContentPresentationState()

        XCTAssertNil(state.beginSnapshotHandoff(to: uncachedIdentity))
        XCTAssertNil(state.snapshotHandoffTabID)

        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: cachedIdentity)
        XCTAssertNotNil(state.beginSnapshotHandoff(to: cachedIdentity))
        XCTAssertEqual(state.snapshotHandoffTabID, cachedTabID)
    }

    @MainActor
    func testPresentationStateIgnoresStaleSnapshotHandoffCompletion() throws {
        let firstTabID = UUID()
        let secondTabID = UUID()
        let firstIdentity = presentationIdentity(for: firstTabID)
        let secondIdentity = presentationIdentity(for: secondTabID)
        let state = BrowserContentPresentationState()
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: firstIdentity)
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: secondIdentity)

        let staleHandoffID = try XCTUnwrap(state.beginSnapshotHandoff(to: firstIdentity))
        _ = state.beginSnapshotHandoff(to: secondIdentity)

        state.completeSnapshotHandoff(staleHandoffID, for: firstIdentity)

        XCTAssertEqual(state.snapshotHandoffTabID, secondTabID)
    }

    @MainActor
    func testPresentationStateClearsSnapshotHandoffWhenSnapshotIsPruned() {
        let prunedTabID = UUID()
        let prunedIdentity = presentationIdentity(for: prunedTabID)
        let state = BrowserContentPresentationState()
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: prunedIdentity)
        state.beginSnapshotHandoff(to: prunedIdentity)

        state.removeSnapshots(keeping: [])

        XCTAssertNil(state.snapshotHandoffTabID)
    }

    @MainActor
    func testPresentationStateExpiresUncompletedSnapshotHandoff() async throws {
        let tabID = UUID()
        let identity = presentationIdentity(for: tabID)
        let state = BrowserContentPresentationState(snapshotHandoffExpirationNanoseconds: 1_000_000)
        state.storeSnapshot(NSImage(size: NSSize(width: 320, height: 200)), for: identity)

        XCTAssertNotNil(state.beginSnapshotHandoff(to: identity))
        XCTAssertEqual(state.snapshotHandoffTabID, tabID)

        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertNil(state.snapshotHandoffTabID)
    }

    private func presentationIdentity(for tabID: TabID) -> WebContentSessionIdentity {
        WebContentSessionIdentity(
            tabID: tabID,
            spaceID: tabID,
            profileID: tabID,
            websiteDataStoreID: tabID
        )
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

    private func scrollEvent(
        horizontalDelta: Int32,
        verticalDelta: Int32 = 0
    ) -> NSEvent {
        let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: verticalDelta,
            wheel2: horizontalDelta,
            wheel3: 0
        )!
        // CG scroll phase 2 maps to NSEvent.Phase.changed. Copying the event
        // preserves that encoding; production code never reconstructs it.
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        return NSEvent(cgEvent: cgEvent)!
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
