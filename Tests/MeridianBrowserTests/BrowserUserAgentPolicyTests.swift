import Foundation
import MeridianCore
import XCTest

final class BrowserUserAgentPolicyTests: XCTestCase {
    func testDesktopSafariUserAgentAdvertisesSafariCompatibility() {
        let userAgent = BrowserUserAgentPolicy.desktopSafariUserAgent(
            osVersion: OperatingSystemVersion(majorVersion: 26, minorVersion: 4, patchVersion: 1)
        )

        XCTAssertTrue(userAgent.contains("Macintosh"))
        XCTAssertTrue(userAgent.contains("AppleWebKit/605.1.15"))
        XCTAssertTrue(userAgent.contains("Version/26.4 Safari/605.1.15"))
        XCTAssertFalse(userAgent.contains("Meridian"))
    }
}
