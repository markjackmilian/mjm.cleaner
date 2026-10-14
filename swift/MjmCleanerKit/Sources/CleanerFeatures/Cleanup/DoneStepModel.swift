import CleanerCore
import Observation

/// Porting di `DoneStepViewModel`: passo 4, resoconto e salvataggio nello storico.
@MainActor
@Observable
public final class DoneStepModel {
    @ObservationIgnored private weak var navigation: (any CleanupNavigating)?

    public let freedText: String
    public let summaryText: String
    public let errorsText: String
    public let rows: [String]
    public private(set) var historyWarning = ""

    /// Il salvataggio parte alla creazione, come nel costruttore C#; i test lo attendono.
    @ObservationIgnored public private(set) var persistence: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        navigation: (any CleanupNavigating)?,
        report: CleanReport,
        journal: PendingJournal?
    ) {
        self.navigation = navigation

        freedText = String(localized: "\(Formatting.bytes(report.bytesFreed)) liberati", bundle: .module)
        let deletedNoun = Formatting.plural(
            report.itemsDeleted,
            String(localized: "elemento eliminato", bundle: .module),
            String(localized: "elementi eliminati", bundle: .module))
        summaryText = String(
            localized: "in \(Formatting.seconds(report.duration)) secondi · \(Formatting.integer(report.itemsDeleted)) \(deletedNoun)",
            bundle: .module)

        // Il resoconto nomina le categorie per identificativo stabile ("project-build-output"),
        // non per il nome visualizzato: qui si traduce nel nome usato ovunque altrove nel wizard.
        // Il ripiego sull'identificativo è solo difensivo.
        let catalog = environment.categories()
        rows = report.categories
            .filter { $0.itemsDeleted > 0 }
            .map { result in
                let name = catalog.first { FeatureText.same($0.id, result.categoryId) }?.displayName ?? result.categoryId
                return "\(name) — \(Formatting.bytes(result.bytesFreed))"
            }

        if report.itemsFailed == 0 {
            errorsText = ""
        } else {
            let failedNoun = Formatting.plural(
                report.itemsFailed,
                String(localized: "elemento non eliminato", bundle: .module),
                String(localized: "elementi non eliminati", bundle: .module))
            errorsText = "\(report.itemsFailed) \(failedNoun). \(Self.describeErrors(report.errors))"
        }

        persistence = Task { await self.persist(environment, report, journal) }
    }

    public func newCleanup() {
        navigation?.startOver()
    }

    /// Il C# riconosceva un problema di permessi anche dal testo inglese del messaggio .NET
    /// (`LooksLikePermissionError`), perché `Directory.Delete` su una cartella negata lanciava
    /// `IOException`. Il Core Swift classifica già EACCES/EPERM come `.accessDenied` anche da
    /// `rmdir` (registro di parità), quindi basta il tipo: niente controlli sul testo.
    static func describeErrors(_ errors: [ScanError]) -> String {
        if errors.contains(where: { $0.kind == .accessDenied }) {
            return String(
                localized: "Alcuni richiedono l'Accesso completo al disco: Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco.",
                bundle: .module)
        }

        return errors.contains(where: { $0.kind == .inUse })
            ? String(localized: "Alcuni erano in uso da applicazioni aperte.", bundle: .module)
            : String(localized: "Dettagli nel log della sessione.", bundle: .module)
    }

    /// Se la scrittura dello storico fallisce la pulizia è comunque avvenuta: va detto, senza far
    /// credere che non abbia cancellato nulla. Il diario si scarta solo dopo che il log di
    /// sessione è stato scritto (spec §8.2): se qualcosa fallisce prima, resta in logs/.
    private func persist(_ environment: AppEnvironment, _ report: CleanReport, _ journal: PendingJournal?) async {
        do {
            let sessionId = try await environment.history.save(report)
            try await environment.sessionLog.write(sessionId: sessionId, report: report)
            if let journal {
                environment.sessionLog.discard(journal)
            }
            try await navigation?.refreshTotal()
        } catch {
            historyWarning = String(localized: "Pulizia completata, storico non aggiornato: \(FeatureText.message(error))", bundle: .module)
        }
    }
}
