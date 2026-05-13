import SwiftUI
import WebKit

@MainActor
public struct WebViewHost: NSViewRepresentable {
    @ObservedObject private var state: WebViewState

    private let profile: BrowserProfile
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let securityPolicy: URLSecurityPolicy
    private let downloadSafetyPolicy: DownloadSafetyPolicy
    private let sitePermissionPolicy: SitePermissionPolicy
    private let onStateChange: @MainActor (String?, URL?, Bool) -> Void
    private let onSecurityMessage: @MainActor (String) -> Void
    private let onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
    private let onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
    private let onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation

    public init(
        state: WebViewState,
        profile: BrowserProfile,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
        onSecurityMessage: @escaping @MainActor (String) -> Void = { _ in },
        onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void = { _, _, _ in },
        onDownloadConfirmationRequired: @escaping @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void = { _, completion in completion(nil) },
        onSitePermissionRequest: @escaping @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation = { _, _ in
            .deny(reason: "Site permission request was blocked because no permission handler is installed.")
        }
    ) {
        self.state = state
        self.profile = profile
        self.dataStoreProvider = dataStoreProvider
        self.securityPolicy = securityPolicy
        self.downloadSafetyPolicy = downloadSafetyPolicy
        self.sitePermissionPolicy = sitePermissionPolicy
        self.onStateChange = onStateChange
        self.onSecurityMessage = onSecurityMessage
        self.onURLConfirmationRequired = onURLConfirmationRequired
        self.onDownloadConfirmationRequired = onDownloadConfirmationRequired
        self.onSitePermissionRequest = onSitePermissionRequest
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            onStateChange: onStateChange,
            onSecurityMessage: onSecurityMessage,
            onURLConfirmationRequired: onURLConfirmationRequired,
            onDownloadConfirmationRequired: onDownloadConfirmationRequired,
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
        context.coordinator.onSecurityMessage = onSecurityMessage
        context.coordinator.onURLConfirmationRequired = onURLConfirmationRequired
        context.coordinator.onDownloadConfirmationRequired = onDownloadConfirmationRequired
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
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        fileprivate var state: WebViewState
        fileprivate let securityPolicy: URLSecurityPolicy
        fileprivate let downloadSafetyPolicy: DownloadSafetyPolicy
        fileprivate var onStateChange: @MainActor (String?, URL?, Bool) -> Void
        fileprivate var onSecurityMessage: @MainActor (String) -> Void
        fileprivate var onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
        fileprivate var onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
        fileprivate var onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
        fileprivate var lastHandledCommandID: UUID?
        private var pendingHTTPFallbacksByUpgradeURL: [URL: URL] = [:]
        private var httpFallbacksInFlight: Set<URL> = []
        private var downloadSourceMetadata: [ObjectIdentifier: DownloadSourceMetadata] = [:]
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        init(
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            downloadSafetyPolicy: DownloadSafetyPolicy,
            onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
            onSecurityMessage: @escaping @MainActor (String) -> Void,
            onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void,
            onDownloadConfirmationRequired: @escaping @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void,
            onSitePermissionRequest: @escaping @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
        ) {
            self.state = state
            self.securityPolicy = securityPolicy
            self.downloadSafetyPolicy = downloadSafetyPolicy
            self.onStateChange = onStateChange
            self.onSecurityMessage = onSecurityMessage
            self.onURLConfirmationRequired = onURLConfirmationRequired
            self.onDownloadConfirmationRequired = onDownloadConfirmationRequired
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
            publish(webView, isLoading: false, message: "Navigation failed.")
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let fallbackURL = httpFallbackURL(for: error),
               securityPolicy.shouldFallbackToHTTP(afterHTTPSUpgradeError: error) {
                beginHTTPFallback(to: fallbackURL, in: webView)
                return
            }

            publish(webView, isLoading: false, message: "Navigation failed.")
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
                if shouldUpgradeNavigationAction(navigationAction, url: url),
                   let upgradedURL = securityPolicy.httpsUpgradeCandidate(for: url) {
                    beginHTTPSUpgrade(from: url, to: upgradedURL, in: webView)
                    decisionHandler(.cancel)
                    return
                }

                publishSecurityMessage(securityPolicy.securityMessage(forAllowedWebURL: url))
                decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
            case .requireExternalApplicationConfirmation:
                requestConfirmation(.externalApplication, url: url, sourceURL: webView.url)
                decisionHandler(.cancel)
            case .requireLocalFileConfirmation:
                requestConfirmation(.localFile, url: url, sourceURL: webView.url)
                decisionHandler(.cancel)
            case .block(let reason):
                publishSecurityMessage(reason)
                decisionHandler(.cancel)
            }
        }

        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        public func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            prepare(download, sourceURL: navigationAction.request.url)
        }

        public func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            prepare(download, sourceURL: navigationResponse.response.url ?? webView.url)
        }

        public func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
        ) {
            let identifier = ObjectIdentifier(download)
            let sourceMetadata = downloadSourceMetadata[identifier] ?? downloadSafetyPolicy.sourceMetadata(from: response.url)
            let request = downloadSafetyPolicy.confirmationRequest(
                suggestedFilename: suggestedFilename,
                sourceMetadata: sourceMetadata
            )

            publishSecurityMessage(request.pendingMessage)
            onDownloadConfirmationRequired(request) { [weak self] destinationURL in
                guard let self else {
                    completionHandler(nil)
                    return
                }

                if let destinationURL {
                    self.downloadDestinations[identifier] = destinationURL
                    self.downloadSourceMetadata[identifier] = sourceMetadata
                } else {
                    self.cleanup(download)
                }

                completionHandler(destinationURL)
            }
        }

        public func downloadDidFinish(_ download: WKDownload) {
            let identifier = ObjectIdentifier(download)
            let destinationURL = downloadDestinations[identifier]
            let sourceMetadata = downloadSourceMetadata[identifier] ?? .currentPage

            if let destinationURL {
                let didApplyQuarantine = downloadSafetyPolicy.applyQuarantineMetadata(
                    to: destinationURL,
                    sourceMetadata: sourceMetadata
                )
                publishSecurityMessage(
                    didApplyQuarantine
                        ? "Download finished: \(destinationURL.lastPathComponent)"
                        : "Download finished, but quarantine metadata could not be applied."
                )
            } else {
                publishSecurityMessage("Download finished.")
            }

            cleanup(download)
        }

        public func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            publishSecurityMessage("Download failed.")
            cleanup(download)
        }

        public func download(
            _ download: WKDownload,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
        ) {
            guard let url = request.url else {
                publishSecurityMessage("Download redirect was blocked because it did not include a URL.")
                decisionHandler(.cancel)
                return
            }

            switch securityPolicy.decision(for: url) {
            case .allowInWebView:
                publishSecurityMessage(securityPolicy.securityMessage(forAllowedWebURL: url))
                downloadSourceMetadata[ObjectIdentifier(download)] = downloadSafetyPolicy.sourceMetadata(from: url)
                decisionHandler(.allow)
            case .requireExternalApplicationConfirmation, .requireLocalFileConfirmation:
                publishSecurityMessage("Download redirect was blocked because it left the web download flow.")
                decisionHandler(.cancel)
            case .block(let reason):
                publishSecurityMessage(reason)
                decisionHandler(.cancel)
            }
        }

        public func download(
            _ download: WKDownload,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @MainActor @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            completionHandler(.rejectProtectionSpace, nil)
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
                    publishSecurityMessage("Pop-up windows require permission for this site.")
                case .deny(let reason):
                    publishSecurityMessage(reason)
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

        private func requestConfirmation(
            _ kind: URLConfirmationRequest.Kind,
            url: URL,
            sourceURL: URL?
        ) {
            publishSecurityMessage(kind.pendingMessage)
            onURLConfirmationRequired(kind, url, URLConfirmationSourceContext(sourceURL: sourceURL))
        }

        private func prepare(_ download: WKDownload, sourceURL: URL?) {
            let identifier = ObjectIdentifier(download)
            if let sourceURL {
                downloadSourceMetadata[identifier] = downloadSafetyPolicy.sourceMetadata(from: sourceURL)
            } else {
                downloadSourceMetadata.removeValue(forKey: identifier)
            }
            download.delegate = self
        }

        private func cleanup(_ download: WKDownload) {
            let identifier = ObjectIdentifier(download)
            downloadSourceMetadata.removeValue(forKey: identifier)
            downloadDestinations.removeValue(forKey: identifier)
        }

        private func publishSecurityMessage(_ message: String?) {
            guard let message = message?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !message.isEmpty else {
                return
            }
            state.securityMessage = message
            onSecurityMessage(message)
        }

        private func shouldUpgradeNavigationAction(_ navigationAction: WKNavigationAction, url: URL) -> Bool {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  !navigationAction.shouldPerformDownload,
                  !httpFallbacksInFlight.contains(url) else {
                return false
            }

            return securityPolicy.httpsUpgradeCandidate(for: url) != nil
        }

        private func beginHTTPSUpgrade(from originalURL: URL, to upgradedURL: URL, in webView: WKWebView) {
            pendingHTTPFallbacksByUpgradeURL[upgradedURL] = originalURL
            httpFallbacksInFlight.remove(originalURL)
            if state.requestedURL != upgradedURL || state.pendingHTTPFallbackURL != originalURL {
                state.request(upgradedURL, pendingHTTPFallbackURL: originalURL)
            }
            webView.load(URLRequest(url: upgradedURL))
        }

        private func beginHTTPFallback(to fallbackURL: URL, in webView: WKWebView) {
            httpFallbacksInFlight.insert(fallbackURL)
            state.request(fallbackURL)
            onStateChange(nil, fallbackURL, true)
            publishSecurityMessage(securityPolicy.securityMessage(forAllowedWebURL: fallbackURL))
            webView.load(URLRequest(url: fallbackURL))
        }

        private func httpFallbackURL(for error: Error) -> URL? {
            let failedURL = failedNavigationURL(from: error) ?? state.requestedURL

            if let failedURL,
               let fallbackURL = pendingHTTPFallbacksByUpgradeURL.removeValue(forKey: failedURL) {
                return fallbackURL
            }

            guard let failedURL,
                  let fallbackURL = state.pendingHTTPFallbackURL,
                  securityPolicy.isHTTPSUpgradeCandidate(failedURL, for: fallbackURL) else {
                return nil
            }

            return fallbackURL
        }

        private func failedNavigationURL(from error: Error) -> URL? {
            let nsError = error as NSError
            return nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        }

        private func publish(_ webView: WKWebView, isLoading: Bool, message: String? = nil) {
            let title = webView.title
            let url = webView.url
            let progress = webView.estimatedProgress
            let canGoBack = webView.canGoBack
            let canGoForward = webView.canGoForward
            let securityMessage = message ?? url.flatMap {
                securityPolicy.securityMessage(forAllowedWebURL: $0)
            }

            Task { @MainActor in
                state.title = title ?? state.title
                state.committedURL = url
                if let url {
                    self.pendingHTTPFallbacksByUpgradeURL.removeValue(forKey: url)
                    self.httpFallbacksInFlight.remove(url)
                }
                state.isLoading = isLoading
                state.estimatedProgress = progress
                state.canGoBack = canGoBack
                state.canGoForward = canGoForward
                state.securityMessage = securityMessage
                if let securityMessage {
                    onSecurityMessage(securityMessage)
                }
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
