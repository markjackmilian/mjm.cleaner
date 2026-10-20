# Passo 3: voci contenute in una cartella proposta altrove — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Al passo 3 una voce che sta dentro una cartella proposta da un'altra voce (per esempio il modello di «File grandi» sotto `~/.cache/huggingface`, proposta da «Cache di sviluppo») è segnata «Inclusa in …», appare spuntata e bloccata finché la cartella è spuntata, e non arriva mai al motore insieme alla sua cartella.

**Architecture:** `ConfirmationRows.build` riceve un risolutore delle root (`RootResolving`, a cui si conforma `PathGuard`), deduplica su una chiave ripiegata come APFS e calcolata sulla root risolta, e lega ogni riga alla riga-cartella più vicina che la contiene (`ConfirmationRow.container`). `ConfirmationRows.selections` è l'unico punto che decide cosa riceve `CleanEngine`: una riga parte solo se è selezionata e nessuna cartella della sua catena lo è. In Features `PathNode` mostra `isChecked` (`isSelected || isCovered`), `CategoryNode` cambia con «Seleziona tutte» solo le voci libere, e `ConfirmStepModel` conta e invia solo le voci che partono da sole.

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-20-confirmation-containment-design.md`

Stato di partenza: il worktree `.claude/worktrees/vigorous-bouman-a475d2`, branch `feat/confirmation-containment`, creato da `feat/large-files-exclusions` (273ed4e, non ancora unito a `main`) più la spec e questo piano. Nessun push. `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **681** test in 60 suite (`CleanerCoreTests`) e **231** in 23 (`CleanerFeaturesTests`).

Decisioni dell'utente (2026-10-20, nella spec):

- **Approccio B, «annotare e legare»:** la voce contenuta resta nel suo gruppo con «Inclusa in …», spuntata e bloccata finché la cartella è spuntata; libera, con il suo stato, se la cartella si deseleziona.
- **Contenimento sulle root risolte**, come le cancellerà il motore.
- **Nota sulla riga della cartella** («Contiene anche 1 voce di File grandi.») e **riga di conteggio** sotto l'avviso del gruppo.

Decisioni prese durante la stesura, verificate eseguendo l'intero piano in una copia scratch:

- **Chiave con il ripiegamento completo di Foundation** (`folding(options: [.caseInsensitive], locale: nil)`): «Straße» e «STRASSE», il segno Kelvin e «k» coincidono, come su APFS. `PathText.folded` (OrdinalIgnoreCase) non li unisce. Nessuna scomposizione NFD esplicita: le chiavi `String` di `Set` e `Dictionary` si confrontano già per equivalenza canonica, e una scomposizione in più sarebbe codice che nessun test distingue.
- **Esempio del collegamento:** `~/.cache` → `~/Dati/cache`, non `/Volumes/…`, perché la deny-list nega `/Volumes` e lì non si cancella nulla. La spec è allineata.
- **`ConfirmationCategory.items` resta come proprietà calcolata** su `rows`: i sette test esistenti di `ConfirmationRowsTests` non cambiano asserzioni, e nel Task 2 `ConfirmStepModel` compila cambiando una sola riga.
- **`resolveRoot` senza valore predefinito**, e `AppEnvironment.init` con `roots:` obbligatorio. Nei test di Features `makeEnvironment` ha un `FakeRootResolver()` predefinito (identità con mappa); la demo ha il suo `DemoRoots`. Nessun risolutore identità nel codice di produzione del Core.
- **`selections` tratta una posizione di `container` inesistente come coperta:** la riga non parte. `build` non la produce mai; c'è un test con righe costruite a mano.
- **«Seleziona tutte» ripete le passate finché nessuna voce libera cambia.** Con una cartella e una voce che contiene nello stesso gruppo, e la voce prima della cartella, una passata sola lascerebbe la voce spuntata dopo «deseleziona tutte».
- **`canDelete` resta `nodes.contains { $0.paths.contains(where: \.isSelected) }`.** Leggere le voci che partono da sole sarebbe equivalente: se una voce è selezionata, la prima selezionata risalendo la sua catena parte. La mutazione è stata provata e sopravvive per questo motivo.
- **`PathRow` legge `path.isChecked` nel corpo** e passa al `Toggle` un `Binding` costruito a mano: la riga si ridisegna quando cambia la sua casella o quella della cartella.
- **Demo:** «File grandi» guarda `~` nelle impostazioni demo, il caso segnalato; `~/.cache/huggingface` in «Cache di sviluppo» e un modello lì dentro in «File grandi».

Frasi nuove, in italiano con `String(localized:)` nel bundle di `CleanerFeatures`, da aggiungere alla tabella del piano di localizzazione:

- «Inclusa in \(percorso) (\(gruppo)): si elimina con la cartella.»
- «Inclusa in \(percorso) (\(gruppo)).»
- «Contiene anche \(numero) \(voce|voci) di \(gruppo).», con «voce» e «voci»
- «1 voce è dentro una cartella spuntata e si elimina con quella.»
- «\(numero) voci sono dentro cartelle spuntate e si eliminano con quelle.»

Nessuna frase nuova nel Core né nell'app.

## Global Constraints

- Il codice vive in `MjmCleanerKit/` (package) e `MjmCleaner/` (app). Cambiano solo:
  - nel Core, `Cleaning/ConfirmationRows.swift` e il nuovo `Safety/RootResolving.swift`;
  - in `CleanerFeatures`, `Environment/AppEnvironment.swift` e `Cleanup/ConfirmStepModel.swift`;
  - nell'app, `Cleanup/ConfirmStepView.swift`, `Demo/DemoData.swift` e `Demo/DemoServices.swift`;
  - `README.md`;
  - i test elencati nei task.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati nel codice di produzione.
- `CleanEngine`, `PathGuard` (a parte la conformità a `RootResolving` in un file nuovo) e `DenyList` non cambiano.
- Testi nuovi: solo quelli elencati sopra, scritti esattamente come nel piano. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica, dalla radice del worktree:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E '✘|Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-containment-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/confirmation-containment`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md`, `MjmCleaner.xcodeproj/project.xcworkspace/` (lo crea `xcodebuild` e `.gitignore` non lo copre) e i tre `Localizable.xcstrings` (`MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`).
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick) e mai avviare l'app: le verifiche sono test e build. Gli screenshot con `-MJMDemo` li cattura il controller, solo dopo averlo chiesto all'utente.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: sonnet per i Task 1 e 4; **opus per i Task 2 e 3** (le righe e la selezione decidono che cosa si cancella) e per la revisione finale. I Task 1, 2 e 3 si rivedono con mutazioni in una copia scratch: la tabella in fondo elenca quelle provate in stesura.
- A fine piano il controller copia il registro in `docs/superpowers/decisions/2026-10-20-registro-decisioni-confirmation-containment.md`, con le frasi nuove, e poi usa `superpowers:finishing-a-development-branch`.

---

## Fatti misurati (2026-10-20, macOS 27.0, Xcode 27)

- Su `feat/large-files-exclusions` 273ed4e: 681 test in 60 suite nel Core, 231 in 23 in Features.
- `String.folding(options: [.caseInsensitive], locale: nil)`: «Straße» e «STRASSE» danno `strasse`; «\u{212A}elvin» dà `kelvin`; «ſs» e «SS» danno `ss`; la legatura «ﬁ» dà `fi`. Le grafie NFC e NFD di «Café» restano diverse in scalari ma uguali come `String`.
- `PathGuard.validateRoot` restituisce `canonicalPathValidated` anche per una root negata dopo la risoluzione (`/Volumes/SSD/Caches`), e la stringa vuota per una root non canonica (`relativa/cache`, `/Users/tester/../altro`).
- Nella copia scratch con tutti i task: 707 test in 62 suite nel Core, 240 in 23 in Features; la build Debug dell'app riesce e lascia invariati i tre `Localizable.xcstrings`.
- Il piano, applicato blocco per blocco a una copia pulita di questo branch, dà gli errori RED e i conteggi GREEN scritti in ogni task (Task 1: 685/232, Task 2: 707/232, Task 3 e 4: 707/240) e un risultato identico alla copia collaudata.

---

### Task 1: `RootResolving` e `AppEnvironment.roots`

**Files:**
- Create: `MjmCleanerKit/Sources/CleanerCore/Safety/RootResolving.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`
- Modify: `MjmCleaner/Demo/DemoServices.swift`
- Modify: `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Safety/RootResolvingTests.swift` (nuovo), `MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`

**Interfaces:**
- Consumes: `PathGuard.validateRoot(_:) -> GuardVerdict`, `GuardVerdict.canonicalPathValidated`, `AppEnvironment.live(paths:update:home:tempDirectory:)`; nei test `InMemoryFileSystem`, `FakeLinkInspector(targets:)`, `TemporaryDirectory`, `UnexpectedTestError`.
- Produces:
  - `public protocol RootResolving: Sendable { func resolvedRoot(_ declaredRoot: String) -> String }`;
  - `extension PathGuard: RootResolving`;
  - `public let AppEnvironment.roots: any RootResolving` e il parametro `roots: any RootResolving` di `AppEnvironment.init`, subito dopo `clean:`;
  - nei test di Features, `struct FakeRootResolver: RootResolving` con `var targets: [String: String]` e il parametro `roots: any RootResolving = FakeRootResolver()` di `makeEnvironment`, subito dopo `clean:`.

- [ ] **Step 1: Test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Safety/RootResolvingTests.swift`:

```swift
import Testing
@testable import CleanerCore

/// `PathGuard` come `RootResolving`: la root come la vede il motore, cioè quella di `validateRoot`.
struct RootResolvingTests {
    private static let home = "/Users/tester"

    private func resolver(_ targets: [String: String?] = [:]) throws -> any RootResolving {
        try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(targets: targets),
            homeDirectory: Self.home)
    }

    @Test func anOrdinaryRootStaysAsDeclared() throws {
        #expect(try resolver().resolvedRoot("/Users/tester/Library/Caches") == "/Users/tester/Library/Caches")
    }

    @Test func aLinkedRootLeadsToItsTarget() throws {
        let roots = try resolver(["/Users/tester/.cache": "/Users/tester/Dati/cache", "/var": "/private/var"])

        #expect(roots.resolvedRoot("/Users/tester/.cache") == "/Users/tester/Dati/cache")
        #expect(roots.resolvedRoot("/var/folders/xyz/T") == "/private/var/folders/xyz/T")
    }

    /// Una root negata dopo la risoluzione vale comunque dove porta: le sue voci non si cancellano, e
    /// il percorso risolto riconosce più contenimenti.
    @Test func aDeniedRootStillLeadsToItsTarget() throws {
        let roots = try resolver(["/Users/tester/Library/Caches": "/Volumes/SSD/Caches"])

        #expect(roots.resolvedRoot("/Users/tester/Library/Caches") == "/Volumes/SSD/Caches")
    }

    /// Senza un percorso canonico (root relativa o con segmenti «..»), resta la root dichiarata.
    @Test func withoutACanonicalPathTheDeclaredRootStays() throws {
        let roots = try resolver()

        #expect(roots.resolvedRoot("relativa/cache") == "relativa/cache")
        #expect(roots.resolvedRoot("/Users/tester/../altro") == "/Users/tester/../altro")
    }
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`, sostituire:

```swift
    @Test func defaultPathsIsolatesDebugDataFromRelease() {
```

con:

```swift
    /// Spec `2026-10-20-confirmation-containment-design.md`: in `live` il passo 3 risolve le root con
    /// lo stesso `PathGuard` del motore, quindi un collegamento reale porta dove porta.
    @Test func liveRootsFollowARealLink() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        guard let resolved = realpath(directory.path, nil) else {
            throw UnexpectedTestError(description: "realpath non riuscito")
        }
        defer { free(resolved) }
        let home = String(cString: resolved) + "/home"
        try FileManager.default.createDirectory(atPath: home + "/Dati/cache", withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: home + "/.cache", withDestinationPath: home + "/Dati/cache")

        let environment = try await AppEnvironment.live(
            paths: AppPaths(supportDirectory: directory.path + "/dati"), home: home, tempDirectory: directory.path + "/tmp")

        #expect(environment.roots.resolvedRoot(home + "/.cache") == home + "/Dati/cache")
        #expect(environment.roots.resolvedRoot(home + "/Dati") == home + "/Dati")
    }

    @Test func defaultPathsIsolatesDebugDataFromRelease() {
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione».
Expected: il Core si ferma per primo, quindi l'errore del test di `AppEnvironmentTests` non compare ancora:

- `error: cannot find type 'RootResolving' in scope`

- [ ] **Step 3: Implementazione**

Creare `MjmCleanerKit/Sources/CleanerCore/Safety/RootResolving.swift`:

```swift
/// Dove si trova davvero la root dichiarata da una regola. Il passo 3 confronta i percorsi come li
/// cancellerà il motore, che prima di eliminare risolve la root con `validateRoot`: senza la
/// risoluzione, una voce sotto `~/.cache` diretta altrove sfuggirebbe alla cartella che la contiene
/// (spec `2026-10-20-confirmation-containment-design.md`).
public protocol RootResolving: Sendable {
    func resolvedRoot(_ declaredRoot: String) -> String
}

extension PathGuard: RootResolving {
    /// La root canonica di `validateRoot`, con i collegamenti degli antenati risolti, anche quando
    /// la root è negata: le voci sotto una root negata non si cancellano comunque, e il percorso
    /// risolto riconosce più contenimenti, che è la direzione sicura. Senza un percorso canonico,
    /// la root dichiarata.
    public func resolvedRoot(_ declaredRoot: String) -> String {
        let canonical = validateRoot(declaredRoot).canonicalPathValidated
        return canonical.isEmpty ? declaredRoot : canonical
    }
}
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
    public let clean: any CleanPerforming
    public let history
```

con:

```swift
    public let clean: any CleanPerforming
    /// Le root come le risolve il motore: il passo 3 le usa per riconoscere le voci contenute in
    /// una cartella proposta da un'altra voce.
    public let roots: any RootResolving
    public let history
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
        clean: any CleanPerforming,
        history: any HistoryStoring,
```

con:

```swift
        clean: any CleanPerforming,
        roots: any RootResolving,
        history: any HistoryStoring,
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
        self.clean = clean
        self.history
```

con:

```swift
        self.clean = clean
        self.roots = roots
        self.history
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
            clean: CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: clock),
            history: history,
```

con:

```swift
            clean: CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: clock),
            roots: pathGuard,
            history: history,
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
/// Un `AppEnvironment` di soli doppi, con la home finta `/Users/tester`.
func makeEnvironment(
    scan: any ScanPerforming = FakeScan(),
    clean: any CleanPerforming = FakeClean(),
```

con:

```swift
/// Risolve le root con una mappa: una root assente resta com'è dichiarata.
struct FakeRootResolver: RootResolving {
    var targets: [String: String] = [:]

    func resolvedRoot(_ declaredRoot: String) -> String {
        targets[declaredRoot] ?? declaredRoot
    }
}

/// Un `AppEnvironment` di soli doppi, con la home finta `/Users/tester`.
func makeEnvironment(
    scan: any ScanPerforming = FakeScan(),
    clean: any CleanPerforming = FakeClean(),
    roots: any RootResolving = FakeRootResolver(),
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
        clean: clean,
        history: history,
```

con:

```swift
        clean: clean,
        roots: roots,
        history: history,
```

In `MjmCleaner/Demo/DemoServices.swift`, sostituire:

```swift
            clean: DemoClean(),
            history: DemoHistory(),
```

con:

```swift
            clean: DemoClean(),
            roots: DemoRoots(),
            history: DemoHistory(),
```

In `MjmCleaner/Demo/DemoServices.swift`, sostituire:

```swift
private struct DemoClean: CleanPerforming {
```

con:

```swift
/// La demo non tocca il disco: ogni root resta quella dichiarata.
private struct DemoRoots: RootResolving {
    func resolvedRoot(_ declaredRoot: String) -> String { declaredRoot }
}

private struct DemoClean: CleanPerforming {
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package».
Expected: `CleanerCoreTests` **685** test in 61 suite, `CleanerFeaturesTests` **232** in 23; nessun `warning:` né `error:`.

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Safety/RootResolving.swift MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift MjmCleaner/Demo/DemoServices.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift MjmCleanerKit/Tests/CleanerCoreTests/Safety/RootResolvingTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift
git commit -m "$(cat <<'EOF'
feat(cleanup): resolve declared roots for the confirmation step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: righe con il contenimento e selezione per il motore

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Cleaning/ConfirmationRows.swift` (intero file)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift` (una riga)
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationRowsTests.swift` (intero file), `MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationCleanupTests.swift` (nuovo)

**Interfaces:**
- Consumes: `RootResolving.resolvedRoot(_:)` e `AppEnvironment.roots` (Task 1); `CleanEngine.rewriteToResolvedRoot(_:declaredRoot:resolvedRoot:)` (interna al Core); `CategorySelection`; nei test `InMemoryFileSystem`, `FakeLinkInspector(targets:)`, `FixedWallClock`, `utc(_:_:_:_:)`.
- Produces:
  - `public struct ConfirmationPosition: Sendable, Equatable, Hashable { public let category: Int; public let row: Int }` con `init(category:row:)`;
  - `public struct ConfirmationRow: Sendable, Equatable { public let item: ScanItem; public let container: ConfirmationPosition? }` con `init(item:container:)`;
  - `ConfirmationCategory` con `public let rows: [ConfirmationRow]`, `init(categoryId:rows:)` e `public var items: [ScanItem]` calcolata;
  - `ConfirmationRows.build(_ results: [CategoryScanResult], resolveRoot: (String) -> String) -> [ConfirmationCategory]`;
  - `ConfirmationRows.selections(_ categories: [ConfirmationCategory], isSelected: (ConfirmationPosition) -> Bool) -> [CategorySelection]`;
  - `static func ConfirmationRows.comparisonKey(_ path: String) -> String` (interna).

- [ ] **Step 1: Test che falliscono**

Sostituire l'intero contenuto di `MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationRowsTests.swift` con:

```swift
import Testing
@testable import CleanerCore

struct ConfirmationRowsTests {
    private func item(_ path: String, _ size: Int64 = 10, directory: Bool = false, root: String = "/root") -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: directory, declaredRoot: root)
    }

    private func result(_ categoryId: String, _ items: ScanItem...) -> CategoryScanResult {
        CategoryScanResult(categoryId: categoryId, items: items, totalBytes: items.reduce(0) { $0 + $1.sizeBytes }, errors: [], exclusions: [])
    }

    /// Le root si risolvono con la mappa; una root assente resta com'è dichiarata.
    private func build(_ results: [CategoryScanResult], roots: [String: String] = [:]) -> [ConfirmationCategory] {
        ConfirmationRows.build(results) { roots[$0] ?? $0 }
    }

    private func position(_ category: Int, _ row: Int) -> ConfirmationPosition {
        ConfirmationPosition(category: category, row: row)
    }

    // IMPORTANT della revisione finale: lo stesso percorso presente in due categorie produceva due
    // righe, raggiungibile configurando le cartelle dei file grandi in sovrapposizione a una root
    // del catalogo. Una riga sola in tutto il passo, non solo dentro ciascuna categoria.
    @Test func samePathInTwoCategoriesProducesOnlyOneRowInTotal() {
        let built = build([
            result("cat-a", item("/Users/tester/Downloads/x.zip", 100)),
            result("cat-b", item("/Users/tester/Downloads/x.zip", 100)),
        ])

        #expect(built.flatMap(\.items).filter { $0.path == "/Users/tester/Downloads/x.zip" }.count == 1)
    }

    // La prima categoria a proporlo se lo tiene; le successive non lo ripetono. Questo è ciò che
    // rende la deselezione della riga davvero esaustiva: non esiste una seconda copia dello stesso
    // percorso in un'altra categoria che il motore possa ancora ricevere.
    @Test func duplicateIsAttributedToTheFirstCategoryOnlyAndDeselectingItsRowRemovesItEntirely() throws {
        let built = build([
            result("cat-a", item("/x/dup", 10)),
            result("cat-b", item("/x/dup", 10), item("/x/solo-b", 5)),
        ])

        let catA = try #require(built.first { $0.categoryId == "cat-a" })
        let catB = try #require(built.first { $0.categoryId == "cat-b" })
        #expect(catA.items.contains { $0.path == "/x/dup" })
        #expect(!catB.items.contains { $0.path == "/x/dup" })
        #expect(catB.items.contains { $0.path == "/x/solo-b" })
    }

    @Test func totalBytesAreNotDoubledForADuplicatePath() {
        let built = build([
            result("cat-a", item("/x/dup", 500)),
            result("cat-b", item("/x/dup", 500), item("/x/other", 50)),
        ])

        #expect(built.flatMap(\.items).reduce(0) { $0 + $1.sizeBytes } == 550)
    }

    // La deduplicazione dentro la stessa categoria deve continuare a funzionare: due regole della
    // stessa categoria possono coprire lo stesso file.
    @Test func deduplicatesWithinTheSameCategoryToo() {
        let built = build([result("cat-a", item("/x/dup", 10), item("/x/dup", 10))])
        #expect(built.map(\.items.count) == [1])
    }

    // Una categoria i cui percorsi sono TUTTI già stati assorbiti da una categoria precedente non
    // deve comparire come categoria vuota nel passo di conferma.
    @Test func categoryWithAllItemsClaimedByAnEarlierCategoryIsOmitted() {
        let built = build([result("cat-a", item("/x/dup", 10)), result("cat-b", item("/x/dup", 10))])
        #expect(!built.contains { $0.categoryId == "cat-b" })
    }

    @Test func categoryWithNoItemsIsOmitted() {
        #expect(build([result("cat-empty")]).isEmpty)
    }

    @Test func distinctPathsAcrossCategoriesAreAllKept() {
        let built = build([result("cat-a", item("/x/a", 10)), result("cat-b", item("/x/b", 20))])
        #expect(built.flatMap(\.items).count == 2)
    }

    // Contenimento (spec `2026-10-20-confirmation-containment-design.md`).

    /// Il caso segnalato: con «File grandi» su `~`, il modello sotto `~/.cache/huggingface` sta nella
    /// cartella che «Cache di sviluppo» propone.
    @Test func aFileInsideAFolderOfAnotherCategoryPointsToThatFolder() {
        let built = build([
            result("dev-caches", item("/Users/tester/.cache/huggingface", 5_900, directory: true, root: "/Users/tester/.cache")),
            result("large-files", item("/Users/tester/.cache/huggingface/hub/model.bin", 4_800, root: "/Users/tester")),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[nil], [position(0, 0)]])
    }

    @Test func containmentDoesNotDependOnTheOrderOfTheGroups() {
        let built = build([
            result("downloads", item("/Users/tester/Downloads/progetto/bin/Debug/app.dll")),
            result("project-build-output", item("/Users/tester/Downloads/progetto/bin", directory: true)),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[position(1, 0)], [nil]])
    }

    @Test func theNearestFolderOfAChainIsTheContainer() {
        let built = build([
            result("cat-c", item("/x/a/b/c.bin")),
            result("cat-a", item("/x/a", directory: true)),
            result("cat-b", item("/x/a/b", directory: true)),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[position(2, 0)], [nil], [position(1, 0)]])
    }

    /// Confine di segmento: `/x/cache` non contiene `/x/cacheExtra/f`.
    @Test func aFolderDoesNotContainASiblingWithACommonPrefix() {
        let built = build([
            result("cat-a", item("/x/cache", directory: true)),
            result("cat-b", item("/x/cacheExtra/f"), item("/x/cache.old")),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[nil], [nil, nil]])
    }

    /// Solo cartelle e pacchetti contengono. Il caso non si presenta sul disco, ma fissa che la
    /// regola guarda `isDirectory` e non solo il testo.
    @Test func aFileContainsNothing() {
        let built = build([result("cat-a", item("/x/a")), result("cat-b", item("/x/a/b"))])

        #expect(built.map { $0.rows.map(\.container) } == [[nil], [nil]])
    }

    @Test func aSameCategoryFolderAlsoContains() {
        let built = build([result("large-files", item("/x/vm.pvm", directory: true), item("/x/vm.pvm/disk.hdd"))])

        #expect(built.map { $0.rows.map(\.container) } == [[nil, position(0, 0)]])
    }

    /// APFS non distingue maiuscole e grafie: `~/Progetti/App/bin` e `~/progetti/APP/BIN` sono la
    /// stessa cartella, e «Straße» è «STRASSE».
    @Test func samePathWithDifferentCaseOrSpellingIsOneRow() {
        let built = build([
            result("cat-a", item("/Users/tester/Progetti/App/bin", directory: true), item("/Users/tester/Lavoro/Café.mov")),
            result("cat-b", item("/Users/tester/progetti/APP/BIN", directory: true), item("/Users/tester/LAVORO/Cafe\u{301}.mov")),
            result("cat-c", item("/Users/tester/Archivio/Straße.zip"), item("/Users/tester/Archivio/STRASSE.zip")),
        ])

        #expect(built.map { $0.items.map(\.path) } == [
            ["/Users/tester/Progetti/App/bin", "/Users/tester/Lavoro/Café.mov"],
            ["/Users/tester/Archivio/Straße.zip"],
        ])
    }

    @Test func containmentIgnoresCaseAndSpelling() {
        let built = build([
            result("cat-a", item("/Users/tester/Lavoro/Straße", directory: true), item("/Users/tester/Lavoro/Caf\u{E9}", directory: true)),
            result("cat-b", item("/Users/tester/lavoro/STRASSE/video.mov"), item("/Users/tester/Lavoro/CAFE\u{301}/foto.raw")),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[nil, nil], [position(0, 0), position(0, 1)]])
    }

    /// `~/.cache` è un collegamento a `~/Dati/cache` e «File grandi» guarda `~/Dati`: il modello sta
    /// nella cartella che il motore cancellerà, anche se il testo dei due percorsi non lo dice.
    @Test func aLinkedRootIsComparedWhereItLeads() {
        let results = [
            result("dev-caches", item("/Users/tester/.cache/huggingface", directory: true, root: "/Users/tester/.cache")),
            result("large-files", item("/Users/tester/Dati/cache/huggingface/model.bin", root: "/Users/tester/Dati")),
        ]

        #expect(build(results, roots: ["/Users/tester/.cache": "/Users/tester/Dati/cache"]).map { $0.rows.map(\.container) }
            == [[nil], [position(0, 0)]])
        #expect(build(results).map { $0.rows.map(\.container) } == [[nil], [nil]])
    }

    @Test func twoSpellingsThatLeadToTheSameFolderAreOneRow() {
        let built = build(
            [
                result("dev-caches", item("/Users/tester/.cache/pip", directory: true, root: "/Users/tester/.cache")),
                result("large-files", item("/Users/tester/Dati/cache/pip", directory: true, root: "/Users/tester/Dati")),
            ],
            roots: ["/Users/tester/.cache": "/Users/tester/Dati/cache"])

        #expect(built.map { $0.items.map(\.path) } == [["/Users/tester/.cache/pip"]])
    }

    @Test func eachDeclaredRootIsResolvedOnce() {
        var asked: [String] = []
        _ = ConfirmationRows.build([
            result("cat-a", item("/a/1", root: "/a"), item("/a/2", root: "/a")),
            result("cat-b", item("/a/3", root: "/a"), item("/b/1", root: "/b")),
        ]) { root in
            asked.append(root)
            return root
        }

        #expect(asked == ["/a", "/b"])
    }

    // `selections`: che cosa riceve il motore.

    private func selections(_ categories: [ConfirmationCategory], selected: Set<ConfirmationPosition>) -> [[String]] {
        ConfirmationRows.selections(categories) { selected.contains($0) }.map { $0.items.map(\.path) }
    }

    private var cacheAndModel: [ConfirmationCategory] {
        build([
            result("dev-caches", item("/u/.cache/huggingface", directory: true)),
            result("large-files", item("/u/.cache/huggingface/model.bin"), item("/u/Movies/raw.mov")),
        ])
    }

    @Test func aRowCoveredByASelectedFolderIsNotSent() {
        let sent = ConfirmationRows.selections(cacheAndModel) { _ in true }

        #expect(sent.map(\.categoryId) == ["dev-caches", "large-files"])
        #expect(sent.map { $0.items.map(\.path) } == [["/u/.cache/huggingface"], ["/u/Movies/raw.mov"]])
    }

    @Test func aRowWhoseFolderIsNotSelectedIsSentOnItsOwn() {
        #expect(selections(cacheAndModel, selected: [position(1, 0)]) == [["/u/.cache/huggingface/model.bin"]])
    }

    @Test func aGroupWithNothingToSendIsOmitted() {
        let sent = ConfirmationRows.selections(cacheAndModel) { $0 != position(1, 1) }

        #expect(sent.map(\.categoryId) == ["dev-caches"])
    }

    /// La copertura risale tutta la catena: il file sotto B è coperto da A anche se B è deselezionata.
    @Test func coverageFollowsTheWholeChain() {
        let chain = build([
            result("cat-a", item("/x/a", directory: true)),
            result("cat-b", item("/x/a/b", directory: true)),
            result("cat-c", item("/x/a/b/c.bin")),
        ])

        #expect(selections(chain, selected: [position(0, 0), position(2, 0)]) == [["/x/a"]])
        #expect(selections(chain, selected: [position(1, 0), position(2, 0)]) == [["/x/a/b"]])
    }

    /// Una posizione che `build` non produrrebbe mai: la riga resta indietro, è la direzione sicura.
    @Test func aRowWhoseContainerDoesNotExistIsNotSent() {
        let forged = [ConfirmationCategory(categoryId: "cat-a", rows: [
            ConfirmationRow(item: item("/x/a"), container: position(4, 0)),
            ConfirmationRow(item: item("/x/b"), container: position(0, 7)),
        ])]

        #expect(ConfirmationRows.selections(forged) { _ in false }.isEmpty)
        #expect(ConfirmationRows.selections(forged) { $0.category == 0 }.isEmpty)
    }

    /// La garanzia, su ogni combinazione di una catena, di una cartella sorella e di un file libero:
    /// nessuna voce inviata sta sotto un'altra voce inviata, e ogni voce selezionata è inviata o sta
    /// sotto una voce inviata.
    @Test func everySelectionSendsNoNestedRowsAndLosesNoSelectedRow() {
        let categories = build([
            result("cat-a", item("/x/a/b/c.bin"), item("/x/libero.iso")),
            result("cat-b", item("/x/a", directory: true), item("/x/sorella", directory: true)),
            result("cat-c", item("/x/a/b", directory: true), item("/x/sorella/f.bin")),
        ])
        let positions = categories.enumerated().flatMap { categoryIndex, category in
            category.rows.indices.map { position(categoryIndex, $0) }
        }
        func path(_ position: ConfirmationPosition) -> String {
            categories[position.category].rows[position.row].item.path
        }
        func isUnder(_ path: String, _ folder: String) -> Bool { path.hasPrefix(folder + "/") }

        for mask in 0..<(1 << positions.count) {
            let selected = Set(positions.indices.filter { mask & (1 << $0) != 0 }.map { positions[$0] })
            let sent = ConfirmationRows.selections(categories) { selected.contains($0) }.flatMap { $0.items.map(\.path) }

            for one in sent {
                #expect(!sent.contains { isUnder(one, $0) }, "maschera \(mask): \(one) inviata sotto un'altra voce inviata")
            }
            for chosen in selected.map(path) {
                #expect(sent.contains(chosen) || sent.contains { isUnder(chosen, $0) }, "maschera \(mask): \(chosen) persa")
            }
        }
    }
}
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationCleanupTests.swift`:

```swift
import Testing
@testable import CleanerCore

/// La garanzia del passo 3 dalle righe al disco (spec `2026-10-20-confirmation-containment-design.md`):
/// le righe si costruiscono con le root risolte da un vero `PathGuard`, la selezione passa da
/// `ConfirmationRows.selections` e la cancella un vero `CleanEngine`, su `InMemoryFileSystem`.
/// `~/.cache` è un collegamento a `~/Dati/cache`, e «File grandi» guarda `~/Dati`.
struct ConfirmationCleanupTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/.cache"
    private static let dataRoot = "/Users/tester/Dati"
    private static let folder = "/Users/tester/Dati/cache/huggingface"
    private static let model = "/Users/tester/Dati/cache/huggingface/hub/model.bin"
    private static let config = "/Users/tester/Dati/cache/huggingface/hub/config.json"

    private let fileSystem = InMemoryFileSystem()
    private let pathGuard: PathGuard

    init() throws {
        fileSystem.addFile(Self.model, size: 4_800)
        fileSystem.addFile(Self.config, size: 10)
        pathGuard = try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: fileSystem,
            links: FakeLinkInspector(targets: [Self.cacheRoot: "\(Self.dataRoot)/cache"]), homeDirectory: Self.home)
    }

    private var rows: [ConfirmationCategory] {
        ConfirmationRows.build(
            [
                CategoryScanResult(
                    categoryId: "dev-caches",
                    items: [ScanItem(path: "\(Self.cacheRoot)/huggingface", sizeBytes: 4_810, isDirectory: true, declaredRoot: Self.cacheRoot)],
                    totalBytes: 4_810, errors: [], exclusions: []),
                CategoryScanResult(
                    categoryId: "large-files",
                    items: [ScanItem(path: Self.model, sizeBytes: 4_800, isDirectory: false, declaredRoot: Self.dataRoot)],
                    totalBytes: 4_800, errors: [], exclusions: []),
            ],
            resolveRoot: pathGuard.resolvedRoot)
    }

    private func clean(selected: Set<ConfirmationPosition>) async -> CleanReport {
        let engine = CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: FixedWallClock(now: utc(2026, 10, 20, 12)))
        return await engine.clean(ConfirmationRows.selections(rows) { selected.contains($0) }, progress: nil, journal: nil)
    }

    @Test func theModelIsBoundToTheFolderItLivesIn() {
        #expect(rows.map { $0.rows.map(\.container) } == [[nil], [ConfirmationPosition(category: 0, row: 0)]])
    }

    /// Cartella spuntata, modello deselezionato: il modello sparisce con la cartella (per questo il
    /// passo 3 lo mostra spuntato), una sola voce cancellata e byte contati una volta.
    @Test func aTickedFolderTakesTheModelWithItAndCountsItOnce() async {
        let report = await clean(selected: [ConfirmationPosition(category: 0, row: 0)])

        #expect(!fileSystem.fileExists(Self.model))
        #expect(!fileSystem.directoryExists(Self.folder))
        #expect(report.itemsDeleted == 1)
        #expect(report.bytesFreed == 4_810)
        #expect(report.errors.isEmpty)
    }

    /// Cartella e modello entrambi spuntati: prima del contenimento il modello partiva da solo dopo la
    /// cartella e finiva fra gli errori con ENOENT, e il totale contava due volte i suoi byte.
    @Test func aTickedFolderAndATickedModelInsideItAreDeletedOnce() async {
        let report = await clean(selected: [ConfirmationPosition(category: 0, row: 0), ConfirmationPosition(category: 1, row: 0)])

        #expect(!fileSystem.directoryExists(Self.folder))
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
        #expect(report.errors.isEmpty)
        #expect(report.bytesFreed == 4_810)
    }

    /// Cartella deselezionata: si cancella solo ciò che è spuntato, e il resto della cartella resta.
    @Test func anUntickedFolderKeepsEverythingButTheTickedModel() async {
        let report = await clean(selected: [ConfirmationPosition(category: 1, row: 0)])

        #expect(!fileSystem.fileExists(Self.model))
        #expect(fileSystem.fileExists(Self.config))
        #expect(report.itemsDeleted == 1)
        #expect(report.bytesFreed == 4_800)
    }

    @Test func nothingTickedDeletesNothing() async {
        let report = await clean(selected: [])

        #expect(fileSystem.fileExists(Self.model))
        #expect(fileSystem.fileExists(Self.config))
        #expect(report.itemsDeleted == 0)
    }
}
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione».
Expected: errori come questi:

- `error: cannot find 'ConfirmationPosition' in scope`
- `error: cannot find type 'ConfirmationPosition' in scope`
- `error: cannot infer key path type from context; consider explicitly specifying a root type`
- `error: extra argument 'resolveRoot' in call`
- `error: type 'ConfirmationRows' has no member 'selections'`
- `error: value of type 'ConfirmationCategory' has no member 'rows'`

- [ ] **Step 3: Implementazione**

Sostituire l'intero contenuto di `MjmCleanerKit/Sources/CleanerCore/Cleaning/ConfirmationRows.swift` con:

```swift
import Foundation

/// Dove sta una riga nel risultato di `ConfirmationRows.build`: l'indice del gruppo e quello della
/// riga dentro il gruppo.
public struct ConfirmationPosition: Sendable, Equatable, Hashable {
    public let category: Int
    public let row: Int

    public init(category: Int, row: Int) {
        self.category = category
        self.row = row
    }
}

/// Una riga del passo di conferma. `container` è la riga-cartella più vicina che contiene questa
/// voce, in qualunque gruppo: cancellare quella cartella cancella anche questa voce.
public struct ConfirmationRow: Sendable, Equatable {
    public let item: ScanItem
    public let container: ConfirmationPosition?

    public init(item: ScanItem, container: ConfirmationPosition?) {
        self.item = item
        self.container = container
    }
}

/// Le righe di una categoria dopo la deduplicazione: una categoria il cui contenuto è stato
/// interamente riassorbito da una precedente non compare, non avrebbe righe da mostrare.
public struct ConfirmationCategory: Sendable, Equatable {
    public let categoryId: String
    public let rows: [ConfirmationRow]

    public init(categoryId: String, rows: [ConfirmationRow]) {
        self.categoryId = categoryId
        self.rows = rows
    }

    public var items: [ScanItem] { rows.map(\.item) }
}

/// Le righe del passo di conferma: un percorso, una riga, in tutto il passo; per ogni riga, la
/// cartella proposta che la contiene (spec `2026-10-20-confirmation-containment-design.md`).
public enum ConfirmationRows {
    /// Deduplica GLOBALMENTE: lo stesso percorso proposto da due categorie (cartelle dei file grandi
    /// sovrapposte a una root del catalogo) produceva due righe, il totale lo contava due volte e
    /// deselezionarlo in una categoria non lo escludeva dall'altra. Si tiene il primo incontrato,
    /// nell'ordine dei risultati: stesso file, stessa dimensione.
    ///
    /// Poi lega ogni riga alla riga-cartella più vicina che la contiene, in qualunque gruppo e in
    /// qualunque ordine: con «File grandi» su `~`, un modello sotto `~/.cache/huggingface` sta nella
    /// cartella che «Cache di sviluppo» propone, e cancellarla cancella anche il modello.
    ///
    /// I percorsi si confrontano come li cancellerà il motore: riportati sulla root risolta da
    /// `resolveRoot` (chiamato una volta per root) e ripiegati come APFS. Riconoscere un
    /// contenimento in più è sicuro (la voce appare spuntata e non parte); riconoscerne uno in meno
    /// mostrerebbe deselezionata una voce che la cartella cancella.
    public static func build(_ results: [CategoryScanResult], resolveRoot: (String) -> String) -> [ConfirmationCategory] {
        var resolvedRoots: [[UInt8]: String] = [:]
        func key(_ item: ScanItem) -> String {
            let rootKey = Array(item.declaredRoot.utf8)
            let resolved: String
            if let known = resolvedRoots[rootKey] {
                resolved = known
            } else {
                resolved = resolveRoot(item.declaredRoot)
                resolvedRoots[rootKey] = resolved
            }
            let rewritten = CleanEngine.rewriteToResolvedRoot(item.path, declaredRoot: item.declaredRoot, resolvedRoot: resolved)
            return comparisonKey(rewritten)
        }

        var seenKeys = Set<String>()
        var kept: [(categoryId: String, entries: [(item: ScanItem, key: String)])] = []
        for result in results {
            var entries: [(item: ScanItem, key: String)] = []
            for item in result.items {
                let itemKey = key(item)
                if seenKeys.insert(itemKey).inserted {
                    entries.append((item, itemKey))
                }
            }
            if !entries.isEmpty {
                kept.append((result.categoryId, entries))
            }
        }

        // Solo cartelle e pacchetti contengono: un file non contiene mai nulla.
        var directories: [String: ConfirmationPosition] = [:]
        for (categoryIndex, category) in kept.enumerated() {
            for (rowIndex, entry) in category.entries.enumerated() where entry.item.isDirectory {
                directories[entry.key] = ConfirmationPosition(category: categoryIndex, row: rowIndex)
            }
        }

        return kept.map { category in
            ConfirmationCategory(
                categoryId: category.categoryId,
                rows: category.entries.map { ConfirmationRow(item: $0.item, container: nearestContainer($0.key, directories)) })
        }
    }

    /// Le voci da consegnare al motore: una riga parte se è selezionata e nessuna riga della sua
    /// catena di cartelle lo è. Così la selezione non contiene mai una voce sotto un'altra voce
    /// della stessa selezione: niente byte contati due volte, niente ENOENT su un file già
    /// cancellato con la sua cartella.
    public static func selections(
        _ categories: [ConfirmationCategory],
        isSelected: (ConfirmationPosition) -> Bool
    ) -> [CategorySelection] {
        func isCovered(_ row: ConfirmationRow) -> Bool {
            var next = row.container
            while let position = next {
                if isSelected(position) { return true }
                // Una posizione che non esiste non viene da `build`: la riga non parte, è la
                // direzione sicura.
                guard categories.indices.contains(position.category),
                      categories[position.category].rows.indices.contains(position.row) else { return true }
                next = categories[position.category].rows[position.row].container
            }
            return false
        }

        return categories.enumerated().compactMap { categoryIndex, category in
            let items = category.rows.enumerated()
                .filter { rowIndex, row in
                    isSelected(ConfirmationPosition(category: categoryIndex, row: rowIndex)) && !isCovered(row)
                }
                .map(\.element.item)
            return items.isEmpty ? nil : CategorySelection(categoryId: category.categoryId, items: items)
        }
    }

    /// La chiave di confronto: ripiegamento completo delle maiuscole, come APFS («ß» e «ss», il segno
    /// Kelvin e «k»). Più ampio di `PathText.folded`, che segue OrdinalIgnoreCase per il guard: qui
    /// unire di più è la direzione sicura. Le grafie NFC e NFD non vanno scomposte a parte: chiavi
    /// `String` in `Set` e `Dictionary` si confrontano per equivalenza canonica.
    static func comparisonKey(_ path: String) -> String {
        path.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Risale gli antenati della chiave tagliando all'ultima «/», per scalari: un segmento che
    /// comincia con un segno combinante formerebbe un solo carattere con la «/» che lo precede.
    private static func nearestContainer(_ key: String, _ directories: [String: ConfirmationPosition]) -> ConfirmationPosition? {
        var scalars = key.unicodeScalars[...]
        while let slash = scalars.lastIndex(of: "/") {
            scalars = scalars[..<slash]
            if let position = directories[String(String.UnicodeScalarView(scalars))] {
                return position
            }
        }
        return nil
    }
}
```

In `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift`, sostituire:

```swift
        nodes = ConfirmationRows.build(results).map { row in
```

con:

```swift
        nodes = ConfirmationRows.build(results, resolveRoot: environment.roots.resolvedRoot).map { row in
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package».
Expected: `CleanerCoreTests` **707** test in 62 suite, `CleanerFeaturesTests` **232** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Cleaning/ConfirmationRows.swift MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationRowsTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationCleanupTests.swift
git commit -m "$(cat <<'EOF'
feat(cleanup): bind confirmation rows to the proposed folder that contains them

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: caselle, note e selezione al passo 3

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift` (intero file)
- Modify: `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`

**Interfaces:**
- Consumes: `ConfirmationRows.build(_:resolveRoot:)`, `ConfirmationRows.selections(_:isSelected:)`, `ConfirmationPosition`, `ConfirmationCategory.rows` (Task 2); `AppEnvironment.roots`, `FakeRootResolver`, `makeEnvironment(roots:)` (Task 1); `Formatting.plural`, `Formatting.integer`.
- Produces:
  - `PathNode`: `public internal(set) var container: PathNode?`, `public internal(set) var containerGroupName: String`, `public internal(set) var containsText: String`, `public var isCovered: Bool`, `public var isChecked: Bool`, `var isSentOnItsOwn: Bool` (interna), `public var containmentText: String`;
  - `CategoryNode`: `allSelected` con la nuova semantica, `public var canSelectAll: Bool`, `public var coveredText: String`;
  - nei test, `makeItem(_:size:root:directory:)` con `directory: Bool = false`.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift`, sostituire:

```swift
func makeItem(_ path: String, size: Int64 = 100, root: String = "/Users/tester/Library/Caches") -> ScanItem {
    ScanItem(path: path, sizeBytes: size, isDirectory: false, declaredRoot: root)
}
```

con:

```swift
func makeItem(_ path: String, size: Int64 = 100, root: String = "/Users/tester/Library/Caches", directory: Bool = false) -> ScanItem {
    ScanItem(path: path, sizeBytes: size, isDirectory: directory, declaredRoot: root)
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`, sostituire:

```swift
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E"])
            == "A, B, C, D, E in esecuzione: le loro cache potrebbero rigenerarsi subito.")
    }
}
```

con:

```swift
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E"])
            == "A, B, C, D, E in esecuzione: le loro cache potrebbero rigenerarsi subito.")
    }

    // Voci contenute in una cartella proposta altrove (spec `2026-10-20-confirmation-containment-design.md`).

    private static let megabyte: Int64 = 1_048_576

    private let nested = [
        makeCategory("dev-caches", name: "Cache di sviluppo"),
        makeCategory("large-files", name: "File grandi", itemsSelectedByDefault: false),
    ]

    /// Il caso segnalato: con «File grandi» su `~`, il modello sta nella cache di Hugging Face.
    private var nestedResults: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "dev-caches",
                items: [
                    makeItem("/Users/tester/.cache/huggingface", size: 6 * Self.megabyte, root: "/Users/tester/.cache", directory: true),
                    makeItem("/Users/tester/.cache/pip", size: Self.megabyte, root: "/Users/tester/.cache", directory: true),
                ],
                totalBytes: 7 * Self.megabyte, errors: [], exclusions: []),
            CategoryScanResult(
                categoryId: "large-files",
                items: [
                    makeItem("/Users/tester/Movies/raw.mov", size: 3 * Self.megabyte, root: "/Users/tester"),
                    makeItem("/Users/tester/.cache/huggingface/hub/model.bin", size: 5 * Self.megabyte, root: "/Users/tester"),
                ],
                totalBytes: 8 * Self.megabyte, errors: [], exclusions: []),
        ]
    }

    @Test func aRowInsideATickedFolderAppearsTickedLockedAndExplained() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: nestedResults)
        let modelRow = model.nodes[1].paths[1]

        #expect(!modelRow.isSelected)
        #expect(modelRow.isCovered)
        #expect(modelRow.isChecked)
        #expect(modelRow.containmentText
            == "Inclusa in /Users/tester/.cache/huggingface (Cache di sviluppo): si elimina con la cartella.")
        #expect(model.nodes[1].paths[0].containmentText == "")
        #expect(!model.nodes[1].paths[0].isChecked)
        #expect(model.nodes.map { $0.paths.map(\.containsText) } == [["Contiene anche 1 voce di File grandi.", ""], ["", ""]])
        #expect(model.totalText == "7 MB · 2 elementi")
    }

    @Test func untickingTheFolderFreesTheRowWithItsOwnChoice() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: nestedResults)
        let folder = model.nodes[0].paths[0]
        let modelRow = model.nodes[1].paths[1]

        folder.isSelected = false
        #expect(!modelRow.isCovered)
        #expect(!modelRow.isChecked)
        #expect(modelRow.containmentText == "Inclusa in /Users/tester/.cache/huggingface (Cache di sviluppo).")
        #expect(model.totalText == "1 MB · 1 elemento")

        modelRow.isSelected = true
        #expect(model.totalText == "6 MB · 2 elementi")

        folder.isSelected = true
        #expect(modelRow.isChecked)
        #expect(model.totalText == "7 MB · 2 elementi")
    }

    @Test func selectAllLeavesCoveredRowsToTheirFolder() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: nestedResults)
        let large = model.nodes[1]

        #expect(!large.allSelected)
        #expect(large.canSelectAll)
        #expect(large.coveredText == "1 voce è dentro una cartella spuntata e si elimina con quella.")

        large.allSelected = true
        #expect(large.paths.map(\.isSelected) == [true, false])
        #expect(large.allSelected)

        large.allSelected = false
        #expect(large.paths.map(\.isSelected) == [false, false])
        #expect(large.paths.map(\.isChecked) == [false, true])
        #expect(!large.allSelected)

        model.nodes[0].paths[0].isSelected = false
        #expect(large.coveredText == "")
        #expect(model.nodes[0].coveredText == "")
    }

    @Test func aGroupMadeOnlyOfCoveredRowsCannotSelectAll() throws {
        let results = [
            nestedResults[0],
            CategoryScanResult(
                categoryId: "large-files",
                items: [
                    makeItem("/Users/tester/.cache/huggingface/hub/model.bin", size: 5 * Self.megabyte, root: "/Users/tester"),
                    makeItem("/Users/tester/.cache/pip/wheels/torch.whl", size: Self.megabyte, root: "/Users/tester"),
                ],
                totalBytes: 6 * Self.megabyte, errors: [], exclusions: []),
        ]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: results)
        let large = model.nodes[1]

        #expect(!large.canSelectAll)
        #expect(large.allSelected)
        #expect(large.coveredText == "2 voci sono dentro cartelle spuntate e si eliminano con quelle.")

        large.allSelected = false
        #expect(large.paths.map(\.isChecked) == [true, true])
    }

    /// Una cartella e una voce che contiene nello stesso gruppo, con la voce prima della cartella:
    /// «deseleziona tutte» raggiunge anche la voce che la cartella libera.
    @Test func selectAllReachesTheRowsThatItsOwnFolderFrees() throws {
        let results = [CategoryScanResult(
            categoryId: "large-files",
            items: [
                makeItem("/Users/tester/VM/Windows.pvm/disk.hdd", size: 4 * Self.megabyte, root: "/Users/tester"),
                makeItem("/Users/tester/VM/Windows.pvm", size: 5 * Self.megabyte, root: "/Users/tester", directory: true),
            ],
            totalBytes: 9 * Self.megabyte, errors: [], exclusions: [])]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: results)
        let large = model.nodes[0]
        #expect(large.paths[1].containsText == "Contiene anche 1 voce di File grandi.")

        large.paths[0].isSelected = true
        large.paths[1].isSelected = true
        #expect(large.allSelected)

        large.allSelected = false
        #expect(large.paths.map(\.isSelected) == [false, false])
        #expect(!model.canDelete)
    }

    @Test func deleteSendsTheFolderAndNotTheRowsItCovers() async throws {
        let clean = FakeClean()
        let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: nested, results: nestedResults)
        model.nodes[1].paths[0].isSelected = true
        model.nodes[1].paths[1].isSelected = true

        await model.delete()

        #expect(clean.selections.first?.map(\.categoryId) == ["dev-caches", "large-files"])
        #expect(clean.selections.first?.map { $0.items.map(\.path) } == [
            ["/Users/tester/.cache/huggingface", "/Users/tester/.cache/pip"], ["/Users/tester/Movies/raw.mov"],
        ])
    }

    /// Le root passano dal risolutore dell'ambiente: `~/.cache` porta a `~/Dati/cache`, dove «File
    /// grandi» ha trovato il modello.
    @Test func containmentUsesTheRootsOfTheEnvironment() throws {
        let results = [
            nestedResults[0],
            CategoryScanResult(
                categoryId: "large-files",
                items: [makeItem("/Users/tester/Dati/cache/huggingface/model.bin", size: 5 * Self.megabyte, root: "/Users/tester/Dati")],
                totalBytes: 5 * Self.megabyte, errors: [], exclusions: []),
        ]
        let roots = FakeRootResolver(targets: ["/Users/tester/.cache": "/Users/tester/Dati/cache"])
        let model = ConfirmStepModel(environment: try makeEnvironment(roots: roots), navigation: nil, categories: nested, results: results)

        #expect(model.nodes[1].paths[0].isCovered)
        #expect(!ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: nested, results: results).nodes[1].paths[0].isCovered)
    }

    /// La garanzia vista dall'utente, su ogni combinazione di una catena di tre cartelle e di un file
    /// libero: una casella vuota non sta mai sotto una voce inviata al motore, e una casella spuntata
    /// è inviata o sta sotto una voce inviata.
    @Test func theTicksOnScreenMatchWhatIsDeleted() async throws {
        let groups = [makeCategory("cat-1"), makeCategory("cat-2"), makeCategory("cat-3")]
        let results = [
            CategoryScanResult(
                categoryId: "cat-1", items: [makeItem("/Users/tester/x/a/b/c.bin"), makeItem("/Users/tester/x/libero.iso")],
                totalBytes: 200, errors: [], exclusions: []),
            CategoryScanResult(categoryId: "cat-2", items: [makeItem("/Users/tester/x/a", directory: true)], totalBytes: 100, errors: [], exclusions: []),
            CategoryScanResult(categoryId: "cat-3", items: [makeItem("/Users/tester/x/a/b", directory: true)], totalBytes: 100, errors: [], exclusions: []),
        ]
        func isUnder(_ path: String, _ folder: String) -> Bool { path.hasPrefix(folder + "/") }

        for mask in 0..<16 {
            let clean = FakeClean()
            let model = ConfirmStepModel(environment: try makeEnvironment(clean: clean), navigation: nil, categories: groups, results: results)
            let rows = model.nodes.flatMap(\.paths)
            for (index, row) in rows.enumerated() {
                row.isSelected = mask & (1 << index) != 0
            }

            await model.delete()
            let sent = clean.selections.first?.flatMap { $0.items.map(\.path) } ?? []

            for row in rows {
                let deleted = sent.contains(row.path) || sent.contains { isUnder(row.path, $0) }
                #expect(deleted == row.isChecked, "maschera \(mask): \(row.path)")
            }
        }
    }
}
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione».
Expected: errori come questi:

- `error: value of type 'CategoryNode' has no member 'canSelectAll'`
- `error: value of type 'CategoryNode' has no member 'coveredText'`
- `error: value of type 'PathNode' has no member 'containmentText'`
- `error: value of type 'PathNode' has no member 'containsText'`
- `error: value of type 'PathNode' has no member 'isChecked'`
- `error: value of type 'PathNode' has no member 'isCovered'`

- [ ] **Step 3: Implementazione**

Sostituire l'intero contenuto di `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift` con:

```swift
import CleanerCore
import Observation

/// Una riga selezionabile: un singolo `ScanItem`, non la root della regola che lo ha prodotto.
/// Raggruppare per `declaredRoot` mostrerebbe una sola casella per migliaia di elementi (la root
/// delle regole a svuotamento — `~/Library/Caches`, `$TMPDIR` — sopravvive comunque alla pulizia,
/// quindi quella casella nominerebbe qualcosa che non verrà mai cancellato) e renderebbe la
/// granularità di deselezione qui identica a quella del passo 1, vanificando questo passo come
/// rete di sicurezza.
@MainActor
@Observable
public final class PathNode: Identifiable {
    public let item: ScanItem

    /// La scelta della voce stessa. Ciò che parte davvero dipende anche dalla cartella che la
    /// contiene: vedi `isCovered`.
    public var isSelected: Bool

    /// La riga-cartella più vicina che contiene questa voce, in qualunque gruppo, e il nome di quel
    /// gruppo. Le imposta il modello dopo aver creato tutti i nodi (spec
    /// `2026-10-20-confirmation-containment-design.md`).
    public internal(set) var container: PathNode?
    public internal(set) var containerGroupName = ""

    /// Sulla riga di una cartella: quante voci, e di quali gruppi, contiene direttamente.
    public internal(set) var containsText = ""

    init(item: ScanItem, isSelected: Bool) {
        self.item = item
        self.isSelected = isSelected
    }

    public var path: String { item.path }
    public var sizeBytes: Int64 { item.sizeBytes }
    public var sizeText: String { Formatting.bytes(item.sizeBytes) }

    /// Vero se una cartella della catena che contiene questa voce è selezionata: la voce si cancella
    /// con quella, qualunque sia la sua casella. È la regola di `ConfirmationRows.selections`.
    public var isCovered: Bool {
        var next = container
        while let node = next {
            if node.isSelected { return true }
            next = node.container
        }
        return false
    }

    /// Ciò che mostra la casella: spuntata se la voce parte da sola o con la sua cartella.
    public var isChecked: Bool { isSelected || isCovered }

    /// La voce arriva al motore da sola: selezionata e non già compresa in una cartella che parte.
    var isSentOnItsOwn: Bool { isSelected && !isCovered }

    /// La nota sotto il percorso di una voce contenuta, e il suggerimento per VoiceOver.
    public var containmentText: String {
        guard let container else { return "" }
        return isCovered
            ? String(localized: "Inclusa in \(container.path) (\(containerGroupName)): si elimina con la cartella.", bundle: .module)
            : String(localized: "Inclusa in \(container.path) (\(containerGroupName)).", bundle: .module)
    }
}

@MainActor
@Observable
public final class CategoryNode: Identifiable {
    public let categoryId: String
    public let displayName: String
    public let paths: [PathNode]

    /// Il totale della categoria, visibile a colpo d'occhio prima di espandere: conteggio e
    /// dimensione di tutte le righe trovate, selezionate o no.
    public let summaryText: String

    /// Vero per i gruppi di dati reali (Download, File grandi): le voci partono deselezionate.
    public let itemsStartDeselected: Bool

    init(categoryId: String, displayName: String, items: [ScanItem], itemsSelectedByDefault: Bool) {
        self.categoryId = categoryId
        self.displayName = displayName
        paths = items.map { PathNode(item: $0, isSelected: itemsSelectedByDefault) }
        itemsStartDeselected = !itemsSelectedByDefault
        let noun = Formatting.plural(items.count, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        summaryText = "\(Formatting.integer(items.count)) \(noun) · \(Formatting.bytes(SafeSum.total(items.map(\.sizeBytes))))"
    }

    /// La casella «Seleziona tutte le voci»: vera se il gruppo ha voci e ogni casella appare
    /// spuntata; impostarla cambia solo le voci libere, perché una voce coperta la decide la sua
    /// cartella. È calcolata, quindi resta allineata alle caselle delle singole voci senza stato da
    /// sincronizzare.
    public var allSelected: Bool {
        get { !paths.isEmpty && paths.allSatisfy(\.isChecked) }
        set {
            // Deselezionare una cartella del gruppo libera le voci che conteneva, anche se vengono
            // prima nell'elenco: si ripete finché nessuna voce libera cambia. Ogni passata ne
            // cambia almeno una verso `newValue` e nessuna torna indietro.
            var changed = true
            while changed {
                changed = false
                for path in paths where !path.isCovered && path.isSelected != newValue {
                    path.isSelected = newValue
                    changed = true
                }
            }
        }
    }

    /// Falso se ogni voce del gruppo è coperta da una cartella spuntata: la casella di gruppo non
    /// avrebbe nulla da cambiare.
    public var canSelectAll: Bool { paths.contains { !$0.isCovered } }

    /// La riga sotto l'avviso del gruppo quando alcune voci si cancellano con una cartella.
    public var coveredText: String {
        let count = paths.count(where: \.isCovered)
        switch count {
        case 0:
            return ""
        case 1:
            return String(localized: "1 voce è dentro una cartella spuntata e si elimina con quella.", bundle: .module)
        default:
            return String(localized: "\(Formatting.integer(count)) voci sono dentro cartelle spuntate e si eliminano con quelle.", bundle: .module)
        }
    }

    /// Il nome della casella di gruppo per VoiceOver, che altrimenti non saprebbe di quale gruppo.
    public var selectAllAccessibilityLabel: String {
        String(localized: "Seleziona tutte le voci di \(displayName)", bundle: .module)
    }
}

/// Porting di `ConfirmStepViewModel`: passo 3, anteprima con deselezioni puntuali ed eliminazione.
@MainActor
@Observable
public final class ConfirmStepModel {
    /// Oltre questo numero di nomi l'avviso diventa illeggibile proprio nel passo in cui l'utente deve decidere.
    private static let maxRunningAppNamesShown = 5

    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private weak var navigation: (any CleanupNavigating)?
    @ObservationIgnored private var deleteTask: Task<CleanReport, Never>?

    /// Le righe del Core, allineate per indice a `nodes`: `delete()` ne ricava la selezione.
    @ObservationIgnored private let rows: [ConfirmationCategory]

    public let nodes: [CategoryNode]

    /// Elenco di ciò che le protezioni hanno tolto d'ufficio: se un totale non torna, qui se ne
    /// trova il motivo.
    public let exclusionsText: String

    public private(set) var isDeleting = false

    /// Aggiornato dall'avanzamento reale del motore di pulizia durante l'eliminazione.
    public private(set) var deleteProgressText = ""

    /// Vuoto finché la sonda non ha risposto: viene popolato in modo asincrono, fuori dal main
    /// actor, perché avvia un processo esterno (`ps`) che in uno scenario patologico può impiegare
    /// fino a una decina di secondi. La schermata resta utilizzabile nel frattempo.
    public private(set) var runningAppsWarning = ""

    @ObservationIgnored public private(set) var runningAppsCheck: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        navigation: (any CleanupNavigating)?,
        categories: [CleanupCategory],
        results: [CategoryScanResult]
    ) {
        self.environment = environment
        self.navigation = navigation

        // Una riga per PERCORSO, non per ScanItem, e la deduplicazione è GLOBALE a tutto il passo:
        // due regole, anche di categorie diverse, possono coprire lo stesso file. Ogni riga sa quale
        // cartella proposta la contiene, confrontando le root come le risolve il motore. La logica
        // vive nel Core (ConfirmationRows), pura e testata; qui si trasforma in nodi.
        let rows = ConfirmationRows.build(results, resolveRoot: environment.roots.resolvedRoot)
        self.rows = rows
        nodes = rows.map { row in
            let category = categories.first { FeatureText.same($0.id, row.categoryId) }
            // Una categoria assente dal catalogo oggi non capita; se capitasse, le sue voci partono
            // deselezionate: è la direzione sicura.
            return CategoryNode(
                categoryId: row.categoryId, displayName: category?.displayName ?? row.categoryId, items: row.items,
                itemsSelectedByDefault: category?.itemsSelectedByDefault ?? false)
        }
        Self.link(nodes, rows)

        let exclusions = results.flatMap(\.exclusions)
        if exclusions.isEmpty {
            exclusionsText = ""
        } else {
            let noun = Formatting.plural(
                exclusions.count,
                String(localized: "elemento escluso", bundle: .module),
                String(localized: "elementi esclusi", bundle: .module))
            let header = String(localized: "\(String(exclusions.count)) \(noun) dalle protezioni:", bundle: .module)
            let lines = exclusions.prefix(5).map { "· \($0.path) — \($0.reason)" }
            exclusionsText = ([header] + lines).joined(separator: "\n")
        }

        let scannedPaths = Array(results.lazy.flatMap(\.items).prefix(2000).map(\.path))
        runningAppsCheck = Task { await self.computeRunningAppsWarning(scannedPaths) }
    }

    /// Le voci che arrivano al motore da sole: una voce coperta è già nei byte della sua cartella.
    private var selectedNodes: [PathNode] {
        nodes.flatMap { $0.paths.filter(\.isSentOnItsOwn) }
    }

    public var totalText: String {
        let selected = selectedNodes
        let noun = Formatting.plural(selected.count, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        return "\(Formatting.bytes(SafeSum.total(selected.map(\.sizeBytes)))) · \(Formatting.integer(selected.count)) \(noun)"
    }

    public var canDelete: Bool {
        !isDeleting && nodes.contains { $0.paths.contains(where: \.isSelected) }
    }

    public var canCancelDelete: Bool { isDeleting }

    public func delete() async {
        guard canDelete else { return }
        isDeleting = true

        // La regola che decide cosa parte è una sola, nel Core: una voce coperta da una cartella
        // selezionata non parte da sola.
        let nodes = nodes
        let selections = ConfirmationRows.selections(rows) { Self.node(at: $0, in: nodes)?.isSelected ?? false }

        // Il diario si apre prima della pulizia e passa al passo 4, che lo scarta solo dopo aver
        // scritto il log di sessione (spec §8.2): dopo un arresto resta leggibile in logs/.
        let journal = environment.sessionLog.openJournal(startedAt: environment.clock.now)
        let relay = ProgressRelay<CleanProgress> { [weak self] in self?.applyDeleteProgress($0) }
        let clean = environment.clean
        let report = relay.report
        let task = Task { await clean.clean(selections, progress: report, journal: journal) }
        deleteTask = task

        // CleanEngine non lancia sull'annullamento: restituisce un resoconto parziale, che va
        // comunque al passo 4 e comunque nello storico — ciò che è già stato cancellato deve
        // risultare, annullamento o non annullamento.
        let result = await task.value
        await relay.finish()
        deleteTask = nil

        navigation?.showDone(result, journal: journal)
        isDeleting = false
    }

    public func cancelDelete() {
        deleteTask?.cancel()
    }

    /// Deliberatamente non «Indietro»: ricomincia dal passo 1 (la selezione resta ricordata nelle
    /// impostazioni) invece di tornare al passo 2 conservando questa analisi. Durante l'eliminazione
    /// non fa nulla: si resta sul passo, dove c'è «Interrompi».
    public func restart() {
        guard !isDeleting else { return }
        navigation?.startOver()
    }

    private static func node(at position: ConfirmationPosition, in nodes: [CategoryNode]) -> PathNode? {
        guard nodes.indices.contains(position.category) else { return nil }
        let paths = nodes[position.category].paths
        return paths.indices.contains(position.row) ? paths[position.row] : nil
    }

    /// Lega ogni nodo alla cartella che lo contiene e scrive, sulla riga della cartella, quante voci
    /// di ciascun gruppo contiene direttamente («Contiene anche 1 voce di File grandi.»).
    private static func link(_ nodes: [CategoryNode], _ rows: [ConfirmationCategory]) {
        var contained: [ObjectIdentifier: [Int: Int]] = [:]
        for (categoryIndex, category) in rows.enumerated() {
            for (rowIndex, row) in category.rows.enumerated() {
                guard let position = row.container,
                      let child = node(at: ConfirmationPosition(category: categoryIndex, row: rowIndex), in: nodes),
                      let container = node(at: position, in: nodes),
                      nodes.indices.contains(position.category) else { continue }
                child.container = container
                child.containerGroupName = nodes[position.category].displayName
                contained[ObjectIdentifier(container), default: [:]][categoryIndex, default: 0] += 1
            }
        }

        for category in nodes {
            for path in category.paths {
                guard let counts = contained[ObjectIdentifier(path)] else { continue }
                path.containsText = counts.keys.sorted().compactMap { groupIndex -> String? in
                    guard let count = counts[groupIndex], nodes.indices.contains(groupIndex) else { return nil }
                    let noun = Formatting.plural(count, String(localized: "voce", bundle: .module), String(localized: "voci", bundle: .module))
                    return String(localized: "Contiene anche \(Formatting.integer(count)) \(noun) di \(nodes[groupIndex].displayName).", bundle: .module)
                }
                .joined(separator: " ")
            }
        }
    }

    private func applyDeleteProgress(_ progress: CleanProgress) {
        let noun = Formatting.plural(progress.itemsTotal, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        deleteProgressText = "\(Formatting.integer(progress.itemsDone)) / \(Formatting.integer(progress.itemsTotal)) \(noun) · \(Formatting.bytes(progress.bytesFreed))"
    }

    /// Un fallimento della sonda non deve mai impedire la pulizia: l'avviso resta vuoto (la sonda
    /// del Core non lancia).
    private func computeRunningAppsWarning(_ scannedPaths: [String]) async {
        let affected = await environment.runningApps.affectedApps(scannedPaths)
        runningAppsWarning = Self.runningAppsText(affected)
    }

    static func runningAppsText(_ affected: [String]) -> String {
        guard !affected.isEmpty else { return "" }

        let shown = affected.prefix(maxRunningAppNamesShown).joined(separator: ", ")
        let remaining = affected.count - maxRunningAppNamesShown
        let suffix = switch remaining {
        case ...0: ""
        case 1: String(localized: " e un'altra", bundle: .module)
        default: String(localized: " e altre \(String(remaining))", bundle: .module)
        }

        let cacheClause = affected.count == 1
            ? String(localized: "la sua cache potrebbe rigenerarsi subito", bundle: .module)
            : String(localized: "le loro cache potrebbero rigenerarsi subito", bundle: .module)

        return String(localized: "\(shown)\(suffix) in esecuzione: \(cacheClause).", bundle: .module)
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package».
Expected: `CleanerCoreTests` **707** test in 62 suite, `CleanerFeaturesTests` **240** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift
git commit -m "$(cat <<'EOF'
feat(cleanup): show items inside a ticked folder as included in it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: vista del passo 3, demo e README

**Files:**
- Modify: `MjmCleaner/Cleanup/ConfirmStepView.swift` (intero file)
- Modify: `MjmCleaner/Demo/DemoData.swift`
- Modify: `MjmCleaner/Demo/DemoServices.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `PathNode.isChecked`, `isCovered`, `isSelected`, `containmentText`, `containsText`; `CategoryNode.coveredText`, `canSelectAll` (Task 3); `OptionalText` (`MjmCleaner/Shell/PageComponents.swift`).
- Produces: nessuna interfaccia nuova.

Questo task non ha test unitari: la vista si verifica con la build e con la lettura del codice, la demo con gli screenshot che il controller cattura solo con il consenso dell'utente.

- [ ] **Step 1: Vista**

Sostituire l'intero contenuto di `MjmCleaner/Cleanup/ConfirmStepView.swift` con:

```swift
import CleanerFeatures
import SwiftUI

/// Passo 3 (`ConfirmStepView`): ogni percorso da eliminare, raggruppato per categoria, con le
/// deselezioni puntuali. «Elimina» parte da un `Task` non legato alla vista: un cambio di vista
/// non annulla la pulizia, la ferma solo «Interrompi» (`cancelDelete()`).
struct ConfirmStepView: View {
    let model: ConfirmStepModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Verifica prima di eliminare", subtitle: model.totalText)
                ForEach(model.nodes) { node in
                    CategoryNodeView(node: node)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            // Le caselle si fermano, lo scorrimento no.
            .disabled(model.isDeleting)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Banner(text: String(localized: "Eliminazione definitiva: questi file non finiscono nel Cestino e non sono recuperabili."))
                OptionalText(text: model.runningAppsWarning)
                OptionalText(text: model.exclusionsText)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.background)
        }
        .actionBar {
            if model.isDeleting {
                Text(model.deleteProgressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer()
            Button("Ricomincia", action: model.restart)
                .disabled(model.isDeleting)
            if model.canCancelDelete {
                Button("Interrompi", action: model.cancelDelete)
            }
            Button(role: .destructive) {
                Task { await model.delete() }
            } label: {
                Text("Elimina \(model.totalText)")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!model.canDelete)
        }
    }
}

private struct CategoryNodeView: View {
    @Bindable var node: CategoryNode
    @State private var isExpanded = true

    var body: some View {
        CollapsibleCard(items: node.paths, isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                Text(node.displayName)
                    .fontWeight(.semibold)
                Text(node.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            if node.itemsStartDeselected {
                Text("Dati reali: le voci partono deselezionate. Spunta solo ciò che vuoi eliminare.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            OptionalText(text: node.coveredText)
            Toggle("Seleziona tutte le voci", isOn: $node.allSelected)
                .toggleStyle(.checkbox)
                .accessibilityLabel(node.selectAllAccessibilityLabel)
                .disabled(!node.canSelectAll)
        } row: { path in
            PathRow(path: path)
        }
    }
}

/// Una voce dentro una cartella spuntata altrove appare spuntata e bloccata, con la nota «Inclusa
/// in …»: si cancella con la cartella, e si sblocca togliendo la spunta a quella.
private struct PathRow: View {
    let path: PathNode

    var body: some View {
        // Letto qui e non solo nel Binding: la riga si ridisegna quando cambia la sua casella o
        // quella della cartella che la contiene.
        let isChecked = path.isChecked
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(path.path, isOn: Binding(get: { isChecked }, set: { path.isSelected = $0 }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(path.isCovered)
                .accessibilityHint(path.containmentText)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(path.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(path.sizeText)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                OptionalText(text: path.containmentText)
                OptionalText(text: path.containsText)
            }
        }
    }
}
```

- [ ] **Step 2: Demo e README**

In `MjmCleaner/Demo/DemoServices.swift`, sostituire:

```swift
        settings.largeFileRoots = ["~/Downloads", "~/Macchine virtuali"]
```

con:

```swift
        settings.largeFileRoots = ["~"]
```

In `MjmCleaner/Demo/DemoData.swift`, sostituire:

```swift
            item("/Users/demo/.npm/_cacache", 730 * megabyte),
        ]),
```

con:

```swift
            item("/Users/demo/.npm/_cacache", 730 * megabyte),
            item("/Users/demo/.cache/huggingface", 5_900 * megabyte),
        ]),
```

In `MjmCleaner/Demo/DemoData.swift`, sostituire:

```swift
        // Al passo 3 le voci dei file grandi partono deselezionate: una macchina virtuale è un'unica voce.
        result("large-files", [
            item("/Users/demo/Macchine virtuali/Windows 11.pvm", 64 * gigabyte),
            item("/Users/demo/Downloads/Xcode_26.xip", 9 * gigabyte),
        ]),
```

con:

```swift
        // Al passo 3 le voci dei file grandi partono deselezionate: una macchina virtuale è un'unica voce.
        // Il modello sta nella cache di Hugging Face che «Cache di sviluppo» propone: compare spuntato
        // e bloccato, con la nota «Inclusa in …».
        result("large-files", [
            item("/Users/demo/Macchine virtuali/Windows 11.pvm", 64 * gigabyte),
            item("/Users/demo/Downloads/Xcode_26.xip", 9 * gigabyte),
            item("/Users/demo/.cache/huggingface/hub/models--mistral-7b/model.safetensors", 4_900 * megabyte),
        ]),
```

In `README.md`, sostituire:

```markdown
Each group has a «Select all» checkbox; Downloads and large-file items start deselected. This is the final point
```

con:

```markdown
Each group has a «Select all» checkbox; Downloads and large-file items start deselected. An item inside a folder that is ticked in another group is marked «Included in …»: it shows ticked and locked, because deleting the folder deletes it too. This is the final point
```

- [ ] **Step 3: Verifica finale**

Run: comando «package».
Expected: `CleanerCoreTests` **707** test in 62 suite, `CleanerFeaturesTests` **240** in 23; nessun `warning:` né `error:`.

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

Run: `git status --short`.
Expected: solo i quattro file di questo task (`M MjmCleaner/Cleanup/ConfirmStepView.swift`, `M MjmCleaner/Demo/DemoData.swift`, `M MjmCleaner/Demo/DemoServices.swift`, `M README.md`), più eventualmente `.zed/`, `mjm-cleaner-ui-handoff.md` e `MjmCleaner.xcodeproj/project.xcworkspace/` non tracciati. Se la build ha toccato un `Localizable.xcstrings`, si ripristina con `git checkout -- <file>` e non va in stage.

- [ ] **Step 4: Commit**

```bash
git add MjmCleaner/Cleanup/ConfirmStepView.swift MjmCleaner/Demo/DemoData.swift MjmCleaner/Demo/DemoServices.swift README.md
git commit -m "$(cat <<'EOF'
feat(cleanup): mark included items in the confirmation step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Screenshot (controller, solo con il consenso dell'utente)**

Il controller chiede all'utente se catturare lo screenshot del passo 3 dell'avvio dimostrativo, con la riga del modello «Inclusa in …». Servono circa due minuti, con Claude in primo piano e senza toccare tastiera e mouse. Senza consenso il task si chiude qui.

---

## Mutazioni provate in stesura

Tutte applicate una alla volta alla copia scratch completa (Task 1–4) ed eseguite con l'intero package. Tutte uccise da un test, non da un errore del compilatore, tranne M18, che è equivalente.

| # | Mutazione | File | Uccisa da |
|---|---|---|---|
| M1 | `selections` ignora la copertura | `ConfirmationRows.swift` | `aRowCoveredByASelectedFolderIsNotSent`, `aTickedFolderAndATickedModelInsideItAreDeletedOnce`, `deleteSendsTheFolderAndNotTheRowsItCovers` e altri |
| M2 | copertura solo di primo livello in `selections` | `ConfirmationRows.swift` | `coverageFollowsTheWholeChain`, `everySelectionSendsNoNestedRowsAndLosesNoSelectedRow` |
| M3 | chiave senza ripiegamento | `ConfirmationRows.swift` | `containmentIgnoresCaseAndSpelling`, `samePathWithDifferentCaseOrSpellingIsOneRow` |
| M4 | chiave con `PathText.folded` | `ConfirmationRows.swift` | `containmentIgnoresCaseAndSpelling`, `samePathWithDifferentCaseOrSpellingIsOneRow` (caso «ß») |
| M5 | chiave sul percorso dichiarato, senza root risolta | `ConfirmationRows.swift` | `aLinkedRootIsComparedWhereItLeads`, `twoSpellingsThatLeadToTheSameFolderAreOneRow`, `theModelIsBoundToTheFolderItLivesIn`, `containmentUsesTheRootsOfTheEnvironment` |
| M6 | antenati tagliati a ogni scalare invece che a ogni «/» | `ConfirmationRows.swift` | `aFolderDoesNotContainASiblingWithACommonPrefix` |
| M7 | anche i file contengono | `ConfirmationRows.swift` | `aFileContainsNothing` |
| M8 | deduplicazione sul percorso esatto | `ConfirmationRows.swift` | `samePathWithDifferentCaseOrSpellingIsOneRow`, `twoSpellingsThatLeadToTheSameFolderAreOneRow` |
| M9 | risolutore chiamato per ogni voce | `ConfirmationRows.swift` | `eachDeclaredRootIsResolvedOnce` |
| M10 | posizione di `container` inesistente inviata | `ConfirmationRows.swift` | `aRowWhoseContainerDoesNotExistIsNotSent` |
| M11 | `isCovered` sempre falso | `ConfirmStepModel.swift` | `theTicksOnScreenMatchWhatIsDeleted` e altri cinque |
| M12 | `isCovered` solo di primo livello | `ConfirmStepModel.swift` | `theTicksOnScreenMatchWhatIsDeleted` |
| M13 | «Seleziona tutte» scrive anche le voci coperte | `ConfirmStepModel.swift` | `selectAllLeavesCoveredRowsToTheirFolder` |
| M14 | «Seleziona tutte» con una passata sola | `ConfirmStepModel.swift` | `selectAllReachesTheRowsThatItsOwnFolderFrees` |
| M15 | `allSelected` legge `isSelected` | `ConfirmStepModel.swift` | `aGroupMadeOnlyOfCoveredRowsCannotSelectAll`, `selectAllLeavesCoveredRowsToTheirFolder` |
| M16 | `canSelectAll` vero per ogni gruppo non vuoto | `ConfirmStepModel.swift` | `aGroupMadeOnlyOfCoveredRowsCannotSelectAll` |
| M17 | il totale conta anche le voci coperte | `ConfirmStepModel.swift` | `untickingTheFolderFreesTheRowWithItsOwnChoice` |
| M18 | `canDelete` con le sole voci che partono da sole | `ConfirmStepModel.swift` | **sopravvive, equivalente**: una voce selezionata ha sempre in cima alla sua catena una voce selezionata che parte; per questo `canDelete` resta com'era |
| M19 | `delete()` costruisce la selezione dai nodi come prima | `ConfirmStepModel.swift` | `deleteSendsTheFolderAndNotTheRowsItCovers` |
| M20 | il modello passa un risolutore identità | `ConfirmStepModel.swift` | `containmentUsesTheRootsOfTheEnvironment` |
| M21 | note «coperta» e «libera» scambiate | `ConfirmStepModel.swift` | `aRowInsideATickedFolderAppearsTickedLockedAndExplained`, `untickingTheFolderFreesTheRowWithItsOwnChoice` |
| M22 | la nota della cartella nomina il proprio gruppo | `ConfirmStepModel.swift` | `aRowInsideATickedFolderAppearsTickedLockedAndExplained` |
| M23 | `resolvedRoot` restituisce sempre la root dichiarata | `RootResolving.swift` | `aLinkedRootLeadsToItsTarget`, `liveRootsFollowARealLink`, `aTickedFolderAndATickedModelInsideItAreDeletedOnce` e altri |
| M24 | `resolvedRoot` restituisce la stringa vuota senza percorso canonico | `RootResolving.swift` | `withoutACanonicalPathTheDeclaredRootStays` |
| M25 | `coveredText` conta le caselle spuntate | `ConfirmStepModel.swift` | `selectAllLeavesCoveredRowsToTheirFolder` |
