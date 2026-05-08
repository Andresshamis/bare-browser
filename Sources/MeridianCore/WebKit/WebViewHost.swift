import SwiftUI
import WebKit

@MainActor
public struct WebViewHost: NSViewRepresentable {
    @ObservedObject private var state: WebViewState

    private let profile: BrowserProfile
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let securityPolicy: URLSecurityPolicy
    private let sitePermissionPolicy: SitePermissionPolicy
    private let onStateChange: @MainActor (String?, URL?, Bool) -> Void
    private let onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation

    public init(
        state: WebViewState,
        profile: BrowserProfile,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
        onSitePermissionRequest: @escaping @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation = { _, _ in
            .deny(reason: "Site permission request was blocked because no permission handler is installed.")
        }
    ) {
        self.state = state
        self.profile = profile
        self.dataStoreProvider = dataStoreProvider
        self.securityPolicy = securityPolicy
        self.sitePermissionPolicy = sitePermissionPolicy
        self.onStateChange = onStateChange
        self.onSitePermissionRequest = onSitePermissionRequest
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            securityPolicy: securityPolicy,
            onStateChange: onStateChange,
            onSitePermissionRequest: onSitePermissionRequest
        )
    }

    public func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStoreProvider.websiteDataStore(for: profile)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        if sitePermissionPolicy.requiresUserActionForAutoplay {
            configuration.mediaTypesRequiringUserActionForPlayback = .all
        }
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
        context.coordinator.onSitePermissionRequest = onSitePermissionRequest

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
        fileprivate var onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
        fileprivate var lastHandledCommandID: UUID?

        init(
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
            onSitePermissionRequest: @escaping @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
        ) {
            self.state = state
            self.securityPolicy = securityPolicy
            self.onStateChange = onStateChange
            self.onSitePermissionRequest = onSitePermissionRequest
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
                Task { @MainActor in
                    state.securityMessage = "External application links require confirmation."
                }
                decisionHandler(.cancel)
            case .requireLocalFileConfirmation:
                Task { @MainActor in
                    state.securityMessage = "Local file links require confirmation."
                }
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
                let origin = SitePermissionOrigin(securityOrigin: navigationAction.sourceFrame.securityOrigin)
                    ?? SitePermissionOrigin(url: webView.url ?? url)
                switch onSitePermissionRequest(.popupWindow, origin) {
                case .allow:
                    webView.load(URLRequest(url: url))
                case .ask:
                    state.securityMessage = "Pop-up windows require permission for this site."
                case .deny(let reason):
                    state.securityMessage = reason
                }
            }
            return nil
        }

        public func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
        ) {
            let permissionOrigin = SitePermissionOrigin(securityOrigin: origin)
                ?? frame.request.url.flatMap(SitePermissionOrigin.init(url:))
            let evaluation = onSitePermissionRequest(Self.permissionKind(for: type), permissionOrigin)
            decisionHandler(Self.webKitPermissionDecision(for: evaluation))
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

        private static func permissionKind(for type: WKMediaCaptureType) -> SitePermissionKind {
            switch type {
            case .camera:
                .camera
            case .microphone:
                .microphone
            case .cameraAndMicrophone:
                .cameraAndMicrophone
            @unknown default:
                .cameraAndMicrophone
            }
        }

        private static func webKitPermissionDecision(
            for evaluation: SitePermissionPolicy.Evaluation
        ) -> WKPermissionDecision {
            switch evaluation {
            case .allow:
                .grant
            case .ask:
                .prompt
            case .deny:
                .deny
            }
        }
    }
}

@MainActor
private extension SitePermissionOrigin {
    init?(securityOrigin: WKSecurityOrigin) {
        self.init(
            scheme: securityOrigin.protocol,
            host: securityOrigin.host,
            port: securityOrigin.port
        )
    }
}
