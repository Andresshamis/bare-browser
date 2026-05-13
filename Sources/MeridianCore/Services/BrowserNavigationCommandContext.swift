import SwiftUI

@MainActor
public struct BrowserNavigationCommandContext {
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var canReload: Bool
    public var canStopLoading: Bool

    private let dispatchCommand: (WebViewState.Command) -> Void

    public init(
        canGoBack: Bool = false,
        canGoForward: Bool = false,
        canReload: Bool = false,
        canStopLoading: Bool = false,
        dispatchCommand: @escaping (WebViewState.Command) -> Void
    ) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.canReload = canReload
        self.canStopLoading = canStopLoading
        self.dispatchCommand = dispatchCommand
    }

    @discardableResult
    public func goBack() -> Bool {
        dispatch(.goBack, when: canGoBack)
    }

    @discardableResult
    public func goForward() -> Bool {
        dispatch(.goForward, when: canGoForward)
    }

    @discardableResult
    public func reload() -> Bool {
        dispatch(.reload, when: canReload)
    }

    @discardableResult
    public func stopLoading() -> Bool {
        dispatch(.stopLoading, when: canStopLoading)
    }

    private func dispatch(_ command: WebViewState.Command, when isEnabled: Bool) -> Bool {
        guard isEnabled else {
            return false
        }

        dispatchCommand(command)
        return true
    }
}

private struct BrowserNavigationCommandContextKey: FocusedValueKey {
    typealias Value = BrowserNavigationCommandContext
}

public extension FocusedValues {
    var browserNavigationCommandContext: BrowserNavigationCommandContext? {
        get { self[BrowserNavigationCommandContextKey.self] }
        set { self[BrowserNavigationCommandContextKey.self] = newValue }
    }
}
