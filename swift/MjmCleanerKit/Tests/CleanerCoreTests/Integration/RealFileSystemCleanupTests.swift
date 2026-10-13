import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Catena reale scansione → pulizia → log su una cartella temporanea. La "home" di prova vive
/// sotto $TMPDIR (/var/folders/…), quindi ogni root passa davvero per la risoluzione
/// /var → /private/var che in produzione riguarda la categoria $TMPDIR.
struct RealFileSystemCleanupTests {
    private struct Fixture {
        let tmp: TemporaryDirectory
        let home: String
        let caches: String
        let scanner: RuleScanner
        let engine: CleanEngine

        init() throws {
            tmp = try TemporaryDirectory()
            home = try tmp.directory("home")
            caches = try tmp.directory("home/Library/Caches")
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
            scanner = RuleScanner(fileSystem: LocalFileSystem(), pathGuard: pathGuard, links: links, clock: SystemWallClock())
            engine = CleanEngine(fileSystem: LocalFileSystem(), pathGuard: pathGuard, clock: SystemWallClock())
        }

        func cleanAll(_ outcome: RuleScanOutcome, journal: (any DeletionRecording)? = nil) async -> CleanReport {
            await engine.clean([CategorySelection(categoryId: "caches", items: outcome.items)], progress: nil, journal: journal)
        }
    }

    @Test func linkToAFileIsRemovedButItsTargetSurvives() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let thesis = try fixture.tmp.file("home/Documents/tesi.docx", contents: "dati preziosi")
        try fixture.tmp.file("home/Library/Caches/app/dati.bin", contents: String(repeating: "x", count: 100))
        try fixture.tmp.file("home/Library/Caches/solo.tmp", contents: String(repeating: "y", count: 50))
        let link = try fixture.tmp.symlink("home/Library/Caches/collegamento", to: thesis)

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        #expect(outcome.items.count == 3)

        let report = await fixture.cleanAll(outcome)

        #expect(report.itemsDeleted == 3)
        #expect(report.itemsFailed == 0)
        #expect(FileManager.default.fileExists(atPath: thesis))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == nil)
        // Accreditati: 100 + 50 + la dimensione del collegamento stesso (come FileInfo.Length).
        #expect(report.bytesFreed == 150 + Int64(thesis.utf8.count))
    }

    @Test func accessDeniedInsideACacheFolderFailsOnlyThatItemWithTheRightKind() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let locked = try fixture.tmp.directory("home/Library/Caches/bloccata/sub")
        try fixture.tmp.file("home/Library/Caches/bloccata/sub/x.bin", contents: "x")
        try fixture.tmp.file("home/Library/Caches/libera.tmp", contents: "y")
        chmod(locked, 0o555)

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        let report = await fixture.cleanAll(outcome)

        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 1)
        #expect(report.errors.contains { $0.kind == .accessDenied })
    }

    // Comportamento C# replicato alla lettera (registro di parità, candidati a miglioramento):
    // un collegamento a una cartella, in clearContents, non viene eliminato.
    @Test func linkToADirectoryIsReportedAsNotFoundAndLeftInPlace() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Documents/fatture/2026.pdf", contents: "dati")
        let link = try fixture.tmp.symlink("home/Library/Caches/versoCartella", to: fixture.home + "/Documents")

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        let report = await fixture.cleanAll(outcome)

        #expect(report.itemsFailed == 1)
        #expect(report.errors.contains { $0.kind == .notFound })
        #expect(FileManager.default.fileExists(atPath: fixture.home + "/Documents/fatture/2026.pdf"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil)
    }

    @Test func deletedPathsAreResolvedUnderPrivateVarAndReachTheJournalAndTheSessionLog() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Library/Caches/a.tmp", contents: "a")
        let support = try fixture.tmp.directory("support")
        let writer = SessionLogWriter(fileSystem: LocalFileSystem(), paths: AppPaths(supportDirectory: support))
        let journal = try #require(writer.openJournal(startedAt: Date()))

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        let report = await fixture.cleanAll(outcome, journal: journal)

        // La root dichiarata è sotto /var/folders; il percorso eliminato è quello risolto dal guard.
        let deleted = try #require(report.deletedPaths.first)
        #expect(deleted.hasPrefix("/private/var/"))
        #expect(try LocalFileSystem().readText(journal.path).contains(deleted))

        try await writer.write(sessionId: 1, report: report)
        writer.discard(journal)

        let log = try LocalFileSystem().readData(PathText.join(AppPaths(supportDirectory: support).logsDirectory, "session-000001.jsonl.gz"))
        #expect(String(decoding: try Gzip.decompress(log), as: UTF8.self).contains(deleted))
        #expect(!FileManager.default.fileExists(atPath: journal.path))
    }
}
