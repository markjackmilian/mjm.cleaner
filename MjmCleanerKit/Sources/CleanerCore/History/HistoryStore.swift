import Foundation
import SQLite3

public struct CleanSessionSummary: Sendable, Equatable {
    public let id: Int64
    public let startedAt: Date
    public let duration: Duration
    public let bytesFreed: Int64
    public let itemsDeleted: Int
    public let itemsFailed: Int
    public let categories: [CategoryCleanResult]

    public init(id: Int64, startedAt: Date, duration: Duration, bytesFreed: Int64, itemsDeleted: Int, itemsFailed: Int, categories: [CategoryCleanResult]) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
        self.itemsFailed = itemsFailed
        self.categories = categories
    }
}

public protocol HistoryStoring: Sendable {
    func initialize() async throws
    func save(_ report: CleanReport) async throws -> Int64
    func sessions(limit: Int) async throws -> [CleanSessionSummary]
    func totalBytesFreed() async throws -> Int64
}

/// Storico delle pulizie su SQLite. Il dettaglio per elemento NON va qui ma nel log di sessione:
/// una pulizia delle cache tocca centinaia di migliaia di file.
public actor HistoryStore: HistoryStoring {
    private static let schemaVersion = 1
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private let databaseFile: String

    public init(databaseFile: String) {
        self.databaseFile = databaseFile
    }

    public func initialize() throws {
        if let directory = PathText.parent(databaseFile), !directory.isEmpty {
            try LocalFileSystem().createDirectory(directory)
        }

        try SQLiteDatabase(path: databaseFile).execute("""
            CREATE TABLE IF NOT EXISTS CleanSession (
              Id           INTEGER PRIMARY KEY AUTOINCREMENT,
              StartedAtUtc TEXT    NOT NULL,
              DurationMs   INTEGER NOT NULL,
              BytesFreed   INTEGER NOT NULL,
              ItemsDeleted INTEGER NOT NULL,
              ItemsFailed  INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS SessionCategory (
              SessionId    INTEGER NOT NULL REFERENCES CleanSession(Id) ON DELETE CASCADE,
              CategoryId   TEXT    NOT NULL,
              BytesFreed   INTEGER NOT NULL,
              ItemsDeleted INTEGER NOT NULL,
              PRIMARY KEY (SessionId, CategoryId)
            );

            PRAGMA user_version = \(Self.schemaVersion);
            """)
    }

    public func save(_ report: CleanReport) throws -> Int64 {
        let database = try SQLiteDatabase(path: databaseFile)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.query(
                "INSERT INTO CleanSession (StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed) VALUES (?, ?, ?, ?, ?);",
                [
                    .text(report.startedAt.formatted(Self.timestampStyle)),
                    .integer(Self.milliseconds(report.duration)),
                    .integer(report.bytesFreed),
                    .integer(Int64(report.itemsDeleted)),
                    .integer(Int64(report.itemsFailed)),
                ])
            let sessionId = database.lastInsertRowId

            for category in report.categories {
                try database.query(
                    "INSERT INTO SessionCategory (SessionId, CategoryId, BytesFreed, ItemsDeleted) VALUES (?, ?, ?, ?);",
                    [.integer(sessionId), .text(category.categoryId), .integer(category.bytesFreed), .integer(Int64(category.itemsDeleted))])
            }

            try database.execute("COMMIT;")
            return sessionId
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    public func sessions(limit: Int) throws -> [CleanSessionSummary] {
        let database = try SQLiteDatabase(path: databaseFile)

        var categories: [Int64: [CategoryCleanResult]] = [:]
        let categoryRows = try database.query(
            """
            SELECT SessionId, CategoryId, BytesFreed, ItemsDeleted
            FROM SessionCategory
            WHERE SessionId IN (SELECT Id FROM CleanSession ORDER BY Id DESC LIMIT ?);
            """,
            [.integer(Int64(limit))])
        for row in categoryRows {
            guard row.count == 4,
                  let sessionId = row[0].integer, let categoryId = row[1].text,
                  let bytes = row[2].integer, let deleted = row[3].integer else {
                throw Self.malformedRow()
            }
            categories[sessionId, default: []].append(CategoryCleanResult(categoryId: categoryId, bytesFreed: bytes, itemsDeleted: Int(deleted)))
        }

        let sessionRows = try database.query(
            """
            SELECT Id, StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed
            FROM CleanSession
            ORDER BY Id DESC
            LIMIT ?;
            """,
            [.integer(Int64(limit))])

        return try sessionRows.map { row in
            guard row.count == 6,
                  let id = row[0].integer, let startedText = row[1].text, let durationMs = row[2].integer,
                  let bytes = row[3].integer, let deleted = row[4].integer, let failed = row[5].integer else {
                throw Self.malformedRow()
            }
            return CleanSessionSummary(
                id: id,
                startedAt: try Self.timestampStyle.parse(startedText),
                duration: .milliseconds(durationMs),
                bytesFreed: bytes,
                itemsDeleted: Int(deleted),
                itemsFailed: Int(failed),
                categories: categories[id] ?? [])
        }
    }

    /// Somma calcolata, non un contatore memorizzato: un contatore prima o poi diverge dalle righe.
    public func totalBytesFreed() throws -> Int64 {
        let rows = try SQLiteDatabase(path: databaseFile).query("SELECT COALESCE(SUM(BytesFreed), 0) FROM CleanSession;")
        guard let total = rows.first?.first?.integer else { throw Self.malformedRow() }
        return total
    }

    /// Millisecondi interi, troncati come `(long)TimeSpan.TotalMilliseconds` in C#.
    private static func milliseconds(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    }

    private static func malformedRow() -> SQLiteError {
        SQLiteError(code: SQLITE_MISMATCH, description: String(localized: "riga dello storico non valida", bundle: .module))
    }
}
