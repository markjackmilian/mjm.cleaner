import CleanerCore
import Observation

/// Porting di `MainWindowViewModel`: la pagina corrente, la sidebar, il contatore «Spazio
/// liberato» e lo sheet delle Impostazioni. Il blocco della navigazione durante l'eliminazione
/// Xcode è imposto qui, non solo dalla vista con `.disabled`, così che i test lo verifichino
/// (spec §6.3). Vale anche per le richieste delle pagine: una pagina non più corrente (un'analisi
/// o un'eliminazione abbandonata) non sostituisce la pagina Xcode mentre elimina.
@MainActor
@Observable
public final class MainModel: CleanupNavigating, DockerNavigating, XcodeNavigating {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let appearance: any AppearanceApplying
    @ObservationIgnored private let folders: any FolderPicking

    public private(set) var page: Page
    public private(set) var totalFreedAmount = "—"

    /// Lo sheet delle Impostazioni è presente finché questo valore non è `nil`: l'app lo presenta
    /// con `.sheet(item:)`. Salva e Annulla lo azzerano.
    public private(set) var settings: SettingsModel?

    public init(environment: AppEnvironment, appearance: any AppearanceApplying, folders: any FolderPicking) {
        self.environment = environment
        self.appearance = appearance
        self.folders = folders
        // Il passo 1 riceve la navigazione appena `self` è disponibile.
        let first = ChooseStepModel(environment: environment, navigation: nil)
        page = .choose(first)
        first.navigation = self
    }

    public var section: SidebarSection { page.kind.section }

    public var isXcodeBusy: Bool {
        if case .xcode(let model) = page { model.isDeleting } else { false }
    }

    public var canNavigateGlobally: Bool { !isXcodeBusy }

    /// ⌘, e «Impostazioni…»: disabilitati mentre Xcode elimina e mentre lo sheet è già aperto
    /// (in C# l'`AsyncRelayCommand` non ammetteva esecuzioni concorrenti).
    public var canShowSettings: Bool { canNavigateGlobally && settings == nil }

    // MARK: Sidebar e menu

    /// La voce scelta nella sidebar. Mentre Xcode elimina il cambio viene rifiutato e la voce
    /// selezionata resta quella della pagina corrente.
    public func select(_ section: SidebarSection) {
        switch section {
        case .cleanup: showCleanup()
        case .docker: showDocker()
        case .xcode: showXcode()
        case .history: showHistory()
        }
    }

    /// «Pulizia» non interrompe un ciclo in corso; dalle altre sezioni riparte dal passo 1.
    public func showCleanup() {
        guard canNavigateGlobally else { return }
        if !page.kind.isWizardStep {
            startOver()
        }
    }

    public func showHistory() {
        guard canNavigateGlobally else { return }
        page = .history(HistoryModel(environment: environment, navigation: self))
    }

    public func showSettings() {
        guard canShowSettings else { return }
        settings = SettingsModel(
            store: environment.settings,
            appearance: appearance,
            folders: folders,
            onSaved: { [weak self] in self?.startOver() },
            onClose: { [weak self] in self?.settings = nil })
    }

    // MARK: Navigating

    /// Torna al passo 1 del wizard: all'avvio e ogni volta che un ciclo si conclude o viene annullato.
    public func startOver() {
        guard canNavigateGlobally else { return }
        page = .choose(ChooseStepModel(environment: environment, navigation: self))
    }

    public func refreshTotal() async throws {
        let total = try await environment.history.totalBytesFreed()
        totalFreedAmount = Formatting.bytes(total)
    }

    // MARK: CleanupNavigating

    public func showScan(_ categories: [CleanupCategory]) {
        guard canNavigateGlobally else { return }
        page = .scan(ScanStepModel(environment: environment, navigation: self, categories: categories))
    }

    public func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult]) {
        guard canNavigateGlobally else { return }
        page = .confirm(ConfirmStepModel(environment: environment, navigation: self, categories: categories, results: results))
    }

    /// Il passo 4 si costruisce anche quando il cambio di pagina è rifiutato: il suo `init` salva
    /// storico e log di una pulizia già avvenuta, che non deve andare persa.
    public func showDone(_ report: CleanReport, journal: PendingJournal?) {
        let done = DoneStepModel(environment: environment, navigation: self, report: report, journal: journal)
        guard canNavigateGlobally else { return }
        page = .done(done)
    }

    // MARK: DockerNavigating

    /// Docker, Xcode e Storico creano una pagina nuova a ogni selezione.
    public func showDocker() {
        guard canNavigateGlobally else { return }
        page = .docker(DockerModel(environment: environment, navigation: self))
    }

    /// Come il passo 4: il resoconto salva la pulizia già avvenuta anche se la pagina non cambia.
    public func showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
        let report = DockerReportModel(
            environment: environment, navigation: self, result: result, engine: engine, diskBefore: diskBefore, diskAfter: diskAfter)
        guard canNavigateGlobally else { return }
        page = .dockerReport(report)
    }

    // MARK: XcodeNavigating

    public func showXcode() {
        guard canNavigateGlobally else { return }
        page = .xcode(XcodeModel(
            xcode: environment.xcode,
            history: environment.history,
            sessionLog: environment.sessionLog,
            clock: environment.clock,
            navigation: self))
    }

    /// Non bloccato: la pagina Xcode chiede il proprio resoconto mentre `isDeleting` è ancora vero.
    public func showXcodeReport(_ report: XcodeReportModel) {
        page = .xcodeReport(report)
    }
}
