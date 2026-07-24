import Foundation
import MeridianCore
import XCTest

final class DefaultBrowserPromptPolicyTests: XCTestCase {
    func testFreshInstallationPromptsWhenLumenIsNotDefault() throws {
        try withDefaults { defaults in
            XCTAssertTrue(
                DefaultBrowserPromptPolicy.shouldPresentPrompt(
                    isDefaultBrowser: false,
                    defaults: defaults
                )
            )
        }
    }

    func testExistingInstallationWithoutPromptStateReceivesCurrentPrompt() throws {
        try withDefaults { defaults in
            defaults.set("existing preference", forKey: "UnrelatedBrowserPreference")

            XCTAssertTrue(
                DefaultBrowserPromptPolicy.shouldPresentPrompt(
                    isDefaultBrowser: false,
                    defaults: defaults
                )
            )
        }
    }

    func testHandledPromptDoesNotRepeat() throws {
        try withDefaults { defaults in
            DefaultBrowserPromptPolicy.markCurrentPromptHandled(defaults: defaults)

            XCTAssertTrue(
                DefaultBrowserPromptPolicy.hasHandledCurrentPrompt(defaults: defaults)
            )
            XCTAssertFalse(
                DefaultBrowserPromptPolicy.shouldPresentPrompt(
                    isDefaultBrowser: false,
                    defaults: defaults
                )
            )
        }
    }

    func testOlderPromptVersionReceivesCurrentPrompt() throws {
        try withDefaults { defaults in
            defaults.set(
                DefaultBrowserPromptPolicy.currentPromptVersion - 1,
                forKey: DefaultBrowserPromptPolicy.promptVersionStorageKey
            )

            XCTAssertTrue(
                DefaultBrowserPromptPolicy.shouldPresentPrompt(
                    isDefaultBrowser: false,
                    defaults: defaults
                )
            )
        }
    }

    func testDefaultBrowserDoesNotReceiveUnnecessaryPrompt() throws {
        try withDefaults { defaults in
            XCTAssertFalse(
                DefaultBrowserPromptPolicy.shouldPresentPrompt(
                    isDefaultBrowser: true,
                    defaults: defaults
                )
            )
        }
    }

    private func withDefaults(
        _ body: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "DefaultBrowserPromptPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
