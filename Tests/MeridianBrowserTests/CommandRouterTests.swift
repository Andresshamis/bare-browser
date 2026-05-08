import Foundation
import MeridianCore
import XCTest

final class CommandRouterTests: XCTestCase {
    func testRoutesURLsAndSearchQueries() {
        let router = CommandRouter()

        XCTAssertEqual(router.route(input: "https://example.com"), .openURL(URL(string: "https://example.com")!))

        guard case .search(_, let query) = router.route(input: "browser profile isolation") else {
            return XCTFail("Expected a search command.")
        }
        XCTAssertEqual(query, "browser profile isolation")
    }

    func testRoutesCreationCommands() {
        let router = CommandRouter()

        XCTAssertEqual(router.route(input: "space Work"), .createSpace("Work"))
        XCTAssertEqual(router.route(input: "folder Research"), .createFolder("Research"))
    }
}
