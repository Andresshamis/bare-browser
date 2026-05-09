import Foundation
import SQLite3

public enum SessionPersistenceRecoveryReason: Equatable, Sendable {
    case noSavedSession
    case unreadableStore
    case corruptPayload
    case unsupportedSchema(Int)
    case repairedSnapshot

    public var userMessage: String? {
        switch self {
        case .noSavedSession:
            return nil
        case .unreadableStore, .corruptPayload, .unsupportedSchema, .repairedSnapshot:
            return "Meridian restored a clean browser session because saved session state was unavailable."
        }
    }
}

public struct SessionPersistenceLoadResult: Equatable, Sendable {
    public var snapshot: BrowserSessionSnapshot
    public var recoveryReason: SessionPersistenceRecoveryReason?

    public init(
        snapshot: BrowserSessionSnapshot,
        recoveryReason: SessionPersistenceRecoveryReason? = nil
    ) {
        self.snapshot = snapshot
        self.recoveryReason = recoveryReason
    }
}

public enum SessionPersistenceStoreError: Error, Equatable, Sendable {
    case cannotOpenStore
    case cannotPrepareStatement
    case cannotExecuteStatement
    case cannotEncodeSnapshot
}

public final class SQLiteSessionPersistenceStore: SessionSnapshotPersisting {
    public static let currentSchemaVersion = 1

    private static let recordID = "main"
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public let databaseURL: URL
    private let fileManager: FileManager
    private let repairScrubInterruption: (() throws -> Void)?

    public init(
        databaseURL: URL = SQLiteSessionPersistenceStore.defaultDatabaseURL(),
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.repairScrubInterruption = nil
    }

    init(
        databaseURL: URL,
        fileManager: FileManager = .default,
        repairScrubInterruption: @escaping () throws -> Void
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.repairScrubInterruption = repairScrubInterruption
    }

    public static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("Meridian Browser", isDirectory: true)
            .appendingPathComponent("Session.sqlite3", isDirectory: false)
    }

    public func loadSnapshot(
        fallback: BrowserSessionSnapshot = SessionSnapshotFactory.initial()
    ) -> SessionPersistenceLoadResult {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return SessionPersistenceLoadResult(snapshot: fallback, recoveryReason: .noSavedSession)
        }

        do {
            let record = try readRecord()
            guard record.schemaVersion <= Self.currentSchemaVersion else {
                try? removeStoreFiles()
                return SessionPersistenceLoadResult(
                    snapshot: fallback,
                    recoveryReason: .unsupportedSchema(record.schemaVersion)
                )
            }

            let decoded = try JSONDecoder().decode(BrowserSessionSnapshot.self, from: record.payload)
            let repaired = SessionPersistenceBoundary.persistentSnapshot(
                from: decoded,
                fallback: fallback
            )
            let wasRepaired = repaired != decoded
            if wasRepaired {
                do {
                    try scrubRepairedRecord(with: repaired)
                } catch {
                    try? removeStoreFiles()
                    return SessionPersistenceLoadResult(
                        snapshot: fallback,
                        recoveryReason: .unreadableStore
                    )
                }
            }

            return SessionPersistenceLoadResult(
                snapshot: repaired,
                recoveryReason: wasRepaired ? .repairedSnapshot : nil
            )
        } catch let error as LoadError {
            if error.removesStoreForPrivacy {
                try? removeStoreFiles()
            }
            return SessionPersistenceLoadResult(snapshot: fallback, recoveryReason: error.recoveryReason)
        } catch is DecodingError {
            try? removeStoreFiles()
            return SessionPersistenceLoadResult(snapshot: fallback, recoveryReason: .corruptPayload)
        } catch {
            try? removeStoreFiles()
            return SessionPersistenceLoadResult(snapshot: fallback, recoveryReason: .unreadableStore)
        }
    }

    public func saveSnapshot(
        _ snapshot: BrowserSessionSnapshot,
        fallback: BrowserSessionSnapshot = SessionSnapshotFactory.initial()
    ) throws {
        var persistentSnapshot = SessionPersistenceBoundary.persistentSnapshot(
            from: snapshot,
            fallback: fallback
        )
        persistentSnapshot.schemaVersion = Self.currentSchemaVersion

        let payload: Data
        do {
            payload = try JSONEncoder().encode(persistentSnapshot)
        } catch {
            throw SessionPersistenceStoreError.cannotEncodeSnapshot
        }

        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try withOpenDatabase(createIfNeeded: true) { database in
            try execute(
                """
                CREATE TABLE IF NOT EXISTS session_snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    schema_version INTEGER NOT NULL,
                    captured_at REAL NOT NULL,
                    payload BLOB NOT NULL,
                    updated_at REAL NOT NULL
                );
                """,
                database: database
            )

            try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
            do {
                try write(
                    payload: payload,
                    schemaVersion: persistentSnapshot.schemaVersion,
                    capturedAt: persistentSnapshot.capturedAt,
                    database: database
                )
                try execute("COMMIT;", database: database)
            } catch {
                try? execute("ROLLBACK;", database: database)
                throw error
            }
        }
    }

    private func readRecord() throws -> SessionRecord {
        try withOpenDatabase(createIfNeeded: false) { database in
            try execute(
                """
                CREATE TABLE IF NOT EXISTS session_snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    schema_version INTEGER NOT NULL,
                    captured_at REAL NOT NULL,
                    payload BLOB NOT NULL,
                    updated_at REAL NOT NULL
                );
                """,
                database: database
            )

            let statement = try prepare(
                "SELECT schema_version, payload FROM session_snapshots WHERE id = ? LIMIT 1;",
                database: database
            )
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, Self.recordID, -1, Self.sqliteTransient)

            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let schemaVersion = Int(sqlite3_column_int(statement, 0))
                guard let bytes = sqlite3_column_blob(statement, 1) else {
                    throw LoadError.corruptPayload
                }
                let count = Int(sqlite3_column_bytes(statement, 1))
                return SessionRecord(
                    schemaVersion: schemaVersion,
                    payload: Data(bytes: bytes, count: count)
                )
            case SQLITE_DONE:
                throw LoadError.noSavedSession
            default:
                throw LoadError.unreadableStore
            }
        }
    }

    private func scrubRepairedRecord(with snapshot: BrowserSessionSnapshot) throws {
        try repairScrubInterruption?()

        var repairedSnapshot = snapshot
        repairedSnapshot.schemaVersion = Self.currentSchemaVersion

        let payload: Data
        do {
            payload = try JSONEncoder().encode(repairedSnapshot)
        } catch {
            throw SessionPersistenceStoreError.cannotEncodeSnapshot
        }

        try withOpenDatabase(createIfNeeded: false) { database in
            try execute("PRAGMA secure_delete = ON;", database: database)
            try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
            do {
                try deleteRecord(database: database)
                try write(
                    payload: payload,
                    schemaVersion: repairedSnapshot.schemaVersion,
                    capturedAt: repairedSnapshot.capturedAt,
                    database: database
                )
                try execute("COMMIT;", database: database)
            } catch {
                try? execute("ROLLBACK;", database: database)
                throw error
            }

            try execute("VACUUM;", database: database)
            try execute("PRAGMA wal_checkpoint(TRUNCATE);", database: database)
        }
    }

    private func write(
        payload: Data,
        schemaVersion: Int,
        capturedAt: Date,
        database: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO session_snapshots (id, schema_version, captured_at, payload, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                schema_version = excluded.schema_version,
                captured_at = excluded.captured_at,
                payload = excluded.payload,
                updated_at = excluded.updated_at;
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, Self.recordID, -1, Self.sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(schemaVersion))
        sqlite3_bind_double(statement, 3, capturedAt.timeIntervalSince1970)
        let bindPayloadResult = payload.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 4, buffer.baseAddress, Int32(payload.count), Self.sqliteTransient)
        }
        guard bindPayloadResult == SQLITE_OK else {
            throw SessionPersistenceStoreError.cannotExecuteStatement
        }
        sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SessionPersistenceStoreError.cannotExecuteStatement
        }
    }

    private func deleteRecord(database: OpaquePointer) throws {
        let statement = try prepare(
            "DELETE FROM session_snapshots WHERE id = ?;",
            database: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, Self.recordID, -1, Self.sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SessionPersistenceStoreError.cannotExecuteStatement
        }
    }

    private func removeStoreFiles() throws {
        for url in storeFileURLs {
            guard fileManager.fileExists(atPath: url.path) else {
                continue
            }
            try fileManager.removeItem(at: url)
        }
    }

    private var storeFileURLs: [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-journal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-wal")
        ]
    }

    private func withOpenDatabase<T>(
        createIfNeeded: Bool,
        operation: (OpaquePointer) throws -> T
    ) throws -> T {
        var database: OpaquePointer?
        let flags = createIfNeeded
            ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX

        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK,
              let openedDatabase = database else {
            if let database {
                sqlite3_close(database)
            }
            throw createIfNeeded
                ? SessionPersistenceStoreError.cannotOpenStore
                : LoadError.unreadableStore
        }

        defer { sqlite3_close(openedDatabase) }
        return try operation(openedDatabase)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SessionPersistenceStoreError.cannotExecuteStatement
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let preparedStatement = statement else {
            throw SessionPersistenceStoreError.cannotPrepareStatement
        }
        return preparedStatement
    }

    private struct SessionRecord {
        var schemaVersion: Int
        var payload: Data
    }

    private enum LoadError: Error {
        case noSavedSession
        case unreadableStore
        case corruptPayload

        var recoveryReason: SessionPersistenceRecoveryReason {
            switch self {
            case .noSavedSession:
                return .noSavedSession
            case .unreadableStore:
                return .unreadableStore
            case .corruptPayload:
                return .corruptPayload
            }
        }

        var removesStoreForPrivacy: Bool {
            switch self {
            case .noSavedSession:
                return false
            case .unreadableStore, .corruptPayload:
                return true
            }
        }
    }
}
