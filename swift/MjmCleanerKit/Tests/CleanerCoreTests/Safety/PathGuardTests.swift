import Testing
@testable import CleanerCore

struct PathGuardTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"

    private func create(_ symlinks: String...) throws -> PathGuard {
        try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(symlinks), homeDirectory: Self.home)
    }

    private func create(targets: [String: String?]) throws -> PathGuard {
        try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(targets: targets), homeDirectory: Self.home)
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
            try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(), homeDirectory: homeDirectory)
        }
    }

    @Test func constructorRejectsHomeThatDiffersFromDenyListHome() {
        #expect(throws: InvalidConfiguration.self) {
            try PathGuard(denyList: DenyList(homeDirectory: "/Users/altro"), links: FakeLinkInspector(), homeDirectory: Self.home)
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
}
