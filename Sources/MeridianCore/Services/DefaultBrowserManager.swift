import AppKit
import Combine
import Foundation

public enum DefaultBrowserPromptPolicy {
    public static let currentPromptVersion = 1
    public static let promptVersionStorageKey = "DefaultBrowserPromptVersion"

    public static func shouldPresentPrompt(
        isDefaultBrowser: Bool,
        defaults: UserDefaults = .standard
    ) -> Bool {
        !isDefaultBrowser
            && defaults.integer(forKey: promptVersionStorageKey) < currentPromptVersion
    }

    public static func hasHandledCurrentPrompt(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.integer(forKey: promptVersionStorageKey) >= currentPromptVersion
    }

    public static func markCurrentPromptHandled(
        defaults: UserDefaults = .standard
    ) {
        defaults.set(currentPromptVersion, forKey: promptVersionStorageKey)
    }
}

public enum DefaultBrowserRegistrationResult: Equatable, Sendable {
    case succeeded
    case failed
}

@MainActor
public final class DefaultBrowserManager: ObservableObject {
    @Published public private(set) var isPromptPresented = false

    private static let webSchemes = ["https", "http"]

    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private let applicationURL: URL
    private let bundleIdentifier: String?

    public init(
        workspace: NSWorkspace = .shared,
        defaults: UserDefaults = .standard,
        applicationURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.defaults = defaults
        self.applicationURL = applicationURL
        self.bundleIdentifier = bundleIdentifier
    }

    @discardableResult
    public func preparePromptIfNeeded() -> Bool {
        guard applicationURL.pathExtension == "app",
              bundleIdentifier != nil,
              !DefaultBrowserPromptPolicy.hasHandledCurrentPrompt(defaults: defaults) else {
            return false
        }

        let isDefaultBrowser = Self.webSchemes.allSatisfy(isDefaultHandler(for:))
        let shouldPresent = DefaultBrowserPromptPolicy.shouldPresentPrompt(
            isDefaultBrowser: isDefaultBrowser,
            defaults: defaults
        )
        DefaultBrowserPromptPolicy.markCurrentPromptHandled(defaults: defaults)
        isPromptPresented = shouldPresent
        return shouldPresent
    }

    public func dismissPrompt() {
        isPromptPresented = false
    }

    public func setAsDefaultBrowser() async -> DefaultBrowserRegistrationResult {
        dismissPrompt()

        for scheme in Self.webSchemes where !isDefaultHandler(for: scheme) {
            do {
                try await setAsDefaultHandler(for: scheme)
            } catch {
                return .failed
            }
        }

        return Self.webSchemes.allSatisfy(isDefaultHandler(for:))
            ? .succeeded
            : .failed
    }

    private func isDefaultHandler(for scheme: String) -> Bool {
        guard let bundleIdentifier,
              let testURL = URL(string: "\(scheme)://example.com"),
              let handlerURL = workspace.urlForApplication(toOpen: testURL),
              let handlerBundle = Bundle(url: handlerURL) else {
            return false
        }
        return handlerBundle.bundleIdentifier == bundleIdentifier
    }

    private func setAsDefaultHandler(for scheme: String) async throws {
        try await withCheckedThrowingContinuation { (
            continuation: CheckedContinuation<Void, Error>
        ) in
            workspace.setDefaultApplication(
                at: applicationURL,
                toOpenURLsWithScheme: scheme
            ) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
