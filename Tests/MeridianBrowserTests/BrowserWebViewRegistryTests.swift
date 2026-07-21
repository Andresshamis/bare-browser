import Foundation
@testable import MeridianCore
import SwiftUI
import WebKit
import XCTest

@MainActor
final class BrowserWebViewRegistryTests: XCTestCase {
    func testContainerKeepsOnlyActiveWebViewMountedDuringSwitch() {
        let container = BrowserWebViewContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let firstWebView = WKWebView()
        let secondWebView = WKWebView()

        container.attach(firstWebView)
        container.attach(secondWebView)

        XCTAssertNil(firstWebView.superview)
        XCTAssertTrue(secondWebView.superview === container)
        XCTAssertEqual(secondWebView.alphaValue, 1)

        container.deactivateActiveWebView()

        XCTAssertNil(firstWebView.superview)
        XCTAssertNil(secondWebView.superview)
    }

    func testContainerSuspendsActiveWebViewWithoutUnmountingIt() {
        let container = BrowserWebViewContainerView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let webView = WKWebView()

        container.attach(webView)
        container.suspendActiveWebView()

        XCTAssertTrue(webView.superview === container)
        XCTAssertEqual(webView.alphaValue, 0)

        XCTAssertTrue(container.attach(webView))
        XCTAssertTrue(webView.superview === container)
        XCTAssertEqual(webView.alphaValue, 1)
    }

    func testRegistryReusesSessionForSameTab() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 8)
        let tab = fixture.tab(title: "Example")
        let state = WebViewState()

        let firstSession = registry.session(
            for: tab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        let secondSession = registry.session(
            for: tab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        XCTAssertTrue(firstSession === secondSession)
        XCTAssertTrue(firstSession.webView === secondSession.webView)
        XCTAssertEqual(registry.liveSessionCount, 1)
    }

    func testRegistryEvictsClosedTabsImmediately() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 8)
        let firstTab = fixture.tab(title: "First")
        let secondTab = fixture.tab(title: "Second")
        let state = WebViewState()

        _ = registry.session(
            for: firstTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        _ = registry.session(
            for: secondTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        registry.prune(keeping: [secondTab.id], activeTabID: secondTab.id)

        XCTAssertFalse(registry.containsSession(for: firstTab.id))
        XCTAssertTrue(registry.containsSession(for: secondTab.id))
        XCTAssertEqual(registry.liveSessionCount, 1)
    }

    func testRegistryUsesLRUCapWithoutEvictingActiveTab() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 2)
        let firstTab = fixture.tab(title: "First")
        let secondTab = fixture.tab(title: "Second")
        let thirdTab = fixture.tab(title: "Third")
        let state = WebViewState()

        _ = registry.session(
            for: firstTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        _ = registry.session(
            for: secondTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        _ = registry.session(
            for: thirdTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        XCTAssertEqual(registry.liveSessionCount, 2)
        XCTAssertFalse(registry.containsSession(for: firstTab.id))
        XCTAssertTrue(registry.containsSession(for: secondTab.id))
        XCTAssertTrue(registry.containsSession(for: thirdTab.id))
    }

    func testRegistryInvalidatesSpecificTabs() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 8)
        let firstTab = fixture.tab(title: "First")
        let secondTab = fixture.tab(title: "Second")
        let state = WebViewState()

        _ = registry.session(
            for: firstTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        _ = registry.session(
            for: secondTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        registry.invalidate(tabIDs: [firstTab.id])

        XCTAssertFalse(registry.containsSession(for: firstTab.id))
        XCTAssertTrue(registry.containsSession(for: secondTab.id))
        XCTAssertEqual(registry.liveSessionCount, 1)
    }

    func testWebContentAppearanceMapsSystemColorSchemeToAppKitAppearance() {
        XCTAssertEqual(BrowserWebContentAppearance.appearanceName(for: .dark), .darkAqua)
        XCTAssertEqual(BrowserWebContentAppearance.appearanceName(for: .light), .aqua)
        XCTAssertEqual(BrowserWebContentAppearance.underPageBackgroundColor(for: .dark), .black)
        XCTAssertEqual(BrowserWebContentAppearance.underPageBackgroundColor(for: .light), .white)
    }

    func testRegistryAppliesColorSchemeToCachedWebViews() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 8)
        let firstTab = fixture.tab(title: "First")
        let secondTab = fixture.tab(title: "Second")
        let state = WebViewState()

        let firstSession = registry.session(
            for: firstTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        let secondSession = registry.session(
            for: secondTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        registry.applyColorScheme(.dark)

        XCTAssertEqual(firstSession.webView.appearance?.name, .darkAqua)
        XCTAssertEqual(secondSession.webView.appearance?.name, .darkAqua)
        XCTAssertBlack(firstSession.webView.underPageBackgroundColor)
        XCTAssertBlack(secondSession.webView.underPageBackgroundColor)
    }

    func testWebContentAppearanceAdvertisesDarkColorSchemeToPageCSS() {
        let webView = WKWebView()
        let navigationObserver = WebViewNavigationObserver()
        let pageLoaded = expectation(description: "HTML page loaded")
        navigationObserver.onFinish = {
            pageLoaded.fulfill()
        }
        webView.navigationDelegate = navigationObserver

        BrowserWebContentAppearance.apply(.dark, to: webView)
        webView.loadHTMLString("<!doctype html><meta name=\"color-scheme\" content=\"light dark\">", baseURL: nil)
        wait(for: [pageLoaded], timeout: 3)

        let mediaQueryEvaluated = expectation(description: "CSS color scheme evaluated")
        webView.evaluateJavaScript("matchMedia('(prefers-color-scheme: dark)').matches") { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result as? Bool, true)
            mediaQueryEvaluated.fulfill()
        }

        wait(for: [mediaQueryEvaluated], timeout: 3)
    }

    func testRegistryRecreatesSessionWhenTabProfileChanges() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 8)
        let tab = fixture.tab(title: "Example")
        let workProfile = BrowserProfile(name: "Work")
        var movedTab = tab
        movedTab.profileID = workProfile.id
        let state = WebViewState()

        let firstSession = registry.session(
            for: tab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        let secondSession = registry.session(
            for: movedTab,
            profile: workProfile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        XCTAssertFalse(firstSession === secondSession)
        XCTAssertFalse(firstSession.webView === secondSession.webView)
        XCTAssertEqual(secondSession.profileID, workProfile.id)
        XCTAssertEqual(registry.liveSessionCount, 1)
    }

    func testRegistryRecreatesSessionWhenParentSpaceChanges() {
        let fixture = RegistryFixture()
        let registry = BrowserWebViewRegistry(capacity: 8)
        let tab = fixture.tab(title: "Example")
        var movedTab = tab
        movedTab.parentSpaceID = UUID()
        let state = WebViewState()

        let firstSession = registry.session(
            for: tab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )
        let secondSession = registry.session(
            for: movedTab,
            profile: fixture.profile,
            state: state,
            dataStoreProvider: fixture.dataStoreProvider,
            securityPolicy: URLSecurityPolicy(),
            downloadSafetyPolicy: DownloadSafetyPolicy(),
            sitePermissionPolicy: SitePermissionPolicy(),
            callbacks: fixture.callbacks()
        )

        XCTAssertFalse(firstSession === secondSession)
        XCTAssertNotEqual(firstSession.identity, secondSession.identity)
        XCTAssertEqual(secondSession.identity.spaceID, movedTab.parentSpaceID)
    }

    func testPrivateProfileTabsShareOneStoreUntilProfileIsReleased() {
        let provider = ProfileWebsiteDataStoreProvider()
        let profile = BrowserProfile.privateBrowsing()

        let first = provider.websiteDataStore(for: profile)
        let second = provider.websiteDataStore(for: profile)
        XCTAssertTrue(first === second)

        provider.releaseEphemeralWebsiteDataStore(for: profile.id)
        let replacement = provider.websiteDataStore(for: profile)
        XCTAssertFalse(first === replacement)
    }

}

private func XCTAssertBlack(
    _ color: NSColor?,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let color = color?.usingColorSpace(.sRGB) else {
        XCTFail("Expected a color", file: file, line: line)
        return
    }

    XCTAssertEqual(color.redComponent, 0, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(color.greenComponent, 0, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(color.blueComponent, 0, accuracy: 0.001, file: file, line: line)
    XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.001, file: file, line: line)
}

private final class WebViewNavigationObserver: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
}

@MainActor
private struct RegistryFixture {
    let profile = BrowserProfile.privateBrowsing()
    let spaceID = UUID()
    let dataStoreProvider = ProfileWebsiteDataStoreProvider()

    func tab(title: String, url: URL? = nil) -> BrowserTab {
        BrowserTab(
            title: title,
            url: url,
            parentSpaceID: spaceID,
            profileID: profile.id
        )
    }

    func callbacks() -> BrowserWebViewCallbacks {
        BrowserWebViewCallbacks(
            onStateChange: { _, _, _, _ in },
            onSecurityMessage: { _ in },
            onURLConfirmationRequired: { _, _, _ in },
            onDownloadConfirmationRequired: { _, completion in completion(nil) },
            onSitePermissionRequest: { _, _ in
                .deny(reason: "Test denies site permission requests.")
            }
        )
    }
}
