import CoreGraphics
@testable import MeridianCore
import XCTest

final class SidebarSpacePagerWindowTests: XCTestCase {
    func testVisibleIndicesOnlyIncludeSelectedAndNeighbors() {
        XCTAssertEqual(SidebarSpacePagerWindow.visibleIndices(selectedIndex: nil, count: 4), [])
        XCTAssertEqual(SidebarSpacePagerWindow.visibleIndices(selectedIndex: 0, count: 4), [0, 1])
        XCTAssertEqual(SidebarSpacePagerWindow.visibleIndices(selectedIndex: 2, count: 5), [1, 2, 3])
        XCTAssertEqual(SidebarSpacePagerWindow.visibleIndices(selectedIndex: 3, count: 4), [2, 3])
        XCTAssertEqual(SidebarSpacePagerWindow.visibleIndices(selectedIndex: 4, count: 4), [])
    }

    func testVisualOffsetMapsPositiveSwipeTowardNextSpace() {
        XCTAssertEqual(
            SidebarSpacePagerWindow.visualOffset(
                for: 24,
                pageWidth: 240,
                canMovePrevious: true,
                canMoveNext: true
            ),
            -24
        )

        XCTAssertEqual(
            SidebarSpacePagerWindow.visualOffset(
                for: -24,
                pageWidth: 240,
                canMovePrevious: true,
                canMoveNext: true
            ),
            24
        )
    }

    func testVisualOffsetAppliesResistanceAtEdges() {
        XCTAssertEqual(
            SidebarSpacePagerWindow.visualOffset(
                for: 40,
                pageWidth: 240,
                canMovePrevious: true,
                canMoveNext: false
            ),
            -40 * SidebarSpacePagerMetrics.edgeResistanceRatio
        )

        XCTAssertEqual(
            SidebarSpacePagerWindow.visualOffset(
                for: -40,
                pageWidth: 240,
                canMovePrevious: false,
                canMoveNext: true
            ),
            40 * SidebarSpacePagerMetrics.edgeResistanceRatio
        )
    }
}
