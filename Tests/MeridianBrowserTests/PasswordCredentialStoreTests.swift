import Foundation
import MeridianCore
import XCTest

final class PasswordCredentialStoreTests: XCTestCase {
    func testKeychainStoreUsesBareBrowserServicePrefixAndKeepsLegacyMeridianLookup() {
        XCTAssertEqual(KeychainPasswordCredentialStore.defaultServicePrefix, "BareBrowser.WebsitePasswords")
        XCTAssertEqual(KeychainPasswordCredentialStore.legacyServicePrefixes, ["MeridianBrowser.WebsitePasswords"])
    }

    func testCandidateNormalizesHTTPSOriginAndKeepsSecretOutOfPromptText() throws {
        let candidate = try XCTUnwrap(PasswordCredentialCandidate(
            originURL: URL(string: "https://name:pass@example.com:443/login?token=secret#fragment")!,
            username: "  user@example.com  ",
            password: "password-secret",
            pageTitle: "  Example Login  "
        ))

        XCTAssertEqual(candidate.origin.absoluteString, "https://example.com")
        XCTAssertEqual(candidate.username, "user@example.com")
        XCTAssertEqual(candidate.password, "password-secret")
        XCTAssertEqual(candidate.pageTitle, "Example Login")
        XCTAssertEqual(candidate.displayHost, "example.com")

        let request = PasswordSaveRequest(candidate: candidate, profileID: UUID())
        XCTAssertFalse(request.confirmationMessage.contains("password-secret"))
        XCTAssertFalse(request.confirmationMessage.contains("/login"))
        XCTAssertFalse(request.confirmationMessage.contains("token"))
        XCTAssertFalse(request.confirmationMessage.contains("fragment"))
        XCTAssertFalse(request.confirmationMessage.contains("name:pass"))
        XCTAssertFalse(request.confirmationMessage.contains("Meridian"))
    }

    func testCandidateAllowsLoopbackHTTPForLocalDevelopment() throws {
        let candidate = try XCTUnwrap(PasswordCredentialCandidate(
            originURL: URL(string: "http://localhost:3000/auth/login?next=/dashboard")!,
            username: "user",
            password: "secret"
        ))

        XCTAssertEqual(candidate.origin.absoluteString, "http://localhost:3000")
        XCTAssertEqual(candidate.displayHost, "localhost:3000")
    }

    func testCandidateRejectsNonLocalInsecureOriginsAndEmptyFields() {
        XCTAssertNil(PasswordCredentialCandidate(
            originURL: URL(string: "http://example.com/login")!,
            username: "user",
            password: "secret"
        ))
        XCTAssertNil(PasswordCredentialCandidate(
            originURL: URL(string: "https://example.com/login")!,
            username: "   ",
            password: "secret"
        ))
        XCTAssertNil(PasswordCredentialCandidate(
            originURL: URL(string: "https://example.com/login")!,
            username: "user",
            password: ""
        ))
    }

    func testCandidateCanBeCreatedFromScriptMessageBody() throws {
        let candidate = try XCTUnwrap(PasswordCredentialCandidate(messageBody: [
            "origin": "https://secure.example/login?ignored=1",
            "username": "member@example.com",
            "password": "secret",
            "pageTitle": "Sign in"
        ]))

        XCTAssertEqual(candidate.origin.absoluteString, "https://secure.example")
        XCTAssertEqual(candidate.username, "member@example.com")
        XCTAssertEqual(candidate.password, "secret")
        XCTAssertEqual(candidate.pageTitle, "Sign in")
    }

    func testCandidateCanUseFallbackUsernameForMultiStepLogin() throws {
        let candidate = try XCTUnwrap(PasswordCredentialCandidate(
            messageBody: [
                "kind": "credential",
                "origin": "https://secure.example/password",
                "username": "",
                "password": "secret"
            ],
            fallbackUsername: "member@example.com"
        ))

        XCTAssertEqual(candidate.origin.absoluteString, "https://secure.example")
        XCTAssertEqual(candidate.username, "member@example.com")
        XCTAssertEqual(candidate.password, "secret")
    }
}
