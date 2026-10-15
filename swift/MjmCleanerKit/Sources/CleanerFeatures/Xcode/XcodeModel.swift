import CleanerCore
import Observation

/// Una risorsa Xcode selezionabile. L'identità della riga è l'oggetto, non il candidato: due
/// candidati non si confrontano mai con `==` per decidere (registro del piano 3).
@MainActor
@Observable
public final class XcodeRow: Identifiable {
    public let candidate: XcodeCandidate
    @ObservationIgnored fileprivate var onSelectionChanged: (@MainActor () -> Void)?

    public var isSelected = false {
        didSet {
            if isSelected != oldValue { onSelectionChanged?() }
        }
    }

    init(candidate: XcodeCandidate) {
        self.candidate = candidate
    }

    public var name: String { candidate.name }
    public var sizeText: String { candidate.sizeBytes.map(Formatting.bytes) ?? String(localized: "non disponibile", bundle: .module) }
    public var identityText: String { candidate.path ?? candidate.cliId ?? candidate.key }
    public var stateText: String { candidate.blockReason ?? candidate.state ?? "" }
    public var hasState: Bool { !stateText.isEmpty }
    public var canSelect: Bool { candidate.canSelect }
}

@MainActor
@Observable
public final class XcodeGroupNode: Identifiable {
    public let kind: XcodeResourceKind
    public let rows: [XcodeRow]
    public let warnings: [String]
    @ObservationIgnored fileprivate var onSelectionChanged: (@MainActor () -> Void)?
    @ObservationIgnored private var syncing = false

    /// Solo le cache (DerivedData, Device Support) si selezionano in gruppo: simulatori e runtime
    /// si scelgono uno per uno.
    public var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            if !syncing && showGroupCheckBox {
                syncing = true
                for row in rows where row.canSelect {
                    row.isSelected = isSelected
                }
                syncing = false
            }
            onSelectionChanged?()
        }
    }

    public init(kind: XcodeResourceKind, candidates: [XcodeCandidate], warnings: [String]) {
        self.kind = kind
        rows = candidates.map(XcodeRow.init)
        self.warnings = warnings
        for row in rows {
            row.onSelectionChanged = { [weak self] in self?.rowChanged() }
        }
    }

    public var title: String {
        switch kind {
        case .derivedData: String(localized: "DerivedData", bundle: .module)
        case .deviceSupport: String(localized: "Device Support", bundle: .module)
        case .device: String(localized: "Dispositivi simulati", bundle: .module)
        case .runtime: String(localized: "Runtime iOS, watchOS, tvOS e visionOS", bundle: .module)
        }
    }

    public var isExpanded: Bool { kind == .derivedData || kind == .deviceSupport }
    public var showGroupCheckBox: Bool { kind == .derivedData || kind == .deviceSupport }

    /// Le dimensioni sono stime: quelle ignote non diventano «0 B» e si contano a parte.
    public var summary: String {
        let known = rows.compactMap(\.candidate.sizeBytes)
        let unknownCount = rows.count - known.count
        var size = known.isEmpty
            ? String(localized: "dimensioni non disponibili", bundle: .module)
            : String(localized: "\(Formatting.bytes(SafeSum.total(known))) stimati noti", bundle: .module)
        if !known.isEmpty && unknownCount > 0 {
            size += unknownCount == 1
                ? String(localized: " · 1 dimensione non disponibile", bundle: .module)
                : String(localized: " · \(String(unknownCount)) dimensioni non disponibili", bundle: .module)
        }
        return rows.isEmpty
            ? String(localized: "0 voci", bundle: .module)
            : String(localized: "\(Formatting.integer(rows.count)) voci · \(size)", bundle: .module)
    }

    private func rowChanged() {
        onSelectionChanged?()
        guard !syncing && showGroupCheckBox else { return }
        let selectable = rows.filter(\.canSelect)
        syncing = true
        isSelected = !selectable.isEmpty && selectable.allSatisfy(\.isSelected)
        syncing = false
    }
}

/// Porting di `XcodeViewModel`: analisi, selezione, anteprima obbligatoria, conferma finale ed
/// esecuzione. Mentre elimina, la finestra principale blocca la navigazione (`isDeleting`).
@MainActor
@Observable
public final class XcodeModel {
    @ObservationIgnored private let xcode: any XcodeCleanupServing
    @ObservationIgnored private let history: any HistoryStoring
    @ObservationIgnored private let sessionLog: any SessionLogWriting
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private weak var navigation: (any XcodeNavigating)?
    @ObservationIgnored private var deleteTask: Task<XcodeCleanResult, Never>?
    @ObservationIgnored private var snapshot: XcodeSnapshot?
    @ObservationIgnored private var executionStarted = false

    public private(set) var isLoading = true
    public private(set) var isDeleting = false
    public private(set) var errorText = ""
    public private(set) var warningText = ""
    public private(set) var progressText = ""
    public var acknowledgeDependencies = false
    public private(set) var confirmation: XcodeConfirmation?
    public private(set) var currentReport: XcodeReportModel?
    public private(set) var groups: [XcodeGroupNode] = []

    @ObservationIgnored public private(set) var initialLoad: Task<Void, Never>?

    public init(
        xcode: any XcodeCleanupServing,
        history: any HistoryStoring,
        sessionLog: any SessionLogWriting,
        clock: any WallClock,
        navigation: (any XcodeNavigating)?
    ) {
        self.xcode = xcode
        self.history = history
        self.sessionLog = sessionLog
        self.clock = clock
        self.navigation = navigation
        initialLoad = Task { await self.load() }
    }

    public var hasError: Bool { !errorText.isEmpty }
    public var hasWarnings: Bool { !warningText.isEmpty }
    public var hasConfirmation: Bool { confirmation != nil }
    public var hasRetainedDependencies: Bool { !(confirmation?.retainedDependentDevices.isEmpty ?? true) }
    public var hasSelectedDevices: Bool { confirmation?.selectedCandidates.contains { $0.kind == .device } ?? false }
    public var hasSelectedRuntimes: Bool { confirmation?.selectedCandidates.contains { $0.kind == .runtime } ?? false }

    public var previewSummaryText: String {
        guard let confirmation else { return "" }
        return String(localized: "Risorse selezionate: \(String(confirmation.selectedCandidates.count))", bundle: .module)
    }

    public var previewEstimateText: String {
        guard let confirmation else { return "" }
        let unknown = confirmation.unknownSizeCount > 0
            ? String(localized: " · \(String(confirmation.unknownSizeCount)) dimensioni non disponibili", bundle: .module)
            : ""
        return String(localized: "Stima nota: \(Formatting.bytes(confirmation.estimatedBytes))", bundle: .module) + unknown
    }

    public var totalText: String {
        let selected = selectedRows
        let known = SafeSum.total(selected.compactMap(\.candidate.sizeBytes))
        let unknown = selected.filter { $0.candidate.sizeBytes == nil }.count
        let suffix = unknown > 0 ? String(localized: " · \(String(unknown)) non disponibili", bundle: .module) : ""
        return String(localized: "\(Formatting.bytes(known)) stimati · \(String(selectedKeys().count)) selezionate", bundle: .module) + suffix
    }

    public var canRetry: Bool { !isLoading && !isDeleting }
    public var canPreview: Bool { !isDeleting && !selectedKeys().isEmpty }
    public var canNavigate: Bool { !isDeleting }
    public var canCancelDelete: Bool { isDeleting }

    public var canConfirmDelete: Bool {
        guard !isDeleting, !executionStarted, let confirmation, !confirmation.selectedCandidates.isEmpty else { return false }
        return confirmation.retainedDependentDevices.isEmpty || acknowledgeDependencies
    }

    /// Come il pulsante «Riprova»: durante un'analisi o un'eliminazione non fa nulla, così la
    /// conferma in corso resta quella che l'esecutore sta eseguendo.
    public func retry() async {
        guard canRetry else { return }
        await load()
    }

    /// L'anteprima passa sempre da `XcodeSelection.preview` sullo snapshot dell'analisi: con lo
    /// stato di Xcode ignoto l'analisi restituisce candidati non classificati (registro del piano 3).
    public func preview() {
        guard let snapshot, !isDeleting else { return }
        do {
            confirmation = try XcodeSelection.preview(snapshot, selectedKeys: selectedKeys())
            acknowledgeDependencies = false
        } catch {
            errorText = FeatureText.message(error)
        }
    }

    public func confirmDelete() async {
        guard !executionStarted, let confirmation else { return }
        executionStarted = true
        isDeleting = true
        errorText = ""
        var executionReturnedReport = false

        do {
            let plan = try XcodeSelection.confirm(confirmation, acknowledgeDependencies: acknowledgeDependencies)

            // Il diario si apre prima dell'esecuzione e passa al resoconto, che lo scarta solo dopo
            // aver scritto il log di sessione (spec §8.2).
            let journal = sessionLog.openJournal(startedAt: clock.now)
            let relay = ProgressRelay<CleanProgress> { [weak self] progress in
                self?.progressText = "\(Formatting.integer(progress.itemsDone)) / \(Formatting.integer(progress.itemsTotal)) · \(progress.currentPath)"
            }
            let xcode = xcode
            let report = relay.report
            let task = Task { await xcode.execute(plan, progress: report, journal: journal) }
            deleteTask = task

            // L'esecutore non lancia: anche un'esecuzione annullata restituisce il resoconto
            // parziale, che va salvato.
            let result = await task.value
            await relay.finish()
            executionReturnedReport = true

            let reportModel = XcodeReportModel(
                history: history, sessionLog: sessionLog, navigation: navigation, result: result, journal: journal)
            currentReport = reportModel
            navigation?.showXcodeReport(reportModel)
        } catch {
            errorText = String(localized: "Pulizia Xcode non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        deleteTask = nil
        executionStarted = executionReturnedReport
        isDeleting = false
    }

    public func cancelDelete() {
        deleteTask?.cancel()
    }

    public func backToSelection() {
        guard !isDeleting else { return }
        confirmation = nil
        acknowledgeDependencies = false
    }

    public func close() {
        guard !isDeleting else { return }
        navigation?.startOver()
    }

    private var selectedRows: [XcodeRow] {
        groups.flatMap(\.rows).filter { $0.isSelected && $0.canSelect }
    }

    /// Le chiavi selezionate. Un `Set<String>` unisce due chiavi canonicamente equivalenti (NFC e
    /// NFD), dove l'`HashSet` ordinale del C# le teneva distinte: si seleziona al più di meno, il
    /// lato sicuro; `XcodeSelection` poi cerca ogni chiave con confronto ordinale.
    func selectedKeys() -> Set<String> {
        Set(selectedRows.map(\.candidate.key))
    }

    private func selectionChanged() {
        confirmation = nil
        acknowledgeDependencies = false
    }

    private func load() async {
        isLoading = true
        errorText = ""
        warningText = ""
        confirmation = nil
        acknowledgeDependencies = false
        groups = []
        snapshot = nil
        // Difesa in profondità: `retry()` non arriva qui durante un'eliminazione (`canRetry`).
        if !isDeleting {
            executionStarted = false
        }

        do {
            let snapshot = try await xcode.analyze()
            self.snapshot = snapshot
            var loaded: [XcodeGroupNode] = []
            for kind in [XcodeResourceKind.derivedData, .deviceSupport, .device, .runtime] {
                let group = XcodeGroupNode(
                    kind: kind,
                    candidates: snapshot.candidates.filter { $0.kind == kind },
                    warnings: snapshot.warnings.filter { $0.resourceGroup == kind }.map(\.message))
                group.onSelectionChanged = { [weak self] in self?.selectionChanged() }
                loaded.append(group)
            }
            groups = loaded
            warningText = FeatureText.distinct(snapshot.warnings.map(\.message)).joined(separator: "\n")
        } catch {
            errorText = String(localized: "Analisi Xcode non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        isLoading = false
    }
}
