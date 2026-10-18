import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Le prove di `HistoryViewTests.cs` che riguardano il modello. Quelle sull'albero visuale
/// (toolbar, chevron, stile delle intestazioni) passano alla verifica dell'app (piano 4b, spec §9.4).
@MainActor
struct HistoryViewTests {
    @Test func emptyHistoryShowsOnlyNessunaPulizia() async throws {
        let home = try await TestHome.create()
        defer { home.remove() }
        let model = HistoryModel(environment: home.environment, navigation: nil)
        await model.initialLoad?.value

        #expect(!model.hasSessions)
        #expect(model.countText == "nessuna pulizia")
        #expect(model.totalText == "0 B")
    }

    @Test func amountIsVisibleWhenThereAreSessions() async throws {
        let history = FakeHistory()
        history.setSessions([
            CleanSessionSummary(
                id: 3, startedAt: Date(timeIntervalSince1970: 1_790_000_000), duration: .seconds(2),
                bytesFreed: 1_288_490_189, itemsDeleted: 10, itemsFailed: 0, categories: []),
        ])
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: nil)
        await model.initialLoad?.value

        #expect(model.hasSessions)
        #expect(model.totalText == "1,2 GB")
        #expect(model.countText == "in 1 pulizia")
    }

    // Solo Swift: totale senza trap, nomi del catalogo, righe falliti, chiusura e storico illeggibile.
    @Test func sessionsAreListedWithNamesAndASaturatedTotal() async throws {
        let history = FakeHistory()
        history.setSessions([
            CleanSessionSummary(
                id: 2, startedAt: Date(timeIntervalSince1970: 1_790_000_000), duration: .seconds(1),
                bytesFreed: Int64.max, itemsDeleted: 1, itemsFailed: 3,
                categories: [CategoryCleanResult(categoryId: "logs", bytesFreed: 1, itemsDeleted: 1)]),
            CleanSessionSummary(
                id: 1, startedAt: Date(timeIntervalSince1970: 1_780_000_000), duration: .seconds(1),
                bytesFreed: 1024, itemsDeleted: 1, itemsFailed: 0, categories: []),
        ])
        let navigation = NavigationSpy()
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: navigation)
        await model.initialLoad?.value

        #expect(model.rows.map(\.id) == [2, 1])
        #expect(model.rows.first?.categoryNames == ["Log e crash report"])
        #expect(model.rows.first?.failed == "3 falliti")
        #expect(model.rows.last?.failed == "")
        #expect(model.totalText == "8388608 TB")
        #expect(model.countText == "in 2 pulizie")

        model.close()
        #expect(navigation.events == ["startOver"])
    }

    /// Solo Swift (fix wave finale del 4b): la colonna Data della `Table` si ordina per `startedAt`, non
    /// per il testo della data.
    @Test func rowsKeepTheSessionStartForSorting() async throws {
        let later = Date(timeIntervalSince1970: 1_790_000_000)
        let earlier = Date(timeIntervalSince1970: 1_780_000_000)
        let history = FakeHistory()
        history.setSessions([
            CleanSessionSummary(id: 2, startedAt: later, duration: .seconds(1), bytesFreed: 1, itemsDeleted: 1, itemsFailed: 0, categories: []),
            CleanSessionSummary(id: 1, startedAt: earlier, duration: .seconds(1), bytesFreed: 1, itemsDeleted: 1, itemsFailed: 0, categories: []),
        ])
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: nil)
        await model.initialLoad?.value

        #expect(model.rows.map(\.startedAt) == [later, earlier])
    }

    @Test func unreadableHistoryLeavesThePageEmpty() async throws {
        let history = FakeHistory()
        history.failReads(with: UnexpectedTestError(description: "database bloccato"))
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: nil)
        await model.initialLoad?.value

        #expect(model.rows.isEmpty)
        #expect(model.totalText == "—")
        #expect(model.countText == "")
        #expect(!model.hasSessions)
    }
}
