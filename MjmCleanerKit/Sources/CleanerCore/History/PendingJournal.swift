import Foundation

/// Diario della pulizia (spec §8.2). In C# `CleanEngine` intercettava qualunque eccezione per non
/// perdere l'elenco di ciò che era già stato cancellato; in Swift un errore di programmazione
/// termina il processo senza possibilità di intercettarlo. Ogni percorso eliminato viene quindi
/// aggiunto subito in coda a `logs/pending-<timestamp>.jsonl`, in chiaro: dopo un arresto
/// improvviso il file resta leggibile. A fine sessione, scritto il log compresso, viene rimosso.
public final class PendingJournal: DeletionRecording {
    public let path: String
    private let fileSystem: any FileSystem

    init(path: String, fileSystem: any FileSystem) {
        self.path = path
        self.fileSystem = fileSystem
    }

    public func recordDeleted(_ deletedPath: String) {
        // Il diario è una rete di sicurezza: un suo errore non deve mai fermare la pulizia.
        try? fileSystem.appendData(path, Data(SessionLogWriter.jsonLine(deletedPath).utf8))
    }
}
