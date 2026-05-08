import Foundation
import MeridianCore
import XCTest

@MainActor
final class BrowserStoreTests: XCTestCase {
    func testInitialSnapshotHasProfileSpaceAndSelectedTab() {
        let store = BrowserStore(snapshot: SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 0)))

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.spaces.count, 1)
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertNotNil(store.selectedSpaceID)
        XCTAssertNotNil(store.selectedTabID)
        XCTAssertEqual(store.activeProfile?.name, "Personal")
    }

    func testCreatesSpaceFolderAndTabWithStableRelationships() {
        let store = BrowserStore()
        let space = store.createSpace(name: "Work")
        let folder = store.createFolder(name: "Research", in: space.id)
        let tab = store.createTab(url: URL(string: "https://webkit.org"), in: space.id, folderID: folder?.id)

        XCTAssertEqual(store.selectedSpaceID, space.id)
        XCTAssertEqual(tab?.parentSpaceID, space.id)
        XCTAssertEqual(tab?.parentFolderID, folder?.id)
        XCTAssertEqual(store.folders.first(where: { $0.id == folder?.id })?.tabIDs, [tab?.id].compactMap { $0 })
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let store = BrowserStore()
        _ = store.createTab(url: URL(string: "https://example.com"))

        let snapshot = store.snapshot(date: Date(timeIntervalSince1970: 10))
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.tabs.count, snapshot.tabs.count)
        XCTAssertEqual(decoded.selectedTabID, snapshot.selectedTabID)
    }

    func testSitePermissionRequestPublishesSanitizedPendingState() {
        let store = BrowserStore()
        let profileID = store.activeProfile!.id
        let origin = SitePermissionOrigin(
            url: URL(string: "https://user:pass@example.com/private/file?token=secret#frag")!
        )

        let result = store.requestSitePermission(kind: .camera, origin: origin, profileID: profileID)

        XCTAssertEqual(result, .ask)
        XCTAssertEqual(store.pendingSitePermissionRequest?.origin.displayString, "example.com")
        XCTAssertEqual(store.pendingSitePermissionRequest?.promptMessage, "example.com wants to use camera.")
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("user") ?? true)
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("token") ?? true)
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("/private") ?? true)
        XCTAssertFalse(store.pendingSitePermissionRequest?.promptMessage.contains("frag") ?? true)
    }

    func testResolvingSitePermissionStoresAllowDecisionForProfileOrigin() {
        let store = BrowserStore()
        let profileID = store.activeProfile!.id
        let origin = SitePermissionOrigin(url: URL(string: "https://example.com")!)!
        _ = store.requestSitePermission(kind: .popupWindow, origin: origin, profileID: profileID)
        let requestID = store.pendingSitePermissionRequest!.id

        let result = store.resolvePendingSitePermission(.allow, requestID: requestID)

        XCTAssertEqual(result, .allow)
        XCTAssertNil(store.pendingSitePermissionRequest)
        XCTAssertEqual(store.sitePermissionSettings.count, 1)
        XCTAssertEqual(store.sitePermissionSettings.first?.kind, .popupWindow)
        XCTAssertEqual(store.sitePermissionSettings.first?.origin.serializedOrigin, "https://example.com")
        XCTAssertEqual(store.sitePermissionSettings.first?.decision, .allow)
        XCTAssertEqual(store.sitePermissionSettings.first?.persistsBeyondSession, true)
        XCTAssertEqual(
            store.requestSitePermission(kind: .popupWindow, origin: origin, profileID: profileID),
            .allow
        )
    }

    func testUnsupportedPermissionIsDeniedWithoutPendingState() {
        let store = BrowserStore()

        let result = store.requestSitePermission(
            kind: .notifications,
            origin: SitePermissionOrigin(url: URL(string: "https://example.com")!)
        )

        XCTAssertEqual(
            result,
            .deny(reason: "Notifications permissions are not supported by Meridian on this WebKit version.")
        )
        XCTAssertNil(store.pendingSitePermissionRequest)
        XCTAssertEqual(
            store.lastUserMessage,
            "Notifications permissions are not supported by Meridian on this WebKit version."
        )
    }
}
