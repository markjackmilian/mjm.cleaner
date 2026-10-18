import CleanerCore
import Observation

/// Le destinazioni della sezione Xcode (`IXcodeNavigation` del C#).
@MainActor
public protocol XcodeNavigating: Navigating {
    func showXcode()
    func showXcodeReport(_ report: XcodeReportModel)
}

/// Una riga del resoconto Xcode.
public struct XcodeResultRow: Identifiable, Sendable {
    public let id: Int
    public let item: XcodeItemResult

    public var name: String { item.candidate.name }
    public var identity: String { item.candidate.path ?? item.candidate.cliId ?? item.candidate.key }
    public var detail: String { item.reason }

    public var outcomeText: String {
        switch item.outcome {
        case .deleted: String(localized: "Eliminata", bundle: .module)
        case .skipped: String(localized: "Saltata", bundle: .module)
        case .failed: String(localized: "Non riuscita", bundle: .module)
        case .uncertain: String(localized: "Esito incerto", bundle: .module)
        }
    }

    public var sizeText: String {
        item.verifiedEstimatedBytes.map(Formatting.bytes) ?? String(localized: "non disponibile", bundle: .module)
    }
}

/// Porting di `XcodeReportViewModel`: il resoconto, salvato una sola volta nello storico.
@MainActor
@Observable
public final class XcodeReportModel {
    @ObservationIgnored private let history: any HistoryStoring
    @ObservationIgnored private let sessionLog: any SessionLogWriting
    @ObservationIgnored private weak var navigation: (any XcodeNavigating)?
    @ObservationIgnored private let result: XcodeCleanResult

    public let items: [XcodeResultRow]
    public let freedText: String
    public let summaryText: String
    public let freeSpaceText: String
    public let warningsText: String
    public private(set) var historyWarning = ""

    /// Il salvataggio parte alla creazione e avviene una volta sola: `persist()` lo attende soltanto.
    @ObservationIgnored public private(set) var persistence: Task<Void, Never>?

    public init(
        history: any HistoryStoring,
        sessionLog: any SessionLogWriting,
        navigation: (any XcodeNavigating)?,
        result: XcodeCleanResult,
        journal: PendingJournal?
    ) {
        self.history = history
        self.sessionLog = sessionLog
        self.navigation = navigation
        self.result = result

        items = result.items.enumerated().map { XcodeResultRow(id: $0.offset, item: $0.element) }
        let report = result.historyReport
        freedText = String(localized: "\(Formatting.integer(report.bytesFreed)) byte stimati conteggiati nella cronologia", bundle: .module)

        func count(_ outcome: XcodeItemOutcome) -> String {
            Formatting.integer(result.items.filter { $0.outcome == outcome }.count)
        }
        summaryText = String(
            localized: "\(Formatting.integer(report.itemsDeleted)) eliminate · \(count(.skipped)) saltate · \(count(.failed)) non riuscite · \(count(.uncertain)) incerte",
            bundle: .module)

        if let before = result.freeBytesBefore, let after = result.freeBytesAfter {
            freeSpaceText = after >= before
                ? String(
                    localized: "Spazio libero rilevato: +\(Formatting.bytes(SafeSum.difference(after, before))) (\(Formatting.bytes(before)) → \(Formatting.bytes(after))). Variazione separata dalle stime eliminate.",
                    bundle: .module)
                : String(
                    localized: "Spazio libero rilevato: \(Formatting.bytes(before)) → \(Formatting.bytes(after)). La variazione può dipendere da altre attività.",
                    bundle: .module)
        } else {
            freeSpaceText = String(localized: "Spazio libero prima o dopo: non disponibile.", bundle: .module)
        }

        warningsText = result.warnings.joined(separator: "\n")
        persistence = Task { await self.persistOnce(journal) }
    }

    public var hasWarnings: Bool { !warningsText.isEmpty }
    public var hasHistoryWarning: Bool { !historyWarning.isEmpty }

    public func persist() async {
        await persistence?.value
    }

    public func analyzeAgain() {
        navigation?.showXcode()
    }

    public func close() {
        navigation?.startOver()
    }

    /// Storico, poi log di sessione, poi contatore: il messaggio dice fin dove si è arrivati. Il
    /// diario si scarta solo dopo il log di sessione (spec §8.2).
    private func persistOnce(_ journal: PendingJournal?) async {
        var historySaved = false
        var logSaved = false
        do {
            let sessionId = try await history.save(result.historyReport)
            historySaved = true
            try await sessionLog.write(sessionId: sessionId, report: result.historyReport)
            logSaved = true
            if let journal {
                sessionLog.discard(journal)
            }
            try await navigation?.refreshTotal()
        } catch {
            let reason = FeatureText.message(error)
            historyWarning = switch (historySaved, logSaved) {
            case (true, true):
                String(localized: "Cronologia e log salvati, ma il contatore cumulativo non è stato aggiornato: \(reason)", bundle: .module)
            case (true, false):
                String(localized: "Cronologia salvata, ma il log di sessione non è stato aggiornato: \(reason)", bundle: .module)
            default:
                String(localized: "Pulizia completata, ma il report non è stato salvato nello storico: \(reason)", bundle: .module)
            }
        }
    }
}
