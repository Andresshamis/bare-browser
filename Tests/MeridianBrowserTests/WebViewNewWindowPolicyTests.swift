import MeridianCore
import WebKit
import XCTest

final class WebViewNewWindowPolicyTests: XCTestCase {
    func testUserInitiatedTargetFrameNavigationsOpenInCurrentTab() {
        XCTAssertTrue(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .linkActivated,
                sourceFrameIsMainFrame: false
            )
        )
        XCTAssertTrue(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .formSubmitted,
                sourceFrameIsMainFrame: false
            )
        )
        XCTAssertTrue(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .formResubmitted,
                sourceFrameIsMainFrame: false
            )
        )
    }

    func testMainFrameScriptedTargetFrameNavigationOpensInCurrentTab() {
        XCTAssertTrue(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .other,
                sourceFrameIsMainFrame: true
            )
        )
    }

    func testSubframeAndHistoryTargetFrameNavigationsStillRequirePopupHandling() {
        XCTAssertFalse(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .other,
                sourceFrameIsMainFrame: false
            )
        )
        XCTAssertFalse(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .reload,
                sourceFrameIsMainFrame: true
            )
        )
        XCTAssertFalse(
            WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                navigationType: .backForward,
                sourceFrameIsMainFrame: true
            )
        )
    }
}
