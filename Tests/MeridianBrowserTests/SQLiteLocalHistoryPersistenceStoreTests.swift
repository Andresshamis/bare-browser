import Foundation
import SQLite3
@testable import MeridianCore
import XCTest

final class SQLiteLocalHistoryPersistenceStoreTests: XCTestCase {
    func testMissingStoreReturnsEmptyHistoryWithoutCreatingDatabase() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("History.sqlite3")
        let persistence = SQLiteLocalHistoryPersistenceStore(databaseURL: databaseURL)

        let result = persistence.loadHistory(profiles: [BrowserProfile(name: "Personal")])

        XCTAssertEqual(result.entries, [])
        XCTAssertEqual(result.recoveryReason, .noSavedHistory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testSaveAndLoadRoundTripFiltersPrivateHistoryFromDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("History.sqlite3")
        let publicProfile = BrowserProfile(name: "Personal")
        let privateProfile = BrowserProfile.privateBrowsing()
        let entries = [
            BrowserHistoryEntry(
                profileID: publicProfile.id,
                url: URL(string: "https://user:pass@public.example/docs?view=full&token=fixture#secret")!,
                title: "Public Docs",
                lastVisitedAt: Date(timeIntervalSince1970: 10)
            ),
            BrowserHistoryEntry(
                profileID: privateProfile.id,
                url: URL(string: "https://private.example/secret?token=fixture")!,
                title: "Private",
                lastVisitedAt: Date(timeIntervalSince1970: 20)
            )
        ]
        let persistence = SQLiteLocalHistoryPersistenceStore(databaseURL: databaseURL)

        try persistence.saveHistory(entries, profiles: [publicProfile, privateProfile])

        let result = persistence.loadHistory(profiles: [publicProfile, privateProfile])
        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertNil(result.recoveryReason)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(entry.profileID, publicProfile.id)
        XCTAssertEqual(entry.url.absoluteString, "https://public.example/docs?view=full")
        XCTAssertEqual(entry.title, "Public Docs")

        let rawDatabase = try rawDatabaseText(at: databaseURL)
        for sensitiveComponent in [
            "private.example",
            "user:pass",
            "token",
            "fixture",
            "secret",
            privateProfile.id.uuidString
        ] {
            XCTAssertFalse(rawDatabase.contains(sensitiveComponent))
        }
    }

    func testLoadRepairScrubsInvalidAndDuplicateRawHistoryFromDisk() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("History.sqlite3")
        let publicProfile = BrowserProfile(name: "Personal")
        let privateProfile = BrowserProfile.privateBrowsing()
        let olderEntry = BrowserHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            profileID: publicProfile.id,
            url: URL(string: "https://user:pass@public.example/docs?view=full&token=older#frag")!,
            title: "Older Docs",
            lastVisitedAt: Date(timeIntervalSince1970: 10),
            visitCount: 2
        )
        let newerEntry = BrowserHistoryEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            profileID: publicProfile.id,
            url: URL(string: "https://public.example/docs?view=full")!,
            title: "Newer Docs",
            lastVisitedAt: Date(timeIntervalSince1970: 20),
            visitCount: 3
        )
        let privateEntry = BrowserHistoryEntry(
            profileID: privateProfile.id,
            url: URL(string: "https://private.example/secret?token=fixture")!,
            title: "Private",
            lastVisitedAt: Date(timeIntervalSince1970: 30)
        )
        let persistence = SQLiteLocalHistoryPersistenceStore(databaseURL: databaseURL)

        try writeRawHistoryRecord(
            databaseURL: databaseURL,
            schemaVersion: SQLiteLocalHistoryPersistenceStore.currentSchemaVersion,
            payload: try JSONEncoder().encode([olderEntry, newerEntry, privateEntry])
        )
        XCTAssertTrue(try rawDatabaseText(at: databaseURL).contains("private.example"))
        XCTAssertTrue(try rawDatabaseText(at: databaseURL).contains("token"))

        let result = persistence.loadHistory(profiles: [publicProfile, privateProfile])

        XCTAssertEqual(result.recoveryReason, .repairedHistory)
        let repairedEntry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(repairedEntry.id, newerEntry.id)
        XCTAssertEqual(repairedEntry.url.absoluteString, "https://public.example/docs?view=full")
        XCTAssertEqual(repairedEntry.title, "Newer Docs")
        XCTAssertEqual(repairedEntry.visitCount, 5)

        let repairedDatabase = try rawDatabaseText(at: databaseURL)
        XCTAssertTrue(repairedDatabase.contains("public.example"))
        for sensitiveComponent in [
            "private.example",
            "user:pass",
            "token",
            "fixture",
            "secret",
            privateProfile.id.uuidString
        ] {
            XCTAssertFalse(repairedDatabase.contains(sensitiveComponent))
        }
    }

    func testLoadFallsBackAndDeletesStoreWhenRepairScrubCannotComplete() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("History.sqlite3")
        let publicProfile = BrowserProfile(name: "Personal")
        let invalidEntry = BrowserHistoryEntry(
            profileID: publicProfile.id,
            url: URL(string: "https://user:pass@public.example/docs?token=fixture#frag")!,
            title: "Needs Repair"
        )
        let persistence = SQLiteLocalHistoryPersistenceStore(
            databaseURL: databaseURL,
            repairScrubInterruption: { throw HistoryRepairScrubFailure() }
        )

        try writeRawHistoryRecord(
            databaseURL: databaseURL,
            schemaVersion: SQLiteLocalHistoryPersistenceStore.currentSchemaVersion,
            payload: try JSONEncoder().encode([invalidEntry])
        )

        let result = persistence.loadHistory(profiles: [publicProfile])

        XCTAssertEqual(result.entries, [])
        XCTAssertEqual(result.recoveryReason, .unreadableStore)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("public.example") ?? true)
        XCTAssertFalse(result.recoveryReason?.userMessage?.contains("fixture") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-journal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-shm"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path + "-wal"))
    }

    func testUnsupportedAndCorruptStoresAreDeletedWithoutLeakingMessages() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unsupportedDatabaseURL = directory.appendingPathComponent("UnsupportedHistory.sqlite3")
        let corruptDatabaseURL = directory.appendingPathComponent("CorruptHistory.sqlite3")
        let profile = BrowserProfile(name: "Personal")

        try writeRawHistoryRecord(
            databaseURL: unsupportedDatabaseURL,
            schemaVersion: SQLiteLocalHistoryPersistenceStore.currentSchemaVersion + 1,
            payload: Data("https://private.example/secret?token=fixture".utf8)
        )
        let unsupportedResult = SQLiteLocalHistoryPersistenceStore(
            databaseURL: unsupportedDatabaseURL
        ).loadHistory(profiles: [profile])

        XCTAssertEqual(
            unsupportedResult.recoveryReason,
            .unsupportedSchema(SQLiteLocalHistoryPersistenceStore.currentSchemaVersion + 1)
        )
        XCTAssertFalse(unsupportedResult.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unsupportedDatabaseURL.path))

        try writeRawHistoryRecord(
            databaseURL: corruptDatabaseURL,
            schemaVersion: SQLiteLocalHistoryPersistenceStore.currentSchemaVersion,
            payload: Data("{\"url\":\"https://private.example/secret?token=fixture\"}".utf8)
        )
        let corruptResult = SQLiteLocalHistoryPersistenceStore(
            databaseURL: corruptDatabaseURL
        ).loadHistory(profiles: [profile])

        XCTAssertEqual(corruptResult.recoveryReason, .corruptPayload)
        XCTAssertFalse(corruptResult.recoveryReason?.userMessage?.contains("private.example") ?? true)
        XCTAssertFalse(corruptResult.recoveryReason?.userMessage?.contains("fixture") ?? true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptDatabaseURL.path))
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

    private func writeRawHistoryRecord(
        databaseURL: URL,
        schemaVersion: Int,
        payload: Data
    ) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

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
        guard let database else {
            return XCTFail("Expected SQLite database")
        }
        defer { sqlite3_close(database) }

        try execute(
            """
            CREATE TABLE IF NOT EXISTS local_history (
                id TEXT PRIMARY KEY NOT NULL,
                schema_version INTEGER NOT NULL,
                payload BLOB NOT NULL,
                updated_at REAL NOT NULL
            );
            """,
            database: database
        )

        let statement = try prepare(
            """
            INSERT INTO local_history (id, schema_version, payload, updated_at)
            VALUES (?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, "main", -1, sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(schemaVersion))
        let bindPayloadResult = payload.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(payload.count), sqliteTransient)
        }
        XCTAssertEqual(bindPayloadResult, SQLITE_OK)
        sqlite3_bind_double(statement, 4, 0)

        XCTAssertEqual(sqlite3_step(statement), SQLITE_DONE)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw LocalHistoryPersistenceStoreError.cannotExecuteStatement
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let preparedStatement = statement else {
            throw LocalHistoryPersistenceStoreError.cannotPrepareStatement
        }
        return preparedStatement
    }
}

private struct HistoryRepairScrubFailure: Error {}
