import XCTest
@testable import MeridianCore

final class BrowserPasskeyAccessTests: XCTestCase {
    func testRequestsAuthorizationOnlyForEntitledUndeterminedBrowser() {
        XCTAssertTrue(
            BrowserPasskeyAccessPolicy.shouldRequestAuthorization(
                isBrowserEntitled: true,
                state: .notDetermined,
                didRequestThisLaunch: false
            )
        )
    }

    func testDoesNotRequestAuthorizationWithoutBrowserEntitlement() {
        XCTAssertFalse(
            BrowserPasskeyAccessPolicy.shouldRequestAuthorization(
                isBrowserEntitled: false,
                state: .notDetermined,
                didRequestThisLaunch: false
            )
        )
    }

    func testDoesNotRepeatOrOverridePasskeyAuthorizationDecision() {
        XCTAssertFalse(
            BrowserPasskeyAccessPolicy.shouldRequestAuthorization(
                isBrowserEntitled: true,
                state: .notDetermined,
                didRequestThisLaunch: true
            )
        )
        XCTAssertFalse(
            BrowserPasskeyAccessPolicy.shouldRequestAuthorization(
                isBrowserEntitled: true,
                state: .authorized,
                didRequestThisLaunch: false
            )
        )
        XCTAssertFalse(
            BrowserPasskeyAccessPolicy.shouldRequestAuthorization(
                isBrowserEntitled: true,
                state: .denied,
                didRequestThisLaunch: false
            )
        )
    }
}
