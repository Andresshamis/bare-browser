import Foundation
import MeridianCore
import XCTest

@MainActor
final class SessionPersistenceBoundaryTests: XCTestCase {
    func testPersistentSnapshotExcludesPrivateProfileAndDependentState() throws {
        let store = BrowserStore(snapshot: SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 0)))
        let publicSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let publicTab = try XCTUnwrap(store.createTab(
            title: "Public",
            url: URL(string: "https://public.example"),
            in: publicSpaceID
        ))
        let publicProfileID = try XCTUnwrap(store.activeProfile?.id)
        let publicPermissionOrigin = try XCTUnwrap(
            SitePermissionOrigin(url: URL(string: "https://camera.example")!)
        )
        _ = store.requestSitePermission(kind: .camera, origin: publicPermissionOrigin, profileID: publicProfileID)
        _ = store.resolvePendingSitePermission(
            .allow,
            requestID: try XCTUnwrap(store.pendingSitePermissionRequest?.id),
            date: Date(timeIntervalSince1970: 1)
        )
        let privateProfile = store.createProfile(name: "Private Session", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private Space", profileID: privateProfile.id)
        let privateFolder = try XCTUnwrap(store.createFolder(name: "Private Folder", in: privateSpace.id))
        let privateTab = try XCTUnwrap(store.createTab(
            title: "Private",
            url: URL(string: "https://private.example/secret"),
            in: privateSpace.id,
            folderID: privateFolder.id
        ))
        let privatePermissionOrigin = try XCTUnwrap(
            SitePermissionOrigin(url: URL(string: "https://private-permission.example")!)
        )
        _ = store.requestSitePermission(
            kind: .microphone,
            origin: privatePermissionOrigin,
            profileID: privateProfile.id
        )
        _ = store.resolvePendingSitePermission(
            .allow,
            requestID: try XCTUnwrap(store.pendingSitePermissionRequest?.id),
            date: Date(timeIntervalSince1970: 2)
        )
        let splitViewID = SplitViewID()

        store.splitViews.append(SplitViewLayout(
            id: splitViewID,
            tabIDs: [publicTab.id, privateTab.id],
            fractions: [0.5, 0.5]
        ))
        if let publicTabIndex = store.tabs.firstIndex(where: { $0.id == publicTab.id }) {
            store.tabs[publicTabIndex].splitViewID = splitViewID
        }
        if let privateTabIndex = store.tabs.firstIndex(where: { $0.id == privateTab.id }) {
            store.tabs[privateTabIndex].splitViewID = splitViewID
        }

        let persisted = store.persistentSnapshot(date: Date(timeIntervalSince1970: 10))

        XCTAssertFalse(persisted.profiles.contains { $0.id == privateProfile.id })
        XCTAssertFalse(persisted.spaces.contains { $0.id == privateSpace.id })
        XCTAssertFalse(persisted.folders.contains { $0.id == privateFolder.id })
        XCTAssertFalse(persisted.tabs.contains { $0.id == privateTab.id })
        XCTAssertFalse(persisted.splitViews.contains { $0.id == splitViewID })
        XCTAssertEqual(persisted.sitePermissionSettings.count, 1)
        XCTAssertEqual(persisted.sitePermissionSettings.first?.origin.serializedOrigin, "https://camera.example")
        XCTAssertEqual(persisted.sitePermissionSettings.first?.profileID, publicProfileID)
        XCTAssertNotEqual(persisted.selectedSpaceID, privateSpace.id)
        XCTAssertNotEqual(persisted.selectedTabID, privateTab.id)
        XCTAssertEqual(persisted.selectedSpaceID, publicSpaceID)
        XCTAssertEqual(persisted.selectedTabID, publicTab.id)
        XCTAssertNil(persisted.tabs.first(where: { $0.id == publicTab.id })?.splitViewID)

        let payload = try XCTUnwrap(String(data: JSONEncoder().encode(persisted), encoding: .utf8))
        let lowercasedPayload = payload.lowercased()
        XCTAssertFalse(payload.contains("private.example"))
        XCTAssertFalse(lowercasedPayload.contains(privateProfile.id.uuidString.lowercased()))
        XCTAssertFalse(lowercasedPayload.contains(privateSpace.id.uuidString.lowercased()))
        XCTAssertFalse(lowercasedPayload.contains(privateTab.id.uuidString.lowercased()))
        XCTAssertFalse(payload.contains("private-permission.example"))
    }

    func testPersistentSnapshotFallsBackWhenOnlyPrivateStateRemains() {
        let date = Date(timeIntervalSince1970: 20)
        let privateProfile = BrowserProfile.privateBrowsing(id: ProfileID())
        let privateSpace = BrowserSpace(name: "Private", profileID: privateProfile.id)
        let privateTab = BrowserTab(
            title: "Private",
            url: URL(string: "https://private.example/only"),
            parentSpaceID: privateSpace.id,
            profileID: privateProfile.id
        )
        var selectedPrivateSpace = privateSpace
        selectedPrivateSpace.regularTabIDs = [privateTab.id]
        selectedPrivateSpace.selectedTabID = privateTab.id
        let privateSnapshot = BrowserSessionSnapshot(
            profiles: [privateProfile],
            spaces: [selectedPrivateSpace],
            folders: [],
            tabs: [privateTab],
            selectedSpaceID: selectedPrivateSpace.id,
            selectedTabID: privateTab.id,
            capturedAt: date
        )
        let fallback = SessionSnapshotFactory.initial(date: date)

        let persisted = SessionPersistenceBoundary.persistentSnapshot(
            from: privateSnapshot,
            fallback: fallback
        )

        XCTAssertEqual(persisted, fallback)
        XCTAssertFalse(persisted.profiles.contains { $0.isEphemeral })
        XCTAssertFalse(persisted.tabs.contains { $0.url?.host(percentEncoded: false) == "private.example" })
    }
}
