@testable import MeridianCore
import AppKit
import XCTest

final class BrowserContextMenuDownloadTests: XCTestCase {
    func testContextMenuTargetParsesPostedURLs() {
        let target = BrowserContextMenuDownloadTarget(messageBody: [
            "imageURL": "https://images.example/photo.jpg",
            "linkURL": "https://example.com/download",
            "pageURL": "https://example.com/page"
        ])

        XCTAssertEqual(target.imageURL, URL(string: "https://images.example/photo.jpg"))
        XCTAssertEqual(target.linkURL, URL(string: "https://example.com/download"))
        XCTAssertEqual(target.pageURL, URL(string: "https://example.com/page"))
    }

    func testContextMenuTargetIgnoresInvalidURLs() {
        let target = BrowserContextMenuDownloadTarget(messageBody: [
            "imageURL": "",
            "linkURL": 12,
            "pageURL": NSNull()
        ])

        XCTAssertNil(target.imageURL)
        XCTAssertNil(target.linkURL)
        XCTAssertNil(target.pageURL)
    }

    func testDownloadKindUsesLegacyWebKitMenuTags() {
        let linkedFileItem = NSMenuItem(title: "Localized title", action: nil, keyEquivalent: "")
        linkedFileItem.tag = 2
        let imageItem = NSMenuItem(title: "Localized title", action: nil, keyEquivalent: "")
        imageItem.tag = 5

        XCTAssertEqual(BrowserContextMenuDownloadKind.kind(for: linkedFileItem), .linkedFile)
        XCTAssertEqual(BrowserContextMenuDownloadKind.kind(for: imageItem), .image)
    }

    func testDownloadKindFallsBackToMenuTitles() {
        XCTAssertEqual(
            BrowserContextMenuDownloadKind.kind(for: NSMenuItem(title: "Download Image", action: nil, keyEquivalent: "")),
            .image
        )
        XCTAssertEqual(
            BrowserContextMenuDownloadKind.kind(for: NSMenuItem(title: "Download Linked File", action: nil, keyEquivalent: "")),
            .linkedFile
        )
    }
}
