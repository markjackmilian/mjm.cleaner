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
            let fs = LocalFileSystem()
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fs, links: links, homeDirectory: home)
            scanner = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock())
            engine = CleanEngine(fileSystem: fs, pathGuard: pathGuard, clock: SystemWallClock())
        }

        func cleanAll(_ outcome: RuleScanOutcome, journal: (any DeletionRecording)? = nil) async -> CleanReport {
            await engine.clean([CategorySelection(categoryId: "caches", items: outcome.items)], progress: nil, journal: journal)
        }

        /// Come nell'app: `ScanEngine` scansiona ogni categoria in un task del pool cooperativo.
        func scanOnTheCooperativePool(_ rule: CleanupRule) async throws -> RuleScanOutcome {
            let category = CleanupCategory(
                id: "caches", displayName: "caches", description: "", risk: .low, selectedByDefault: true, parentId: nil, rules: [rule])
            let result = try #require(try await ScanEngine(scanner: scanner).scan([category], progress: nil).first)
            return RuleScanOutcome(items: result.items, errors: result.errors, exclusions: result.exclusions)
        }

        /// Un albero profondo sotto le cache, con una cartella "bin" e un file in fondo: per
        /// `matchingDirs` la cartella da trovare è all'ultimo livello.
        func deepTreeWithABinAtTheBottom() throws -> (root: String, middle: String, bottom: String, bytes: Int64) {
            let deep = try tmp.deepTree("home/Library/Caches/deep")
            try #require(deep.depth >= 300)
            let bottom = deep.root + String(repeating: "/a", count: deep.depth)
            try tmp.file("home/Library/Caches/deep" + String(repeating: "/a", count: deep.depth) + "/bin/x", contents: "x")
            return (deep.root, deep.root + String(repeating: "/a", count: deep.depth / 2), bottom, deep.bytes + 1)
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

    // Solo Swift (crash del 2026-10-15 nell'app): misura e cancellazione scendevano di una chiamata
    // per livello di cartella; una cartella di qualche centinaio di livelli esauriva lo stack.
    @Test func aFolderDeeperThanTheStackIsMeasuredOnASmallStack() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let deep = try fixture.tmp.deepTree("home/Library/Caches/deep")
        try #require(deep.depth >= 300)
        let engine = fixture.engine

        let size = try await onSmallStack { try engine.sumOfFiles(under: deep.root) }

        #expect(size == deep.bytes)
    }

    // Solo Swift (correzione del 2026-10-15): dentro una cartella eliminata, un collegamento a una
    // cartella non accredita né i byte della destinazione né quelli del collegamento.
    @Test func aLinkToAFolderInsideADeletedFolderIsNotCredited() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let invoice = try fixture.tmp.file("home/Documents/fatture/2026.pdf", contents: String(repeating: "z", count: 500))
        try fixture.tmp.file("home/Library/Caches/app/dati.bin", contents: String(repeating: "x", count: 100))
        try fixture.tmp.symlink("home/Library/Caches/app/documenti", to: fixture.home + "/Documents")
        let item = ScanItem(path: fixture.caches + "/app", sizeBytes: 0, isDirectory: true, declaredRoot: fixture.caches)

        let report = await fixture.engine.clean([CategorySelection(categoryId: "caches", items: [item])], progress: nil, journal: nil)

        #expect(report.itemsDeleted == 1)
        #expect(report.bytesFreed == 100)
        #expect(FileManager.default.fileExists(atPath: invoice))
    }

    @Test func aFolderDeeperThanTheStackIsMeasuredAndDeleted() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let deep = try fixture.tmp.deepTree("home/Library/Caches/deep")
        try #require(deep.depth >= 300)
        let item = ScanItem(path: deep.root, sizeBytes: 0, isDirectory: true, declaredRoot: fixture.caches)

        let report = await fixture.engine.clean([CategorySelection(categoryId: "caches", items: [item])], progress: nil, journal: nil)

        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
        #expect(report.bytesFreed == deep.bytes)
        #expect(!FileManager.default.fileExists(atPath: deep.root))
    }

    // Solo Swift (crash del 2026-10-15 nell'app): anche lo scanner scendeva di una chiamata per
    // livello di cartella, nella misura delle cartelle e nelle visite di matchingFiles e
    // matchingDirs; un albero di qualche centinaio di livelli esauriva lo stack già in analisi.
    // Le tre visite su un thread da 64 KB; sul pool cooperativo, come nell'app, matchingDirs, il
    // cui frame esauriva i 512 KB già a circa 450 livelli in Debug.
    @Test func aFolderDeeperThanTheStackIsMeasuredByTheScannerOnASmallStack() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let tree = try fixture.deepTreeWithABinAtTheBottom()
        let scanner = fixture.scanner
        let rule = CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: [])

        let outcome = try await onSmallStack { try scanner.scan(rule) }

        #expect(outcome == RuleScanOutcome(
            items: [ScanItem(path: tree.root, sizeBytes: tree.bytes, isDirectory: true, declaredRoot: fixture.caches)], errors: [], exclusions: []))
    }

    @Test func filesDeeperThanTheStackAreFoundOnASmallStack() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let tree = try fixture.deepTreeWithABinAtTheBottom()
        let scanner = fixture.scanner
        let rule = CleanupRule(fixture.caches, .matchingFiles, include: ["*"], exclude: [])

        let outcome = try await onSmallStack { try scanner.scan(rule) }

        // In profondità e in ordine di elenco, come la ricorsione: "bin" prima di "f", "a" prima di "m".
        #expect(outcome.items.map(\.path) == [tree.bottom + "/bin/x", tree.bottom + "/f", tree.middle + "/m"])
        #expect(outcome.items.reduce(0) { $0 + $1.sizeBytes } == tree.bytes)
        #expect(outcome.errors.isEmpty && outcome.exclusions.isEmpty)
    }

    @Test func aFolderMatchedDeeperThanTheStackIsFoundOnASmallStack() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let tree = try fixture.deepTreeWithABinAtTheBottom()
        let scanner = fixture.scanner
        let rule = CleanupRule(fixture.caches, .matchingDirs, include: ["bin"], exclude: [])

        let outcome = try await onSmallStack { try scanner.scan(rule) }

        #expect(outcome == RuleScanOutcome(
            items: [ScanItem(path: tree.bottom + "/bin", sizeBytes: 1, isDirectory: true, declaredRoot: fixture.caches)], errors: [], exclusions: []))
    }

    @Test func aFolderMatchedDeeperThanTheStackIsFoundOnTheCooperativePool() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let tree = try fixture.deepTreeWithABinAtTheBottom()

        let outcome = try await fixture.scanOnTheCooperativePool(CleanupRule(fixture.caches, .matchingDirs, include: ["bin"], exclude: []))

        #expect(outcome == RuleScanOutcome(
            items: [ScanItem(path: tree.bottom + "/bin", sizeBytes: 1, isDirectory: true, declaredRoot: fixture.caches)], errors: [], exclusions: []))
    }
}
