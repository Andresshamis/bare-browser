import SwiftUI
import WebKit

@MainActor
public struct WebViewHost: NSViewRepresentable {
    @ObservedObject private var state: WebViewState

    private let profile: BrowserProfile
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let securityPolicy: URLSecurityPolicy
    private let downloadSafetyPolicy: DownloadSafetyPolicy
    private let onStateChange: @MainActor (String?, URL?, Bool) -> Void
    private let onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
    private let onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void

    public init(
        state: WebViewState,
        profile: BrowserProfile,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
        onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void = { _, _, _ in },
        onDownloadConfirmationRequired: @escaping @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void = { _, completion in completion(nil) }
    ) {
        self.state = state
        self.profile = profile
        self.dataStoreProvider = dataStoreProvider
        self.securityPolicy = securityPolicy
        self.downloadSafetyPolicy = downloadSafetyPolicy
        self.onStateChange = onStateChange
        self.onURLConfirmationRequired = onURLConfirmationRequired
        self.onDownloadConfirmationRequired = onDownloadConfirmationRequired
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            state: state,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            onStateChange: onStateChange,
            onURLConfirmationRequired: onURLConfirmationRequired,
            onDownloadConfirmationRequired: onDownloadConfirmationRequired
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
        context.coordinator.onDownloadConfirmationRequired = onDownloadConfirmationRequired

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
        fileprivate var onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
        fileprivate var onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
        fileprivate var lastHandledCommandID: UUID?
        private var downloadSourceMetadata: [ObjectIdentifier: DownloadSourceMetadata] = [:]
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        init(
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            downloadSafetyPolicy: DownloadSafetyPolicy,
            onStateChange: @escaping @MainActor (String?, URL?, Bool) -> Void,
            onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void,
            onDownloadConfirmationRequired: @escaping @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
        ) {
            self.state = state
            self.securityPolicy = securityPolicy
            self.downloadSafetyPolicy = downloadSafetyPolicy
            self.onStateChange = onStateChange
            self.onURLConfirmationRequired = onURLConfirmationRequired
            self.onDownloadConfirmationRequired = onDownloadConfirmationRequired
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
                decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
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

            state.securityMessage = request.pendingMessage
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
                state.securityMessage = didApplyQuarantine
                    ? "Download finished: \(destinationURL.lastPathComponent)"
                    : "Download finished, but quarantine metadata could not be applied."
            } else {
                state.securityMessage = "Download finished."
            }

            cleanup(download)
        }

        public func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            state.securityMessage = error.localizedDescription
            cleanup(download)
        }

        public func download(
            _ download: WKDownload,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
        ) {
            guard let url = request.url else {
                state.securityMessage = "Download redirect was blocked because it did not include a URL."
                decisionHandler(.cancel)
                return
            }

            switch securityPolicy.decision(for: url) {
            case .allowInWebView:
                downloadSourceMetadata[ObjectIdentifier(download)] = downloadSafetyPolicy.sourceMetadata(from: url)
                decisionHandler(.allow)
            case .requireExternalApplicationConfirmation, .requireLocalFileConfirmation:
                state.securityMessage = "Download redirect was blocked because it left the web download flow."
                decisionHandler(.cancel)
            case .block(let reason):
                state.securityMessage = reason
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
