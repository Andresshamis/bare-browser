import AppKit
import OSLog
import QuartzCore
import SwiftUI
import WebKit

private let webViewLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MeridianBrowser",
    category: "WebView"
)

private enum BrowserContextMenuScript {
    static let messageHandlerName = "meridianContextMenuTarget"
    @MainActor static var contentWorld: WKContentWorld {
        WKContentWorld.defaultClient
    }

    static let source = """
    (() => {
        if (window.__meridianContextMenuTargetInstalled) {
            return;
        }
        window.__meridianContextMenuTargetInstalled = true;

        const absoluteURL = value => {
            if (!value || typeof value !== "string") {
                return null;
            }
            try {
                return new URL(value, document.baseURI).href;
            } catch {
                return null;
            }
        };

        const elementFor = node => {
            if (!node) {
                return null;
            }
            return node instanceof Element ? node : node.parentElement;
        };

        const imageURLFor = node => {
            let candidate = elementFor(node);
            while (candidate && candidate !== document) {
                if (candidate instanceof HTMLImageElement) {
                    return absoluteURL(candidate.currentSrc || candidate.src);
                }
                if (candidate instanceof SVGImageElement) {
                    return absoluteURL(candidate.href && candidate.href.baseVal);
                }
                candidate = candidate.parentElement;
            }
            return null;
        };

        const contextTargetForNode = (target, clientX, clientY) => {
            const element = elementFor(target);
            const link = element && element.closest ? element.closest("a[href]") : null;
            return {
                imageURL: imageURLFor(target),
                linkURL: link ? absoluteURL(link.getAttribute("href")) : null,
                pageURL: absoluteURL(window.location.href),
                clientX: Number.isFinite(clientX) ? clientX : null,
                clientY: Number.isFinite(clientY) ? clientY : null
            };
        };

        const contextTargetFor = event => contextTargetForNode(event.target, event.clientX, event.clientY);

        window.__meridianContextTargetForPoint = (clientX, clientY) => {
            const target = Number.isFinite(clientX) && Number.isFinite(clientY)
                ? document.elementFromPoint(clientX, clientY)
                : null;
            return contextTargetForNode(target, clientX, clientY);
        };

        const postContextTarget = event => {
            window.webkit.messageHandlers.\(messageHandlerName).postMessage(contextTargetFor(event));
        };

        const shouldCapturePress = event => event.button === 2 || event.ctrlKey;

        document.addEventListener("pointerdown", event => {
            if (shouldCapturePress(event)) {
                postContextTarget(event);
            }
        }, true);

        document.addEventListener("mousedown", event => {
            if (shouldCapturePress(event)) {
                postContextTarget(event);
            }
        }, true);

        document.addEventListener("contextmenu", event => {
            const target = contextTargetFor(event);
            window.webkit.messageHandlers.\(messageHandlerName).postMessage(target);
        }, true);
    })();
    """
}

private enum BrowserFaviconScript {
    static let source = """
    (() => {
        const absoluteURL = value => {
            if (!value || typeof value !== "string") {
                return null;
            }
            try {
                return new URL(value, document.baseURI).href;
            } catch {
                return null;
            }
        };

        const sizeScore = sizes => {
            if (!sizes || sizes.toLowerCase() === "any") {
                return 0;
            }
            return sizes
                .split(/\\s+/)
                .map(value => {
                    const match = value.match(/^(\\d+)x(\\d+)$/i);
                    return match ? Number(match[1]) * Number(match[2]) : 0;
                })
                .reduce((best, value) => Math.max(best, value), 0);
        };

        const candidates = Array.from(document.querySelectorAll("link[rel][href]"))
            .map(link => {
                const relTokens = (link.getAttribute("rel") || "")
                    .toLowerCase()
                    .split(/\\s+/)
                    .filter(Boolean);
                const href = absoluteURL(link.getAttribute("href"));
                if (!href) {
                    return null;
                }

                const relScore = relTokens.includes("apple-touch-icon") ||
                    relTokens.includes("apple-touch-icon-precomposed") ? 400 :
                    relTokens.includes("icon") ? 300 :
                    relTokens.includes("shortcut") && relTokens.includes("icon") ? 250 :
                    relTokens.includes("mask-icon") ? 100 :
                    0;
                if (relScore === 0) {
                    return null;
                }

                return {
                    href,
                    score: relScore + Math.min(sizeScore(link.getAttribute("sizes")), 10000)
                };
            })
            .filter(Boolean)
            .sort((lhs, rhs) => rhs.score - lhs.score);

        return candidates.length ? candidates[0].href : absoluteURL("/favicon.ico");
    })()
    """

    static func url(from value: Any?) -> URL? {
        guard let string = value as? String else {
            return nil;
        }
        return URL(string: string)
    }
}

struct BrowserContextMenuDownloadTarget: Equatable {
    var imageURL: URL?
    var linkURL: URL?
    var pageURL: URL?
    var clientPoint: CGPoint?
    var shouldShowDownloadMenu: Bool

    init(
        imageURL: URL? = nil,
        linkURL: URL? = nil,
        pageURL: URL? = nil,
        clientPoint: CGPoint? = nil,
        shouldShowDownloadMenu: Bool = false
    ) {
        self.imageURL = imageURL
        self.linkURL = linkURL
        self.pageURL = pageURL
        self.clientPoint = clientPoint
        self.shouldShowDownloadMenu = shouldShowDownloadMenu
    }

    init(messageBody: Any) {
        let body = messageBody as? [String: Any]
            ?? (messageBody as? NSDictionary) as? [String: Any]
        imageURL = Self.url(from: body?["imageURL"])
        linkURL = Self.url(from: body?["linkURL"])
        pageURL = Self.url(from: body?["pageURL"])
        clientPoint = Self.point(x: body?["clientX"], y: body?["clientY"])
        shouldShowDownloadMenu = body?["showDownloadMenu"] as? Bool ?? false
    }

    private static func url(from value: Any?) -> URL? {
        guard let string = value as? String,
              let url = URL(string: string) else {
            return nil
        }

        return url
    }

    private static func point(x: Any?, y: Any?) -> CGPoint? {
        guard let x = Self.double(from: x),
              let y = Self.double(from: y) else {
            return nil
        }

        return CGPoint(x: x, y: y)
    }

    private static func double(from value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value.isFinite ? value : nil
        case let value as CGFloat:
            return value.isFinite ? Double(value) : nil
        case let value as NSNumber:
            let doubleValue = value.doubleValue
            return doubleValue.isFinite ? doubleValue : nil
        default:
            return nil
        }
    }
}

enum BrowserContextMenuDownloadKind: Hashable {
    case image
    case linkedFile

    private static let legacyDownloadLinkToDiskTag = 2
    private static let legacyDownloadImageToDiskTag = 5

    static func kind(for item: NSMenuItem) -> BrowserContextMenuDownloadKind? {
        switch item.tag {
        case legacyDownloadImageToDiskTag:
            return .image
        case legacyDownloadLinkToDiskTag:
            return .linkedFile
        default:
            break
        }

        let normalizedTitle = item.title.lowercased()
        if normalizedTitle.contains("download image") || normalizedTitle.contains("save image") {
            return .image
        }
        if normalizedTitle.contains("download linked file") || normalizedTitle.contains("download link") {
            return .linkedFile
        }

        let normalizedIdentifier = item.identifier?.rawValue.lowercased()
        if normalizedIdentifier?.contains("downloadimage") == true {
            return .image
        }
        if normalizedIdentifier?.contains("downloadlink") == true
            || normalizedIdentifier?.contains("downloadlinkedfile") == true {
            return .linkedFile
        }

        return nil
    }
}

@MainActor
struct BrowserWebViewCallbacks {
    var onStateChange: @MainActor (String?, URL?, Bool, String?) -> Void
    var onFaviconChange: @MainActor (URL?) -> Void
    var onSecurityMessage: @MainActor (String) -> Void
    var onURLConfirmationRequired: @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
    var onDownloadConfirmationRequired: @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
    var onDownloadStarted: @MainActor (DownloadConfirmationRequest, URL, @escaping @MainActor () -> Void) -> Void
    var onDownloadProgress: @MainActor (UUID, Double?) -> Void
    var onDownloadFinished: @MainActor (UUID, URL?, Bool) -> Void
    var onDownloadFailed: @MainActor (UUID, String) -> Void
    var onSitePermissionRequest: @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
    var onSnapshot: @MainActor (NSImage) -> Void

    init(
        onStateChange: @escaping @MainActor (String?, URL?, Bool, String?) -> Void,
        onFaviconChange: @escaping @MainActor (URL?) -> Void = { _ in },
        onSecurityMessage: @escaping @MainActor (String) -> Void,
        onURLConfirmationRequired: @escaping @MainActor (URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void,
        onDownloadConfirmationRequired: @escaping @MainActor (DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void,
        onDownloadStarted: @escaping @MainActor (DownloadConfirmationRequest, URL, @escaping @MainActor () -> Void) -> Void = { _, _, _ in },
        onDownloadProgress: @escaping @MainActor (UUID, Double?) -> Void = { _, _ in },
        onDownloadFinished: @escaping @MainActor (UUID, URL?, Bool) -> Void = { _, _, _ in },
        onDownloadFailed: @escaping @MainActor (UUID, String) -> Void = { _, _ in },
        onSitePermissionRequest: @escaping @MainActor (SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation,
        onSnapshot: @escaping @MainActor (NSImage) -> Void = { _ in }
    ) {
        self.onStateChange = onStateChange
        self.onFaviconChange = onFaviconChange
        self.onSecurityMessage = onSecurityMessage
        self.onURLConfirmationRequired = onURLConfirmationRequired
        self.onDownloadConfirmationRequired = onDownloadConfirmationRequired
        self.onDownloadStarted = onDownloadStarted
        self.onDownloadProgress = onDownloadProgress
        self.onDownloadFinished = onDownloadFinished
        self.onDownloadFailed = onDownloadFailed
        self.onSitePermissionRequest = onSitePermissionRequest
        self.onSnapshot = onSnapshot
    }
}

public struct WebContentMouseExclusionRegion: Equatable, Sendable {
    public var edge: SidebarRevealEdge
    public var width: CGFloat
    public var inset: CGFloat
    public var cornerRadius: CGFloat

    public init(
        edge: SidebarRevealEdge,
        width: CGFloat,
        inset: CGFloat,
        cornerRadius: CGFloat
    ) {
        self.edge = edge
        self.width = width
        self.inset = inset
        self.cornerRadius = cornerRadius
    }

    func frame(in bounds: CGRect) -> CGRect {
        let clampedWidth = min(max(width, 0), max(0, bounds.width - inset * 2))
        let clampedHeight = max(0, bounds.height - inset * 2)
        let x = switch edge {
        case .left:
            bounds.minX + inset
        case .right:
            bounds.maxX - inset - clampedWidth
        }

        return CGRect(
            x: x,
            y: bounds.minY + inset,
            width: clampedWidth,
            height: clampedHeight
        )
    }
}

@MainActor
enum BrowserWebContentAppearance {
    static func appearanceName(for colorScheme: ColorScheme) -> NSAppearance.Name {
        colorScheme == .dark ? .darkAqua : .aqua
    }

    static func underPageBackgroundColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? .black : .white
    }

    static func apply(_ colorScheme: ColorScheme, to webView: WKWebView) {
        webView.appearance = NSAppearance(named: appearanceName(for: colorScheme))
        webView.underPageBackgroundColor = underPageBackgroundColor(for: colorScheme)
    }
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
        callbacks: BrowserWebViewCallbacks,
        isActive: Bool = true
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
                    sequence: sequence,
                    isActive: isActive
                )
            }
            session.lastUsedSequence = sequence
            session.coordinator.update(
                state: state,
                securityPolicy: securityPolicy,
                downloadSafetyPolicy: downloadSafetyPolicy,
                callbacks: callbacks,
                requestedURL: tab.url,
                pendingHTTPFallbackURL: tab.restorationMetadata.pendingHTTPFallbackURL,
                isActive: isActive
            )
            if isActive {
                markActive(tab.id)
            }
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
            sequence: sequence,
            isActive: isActive
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
        sequence: UInt64,
        isActive: Bool
    ) -> BrowserWebViewSession {
        let coordinator = WebViewHost.Coordinator(
            tabID: tab.id,
            state: state,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            callbacks: callbacks,
            requestedURL: tab.url,
            pendingHTTPFallbackURL: tab.restorationMetadata.pendingHTTPFallbackURL,
            isActive: isActive
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
        if isActive {
            markActive(tab.id)
        }
        enforceCapacity(activeTabID: tab.id)
        return session
    }

    public func markActive(_ activeTabID: TabID?) {
        for (tabID, session) in sessions {
            session.coordinator.isActive = tabID == activeTabID
        }
    }

    func applyColorScheme(_ colorScheme: ColorScheme) {
        for session in sessions.values {
            BrowserWebContentAppearance.apply(colorScheme, to: session.webView)
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
        configuration.userContentController.addUserScript(WKUserScript(
            source: BrowserContextMenuScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: BrowserContextMenuScript.contentWorld
        ))
        configuration.userContentController.add(
            WeakScriptMessageHandler(target: coordinator),
            contentWorld: BrowserContextMenuScript.contentWorld,
            name: BrowserContextMenuScript.messageHandlerName
        )
        ContentBlockerService.installDefaultRules(into: configuration.userContentController)

        let webView = BrowserWKWebView(frame: .zero, configuration: configuration)
        webView.contextMenuDownloadHandler = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        return webView
    }
}

@MainActor
private protocol BrowserContextMenuDownloadHandling: AnyObject {
    func prepareContextMenu(for event: NSEvent, in webView: WKWebView)
    func configureContextMenu(_ menu: NSMenu?, in webView: WKWebView)
    func performContextMenuDownload(_ kind: BrowserContextMenuDownloadKind, in webView: WKWebView)
}

private final class BrowserWKWebView: WKWebView {
    private struct UnsafeNotification: @unchecked Sendable {
        let value: Notification
    }

    private final class NotificationObserverBag: @unchecked Sendable {
        private var observers: [NSObjectProtocol] = []

        func replace(with observers: [NSObjectProtocol]) {
            removeAll()
            self.observers = observers
        }

        func removeAll() {
            let center = NotificationCenter.default
            for observer in observers {
                center.removeObserver(observer)
            }
            observers = []
        }

        deinit {
            removeAll()
        }
    }

    weak var contextMenuDownloadHandler: BrowserContextMenuDownloadHandling?
    private let contextMenuNotificationObservers = NotificationObserverBag()

    override func rightMouseDown(with event: NSEvent) {
        webViewLogger.info("context-menu rightMouseDown")
        contextMenuDownloadHandler?.prepareContextMenu(for: event, in: self)
        installContextMenuNotificationObservers()
        super.rightMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        webViewLogger.info("context-menu requested")
        return configuredMenu(for: event)
    }

    private func configuredMenu(for event: NSEvent) -> NSMenu? {
        contextMenuDownloadHandler?.prepareContextMenu(for: event, in: self)
        let menu = super.menu(for: event)
        webViewLogger.info("context-menu native menu built itemCount=\(menu?.items.count ?? 0, privacy: .public)")
        contextMenuDownloadHandler?.configureContextMenu(menu, in: self)
        webViewLogger.info("context-menu configured itemCount=\(menu?.items.count ?? 0, privacy: .public)")
        return menu
    }

    private func installContextMenuNotificationObservers() {
        removeContextMenuNotificationObservers()

        let center = NotificationCenter.default
        let beginObserver = center.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notification = UnsafeNotification(value: notification)
            MainActor.assumeIsolated {
                self?.contextMenuDidBeginTracking(notification.value)
            }
        }
        let willSendObserver = center.addObserver(
            forName: NSMenu.willSendActionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let notification = UnsafeNotification(value: notification)
            MainActor.assumeIsolated {
                self?.contextMenuWillSendAction(notification.value)
            }
        }
        let endObserver = center.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeContextMenuNotificationObservers()
            }
        }

        contextMenuNotificationObservers.replace(with: [beginObserver, willSendObserver, endObserver])
    }

    private func removeContextMenuNotificationObservers() {
        contextMenuNotificationObservers.removeAll()
    }

    private func contextMenuDidBeginTracking(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              isWebKitContextMenu(menu) else {
            return
        }

        webViewLogger.info("context-menu didBeginTracking itemCount=\(menu.items.count, privacy: .public)")
        contextMenuDownloadHandler?.configureContextMenu(menu, in: self)
    }

    private func contextMenuWillSendAction(_ notification: Notification) {
        guard let item = contextMenuItem(from: notification),
              item.target !== contextMenuDownloadHandler,
              let kind = BrowserContextMenuDownloadKind.kind(for: item) else {
            return
        }

        webViewLogger.info(
            "context-menu willSendAction intercepted title=\(item.title, privacy: .public)"
        )
        contextMenuDownloadHandler?.performContextMenuDownload(kind, in: self)
    }

    private func contextMenuItem(from notification: Notification) -> NSMenuItem? {
        if let item = notification.object as? NSMenuItem {
            return item
        }

        if let values = notification.userInfo?.values {
            for value in values {
                if let item = value as? NSMenuItem {
                    return item
                }
            }
        }

        guard let menu = notification.object as? NSMenu else {
            return nil
        }

        if let highlightedItem = menu.highlightedItem {
            return highlightedItem
        }

        if let index = notification.userInfo?["NSMenuItemIndex"] as? NSNumber {
            let itemIndex = index.intValue
            if menu.items.indices.contains(itemIndex) {
                return menu.items[itemIndex]
            }
        }

        return nil
    }

    private func isWebKitContextMenu(_ menu: NSMenu) -> Bool {
        menu.items.contains { item in
            item.identifier?.rawValue.hasPrefix("WKMenuItemIdentifier") == true
                || item.submenu.map(isWebKitContextMenu(_:)) == true
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

final class BrowserWebViewContainerView: NSView {
    private weak var activeWebView: WKWebView?
    private let hitTestBlocker = WebContentHitTestBlockerView()
    var mouseExclusionRegion: WebContentMouseExclusionRegion? {
        didSet {
            updateHitTestBlockerFrame()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configureHitTestBlocker()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        configureHitTestBlocker()
    }

    @discardableResult
    func attach(_ webView: WKWebView) -> Bool {
        guard activeWebView !== webView || webView.superview !== self || webView.alphaValue < 1 else {
            return false
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            if let activeWebView,
               activeWebView !== webView,
               activeWebView.superview === self {
                activeWebView.removeFromSuperview()
            }

            if webView.superview !== self {
                webView.removeFromSuperview()
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = [.width, .height]
                webView.frame = bounds
                webView.isHidden = false
                addSubview(webView)
            }

            webView.isHidden = false
            webView.alphaValue = 1
            webView.layer?.opacity = 1
            webView.frame = bounds
            activeWebView = webView
            keepHitTestBlockerAboveWebContent()
            CATransaction.commit()
        }
        return true
    }

    func suspendActiveWebView() {
        guard let activeWebView,
              activeWebView.superview === self else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeWebView.alphaValue = 0
        activeWebView.layer?.opacity = 0
        activeWebView.frame = bounds
        CATransaction.commit()
    }

    func deactivateActiveWebView() {
        guard let activeWebView else {
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        activeWebView.removeFromSuperview()
        self.activeWebView = nil
        CATransaction.commit()
    }

    func detachCurrentWebView() {
        activeWebView?.removeFromSuperview()
        activeWebView = nil
    }

    override func layout() {
        super.layout()
        for subview in subviews {
            guard subview !== hitTestBlocker else {
                continue
            }
            subview.frame = bounds
        }
        updateHitTestBlockerFrame()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else {
            return nil
        }

        let blockerPoint = convert(point, to: hitTestBlocker)
        if let blockerHit = hitTestBlocker.hitTest(blockerPoint) {
            return blockerHit
        }

        guard let activeWebView,
              activeWebView.alphaValue >= 1,
              !activeWebView.isHidden,
              activeWebView.superview === self else {
            return nil
        }

        return activeWebView.hitTest(convert(point, to: activeWebView))
    }

    private func configureHitTestBlocker() {
        hitTestBlocker.isHidden = true
        addSubview(hitTestBlocker)
    }

    private func keepHitTestBlockerAboveWebContent() {
        guard hitTestBlocker.superview === self else {
            addSubview(hitTestBlocker)
            return
        }

        hitTestBlocker.removeFromSuperview()
        addSubview(hitTestBlocker)
        updateHitTestBlockerFrame()
    }

    private func updateHitTestBlockerFrame() {
        guard let mouseExclusionRegion else {
            hitTestBlocker.isHidden = true
            return
        }

        hitTestBlocker.cornerRadius = mouseExclusionRegion.cornerRadius
        hitTestBlocker.frame = mouseExclusionRegion.frame(in: bounds)
        hitTestBlocker.isHidden = hitTestBlocker.frame.isEmpty
        window?.invalidateCursorRects(for: hitTestBlocker)
    }
}

final class WebContentHitTestBlockerView: NSView {
    var cornerRadius: CGFloat = 0 {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    private var hoverTrackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRegionContains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self
        )
        addTrackingArea(area)
        hoverTrackingArea = area
        super.updateTrackingAreas()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    func hitRegionContains(_ point: NSPoint) -> Bool {
        guard bounds.contains(point) else {
            return false
        }

        guard cornerRadius > 0 else {
            return true
        }

        return NSBezierPath(
            roundedRect: bounds,
            xRadius: cornerRadius,
            yRadius: cornerRadius
        )
        .contains(point)
    }
}

@MainActor
public struct WebViewHost: NSViewRepresentable {
    @ObservedObject private var state: WebViewState
    @Environment(\.colorScheme) private var colorScheme

    private let activeTab: BrowserTab?
    private let activeProfile: BrowserProfile?
    private let isActive: Bool
    private let registry: BrowserWebViewRegistry
    private let dataStoreProvider: ProfileWebsiteDataStoreProvider
    private let securityPolicy: URLSecurityPolicy
    private let downloadSafetyPolicy: DownloadSafetyPolicy
    private let sitePermissionPolicy: SitePermissionPolicy
    private let mouseExclusionRegion: WebContentMouseExclusionRegion?
    private let onStateChange: @MainActor (TabID, String?, URL?, Bool, String?) -> Void
    private let onFaviconChange: @MainActor (TabID, URL?) -> Void
    private let onSecurityMessage: @MainActor (TabID, String) -> Void
    private let onURLConfirmationRequired: @MainActor (TabID, URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void
    private let onDownloadConfirmationRequired: @MainActor (TabID, DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void
    private let onDownloadStarted: @MainActor (TabID, DownloadConfirmationRequest, URL, @escaping @MainActor () -> Void) -> Void
    private let onDownloadProgress: @MainActor (TabID, UUID, Double?) -> Void
    private let onDownloadFinished: @MainActor (TabID, UUID, URL?, Bool) -> Void
    private let onDownloadFailed: @MainActor (TabID, UUID, String) -> Void
    private let onSitePermissionRequest: @MainActor (TabID, ProfileID, SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation
    private let onSnapshotCaptured: @MainActor (TabID, NSImage) -> Void
    private let onWebViewActivated: @MainActor (TabID) -> Void

    public init(
        state: WebViewState,
        activeTab: BrowserTab?,
        activeProfile: BrowserProfile?,
        isActive: Bool = true,
        registry: BrowserWebViewRegistry,
        dataStoreProvider: ProfileWebsiteDataStoreProvider,
        securityPolicy: URLSecurityPolicy = URLSecurityPolicy(),
        downloadSafetyPolicy: DownloadSafetyPolicy = DownloadSafetyPolicy(),
        sitePermissionPolicy: SitePermissionPolicy = SitePermissionPolicy(),
        mouseExclusionRegion: WebContentMouseExclusionRegion? = nil,
        onStateChange: @escaping @MainActor (TabID, String?, URL?, Bool, String?) -> Void,
        onFaviconChange: @escaping @MainActor (TabID, URL?) -> Void = { _, _ in },
        onSecurityMessage: @escaping @MainActor (TabID, String) -> Void = { _, _ in },
        onURLConfirmationRequired: @escaping @MainActor (TabID, URLConfirmationRequest.Kind, URL, URLConfirmationSourceContext) -> Void = { _, _, _, _ in },
        onDownloadConfirmationRequired: @escaping @MainActor (TabID, DownloadConfirmationRequest, @escaping @MainActor (URL?) -> Void) -> Void = { _, _, completion in completion(nil) },
        onDownloadStarted: @escaping @MainActor (TabID, DownloadConfirmationRequest, URL, @escaping @MainActor () -> Void) -> Void = { _, _, _, _ in },
        onDownloadProgress: @escaping @MainActor (TabID, UUID, Double?) -> Void = { _, _, _ in },
        onDownloadFinished: @escaping @MainActor (TabID, UUID, URL?, Bool) -> Void = { _, _, _, _ in },
        onDownloadFailed: @escaping @MainActor (TabID, UUID, String) -> Void = { _, _, _ in },
        onSitePermissionRequest: @escaping @MainActor (TabID, ProfileID, SitePermissionKind, SitePermissionOrigin?) -> SitePermissionPolicy.Evaluation = { _, _, _, _ in
            .deny(reason: "Site permission request was blocked because no permission handler is installed.")
        },
        onSnapshotCaptured: @escaping @MainActor (TabID, NSImage) -> Void = { _, _ in },
        onWebViewActivated: @escaping @MainActor (TabID) -> Void = { _ in }
    ) {
        self.state = state
        self.activeTab = activeTab
        self.activeProfile = activeProfile
        self.isActive = isActive
        self.registry = registry
        self.dataStoreProvider = dataStoreProvider
        self.securityPolicy = securityPolicy
        self.downloadSafetyPolicy = downloadSafetyPolicy
        self.sitePermissionPolicy = sitePermissionPolicy
        self.mouseExclusionRegion = mouseExclusionRegion
        self.onStateChange = onStateChange
        self.onFaviconChange = onFaviconChange
        self.onSecurityMessage = onSecurityMessage
        self.onURLConfirmationRequired = onURLConfirmationRequired
        self.onDownloadConfirmationRequired = onDownloadConfirmationRequired
        self.onDownloadStarted = onDownloadStarted
        self.onDownloadProgress = onDownloadProgress
        self.onDownloadFinished = onDownloadFinished
        self.onDownloadFailed = onDownloadFailed
        self.onSitePermissionRequest = onSitePermissionRequest
        self.onSnapshotCaptured = onSnapshotCaptured
        self.onWebViewActivated = onWebViewActivated
    }

    public func makeNSView(context: Context) -> NSView {
        BrowserWebViewContainerView()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            tabID: activeTab?.id ?? UUID(),
            state: state,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            callbacks: BrowserWebViewCallbacks(
                onStateChange: { _, _, _, _ in },
                onFaviconChange: { _ in },
                onSecurityMessage: { _ in },
                onURLConfirmationRequired: { _, _, _ in },
                onDownloadConfirmationRequired: { _, completion in completion(nil) },
                onDownloadStarted: { _, _, _ in },
                onDownloadProgress: { _, _ in },
                onDownloadFinished: { _, _, _ in },
                onDownloadFailed: { _, _ in },
                onSitePermissionRequest: { _, _ in
                    .deny(reason: "Site permission request was blocked because no active tab is attached.")
                },
                onSnapshot: { _ in }
            ),
            requestedURL: activeTab?.url,
            pendingHTTPFallbackURL: activeTab?.restorationMetadata.pendingHTTPFallbackURL,
            isActive: false
        )
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let container = nsView as? BrowserWebViewContainerView else {
            return
        }
        container.mouseExclusionRegion = mouseExclusionRegion
        registry.applyColorScheme(colorScheme)

        guard let tab = activeTab,
              let profile = activeProfile,
              tab.content.isWeb,
              tab.url != nil else {
            container.suspendActiveWebView()
            registry.markActive(nil)
            return
        }

        let callbacks = BrowserWebViewCallbacks(
            onStateChange: { title, url, isLoading, securityMessage in
                onStateChange(tab.id, title, url, isLoading, securityMessage)
            },
            onFaviconChange: { faviconURL in
                onFaviconChange(tab.id, faviconURL)
            },
            onSecurityMessage: { message in
                onSecurityMessage(tab.id, message)
            },
            onURLConfirmationRequired: { kind, url, sourceContext in
                onURLConfirmationRequired(tab.id, kind, url, sourceContext)
            },
            onDownloadConfirmationRequired: { request, completion in
                onDownloadConfirmationRequired(tab.id, request, completion)
            },
            onDownloadStarted: { request, destinationURL, cancel in
                onDownloadStarted(tab.id, request, destinationURL, cancel)
            },
            onDownloadProgress: { downloadID, progress in
                onDownloadProgress(tab.id, downloadID, progress)
            },
            onDownloadFinished: { downloadID, destinationURL, quarantineApplied in
                onDownloadFinished(tab.id, downloadID, destinationURL, quarantineApplied)
            },
            onDownloadFailed: { downloadID, message in
                onDownloadFailed(tab.id, downloadID, message)
            },
            onSitePermissionRequest: { kind, origin in
                onSitePermissionRequest(tab.id, profile.id, kind, origin)
            },
            onSnapshot: { image in
                onSnapshotCaptured(tab.id, image)
            }
        )
        let session = registry.session(
            for: tab,
            profile: profile,
            state: state,
            dataStoreProvider: dataStoreProvider,
            securityPolicy: securityPolicy,
            downloadSafetyPolicy: downloadSafetyPolicy,
            sitePermissionPolicy: sitePermissionPolicy,
            callbacks: callbacks,
            isActive: isActive
        )

        BrowserWebContentAppearance.apply(colorScheme, to: session.webView)
        let didActivateWebView = container.attach(session.webView)
        session.coordinator.applyPendingState(to: session.webView)
        if didActivateWebView && isActive {
            session.coordinator.publishCurrentState(from: session.webView)
            onWebViewActivated(tab.id)
        }
    }

    public static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        (nsView as? BrowserWebViewContainerView)?.detachCurrentWebView()
    }

    @MainActor
    public final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler, BrowserContextMenuDownloadHandling {
        fileprivate let tabID: TabID
        fileprivate var state: WebViewState
        fileprivate var securityPolicy: URLSecurityPolicy
        fileprivate var downloadSafetyPolicy: DownloadSafetyPolicy
        fileprivate var callbacks: BrowserWebViewCallbacks
        fileprivate var requestedURL: URL?
        fileprivate var pendingHTTPFallbackURL: URL?
        fileprivate var isActive: Bool
        fileprivate var lastHandledCommandID: UUID?
        fileprivate var lastLoadedRequestedURL: URL?
        private var pendingHTTPFallbacksByUpgradeURL: [URL: URL] = [:]
        private var httpFallbacksInFlight: Set<URL> = []
        private var downloadSourceMetadata: [ObjectIdentifier: DownloadSourceMetadata] = [:]
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        private var downloadRequests: [ObjectIdentifier: DownloadConfirmationRequest] = [:]
        private var downloadProgressObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private var contextMenuDownloadTarget = BrowserContextMenuDownloadTarget()
        private weak var contextMenuWebView: WKWebView?
        private var pendingSnapshotCaptureTask: Task<Void, Never>?

        init(
            tabID: TabID,
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            downloadSafetyPolicy: DownloadSafetyPolicy,
            callbacks: BrowserWebViewCallbacks,
            requestedURL: URL?,
            pendingHTTPFallbackURL: URL?,
            isActive: Bool
        ) {
            self.tabID = tabID
            self.state = state
            self.securityPolicy = securityPolicy
            self.downloadSafetyPolicy = downloadSafetyPolicy
            self.callbacks = callbacks
            self.requestedURL = requestedURL
            self.pendingHTTPFallbackURL = pendingHTTPFallbackURL
            self.isActive = isActive
        }

        deinit {
            pendingSnapshotCaptureTask?.cancel()
        }

        fileprivate func update(
            state: WebViewState,
            securityPolicy: URLSecurityPolicy,
            downloadSafetyPolicy: DownloadSafetyPolicy,
            callbacks: BrowserWebViewCallbacks,
            requestedURL: URL?,
            pendingHTTPFallbackURL: URL?,
            isActive: Bool
        ) {
            self.state = state
            self.securityPolicy = securityPolicy
            self.downloadSafetyPolicy = downloadSafetyPolicy
            self.callbacks = callbacks
            self.requestedURL = requestedURL
            self.pendingHTTPFallbackURL = pendingHTTPFallbackURL
            self.isActive = isActive
        }

        fileprivate func applyPendingState(to webView: WKWebView) {
            if let commandRequest = state.pendingCommand,
               commandRequest.targetTabID == nil || commandRequest.targetTabID == tabID,
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
                Task { @MainActor in
                    self.state.clearPendingCommand(id: commandRequest.id)
                }
            }

            guard let requestedURL else {
                return
            }

            loadRequestedURLIfNeeded(requestedURL, in: webView)
        }

        fileprivate func publishCurrentState(from webView: WKWebView) {
            publish(webView, isLoading: webView.isLoading)
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            cancelPendingSnapshotCapture()
            publish(webView, isLoading: true)
        }

        public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            cancelPendingSnapshotCapture()
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

            if navigationAction.shouldPerformDownload {
                decisionHandler(shouldAllowWebDownload(from: url) ? .download : .cancel)
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
                decisionHandler(.allow)
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
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
                return
            }

            decisionHandler(shouldAllowWebDownload(from: navigationResponse.response.url) ? .download : .cancel)
        }

        public func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            prepare(
                download,
                sourceURL: downloadSourceURL(candidateURL: navigationAction.request.url, webView: webView)
            )
        }

        public func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            prepare(
                download,
                sourceURL: downloadSourceURL(candidateURL: navigationResponse.response.url, webView: webView)
            )
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

            webViewLogger.info(
                "download destination requested suggestedFilenameEmpty=\(suggestedFilename.isEmpty, privacy: .public) risk=\(String(describing: request.risk), privacy: .public)"
            )
            publishSecurityMessage(request.pendingMessage)
            callbacks.onDownloadConfirmationRequired(request) { [weak self] destinationURL in
                guard let self else {
                    completionHandler(nil)
                    return
                }

                if let destinationURL {
                    webViewLogger.info("download destination approved")
                    self.downloadDestinations[identifier] = destinationURL
                    self.downloadSourceMetadata[identifier] = sourceMetadata
                    self.downloadRequests[identifier] = request
                    self.observeProgress(for: download, request: request)
                    self.callbacks.onDownloadStarted(request, destinationURL) { [weak download] in
                        download?.cancel { _ in }
                    }
                } else {
                    webViewLogger.info("download destination canceled")
                    self.cleanup(download)
                }

                completionHandler(destinationURL)
            }
        }

        public func downloadDidFinish(_ download: WKDownload) {
            let identifier = ObjectIdentifier(download)
            let destinationURL = downloadDestinations[identifier]
            let sourceMetadata = downloadSourceMetadata[identifier] ?? .currentPage
            let request = downloadRequests[identifier]

            if let destinationURL {
                let didApplyQuarantine = downloadSafetyPolicy.applyQuarantineMetadata(
                    to: destinationURL,
                    sourceMetadata: sourceMetadata
                )
                webViewLogger.info("download finished quarantine=\(didApplyQuarantine, privacy: .public)")
                if let request {
                    callbacks.onDownloadFinished(request.id, destinationURL, didApplyQuarantine)
                }
                publishSecurityMessage(
                    didApplyQuarantine
                        ? "Download finished: \(destinationURL.lastPathComponent)"
                        : "Download finished, but quarantine metadata could not be applied."
                )
            } else {
                if let request {
                    callbacks.onDownloadFinished(request.id, destinationURL, true)
                }
                publishSecurityMessage("Download finished.")
            }

            cleanup(download)
        }

        public func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            if let request = downloadRequests[ObjectIdentifier(download)] {
                callbacks.onDownloadFailed(request.id, "Download failed.")
            }
            webViewLogger.info("download failed")
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

            switch securityPolicy.decision(forWebDownloadURL: url) {
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
            completionHandler(.performDefaultHandling, nil)
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

        public func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard isActive,
                  message.name == BrowserContextMenuScript.messageHandlerName else {
                return
            }

            let target = BrowserContextMenuDownloadTarget(messageBody: message.body)
            contextMenuDownloadTarget = target
            webViewLogger.info(
                "context-menu script target image=\(target.imageURL != nil, privacy: .public) link=\(target.linkURL != nil, privacy: .public) point=\(target.clientPoint != nil, privacy: .public)"
            )
        }

        func prepareContextMenu(for event: NSEvent, in webView: WKWebView) {
            contextMenuWebView = webView
            let viewPoint = webView.convert(event.locationInWindow, from: nil)
            contextMenuDownloadTarget.clientPoint = CGPoint(
                x: viewPoint.x,
                y: max(0, webView.bounds.height - viewPoint.y)
            )
            webViewLogger.info(
                "context-menu prepared point x=\(Double(viewPoint.x), privacy: .public) y=\(Double(viewPoint.y), privacy: .public)"
            )
        }

        func configureContextMenu(_ menu: NSMenu?, in webView: WKWebView) {
            contextMenuWebView = webView
            guard let menu else {
                return
            }

            installDownloadContextMenuItems(in: menu)
        }

        func performContextMenuDownload(_ kind: BrowserContextMenuDownloadKind, in webView: WKWebView) {
            contextMenuWebView = webView
            startContextMenuDownload(kind)
        }

        private func installDownloadContextMenuItems(in menu: NSMenu) {
            let removedItems = removeDownloadContextMenuItems(from: menu)
            let removedKinds = Set(removedItems.kinds)
            webViewLogger.info(
                "context-menu download install removed=\(removedKinds.debugDescription, privacy: .public) image=\(self.contextMenuDownloadTarget.imageURL != nil, privacy: .public) link=\(self.contextMenuDownloadTarget.linkURL != nil, privacy: .public)"
            )
            guard contextMenuDownloadTarget.imageURL != nil
                    || contextMenuDownloadTarget.linkURL != nil
                    || !removedKinds.isEmpty else {
                webViewLogger.info("context-menu download install skipped")
                return
            }

            let insertionIndex = removedItems.firstIndex ?? 0
            var replacementItems: [NSMenuItem] = []
            if contextMenuDownloadTarget.imageURL != nil || removedKinds.contains(.image) {
                replacementItems.append(downloadContextMenuItem(
                    title: "Download Image",
                    action: #selector(downloadContextMenuImage(_:))
                ))
            }
            if shouldInstallLinkedFileMenuItem(removedKinds: removedKinds) {
                replacementItems.append(downloadContextMenuItem(
                    title: "Download Linked File",
                    action: #selector(downloadContextMenuLinkedFile(_:))
                ))
            }

            guard !replacementItems.isEmpty else {
                webViewLogger.info("context-menu download replacement empty")
                return
            }

            let boundedIndex = min(insertionIndex, menu.items.count)
            for (offset, item) in replacementItems.enumerated() {
                menu.insertItem(item, at: boundedIndex + offset)
            }

            let separatorIndex = boundedIndex + replacementItems.count
            if separatorIndex < menu.items.count,
               !menu.items[separatorIndex].isSeparatorItem {
                menu.insertItem(.separator(), at: separatorIndex)
            }
            webViewLogger.info(
                "context-menu download replacement inserted count=\(replacementItems.count, privacy: .public) index=\(boundedIndex, privacy: .public)"
            )
        }

        private func shouldInstallLinkedFileMenuItem(removedKinds: Set<BrowserContextMenuDownloadKind>) -> Bool {
            if let linkURL = contextMenuDownloadTarget.linkURL {
                return linkURL != contextMenuDownloadTarget.imageURL
            }

            return removedKinds.contains(.linkedFile)
        }

        @discardableResult
        private func removeDownloadContextMenuItems(
            from menu: NSMenu
        ) -> (firstIndex: Int?, kinds: [BrowserContextMenuDownloadKind]) {
            var firstRemovedIndex: Int?
            var removedKinds: [BrowserContextMenuDownloadKind] = []
            for index in menu.items.indices.reversed() {
                let item = menu.items[index]
                if let submenu = item.submenu {
                    let submenuResult = removeDownloadContextMenuItems(from: submenu)
                    removedKinds.append(contentsOf: submenuResult.kinds)
                }
                if let kind = BrowserContextMenuDownloadKind.kind(for: item) {
                    firstRemovedIndex = index
                    removedKinds.append(kind)
                    menu.removeItem(at: index)
                }
            }
            return (firstRemovedIndex, removedKinds)
        }

        private func downloadContextMenuItem(title: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            return item
        }

        @objc private func downloadContextMenuImage(_ sender: NSMenuItem) {
            startContextMenuDownload(.image)
        }

        @objc private func downloadContextMenuLinkedFile(_ sender: NSMenuItem) {
            startContextMenuDownload(.linkedFile)
        }

        private func startContextMenuDownload(_ kind: BrowserContextMenuDownloadKind) {
            guard isActive else {
                webViewLogger.info("context-menu download action ignored inactive")
                return
            }

            guard let webView = contextMenuWebView else {
                webViewLogger.info("context-menu download action missing webView kind=\(String(describing: kind), privacy: .public)")
                publishSecurityMessage("Download could not start because the web view is unavailable.")
                return
            }

            webViewLogger.info(
                "context-menu download action kind=\(String(describing: kind), privacy: .public) cachedImage=\(self.contextMenuDownloadTarget.imageURL != nil, privacy: .public) cachedLink=\(self.contextMenuDownloadTarget.linkURL != nil, privacy: .public) point=\(self.contextMenuDownloadTarget.clientPoint != nil, privacy: .public)"
            )
            resolveContextMenuDownloadURL(kind, in: webView) { [weak self, weak webView] targetURL in
                guard let self,
                      let webView else {
                    return
                }

                guard let targetURL else {
                    webViewLogger.info("context-menu download resolved nil kind=\(String(describing: kind), privacy: .public)")
                    self.publishSecurityMessage("No downloadable URL was found for this menu item.")
                    return
                }

                self.startDownload(targetURL, from: webView)
            }
        }

        private func resolveContextMenuDownloadURL(
            _ kind: BrowserContextMenuDownloadKind,
            in webView: WKWebView,
            completion: @escaping @MainActor (URL?) -> Void
        ) {
            let cachedTarget = contextMenuDownloadTarget
            let cachedURL = downloadURL(for: kind, in: cachedTarget)
            guard let point = cachedTarget.clientPoint,
                  point.x.isFinite,
                  point.y.isFinite else {
                webViewLogger.info(
                    "context-menu resolve using cached URL kind=\(String(describing: kind), privacy: .public) hasURL=\(cachedURL != nil, privacy: .public)"
                )
                completion(cachedURL)
                return
            }

            webViewLogger.info(
                "context-menu resolve evaluating point kind=\(String(describing: kind), privacy: .public) cachedURL=\(cachedURL != nil, privacy: .public)"
            )
            let script = """
            (() => {
                const resolver = window.__meridianContextTargetForPoint;
                return resolver ? resolver(\(Double(point.x)), \(Double(point.y))) : null;
            })()
            """
            webView.evaluateJavaScript(
                script,
                in: nil,
                in: BrowserContextMenuScript.contentWorld
            ) { [weak self] result in
                guard let self,
                      let body = try? result.get() else {
                    completion(cachedURL)
                    return
                }

                let resolvedTarget = BrowserContextMenuDownloadTarget(messageBody: body)
                webViewLogger.info(
                    "context-menu resolve result image=\(resolvedTarget.imageURL != nil, privacy: .public) link=\(resolvedTarget.linkURL != nil, privacy: .public)"
                )
                if resolvedTarget.imageURL != nil || resolvedTarget.linkURL != nil {
                    self.contextMenuDownloadTarget = resolvedTarget
                    completion(self.downloadURL(for: kind, in: resolvedTarget) ?? cachedURL)
                } else {
                    completion(cachedURL)
                }
            }
        }

        private func downloadURL(
            for kind: BrowserContextMenuDownloadKind,
            in target: BrowserContextMenuDownloadTarget
        ) -> URL? {
            switch kind {
            case .image:
                return target.imageURL
            case .linkedFile:
                return target.linkURL
            }
        }

        private func startDownload(_ targetURL: URL, from webView: WKWebView) {
            switch securityPolicy.decision(forWebDownloadURL: targetURL) {
            case .allowInWebView:
                webViewLogger.info(
                    "context-menu startDownload allowed scheme=\(targetURL.scheme ?? "none", privacy: .public)"
                )
                publishSecurityMessage(
                    securityPolicy.securityMessage(forAllowedWebURL: targetURL)
                        ?? "Preparing download..."
                )
                webView.startDownload(using: URLRequest(url: targetURL)) { [weak self] download in
                    guard let self else {
                        return
                    }
                    self.prepare(
                        download,
                        sourceURL: self.downloadSourceURL(candidateURL: targetURL, webView: webView)
                    )
                }
            case .requireExternalApplicationConfirmation, .requireLocalFileConfirmation:
                webViewLogger.info("context-menu startDownload blocked external-or-file")
                publishSecurityMessage("Download was blocked because it left the web download flow.")
            case .block(let reason):
                webViewLogger.info("context-menu startDownload blocked reason=\(reason, privacy: .public)")
                publishSecurityMessage(reason)
            }
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
            webViewLogger.info("download prepared source=\(sourceURL != nil, privacy: .public)")
        }

        private func shouldAllowWebDownload(from url: URL?) -> Bool {
            guard isActive else {
                return false
            }

            guard let url else {
                publishSecurityMessage("Download was blocked because it did not include a URL.")
                return false
            }

            switch securityPolicy.decision(forWebDownloadURL: url) {
            case .allowInWebView:
                publishSecurityMessage(securityPolicy.securityMessage(forAllowedWebURL: url))
                return true
            case .requireExternalApplicationConfirmation, .requireLocalFileConfirmation:
                publishSecurityMessage("Download was blocked because it left the web download flow.")
                return false
            case .block(let reason):
                publishSecurityMessage(reason)
                return false
            }
        }

        private func downloadSourceURL(candidateURL: URL?, webView: WKWebView) -> URL? {
            guard let candidateURL else {
                return webView.url
            }

            switch candidateURL.scheme?.lowercased() {
            case "blob", "data":
                return webView.url ?? candidateURL
            default:
                return candidateURL
            }
        }

        private func cleanup(_ download: WKDownload) {
            let identifier = ObjectIdentifier(download)
            downloadProgressObservations.removeValue(forKey: identifier)
            downloadSourceMetadata.removeValue(forKey: identifier)
            downloadDestinations.removeValue(forKey: identifier)
            downloadRequests.removeValue(forKey: identifier)
        }

        private func observeProgress(
            for download: WKDownload,
            request: DownloadConfirmationRequest
        ) {
            let identifier = ObjectIdentifier(download)
            downloadProgressObservations[identifier] = download.progress.observe(
                \.fractionCompleted,
                 options: [.initial, .new]
            ) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    self?.callbacks.onDownloadProgress(
                        request.id,
                        BrowserDownload.normalizedProgress(progress.fractionCompleted)
                    )
                }
            }
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
            requestedURL = upgradedURL
            pendingHTTPFallbackURL = originalURL
            if isActive,
               state.requestedURL != upgradedURL || state.pendingHTTPFallbackURL != originalURL {
                state.request(upgradedURL, pendingHTTPFallbackURL: originalURL)
            }
            lastLoadedRequestedURL = upgradedURL
            webView.load(URLRequest(url: upgradedURL))
        }

        private func beginHTTPFallback(to fallbackURL: URL, in webView: WKWebView) {
            httpFallbacksInFlight.insert(fallbackURL)
            requestedURL = fallbackURL
            pendingHTTPFallbackURL = nil
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
            if pendingHTTPFallbackURL == fallbackURL {
                pendingHTTPFallbackURL = nil
            }
            if isActive, state.pendingHTTPFallbackURL == fallbackURL {
                state.pendingHTTPFallbackURL = nil
            }
        }

        private func httpFallbackURL(for error: Error) -> URL? {
            let failedURL = failedNavigationURL(from: error) ?? lastLoadedRequestedURL ?? requestedURL

            if let failedURL,
               let fallbackURL = pendingHTTPFallbacksByUpgradeURL.removeValue(forKey: failedURL) {
                return fallbackURL
            }

            guard let failedURL,
                  let fallbackURL = pendingHTTPFallbackURL,
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

            if !isLoading {
                discoverFavicon(in: webView, pageURL: url)
                scheduleSnapshotCapture(from: webView, url: url)
            }
        }

        private func discoverFavicon(in webView: WKWebView, pageURL: URL?) {
            guard let pageURL,
                  let scheme = pageURL.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                callbacks.onFaviconChange(nil)
                return
            }

            webView.evaluateJavaScript(
                BrowserFaviconScript.source,
                in: nil,
                in: BrowserContextMenuScript.contentWorld
            ) { [weak self] result in
                guard let self else {
                    return
                }

                let faviconURL = (try? result.get()).flatMap(BrowserFaviconScript.url(from:))
                self.callbacks.onFaviconChange(faviconURL)
            }
        }

        private func scheduleSnapshotCapture(from webView: WKWebView, url: URL?) {
            cancelPendingSnapshotCapture()
            guard isActive,
                  !webView.bounds.isEmpty else {
                return
            }

            pendingSnapshotCaptureTask = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled,
                      let self,
                      let webView,
                      self.isActive,
                      !webView.isLoading,
                      webView.url == url else {
                    return
                }

                self.captureSnapshot(from: webView)
            }
        }

        private func cancelPendingSnapshotCapture() {
            pendingSnapshotCaptureTask?.cancel()
            pendingSnapshotCaptureTask = nil
        }

        private func captureSnapshot(from webView: WKWebView) {
            guard isActive,
                  !webView.bounds.isEmpty else {
                return
            }

            pendingSnapshotCaptureTask = nil

            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                guard let image else {
                    return
                }

                Task { @MainActor in
                    guard let self,
                          self.isActive else {
                        return
                    }

                    self.callbacks.onSnapshot(image)
                }
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
            return "Navigation failed. Check Bare Browser logs for details."
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
            return "Navigation failed. Check Bare Browser logs for details."
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
