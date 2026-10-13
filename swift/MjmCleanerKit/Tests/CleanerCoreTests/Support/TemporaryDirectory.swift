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
