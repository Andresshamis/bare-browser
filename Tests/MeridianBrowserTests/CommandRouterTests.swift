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
        XCTAssertEqual(router.route(input: "profile Work"), .createProfile("Work"))
        XCTAssertEqual(router.route(input: "new profile Personal Projects"), .createProfile("Personal Projects"))
    }

    func testRoutesBrowserActionAliasesBeforeSearch() {
        let router = CommandRouter()

        XCTAssertEqual(router.route(input: "reload"), .browserAction(.reload))
        XCTAssertEqual(router.route(input: " refresh page "), .browserAction(.reload))
        XCTAssertEqual(router.route(input: "stop loading"), .browserAction(.stopLoading))
        XCTAssertEqual(router.route(input: "back"), .browserAction(.goBack))
        XCTAssertEqual(router.route(input: "go forward"), .browserAction(.goForward))
        XCTAssertEqual(router.route(input: "close tab"), .browserAction(.closeTab))
        XCTAssertEqual(router.route(input: "pin tab"), .browserAction(.pinTab))
        XCTAssertEqual(router.route(input: "add to essentials"), .browserAction(.addTabToEssentials))
        XCTAssertEqual(router.route(input: "move to tabs"), .browserAction(.moveTabToRegular))
        XCTAssertEqual(router.route(input: "move tab up"), .browserAction(.moveTabUp))
        XCTAssertEqual(router.route(input: "move tab down"), .browserAction(.moveTabDown))
        XCTAssertEqual(router.route(input: "password manager"), .browserAction(.openPasswordManager))
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

    func testTabPlacementActionSuggestionsRespectAvailability() {
        let router = CommandRouter()

        let unavailableSuggestions = router.browserActionSuggestions(
            for: "pin",
            availability: CommandRouter.BrowserActionAvailability(canPinTab: false)
        )
        XCTAssertTrue(unavailableSuggestions.isEmpty)

        let suggestions = router.browserActionSuggestions(
            for: "tab",
            availability: CommandRouter.BrowserActionAvailability(
                canPinTab: true,
                canAddTabToEssentials: true,
                canMoveTabToRegular: true
            )
        )

        XCTAssertEqual(
            suggestions.map(\.action),
            [.pinTab, .addTabToEssentials, .moveTabToRegular]
        )
    }

    func testTabReorderActionSuggestionsRespectAvailability() {
        let router = CommandRouter()

        let unavailableSuggestions = router.browserActionSuggestions(
            for: "move tab",
            availability: CommandRouter.BrowserActionAvailability(canMoveTabUp: false, canMoveTabDown: false)
        )
        XCTAssertTrue(unavailableSuggestions.isEmpty)

        let suggestions = router.browserActionSuggestions(
            for: "move tab",
            availability: CommandRouter.BrowserActionAvailability(
                canMoveTabUp: true,
                canMoveTabDown: true
            )
        )

        XCTAssertEqual(
            suggestions.map(\.action),
            [.moveTabUp, .moveTabDown]
        )
    }

    func testUnrecognizedActionLikeInputStillSearches() {
        let router = CommandRouter()

        guard case .search(_, let query) = router.route(input: "backlog grooming") else {
            return XCTFail("Expected a search command.")
        }
        XCTAssertEqual(query, "backlog grooming")
    }

    func testPasswordManagerActionIsAlwaysSuggested() {
        let router = CommandRouter()

        let suggestions = router.browserActionSuggestions(
            for: "passwords",
            availability: CommandRouter.BrowserActionAvailability()
        )

        XCTAssertEqual(suggestions.map(\.action), [.openPasswordManager])
    }
}
