import Foundation
import Testing
@testable import CleanerCore

/// Le cartelle escluse nelle Impostazioni (spec `2026-10-19-large-files-exclusions-design.md`):
/// mai attraversate, mai proposte, e nemmeno una cartella che ne contiene una.
struct ExcludedFoldersScanTests {
    private static let home = "/Users/tester"
    private static let caches = "/Users/tester/Library/Caches"
    private static let work = "/Users/tester/Lavoro"
    private static let src = "/Users/tester/src"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]
    private static let excludedReason = "cartella esclusa nelle Impostazioni"
    private static let containsReason = "contiene una cartella esclusa nelle Impostazioni"

    private func create(_ fs: any FileSystem, targets: [String: String?] = [:]) throws -> RuleScanner {
        let links = FakeLinkInspector(targets: targets)
        return RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    private func projects(_ fs: InMemoryFileSystem) {
        fs.addFile("\(Self.src)/app/app.csproj", size: 1)
        fs.addFile("\(Self.src)/app/bin/app.dll", size: 100)
        fs.addFile("\(Self.src)/vecchio/vecchio.csproj", size: 1)
        fs.addFile("\(Self.src)/vecchio/bin/vecchio.dll", size: 200)
    }

    private func binAndObj(excluded: [String]) -> CleanupRule {
        CleanupRule(Self.src, .matchingDirs, include: ["bin", "obj"], exclude: [], requiresProjectMarker: true, excludedPaths: excluded)
    }

    @Test(arguments: ["/Users/tester/Library/Caches", "/Users/tester/Library", "/USERS/tester/library/caches/"])
    func ruleWhoseRootIsExcludedProducesNothing(excluded: String) throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.caches)/app/dati.bin", size: 100)

        let outcome = try create(fs).scan(CleanupRule(Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: [excluded]))

        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.caches, reason: Self.excludedReason)])
    }

    /// Escludere la radice esclude tutto: la direzione sicura.
    @Test func excludingTheFilesystemRootExcludesEveryRule() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.caches)/app/dati.bin", size: 100)

        let outcome = try create(fs).scan(CleanupRule(Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: ["/"]))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.caches, reason: Self.excludedReason)])
    }

    @Test func matchingFilesPrunesAnExcludedBranchWithoutLookingInside() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.work)/archivio/vecchio.iso", size: 900)
        memory.addFile("\(Self.work)/archivio/sotto/altro.iso", size: 900)
        memory.addFile("\(Self.work)/nuovo.iso", size: 900)
        let fs = AccessLogFileSystem(memory)

        let outcome = try create(fs).scan(CleanupRule(
            Self.work, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 500, excludedPaths: ["\(Self.work)/archivio"]))

        #expect(outcome.items.map(\.path) == ["\(Self.work)/nuovo.iso"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.work)/archivio", reason: Self.excludedReason)])
        #expect(!fs.paths.values.contains { PathText.isSameOrUnder($0, "\(Self.work)/archivio/vecchio.iso") })
        #expect(!fs.paths.values.contains { PathText.isSameOrUnder($0, "\(Self.work)/archivio/sotto") })
    }

    /// Il confine di segmento: "archivio" non esclude "archivio-2026".
    @Test func anExclusionDoesNotCoverASiblingWithTheSamePrefix() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.work)/archivio/vecchio.iso", size: 900)
        fs.addFile("\(Self.work)/archivio-2026/nuovo.iso", size: 900)

        let outcome = try create(fs).scan(CleanupRule(
            Self.work, .matchingFiles, include: Self.all, exclude: [], excludedPaths: ["\(Self.work)/archivio"]))

        #expect(outcome.items.map(\.path) == ["\(Self.work)/archivio-2026/nuovo.iso"])
    }

    @Test func matchingDirsPrunesAnExcludedProject() throws {
        let fs = InMemoryFileSystem()
        projects(fs)

        let outcome = try create(fs).scan(binAndObj(excluded: ["\(Self.src)/vecchio"]))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/app/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/vecchio", reason: Self.excludedReason)])
    }

    @Test func matchingDirsNeverProposesAnExcludedBin() throws {
        let fs = InMemoryFileSystem()
        projects(fs)

        let outcome = try create(fs).scan(binAndObj(excluded: ["\(Self.src)/app/bin"]))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/vecchio/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/app/bin", reason: Self.excludedReason)])
    }

    @Test func matchingDirsDoesNotProposeABinThatContainsAnExclusion() throws {
        let fs = InMemoryFileSystem()
        projects(fs)
        fs.addFile("\(Self.src)/app/bin/tieni/firma.p12", size: 5)

        let outcome = try create(fs).scan(binAndObj(excluded: ["\(Self.src)/app/bin/tieni"]))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/vecchio/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/app/bin", reason: Self.containsReason)])
    }

    @Test func clearContentsSkipsAnExcludedChild() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)
        fs.addFile("\(Self.caches)/com.bar/dati.bin", size: 50)

        let outcome = try create(fs).scan(CleanupRule(
            Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: ["\(Self.caches)/com.foo"]))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.bar"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.caches)/com.foo", reason: Self.excludedReason)])
    }

    /// Il confine di segmento anche nel verso opposto: "com.foo" non contiene "com.foobar".
    @Test func aChildIsNotTakenForTheParentOfASiblingExclusion() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)
        fs.addFile("\(Self.caches)/com.foobar/dati.bin", size: 50)

        let outcome = try create(fs).scan(CleanupRule(
            Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: ["\(Self.caches)/com.foobar"]))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.foo"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.caches)/com.foobar", reason: Self.excludedReason)])
    }

    /// Svuotare "com.foo" cancellerebbe anche "com.foo/tieni": il figlio intero resta, e non si
    /// attraversa nemmeno per misurarlo.
    @Test func clearContentsSkipsAChildThatContainsAnExclusionWithoutMeasuringIt() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/com.foo/tieni/dati.bin", size: 100)
        memory.addFile("\(Self.caches)/com.foo/via.bin", size: 100)
        memory.addFile("\(Self.caches)/com.bar/dati.bin", size: 50)
        let fs = AccessLogFileSystem(memory)

        let outcome = try create(fs).scan(CleanupRule(
            Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: ["\(Self.caches)/com.foo/tieni"]))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.bar"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.caches)/com.foo", reason: Self.containsReason)])
        #expect(!fs.paths.values.contains { PathText.isSameOrUnder($0, "\(Self.caches)/com.foo") })
    }

    /// `$TMPDIR` sta sotto il collegamento "/var": un'esclusione scritta sul percorso risolto,
    /// come la restituisce il pannello di scelta, vale lo stesso. Quella scritta sotto "/var" vale
    /// già con il confronto testuale.
    @Test(arguments: ["/private/var/folders/ab/T/tieni", "/var/folders/ab/T/tieni"])
    func exclusionMatchesTheTextualAndTheResolvedRoot(excluded: String) throws {
        let fs = InMemoryFileSystem()
        let temp = "/var/folders/ab/T"
        fs.addFile("\(temp)/tieni/dati.bin", size: 100)
        fs.addFile("\(temp)/via/dati.bin", size: 100)

        let outcome = try create(fs, targets: ["/var": "/private/var"]).scan(CleanupRule(
            temp, .clearContents, include: Self.all, exclude: [], excludedPaths: [excluded]))

        #expect(outcome.items.map(\.path) == ["\(temp)/via"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(temp)/tieni", reason: Self.excludedReason)])
    }

    @Test func noExclusionsLeaveTheScanUnchanged() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)

        let outcome = try create(fs).scan(CleanupRule(Self.caches, .clearContents, include: Self.all, exclude: []))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.foo"])
        #expect(outcome.exclusions.isEmpty)
    }
}
