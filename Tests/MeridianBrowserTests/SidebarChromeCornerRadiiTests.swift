@testable import MeridianCore
import XCTest

final class SidebarChromeCornerRadiiTests: XCTestCase {
    func testFloatingSidebarRoundsAllCorners() {
        XCTAssertEqual(
            SidebarChromeCornerRadii.resolved(isPinned: false, edge: .left, radius: 12),
            SidebarChromeCornerRadii(
                topLeading: 12,
                topTrailing: 12,
                bottomLeading: 12,
                bottomTrailing: 12
            )
        )
    }

    func testPinnedLeftSidebarRoundsOnlyLeftWindowCorners() {
        XCTAssertEqual(
            SidebarChromeCornerRadii.resolved(isPinned: true, edge: .left, radius: 12),
            SidebarChromeCornerRadii(
                topLeading: 12,
                topTrailing: 0,
                bottomLeading: 12,
                bottomTrailing: 0
            )
        )
    }

    func testPinnedRightSidebarRoundsOnlyRightWindowCorners() {
        XCTAssertEqual(
            SidebarChromeCornerRadii.resolved(isPinned: true, edge: .right, radius: 12),
            SidebarChromeCornerRadii(
                topLeading: 0,
                topTrailing: 12,
                bottomLeading: 0,
                bottomTrailing: 12
            )
        )
    }
}
