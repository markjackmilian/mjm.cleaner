import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Il doppio deve comportarsi come `MockFileSystem` nei punti su cui i test C# contavano.
struct InMemoryFileSystemTests {
    @Test func addFileCreatesParentDirectories() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/Library/Caches/app/dati.bin", size: 100)
        #expect(fs.directoryExists("/Users/tester/Library/Caches/app"))
        #expect(fs.fileExists("/Users/tester/Library/Caches/app/dati.bin"))
        #expect(try fs.contentsOfDirectory("/Users/tester/Library/Caches") == ["/Users/tester/Library/Caches/app"])
        #expect(try fs.fileLength("/Users/tester/Library/Caches/app/dati.bin") == 100)
    }

    @Test func filesCarryTheirStampsAndDirectoriesCanBeAged() throws {
        let fs = InMemoryFileSystem()
        let old = utc(2020, 1, 1)
        fs.addFile("/a/f.txt", size: 1, stamp: old)
        fs.setTimes("/a", lastWrite: old, lastAccess: old)
        #expect(try fs.itemInfo("/a/f.txt").newestStamp == old)
        #expect(try fs.itemInfo("/a").newestStamp == old)
        #expect(try fs.itemInfo("/a").kind == .directory)
    }

    @Test func missingPathsBehaveLikeDotNet() throws {
        let fs = InMemoryFileSystem()
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) { try fs.itemInfo("/manca") }
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) { try fs.contentsOfDirectory("/manca") }
        try fs.deleteFile("/manca")
    }

    @Test func deleteDirectoryRecursivelyRemovesTheWholeSubtree() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/c/app/a/1.bin", size: 1)
        fs.addFile("/c/altro.bin", size: 1)
        try fs.deleteDirectoryRecursively("/c/app")
        #expect(!fs.directoryExists("/c/app"))
        #expect(!fs.fileExists("/c/app/a/1.bin"))
        #expect(fs.fileExists("/c/altro.bin"))
    }

    @Test func textRoundTripsAndAppendCreates() throws {
        let fs = InMemoryFileSystem()
        try fs.createDirectory("/s/logs")
        try fs.writeText("/s/settings.json", "{}")
        try fs.appendData("/s/logs/p.jsonl", Data("a\n".utf8))
        try fs.appendData("/s/logs/p.jsonl", Data("b\n".utf8))
        #expect(try fs.readText("/s/settings.json") == "{}")
        #expect(try fs.readText("/s/logs/p.jsonl") == "a\nb\n")
    }

    @Test func writeIntoMissingDirectoryFailsLikeDotNet() {
        let fs = InMemoryFileSystem()
        #expect(throws: FileSystemError.self) { try fs.writeText("/manca/x.json", "{}") }
    }
}
