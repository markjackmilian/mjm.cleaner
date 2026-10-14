import Darwin
import Foundation

/// Errore del filesystem: il codice errno originale e il percorso coinvolto. La classificazione
/// mostrata all'utente (accesso negato, in uso, …) avviene in `RuleScanner.describe`.
public struct FileSystemError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int32
    public let path: String

    public init(code: Int32, path: String) {
        self.code = code
        self.path = path
    }

    /// Testo di sistema dell'errore (`strerror`): fa le veci del `Message` delle eccezioni .NET.
    public var message: String { String(cString: strerror(code)) }

    public var description: String { "\(message): \(path)" }
}

public enum FileItemKind: Sendable, Equatable {
    case file
    case directory
    case symbolicLink
    case other
}

/// Metadati letti con `lstat`, come `FileInfo`/`DirectoryInfo` di .NET su Unix: per un
/// collegamento simbolico valgono dimensione e date del collegamento stesso, non del bersaglio.
public struct FileItemInfo: Sendable, Equatable {
    public let kind: FileItemKind
    public let size: Int64
    public let lastWrite: Date
    public let lastAccess: Date
    /// Data di creazione (`st_birthtimespec`), come `CreationTimeUtc` di .NET su macOS: a
    /// differenza di `lastWrite` non cambia quando il contenuto viene riscritto sul posto (scrittura
    /// o aggiunta in coda). `LocalFileSystem.writeData` però sostituisce il file (temporaneo +
    /// rename), quindi un file riscritto con `writeData` riceve una nuova data di nascita; le
    /// cartelle, per cui la legge Xcode, non ne sono toccate. Chi non la conosce la omette e vale
    /// `lastWrite`.
    public let creation: Date

    public init(kind: FileItemKind, size: Int64, lastWrite: Date, lastAccess: Date, creation: Date? = nil) {
        self.kind = kind
        self.size = size
        self.lastWrite = lastWrite
        self.lastAccess = lastAccess
        self.creation = creation ?? lastWrite
    }

    /// Il più recente fra accesso e scrittura: l'«età» di ogni regola.
    public var newestStamp: Date { max(lastWrite, lastAccess) }
}

/// Il sottoinsieme di `System.IO.Abstractions` che il Core usa, con la stessa semantica di .NET
/// su Unix. Ogni operazione che fallisce lancia `FileSystemError`. In fase 2 un'implementazione
/// sandbox aprirà l'accesso security-scoped attorno a queste stesse operazioni.
public protocol FileSystem: Sendable {
    /// Come `Directory.Exists`: segue i collegamenti; vero solo se la destinazione è una cartella.
    func directoryExists(_ path: String) -> Bool
    /// Come `File.Exists`: vero per ciò che esiste e non è una cartella. Un collegamento a una
    /// cartella vale falso, un collegamento interrotto vale vero.
    func fileExists(_ path: String) -> Bool
    /// Come `Directory.EnumerateFileSystemEntries` su un solo livello: percorsi completi, in
    /// ordine ordinale (l'ordine di `readdir` non è garantito; ordinare rende ripetibili i risultati).
    func contentsOfDirectory(_ path: String) throws -> [String]
    /// Metadati senza seguire i collegamenti (`lstat`). Un percorso inesistente lancia `ENOENT`.
    func itemInfo(_ path: String) throws -> FileItemInfo
    /// Come `File.Delete`: un percorso inesistente non è un errore; un collegamento si rimuove,
    /// la destinazione resta.
    func deleteFile(_ path: String) throws
    /// Come `Directory.Delete(path, recursive: true)`: non segue mai i collegamenti (su un
    /// collegamento rimuove solo il collegamento), prova a eliminare tutto e lancia il primo
    /// errore incontrato.
    func deleteDirectoryRecursively(_ path: String) throws
    func readData(_ path: String) throws -> Data
    /// Sostituisce il contenuto in modo atomico (file temporaneo accanto + rename).
    func writeData(_ path: String, _ data: Data) throws
    /// Aggiunge in coda, creando il file se manca.
    func appendData(_ path: String, _ data: Data) throws
    /// Come `Directory.CreateDirectory`: crea anche i livelli intermedi; una cartella esistente
    /// non è un errore.
    func createDirectory(_ path: String) throws
    /// Come `DriveInfo.AvailableFreeSpace` del volume che contiene `path`: i byte disponibili a un
    /// processo senza privilegi (`statfs`: `f_bavail × f_bsize`), senza lo spazio eliminabile
    /// che macOS libererebbe su richiesta.
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64
}

extension FileSystem {
    /// Come `FileInfo.Length`: dimensione logica; su una cartella lancia `ENOENT`, come .NET
    /// lancia `FileNotFoundException`.
    public func fileLength(_ path: String) throws -> Int64 {
        let info = try itemInfo(path)
        guard info.kind != .directory else { throw FileSystemError(code: ENOENT, path: path) }
        return info.size
    }

    public func readText(_ path: String) throws -> String {
        String(decoding: try readData(path), as: UTF8.self)
    }

    public func writeText(_ path: String, _ text: String) throws {
        try writeData(path, Data(text.utf8))
    }
}
