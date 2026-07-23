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
        let publicDownload = BrowserDownload(
            profileID: publicProfileID,
            filename: "public.pdf",
            sourceDescription: "public.example",
            destinationURL: URL(fileURLWithPath: "/tmp/public.pdf"),
            state: .finished,
            startedAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            completedAt: Date(timeIntervalSince1970: 2)
        )
        let interruptedDownload = BrowserDownload(
            profileID: publicProfileID,
            filename: "interrupted.zip",
            sourceDescription: "public.example",
            state: .downloading,
            progress: 0.4,
            startedAt: Date(timeIntervalSince1970: 3),
            updatedAt: Date(timeIntervalSince1970: 4)
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

        var snapshot = store.snapshot(date: Date(timeIntervalSince1970: 10))
        snapshot.downloads = [
            publicDownload,
            interruptedDownload,
            BrowserDownload(
                profileID: privateProfile.id,
                filename: "private-secret.pdf",
                sourceDescription: "private-download.example",
                destinationURL: URL(fileURLWithPath: "/tmp/private-secret.pdf"),
                state: .finished,
                startedAt: Date(timeIntervalSince1970: 5),
                updatedAt: Date(timeIntervalSince1970: 6),
                completedAt: Date(timeIntervalSince1970: 6)
            )
        ]
        let persisted = SessionPersistenceBoundary.persistentSnapshot(
            from: snapshot,
            fallback: SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 10))
        )

        XCTAssertFalse(persisted.profiles.contains { $0.id == privateProfile.id })
        XCTAssertFalse(persisted.spaces.contains { $0.id == privateSpace.id })
        XCTAssertFalse(persisted.folders.contains { $0.id == privateFolder.id })
        XCTAssertFalse(persisted.tabs.contains { $0.id == privateTab.id })
        XCTAssertFalse(persisted.splitViews.contains { $0.id == splitViewID })
        XCTAssertEqual(persisted.downloads.count, 2)
        XCTAssertTrue(persisted.downloads.contains { $0.id == publicDownload.id })
        XCTAssertFalse(persisted.downloads.contains { $0.profileID == privateProfile.id })
        let persistedInterrupted = try XCTUnwrap(persisted.downloads.first { $0.id == interruptedDownload.id })
        XCTAssertEqual(persistedInterrupted.state, .failed)
        XCTAssertEqual(persistedInterrupted.completedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(persistedInterrupted.failureMessage, "Download was interrupted when Lumen Browser closed.")
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
        XCTAssertFalse(payload.contains("private-secret.pdf"))
        XCTAssertFalse(payload.contains("private-download.example"))
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

    func testRepairSeparatesDuplicateWebsiteStoresAndRepairsTabProfileMetadata() throws {
        let sharedStoreID = UUID()
        let olderProfile = BrowserProfile(
            name: "University",
            websiteDataStoreID: sharedStoreID,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newerProfile = BrowserProfile(
            name: "Personal",
            websiteDataStoreID: sharedStoreID,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        var universitySpace = BrowserSpace(name: "University", profileID: olderProfile.id)
        var personalSpace = BrowserSpace(name: "Personal", profileID: newerProfile.id)
        let universityTab = BrowserTab(
            title: "Mail",
            parentSpaceID: universitySpace.id,
            profileID: newerProfile.id
        )
        let personalTab = BrowserTab(
            title: "Search",
            parentSpaceID: personalSpace.id,
            profileID: olderProfile.id
        )
        universitySpace.regularTabIDs = [universityTab.id]
        universitySpace.selectedTabID = universityTab.id
        personalSpace.regularTabIDs = [personalTab.id]
        personalSpace.selectedTabID = personalTab.id
        let snapshot = BrowserSessionSnapshot(
            profiles: [newerProfile, olderProfile],
            spaces: [universitySpace, personalSpace],
            folders: [],
            tabs: [universityTab, personalTab],
            selectedSpaceID: personalSpace.id,
            selectedTabID: personalTab.id
        )

        let result = SessionPersistenceBoundary.repairPersistentSnapshot(
            from: snapshot,
            fallback: SessionSnapshotFactory.initial()
        )

        let repairedOlder = try XCTUnwrap(result.snapshot.profiles.first { $0.id == olderProfile.id })
        let repairedNewer = try XCTUnwrap(result.snapshot.profiles.first { $0.id == newerProfile.id })
        XCTAssertEqual(repairedOlder.persistentWebsiteDataStoreID, sharedStoreID)
        XCTAssertNotEqual(repairedNewer.persistentWebsiteDataStoreID, sharedStoreID)
        XCTAssertNotNil(repairedNewer.persistentWebsiteDataStoreID)
        XCTAssertEqual(result.report.duplicateWebsiteDataStoresIsolated, 1)
        XCTAssertEqual(result.report.tabProfileMismatchesRepaired, 2)
        XCTAssertEqual(
            result.snapshot.tabs.first { $0.id == universityTab.id }?.profileID,
            olderProfile.id
        )
        XCTAssertEqual(
            result.snapshot.tabs.first { $0.id == personalTab.id }?.profileID,
            newerProfile.id
        )
        XCTAssertTrue(result.report.userMessage?.contains("signed out") == true)
    }

    func testRepairRebuildsCorruptGraphCyclesMembershipAndSelections() throws {
        let personalProfile = BrowserProfile(name: "Personal")
        let workProfile = BrowserProfile(name: "Work")
        var personalSpace = BrowserSpace(name: "Personal", profileID: personalProfile.id)
        var workSpace = BrowserSpace(name: "Work", profileID: workProfile.id)
        var firstFolder = BrowserFolder(name: "First", parentSpaceID: personalSpace.id)
        var secondFolder = BrowserFolder(name: "Second", parentSpaceID: personalSpace.id)
        firstFolder.parentFolderID = secondFolder.id
        secondFolder.parentFolderID = firstFolder.id
        firstFolder.childFolderIDs = [secondFolder.id]
        secondFolder.childFolderIDs = [firstFolder.id]
        let personalTab = BrowserTab(
            title: "Personal",
            parentSpaceID: personalSpace.id,
            parentFolderID: workSpace.id,
            profileID: workProfile.id
        )
        let workTab = BrowserTab(
            title: "Work",
            parentSpaceID: workSpace.id,
            profileID: workProfile.id
        )
        personalSpace.regularTabIDs = [workTab.id, personalTab.id, personalTab.id]
        personalSpace.folderIDs = [firstFolder.id, secondFolder.id]
        personalSpace.selectedTabID = workTab.id
        workSpace.regularTabIDs = [personalTab.id, workTab.id]
        workSpace.selectedTabID = personalTab.id
        let duplicateWorkSpace = BrowserSpace(
            id: workSpace.id,
            name: "Duplicate",
            profileID: personalProfile.id
        )
        var duplicatePersonalTab = personalTab
        duplicatePersonalTab.title = "Duplicate"
        let snapshot = BrowserSessionSnapshot(
            profiles: [personalProfile, workProfile],
            spaces: [personalSpace, workSpace, duplicateWorkSpace],
            folders: [firstFolder, secondFolder],
            tabs: [personalTab, workTab, duplicatePersonalTab],
            selectedSpaceID: UUID(),
            selectedTabID: UUID()
        )

        let result = SessionPersistenceBoundary.repairPersistentSnapshot(
            from: snapshot,
            fallback: SessionSnapshotFactory.initial()
        )

        XCTAssertEqual(result.report.duplicateSpaceIDsRemoved, 1)
        XCTAssertEqual(result.report.duplicateTabIDsRemoved, 1)
        XCTAssertGreaterThanOrEqual(result.report.folderRelationshipsRepaired, 2)
        XCTAssertGreaterThan(result.report.ownershipListsRebuilt, 0)
        XCTAssertGreaterThan(result.report.selectionsRepaired, 0)
        XCTAssertEqual(Set(result.snapshot.spaces.map(\.id)).count, result.snapshot.spaces.count)
        XCTAssertEqual(Set(result.snapshot.tabs.map(\.id)).count, result.snapshot.tabs.count)
        XCTAssertTrue(result.snapshot.folders.allSatisfy { $0.parentFolderID == nil })
        let repairedPersonalSpace = try XCTUnwrap(
            result.snapshot.spaces.first { $0.id == personalSpace.id }
        )
        let repairedWorkSpace = try XCTUnwrap(result.snapshot.spaces.first { $0.id == workSpace.id })
        XCTAssertFalse(repairedPersonalSpace.regularTabIDs.contains(workTab.id))
        XCTAssertEqual(repairedWorkSpace.regularTabIDs, [workTab.id])
        XCTAssertEqual(result.snapshot.selectedSpaceID, personalSpace.id)
        XCTAssertEqual(result.snapshot.tabs.first { $0.id == personalTab.id }?.profileID, personalProfile.id)
    }
}
