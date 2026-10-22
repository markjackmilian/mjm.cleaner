import Foundation
import Testing
@testable import CleanerCore

/// I pacchetti macOS nelle regole `matchingFiles` (spec `2026-10-19-large-files-exclusions-design.md`):
/// un'unità proposta intera, mai i file al suo interno.
struct PackageScanTests {
    private static let home = "/Users/tester"
    private static let work = "/Users/tester/Lavoro"
    private static let downloads = "/Users/tester/Downloads"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]
    private static let megabyte: Int64 = 1_048_576
    private static let gigabyte: Int64 = 1_073_741_824

    private func create(_ fs: any FileSystem) throws -> RuleScanner {
        let links = FakeLinkInspector()
        return RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    /// Le regole dei file grandi: soglia e nessuna età.
    private func largeFiles(_ root: String, exclude: [String] = [], excluded: [String] = []) -> CleanupRule {
        CleanupRule(root, .matchingFiles, include: Self.all, exclude: exclude, minSizeBytes: 500 * Self.megabyte, excludedPaths: excluded)
    }

    /// Un pacchetto con i suoi file, tutti con la stessa data, anche la cartella del pacchetto.
    private func makePackage(_ fs: InMemoryFileSystem, _ path: String, files: [(String, Int64)], written: Date = now) {
        fs.addPackage(path)
        for (name, size) in files {
            fs.addFile("\(path)/\(name)", size: size, stamp: written)
        }
        fs.setTimes(path, lastWrite: written, lastAccess: written)
    }

    @Test func aPackageIsProposedWholeWithTheSizeOfItsTree() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/Windows 11.pvm", files: [("disco.hds", 80 * Self.gigabyte), ("config.pvs", 4096)])
        fs.addFile("\(Self.work)/immagine.iso", size: 600 * Self.megabyte)

        let outcome = try create(fs).scan(largeFiles(Self.work))

        #expect(outcome.items == [
            ScanItem(path: "\(Self.work)/Windows 11.pvm", sizeBytes: 80 * Self.gigabyte + 4096, isDirectory: true, declaredRoot: Self.work),
            ScanItem(path: "\(Self.work)/immagine.iso", sizeBytes: 600 * Self.megabyte, isDirectory: false, declaredRoot: Self.work),
        ])
    }

    /// Due file da 300 MB non superano la soglia da soli, il pacchetto che li contiene sì.
    @Test func theThresholdAppliesToThePackageTotal() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/Grande.app", files: [("a.bin", 300 * Self.megabyte), ("b.bin", 300 * Self.megabyte)])
        makePackage(fs, "\(Self.work)/Piccola.app", files: [("a.bin", 200 * Self.megabyte), ("b.bin", 200 * Self.megabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.work))

        #expect(outcome.items.map(\.path) == ["\(Self.work)/Grande.app"])
    }

    /// Come una cartella di `clearContents`: conta il timestamp più recente dell'albero, quindi un
    /// pacchetto con un solo file recente non è vecchio. Vale per le app in Download e per i
    /// `.logarchive` nei Log.
    @Test func packageAgeIsTheNewestStampOfItsTree() throws {
        let fs = InMemoryFileSystem()
        let old = Self.now.addingTimeInterval(-days(120))
        makePackage(fs, "\(Self.downloads)/Vecchia.app", files: [("binario", 10)], written: old)
        makePackage(fs, "\(Self.downloads)/Usata.app", files: [("binario", 10)], written: old)
        fs.addFile("\(Self.downloads)/Usata.app/preferenze.plist", size: 1, stamp: Self.now.addingTimeInterval(-days(2)))

        let outcome = try create(fs).scan(CleanupRule(Self.downloads, .matchingFiles, include: Self.all, exclude: [], minAge: days(90)))

        #expect(outcome.items.map(\.path) == ["\(Self.downloads)/Vecchia.app"])
    }

    @Test func completeDownloadsIncludesRecentFilesAndPackagesButHonorsExclusions() throws {
        let fs = InMemoryFileSystem()
        let recentFile = "\(Self.downloads)/recente.txt"
        let oldFile = "\(Self.downloads)/vecchio.txt"
        let recentPackage = "\(Self.downloads)/Recente.app"
        let excludedPackage = "\(Self.downloads)/Esclusa.app"
        fs.addFile(recentFile, size: 10, stamp: Self.now)
        fs.addFile(oldFile, size: 20, stamp: Self.now.addingTimeInterval(-days(120)))
        makePackage(fs, recentPackage, files: [("binario", 30)])
        makePackage(fs, excludedPackage, files: [("binario", 40)])
        let category = CleanupCategory(
            id: "downloads", displayName: "Download", description: "", risk: .high, selectedByDefault: false,
            parentId: nil,
            rules: [CleanupRule(Self.downloads, .matchingFiles, include: Self.all, exclude: [], minAge: days(90), excludedPaths: [excludedPackage])],
            itemsSelectedByDefault: false)

        let outcome = try create(fs).scan(category.forCompleteDownloads().rules[0])

        #expect(outcome.items.map(\.path) == [recentPackage, recentFile, oldFile])
        #expect(outcome.exclusions.map(\.path) == [excludedPackage])
    }

    /// Una cartella con data sotto il 1990 (uno ZIP estratto con data 1980) non ha un'età
    /// determinabile: il pacchetto non è «vecchio» e non si propone, come in `clearContents`.
    @Test func aPackageWithoutADeterminableStampIsNotProposed() throws {
        let fs = InMemoryFileSystem()
        let package = "\(Self.downloads)/Estratta.app"
        makePackage(fs, package, files: [("binario", 10)], written: Self.now.addingTimeInterval(-days(120)))
        let sentinel = Date(timeIntervalSince1970: 315_532_800)
        fs.setTimes(package, lastWrite: sentinel, lastAccess: sentinel)

        let outcome = try create(fs).scan(CleanupRule(Self.downloads, .matchingFiles, include: Self.all, exclude: [], minAge: days(90)))

        #expect(outcome.items.isEmpty)
    }

    @Test func globsApplyToThePackageName() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/Windows 11.pvm", files: [("disco.hds", 80 * Self.gigabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.work, exclude: ["*.pvm"]))

        #expect(outcome.items.isEmpty)
    }

    /// Un figlio diretto della home non si propone mai (profondità minima del guard): il pacchetto
    /// non si attraversa nemmeno per misurarlo.
    @Test func aPackageTheGuardRejectsIsNeverMeasured() throws {
        let memory = InMemoryFileSystem()
        makePackage(memory, "\(Self.home)/Windows 11.pvm", files: [("disco.hds", 80 * Self.gigabyte)])
        let fs = AccessLogFileSystem(memory)

        let outcome = try create(fs).scan(largeFiles(Self.home))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions.map(\.path) == ["\(Self.home)/Windows 11.pvm"])
        #expect(!fs.paths.values.contains { $0.hasPrefix("\(Self.home)/Windows 11.pvm/") })
    }

    @Test func aPackageInsideAProtectedBranchIsNeverReached() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.home)/Pictures/Photos Library.photoslibrary", files: [("database.db", 2 * Self.gigabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.home))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions.map(\.path) == ["\(Self.home)/Pictures"])
    }

    @Test func aGitDirectoryIsSkippedEvenIfItLooksLikeAPackage() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/progetto/.git", files: [("pack.bin", 900 * Self.megabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.work))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions.map(\.path) == ["\(Self.work)/progetto/.git"])
    }

    @Test func aPackageInsideAnExcludedFolderIsNeverProposed() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/macchine/Windows 11.pvm", files: [("disco.hds", 80 * Self.gigabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.work, excluded: ["\(Self.work)/macchine"]))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.work)/macchine", reason: "cartella esclusa nelle Impostazioni")])
    }

    /// Un pacchetto scelto nel pannello delle esclusioni, con la barra finale che il pannello può
    /// restituire, non si propone: compare fra le esclusioni con il motivo di una cartella esclusa
    /// (spec `2026-10-20-package-exclusions-folder-warning-design.md`).
    @Test func anExcludedPackageIsSkippedWithTheExcludedFolderReason() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/Windows 11.pvm", files: [("disco.hds", 80 * Self.gigabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.work, excluded: ["\(Self.work)/Windows 11.pvm/"]))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.work)/Windows 11.pvm", reason: "cartella esclusa nelle Impostazioni")])
    }

    @Test func aPackageContainingAnExclusionIsNotProposed() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.work)/Windows 11.pvm", files: [("disco.hds", 80 * Self.gigabyte), ("Snapshots/1.hds", 10 * Self.gigabyte)])

        let outcome = try create(fs).scan(largeFiles(Self.work, excluded: ["\(Self.work)/Windows 11.pvm/Snapshots"]))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [
            GuardExclusion(path: "\(Self.work)/Windows 11.pvm", reason: "contiene una cartella esclusa nelle Impostazioni"),
        ])
    }

    /// Le altre modalità non cambiano: in `clearContents` ogni figlio è già un'unità.
    @Test func clearContentsStillTreatsAPackageAsOneChild() throws {
        let fs = InMemoryFileSystem()
        makePackage(fs, "\(Self.home)/Library/Caches/Strumento.app", files: [("binario", 10)])

        let outcome = try create(fs).scan(CleanupRule("\(Self.home)/Library/Caches", .clearContents, include: Self.all, exclude: []))

        #expect(outcome.items.map(\.path) == ["\(Self.home)/Library/Caches/Strumento.app"])
    }
}
