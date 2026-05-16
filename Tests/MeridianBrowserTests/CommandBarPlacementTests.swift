import CoreGraphics
@testable import MeridianCore
import XCTest

final class CommandBarPlacementTests: XCTestCase {
    func testDefaultOriginIsCenteredNearTop() {
        let origin = CommandBarPlacement.resolvedOrigin(
            persistedX: CommandBarPlacement.unsetCoordinate,
            persistedY: CommandBarPlacement.unsetCoordinate,
            containerSize: CGSize(width: 900, height: 620)
        )

        XCTAssertEqual(origin.x, 140)
        XCTAssertEqual(origin.y, CommandBarPlacement.defaultTopMargin)
    }

    func testPersistedOriginIsClampedInsideContainer() {
        let origin = CommandBarPlacement.resolvedOrigin(
            persistedX: 10_000,
            persistedY: 10_000,
            containerSize: CGSize(width: 900, height: 620)
        )

        XCTAssertEqual(origin.x, 900 - CommandBarPlacement.boundingSize.width - CommandBarPlacement.margin)
        XCTAssertEqual(origin.y, 620 - CommandBarPlacement.boundingSize.height - CommandBarPlacement.margin)
    }

    func testClampCentersWhenContainerIsSmallerThanCommandBar() {
        let origin = CommandBarPlacement.clampedOrigin(
            CGPoint(x: 100, y: 100),
            itemSize: CGSize(width: 620, height: 260),
            containerSize: CGSize(width: 500, height: 200)
        )

        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 0)
    }
}
