import Foundation
@testable import MeridianCore
import XCTest

final class SidebarSpacePagerGestureTests: XCTestCase {
    func testPhysicalGestureLifecycleIssuesMonotonicTokens() throws {
        var lifecycle = SidebarSpacePagerPhysicalGestureLifecycle()

        let firstID = lifecycle.begin()
        XCTAssertEqual(lifecycle.activeGestureID, firstID)
        XCTAssertEqual(
            try XCTUnwrap(lifecycle.finish(for: .physicalEnded)),
            firstID
        )
        XCTAssertFalse(lifecycle.isActive)

        let secondID = lifecycle.begin()
        XCTAssertGreaterThan(secondID, firstID)
        XCTAssertEqual(
            try XCTUnwrap(lifecycle.finish(for: .physicalCancelled)),
            secondID
        )
    }

    func testPhysicalEventBoundariesEndPhysicalTrackpadGesture() throws {
        let reasons: [SidebarSpacePagerPhysicalGestureEndReason] = [
            .physicalEnded,
            .physicalCancelled,
            .momentumBegan,
            .unphasedInput
        ]

        for reason in reasons {
            var lifecycle = SidebarSpacePagerPhysicalGestureLifecycle()
            let gestureID = lifecycle.begin()

            XCTAssertEqual(
                try XCTUnwrap(lifecycle.finish(for: reason)),
                gestureID
            )
            XCTAssertFalse(lifecycle.isActive)
        }
    }

    func testAdjustedDeltaHasOneDeterministicDirectionContract() {
        XCTAssertEqual(
            SidebarSpacePagerHorizontalIntent.intent(
                forAdjustedDisplacement: -3,
                minimumDisplacement: 2
            ),
            .backward
        )
        XCTAssertEqual(
            SidebarSpacePagerHorizontalIntent.intent(
                forAdjustedDisplacement: 3,
                minimumDisplacement: 2
            ),
            .forward
        )
        XCTAssertNil(SidebarSpacePagerHorizontalIntent.intent(
            forAdjustedDisplacement: 1,
            minimumDisplacement: 2
        ))
    }

    func testAppKitWheelDirectionRoutesForwardToCreationAndBackwardToPaging() throws {
        let forwardInput = try XCTUnwrap(SidebarSpacePagerHorizontalInputSample(
            scrollingDeltaX: -3
        ))
        let backwardInput = try XCTUnwrap(SidebarSpacePagerHorizontalInputSample(
            scrollingDeltaX: 3
        ))

        var forwardSession = SidebarSpaceCreationGestureSession()
        forwardSession.begin(canPullForward: true)
        guard case .pulling = forwardSession.routeAdjustedDelta(
            forwardInput.adjustedDisplacementX,
            pageWidth: 300
        ) else {
            return XCTFail("Forward AppKit input must enter creation")
        }

        var backwardSession = SidebarSpaceCreationGestureSession()
        backwardSession.begin(canPullForward: true)
        XCTAssertEqual(
            backwardSession.routeAdjustedDelta(
                backwardInput.adjustedDisplacementX,
                pageWidth: 300
            ),
            .pagingBackward
        )
    }

    func testForwardWheelInputCanCreateUnlimitedConsecutiveSpaces() throws {
        var pageCount = 3
        var selectedPageIndex = pageCount - 1
        let initialForwardInput = try XCTUnwrap(
            SidebarSpacePagerHorizontalInputSample(scrollingDeltaX: -3)
        )
        let remainingForwardInput = try XCTUnwrap(
            SidebarSpacePagerHorizontalInputSample(
                scrollingDeltaX:
                    -(SidebarSpacePagerMetrics.creationPullThreshold - 3)
            )
        )

        for _ in 0..<12 {
            XCTAssertEqual(selectedPageIndex, pageCount - 1)

            var session = SidebarSpaceCreationGestureSession()
            session.begin(canPullForward: true)
            guard case .pulling = session.routeAdjustedDelta(
                initialForwardInput.adjustedDisplacementX,
                pageWidth: 300
            ) else {
                return XCTFail("Every final page must allow another creation pull")
            }
            guard case .pulling(let update) = session.routeAdjustedDelta(
                remainingForwardInput.adjustedDisplacementX,
                pageWidth: 300
            ) else {
                return XCTFail("Creation pull must stay forward")
            }
            XCTAssertEqual(update.progress, 1, accuracy: 0.0001)
            XCTAssertEqual(session.finishPull(cancelled: false), .create)

            pageCount += 1
            selectedPageIndex = pageCount - 1
        }

        XCTAssertEqual(pageCount, 15)
        XCTAssertEqual(selectedPageIndex, 14)
    }

    func testNarratedLastSpaceSequenceRemainsDeterministicWhenRepeated() throws {
        var session = SidebarSpaceCreationGestureSession()

        for _ in 0..<4 {
            session.begin(canPullForward: true)
            XCTAssertEqual(
                session.routeAdjustedDelta(-3, pageWidth: 300),
                .pagingBackward
            )
            XCTAssertEqual(
                session.routeAdjustedDelta(100, pageWidth: 300),
                .pagingBackward
            )
            session.end()

            session.begin(canPullForward: true)
            guard case .pulling = session.routeAdjustedDelta(3, pageWidth: 300) else {
                return XCTFail("Forward input from the final space must start creation")
            }
            guard case .pulling(let update) = session.routeAdjustedDelta(
                SidebarSpacePagerMetrics.creationPullThreshold - 3,
                pageWidth: 300
            ) else {
                return XCTFail("Established creation must remain creation")
            }
            XCTAssertEqual(update.progress, 1, accuracy: 0.0001)
            XCTAssertEqual(session.finishPull(cancelled: false), .create)
            session.end()
        }

        session.begin(canPullForward: true)
        XCTAssertEqual(
            session.routeAdjustedDelta(-3, pageWidth: 300),
            .pagingBackward
        )
    }

    func testBackwardInputRoutesBeforeAnyGeometryCanParticipate() {
        var session = SidebarSpaceCreationGestureSession()
        session.begin(canPullForward: true)

        XCTAssertEqual(
            session.routeAdjustedDelta(-2, pageWidth: 300),
            .pagingBackward
        )
        XCTAssertFalse(session.isPulling)
        XCTAssertEqual(session.finishPull(cancelled: false), .none)
    }

    func testSubthresholdInputIsNotForcedIntoCreationOnRelease() {
        var session = SidebarSpaceCreationGestureSession()
        session.begin(canPullForward: true)

        XCTAssertEqual(
            session.routeAdjustedDelta(1, pageWidth: 300),
            .pending
        )
        XCTAssertEqual(session.finishPull(cancelled: false), .none)
    }

    func testCreationPullReversalCancelsForRemainderOfPhysicalGesture() {
        var session = SidebarSpaceCreationGestureSession()
        session.begin(canPullForward: true)

        guard case .pulling = session.routeAdjustedDelta(30, pageWidth: 300) else {
            return XCTFail("Expected creation pull")
        }
        XCTAssertEqual(
            session.routeAdjustedDelta(-31, pageWidth: 300),
            .cancelled
        )
        XCTAssertEqual(
            session.routeAdjustedDelta(200, pageWidth: 300),
            .cancelled
        )
        XCTAssertTrue(session.isCancelled)
        XCTAssertEqual(session.finishPull(cancelled: false), .cancel)
    }

    func testSwiftUIIdleCannotClearAnActivePhysicalGesture() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 2
        tracker.beginPhysicalGesture(id: 1)
        tracker.adjustedGestureDisplacementX = 12

        tracker.transition(from: .interacting, to: .idle)

        XCTAssertEqual(tracker.activePhysicalGestureID, 1)
        XCTAssertTrue(tracker.acceptsDirectionalSnap)
        XCTAssertEqual(tracker.gestureStartFractionalPageIndex, 2)
        XCTAssertEqual(tracker.adjustedGestureDisplacementX, 12)

        tracker.endPhysicalGesture(id: 1)
        XCTAssertNil(tracker.activePhysicalGestureID)
        XCTAssertFalse(tracker.acceptsDirectionalSnap)
    }

    func testDeferredCompletionCannotEndANewerGesture() {
        let tracker = SidebarSpacePagerGeometryTracker()
        tracker.visibleFractionalPageIndex = 1
        tracker.beginPhysicalGesture(id: 7)
        tracker.recordResolvedTargetPageIndex(2)

        tracker.visibleFractionalPageIndex = 1.2
        tracker.beginPhysicalGesture(id: 8)
        tracker.endPhysicalGesture(id: 7)

        XCTAssertEqual(tracker.activePhysicalGestureID, 8)
        XCTAssertTrue(tracker.acceptsDirectionalSnap)
        XCTAssertEqual(tracker.gestureSourcePageIndex, 2)

        tracker.endPhysicalGesture(id: 8)
        XCTAssertNil(tracker.activePhysicalGestureID)
    }

    func testVisualLastPageCanEnableCreationWithoutSelectionState() {
        XCTAssertTrue(SidebarSpaceCreationPullEligibility.canBegin(
            creationIsAvailable: true,
            scrollIsIdle: true,
            currentOffsetX: 600,
            lastPageOffsetX: 600
        ))
        XCTAssertFalse(SidebarSpaceCreationPullEligibility.canBegin(
            creationIsAvailable: false,
            scrollIsIdle: true,
            currentOffsetX: 600,
            lastPageOffsetX: 600
        ))
    }
}
