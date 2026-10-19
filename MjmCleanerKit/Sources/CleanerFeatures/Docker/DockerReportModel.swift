import CleanerCore
import Observation

/// Porting di `DockerReportViewModel`: il resoconto di una pulizia Docker e il suo salvataggio.
/// Le rimozioni di Docker passano dalla CLI e non da `CleanEngine`: come in C# non hanno diario.
@MainActor
@Observable
public final class DockerReportModel {
    @ObservationIgnored private weak var navigation: (any DockerNavigating)?

    public let freedText: String
    public let summaryText: String
    public let dfText: String
    public let diskText: String
    public let purgeHint: String
    public let daemonLostText: String
    public let deleted: [String]
    public let failed: [String]
    public private(set) var historyWarning = ""

    @ObservationIgnored public private(set) var persistence: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        navigation: (any DockerNavigating)?,
        result: DockerCleanResult,
        engine: DockerEngine,
        diskBefore: DockerDiskUsage?,
        diskAfter: DockerDiskUsage?
    ) {
        self.navigation = navigation
        let report = result.report

        freedText = String(localized: "\(Formatting.bytes(report.bytesFreed)) recuperati", bundle: .module)
        let deletedNoun = Formatting.plural(
            report.itemsDeleted,
            String(localized: "voce eliminata", bundle: .module),
            String(localized: "voci eliminate", bundle: .module))
        var summary = "\(Formatting.integer(report.itemsDeleted)) \(deletedNoun)"
        if report.itemsFailed > 0 {
            let failedNoun = Formatting.plural(
                report.itemsFailed,
                String(localized: "eliminata", bundle: .module),
                String(localized: "eliminate", bundle: .module))
            summary += String(localized: " · \(Formatting.integer(report.itemsFailed)) non \(failedNoun)", bundle: .module)
        }
        summaryText = summary

        if let after = result.after {
            dfText = String(
                localized: "docker system df: \(Formatting.bytes(result.before.total)) → \(Formatting.bytes(after.total))",
                bundle: .module)
        } else {
            dfText = String(localized: "docker system df: misura finale non disponibile.", bundle: .module)
        }

        // Solo Docker Desktop ha un disco misurato (`DiskUsageProbe.measure(for:)`).
        switch engine.kind {
        case .dockerDesktop:
            if let before = diskBefore?.allocatedBytes, let after = diskAfter?.allocatedBytes {
                diskText = String(localized: "Docker.raw sul disco: \(Formatting.bytes(before)) → \(Formatting.bytes(after))", bundle: .module)
            } else {
                diskText = String(localized: "Docker.raw sul disco: non misurabile.", bundle: .module)
            }
        case .orbStack:
            diskText = String(localized: "Disco virtuale: OrbStack restituisce lo spazio al Mac automaticamente.", bundle: .module)
        case .other:
            diskText = String(localized: "Disco virtuale: non misurato per questo motore.", bundle: .module)
        }

        // Docker Desktop restituisce lo spazio al Mac in modo differito: il disco virtuale può
        // restare grande anche dopo una pulizia riuscita. Purge è l'unico modo per forzarlo, e
        // cancella TUTTO: lo si suggerisce, mai lo si esegue. È un comando di Docker Desktop: gli
        // altri motori non lo hanno.
        if engine.kind == .dockerDesktop,
           report.itemsDeleted > 0,
           let rawBefore = diskBefore?.allocatedBytes,
           let rawAfter = diskAfter?.allocatedBytes,
           rawAfter >= rawBefore {
            purgeHint = String(
                localized: "Docker.raw non si è ridotto: Docker Desktop restituisce lo spazio al Mac con calma. Per recuperarlo subito: Docker Desktop → Troubleshoot → Clean / Purge data. Attenzione: quell'operazione cancella tutte le immagini, i container e i volumi.",
                bundle: .module)
        } else {
            purgeHint = ""
        }

        daemonLostText = result.daemonLost
            ? String(localized: "\(engine.displayName) si è fermato durante la pulizia: le voci restanti non sono state eliminate. Avvialo e premi «Nuova analisi» per riprovare.", bundle: .module)
            : ""

        deleted = report.deletedPaths.map(Self.describe)
        failed = report.errors.map { "\($0.path) — \($0.message)" }

        persistence = Task { await self.persist(environment, report) }
    }

    public var hasFailures: Bool { !failed.isEmpty }

    public func analyzeAgain() {
        navigation?.showDocker()
    }

    public func close() {
        navigation?.startOver()
    }

    /// "docker:image:sha256:… (nome)" → "immagine nome": l'identificativo completo resta nel log di
    /// sessione. Si lavora sui byte UTF-8, come `StartsWith`/`IndexOf` ordinali del C#.
    static func describe(_ logEntry: String) -> String {
        let image = "docker:image:"
        let volume = "docker:volume:"
        let bytes = Array(logEntry.utf8)

        if FeatureText.hasOrdinalPrefix(logEntry, image) {
            let open = (0..<max(0, bytes.count - 1)).first { bytes[$0] == UInt8(ascii: " ") && bytes[$0 + 1] == UInt8(ascii: "(") }
            if let open, open > 0, open + 2 <= bytes.count - 1 {
                let name = String(decoding: bytes[(open + 2)..<(bytes.count - 1)], as: UTF8.self)
                return String(localized: "immagine \(name)", bundle: .module)
            }
            let id = String(decoding: bytes.dropFirst(image.utf8.count), as: UTF8.self)
            return String(localized: "immagine \(id)", bundle: .module)
        }

        if FeatureText.hasOrdinalPrefix(logEntry, volume) {
            let name = String(decoding: bytes.dropFirst(volume.utf8.count), as: UTF8.self)
            return String(localized: "volume \(name)", bundle: .module)
        }

        return String(localized: "cache di build", bundle: .module)
    }

    /// Come per il wizard: la pulizia è avvenuta anche se lo storico non si aggiorna, e va detto.
    private func persist(_ environment: AppEnvironment, _ report: CleanReport) async {
        do {
            let sessionId = try await environment.history.save(report)
            try await environment.sessionLog.write(sessionId: sessionId, report: report)
            try await navigation?.refreshTotal()
        } catch {
            historyWarning = String(localized: "Pulizia completata, storico non aggiornato: \(FeatureText.message(error))", bundle: .module)
        }
    }
}
