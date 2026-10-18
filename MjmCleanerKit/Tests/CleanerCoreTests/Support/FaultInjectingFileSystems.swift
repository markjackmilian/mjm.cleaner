import CleanerCore
import Darwin
import Foundation
import Synchronization

/// Errore fuori dal contratto del Core (non un `FileSystemError`): l'equivalente delle eccezioni
/// che in C# non rientravano in `RuleScanner.IsExpected`.
struct UnexpectedTestError: Error, CustomStringConvertible {
    let description: String
}

/// Porting di `VanishingFileSystem.cs`: un elemento che scompare fra l'enumerazione e la lettura
/// della sua dimensione. In C# lanciava solo `FileInfo.Length`; in Swift dimensione e date
/// arrivano dalla stessa chiamata, quindi lancia `itemInfo`. L'esito dei test non cambia: per un
/// percorso scomparso .NET restituiva comunque la sentinella 1601 come data, e il Core Swift
/// tratta `ENOENT` esattamente come quella sentinella.
final class VanishingFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let vanishedPath: String

    init(_ inner: any FileSystem, vanishedPath: String) {
        self.vanishedPath = vanishedPath
        super.init(inner)
    }

    override func itemInfo(_ path: String) throws -> FileItemInfo {
        if path == vanishedPath { throw FileSystemError(code: ENOENT, path: path) }
        return try super.itemInfo(path)
    }
}

/// Porting di `VanishingChildFileSystem.cs`: la prima volta che `directoryExists` risponde vero
/// per il percorso bersaglio, la cartella viene eliminata dal filesystem interno — sparisce fra
/// il momento in cui lo scanner la riconosce e quello in cui ne legge le statistiche.
final class VanishingChildFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let vanishingPath: String
    private let triggered = Mutex(false)

    init(_ inner: any FileSystem, vanishingPath: String) {
        self.vanishingPath = vanishingPath
        super.init(inner)
    }

    override func directoryExists(_ path: String) -> Bool {
        guard path == vanishingPath else { return super.directoryExists(path) }
        let existed = super.directoryExists(path)
        let shouldVanish = triggered.withLock { alreadyTriggered in
            guard existed, !alreadyTriggered else { return false }
            alreadyTriggered = true
            return true
        }
        if shouldVanish { try? inner.deleteDirectoryRecursively(path) }
        return existed
    }
}

/// Porting di `UnreadableDirectoryFileSystem.cs`: una cartella visibile ma non elencabile. Senza
/// `error` esplicito lancia `EACCES`; con un `UnexpectedTestError` simula i mount virtuali che in
/// C# rispondevano con eccezioni di tipo imprevedibile.
final class UnreadableDirectoryFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let unreadablePath: String
    private let error: any Error

    init(_ inner: any FileSystem, unreadablePath: String, error: (any Error)? = nil) {
        self.unreadablePath = unreadablePath
        self.error = error ?? FileSystemError(code: EACCES, path: unreadablePath)
        super.init(inner)
    }

    override func contentsOfDirectory(_ path: String) throws -> [String] {
        if path == unreadablePath { throw error }
        return try super.contentsOfDirectory(path)
    }
}

/// Solo Swift: una voce di cui non si leggono le informazioni (`itemInfo` lancia `EACCES`) mentre
/// `directoryExists` continua a rispondere, per separare la lettura del timestamp di una cartella
/// dal suo elenco.
final class UnreadableInfoFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let unreadablePath: String

    init(_ inner: any FileSystem, unreadablePath: String) {
        self.unreadablePath = unreadablePath
        super.init(inner)
    }

    override func itemInfo(_ path: String) throws -> FileItemInfo {
        if path == unreadablePath { throw FileSystemError(code: EACCES, path: path) }
        return try super.itemInfo(path)
    }
}

/// Solo Swift: annulla il task corrente quando si elenca una certa cartella, per un annullamento
/// che arriva a metà di un attraversamento.
final class CancellingFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let cancellingPath: String

    init(_ inner: any FileSystem, cancellingPath: String) {
        self.cancellingPath = cancellingPath
        super.init(inner)
    }

    override func contentsOfDirectory(_ path: String) throws -> [String] {
        if path == cancellingPath { cancelCurrentTask() }
        return try super.contentsOfDirectory(path)
    }
}

/// Porting di `ThrowingOnDeleteFileSystem.cs`: un errore fuori contratto durante la cancellazione
/// di un file specifico.
final class ThrowingOnDeleteFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let throwingPath: String

    init(_ inner: any FileSystem, throwingPath: String) {
        self.throwingPath = throwingPath
        super.init(inner)
    }

    override func deleteFile(_ path: String) throws {
        if path == throwingPath {
            throw UnexpectedTestError(description: "errore imprevisto durante la cancellazione di \(path)")
        }
        try super.deleteFile(path)
    }
}
