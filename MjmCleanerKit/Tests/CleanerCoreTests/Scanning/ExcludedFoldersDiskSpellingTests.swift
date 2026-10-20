import Darwin
import Foundation
import Synchronization
import Testing
@testable import CleanerCore

/// Registra i percorsi chiesti a `storedPath`.
private final class StoredPathLogFileSystem: ForwardingFileSystem, @unchecked Sendable {
    let paths = Recorder<String>()

    override func storedPath(_ path: String) throws -> String {
        paths.append(path)
        return try super.storedPath(path)
    }
}

/// `storedPath` riesce sulle prime `successes` chiamate per `path`, poi lancia `code`: una root che
/// smette di essere verificabile dopo `validateRoot`.
private final class StoredPathFailingLaterFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let path: String
    private let code: Int32
    private let successes: Mutex<Int>

    init(_ inner: any FileSystem, path: String, successes: Int, code: Int32) {
        self.path = path
        self.code = code
        self.successes = Mutex(successes)
        super.init(inner)
    }

    override func storedPath(_ path: String) throws -> String {
        if path == self.path {
            let fails = successes.withLock { remaining -> Bool in
                guard remaining > 0 else { return true }
                remaining -= 1
                return false
            }
            if fails { throw FileSystemError(code: code, path: path) }
        }
        return try super.storedPath(path)
    }
}

/// Le cartelle escluse confrontate anche nella grafia del disco (spec
/// `2026-10-20-excluded-folders-canonical-design.md`). `AliasingFileSystem` fa da collegamento e da
/// equivalenza di APFS per `storedPath`; `FakeLinkInspector` fa da collegamento per scanner e guard.
struct ExcludedFoldersDiskSpellingTests {
    private static let home = "/Users/tester"
    private static let caches = "/Users/tester/Library/Caches"
    private static let src = "/Users/tester/src"
    private static let temp = "/private/var/folders/ab/T"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]
    private static let excludedReason = "cartella esclusa nelle Impostazioni"
    private static let containsReason = "contiene una cartella esclusa nelle Impostazioni"

    private func create(_ fs: any FileSystem, links: FakeLinkInspector = FakeLinkInspector()) throws -> RuleScanner {
        RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    private func clearCaches(_ excluded: String) -> CleanupRule {
        CleanupRule(Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: [excluded])
    }

    private func projects(_ fs: InMemoryFileSystem) {
        fs.addFile("\(Self.src)/app/app.csproj", size: 1)
        fs.addFile("\(Self.src)/app/bin/app.dll", size: 100)
        fs.addFile("\(Self.src)/vecchio/vecchio.csproj", size: 1)
        fs.addFile("\(Self.src)/vecchio/bin/vecchio.dll", size: 200)
    }

    private func binAndObj(excluded: String) -> CleanupRule {
        CleanupRule(Self.src, .matchingDirs, include: ["bin", "obj"], exclude: [], requiresProjectMarker: true, excludedPaths: [excluded])
    }

    private func unverifiable(_ code: Int32, _ path: String) -> String {
        "cartella esclusa non verificabile sul filesystem: \(FileSystemError(code: code, path: path).description)"
    }

    // MARK: - Collegamenti

    /// Un'esclusione scritta a mano può passare per un collegamento sotto la root: lo scanner, che
    /// non segue i collegamenti, trova la cartella con il nome della destinazione.
    @Test func anExclusionWrittenThroughALinkUnderTheRootPrunesTheTarget() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.src)/app/app.csproj", size: 1)
        memory.addFile("\(Self.src)/app/bin/app.dll", size: 100)
        memory.addFile("\(Self.src)/archivio/vecchio/vecchio.csproj", size: 1)
        memory.addFile("\(Self.src)/archivio/vecchio/bin/vecchio.dll", size: 200)
        let fs = AliasingFileSystem(memory, aliases: [("\(Self.src)/collegamento", "\(Self.src)/archivio")])

        let outcome = try create(fs).scan(binAndObj(excluded: "\(Self.src)/collegamento/vecchio"))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/app/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/archivio/vecchio", reason: Self.excludedReason)])
    }

    /// Il caso «contiene» attraverso un collegamento: svuotare "com.foo" cancellerebbe la cartella
    /// esclusa, scritta passando per "collegamento".
    @Test func aChildContainingAnExclusionWrittenThroughALinkIsNotProposed() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/com.foo/tieni/dati.bin", size: 100)
        memory.addFile("\(Self.caches)/com.bar/dati.bin", size: 50)
        let fs = AliasingFileSystem(memory, aliases: [("\(Self.caches)/collegamento", "\(Self.caches)/com.foo")])

        let outcome = try create(fs).scan(clearCaches("\(Self.caches)/collegamento/tieni"))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.bar"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.caches)/com.foo", reason: Self.containsReason)])
    }

    /// `storedPath` non segue l'ultimo componente: un'esclusione che è un collegamento vale anche
    /// per la sua destinazione finale.
    @Test func anExclusionThatIsALinkAlsoExcludesItsTarget() throws {
        let fs = InMemoryFileSystem()
        projects(fs)
        let links = FakeLinkInspector(targets: ["\(Self.src)/collegamento": "\(Self.src)/vecchio"])

        let outcome = try create(fs, links: links).scan(binAndObj(excluded: "\(Self.src)/collegamento"))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/app/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/vecchio", reason: Self.excludedReason)])
    }

    @Test func aBinContainingTheTargetOfAnExclusionThatIsALinkIsNotProposed() throws {
        let fs = InMemoryFileSystem()
        projects(fs)
        fs.addFile("\(Self.src)/app/bin/tieni/firma.p12", size: 5)
        let links = FakeLinkInspector(targets: ["\(Self.src)/tieni": "\(Self.src)/app/bin/tieni"])

        let outcome = try create(fs, links: links).scan(binAndObj(excluded: "\(Self.src)/tieni"))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/vecchio/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/app/bin", reason: Self.containsReason)])
    }

    /// Un'esclusione scritta attraverso un collegamento il cui ultimo componente è a sua volta un
    /// collegamento: si riconosce e si risolve sulla grafia del disco, non sul testo.
    @Test func anExclusionWrittenThroughALinkThatIsItselfALinkAlsoExcludesItsTarget() throws {
        let memory = InMemoryFileSystem()
        projects(memory)
        memory.addFile("\(Self.src)/app/bin/tieni/firma.p12", size: 5)
        let fs = AliasingFileSystem(memory, aliases: [("\(Self.src)/collegamento", "\(Self.src)/archivio")])
        let links = FakeLinkInspector(targets: ["\(Self.src)/archivio/tieni": "\(Self.src)/app/bin/tieni"])

        let outcome = try create(fs, links: links).scan(binAndObj(excluded: "\(Self.src)/collegamento/tieni"))

        #expect(outcome.items.map(\.path) == ["\(Self.src)/vecchio/bin"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.src)/app/bin", reason: Self.containsReason)])
    }

    // MARK: - Grafie diverse dello stesso percorso

    /// Una root dichiarata "/private/var/…" non ha collegamenti da risolvere: un'esclusione scritta
    /// sotto il collegamento "/var" vale solo nella grafia del disco. `contains` prova il caso
    /// «contiene».
    @Test(arguments: [("/var/folders/ab/T/tieni", false), ("/var/folders/ab/T/tieni/sotto", true)])
    func anExclusionUnderVarMatchesARootDeclaredUnderPrivateVar(excluded: String, contains: Bool) throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.temp)/tieni/sotto/dati.bin", size: 100)
        memory.addFile("\(Self.temp)/via/dati.bin", size: 100)
        let fs = AliasingFileSystem(memory, aliases: [("/var", "/private/var")])

        let outcome = try create(fs).scan(CleanupRule(Self.temp, .clearContents, include: Self.all, exclude: [], excludedPaths: [excluded]))

        #expect(outcome.items.map(\.path) == ["\(Self.temp)/via"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.temp)/tieni", reason: contains ? Self.containsReason : Self.excludedReason)])
    }

    /// La root stessa sotto un'esclusione scritta sotto "/var": una sola esclusione sulla root, come
    /// per un'esclusione scritta con il testo della root.
    @Test func aRootUnderAnExclusionWrittenUnderVarProducesNothing() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.temp)/via/dati.bin", size: 100)
        let fs = AliasingFileSystem(memory, aliases: [("/var", "/private/var")])

        let outcome = try create(fs).scan(CleanupRule(Self.temp, .clearContents, include: Self.all, exclude: [], excludedPaths: ["/var/folders/ab"]))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.temp, reason: Self.excludedReason)])
    }

    /// APFS case-insensitive ripiega più di OrdinalIgnoreCase e confronta i nomi senza badare alla
    /// normalizzazione Unicode. `suffix` vuoto prova l'esclusione diretta, "/tieni" il caso
    /// «contiene».
    @Test(arguments: [
        ("Kit", "\u{212A}it"),
        ("caf\u{00E9}", "cafe\u{0301}"),
        ("cafe\u{0301}", "caf\u{00E9}"),
        ("Messages", "Me\u{00DF}ages"),
    ], ["", "/tieni"])
    func anExclusionInAnotherSpellingOfTheSameNameMatches(names: (stored: String, alias: String), suffix: String) throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/\(names.stored)/tieni/dati.bin", size: 100)
        memory.addFile("\(Self.caches)/com.bar/dati.bin", size: 50)
        let fs = AliasingFileSystem(memory, aliases: [("\(Self.caches)/\(names.alias)", "\(Self.caches)/\(names.stored)")])

        let outcome = try create(fs).scan(clearCaches("\(Self.caches)/\(names.alias)\(suffix)"))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.bar"])
        #expect(outcome.exclusions == [GuardExclusion(
            path: "\(Self.caches)/\(names.stored)", reason: suffix.isEmpty ? Self.excludedReason : Self.containsReason)])
    }

    /// La root dichiarata in NFD, il disco e l'esclusione presa dal pannello in NFC: gli elementi
    /// arrivano sotto la root dichiarata, e l'esclusione vale solo sotto la grafia del disco della
    /// root. `contains` prova il caso «contiene».
    @Test(arguments: [("/tieni", false), ("/tieni/sotto", true)])
    func anExclusionInTheDiskSpellingMatchesARootDeclaredInAnotherNormalization(suffix: String, contains: Bool) throws {
        let declared = "/Users/tester/Lavoro/Cafe\u{0301}"
        let onDisk = "/Users/tester/Lavoro/Caf\u{00E9}"
        let memory = InMemoryFileSystem()
        memory.addFile("\(declared)/tieni/sotto/dati.bin", size: 100)
        memory.addFile("\(declared)/via/dati.bin", size: 100)
        let fs = AliasingFileSystem(memory, aliases: [(declared, onDisk)])

        let outcome = try create(fs).scan(CleanupRule(declared, .clearContents, include: Self.all, exclude: [], excludedPaths: ["\(onDisk)\(suffix)"]))

        #expect(outcome.items.map(\.path) == ["\(declared)/via"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(declared)/tieni", reason: contains ? Self.containsReason : Self.excludedReason)])
    }

    /// La root dichiarata è un collegamento: `storedPath` non segue l'ultimo componente, quindi la
    /// grafia del disco va presa dalla root risolta, la destinazione, non dal collegamento.
    @Test func anExclusionInTheDiskSpellingOfALinkedRootMatches() throws {
        let target = "/Users/tester/Archivio/Cafe\u{0301}"
        let onDisk = "/Users/tester/Archivio/Caf\u{00E9}"
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/tieni/dati.bin", size: 100)
        memory.addFile("\(Self.caches)/via/dati.bin", size: 100)
        let fs = AliasingFileSystem(memory, aliases: [(target, onDisk)])
        let links = FakeLinkInspector(targets: [Self.caches: target])

        let outcome = try create(fs, links: links).scan(CleanupRule(
            Self.caches, .clearContents, include: Self.all, exclude: [], excludedPaths: ["\(onDisk)/tieni"]))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/via"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.caches)/tieni", reason: Self.excludedReason)])
    }

    // MARK: - Rifiuti

    /// Un'esclusione che non è un percorso assoluto canonico non varrebbe mai: la regola non
    /// produce nulla, come per un'esclusione non verificabile.
    @Test(arguments: ["Parallels", "", "/Users/tester//Parallels", "/Users/tester/./Parallels", "/Users/tester/src/../Parallels"])
    func aNonCanonicalExclusionStopsTheRule(excluded: String) throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)

        let outcome = try create(fs).scan(clearCaches(excluded))

        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.caches, reason: "cartella esclusa con un percorso non valido: «\(excluded)»")])
    }

    @Test(arguments: [EIO, ELOOP])
    func anExclusionWhoseDiskSpellingCannotBeReadStopsTheRule(code: Int32) throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)
        let fs = AliasingFileSystem(memory, failures: [("/Volumes/Archivio", code)])

        let outcome = try create(fs).scan(clearCaches("/Volumes/Archivio"))

        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.caches, reason: unverifiable(code, "/Volumes/Archivio"))])
    }

    /// Un collegamento la cui destinazione non si determina, per esempio un ciclo, non dice cosa
    /// proteggere.
    @Test func anExclusionThatIsALinkWithoutADeterminableTargetStopsTheRule() throws {
        let fs = InMemoryFileSystem()
        projects(fs)
        let links = FakeLinkInspector("\(Self.src)/collegamento")

        let outcome = try create(fs, links: links).scan(binAndObj(excluded: "\(Self.src)/collegamento"))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.src, reason: unverifiable(ELOOP, "\(Self.src)/collegamento"))])
    }

    @Test func anExclusionThatIsALinkToAnUnreadableTargetStopsTheRule() throws {
        let memory = InMemoryFileSystem()
        projects(memory)
        let fs = AliasingFileSystem(memory, failures: [("/Volumes/Rotto/vecchio", EIO)])
        let links = FakeLinkInspector(targets: ["\(Self.src)/collegamento": "/Volumes/Rotto/vecchio"])

        let outcome = try create(fs, links: links).scan(binAndObj(excluded: "\(Self.src)/collegamento"))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(path: Self.src, reason: unverifiable(EIO, "/Volumes/Rotto/vecchio"))])
    }

    /// La root risolta che smette di essere verificabile fra `validateRoot` e le esclusioni: in
    /// pratica una gara, ma senza la sua grafia del disco un'esclusione potrebbe non valere.
    @Test func aRootThatStopsBeingVerifiableAfterValidationStopsTheRule() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)
        let fs = StoredPathFailingLaterFileSystem(memory, path: Self.caches, successes: 1, code: EIO)

        let outcome = try create(fs).scan(clearCaches("\(Self.caches)/com.foo"))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions == [GuardExclusion(
            path: Self.caches, reason: "root non verificabile sul filesystem: \(FileSystemError(code: EIO, path: Self.caches).description)")])
    }

    /// EACCES su un'esclusione: nemmeno il kernel la raggiunge, quindi si risale come nel
    /// `PathGuard` e l'esclusione vale con il testo ricomposto, senza fermare la regola.
    @Test func anExclusionThatCannotBeLookedUpClimbsAndStillApplies() throws {
        let memory = InMemoryFileSystem()
        memory.addFile("\(Self.caches)/com.foo/dati.bin", size: 100)
        memory.addFile("\(Self.caches)/com.bar/dati.bin", size: 50)
        let fs = AliasingFileSystem(memory, failures: [("\(Self.caches)/com.foo", EACCES)])

        let outcome = try create(fs).scan(clearCaches("\(Self.caches)/com.foo"))

        #expect(outcome.items.map(\.path) == ["\(Self.caches)/com.bar"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(Self.caches)/com.foo", reason: Self.excludedReason)])
    }

    // MARK: - Costo

    /// Senza esclusioni la regola non chiede a `storedPath` più di quanto chieda `validateRoot`;
    /// con un'esclusione sì, e il registro lo vede.
    @Test func aRuleWithoutExclusionsAsksStoredPathNoMoreThanValidateRoot() throws {
        let memory = InMemoryFileSystem()
        memory.addDirectory(Self.caches)
        let fs = StoredPathLogFileSystem(memory)
        let links = FakeLinkInspector()
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home)
        let scanner = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: FixedWallClock(now: Self.now))

        let beforeRoot = fs.paths.values.count
        _ = pathGuard.validateRoot(Self.caches)
        let byValidateRoot = fs.paths.values.count - beforeRoot

        let beforeScan = fs.paths.values.count
        _ = try scanner.scan(CleanupRule(Self.caches, .clearContents, include: Self.all, exclude: []))
        #expect(fs.paths.values.count - beforeScan == byValidateRoot)

        let beforeExcluded = fs.paths.values.count
        _ = try scanner.scan(clearCaches("\(Self.caches)/com.foo"))
        #expect(fs.paths.values.count - beforeExcluded > byValidateRoot)
    }
}
