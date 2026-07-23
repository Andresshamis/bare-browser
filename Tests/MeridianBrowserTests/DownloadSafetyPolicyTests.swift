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
            sourceURL: URL(string: "https://example.com:8443/archive.zip"),
            date: Date(timeIntervalSince1970: 16)
        )

        XCTAssertEqual(value, "0083;10;Lumen Browser;https://example.com:8443")
    }

    func testBuildsSanitizedDownloadSourceMetadata() {
        let policy = DownloadSafetyPolicy()
        let metadata = policy.sourceMetadata(
            from: URL(string: "https://user:password@example.com/private/source-name.zip?token=secret#fragment")
        )

        XCTAssertEqual(metadata.displayDescription, "example.com")
        XCTAssertEqual(metadata.quarantineOrigin, "https://example.com")

        let exposedMetadata = [
            metadata.displayDescription,
            metadata.quarantineOrigin ?? ""
        ].joined(separator: "\n")
        XCTAssertFalse(exposedMetadata.contains("user"))
        XCTAssertFalse(exposedMetadata.contains("password"))
        XCTAssertFalse(exposedMetadata.contains("private"))
        XCTAssertFalse(exposedMetadata.contains("source-name"))
        XCTAssertFalse(exposedMetadata.contains("token"))
        XCTAssertFalse(exposedMetadata.contains("secret"))
        XCTAssertFalse(exposedMetadata.contains("fragment"))
    }

    func testQuarantineMetadataOmitsSensitiveSourceURLComponents() {
        let policy = DownloadSafetyPolicy()
        let value = policy.quarantineMetadataValue(
            sourceURL: URL(string: "https://user:password@example.com/private/archive.zip?token=secret#fragment"),
            date: Date(timeIntervalSince1970: 16)
        )

        XCTAssertEqual(value, "0083;10;Lumen Browser;https://example.com")
        XCTAssertFalse(value.contains("user"))
        XCTAssertFalse(value.contains("password"))
        XCTAssertFalse(value.contains("private"))
        XCTAssertFalse(value.contains("archive.zip"))
        XCTAssertFalse(value.contains("token"))
        XCTAssertFalse(value.contains("secret"))
        XCTAssertFalse(value.contains("fragment"))
    }

    func testQuarantineMetadataOmitsUnsafeSourceOrigins() {
        let policy = DownloadSafetyPolicy()
        let value = policy.quarantineMetadataValue(
            sourceURL: URL(string: "file:///Users/example/secret.txt"),
            date: Date(timeIntervalSince1970: 16)
        )

        XCTAssertEqual(value, "0083;10;Lumen Browser;")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
