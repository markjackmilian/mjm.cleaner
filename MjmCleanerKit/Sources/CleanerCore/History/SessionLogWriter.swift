import Foundation

public protocol SessionLogWriting: Sendable {
    func write(sessionId: Int64, report: CleanReport) async throws
    func openJournal(startedAt: Date) -> PendingJournal?
    func discard(_ journal: PendingJournal)
}

/// Elenco completo dei percorsi eliminati, una riga JSON per elemento, compresso. Non va in
/// SQLite: una pulizia delle cache tocca centinaia di migliaia di file e il database crescerebbe
/// più in fretta dello spazio liberato.
public struct SessionLogWriter: SessionLogWriting {
    private let fileSystem: any FileSystem
    private let paths: AppPaths
    private let retention: Int

    public init(fileSystem: any FileSystem, paths: AppPaths, retention: Int = 20) {
        self.fileSystem = fileSystem
        self.paths = paths
        self.retention = retention
    }

    @concurrent
    public func write(sessionId: Int64, report: CleanReport) async throws {
        try fileSystem.createDirectory(paths.logsDirectory)

        var text = ""
        for path in report.deletedPaths {
            try Task.checkCancellation()
            text += Self.jsonLine(path)
        }

        let file = PathText.join(paths.logsDirectory, Self.fileName(sessionId))
        try fileSystem.writeData(file, Gzip.compress(Data(text.utf8)))
        try prune()
    }

    public func openJournal(startedAt: Date) -> PendingJournal? {
        do {
            try fileSystem.createDirectory(paths.logsDirectory)
            let path = PathText.join(paths.logsDirectory, "pending-\(Self.journalStamp(startedAt)).jsonl")
            try fileSystem.appendData(path, Data())
            return PendingJournal(path: path, fileSystem: fileSystem)
        } catch {
            // Senza diario la pulizia procede comunque, come in C#.
            return nil
        }
    }

    public func discard(_ journal: PendingJournal) {
        try? fileSystem.deleteFile(journal.path)
    }

    /// `{"path":"…"}` più "\n", lo stesso record che scriveva il C#. L'escape è scritto a mano: un
    /// `JSONEncoder` per ciascuna di centinaia di migliaia di righe costerebbe senza motivo.
    public static func jsonLine(_ path: String) -> String {
        var escaped = ""
        for scalar in path.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case _ where scalar.value < 0x20: escaped += String(format: "\\u%04x", scalar.value)
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "{\"path\":\"\(escaped)\"}\n"
    }

    private static func fileName(_ sessionId: Int64) -> String {
        String(format: "session-%06lld.jsonl.gz", sessionId)
    }

    /// "20260915T103000Z": data e ora UTC del diario, leggibili e ordinabili.
    private static func journalStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Ordina sul valore NUMERICO del nome: oltre le sei cifre l'ordine lessicografico metterebbe
    /// "1…" prima di "9…" e la rotazione cancellerebbe la sessione più recente. I nomi che non
    /// corrispondono a `session-<cifre>.jsonl.gz` (diari compresi) non sono toccati mai.
    private func prune() throws {
        let stale = try fileSystem.contentsOfDirectory(paths.logsDirectory)
            .filter { fileSystem.fileExists($0) }
            .compactMap { path in Self.sessionId(of: PathText.fileName(path)).map { (path: path, id: $0) } }
            .sorted { $0.id > $1.id }
            .dropFirst(retention)

        for entry in stale {
            // La rotazione dei log non deve far fallire una pulizia riuscita.
            try? fileSystem.deleteFile(entry.path)
        }
    }

    private static func sessionId(of name: String) -> Int64? {
        guard let match = name.wholeMatch(of: /session-(\d+)\.jsonl\.gz/) else { return nil }
        return Int64(match.1)
    }
}
