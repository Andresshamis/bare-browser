import Foundation

public struct CommandRouter: Sendable {
    public enum Command: Equatable, Sendable {
        case openURL(URL)
        case search(URL, query: String)
        case createTab(URL?)
        case createSpace(String)
        case createFolder(String)
        case createProfile(String)
        case switchSpace(SpaceID)
        case switchProfile(ProfileID)
        case browserAction(BrowserAction)
        case noOp
    }

    public enum BrowserAction: String, Equatable, Sendable {
        case reload
        case stopLoading
        case goBack
        case goForward
        case closeTab
        case pinTab
        case addTabToEssentials
        case moveTabToRegular
        case splitActiveTab
    }

    public struct BrowserActionAvailability: Equatable, Sendable {
        public var canGoBack: Bool
        public var canGoForward: Bool
        public var canReload: Bool
        public var canCloseTab: Bool
        public var canPinTab: Bool
        public var canAddTabToEssentials: Bool
        public var canMoveTabToRegular: Bool
        public var isLoading: Bool

        public init(
            canGoBack: Bool = false,
            canGoForward: Bool = false,
            canReload: Bool = false,
            canCloseTab: Bool = false,
            canPinTab: Bool = false,
            canAddTabToEssentials: Bool = false,
            canMoveTabToRegular: Bool = false,
            isLoading: Bool = false
        ) {
            self.canGoBack = canGoBack
            self.canGoForward = canGoForward
            self.canReload = canReload
            self.canCloseTab = canCloseTab
            self.canPinTab = canPinTab
            self.canAddTabToEssentials = canAddTabToEssentials
            self.canMoveTabToRegular = canMoveTabToRegular
            self.isLoading = isLoading
        }
    }

    public struct BrowserActionSuggestion: Identifiable, Equatable, Sendable {
        public var id: String { action.rawValue }
        public var action: BrowserAction
        public var title: String
        public var subtitle: String
        public var symbolName: String
        public var aliases: [String]

        public init(
            action: BrowserAction,
            title: String,
            subtitle: String,
            symbolName: String,
            aliases: [String]
        ) {
            self.action = action
            self.title = title
            self.subtitle = subtitle
            self.symbolName = symbolName
            self.aliases = aliases
        }
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

        if trimmed.lowercased().hasPrefix("new profile ") {
            return .createProfile(String(trimmed.dropFirst("new profile ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if trimmed.lowercased().hasPrefix("profile ") {
            return .createProfile(String(trimmed.dropFirst("profile ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let action = Self.browserAction(forAlias: trimmed) {
            return .browserAction(action)
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

    public func browserActionSuggestions(
        for input: String,
        availability: BrowserActionAvailability
    ) -> [BrowserActionSuggestion] {
        let query = Self.normalizedActionInput(input)
        guard !query.isEmpty else {
            return []
        }

        return Self.availableActionSuggestions(availability: availability).filter { suggestion in
            let searchableValues = [suggestion.title, suggestion.subtitle] + suggestion.aliases
            return searchableValues.contains { value in
                Self.normalizedActionInput(value).contains(query)
            }
        }
    }

    private static func browserAction(forAlias input: String) -> BrowserAction? {
        let normalizedInput = normalizedActionInput(input)
        return allActionSuggestions.first { suggestion in
            suggestion.aliases.contains { normalizedActionInput($0) == normalizedInput }
        }?.action
    }

    private static func availableActionSuggestions(
        availability: BrowserActionAvailability
    ) -> [BrowserActionSuggestion] {
        return allActionSuggestions.filter { suggestion in
            switch suggestion.action {
            case .reload:
                return availability.canReload
            case .stopLoading:
                return availability.canReload && availability.isLoading
            case .goBack:
                return availability.canGoBack
            case .goForward:
                return availability.canGoForward
            case .closeTab:
                return availability.canCloseTab
            case .pinTab:
                return availability.canPinTab
            case .addTabToEssentials:
                return availability.canAddTabToEssentials
            case .moveTabToRegular:
                return availability.canMoveTabToRegular
            case .splitActiveTab:
                return false
            }
        }
    }

    private static let allActionSuggestions: [BrowserActionSuggestion] = [
        BrowserActionSuggestion(
            action: .reload,
            title: "Reload",
            subtitle: "Current page",
            symbolName: "arrow.clockwise",
            aliases: ["reload", "reload page", "refresh", "refresh page"]
        ),
        BrowserActionSuggestion(
            action: .stopLoading,
            title: "Stop Loading",
            subtitle: "Current page",
            symbolName: "xmark",
            aliases: ["stop", "stop loading"]
        ),
        BrowserActionSuggestion(
            action: .goBack,
            title: "Back",
            subtitle: "Navigation history",
            symbolName: "chevron.left",
            aliases: ["back", "go back"]
        ),
        BrowserActionSuggestion(
            action: .goForward,
            title: "Forward",
            subtitle: "Navigation history",
            symbolName: "chevron.right",
            aliases: ["forward", "go forward"]
        ),
        BrowserActionSuggestion(
            action: .closeTab,
            title: "Close Tab",
            subtitle: "Selected tab",
            symbolName: "xmark",
            aliases: ["close", "close tab", "close current tab"]
        ),
        BrowserActionSuggestion(
            action: .pinTab,
            title: "Pin Tab",
            subtitle: "Move selected tab to Pinned",
            symbolName: "pin",
            aliases: ["pin", "pin tab", "pin current tab", "move to pinned"]
        ),
        BrowserActionSuggestion(
            action: .addTabToEssentials,
            title: "Add to Essentials",
            subtitle: "Move selected tab to Essentials",
            symbolName: "sparkle",
            aliases: ["essential", "essentials", "add to essentials", "favorite tab", "move to essentials"]
        ),
        BrowserActionSuggestion(
            action: .moveTabToRegular,
            title: "Move to Tabs",
            subtitle: "Return selected tab to regular Tabs",
            symbolName: "rectangle.stack",
            aliases: ["move to tabs", "regular tab", "unpin tab", "remove from essentials"]
        )
    ]

    private static func normalizedActionInput(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
