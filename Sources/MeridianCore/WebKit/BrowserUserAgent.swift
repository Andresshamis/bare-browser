import WebKit

enum BrowserUserAgent {
    static let desktopSafariCompatible =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.4 Safari/605.1.15"

    @MainActor
    static func applyDesktopSafariCompatibility(to webView: WKWebView) {
        webView.customUserAgent = desktopSafariCompatible
    }
}
