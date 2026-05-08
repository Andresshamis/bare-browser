import Foundation
import MeridianCore
import SQLite3
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
        let publicSpaceID = try XCTUnwrap(store.selectedSpaceID)
        let publicTab = try XCTUnwrap(store.createTab(
            title: "Public Research",
            url: URL(string: "https://public.example/articles"),
            in: publicSpaceID
        ))
        let privateProfile = store.createProfile(name: "Private Session", ephemeral: true)
        let privateSpace = store.createSpace(name: "Private", profileID: privateProfile.id)
        let privateTab = try XCTUnwrap(store.createTab(
            title: "Private Secret",
            url: URL(string: "https://private.example/secret?token=fixture"),
            in: privateSpace.id
        ))
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
        XCTAssertEqual(result.snapshot.selectedSpaceID, publicSpaceID)
        XCTAssertEqual(result.snapshot.selectedTabID, publicTab.id)

        let rawDatabase = String(decoding: try Data(contentsOf: databaseURL), as: UTF8.self)
        XCTAssertFalse(rawDatabase.contains("private.example"))
        XCTAssertFalse(rawDatabase.contains("secret"))
        XCTAssertFalse(rawDatabase.contains("token"))
        XCTAssertFalse(rawDatabase.contains(privateProfile.id.uuidString))
    }

    func testUnsupportedSchemaFallsBackToSeededSession() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 4))
        let futureSchemaVersion = SQLiteSessionPersistenceStore.currentSchemaVersion + 1
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)
        let payload = try JSONEncoder().encode(fallback)

        try writeRawSessionRecord(
            databaseURL: databaseURL,
            schemaVersion: futureSchemaVersion,
            payload: payload
        )
        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .unsupportedSchema(futureSchemaVersion))
        XCTAssertNotNil(result.recoveryReason?.userMessage)
    }

    func testUnreadableStoreFallsBackWithoutLeakingStoredBytesInMessage() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Session.sqlite3")
        let fallback = SessionSnapshotFactory.initial(date: Date(timeIntervalSince1970: 5))
        try Data("private.example/token=secret".utf8).write(to: databaseURL)
        let persistence = SQLiteSessionPersistenceStore(databaseURL: databaseURL)

        let result = persistence.loadSnapshot(fallback: fallback)

        XCTAssertEqual(result.snapshot, fallback)
        XCTAssertEqual(result.recoveryReason, .unreadableStore)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("secret") ?? true)
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

private final class SessionPersistenceSpy: SessionSnapshotPersisting {
    var savedSnapshots: [BrowserSessionSnapshot] = []
    var fallbacks: [BrowserSessionSnapshot] = []

    func saveSnapshot(_ snapshot: BrowserSessionSnapshot, fallback: BrowserSessionSnapshot) throws {
        savedSnapshots.append(snapshot)
        fallbacks.append(fallback)
    }
}
