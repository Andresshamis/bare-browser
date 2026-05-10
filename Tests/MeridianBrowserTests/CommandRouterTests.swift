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

    func testRoutesBrowserActionAliasesBeforeSearch() {
        let router = CommandRouter()

        XCTAssertEqual(router.route(input: "reload"), .browserAction(.reload))
        XCTAssertEqual(router.route(input: " refresh page "), .browserAction(.reload))
        XCTAssertEqual(router.route(input: "stop loading"), .browserAction(.stopLoading))
        XCTAssertEqual(router.route(input: "back"), .browserAction(.goBack))
        XCTAssertEqual(router.route(input: "go forward"), .browserAction(.goForward))
        XCTAssertEqual(router.route(input: "close tab"), .browserAction(.closeTab))
    }

    func testBrowserActionSuggestionsRespectAvailability() {
        let router = CommandRouter()
        let unavailableBackSuggestions = router.browserActionSuggestions(
            for: "back",
            availability: CommandRouter.BrowserActionAvailability(
                canGoBack: false,
                canGoForward: true,
                canReload: true,
                canCloseTab: true,
                isLoading: true
            )
        )
        XCTAssertTrue(unavailableBackSuggestions.isEmpty)

        let suggestions = router.browserActionSuggestions(
            for: "forward",
            availability: CommandRouter.BrowserActionAvailability(
                canGoForward: true,
                canReload: true,
                canCloseTab: true,
                isLoading: true
            )
        )
        XCTAssertEqual(
            suggestions.map(\.action),
            [.goForward]
        )
    }

    func testUnrecognizedActionLikeInputStillSearches() {
        let router = CommandRouter()

        guard case .search(_, let query) = router.route(input: "backlog grooming") else {
            return XCTFail("Expected a search command.")
        }
        XCTAssertEqual(query, "backlog grooming")
    }
}
