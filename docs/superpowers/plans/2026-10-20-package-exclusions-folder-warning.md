# Pacchetti fra le cartelle escluse, avviso per le categorie senza cartelle — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nel pannello delle cartelle escluse si può scegliere anche un pacchetto macOS intero (`.pvm`, `.app`…). Al passo 1 «Cartelle bin e obj nei progetti» e «File grandi» senza cartelle nelle Impostazioni sono disattivate, con l'avviso «Nessuna cartella da analizzare.» e il pulsante «Apri Impostazioni…».

**Architecture:** `FolderPicking.pickFolder(title:allowsPackages:)` dice all'adattatore AppKit se accettare i pacchetti, e `SettingsModel` lo chiede solo per le esclusioni. `CategoryChoice.isAvailable` vale `!category.rules.isEmpty`, e `isSelected` resta falso per una categoria non disponibile. `ChooseStepModel.openSettings()` passa da `CleanupNavigating.showSettings()`, che `MainModel` implementa già. Il Core non cambia.

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-20-package-exclusions-folder-warning-design.md`

Stato di partenza: branch `feat/package-exclusions-folder-warning` nel worktree `.claude/worktrees/charming-cerf-98b828`, creato da `feat/large-files-exclusions` (273ed4e) più la spec (0ae6761) e questo piano. Nessun push. `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **681** test in 60 suite (`CleanerCoreTests`) e **231** in 23 (`CleanerFeaturesTests`).

Decisioni dell'utente (2026-10-20, nella spec):

- **Nel pannello delle esclusioni si scelgono cartelle e pacchetti**, non file singoli.
- **Il pacchetto si sceglie come unità**: `canChooseFiles = true`, `allowedContentTypes = [.package]`, `treatsFilePackagesAsDirectories = false`.
- **L'avviso vale per entrambe le categorie** che prendono le cartelle dalle Impostazioni.
- **Al passo 1 la riga è disattivata e deselezionata**, con l'avviso e «Apri Impostazioni…».

Decisioni prese durante la stesura, verificate applicando l'intero piano a una copia scratch:

- **Il clamp sta solo nel getter di `isSelected`** (`selected && isAvailable`). Un solo punto: con un secondo clamp nell'`init` o nel setter, la mutazione che ne toglie uno sopravviverebbe.
- **`FakePicker.titles` diventa `requests`**, con titolo e `allowsPackages`. `titles` si usa in `SettingsViewModelTests` e in `MainModelTests.theSettingsSheetPicksFoldersWithTheGivenPicker`.
- **`CleanupNavigating.showSettings()` non ha implementazione predefinita.** `MainModel` la ha già, pubblica e con la guardia `canShowSettings`. Gli altri conformi sono i tre doppi dei test.
- **Il test del catalogo passa già al primo giro.** Fissa un fatto su cui il passo 1 si appoggia: le sole categorie che possono restare senza regole sono `project-build-output` e `large-files`.
- **`ChooseStepView` passa `model.openSettings` come `() -> Void`**, come `FolderList` riceve `model.removeProjectRoot`.
- **Nei test, `allSatisfy` dentro `#expect` prende una closure, non un key path.** `#expect(model.choices.allSatisfy(\.isAvailable))` non compila: l'espansione della macro dice «call can throw, but it is not marked with 'try'».
- **`MainModel.page.chooseStep` è `fileprivate` in `MainModelTests`.** Il test di `SettingsOpeningTests` usa `guard case .choose(let choose) = main.page`, come `stepOneNavigatesThroughTheMainModel`.
- **Nessun test esistente cambia per il passo 1.** Quelli che spuntano una categoria usano `system-caches` o `logs`, che hanno sempre regole.

Frasi nuove, in italiano con `String(localized:)` come le esistenti, da aggiungere alla tabella del piano di localizzazione:

- Features: «Scegli una cartella o un pacchetto da escludere» (sostituisce «Scegli una cartella da escludere»), «Nessuna cartella da analizzare.».
- App: «Apri Impostazioni…»; «Cartelle e pacchetti, come una macchina virtuale, mai analizzati né proposti in nessuna categoria della pulizia. Le pagine Xcode e Docker non li usano.» (sostituisce «Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.»).

## Global Constraints

- Cambiano solo:
  - in `CleanerFeatures`, `Environment/PlatformServices.swift`, `Settings/SettingsModel.swift` e `Cleanup/ChooseStepModel.swift`;
  - nell'app, `App/AppKitServices.swift`, `Settings/SettingsView.swift` e `Cleanup/ChooseStepView.swift`;
  - `README.md`;
  - i test elencati nei task, in `MjmCleanerKit/Tests/CleanerFeaturesTests/` e `MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`.
  Il codice del Core (`MjmCleanerKit/Sources/CleanerCore/`) non cambia.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati nel codice di produzione.
- Testi nuovi: solo quelli elencati sopra, scritti esattamente come nel piano. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica, dalla radice del worktree:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E '✘|Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-package-exclusions-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/package-exclusions-folder-warning`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` (`MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`).
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick) e mai avviare l'app: le verifiche sono test e build. Gli screenshot con `-MJMDemo` li cattura il controller, solo dopo averlo chiesto all'utente; per questo piano non servono, perché la demo ha cartelle di progetto e dei file grandi.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: sonnet per i tre task, con mutazioni in una copia scratch nei Task 1 e 2; opus per la revisione finale.
- Mutazioni provate in stesura, tutte uccise dai test del piano, da ripetere nelle revisioni: vedi la tabella in fondo.
- A fine piano il controller copia il registro in `docs/superpowers/decisions/2026-10-20-registro-decisioni-package-exclusions-folder-warning.md`, aggiunge le frasi nuove alla nota sulla localizzazione e poi usa `superpowers:finishing-a-development-branch`.

---

## Fatti misurati (2026-10-20, macOS 27.0, Xcode 27)

- Sonda con `NSWorkspace.isFilePackage`, `URLResourceValues.isPackage` e `contentType` su cartelle vuote appena create: `Windows 11.pvm` pacchetto (`com.parallels.vm.vmpackage`, conforme a `.package`; Parallels Desktop è installato), `Prova.app` pacchetto (`com.apple.application-bundle`), `Sistema.logarchive` pacchetto (`com.apple.logarchive`); `Linux.utm`, `Ubuntu.vmwarevm` e `Normale` cartelle (`public.folder`).
- Su `feat/large-files-exclusions` (273ed4e): 681 test in 60 suite nel Core, 231 in 23 in Features.
- Il piano completo, applicato blocco per blocco a una copia di 0ae6761 (26 sostituzioni, ognuna trovata una sola volta): RED e GREEN come negli «Expected» di ogni task; alla fine 682 test in 60 suite nel Core e 238 in 23 in Features, build Debug dell'app riuscita, i tre `Localizable.xcstrings` identici.

---

### Task 1: pannello delle esclusioni che accetta i pacchetti

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`
- Modify: `MjmCleaner/App/AppKitServices.swift`
- Modify: `MjmCleaner/Settings/SettingsView.swift`
- Modify: `README.md`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/PlatformDoubles.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`

**Interfaces:**
- Consumes: nulla dai task precedenti.
- Produces: `FolderPicking.pickFolder(title: String, allowsPackages: Bool) async -> String?`; `FakePicker.Request` (`title: String`, `allowsPackages: Bool`, `Equatable`) e `FakePicker.requests: [FakePicker.Request]` al posto di `FakePicker.titles`.

- [ ] **Step 1: Test e doppio del pannello**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/PlatformDoubles.swift`, sostituire:

```swift
/// `FixedPicker` dei test C#: restituisce sempre lo stesso percorso (o `nil`, come un annullamento).
@MainActor
final class FakePicker: FolderPicking {
    private let result: String?
    private(set) var titles: [String] = []

    init(_ result: String? = nil) {
        self.result = result
    }

    func pickFolder(title: String) async -> String? {
        titles.append(title)
        return result
    }
}
```

con:

```swift
/// `FixedPicker` dei test C#: restituisce sempre lo stesso percorso (o `nil`, come un annullamento).
/// Registra ogni richiesta: il titolo e se il pannello accetta i pacchetti.
@MainActor
final class FakePicker: FolderPicking {
    struct Request: Equatable {
        let title: String
        let allowsPackages: Bool
    }

    private let result: String?
    private(set) var requests: [Request] = []

    init(_ result: String? = nil) {
        self.result = result
    }

    func pickFolder(title: String, allowsPackages: Bool) async -> String? {
        requests.append(Request(title: title, allowsPackages: allowsPackages))
        return result
    }
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift`, sostituire:

```swift
        #expect(fixture.picker.titles == ["Scegli una cartella da escludere"])
```

con:

```swift
        #expect(fixture.picker.requests == [FakePicker.Request(title: "Scegli una cartella o un pacchetto da escludere", allowsPackages: true)])
```

poi sostituire:

```swift
    @Test func cancelDiscardsTheExcludedFolders() async {
```

con:

```swift
    /// Solo le cartelle escluse accettano un pacchetto: una macchina virtuale si esclude da sola,
    /// mentre le cartelle in cui cercare restano cartelle (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`).
    @Test func onlyTheExcludedFoldersPanelAcceptsPackages() async {
        let fixture = create(picked: nil)

        await fixture.model.addProjectRoot()
        await fixture.model.addLargeFileRoot()
        await fixture.model.addExcludedFolder()

        #expect(fixture.picker.requests == [
            FakePicker.Request(title: "Scegli una cartella di progetto", allowsPackages: false),
            FakePicker.Request(title: "Scegli una cartella in cui cercare file grandi", allowsPackages: false),
            FakePicker.Request(title: "Scegli una cartella o un pacchetto da escludere", allowsPackages: true),
        ])
    }

    @Test func cancelDiscardsTheExcludedFolders() async {
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`, sostituire:

```swift
        #expect(picker.titles.count == 1)
```

con:

```swift
        #expect(picker.requests.count == 1)
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errore di compilazione `type 'FakePicker' does not conform to protocol 'FolderPicking'`.

- [ ] **Step 3: Protocollo e modello**

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift`, sostituire:

```swift
    /// Percorso locale della cartella scelta, o `nil` se l'utente annulla.
    func pickFolder(title: String) async -> String?
```

con:

```swift
    /// Percorso locale della cartella scelta, o `nil` se l'utente annulla. Con `allowsPackages` si
    /// può scegliere anche un pacchetto macOS intero, come una macchina virtuale o un'app: serve
    /// alle cartelle escluse (spec `2026-10-20-package-exclusions-folder-warning-design.md`).
    func pickFolder(title: String, allowsPackages: Bool) async -> String?
```

In `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`, sostituire:

```swift
        if let path = await addFolder(to: \.projectRoots, title: title) {
```

con:

```swift
        if let path = await addFolder(to: \.projectRoots, title: title, allowsPackages: false) {
```

poi sostituire:

```swift
        if let path = await addFolder(to: \.largeFileRoots, title: title) {
```

con:

```swift
        if let path = await addFolder(to: \.largeFileRoots, title: title, allowsPackages: false) {
```

poi sostituire:

```swift
        let title = String(localized: "Scegli una cartella da escludere", bundle: .module)
        if let path = await addFolder(to: \.excludedFolders, title: title) {
```

con:

```swift
        // Anche un pacchetto: escludere una macchina virtuale non deve costare l'intera cartella
        // che la contiene.
        let title = String(localized: "Scegli una cartella o un pacchetto da escludere", bundle: .module)
        if let path = await addFolder(to: \.excludedFolders, title: title, allowsPackages: true) {
```

poi sostituire:

```swift
    private func addFolder(to list: ReferenceWritableKeyPath<SettingsModel, [String]>, title: String) async -> String? {
        guard let path = await folders.pickFolder(title: title) else { return nil }
```

con:

```swift
    private func addFolder(
        to list: ReferenceWritableKeyPath<SettingsModel, [String]>, title: String, allowsPackages: Bool
    ) async -> String? {
        guard let path = await folders.pickFolder(title: title, allowsPackages: allowsPackages) else { return nil }
```

- [ ] **Step 4: Verificare che i test passino**

Run: comando «una suite» con `--filter SettingsViewModelTests`.
Expected: `✔ Test run with 21 tests in 1 suite passed`, nessun `✘`.

Run: comando «package».
Expected: `CleanerCoreTests` **681** test in 60 suite, `CleanerFeaturesTests` **232** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Adattatore AppKit, didascalia e README**

In `MjmCleaner/App/AppKitServices.swift`, sostituire:

```swift
import AppKit
import CleanerCore
import CleanerFeatures
```

con:

```swift
import AppKit
import CleanerCore
import CleanerFeatures
import UniformTypeIdentifiers
```

poi sostituire:

```swift
/// `StorageFolderPicker`: il pannello di sistema, solo cartelle. Il percorso resta testo invariato
/// (spec §6.6); in fase 2 qui si salverà anche il bookmark.
@MainActor
struct AppKitFolderPicker: FolderPicking {
    func pickFolder(title: String) async -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
```

con:

```swift
/// `StorageFolderPicker`: il pannello di sistema. Il percorso resta testo invariato (spec §6.6); in
/// fase 2 qui si salverà anche il bookmark.
///
/// Di norma solo cartelle: un pacchetto (`.app`, `.pvm`, `.logarchive`…) compare come un file
/// grigio. Con `allowsPackages` il pacchetto si sceglie intero, senza entrarci, e i file normali
/// restano grigi: lo scanner tratta i pacchetti come unità, e un pezzo interno escluso non
/// servirebbe a nulla. `.utm` e `.vmwarevm` senza le loro app sono cartelle comuni e si scelgono
/// comunque (verificato il 2026-10-20).
@MainActor
struct AppKitFolderPicker: FolderPicking {
    func pickFolder(title: String, allowsPackages: Bool) async -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = allowsPackages
        if allowsPackages {
            panel.allowedContentTypes = [.package]
        }
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
```

In `MjmCleaner/Settings/SettingsView.swift`, sostituire:

```swift
                    Text("Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.")
```

con:

```swift
                    Text("Cartelle e pacchetti, come una macchina virtuale, mai analizzati né proposti in nessuna categoria della pulizia. Le pagine Xcode e Docker non li usano.")
```

In `README.md`, sostituire:

```text
files, the large-file size threshold, the folders excluded from every cleanup
category, and the minimum ages for Downloads, logs, and NuGet packages.
```

con:

```text
files, the large-file size threshold, the folders and packages excluded from
every cleanup category, and the minimum ages for Downloads, logs, and NuGet
packages.
```

poi sostituire:

```text
Folders excluded in Settings are never scanned or proposed. A folder that would
```

con:

```text
Folders excluded in Settings are never scanned or proposed. A single macOS
package, such as a virtual machine, can be excluded on its own instead of the
folder that contains it. A folder that would
```

- [ ] **Step 6: Build dell'app**

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

Run: `git status --short`
Expected: gli otto file di questo task, più eventualmente `.zed/` e `mjm-cleaner-ui-handoff.md` non tracciati. Se la build ha toccato un `Localizable.xcstrings`, si ripristina con `git checkout -- <file>` e non va in stage.

- [ ] **Step 7: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift \
  MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift \
  MjmCleaner/App/AppKitServices.swift \
  MjmCleaner/Settings/SettingsView.swift \
  README.md \
  MjmCleanerKit/Tests/CleanerFeaturesTests/Support/PlatformDoubles.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift
git commit -m "feat(settings): let the excluded folders panel choose a whole package

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: categorie senza cartelle non disponibili al passo 1 (modello)

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsOpeningTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/CleanupNavigationSpy.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/ScanStepModelTests.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`, `MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`

**Interfaces:**
- Consumes: `MainModel.showSettings()` (esistente, pubblica, con la guardia `canShowSettings`); `Page.choose(ChooseStepModel)` (esistente).
- Produces: `CleanupNavigating.showSettings()`; `CategoryChoice.isAvailable: Bool`; `CategoryChoice.unavailableText: String`; `ChooseStepModel.openSettings()`. Il Task 3 li usa nella vista.

- [ ] **Step 1: Test**

In `MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`, sostituire:

```swift
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads", "large-files",
        ])
    }
```

con:

```swift
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads", "large-files",
        ])
    }

    /// Solo «Cartelle bin e obj nei progetti» e «File grandi» prendono le regole dalle cartelle delle
    /// Impostazioni: senza cartelle restano vuote, e il passo 1 le mostra non disponibili (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`). Ogni altra categoria ha sempre regole.
    @Test func onlyTheCategoriesFedBySettingsFoldersCanBeEmpty() throws {
        #expect(try build().filter(\.rules.isEmpty).map(\.id) == ["project-build-output", "large-files"])

        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        settings.largeFileRoots = ["~/Downloads"]
        #expect(try build(settings).filter(\.rules.isEmpty).isEmpty)
    }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift`, sostituire:

```swift
        model.analyze()

        #expect(store.current == settings)
    }
}
```

con:

```swift
        model.analyze()

        #expect(store.current == settings)
    }

    // Categorie senza cartelle (spec `2026-10-20-package-exclusions-folder-warning-design.md`).

    /// Senza cartelle nelle Impostazioni «Cartelle bin e obj nei progetti» e «File grandi» non hanno
    /// nulla da analizzare: anche se ricordate, partono deselezionate e con l'avviso.
    @Test func categoriesWithoutFoldersAreUnavailableEvenWhenRemembered() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["project-build-output", "logs", "large-files"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)

        let unavailable = model.choices.filter { !$0.isAvailable }
        #expect(unavailable.map(\.category.id) == ["project-build-output", "large-files"])
        #expect(unavailable.map(\.unavailableText) == ["Nessuna cartella da analizzare.", "Nessuna cartella da analizzare."])
        #expect(model.choices.filter(\.isAvailable).allSatisfy { $0.unavailableText.isEmpty })
        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["logs"])
        #expect(model.selectedCountText == "1 categoria selezionata")
    }

    /// La casella disattivata è della vista; il modello ignora comunque una spunta, così una categoria
    /// vuota non arriva mai all'analisi né alla selezione salvata.
    @Test func selectingAnUnavailableCategoryIsIgnored() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs"]
        let store = FakeSettingsStore(settings)
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)
        let largeFiles = try #require(model.choices.first { $0.category.id == "large-files" })

        largeFiles.isSelected = true

        #expect(!largeFiles.isSelected)
        #expect(model.selectedCountText == "1 categoria selezionata")

        model.analyze()

        #expect(navigation.scannedCategories.map(\.id) == ["logs"])
        #expect(store.current.selectedCategoryIds == ["logs"])
    }

    @Test func categoriesWithFoldersAreAvailableAndSelectable() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["project-build-output"]
        settings.projectRoots = ["~/src"]
        settings.largeFileRoots = ["~/Downloads"]
        let model = ChooseStepModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings)), navigation: nil)
        let largeFiles = try #require(model.choices.first { $0.category.id == "large-files" })

        largeFiles.isSelected = true

        #expect(model.choices.allSatisfy { $0.isAvailable })
        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["project-build-output", "large-files"])
        #expect(largeFiles.unavailableText.isEmpty)
    }

    /// Anche chi costruisce una riga già spuntata non può selezionare una categoria senza regole.
    @Test func aChoiceBuiltSelectedWithoutRulesIsNotSelected() {
        let choice = CategoryChoice(category: makeCategory("large-files"), isSelected: true)

        #expect(!choice.isAvailable)
        #expect(!choice.isSelected)
    }

    /// «Apri Impostazioni…» accanto all'avviso.
    @Test func openSettingsAsksTheWindowForTheSettingsSheet() throws {
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(), navigation: navigation)

        model.openSettings()

        #expect(navigation.events == ["settings"])
    }
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsOpeningTests.swift`, sostituire:

```swift
        opened.cancel()
        #expect(main.settings == nil)
        #expect(main.canShowSettings)
    }
}
```

con:

```swift
        opened.cancel()
        #expect(main.settings == nil)
        #expect(main.canShowSettings)
    }

    /// «Apri Impostazioni…» del passo 1 apre lo stesso sheet di ⌘, (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`).
    @Test func stepOneOpensTheSettingsSheet() throws {
        let main = try Self.main()
        guard case .choose(let choose) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }

        choose.openSettings()

        #expect(main.settings != nil)
    }
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/CleanupNavigationSpy.swift`, sostituire:

```swift
        doneJournal = journal
    }
}
```

con:

```swift
        doneJournal = journal
    }

    func showSettings() {
        record("settings")
    }
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/ScanStepModelTests.swift`, sostituire:

```swift
    func showDone(_ report: CleanReport, journal: PendingJournal?) {}
}
```

con:

```swift
    func showDone(_ report: CleanReport, journal: PendingJournal?) {}
    func showSettings() {}
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`, sostituire:

```swift
        progressAtDone.append(model?.deleteProgressText ?? "")
    }
}
```

con:

```swift
        progressAtDone.append(model?.deleteProgressText ?? "")
    }

    func showSettings() {}
}
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errore di compilazione `value of type 'ChooseStepModel' has no member 'openSettings'` (misurato in stesura). Gli errori su `isAvailable` e `unavailableText` possono non comparire, perché il compilatore si ferma prima. Il test del catalogo nel Core compila e passerà già: fissa un fatto esistente.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift`, sostituire:

```swift
    func showDone(_ report: CleanReport, journal: PendingJournal?)
}
```

con:

```swift
    func showDone(_ report: CleanReport, journal: PendingJournal?)
    /// Lo sheet delle Impostazioni, dal passo 1: per scegliere le cartelle di una categoria che non
    /// ne ha.
    func showSettings()
}
```

poi sostituire:

```swift
    public let category: CleanupCategory
    public var isSelected: Bool
    /// La prima riga del gruppo non ha separatore sopra.
    public let showSeparator: Bool

    public init(category: CleanupCategory, isSelected: Bool, showSeparator: Bool = false) {
        self.category = category
        self.isSelected = isSelected
        self.showSeparator = showSeparator
    }
```

con:

```swift
    public let category: CleanupCategory
    /// La prima riga del gruppo non ha separatore sopra.
    public let showSeparator: Bool

    /// Vero se la categoria ha qualcosa da analizzare. «Cartelle bin e obj nei progetti» e «File
    /// grandi» prendono le regole dalle cartelle scelte nelle Impostazioni: senza cartelle non ne
    /// hanno, e un'analisi non troverebbe nulla senza dire perché (spec
    /// `2026-10-20-package-exclusions-folder-warning-design.md`).
    public let isAvailable: Bool

    private var selected: Bool

    public init(category: CleanupCategory, isSelected: Bool, showSeparator: Bool = false) {
        self.category = category
        self.showSeparator = showSeparator
        isAvailable = !category.rules.isEmpty
        selected = isSelected
    }

    /// Una categoria non disponibile non risulta mai selezionata, né dalla selezione ricordata né da
    /// un'assegnazione: così resta fuori dal contatore, dall'analisi e dalla selezione salvata. La
    /// casella disattivata è della vista; questa è la garanzia.
    public var isSelected: Bool {
        get { selected && isAvailable }
        set { selected = newValue }
    }

    /// L'avviso del passo 1 per una categoria senza cartelle; vuoto se la categoria è disponibile.
    public var unavailableText: String {
        isAvailable ? "" : String(localized: "Nessuna cartella da analizzare.", bundle: .module)
    }
```

poi sostituire:

```swift
        navigation?.showScan(selected)
    }
}
```

con:

```swift
        navigation?.showScan(selected)
    }

    /// «Apri Impostazioni…» accanto all'avviso di una categoria senza cartelle. Dopo Salva la
    /// finestra ricrea il passo 1, con le categorie calcolate sulle impostazioni nuove.
    public func openSettings() {
        navigation?.showSettings()
    }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: comando «una suite» con `--filter ChooseStepTests`.
Expected: `✔ Test run with 17 tests in 1 suite passed`, nessun `✘`.

Run: comando «package».
Expected: `CleanerCoreTests` **682** test in 60 suite, `CleanerFeaturesTests` **238** in 23; nessun `warning:` né `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsOpeningTests.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/Support/CleanupNavigationSpy.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/ScanStepModelTests.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift \
  MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift
git commit -m "feat(cleanup): keep categories without folders out of step 1 selection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: avviso e «Apri Impostazioni…» nella vista del passo 1

**Files:**
- Modify: `MjmCleaner/Cleanup/ChooseStepView.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: `CategoryChoice.isAvailable`, `CategoryChoice.unavailableText`, `ChooseStepModel.openSettings()` (Task 2).
- Produces: nulla per altri task.

- [ ] **Step 1: Vista**

La vista non ha test automatici: il comportamento è nei test del modello del Task 2, e qui si verifica con la build.

In `MjmCleaner/Cleanup/ChooseStepView.swift`, sostituire:

```swift
                        ChoiceRow(choice: choice)
```

con:

```swift
                        ChoiceRow(choice: choice, openSettings: model.openSettings)
```

poi sostituire:

```swift
private struct ChoiceRow: View {
    @Bindable var choice: CategoryChoice

    var body: some View {
        HStack(spacing: 12) {
            Toggle(choice.displayName, isOn: $choice.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            CategoryTile(visual: choice.visual)
            VStack(alignment: .leading, spacing: 2) {
                // Il nome lo legge già la casella: VoiceOver non lo ripete.
                Text(choice.displayName)
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
                Text(choice.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            RiskPill(risk: choice.risk)
        }
        .padding(.vertical, 11)
        .padding(.leading, choice.isChild ? 60 : 16)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .onTapGesture { choice.isSelected.toggle() }
    }
}
```

con:

```swift
/// Una categoria senza cartelle nelle Impostazioni ha la casella disattivata e, sotto la
/// descrizione, l'avviso con «Apri Impostazioni…».
private struct ChoiceRow: View {
    @Bindable var choice: CategoryChoice
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(choice.displayName, isOn: $choice.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!choice.isAvailable)
            CategoryTile(visual: choice.visual)
                .opacity(choice.isAvailable ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                // Il nome lo legge già la casella: VoiceOver non lo ripete.
                Text(choice.displayName)
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
                Text(choice.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !choice.isAvailable {
                    MissingFoldersNote(text: choice.unavailableText, openSettings: openSettings)
                }
            }
            Spacer(minLength: 12)
            RiskPill(risk: choice.risk)
        }
        .padding(.vertical, 11)
        .padding(.leading, choice.isChild ? 60 : 16)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            // Come la casella: una categoria senza cartelle non si spunta.
            if choice.isAvailable {
                choice.isSelected.toggle()
            }
        }
    }
}

/// L'avviso di una categoria senza cartelle, con il triangolo di `Banner` e la scorciatoia per le
/// Impostazioni.
private struct MissingFoldersNote: View {
    let text: String
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
            Button("Apri Impostazioni…", action: openSettings)
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.top, 2)
    }
}
```

- [ ] **Step 2: README**

In `README.md`, sostituire:

```text
| **1 · Choose** | Select the categories to clean. Each category declares its risk level; high-risk categories are never preselected. |
```

con:

```text
| **1 · Choose** | Select the categories to clean. Each category declares its risk level; high-risk categories are never preselected. Project bin and obj directories and Large files stay unavailable, with a shortcut to Settings, until a directory is chosen there. |
```

- [ ] **Step 3: Verifiche**

Run: comando «package».
Expected: `CleanerCoreTests` **682** test in 60 suite, `CleanerFeaturesTests` **238** in 23; nessun `warning:` né `error:`.

Run: comando «app».
Expected: `** BUILD SUCCEEDED **`, senza `warning:` né `error:`.

Run: `git status --short`
Expected: solo `M MjmCleaner/Cleanup/ChooseStepView.swift` e `M README.md`, più eventualmente `.zed/` e `mjm-cleaner-ui-handoff.md` non tracciati. Se la build ha toccato un `Localizable.xcstrings`, si ripristina con `git checkout -- <file>` e non va in stage.

- [ ] **Step 4: Commit**

```bash
git add MjmCleaner/Cleanup/ChooseStepView.swift README.md
git commit -m "feat(cleanup): explain in step 1 why a category without folders is unavailable

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Mutazioni provate in stesura

Ognuna applicata da sola alla copia scratch con il piano completo, poi `swift test --filter CleanerFeaturesTests`. Tutte uccise (2026-10-20).

| Mutazione | File | Test che la uccidono |
|---|---|---|
| getter di `isSelected` senza `&& isAvailable` | `ChooseStepModel.swift` | `categoriesWithoutFoldersAreUnavailableEvenWhenRemembered`, `selectingAnUnavailableCategoryIsIgnored`, `aChoiceBuiltSelectedWithoutRulesIsNotSelected` |
| `isAvailable = true` | `ChooseStepModel.swift` | gli stessi tre |
| `isAvailable = category.rules.isEmpty` | `ChooseStepModel.swift` | `categoriesWithFoldersAreAvailableAndSelectable` e altri sette, fra cui `rememberedSelectionIsRestoredAndAnalyzeSavesItBeforeScanning` |
| `unavailableText` sempre vuoto | `ChooseStepModel.swift` | `categoriesWithoutFoldersAreUnavailableEvenWhenRemembered` |
| `openSettings()` che non chiama la navigazione | `ChooseStepModel.swift` | `openSettingsAsksTheWindowForTheSettingsSheet`, `stepOneOpensTheSettingsSheet` |
| `addExcludedFolder` con `allowsPackages: false` | `SettingsModel.swift` | `onlyTheExcludedFoldersPanelAcceptsPackages`, `excludedFoldersAreLoadedAddedRemovedAndSaved` |
| `addProjectRoot` con `allowsPackages: true` | `SettingsModel.swift` | `onlyTheExcludedFoldersPanelAcceptsPackages` |
| `addLargeFileRoot` con `allowsPackages: true` | `SettingsModel.swift` | `onlyTheExcludedFoldersPanelAcceptsPackages` |
| `addFolder` passa `true` al pannello qualunque sia il parametro | `SettingsModel.swift` | `onlyTheExcludedFoldersPanelAcceptsPackages` |
