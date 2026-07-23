import Foundation
import SQLite3

public enum LocalHistoryPersistenceRecoveryReason: Equatable, Sendable {
    case noSavedHistory
    case unreadableStore
    case corruptPayload
    case unsupportedSchema(Int)
    case repairedHistory

    public var userMessage: String? {
        switch self {
        case .noSavedHistory:
            return nil
        case .unreadableStore, .corruptPayload, .unsupportedSchema, .repairedHistory:
            return "Lumen Browser restored local history from a clean state because saved history was unavailable."
        }
    }
}

public struct LocalHistoryPersistenceLoadResult: Equatable, Sendable {
    public var entries: [BrowserHistoryEntry]
    public var recoveryReason: LocalHistoryPersistenceRecoveryReason?

    public init(
        entries: [BrowserHistoryEntry],
        recoveryReason: LocalHistoryPersistenceRecoveryReason? = nil
    ) {
        self.entries = entries
        self.recoveryReason = recoveryReason
    }
}

public enum LocalHistoryPersistenceStoreError: Error, Equatable, Sendable {
    case cannotOpenStore
    case cannotPrepareStatement
    case cannotExecuteStatement
    case cannotEncodeHistory
}

public final class SQLiteLocalHistoryPersistenceStore: LocalHistoryPersisting {
    public static let currentSchemaVersion = 1

    private static let recordID = "main"
    private static let supportDirectoryName = "Lumen Browser"
    private static let legacySupportDirectoryNames = [
        "Bare Browser",
        "Meridian Browser"
    ]
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public let databaseURL: URL
    private let fileManager: FileManager
    private let repairScrubInterruption: (() throws -> Void)?

    public init(
        databaseURL: URL = SQLiteLocalHistoryPersistenceStore.defaultDatabaseURL(),
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

        let databaseFilename = "History.sqlite3"
        let currentURL = applicationSupport
            .appendingPathComponent(supportDirectoryName, isDirectory: true)
            .appendingPathComponent(databaseFilename, isDirectory: false)

        if fileManager.fileExists(atPath: currentURL.path) {
            return currentURL
        }

        for legacySupportDirectoryName in legacySupportDirectoryNames {
            let legacyURL = applicationSupport
                .appendingPathComponent(legacySupportDirectoryName, isDirectory: true)
                .appendingPathComponent(databaseFilename, isDirectory: false)

            if fileManager.fileExists(atPath: legacyURL.path) {
                return legacyURL
            }
        }

        return currentURL
    }

    public func loadHistory(profiles: [BrowserProfile]) -> LocalHistoryPersistenceLoadResult {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return LocalHistoryPersistenceLoadResult(entries: [], recoveryReason: .noSavedHistory)
        }

        do {
            let record = try readRecord()
            guard record.schemaVersion <= Self.currentSchemaVersion else {
                try? removeStoreFiles()
                return LocalHistoryPersistenceLoadResult(
                    entries: [],
                    recoveryReason: .unsupportedSchema(record.schemaVersion)
                )
            }

            let decoded = try JSONDecoder().decode([BrowserHistoryEntry].self, from: record.payload)
            let repaired = LocalHistoryPersistenceBoundary.persistentEntries(
                from: decoded,
                profiles: profiles
            )
            let wasRepaired = repaired != decoded
            if wasRepaired {
                do {
                    try scrubRepairedRecord(with: repaired)
                } catch {
                    try? removeStoreFiles()
                    return LocalHistoryPersistenceLoadResult(entries: [], recoveryReason: .unreadableStore)
                }
            }

            return LocalHistoryPersistenceLoadResult(
                entries: repaired,
                recoveryReason: wasRepaired ? .repairedHistory : nil
            )
        } catch let error as LoadError {
            if error.removesStoreForPrivacy {
                try? removeStoreFiles()
            }
            return LocalHistoryPersistenceLoadResult(entries: [], recoveryReason: error.recoveryReason)
        } catch is DecodingError {
            try? removeStoreFiles()
            return LocalHistoryPersistenceLoadResult(entries: [], recoveryReason: .corruptPayload)
        } catch {
            try? removeStoreFiles()
            return LocalHistoryPersistenceLoadResult(entries: [], recoveryReason: .unreadableStore)
        }
    }

    public func saveHistory(_ entries: [BrowserHistoryEntry], profiles: [BrowserProfile]) throws {
        let persistentEntries = LocalHistoryPersistenceBoundary.persistentEntries(
            from: entries,
            profiles: profiles
        )
        let payload: Data
        do {
            payload = try JSONEncoder().encode(persistentEntries)
        } catch {
            throw LocalHistoryPersistenceStoreError.cannotEncodeHistory
        }

        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try withOpenDatabase(createIfNeeded: true) { database in
            try createTable(database: database)
            try execute("PRAGMA secure_delete = ON;", database: database)
            try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
            do {
                try deleteRecord(database: database)
                try write(
                    payload: payload,
                    schemaVersion: Self.currentSchemaVersion,
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

    private func readRecord() throws -> HistoryRecord {
        try withOpenDatabase(createIfNeeded: false) { database in
            try createTable(database: database)

            let statement = try prepare(
                "SELECT schema_version, payload FROM local_history WHERE id = ? LIMIT 1;",
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
                return HistoryRecord(
                    schemaVersion: schemaVersion,
                    payload: Data(bytes: bytes, count: count)
                )
            case SQLITE_DONE:
                throw LoadError.noSavedHistory
            default:
                throw LoadError.unreadableStore
            }
        }
    }

    private func scrubRepairedRecord(with entries: [BrowserHistoryEntry]) throws {
        try repairScrubInterruption?()

        let payload: Data
        do {
            payload = try JSONEncoder().encode(entries)
        } catch {
            throw LocalHistoryPersistenceStoreError.cannotEncodeHistory
        }

        try withOpenDatabase(createIfNeeded: false) { database in
            try createTable(database: database)
            try execute("PRAGMA secure_delete = ON;", database: database)
            try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
            do {
                try deleteRecord(database: database)
                try write(
                    payload: payload,
                    schemaVersion: Self.currentSchemaVersion,
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

    private func createTable(database: OpaquePointer) throws {
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
    }

    private func write(
        payload: Data,
        schemaVersion: Int,
        database: OpaquePointer
    ) throws {
        let statement = try prepare(
            """
            INSERT INTO local_history (id, schema_version, payload, updated_at)
            VALUES (?, ?, ?, ?);
            """,
            database: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, Self.recordID, -1, Self.sqliteTransient)
        sqlite3_bind_int(statement, 2, Int32(schemaVersion))
        let bindPayloadResult = payload.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, 3, buffer.baseAddress, Int32(payload.count), Self.sqliteTransient)
        }
        guard bindPayloadResult == SQLITE_OK else {
            throw LocalHistoryPersistenceStoreError.cannotExecuteStatement
        }
        sqlite3_bind_double(statement, 4, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalHistoryPersistenceStoreError.cannotExecuteStatement
        }
    }

    private func deleteRecord(database: OpaquePointer) throws {
        let statement = try prepare(
            "DELETE FROM local_history WHERE id = ?;",
            database: database
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, Self.recordID, -1, Self.sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalHistoryPersistenceStoreError.cannotExecuteStatement
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
                ? LocalHistoryPersistenceStoreError.cannotOpenStore
                : LoadError.unreadableStore
        }

        defer { sqlite3_close(openedDatabase) }
        return try operation(openedDatabase)
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

    private struct HistoryRecord {
        var schemaVersion: Int
        var payload: Data
    }

    private enum LoadError: Error {
        case noSavedHistory
        case unreadableStore
        case corruptPayload

        var recoveryReason: LocalHistoryPersistenceRecoveryReason {
            switch self {
            case .noSavedHistory:
                return .noSavedHistory
            case .unreadableStore:
                return .unreadableStore
            case .corruptPayload:
                return .corruptPayload
            }
        }

        var removesStoreForPrivacy: Bool {
            switch self {
            case .noSavedHistory:
                return false
            case .unreadableStore, .corruptPayload:
                return true
            }
        }
    }
}
