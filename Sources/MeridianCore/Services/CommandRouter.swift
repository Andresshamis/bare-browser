import Foundation

public struct CommandRouter: Sendable {
    public enum Command: Equatable, Sendable {
        case openURL(URL)
        case search(URL, query: String)
        case createTab(URL?)
        case createSpace(String)
        case createFolder(String)
        case switchSpace(SpaceID)
        case switchProfile(ProfileID)
        case browserAction(BrowserAction)
        case noOp
    }

    public enum BrowserAction: String, Equatable, Sendable {
        case reload
        case goBack
        case goForward
        case closeTab
        case splitActiveTab
    }

    private let addressResolver: AddressResolver

    public init(addressResolver: AddressResolver = AddressResolver()) {
        self.addressResolver = addressResolver
    }

    public func route(input: String) -> Command {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .noOp
        }

        if trimmed.lowercased().hasPrefix("space ") {
            return .createSpace(String(trimmed.dropFirst("space ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if trimmed.lowercased().hasPrefix("folder ") {
            return .createFolder(String(trimmed.dropFirst("folder ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        switch addressResolver.resolve(trimmed) {
        case .url(let url):
            return .openURL(url)
        case .search(let url, let query):
            return .search(url, query: query)
        case .empty:
            return .noOp
        }
    }
}
