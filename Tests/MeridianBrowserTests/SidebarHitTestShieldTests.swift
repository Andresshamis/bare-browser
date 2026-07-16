import AppKit
@testable import MeridianCore
import WebKit
import XCTest

@MainActor
final class SidebarHitTestShieldTests: XCTestCase {
    func testShieldConsumesHitsInsideRoundedSidebarBounds() {
        let shield = SidebarHitTestShieldNSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        shield.cornerRadius = 12

        XCTAssertTrue(shield.hitTest(NSPoint(x: 120, y: 200)) === shield)
        XCTAssertTrue(shield.hitTest(NSPoint(x: 12, y: 12)) === shield)
    }

    func testShieldIgnoresHitsOutsideRoundedSidebarShape() {
        let shield = SidebarHitTestShieldNSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        shield.cornerRadius = 12

        XCTAssertNil(shield.hitTest(NSPoint(x: -1, y: 200)))
        XCTAssertNil(shield.hitTest(NSPoint(x: 2, y: 2)))
    }

    func testShieldSuppressesWebContentEventsInsideBounds() {
        let shield = SidebarHitTestShieldNSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        let webView = WKWebView(frame: .zero)
        let webContentSubview = NSView(frame: .zero)
        webView.addSubview(webContentSubview)

        XCTAssertTrue(
            shield.shouldSuppressWebContentEvent(
                localPoint: NSPoint(x: 120, y: 200),
                targetView: webContentSubview
            )
        )
    }

    func testShieldDoesNotSuppressNonWebEventsInsideBounds() {
        let shield = SidebarHitTestShieldNSView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))

        XCTAssertFalse(
            shield.shouldSuppressWebContentEvent(
                localPoint: NSPoint(x: 120, y: 200),
                targetView: NSView(frame: .zero)
            )
        )
    }

    func testWebContentExclusionRegionFramesLeftFloatingSidebar() {
        let region = WebContentMouseExclusionRegion(edge: .left, width: 280, inset: 8, cornerRadius: 12)

        XCTAssertEqual(
            region.frame(in: CGRect(x: 0, y: 0, width: 1000, height: 700)),
            CGRect(x: 8, y: 8, width: 280, height: 684)
        )
    }

    func testWebContentExclusionRegionFramesRightFloatingSidebar() {
        let region = WebContentMouseExclusionRegion(edge: .right, width: 280, inset: 8, cornerRadius: 12)

        XCTAssertEqual(
            region.frame(in: CGRect(x: 0, y: 0, width: 1000, height: 700)),
            CGRect(x: 712, y: 8, width: 280, height: 684)
        )
    }

    func testWebContentBlockerConsumesHitsInsideRoundedShape() {
        let blocker = WebContentHitTestBlockerView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        blocker.cornerRadius = 12

        XCTAssertTrue(blocker.hitTest(NSPoint(x: 120, y: 200)) === blocker)
        XCTAssertNil(blocker.hitTest(NSPoint(x: 2, y: 2)))
    }

    func testHiddenWebContentBlockerDoesNotConsumeHits() {
        let blocker = WebContentHitTestBlockerView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        blocker.isHidden = true

        XCTAssertNil(blocker.hitTest(NSPoint(x: 120, y: 200)))
    }

    func testClearingWebContentExclusionRestoresHitsToWebView() {
        let container = BrowserWebViewContainerView(frame: NSRect(x: 0, y: 0, width: 1000, height: 700))
        let webView = WKWebView(frame: container.bounds)
        container.attach(webView)
        container.mouseExclusionRegion = WebContentMouseExclusionRegion(
            edge: .left,
            width: 280,
            inset: 8,
            cornerRadius: 12
        )

        let formerlyBlockedPoint = NSPoint(x: 120, y: 200)
        XCTAssertTrue(container.hitTest(formerlyBlockedPoint) is WebContentHitTestBlockerView)

        container.mouseExclusionRegion = nil

        let restoredHit = container.hitTest(formerlyBlockedPoint)
        XCTAssertNotNil(restoredHit)
        XCTAssertFalse(restoredHit is WebContentHitTestBlockerView)
        XCTAssertTrue(restoredHit.map(viewBelongsToWebView) == true)
    }

    private func viewBelongsToWebView(_ view: NSView) -> Bool {
        var candidate: NSView? = view
        while let current = candidate {
            if current is WKWebView {
                return true
            }
            candidate = current.superview
        }

        return false
    }
}
