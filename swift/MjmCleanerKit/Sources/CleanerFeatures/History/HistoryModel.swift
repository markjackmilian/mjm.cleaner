import CleanerCore
import Foundation
import Observation

/// Una riga della tabella Storico (spec §6.2: Data · Spazio · Categorie · Elementi).
public struct HistoryRow: Identifiable, Sendable {
    public let id: Int64
    /// I timestamp sono salvati in UTC e resi in ora locale: altrimenti il cambio d'ora riordina lo storico.
    public let when: String
    public let startedAt: Date
    public let bytesFreed: Int64
    public let freed: String
    public let items: String
    public let categoryNames: [String]
    public let failed: String

    public init(session: CleanSessionSummary, names: CategoryNames, timeZone: TimeZone = .current) {
        id = session.id
        startedAt = session.startedAt
        when = Formatting.historyDate(session.startedAt, timeZone: timeZone)
        bytesFreed = session.bytesFreed
        freed = Formatting.bytes(session.bytesFreed)
        items = Formatting.integer(session.itemsDeleted)
        categoryNames = session.categories.map { names.name(for: $0.categoryId) }
        failed = session.itemsFailed == 0
            ? ""
            : String(localized: "\(String(session.itemsFailed)) falliti", bundle: .module)
    }
}

/// Porting di `HistoryViewModel`: le ultime 50 pulizie, caricate alla creazione della pagina.
@MainActor
@Observable
public final class HistoryModel {
    @ObservationIgnored private weak var navigation: (any Navigating)?

    public private(set) var rows: [HistoryRow] = []
    public private(set) var totalText = "—"
    public private(set) var countText = ""
    /// Senza sessioni la barra mostra solo «nessuna pulizia»: «0 B» davanti sarebbe rumore.
    public private(set) var hasSessions = false

    /// Il caricamento parte alla creazione, come nel costruttore C#; i test lo attendono.
    @ObservationIgnored public private(set) var initialLoad: Task<Void, Never>?

    public init(environment: AppEnvironment, navigation: (any Navigating)?) {
        self.navigation = navigation
        initialLoad = Task { await self.load(environment) }
    }

    public static func summarize(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "nessuna pulizia", bundle: .module)
        case 1: String(localized: "in 1 pulizia", bundle: .module)
        default: String(localized: "in \(String(count)) pulizie", bundle: .module)
        }
    }

    public func close() {
        navigation?.startOver()
    }

    /// Uno storico illeggibile lascia la pagina vuota, come il task C# che falliva senza effetti visibili.
    private func load(_ environment: AppEnvironment) async {
        guard let sessions = try? await environment.history.sessions(limit: 50) else { return }
        let names = CategoryNames.build(environment.categories())

        rows = sessions.map { HistoryRow(session: $0, names: names) }
        totalText = Formatting.bytes(SafeSum.total(rows.map(\.bytesFreed)))
        countText = Self.summarize(rows.count)
        hasSessions = !rows.isEmpty
    }
}
