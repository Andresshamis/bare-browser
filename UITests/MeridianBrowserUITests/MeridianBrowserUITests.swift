import XCTest

final class MeridianBrowserUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunchesFirstWindow() throws {
        let app = XCUIApplication(bundleIdentifier: "app.meridianbrowser.MeridianBrowser")
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
    }
}
