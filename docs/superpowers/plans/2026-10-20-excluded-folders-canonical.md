# Cartelle escluse nella grafia del disco — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un'esclusione delle Impostazioni vale anche quando è scritta attraverso un collegamento sotto la root, sotto `/var` con una root dichiarata `/private/var/…`, in un'altra normalizzazione Unicode o con un'equivalenza di APFS, e quando è essa stessa un collegamento. Un'esclusione non valida o non verificabile fa sì che la regola non produca nulla. In più, un test copre l'analisi abbandonata che termina con `CancellationError`.

**Architecture:** La risalita di `PathGuard.storedForm` diventa `FileSystem.storedForm`, condivisa. `ExcludedFolders.resolve` calcola una volta per regola le forme di ogni esclusione (testo, grafia del disco, destinazione del collegamento) e della root (risolta, grafia del disco). Ogni elemento si confronta anche sotto le forme alternative della root, perché lo scanner non segue collegamenti e `readdir` dà i nomi del disco. `RuleScanner.scan` chiama la fabbrica dopo `validateRoot` e trasforma un rifiuto in un'unica esclusione sulla root.

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-20-excluded-folders-canonical-design.md`

Stato di partenza: branch `feat/excluded-folders-canonical` nel worktree `.claude/worktrees/mystifying-shaw-38cff4`, creato da `feat/large-files-exclusions` (273ed4e, non ancora su `main`), più la spec (8af2b37) e questo piano. `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **681** test in 60 suite (`CleanerCoreTests`) e **231** in 23 (`CleanerFeaturesTests`).

Decisioni dell'utente (2026-10-20, nella spec):

- **Approccio A**: grafia del disco delle esclusioni e della root, una volta per regola, nello scanner.
- **Un'esclusione che è un collegamento vale anche per la sua destinazione finale.**
- **Un'esclusione non verificabile, o non canonica, fa sì che la regola non produca nulla.**

Decisioni prese durante la stesura, verificate eseguendo l'intero piano in una copia scratch del branch:

- **`storedForm` è un'estensione interna di `FileSystem`** in `Platform/StoredForm.swift`, con l'insieme degli errori per cui si risale in una costante privata del file (`climbableStoredPathErrors`). `PathGuard` la chiama in quattro punti; motivi e comportamento del guard non cambiano, e `PathGuardTests` non si tocca.
- **`ExcludedFolders.resolve` restituisce `Result<ExcludedFolders, ExcludedFolders.Rejection>`**, con `Rejection: Error, Equatable` che porta il motivo già localizzato. L'inizializzatore pubblico sparisce: nessun test lo usava.
- **Prima le esclusioni, poi la root.** La fabbrica calcola le forme delle esclusioni e solo dopo `storedForm` della root risolta. Il test della root che smette di essere verificabile usa un'esclusione esistente, che non interroga il percorso della root.
- **La canonicità è quella di `CanonicalPath.canonical`**, la stessa di `DenyList` e `PathGuard`: rifiuta la stringa vuota, i percorsi relativi, «//», «/./», «/../» e NUL. «/» resta valido, e continua a escludere tutto.
- **Test in più rispetto alla spec:** `StoredFormTests` (4 test sulla funzione condivisa); `aRootUnderAnExclusionWrittenUnderVarProducesNothing`; `anExclusionThatIsALinkToAnUnreadableTargetStopsTheRule`; nell'integrazione, una root dichiarata in NFD con il disco in NFC, che su disco reale uccide la mutazione «senza grafia del disco della root» (le altre quattro non la vedono, perché la root risolta coincide con quella del disco).
- **Il test «nessuna chiamata in più»** confronta le chiamate a `storedPath` di una scansione senza esclusioni con quelle di `validateRoot` da solo, misurate con lo stesso doppio, invece di fissare un numero che dipende dal `PathGuard`.
- **`InMemoryFileSystem` usa `String` come chiave**, e `String` unisce NFC e NFD, e U+212A e «K» (equivalenza canonica). Le equivalenze si simulano con `AliasingFileSystem`, che confronta byte UTF-8; nell'integrazione le grafie attese si confrontano per byte.
- **Mutazione della spec non costruibile:** «la fabbrica chiamata dopo il controllo sulla root esclusa» non compila, perché quel controllo usa il risultato della fabbrica. La sostituiscono M11 (rifiuto ignorato) e M13 (forme alternative della root mai usate).
- **Analisi abbandonata.** `Gate.wait()` non reagisce all'annullamento (continuation con un proprio timer), quindi il doppio può aspettare il cancello anche da annullato e poi lanciare `CancellationError` se `Task.isCancelled`. `MainModelTests` aggiunge `import Synchronization` per `Mutex`.

Frasi nuove, in italiano con `String(localized:)` come le esistenti, da aggiungere alla tabella del piano di localizzazione (Core): «cartella esclusa con un percorso non valido: «\(testo)»», «cartella esclusa non verificabile sul filesystem: \(errore)». La terza frase usata dalla fabbrica, «root non verificabile sul filesystem: \(errore)», esiste già in `PathGuard`.

## Global Constraints

- Il codice vive in `MjmCleanerKit/`. Cambiano solo:
  - nel Core, `Safety/PathGuard.swift`, `Scanning/ExcludedFolders.swift`, `Scanning/RuleScanner.swift`, più il nuovo `Platform/StoredForm.swift`;
  - i test elencati nei task: i nuovi `CleanerCoreTests/Platform/StoredFormTests.swift`, `CleanerCoreTests/Scanning/ExcludedFoldersDiskSpellingTests.swift`, `CleanerCoreTests/Integration/ExcludedFoldersRealFileSystemTests.swift`, e `CleanerFeaturesTests/MainModelTests.swift`;
  - `README.md`.
- L'app (`MjmCleaner/`) non cambia. Nessun file `Localizable.xcstrings` cambia.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati nel codice di produzione.
- `DenyList` non cambia; `PathGuard` cambia solo per usare la funzione condivisa, con gli stessi motivi di rifiuto.
- Testi nuovi: solo i due elencati sopra, scritti esattamente come nel piano.
- Comandi di verifica, dalla radice del worktree:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E '✘|Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-excluded-canonical-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/excluded-folders-canonical`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md` e i `Localizable.xcstrings`.
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick) e mai avviare l'app: le verifiche sono test e build.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: **opus per i Task 1 e 2** (il `PathGuard` è l'ultima linea di difesa prima di ogni cancellazione; lo scanner decide cosa si propone) e per la revisione finale; sonnet per i Task 3 e 4. Tutti i task si rivedono con mutazioni in una copia scratch.
- Mutazioni provate in stesura, tutte uccise dai test del piano: vedi la tabella in fondo. I revisori le ripetono e ne cercano altre.
- A fine piano il controller copia il registro in `docs/superpowers/decisions/2026-10-20-registro-decisioni-excluded-folders-canonical.md`, con le frasi nuove, e poi usa `superpowers:finishing-a-development-branch`.

---

## Fatti misurati (2026-10-20, macOS 27.0, Xcode 27)

- Sul branch di partenza: 681 test in 60 suite nel Core, 231 in 23 in Features.
- Copia scratch con l'intero piano: 705 test in 63 suite nel Core, 232 in 23 in Features, nessun warning con `-warnings-as-errors`.
- Con i soli test del Task 2 sul codice di prima (Task 1 applicato), 14 dei 15 test falliscono; passa solo `anExclusionThatCannotBeLookedUpClimbsAndStillApplies`, perché lì il testo basta già.
- `LocalFileSystem.contentsOfDirectory` restituisce i nomi con i byte del disco: una cartella creata in NFD con `mkdir` torna in NFD.

---

### Task 1: `FileSystem.storedForm`, la risalita condivisa

**Files:**
- Create: `MjmCleanerKit/Sources/CleanerCore/Platform/StoredForm.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Platform/StoredFormTests.swift` (nuovo)

**Interfaces:**
- Consumes: `FileSystem.storedPath(_:)`, `FileSystemError`, `PathText.parent`, `PathText.fileName`, `PathText.join`; nei test `AliasingFileSystem(_:aliases:failures:)` e `ForwardingFileSystem`.
- Produces: `func FileSystem.storedForm(_ path: String) -> Result<String, FileSystemError>` (estensione interna del Core). Il Task 2 la usa da `ExcludedFolders`.

- [ ] **Step 1: Test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Platform/StoredFormTests.swift`:

```swift
import Darwin
import Testing
@testable import CleanerCore

private struct UnexpectedStoredPathError: Error {}

/// `storedPath` lancia un errore che non viene dal filesystem su un percorso esatto.
private final class ForeignErrorFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let path: String

    init(path: String) {
        self.path = path
        super.init(InMemoryFileSystem())
    }

    override func storedPath(_ path: String) throws -> String {
        if path == self.path { throw UnexpectedStoredPathError() }
        return try super.storedPath(path)
    }
}

/// `FileSystem.storedForm`, la risalita condivisa da `PathGuard` ed `ExcludedFolders`: si risale
/// all'antenato esistente più profondo e si ricompone il resto dal testo, solo con gli errori per
/// cui nemmeno il kernel raggiunge l'oggetto.
struct StoredFormTests {
    private static let alias = "/Users/tester/Des\u{212A}top"
    private static let stored = "/Users/tester/Desktop"

    @Test(arguments: [ENOENT, ENOTDIR, EACCES, EPERM])
    func climbsToTheDeepestAncestorTheDiskSpells(code: Int32) {
        let fs = AliasingFileSystem(aliases: [(Self.alias, Self.stored)], failures: [("\(Self.alias)/nuovo/x", code)])

        #expect(fs.storedForm("\(Self.alias)/nuovo/x") == .success("\(Self.stored)/nuovo/x"))
    }

    /// La risalita si ferma al primo errore che non è fra quelli previsti, anche dopo un ENOENT.
    @Test(arguments: [EIO, ELOOP, ENAMETOOLONG])
    func anyOtherErrorIsTheResult(code: Int32) {
        let fs = AliasingFileSystem(
            aliases: [(Self.alias, Self.stored)], failures: [("\(Self.alias)/nuovo/x", ENOENT), ("\(Self.alias)/nuovo", code)])

        #expect(fs.storedForm("\(Self.alias)/nuovo/x") == .failure(FileSystemError(code: code, path: "\(Self.alias)/nuovo")))
    }

    /// Nemmeno la radice si legge: non c'è un antenato da cui ricomporre il percorso.
    @Test func reachingTheRootWithoutSuccessIsTheResult() {
        let fs = AliasingFileSystem(failures: [("/", ENOENT)])

        #expect(fs.storedForm("/Users/tester/x") == .failure(FileSystemError(code: ENOENT, path: "/")))
    }

    @Test func anErrorThatIsNotFromTheFileSystemBecomesEIOOnItsPath() {
        let fs = ForeignErrorFileSystem(path: "/Users/tester")

        #expect(fs.storedForm("/Users/tester/x") == .failure(FileSystemError(code: EIO, path: "/Users/tester")))
    }
}
```

- [ ] **Step 2: Verificare che non compilino**

Run: il comando «compilazione (passo RED)» delle Global Constraints.
Expected: `error: value of type 'AliasingFileSystem' has no member 'storedForm'` e `error: value of type 'ForeignErrorFileSystem' has no member 'storedForm'` (misurati in stesura).

- [ ] **Step 3: La funzione condivisa**

Creare `MjmCleanerKit/Sources/CleanerCore/Platform/StoredForm.swift`:

```swift
import Darwin

/// Gli errori di `storedPath` per cui `storedForm` risale all'antenato: il componente non esiste
/// (ENOENT, ENOTDIR) o il suo genitore non si attraversa (EACCES, EPERM). In entrambi i casi
/// nemmeno l'eliminazione raggiunge l'oggetto, perché la ricerca del kernel è la stessa. Ogni
/// altro errore rende il percorso non verificabile.
private let climbableStoredPathErrors: Set<Int32> = [ENOENT, ENOTDIR, EACCES, EPERM]

extension FileSystem {
    /// Il percorso come lo registra il filesystem: quello dell'antenato più profondo che esiste,
    /// `path` compreso, seguito dai componenti che mancano, presi dal testo. Un elemento sparito
    /// dopo la scansione resta verificabile, e la cancellazione che segue lo segnala «non
    /// trovato» come prima. Si risale solo con `climbableStoredPathErrors`: ogni altro errore, o la
    /// radice raggiunta senza successo, è il risultato. Un errore che non viene dal filesystem vale
    /// `EIO` sul percorso dove è avvenuto. Condivisa da `PathGuard` ed `ExcludedFolders`; `path` è
    /// canonico.
    func storedForm(_ path: String) -> Result<String, FileSystemError> {
        var existing = path
        var missing: [String] = []
        while true {
            do {
                let stored = try storedPath(existing)
                return .success(missing.reversed().reduce(stored) { PathText.join($0, $1) })
            } catch let error as FileSystemError {
                guard climbableStoredPathErrors.contains(error.code), let parent = PathText.parent(existing), !parent.isEmpty else {
                    return .failure(error)
                }
                missing.append(PathText.fileName(existing))
                existing = parent
            } catch {
                return .failure(FileSystemError(code: EIO, path: existing))
            }
        }
    }
}
```

- [ ] **Step 4: `PathGuard` usa la funzione condivisa**

In `MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift`, sei modifiche.

(a) Nel commento della struttura, sostituire il paragrafo:

```swift
/// Solo Swift (piano APFS, spec §12): la deny-list e la profondità minima si applicano anche al
/// percorso come lo registra il filesystem (`FileSystem.storedPath`), dopo ogni controllo
/// testuale. APFS case-insensitive ripiega più di OrdinalIgnoreCase (U+212A per "k", "ſ" per
/// "s", "ß" per "ss", NFC e NFD): un elemento scritto "~/Des\u{212A}top/x" supera i confronti
/// testuali e il kernel lo risolve in "~/Desktop/x".
```

con:

```swift
/// Solo Swift (piano APFS, spec §12): la deny-list e la profondità minima si applicano anche al
/// percorso come lo registra il filesystem (`FileSystem.storedForm`, condivisa con
/// `ExcludedFolders`), dopo ogni controllo testuale. APFS case-insensitive ripiega più di
/// OrdinalIgnoreCase (U+212A per "k", "ſ" per "s", "ß" per "ss", NFC e NFD): un elemento scritto
/// "~/Des\u{212A}top/x" supera i confronti testuali e il kernel lo risolve in "~/Desktop/x".
```

(b) Eliminare il blocco (con la riga vuota che lo segue):

```swift
    /// Gli errori di `storedPath` per cui si risale all'antenato: il componente non esiste
    /// (ENOENT, ENOTDIR) o il suo genitore non si attraversa (EACCES, EPERM). In entrambi i casi
    /// nemmeno l'eliminazione raggiunge l'oggetto, perché la ricerca del kernel è la stessa. Ogni
    /// altro errore rende il percorso non verificabile, e il percorso viene negato.
    private static let climbableErrors: Set<Int32> = [ENOENT, ENOTDIR, EACCES, EPERM]

```

(c) Nell'inizializzatore, sostituire `        switch Self.storedForm(home, in: fileSystem) {` con:

```swift
        switch fileSystem.storedForm(home) {
```

(d) In `validateRoot`, sostituire `        switch storedForm(canonicalResolved) {` con:

```swift
        switch fileSystem.storedForm(canonicalResolved) {
```

(e) In `validate` e in `pruneReason`, sostituire entrambe le righe `        switch storedForm(path) {` con:

```swift
        switch fileSystem.storedForm(path) {
```

(f) Eliminare per intero i due metodi privati, dal primo fino alla riga vuota prima di `private static func isHomeOrDirectChild`:

```swift
    private func storedForm(_ path: String) -> Result<String, FileSystemError> {
        Self.storedForm(path, in: fileSystem)
    }

    /// Il percorso come lo registra il filesystem: quello dell'antenato più profondo che esiste,
    /// `path` compreso, seguito dai componenti che mancano, presi dal testo. Un elemento sparito
    /// dopo la scansione resta verificabile, e la cancellazione che segue lo segnala «non
    /// trovato» come prima. Si risale solo con `climbableErrors`. `path` è canonico.
    private static func storedForm(_ path: String, in fileSystem: any FileSystem) -> Result<String, FileSystemError> {
        var existing = path
        var missing: [String] = []
        while true {
            do {
                let stored = try fileSystem.storedPath(existing)
                return .success(missing.reversed().reduce(stored) { PathText.join($0, $1) })
            } catch let error as FileSystemError {
                guard climbableErrors.contains(error.code), let parent = PathText.parent(existing), !parent.isEmpty else {
                    return .failure(error)
                }
                missing.append(PathText.fileName(existing))
                existing = parent
            } catch {
                return .failure(FileSystemError(code: EIO, path: existing))
            }
        }
    }

```

Controllo: `grep -n "storedForm\|climbableErrors" MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift`
Expected: esattamente cinque righe: il commento della struttura (`FileSystem.storedForm`, condivisa con) e quattro `switch fileSystem.storedForm(…) {` (`home`, `canonicalResolved`, due volte `path`). Nessun `climbableErrors`.

- [ ] **Step 5: Test delle due suite**

Run: il comando «una suite» con `--filter "StoredFormTests|PathGuardTests"`.
Expected: `✔ Test run with 62 tests in 2 suites passed`.

- [ ] **Step 6: Tutto il package**

Run: il comando «package».
Expected: `CleanerCoreTests` **685** test in 61 suite, `CleanerFeaturesTests` **231** in 23; nessun `warning:` né `error:`.

- [ ] **Step 7: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Platform/StoredForm.swift MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift MjmCleanerKit/Tests/CleanerCoreTests/Platform/StoredFormTests.swift
git commit -m "refactor(safety): share the stored-form climb of PathGuard

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Esclusioni confrontate nella grafia del disco

**Files:**
- Modify (riscritto per intero): `MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`
- Modify: `README.md`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ExcludedFoldersDiskSpellingTests.swift` (nuovo)

**Interfaces:**
- Consumes: `FileSystem.storedForm(_:)` (Task 1), `CanonicalPath.canonical(_:)`, `LinkInspecting.isSymbolicLink(_:)` e `resolveLinkTarget(_:)`, `PathText`; nei test `AliasingFileSystem`, `FakeLinkInspector`, `InMemoryFileSystem`, `ForwardingFileSystem`, `Recorder`, `FixedWallClock`, `utc(_:_:_:_:)`.
- Produces:
  - `static func ExcludedFolders.resolve(_ excluded: [String], root: String, resolvedRoot: String, fileSystem: any FileSystem, links: any LinkInspecting) -> Result<ExcludedFolders, ExcludedFolders.Rejection>`;
  - `struct ExcludedFolders.Rejection: Error, Equatable { let reason: String }`;
  - invariati: `excludedReason(_:)`, `candidateReason(_:)`, `static var excludedReason`, `static var containsReason`.
  - L'inizializzatore `ExcludedFolders.init(_:root:resolvedRoot:)` non esiste più.

- [ ] **Step 1: Test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ExcludedFoldersDiskSpellingTests.swift`:

```swift
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
    /// root.
    @Test func anExclusionInTheDiskSpellingMatchesARootDeclaredInAnotherNormalization() throws {
        let declared = "/Users/tester/Lavoro/Cafe\u{0301}"
        let onDisk = "/Users/tester/Lavoro/Caf\u{00E9}"
        let memory = InMemoryFileSystem()
        memory.addFile("\(declared)/tieni/dati.bin", size: 100)
        memory.addFile("\(declared)/via/dati.bin", size: 100)
        let fs = AliasingFileSystem(memory, aliases: [(declared, onDisk)])

        let outcome = try create(fs).scan(CleanupRule(declared, .clearContents, include: Self.all, exclude: [], excludedPaths: ["\(onDisk)/tieni"]))

        #expect(outcome.items.map(\.path) == ["\(declared)/via"])
        #expect(outcome.exclusions == [GuardExclusion(path: "\(declared)/tieni", reason: Self.excludedReason)])
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
```

- [ ] **Step 2: Verificare che falliscano**

Run: il comando «una suite» con `--filter ExcludedFoldersDiskSpellingTests`.
Expected: `✘ Test run with 15 tests in 1 suite failed`, con 14 test falliti. Passa solo `anExclusionThatCannotBeLookedUpClimbsAndStillApplies`, che con il confronto testuale è già vero (misurato in stesura).

- [ ] **Step 3: `ExcludedFolders` con le forme del disco**

Sostituire l'intero contenuto di `MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift` con:

```swift
import Darwin

/// Le cartelle escluse nelle Impostazioni, viste da una regola (spec
/// `2026-10-20-excluded-folders-canonical-design.md`). Un'esclusione si confronta in più forme: il
/// testo com'è scritto, la grafia del disco (`FileSystem.storedForm`) e, se questa è un
/// collegamento, la grafia del disco della sua destinazione finale. Anche il percorso di un
/// elemento ha più forme: com'è, sotto la root risolta da `validateRoot` e sotto la grafia del
/// disco della root. Lo scanner non segue mai i collegamenti e `readdir` dà i nomi come stanno sul
/// disco, quindi sotto la root la grafia del disco di un elemento è quella della root seguita dal
/// suffisso. Così un'esclusione vale anche scritta attraverso un collegamento, sotto "/var" con una
/// root "/private/var/…", in un'altra normalizzazione Unicode o con un'equivalenza di APFS (U+212A,
/// "ß"). Il confronto ignora le maiuscole, come la deny-list: aggiungere forme può solo escludere
/// di più.
///
/// «/» si riduce alla stringa vuota, e `isSameOrUnder(path, "")` è vero per ogni percorso
/// assoluto: escludere la radice esclude tutto, che è la direzione sicura.
struct ExcludedFolders: Sendable {
    /// Il motivo per cui la regola non produce nulla: un'esclusione non valida o non verificabile,
    /// o la root non verificabile. «Non verificabile» vuol dire negare, come nel `PathGuard`.
    struct Rejection: Error, Equatable {
        let reason: String
    }

    /// Le forme di tutte le esclusioni.
    private let folders: [String]
    private let root: String
    /// Le forme della root diverse da quella dichiarata: la root risolta e la grafia del disco.
    private let alternativeRoots: [String]

    private init(folders: [String], root: String, alternativeRoots: [String]) {
        self.folders = folders
        self.root = root
        self.alternativeRoots = alternativeRoots
    }

    /// Le esclusioni di una regola, con le forme della root e di ogni esclusione già calcolate:
    /// una chiamata per regola, dopo `validateRoot`. Senza esclusioni non interroga il filesystem.
    static func resolve(
        _ excluded: [String], root: String, resolvedRoot: String,
        fileSystem: any FileSystem, links: any LinkInspecting
    ) -> Result<ExcludedFolders, Rejection> {
        let root = PathText.trimmingTrailingSlashes(root)
        guard !excluded.isEmpty else {
            return .success(ExcludedFolders(folders: [], root: root, alternativeRoots: []))
        }

        var folders: [String] = []
        for path in excluded {
            switch forms(of: path, fileSystem, links) {
            case .success(let forms): folders += forms
            case .failure(let rejection): return .failure(rejection)
            }
        }

        let storedRoot: String
        switch fileSystem.storedForm(resolvedRoot) {
        case .success(let stored): storedRoot = stored
        case .failure(let error):
            return .failure(Rejection(reason: String(localized: "root non verificabile sul filesystem: \(error.description)", bundle: .module)))
        }

        var roots = [root]
        for candidate in [resolvedRoot, storedRoot].map(PathText.trimmingTrailingSlashes)
        where !candidate.isEmpty && !roots.contains(where: { PathText.equalsIgnoringCase($0, candidate) }) {
            roots.append(candidate)
        }
        return .success(ExcludedFolders(folders: folders, root: root, alternativeRoots: Array(roots.dropFirst())))
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

    /// Le forme di un'esclusione, tutte senza «/» finali: il testo, la grafia del disco e, se
    /// questa è un collegamento, la grafia del disco della destinazione finale. Un testo che non è
    /// un percorso assoluto canonico, o una forma che non si riesce a ricavare, rifiuta la regola.
    private static func forms(of excluded: String, _ fileSystem: any FileSystem, _ links: any LinkInspecting) -> Result<[String], Rejection> {
        guard let canonical = CanonicalPath.canonical(excluded) else {
            return .failure(Rejection(reason: String(localized: "cartella esclusa con un percorso non valido: «\(excluded)»", bundle: .module)))
        }
        var forms = [PathText.trimmingTrailingSlashes(canonical)]

        let stored: String
        switch fileSystem.storedForm(canonical) {
        case .success(let path): stored = path
        case .failure(let error): return .failure(unverifiable(error))
        }
        forms.append(PathText.trimmingTrailingSlashes(stored))

        // `storedPath` non segue l'ultimo componente: un'esclusione che è un collegamento vale
        // anche per la sua destinazione. Una destinazione non determinabile è un ciclo, o un
        // collegamento che non si legge più.
        guard links.isSymbolicLink(stored) else { return .success(forms) }
        guard let target = links.resolveLinkTarget(stored) else {
            return .failure(unverifiable(FileSystemError(code: ELOOP, path: stored)))
        }
        switch fileSystem.storedForm(target) {
        case .success(let path): forms.append(PathText.trimmingTrailingSlashes(path))
        case .failure(let error): return .failure(unverifiable(error))
        }
        return .success(forms)
    }

    private static func unverifiable(_ error: FileSystemError) -> Rejection {
        Rejection(reason: String(localized: "cartella esclusa non verificabile sul filesystem: \(error.description)", bundle: .module))
    }

    /// Il percorso com'è e, se sta sotto la root dichiarata, lo stesso suffisso sotto ogni forma
    /// alternativa della root. Un prefisso riconosciuto senza maiuscole occupa lo stesso numero di
    /// scalari della root (`PathText.hasPrefixIgnoringCase`).
    private func forms(_ path: String) -> [String] {
        guard !alternativeRoots.isEmpty, PathText.isSameOrUnder(path, root) else { return [path] }
        let suffix = path.unicodeScalars.dropFirst(root.unicodeScalars.count)
        return [path] + alternativeRoots.map { alternative in
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: alternative.unicodeScalars)
            scalars.append(contentsOf: suffix)
            return String(scalars)
        }
    }
}
```

- [ ] **Step 4: `RuleScanner` chiama la fabbrica**

In `MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`, in `scan`, sostituire:

```swift
        // Le cartelle escluse nelle Impostazioni si confrontano anche con la root risolta. Se la
        // root stessa è esclusa, o sta sotto un'esclusione, la regola non produce nulla.
        let excluded = ExcludedFolders(rule.excludedPaths, root: rule.root, resolvedRoot: rootVerdict.canonicalPathValidated)
        if let reason = excluded.excludedReason(rule.root) {
```

con:

```swift
        // Le cartelle escluse nelle Impostazioni si confrontano anche con la root risolta e nella
        // grafia del disco. Un'esclusione non valida o non verificabile ferma la regola, come la
        // root esclusa o sotto un'esclusione: la regola non produce nulla.
        let excluded: ExcludedFolders
        switch ExcludedFolders.resolve(
            rule.excludedPaths, root: rule.root, resolvedRoot: rootVerdict.canonicalPathValidated, fileSystem: fileSystem, links: links) {
        case .success(let folders): excluded = folders
        case .failure(let rejection):
            accumulator.exclusions.append(GuardExclusion(path: rule.root, reason: rejection.reason))
            return accumulator.outcome
        }
        if let reason = excluded.excludedReason(rule.root) {
```

- [ ] **Step 5: README**

In `README.md`, sostituire:

```markdown
Folders excluded in Settings are never scanned or proposed. A folder that would
be deleted as a whole, such as a cache subfolder, a `bin` or `obj` directory,
or a macOS package, is not proposed if it contains an excluded folder. The Xcode
and Docker pages do not use excluded folders.
```

con:

```markdown
Folders excluded in Settings are never scanned or proposed. A folder that would
be deleted as a whole, such as a cache subfolder, a `bin` or `obj` directory,
or a macOS package, is not proposed if it contains an excluded folder. An
exclusion also matches the same folder reached through a symbolic link, written
under `/var` instead of `/private/var`, or spelled differently but naming the
same folder on disk (another Unicode normalization, an APFS case equivalence).
An excluded folder that is a symbolic link also excludes its target. An excluded
folder that is not an absolute path, or that cannot be checked on disk, stops
every cleanup rule, and step 3 shows why. The Xcode and Docker pages do not use
excluded folders.
```

- [ ] **Step 6: Test delle esclusioni**

Run: il comando «una suite» con `--filter "ExcludedFolders|RuleScannerTests|MatchingDirsTests|PackageScanTests|CategoryCatalogTests"`.
Expected: nessun `✘`.

- [ ] **Step 7: Tutto il package**

Run: il comando «package».
Expected: `CleanerCoreTests` **700** test in 62 suite, `CleanerFeaturesTests` **231** in 23; nessun `warning:` né `error:`.

- [ ] **Step 8: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ExcludedFoldersDiskSpellingTests.swift README.md
git commit -m "fix(scan): match excluded folders in the disk's spelling too

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Integrazione su APFS reale

I test di questo task passano appena scritti, perché il comportamento viene dal Task 2. Il passo 3 prova che mordono, con una mutazione temporanea che poi si annulla.

**Files:**
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Integration/ExcludedFoldersRealFileSystemTests.swift` (nuovo)

**Interfaces:**
- Consumes: `RuleScanner`, `PathGuard`, `DenyList`, `LocalFileSystem`, `FileSystemLinkInspector`, `SystemWallClock`, `CleanupRule(… minSizeBytes:excludedPaths:)`, `GuardExclusion`; nei test `TemporaryDirectory` (`directory`, `file(_:contents:)`, `symlink(_:to:)`, `volumeIsCaseInsensitive`).
- Produces: nessuna interfaccia.

- [ ] **Step 1: I test**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Integration/ExcludedFoldersRealFileSystemTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Passano**

Run: il comando «una suite» con `--filter ExcludedFoldersRealFileSystemTests`.
Expected: `✔ Test run with 5 tests in 1 suite passed`.

- [ ] **Step 3: Mordono**

In `MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift` eliminare temporaneamente la riga:

```swift
        forms.append(PathText.trimmingTrailingSlashes(stored))
```

Run: il comando «una suite» con `--filter ExcludedFoldersRealFileSystemTests`.
Expected: `✘ Test run with 5 tests in 1 suite failed`, con 4 test falliti: `anExclusionWrittenThroughARealLinkUnderTheRootPrunesTheTarget`, `anExclusionUnderVarMatchesARootDeclaredUnderPrivateVar`, `anExclusionInAnotherSpellingOfTheSameNameMatches` e `anExclusionInTheDiskSpellingMatchesARootDeclaredInAnotherNormalization`. Il quinto, `anExclusionThatIsARealLinkAlsoExcludesItsTarget`, vive della destinazione del collegamento (mutazione M3 in fondo).

Poi annullare la mutazione:

```bash
git checkout -- MjmCleanerKit/Sources/CleanerCore/Scanning/ExcludedFolders.swift
git status --short MjmCleanerKit/Sources
```

Expected: `git status` non mostra nulla sotto `MjmCleanerKit/Sources`.

- [ ] **Step 4: Tutto il package**

Run: il comando «package».
Expected: `CleanerCoreTests` **705** test in 63 suite, `CleanerFeaturesTests` **231** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerCoreTests/Integration/ExcludedFoldersRealFileSystemTests.swift
git commit -m "test(scan): check excluded folders in the disk's spelling on real APFS

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: L'analisi abbandonata che termina con l'annullamento

`ScanStepModel.perform` è già corretto: questo task aggiunge solo il test che mancava (registro di `feat/large-files-exclusions`, «Final: parked»). Il test passa appena scritto; il passo 3 prova che morde.

**Files:**
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`

**Interfaces:**
- Consumes: `MainModel`, `ScanStepModel` (`run`, `isRunning`), `main.page.scanStep`, `main.settings?.save()`, `makeEnvironment(scan:)`, `makeCategory(_:)`, `FakeAppearance`, `FakePicker`, `Gate`, `ScanPerforming`.
- Produces: nel file, il doppio privato `CancellableGatedScan`.

- [ ] **Step 1: Il test e il doppio**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`, tre modifiche.

(a) Sostituire le importazioni in testa:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures
```

con:

```swift
import CleanerCore
import Foundation
import Synchronization
import Testing
@testable import CleanerFeatures
```

(b) Subito prima di `    @Test func startOverIsRefusedWhileXcodeDeletes() async throws {`, inserire:

```swift
    /// Il ramo dell'annullamento: un'analisi abbandonata che termina con `CancellationError` non
    /// chiama più `startOver()`, che abbandonerebbe la nuova analisi e tornerebbe al passo 1.
    @Test func anAbandonedScanEndingInCancellationLeavesTheNewScanAlone() async throws {
        let scan = CancellableGatedScan()
        let main = MainModel(environment: try makeEnvironment(scan: scan), appearance: FakeAppearance(), folders: FakePicker())
        main.showScan([makeCategory("logs")])
        let abandoned = try #require(main.page.scanStep)
        try await scan.started.wait()

        main.showSettings()
        try #require(main.settings).save()
        main.showScan([makeCategory("logs")])
        let current = try #require(main.page.scanStep)

        scan.release.open()
        await abandoned.run?.value

        #expect(scan.threwCancellation)
        #expect(main.page.scanStep === current)
        #expect(current.isRunning)

        scan.later.open()
        await current.run?.value
    }

```

(c) Subito prima di `/// Storico che segnala la rilettura del contatore, l'ultimo passo del salvataggio di un resoconto:`, inserire:

```swift
/// Come `GatedScan`, ma la prima analisi si ferma come `ScanEngine`: aspetta `release` anche se
/// annullata, poi lancia `CancellationError` se il suo task è stato annullato. Le analisi successive
/// aspettano `later` e restituiscono un risultato vuoto.
private final class CancellableGatedScan: ScanPerforming {
    let started = Gate<Void>()
    let release = Gate<Void>()
    let later = Gate<Void>()
    private let calls = Mutex(0)
    private let cancellation = Mutex(false)

    var threwCancellation: Bool { cancellation.withLock { $0 } }

    func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult] {
        let call = calls.withLock { count -> Int in
            count += 1
            return count
        }
        guard call == 1 else {
            try? await later.wait()
            return []
        }
        started.open()
        try? await release.wait()
        if Task.isCancelled {
            cancellation.withLock { $0 = true }
            throw CancellationError()
        }
        return []
    }
}

```

- [ ] **Step 2: Passa**

Run: il comando «una suite» con `--filter MainModelTests`.
Expected: nessun `✘`; `✔ Test run with 21 tests in 1 suite passed`.

- [ ] **Step 3: Morde**

In `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ScanStepModel.swift`, nel ramo `catch is CancellationError` di `perform`, eliminare temporaneamente la riga `            guard !abandoned else { return }` (la seconda delle due presenti nel metodo, quella che precede `navigation?.startOver()`).

Run: il comando «una suite» con `--filter MainModelTests`.
Expected: `✘ Test run with 21 tests in 1 suite failed`, con il solo `anAbandonedScanEndingInCancellationLeavesTheNewScanAlone` fallito (misurato in stesura).

Poi annullare la mutazione:

```bash
git checkout -- MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ScanStepModel.swift
git status --short MjmCleanerKit/Sources
```

Expected: `git status` non mostra nulla sotto `MjmCleanerKit/Sources`.

- [ ] **Step 4: Tutto il package e l'app**

Run: il comando «package».
Expected: `CleanerCoreTests` **705** test in 63 suite, `CleanerFeaturesTests` **232** in 23; nessun `warning:` né `error:`.

Run: il comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

Run: `git status --short`
Expected: solo `M MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`, più eventualmente `.zed/` e `mjm-cleaner-ui-handoff.md` non tracciati. Se la build ha toccato un `Localizable.xcstrings`, si ripristina con `git checkout -- <file>` e non va in stage.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift
git commit -m "test(cleanup): cover an abandoned scan that ends in cancellation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Mutazioni provate in stesura

Tutte applicate una alla volta alla copia scratch completa (Task 1–4), con le suite `StoredFormTests`, `ExcludedFolders…`, `PathGuardTests`, `RuleScannerTests`, `MatchingDirsTests`, `PackageScanTests` (Core) e `MainModelTests` (Features). Tutte uccise da un test, non da un errore del compilatore: M2 all'inizio cadeva su una variabile inutilizzata ed è stata riscritta con `dropLast()`.

| # | Mutazione | File | Uccisa da |
|---|---|---|---|
| M1 | senza la grafia del disco delle esclusioni (niente `forms.append(… stored)`) | `ExcludedFolders.swift` | collegamento sotto la root, «contiene» via collegamento, `/var` con root `/private/var`, root sotto un'esclusione `/var`, equivalenze; nell'integrazione 4 test su 5 |
| M2 | senza la grafia del disco della root (`[resolvedRoot, storedRoot].dropLast()`) | `ExcludedFolders.swift` | `anExclusionInTheDiskSpellingMatchesARootDeclaredInAnotherNormalization` (unità e integrazione) |
| M3 | senza la destinazione del collegamento | `ExcludedFolders.swift` | i quattro test sui collegamenti-esclusione, `anExclusionThatIsARealLinkAlsoExcludesItsTarget` |
| M4 | esclusione non canonica confrontata come testo | `ExcludedFolders.swift` | `aNonCanonicalExclusionStopsTheRule` |
| M5 | `storedForm` fallita: solo il testo | `ExcludedFolders.swift` | `anExclusionWhoseDiskSpellingCannotBeReadStopsTheRule` |
| M6 | destinazione non determinabile ignorata | `ExcludedFolders.swift` | `anExclusionThatIsALinkWithoutADeterminableTargetStopsTheRule` |
| M7 | `storedForm` della destinazione fallita ignorata | `ExcludedFolders.swift` | `anExclusionThatIsALinkToAnUnreadableTargetStopsTheRule` |
| M8 | root non verificabile sostituita dalla root risolta | `ExcludedFolders.swift` | `aRootThatStopsBeingVerifiableAfterValidationStopsTheRule` |
| M9 | EACCES non risale | `StoredForm.swift` | `anExclusionThatCannotBeLookedUpClimbsAndStillApplies`, `climbsToTheDeepestAncestorTheDiskSpells`, `PathGuardTests.missingOrHiddenComponentsClimbToTheirAncestor` |
| M10 | ENOTDIR non risale | `StoredForm.swift` | `climbsToTheDeepestAncestorTheDiskSpells`, `PathGuardTests.missingOrHiddenComponentsClimbToTheirAncestor` |
| M11 | rifiuto ignorato in `RuleScanner` (esclusioni vuote al suo posto) | `RuleScanner.swift` | i cinque test dei rifiuti |
| M12 | `storedPath` interrogato anche senza esclusioni | `ExcludedFolders.swift` | `aRuleWithoutExclusionsAsksStoredPathNoMoreThanValidateRoot` |
| M13 | forme alternative della root mai usate | `ExcludedFolders.swift` | 6 test fra unità, integrazione ed `ExcludedFoldersScanTests` (root risolta) |
| M14 | senza `guard !abandoned` nel ramo dell'annullamento | `ScanStepModel.swift` | `anAbandonedScanEndingInCancellationLeavesTheNewScanAlone` |
