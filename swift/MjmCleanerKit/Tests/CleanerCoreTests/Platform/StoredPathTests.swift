import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// `FileSystem.storedPath` (piano APFS, spec §12): le misure dello spike del 2026-10-16
/// (`docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md`) fissate sul disco reale. I
/// percorsi si confrontano per byte UTF-8: l'uguaglianza di `String` unirebbe NFC e NFD.
struct StoredPathTests {
    private let fs = LocalFileSystem()

    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive), arguments: [
        ("Desktop", "Des\u{212A}top"),
        ("Desktop", "De\u{017F}ktop"),
        ("Desktop", "DESKTOP"),
        ("Messages", "Me\u{00DF}ages"),
        ("caf\u{00E9}", "cafe\u{0301}"),
    ])
    func storedPathSpellsNamesAsTheDiskStoresThem(stored: String, alias: String) throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        // `mkdir` e non FileManager, che scriverebbe il nome in NFD (`fileSystemRepresentation`).
        #expect(mkdir(tmp.path + "/" + stored, 0o755) == 0)
        try tmp.file(stored + "/x")
        let base = try fs.storedPath(tmp.path)

        #expect(bytes(try fs.storedPath(tmp.path + "/" + alias + "/x")) == bytes(base + "/" + stored + "/x"))
        #expect(bytes(try fs.storedPath(tmp.path + "/" + alias)) == bytes(base + "/" + stored))
    }

    @Test func storedPathResolvesLinkedAncestorsButNotTheLastComponent() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.file("dir/f")
        try tmp.symlink("link", to: tmp.path + "/dir")
        let base = try fs.storedPath(tmp.path)

        // La cartella temporanea sta sotto /var/folders: /var è un collegamento a /private/var.
        #expect(base.hasPrefix("/private/var/"))
        #expect(try fs.storedPath(tmp.path + "/link") == base + "/link")
        #expect(try fs.storedPath(tmp.path + "/link/f") == base + "/dir/f")
    }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func storedPathOfAHardLinkIsTheNameThatWasLookedUp() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let original = try tmp.file("Desktop/x", contents: "dati")
        try tmp.directory("Caches")
        #expect(link(original, tmp.path + "/Caches/y") == 0)
        let base = try fs.storedPath(tmp.path)

        #expect(try fs.storedPath(tmp.path + "/Caches/y") == base + "/Caches/y")
        #expect(try fs.storedPath(tmp.path + "/Des\u{212A}top/x") == base + "/Desktop/x")
        #expect(try fs.storedPath(tmp.path + "/Caches/y") == base + "/Caches/y")
    }

    @Test func storedPathOfTheRootAndOfTheHomeKeepsTheUserVisibleSpelling() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmed = PathText.trimmingTrailingSlashes(home)

        #expect(try fs.storedPath("/") == "/")
        // /Users è un firmlink verso /System/Volumes/Data/Users: resta nella forma che vede l'utente.
        #expect(try fs.storedPath(trimmed) == trimmed)
    }

    @Test func storedPathReportsTheErrnoOfTheLookup() throws {
        let headerSize = MemoryLayout<UInt32>.size
        let referenceSize = MemoryLayout<attrreference_t>.size
        func response(offset: Int32, bytes: [UInt8]) -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: headerSize + referenceSize + bytes.count)
            var reference = attrreference_t()
            reference.attr_dataoffset = offset
            reference.attr_length = UInt32(bytes.count)
            withUnsafeBytes(of: &reference) { raw in
                buffer.replaceSubrange(headerSize..<(headerSize + referenceSize), with: raw)
            }
            let start = headerSize + Int(offset)
            if start >= 0, start + bytes.count <= buffer.count {
                buffer.replaceSubrange(start..<(start + bytes.count), with: bytes)
            }
            return buffer
        }

        #expect(throws: FileSystemError(code: EIO, path: "synthetic")) {
            try LocalFileSystem.parseStoredPathResponse(response(offset: Int32(referenceSize), bytes: [0]), path: "synthetic")
        }
        #expect(throws: FileSystemError(code: EIO, path: "synthetic")) {
            try LocalFileSystem.parseStoredPathResponse(response(offset: 0, bytes: [65, 0]), path: "synthetic")
        }
        #expect(throws: FileSystemError(code: EIO, path: "synthetic")) {
            try LocalFileSystem.parseStoredPathResponse(response(offset: Int32(referenceSize), bytes: [65]), path: "synthetic")
        }

        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = try tmp.file("file")
        let locked = try tmp.directory("chiusa/dentro")
        try tmp.symlink("ciclo1", to: tmp.path + "/ciclo2")
        try tmp.symlink("ciclo2", to: tmp.path + "/ciclo1")
        let deep = try tmp.deepTree("profondo")
        let bottom = deep.root + String(repeating: "/a", count: deep.depth)
        try tmp.symlink("corto", to: bottom)
        let chiusa = tmp.path + "/chiusa"
        chmod(chiusa, 0o600)
        defer { chmod(chiusa, 0o755) }

        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/manca/x")) { try fs.storedPath(tmp.path + "/manca/x") }
        #expect(throws: FileSystemError(code: ENOTDIR, path: file + "/x")) { try fs.storedPath(file + "/x") }
        #expect(throws: FileSystemError(code: EACCES, path: locked)) { try fs.storedPath(locked) }
        #expect(throws: FileSystemError(code: ELOOP, path: tmp.path + "/ciclo1/x")) { try fs.storedPath(tmp.path + "/ciclo1/x") }
        // Un collegamento corto verso un percorso lungo: la risoluzione supera MAXPATHLEN.
        let tooLong = tmp.path + "/corto" + String(repeating: "/b", count: 40)
        #expect(throws: FileSystemError(code: ENAMETOOLONG, path: tooLong)) { try fs.storedPath(tooLong) }
        // La cartella chiusa resta leggibile come oggetto: manca solo il permesso di attraversarla.
        #expect(try fs.storedPath(chiusa) == (try fs.storedPath(tmp.path)) + "/chiusa")
    }

    @Test func inMemoryStoredPathIsTheNodeKeyAndMissingPathsThrow() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/Library/Caches/a.bin", size: 1)

        #expect(try fs.storedPath("/Users/tester/Library/Caches/a.bin") == "/Users/tester/Library/Caches/a.bin")
        #expect(try fs.storedPath("/") == "/")
        #expect(throws: FileSystemError(code: ENOENT, path: "/Users/tester/library")) { try fs.storedPath("/Users/tester/library") }
    }

    @Test func forwardingFileSystemForwardsTheStoredPath() throws {
        let inner = InMemoryFileSystem()
        inner.addDirectory("/Users/tester/Library")

        #expect(try ForwardingFileSystem(inner).storedPath("/Users/tester/Library") == "/Users/tester/Library")
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) { try ForwardingFileSystem(inner).storedPath("/manca") }
    }
}
