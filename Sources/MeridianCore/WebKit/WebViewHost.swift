import AppKit
import OSLog
import QuartzCore
import SwiftUI
import WebKit

private let webViewLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MeridianBrowser",
    category: "WebView"
)

@MainActor
struct BrowserWebViewCallbacks {
    var onStateChange: @MainActor (String?, URL?, Bool, String?) -> Void
    var onSecurityMessage: @MainActor (String) -> Void
    var onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
    var onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
    var onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
}

@MainActor
final class BrowserWebViewSession {
    let tabID: TabID
    let profileID: ProfileID
    let webView: WKWebView
    let coordinator: WebViewHost.Coordinator
    fileprivate var lastUsedSequence: UInt64

    init(
        tabID: TabID,
        profileID: ProfileID,
        webView: WKWebView,
        coordinator: WebViewHost.Coordinator,
        lastUsedSequence: UInt64
    ) {
        self.tabID = tabID
        self.profileID = profileID
        self.webView = webView
        self.coordinator = coordinator
        self.lastUsedSequence = lastUsedSequence
    }

    var lastLoadedURL: URL? {
        coordinator.lastLoadedRequestedURL
    }
}

@MainActor
public final class BrowserWebViewRegistry: ObservableObject {
    private var sessions: [TabID: BrowserWebViewSession] = [:]
    private let capacity: Int
    private var usageSequence: UInt64 = 0

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    public var liveSessionCount: Int {
        sessions.count
    }

    public func containsSession(for tabID: TabID) -> Bool {
        sessions[tabID] != nil
    }

    func session(
        for tab: BrowserTab,
        profile: BrowserProfile,
        state: WebViewState,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy,
        downloadSafetyPolicy: DownloadSafetyPolicy,
        sitePermissionPolicy: SitePermissionPolicy,
        callbacks: BrowserWebViewCallbacks
    ) -> BrowserWebViewSession {
        let sequence = nextUsageSequence()
        if let session = sessions[tab.id] {
            guard session.profileID == profile.id else {
                detach(session.webView)
                sessions.removeValue(forKey: tab.id)
                return makeSession(
                    for: tab,
                    profile: profile,
                    state: state,
                    dataStoreProvider: dataStoreProvider,
                    securityPolicy: securityPolicy,
                    downloadSafetyPolicy: downloadSafetyPolicy,
                    sitePermissionPolicy: sitePermissionPolicy,
                    callbacks: callbacks,
                    sequence: sequence
                )
            }
            session.lastUsedSequence = sequence
            session.coordinator.update(
                state: state,
                securityPolicy: securityPolicy,
                downloadSafetyPolicy: downloadSafetyPolicy,
                callbacks: callbacks,
                isActive: true
            )
            markActive(tab.id)
            enforceCapacity(activeTabID: tab.id)
            return session
        }

        return makeSession(
            for: tab,
            profile: profile,
            state: state,
            dataStoreProvider: dataStoreProvider,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            sitePermissionPolicy: sitePermissionPolicy,
            callbacks: callbacks,
            sequence: sequence
        )
    }

    private func makeSession(
        for tab: BrowserTab,
        profile: BrowserProfile,
        state: WebViewState,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy,
        downloadSafetyPolicy: DownloadSafetyPolicy,
        sitePermissionPolicy: SitePermissionPolicy,
        callbacks: BrowserWebViewCallbacks,
        sequence: UInt64
    ) -> BrowserWebViewSession {
        let coordinator = WebViewHost.Coordinator(
            tabID: tab.id,
            state: state,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            callbacks: callbacks,
            isActive: true
        )
        let webView = Self.makeWebView(
            profile: profile,
            dataStoreProvider: dataStoreProvider,
            sitePermissionPolicy: sitePermissionPolicy,
            coordinator: coordinator
        )
        let session = BrowserWebViewSession(
            tabID: tab.id,
            profileID: profile.id,
            webView: webView,
            coordinator: coordinator,
            lastUsedSequence: sequence
        )
        sessions[tab.id] = session
        markActive(tab.id)
        enforceCapacity(activeTabID: tab.id)
        return session
    }

    public func markActive(_ activeTabID: TabID?) {
        for (tabID, session) in sessions {
            session.coordinator.isActive = tabID == activeTabID
        }
    }

    public func prune(keeping tabIDs: Set<TabID>, activeTabID: TabID?) {
        let closedSessions = sessions.values.filter { !tabIDs.contains($0.tabID) }
        for session in closedSessions {
            detach(session.webView)
            sessions.removeValue(forKey: session.tabID)
        }
        markActive(activeTabID)
        enforceCapacity(activeTabID: activeTabID)
    }

    public func invalidate(tabIDs: Set<TabID>) {
        for tabID in tabIDs {
            guard let session = sessions.removeValue(forKey: tabID) else {
                continue
            }
            detach(session.webView)
        }
    }

    private func nextUsageSequence() -> UInt64 {
        usageSequence &+= 1
        return usageSequence
    }

    private func enforceCapacity(activeTabID: TabID?) {
        guard sessions.count > capacity else {
            return
        }

        let evictionCandidates = sessions.values
            .filter { $0.tabID != activeTabID }
            .sorted { $0.lastUsedSequence < $1.lastUsedSequence }

        for session in evictionCandidates where sessions.count > capacity {
            detach(session.webView)
            sessions.removeValue(forKey: session.tabID)
        }
    }

    private func detach(_ webView: WKWebView) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        CATransaction.commit()
    }

    private static func makeWebView(
        profile: BrowserProfile,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        sitePermissionPolicy: SitePermissionPolicy,
        coordinator: WebViewHost.Coordinator
    ) -> WKWebView {
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
        webView.customUserAgent = BrowserUserAgentPolicy.desktopSafariUserAgent()
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        return webView
    }
}

private final class BrowserWebViewContainerView: NSView {
    private weak var attachedWebView: WKWebView?
    private var attachedConstraints: [NSLayoutConstraint] = []

    func attach(_ webView: WKWebView) {
        guard attachedWebView !== webView || webView.superview !== self else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            detachCurrentWebView()

            if webView.superview !== self {
                webView.removeFromSuperview()
            }
            webView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(webView)
            attachedWebView = webView
            attachedConstraints = [
                webView.leadingAnchor.constraint(equalTo: leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: trailingAnchor),
                webView.topAnchor.constraint(equalTo: topAnchor),
                webView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ]
            NSLayoutConstraint.activate(attachedConstraints)
            layoutSubtreeIfNeeded()
            CATransaction.commit()
        }
    }

    func detachCurrentWebView() {
        guard let attachedWebView else {
            return
        }

        NSLayoutConstraint.deactivate(attachedConstraints)
        attachedConstraints.removeAll()
        attachedWebView.removeFromSuperview()
        self.attachedWebView = nil
    }
}

@MainActor
public struct WebViewHost: NSViewRepresentable {
    @ObservedObject private var state: WebViewState

    private let tab: BrowserTab
    private let profile: BrowserProfile
    private let registry: BrowserWebViewRegistry
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let securityPolicy: URLSecurityPolicy
    private let downloadSafetyPolicy: DownloadSafetyPolicy
    private let sitePermissionPolicy: SitePermissionPolicy
    private let onStateChange: @MainActor (String?, URL?, Bool, String?) -> Void
    private let onSecurityMessage: @MainActor (String) -> Void
    private let onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
    private let onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
    private let onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation

    public init(
        state: WebViewState,
        tab: BrowserTab,
        profile: BrowserProfile,
        registry: BrowserWebViewRegistry,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        onStateChange: @escaping @MainActor (String?, URL?, Bool, String?) -> Void,
        onSecurityMessage: @escaping @MainActor (String) -> Void = { _ in },
        onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void = { _, _, _ in },
        onDownloadConfirmationRequired: @escaping @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void = { _, completion in completion(nil) },
        onSitePermissionRequest: @escaping @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation = { _, _ in
            .deny(reason: "Site permission request was blocked because no permission handler is installed.")
        }
    ) {
        self.state = state
        self.tab = tab
        self.profile = profile
        self.registry = registry
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

    public func makeNSView(context: Context) -> NSView {
        BrowserWebViewContainerView()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            tabID: tab.id,
            state: state,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            callbacks: BrowserWebViewCallbacks(
                onStateChange: onStateChange,
                onSecurityMessage: onSecurityMessage,
                onURLConfirmationRequired: onURLConfirmationRequired,
                onDownloadConfirmationRequired: onDownloadConfirmationRequired,
                onSitePermissionRequest: onSitePermissionRequest
            ),
            isActive: false
        )
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? BrowserWebViewContainerView else {
            return
        }

        let callbacks = BrowserWebViewCallbacks(
            onStateChange: onStateChange,
            onSecurityMessage: onSecurityMessage,
            onURLConfirmationRequired: onURLConfirmationRequired,
            onDownloadConfirmationRequired: onDownloadConfirmationRequired,
            onSitePermissionRequest: onSitePermissionRequest
        )
        let session = registry.session(
            for: tab,
            profile: profile,
            state: state,
            dataStoreProvider: dataStoreProvider,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            sitePermissionPolicy: sitePermissionPolicy,
            callbacks: callbacks
        )

        container.attach(session.webView)
        session.coordinator.applyPendingState(to: session.webView)
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? BrowserWebViewContainerView)?.detachCurrentWebView()
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        fileprivate let tabID: TabID
        fileprivate var state: WebViewState
        fileprivate var securityPolicy: URLSecurityPolicy
        fileprivate var downloadSafetyPolicy: DownloadSafetyPolicy
        fileprivate var callbacks: BrowserWebViewCallbacks
        fileprivate var isActive: Bool
        fileprivate var lastHandledCommandID: UUID?
        fileprivate var lastLoadedRequestedURL: URL?
        private var pendingHTTPFallbacksByUpgradeURL: [URL: URL] = [:]
        private var httpFallbacksInFlight: Set<URL> = []
        private var downloadSourceMetadata: [ObjectIdentifier: DownloadSourceMetadata] = [:]
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]

        init(
            tabID: TabID,
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            downloadSafetyPolicy: DownloadSafetyPolicy,
            callbacks: BrowserWebViewCallbacks,
            isActive: Bool
        ) {
            self.tabID = tabID
            self.state = state
            self.securityPolicy = securityPolicy
            self.downloadSafetyPolicy = downloadSafetyPolicy
            self.callbacks = callbacks
            self.isActive = isActive
        }

        fileprivate func update(
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            downloadSafetyPolicy: DownloadSafetyPolicy,
            callbacks: BrowserWebViewCallbacks,
            isActive: Bool
        ) {
            self.state = state
            self.securityPolicy = securityPolicy
            self.downloadSafetyPolicy = downloadSafetyPolicy
            self.callbacks = callbacks
            self.isActive = isActive
        }

        fileprivate func applyPendingState(to webView: WKWebView) {
            if let commandRequest = state.pendingCommand,
               lastHandledCommandID != commandRequest.id {
                lastHandledCommandID = commandRequest.id
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

            loadRequestedURLIfNeeded(requestedURL, in: webView)
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
            handleNavigationFailure(webView, error: error, phase: "committed")
        }

        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let fallbackURL = httpFallbackURL(for: error) {
                if securityPolicy.shouldFallbackToHTTP(afterHTTPSUpgradeError: error) {
                    beginHTTPFallback(to: fallbackURL, in: webView)
                    return
                }

                discardHTTPFallback(to: fallbackURL)
            }

            handleNavigationFailure(webView, error: error, phase: "provisional")
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
                guard isActive || !navigationAction.shouldPerformDownload else {
                    decisionHandler(.cancel)
                    return
                }

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
            guard isActive || navigationResponse.canShowMIMEType else {
                decisionHandler(.cancel)
                return
            }

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
            guard isActive else {
                cleanup(download)
                completionHandler(nil)
                return
            }

            let identifier = ObjectIdentifier(download)
            let sourceMetadata = downloadSourceMetadata[identifier] ?? downloadSafetyPolicy.sourceMetadata(from: response.url)
            let request = downloadSafetyPolicy.confirmationRequest(
                suggestedFilename: suggestedFilename,
                sourceMetadata: sourceMetadata
            )

            publishSecurityMessage(request.pendingMessage)
            callbacks.onDownloadConfirmationRequired(request) { [weak self] destinationURL in
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
            guard isActive else {
                decisionHandler(.cancel)
                return
            }

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
            guard isActive else {
                return nil
            }

            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                if WebViewNewWindowPolicy.shouldOpenInCurrentTab(
                    navigationType: navigationAction.navigationType,
                    sourceFrameIsMainFrame: navigationAction.sourceFrame.isMainFrame
                ) {
                    routeWebContentNavigation(to: url, in: webView)
                } else {
                    let origin = SitePermissionOrigin(securityOrigin: navigationAction.sourceFrame.securityOrigin)
                        ?? SitePermissionOrigin(url: webView.url ?? url)
                    switch callbacks.onSitePermissionRequest(.popupWindow, origin) {
                    case .allow:
                        routeWebContentNavigation(to: url, in: webView)
                    case .ask:
                        publishSecurityMessage("Pop-up windows require permission for this site.")
                    case .deny(let reason):
                        publishSecurityMessage(reason)
                    }
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
            guard isActive else {
                decisionHandler(.deny)
                return
            }

            let permissionOrigin = SitePermissionOrigin(securityOrigin: origin)
                ?? frame.request.url.flatMap(SitePermissionOrigin.init(url:))
            let evaluation = callbacks.onSitePermissionRequest(Self.permissionKind(for: type), permissionOrigin)
            decisionHandler(Self.webKitPermissionDecision(for: evaluation))
        }

        private func requestConfirmation(
            _ kind: URLConfirmationRequest.Kind,
            url: URL,
            sourceURL: URL?
        ) {
            guard isActive else {
                return
            }

            publishSecurityMessage(kind.pendingMessage)
            callbacks.onURLConfirmationRequired(kind, url, URLConfirmationSourceContext(sourceURL: sourceURL))
        }

        fileprivate func loadRequestedURLIfNeeded(_ requestedURL: URL, in webView: WKWebView) {
            guard lastLoadedRequestedURL != requestedURL else {
                return
            }

            lastLoadedRequestedURL = requestedURL
            guard webView.url != requestedURL else {
                return
            }

            webView.load(URLRequest(url: requestedURL))
        }

        private func routeWebContentNavigation(to url: URL, in webView: WKWebView) {
            switch securityPolicy.decision(for: url) {
            case .allowInWebView:
                publishSecurityMessage(securityPolicy.securityMessage(forAllowedWebURL: url))
                loadRequestedURLIfNeeded(url, in: webView)
            case .requireExternalApplicationConfirmation:
                requestConfirmation(.externalApplication, url: url, sourceURL: webView.url)
            case .requireLocalFileConfirmation:
                requestConfirmation(.localFile, url: url, sourceURL: webView.url)
            case .block(let reason):
                publishSecurityMessage(reason)
            }
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
            guard isActive else {
                return
            }
            state.securityMessage = message
            callbacks.onSecurityMessage(message)
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
            if isActive,
               state.requestedURL != upgradedURL || state.pendingHTTPFallbackURL != originalURL {
                state.request(upgradedURL, pendingHTTPFallbackURL: originalURL)
            }
            lastLoadedRequestedURL = upgradedURL
            webView.load(URLRequest(url: upgradedURL))
        }

        private func beginHTTPFallback(to fallbackURL: URL, in webView: WKWebView) {
            httpFallbacksInFlight.insert(fallbackURL)
            if isActive {
                state.request(fallbackURL)
            }
            let securityMessage = securityPolicy.securityMessage(forAllowedWebURL: fallbackURL)
            callbacks.onStateChange(nil, fallbackURL, true, securityMessage)
            publishSecurityMessage(securityMessage)
            lastLoadedRequestedURL = fallbackURL
            webView.load(URLRequest(url: fallbackURL))
        }

        private func discardHTTPFallback(to fallbackURL: URL) {
            pendingHTTPFallbacksByUpgradeURL = pendingHTTPFallbacksByUpgradeURL.filter { $0.value != fallbackURL }
            httpFallbacksInFlight.remove(fallbackURL)
            if isActive, state.pendingHTTPFallbackURL == fallbackURL {
                state.pendingHTTPFallbackURL = nil
            }
        }

        private func httpFallbackURL(for error: Error) -> URL? {
            let failedURL = failedNavigationURL(from: error) ?? lastLoadedRequestedURL ?? state.requestedURL

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
                if let url {
                    self.pendingHTTPFallbacksByUpgradeURL.removeValue(forKey: url)
                    self.httpFallbacksInFlight.remove(url)
                }
                if self.isActive {
                    self.state.title = title ?? self.state.title
                    self.state.committedURL = url
                    self.state.isLoading = isLoading
                    self.state.estimatedProgress = progress
                    self.state.canGoBack = canGoBack
                    self.state.canGoForward = canGoForward
                    self.state.securityMessage = securityMessage
                    if let securityMessage {
                        self.callbacks.onSecurityMessage(securityMessage)
                    }
                }
                self.callbacks.onStateChange(title, url, isLoading, securityMessage)
            }
        }

        private func handleNavigationFailure(_ webView: WKWebView, error: Error, phase: String) {
            let diagnostics = NavigationFailureDiagnostics(error: error)
            guard let message = diagnostics.userMessage else {
                webViewLogger.debug(
                    "Suppressed benign navigation failure. phase=\(phase, privacy: .public) domain=\(diagnostics.domain, privacy: .public) code=\(diagnostics.code, privacy: .public)"
                )
                publish(webView, isLoading: false)
                return
            }

            webViewLogger.error(
                "Navigation failed. phase=\(phase, privacy: .public) domain=\(diagnostics.domain, privacy: .public) code=\(diagnostics.code, privacy: .public)"
            )
            publish(webView, isLoading: false, message: message)
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

struct NavigationFailureDiagnostics {
    let domain: String
    let code: Int
    let userMessage: String?

    init(error: Error) {
        let nsError = error as NSError
        domain = nsError.domain
        code = nsError.code
        userMessage = Self.userMessage(for: nsError)
    }

    private static func userMessage(for error: NSError) -> String? {
        if isBenignNavigationCancellation(error) {
            return nil
        }

        guard error.domain == NSURLErrorDomain else {
            return "Navigation failed. Check Meridian logs for details."
        }

        switch error.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "Navigation failed: network connection is unavailable."
        case NSURLErrorTimedOut:
            return "Navigation failed: request timed out."
        case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed:
            return "Navigation failed: server could not be reached."
        case NSURLErrorUnsupportedURL:
            return "Navigation failed: URL is not supported."
        case NSURLErrorAppTransportSecurityRequiresSecureConnection:
            return "Navigation failed: insecure connection was blocked."
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return "Navigation failed: secure connection could not be verified."
        default:
            return "Navigation failed. Check Meridian logs for details."
        }
    }

    private static func isBenignNavigationCancellation(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return true
        }

        if error.domain == "WebKitErrorDomain" && error.code == 102 {
            return true
        }

        return false
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
