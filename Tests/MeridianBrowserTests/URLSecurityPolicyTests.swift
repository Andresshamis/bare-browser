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

        XCTAssertEqual(
            policy.decision(for: URL(string: "mailto:hello@example.com")!),
            .requireExternalApplicationConfirmation
        )
        XCTAssertEqual(
            policy.decision(for: URL(fileURLWithPath: "/tmp/test.html")),
            .requireLocalFileConfirmation
        )
    }

    func testFlagsNonLocalHTTPAsInsecureTransport() {
        let policy = URLSecurityPolicy()

        XCTAssertTrue(policy.isInsecureTransport(URL(string: "http://example.com")!))
        XCTAssertFalse(policy.isInsecureTransport(URL(string: "http://127.0.0.1:8080")!))
        XCTAssertFalse(policy.isInsecureTransport(URL(string: "https://example.com")!))
    }
}
