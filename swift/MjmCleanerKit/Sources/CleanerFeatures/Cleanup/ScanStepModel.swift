import CleanerCore
import Observation

/// Lo stato di una categoria durante l'analisi.
@MainActor
@Observable
public final class CategoryProgress: Identifiable {
    public let displayName: String
    public fileprivate(set) var status = String(localized: "in attesa", bundle: .module)

    init(displayName: String) {
        self.displayName = displayName
    }
}

/// Porting di `ScanStepViewModel`: passo 2, analisi in sola lettura delle categorie scelte.
@MainActor
@Observable
public final class ScanStepModel {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private weak var navigation: (any CleanupNavigating)?
    @ObservationIgnored private let categories: [CleanupCategory]

    public let progress: [CategoryProgress]
    public private(set) var currentPath = ""
    public private(set) var isRunning = true

    /// Vuoto finché l'analisi non fallisce. Senza un errore diverso dall'annullamento catturato
    /// esplicitamente, `isRunning` resterebbe vero per sempre, Annulla non avrebbe più effetto e
    /// l'utente resterebbe intrappolato sul passo 2 senza via d'uscita.
    public private(set) var errorText = ""

    public var hasError: Bool { !errorText.isEmpty }

    /// L'analisi parte alla creazione della pagina; Annulla annulla questo task.
    @ObservationIgnored public private(set) var run: Task<Void, Never>?

    public init(environment: AppEnvironment, navigation: (any CleanupNavigating)?, categories: [CleanupCategory]) {
        self.environment = environment
        self.navigation = navigation
        self.categories = categories
        progress = categories.map { CategoryProgress(displayName: $0.displayName) }
        run = Task { await self.perform() }
    }

    public func cancel() {
        run?.cancel()
    }

    /// Unica via d'uscita quando l'analisi fallisce: non c'è nulla da annullare, si torna al passo 1.
    public func backToStart() {
        navigation?.startOver()
    }

    private func perform() async {
        let relay = ProgressRelay<ScanProgress> { [weak self] in self?.apply($0) }
        do {
            let results = try await environment.scan.scan(categories, progress: relay.report)
            await relay.finish()
            isRunning = false
            navigation?.showConfirm(categories, results: results)
        } catch is CancellationError {
            await relay.finish()
            isRunning = false
            navigation?.startOver()
        } catch {
            await relay.finish()
            isRunning = false
            errorText = String(localized: "Analisi non riuscita: \(FeatureText.message(error))", bundle: .module)
        }
    }

    private func apply(_ update: ScanProgress) {
        guard let category = categories.first(where: { FeatureText.same($0.id, update.categoryId) }),
              let row = progress.first(where: { FeatureText.same($0.displayName, category.displayName) })
        else { return }

        if update.currentPath.isEmpty {
            let noun = Formatting.plural(update.itemsFound, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
            row.status = "\(update.itemsFound) \(noun) · \(Formatting.bytes(update.bytesFound))"
        } else {
            row.status = String(localized: "in corso…", bundle: .module)
            currentPath = update.currentPath
        }
    }
}
