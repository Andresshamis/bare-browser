import MeridianCore
import XCTest

final class DownloadSafetyPolicyTests: XCTestCase {
    func testSanitizesFilenames() {
        let policy = DownloadSafetyPolicy()

        XCTAssertEqual(policy.sanitizedFilename(from: "../bad:name.sh"), "..-bad-name.sh")
        XCTAssertEqual(policy.sanitizedFilename(from: "   "), "download")
    }

    func testClassifiesExecutableDownloads() {
        let policy = DownloadSafetyPolicy()

        XCTAssertEqual(policy.risk(for: "archive.zip"), .low)
        XCTAssertEqual(
            policy.risk(for: "script.sh"),
            .requiresConfirmation(reason: "Downloads ending in .sh can execute code.")
        )
        XCTAssertEqual(
            policy.risk(for: "installer.pkg"),
            .blocked(reason: "Downloads ending in .pkg require a dedicated installer flow.")
        )
    }
}
