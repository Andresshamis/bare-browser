@testable import MeridianCore
import XCTest

final class SidebarTabDropStateTests: XCTestCase {
    func testCompletedDropSuppressesStaleTargetCallbacksUntilNextDrag() {
        var state = SidebarTabDropState()

        state.beginDrag()
        state.target("tabs-before-second")
        XCTAssertEqual(state.activeSlotID, "tabs-before-second")

        state.finishDrop()
        XCTAssertNil(state.activeSlotID)

        state.target("tabs-before-third")
        XCTAssertNil(state.activeSlotID)

        state.beginDrag()
        state.target("tabs-before-third")
        XCTAssertEqual(state.activeSlotID, "tabs-before-third")
    }

    func testClearingDifferentSlotDoesNotRemoveCurrentTarget() {
        var state = SidebarTabDropState()

        state.beginDrag()
        state.target("current")
        state.clearTarget("other")

        XCTAssertEqual(state.activeSlotID, "current")
    }
}
