import Testing
@testable import CleanerCore

struct CleanEngineTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"
    private static let now = utc(2026, 9, 15, 12)

    private func create(_ fs: any FileSystem, _ symlinks: String...) throws -> CleanEngine {
        let links = FakeLinkInspector(symlinks)
        return CleanEngine(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
            clock: FixedWallClock(now: Self.now))
    }

    private func create(_ fs: any FileSystem, targets: [String: String?]) throws -> CleanEngine {
        CleanEngine(
            fileSystem: fs,
            pathGuard: try PathGuard(
                denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: FakeLinkInspector(targets: targets),
                homeDirectory: Self.home),
            clock: FixedWallClock(now: Self.now))
    }

    private func selection(_ id: String, _ items: ScanItem...) -> CategorySelection {
        CategorySelection(categoryId: id, items: items)
    }

    private func item(_ path: String, _ size: Int64, isDirectory: Bool = false, root: String = Self.cacheRoot) -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: isDirectory, declaredRoot: root)
    }

    /// Porting di `RedirectingPathGuard`: ammette sempre, ma `validate` restituisce di proposito un
    /// percorso DIVERSO dall'argomento. Ancora "si valida un percorso, si cancella QUEL percorso".
    private struct RedirectingPathGuard: PathGuarding {
        let root: String
        let redirectTarget: String

        func validateRoot(_ declaredRoot: String) -> GuardVerdict { .allow(root) }
        func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict { .allow(redirectTarget) }
        func pruneReason(_ candidatePath: String) -> String? { nil }
    }

    @Test func deletesFilesAndCountsBytes() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 100)

        let report = try await create(fs).clean([selection("caches", item("\(Self.cacheRoot)/a.tmp", 100))], progress: nil, journal: nil)

        #expect(!fs.fileExists("\(Self.cacheRoot)/a.tmp"))
        #expect(report.bytesFreed == 100)
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
    }

    @Test func completeDownloadsPrunesOnlyDirectoriesEmptiedBySelectedFiles() async throws {
        let fs = InMemoryFileSystem()
        let root = "\(Self.home)/Downloads"
        let emptied = "\(root)/Archivio/Vecchio"
        fs.addFile("\(emptied)/selected.txt", size: 10)
        fs.addFile("\(root)/Archivio/unchecked.txt", size: 20)
        fs.addFile("\(root)/Esclusa/keep.txt", size: 30)
        fs.addDirectory(root)

        let item = ScanItem(
            path: "\(emptied)/selected.txt", sizeBytes: 10, isDirectory: false, declaredRoot: root,
            pruneEmptyDirectories: true)
        let report = try await create(fs).clean(
            [CategorySelection(categoryId: "downloads", items: [item])], progress: nil, journal: nil)

        #expect(!fs.directoryExists(emptied))
        #expect(!fs.directoryExists("\(root)/Archivio/Vecchio"))
        #expect(fs.directoryExists("\(root)/Archivio"))
        #expect(fs.fileExists("\(root)/Archivio/unchecked.txt"))
        #expect(fs.directoryExists("\(root)/Esclusa"))
        #expect(fs.fileExists("\(root)/Esclusa/keep.txt"))
        #expect(fs.directoryExists(root))
        #expect(report.bytesFreed == 10)
        #expect(report.itemsDeleted == 1)
    }

    @Test func ordinaryDownloadCleanupDoesNotPruneDirectories() async throws {
        let fs = InMemoryFileSystem()
        let root = "\(Self.home)/Downloads"
        let folder = "\(root)/Archivio"
        fs.addFile("\(folder)/selected.txt", size: 10)

        _ = try await create(fs).clean(
            [selection("downloads", item("\(folder)/selected.txt", 10, root: root))], progress: nil, journal: nil)

        #expect(fs.directoryExists(folder))
        #expect(fs.directoryExists(root))
    }

    @Test func deletesDirectoriesRecursively() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/app/dentro/x.bin", size: 40)

        let report = try await create(fs).clean(
            [selection("caches", item("\(Self.cacheRoot)/app", 40, isDirectory: true))], progress: nil, journal: nil)

        #expect(!fs.directoryExists("\(Self.cacheRoot)/app"))
        #expect(report.bytesFreed == 40)
    }

    @Test func guardRejectionPreventsDeletion() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Documents/riservato.pdf", size: 10)

        // Elemento fabbricato a mano: simula una regola sbagliata che arriva fino all'eliminazione.
        let report = try await create(fs).clean(
            [selection("bug", item("\(Self.home)/Documents/riservato.pdf", 10, root: Self.home))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(Self.home)/Documents/riservato.pdf"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
    }

    @Test func missingFileIsRecordedButNotFatal() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/esiste.tmp", size: 10)

        let report = try await create(fs).clean(
            [selection("caches", item("\(Self.cacheRoot)/sparito.tmp", 999), item("\(Self.cacheRoot)/esiste.tmp", 10))],
            progress: nil, journal: nil)

        #expect(report.bytesFreed == 10)
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 1)
        #expect(report.errors.contains { $0.kind == .notFound })
    }

    @Test func onlyActuallyFreedBytesAreCounted() async throws {
        let report = try await create(InMemoryFileSystem()).clean(
            [selection("caches", item("\(Self.cacheRoot)/mai-esistito.tmp", 5_000))], progress: nil, journal: nil)
        #expect(report.bytesFreed == 0)

        // Dimensione dichiarata falsa: l'elemento esiste davvero, ma con un contenuto molto più
        // piccolo di quanto sizeBytes affermi. Il resoconto deve riportare i byte MISURATI subito
        // prima della cancellazione, non quelli dichiarati dall'interfaccia: un contatore che
        // somma le intenzioni diventa decorativo in un mese.
        let lied = InMemoryFileSystem()
        lied.addFile("\(Self.cacheRoot)/piccola/dentro/x.bin", size: 10)

        let liedReport = try await create(lied).clean(
            [selection("caches", item("\(Self.cacheRoot)/piccola", 5_000_000_000, isDirectory: true))], progress: nil, journal: nil)

        #expect(!lied.directoryExists("\(Self.cacheRoot)/piccola"))
        #expect(liedReport.bytesFreed == 10)
    }

    @Test func resultsAreGroupedByCategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.home)/.cache/b.tmp", size: 20)

        let report = try await create(fs).clean(
            [
                selection("uno", item("\(Self.cacheRoot)/a.tmp", 10)),
                selection("due", item("\(Self.home)/.cache/b.tmp", 20, root: "\(Self.home)/.cache")),
            ],
            progress: nil, journal: nil)

        #expect(report.categories.filter { $0.categoryId == "uno" }.map(\.bytesFreed) == [10])
        #expect(report.categories.filter { $0.categoryId == "due" }.map(\.bytesFreed) == [20])
        #expect(report.bytesFreed == 30)
    }

    @Test func deletedPathsAreRecordedForTheSessionLog() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)

        let report = try await create(fs).clean([selection("caches", item("\(Self.cacheRoot)/a.tmp", 10))], progress: nil, journal: nil)

        #expect(report.deletedPaths == ["\(Self.cacheRoot)/a.tmp"])
    }

    @Test func cancellationReturnsPartialReportInsteadOfThrowing() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        let engine = try create(fs)
        let selections = [selection("caches", item("\(Self.cacheRoot)/a.tmp", 10))]

        let report = await Task {
            cancelCurrentTask()
            return await engine.clean(selections, progress: nil, journal: nil)
        }.value

        #expect(report.itemsDeleted == 0)
        #expect(fs.fileExists("\(Self.cacheRoot)/a.tmp"))
    }

    // CRITICAL: l'elenco arriva dall'interfaccia dopo la conferma dell'utente, quindi è
    // manipolabile. Una declaredRoot fabbricata che è in realtà un collegamento verso una cartella
    // protetta deve fallire alla convalida della ROOT (validateRoot), non a quella del singolo
    // elemento: validate da sola non vede che il genitore diretto dell'elemento è un collegamento,
    // perché il suo ciclo si ferma proprio alla root senza eseguire alcuna iterazione quando la
    // root È il genitore diretto — il caso di ogni elemento clearContents.
    @Test func fabricatedDeclaredRootResolvingToProtectedPathIsRejected() async throws {
        let fakeRoot = "\(Self.cacheRoot)/finto"
        let fs = InMemoryFileSystem()
        fs.addFile("\(fakeRoot)/contratto.pdf", size: 10)

        let report = try await create(fs, targets: [fakeRoot: "\(Self.home)/Documents"]).clean(
            [selection("bug", item("\(fakeRoot)/contratto.pdf", 10, root: fakeRoot))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(fakeRoot)/contratto.pdf"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.deletedPaths.isEmpty)
    }

    // Stessa fuga, variante con directory: con isDirectory = true l'eliminazione sarebbe ricorsiva
    // (deleteDirectoryRecursively), l'esito più costoso possibile se il guard non fermasse tutto
    // alla root.
    @Test func fabricatedDeclaredRootResolvingToProtectedPathRejectsDirectoryRecursively() async throws {
        let fakeRoot = "\(Self.cacheRoot)/finto2"
        let fs = InMemoryFileSystem()
        fs.addFile("\(fakeRoot)/fatture2026/gennaio.pdf", size: 10)

        let report = try await create(fs, targets: [fakeRoot: "\(Self.home)/Documents"]).clean(
            [selection("bug", item("\(fakeRoot)/fatture2026", 10, isDirectory: true, root: fakeRoot))], progress: nil, journal: nil)

        #expect(fs.directoryExists("\(fakeRoot)/fatture2026"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.deletedPaths.isEmpty)
    }

    // Nessuna manipolazione dell'elenco: la declaredRoot è quella vera prodotta dallo scanner. Ma
    // fra la scansione e la conferma dell'utente, ~/Library/Caches è stata sostituita con un
    // collegamento verso ~/Documents (es. un tool di sincronizzazione). Il guard viene invocato di
    // nuovo qui, immediatamente prima della cancellazione, apposta per questo scarto temporale:
    // senza richiamare validateRoot in CleanEngine, un elemento del tutto legittimo al momento
    // della scansione verrebbe cancellato attraverso il collegamento.
    @Test func rootReplacedBySymlinkAfterScanRejectsOtherwiseLegitimateItem() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/tesi.docx", size: 10)

        let report = try await create(fs, targets: [Self.cacheRoot: "\(Self.home)/Documents"]).clean(
            [selection("caches", item("\(Self.cacheRoot)/tesi.docx", 10))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(Self.cacheRoot)/tesi.docx"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.deletedPaths.isEmpty)
    }

    // IMPORTANT 2: un'eccezione fuori dal contratto di RuleScanner.isExpected (qui
    // UnexpectedTestError, non FileSystemError) non deve far propagare clean né perdere il
    // resoconto. Con l'eliminazione definitiva, l'elenco di ciò che è già stato cancellato prima
    // del crash è l'unica ricostruzione possibile di cosa è sparito: perderlo è peggio del
    // fallimento stesso.
    @Test func unexpectedExceptionDuringDeletionReturnsPartialReportInsteadOfThrowing() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/uno.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/due.tmp", size: 20)
        fs.addFile("\(Self.cacheRoot)/tre.tmp", size: 30)

        let report = try await create(ThrowingOnDeleteFileSystem(fs, throwingPath: "\(Self.cacheRoot)/due.tmp")).clean(
            [selection("caches",
                       item("\(Self.cacheRoot)/uno.tmp", 10),
                       item("\(Self.cacheRoot)/due.tmp", 20),
                       item("\(Self.cacheRoot)/tre.tmp", 30))],
            progress: nil, journal: nil)

        // Il primo elemento, cancellato prima del guasto, resta nel resoconto...
        #expect(report.deletedPaths.contains("\(Self.cacheRoot)/uno.tmp"))
        #expect(report.bytesFreed == 10)
        #expect(report.itemsDeleted == 1)
        // ...l'errore imprevisto compare fra gli errori invece di propagare...
        #expect(report.itemsFailed == 1)
        #expect(!report.errors.isEmpty)
        // ...e il terzo elemento, mai raggiunto, non risulta né eliminato né tentato.
        #expect(fs.fileExists("\(Self.cacheRoot)/due.tmp"))
        #expect(fs.fileExists("\(Self.cacheRoot)/tre.tmp"))
    }

    // MINOR 1: due CategorySelection con lo stesso categoryId devono produrre UNA voce nel resoconto
    // con i totali sommati, non due. L'interfaccia cercherà una categoria per identificativo
    // (Single() nel C#), accesso che fallisce in presenza di duplicati.
    @Test func duplicateCategoryIdsAreMergedIntoOneReportEntry() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/b.tmp", size: 20)

        let report = try await create(fs).clean(
            [selection("caches", item("\(Self.cacheRoot)/a.tmp", 10)), selection("caches", item("\(Self.cacheRoot)/b.tmp", 20))],
            progress: nil, journal: nil)

        #expect(report.categories == [CategoryCleanResult(categoryId: "caches", bytesFreed: 30, itemsDeleted: 2)])
    }

    // MINOR 2: il continue sugli elementi respinti dal guard non deve saltare la segnalazione di
    // avanzamento. Con due elementi di cui il secondo respinto, l'ULTIMA notifica deve riportare
    // due elementi elaborati su due, non fermarsi a uno.
    @Test func progressReachesTheEndEvenWithRejectedItems() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.home)/Documents/riservato.pdf", size: 10)
        let progress = Recorder<CleanProgress>()

        _ = try await create(fs).clean(
            [selection("misto", item("\(Self.cacheRoot)/a.tmp", 10), item("\(Self.home)/Documents/riservato.pdf", 10, root: Self.home))],
            progress: { progress.append($0) }, journal: nil)

        let last = try #require(progress.values.last)
        #expect(last.itemsDone == 2)
        #expect(last.itemsTotal == 2)
    }

    // IMPORTANT: RuleScanner enumera a partire dalla root DICHIARATA, quindi ScanItem.path e
    // ScanItem.declaredRoot sono entrambi non risolti. Se validateRoot risolve la root a una
    // stringa diversa — l'esempio reale è $TMPDIR: "/var" è un collegamento a "/private/var" su
    // ogni macOS di serie — l'elemento va riportato nello stesso sistema di riferimento PRIMA di
    // validarlo, altrimenti il contenimento confronta basi diverse e fallisce sempre, rendendo la
    // categoria $TMPDIR (selezionata di default) inservibile su ogni Mac. Stessi percorsi di esempio
    // di PathGuardTests.validateRootResolvesSymlinkedAncestorAndAllowsUnprotectedTarget, qui
    // verificati end-to-end fino alla cancellazione effettiva.
    @Test func itemUnderRootThatResolvesToADifferentStringIsStillDeletable() async throws {
        let declaredTmpRoot = "/var/folders/xyz/T"
        let resolvedTmpRoot = "/private/var/folders/xyz/T"
        let fs = InMemoryFileSystem()
        fs.addFile("\(resolvedTmpRoot)/temp123.tmp", size: 15)

        let report = try await create(fs, targets: ["/var": "/private/var"]).clean(
            [selection("tmp", item("\(declaredTmpRoot)/temp123.tmp", 15, root: declaredTmpRoot))], progress: nil, journal: nil)

        #expect(report.bytesFreed == 15)
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
        // Si cancella il percorso RISOLTO restituito dal guard, non quello dichiarato.
        #expect(report.deletedPaths == ["\(resolvedTmpRoot)/temp123.tmp"])
        #expect(!fs.fileExists("\(resolvedTmpRoot)/temp123.tmp"))
    }

    // MINOR: un elemento con declaredRoot vuota ("malformato") non deve far fallire l'intera
    // pre-validazione delle root. Nel C# il dizionario costruito una volta sola sulle root distinte
    // veniva indicizzato con una DeclaredRoot nulla — Dictionary rifiuta una chiave nulla lanciando
    // ArgumentNullException fuori da ogni isolamento per elemento — facendo fallire l'intera
    // pulizia (zero eliminati) invece del solo elemento malformato.
    // Porting di MalformedItemWithNullDeclaredRootDoesNotAbortTheWholeRun: in Swift una root nulla è
    // impossibile per tipo; l'equivalente malformato è la root vuota. Solo quell'elemento fallisce.
    @Test func malformedItemWithEmptyDeclaredRootDoesNotAbortTheWholeRun() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/uno.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/tre.tmp", size: 30)

        let report = try await create(fs).clean(
            [selection("caches",
                       item("\(Self.cacheRoot)/uno.tmp", 10),
                       item("qualunque/percorso", 20, root: ""),
                       item("\(Self.cacheRoot)/tre.tmp", 30))],
            progress: nil, journal: nil)

        #expect(report.itemsDeleted == 2)
        #expect(report.itemsFailed == 1)
        #expect(report.bytesFreed == 40)
        #expect(!fs.fileExists("\(Self.cacheRoot)/uno.tmp"))
        #expect(!fs.fileExists("\(Self.cacheRoot)/tre.tmp"))
    }

    // Difesa "nessuna categoria fantasma dopo l'annullamento" (MINOR 3 della correzione precedente),
    // finora non ancorata da alcun test: cancellationReturnsPartialReportInsteadOfThrowing annulla
    // PRIMA di iniziare, quindi passa identico con o senza quella difesa. Qui l'annullamento avviene
    // A METÀ (dopo la prima categoria, dal callback di avanzamento): le categorie successive, mai
    // iniziate, non devono comparire nel resoconto nemmeno a zero.
    @Test func cancellationMidRunDoesNotAddUnprocessedCategoriesToTheReport() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/uno.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/due.tmp", size: 20)
        fs.addFile("\(Self.cacheRoot)/tre.tmp", size: 30)
        let engine = try create(fs)
        let selections = [
            selection("uno", item("\(Self.cacheRoot)/uno.tmp", 10)),
            selection("due", item("\(Self.cacheRoot)/due.tmp", 20)),
            selection("tre", item("\(Self.cacheRoot)/tre.tmp", 30)),
        ]

        let report = await Task {
            await engine.clean(selections, progress: { _ in cancelCurrentTask() }, journal: nil)
        }.value

        #expect(report.categories.map(\.categoryId) == ["uno"])
        #expect(report.bytesFreed == 10)
        #expect(fs.fileExists("\(Self.cacheRoot)/due.tmp"))
        #expect(fs.fileExists("\(Self.cacheRoot)/tre.tmp"))
    }

    // "Si valida un percorso, si cancella QUEL percorso": è la proposizione per cui esiste
    // GuardVerdict.canonicalPathValidated, il cui stesso commento dichiara che può differire
    // dall'argomento passato a validate. Oggi le due stringhe coincidono sempre (validate normalizza
    // solo lo slash finale, e gli elementi enumerati non ne hanno mai uno) — una coincidenza, non una
    // garanzia: RedirectingPathGuard la rompe deliberatamente, restituendo un percorso diverso da
    // quello ricevuto, entrambi esistenti sul filesystem simulato.
    @Test func deletesThePathTheGuardReturnsNotThePathItWasGiven() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/richiesto.tmp", size: 999) // non va toccato
        fs.addFile("\(Self.cacheRoot)/reale.tmp", size: 7)       // quello che il guard restituisce
        let engine = CleanEngine(
            fileSystem: fs,
            pathGuard: RedirectingPathGuard(root: Self.cacheRoot, redirectTarget: "\(Self.cacheRoot)/reale.tmp"),
            clock: FixedWallClock(now: Self.now))

        let report = await engine.clean([selection("caches", item("\(Self.cacheRoot)/richiesto.tmp", 999))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(Self.cacheRoot)/richiesto.tmp"))
        #expect(!fs.fileExists("\(Self.cacheRoot)/reale.tmp"))
        #expect(report.bytesFreed == 7)
        #expect(report.deletedPaths == ["\(Self.cacheRoot)/reale.tmp"])
    }

    // Nuovo (spec §8.2): il diario riceve ogni percorso nel momento in cui viene eliminato, e solo
    // quelli eliminati davvero.
    @Test func journalReceivesEveryDeletedPathAsItHappens() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/b.tmp", size: 10)
        let journal = RecordingJournal()
        // Il diario deve già contenere ogni percorso quando ne viene segnalato l'avanzamento: un
        // diario riempito in blocco alla fine passerebbe il solo controllo sul contenuto finale.
        let countsAtProgress = Recorder<Int>()

        _ = try await create(fs).clean(
            [selection("caches",
                       item("\(Self.cacheRoot)/a.tmp", 10),
                       item("\(Self.cacheRoot)/sparito.tmp", 10),
                       item("\(Self.cacheRoot)/b.tmp", 10))],
            progress: { _ in countsAtProgress.append(journal.paths.values.count) }, journal: journal)

        #expect(journal.paths.values == ["\(Self.cacheRoot)/a.tmp", "\(Self.cacheRoot)/b.tmp"])
        #expect(countsAtProgress.values == [1, 1, 2])
    }

    // Solo Swift: una chiave String unirebbe root che OrdinalIgnoreCase distingue.
    @Test func everyDistinctRootIsValidatedEvenWhenAnotherRootIsCanonicallyEquivalent() async throws {
        let fs = InMemoryFileSystem()
        let decoyRoot = "\(Self.home)/Des\u{212A}top"
        let protectedRoot = "\(Self.home)/Desktop"
        fs.addFile("\(decoyRoot)/decoy.tmp", size: 1)
        fs.addFile("\(protectedRoot)/secret.txt", size: 10)
        // Su APFS il segno KELVIN (U+212A), ripiegato in "k", è la stessa cartella di ~/Desktop: il
        // vecchio codice avrebbe riscritto secret.txt proprio in questa grafia. Il filesystem simulato
        // confronta le chiavi per equivalenza canonica e non ripiega come APFS, quindi il file va
        // registrato anche sotto la grafia decoy, dove il vecchio codice lo cercherebbe.
        fs.addFile("\(decoyRoot)/secret.txt", size: 10)

        let report = try await create(fs).clean(
            [selection("bug",
                       item("\(decoyRoot)/decoy.tmp", 1, root: decoyRoot),
                       item("\(protectedRoot)/secret.txt", 10, root: protectedRoot))],
            progress: nil, journal: nil)

        #expect(fs.fileExists("\(protectedRoot)/secret.txt"))
        #expect(fs.fileExists("\(decoyRoot)/secret.txt"))
        #expect(!report.deletedPaths.contains { $0.hasSuffix("secret.txt") })
    }

    // Solo Swift: U+03B9 (2 byte) e U+1FBE (3 byte) hanno lo stesso ripiegamento (U+0399), quindi il
    // resto va tagliato per scalari, né per byte né per Character. U+0600 è un Prepend: con i
    // Character il "/" che lo segue si fonde con lui e il taglio perderebbe la "/" iniziale.
    @Test func rewriteSlicesTheRemainderByScalarsAfterACaseInsensitiveMatch() {
        #expect(CleanEngine.rewriteToResolvedRoot("/VAR/\u{1FBE}/xé.tmp", declaredRoot: "/var/\u{03B9}", resolvedRoot: "/private/var/\u{03B9}")
            == "/private/var/\u{03B9}/xé.tmp")
        #expect(CleanEngine.rewriteToResolvedRoot("/VAR/\u{0600}/x.tmp", declaredRoot: "/var/\u{0600}", resolvedRoot: "/private/var/\u{0600}")
            == "/private/var/\u{0600}/x.tmp")
    }

    private final class RecordingJournal: DeletionRecording {
        let paths = Recorder<String>()
        func recordDeleted(_ path: String) { paths.append(path) }
    }
}
