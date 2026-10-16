import Testing
@testable import CleanerCore

struct MatchingDirsTests {
    private static let home = "/Users/tester"
    private static let projects = "/Users/tester/projects"
    private static let now = utc(2026, 9, 15, 12)

    private func create(_ fs: any FileSystem, _ symlinks: String...) throws -> RuleScanner {
        let links = FakeLinkInspector(symlinks)
        return RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    private func binObjRule(_ root: String = Self.projects, minSizeBytes: Int64? = nil) -> CleanupRule {
        CleanupRule(root, .matchingDirs, include: ["bin", "obj"], exclude: [], minSizeBytes: minSizeBytes, requiresProjectMarker: true)
    }

    private func single(_ outcome: RuleScanOutcome) throws -> ScanItem {
        #expect(outcome.items.count == 1)
        return try #require(outcome.items.first)
    }

    @Test func findsBinAndObjNextToProjectFile() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "<Project/>")
        fs.addFile("\(Self.projects)/app/bin/Debug/app.dll", size: 500)
        fs.addFile("\(Self.projects)/app/obj/project.assets.json", size: 100)

        let outcome = try create(fs).scan(binObjRule())

        #expect(outcome.items.count == 2)
        #expect(outcome.items.contains { $0.path == "\(Self.projects)/app/bin" && $0.sizeBytes == 500 })
        #expect(outcome.items.contains { $0.path == "\(Self.projects)/app/obj" && $0.sizeBytes == 100 })
    }

    @Test func skipsBinWithoutProjectFileAlongside() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/strumenti/bin/attrezzo", size: 10)
        #expect(try create(fs).scan(binObjRule()).items.isEmpty)
    }

    @Test func recognisesEveryProjectFileExtension() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/a/a.fsproj", text: "x")
        fs.addFile("\(Self.projects)/a/bin/x", size: 1)
        fs.addFile("\(Self.projects)/b/b.sln", text: "x")
        fs.addFile("\(Self.projects)/b/bin/x", size: 1)
        fs.addFile("\(Self.projects)/c/c.vbproj", text: "x")
        fs.addFile("\(Self.projects)/c/bin/x", size: 1)

        #expect(try create(fs).scan(binObjRule()).items.count == 3)
    }

    @Test func doesNotDescendIntoAFoundDirectory() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/app/bin/annidato/bin/x.dll", size: 10)

        #expect(try single(create(fs).scan(binObjRule())).path == "\(Self.projects)/app/bin")
    }

    @Test func withoutMarkerRequirementFindsDirectoriesByName() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        fs.addFile("\(nuget)/newtonsoft.json/13.0.3/pacchetto.nupkg", size: 42)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: [], maxDepth: 1))

        #expect(try single(outcome).path == "\(nuget)/newtonsoft.json")
    }

    @Test func honoursMaxDepth() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        fs.addFile("\(nuget)/pacchetto/1.0.0/dentro/file.bin", size: 5)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: [], maxDepth: 1))

        #expect(try single(outcome).path == "\(nuget)/pacchetto")
    }

    @Test func doesNotFollowSymlinkedDirectories() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/collegamento/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/collegamento/bin/x.dll", size: 10)

        #expect(try create(fs, "\(Self.projects)/collegamento").scan(binObjRule()).items.isEmpty)
    }

    // Solo Swift (visite iterative del 2026-10-16): oltre `maxDepth` non si scende nemmeno nelle
    // cartelle che non corrispondono, come nella ricorsione.
    @Test func maxDepthLimitsTheDescentThroughFoldersThatDoNotMatch() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/x/bin/a.dll", size: 10)
        fs.addFile("\(Self.projects)/y/z/bin/b.dll", size: 10)

        let outcome = try create(fs).scan(CleanupRule(Self.projects, .matchingDirs, include: ["bin"], exclude: [], maxDepth: 1))

        #expect(try single(outcome).path == "\(Self.projects)/x/bin")
    }

    // IMPORTANT 1 della revisione del Task 9: un nome che corrisponde a ExcludeGlobs veniva
    // trattato come un semplice mancato match ("continua a cercare più in basso") invece che
    // come un rifiuto esplicito, e la ricorsione scendeva dentro il ramo escluso — proponendo la
    // singola versione di un pacchetto NuGet esplicitamente escluso invece del pacchetto intero,
    // l'esito che questo task esiste per impedire.
    @Test func excludedDirectoryIsSkippedEntirelyInsteadOfBeingTraversed() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        fs.addFile("\(nuget)/escluso.pacchetto/1.0.0/lib/a.dll", size: 10)
        fs.addFile("\(nuget)/normale/1.0.0/lib/b.dll", size: 20)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: ["escluso.*"], maxDepth: 1))

        #expect(try single(outcome).path == "\(nuget)/normale")
        #expect(!outcome.items.contains { $0.path.contains("escluso") })
    }

    // IMPORTANT 2 della revisione del Task 9: nessun test copriva la potatura della deny-list in
    // questa modalità — un refactor capace di rimuovere la chiamata a ShouldPrune sarebbe passato
    // comunque. Root = "~/Library", con una sottocartella protetta (Keychains, contenente a sua
    // volta un "bin" che altrimenti verrebbe trovato e nominato per intero in un'esclusione per
    // elemento) e una ordinaria (Caches), per isolare l'effetto della potatura. I nomi dei globi
    // ("bin") non corrispondono a "Keychains"/"Caches" stessi, quindi il match avviene solo più
    // in profondità: questo esercita il ramo "non corrisponde, quindi pota o ricorri", non il
    // ramo "corrisponde ma il guard nega" (coperto a parte).
    @Test func prunesDeniedBranchWithoutDescendingIntoIt() throws {
        let fs = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        fs.addFile("\(library)/Keychains/bin/segreto.pfx", size: 10)
        fs.addFile("\(library)/Caches/proj/bin/output.dll", size: 10)

        let outcome = try create(fs).scan(CleanupRule(library, .matchingDirs, include: ["bin"], exclude: []))

        #expect(outcome.exclusions.map(\.path) == ["\(library)/Keychains"])
        #expect(!outcome.exclusions.contains { $0.path.contains("bin") || $0.path.contains("segreto") })
        #expect(!outcome.errors.contains { $0.path.contains("segreto") })
        #expect(!outcome.items.contains { $0.path.contains("Keychains") })
        #expect(outcome.items.contains { $0.path == "\(library)/Caches/proj/bin" })
    }

    // Complemento del test precedente: una directory che CORRISPONDE ma che il guard respinge
    // (qui perché il nome incluso coincide con un percorso della deny-list) deve diventare
    // un'esclusione, non un elemento — e la ricorsione, come per ogni corrispondenza, non deve
    // proseguire al suo interno.
    @Test func matchedDirectoryRejectedByGuardBecomesAnExclusionNotAnItem() throws {
        let fs = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        fs.addFile("\(library)/Keychains/login.keychain", size: 10)

        let outcome = try create(fs).scan(CleanupRule(library, .matchingDirs, include: ["Keychains"], exclude: []))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions.contains { $0.path == "\(library)/Keychains" })
    }

    // Il filtro di età, per una directory, non è mai ancorato al timestamp del solo contenitore
    // (si veda DirectoryStats): un pacchetto NuGet con la cartella "vecchia" ma un file al suo
    // interno toccato ieri non va proposto, mentre uno con contenitore e contenuto entrambi
    // vecchi sì. È il meccanismo con cui i pacchetti "non usati da N mesi" vengono selezionati.
    @Test func honoursMinAgeUsingTheNewestTimestampInTheTree() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        let oldStamp = Self.now.addingTimeInterval(-days(200))
        let recentStamp = Self.now.addingTimeInterval(-days(1))

        let oldPackage = "\(nuget)/vecchio"
        fs.addFile("\(oldPackage)/lib.dll", size: 10, stamp: oldStamp)
        fs.setTimes(oldPackage, lastWrite: oldStamp, lastAccess: oldStamp)

        let recentlyUsedPackage = "\(nuget)/usato_di_recente"
        fs.addFile("\(recentlyUsedPackage)/lib.dll", size: 10, stamp: recentStamp)
        fs.setTimes(recentlyUsedPackage, lastWrite: oldStamp, lastAccess: oldStamp)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: [], minAge: days(30), maxDepth: 1))

        #expect(try single(outcome).path == oldPackage)
    }

    // La dimensione di una directory trovata è la somma ricorsiva su più livelli, non la
    // dimensione di un solo file al suo interno.
    @Test func sumsSizeRecursivelyAcrossMultipleLevels() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/app/bin/a.dll", size: 100)
        fs.addFile("\(Self.projects)/app/bin/livello1/b.dll", size: 50)
        fs.addFile("\(Self.projects)/app/bin/livello1/livello2/c.dll", size: 25)

        let item = try single(create(fs).scan(binObjRule()))

        #expect(item.path == "\(Self.projects)/app/bin")
        #expect(item.sizeBytes == 175)
    }

    // Un sottoalbero illeggibile (permessi negati) durante la somma ricorsiva non azzera il
    // totale della directory trovata e non interrompe la scansione: contribuisce 0 (i suoi
    // contenuti non sono elencabili) e viene registrato come errore sulla propria directory,
    // mentre i rami leggibili continuano a contare normalmente.
    @Test func unreadableSubtreeDoesNotZeroTheTotalNorStopTheScan() throws {
        let mock = InMemoryFileSystem()
        mock.addFile("\(Self.projects)/app/app.csproj", text: "x")
        mock.addFile("\(Self.projects)/app/bin/livello1/a.dll", size: 100)
        mock.addFile("\(Self.projects)/app/bin/livello1/livello2/b.dll", size: 50)
        let unreadable = "\(Self.projects)/app/bin/protetta"
        mock.addFile("\(unreadable)/c.dll", size: 9999)

        let outcome = try create(UnreadableDirectoryFileSystem(mock, unreadablePath: unreadable)).scan(binObjRule())

        let item = try single(outcome)
        #expect(item.path == "\(Self.projects)/app/bin")
        #expect(item.sizeBytes == 150)
        #expect(outcome.errors.contains { $0.path == unreadable && $0.kind == .accessDenied })
    }

    // Re-revisione del Task 9: una directory corrispondente ma svanita fra il momento in cui
    // ScanDirectories la riconosce come tale (Directory.Exists) e il momento in cui
    // DirectoryStats ne legge le statistiche non deve comparire fra gli elementi proposti (con
    // dimensione zero), pur restando registrata fra gli errori — altrimenti lo stesso percorso
    // starebbe contemporaneamente fra ciò che si sta per cancellare e fra ciò che è fallito.
    // L'equivalente esiste già per ClearContents (ClearContentsDoesNotListADirectoryThatVanishesBeforeStatsRead);
    // riusa lo stesso doppio di filesystem (VanishingChildFileSystem), non uno nuovo.
    @Test func doesNotListAMatchedDirectoryThatVanishesBeforeStatsRead() throws {
        let mock = InMemoryFileSystem()
        mock.addFile("\(Self.projects)/app/app.csproj", text: "x")
        let vanished = "\(Self.projects)/app/bin"
        mock.addFile("\(vanished)/dentro.dll", size: 10)
        mock.addFile("\(Self.projects)/app/obj/normale.bin", size: 20)

        let outcome = try create(VanishingChildFileSystem(mock, vanishingPath: vanished)).scan(binObjRule())

        #expect(!outcome.items.contains { $0.path == vanished })
        #expect(outcome.items.contains { $0.path == "\(Self.projects)/app/obj" && $0.sizeBytes == 20 })
        #expect(outcome.errors.contains { $0.path == vanished && $0.kind == .notFound })
    }

    // Minor della revisione del Task 9: MinSizeBytes è applicato nelle altre due modalità ma era
    // ignorato in questa.
    @Test func honoursMinSizeBytes() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/app/bin/grande.dll", size: 2000)
        fs.addFile("\(Self.projects)/app/obj/piccolo.bin", size: 10)

        #expect(try single(create(fs).scan(binObjRule(minSizeBytes: 1000))).path == "\(Self.projects)/app/bin")
    }

    // Minor della revisione del Task 9: una *directory* chiamata "x.sln" soddisfaceva il vincolo
    // del marcatore di progetto perché il controllo non verificava che il fratello fosse un
    // file — un modo in più di soddisfare il vincolo che esiste per non proporre "/usr/bin".
    @Test func projectMarkerMustBeAFileNotADirectory() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/x.sln/nota.txt", text: "x")
        fs.addFile("\(Self.projects)/app/bin/output.dll", size: 10)

        #expect(try create(fs).scan(binObjRule()).items.isEmpty)
    }

    // Solo Swift (visite iterative del 2026-10-16): come la ricorsione, in profondità e
    // nell'ordine di elenco; gli errori della misura di una cartella trovata stanno fra quelli
    // della visita, al punto in cui la cartella si incontra.
    @Test func visitsDepthFirstInListingOrder() throws {
        let mock = InMemoryFileSystem()
        let sub = "\(Self.projects)/a/sub"
        mock.addFile("\(sub)/app.csproj", text: "x")
        mock.addFile("\(sub)/.git/HEAD", size: 1)
        mock.addFile("\(sub)/bin/x.dll", size: 10)
        mock.addDirectory("\(sub)/chiusa")
        mock.addFile("\(Self.projects)/b/app.csproj", text: "x")
        mock.addFile("\(Self.projects)/b/bin/y.dll", size: 20)
        mock.addDirectory("\(Self.projects)/b/bin/chiusa")
        mock.addFile("\(Self.projects)/b/obj/z.bin", size: 5)
        mock.addDirectory("\(Self.projects)/c")
        mock.addFile("\(Self.projects)/d/.git/HEAD", size: 1)
        let fs = UnreadableDirectoryFileSystem(
            UnreadableDirectoryFileSystem(
                UnreadableDirectoryFileSystem(mock, unreadablePath: "\(sub)/chiusa"), unreadablePath: "\(Self.projects)/b/bin/chiusa"),
            unreadablePath: "\(Self.projects)/c")

        let outcome = try create(fs).scan(binObjRule())

        #expect(outcome.items == [
            ScanItem(path: "\(sub)/bin", sizeBytes: 10, isDirectory: true, declaredRoot: Self.projects),
            ScanItem(path: "\(Self.projects)/b/bin", sizeBytes: 20, isDirectory: true, declaredRoot: Self.projects),
            ScanItem(path: "\(Self.projects)/b/obj", sizeBytes: 5, isDirectory: true, declaredRoot: Self.projects),
        ])
        #expect(outcome.errors.map(\.path) == ["\(sub)/chiusa", "\(Self.projects)/b/bin/chiusa", "\(Self.projects)/c"])
        #expect(outcome.exclusions.map(\.path) == ["\(sub)/.git", "\(Self.projects)/d/.git"])
    }
}
