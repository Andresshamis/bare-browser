import Foundation
@testable import MeridianCore
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
