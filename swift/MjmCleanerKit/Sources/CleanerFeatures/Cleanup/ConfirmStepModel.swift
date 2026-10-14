import CleanerCore
import Observation

/// Una riga selezionabile: un singolo `ScanItem`, non la root della regola che lo ha prodotto.
/// Raggruppare per `declaredRoot` mostrerebbe una sola casella per migliaia di elementi (la root
/// delle regole a svuotamento — `~/Library/Caches`, `$TMPDIR` — sopravvive comunque alla pulizia,
/// quindi quella casella nominerebbe qualcosa che non verrà mai cancellato) e renderebbe la
/// granularità di deselezione qui identica a quella del passo 1, vanificando questo passo come
/// rete di sicurezza.
@MainActor
@Observable
public final class PathNode: Identifiable {
    public let item: ScanItem
    public var isSelected = true

    init(item: ScanItem) {
        self.item = item
    }

    public var path: String { item.path }
    public var sizeBytes: Int64 { item.sizeBytes }
    public var sizeText: String { Formatting.bytes(item.sizeBytes) }
}

@MainActor
@Observable
public final class CategoryNode: Identifiable {
    public let categoryId: String
    public let displayName: String
    public let paths: [PathNode]

    /// Il totale della categoria, visibile a colpo d'occhio prima di espandere: conteggio e
    /// dimensione di tutte le righe trovate, selezionate o no.
    public let summaryText: String

    init(categoryId: String, displayName: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.displayName = displayName
        paths = items.map(PathNode.init)
        let noun = Formatting.plural(items.count, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        summaryText = "\(Formatting.integer(items.count)) \(noun) · \(Formatting.bytes(SafeSum.total(items.map(\.sizeBytes))))"
    }
}

/// Porting di `ConfirmStepViewModel`: passo 3, anteprima con deselezioni puntuali ed eliminazione.
@MainActor
@Observable
public final class ConfirmStepModel {
    /// Oltre questo numero di nomi l'avviso diventa illeggibile proprio nel passo in cui l'utente deve decidere.
    private static let maxRunningAppNamesShown = 5

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private weak var navigation: (any CleanupNavigating)?
    @ObservationIgnored private var deleteTask: Task<CleanReport, Never>?

    public let nodes: [CategoryNode]

    /// Elenco di ciò che le protezioni hanno tolto d'ufficio: se un totale non torna, qui se ne
    /// trova il motivo.
    public let exclusionsText: String

    public private(set) var isDeleting = false

    /// Aggiornato dall'avanzamento reale del motore di pulizia durante l'eliminazione.
    public private(set) var deleteProgressText = ""

    /// Vuoto finché la sonda non ha risposto: viene popolato in modo asincrono, fuori dal main
    /// actor, perché avvia un processo esterno (`ps`) che in uno scenario patologico può impiegare
    /// fino a una decina di secondi. La schermata resta utilizzabile nel frattempo.
    public private(set) var runningAppsWarning = ""

    @ObservationIgnored public private(set) var runningAppsCheck: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        navigation: (any CleanupNavigating)?,
        categories: [CleanupCategory],
        results: [CategoryScanResult]
    ) {
        self.environment = environment
        self.navigation = navigation

        // Una riga per PERCORSO, non per ScanItem, e la deduplicazione è GLOBALE a tutto il passo:
        // due regole, anche di categorie diverse, possono coprire lo stesso file. La logica vive
        // nel Core (ConfirmationRows), pura e testata; qui si trasforma in nodi.
        nodes = ConfirmationRows.build(results).map { row in
            let name = categories.first { FeatureText.same($0.id, row.categoryId) }?.displayName ?? row.categoryId
            return CategoryNode(categoryId: row.categoryId, displayName: name, items: row.items)
        }

        let exclusions = results.flatMap(\.exclusions)
        if exclusions.isEmpty {
            exclusionsText = ""
        } else {
            let noun = Formatting.plural(
                exclusions.count,
                String(localized: "elemento escluso", bundle: .module),
                String(localized: "elementi esclusi", bundle: .module))
            let header = String(localized: "\(String(exclusions.count)) \(noun) dalle protezioni:", bundle: .module)
            let lines = exclusions.prefix(5).map { "· \($0.path) — \($0.reason)" }
            exclusionsText = ([header] + lines).joined(separator: "\n")
        }

        let scannedPaths = Array(results.lazy.flatMap(\.items).prefix(2000).map(\.path))
        runningAppsCheck = Task { await self.computeRunningAppsWarning(scannedPaths) }
    }

    private var selectedNodes: [PathNode] {
        nodes.flatMap { $0.paths.filter(\.isSelected) }
    }

    public var totalText: String {
        let selected = selectedNodes
        let noun = Formatting.plural(selected.count, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        return "\(Formatting.bytes(SafeSum.total(selected.map(\.sizeBytes)))) · \(Formatting.integer(selected.count)) \(noun)"
    }

    public var canDelete: Bool {
        !isDeleting && nodes.contains { $0.paths.contains(where: \.isSelected) }
    }

    public var canCancelDelete: Bool { isDeleting }

    public func delete() async {
        guard canDelete else { return }
        isDeleting = true

        let selections = nodes
            .map { CategorySelection(categoryId: $0.categoryId, items: $0.paths.filter(\.isSelected).map(\.item)) }
            .filter { !$0.items.isEmpty }

        // Il diario si apre prima della pulizia e passa al passo 4, che lo scarta solo dopo aver
        // scritto il log di sessione (spec §8.2): dopo un arresto resta leggibile in logs/.
        let journal = environment.sessionLog.openJournal(startedAt: environment.clock.now)
        let relay = ProgressRelay<CleanProgress> { [weak self] in self?.applyDeleteProgress($0) }
        let clean = environment.clean
        let report = relay.report
        let task = Task { await clean.clean(selections, progress: report, journal: journal) }
        deleteTask = task

        // CleanEngine non lancia sull'annullamento: restituisce un resoconto parziale, che va
        // comunque al passo 4 e comunque nello storico — ciò che è già stato cancellato deve
        // risultare, annullamento o non annullamento.
        let result = await task.value
        await relay.finish()
        deleteTask = nil

        navigation?.showDone(result, journal: journal)
        isDeleting = false
    }

    public func cancelDelete() {
        deleteTask?.cancel()
    }

    /// Deliberatamente non «Indietro»: ricomincia dal passo 1 (la selezione resta ricordata nelle
    /// impostazioni) invece di tornare al passo 2 conservando questa analisi.
    public func restart() {
        navigation?.startOver()
    }

    private func applyDeleteProgress(_ progress: CleanProgress) {
        let noun = Formatting.plural(progress.itemsTotal, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        deleteProgressText = "\(Formatting.integer(progress.itemsDone)) / \(Formatting.integer(progress.itemsTotal)) \(noun) · \(Formatting.bytes(progress.bytesFreed))"
    }

    /// Un fallimento della sonda non deve mai impedire la pulizia: l'avviso resta vuoto (la sonda
    /// del Core non lancia).
    private func computeRunningAppsWarning(_ scannedPaths: [String]) async {
        let affected = await environment.runningApps.affectedApps(scannedPaths)
        runningAppsWarning = Self.runningAppsText(affected)
    }

    static func runningAppsText(_ affected: [String]) -> String {
        guard !affected.isEmpty else { return "" }

        let shown = affected.prefix(maxRunningAppNamesShown).joined(separator: ", ")
        let remaining = affected.count - maxRunningAppNamesShown
        let suffix = switch remaining {
        case ...0: ""
        case 1: String(localized: " e un'altra", bundle: .module)
        default: String(localized: " e altre \(String(remaining))", bundle: .module)
        }

        let cacheClause = affected.count == 1
            ? String(localized: "la sua cache potrebbe rigenerarsi subito", bundle: .module)
            : String(localized: "le loro cache potrebbero rigenerarsi subito", bundle: .module)

        return String(localized: "\(shown)\(suffix) in esecuzione: \(cacheClause).", bundle: .module)
    }
}
