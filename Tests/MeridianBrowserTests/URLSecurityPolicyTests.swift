import Foundation
import MeridianCore
import XCTest

final class URLSecurityPolicyTests: XCTestCase {
    func testAllowsHTTPAndHTTPSInWebView() {
        let policy = URLSecurityPolicy()

        XCTAssertEqual(policy.decision(for: URL(string: "https://example.com")!), .allowInWebView)
        XCTAssertEqual(policy.decision(for: URL(string: "http://localhost:3000")!), .allowInWebView)
    }

    func testBlocksUnsafeScriptSchemes() {
        let policy = URLSecurityPolicy()

        XCTAssertEqual(
            policy.decision(for: URL(string: "javascript:alert(1)")!),
            .block(reason: "Blocked unsafe URL scheme: javascript.")
        )
    }

    func testRequiresConfirmationForExternalAndLocalSchemes() {
        let policy = URLSecurityPolicy()
        let externalURL = URL(string: "mailto:hello@example.com")!
        let fileURL = URL(fileURLWithPath: "/tmp/test.html")

        XCTAssertEqual(
            policy.decision(for: externalURL),
            .requireExternalApplicationConfirmation
        )
        XCTAssertEqual(
            policy.confirmationKind(for: externalURL),
            .externalApplication
        )
        XCTAssertEqual(
            policy.decision(for: fileURL),
            .requireLocalFileConfirmation
        )
        XCTAssertEqual(policy.confirmationKind(for: fileURL), .localFile)
    }

    func testFlagsNonLocalHTTPAsInsecureTransport() {
        let policy = URLSecurityPolicy()

        XCTAssertTrue(policy.isInsecureTransport(URL(string: "http://example.com")!))
        XCTAssertFalse(policy.isInsecureTransport(URL(string: "http://127.0.0.1:8080")!))
        XCTAssertFalse(policy.isInsecureTransport(URL(string: "https://example.com")!))
    }

    func testBuildsHTTPSUpgradeCandidateForNonLocalHTTP() throws {
        let policy = URLSecurityPolicy()
        let originalURL = URL(string: "http://example.com:8080/path/article?view=reader#section")!

        let upgradedURL = try XCTUnwrap(policy.httpsUpgradeCandidate(for: originalURL))

        XCTAssertEqual(upgradedURL, URL(string: "https://example.com:8080/path/article?view=reader#section")!)
        XCTAssertTrue(policy.isHTTPSUpgradeCandidate(upgradedURL, for: originalURL))
    }

    func testDoesNotUpgradeLocalOrAlreadySecureURLs() {
        let policy = URLSecurityPolicy()

        XCTAssertNil(policy.httpsUpgradeCandidate(for: URL(string: "http://localhost:3000")!))
        XCTAssertNil(policy.httpsUpgradeCandidate(for: URL(string: "http://127.0.0.1:8080")!))
        XCTAssertNil(policy.httpsUpgradeCandidate(for: URL(string: "http://[::1]:8080")!))
        XCTAssertNil(policy.httpsUpgradeCandidate(for: URL(string: "https://example.com")!))
    }

    func testCertificateAndCancellationErrorsDoNotFallbackToHTTP() {
        let policy = URLSecurityPolicy()
        let certificateError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorServerCertificateUntrusted
        )
        let cancelledError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled
        )
        let userCancelledAuthenticationError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorUserCancelledAuthentication
        )
        let connectionError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCannotConnectToHost
        )

        XCTAssertFalse(policy.shouldFallbackToHTTP(afterHTTPSUpgradeError: certificateError))
        XCTAssertFalse(policy.shouldFallbackToHTTP(afterHTTPSUpgradeError: cancelledError))
        XCTAssertFalse(policy.shouldFallbackToHTTP(afterHTTPSUpgradeError: userCancelledAuthenticationError))
        XCTAssertTrue(policy.shouldFallbackToHTTP(afterHTTPSUpgradeError: connectionError))
    }

    func testInsecureTransportMessageDoesNotIncludeURLComponents() {
        let policy = URLSecurityPolicy()
        let url = URL(string: "http://user:pass@example.com/private?token=secret#fragment")!

        let message = policy.securityMessage(forAllowedWebURL: url)

        XCTAssertEqual(message, URLSecurityPolicy.insecureTransportMessage)
        for sensitiveComponent in ["user", "pass", "private", "token", "secret", "fragment"] {
            XCTAssertFalse(message?.contains(sensitiveComponent) ?? true, sensitiveComponent)
        }
    }
}
