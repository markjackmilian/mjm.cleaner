# Download e File grandi separati, cartelle escluse, «Seleziona tutte» — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Download e File grandi diventano due categorie con le voci deselezionate al passo 3. Le cartelle escluse nelle Impostazioni non vengono mai analizzate né proposte. I pacchetti macOS (`.pvm`, `.app`…) si propongono interi, mai i loro file. Ogni gruppo del passo 3 ha «Seleziona tutte le voci».

**Architecture:** `CleanupRule` porta `excludedPaths`, che `CategoryCatalog` riempie su ogni regola con le cartelle escluse. `RuleScanner` le interpreta con il nuovo `ExcludedFolders`: pota i rami esclusi e scarta i candidati che stanno dentro un'esclusione o ne contengono una. In `matchingFiles` una cartella che `FileSystem.isPackage` riconosce come pacchetto non si attraversa: diventa un candidato unico. `CleanupCategory.itemsSelectedByDefault` decide lo stato iniziale delle voci al passo 3, dove `CategoryNode.allSelected` alimenta la casella di gruppo.

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-19-large-files-exclusions-design.md`

Stato di partenza: `main` con questo piano (nessun push). Il codice è quello di `cce0305`; `e02816e` aggiunge solo la spec. `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **648** test in 58 suite (`CleanerCoreTests`) e **219** in 23 (`CleanerFeaturesTests`). Prima del Task 1 il controller crea il worktree `.claude/worktrees/large-files-exclusions` sul branch `feat/large-files-exclusions`, partendo da `main`.

Decisioni dell'utente (2026-10-19, nella spec):

- **Due categorie**, `downloads` e `large-files`, al posto di `downloads-large`.
- **Al passo 3 le voci di Download e File grandi partono deselezionate.** Le altre, Cestino compreso, restano preselezionate.
- **Le cartelle escluse valgono per tutto il wizard.** Le pagine Xcode e Docker restano fuori.
- **Un pacchetto macOS è un'unità.**
- **Esclusioni nelle regole, interpretate da `RuleScanner`** (approccio A). Il `PathGuard` resta la sola deny-list di sistema.

Decisioni prese durante la stesura, verificate eseguendo l'intero piano in una copia scratch di `e02816e`:

- **`isPackage` è un requisito del protocollo `FileSystem`, senza implementazione predefinita.** Un'implementazione predefinita a `false` farebbe tacere un doppio che si dimentica di inoltrarla. I conformi sono tre: `LocalFileSystem`, `InMemoryFileSystem` e `ForwardingFileSystem` (nei test).
- **Il ripiego per estensione (`pvm`, `vmwarevm`, `utm`) è necessario.** Sul Mac dell'utente, il 2026-10-19, `URLResourceValues.isPackage` dava vero per `.app`, `.pvm`, `.logarchive` e `.photoslibrary` (Parallels Desktop è installato), ma falso per `.vmwarevm` e `.utm`. Costo misurato: circa 20 µs per cartella su 10.000 cartelle, trascurabile rispetto alle letture che la scansione fa già.
- **`excludedPaths` ha valore predefinito `[]`, e `itemsSelectedByDefault` ha `true`.** I costruttori esistenti nei test e in `ScanEngineTests` non cambiano. Il catalogo passa `false` esplicitamente, e un test del catalogo fissa quali categorie hanno le voci deselezionate.
- **`CleanupRule.excluding(_:)` e `CleanupCategory.excluding(_:)`.** Il catalogo costruisce le categorie come oggi e poi applica `.map { $0.excluding(excluded) }`, invece di passare le esclusioni a ognuna delle tredici regole. Un test verifica che `excluding` conservi ogni altro campo.
- **«/» esclude tutto.** `ExcludedFolders` toglie i «/» finali, quindi «/» diventa la stringa vuota, e `PathText.isSameOrUnder(path, "")` è vero per ogni percorso assoluto: è la direzione sicura, e c'è un test.
- **Ordine dei controlli.** In `matchingFiles` l'esclusione dell'utente segue `.git` e la deny-list, poi viene il pacchetto. In `matchingDirs` l'esclusione segue subito `.git`, prima dei glob di esclusione e prima del controllo `bin`/`obj`: una cartella esclusa non si propone anche se si chiama `bin`. In `clearContents` e per i pacchetti, l'esclusione segue il verdetto del guard e precede le statistiche.
- **Nessun controllo di esclusione sui singoli file di `matchingFiles`.** Un file non può coincidere con una cartella né contenerne una, e la potatura dei rami copre già i file al loro interno. Il controllo sarebbe codice morto.
- **Precedenza della deny-list sui pacchetti.** La spec chiede un test: nessuna cartella della deny-list è un pacchetto, e un pacchetto sotto un ramo protetto non si raggiunge mai. Il test `aPackageInsideAProtectedBranchIsNeverReached` lo fissa. La precedenza di `.git` ha un test suo (la mutazione «pacchetto prima di `.git`» lo fa fallire).
- **L'helper dei test dei pacchetti si chiama `makePackage`.** `package(` a inizio istruzione è il modificatore d'accesso di Swift e non compila.
- **`ChooseStepTests.rememberedSelectionIsRestoredAndAnalyzeSavesItBeforeScanning` passa a otto separatori**, perché le categorie diventano otto.
- **`xcodebuild` non tocca i `Localizable.xcstrings`.** Verificato nella copia scratch: dopo la build dell'app restano invariati. Le modifiche non committate a quei file su `main` non vengono da questo lavoro.

Frasi nuove, in italiano con `String(localized:)` come le esistenti, da aggiungere alla tabella del piano di localizzazione:

- Core: «cartella esclusa nelle Impostazioni», «contiene una cartella esclusa nelle Impostazioni», «Download», «File in Download non usati da tempo. Contiene dati reali: nella verifica ogni voce parte deselezionata.», «File grandi», «File e pacchetti oltre la soglia, nelle cartelle scelte nelle Impostazioni. Contiene dati reali: nella verifica ogni voce parte deselezionata.». Sparisce dal Core «Download e file grandi» con la sua descrizione «Contiene dati reali, non file rigenerabili. Ogni voce va selezionata manualmente.».
- Features: «Download e file grandi» (nome storico in `CategoryNames`), «Scegli una cartella da escludere», «Seleziona tutte le voci di \(nome)».
- App: «Cartelle escluse», «Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.», «Dati reali: le voci partono deselezionate. Spunta solo ciò che vuoi eliminare.», «Seleziona tutte le voci».

## Global Constraints

- Il codice vive in `MjmCleanerKit/` (package) e `MjmCleaner/` (app). Cambiano solo:
  - nel Core, `Platform/FileSystem.swift`, `Platform/LocalFileSystem.swift`, `Scanning/RuleScanner.swift`, `Categories/CleanupRule.swift`, `Categories/CleanupCategory.swift`, `Categories/CategoryCatalog.swift`, `Settings/CleanerSettings.swift`, più il nuovo `Scanning/ExcludedFolders.swift`;
  - in `CleanerFeatures`, `Cleanup/CategoryVisuals.swift`, `Cleanup/ConfirmStepModel.swift`, `History/CategoryNames.swift` e `Settings/SettingsModel.swift`;
  - nell'app, `Settings/SettingsView.swift`, `Cleanup/ConfirmStepView.swift`, `Demo/DemoData.swift`, `Demo/DemoServices.swift`, la cartella `Assets.xcassets/TileDownloadsLarge.colorset` (rinominata `TileDownloads.colorset`) e il nuovo `Assets.xcassets/TileLargeFiles.colorset/Contents.json`;
  - `README.md`;
  - i test elencati nei task.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati nel codice di produzione.
- Il `PathGuard` e la `DenyList` non cambiano: le esclusioni dell'utente sono una preferenza, non una protezione di sistema.
- Testi nuovi: solo quelli elencati sopra, scritti esattamente come nel piano. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica, dalla radice del worktree:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E '✘|Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-large-files-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/large-files-exclusions`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera (per la cartella dell'asset rinominata si usa `git mv`, che la mette in stage da sé). Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` (`MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`).
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick) e mai avviare l'app: le verifiche sono test e build. Gli screenshot con `-MJMDemo` li cattura il controller, solo dopo averlo chiesto all'utente.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: sonnet; **opus per i Task 2, 3 e 6** (lo scanner decide cosa si propone di cancellare, il passo 3 cosa si cancella davvero) e per la revisione finale. I Task 1, 2, 3, 4 e 6 si rivedono con mutazioni in una copia scratch.
- Mutazioni provate in stesura, tutte uccise dai test del piano, da ripetere nelle revisioni: vedi la tabella in fondo.
- A fine piano il controller copia il registro in `docs/superpowers/decisions/2026-10-19-registro-decisioni-large-files-exclusions.md`, aggiunge le frasi nuove alla nota sulla localizzazione e poi usa `superpowers:finishing-a-development-branch`.

---

## Fatti misurati (2026-10-19, macOS 27.0, Xcode 27)

- `URL.resourceValues(forKeys: [.isPackageKey]).isPackage` su cartelle vuote appena create: `X.app` vero, `VM.pvm` e `VM2.PVM` veri (Parallels Desktop installato), `L.logarchive` vero, `P.photoslibrary` vero, `W.vmwarevm` falso, `U.utm` falso, `plain` falso.
- 10.000 chiamate su cartelle reali: 0,21 s, circa 20 µs l'una.
- Su `main` (`cce0305` più la spec): 648 test in 58 suite nel Core, 219 in 23 in Features.
- Nella copia scratch, la build Debug dell'app con le modifiche del Task 7 riesce e lascia invariati i tre `Localizable.xcstrings`.

---

### Task 1: `FileSystem.isPackage`

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift`
- Modify: `MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`
- Modify: `MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Platform/LocalFileSystemTests.swift`, `MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystemTests.swift`

**Interfaces:**
- Consumes: `FileSystem`, `PathText.equalsIgnoringCase`, `TemporaryDirectory` (test).
- Produces:
  - `func FileSystem.isPackage(_ path: String) -> Bool` (requisito del protocollo);
  - `static let LocalFileSystem.virtualMachinePackageExtensions: [String]` (interna);
  - nei test, `func InMemoryFileSystem.addPackage(_ path: String)` e `InMemoryFileSystem.isPackage(_:)`; `ForwardingFileSystem.isPackage(_:)` inoltra.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerCoreTests/Platform/LocalFileSystemTests.swift`, sostituire:

```swift
    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func defaultApfsVolumeIsCaseInsensitive() throws {
```

con:

```swift
    /// `.app` è un pacchetto per ogni Mac; `.utm` e `.VMwareVM` lo sono grazie al ripiego per
    /// estensione anche dove UTM e VMware Fusion non sono installati. Una cartella qualunque, un file
    /// con estensione da pacchetto, un collegamento a un pacchetto e un percorso assente no.
    @Test func isPackageRecognisesBundlesAndVirtualMachines() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let app = try tmp.directory("Strumento.app")
        let utm = try tmp.directory("Linux.utm")
        let vmware = try tmp.directory("Windows.VMwareVM")
        let plain = try tmp.directory("cartella")
        let file = try tmp.file("finto.pvm", contents: "x")
        let link = try tmp.symlink("collegamento.app", to: app)

        #expect(fs.isPackage(app))
        #expect(fs.isPackage(utm))
        #expect(fs.isPackage(vmware))
        #expect(!fs.isPackage(plain))
        #expect(!fs.isPackage(file))
        #expect(!fs.isPackage(link))
        #expect(!fs.isPackage(tmp.path + "/assente.app"))
    }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func defaultApfsVolumeIsCaseInsensitive() throws {
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystemTests.swift`, aggiungere come ultimo test della struct `InMemoryFileSystemTests`, prima della `}` che la chiude:

```swift
    @Test func onlyDeclaredPackagesArePackages() throws {
        let fs = InMemoryFileSystem()
        fs.addPackage("/Users/tester/Parallels/Windows 11.pvm")
        fs.addFile("/Users/tester/Parallels/Windows 11.pvm/disco.hds", size: 10)
        fs.addDirectory("/Users/tester/Parallels/archivio")

        #expect(fs.isPackage("/Users/tester/Parallels/Windows 11.pvm"))
        #expect(fs.directoryExists("/Users/tester/Parallels/Windows 11.pvm"))
        #expect(!fs.isPackage("/Users/tester/Parallels/archivio"))
        #expect(!fs.isPackage("/Users/tester/Parallels/Windows 11.pvm/disco.hds"))

        try fs.deleteDirectoryRecursively("/Users/tester/Parallels/Windows 11.pvm")
        #expect(!fs.isPackage("/Users/tester/Parallels/Windows 11.pvm"))
    }
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione `value of type 'InMemoryFileSystem' has no member 'addPackage'` e `value of type 'InMemoryFileSystem' has no member 'isPackage'` (misurati in stesura; l'errore su `LocalFileSystem` può non comparire, perché il compilatore si ferma prima).

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift`, sostituire:

```swift
    func storedPath(_ path: String) throws -> String
}
```

con:

```swift
    func storedPath(_ path: String) throws -> String
    /// Vero se `path` è una cartella che macOS tratta come un documento unico, cioè un pacchetto
    /// (`.app`, `.pvm`, `.photoslibrary`, `.logarchive`…), senza equivalente .NET. Un file, un
    /// collegamento simbolico o un percorso inesistente valgono falso.
    func isPackage(_ path: String) -> Bool
}
```

In `MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift`, sostituire:

```swift
    static func parseStoredPathResponse(_ buffer: [UInt8], path: String) throws -> String {
```

con:

```swift
    /// Le estensioni dei pacchetti di macchine virtuali: macOS li riconosce come pacchetti solo se
    /// il loro programma è installato (sul Mac dell'utente, il 2026-10-19, `.pvm` sì perché c'è
    /// Parallels Desktop, `.vmwarevm` e `.utm` no). Senza il programma una macchina copiata o
    /// archiviata sembrerebbe una cartella qualunque, e lo scanner ne proporrebbe i dischi interni.
    static let virtualMachinePackageExtensions = ["pvm", "vmwarevm", "utm"]

    /// `lstat` prima di tutto: un collegamento non è mai un pacchetto, anche se punta a uno. Poi le
    /// estensioni delle macchine virtuali, poi `URLResourceValues.isPackage` (circa 20 µs per
    /// cartella, misurati il 2026-10-19 su 10.000 cartelle).
    public func isPackage(_ path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFDIR else { return false }
        let url = URL(filePath: path, directoryHint: .isDirectory)
        if Self.virtualMachinePackageExtensions.contains(where: { PathText.equalsIgnoringCase($0, url.pathExtension) }) {
            return true
        }
        return (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) ?? false
    }

    static func parseStoredPathResponse(_ buffer: [UInt8], path: String) throws -> String {
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`, sostituire:

```swift
    func storedPath(_ path: String) throws -> String { try inner.storedPath(path) }
```

con:

```swift
    func storedPath(_ path: String) throws -> String { try inner.storedPath(path) }
    func isPackage(_ path: String) -> Bool { inner.isPackage(path) }
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:

```swift
    private let nodes = Mutex<[String: Node]>(["/": .directory(Date())])
```

con:

```swift
    private let nodes = Mutex<[String: Node]>(["/": .directory(Date())])
    private let packages = Mutex<Set<String>>([])
```

poi sostituire:

```swift
    func setTimes(_ path: String, lastWrite: Date, lastAccess: Date) {
```

con:

```swift
    /// Dichiara `path` un pacchetto macOS, creandolo come cartella se manca: il riconoscimento
    /// reale dipende dai tipi registrati nel sistema, qui basta la dichiarazione del test.
    func addPackage(_ path: String) {
        addDirectory(path)
        packages.withLock { _ = $0.insert(Self.key(path)) }
    }

    func setTimes(_ path: String, lastWrite: Date, lastAccess: Date) {
```

poi sostituire:

```swift
    // MARK: - Privati
```

con:

```swift
    /// Vero solo per le cartelle dichiarate con `addPackage` e ancora presenti.
    func isPackage(_ path: String) -> Bool {
        let key = Self.key(path)
        return packages.withLock { $0.contains(key) } && directoryExists(path)
    }

    // MARK: - Privati
```

- [ ] **Step 4: Verificare che passino**

Run: comando «una suite» con `--filter 'LocalFileSystemTests|InMemoryFileSystemTests'`.
Expected: `✔ Test run with 27 tests in 2 suites passed`.

Run: comando «package».
Expected: `CleanerCoreTests` **650** test in 58 suite, `CleanerFeaturesTests` **219** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift MjmCleanerKit/Tests/CleanerCoreTests/Platform/LocalFileSystemTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystemTests.swift
git commit -m "$(cat <<'EOF'
feat(core): tell macOS packages apart from ordinary folders

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Cartelle escluse nello scanner

**Files:**
- Create: `MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ExcludedFoldersScanTests.swift` (nuovo)

**Interfaces:**
- Consumes: `PathText.isSameOrUnder`, `PathText.hasPrefixIgnoringCase`, `PathText.equalsIgnoringCase`, `PathText.trimmingTrailingSlashes`, `GuardVerdict.canonicalPathValidated` di `validateRoot`; nei test `AccessLogFileSystem`, `FakeLinkInspector(targets:)`, `FixedWallClock`, `utc`.
- Produces:
  - `CleanupRule.excludedPaths: [String]` e il parametro `excludedPaths: [String] = []`, ultimo di `CleanupRule.init`;
  - `struct ExcludedFolders` (interna) con `init(_ folders: [String], root: String, resolvedRoot: String)`, `func excludedReason(_ path: String) -> String?`, `func candidateReason(_ path: String) -> String?`, `static var excludedReason: String` («cartella esclusa nelle Impostazioni»), `static var containsReason: String` («contiene una cartella esclusa nelle Impostazioni»);
  - `RuleScanner`: le funzioni private `scanContents`, `scanFiles` e `scanDirectories` ricevono `_ excluded: ExcludedFolders` dopo `rule`.

- [ ] **Step 1: Test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ExcludedFoldersScanTests.swift`:

```swift
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
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `extra argument 'excludedPaths' in call`.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift`, sostituire:

```swift
    public let requiresProjectMarker: Bool

    public init(
```

con:

```swift
    public let requiresProjectMarker: Bool
    /// Le cartelle escluse nelle Impostazioni, già espanse: mai attraversate né proposte, e nemmeno
    /// una cartella che ne contiene una (spec `2026-10-19-large-files-exclusions-design.md`).
    public let excludedPaths: [String]

    public init(
```

poi sostituire:

```swift
        requiresProjectMarker: Bool = false
    ) {
```

con:

```swift
        requiresProjectMarker: Bool = false,
        excludedPaths: [String] = []
    ) {
```

poi sostituire:

```swift
        self.requiresProjectMarker = requiresProjectMarker
    }
```

con:

```swift
        self.requiresProjectMarker = requiresProjectMarker
        self.excludedPaths = excludedPaths
    }
```

Creare `MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift`:

```swift
/// Le cartelle escluse nelle Impostazioni, viste da una regola. Un percorso si confronta in due
/// forme: quella testuale, sotto la root dichiarata, e quella con la root risolta da
/// `validateRoot`. Così un'esclusione scritta "/private/var/…" vale anche per la root `$TMPDIR`,
/// che sta sotto il collegamento "/var". Il confronto ignora le maiuscole, come la deny-list.
///
/// «/» si riduce alla stringa vuota, e `isSameOrUnder(path, "")` è vero per ogni percorso
/// assoluto: escludere la radice esclude tutto, che è la direzione sicura.
struct ExcludedFolders: Sendable {
    private let folders: [String]
    private let root: String
    private let resolvedRoot: String

    init(_ folders: [String], root: String, resolvedRoot: String) {
        self.folders = folders.map(PathText.trimmingTrailingSlashes)
        self.root = PathText.trimmingTrailingSlashes(root)
        self.resolvedRoot = PathText.trimmingTrailingSlashes(resolvedRoot)
    }

    static var excludedReason: String {
        String(localized: "cartella esclusa nelle Impostazioni", bundle: .module)
    }

    static var containsReason: String {
        String(localized: "contiene una cartella esclusa nelle Impostazioni", bundle: .module)
    }

    /// Il motivo per non entrare in una cartella e non proporla: coincide con una cartella esclusa
    /// o sta sotto una di esse. `nil` se nessuna esclusione la riguarda.
    func excludedReason(_ path: String) -> String? {
        let excluded = forms(path).contains { form in
            folders.contains { PathText.isSameOrUnder(form, $0) }
        }
        return excluded ? Self.excludedReason : nil
    }

    /// Il motivo per non proporre un candidato: oltre ai casi di `excludedReason`, una cartella
    /// esclusa sta sotto di lui, ed eliminarlo cancellerebbe anche quella.
    func candidateReason(_ path: String) -> String? {
        if let reason = excludedReason(path) { return reason }
        let containsExcluded = forms(path).contains { form in
            folders.contains { PathText.hasPrefixIgnoringCase($0, form + "/") }
        }
        return containsExcluded ? Self.containsReason : nil
    }

    /// Il percorso com'è e, se sta sotto la root testuale e la root risolta è diversa, lo stesso
    /// percorso sotto la root risolta. Un prefisso riconosciuto senza maiuscole occupa lo stesso
    /// numero di scalari della root (`PathText.hasPrefixIgnoringCase`).
    private func forms(_ path: String) -> [String] {
        guard !resolvedRoot.isEmpty, !PathText.equalsIgnoringCase(root, resolvedRoot), PathText.isSameOrUnder(path, root) else {
            return [path]
        }
        var resolved = String.UnicodeScalarView()
        resolved.append(contentsOf: resolvedRoot.unicodeScalars)
        resolved.append(contentsOf: path.unicodeScalars.dropFirst(root.unicodeScalars.count))
        return [path, String(resolved)]
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`, sostituire:

```swift
        switch rule.mode {
        case .clearContents:
            try scanContents(rule, &accumulator)
        case .matchingFiles:
            try scanFiles(rule, &accumulator)
        case .matchingDirs:
            try scanDirectories(rule, &accumulator)
        }
```

con:

```swift
        // Le cartelle escluse nelle Impostazioni si confrontano anche con la root risolta. Se la
        // root stessa è esclusa, o sta sotto un'esclusione, la regola non produce nulla.
        let excluded = ExcludedFolders(rule.excludedPaths, root: rule.root, resolvedRoot: rootVerdict.canonicalPathValidated)
        if let reason = excluded.excludedReason(rule.root) {
            accumulator.exclusions.append(GuardExclusion(path: rule.root, reason: reason))
            return accumulator.outcome
        }

        switch rule.mode {
        case .clearContents:
            try scanContents(rule, excluded, &accumulator)
        case .matchingFiles:
            try scanFiles(rule, excluded, &accumulator)
        case .matchingDirs:
            try scanDirectories(rule, excluded, &accumulator)
        }
```

poi sostituire:

```swift
    private func scanContents(_ rule: CleanupRule, _ accumulator: inout Accumulator) throws {
```

con:

```swift
    private func scanContents(_ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
```

poi sostituire (in `scanContents`):

```swift
            let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
            guard verdict.isAllowed else {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                continue
            }

            let isLink = links.isSymbolicLink(entry)
```

con:

```swift
            let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
            guard verdict.isAllowed else {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                continue
            }

            // Anche le esclusioni dell'utente precedono le statistiche: un figlio escluso, o che
            // contiene una cartella esclusa, non si attraversa nemmeno per misurarlo.
            if let reason = excluded.candidateReason(entry) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                continue
            }

            let isLink = links.isSymbolicLink(entry)
```

poi sostituire:

```swift
    private func scanFiles(_ rule: CleanupRule, _ accumulator: inout Accumulator) throws {
```

con:

```swift
    private func scanFiles(_ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
```

poi sostituire (in `scanFiles`):

```swift
                if let pruneReason = pathGuard.pruneReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: pruneReason))
                    continue
                }

                enter(entry, depth: depth + 1, rule, &open, &accumulator.errors)
                continue
            }
```

con:

```swift
                if let pruneReason = pathGuard.pruneReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: pruneReason))
                    continue
                }

                // Le cartelle escluse nelle Impostazioni si potano come quelle della deny-list.
                if let reason = excluded.excludedReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                    continue
                }

                enter(entry, depth: depth + 1, rule, &open, &accumulator.errors)
                continue
            }
```

poi sostituire:

```swift
    private func scanDirectories(_ rule: CleanupRule, _ accumulator: inout Accumulator) throws {
```

con:

```swift
    private func scanDirectories(_ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
```

poi sostituire (in `scanDirectories`):

```swift
            // Un'esclusione è un rifiuto esplicito, non un "continua a cercare più in basso":
```

con:

```swift
            // Una cartella esclusa nelle Impostazioni non si propone e non si attraversa, anche se
            // si chiama "bin" o "obj".
            if let reason = excluded.excludedReason(entry) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                continue
            }

            // Un'esclusione è un rifiuto esplicito, non un "continua a cercare più in basso":
```

poi sostituire (in `scanDirectories`, nel ramo `if matches`):

```swift
                guard verdict.isAllowed else {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                    continue
                }

                let stats = try directoryStats(entry, &accumulator.errors)
                guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { continue }
                if let minSize = rule.minSizeBytes, stats.size < minSize { continue }

                accumulator.items.append(ScanItem(path: entry, sizeBytes: stats.size, isDirectory: true, declaredRoot: rule.root))
                // Trovata: non si scende oltre, l'intera cartella verrà eliminata.
```

con:

```swift
                guard verdict.isAllowed else {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                    continue
                }

                // Eliminare la cartella trovata cancellerebbe anche una cartella esclusa al suo interno.
                if let reason = excluded.candidateReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                    continue
                }

                let stats = try directoryStats(entry, &accumulator.errors)
                guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { continue }
                if let minSize = rule.minSizeBytes, stats.size < minSize { continue }

                accumulator.items.append(ScanItem(path: entry, sizeBytes: stats.size, isDirectory: true, declaredRoot: rule.root))
                // Trovata: non si scende oltre, l'intera cartella verrà eliminata.
```

- [ ] **Step 4: Verificare che passino**

Run: comando «una suite» con `--filter ExcludedFoldersScanTests`.
Expected: `✔ Test run with 12 tests in 1 suite passed`.

Run: comando «package».
Expected: `CleanerCoreTests` **662** test in 59 suite, `CleanerFeaturesTests` **219** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ExcludedFoldersScanTests.swift
git commit -m "$(cat <<'EOF'
feat(core): never scan or propose the folders excluded by the user

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Pacchetti macOS come unità in `matchingFiles`

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/PackageScanTests.swift` (nuovo)

**Interfaces:**
- Consumes: `FileSystem.isPackage` (Task 1), `ExcludedFolders.candidateReason` e `excludedReason` (Task 2), `InMemoryFileSystem.addPackage` (Task 1), `RuleScanner.directoryStats`, `acceptStamp` e `matchesGlobs` di oggi.
- Produces: `private func RuleScanner.considerPackage(_ package: String, _ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws`.

- [ ] **Step 1: Test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/PackageScanTests.swift`:

```swift
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
```

- [ ] **Step 2: Verificare che falliscano**

Run: comando «una suite» con `--filter PackageScanTests`.
Expected: `✘ Test run with 10 tests in 1 suite failed`, con 6 test falliti: `aPackageIsProposedWholeWithTheSizeOfItsTree`, `theThresholdAppliesToThePackageTotal`, `packageAgeIsTheNewestStampOfItsTree`, `globsApplyToThePackageName`, `aPackageTheGuardRejectsIsNeverMeasured` e `aPackageContainingAnExclusionIsNotProposed`. Gli altri quattro passano già: fissano protezioni che valgono anche prima dei pacchetti.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`, sostituire (in `scanFiles`):

```swift
                // Le cartelle escluse nelle Impostazioni si potano come quelle della deny-list.
                if let reason = excluded.excludedReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                    continue
                }

                enter(entry, depth: depth + 1, rule, &open, &accumulator.errors)
                continue
            }
```

con:

```swift
                // Le cartelle escluse nelle Impostazioni si potano come quelle della deny-list.
                if let reason = excluded.excludedReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: reason))
                    continue
                }

                // Un pacchetto macOS (una macchina virtuale, un'app, un .logarchive) è un documento
                // unico: cancellarne un file interno lo rompe. Non si entra mai, si valuta intero.
                if fileSystem.isPackage(entry) {
                    try considerPackage(entry, rule, excluded, &accumulator)
                    continue
                }

                enter(entry, depth: depth + 1, rule, &open, &accumulator.errors)
                continue
            }
```

poi sostituire:

```swift
    /// Cerca in profondità cartelle il cui nome corrisponde ai pattern (bin/obj, pacchetti NuGet).
```

con:

```swift
    /// Un pacchetto trovato da `scanFiles`: si propone intero, con le regole di una cartella di
    /// `scanContents`. Il guard e le esclusioni dell'utente decidono prima delle statistiche, che
    /// attraversano l'intero albero; età e soglia valgono sul timestamp più recente e sul totale.
    private func considerPackage(_ package: String, _ rule: CleanupRule, _ excluded: ExcludedFolders, _ accumulator: inout Accumulator) throws {
        guard Self.matchesGlobs(PathText.fileName(package), rule) else { return }

        let verdict = pathGuard.validate(package, declaredRoot: rule.root)
        guard verdict.isAllowed else {
            accumulator.exclusions.append(GuardExclusion(path: package, reason: verdict.reason))
            return
        }

        if let reason = excluded.candidateReason(package) {
            accumulator.exclusions.append(GuardExclusion(path: package, reason: reason))
            return
        }

        let stats = try directoryStats(package, &accumulator.errors)
        guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { return }
        if let minSize = rule.minSizeBytes, stats.size < minSize { return }

        accumulator.items.append(ScanItem(path: package, sizeBytes: stats.size, isDirectory: true, declaredRoot: rule.root))
    }

    /// Cerca in profondità cartelle il cui nome corrisponde ai pattern (bin/obj, pacchetti NuGet).
```

- [ ] **Step 4: Verificare che passino**

Run: comando «una suite» con `--filter PackageScanTests`.
Expected: `✔ Test run with 10 tests in 1 suite passed`.

Run: comando «package».
Expected: `CleanerCoreTests` **672** test in 60 suite, `CleanerFeaturesTests` **219** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift MjmCleanerKit/Tests/CleanerCoreTests/Scanning/PackageScanTests.swift
git commit -m "$(cat <<'EOF'
feat(core): propose macOS packages whole instead of the files inside them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Download e File grandi come due categorie, con le cartelle escluse su ogni regola

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupCategory.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Categories/CategoryCatalog.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/CategoryVisuals.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/History/CategoryNames.swift`
- Rename: `MjmCleaner/Assets.xcassets/TileDownloadsLarge.colorset` → `MjmCleaner/Assets.xcassets/TileDownloads.colorset`
- Create: `MjmCleaner/Assets.xcassets/TileLargeFiles.colorset/Contents.json`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`, `MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryTests.swift`

**Interfaces:**
- Consumes: `CleanupRule.excludedPaths` (Task 2), `PathExpander.expand`.
- Produces:
  - `CleanerSettings.excludedFolders: [String]`, chiave JSON `ExcludedFolders`;
  - `CleanupCategory.itemsSelectedByDefault: Bool` e il parametro `itemsSelectedByDefault: Bool = true`, ultimo di `CleanupCategory.init`;
  - `func CleanupRule.excluding(_ excludedPaths: [String]) -> CleanupRule` e `func CleanupCategory.excluding(_ excludedPaths: [String]) -> CleanupCategory`;
  - nel catalogo gli ID `downloads` e `large-files` al posto di `downloads-large`, entrambi con `itemsSelectedByDefault: false`;
  - in `CategoryVisuals` le tile `TileDownloads` (`#E8833A`, `arrow.down.to.line`) e `TileLargeFiles` (`#B5477F`, `scalemass`).

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`, sostituire:

```swift
    @Test func definesTheSevenCategories() throws {
        #expect(try build().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads-large",
        ])
    }
```

con:

```swift
    @Test func definesTheEightCategories() throws {
        #expect(try build().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads", "large-files",
        ])
    }

    /// Download e file grandi contengono dati reali: mai preselezionati, né al passo 1 né al passo 3.
    @Test func downloadsAndLargeFilesAreHighRiskAndTheirItemsStartDeselected() throws {
        let categories = try build()
        for id in ["downloads", "large-files"] {
            let category = try category(id, in: categories)
            #expect(category.risk == .high)
            #expect(!category.selectedByDefault)
        }
        #expect(categories.filter { !$0.itemsSelectedByDefault }.map(\.id) == ["downloads", "large-files"])
    }

    @Test func downloadsHaveTheAgeRuleAndLargeFilesOneThresholdRulePerRoot() throws {
        var settings = CleanerSettings()
        settings.largeFileRoots = ["~/Lavoro", "/Volumes/Dati"]
        settings.largeFileThresholdBytes = 700 * 1_048_576
        settings.downloadsMinAgeDays = 45
        let categories = try build(settings)

        #expect(try category("downloads", in: categories).rules == [
            CleanupRule("/Users/tester/Downloads", .matchingFiles, include: ["*"], exclude: [], minAge: days(45)),
        ])
        #expect(try category("large-files", in: categories).rules == [
            CleanupRule("/Users/tester/Lavoro", .matchingFiles, include: ["*"], exclude: [], minSizeBytes: 700 * 1_048_576),
            CleanupRule("/Volumes/Dati", .matchingFiles, include: ["*"], exclude: [], minSizeBytes: 700 * 1_048_576),
        ])
    }

    @Test func excludedFoldersReachEveryRuleAlreadyExpanded() throws {
        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        settings.largeFileRoots = ["~"]
        settings.excludedFolders = ["~/Parallels", "/Volumes/Archivio/"]
        let rules = try build(settings).flatMap(\.rules)

        #expect(rules.count == 13)
        #expect(rules.allSatisfy { $0.excludedPaths == ["/Users/tester/Parallels", "/Volumes/Archivio"] })
    }

    /// `excluding` cambia solo le cartelle escluse: ogni altro campo della regola e della categoria
    /// resta com'era (la soglia di età di NuGet, la profondità, il marcatore di progetto…).
    @Test func excludingKeepsEveryOtherField() {
        let rule = CleanupRule(
            "/Users/tester/.nuget/packages", .matchingDirs, include: ["a*"], exclude: ["b*"], minAge: days(3), minSizeBytes: 7,
            maxDepth: 1, requiresProjectMarker: true)
        let category = CleanupCategory(
            id: "x", displayName: "X", description: "d", risk: .high, selectedByDefault: true, parentId: "p", rules: [rule],
            itemsSelectedByDefault: false)

        #expect(rule.excluding(["/e"]) == CleanupRule(
            "/Users/tester/.nuget/packages", .matchingDirs, include: ["a*"], exclude: ["b*"], minAge: days(3), minSizeBytes: 7,
            maxDepth: 1, requiresProjectMarker: true, excludedPaths: ["/e"]))
        #expect(category.excluding(["/e"]) == CleanupCategory(
            id: "x", displayName: "X", description: "d", risk: .high, selectedByDefault: true, parentId: "p",
            rules: [rule.excluding(["/e"])], itemsSelectedByDefault: false))
    }

    @Test func withoutExcludedFoldersNoRuleExcludesAnything() throws {
        #expect(try build().flatMap(\.rules).allSatisfy { $0.excludedPaths.isEmpty })
    }
```

Nello stesso file, in `ageThresholdsComeFromSettings`, sostituire:

```swift
        let downloadsRule = try #require(try category("downloads-large", in: categories).rules.first { $0.root == "/Users/tester/Downloads" })
```

con:

```swift
        let downloadsRule = try #require(try category("downloads", in: categories).rules.first)
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift`, sostituire:

```swift
    @Test func neverCheckedLeavesNoLastCheckKey() throws {
```

con:

```swift
    @Test func excludedFoldersDefaultToEmptyAndLegacyFilesLoadWithoutThem() {
        #expect(CleanerSettings().excludedFolders.isEmpty)
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "LargeFileRoots": [ "/Volumes/Dati" ] }"#)
        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()
        #expect(settings.largeFileRoots == ["/Volumes/Dati"])
        #expect(settings.excludedFolders.isEmpty)
    }

    @Test func excludedFoldersRoundTripUnderTheirKey() throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.excludedFolders = ["/Users/tester/Parallels", "/Volumes/Archivio"]
        try store.save(settings)

        #expect(try savedJSON(fs)["ExcludedFolders"] as? [String] == ["/Users/tester/Parallels", "/Volumes/Archivio"])
        #expect(store.load().excludedFolders == ["/Users/tester/Parallels", "/Volumes/Archivio"])
    }

    @Test func neverCheckedLeavesNoLastCheckKey() throws {
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`, sostituire:

```swift
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads-large",
```

con:

```swift
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads", "large-files",
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift`, sostituire:

```swift
        ("project-build-output", "#1D8784"), ("logs", "#85858B"), ("trash", "#D2453A"), ("downloads-large", "#E8833A"),
    ])
    func tilesUseTheDesignColors(id: String, color: String) {
        #expect(CategoryVisuals.visual(for: id).designHex == color)
    }
```

con:

```swift
        ("project-build-output", "#1D8784"), ("logs", "#85858B"), ("trash", "#D2453A"), ("downloads", "#E8833A"),
        ("large-files", "#B5477F"),
    ])
    func tilesUseTheDesignColors(id: String, color: String) {
        #expect(CategoryVisuals.visual(for: id).designHex == color)
    }

    @Test func downloadsAndLargeFilesHaveTheirOwnTiles() {
        #expect(CategoryVisuals.visual(for: "downloads")
            == CategoryVisual(tileColorName: "TileDownloads", designHex: "#E8833A", symbolName: "arrow.down.to.line"))
        #expect(CategoryVisuals.visual(for: "large-files")
            == CategoryVisual(tileColorName: "TileLargeFiles", designHex: "#B5477F", symbolName: "scalemass"))
    }
```

Nello stesso file sostituire:

```swift
        #expect(model.choices.map(\.showSeparator) == [false, true, true, true, true, true, true])
```

con:

```swift
        #expect(model.choices.map(\.showSeparator) == [false, true, true, true, true, true, true, true])
```

e sostituire:

```swift
    @Test func analyzeStillScansWhenTheSelectionCannotBeSaved() throws {
```

con:

```swift
    /// La categoria unica di prima non si trasforma nelle due nuove: sono ad alto rischio, e l'utente
    /// le ri-spunta.
    @Test func aRememberedDownloadsLargeSelectsNeitherNewCategory() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs", "downloads-large"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)

        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["logs"])
    }

    @Test func analyzeStillScansWhenTheSelectionCannotBeSaved() throws {
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryTests.swift`, sostituire:

```swift
            session: try Self.session("system-caches", "docker-images", "xcode-derived-data", "trash-downloads-large", "sconosciuta"),
            names: Self.names)
        #expect(row.categoryNames == ["Cache utente e di sistema", "Immagini Docker", "DerivedData", "Cestino, Download e file grandi", "sconosciuta"])
```

con:

```swift
            session: try Self.session(
                "system-caches", "docker-images", "xcode-derived-data", "trash-downloads-large", "downloads-large", "sconosciuta"),
            names: Self.names)
        #expect(row.categoryNames == [
            "Cache utente e di sistema", "Immagini Docker", "DerivedData", "Cestino, Download e file grandi", "Download e file grandi",
            "sconosciuta",
        ])
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `value of type 'CleanerSettings' has no member 'excludedFolders'`, `value of type 'CleanupCategory' has no member 'itemsSelectedByDefault'` e `value of type 'CleanupRule' has no member 'excluding'`.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`, sostituire:

```swift
    public var largeFileThresholdBytes: Int64 = 500 * 1024 * 1024
```

con:

```swift
    public var largeFileThresholdBytes: Int64 = 500 * 1024 * 1024
    /// Cartelle mai analizzate né proposte, in nessuna categoria della pulizia guidata.
    public var excludedFolders: [String] = []
```

poi sostituire:

```swift
        case largeFileThresholdBytes = "LargeFileThresholdBytes"
```

con:

```swift
        case largeFileThresholdBytes = "LargeFileThresholdBytes"
        case excludedFolders = "ExcludedFolders"
```

poi sostituire:

```swift
        largeFileThresholdBytes = try container.decodeIfPresent(Int64.self, forKey: .largeFileThresholdBytes) ?? defaults.largeFileThresholdBytes
```

con:

```swift
        largeFileThresholdBytes = try container.decodeIfPresent(Int64.self, forKey: .largeFileThresholdBytes) ?? defaults.largeFileThresholdBytes
        excludedFolders = try container.decodeIfPresent([String].self, forKey: .excludedFolders) ?? defaults.excludedFolders
```

In `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift`, sostituire:

```swift
        self.excludedPaths = excludedPaths
    }
}
```

con:

```swift
        self.excludedPaths = excludedPaths
    }

    /// La stessa regola con le cartelle escluse nelle Impostazioni.
    public func excluding(_ excludedPaths: [String]) -> CleanupRule {
        CleanupRule(
            root, mode, include: includeGlobs, exclude: excludeGlobs, minAge: minAge, minSizeBytes: minSizeBytes,
            maxDepth: maxDepth, requiresProjectMarker: requiresProjectMarker, excludedPaths: excludedPaths)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupCategory.swift`, sostituire:

```swift
    public let rules: [CleanupRule]

    public init(
```

con:

```swift
    public let rules: [CleanupRule]
    /// Lo stato iniziale delle voci al passo 3: falso per le categorie di dati reali (Download, File
    /// grandi), dove ogni voce va spuntata a mano.
    public let itemsSelectedByDefault: Bool

    public init(
```

poi sostituire:

```swift
        rules: [CleanupRule]
    ) {
```

con:

```swift
        rules: [CleanupRule],
        itemsSelectedByDefault: Bool = true
    ) {
```

poi sostituire:

```swift
        self.rules = rules
    }
}
```

con:

```swift
        self.rules = rules
        self.itemsSelectedByDefault = itemsSelectedByDefault
    }

    /// La stessa categoria con le cartelle escluse nelle Impostazioni su ogni regola.
    public func excluding(_ excludedPaths: [String]) -> CleanupCategory {
        CleanupCategory(
            id: id, displayName: displayName, description: description, risk: risk, selectedByDefault: selectedByDefault,
            parentId: parentId, rules: rules.map { $0.excluding(excludedPaths) }, itemsSelectedByDefault: itemsSelectedByDefault)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Categories/CategoryCatalog.swift`, sostituire:

```swift
        func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 86_400 }

        return [
```

con:

```swift
        func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 86_400 }
        // Le cartelle escluse valgono per ogni regola del wizard (spec
        // `2026-10-19-large-files-exclusions-design.md`).
        let excluded = settings.excludedFolders.map(expanded)

        return [
```

poi sostituire la categoria `downloads-large` e la fine della funzione:

```swift
            CleanupCategory(
                id: "downloads-large",
                displayName: String(localized: "Download e file grandi", bundle: .module),
                description: String(localized: "Contiene dati reali, non file rigenerabili. Ogni voce va selezionata manualmente.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Downloads"), .matchingFiles, include: all, exclude: [], minAge: days(settings.downloadsMinAgeDays)),
                ] + settings.largeFileRoots.map { root in
                    CleanupRule(expanded(root), .matchingFiles, include: all, exclude: [], minSizeBytes: settings.largeFileThresholdBytes)
                }),
        ]
    }
}
```

con:

```swift
            CleanupCategory(
                id: "downloads",
                displayName: String(localized: "Download", bundle: .module),
                description: String(localized: "File in Download non usati da tempo. Contiene dati reali: nella verifica ogni voce parte deselezionata.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Downloads"), .matchingFiles, include: all, exclude: [], minAge: days(settings.downloadsMinAgeDays)),
                ],
                itemsSelectedByDefault: false),

            // Separata dai Download (2026-10-19): nello stesso gruppo i file grandi si confondevano
            // con i download, e fra loro c'erano i dischi delle macchine virtuali.
            CleanupCategory(
                id: "large-files",
                displayName: String(localized: "File grandi", bundle: .module),
                description: String(localized: "File e pacchetti oltre la soglia, nelle cartelle scelte nelle Impostazioni. Contiene dati reali: nella verifica ogni voce parte deselezionata.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: settings.largeFileRoots.map { root in
                    CleanupRule(expanded(root), .matchingFiles, include: all, exclude: [], minSizeBytes: settings.largeFileThresholdBytes)
                },
                itemsSelectedByDefault: false),
        ].map { $0.excluding(excluded) }
    }
}
```

In `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/CategoryVisuals.swift`, sostituire:

```swift
        case Array("downloads-large".utf8): CategoryVisual(tileColorName: "TileDownloadsLarge", designHex: "#E8833A", symbolName: "arrow.down.to.line")
```

con:

```swift
        case Array("downloads".utf8): CategoryVisual(tileColorName: "TileDownloads", designHex: "#E8833A", symbolName: "arrow.down.to.line")
        case Array("large-files".utf8): CategoryVisual(tileColorName: "TileLargeFiles", designHex: "#B5477F", symbolName: "scalemass")
```

In `MjmCleanerKit/Sources/CleanerFeatures/History/CategoryNames.swift`, sostituire:

```swift
            ("trash-downloads-large", String(localized: "Cestino, Download e file grandi", bundle: .module)),
```

con:

```swift
            ("trash-downloads-large", String(localized: "Cestino, Download e file grandi", bundle: .module)),
            // Fino al 2026-10-19 una sola categoria; ora sono «Download» e «File grandi».
            ("downloads-large", String(localized: "Download e file grandi", bundle: .module)),
```

Rinominare l'asset e creare quello nuovo, dalla radice del worktree:

```bash
git mv MjmCleaner/Assets.xcassets/TileDownloadsLarge.colorset MjmCleaner/Assets.xcassets/TileDownloads.colorset
mkdir -p MjmCleaner/Assets.xcassets/TileLargeFiles.colorset
```

Creare `MjmCleaner/Assets.xcassets/TileLargeFiles.colorset/Contents.json`, nello stesso formato delle altre tile (un colore solo, `universal`):

```json
{
  "colors": [
    {
      "color": {
        "color-space": "srgb",
        "components": {
          "alpha": "1.000",
          "red": "0xB5",
          "green": "0x47",
          "blue": "0x7F"
        }
      },
      "idiom": "universal"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
```

- [ ] **Step 4: Verificare che passino**

Run: comando «una suite» con `--filter 'CategoryCatalogTests|SettingsStoreTests|AppEnvironmentTests|ChooseStepTests|HistoryTests'`.
Expected: nessun `✘`.

Run: comando «package».
Expected: `CleanerCoreTests` **679** test in 60 suite, `CleanerFeaturesTests` **221** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift MjmCleanerKit/Sources/CleanerCore/Categories/CleanupCategory.swift MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift MjmCleanerKit/Sources/CleanerCore/Categories/CategoryCatalog.swift MjmCleanerKit/Sources/CleanerFeatures/Cleanup/CategoryVisuals.swift MjmCleanerKit/Sources/CleanerFeatures/History/CategoryNames.swift MjmCleaner/Assets.xcassets/TileLargeFiles.colorset/Contents.json MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryTests.swift
git status --short
git commit -m "$(cat <<'EOF'
feat: split Downloads and large files into two categories

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

Prima del commit, `git status --short` deve mostrare in stage anche la rinomina `R  MjmCleaner/Assets.xcassets/TileDownloadsLarge.colorset/Contents.json -> MjmCleaner/Assets.xcassets/TileDownloads.colorset/Contents.json`, fatta da `git mv`.

---

### Task 5: «Cartelle escluse» nelle Impostazioni

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`
- Modify: `MjmCleaner/Settings/SettingsView.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift`

**Interfaces:**
- Consumes: `CleanerSettings.excludedFolders` (Task 4), `SettingsModel.addFolder(to:title:)` e `remove(_:from:)` di oggi, `FakePicker.titles` (test).
- Produces: `SettingsModel.excludedFolders: [String]`, `selectedExcludedFolder: String?`, `canRemoveExcludedFolder: Bool`, `func addExcludedFolder() async`, `func removeExcludedFolder()`.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift`, sostituire:

```swift
        let appearance: FakeAppearance
        let events: Recorder<String>
    }
```

con:

```swift
        let appearance: FakeAppearance
        let picker: FakePicker
        let events: Recorder<String>
    }
```

poi sostituire:

```swift
        let events = Recorder<String>()
        let model = SettingsModel(
            store: store,
            appearance: appearance,
            folders: FakePicker(picked),
```

con:

```swift
        let events = Recorder<String>()
        let picker = FakePicker(picked)
        let model = SettingsModel(
            store: store,
            appearance: appearance,
            folders: picker,
```

poi sostituire:

```swift
        return Fixture(model: model, store: store, appearance: appearance, events: events)
```

con:

```swift
        return Fixture(model: model, store: store, appearance: appearance, picker: picker, events: events)
```

poi sostituire:

```swift
    @Test func cancelledPickerKeepsTheCurrentSelection() async {
```

con:

```swift
    @Test func excludedFoldersAreLoadedAddedRemovedAndSaved() async {
        let fixture = create(settings { $0.excludedFolders = ["/Users/tester/Parallels"] }, picked: "/Volumes/Archivio")
        #expect(fixture.model.excludedFolders == ["/Users/tester/Parallels"])
        #expect(!fixture.model.canRemoveExcludedFolder)

        await fixture.model.addExcludedFolder()
        #expect(fixture.picker.titles == ["Scegli una cartella da escludere"])
        #expect(fixture.model.excludedFolders == ["/Users/tester/Parallels", "/Volumes/Archivio"])
        #expect(fixture.model.selectedExcludedFolder == "/Volumes/Archivio")
        #expect(fixture.model.canRemoveExcludedFolder)

        // La stessa cartella scelta di nuovo non si ripete.
        await fixture.model.addExcludedFolder()
        #expect(fixture.model.excludedFolders == ["/Users/tester/Parallels", "/Volumes/Archivio"])

        fixture.model.selectedExcludedFolder = "/Users/tester/Parallels"
        fixture.model.removeExcludedFolder()
        #expect(fixture.model.excludedFolders == ["/Volumes/Archivio"])
        #expect(!fixture.model.canRemoveExcludedFolder)

        fixture.model.save()
        #expect(fixture.store.current.excludedFolders == ["/Volumes/Archivio"])
    }

    @Test func cancelDiscardsTheExcludedFolders() async {
        let fixture = create(settings { $0.excludedFolders = ["/a"] }, picked: "/b")
        await fixture.model.addExcludedFolder()
        fixture.model.cancel()
        #expect(fixture.store.current.excludedFolders == ["/a"])
        #expect(fixture.store.saves == 0)
    }

    @Test func removingAnExcludedFolderWithoutSelectionKeepsTheList() {
        let fixture = create(settings { $0.excludedFolders = ["/a", "/b"] })
        fixture.model.removeExcludedFolder()
        #expect(fixture.model.excludedFolders == ["/a", "/b"])
    }

    @Test func cancelledPickerKeepsTheCurrentSelection() async {
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `value of type 'SettingsModel' has no member 'excludedFolders'` e `value of type 'SettingsModel' has no member 'addExcludedFolder'`.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`, sostituire:

```swift
    public var selectedLargeFileRoot: String?
```

con:

```swift
    public var selectedLargeFileRoot: String?
    /// Cartelle mai analizzate né proposte, in nessuna categoria della pulizia guidata.
    public var excludedFolders: [String]
    public var selectedExcludedFolder: String?
```

poi sostituire:

```swift
    public var canRemoveLargeFileRoot: Bool { selectedLargeFileRoot != nil }
```

con:

```swift
    public var canRemoveLargeFileRoot: Bool { selectedLargeFileRoot != nil }
    public var canRemoveExcludedFolder: Bool { selectedExcludedFolder != nil }
```

poi sostituire:

```swift
        largeFileRoots = settings.largeFileRoots
        loadedThresholdBytes = settings.largeFileThresholdBytes
```

con:

```swift
        largeFileRoots = settings.largeFileRoots
        excludedFolders = settings.excludedFolders
        loadedThresholdBytes = settings.largeFileThresholdBytes
```

poi sostituire:

```swift
        settings.largeFileRoots = largeFileRoots
```

con:

```swift
        settings.largeFileRoots = largeFileRoots
        settings.excludedFolders = excludedFolders
```

poi sostituire:

```swift
    private func addFolder(to list: ReferenceWritableKeyPath<SettingsModel, [String]>, title: String) async -> String? {
```

con:

```swift
    public func addExcludedFolder() async {
        let title = String(localized: "Scegli una cartella da escludere", bundle: .module)
        if let path = await addFolder(to: \.excludedFolders, title: title) {
            selectedExcludedFolder = path
        }
    }

    public func removeExcludedFolder() {
        if let folder = selectedExcludedFolder {
            remove(folder, from: \.excludedFolders)
        }
        selectedExcludedFolder = nil
    }

    private func addFolder(to list: ReferenceWritableKeyPath<SettingsModel, [String]>, title: String) async -> String? {
```

In `MjmCleaner/Settings/SettingsView.swift`, sostituire:

```swift
                } header: {
                    Text("File grandi")
                } footer: {
                    Text("Vengono proposti solo i file più grandi della soglia.")
                }
```

con:

```swift
                } header: {
                    Text("File grandi")
                } footer: {
                    Text("Vengono proposti solo i file più grandi della soglia.")
                }

                Section {
                    FolderList(
                        roots: model.excludedFolders,
                        selection: $model.selectedExcludedFolder,
                        canRemove: model.canRemoveExcludedFolder,
                        add: model.addExcludedFolder,
                        remove: model.removeExcludedFolder)
                } header: {
                    Text("Cartelle escluse")
                } footer: {
                    Text("Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.")
                }
```

- [ ] **Step 4: Verificare che passino**

Run: comando «una suite» con `--filter SettingsViewModelTests`.
Expected: nessun `✘`.

Run: comando «package».
Expected: `CleanerCoreTests` **679** test in 60 suite, `CleanerFeaturesTests` **224** in 23; nessun `warning:` né `error:`.

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift MjmCleaner/Settings/SettingsView.swift MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat(settings): choose the folders excluded from every cleanup category

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Passo 3, preselezione per categoria e «Seleziona tutte le voci»

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift`
- Modify: `MjmCleaner/Cleanup/ConfirmStepView.swift`
- Modify: `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`

**Interfaces:**
- Consumes: `CleanupCategory.itemsSelectedByDefault` (Task 4), `ConfirmationRows.build`, `FakeClean` (test).
- Produces:
  - `PathNode.init(item: ScanItem, isSelected: Bool)` (interno; `isSelected` resta `public var`);
  - `CategoryNode.init(categoryId:displayName:items:itemsSelectedByDefault:)` (interno);
  - `CategoryNode.itemsStartDeselected: Bool`, `CategoryNode.allSelected: Bool { get set }`, `CategoryNode.selectAllAccessibilityLabel: String`;
  - nei test, `makeCategory(_:name:parent:risk:itemsSelectedByDefault:)` con `itemsSelectedByDefault: Bool = true`.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift`, sostituire:

```swift
func makeCategory(_ id: String, name: String? = nil, parent: String? = nil, risk: RiskLevel = .low) -> CleanupCategory {
    CleanupCategory(
        id: id, displayName: name ?? id, description: "descrizione", risk: risk,
        selectedByDefault: false, parentId: parent, rules: [])
}
```

con:

```swift
func makeCategory(
    _ id: String, name: String? = nil, parent: String? = nil, risk: RiskLevel = .low, itemsSelectedByDefault: Bool = true
) -> CleanupCategory {
    CleanupCategory(
        id: id, displayName: name ?? id, description: "descrizione", risk: risk,
        selectedByDefault: false, parentId: parent, rules: [], itemsSelectedByDefault: itemsSelectedByDefault)
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`, sostituire:

```swift
    @Test func deleteWithNothingSelectedDoesNothing() async throws {
```

con:

```swift
    // Download e File grandi (spec `2026-10-19-large-files-exclusions-design.md`).

    private let realData = [
        makeCategory("logs", name: "Log e crash report"),
        makeCategory("downloads", name: "Download", itemsSelectedByDefault: false),
        makeCategory("large-files", name: "File grandi", itemsSelectedByDefault: false),
    ]

    private var realDataResults: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log", size: 1024)],
                totalBytes: 1024, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "downloads", items: [makeItem("/Users/tester/Downloads/vecchio.dmg", size: 2048)],
                totalBytes: 2048, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "large-files",
                items: [makeItem("/Users/tester/Parallels/Windows 11.pvm", size: 4096), makeItem("/Users/tester/Lavoro/immagine.iso", size: 8192)],
                totalBytes: 12_288, errors: [], exclusions: []),
        ]
    }

    @Test func downloadsAndLargeFilesStartDeselected() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: realData, results: realDataResults)

        #expect(model.nodes.map { $0.paths.map(\.isSelected) } == [[true], [false], [false, false]])
        #expect(model.nodes.map(\.itemsStartDeselected) == [false, true, true])
        #expect(model.totalText == "1 KB · 1 elemento")
    }

    @Test func withOnlyRealDataNothingIsDeletedUntilAnItemIsTicked() throws {
        let model = ConfirmStepModel(
            environment: try makeEnvironment(), navigation: nil,
            categories: Array(realData.dropFirst()), results: Array(realDataResults.dropFirst()))

        #expect(model.totalText == "0 B · 0 elementi")
        #expect(!model.canDelete)

        model.nodes[1].paths[1].isSelected = true

        #expect(model.totalText == "8 KB · 1 elemento")
        #expect(model.canDelete)
    }

    @Test func selectAllReadsAndWritesTheWholeGroup() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: realData, results: realDataResults)
        let large = model.nodes[2]

        #expect(!large.allSelected)
        large.paths[0].isSelected = true
        #expect(!large.allSelected)

        large.allSelected = true
        #expect(large.paths.map(\.isSelected) == [true, true])
        #expect(large.allSelected)

        large.allSelected = false
        #expect(large.paths.map(\.isSelected) == [false, false])
        #expect(model.nodes[0].allSelected)
        #expect(large.selectAllAccessibilityLabel == "Seleziona tutte le voci di File grandi")
    }

    @Test func aCategoryMissingFromTheCatalogStartsDeselected() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: [], results: [realDataResults[0]])

        #expect(model.nodes.map { $0.paths.map(\.isSelected) } == [[false]])
        #expect(!model.canDelete)
    }

    @Test func deleteHandsOverOnlyTheTickedRealData() async throws {
        let clean = FakeClean()
        let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: realData, results: realDataResults)
        model.nodes[2].paths[1].isSelected = true

        await model.delete()

        #expect(clean.selections.first?.map(\.categoryId) == ["logs", "large-files"])
        #expect(clean.selections.first?.map { $0.items.map(\.path) } == [
            ["/Users/tester/Library/Logs/a.log"], ["/Users/tester/Lavoro/immagine.iso"],
        ])
    }

    @Test func deleteWithNothingSelectedDoesNothing() async throws {
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `value of type 'CategoryNode' has no member 'itemsStartDeselected'` e `value of type 'CategoryNode' has no member 'allSelected'`.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift`, sostituire:

```swift
    public let item: ScanItem
    public var isSelected = true

    init(item: ScanItem) {
        self.item = item
    }
```

con:

```swift
    public let item: ScanItem
    public var isSelected: Bool

    init(item: ScanItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }
```

poi sostituire:

```swift
    public let summaryText: String

    init(categoryId: String, displayName: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.displayName = displayName
        paths = items.map(PathNode.init)
```

con:

```swift
    public let summaryText: String

    /// Vero per i gruppi di dati reali (Download, File grandi): le voci partono deselezionate.
    public let itemsStartDeselected: Bool

    init(categoryId: String, displayName: String, items: [ScanItem], itemsSelectedByDefault: Bool) {
        self.categoryId = categoryId
        self.displayName = displayName
        paths = items.map { PathNode(item: $0, isSelected: itemsSelectedByDefault) }
        itemsStartDeselected = !itemsSelectedByDefault
```

poi sostituire:

```swift
        summaryText = "\(Formatting.integer(items.count)) \(noun) · \(Formatting.bytes(SafeSum.total(items.map(\.sizeBytes))))"
    }
}
```

con:

```swift
        summaryText = "\(Formatting.integer(items.count)) \(noun) · \(Formatting.bytes(SafeSum.total(items.map(\.sizeBytes))))"
    }

    /// La casella «Seleziona tutte le voci»: vera se il gruppo ha voci e sono tutte selezionate;
    /// impostarla seleziona o deseleziona ogni voce. È calcolata, quindi resta allineata alle
    /// caselle delle singole voci senza stato da sincronizzare.
    public var allSelected: Bool {
        get { !paths.isEmpty && paths.allSatisfy(\.isSelected) }
        set {
            for path in paths {
                path.isSelected = newValue
            }
        }
    }

    /// Il nome della casella di gruppo per VoiceOver, che altrimenti non saprebbe di quale gruppo.
    public var selectAllAccessibilityLabel: String {
        String(localized: "Seleziona tutte le voci di \(displayName)", bundle: .module)
    }
}
```

poi sostituire:

```swift
        nodes = ConfirmationRows.build(results).map { row in
            let name = categories.first { FeatureText.same($0.id, row.categoryId) }?.displayName ?? row.categoryId
            return CategoryNode(categoryId: row.categoryId, displayName: name, items: row.items)
        }
```

con:

```swift
        nodes = ConfirmationRows.build(results).map { row in
            let category = categories.first { FeatureText.same($0.id, row.categoryId) }
            // Una categoria assente dal catalogo oggi non capita; se capitasse, le sue voci partono
            // deselezionate: è la direzione sicura.
            return CategoryNode(
                categoryId: row.categoryId, displayName: category?.displayName ?? row.categoryId, items: row.items,
                itemsSelectedByDefault: category?.itemsSelectedByDefault ?? false)
        }
```

In `MjmCleaner/Cleanup/ConfirmStepView.swift`, sostituire:

```swift
private struct CategoryNodeView: View {
    let node: CategoryNode
    @State private var isExpanded = true
```

con:

```swift
private struct CategoryNodeView: View {
    @Bindable var node: CategoryNode
    @State private var isExpanded = true
```

poi sostituire:

```swift
        } header: {
            EmptyView()
        } row: { path in
```

con:

```swift
        } header: {
            if node.itemsStartDeselected {
                Text("Dati reali: le voci partono deselezionate. Spunta solo ciò che vuoi eliminare.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Toggle("Seleziona tutte le voci", isOn: $node.allSelected)
                .toggleStyle(.checkbox)
                .accessibilityLabel(node.selectAllAccessibilityLabel)
        } row: { path in
```

- [ ] **Step 4: Verificare che passino**

Run: comando «una suite» con `--filter ConfirmStepModelTests`.
Expected: nessun `✘`.

Run: comando «package».
Expected: `CleanerCoreTests` **679** test in 60 suite, `CleanerFeaturesTests` **229** in 23; nessun `warning:` né `error:`.

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift MjmCleaner/Cleanup/ConfirmStepView.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift
git commit -m "$(cat <<'EOF'
feat(cleanup): start real-data items deselected and select whole groups

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Demo, README e verifica finale

**Files:**
- Modify: `MjmCleaner/Demo/DemoData.swift`
- Modify: `MjmCleaner/Demo/DemoServices.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: gli ID `large-files` (Task 4) e `CleanerSettings.excludedFolders` (Task 4).
- Produces: nessuna interfaccia nuova. L'avvio dimostrativo mostra le due categorie al passo 1, un gruppo «File grandi» deselezionato al passo 3 e una cartella esclusa nelle Impostazioni.

- [ ] **Step 1: Demo**

In `MjmCleaner/Demo/DemoData.swift`, sostituire:

```swift
    static let analyzedCategoryIds = ["system-caches", "dev-caches", "nuget-packages", "logs"]
```

con:

```swift
    static let analyzedCategoryIds = ["system-caches", "dev-caches", "nuget-packages", "logs", "large-files"]
```

poi sostituire:

```swift
        result("logs", [
            item("/Users/demo/Library/Logs/DiagnosticReports", 96 * megabyte),
        ]),
    ]
```

con:

```swift
        result("logs", [
            item("/Users/demo/Library/Logs/DiagnosticReports", 96 * megabyte),
        ]),
        // Al passo 3 le voci dei file grandi partono deselezionate: una macchina virtuale è un'unica voce.
        result("large-files", [
            item("/Users/demo/Macchine virtuali/Windows 11.pvm", 64 * gigabyte),
            item("/Users/demo/Downloads/Xcode_26.xip", 9 * gigabyte),
        ]),
    ]
```

In `MjmCleaner/Demo/DemoServices.swift`, sostituire:

```swift
        settings.largeFileRoots = ["~/Downloads"]
```

con:

```swift
        settings.largeFileRoots = ["~/Downloads", "~/Macchine virtuali"]
        settings.excludedFolders = ["~/Lavoro/archivio"]
```

- [ ] **Step 2: README**

In `README.md`, sostituire:

```markdown
| **3 · Confirm** | Shows the mandatory preview: exact paths, sizes, a warning about running applications, and the exclusions made by `PathGuard`. This is the final point at which the operation can be abandoned. |
```

con:

```markdown
| **3 · Confirm** | Shows the mandatory preview: exact paths, sizes, a warning about running applications, and the exclusions made by `PathGuard` and by the excluded folders. Each group has a «Select all» checkbox; Downloads and large-file items start deselected. This is the final point at which the operation can be abandoned. |
```

poi sostituire:

```markdown
directories searched for `bin` and `obj`, the directories searched for large
files, the large-file size threshold, and the minimum ages for Downloads, logs,
and NuGet packages.
```

con:

```markdown
directories searched for `bin` and `obj`, the directories searched for large
files, the large-file size threshold, the folders excluded from every cleanup
category, and the minimum ages for Downloads, logs, and NuGet packages.
```

poi sostituire:

```markdown
- **Trash, Downloads, and large files** — high risk, never preselected
```

con:

```markdown
- **Trash** — high risk, never preselected
- **Downloads** — files in `~/Downloads` older than the minimum age; high risk,
  never preselected, and every item starts deselected in the preview
- **Large files** — files and packages above the threshold in the directories
  chosen in Settings; high risk, never preselected, and every item starts
  deselected in the preview

macOS packages, such as apps, Photos libraries, and Parallels, VMware Fusion, or
UTM virtual machines, are listed as a single item and never entered: deleting a
file inside one would break it. Folders excluded in Settings are never scanned
or proposed, and neither is a folder that contains one; the Xcode and Docker
pages do not use them.
```

- [ ] **Step 3: Verifica finale**

Run: comando «package».
Expected: `CleanerCoreTests` **679** test in 60 suite, `CleanerFeaturesTests` **229** in 23; nessun `warning:` né `error:`.

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

Run: `git status --short`.
Expected: solo i tre file di questo task (`M MjmCleaner/Demo/DemoData.swift`, `M MjmCleaner/Demo/DemoServices.swift`, `M README.md`), più eventualmente `.zed/` e `mjm-cleaner-ui-handoff.md` non tracciati. Se la build ha toccato un `Localizable.xcstrings`, si ripristina con `git checkout -- <file>` e non va in stage.

Run: `grep -rn "downloads-large\|TileDownloadsLarge" MjmCleanerKit/Sources MjmCleaner README.md`.
Expected: solo le due righe dei nomi storici in `CategoryNames.swift`, cioè `("trash-downloads-large", …)` e `("downloads-large", …)`.

- [ ] **Step 4: Commit**

```bash
git add MjmCleaner/Demo/DemoData.swift MjmCleaner/Demo/DemoServices.swift README.md
git commit -m "$(cat <<'EOF'
docs: describe the split categories, excluded folders and group selection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Screenshot (controller, solo con il consenso dell'utente)**

Il controller chiede all'utente se catturare gli screenshot dell'avvio dimostrativo (passo 1, passo 3 e Impostazioni). Servono circa due minuti, con Claude in primo piano e senza toccare tastiera e mouse. Senza consenso il task si chiude qui.

---

## Mutazioni provate in stesura

Tutte applicate una alla volta alla copia scratch completa (Task 1–7) ed eseguite con le suite indicate. Tutte uccise da un test, non da un avviso del compilatore: le quattro che all'inizio cadevano su una variabile inutilizzata (M1, M7, M20, M21) sono state riscritte in una forma che compila e ripetute.

| # | Mutazione | File | Uccisa da |
|---|---|---|---|
| M1 | `excludedReason` restituisce sempre `nil` | `ExcludedFolders.swift` | `ExcludedFoldersScanTests` (27 problemi) |
| M2 | niente potatura delle esclusioni in `scanFiles` | `RuleScanner.swift` | `matchingFilesPrunesAnExcludedBranchWithoutLookingInside`, `aPackageInsideAnExcludedFolderIsNeverProposed` |
| M3 | niente potatura delle esclusioni in `scanDirectories` | `RuleScanner.swift` | `matchingDirsNeverProposesAnExcludedBin` |
| M4 | `bin` che contiene un'esclusione proposto | `RuleScanner.swift` | `matchingDirsDoesNotProposeABinThatContainsAnExclusion` |
| M5 | nessuna esclusione in `scanContents` | `RuleScanner.swift` | 11 problemi in `ExcludedFoldersScanTests` |
| M6 | `scanContents` misura prima di escludere | `RuleScanner.swift` | `clearContentsSkipsAChildThatContainsAnExclusionWithoutMeasuringIt` |
| M7 | `candidateReason` senza il caso «contiene» | `ExcludedFolders.swift` | test «contiene» di scanner e pacchetti |
| M8 | solo la forma testuale del percorso | `ExcludedFolders.swift` | `exclusionMatchesTheTextualAndTheResolvedRoot` (argomento `/private/var/…`) |
| M9 | confine di segmento perso in `excludedReason` | `ExcludedFolders.swift` | `anExclusionDoesNotCoverASiblingWithTheSamePrefix` |
| M10 | confine di segmento perso nel caso «contiene» | `ExcludedFolders.swift` | `aChildIsNotTakenForTheParentOfASiblingExclusion` |
| M11 | niente controllo sulla root della regola | `RuleScanner.swift` | `ruleWhoseRootIsExcludedProducesNothing`, `excludingTheFilesystemRootExcludesEveryRule` |
| M12 | pacchetti attraversati come cartelle | `RuleScanner.swift` | 9 problemi in `PackageScanTests` |
| M13 | statistiche del pacchetto prima del guard | `RuleScanner.swift` | `aPackageTheGuardRejectsIsNeverMeasured` |
| M14 | soglia ignorata sui pacchetti | `RuleScanner.swift` | `theThresholdAppliesToThePackageTotal` |
| M15 | età ignorata sui pacchetti | `RuleScanner.swift` | `packageAgeIsTheNewestStampOfItsTree` |
| M16 | pacchetto che contiene un'esclusione proposto | `RuleScanner.swift` | `aPackageContainingAnExclusionIsNotProposed` |
| M17 | glob ignorati sui pacchetti | `RuleScanner.swift` | `globsApplyToThePackageName` |
| M18 | controllo del pacchetto prima di `.git` | `RuleScanner.swift` | `aGitDirectoryIsSkippedEvenIfItLooksLikeAPackage` |
| M19 | niente ripiego per le estensioni delle VM | `LocalFileSystem.swift` | `isPackageRecognisesBundlesAndVirtualMachines` |
| M20 | niente `lstat` in `isPackage` | `LocalFileSystem.swift` | `isPackageRecognisesBundlesAndVirtualMachines` (file `.pvm`, collegamento) |
| M21 | il catalogo non passa le esclusioni | `CategoryCatalog.swift` | `excludedFoldersReachEveryRuleAlreadyExpanded` |
| M22 | voci dei file grandi preselezionate | `CategoryCatalog.swift` | `downloadsAndLargeFilesAreHighRiskAndTheirItemsStartDeselected` |
| M23 | `CleanupCategory.excluding` perde `itemsSelectedByDefault` | `CleanupCategory.swift` | `downloadsAndLargeFilesAreHighRiskAndTheirItemsStartDeselected`, `excludingKeepsEveryOtherField` |
| M24 | `CleanupRule.excluding` perde `maxDepth` | `CleanupRule.swift` | `excludingKeepsEveryOtherField` |
| M25 | il passo 3 ignora la preselezione della categoria | `ConfirmStepModel.swift` | `downloadsAndLargeFilesStartDeselected` e altri (11 problemi) |
| M26 | categoria assente dal catalogo preselezionata | `ConfirmStepModel.swift` | `aCategoryMissingFromTheCatalogStartsDeselected` |
| M27 | `allSelected` vero con una sola voce spuntata | `ConfirmStepModel.swift` | `selectAllReadsAndWritesTheWholeGroup` |
| M28 | `allSelected` scrive solo la prima voce | `ConfirmStepModel.swift` | `selectAllReadsAndWritesTheWholeGroup` |
| M29 | Salva non scrive le cartelle escluse | `SettingsModel.swift` | `excludedFoldersAreLoadedAddedRemovedAndSaved` |
