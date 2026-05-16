import MeridianCore
import XCTest

@MainActor
final class WebViewStateTests: XCTestCase {
    func testDispatchTargetsCommandToTab() {
        let state = WebViewState()
        let tabID = UUID()

        state.dispatch(.reload, targetTabID: tabID)

        XCTAssertEqual(state.pendingCommand?.command, .reload)
        XCTAssertEqual(state.pendingCommand?.targetTabID, tabID)
    }

    func testClearPendingCommandOnlyClearsMatchingRequest() throws {
        let state = WebViewState()
        state.dispatch(.stopLoading, targetTabID: UUID())
        let commandID = try XCTUnwrap(state.pendingCommand?.id)

        state.clearPendingCommand(id: UUID())
        XCTAssertNotNil(state.pendingCommand)

        state.clearPendingCommand(id: commandID)
        XCTAssertNil(state.pendingCommand)
    }
}
