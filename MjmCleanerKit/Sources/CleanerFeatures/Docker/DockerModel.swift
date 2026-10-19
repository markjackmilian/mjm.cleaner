import CleanerCore
import Observation

/// Le destinazioni della sezione Docker.
@MainActor
public protocol DockerNavigating: Navigating {
    func showDocker()
    func showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)
}

/// Una risorsa Docker nella schermata di conferma.
@MainActor
@Observable
public final class DockerRow: Identifiable {
    public let candidate: DockerCandidate
    public let showCheckBox: Bool
    public let requiresIndividualConfirmation: Bool
    @ObservationIgnored fileprivate var onSelectionChanged: (@MainActor () -> Void)?

    public var isSelected: Bool {
        didSet {
            if isSelected != oldValue { onSelectionChanged?() }
        }
    }

    init(candidate: DockerCandidate, showCheckBox: Bool) {
        self.candidate = candidate
        self.showCheckBox = showCheckBox
        requiresIndividualConfirmation = DockerConfirmationGroups.requiresIndividualConfirmation(candidate)
        isSelected = candidate.selectedByDefault
    }

    public var name: String { candidate.displayName }
    public var sizeText: String { candidate.sizeBytes.map(Formatting.bytes) ?? "—" }

    public var kindLabel: String {
        switch candidate.kind {
        case .image: String(localized: "immagine", bundle: .module)
        case .volume: String(localized: "volume", bundle: .module)
        case .buildCache: String(localized: "cache", bundle: .module)
        }
    }

    public var detailText: String {
        let cost = candidate.cost.isEmpty ? "" : String(localized: " · costo: \(candidate.cost)", bundle: .module)
        let individual = requiresIndividualConfirmation
            ? String(localized: " · si conferma solo singolarmente", bundle: .module)
            : ""
        return candidate.reason + cost + individual
    }
}

@MainActor
@Observable
public final class DockerGroupNode: Identifiable {
    public let definition: DockerConfirmationGroup
    public let rows: [DockerRow]
    @ObservationIgnored private var syncing = false

    /// Per un gruppo selezionabile, la casella seleziona solo le voci che non richiedono una
    /// conferma singola: un volume con nome che nessuna regola sa ricondurre a un progetto non
    /// entra mai con la casella del gruppo (registro del piano 2, follow-up).
    public var isSelected: Bool {
        didSet {
            guard isSelected != oldValue, !syncing, definition.mode == .selectable else { return }
            syncing = true
            for row in rows where !row.requiresIndividualConfirmation {
                row.isSelected = isSelected
            }
            syncing = false
        }
    }

    init(_ definition: DockerConfirmationGroup) {
        self.definition = definition
        rows = definition.items.map { DockerRow(candidate: $0, showCheckBox: definition.mode == .selectable) }
        isSelected = definition.selectedByDefault
        for row in rows {
            row.onSelectionChanged = { [weak self] in self?.rowChanged() }
        }
    }

    public var title: String { definition.title }
    public var description: String { definition.description }

    /// Le voci da tenere restano chiuse: si guardano solo se servono.
    public var isExpanded: Bool { definition.mode != .readOnly }

    /// La casella del gruppo esiste per i blocchi e per i gruppi in cui almeno una voce si può
    /// selezionare insieme alle altre: un gruppo di soli volumi con nome non ne ha bisogno.
    public var showGroupCheckBox: Bool {
        switch definition.mode {
        case .block: true
        case .selectable: rows.contains { !$0.requiresIndividualConfirmation }
        case .readOnly: false
        }
    }

    public var groupCheckBoxLabel: String {
        definition.mode == .block
            ? String(localized: "Elimina in blocco", bundle: .module)
            : String(localized: "Seleziona tutte", bundle: .module)
    }

    public var summaryText: String {
        let noun = Formatting.plural(rows.count, String(localized: "voce", bundle: .module), String(localized: "voci", bundle: .module))
        let bytes = SafeSum.total(rows.map { $0.candidate.sizeBytes ?? 0 })
        return "\(Formatting.integer(rows.count)) \(noun) · \(Formatting.bytes(bytes))"
    }

    private func rowChanged() {
        guard !syncing else { return }
        syncing = true
        isSelected = rows.filter { !$0.requiresIndividualConfirmation }.allSatisfy(\.isSelected)
        syncing = false
    }
}

/// Porting di `DockerViewModel`: analisi in sola lettura, anteprima con selezione, esecuzione.
/// L'anteprima è il dry-run: nessun comando distruttivo parte prima di «Elimina».
@MainActor
@Observable
public final class DockerModel {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private weak var navigation: (any DockerNavigating)?
    @ObservationIgnored private var diskBefore: DockerDiskUsage?
    /// Il contesto e il motore dell'ultima analisi riuscita: «Elimina» resta lì.
    @ObservationIgnored private var target: DockerTarget?
    @ObservationIgnored private var deleteTask: Task<DockerCleanResult, any Error>?

    public private(set) var isLoading = true
    public private(set) var errorText = ""
    public private(set) var isReady = false
    public private(set) var serverText = ""
    public private(set) var diskText = ""
    public private(set) var dfText = ""
    public private(set) var groups: [DockerGroupNode] = []
    public private(set) var isDeleting = false
    public private(set) var deleteProgressText = ""
    public private(set) var deleteErrorText = ""

    @ObservationIgnored public private(set) var initialLoad: Task<Void, Never>?

    public init(environment: AppEnvironment, navigation: (any DockerNavigating)?) {
        self.environment = environment
        self.navigation = navigation
        initialLoad = Task { await self.load() }
    }

    public var hasError: Bool { !errorText.isEmpty }
    public var hasDeleteError: Bool { !deleteErrorText.isEmpty }
    public var canRetry: Bool { !isLoading }
    public var canDelete: Bool { isReady && !isDeleting && !selection().isEmpty }
    public var canCancelDelete: Bool { isDeleting }

    public var totalText: String {
        let selected = selection()
        let noun = Formatting.plural(selected.count, String(localized: "voce", bundle: .module), String(localized: "voci", bundle: .module))
        let bytes = SafeSum.total(selected.map { $0.sizeBytes ?? 0 })
        return "\(Formatting.bytes(bytes)) · \(Formatting.integer(selected.count)) \(noun)"
    }

    /// Come il pulsante «Riprova»: durante un'analisi non ne avvia un'altra.
    public func retry() async {
        guard canRetry else { return }
        await load()
    }

    public func delete() async {
        // `canDelete` richiede un'analisi riuscita, che ha fissato il bersaglio.
        guard canDelete, let target else { return }
        let engine = target.engine
        isDeleting = true
        deleteErrorText = ""

        let selected = selection()
        let relay = ProgressRelay<CleanProgress> { [weak self] progress in
            self?.deleteProgressText = "\(Formatting.integer(progress.itemsDone)) / \(Formatting.integer(progress.itemsTotal)) · \(progress.currentPath)"
        }
        let docker = environment.docker
        let report = relay.report
        let task = Task { try await docker.execute(selected, on: target, progress: report) }
        deleteTask = task

        do {
            let result = try await task.value
            await relay.finish()
            // La misura non eredita l'annullamento di chi ha chiamato `delete()`, come il
            // `CancellationToken.None` del C#: le voci sono già state rimosse e il resoconto va
            // comunque mostrato e salvato.
            let diskAfter = try await Task { try await docker.measureDisk(for: engine) }.value
            navigation?.showDockerReport(result, engine: engine, diskBefore: diskBefore, diskAfter: diskAfter)
        } catch let error as DockerUnavailableError {
            await relay.finish()
            deleteErrorText = error.message
        } catch let error as DockerEngineChangedError {
            // Non si è cancellato nulla e il messaggio dice già cosa fare: l'elenco resta com'è, e
            // un nuovo clic verrebbe rifiutato di nuovo.
            await relay.finish()
            deleteErrorText = error.message
        } catch {
            await relay.finish()
            deleteErrorText = String(localized: "Pulizia non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        deleteTask = nil
        isDeleting = false
    }

    public func cancelDelete() {
        deleteTask?.cancel()
    }

    public func close() {
        navigation?.startOver()
    }

    /// Le voci da consegnare all'esecutore, decise dal Core (`DockerConfirmationGroups.selection`).
    /// Gruppi e righe si ritrovano per identificativo con confronti ordinali: i valori `struct`
    /// non hanno l'identità di riferimento che il C# usava (`ReferenceEquals`).
    func selection() -> [DockerCandidate] {
        var groupsById: [[UInt8]: DockerGroupNode] = [:]
        var rowsByKey: [[UInt8]: DockerRow] = [:]
        for group in groups {
            if groupsById[FeatureText.ordinalKey(group.definition.id)] == nil {
                groupsById[FeatureText.ordinalKey(group.definition.id)] = group
            }
            for row in group.rows where rowsByKey[Self.rowKey(row.candidate)] == nil {
                rowsByKey[Self.rowKey(row.candidate)] = row
            }
        }

        return DockerConfirmationGroups.selection(
            groups.map(\.definition),
            isGroupSelected: { groupsById[FeatureText.ordinalKey($0.id)]?.isSelected ?? false },
            isItemSelected: { rowsByKey[Self.rowKey($0)]?.isSelected ?? false })
    }

    /// Tipo e identificativo: gli ID di Docker sono unici per tipo (immagini per digest, volumi per nome).
    private static func rowKey(_ candidate: DockerCandidate) -> [UInt8] {
        let kind = switch candidate.kind {
        case .image: "image"
        case .volume: "volume"
        case .buildCache: "build-cache"
        }
        return FeatureText.ordinalKey(kind + ":" + candidate.id)
    }

    private func load() async {
        isLoading = true
        isReady = false
        errorText = ""
        groups = []

        do {
            let analysis = try await environment.docker.analyze(environment.expandedProjectRoots())
            target = analysis.target
            diskBefore = analysis.disk
            serverText = Self.describeServer(analysis.engine)
            diskText = Self.describeDisk(analysis.disk, engine: analysis.engine)
            dfText = Self.describeDf(analysis.snapshot.df)
            groups = DockerConfirmationGroups.build(analysis.candidates).map(DockerGroupNode.init)
            isReady = true
        } catch let error as DockerUnavailableError {
            // Messaggio già pensato per l'utente: nessun motore viene avviato da qui, è l'utente a
            // deciderlo.
            errorText = error.message
        } catch {
            errorText = String(localized: "Analisi di Docker non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        isLoading = false
    }

    static func describeServer(_ engine: DockerEngine) -> String {
        switch engine.kind {
        case .dockerDesktop, .orbStack:
            String(localized: "\(engine.displayName) · Docker \(engine.serverVersion) in esecuzione", bundle: .module)
        case .other where engine.operatingSystem.isEmpty:
            String(localized: "Docker \(engine.serverVersion) in esecuzione", bundle: .module)
        case .other:
            String(localized: "Docker \(engine.serverVersion) in esecuzione su «\(engine.operatingSystem)»", bundle: .module)
        }
    }

    /// Solo Docker Desktop ha un disco misurato (`DiskUsageProbe.measure(for:)`): OrbStack lo riduce
    /// da solo, per gli altri motori fa fede `docker system df`.
    static func describeDisk(_ disk: DockerDiskUsage?, engine: DockerEngine) -> String {
        if engine.kind == .orbStack {
            return String(
                localized: "OrbStack restituisce da solo al Mac lo spazio liberato: il suo disco virtuale non viene misurato.",
                bundle: .module)
        }
        guard let disk else {
            return String(localized: "Disco virtuale di questo motore non misurato: fa fede docker system df.", bundle: .module)
        }
        guard disk.exists else {
            return String(
                localized: "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.",
                bundle: .module)
        }
        guard let allocated = disk.allocatedBytes, let apparent = disk.apparentBytes else {
            return String(localized: "Docker.raw trovato, ma lo spazio occupato non è misurabile.", bundle: .module)
        }
        return String(
            localized: "Docker.raw occupa \(Formatting.bytes(allocated)) sul disco (dimensione apparente \(Formatting.bytes(apparent)): è il limite massimo del disco virtuale, non lo spazio usato).",
            bundle: .module)
    }

    static func describeDf(_ df: DockerDfSummary) -> String {
        df.entries
            .filter { !FeatureText.same($0.type, "Containers") }
            .map { entry in
                String(
                    localized: "\(typeLabel(entry.type)) \(Formatting.bytes(entry.sizeBytes)) (recuperabili \(Formatting.bytes(entry.reclaimableBytes)))",
                    bundle: .module)
            }
            .joined(separator: " · ")
    }

    static func typeLabel(_ dfType: String) -> String {
        if FeatureText.same(dfType, DockerDfSummary.imagesType) { return String(localized: "Immagini", bundle: .module) }
        if FeatureText.same(dfType, DockerDfSummary.volumesType) { return String(localized: "Volumi", bundle: .module) }
        if FeatureText.same(dfType, DockerDfSummary.buildCacheType) { return String(localized: "Cache di build", bundle: .module) }
        return dfType
    }
}
