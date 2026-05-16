import Combine
import Foundation

@MainActor
public final class WebViewState: ObservableObject {
    public enum Command: Equatable, Sendable {
        case goBack
        case goForward
        case reload
        case stopLoading
    }

    public struct CommandRequest: Equatable, Sendable {
        public var id: UUID
        public var command: Command
        public var targetTabID: TabID?

        public init(id: UUID = UUID(), command: Command, targetTabID: TabID? = nil) {
            self.id = id
            self.command = command
            self.targetTabID = targetTabID
        }
    }

    @Published public var requestedURL: URL?
    @Published public var pendingHTTPFallbackURL: URL?
    @Published public var committedURL: URL?
    @Published public var title: String
    @Published public var isLoading: Bool
    @Published public var estimatedProgress: Double
    @Published public var canGoBack: Bool
    @Published public var canGoForward: Bool
    @Published public var securityMessage: String?
    @Published public var pendingCommand: CommandRequest?

    public init(
        requestedURL: URL? = nil,
        pendingHTTPFallbackURL: URL? = nil,
        committedURL: URL? = nil,
        title: String = "New Tab",
        isLoading: Bool = false,
        estimatedProgress: Double = 0,
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        securityMessage: String? = nil
    ) {
        self.requestedURL = requestedURL
        self.pendingHTTPFallbackURL = pendingHTTPFallbackURL
        self.committedURL = committedURL
        self.title = title
        self.isLoading = isLoading
        self.estimatedProgress = estimatedProgress
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.securityMessage = securityMessage
        self.pendingCommand = nil
    }

    public func request(_ url: URL?, pendingHTTPFallbackURL: URL? = nil) {
        requestedURL = url
        self.pendingHTTPFallbackURL = pendingHTTPFallbackURL
    }

    public func dispatch(_ command: Command, targetTabID: TabID? = nil) {
        pendingCommand = CommandRequest(command: command, targetTabID: targetTabID)
    }

    public func clearPendingCommand(id: UUID) {
        guard pendingCommand?.id == id else {
            return
        }
        pendingCommand = nil
    }
}
