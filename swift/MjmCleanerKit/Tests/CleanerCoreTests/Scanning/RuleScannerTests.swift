import Foundation
import Testing
@testable import CleanerCore

struct RuleScannerTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]

    private func create(_ fs: any FileSystem, _ symlinks: String...) throws -> RuleScanner {
        let links = FakeLinkInspector(symlinks)
        return RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    /// `File(size, written)` del C#: data di scrittura e accesso uguali, per default "adesso".
    private func addFile(_ fs: InMemoryFileSystem, _ path: String, _ size: Int64, written: Date? = nil) {
        fs.addFile(path, size: size, stamp: written ?? Self.now)
    }

    private func single(_ outcome: RuleScanOutcome) throws -> ScanItem {
        #expect(outcome.items.count == 1)
        return try #require(outcome.items.first)
    }

    @Test func returnsNothingWhenRootDoesNotExist() throws {
        let outcome = try create(InMemoryFileSystem()).scan(
            CleanupRule("/Users/tester/Library/Developer/Xcode/DerivedData", .clearContents, include: Self.all, exclude: []))
        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.isEmpty)
    }

    @Test func clearContentsListsDirectChildrenNotTheRoot() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/app1/dati.bin", 100)
        addFile(fs, "\(Self.cacheRoot)/solo.tmp", 50)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(outcome.items.count == 2)
        #expect(!outcome.items.contains { $0.path == Self.cacheRoot })
        #expect(outcome.items.contains { $0.path == "\(Self.cacheRoot)/app1" && $0.isDirectory && $0.sizeBytes == 100 })
        #expect(outcome.items.contains { $0.path == "\(Self.cacheRoot)/solo.tmp" && !$0.isDirectory && $0.sizeBytes == 50 })
    }

    @Test func directorySizeIsSummedRecursively() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/app/a/1.bin", 100)
        addFile(fs, "\(Self.cacheRoot)/app/b/2.bin", 250)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(try single(outcome).sizeBytes == 350)
    }

    @Test func itemsCarryTheDeclaredRoot() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/x.tmp", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(try single(outcome).declaredRoot == Self.cacheRoot)
    }

    @Test func guardRejectionBecomesExclusionNotItem() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.home)/Documents/riservato.pdf", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.home, .clearContents, include: Self.all, exclude: []))

        #expect(outcome.items.isEmpty)
        #expect(!outcome.exclusions.isEmpty)
    }

    @Test func symlinkIsListedButItsTargetIsNotTraversed() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/collegamento/dentro.bin", 9999)

        let outcome = try create(fs, "\(Self.cacheRoot)/collegamento")
            .scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        let item = try single(outcome)
        #expect(item.path == "\(Self.cacheRoot)/collegamento")
        #expect(item.sizeBytes == 0)
    }

    @Test func matchingFilesHonoursMinAge() throws {
        let fs = InMemoryFileSystem()
        let logs = "\(Self.home)/Library/Logs"
        addFile(fs, "\(logs)/vecchio.log", 10, written: Self.now.addingTimeInterval(-days(60)))
        addFile(fs, "\(logs)/recente.log", 10, written: Self.now.addingTimeInterval(-days(2)))

        let outcome = try create(fs).scan(CleanupRule(logs, .matchingFiles, include: Self.all, exclude: [], minAge: days(30)))

        #expect(try single(outcome).path == "\(logs)/vecchio.log")
    }

    @Test func matchingFilesHonoursGlobsAndExclusions() throws {
        let fs = InMemoryFileSystem()
        let logs = "\(Self.home)/Library/Logs"
        addFile(fs, "\(logs)/a.log", 10)
        addFile(fs, "\(logs)/b.txt", 10)
        addFile(fs, "\(logs)/importante.log", 10)

        let outcome = try create(fs).scan(CleanupRule(logs, .matchingFiles, include: ["*.log"], exclude: ["importante.*"]))

        #expect(try single(outcome).path == "\(logs)/a.log")
    }

    @Test func matchingFilesHonoursMinSize() throws {
        let fs = InMemoryFileSystem()
        let downloads = "\(Self.home)/Downloads"
        addFile(fs, "\(downloads)/grande.dmg", 2000)
        addFile(fs, "\(downloads)/piccolo.txt", 10)

        let outcome = try create(fs).scan(CleanupRule(downloads, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 1000))

        #expect(try single(outcome).path == "\(downloads)/grande.dmg")
    }

    @Test func cancellationStopsTheScan() async throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/a.tmp", 10)
        let scanner = try create(fs)
        let rule = CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: [])

        let task = Task {
            cancelCurrentTask()
            return try scanner.scan(rule)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // IMPORTANT 2 della revisione del Task 8: ClearContents ignorava IncludeGlobs, ExcludeGlobs
    // e MinSizeBytes, proponendo elementi che la regola dichiara di conservare.
    @Test func clearContentsHonoursExcludeGlobs() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/normale.tmp", 10)
        addFile(fs, "\(Self.cacheRoot)/da_conservare.keep", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: ["*.keep"]))

        #expect(try single(outcome).path == "\(Self.cacheRoot)/normale.tmp")
    }

    @Test func clearContentsHonoursMinSize() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/grande.tmp", 2_000_000)
        addFile(fs, "\(Self.cacheRoot)/piccolo.tmp", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: [], minSizeBytes: 1_000_000))

        #expect(try single(outcome).path == "\(Self.cacheRoot)/grande.tmp")
    }

    // IMPORTANT 3: in ClearContents il filtro di età guardava il timestamp del solo
    // contenitore, non del contenuto. Su disco vero l'mtime di una directory non cambia quando
    // un file al suo interno viene riscritto sul posto, quindi una directory "vecchia" può
    // contenere un file scritto oggi: l'età va calcolata sul timestamp più recente nell'albero.
    @Test func clearContentsDirectoryAgeReflectsNewestContainedFile() throws {
        let fs = InMemoryFileSystem()
        let dir = "\(Self.cacheRoot)/app"
        addFile(fs, "\(dir)/nuovo.bin", 10, written: Self.now.addingTimeInterval(-days(1)))
        let old = Self.now.addingTimeInterval(-days(200))
        fs.setTimes(dir, lastWrite: old, lastAccess: old)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: [], minAge: days(30)))

        #expect(outcome.items.isEmpty)
    }

    // IMPORTANT 4: MatchingFiles scendeva dentro i rami negati dalla deny-list, producendo
    // un'esclusione per ciascun file privato al loro interno (i cui nomi finiscono così
    // nell'elenco delle esclusioni mostrato all'utente) invece di potare il ramo intero.
    // Root = "~/Library", non la home stessa: contiene sia una sottocartella protetta
    // (Keychains) sia una non protetta (Caches), per isolare l'effetto della potatura.
    @Test func matchingFilesPrunesDeniedBranchWithoutDescendingIntoIt() throws {
        let fs = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        addFile(fs, "\(library)/Keychains/login.keychain", 10)
        addFile(fs, "\(library)/Caches/normale.tmp", 10)

        let outcome = try create(fs).scan(CleanupRule(library, .matchingFiles, include: Self.all, exclude: []))

        #expect(outcome.exclusions.contains { $0.path == "\(library)/Keychains" })
        #expect(!outcome.exclusions.contains { $0.path == "\(library)/Keychains/login.keychain" })
        #expect(try single(outcome).path == "\(library)/Caches/normale.tmp")
    }

    // Test opposto, a protezione dal rischio contrario: un ramo ordinario non va potato, e la
    // ricorsione deve continuare a funzionare normalmente.
    @Test func matchingFilesDoesNotPruneOrdinaryBranches() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/app/sub/file.log", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .matchingFiles, include: Self.all, exclude: []))

        #expect(outcome.exclusions.isEmpty)
        #expect(try single(outcome).path == "\(Self.cacheRoot)/app/sub/file.log")
    }

    // Minor (caso E2 della revisione): un elemento scomparso fra l'enumerazione e la lettura
    // della dimensione veniva annotato come errore NotFound ma anche aggiunto agli elementi con
    // dimensione zero, comparendo così sia fra gli errori sia fra ciò che si propone di
    // eliminare. Richiede un IFileSystem che simuli davvero la corsa critica: un percorso mai
    // aggiunto al MockFileSystem non verrebbe nemmeno enumerato, e non eserciterebbe il ramo
    // "elencato ma poi introvabile" che questo test deve coprire.
    @Test func matchingFilesDoesNotListAFileThatVanishesBeforeSizeRead() throws {
        let mock = InMemoryFileSystem()
        let logs = "\(Self.home)/Library/Logs"
        let vanished = "\(logs)/scomparso.log"
        addFile(mock, vanished, 10)

        let outcome = try create(VanishingFileSystem(mock, vanishedPath: vanished))
            .scan(CleanupRule(logs, .matchingFiles, include: Self.all, exclude: []))

        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.contains { $0.path == vanished && $0.kind == .notFound })
    }

    // IMPORTANT (re-revisione): root = home con soglia sui file grandi (LargeFileRoots = ["~"]
    // nel catalogo reale) deve continuare a trovare i file legittimi, non restituire zero
    // elementi. Misura anche l'effetto congiunto con la correzione a ValidateRoot: la home come
    // root è ora ammessa (voci a uguaglianza esatta non applicate alle root), e i rami protetti
    // al suo interno vengono comunque potati da ScanFiles (Important 4), non attraversati.
    @Test func matchingFilesFindsLegitimateLargeFilesInHomeWhilePruningProtectedBranches() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.home)/Downloads/installer.dmg", 2_000_000)
        addFile(fs, "\(Self.home)/progetti/archivio.zip", 3_000_000)
        addFile(fs, "\(Self.home)/Documents/riservato.pdf", 5_000_000)
        addFile(fs, "\(Self.home)/.ssh/id_rsa", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.home, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 1_000_000))

        #expect(outcome.items.count == 2)
        #expect(outcome.items.contains { $0.path == "\(Self.home)/Downloads/installer.dmg" })
        #expect(outcome.items.contains { $0.path == "\(Self.home)/progetti/archivio.zip" })
        #expect(outcome.exclusions.contains { $0.path == "\(Self.home)/Documents" })
        #expect(outcome.exclusions.contains { $0.path == "\(Self.home)/.ssh" })
    }

    // Minor (re-revisione): la potatura introdotta per l'Important 4 era stata aggiunta solo a
    // ScanFiles, e il calcolo delle statistiche era stato spostato prima del verdetto del guard
    // in ScanContents — una directory negata veniva quindi attraversata per intero (i percorsi
    // interni illeggibili finiscono fra gli errori mostrati all'utente) e solo dopo esclusa.
    // Verificato con un file che, se letto, produrrebbe un errore: con la correzione, il guard
    // esclude "Keychains" PRIMA di attraversarla, quindi quel file non viene mai toccato.
    @Test func clearContentsValidatesBeforeTraversingADeniedDirectory() throws {
        let mock = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        let innerSecret = "\(library)/Keychains/login.keychain"
        addFile(mock, innerSecret, 10)
        addFile(mock, "\(library)/Caches/normale.tmp", 10)

        let outcome = try create(VanishingFileSystem(mock, vanishedPath: innerSecret))
            .scan(CleanupRule(library, .clearContents, include: Self.all, exclude: []))

        #expect(!outcome.errors.contains { $0.path == innerSecret })
        #expect(outcome.exclusions.contains { $0.path == "\(library)/Keychains" })
        #expect(outcome.items.contains { $0.path == "\(library)/Caches" })
    }

    // Minor (re-revisione): DirectoryInfo.LastWriteTimeUtc/LastAccessTimeUtc su una directory
    // scomparsa non lanciano — restituiscono la sentinella "1601-01-01", la data più vecchia
    // possibile, non "indeterminato". Prima della correzione questo faceva apparire la
    // directory antichissima (quindi superava qualunque soglia di età) e, non essendo la
    // deduplicazione estesa alle directory, veniva comunque aggiunta agli elementi mentre lo
    // stesso percorso finiva anche fra gli errori.
    @Test func clearContentsDoesNotListADirectoryThatVanishesBeforeStatsRead() throws {
        let mock = InMemoryFileSystem()
        let vanished = "\(Self.cacheRoot)/scomparsa"
        addFile(mock, "\(vanished)/dentro.bin", 10)

        let outcome = try create(VanishingChildFileSystem(mock, vanishingPath: vanished))
            .scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(!outcome.items.contains { $0.path == vanished })
    }

    // IMPORTANT della revisione finale: configurando le cartelle per la ricerca dei file grandi
    // su una directory che contiene repository, la ricorsione entrava in ".git" e proponeva i
    // pack file dell'intera storia del repository, indistinguibili per nome o estensione da un
    // file grande legittimo — una perdita non ricostruibile, perché la cartella ".git"
    // sopravvive alla cancellazione ma la storia no. Misura che il ramo viene saltato per
    // intero, mentre un file grande legittimo accanto al repository continua a comparire.
    @Test func matchingFilesNeverEntersAGitDirectory() throws {
        let fs = InMemoryFileSystem()
        let projects = "\(Self.home)/projects"
        addFile(fs, "\(projects)/progetto/.git/objects/pack/grosso.pack", 200_000_000)
        addFile(fs, "\(projects)/progetto/dati.bin", 100_000_000)

        let outcome = try create(fs).scan(CleanupRule(projects, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 50_000_000))

        #expect(!outcome.items.contains { $0.path.contains(".git") })
        #expect(outcome.items.contains { $0.path == "\(projects)/progetto/dati.bin" })
        #expect(outcome.exclusions.contains { $0.path == "\(projects)/progetto/.git" })
    }

    // Per simmetria: la ricerca per directory (usata per "bin"/"obj" e i pacchetti NuGet) non
    // deve nemmeno considerare ".git" come candidato, né scendervi in cerca di altro.
    @Test func matchingDirsNeverEntersOrMatchesAGitDirectory() throws {
        let fs = InMemoryFileSystem()
        let projects = "\(Self.home)/projects"
        fs.addFile("\(projects)/progetto/app.csproj", text: "<Project/>")
        addFile(fs, "\(projects)/progetto/bin/app.dll", 10)
        addFile(fs, "\(projects)/progetto/.git/objects/pack/grosso.pack", 200_000_000)

        let outcome = try create(fs).scan(
            CleanupRule(projects, .matchingDirs, include: ["bin", "obj"], exclude: [], requiresProjectMarker: true))

        #expect(!outcome.items.contains { $0.path.contains(".git") })
        #expect(outcome.items.contains { $0.path == "\(projects)/progetto/bin" })
        #expect(outcome.exclusions.contains { $0.path == "\(projects)/progetto/.git" })
    }

    // Mount virtuali (es. ~/Library/Developer/CoreDevice/DeviceFS, il filesystem di un
    // dispositivo collegato) rispondono "Invalid argument" all'enumerazione: un'eccezione fuori
    // da IsExpected. Non deve fermare l'analisi né richiedere che l'utente escluda il percorso:
    // il ramo si registra come errore e il resto della scansione continua.
    @Test func unexpectedEnumerationFailureIsRecordedAndScanContinues() throws {
        let mock = InMemoryFileSystem()
        let projects = "\(Self.home)/projects"
        let broken = "\(Self.home)/Library/Developer/CoreDevice/DeviceFS/device-1/DiagnosticReports"
        addFile(mock, "\(projects)/grosso.bin", 200_000_000)
        addFile(mock, "\(broken)/report.ips", 10)
        let fs = UnreadableDirectoryFileSystem(
            mock, unreadablePath: broken, error: UnexpectedTestError(description: "Invalid argument : '\(broken)'"))

        let outcome = try create(fs).scan(
            CleanupRule(Self.home, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 100_000_000, maxDepth: 12))

        #expect(outcome.items.contains { $0.path == "\(projects)/grosso.bin" })
        #expect(outcome.errors.contains { $0.path == broken })
    }
}
