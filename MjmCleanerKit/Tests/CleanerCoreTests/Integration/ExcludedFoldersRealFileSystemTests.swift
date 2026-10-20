import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Le cartelle escluse nella grafia del disco su APFS reale (spec
/// `2026-10-20-excluded-folders-canonical-design.md`). La cartella temporanea sta sotto
/// /var/folders, e /var è un collegamento a /private/var: ogni root dichiarata con il testo
/// passa per la risoluzione di `validateRoot`. I file da 10 byte superano la soglia di 5.
struct ExcludedFoldersRealFileSystemTests {
    private static let excludedReason = "cartella esclusa nelle Impostazioni"
    private static let big = String(repeating: "x", count: 10)

    private struct Fixture {
        let tmp: TemporaryDirectory
        let work: String
        let scanner: RuleScanner

        init() throws {
            tmp = try TemporaryDirectory()
            let home = try tmp.directory("home")
            work = try tmp.directory("home/Lavoro")
            let fs = LocalFileSystem()
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fs, links: links, homeDirectory: home)
            scanner = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock())
        }

        /// File grandi sotto `root`, con le esclusioni date.
        func scanLargeFiles(_ root: String, excluding excluded: [String]) throws -> RuleScanOutcome {
            try scanner.scan(CleanupRule(root, .matchingFiles, include: ["*"], exclude: [], minSizeBytes: 5, excludedPaths: excluded))
        }
    }

    @Test func anExclusionWrittenThroughARealLinkUnderTheRootPrunesTheTarget() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Lavoro/archivio/vecchio/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/nuovo/disco.iso", contents: Self.big)
        try fixture.tmp.symlink("home/Lavoro/collegamento", to: fixture.work + "/archivio")

        let outcome = try fixture.scanLargeFiles(fixture.work, excluding: [fixture.work + "/collegamento/vecchio"])

        #expect(outcome.items.map(\.path) == [fixture.work + "/nuovo/disco.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: fixture.work + "/archivio/vecchio", reason: Self.excludedReason)])
    }

    /// La root dichiarata nella grafia del disco ("/private/var/…"), l'esclusione con il testo
    /// della cartella temporanea ("/var/…").
    @Test func anExclusionUnderVarMatchesARootDeclaredUnderPrivateVar() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Lavoro/archivio/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/nuovo/disco.iso", contents: Self.big)
        let declared = try LocalFileSystem().storedPath(fixture.work)
        try #require(declared.hasPrefix("/private/var/") && fixture.work.hasPrefix("/var/"))

        let outcome = try fixture.scanLargeFiles(declared, excluding: [fixture.work + "/archivio"])

        #expect(outcome.items.map(\.path) == [declared + "/nuovo/disco.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: declared + "/archivio", reason: Self.excludedReason)])
    }

    /// Le grafie che APFS case-insensitive considera lo stesso nome, come in `StoredPathTests`. La
    /// cartella si crea con `mkdir`, che non cambia la normalizzazione del nome.
    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive), arguments: [
        ("Kit", "\u{212A}it"),
        ("Messages", "Me\u{00DF}ages"),
        ("caf\u{00E9}", "cafe\u{0301}"),
        ("cafe\u{0301}", "caf\u{00E9}"),
    ])
    func anExclusionInAnotherSpellingOfTheSameNameMatches(stored: String, alias: String) throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        #expect(mkdir(fixture.work + "/" + stored, 0o755) == 0)
        try fixture.tmp.file("home/Lavoro/" + stored + "/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/nuovo/disco.iso", contents: Self.big)

        let outcome = try fixture.scanLargeFiles(fixture.work, excluding: [fixture.work + "/" + alias])

        #expect(outcome.items.map(\.path) == [fixture.work + "/nuovo/disco.iso"])
        #expect(outcome.exclusions.map(\.reason) == [Self.excludedReason])
        #expect(outcome.exclusions.map { Array($0.path.utf8) } == [Array((fixture.work + "/" + stored).utf8)])
    }

    /// La root dichiarata in NFD, la cartella sul disco e l'esclusione in NFC: gli elementi arrivano
    /// sotto la root dichiarata, e l'esclusione vale solo sotto la grafia del disco della root.
    @Test func anExclusionInTheDiskSpellingMatchesARootDeclaredInAnotherNormalization() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let onDisk = fixture.work + "/Caf\u{00E9}"
        let declared = fixture.work + "/Cafe\u{0301}"
        #expect(mkdir(onDisk, 0o755) == 0)
        try fixture.tmp.file("home/Lavoro/Caf\u{00E9}/tieni/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/Caf\u{00E9}/nuovo/disco.iso", contents: Self.big)

        let outcome = try fixture.scanLargeFiles(declared, excluding: [onDisk + "/tieni"])

        #expect(outcome.items.map { Array($0.path.utf8) } == [Array((declared + "/nuovo/disco.iso").utf8)])
        #expect(outcome.exclusions.map(\.reason) == [Self.excludedReason])
        #expect(outcome.exclusions.map { Array($0.path.utf8) } == [Array((declared + "/tieni").utf8)])
    }

    /// Un'esclusione che è un collegamento reale vale anche per la cartella a cui punta.
    @Test func anExclusionThatIsARealLinkAlsoExcludesItsTarget() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Lavoro/archivio/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/nuovo/disco.iso", contents: Self.big)
        try fixture.tmp.symlink("home/Lavoro/tieni", to: fixture.work + "/archivio")

        let outcome = try fixture.scanLargeFiles(fixture.work, excluding: [fixture.work + "/tieni"])

        #expect(outcome.items.map(\.path) == [fixture.work + "/nuovo/disco.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: fixture.work + "/archivio", reason: Self.excludedReason)])
    }

    /// Come sopra, ma con la root dichiarata nella grafia del disco e il collegamento che punta al
    /// testo "/var/…": la destinazione vale solo nella sua grafia del disco.
    @Test func anExclusionThatIsARealLinkExcludesItsTargetInTheDiskSpelling() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Lavoro/archivio/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/nuovo/disco.iso", contents: Self.big)
        try fixture.tmp.symlink("home/Lavoro/tieni", to: fixture.work + "/archivio")
        let declared = try LocalFileSystem().storedPath(fixture.work)
        try #require(declared.hasPrefix("/private/var/") && fixture.work.hasPrefix("/var/"))

        let outcome = try fixture.scanLargeFiles(declared, excluding: [fixture.work + "/tieni"])

        #expect(outcome.items.map(\.path) == [declared + "/nuovo/disco.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: declared + "/archivio", reason: Self.excludedReason)])
    }

    /// Una catena di collegamenti con un ".." relativo che esce da una cartella collegata:
    /// `keep` → `work/a/b`, con `a` → `work/real/deep` e `deep/b` → `../target`. Il kernel arriva a
    /// `work/real/target`, mentre `resolveLinkTarget`, che segue la catena sul testo, darebbe
    /// `work/target`. L'esclusione vale per la cartella a cui arriva il kernel.
    @Test func anExclusionThatIsALinkThroughARelativeChainExcludesWhatTheKernelReaches() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Lavoro/real/target/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/real/nuovo/disco.iso", contents: Self.big)
        try fixture.tmp.directory("home/Lavoro/real/deep")
        try fixture.tmp.symlink("home/Lavoro/real/deep/b", to: "../target")
        try fixture.tmp.symlink("home/Lavoro/a", to: fixture.work + "/real/deep")
        try fixture.tmp.symlink("home/Lavoro/keep", to: fixture.work + "/a/b")

        let outcome = try fixture.scanLargeFiles(fixture.work + "/real", excluding: [fixture.work + "/keep"])

        #expect(outcome.items.map(\.path) == [fixture.work + "/real/nuovo/disco.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: fixture.work + "/real/target", reason: Self.excludedReason)])
    }

    /// La root è un collegamento alla stessa catena: `validateRoot` la risolve sul testo in un
    /// percorso che non esiste, e l'esclusione nella grafia del disco della cartella vera vale
    /// lo stesso, perché alla root si aggiunge la forma seguita dal kernel.
    @Test func aRootLinkedThroughARelativeChainMatchesAnExclusionInTheDiskSpelling() throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Lavoro/real/target/keep/disco.iso", contents: Self.big)
        try fixture.tmp.file("home/Lavoro/real/target/nuovo/disco.iso", contents: Self.big)
        try fixture.tmp.directory("home/Lavoro/real/deep")
        try fixture.tmp.symlink("home/Lavoro/real/deep/b", to: "../target")
        try fixture.tmp.symlink("home/Lavoro/a", to: fixture.work + "/real/deep")
        try fixture.tmp.symlink("home/Lavoro/root", to: fixture.work + "/a/b")
        let exclusion = try LocalFileSystem().storedPath(fixture.work + "/real/target/keep")

        let outcome = try fixture.scanLargeFiles(fixture.work + "/root", excluding: [exclusion])

        #expect(outcome.items.map(\.path) == [fixture.work + "/root/nuovo/disco.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: fixture.work + "/root/keep", reason: Self.excludedReason)])
    }
}
