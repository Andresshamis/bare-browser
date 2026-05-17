import Foundation
@testable import MeridianCore
import WebKit
import XCTest

@MainActor
final class WebViewHostHTTPFallbackTests: XCTestCase {
    func testCancelledHTTPSUpgradeClearsFallbackWithoutLoadingHTTP() {
        let httpURL = URL(string: "http://example.com/path")!
        let httpsURL = URL(string: "https://example.com/path")!
        let state = WebViewState(
            requestedURL: httpsURL,
            pendingHTTPFallbackURL: httpURL
        )
        var fallbackLoadEvents: [URL] = []
        let coordinator = WebViewHost.Coordinator(
            tabID: UUID(),
            state: state,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            callbacks: BrowserWebViewCallbacks(
                onStateChange: { _, url, isLoading, _ in
                    if isLoading, let url {
                        fallbackLoadEvents.append(url)
                    }
                },
                onSecurityMessage: { _ in },
                onURLConfirmationRequired: { _, _, _ in },
                onDownloadConfirmationRequired: { _, completion in completion(nil) },
                onSitePermissionRequest: { _, _ in .deny(reason: "Test denies site permission requests.") }
            ),
            requestedURL: httpsURL,
            pendingHTTPFallbackURL: httpURL,
            isActive: true
        )
        let webView = WKWebView()
        let error = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: [NSURLErrorFailingURLErrorKey: httpsURL]
        )

        coordinator.webView(webView, didFailProvisionalNavigation: nil, withError: error)

        XCTAssertEqual(state.requestedURL, httpsURL)
        XCTAssertNil(state.pendingHTTPFallbackURL)
        XCTAssertTrue(fallbackLoadEvents.isEmpty)
    }
}
