import SwiftUI
import WebKit

@MainActor
public struct WebViewHost: NSViewRepresentable {
    @ObservedObject private var state: WebViewState

    private let profile: BrowserProfile
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let securityPolicy: URLSecurityPolicy
    private let onStateChange: @MainActor (String?, URL?, Bool) -> Void
    private let onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void

    public init(
        state: WebViewState,
        profile: BrowserProfile,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
        onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void = { _, _, _ in }
    ) {
        self.state = state
        self.profile = profile
        self.dataStoreProvider = dataStoreProvider
        self.securityPolicy = securityPolicy
        self.onStateChange = onStateChange
        self.onURLConfirmationRequired = onURLConfirmationRequired
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            securityPolicy: securityPolicy,
            onStateChange: onStateChange,
            onURLConfirmationRequired: onURLConfirmationRequired
        )
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStoreProvider.websiteDataStore(for: profile)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        ContentBlockerService.installDefaultRules(into: configuration.userContentController)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        if let requestedURL = state.requestedURL {
            webView.load(URLRequest(url: requestedURL))
        }

        return webView
    }

    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.state = state
        context.coordinator.onStateChange = onStateChange
        context.coordinator.onURLConfirmationRequired = onURLConfirmationRequired

        if let commandRequest = state.pendingCommand,
           context.coordinator.lastHandledCommandID != commandRequest.id {
            context.coordinator.lastHandledCommandID = commandRequest.id
            switch commandRequest.command {
            case .goBack where webView.canGoBack:
                webView.goBack()
            case .goForward where webView.canGoForward:
                webView.goForward()
            case .reload:
                webView.reload()
            case .stopLoading:
                webView.stopLoading()
            default:
                break
            }
        }

        guard let requestedURL = state.requestedURL else {
            return
        }

        if webView.url != requestedURL {
            webView.load(URLRequest(url: requestedURL))
        }
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        fileprivate var state: WebViewState
        fileprivate let securityPolicy: URLSecurityPolicy
        fileprivate var onStateChange: @MainActor (String?, URL?, Bool) -> Void
        fileprivate var onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
        fileprivate var lastHandledCommandID: UUID?

        init(
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
            onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
        ) {
            self.state = state
            self.securityPolicy = securityPolicy
            self.onStateChange = onStateChange
            self.onURLConfirmationRequired = onURLConfirmationRequired
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            publish(webView, isLoading: true)
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            publish(webView, isLoading: true)
        }

        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publish(webView, isLoading: false)
        }

        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            publish(webView, isLoading: false, message: error.localizedDescription)
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            publish(webView, isLoading: false, message: error.localizedDescription)
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            switch securityPolicy.decision(for: url) {
            case .allowInWebView:
                decisionHandler(.allow)
            case .requireExternalApplicationConfirmation:
                requestConfirmation(.externalApplication, url: url, sourceURL: webView.url)
                decisionHandler(.cancel)
            case .requireLocalFileConfirmation:
                requestConfirmation(.localFile, url: url, sourceURL: webView.url)
                decisionHandler(.cancel)
            case .block(let reason):
                Task { @MainActor in
                    state.securityMessage = reason
                }
                decisionHandler(.cancel)
            }
        }

        public func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        private func requestConfirmation(
            _ kind: URLConfirmationRequest.Kind,
            url: URL,
            sourceURL: URL?
        ) {
            state.securityMessage = kind.pendingMessage
            onURLConfirmationRequired(kind, url, URLConfirmationSourceContext(sourceURL: sourceURL))
        }

        private func publish(_ webView: WKWebView, isLoading: Bool, message: String? = nil) {
            let title = webView.title
            let url = webView.url
            let progress = webView.estimatedProgress
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward

            Task { @MainActor in
                state.title = title ?? state.title
                state.committedURL = url
                state.isLoading = isLoading
                state.estimatedProgress = progress
                state.canGoBack = canGoBack
                state.canGoForward = canGoForward
                state.securityMessage = message
                onStateChange(title, url, isLoading)
            }
        }
    }
}
