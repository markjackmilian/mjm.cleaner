import Foundation
import Testing
@testable import CleanerCore

/// Test di integrazione su un database SQLite reale in una cartella temporanea, come in C#.
struct HistoryStoreTests {
    private func report(_ bytes: Int64, deleted: Int = 1, failed: Int = 0, _ categories: CategoryCleanResult...) -> CleanReport {
        CleanReport(
            startedAt: utc(2026, 9, 15, 10, 30),
            duration: .seconds(38),
            bytesFreed: bytes,
            itemsDeleted: deleted,
            itemsFailed: failed,
            categories: categories.isEmpty ? [CategoryCleanResult(categoryId: "caches", bytesFreed: bytes, itemsDeleted: deleted)] : categories,
            errors: [],
            deletedPaths: [])
    }

    @Test func initializeCreatesSchemaAndIsIdempotent() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let databaseFile = tmp.path + "/dati/history.db"
        let store = HistoryStore(databaseFile: databaseFile)

        try await store.initialize()
        try await store.initialize()

        #expect(FileManager.default.fileExists(atPath: databaseFile))
        #expect(try await store.totalBytesFreed() == 0)
    }

    @Test func saveThenReadBackSession() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        let id = try await store.save(report(1_500))

        let sessions = try await store.sessions(limit: 10)
        let session = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(session.id == id)
        #expect(session.bytesFreed == 1_500)
        #expect(session.duration == .seconds(38))
        #expect(session.startedAt == utc(2026, 9, 15, 10, 30))
        #expect(session.categories.map(\.categoryId) == ["caches"])
    }

    @Test func totalIsTheSumOfAllSessions() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        _ = try await store.save(report(1_000))
        _ = try await store.save(report(2_500))

        #expect(try await store.totalBytesFreed() == 3_500)
    }

    @Test func sessionsAreReturnedNewestFirstAndLimited() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        let first = try await store.save(report(10))
        let second = try await store.save(report(20))
        let third = try await store.save(report(30))

        let sessions = try await store.sessions(limit: 2)

        #expect(sessions.map(\.id) == [third, second])
        #expect(!sessions.contains { $0.id == first })
    }

    @Test func categoryBreakdownIsPersisted() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        _ = try await store.save(report(300, deleted: 3, failed: 0,
                                        CategoryCleanResult(categoryId: "caches", bytesFreed: 100, itemsDeleted: 1),
                                        CategoryCleanResult(categoryId: "logs", bytesFreed: 200, itemsDeleted: 2)))

        let session = try #require(try await store.sessions(limit: 1).first)
        #expect(session.categories.count == 2)
        #expect(session.categories.first { $0.categoryId == "logs" }?.bytesFreed == 200)
    }

    @Test func failedItemsAreRecorded() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        _ = try await store.save(report(10, deleted: 1, failed: 4))

        #expect(try await store.sessions(limit: 1).first?.itemsFailed == 4)
    }
}
