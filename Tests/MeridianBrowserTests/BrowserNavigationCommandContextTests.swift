import MeridianCore
import XCTest

@MainActor
final class BrowserNavigationCommandContextTests: XCTestCase {
    func testAvailableCommandsDispatchToWebViewStateCommands() {
        var dispatchedCommands: [WebViewState.Command] = []
        let context = BrowserNavigationCommandContext(
            canGoBack: true,
            canGoForward: true,
            canReload: true,
            canStopLoading: true
        ) { command in
            dispatchedCommands.append(command)
        }

        XCTAssertTrue(context.goBack())
        XCTAssertTrue(context.goForward())
        XCTAssertTrue(context.reload())
        XCTAssertTrue(context.stopLoading())

        XCTAssertEqual(dispatchedCommands, [.goBack, .goForward, .reload, .stopLoading])
    }

    func testUnavailableCommandsDoNotDispatch() {
        var dispatchedCommands: [WebViewState.Command] = []
        let context = BrowserNavigationCommandContext { command in
            dispatchedCommands.append(command)
        }

        XCTAssertFalse(context.goBack())
        XCTAssertFalse(context.goForward())
        XCTAssertFalse(context.reload())
        XCTAssertFalse(context.stopLoading())

        XCTAssertTrue(dispatchedCommands.isEmpty)
    }

    func testReloadAndStopHaveIndependentAvailability() {
        var dispatchedCommands: [WebViewState.Command] = []
        let context = BrowserNavigationCommandContext(
            canReload: true,
            canStopLoading: false
        ) { command in
            dispatchedCommands.append(command)
        }

        XCTAssertTrue(context.reload())
        XCTAssertFalse(context.stopLoading())

        XCTAssertEqual(dispatchedCommands, [.reload])
    }
}
