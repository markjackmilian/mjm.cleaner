import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Ogni test riproduce un comportamento misurato su .NET 10 (vedi «Fatti misurati» nel piano):
/// il porting deve vedere il filesystem come lo vedeva l'app C#.
struct LocalFileSystemTests {
    private let fs = LocalFileSystem()

    @Test func directoryExistsFollowsLinksLikeDotNet() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("dir")
        let link = try tmp.symlink("link", to: dir)
        #expect(fs.directoryExists(dir))
        #expect(fs.directoryExists(link))
        #expect(!fs.directoryExists(tmp.path + "/assente"))
    }

    @Test func fileExistsMirrorsDotNetForLinks() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("dir")
        let file = try tmp.file("dir/f.txt", contents: "12345")
        #expect(fs.fileExists(file))
        #expect(!fs.fileExists(dir))
        #expect(!fs.fileExists(try tmp.symlink("versoCartella", to: dir)))
        #expect(fs.fileExists(try tmp.symlink("versoFile", to: file)))
        #expect(fs.fileExists(try tmp.symlink("interrotto", to: tmp.path + "/manca")))
    }

    @Test func itemInfoReadsTheLinkItselfNotTheTarget() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let target = try tmp.file("vecchio.txt", contents: "12345")
        let old = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: target)
        let link = try tmp.symlink("link", to: target)

        let info = try fs.itemInfo(link)

        #expect(info.kind == .symbolicLink)
        #expect(info.size == Int64(target.utf8.count))
        #expect(info.lastWrite > old)
        #expect(try fs.itemInfo(target).size == 5)
    }

    @Test func itemInfoOnMissingPathThrowsNotFound() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/assente")) {
            try fs.itemInfo(tmp.path + "/assente")
        }
    }

    @Test func fileLengthOnADirectoryThrowsNotFoundLikeFileInfoLength() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("dir")
        #expect(throws: FileSystemError(code: ENOENT, path: dir)) { try fs.fileLength(dir) }
    }

    @Test func contentsOfDirectoryReturnsSortedFullPaths() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.file("b.txt"); try tmp.file("a.txt"); try tmp.directory("c")
        #expect(try fs.contentsOfDirectory(tmp.path) == [tmp.path + "/a.txt", tmp.path + "/b.txt", tmp.path + "/c"])
    }

    @Test func contentsOfMissingDirectoryThrowsNotFound() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/assente")) {
            try fs.contentsOfDirectory(tmp.path + "/assente")
        }
    }

    @Test func deleteFileIgnoresMissingPathLikeFileDelete() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try fs.deleteFile(tmp.path + "/assente")
    }

    @Test func deleteFileRemovesTheLinkNotTheTarget() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let target = try tmp.file("tesi.docx", contents: "x")
        let link = try tmp.symlink("link", to: target)
        try fs.deleteFile(link)
        #expect(!FileManager.default.fileExists(atPath: link))
        #expect(FileManager.default.fileExists(atPath: target))
    }

    @Test func deleteDirectoryRecursivelyNeverFollowsLinks() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let precious = try tmp.file("Documents/fatture/2026.pdf", contents: "dati")
        try tmp.file("cache/app/dati.bin", contents: "x")
        try tmp.symlink("cache/app/collegamento", to: tmp.path + "/Documents")

        try fs.deleteDirectoryRecursively(tmp.path + "/cache")

        #expect(!FileManager.default.fileExists(atPath: tmp.path + "/cache"))
        #expect(FileManager.default.fileExists(atPath: precious))
    }

    @Test func deleteDirectoryRecursivelyOnALinkRemovesOnlyTheLink() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let precious = try tmp.file("Documents/tesi.docx", contents: "dati")
        let link = try tmp.symlink("link", to: tmp.path + "/Documents")

        try fs.deleteDirectoryRecursively(link)

        #expect(!FileManager.default.fileExists(atPath: link))
        #expect(FileManager.default.fileExists(atPath: precious))
    }

    @Test func deleteDirectoryRecursivelyOnALinkWithTrailingSlashRemovesOnlyTheLink() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let precious = try tmp.file("Documents/tesi.docx", contents: "dati")
        let link = try tmp.symlink("link", to: tmp.path + "/Documents")

        try fs.deleteDirectoryRecursively(link + "/")

        #expect(!FileManager.default.fileExists(atPath: link))
        #expect(FileManager.default.fileExists(atPath: precious))
    }

    @Test func deleteDirectoryRecursivelyReportsTheChildAccessDenied() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let locked = try tmp.directory("locked/sub")
        try tmp.file("locked/sub/x.txt", contents: "x")
        try tmp.file("locked/y.txt", contents: "y")
        chmod(locked, 0o555)

        #expect(throws: FileSystemError(code: EACCES, path: locked + "/x.txt")) {
            try fs.deleteDirectoryRecursively(tmp.path + "/locked")
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.path + "/locked/y.txt"))
    }

    // Solo Swift (correzione del 2026-10-15): una sottocartella che non si legge resta al suo posto
    // e il suo errore è il primo, prima di quello della cartella che non si svuota.
    @Test func deleteDirectoryRecursivelyReportsAnUnreadableSubdirectory() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let unreadable = try tmp.directory("tree/chiusa")
        try tmp.file("tree/chiusa/x.txt", contents: "x")
        try tmp.file("tree/z.txt", contents: "z")
        chmod(unreadable, 0o300)

        #expect(throws: FileSystemError(code: EACCES, path: unreadable)) {
            try fs.deleteDirectoryRecursively(tmp.path + "/tree")
        }
        #expect(FileManager.default.fileExists(atPath: unreadable + "/x.txt"))
        #expect(!FileManager.default.fileExists(atPath: tmp.path + "/tree/z.txt"))
    }

    // Solo Swift (correzione del 2026-10-15): con più errori vale il primo nell'ordine di
    // `contentsOfDirectory`, come nella cancellazione ricorsiva di .NET.
    @Test func deleteDirectoryRecursivelyReportsTheFirstFailureInListingOrder() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let first = try tmp.directory("tree/a")
        let second = try tmp.directory("tree/b")
        try tmp.file("tree/a/x.txt", contents: "x")
        try tmp.file("tree/b/x.txt", contents: "x")
        chmod(first, 0o555)
        chmod(second, 0o555)

        #expect(throws: FileSystemError(code: EACCES, path: first + "/x.txt")) {
            try fs.deleteDirectoryRecursively(tmp.path + "/tree")
        }
    }

    // Solo Swift (crash del 2026-10-15 nell'app): la cancellazione scendeva di una chiamata per
    // livello e una cartella di qualche centinaio di livelli esauriva lo stack del thread.
    @Test func deleteDirectoryRecursivelyRemovesATreeDeeperThanTheStack() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let deep = try tmp.deepTree("deep")
        try #require(deep.depth >= 300)

        try await onSmallStack { try LocalFileSystem().deleteDirectoryRecursively(deep.root) }

        #expect(!FileManager.default.fileExists(atPath: deep.root))
    }

    @Test func writeDataReplacesAndAppendDataCreatesThenAppends() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = tmp.path + "/impostazioni.json"
        try fs.writeData(file, Data("uno".utf8))
        try fs.writeData(file, Data("due".utf8))
        #expect(try fs.readText(file) == "due")

        let journal = tmp.path + "/diario.jsonl"
        try fs.appendData(journal, Data("a\n".utf8))
        try fs.appendData(journal, Data("b\n".utf8))
        #expect(try fs.readText(journal) == "a\nb\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).sorted() == ["diario.jsonl", "impostazioni.json"])
    }

    @Test func createDirectoryCreatesIntermediatesAndToleratesExisting() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try fs.createDirectory(tmp.path + "/a/b/c")
        try fs.createDirectory(tmp.path + "/a/b/c")
        #expect(fs.directoryExists(tmp.path + "/a/b/c"))
    }

    /// `.app` è un pacchetto per ogni Mac; `.utm` e `.VMwareVM` lo sono grazie al ripiego per
    /// estensione anche dove UTM e VMware Fusion non sono installati. Una cartella qualunque, un file
    /// con estensione da pacchetto, un collegamento a un pacchetto e un percorso assente no.
    /// Un collegamento con estensione da macchina virtuale non è un pacchetto, e la lista del ripiego è fissata.
    @Test func isPackageRecognisesBundlesAndVirtualMachines() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let app = try tmp.directory("Strumento.app")
        let utm = try tmp.directory("Linux.utm")
        let vmware = try tmp.directory("Windows.VMwareVM")
        let pvm = try tmp.directory("Windows 11.pvm")
        let plain = try tmp.directory("cartella")
        let file = try tmp.file("finto.pvm", contents: "x")
        let link = try tmp.symlink("collegamento.app", to: app)
        let vmLink = try tmp.symlink("collegamento.utm", to: utm)

        #expect(fs.isPackage(app))
        #expect(fs.isPackage(utm))
        #expect(fs.isPackage(vmware))
        #expect(fs.isPackage(pvm))
        #expect(!fs.isPackage(plain))
        #expect(!fs.isPackage(file))
        #expect(!fs.isPackage(link))
        #expect(!fs.isPackage(vmLink))
        #expect(!fs.isPackage(tmp.path + "/assente.app"))
        #expect(Set(LocalFileSystem.virtualMachinePackageExtensions) == ["pvm", "vmwarevm", "utm"])
    }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func defaultApfsVolumeIsCaseInsensitive() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.file("Documents/tesi.docx")
        #expect(fs.fileExists(tmp.path + "/documents/TESI.docx"))
    }
}

extension TemporaryDirectory {
    /// Vero sul volume dati predefinito di macOS; falso su un volume APFS case-sensitive.
    static var volumeIsCaseInsensitive: Bool {
        pathconf(FileManager.default.temporaryDirectory.path(percentEncoded: false), _PC_CASE_SENSITIVE) == 0
    }
}
