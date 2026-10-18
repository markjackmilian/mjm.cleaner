import Darwin
import Testing
@testable import CleanerCore

private struct UnexpectedStoredPathError: Error {}

private final class NonFileSystemErrorStoredPathFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let paths: Set<String>

    init(paths: [String]) {
        self.paths = Set(paths)
        super.init(InMemoryFileSystem())
    }

    override func storedPath(_ path: String) throws -> String {
        if paths.contains(path) { throw UnexpectedStoredPathError() }
        return try super.storedPath(path)
    }
}

struct PathGuardTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"

    private func create(_ symlinks: String...) throws -> PathGuard {
        try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(symlinks), homeDirectory: Self.home)
    }

    private func create(targets: [String: String?]) throws -> PathGuard {
        try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(targets: targets),
            homeDirectory: Self.home)
    }

    @Test func allowsItemInsideDeclaredRoot() throws {
        #expect(try create().validate("\(Self.cacheRoot)/com.apple.Safari", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesItemOutsideDeclaredRoot() throws {
        let verdict = try create().validate("/Users/tester/projects/app/bin", declaredRoot: Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("contenimento"))
    }

    @Test func deniesTraversalEscapingDeclaredRoot() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/../../Documents/fatture", declaredRoot: Self.cacheRoot).isAllowed)
    }

    // Sostituisce il test del brief "CanonicalizesBeforeComparing", che si aspettava questo
    // stesso input PERMESSO dopo una risoluzione testuale di "." e "..". Quella risoluzione è
    // il difetto misurato dalla revisione (CRITICAL 2): Path.GetFullPath risolve ".." prima di
    // seguire un eventuale collegamento simbolico, mentre il kernel lo risolve dopo — quindi un
    // percorso come "{root}/collegamento/.." veniva canonicalizzato a "{root}" (dentro la root,
    // permesso) mentre il sistema avrebbe cancellato il bersaglio del collegamento, altrove.
    // Nessuna canonicalizzazione testuale può chiudere questo buco: la correzione è rifiutare
    // ogni percorso con un segmento "." o ".." invece di risolverlo. Decisione presa in sede di
    // revisione, non un'interpretazione: qui si applica, non si discute più.
    @Test func deniesNonCanonicalPathWithDotSegments() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/./sub/../sub/file", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesDeniedPathEvenWhenInsideDeclaredRoot() throws {
        #expect(try !create().validate("\(Self.home)/Documents/x", declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesHomeItself() throws {
        #expect(try !create().validate(Self.home, declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesDirectChildOfHome() throws {
        let verdict = try create().validate("\(Self.home)/Downloads", declaredRoot: "\(Self.home)/Downloads")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("profondità"))
    }

    @Test func allowsGrandchildOfHome() throws {
        #expect(try create().validate("\(Self.home)/Downloads/vecchio.dmg", declaredRoot: "\(Self.home)/Downloads").isAllowed)
    }

    @Test func allowsSymlinkItselfSoTheLinkCanBeRemoved() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(guardrail.validate("\(Self.cacheRoot)/collegamento", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesItemWhoseAncestorIsSymlink() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        let verdict = guardrail.validate("\(Self.cacheRoot)/collegamento/vittima.txt", declaredRoot: Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("collegamento"))
    }

    // Il collegamento non è solo il genitore immediato: qualunque antenato fra l'elemento e la
    // root rompe il contenimento allo stesso modo. La revisione ha misurato che oggi
    // funzionano già — questi test li fissano perché non regrediscano con le correzioni.
    @Test func deniesItemTwoLevelsBelowSymlinkedAncestor() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(!guardrail.validate("\(Self.cacheRoot)/collegamento/sub/vittima.txt", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesItemThreeLevelsBelowSymlinkedAncestor() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(!guardrail.validate("\(Self.cacheRoot)/collegamento/sub/sub2/vittima.txt", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesRegardlessOfCase() throws {
        #expect(try !create().validate("\(Self.home)/documents/x", declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesDockerContainer() throws {
        let docker = "\(Self.home)/Library/Containers/com.docker.docker/Data/vms"
        #expect(try !create().validate(docker, declaredRoot: "\(Self.home)/Library/Containers").isAllowed)
    }

    // I tre casi seguenti nascono dalla revisione del Task 3, che li aveva misurati
    // come passanti: la radice si riduceva a stringa vuota e sfuggiva a ogni confronto.
    @Test(arguments: ["/", "//"])
    func deniesFilesystemRoot(root: String) throws {
        #expect(try !create().validate(root, declaredRoot: "/").isAllowed)
    }

    @Test func deniesAnotherUsersHome() throws {
        #expect(try !create().validate("/Users/altro/Documents/fatture", declaredRoot: "/Users").isAllowed)
    }

    @Test func deniesExternalVolume() throws {
        #expect(try !create().validate("/Volumes/Backup/2026", declaredRoot: "/Volumes").isAllowed)
    }

    // CRITICAL 3 della revisione: con radice "/" o "//" il contenimento (path.StartsWith(root))
    // diventa vero per qualunque percorso assoluto, non solo per la radice stessa passata come
    // candidatePath (già coperto da DeniesFilesystemRoot). Qui il candidato è un percorso
    // normale, per misurare esattamente la fuga di contenimento segnalata.
    @Test(arguments: ["/", "//"])
    func deniesAnyPathWhenDeclaredRootIsDegenerate(root: String) throws {
        #expect(try !create().validate("/Users/tester/projects/app/bin", declaredRoot: root).isAllowed)
    }

    // CRITICAL 2(a): un segmento ".." dopo un nome che potrebbe essere un collegamento va
    // rifiutato per non canonicità, senza tentare di risolverlo — è esattamente il caso che
    // Path.GetFullPath risolveva testualmente facendo sparire il collegamento dalla stringa.
    @Test(arguments: ["collegamento/..", "collegamento/../sub/file", "a/collegamento/../altro/x"])
    func deniesNonCanonicalPathThroughAlias(suffix: String) throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(!guardrail.validate("\(Self.cacheRoot)/\(suffix)", declaredRoot: Self.cacheRoot).isAllowed)
    }

    // IMPORTANT 1: l'ultimo controllo prima di una cancellazione irreversibile deve restituire
    // un rifiuto anche su input malformati, mai un'eccezione che un catch a monte potrebbe
    // trasformare in un salto silenzioso.
    @Test func deniesEmptyCandidatePathWithoutThrowing() throws {
        #expect(try !create().validate("", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesEmptyDeclaredRootWithoutThrowing() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/file", declaredRoot: "").isAllowed)
    }

    @Test func deniesPathWithEmbeddedNulCharacterWithoutThrowing() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/file\0name", declaredRoot: Self.cacheRoot).isAllowed)
    }

    // CRITICAL 1: la root dichiarata va verificata a parte, una volta per regola, risalendo
    // fino alla radice del filesystem — non solo fino alla root, come fa Validate per ciascun
    // elemento. Senza ValidateRoot, una root che sia essa stessa (o abbia come antenato) un
    // collegamento simbolico — es. una cache spostata su un disco esterno con
    // "ln -s /Volumes/SSD/Caches ~/Library/Caches" — non verrebbe mai esaminata.
    @Test func validateRootAllowsOrdinaryRoot() throws {
        #expect(try create().validateRoot(Self.cacheRoot).isAllowed)
    }

    @Test func validateRootDeniesWhenRootIsSymlink() throws {
        let verdict = try create(Self.cacheRoot).validateRoot(Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("collegamento"))
    }

    @Test func validateRootDeniesWhenAncestorOfRootIsSymlink() throws {
        #expect(try !create("\(Self.home)/Library").validateRoot(Self.cacheRoot).isAllowed)
    }

    @Test func validateRootDeniesWhenHomeIsSymlink() throws {
        #expect(try !create(Self.home).validateRoot(Self.cacheRoot).isAllowed)
    }

    // Dimostra perché ValidateRoot va invocata prima della scansione: il ciclo di Validate è
    // delimitato alla root (per non risalire alla radice del filesystem per ciascuno dei
    // centinaia di migliaia di elementi scansionati), quindi da solo non vede una root che sia
    // essa stessa un collegamento. Non è una regressione: è la responsabilità che ValidateRoot
    // esiste apposta per coprire.
    @Test func validateAloneAllowsDirectChildOfSymlinkedRootButValidateRootDenies() throws {
        let guardrail = try create(Self.cacheRoot)
        #expect(guardrail.validate("\(Self.cacheRoot)/child.tmp", declaredRoot: Self.cacheRoot).isAllowed)
        #expect(!guardrail.validateRoot(Self.cacheRoot).isAllowed)
    }

    // IMPORTANT 2: home e collegamento con la deny-list.
    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//"] as [String?])
    func constructorRejectsInvalidHomeDirectory(homeDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) {
            try PathGuard(
                denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(),
                homeDirectory: homeDirectory)
        }
    }

    @Test func constructorRejectsHomeThatDiffersFromDenyListHome() {
        #expect(throws: InvalidConfiguration.self) {
            try PathGuard(
                denyList: DenyList(homeDirectory: "/Users/altro"), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(),
                homeDirectory: Self.home)
        }
    }

    // IMPORTANT 1 della revisione del Task 8: su macOS "/var" (quindi "$TMPDIR"), "/etc" e
    // "/tmp" sono essi stessi collegamenti simbolici verso "/private/...". Negare ogni root il
    // cui antenato sia un collegamento (comportamento precedente) rendeva $TMPDIR
    // permanentemente non pulibile su ogni Mac, pur non essendoci alcun dato a rischio. La
    // correzione risolve la root invece di negarla alla cieca, e applica al percorso risolto la
    // stessa deny-list e lo stesso controllo di canonicità già in uso altrove.
    @Test func validateRootResolvesSymlinkedAncestorAndStillDeniesProtectedTarget() throws {
        let verdict = try create(targets: ["/etc": "/private/etc"]).validateRoot("/etc/qualcosa")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("/private/etc"))
        #expect(verdict.canonicalPathValidated == "/private/etc/qualcosa")
    }

    @Test func validateRootResolvesSymlinkedAncestorAndAllowsUnprotectedTarget() throws {
        let verdict = try create(targets: ["/var": "/private/var"]).validateRoot("/var/folders/xyz/T")
        #expect(verdict.isAllowed)
        #expect(verdict.canonicalPathValidated == "/private/var/folders/xyz/T")
    }

    // Il test più importante dei tre: è lo scenario che ha fatto nascere ValidateRoot
    // (CRITICAL 1) e deve continuare a essere negato dopo la correzione.
    @Test func validateRootStillDeniesCacheRootRelocatedToExternalVolume() throws {
        let verdict = try create(targets: [Self.cacheRoot: "/Volumes/SSD/Caches"]).validateRoot(Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("/Volumes"))
        #expect(verdict.canonicalPathValidated == "/Volumes/SSD/Caches")
    }

    // IMPORTANT 4: la discesa ricorsiva di uno scanner deve poter chiedere se un ramo è protetto
    // dalla deny-list senza applicare anche la regola di profondità di Validate, che poterebbe
    // ogni cartella legittima di primo livello sotto la home.
    @Test func shouldPruneReportsDeniedBranch() throws {
        let reason = try #require(try create().pruneReason("\(Self.home)/Documents"))
        #expect(reason.contains("Documents"))
    }

    @Test func shouldPruneAllowsOrdinaryBranch() throws {
        #expect(try create().pruneReason(Self.cacheRoot) == nil)
    }

    // IMPORTANT (re-revisione): le voci a uguaglianza esatta della deny-list ("/", "/Users", la
    // home) proteggono solo se stesse, non un intero sottoalbero — applicarle alla ROOT di una
    // scansione (non solo agli elementi, dove è corretto) vieta di guardare sotto quella root.
    // Misurato con LargeFileRoots = ["~"], un'impostazione utente plausibile: la home veniva
    // negata già da ValidateRoot, azzerando la funzione "trova i file grandi" proprio nella
    // configurazione più naturale.
    @Test func validateRootAllowsHomeItselfBecauseExactMatchEntriesDoNotApplyToRoots() throws {
        #expect(try create().validateRoot(Self.home).isAllowed)
    }

    // Ciò che deve restare invariato: "/Users" è una voce RICORSIVA mirata (protegge le home
    // degli altri utenti, non la propria), quindi continua a negare una root che vi punti.
    @Test func validateRootStillDeniesUsersDirectoryViaRecursiveRule() throws {
        #expect(try !create().validateRoot("/Users").isAllowed)
    }

    // Ciò che deve restare invariato, il più importante: un percorso individualmente protetto
    // sotto la home resta negato ELEMENTO PER ELEMENTO da Validate, anche quando ValidateRoot
    // ammette la home come root della scansione.
    @Test func validateStillDeniesProtectedPathUnderHomeEvenThoughValidateRootAllowsHome() throws {
        #expect(try create().validateRoot(Self.home).isAllowed)
        #expect(try !create().validate("\(Self.home)/Documents/fattura.pdf", declaredRoot: Self.home).isAllowed)
    }

    // Punto 4 della revisione finale: un elemento manipolato fra la scansione e la conferma che
    // coincide con la root dichiarata cancellerebbe l'intera root invece di svuotarla (es.
    // "~/Library/Caches" rimossa invece che svuotata). Lo scanner non lo produce mai — nessuno
    // dei controlli precedenti lo intercetta per una root profonda come questa: il contenimento
    // ammette l'uguaglianza, la deny-list la esenta esplicitamente, e non è né la home né un suo
    // figlio diretto.
    @Test func deniesItemThatCoincidesWithADeepDeclaredRoot() throws {
        let verdict = try create().validate(Self.cacheRoot, declaredRoot: Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains(Self.cacheRoot))
    }

    // Ciò che deve restare invariato: quando la root coincide anche con un figlio diretto della
    // home, il motivo restituito resta quello più specifico della regola di profondità (punto
    // 4 di Validate), non quello più generico introdotto qui.
    @Test func directChildOfHomeRootStillReportsDepthReasonNotCoincidenceReason() throws {
        let verdict = try create().validate("\(Self.home)/Downloads", declaredRoot: "\(Self.home)/Downloads")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("profondità"))
    }

    // Solo Swift: semantica Unicode delle stringhe (vedi registro di parità, differenze).
    @Test(arguments: [
        ("/Users/tester/Downloads/x\u{600}/..", "/Users/tester/Downloads"),
        ("/Users/tester/x\u{600}/../Documents/f", "/Users/tester/x\u{600}/.."),
        ("/Users/tester/Library/Caches/../\u{301}x", "/Users/tester/Library/Caches"),
    ])
    func deniesDotSegmentsHiddenByScalarsThatMergeWithTheSlash(path: String, root: String) throws {
        #expect(try !create().validate(path, declaredRoot: root).isAllowed)
    }

    @Test(arguments: ["/Users/tester/x\u{600}/..", "/x\u{600}/.."])
    func validateRootDeniesDotSegmentsHiddenByScalarsThatMergeWithTheSlash(root: String) throws {
        #expect(try !create().validateRoot(root).isAllowed)
    }

    @Test func caseFoldingThatWouldChangeLengthNeverSatisfiesContainment() throws {
        let home = "/Users/alessandro.rossi"
        let guardrail = try PathGuard(
            denyList: DenyList(homeDirectory: home),
            fileSystem: InMemoryFileSystem(),
            links: FakeLinkInspector("/Users/aleßandro.roßi/Library/Caches/l"),
            homeDirectory: home)

        let verdict = guardrail.validate("/Users/aleßandro.roßi/Library/Caches/l/tesi.docx", declaredRoot: "\(home)/Library/Caches")

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("contenimento"))
    }

    @Test func resolvingALinkedAncestorKeepsTheSeparatorAfterAPrependScalar() throws {
        let verdict = try create(targets: ["/Users/tester/a\u{600}": "/Users/tester/Library"])
            .validateRoot("/Users/tester/a\u{600}/Preferences")
        #expect(!verdict.isAllowed)
        #expect(verdict.canonicalPathValidated == "/Users/tester/Library/Preferences")
    }

    @Test func dotlessIDoesNotSatisfyContainment() throws {
        let verdict = try create("/Users/tester/Lıbrary/Caches")
            .validate("/Users/tester/Lıbrary/Caches/tesi.docx", declaredRoot: "/Users/tester/Library/Caches")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("contenimento"))
    }

    @Test func dotlessIDoesNotBypassTheOtherUsersRule() throws {
        let home = "/Users/marco.milani"
        let guardrail = try PathGuard(
            denyList: DenyList(homeDirectory: home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(), homeDirectory: home)
        #expect(!guardrail.validate("/Users/marco.mılanı/Library/Caches/x", declaredRoot: "\(home)/Library/Caches").isAllowed)
        #expect(guardrail.pruneReason("/Users/marco.mılanı/Documents") != nil)
    }

    // MARK: - Percorso registrato dal filesystem (solo Swift, piano APFS, spec §12)

    private func create(storing fileSystem: any FileSystem, home: String = Self.home, targets: [String: String?] = [:]) throws -> PathGuard {
        try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fileSystem, links: FakeLinkInspector(targets: targets), homeDirectory: home)
    }

    // Il buco: root ed elemento scritti con un nome che APFS equipara a quello di una cartella
    // protetta superano i confronti OrdinalIgnoreCase, e il kernel li risolve nella cartella
    // protetta. Equivalenze misurate nello spike del 2026-10-16.
    @Test(arguments: [
        ("Des\u{212A}top", "Desktop"),
        ("De\u{017F}ktop", "Desktop"),
        ("Library/Me\u{00DF}ages", "Library/Messages"),
        (".\u{017F}sh", ".ssh"),
    ])
    func deniesAnItemWhoseStoredPathIsProtected(alias: String, stored: String) throws {
        let root = "\(Self.home)/\(alias)"
        let protected = "\(Self.home)/\(stored)"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(root, protected)]))

        let rootVerdict = guardrail.validateRoot(root)
        let verdict = guardrail.validate("\(root)/x", declaredRoot: root)

        #expect(!rootVerdict.isAllowed)
        #expect(rootVerdict.reason.contains(protected))
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains(protected))
        #expect(verdict.canonicalPathValidated == "\(root)/x")
    }

    // La profondità minima si ripete sulla grafia del disco: "/U\u{017F}ers" sfugge sia alla regola
    // "/Users" sia alla home testuale.
    @Test func deniesADirectChildOfTheHomeReachedThroughAnAlias() throws {
        let alias = "/U\u{017F}ers/tester"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(alias, Self.home)]))

        let verdict = guardrail.validate("\(alias)/Downloads", declaredRoot: alias)

        #expect(guardrail.validateRoot(alias).isAllowed)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("profondità"))
        #expect(guardrail.validate("\(alias)/Downloads/vecchio.dmg", declaredRoot: alias).isAllowed)
    }

    // Anche le voci a uguaglianza esatta valgono sulla grafia del disco.
    @Test func deniesAnItemWhoseStoredPathIsTheHome() throws {
        let guardrail = try create(storing: AliasingFileSystem(aliases: [("/U\u{017F}ers/tester", Self.home)]))

        let verdict = guardrail.validate("/U\u{017F}ers/tester", declaredRoot: "/U\u{017F}ers")

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("percorso protetto: \(Self.home)"))
    }

    // La destinazione di un collegamento si legge come testo (readlink): una cache spostata su
    // "~/Des\u{212A}top" con un collegamento passava la deny-list testuale.
    @Test func validateRootDeniesALinkTargetSpelledWithAnAlias() throws {
        let alias = "\(Self.home)/Des\u{212A}top"
        let guardrail = try create(
            storing: AliasingFileSystem(aliases: [(alias, "\(Self.home)/Desktop")]), targets: [Self.cacheRoot: alias])

        let verdict = guardrail.validateRoot(Self.cacheRoot)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("\(Self.home)/Desktop"))
        #expect(verdict.canonicalPathValidated == alias)
    }

    @Test func validateRootDeniesARootStoredAsTheFilesystemRoot() throws {
        let root = "\(Self.home)/radice"
        let verdict = try create(storing: AliasingFileSystem(aliases: [(root, "/")])).validateRoot(root)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("degenere"))
    }

    @Test func pruneReasonPrunesABranchWhoseStoredPathIsProtected() throws {
        let alias = "\(Self.home)/progetti/Des\u{212A}top"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(alias, "\(Self.home)/Desktop")]))

        let reason = try #require(guardrail.pruneReason(alias))

        #expect(reason.contains("\(Self.home)/Desktop"))
        #expect(guardrail.pruneReason("\(Self.home)/progetti/app") == nil)
    }

    // Fail-closed: un errore che non dice «non esiste» né «non si attraversa» lascia il percorso
    // non verificabile, e la cancellazione non si tenta.
    @Test(arguments: [EIO, ELOOP, ENAMETOOLONG])
    func anUnverifiableStoredPathIsDenied(code: Int32) throws {
        let item = "\(Self.cacheRoot)/x"
        let branch = "\(Self.cacheRoot)/sub"
        let root = "\(Self.home)/Library/Logs"
        let guardrail = try create(storing: AliasingFileSystem(failures: [(item, code), (branch, code), (root, code)]))

        let verdict = guardrail.validate(item, declaredRoot: Self.cacheRoot)
        let rootVerdict = guardrail.validateRoot(root)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("non verificabile"))
        #expect(!rootVerdict.isAllowed)
        #expect(rootVerdict.reason.contains("non verificabile"))
        #expect(try #require(guardrail.pruneReason(branch)).contains("non verificabile"))

        let unexpected = try create(storing: NonFileSystemErrorStoredPathFileSystem(paths: [item, branch, root]))
        let unexpectedItem = unexpected.validate(item, declaredRoot: Self.cacheRoot)
        let unexpectedRoot = unexpected.validateRoot(root)

        #expect(!unexpectedItem.isAllowed)
        #expect(unexpectedItem.reason.contains("non verificabile"))
        #expect(!unexpectedRoot.isAllowed)
        #expect(unexpectedRoot.reason.contains("non verificabile"))
        #expect(try #require(unexpected.pruneReason(branch)).contains("non verificabile"))
    }

    // Un elemento sparito o dietro una cartella che non si attraversa resta verificabile: si
    // risale all'antenato, e la cancellazione che segue riporta il proprio errore come prima.
    @Test(arguments: [ENOENT, ENOTDIR, EACCES, EPERM])
    func missingOrHiddenComponentsClimbToTheirAncestor(code: Int32) throws {
        let item = "\(Self.cacheRoot)/x"
        let guardrail = try create(storing: AliasingFileSystem(failures: [(item, code), (Self.cacheRoot, code)]))

        #expect(guardrail.validateRoot(Self.cacheRoot).isAllowed)
        #expect(guardrail.validate(item, declaredRoot: Self.cacheRoot).isAllowed)
        #expect(guardrail.pruneReason(item) == nil)
    }

    // I componenti che mancano si giudicano dopo l'antenato nella sua grafia del disco, nel loro
    // ordine: qui mancano sia "Xcode" sia "UserData".
    @Test func missingComponentsAreJudgedAfterTheStoredSpellingOfTheirAncestor() throws {
        let alias = "/U\u{017F}ers/tester/Library/Developer"
        let root = "\(alias)/Xcode"
        let item = "\(root)/UserData"
        let guardrail = try create(storing: AliasingFileSystem(
            aliases: [(alias, "\(Self.home)/Library/Developer")], failures: [(item, ENOENT), (root, ENOENT)]))

        let verdict = guardrail.validate(item, declaredRoot: root)

        #expect(guardrail.validateRoot(root).isAllowed)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("\(Self.home)/Library/Developer/Xcode/UserData"))
    }

    // La deny-list registrata si costruisce sulla home come la scrive il disco: con una home
    // sotto un collegamento (/var → /private/var) i percorsi già risolti da validateRoot non
    // somigliano più alla home testuale.
    @Test func theStoredHomeProtectsAHomeUnderALink() throws {
        let home = "/var/h/tester"
        let stored = "/private/var/h/tester"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(home, stored)]), home: home)

        let rootVerdict = guardrail.validateRoot("\(stored)/Documents")
        let item = guardrail.validate("\(stored)/Documents/x", declaredRoot: stored)
        let child = guardrail.validate("\(stored)/Downloads", declaredRoot: stored)

        #expect(!rootVerdict.isAllowed)
        #expect(rootVerdict.reason.contains("\(stored)/Documents"))
        #expect(!item.isAllowed)
        #expect(item.reason.contains("\(stored)/Documents"))
        #expect(!child.isAllowed)
        #expect(child.reason.contains("profondità"))
        #expect(guardrail.validate("\(stored)/Library/Caches/x", declaredRoot: "\(stored)/Library/Caches").isAllowed)
        #expect(guardrail.pruneReason("\(stored)/Documents") != nil)
        #expect(guardrail.pruneReason("\(stored)/Library/Caches") == nil)
    }

    @Test func constructorRejectsAHomeThatTheFilesystemCannotVerify() {
        #expect(throws: InvalidConfiguration.self) {
            try create(storing: AliasingFileSystem(failures: [(Self.home, EIO)]))
        }
        #expect(throws: InvalidConfiguration.self) {
            try create(storing: NonFileSystemErrorStoredPathFileSystem(paths: [Self.home]))
        }
    }

    @Test(arguments: ["/", "/Users", "Users/tester", "", "/Users/tester/../altro"])
    func constructorRejectsADegenerateStoredHome(stored: String) {
        #expect(throws: InvalidConfiguration.self) {
            try create(storing: AliasingFileSystem(aliases: [(Self.home, stored)]))
        }
    }

    // I controlli sulla grafia del disco vengono dopo quelli testuali: un rifiuto che il C#
    // emetteva conserva il proprio motivo.
    @Test func textualRefusalsKeepTheirReason() throws {
        let link = "\(Self.cacheRoot)/collegamento"
        let guardrail = try PathGuard(
            denyList: DenyList(homeDirectory: Self.home),
            fileSystem: AliasingFileSystem(aliases: [(link, "\(Self.home)/Documents")]),
            links: FakeLinkInspector(link),
            homeDirectory: Self.home)

        let verdict = guardrail.validate("\(link)/x", declaredRoot: Self.cacheRoot)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("antenato è un collegamento simbolico"))
    }
}
