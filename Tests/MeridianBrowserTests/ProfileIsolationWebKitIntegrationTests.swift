import Foundation
import Network
@testable import MeridianCore
import WebKit
import XCTest

@MainActor
final class ProfileIsolationWebKitIntegrationTests: XCTestCase {
    func testPersistentProfilesIsolateWebPlatformStorageAndRetainItAcrossWebViews() async throws {
        let server = try LoopbackProfileFixtureServer()
        let pageURL = try await server.start()
        defer { server.stop() }

        let provider = ProfileWebsiteDataStoreProvider()
        let university = BrowserProfile(name: "University")
        let personal = BrowserProfile(name: "Personal")
        do {
            let universityWebView = makeWebView(profile: university, provider: provider)
            try await load(pageURL, in: universityWebView)
            try await writeMarker("university", in: universityWebView)

            let recreatedUniversityWebView = makeWebView(profile: university, provider: provider)
            try await load(pageURL, in: recreatedUniversityWebView)
            let retained = try await readMarker(in: recreatedUniversityWebView)
            XCTAssertEqual(retained, .present("university"))

            let personalWebView = makeWebView(profile: personal, provider: provider)
            try await load(pageURL, in: personalWebView)
            let isolated = try await readMarker(in: personalWebView)
            XCTAssertEqual(isolated, .absent)
        } catch {
            await removePersistentStores([university, personal], provider: provider)
            throw error
        }

        await removePersistentStores([university, personal], provider: provider)
    }

    func testPrivateProfileSharesStorageUntilItsInMemoryStoreIsReleased() async throws {
        let server = try LoopbackProfileFixtureServer()
        let pageURL = try await server.start()
        defer { server.stop() }

        let provider = ProfileWebsiteDataStoreProvider()
        let privateProfile = BrowserProfile.privateBrowsing()
        let firstWebView = makeWebView(profile: privateProfile, provider: provider)
        try await load(pageURL, in: firstWebView)
        try await writeMarker("private-session", in: firstWebView)

        let secondWebView = makeWebView(profile: privateProfile, provider: provider)
        try await load(pageURL, in: secondWebView)
        let sharedState = try await readMarker(in: secondWebView)
        XCTAssertEqual(sharedState, .present("private-session"))

        provider.releaseEphemeralWebsiteDataStore(for: privateProfile.id)
        let replacementWebView = makeWebView(profile: privateProfile, provider: provider)
        try await load(pageURL, in: replacementWebView)
        let replacementState = try await readMarker(in: replacementWebView)
        XCTAssertEqual(replacementState, .absent)
    }

    func testReassigningSpaceRecreatesSessionAgainstDestinationProfileStore() async throws {
        let server = try LoopbackProfileFixtureServer()
        let pageURL = try await server.start()
        defer { server.stop() }

        let provider = ProfileWebsiteDataStoreProvider()
        let personal = BrowserProfile(name: "Personal")
        var personalSpace = BrowserSpace(name: "Personal", profileID: personal.id)
        let personalTab = BrowserTab(
            title: "Fixture",
            url: pageURL,
            parentSpaceID: personalSpace.id,
            profileID: personal.id
        )
        personalSpace.regularTabIDs = [personalTab.id]
        personalSpace.selectedTabID = personalTab.id
        let browserStore = BrowserStore(snapshot: BrowserSessionSnapshot(
            profiles: [personal],
            spaces: [personalSpace],
            folders: [],
            tabs: [personalTab],
            selectedSpaceID: personalSpace.id,
            selectedTabID: personalTab.id
        ))
        let university = browserStore.createPersistentProfile(name: "University")
        do {
            let personalSeeder = makeWebView(profile: personal, provider: provider)
            try await load(pageURL, in: personalSeeder)
            try await writeMarker("personal", in: personalSeeder)
            let universitySeeder = makeWebView(profile: university, provider: provider)
            try await load(pageURL, in: universitySeeder)
            try await writeMarker("university", in: universitySeeder)

            let spaceID = try XCTUnwrap(browserStore.selectedSpaceID)
            let tab = try XCTUnwrap(browserStore.activeTab)
            let registry = BrowserWebViewRegistry()
            let state = WebViewState()
            let firstSession = registry.session(
                for: tab,
                profile: personal,
                state: state,
                dataStoreProvider: provider,
                securityPolicy: URLSecurityPolicy(),
                downloadSafetyPolicy: DownloadSafetyPolicy(),
                sitePermissionPolicy: SitePermissionPolicy(),
                callbacks: fixtureCallbacks()
            )
            try await load(pageURL, in: firstSession.webView)
            let firstState = try await markerState(in: firstSession.webView)
            XCTAssertEqual(firstState, .present("personal"))

            XCTAssertTrue(browserStore.setProfile(university.id, forSpace: spaceID))
            let reassignedTab = try XCTUnwrap(browserStore.tabs.first { $0.id == tab.id })
            let secondSession = registry.session(
                for: reassignedTab,
                profile: university,
                state: state,
                dataStoreProvider: provider,
                securityPolicy: URLSecurityPolicy(),
                downloadSafetyPolicy: DownloadSafetyPolicy(),
                sitePermissionPolicy: SitePermissionPolicy(),
                callbacks: fixtureCallbacks()
            )
            XCTAssertFalse(firstSession === secondSession)
            try await load(pageURL, in: secondSession.webView)
            let secondState = try await markerState(in: secondSession.webView)
            XCTAssertEqual(secondState, .present("university"))
        } catch {
            await removePersistentStores([personal, university], provider: provider)
            throw error
        }

        await removePersistentStores([personal, university], provider: provider)
    }

    private func makeWebView(
        profile: BrowserProfile,
        provider: ProfileWebsiteDataStoreProvider
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = provider.websiteDataStore(for: profile)
        return WKWebView(frame: .zero, configuration: configuration)
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        let waiter = ProfileFixtureNavigationWaiter()
        try await waiter.load(url, in: webView)
    }

    private func writeMarker(_ marker: String, in webView: WKWebView) async throws {
        let script = """
        const marker = meridianMarker;
        document.cookie = `meridian_cookie=${marker}; path=/; SameSite=Lax`;
        localStorage.setItem("meridian_local", marker);

        const database = await new Promise((resolve, reject) => {
            const request = indexedDB.open("meridian_profile_fixture", 1);
            request.onupgradeneeded = () => request.result.createObjectStore("values");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
        await new Promise((resolve, reject) => {
            const transaction = database.transaction("values", "readwrite");
            transaction.objectStore("values").put(marker, "marker");
            transaction.oncomplete = () => resolve();
            transaction.onerror = () => reject(transaction.error);
        });

        const cache = await caches.open("meridian_profile_fixture");
        await cache.put("/cached-marker", new Response(marker));
        await navigator.serviceWorker.register("/service-worker.js");
        await navigator.serviceWorker.ready;
        return true;
        """
        _ = try await webView.callAsyncJavaScript(
            script,
            arguments: ["meridianMarker": marker],
            in: nil,
            contentWorld: .page
        )
    }

    private func readMarker(in webView: WKWebView) async throws -> WebPlatformMarkerState {
        let script = """
        const database = await new Promise((resolve, reject) => {
            const request = indexedDB.open("meridian_profile_fixture", 1);
            request.onupgradeneeded = () => request.result.createObjectStore("values");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
        });
        const indexedDBMarker = await new Promise((resolve, reject) => {
            const request = database.transaction("values", "readonly")
                .objectStore("values").get("marker");
            request.onsuccess = () => resolve(request.result || null);
            request.onerror = () => reject(request.error);
        });
        const cache = await caches.open("meridian_profile_fixture");
        const response = await cache.match("/cached-marker");
        const cacheMarker = response ? await response.text() : null;
        const registration = await navigator.serviceWorker.getRegistration();
        return JSON.stringify({
            cookie: document.cookie.match(/(?:^|; )meridian_cookie=([^;]*)/)?.[1] || null,
            localStorage: localStorage.getItem("meridian_local"),
            indexedDB: indexedDBMarker,
            cache: cacheMarker,
            serviceWorker: Boolean(registration)
        });
        """
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try XCTUnwrap(value as? String)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let result = try JSONDecoder().decode(WebPlatformMarkerResult.self, from: data)
        let markers = [result.cookie, result.localStorage, result.indexedDB, result.cache]
        if markers.allSatisfy({ $0 == nil }) && !result.serviceWorker {
            return .absent
        }
        guard let marker = result.cookie,
              markers.allSatisfy({ $0 == marker }),
              result.serviceWorker else {
            XCTFail("WebKit storage fixture returned a partially isolated state.")
            return .partial
        }
        return .present(marker)
    }

    private func markerState(in webView: WKWebView) async throws -> WebPlatformMarkerState {
        try await readMarker(in: webView)
    }

    private func fixtureCallbacks() -> BrowserWebViewCallbacks {
        BrowserWebViewCallbacks(
            onStateChange: { _, _, _, _ in },
            onSecurityMessage: { _ in },
            onURLConfirmationRequired: { _, _, _ in },
            onDownloadConfirmationRequired: { _, completion in completion(nil) },
            onSitePermissionRequest: { _, _ in
                .deny(reason: "Profile isolation fixture denies permission requests.")
            }
        )
    }

    private func removePersistentStores(
        _ profiles: [BrowserProfile],
        provider: ProfileWebsiteDataStoreProvider
    ) async {
        for profile in profiles {
            guard let identifier = profile.persistentWebsiteDataStoreID else {
                continue
            }
            try? await provider.removeWebsiteDataStore(identifier: identifier)
        }
    }
}

private enum WebPlatformMarkerState: Equatable {
    case present(String)
    case absent
    case partial
}

private struct WebPlatformMarkerResult: Decodable {
    var cookie: String?
    var localStorage: String?
    var indexedDB: String?
    var cache: String?
    var serviceWorker: Bool
}

@MainActor
private final class ProfileFixtureNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(returning: ())
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private final class LoopbackProfileFixtureServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LumenBrowser.ProfileIsolationFixture")
    private var startContinuation: CheckedContinuation<URL, Error>?

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                self?.handle(state)
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else {
                startContinuation?.resume(throwing: FixtureServerError.missingPort)
                startContinuation = nil
                return
            }
            startContinuation?.resume(returning: url)
            startContinuation = nil
        case .failed(let error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else {
                return
            }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let response = self.response(for: path)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for path: String) -> Data {
        let contentType: String
        let body: String
        if path == "/service-worker.js" {
            contentType = "application/javascript"
            body = "self.addEventListener('fetch', () => {});"
        } else {
            contentType = "text/html; charset=utf-8"
            body = "<!doctype html><meta charset='utf-8'><title>Profile Isolation Fixture</title>"
        }
        let bodyData = Data(body.utf8)
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Cache-Control: no-store\r
        Connection: close\r
        \r

        """
        return Data(header.utf8) + bodyData
    }
}

private enum FixtureServerError: Error {
    case missingPort
}
