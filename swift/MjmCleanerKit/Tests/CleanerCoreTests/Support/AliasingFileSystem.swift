import CleanerCore
import Darwin

/// Solo Swift (piano APFS): simula, per i test del `PathGuard`, come APFS case-insensitive
/// registra i nomi. Ogni voce di `aliases` riscrive un prefisso (fino a un confine di segmento)
/// nella grafia del disco, per esempio "/Users/tester/Des\u{212A}top" → "/Users/tester/Desktop";
/// ogni voce di `failures` fa lanciare il proprio errno a `storedPath` su quel percorso esatto.
/// I confronti sono per byte UTF-8: `String` unirebbe U+212A e "K" (equivalenza canonica). Il
/// resto va al filesystem interno, vuoto per default: lì `storedPath` lancia ENOENT fino alla
/// radice e il `PathGuard` ricompone il testo.
final class AliasingFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let aliases: [(alias: [UInt8], stored: String)]
    private let failures: [(path: [UInt8], code: Int32)]

    init(_ inner: any FileSystem = InMemoryFileSystem(), aliases: [(String, String)] = [], failures: [(String, Int32)] = []) {
        self.aliases = aliases.map { (Array($0.0.utf8), $0.1) }
        self.failures = failures.map { (Array($0.0.utf8), $0.1) }
        super.init(inner)
    }

    override func storedPath(_ path: String) throws -> String {
        let bytes = Array(path.utf8)
        if let failure = failures.first(where: { $0.path == bytes }) {
            throw FileSystemError(code: failure.code, path: path)
        }
        for entry in aliases where bytes.starts(with: entry.alias) {
            let rest = bytes.dropFirst(entry.alias.count)
            if rest.isEmpty { return entry.stored }
            if rest.first == UInt8(ascii: "/") { return entry.stored + String(decoding: rest, as: UTF8.self) }
        }
        return try super.storedPath(path)
    }
}
