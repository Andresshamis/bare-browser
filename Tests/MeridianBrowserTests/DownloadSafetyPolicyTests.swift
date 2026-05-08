import Foundation
import MeridianCore
import XCTest

final class DownloadSafetyPolicyTests: XCTestCase {
    func testSanitizesFilenames() {
        let policy = DownloadSafetyPolicy()

        XCTAssertEqual(policy.sanitizedFilename(from: "../bad:name.sh"), "-bad-name.sh")
        XCTAssertEqual(policy.sanitizedFilename(from: ".env"), "env")
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

    func testSafeDestinationSanitizesAndAvoidsExistingFiles() throws {
        let policy = DownloadSafetyPolicy()
        let temporaryDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let existingURL = temporaryDirectory.appendingPathComponent("bad-name.sh")
        FileManager.default.createFile(atPath: existingURL.path, contents: Data())

        let destinationURL = policy.safeDestinationURL(
            for: temporaryDirectory.appendingPathComponent("bad:name.sh")
        )

        XCTAssertEqual(destinationURL?.lastPathComponent, "bad-name 2.sh")
    }

    func testBuildsQuarantineMetadataValue() {
        let policy = DownloadSafetyPolicy()
        let value = policy.quarantineMetadataValue(
            sourceURL: URL(string: "https://example.com/archive.zip"),
            date: Date(timeIntervalSince1970: 16)
        )

        XCTAssertEqual(value, "0083;10;Meridian Browser;https://example.com/archive.zip")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
