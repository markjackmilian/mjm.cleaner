import Darwin

/// Riconosce i collegamenti simbolici. Separato da `FileSystem` come `ILinkInspector` in C#: i
/// test del `PathGuard` e degli scanner simulano i collegamenti senza un filesystem che li modelli.
public protocol LinkInspecting: Sendable {
    func isSymbolicLink(_ path: String) -> Bool

    /// La destinazione finale del collegamento (catena seguita per intero), oppure `nil` se
    /// `path` non è un collegamento o la destinazione non è determinabile. Come
    /// `ResolveLinkTarget(returnFinalTarget: true).FullName`: una destinazione relativa si risolve
    /// rispetto alla cartella del collegamento con normalizzazione testuale, e la destinazione
    /// finale può anche non esistere.
    func resolveLinkTarget(_ path: String) -> String?
}

public struct FileSystemLinkInspector: LinkInspecting {
    /// Stesso ordine di grandezza di MAXSYMLINKS (32) su macOS: oltre, è un ciclo.
    private static let maxHops = 32

    public init() {}

    public func isSymbolicLink(_ path: String) -> Bool {
        var status = stat()
        return lstat(path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
    }

    public func resolveLinkTarget(_ path: String) -> String? {
        guard isSymbolicLink(path) else { return nil }

        var current = path
        for _ in 0..<Self.maxHops {
            guard isSymbolicLink(current) else { return current }
            guard let destination = readLink(current) else { return nil }
            let base = PathText.parent(current) ?? "/"
            current = PathText.normalize(destination.utf8.first == UInt8(ascii: "/") ? destination : PathText.join(base, destination))
        }
        return nil
    }

    private func readLink(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlink(path, &buffer, buffer.count - 1)
        guard count >= 0 else { return nil }
        return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
