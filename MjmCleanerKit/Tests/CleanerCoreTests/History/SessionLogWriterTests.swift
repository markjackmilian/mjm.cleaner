import Darwin
import Foundation
import Testing
@testable import CleanerCore

struct SessionLogWriterTests {
    private static let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")

    private func report(_ deletedPaths: String...) -> CleanReport {
        CleanReport(startedAt: Date(timeIntervalSince1970: 0), duration: .zero, bytesFreed: 0,
                    itemsDeleted: deletedPaths.count, itemsFailed: 0, categories: [], errors: [], deletedPaths: deletedPaths)
    }

    private func logNames(_ fs: InMemoryFileSystem) throws -> [String] {
        try fs.contentsOfDirectory(Self.paths.logsDirectory).map(PathText.fileName).sorted()
    }

    private func lines(_ fs: InMemoryFileSystem, _ file: String) throws -> [String] {
        String(decoding: try Gzip.decompress(fs.readData(file)), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    /// Doppio locale: la scrittura del log principale fallisce con accesso negato (in C# il file
    /// veniva marcato ReadOnly su MockFileSystem, che il doppio Swift non modella).
    private final class FailingWriteFileSystem: ForwardingFileSystem, @unchecked Sendable {
        override func writeData(_ path: String, _ data: Data) throws {
            throw FileSystemError(code: EACCES, path: path)
        }
    }

    @Test func writesOneLinePerDeletedPath() async throws {
        let fs = InMemoryFileSystem()
        try await SessionLogWriter(fileSystem: fs, paths: Self.paths).write(sessionId: 7, report: report("/a/uno.tmp", "/a/due.tmp"))

        let file = PathText.join(Self.paths.logsDirectory, "session-000007.jsonl.gz")
        #expect(fs.fileExists(file))
        let content = try lines(fs, file)
        #expect(content.count == 2)
        #expect(content.first?.contains("/a/uno.tmp") == true)
        #expect(content.last?.contains("/a/due.tmp") == true)
    }

    @Test func keepsOnlyTheMostRecentSessions() async throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths, retention: 3)

        for id in Int64(1)...5 {
            try await writer.write(sessionId: id, report: report("/a/\(id).tmp"))
        }

        #expect(try logNames(fs) == ["session-000003.jsonl.gz", "session-000004.jsonl.gz", "session-000005.jsonl.gz"])
    }

    @Test func createsTheLogsDirectoryWhenMissing() async throws {
        let fs = InMemoryFileSystem()
        try await SessionLogWriter(fileSystem: fs, paths: Self.paths).write(sessionId: 1, report: report("/a/x.tmp"))
        #expect(fs.directoryExists(Self.paths.logsDirectory))
    }

    // Oltre le sei cifre l'ordinamento lessicografico capovolge l'ordine ("1000000" < "999999"):
    // la rotazione deve ordinare sul valore numerico, o cancellerebbe la sessione appena scritta.
    @Test func ordersRotationByNumericSessionIdNotByString() async throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths, retention: 3)

        for id: Int64 in [999_997, 999_998, 999_999, 1_000_000] {
            try await writer.write(sessionId: id, report: report("/a/\(id).tmp"))
        }

        #expect(try logNames(fs) == ["session-1000000.jsonl.gz", "session-999998.jsonl.gz", "session-999999.jsonl.gz"])
    }

    // Una pulizia che non ha eliminato nulla scrive comunque un gzip valido con zero righe. Il
    // test C# fissava anche la lunghezza (15 byte) del gzip di .NET: è un dettaglio della libreria,
    // non un comportamento, e non si porta.
    @Test func writesAValidEmptyLogFileWhenNothingWasDeleted() async throws {
        let fs = InMemoryFileSystem()
        try await SessionLogWriter(fileSystem: fs, paths: Self.paths).write(sessionId: 1, report: report())

        let file = PathText.join(Self.paths.logsDirectory, "session-000001.jsonl.gz")
        #expect(fs.fileExists(file))
        #expect(try Gzip.decompress(fs.readData(file)).isEmpty)
    }

    // Solo la rotazione ignora i propri errori: un fallimento della scrittura principale deve
    // arrivare al chiamante.
    @Test func propagatesFailuresFromTheMainWriteInsteadOfSwallowingThem() async throws {
        let writer = SessionLogWriter(fileSystem: FailingWriteFileSystem(InMemoryFileSystem()), paths: Self.paths)

        await #expect(throws: FileSystemError.self) {
            try await writer.write(sessionId: 1, report: report("/a/x.tmp"))
        }
    }

    // MARK: - Nuovi (spec §8.2): diario della pulizia

    @Test func jsonLineEscapesQuotesBackslashesAndControlCharacters() throws {
        let path = "/a/\"strano\"\\nome\n\tfine"
        let line = SessionLogWriter.jsonLine(path)
        #expect(line.hasSuffix("\n"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String])
        #expect(object == ["path": path])
    }

    @Test func journalAppendsOneLinePerDeletedPathAndSurvivesWithoutTheSessionLog() throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths)
        let journal = try #require(writer.openJournal(startedAt: utc(2026, 9, 15, 10, 30)))

        journal.recordDeleted("/a/uno.tmp")
        journal.recordDeleted("/a/due.tmp")

        #expect(PathText.fileName(journal.path) == "pending-20260915T103000Z.jsonl")
        let lines = try fs.readText(journal.path).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first?.contains("/a/uno.tmp") == true)
    }

    @Test func discardRemovesTheJournal() throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths)
        let journal = try #require(writer.openJournal(startedAt: utc(2026, 9, 15)))

        writer.discard(journal)

        #expect(!fs.fileExists(journal.path))
    }

    @Test func rotationNeverTouchesPendingJournals() async throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths, retention: 1)
        let journal = try #require(writer.openJournal(startedAt: utc(2026, 9, 15)))
        journal.recordDeleted("/a/sopravvissuto.tmp")

        try await writer.write(sessionId: 1, report: report("/a/1.tmp"))
        try await writer.write(sessionId: 2, report: report("/a/2.tmp"))

        #expect(try logNames(fs) == ["pending-20260915T000000Z.jsonl", "session-000002.jsonl.gz"])
    }
}
