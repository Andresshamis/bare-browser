import Foundation
import SQLite3
@testable import MeridianCore
import XCTest

@MainActor
final class SQLiteSessionPersistenceStoreTests: XCTestCase {
    func testMissingStoreReturnsFallbackWithoutCreatingDatabase() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 1))
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)

        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .noSavedSession)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testSaveAndLoadRoundTripFiltersPrivateSessionStateFromDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 2))
        let store = BrowserStore(snapshot: fallback)
        let publicProfileID = try XCTUnwrap(store.activeProfile?.id)
        let publicSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let publicTab = try XCTUnwrap(store.createTab(
            title: "Public Research",
            url: URL(string: "https://public.example/articles"),
            in: publicSpaceID
        ))
        let publicPermissionOrigin = try XCTUnwrap(
            SitePermissionOrigin(url: URL(string: "https://camera.example")!)
        )
        _ = store.requestSitePermission(kind: .camera, origin: publicPermissionOrigin, profileID: publicProfileID)
        _ = store.resolvePendingSitePermission(
            .allow,
            requestID: try XCTUnwrap(store.pendingSitePermissionRequest?.id),
            date: Date(timeIntervalSince1970: 2.5)
        )
        let privateProfile = store.createProfile(name: "Private Session", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private", profileID: privateProfile.id)
        let privateTab = try XCTUnwrap(store.createTab(
            title: "Private Secret",
            url: URL(string: "https://private.example/secret?token=fixture"),
            in: privateSpace.id
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
            date: Date(timeIntervalSince1970: 2.75)
        )
        let publicDownloadRequest = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "public-download.pdf",
            sourceURL: URL(string: "https://public-download.example/file.pdf")
        )
        let publicDownloadURL = directory.appendingPathComponent("public-download.pdf")
        store.requestDownloadConfirmation(publicDownloadRequest, profileID: publicProfileID) { _ in }
        XCTAssertTrue(store.approvePendingDownloadConfirmation(destination: publicDownloadURL))
        store.finishDownload(
            publicDownloadRequest.id,
            destinationURL: publicDownloadURL,
            quarantineApplied: true,
            date: Date(timeIntervalSince1970: 2.8)
        )
        let privateDownloadRequest = store.downloadSafetyPolicy.confirmationRequest(
            suggestedFilename: "private-secret.pdf",
            sourceURL: URL(string: "https://private-download.example/secret.pdf")
        )
        let privateDownloadURL = directory.appendingPathComponent("private-secret.pdf")
        store.requestDownloadConfirmation(privateDownloadRequest, profileID: privateProfile.id) { _ in }
        XCTAssertTrue(store.approvePendingDownloadConfirmation(destination: privateDownloadURL))
        store.finishDownload(
            privateDownloadRequest.id,
            destinationURL: privateDownloadURL,
            quarantineApplied: true,
            date: Date(timeIntervalSince1970: 2.9)
        )
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)

        try persistence.saveSnapshot(
            store.snapshot(date: Date(timeIntervalSince1970: 3)),
            fallback: fallback
        )

        let result = persistence.loadSnapshot(fallback: fallback)
        XCTAssertNil(result.recoveryReason)
        XCTAssertTrue(result.snapshot.tabs.contains { $0.id == publicTab.id })
        XCTAssertFalse(result.snapshot.profiles.contains { $0.id == privateProfile.id })
        XCTAssertFalse(result.snapshot.spaces.contains { $0.id == privateSpace.id })
        XCTAssertFalse(result.snapshot.tabs.contains { $0.id == privateTab.id })
        XCTAssertEqual(result.snapshot.sitePermissionSettings.count, 1)
        XCTAssertEqual(result.snapshot.sitePermissionSettings.first?.origin.serializedOrigin, "https://camera.example")
        XCTAssertTrue(result.snapshot.downloads.contains { $0.id == publicDownloadRequest.id })
        XCTAssertFalse(result.snapshot.downloads.contains { $0.id == privateDownloadRequest.id })
        XCTAssertEqual(result.snapshot.selectedSpaceID, publicSpaceID)
        XCTAssertEqual(result.snapshot.selectedTabID, publicTab.id)

        let rawDatabase = String(decoding: try Data(contentsOf: databaseURL), as: UTF8.self)
        XCTAssertTrue(rawDatabase.contains("camera.example"))
        XCTAssertTrue(rawDatabase.contains("public-download.pdf"))
        XCTAssertFalse(rawDatabase.contains("private.example"))
        XCTAssertFalse(rawDatabase.contains("private-permission.example"))
        XCTAssertFalse(rawDatabase.contains("private-download.example"))
        XCTAssertFalse(rawDatabase.contains("private-secret.pdf"))
        XCTAssertFalse(rawDatabase.contains("secret"))
        XCTAssertFalse(rawDatabase.contains("token"))
        XCTAssertFalse(rawDatabase.contains(privateProfile.id.uuidString))
    }

    func testLoadRepairScrubsPrivacyInvalidRawRecordFromDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 4))
        let store = BrowserStore(snapshot: fallback)
        let publicProfileID = try XCTUnwrap(store.activeProfile?.id)
        let publicSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let publicTab = try XCTUnwrap(store.createTab(
            title: "Public Research",
            url: URL(string: "https://public.example/articles"),
            in: publicSpaceID
        ))
        let publicPermissionOrigin = try XCTUnwrap(
            SitePermissionOrigin(url: URL(string: "https://camera.example")!)
        )
        _ = store.requestSitePermission(kind: .camera, origin: publicPermissionOrigin, profileID: publicProfileID)
        _ = store.resolvePendingSitePermission(
            .allow,
            requestID: try XCTUnwrap(store.pendingSitePermissionRequest?.id),
            date: Date(timeIntervalSince1970: 4.5)
        )
        let privateProfile = store.createProfile(name: "Private Session", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private", profileID: privateProfile.id)
        let privateTab = try XCTUnwrap(store.createTab(
            title: "Private Secret",
            url: URL(string: "https://private.example/secret?token=fixture"),
            in: privateSpace.id
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
            date: Date(timeIntervalSince1970: 4.75)
        )
        let invalidSnapshot = store.snapshot(date: Date(timeIntervalSince1970: 5))
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)

        try writeRawSessionRecord(
            databaseURL: databaseURL,
            schemaVersion: SQLiteSessionPersistenceStore.currentSchemaVersion,
            payload: try JSONEncoder().encode(invalidSnapshot)
        )
        let originalDatabase = try rawDatabaseText(at: databaseURL)
        XCTAssertTrue(originalDatabase.contains("private.example"))
        XCTAssertTrue(originalDatabase.contains("private-permission.example"))
        XCTAssertTrue(originalDatabase.contains(privateProfile.id.uuidString))

        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.recoveryReason, .repairedSnapshot)
        XCTAssertTrue(result.integrityRepairReport.didRepairIsolationState)
        XCTAssertTrue(result.snapshot.tabs.contains { $0.id == publicTab.id })
        XCTAssertFalse(result.snapshot.profiles.contains { $0.id == privateProfile.id })
        XCTAssertFalse(result.snapshot.spaces.contains { $0.id == privateSpace.id })
        XCTAssertFalse(result.snapshot.tabs.contains { $0.id == privateTab.id })
        XCTAssertEqual(result.snapshot.sitePermissionSettings.count, 1)
        XCTAssertEqual(result.snapshot.sitePermissionSettings.first?.origin.serializedOrigin, "https://camera.example")
        XCTAssertEqual(result.snapshot.selectedSpaceID, publicSpaceID)
        XCTAssertEqual(result.snapshot.selectedTabID, publicTab.id)

        let repairedDatabase = try rawDatabaseText(at: databaseURL)
        XCTAssertTrue(repairedDatabase.contains("public.example"))
        XCTAssertTrue(repairedDatabase.contains("camera.example"))
        XCTAssertFalse(repairedDatabase.contains("private.example"))
        XCTAssertFalse(repairedDatabase.contains("private-permission.example"))
        XCTAssertFalse(repairedDatabase.contains("secret"))
        XCTAssertFalse(repairedDatabase.contains("token"))
        XCTAssertFalse(repairedDatabase.contains("fixture"))
        XCTAssertFalse(repairedDatabase.contains(privateProfile.id.uuidString))

        let cleanReload = persistence.loadSnapshot(fallback: fallback)
        XCTAssertNil(cleanReload.recoveryReason)
        XCTAssertFalse(cleanReload.integrityRepairReport.didRepairIsolationState)
    }

    func testLoadFallsBackAndDeletesStoreWhenRepairScrubCannotComplete() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 6))
        let privateProfile = BrowserProfile.privateBrowsing(id: ProfileID())
        let privateSpace = BrowserSpace(name: "Private", profileID: privateProfile.id)
        let privateTab = BrowserTab(
            title: "Private Only",
            url: URL(string: "https://private.example/secret?token=fixture"),
            parentSpaceID: privateSpace.id,
            profileID: privateProfile.id
        )
        var selectedPrivateSpace = privateSpace
        selectedPrivateSpace.regularTabIDs = [privateTab.id]
        selectedPrivateSpace.selectedTabID = privateTab.id
        let invalidSnapshot = BrowserSessionSnapshot(
            profiles: [privateProfile],
            spaces: [selectedPrivateSpace],
            folders: [],
            tabs: [privateTab],
            selectedSpaceID: selectedPrivateSpace.id,
            selectedTabID: privateTab.id,
            capturedAt: Date(timeIntervalSince1970: 7)
        )
        let persistence = SQLiteSessionPersistenceStore(
            databaseURL: databaseURL,
            repairScrubInterruption: { throw RepairScrubFailure() }
        )

        try writeRawSessionRecord(
            databaseURL: databaseURL,
            schemaVersion: SQLiteSessionPersistenceStore.currentSchemaVersion,
            payload: try JSONEncoder().encode(invalidSnapshot)
        )
        XCTAssertTrue(try rawDatabaseText(at: databaseURL).contains("private.example"))

        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .unreadableStore)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("fixture") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-journal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))
    }

    func testUnsupportedSchemaFallsBackToSeededSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 8))
        let futureSchemaVersion = SQLiteSessionPersistenceStore.currentSchemaVersion + 1
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)
        let payload = Data("https://private.example/secret?token=fixture".utf8)

        try writeRawSessionRecord(
            databaseURL: databaseURL,
            schemaVersion: futureSchemaVersion,
            payload: payload
        )
        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .unsupportedSchema(futureSchemaVersion))
        XCTAssertNotNil(result.recoveryReason?.userMessage)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("fixture") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testCorruptPayloadDeletesStoreWithoutLeakingStoredBytesInMessage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 9))
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)

        try writeRawSessionRecord(
            databaseURL: databaseURL,
            schemaVersion: SQLiteSessionPersistenceStore.currentSchemaVersion,
            payload: Data("{\"url\":\"https://private.example/secret?token=fixture\"}".utf8)
        )

        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .corruptPayload)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("fixture") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testUnreadableStoreFallsBackWithoutLeakingStoredBytesInMessage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 10))
        try Data("private.example/token=secret".utf8).write(to: databaseURL)
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)

        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .unreadableStore)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("secret") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testBrowserStorePersistsSessionMutationsThroughConfiguredWriter() throws {
        let spy = SessionPersistenceSpy()
        let store = BrowserStore(sessionPersistence: spy)

        _ = store.createTab(title: "Saved", url: URL(string: "https://example.com/saved"))

        let savedSnapshot = try XCTUnwrap(spy.savedSnapshots.last)
        XCTAssertTrue(savedSnapshot.tabs.contains { $0.url?.absoluteString == "https://example.com/saved" })
        XCTAssertEqual(spy.fallbacks.count, spy.savedSnapshots.count)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func rawDatabaseText(at databaseURL: URL) throws -> String {
        String(decoding: try Data(contentsOf: databaseURL), as: UTF8.self)
    }

    private func writeRawSessionRecord(
        databaseURL: URL,
        schemaVersion: Int,
        payload: Data
    ) throws {
        var database: OpaquePointer?
        XCTAssertEqual(
            sqlite3_open_v2(
                databaseURL.path,
                &database,
                SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                nil
            ),
            SQLITE_OK
        )
        let openedDatabase = try XCTUnwrap(database)
        defer { sqlite3_close(openedDatabase) }

        XCTAssertEqual(
            sqlite3_exec(
                openedDatabase,
                """
                CREATE TABLE IF NOT EXISTS session_snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    schema_version INTEGER NOT NULL,
                    captured_at REAL NOT NULL,
                    payload BLOB NOT NULL,
                    updated_at REAL NOT NULL
                );
                """,
                nil,
                nil,
                nil
            ),
            SQLITE_OK
        )

        var statement: OpaquePointer?
        XCTAssertEqual(
            sqlite3_prepare_v2(
                openedDatabase,
                "INSERT INTO session_snapshots (id, schema_version, captured_at, payload, updated_at) VALUES (?, ?, ?, ?, ?);",
                -1,
                &statement,
                nil
            ),
            SQLITE_OK
        )
        let preparedStatement = try XCTUnwrap(statement)
        defer { sqlite3_finalize(preparedStatement) }

        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(preparedStatement, 1, "main", -1, sqliteTransient)
        sqlite3_bind_int(preparedStatement, 2, Int32(schemaVersion))
        sqlite3_bind_double(preparedStatement, 3, 0)
        let bindPayloadResult = payload.withUnsafeBytes { buffer in
            sqlite3_bind_blob(preparedStatement, 4, buffer.baseAddress, Int32(payload.count), sqliteTransient)
        }
        XCTAssertEqual(bindPayloadResult, SQLITE_OK)
        sqlite3_bind_double(preparedStatement, 5, 0)

        XCTAssertEqual(sqlite3_step(preparedStatement), SQLITE_DONE)
    }
}

private struct RepairScrubFailure: Error {}

private final class SessionPersistenceSpy: SessionSnapshotPersisting {
    var savedSnapshots: [BrowserSessionSnapshot] = []
    var fallbacks: [BrowserSessionSnapshot] = []

    func saveSnapshot(_ snapshot: BrowserSessionSnapshot, fallback: BrowserSessionSnapshot) throws {
        savedSnapshots.append(snapshot)
        fallbacks.append(fallback)
    }
}
