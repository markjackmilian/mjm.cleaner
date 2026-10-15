import Darwin
import Foundation

/// Cartella temporanea reale per i test di integrazione: il filesystem simulato non riproduce
/// collegamenti simbolici, permessi né il comportamento di APFS.
struct TemporaryDirectory {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        path = (base.hasSuffix("/") ? base : base + "/") + "mjm-cleaner-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ relative: String, contents: String = "") throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: full))
        return full
    }

    @discardableResult
    func directory(_ relative: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    @discardableResult
    func symlink(_ relative: String, to destination: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: full, withDestinationPath: destination)
        return full
    }

    /// Una catena di cartelle `a/a/…/a` sotto `relative`, lunga quanto entra con un margine in
    /// PATH_MAX (1024 byte, terminatore compreso), con un file a metà e uno in fondo. Restituisce la
    /// cartella di partenza, i livelli e i byte dei due file.
    func deepTree(_ relative: String) throws -> (root: String, depth: Int, bytes: Int64) {
        let root = path + "/" + relative
        let depth = (1000 - root.utf8.count) / 2
        let middle = root + String(repeating: "/a", count: depth / 2)
        let bottom = root + String(repeating: "/a", count: depth)
        try FileManager.default.createDirectory(atPath: bottom, withIntermediateDirectories: true)
        try Data("metà".utf8).write(to: URL(fileURLWithPath: middle + "/m"))
        try Data("fondo".utf8).write(to: URL(fileURLWithPath: bottom + "/f"))
        return (root, depth, Int64("metà".utf8.count + "fondo".utf8.count))
    }

    /// Ripristina i permessi prima di rimuovere: alcuni test tolgono la scrittura a una cartella.
    func remove() {
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let relative as String in enumerator {
                chmod(path + "/" + relative, 0o755)
            }
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}
