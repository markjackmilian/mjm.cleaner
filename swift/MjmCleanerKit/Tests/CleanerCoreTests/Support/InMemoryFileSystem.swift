import CleanerCore
import Darwin
import Foundation
import Synchronization

/// Filesystem simulato con la semantica di `MockFileSystem` su cui contavano i test C#: le
/// cartelle intermedie nascono da sole con la data corrente, i collegamenti simbolici non
/// esistono (li simula `FakeLinkInspector`), i percorsi distinguono maiuscole e minuscole,
/// `deleteFile` su un percorso inesistente non è un errore. La dimensione di un file creato con
/// `size:` è solo dichiarata, senza allocare i byte: alcuni test usano file da centinaia di MB.
final class InMemoryFileSystem: FileSystem {
    private struct Node {
        var isDirectory: Bool
        var size: Int64
        var contents: Data
        var lastWrite: Date
        var lastAccess: Date
        var creation: Date

        static func directory(_ stamp: Date) -> Node {
            Node(isDirectory: true, size: 0, contents: Data(), lastWrite: stamp, lastAccess: stamp, creation: stamp)
        }
    }

    private let nodes = Mutex<[String: Node]>(["/": .directory(Date())])
    private let freeSpace = Mutex<Int64>(0)

    init() {}

    // MARK: - Costruzione dello scenario

    func addFile(_ path: String, size: Int64 = 0, stamp: Date = Date()) {
        store(path, Node(isDirectory: false, size: size, contents: Data(), lastWrite: stamp, lastAccess: stamp, creation: stamp))
    }

    func addFile(_ path: String, text: String, stamp: Date = Date()) {
        let data = Data(text.utf8)
        store(path, Node(isDirectory: false, size: Int64(data.count), contents: data, lastWrite: stamp, lastAccess: stamp, creation: stamp))
    }

    /// Lo spazio libero che `availableFreeSpace` riporta per ogni percorso esistente.
    func setAvailableFreeSpace(_ bytes: Int64) {
        freeSpace.withLock { $0 = bytes }
    }

    func addDirectory(_ path: String) {
        let key = Self.key(path)
        nodes.withLock { nodes in
            Self.ensureParents(of: key, in: &nodes)
            if nodes[key] == nil { nodes[key] = .directory(Date()) }
        }
    }

    func setTimes(_ path: String, lastWrite: Date, lastAccess: Date) {
        let key = Self.key(path)
        nodes.withLock { nodes in
            nodes[key]?.lastWrite = lastWrite
            nodes[key]?.lastAccess = lastAccess
        }
    }

    // MARK: - FileSystem

    func directoryExists(_ path: String) -> Bool {
        nodes.withLock { $0[Self.key(path)]?.isDirectory == true }
    }

    func fileExists(_ path: String) -> Bool {
        nodes.withLock { $0[Self.key(path)]?.isDirectory == false }
    }

    func contentsOfDirectory(_ path: String) throws -> [String] {
        let key = Self.key(path)
        return try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            guard node.isDirectory else { throw FileSystemError(code: ENOTDIR, path: path) }
            return nodes.keys.filter { $0 != "/" && PathText.parent($0) == key }.sorted()
        }
    }

    func itemInfo(_ path: String) throws -> FileItemInfo {
        let key = Self.key(path)
        return try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            return FileItemInfo(
                kind: node.isDirectory ? .directory : .file,
                size: node.isDirectory ? 0 : node.size,
                lastWrite: node.lastWrite,
                lastAccess: node.lastAccess,
                creation: node.creation)
        }
    }

    func deleteFile(_ path: String) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            guard let node = nodes[key] else { return }
            guard !node.isDirectory else { throw FileSystemError(code: EPERM, path: path) }
            nodes[key] = nil
        }
    }

    func deleteDirectoryRecursively(_ path: String) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            guard node.isDirectory else { throw FileSystemError(code: ENOTDIR, path: path) }
            let doomed = nodes.keys.filter { $0 == key || $0.hasPrefix(key + "/") }
            for candidate in doomed {
                nodes[candidate] = nil
            }
        }
    }

    func readData(_ path: String) throws -> Data {
        let key = Self.key(path)
        return try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            guard !node.isDirectory else { throw FileSystemError(code: EISDIR, path: path) }
            return node.contents
        }
    }

    func writeData(_ path: String, _ data: Data) throws {
        try write(path) { _ in data }
    }

    func appendData(_ path: String, _ data: Data) throws {
        try write(path) { existing in (existing ?? Data()) + data }
    }

    func createDirectory(_ path: String) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            if let node = nodes[key], !node.isDirectory { throw FileSystemError(code: EEXIST, path: path) }
            Self.ensureParents(of: key, in: &nodes)
            if nodes[key] == nil { nodes[key] = .directory(Date()) }
        }
    }

    /// Come `statfs`: un percorso inesistente lancia `ENOENT`.
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64 {
        let key = Self.key(path)
        guard nodes.withLock({ $0[key] != nil }) else { throw FileSystemError(code: ENOENT, path: path) }
        return freeSpace.withLock { $0 }
    }

    // MARK: - Privati

    private func store(_ path: String, _ node: Node) {
        let key = Self.key(path)
        nodes.withLock { nodes in
            Self.ensureParents(of: key, in: &nodes)
            nodes[key] = node
        }
    }

    /// Come `File.WriteAllText` di .NET: la cartella padre deve esistere.
    private func write(_ path: String, _ transform: (Data?) -> Data) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            guard let parent = PathText.parent(key), nodes[parent]?.isDirectory == true else {
                throw FileSystemError(code: ENOENT, path: path)
            }
            if nodes[key]?.isDirectory == true { throw FileSystemError(code: EISDIR, path: path) }
            let data = transform(nodes[key]?.contents)
            let now = Date()
            nodes[key] = Node(
                isDirectory: false, size: Int64(data.count), contents: data,
                lastWrite: now, lastAccess: now, creation: nodes[key]?.creation ?? now)
        }
    }

    private static func key(_ path: String) -> String {
        let trimmed = PathText.trimmingTrailingSlashes(path)
        return trimmed.isEmpty ? "/" : trimmed
    }

    private static func ensureParents(of key: String, in nodes: inout [String: Node]) {
        var missing: [String] = []
        var current = PathText.parent(key)
        while let directory = current, !directory.isEmpty, nodes[directory] == nil {
            missing.append(directory)
            current = PathText.parent(directory)
        }
        for directory in missing.reversed() {
            nodes[directory] = .directory(Date())
        }
    }
}
