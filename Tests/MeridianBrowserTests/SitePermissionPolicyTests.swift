import Foundation
import MeridianCore
import XCTest

final class SitePermissionPolicyTests: XCTestCase {
    func testModelsRequiredPermissionKindsAndSupport() {
        let policy = SitePermissionPolicy()

        XCTAssertEqual(policy.support(for: .camera), .webKitPermissionDelegate)
        XCTAssertEqual(policy.support(for: .microphone), .webKitPermissionDelegate)
        XCTAssertEqual(policy.support(for: .geolocation), .unsupported)
        XCTAssertEqual(policy.support(for: .notifications), .unsupported)
        XCTAssertEqual(policy.support(for: .autoplay), .webKitConfiguration)
        XCTAssertEqual(policy.support(for: .popupWindow), .webKitUIDelegate)
    }

    func testOriginStripsSensitiveURLComponents() {
        let origin = SitePermissionOrigin(
            url: URL(string: "https://user:pass@Example.com/private/path?token=secret#frag")!
        )

        XCTAssertEqual(origin?.scheme, "https")
        XCTAssertEqual(origin?.host, "example.com")
        XCTAssertNil(origin?.port)
        XCTAssertEqual(origin?.serializedOrigin, "https://example.com")
        XCTAssertFalse(origin?.serializedOrigin.contains("user") ?? true)
        XCTAssertFalse(origin?.serializedOrigin.contains("token") ?? true)
        XCTAssertFalse(origin?.serializedOrigin.contains("/private") ?? true)
        XCTAssertFalse(origin?.serializedOrigin.contains("frag") ?? true)
    }

    func testDefaultPolicyAsksForSupportedDelegatesAndDeniesUnsupported() {
        let policy = SitePermissionPolicy()
        let profileID = UUID()
        let origin = SitePermissionOrigin(url: URL(string: "https://example.com")!)!
        let cameraRequest = SitePermissionRequest(
            kind: .camera,
            origin: origin,
            profileID: profileID,
            isEphemeralProfile: false
        )
        let locationRequest = SitePermissionRequest(
            kind: .geolocation,
            origin: origin,
            profileID: profileID,
            isEphemeralProfile: false
        )

        XCTAssertEqual(policy.evaluation(for: cameraRequest, settings: []), .ask)
        XCTAssertEqual(
            policy.evaluation(for: locationRequest, settings: []),
            .deny(reason: "Location permissions are not supported by Meridian on this WebKit version.")
        )
        XCTAssertTrue(policy.requiresUserActionForAutoplay)
    }

    func testStoredAllowAndDenyDecisionsOverrideAskDefault() {
        let policy = SitePermissionPolicy()
        let profileID = UUID()
        let origin = SitePermissionOrigin(url: URL(string: "https://example.com:8443/chat")!)!
        let request = SitePermissionRequest(
            kind: .microphone,
            origin: origin,
            profileID: profileID,
            isEphemeralProfile: false
        )
        let allow = SitePermissionSetting(
            kind: .microphone,
            origin: origin,
            profileID: profileID,
            decision: .allow,
            persistsBeyondSession: true
        )
        let deny = SitePermissionSetting(
            kind: .microphone,
            origin: origin,
            profileID: profileID,
            decision: .deny,
            persistsBeyondSession: true
        )

        XCTAssertEqual(policy.evaluation(for: request, settings: [allow]), .allow)
        XCTAssertEqual(
            policy.evaluation(for: request, settings: [allow, deny]),
            .deny(reason: "Microphone is blocked for this site.")
        )
    }

    func testPrivateProfileSettingsAreSessionOnly() {
        let policy = SitePermissionPolicy()
        let request = SitePermissionRequest(
            kind: .camera,
            origin: SitePermissionOrigin(url: URL(string: "https://example.com")!)!,
            profileID: UUID(),
            isEphemeralProfile: true
        )

        let setting = policy.setting(for: request, decision: .allow)

        XCTAssertEqual(setting?.decision, .allow)
        XCTAssertEqual(setting?.persistsBeyondSession, false)
    }
}
