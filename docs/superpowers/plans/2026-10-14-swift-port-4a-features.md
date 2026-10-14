# Porting Swift — Piano 4a: Features

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Creare in `swift/MjmCleanerKit` il modulo `CleanerFeatures`, porting dei ViewModel e di `AppServices` di `src/MjmCleaner.App`: modelli di presentazione `@MainActor @Observable` per Pulizia (quattro passi), Docker, Xcode, Storico e Impostazioni, la finestra principale con navigazione e blocco durante l'eliminazione Xcode, e la composizione `AppEnvironment`. Si portano le prove di comportamento di `tests/MjmCleaner.App.Tests` in Swift Testing e si aggiungono i test del diario della pulizia (spec §8.2) e dei follow-up dei piani 2 e 3.

**Architecture:** Un secondo target del package, `CleanerFeatures`, dipende da `CleanerCore` e non importa SwiftUI né AppKit (spec §4.1). Ogni ViewModel C# diventa una `final class` `@MainActor @Observable` con lo stesso comportamento. Ciò che il ViewModel chiedeva alla UI diventa un protocollo che l'app implementerà nel piano 4b (`FolderPicking`, `AppearanceApplying`), oppure uno stato del modello (`MainModel.settings` per lo sheet delle Impostazioni). La navigazione passa da protocolli con un metodo per destinazione (`Navigating`, `CleanupNavigating`, `DockerNavigating`, `XcodeNavigating`), così ogni pagina si verifica con un doppio. L'avanzamento del Core arriva sul main actor nell'ordine giusto tramite `ProgressRelay`.

**Tech Stack:** Swift 6 language mode, `swift-tools-version: 6.2`, macOS 15, Swift Testing, Observation, `Synchronization.Mutex` nei doppi di test. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` (soprattutto §4, §6, §7, §8, §9.2, §10.1)

Questo è il **quarto di cinque piani**: (1) fondamenta e Core, (2) Docker, (3) Xcode, tutti completati; (4) Features e app SwiftUI; (5) verifica, release e rimozione del C#. Il piano 4 è diviso in due, per scelta dell'utente: **4a** (questo) porta `CleanerFeatures` e si verifica con `swift test`; **4b** creerà il progetto Xcode, le viste SwiftUI, gli asset e gli adattatori AppKit, scritto sul codice reale di 4a. Fra 4a e 5 si inserisce un piano breve dedicato al buco APFS del ripiegamento (U+212A/ſ, registro del piano 1, Task 9), deciso dall'utente: non riguarda questo piano.

Stato di partenza: `main` con i piani 1–3, 496 test verdi nel target `CleanerCoreTests`. Questo piano aggiunge il target `CleanerFeaturesTests` con **118** test (44 portati dal C#, 74 solo Swift) e non tocca nessun file sotto `Sources/CleanerCore` né `Tests/CleanerCoreTests`.

Decisioni prese con l'utente prima della stesura (2026-10-14):

- **Sheet delle Impostazioni come stato del modello.** `MainModel.settings: SettingsModel?`; `showSettings()` lo crea (rifiutando se Xcode sta eliminando o se è già aperto), Salva e Annulla lo azzerano, l'app lo presenta con `.sheet(item:)`. Restano protocolli solo `FolderPicking` e `AppearanceApplying`. Scostamento dalla lettera della spec §4.1, che elencava un protocollo anche per l'apertura delle Impostazioni: si annota nel registro di parità.
- **Errori di scrittura di `settings.json`.** In C# chiudevano l'app (eccezione non gestita); in Swift `SettingsStoring.save` lancia. Salva lascia aperto lo sheet e mostra «Impostazioni non salvate: <motivo>» (unico testo nuovo della fase 1, eccezione alla spec §12); «Analizza» ignora l'errore e prosegue, perché ricordare la selezione è solo una comodità. Entrambe le differenze vanno nel registro.

## Global Constraints

Dai piani 1–3, invariati salvo il branch:

- Il codice Swift vive in `swift/`; il package in `swift/MjmCleanerKit/`. Il C# (`src/`, `tests/`) **non si modifica**: è il riferimento eseguibile.
- `swift-tools-version: 6.2`, `platforms: [.macOS(.v15)]`, `defaultLocalization: "it"`, Swift 6 language mode (concorrenza stretta).
- Nessuna dipendenza esterna. Librerie di sistema ammesse: Foundation, Darwin, Observation, `SQLite3`, zlib (via `CZlib`), `Synchronization`.
- `CleanerCore` e `CleanerFeatures` non importano SwiftUI né AppKit. **Nessun file sotto `Sources/CleanerCore` o `Tests/CleanerCoreTests` cambia in questo piano.**
- Nel codice di `CleanerFeatures`, come nel Core: vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati.
- Testi visibili all'utente: sempre `String(localized: "…", bundle: .module)`, in italiano, identici al C#. I numeri si formattano prima con `Formatting` e si interpolano come `String`, mai come `Int`: un intero dentro `String(localized:)` diventa `%lld` e perderebbe il separatore delle migliaia.
- Ogni test C# portato mantiene il nome (in lowerCamelCase) e il file di origine, nella stessa cartella relativa sotto `Tests/CleanerFeaturesTests/` (radice o `Xcode/`). I test solo Swift stanno in file propri, con il nome del modello che verificano.
- Comando di verifica standard, da `swift/MjmCleanerKit`: `swift test -Xswiftc -warnings-as-errors` (equivale al `TreatWarningsAsErrors` del C#).
- Commit frequenti; ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch: `feat/swift-port-app`, creato da `main` prima del commit del piano; lo stesso branch accoglierà il piano 4b. Nessun push.
- Si mettono in stage solo percorsi espliciti: mai `git add -A`, `git add .` o una cartella intera. `.zed/` e `mjm-cleaner-ui-handoff.md` nella radice sono file dell'utente e non vanno mai in stage.

Vincoli specifici di `CleanerFeatures`, che applicano le decisioni dei registri dei piani 1–3:

- **Testo e confronti.** Per decidere si confrontano byte UTF-8 con `FeatureText.same`, `ordinalKey`, `hasOrdinalPrefix` e `distinct` (Task 1), come `XcodeText`/`DockerText` nel Core, che sono interni al Core. Mai `==` fra `String`, mai `hasPrefix`/`hasSuffix`/`lowercased()` per decidere: `==` confronta per equivalenza canonica (NFC = NFD).
- **Concorrenza.** Modelli `@MainActor @Observable final class`. Il lavoro che il C# avviava nel costruttore (`_ = LoadAsync()`) parte in un `Task` conservato in una proprietà `@ObservationIgnored` (`initialLoad`, `run`, `persistence`, `runningAppsCheck`), così i test lo attendono. L'avanzamento del Core arriva da altri thread e passa da `ProgressRelay` (Task 1). L'annullamento si fa con `cancel()` sul `Task` che esegue l'operazione, come il `CancellationTokenSource` del C#. Le pagine tengono la navigazione con un riferimento `weak`.
- **Diario della pulizia (spec §8.2).** Il passo 3 e la pagina Xcode aprono il `PendingJournal` con `sessionLog.openJournal(startedAt: clock.now)` **prima** di `clean`/`execute`, lo passano all'operazione e poi al modello del resoconto. Il resoconto lo scarta con `sessionLog.discard` **solo dopo** che `sessionLog.write` è riuscita; se storico o log falliscono, il diario resta in `logs/`. Docker non ha diario, come in C#: le rimozioni passano dalla CLI e non da `CleanEngine`.
- **Follow-up dei registri dei piani 2 e 3**, tutti coperti da test di questo piano:
  - composizione come `AppServices.cs`: l'esecutore Xcode usa lo stesso collettore e lo stesso `PathGuard` della scansione (Task 2);
  - diario aperto prima di `execute`, scartato solo dopo il log di sessione (Task 7, 8, 10, 11);
  - l'esecutore Xcode non lancia: anche un'esecuzione annullata restituisce un resoconto da salvare (Task 10);
  - avanzamento fuori dal main actor (Task 1, 6, 7, 9, 10);
  - somme di byte senza overflow (`SafeSum`, Task 1);
  - mai decidere con `==` su `XcodeCandidate`: le righe si identificano per oggetto (Task 10);
  - l'anteprima passa sempre da `XcodeSelection.preview` sullo snapshot dell'analisi (Task 10);
  - test del blocco della navigazione durante l'eliminazione Xcode (Task 11);
  - i volumi Docker «named-unused» non entrano mai con la casella del gruppo (Task 9);
  - diario e storico non si riconciliano mai per testo: i modelli non confrontano percorsi del diario con quelli dello storico.

---

## Convenzioni di porting

Valgono le tabelle dei piani 1–3. Si aggiungono queste.

### ViewModel → modelli

| C# (CommunityToolkit.Mvvm, Avalonia) | Swift (`CleanerFeatures`) |
|---|---|
| `ViewModelBase : ObservableObject`, `[ObservableProperty]` | `@MainActor @Observable public final class`, proprietà `var` o `public private(set) var` |
| `[NotifyPropertyChangedFor]`, `NotifyCanExecuteChangedFor`, `Recalculate()` | proprietà calcolate: Observation registra le letture, anche su altri oggetti osservabili |
| `[RelayCommand]` con `CanExecute` | metodo + proprietà `canX`. Il metodo ripete solo le guardie che il C# aveva nel proprio corpo: `Execute` del toolkit non controlla `CanExecute` |
| `AsyncRelayCommand` | `public func x() async`; la vista lo chiama in un `Task` |
| `_ = LoadAsync()` nel costruttore | `Task` salvato in `initialLoad`/`run`/`persistence`, attendibile nei test |
| `CancellationTokenSource` + `Cancel()` | `Task` conservato + `cancel()` |
| `Progress<T>` con `IProgress<T>` | `ProgressRelay<T>` (Task 1): `relay.report` al Core, `await relay.finish()` prima di proseguire |
| `ObservableCollection<T>` | `[T]` di classi `@Observable` (righe e gruppi) |
| `PropertyChanged +=` fra righe, gruppi e pagina | `didSet` sulla proprietà osservata + callback `onSelectionChanged` interno |
| `AppServices` | `AppEnvironment` (Task 2) |
| `IFolderPicker` / `IAppearanceController` | `FolderPicking` / `AppearanceApplying` (`@MainActor`, implementati dall'app nel piano 4b) |
| `IXcodeNavigation`, `MainWindowViewModel` passato ai ViewModel, `GoTo(object)` | `Navigating` (`startOver`, `refreshTotal`) e protocolli di sezione con un metodo per destinazione |
| `OpenSettingsWindow` + `CloseRequested` | `MainModel.settings: SettingsModel?` + `onClose` |
| `SidebarSections.For(object)` / `IsWizardPage` | `PageKind.section` / `PageKind.isWizardStep` |
| `ViewModelBase.FormatBytes`, `{x:N0}`, `Plural` | `Formatting.bytes`, `Formatting.integer`, `Formatting.plural` |
| `ex.Message` | `FeatureText.message(error)` |
| `Sum()` su byte | `SafeSum.total` (satura invece di andare in trap) |
| `StringComparer.Ordinal`, `string ==` | `FeatureText.same` / `ordinalKey` |
| `CategoryVisuals` (colore esadecimale + geometria) | `CategoryVisual` (nome dell'asset, colore del progetto, SF Symbol) |

### Test

| xUnit (`MjmCleaner.App.Tests`) | Swift Testing (`CleanerFeaturesTests`) |
|---|---|
| `[Fact]`/`[AvaloniaFact]` su un ViewModel | `@Test` in una `struct` `@MainActor` |
| `TestHome.CreateAsync()` + `using` | `try await TestHome.create()` + `defer { home.remove() }` (Task 2) |
| `TaskCompletionSource` | `Gate<Value>` (Task 2) |
| `vm.XCommand.Execute(null)` / `ExecuteAsync(null)` | `model.x()` / `await model.x()` |
| `vm.XCommand.CanExecute(null)` | `model.canX` |
| `await vm.InitialLoad` | `await model.initialLoad?.value` |
| una chiamata `ExecuteAsync` iniziata e controllata subito | `Task { await model.x() }` + `await service.executionStarted.wait()` |
| `RuntimeHelpers.GetUninitializedObject(typeof(T))` | un caso di `PageKind` |
| `Assert.All(list, x => Assert.True(…))` | `#expect(list.allSatisfy { … })` con una closure (vedi «Fatti misurati») |
| `record with { SizeBytes = null }` | `var c = …; c.sizeBytes = nil` |
| `FakeXcode`, `FakeNavigation` (classi interne di `XcodeViewModelTests`) | stessi nomi, annidati in `XcodeViewModelTests` |
| `FakeHistory`, `FakeLog`, `MemoryStore`, `RecordingAppearance`, `FixedPicker` | `FakeHistory`, `FakeSessionLog`, `FakeSettingsStore`, `FakeAppearance`, `FakePicker` in `Support/`, condivisi |

### Fatti misurati (2026-10-14)

Su .NET 10.0.401, con una console usa e getta non presente nel repository e la cultura corrente della macchina (`en-IT`):

- `ViewModelBase.FormatBytes`: 0 → «0 B», 1023 → «1023 B», 1075 → «1 KB», 1126 → «1,1 KB», **1280 → «1,3 KB»** e 2 621 440 → «2,5 MB» (il formato `0.#` arrotonda lontano dallo zero), 1 048 575 → «1024 KB», 10 200 547 328 → «9,5 GB», `long.MaxValue` → «8388608 TB», -1 → «-1 B».
- `N0` con it-IT e con la cultura corrente danno lo stesso testo: 2117 → «2.117», 1 234 567 → «1.234.567», -2117 → «-2.117».
- `{0:0}` su `TimeSpan.TotalSeconds`: 0,5 → «1», 1,5 → «2», 2,5 → «3», 3,49 → «3», 59,5 → «60».
- `ToString("d MMM yyyy, HH:mm", it-IT)`: mesi «gen feb mar apr mag giu lug ago set ott nov dic» (es. «26 set 2026, 01:19»).
- I valori `bytes / 1024ⁿ` sono razionali diadici esatti. Il `0.#` di .NET arrotonda il valore a 15 cifre significative e poi a un decimale. Fino a 100 TB il risultato coincide con l'arrotondamento del valore esatto, fatto da `Formatting.bytes`; oltre, un doppio arrotondamento potrebbe in teoria divergere.

Su Swift 6.4 (Xcode 27):

- `#expect(rows.allSatisfy(\.isSelected))` non compila (`call can throw, but it is not marked with 'try'`): il macro scompone la chiamata `rethrows` con il key path. Con una closure (`allSatisfy { $0.isSelected }`) compila.
- Il tratto `.timeLimit` non interrompe un test sospeso su `value` di un `Task` non strutturato. I doppi che attendono un annullamento aspettano quindi al massimo 5 secondi e registrano se l'annullamento è arrivato: una mutazione che lo toglie fa fallire il test invece di bloccarlo.
- `@Observable` accetta `didSet` sulle proprietà osservate e `weak var` con `@ObservationIgnored`; in un `init` le assegnazioni non chiamano `didSet`.

---

## Mappa dei file

```
swift/MjmCleanerKit/
├── Package.swift                                          Task 1 (target CleanerFeatures e CleanerFeaturesTests)
├── Sources/CleanerFeatures/
│   ├── Resources/Localizable.xcstrings                    Task 1
│   ├── Support/Formatting.swift, FeatureText.swift,
│   │           SafeSum.swift, ProgressRelay.swift         Task 1
│   ├── Environment/AppEnvironment.swift,
│   │               DockerCleanupServing.swift,
│   │               PlatformServices.swift                 Task 2
│   ├── Settings/SettingsModel.swift                       Task 3
│   ├── History/CategoryNames.swift, HistoryModel.swift    Task 4
│   ├── Cleanup/CategoryVisuals.swift, ChooseStepModel.swift   Task 5
│   ├── Cleanup/ScanStepModel.swift                        Task 6
│   ├── Cleanup/ConfirmStepModel.swift                     Task 7
│   ├── Cleanup/DoneStepModel.swift                        Task 8
│   ├── Docker/DockerModel.swift, DockerReportModel.swift  Task 9
│   ├── Xcode/XcodeReportModel.swift, XcodeModel.swift     Task 10
│   └── Shell/Page.swift, MainModel.swift                  Task 11
└── Tests/CleanerFeaturesTests/
    ├── FormattingTests.swift, FeatureTextTests.swift,
    │   ProgressRelayTests.swift                           Task 1
    ├── Support/TestSupport.swift, ServiceDoubles.swift,
    │           TestHome.swift                             Task 2
    ├── AppEnvironmentTests.swift                          Task 2
    ├── Support/PlatformDoubles.swift                      Task 3
    ├── SettingsViewModelTests.swift                       Task 3
    ├── Support/NavigationSpy.swift                        Task 4
    ├── HistoryTests.swift, HistoryViewTests.swift         Task 4
    ├── Support/CleanupNavigationSpy.swift                 Task 5
    ├── ChooseStepTests.swift                              Task 5
    ├── ScanStepModelTests.swift                           Task 6
    ├── ConfirmStepModelTests.swift                        Task 7
    ├── DoneStepModelTests.swift                           Task 8
    ├── Support/DockerNavigationSpy.swift                  Task 9
    ├── DockerModelTests.swift, DockerReportModelTests.swift   Task 9
    ├── Xcode/XcodeViewModelTests.swift,
    │   Xcode/XcodeReportViewModelTests.swift,
    │   Xcode/XcodeViewLayoutTests.swift                   Task 10
    └── SidebarSectionTests.swift, NavigationLockTests.swift,
        SettingsOpeningTests.swift, MainModelTests.swift   Task 11
docs/superpowers/porting/2026-10-13-parity.md              ogni task
```

Ogni task termina aggiornando le proprie righe nel registro di parità. Le sedici righe della tabella `MjmCleaner.App.Tests` oggi hanno «—» e piano 4. Ogni task **sostituisce l'intera riga** del proprio file con quella indicata. Il Task 1 crea la sezione «Test solo Swift di CleanerFeaturesTests», dove i task successivi aggiungono righe in fondo. Il Task 12 chiude le righe dei file non portati e aggiunge la riga di completamento in testa.

---

### Task 1: target `CleanerFeatures` e utilità dei modelli

Il target nuovo e le quattro utilità che ogni modello usa: i formati del C# (`FormatBytes`, `N0`, `Plural`, secondi, date dello storico), i confronti ordinali e il testo degli errori, le somme senza trap e il ponte dell'avanzamento verso il main actor.

**Files:**
- Modify: `swift/MjmCleanerKit/Package.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Resources/Localizable.xcstrings`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Support/Formatting.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Support/FeatureText.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Support/SafeSum.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Support/ProgressRelay.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/FormattingTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/FeatureTextTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ProgressRelayTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/ViewModelBase.cs`, `HistoryViewModel.cs` (`HistoryRow.When`), `DoneStepViewModel.cs` (secondi); `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeText.swift` (`message`)

**Interfaces:**
- Consumes: `FileSystemError`, `ProcessLaunchError`, `DockerUnavailableError`, `XcodeArgumentError` (Core, per i test di `message`).
- Produces:
  - `public enum Formatting` — `bytes(_ bytes: Int64) -> String`, `integer<Number: BinaryInteger>(_ value: Number) -> String`, `plural(_ count: Int, _ singular: String, _ plural: String) -> String`, `seconds(_ duration: Duration) -> String`, `historyDate(_ date: Date, timeZone: TimeZone = .current) -> String`
  - `enum FeatureText` (interno) — `same(_:_:) -> Bool`, `ordinalKey(_:) -> [UInt8]`, `hasOrdinalPrefix(_:_:) -> Bool`, `distinct(_:) -> [String]`, `message(_ error: any Error) -> String`
  - `enum SafeSum` (interno) — `total(_:) -> Int64` su una sequenza di `Int64`, `difference(_:_:) -> Int64`
  - `@MainActor final class ProgressRelay<Value: Sendable>` (interno) — `init(_ apply: @escaping @MainActor (Value) -> Void)`, `var report: @Sendable (Value) -> Void`, `func finish() async`

Note di porting:
- `FormatBytes` si porta identica (spec §6.5), ma scritta a mano: i decimi si arrotondano lontano dallo zero (`.toNearestOrAwayFromZero`), come il `0.#` di .NET, e la virgola è fissa. `ByteCountFormatter` (base 1000) e le tabelle ICU non entrano.
- `N0` in C# usava la cultura corrente; su questa macchina (`en-IT`) dà lo stesso testo di it-IT (vedi «Fatti misurati»). Swift usa sempre il punto: registro di parità.
- `message` replica `XcodeText.message` del Core, che è interno, e aggiunge `LocalizedError` (gli errori Docker hanno `errorDescription`). Gli altri errori usano `String(describing:)`, che per `XcodeArgumentError` e gli errori SQLite del Core è la loro `description`.

- [ ] **Step 1: Aggiungere i target al package**

`Package.swift`, sostituire l'intero file con:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MjmCleanerKit",
    defaultLocalization: "it",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
        .library(name: "CleanerFeatures", targets: ["CleanerFeatures"]),
    ],
    targets: [
        // Module map verso la zlib di sistema: Foundation non sa scrivere gzip.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "CleanerCore",
            dependencies: ["CZlib"],
            resources: [.process("Resources")]
        ),
        // Modelli di presentazione, navigazione e composizione (spec §4.1): niente SwiftUI né
        // AppKit, così il comportamento delle pagine si verifica con `swift test`, senza l'app.
        .target(
            name: "CleanerFeatures",
            dependencies: ["CleanerCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"],
            // Le fixture JSON di Docker e di Xcode si leggono dal sorgente dei test (`#filePath`),
            // non da un bundle: escluderle evita che SwiftPM le rifiuti come file non gestiti, un
            // errore con -warnings-as-errors.
            exclude: ["Docker/Fixtures", "Xcode/Fixtures"]
        ),
        .testTarget(
            name: "CleanerFeaturesTests",
            dependencies: ["CleanerFeatures", "CleanerCore"]
        ),
    ]
)
```

Il catalogo dei testi parte vuoto, come quello del Core: le chiavi italiane valgono da testo.

`Sources/CleanerFeatures/Resources/Localizable.xcstrings`:

```json
{
  "sourceLanguage" : "it",
  "strings" : {
  },
  "version" : "1.0"
}
```

- [ ] **Step 2: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/FormattingTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerFeatures

/// Gli esiti attesi sono quelli di `ViewModelBase.FormatBytes`, `N0` e `ToString("d MMM yyyy,
/// HH:mm", it-IT)` misurati su .NET 10 (piano 4a, «Fatti misurati»).
struct FormattingTests {
    @Test(arguments: [
        (Int64(0), "0 B"), (1, "1 B"), (1023, "1023 B"), (1024, "1 KB"), (1075, "1 KB"),
        (1126, "1,1 KB"), (1280, "1,3 KB"), (1331, "1,3 KB"), (1536, "1,5 KB"), (10_240, "10 KB"),
        (1_048_575, "1024 KB"), (1_048_576, "1 MB"), (2_621_440, "2,5 MB"), (2_673_869, "2,6 MB"),
        (10_200_547_328, "9,5 GB"), (11_811_160_064, "11 GB"), (1_099_511_627_776, "1 TB"),
        (1_152_921_504_606_846_976, "1048576 TB"), (Int64.max, "8388608 TB"), (-1, "-1 B"), (-5000, "-5000 B"),
    ])
    func bytesFollowFormatBytes(bytes: Int64, expected: String) {
        #expect(Formatting.bytes(bytes) == expected)
    }

    @Test(arguments: [
        (Int64(0), "0"), (999, "999"), (1000, "1.000"), (2117, "2.117"), (1_234_567, "1.234.567"),
        (-2117, "-2.117"), (Int64.max, "9.223.372.036.854.775.807"), (Int64.min, "-9.223.372.036.854.775.808"),
    ])
    func integersUseTheItalianThousandsSeparator(value: Int64, expected: String) {
        #expect(Formatting.integer(value) == expected)
    }

    @Test func pluralAgreesOnlyWithOne() {
        #expect(Formatting.plural(1, "elemento", "elementi") == "elemento")
        #expect(Formatting.plural(0, "elemento", "elementi") == "elementi")
        #expect(Formatting.plural(2, "elemento", "elementi") == "elementi")
    }

    @Test(arguments: [
        (Duration.zero, "0"), (.milliseconds(400), "0"), (.milliseconds(500), "1"), (.milliseconds(1500), "2"),
        (.milliseconds(2500), "3"), (.milliseconds(3490), "3"), (.milliseconds(59_500), "60"), (.milliseconds(120_400), "120"),
    ])
    func secondsRoundHalfAwayFromZero(duration: Duration, expected: String) {
        #expect(Formatting.seconds(duration) == expected)
    }

    @Test func historyDateUsesItalianMonthsInTheGivenTimeZone() throws {
        let rome = try #require(TimeZone(identifier: "Europe/Rome"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rome
        let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

        for (offset, month) in months.enumerated() {
            let date = try #require(calendar.date(from: DateComponents(year: 2026, month: offset + 1, day: 6, hour: 9, minute: 5)))
            #expect(Formatting.historyDate(date, timeZone: rome) == "6 \(month) 2026, 09:05")
        }

        let utc = try #require(TimeZone(identifier: "UTC"))
        let instant = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 1, minute: 19)))
        #expect(Formatting.historyDate(instant, timeZone: rome) == "26 set 2026, 01:19")
        // Lo stesso istante in UTC è il giorno prima: la data segue il fuso indicato.
        #expect(Formatting.historyDate(instant, timeZone: utc) == "25 set 2026, 23:19")
    }
}
```

`Tests/CleanerFeaturesTests/FeatureTextTests.swift`:

```swift
import CleanerCore
import Darwin
import Foundation
import Testing
@testable import CleanerFeatures

/// Confronti ordinali, testo degli errori e somme senza trap: le utilità che i modelli usano al
/// posto di `==`, `ex.Message` e `Sum()` del C#.
struct FeatureTextTests {
    @Test func comparisonsAreOrdinalNotCanonical() {
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"

        // `==` fra String li considera uguali; StringComparison.Ordinal no.
        #expect(composed == decomposed)
        #expect(!FeatureText.same(composed, decomposed))
        #expect(FeatureText.ordinalKey(composed) != FeatureText.ordinalKey(decomposed))
        #expect(FeatureText.hasOrdinalPrefix("docker:image:sha", "docker:image:"))
        #expect(!FeatureText.hasOrdinalPrefix("docker:imag", "docker:image:"))
        #expect(FeatureText.distinct(["b", composed, "b", decomposed, composed]) == ["b", composed, decomposed])
    }

    @Test func messagesFollowTheCoreConventions() {
        #expect(FeatureText.message(FileSystemError(code: EACCES, path: "/x")) == String(cString: strerror(EACCES)))
        #expect(FeatureText.message(ProcessLaunchError(executable: "/usr/bin/xcrun", code: ENOENT)) == String(cString: strerror(ENOENT)))
        #expect(FeatureText.message(CancellationError()) == "operazione annullata")
        #expect(FeatureText.message(DockerUnavailableError("Docker non risponde.")) == "Docker non risponde.")
        #expect(FeatureText.message(XcodeArgumentError("Unknown Xcode candidate key: x")) == "Unknown Xcode candidate key: x")
    }

    @Test func sumsSaturateInsteadOfTrapping() {
        #expect(SafeSum.total([Int64]()) == 0)
        #expect(SafeSum.total([1, 2, 3]) == 6)
        #expect(SafeSum.total([Int64.max, 1]) == Int64.max)
        #expect(SafeSum.total([Int64.min, -1]) == Int64.min)
        #expect(SafeSum.difference(10, 4) == 6)
        #expect(SafeSum.difference(Int64.max, -1) == Int64.max)
        #expect(SafeSum.difference(Int64.min, 1) == Int64.min)
    }
}
```

`Tests/CleanerFeaturesTests/ProgressRelayTests.swift`:

```swift
import Testing
@testable import CleanerFeatures

@MainActor
struct ProgressRelayTests {
    @Test func valuesReportedFromOtherThreadsArriveInOrderOnTheMainActor() async {
        var applied: [Int] = []
        let relay = ProgressRelay<Int> { value in
            MainActor.assertIsolated()
            applied.append(value)
        }
        let report = relay.report

        await Task.detached {
            for value in 1...200 { report(value) }
        }.value
        await relay.finish()

        #expect(applied == Array(1...200))
    }

    @Test func finishWithoutValuesReturns() async {
        var applied = 0
        let relay = ProgressRelay<Int> { _ in applied += 1 }

        await relay.finish()

        #expect(applied == 0)
    }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run (da `swift/MjmCleanerKit`): `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: il caricamento del package fallisce prima della compilazione, per esempio con `public headers ("include") directory path for 'CleanerFeatures' is invalid`: il target non ha ancora sorgenti Swift, quindi SwiftPM lo tratta come un target C. È la stessa forma di RED del Task 1 del piano 1. Se il messaggio è diverso, basta che la build fallisca a causa di `CleanerFeatures`.

- [ ] **Step 4: Implementare i formati**

`Sources/CleanerFeatures/Support/Formatting.swift`:

```swift
import Foundation

/// Numeri, dimensioni e date dell'interfaccia, come `ViewModelBase.FormatBytes`, il formato `N0` e
/// `d MMM yyyy, HH:mm` del C# con la cultura it-IT. Scritti a mano e non con le tabelle ICU del
/// sistema: lo stesso testo su ogni macchina e nei test (spec §6.5; `ByteCountFormatter` lavora in
/// base 1000 e mostrerebbe numeri diversi).
public enum Formatting {
    /// Abbreviazioni dei mesi di it-IT, come le scrive .NET (misurato: «6 set 2026, 09:05»).
    private static let months = ["gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic"]

    /// `FormatBytes`: base 1024, unità B/KB/MB/GB/TB, al massimo un decimale con la virgola.
    /// L'arrotondamento è lontano dallo zero come il formato `0.#` di .NET: 1280 B → «1,3 KB».
    public static func bytes(_ bytes: Int64) -> String {
        var value = Double(bytes)
        var scaledUnit: String?
        for next in ["KB", "MB", "GB", "TB"] where value >= 1024 {
            value /= 1024
            scaledUnit = next
        }

        guard let unit = scaledUnit else { return "\(bytes) B" }

        // Il valore è al massimo 8 388 608 (Int64.max in TB): i decimi stanno in un Int64.
        let tenths = Int64((value * 10).rounded(.toNearestOrAwayFromZero))
        let whole = tenths / 10
        let fraction = tenths % 10
        return fraction == 0 ? "\(whole) \(unit)" : "\(whole),\(fraction) \(unit)"
    }

    /// Il formato `N0` di it-IT: punto come separatore delle migliaia, nessun decimale.
    public static func integer<Number: BinaryInteger>(_ value: Number) -> String {
        let digits = Array(String(value.magnitude))
        var grouped = ""
        for (offset, digit) in digits.enumerated() {
            if offset > 0 && (digits.count - offset) % 3 == 0 {
                grouped.append(".")
            }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }

    /// Concordanza minima singolare/plurale: evita «1 elementi» quando `count` è 1.
    public static func plural(_ count: Int, _ singular: String, _ plural: String) -> String {
        count == 1 ? singular : plural
    }

    /// I secondi interi di una durata, come `{0:0}` su `TimeSpan.TotalSeconds` (2,5 → «3»).
    public static func seconds(_ duration: Duration) -> String {
        let parts = duration.components
        let total = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return String(Int64(total.rounded(.toNearestOrAwayFromZero)))
    }

    /// Data dello storico in ora locale, `d MMM yyyy, HH:mm` con i mesi di it-IT: i timestamp
    /// sono salvati in UTC e resi in ora locale, altrimenti il cambio d'ora riordinerebbe lo storico.
    public static func historyDate(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let monthIndex = (parts.month ?? 1) - 1
        let month = months.indices.contains(monthIndex) ? months[monthIndex] : ""
        return String(
            format: "%ld %@ %ld, %02ld:%02ld",
            parts.day ?? 0, month, parts.year ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}
```

- [ ] **Step 5: Implementare confronti, somme e avanzamento**

`Sources/CleanerFeatures/Support/FeatureText.swift`:

```swift
import CleanerCore
import Darwin
import Foundation

/// Confronti di testo e messaggi d'errore dei modelli. `==` fra `String` confronta per equivalenza
/// canonica (NFC = NFD): per decidere si confrontano i byte UTF-8, come `StringComparison.Ordinal`
/// del C#. Stessa disciplina di `XcodeText` e `DockerText` del Core, che sono interni al Core.
enum FeatureText {
    /// `string.Equals(a, b, StringComparison.Ordinal)`.
    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.elementsEqual(rhs.utf8)
    }

    /// Chiave per `Set`/`Dictionary` con la semantica di `StringComparer.Ordinal`.
    static func ordinalKey(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// `text.StartsWith(prefix, StringComparison.Ordinal)`.
    static func hasOrdinalPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// `Distinct()` con il comparatore predefinito (ordinale): resta la prima occorrenza, nell'ordine.
    static func distinct(_ texts: [String]) -> [String] {
        var seen = Set<[UInt8]>()
        return texts.filter { seen.insert(ordinalKey($0)).inserted }
    }

    /// Il testo di `ex.Message` mostrato nelle pagine. Gli errori del filesystem usano il testo di
    /// sistema dell'errno (spec §5.3), come `XcodeText.message` nel Core.
    static func message(_ error: any Error) -> String {
        switch error {
        case let error as FileSystemError:
            return error.message
        case let error as ProcessLaunchError:
            return String(cString: strerror(error.code))
        case is CancellationError:
            return String(localized: "operazione annullata", bundle: .module)
        case let error as any LocalizedError:
            return error.errorDescription ?? String(describing: error)
        default:
            return String(describing: error)
        }
    }
}
```

`Sources/CleanerFeatures/Support/SafeSum.swift`:

```swift
/// Somme e differenze di byte che non vanno mai in trap. `Sum()` del C# lanciava
/// `OverflowException` e la pagina restava senza totale; in Swift `+` arresterebbe l'app. Le somme
/// saturano a `Int64.max`/`Int64.min`, un valore che resta comunque leggibile (registro di parità).
enum SafeSum {
    static func total<Values: Sequence>(_ values: Values) -> Int64 where Values.Element == Int64 {
        var sum: Int64 = 0
        for value in values {
            let (result, overflow) = sum.addingReportingOverflow(value)
            sum = overflow ? (value > 0 ? .max : .min) : result
        }
        return sum
    }

    /// `minuend - subtrahend`, saturata.
    static func difference(_ minuend: Int64, _ subtrahend: Int64) -> Int64 {
        let (result, overflow) = minuend.subtractingReportingOverflow(subtrahend)
        guard overflow else { return result }
        return subtrahend < 0 ? .max : .min
    }
}
```

`Sources/CleanerFeatures/Support/ProgressRelay.swift`:

```swift
/// Porta sul main actor, nell'ordine in cui arriva, l'avanzamento che il Core segnala dai propri
/// thread (spec §4.2: `IProgress<T>` → callback `@Sendable` consumato dal modello sul `MainActor`).
/// Un `Task { @MainActor in … }` per ogni valore non garantirebbe l'ordine: qui un solo
/// consumatore legge un `AsyncStream`.
@MainActor
final class ProgressRelay<Value: Sendable> {
    private let continuation: AsyncStream<Value>.Continuation
    private let consumer: Task<Void, Never>

    init(_ apply: @escaping @MainActor (Value) -> Void) {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self)
        self.continuation = continuation
        consumer = Task { @MainActor in
            for await value in stream {
                apply(value)
            }
        }
    }

    /// Il callback da passare al Core: si può chiamare da qualunque thread.
    var report: @Sendable (Value) -> Void {
        let continuation = continuation
        return { continuation.yield($0) }
    }

    /// Chiude il flusso e attende che ogni valore già segnalato sia stato applicato.
    func finish() async {
        continuation.finish()
        await consumer.value
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter CleanerFeaturesTests`
Expected: `Test run with 10 tests in 3 suites passed` (5 di `FormattingTests`, 3 di `FeatureTextTests`, 2 di `ProgressRelayTests`), nessun warning.

Run: `swift test -Xswiftc -warnings-as-errors`
Expected: i 496 test di `CleanerCoreTests` restano verdi (`Test run with 496 tests`); in totale 506.

- [ ] **Step 7: Registro di parità e commit**

In `docs/superpowers/porting/2026-10-13-parity.md`, subito dopo la riga «Altri test solo Swift sono dentro i file portati e sono indicati nella colonna Note delle rispettive righe.», aggiungere:

```markdown

### Test solo Swift di CleanerFeaturesTests

| File Swift | Test | Contenuto |
|---|---|---|
| FormattingTests.swift | 5 | `FormatBytes`, `N0`, concordanza, secondi e date dello storico con gli esiti misurati su .NET 10 |
| FeatureTextTests.swift | 3 | confronti ordinali (NFC ≠ NFD), testo degli errori come `ex.Message`, somme che saturano invece di andare in trap |
| ProgressRelayTests.swift | 2 | avanzamento segnalato da altri thread applicato sul main actor, nell'ordine |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Formati dei numeri nei modelli | `FormatBytes` con `string.Format(it-IT, "{0:0.#}")`; `N0` con la cultura corrente (`en-IT` su questo Mac, stesso separatore di it-IT) | `Formatting`, scritto a mano: decimi arrotondati lontano dallo zero, virgola e punto fissi | equivalente sui casi misurati; oltre 100 TB il doppio arrotondamento di .NET a 15 cifre potrebbe in teoria divergere |
| Somme di byte nei modelli | `Sum()` lancia `OverflowException` e la pagina resta senza totale | `SafeSum` satura a `Int64.max` (follow-up del piano 3) | voluta |
```

```bash
git add swift/MjmCleanerKit/Package.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Resources/Localizable.xcstrings \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Support/Formatting.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Support/FeatureText.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Support/SafeSum.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Support/ProgressRelay.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/FormattingTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/FeatureTextTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ProgressRelayTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): add the CleanerFeatures target with formatting and progress utilities

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `AppEnvironment` e giunture verso l'app

Il porting di `AppServices`: lo stesso grafo di oggetti, con un'unica fonte per la home. Insieme arrivano i protocolli che l'app implementerà (`FolderPicking`, `AppearanceApplying`), la navigazione di base (`Navigating`), il testo della vista d'errore all'avvio (`StartupFailure`), un protocollo per il servizio Docker e i doppi di test condivisi da tutti i task successivi.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestHome.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`
- Reference: `src/MjmCleaner.App/Services/AppServices.cs`, `Services/FolderPicker.cs`, `Services/AppearanceController.cs`, `App.axaml.cs` (`CreateMainWindowAsync`), `Views/FatalErrorWindow.cs`, `ViewModels/XcodeViewModel.cs` (`IXcodeNavigation`); `tests/MjmCleaner.App.Tests/TestHome.cs`

**Interfaces:**
- Consumes: i costruttori del Core — `LocalFileSystem()`, `SystemWallClock()`, `FileSystemLinkInspector()`, `DenyList(homeDirectory:) throws`, `PathGuard(denyList:links:homeDirectory:) throws`, `RuleScanner(fileSystem:pathGuard:links:clock:)`, `ProcessRunner()`, `DockerCli(runner:binaryPath:)`, `DockerBinaryLocator.find(_:homeDirectory:)`, `DockerCleanupService(collector:scanner:disk:executor:)`, `DockerInventoryCollector(cli:fileSystem:)`, `ProjectReferenceScanner(fileSystem:)`, `DiskUsageProbe(runner:fileSystem:diskImagePath:)`, `DiskUsageProbe.defaultPath(_:)`, `DockerCleanExecutor(cli:clock:)`, `XcodeCli(runner:binaryPath:)`, `XcodeCli.locateBinary(_:)`, `XcodeSizeProbe(fileSystem:runner:links:homeDirectory:)`, `XcodeFileScanner(fileSystem:ruleScanner:pathGuard:links:sizeProbe:homeDirectory:)`, `XcodeInventoryCollector(cli:fileScanner:)`, `XcodeRunningProbe(runner:)`, `XcodeCleanExecutor(cli:collector:cleanEngine:measures:runningProbe:clock:)`, `XcodeCleanupService(collector:runningProbe:executor:)`, `CleanEngine(fileSystem:pathGuard:clock:)`, `ScanEngine(scanner:)`, `HistoryStore(databaseFile:)` + `initialize()`, `SessionLogWriter(fileSystem:paths:)`, `SettingsStore(fileSystem:paths:)`, `RunningAppsProbe.forCurrentMachine(runner:home:)`, `PathExpander(homeDirectory:tempDirectory:) throws`, `CategoryCatalog.build(_:_:)`, `AppPaths.forBundleIdentifier(_:)`; `FeatureText.message` (Task 1).
- Produces:
  - `public protocol DockerCleanupServing: Sendable` — `analyze(_ projectRoots: [String]) async throws -> DockerAnalysis`, `execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult`, `measureDisk() async throws -> DockerDiskUsage`; `DockerCleanupService` vi si conforma
  - `public struct AppEnvironment: Sendable` — proprietà `scan`, `clean`, `history`, `sessionLog`, `settings`, `runningApps` (protocolli del Core), `docker: any DockerCleanupServing`, `xcode: any XcodeCleanupServing`, `paths: AppPaths`, `clock: any WallClock`; `init(scan:clean:history:sessionLog:settings:runningApps:docker:xcode:paths:clock:expander:)`; `categories() -> [CleanupCategory]`; `expandedProjectRoots() -> [String]`; `static func defaultPaths(bundleIdentifier: String?) -> AppPaths`; `static func live(paths: AppPaths, home: String = NSHomeDirectory(), tempDirectory: String = NSTemporaryDirectory()) async throws -> AppEnvironment`
  - `@MainActor public protocol FolderPicking` — `pickFolder(title: String) async -> String?`
  - `@MainActor public protocol AppearanceApplying` — `apply(_ preference: AppearancePreference)`
  - `@MainActor public protocol Navigating: AnyObject` — `startOver()`, `refreshTotal() async throws`
  - `public enum StartupFailure` — `static var title: String`, `static func message(paths: AppPaths, error: any Error) -> String`
  - test: `Recorder<Value>`, `Gate<Value>` (`open(_:)`, `open()`, `wait() async -> Value`, `isOpen`), `UnexpectedTestError(description:)`, `FixedWallClock(now:)`, `TemporaryDirectory` (`path`, `remove()`), `makeReport(…)`, `makeCategory(_:name:parent:risk:)`, `makeItem(_:size:root:)`; doppi `FakeSettingsStore`, `FakeHistory`, `FakeSessionLog`, `FakeScan`, `FakeClean`, `FakeRunningApps`, `FakeDocker`, `IdleXcode`; `makeEnvironment(scan:clean:history:sessionLog:settings:runningApps:docker:xcode:) throws -> AppEnvironment` (home finta `/Users/tester`); `TestHome.create(settings:) async throws -> TestHome` con `environment` e `remove()`

Note di porting:
- `AppServices.CreateAsync` leggeva la home da `Environment.SpecialFolder.UserProfile` in più punti; qui `live` la riceve una volta sola (registro del piano 1, revisione finale: «unica fonte della home in AppEnvironment») e la passa a `DenyList`, `PathGuard`, `DockerBinaryLocator`, `DiskUsageProbe`, `XcodeSizeProbe`, `XcodeFileScanner`, `RunningAppsProbe` e `PathExpander`.
- In C# `BuildCategories()` ed `ExpandedProjectRoots()` creavano ogni volta `PathExpander.ForCurrentUser()`; qui l'espansore nasce con l'ambiente, sulla stessa home.
- `live` lancia gli errori di `DenyList`, `PathGuard`, `PathExpander` (`InvalidConfiguration`) e di `HistoryStore.initialize()` (filesystem o SQLite). Nel piano 4b l'app li mostra con `StartupFailure`, come `FatalErrorWindow`. In C# solo `IOException`, `UnauthorizedAccessException` e `SqliteException` arrivavano alla finestra d'errore; dove intercettarli lo decide il piano 4b.
- `PendingJournal` ha un inizializzatore interno al Core: i doppi lo ottengono da un `SessionLogWriter` vero su una cartella temporanea (`FakeSessionLog(journalDirectory:)`), senza toccare il Core.

- [ ] **Step 1: Scrivere i test e i doppi condivisi (falliscono)**

`Tests/CleanerFeaturesTests/Support/TestSupport.swift`:

```swift
import CleanerCore
import Foundation
import Synchronization

/// Raccoglie valori da callback `@Sendable` e da doppi chiamati fuori dal main actor.
final class Recorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

/// Un segnale che si apre una volta sola, con un valore: chi attende prima dell'apertura resta
/// sospeso, chi arriva dopo riceve subito il valore. Sostituisce i `TaskCompletionSource` del C#.
final class Gate<Value: Sendable>: Sendable {
    private struct State {
        var value: Value?
        var waiters: [CheckedContinuation<Value, Never>] = []
    }

    private let state = Mutex(State())

    var isOpen: Bool {
        state.withLock { $0.value != nil }
    }

    func open(_ value: Value) {
        let waiters = state.withLock { state -> [CheckedContinuation<Value, Never>] in
            guard state.value == nil else { return [] }
            state.value = value
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters {
            waiter.resume(returning: value)
        }
    }

    func wait() async -> Value {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state -> Value? in
                if let value = state.value { return value }
                state.waiters.append(continuation)
                return nil
            }
            if let ready {
                continuation.resume(returning: ready)
            }
        }
    }
}

extension Gate where Value == Void {
    func open() {
        open(())
    }
}

/// Un errore qualunque lanciato da un doppio, come `new IOException("…")` nei test C#.
struct UnexpectedTestError: Error, CustomStringConvertible {
    let description: String
}

struct FixedWallClock: WallClock {
    let now: Date
}

/// Cartella temporanea reale: la composizione vera scrive `history.db` e i log su disco.
struct TemporaryDirectory {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        path = PathText.join(PathText.trimmingTrailingSlashes(base), "mjm-cleaner-features-" + UUID().uuidString)
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Un `CleanReport` vuoto o con i valori indicati.
func makeReport(
    bytesFreed: Int64 = 0,
    itemsDeleted: Int = 0,
    itemsFailed: Int = 0,
    duration: Duration = .zero,
    categories: [CategoryCleanResult] = [],
    errors: [ScanError] = [],
    deletedPaths: [String] = []
) -> CleanReport {
    CleanReport(
        startedAt: Date(timeIntervalSince1970: 1_790_000_000),
        duration: duration,
        bytesFreed: bytesFreed,
        itemsDeleted: itemsDeleted,
        itemsFailed: itemsFailed,
        categories: categories,
        errors: errors,
        deletedPaths: deletedPaths)
}

func makeCategory(_ id: String, name: String? = nil, parent: String? = nil, risk: RiskLevel = .low) -> CleanupCategory {
    CleanupCategory(
        id: id, displayName: name ?? id, description: "descrizione", risk: risk,
        selectedByDefault: false, parentId: parent, rules: [])
}

func makeItem(_ path: String, size: Int64 = 100, root: String = "/Users/tester/Library/Caches") -> ScanItem {
    ScanItem(path: path, sizeBytes: size, isDirectory: false, declaredRoot: root)
}
```

`Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`:

```swift
import CleanerCore
import CleanerFeatures
import Foundation
import Synchronization

/// Doppi dei servizi del Core condivisi dai test dei modelli. Lo stato sta in `Mutex`: i servizi
/// sono `Sendable` e vengono chiamati anche fuori dal main actor.

final class FakeSettingsStore: SettingsStoring {
    private struct State {
        var current: CleanerSettings
        var saves = 0
        var failure: (any Error)?
    }

    private let state: Mutex<State>

    init(_ initial: CleanerSettings = CleanerSettings()) {
        state = Mutex(State(current: initial))
    }

    var current: CleanerSettings { state.withLock { $0.current } }
    var saves: Int { state.withLock { $0.saves } }

    func failSaves(with error: any Error) {
        state.withLock { $0.failure = error }
    }

    func load() -> CleanerSettings {
        state.withLock { $0.current }
    }

    func save(_ settings: CleanerSettings) throws {
        try state.withLock { state in
            state.saves += 1
            if let failure = state.failure { throw failure }
            state.current = settings
        }
    }
}

/// Registra in `events` l'ordine delle operazioni ("save", "total"), condiviso col log di sessione.
final class FakeHistory: HistoryStoring {
    private struct State {
        var sessions: [CleanSessionSummary] = []
        var total: Int64 = 0
        var saved: [CleanReport] = []
        var saveFailure: (any Error)?
        var readFailure: (any Error)?
    }

    let events: Recorder<String>
    private let state = Mutex(State())

    init(events: Recorder<String> = Recorder()) {
        self.events = events
    }

    var saves: Int { state.withLock { $0.saved.count } }
    var saved: [CleanReport] { state.withLock { $0.saved } }

    func setSessions(_ sessions: [CleanSessionSummary]) { state.withLock { $0.sessions = sessions } }
    func setTotal(_ total: Int64) { state.withLock { $0.total = total } }
    func failSaves(with error: any Error) { state.withLock { $0.saveFailure = error } }
    func failReads(with error: any Error) { state.withLock { $0.readFailure = error } }

    func initialize() async throws {}

    func save(_ report: CleanReport) async throws -> Int64 {
        events.append("save")
        return try state.withLock { state in
            state.saved.append(report)
            if let failure = state.saveFailure { throw failure }
            return Int64(state.saved.count)
        }
    }

    func sessions(limit: Int) async throws -> [CleanSessionSummary] {
        try state.withLock { state in
            if let failure = state.readFailure { throw failure }
            return Array(state.sessions.prefix(limit))
        }
    }

    func totalBytesFreed() async throws -> Int64 {
        events.append("total")
        return try state.withLock { state in
            if let failure = state.readFailure { throw failure }
            return state.total
        }
    }
}

/// Log di sessione finto. Con `journalDirectory` i diari sono veri (`SessionLogWriter` su una
/// cartella temporanea), perché `PendingJournal` si crea solo dal Core; senza, `openJournal`
/// restituisce `nil` come quando la cartella dei log non è scrivibile.
final class FakeSessionLog: SessionLogWriting {
    private struct State {
        var writes: [Int64] = []
        var discarded: [String] = []
        var writeFailure: (any Error)?
    }

    let events: Recorder<String>
    private let journals: SessionLogWriter?
    private let state = Mutex(State())

    init(events: Recorder<String> = Recorder(), journalDirectory: String? = nil) {
        self.events = events
        journals = journalDirectory.map {
            SessionLogWriter(fileSystem: LocalFileSystem(), paths: AppPaths(supportDirectory: $0))
        }
    }

    var writes: Int { state.withLock { $0.writes.count } }
    var discarded: [String] { state.withLock { $0.discarded } }

    func failWrites(with error: any Error) {
        state.withLock { $0.writeFailure = error }
    }

    func write(sessionId: Int64, report: CleanReport) async throws {
        events.append("write")
        try state.withLock { state in
            if let failure = state.writeFailure { throw failure }
            state.writes.append(sessionId)
        }
    }

    func openJournal(startedAt: Date) -> PendingJournal? {
        events.append("open")
        return journals?.openJournal(startedAt: startedAt)
    }

    func discard(_ journal: PendingJournal) {
        events.append("discard")
        state.withLock { $0.discarded.append(journal.path) }
        journals?.discard(journal)
    }
}

/// Analisi finta: restituisce `results`, lancia `failure` o, con `waitsForCancellation`, resta
/// sospesa finché il task non viene annullato e allora lancia `CancellationError` come `ScanEngine`.
/// L'attesa dura al massimo 5 secondi: se l'annullamento non arriva il test fallisce invece di bloccarsi.
final class FakeScan: ScanPerforming {
    private struct State {
        var results: [CategoryScanResult] = []
        var failure: (any Error)?
        var waitsForCancellation = false
        var progress: [ScanProgress] = []
        var scanned: [[String]] = []
    }

    let started = Gate<Void>()
    private let state = Mutex(State())

    var scannedCategoryIds: [[String]] { state.withLock { $0.scanned } }

    func respond(with results: [CategoryScanResult], progress: [ScanProgress] = []) {
        state.withLock {
            $0.results = results
            $0.progress = progress
        }
    }

    func fail(with error: any Error) { state.withLock { $0.failure = error } }
    func waitForCancellation() { state.withLock { $0.waitsForCancellation = true } }

    func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult] {
        let current = state.withLock { state -> State in
            state.scanned.append(categories.map(\.id))
            return state
        }
        started.open()
        for update in current.progress {
            progress?(update)
        }
        if current.waitsForCancellation {
            try await Task.sleep(for: .seconds(5))
        }
        if let failure = current.failure { throw failure }
        return current.results
    }
}

/// Pulizia finta: registra selezioni e diario, segnala un avanzamento per elemento e restituisce
/// `result`. Con `waitsForCancellation` resta sospesa finché il task non viene annullato (al massimo
/// 5 secondi) e poi restituisce `result` come resoconto parziale, come `CleanEngine`;
/// `observedCancellation` dice se l'annullamento è arrivato.
final class FakeClean: CleanPerforming {
    private struct State {
        var result = makeReport()
        var waitsForCancellation = false
        var selections: [[CategorySelection]] = []
        var receivedJournal: [Bool] = []
        var observedCancellation: [Bool] = []
    }

    let started = Gate<Void>()
    private let state = Mutex(State())

    var selections: [[CategorySelection]] { state.withLock { $0.selections } }
    var receivedJournal: [Bool] { state.withLock { $0.receivedJournal } }
    var observedCancellation: [Bool] { state.withLock { $0.observedCancellation } }

    func respond(with result: CleanReport) { state.withLock { $0.result = result } }
    func waitForCancellation() { state.withLock { $0.waitsForCancellation = true } }

    func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport {
        let current = state.withLock { state -> State in
            state.selections.append(selections)
            state.receivedJournal.append(journal != nil)
            return state
        }
        started.open()

        let items = selections.flatMap(\.items)
        for (index, item) in items.enumerated() {
            journal?.recordDeleted(item.path)
            progress?(CleanProgress(currentPath: item.path, itemsDone: index + 1, itemsTotal: items.count, bytesFreed: 0))
        }
        if current.waitsForCancellation {
            try? await Task.sleep(for: .seconds(5))
            let cancelled = Task.isCancelled
            state.withLock { $0.observedCancellation.append(cancelled) }
        }
        return current.result
    }
}

final class FakeRunningApps: RunningAppsProbing {
    private let names: [String]

    init(_ names: [String] = []) {
        self.names = names
    }

    func affectedApps(_ paths: [String]) async -> [String] {
        names
    }
}

/// Docker finto: le analisi si consumano in ordine (l'ultima resta), l'esecuzione restituisce
/// `executeResult` o lancia `executeFailure`.
final class FakeDocker: DockerCleanupServing {
    private struct State {
        var analyses: [Result<DockerAnalysis, any Error>] = []
        var executeResult: Result<DockerCleanResult, any Error> = .success(DockerCleanResult(
            report: makeReport(), before: .empty, after: .empty, daemonLost: false))
        var disk = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
        var analyzedRoots: [[String]] = []
        var executed: [[DockerCandidate]] = []
    }

    private let state = Mutex(State())

    var analyzedRoots: [[String]] { state.withLock { $0.analyzedRoots } }
    var executed: [[DockerCandidate]] { state.withLock { $0.executed } }

    func enqueue(_ analysis: Result<DockerAnalysis, any Error>) { state.withLock { $0.analyses.append(analysis) } }
    func respond(with result: Result<DockerCleanResult, any Error>) { state.withLock { $0.executeResult = result } }
    func setDiskAfter(_ disk: DockerDiskUsage) { state.withLock { $0.disk = disk } }

    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let next = state.withLock { state -> Result<DockerAnalysis, any Error>? in
            state.analyzedRoots.append(projectRoots)
            return state.analyses.count > 1 ? state.analyses.removeFirst() : state.analyses.first
        }
        guard let next else { throw DockerUnavailableError("nessuna analisi preparata") }
        return try next.get()
    }

    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        let result = state.withLock { state -> Result<DockerCleanResult, any Error> in
            state.executed.append(selected)
            return state.executeResult
        }
        for (index, candidate) in selected.enumerated() {
            progress?(CleanProgress(currentPath: candidate.displayName, itemsDone: index + 1, itemsTotal: selected.count, bytesFreed: 0))
        }
        return try result.get()
    }

    func measureDisk() async throws -> DockerDiskUsage {
        state.withLock { $0.disk }
    }
}

/// Xcode inattivo, per i test che non aprono la pagina Xcode.
struct IdleXcode: XcodeCleanupServing {
    func analyze() async throws -> XcodeSnapshot { .empty }

    func execute(_ plan: XcodeConfirmedPlan, progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> XcodeCleanResult {
        XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: nil, freeBytesAfter: nil, warnings: [])
    }
}

/// Un `AppEnvironment` di soli doppi, con la home finta `/Users/tester`.
func makeEnvironment(
    scan: any ScanPerforming = FakeScan(),
    clean: any CleanPerforming = FakeClean(),
    history: any HistoryStoring = FakeHistory(),
    sessionLog: any SessionLogWriting = FakeSessionLog(),
    settings: any SettingsStoring = FakeSettingsStore(),
    runningApps: any RunningAppsProbing = FakeRunningApps(),
    docker: any DockerCleanupServing = FakeDocker(),
    xcode: any XcodeCleanupServing = IdleXcode()
) throws -> AppEnvironment {
    AppEnvironment(
        scan: scan,
        clean: clean,
        history: history,
        sessionLog: sessionLog,
        settings: settings,
        runningApps: runningApps,
        docker: docker,
        xcode: xcode,
        paths: AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner"),
        clock: FixedWallClock(now: Date(timeIntervalSince1970: 1_790_000_000)),
        expander: try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/private/var/folders/zz/T"))
}
```

`Tests/CleanerFeaturesTests/Support/TestHome.swift`:

```swift
import CleanerCore
import CleanerFeatures

/// Porting di `TestHome.cs`: una cartella dati temporanea per i test che usano la composizione vera
/// (`AppEnvironment.live`). Tutto ciò che scrive sta sotto di essa e sparisce con `remove()`.
struct TestHome {
    let directory: TemporaryDirectory
    let environment: AppEnvironment

    static func create(settings: CleanerSettings? = nil) async throws -> TestHome {
        let directory = try TemporaryDirectory()
        let environment = try await AppEnvironment.live(paths: AppPaths(supportDirectory: directory.path))
        if let settings {
            try environment.settings.save(settings)
        }
        return TestHome(directory: directory, environment: environment)
    }

    func remove() {
        directory.remove()
    }
}
```

`Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`:

```swift
import CleanerCore
import Darwin
import Foundation
import Testing
@testable import CleanerFeatures

/// La composizione (`AppServices.CreateAsync`) e la vista d'errore dell'avvio (`FatalErrorWindow`).
struct AppEnvironmentTests {
    @Test func liveCompositionKeepsEveryFileUnderTheGivenDataFolder() async throws {
        let home = try await TestHome.create()
        defer { home.remove() }
        let paths = home.environment.paths

        #expect(FileManager.default.fileExists(atPath: paths.databaseFile))
        #expect(try await home.environment.history.totalBytesFreed() == 0)

        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        try home.environment.settings.save(settings)

        #expect(FileManager.default.fileExists(atPath: paths.settingsFile))
        #expect(home.environment.settings.load().projectRoots == ["~/src"])
    }

    @Test func categoriesAndProjectRootsFollowTheCurrentSettings() throws {
        var initial = CleanerSettings()
        initial.projectRoots = ["~/src", "/Volumes/Dati/progetti"]
        let environment = try makeEnvironment(settings: FakeSettingsStore(initial))

        #expect(environment.expandedProjectRoots() == ["/Users/tester/src", "/Volumes/Dati/progetti"])
        #expect(environment.categories().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads-large",
        ])
    }

    @Test func defaultPathsUseTheBundleIdentifierOrTheProvisionalOne() {
        #expect(AppEnvironment.defaultPaths(bundleIdentifier: "com.esempio.app") == AppPaths.forBundleIdentifier("com.esempio.app"))
        #expect(AppEnvironment.defaultPaths(bundleIdentifier: nil) == AppPaths.forBundleIdentifier("com.mjm.cleaner"))
    }

    @Test func liveCompositionFailsWhenTheDataFolderIsUnusable() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let blocker = PathText.join(directory.path, "file")
        try Data().write(to: URL(fileURLWithPath: blocker))
        let paths = AppPaths(supportDirectory: PathText.join(blocker, "dati"))

        await #expect(throws: (any Error).self) {
            _ = try await AppEnvironment.live(paths: paths)
        }
    }

    @Test func startupFailureNamesThePathAndTheReason() {
        let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")

        let message = StartupFailure.message(paths: paths, error: FileSystemError(code: EACCES, path: paths.databaseFile))

        #expect(StartupFailure.title == "Impossibile accedere ai dati dell'applicazione")
        #expect(message == "Percorso: /Users/tester/Library/Application Support/com.mjm.cleaner\n\nMotivo: \(String(cString: strerror(EACCES)))")
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find type 'AppEnvironment' in scope` e `cannot find 'AppEnvironment' in scope` (il compilatore può segnalare anche `DockerCleanupServing`).

- [ ] **Step 3: Implementare il protocollo Docker e le giunture verso l'app**

`Sources/CleanerFeatures/Environment/DockerCleanupServing.swift`:

```swift
import CleanerCore

/// Il servizio Docker visto dalla pagina. In C# la pagina usava la classe concreta
/// `DockerCleanupService` e nessun test la esercitava; il protocollo permette di verificare la
/// pagina con un doppio, senza toccare il Core.
public protocol DockerCleanupServing: Sendable {
    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult
    func measureDisk() async throws -> DockerDiskUsage
}

extension DockerCleanupService: DockerCleanupServing {}
```

`Sources/CleanerFeatures/Environment/PlatformServices.swift`:

```swift
import CleanerCore

/// `IFolderPicker`: il pannello di scelta delle cartelle appartiene all'app (`NSOpenPanel`), il
/// modello chiede solo un percorso (spec §4.1, §6.6).
@MainActor
public protocol FolderPicking {
    /// Percorso locale della cartella scelta, o `nil` se l'utente annulla.
    func pickFolder(title: String) async -> String?
}

/// `IAppearanceController`: l'aspetto vale per tutta l'app, quindi per ogni finestra e sheet
/// (`NSApp.appearance`, spec §6.4).
@MainActor
public protocol AppearanceApplying {
    func apply(_ preference: AppearancePreference)
}

/// Ciò che ogni pagina chiede alla finestra principale: `IXcodeNavigation` del C# senza `GoTo`,
/// che diventa un metodo per destinazione nei protocolli delle singole sezioni.
@MainActor
public protocol Navigating: AnyObject {
    /// Torna al passo 1 del wizard.
    func startOver()

    /// Aggiorna il contatore «Spazio liberato» della sidebar.
    func refreshTotal() async throws
}

/// La vista d'errore mostrata quando la composizione fallisce all'avvio (`FatalErrorWindow`):
/// cartella dati non scrivibile, database corrotto. Dice cosa è andato storto e dove.
public enum StartupFailure {
    public static var title: String {
        String(localized: "Impossibile accedere ai dati dell'applicazione", bundle: .module)
    }

    public static func message(paths: AppPaths, error: any Error) -> String {
        let reason = FeatureText.message(error)
        return String(localized: "Percorso: \(paths.supportDirectory)\n\nMotivo: \(reason)", bundle: .module)
    }
}
```

- [ ] **Step 4: Implementare `AppEnvironment`**

`Sources/CleanerFeatures/Environment/AppEnvironment.swift`:

```swift
import CleanerCore
import Foundation

/// Porting di `AppServices`: la composizione manuale delle dipendenze. Per un'applicazione con un
/// solo grafo di oggetti un contenitore di inversione del controllo aggiungerebbe solo
/// indirezione. I servizi sono protocolli del Core, così i test dei modelli usano doppi.
public struct AppEnvironment: Sendable {
    public let scan: any ScanPerforming
    public let clean: any CleanPerforming
    public let history: any HistoryStoring
    public let sessionLog: any SessionLogWriting
    public let settings: any SettingsStoring
    public let runningApps: any RunningAppsProbing
    public let docker: any DockerCleanupServing
    public let xcode: any XcodeCleanupServing
    public let paths: AppPaths
    public let clock: any WallClock
    private let expander: PathExpander

    public init(
        scan: any ScanPerforming,
        clean: any CleanPerforming,
        history: any HistoryStoring,
        sessionLog: any SessionLogWriting,
        settings: any SettingsStoring,
        runningApps: any RunningAppsProbing,
        docker: any DockerCleanupServing,
        xcode: any XcodeCleanupServing,
        paths: AppPaths,
        clock: any WallClock,
        expander: PathExpander
    ) {
        self.scan = scan
        self.clean = clean
        self.history = history
        self.sessionLog = sessionLog
        self.settings = settings
        self.runningApps = runningApps
        self.docker = docker
        self.xcode = xcode
        self.paths = paths
        self.clock = clock
        self.expander = expander
    }

    /// `BuildCategories()`: il catalogo con le impostazioni correnti.
    public func categories() -> [CleanupCategory] {
        CategoryCatalog.build(settings.load(), expander)
    }

    /// Le stesse cartelle progetto di bin/obj, espanse: dove cercare le immagini Docker citate.
    public func expandedProjectRoots() -> [String] {
        settings.load().projectRoots.map(expander.expand)
    }

    /// `~/Library/Application Support/<bundle id>/` (spec §4.4). Senza bundle id, per esempio
    /// sotto `swift test`, vale quello provvisorio dell'app.
    public static func defaultPaths(bundleIdentifier: String?) -> AppPaths {
        AppPaths.forBundleIdentifier(bundleIdentifier ?? "com.mjm.cleaner")
    }

    /// `AppServices.CreateAsync`: lo stesso grafo, con un'unica fonte per la home (home e cartella
    /// temporanea si sostituiscono solo nei test). Lancia se la cartella dati o lo storico non si
    /// aprono: l'app mostra allora la vista d'errore (`StartupFailure`).
    public static func live(
        paths: AppPaths,
        home: String = NSHomeDirectory(),
        tempDirectory: String = NSTemporaryDirectory()
    ) async throws -> AppEnvironment {
        let fileSystem = LocalFileSystem()
        let clock = SystemWallClock()
        let links = FileSystemLinkInspector()
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
        let scanner = RuleScanner(fileSystem: fileSystem, pathGuard: pathGuard, links: links, clock: clock)

        // Docker passa solo dalla CLI: nessun file sotto la cartella di Docker Desktop viene mai
        // cancellato (la deny-list resta invariata); di Docker.raw si legge soltanto la dimensione.
        let processes = ProcessRunner()
        let dockerCli = DockerCli(runner: processes, binaryPath: DockerBinaryLocator.find(fileSystem, homeDirectory: home))
        let docker = DockerCleanupService(
            collector: DockerInventoryCollector(cli: dockerCli, fileSystem: fileSystem),
            scanner: ProjectReferenceScanner(fileSystem: fileSystem),
            disk: DiskUsageProbe(runner: processes, fileSystem: fileSystem, diskImagePath: DiskUsageProbe.defaultPath(home)),
            executor: DockerCleanExecutor(cli: dockerCli, clock: clock))

        // L'esecutore Xcode usa lo stesso collettore e lo stesso PathGuard della scansione
        // (AppServices.cs): ciò che rivalida prima di eliminare è ciò che l'analisi ha mostrato.
        let xcodeCli = XcodeCli(runner: processes, binaryPath: XcodeCli.locateBinary(fileSystem))
        let xcodeMeasures = XcodeSizeProbe(fileSystem: fileSystem, runner: processes, links: links, homeDirectory: home)
        let xcodeFiles = XcodeFileScanner(
            fileSystem: fileSystem, ruleScanner: scanner, pathGuard: pathGuard, links: links,
            sizeProbe: xcodeMeasures, homeDirectory: home)
        let xcodeInventory = XcodeInventoryCollector(cli: xcodeCli, fileScanner: xcodeFiles)
        let xcodeRunning = XcodeRunningProbe(runner: processes)
        let xcode = XcodeCleanupService(
            collector: xcodeInventory,
            runningProbe: xcodeRunning,
            executor: XcodeCleanExecutor(
                cli: xcodeCli,
                collector: xcodeInventory,
                cleanEngine: CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: clock),
                measures: xcodeMeasures,
                runningProbe: xcodeRunning,
                clock: clock))

        let history = HistoryStore(databaseFile: paths.databaseFile)
        try await history.initialize()

        return AppEnvironment(
            scan: ScanEngine(scanner: scanner),
            clean: CleanEngine(fileSystem: fileSystem, pathGuard: pathGuard, clock: clock),
            history: history,
            sessionLog: SessionLogWriter(fileSystem: fileSystem, paths: paths),
            settings: SettingsStore(fileSystem: fileSystem, paths: paths),
            runningApps: RunningAppsProbe.forCurrentMachine(runner: processes, home: home),
            docker: docker,
            xcode: xcode,
            paths: paths,
            clock: clock,
            expander: try PathExpander(homeDirectory: home, tempDirectory: tempDirectory))
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter CleanerFeaturesTests`
Expected: `Test run with 15 tests in 4 suites passed` (5 di `AppEnvironmentTests` più i 10 del Task 1), nessun warning. `liveCompositionKeepsEveryFileUnderTheGivenDataFolder` crea e legge davvero `history.db` e `settings.json` sotto una cartella temporanea: niente viene scritto nella cartella dati reale.

- [ ] **Step 6: Registro di parità e commit**

In fondo alla tabella «Test solo Swift di CleanerFeaturesTests», aggiungere:

```markdown
| AppEnvironmentTests.swift | 5 | composizione vera su una cartella temporanea (`history.db`, `settings.json`), categorie e cartelle progetto dalle impostazioni, cartella dati predefinita, avvio che fallisce su una cartella inutilizzabile, testo della vista d'errore |
```

Sotto la tabella `MjmCleaner.App.Tests`, sostituire la riga «Utilità (nessuna prova propria): `TestAppBuilder.cs`, `TestHome.cs` (piano 4).» con:

```markdown
Utilità (nessuna prova propria): `TestHome.cs` → `Support/TestHome.swift` (piano 4a, su `AppEnvironment.live`); `TestAppBuilder.cs` configurava Avalonia headless e non ha equivalente. I doppi `FakeHistory`, `FakeLog`, `MemoryStore`, `RecordingAppearance` e `FixedPicker`, ripetuti in più file C#, diventano doppi condivisi in `Support/` (`FakeHistory`, `FakeSessionLog`, `FakeSettingsStore`, `FakeAppearance`, `FakePicker`); `FakeXcode` e `FakeNavigation` restano annidati in `XcodeViewModelTests` come in C#.
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Servizio Docker nei modelli | la pagina usa la classe concreta `DockerCleanupService` | protocollo `DockerCleanupServing` in `CleanerFeatures`, a cui `DockerCleanupService` si conforma; il Core non cambia | per costruzione |
| Home nella composizione | `Environment.GetFolderPath(UserProfile)` e `PathExpander.ForCurrentUser()` letti più volte | `AppEnvironment.live(paths:home:tempDirectory:)` riceve la home una volta e la passa a ogni servizio | equivalente |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestHome.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): compose AppEnvironment like AppServices

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `SettingsModel`

Il contenuto dello sheet delle Impostazioni: aspetto in anteprima e ripristino, cartelle progetto e dei file grandi, soglia e età minime, Salva e Annulla.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/PlatformDoubles.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/SettingsViewModel.cs`, `Views/SettingsWindow.axaml` (limiti dei campi), `Views/SettingsWindow.axaml.cs` (`OnClosed` → `Dismiss`); `tests/MjmCleaner.App.Tests/SettingsViewModelTests.cs`, `SettingsWindowTests.cs`

**Interfaces:**
- Consumes: `SettingsStoring`, `CleanerSettings`, `AppearancePreference` (Core); `FolderPicking`, `AppearanceApplying` (Task 2); `FeatureText` (Task 1); `FakeSettingsStore`, `Recorder`, `UnexpectedTestError` (Task 2, test).
- Produces:
  - `@MainActor @Observable public final class SettingsModel: Identifiable` — `init(store: any SettingsStoring, appearance: any AppearanceApplying, folders: any FolderPicking, onSaved: @escaping @MainActor () -> Void, onClose: @escaping @MainActor () -> Void)`; proprietà `appearance`, `projectRoots`, `largeFileRoots`, `selectedProjectRoot`, `selectedLargeFileRoot`, `largeFileThresholdMegabytes`, `downloadsMinAgeDays`, `logsMinAgeDays`, `nuGetMinAgeDays`, `saveErrorText`, `hasSaveError`, `canRemoveProjectRoot`, `canRemoveLargeFileRoot`; metodi `save()`, `cancel()`, `dismiss()`, `addProjectRoot() async`, `removeProjectRoot()`, `addLargeFileRoot() async`, `removeLargeFileRoot()`; `static let thresholdMegabytesRange = 1...100_000`, `static let minAgeDaysRange = 0...3650`
  - test: `FakeAppearance` (`applied`), `FakePicker` (`init(_ result: String?)`, `titles`)

Note di porting:
- Le proprietà `IsAuto`/`IsLight`/`IsDark` servivano ai `RadioButton` di Avalonia: nel piano 4b un `Picker` si lega direttamente ad `appearance`. I test ne usano il valore (`vm.IsDark = true` → `model.appearance = .dark`).
- Il setter generato dal toolkit notificava solo i cambi di valore: `didSet` controlla `oldValue` per non riapplicare lo stesso aspetto (test solo-Swift `reapplyingTheSameAppearanceDoesNothing`).
- `CloseRequested` diventa `onClose`, che `MainModel` (Task 11) collega all'azzeramento di `settings`. Nello sheet, Salva e Annulla chiamano `onClose`; la chiusura in altri modi chiama `dismiss()`, che è idempotente come in C#.
- Salvataggio fallito (decisione dell'utente): nessuna chiamata a `onSaved`/`onClose`, `saveErrorText` = «Impostazioni non salvate: <motivo>», lo sheet resta aperto.
- I megabyte vengono limitati all'intervallo di un `int` del C# prima della moltiplicazione, così il prodotto non trabocca mai. I limiti `Minimum`/`Maximum` dei campi diventano costanti per lo `Stepper` del piano 4b.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/Support/PlatformDoubles.swift`:

```swift
import CleanerCore
import CleanerFeatures

/// `RecordingAppearance` dei test C#: registra ogni aspetto applicato.
@MainActor
final class FakeAppearance: AppearanceApplying {
    private(set) var applied: [AppearancePreference] = []

    func apply(_ preference: AppearancePreference) {
        applied.append(preference)
    }
}

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

`Tests/CleanerFeaturesTests/SettingsViewModelTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

@MainActor
struct SettingsViewModelTests {
    private struct Fixture {
        let model: SettingsModel
        let store: FakeSettingsStore
        let appearance: FakeAppearance
        let events: Recorder<String>
    }

    private func create(_ settings: CleanerSettings = CleanerSettings(), picked: String? = nil) -> Fixture {
        let store = FakeSettingsStore(settings)
        let appearance = FakeAppearance()
        let events = Recorder<String>()
        let model = SettingsModel(
            store: store,
            appearance: appearance,
            folders: FakePicker(picked),
            onSaved: { events.append("saved") },
            onClose: { events.append("close") })
        return Fixture(model: model, store: store, appearance: appearance, events: events)
    }

    private func settings(_ change: (inout CleanerSettings) -> Void) -> CleanerSettings {
        var settings = CleanerSettings()
        change(&settings)
        return settings
    }

    @Test func pickingAnAppearancePreviewsItImmediately() {
        let fixture = create()
        fixture.model.appearance = .dark
        #expect(fixture.model.appearance == .dark)
        #expect(fixture.appearance.applied == [.dark])
        #expect(fixture.store.saves == 0)
    }

    @Test func cancelRestoresTheLoadedAppearanceAndCloses() {
        let fixture = create(settings { $0.appearance = .light })
        fixture.model.appearance = .dark
        fixture.model.cancel()
        #expect(fixture.appearance.applied.last == .light)
        #expect(fixture.events.values == ["close"])
        #expect(fixture.store.saves == 0)
    }

    @Test func closingFromTheTitleBarBehavesLikeCancel() {
        let fixture = create()
        fixture.model.appearance = .light
        fixture.model.dismiss()
        #expect(fixture.appearance.applied.last == .auto)
    }

    @Test func savePersistsAppearanceAndFoldersThenReturnsToStart() {
        let fixture = create(settings { $0.projectRoots = ["~/src"] })
        fixture.model.appearance = .dark
        fixture.model.save()
        fixture.model.dismiss()
        #expect(fixture.store.current.appearance == .dark)
        #expect(fixture.store.current.projectRoots == ["~/src"])
        #expect(fixture.events.values == ["saved", "close"])
        #expect(fixture.appearance.applied.last == .dark)
    }

    @Test func addingAFolderAppendsAndSelectsIt() async {
        let fixture = create(picked: "/Users/tester/projects")
        await fixture.model.addProjectRoot()
        #expect(fixture.model.projectRoots == ["/Users/tester/projects"])
        #expect(fixture.model.selectedProjectRoot == "/Users/tester/projects")
    }

    @Test func cancelledPickerAddsNothingAndDuplicatesAreNotRepeated() async {
        let fixture = create(settings { $0.largeFileRoots = ["/Volumes/Data"] }, picked: "/Volumes/Data")
        await fixture.model.addLargeFileRoot()
        #expect(fixture.model.largeFileRoots == ["/Volumes/Data"])

        let empty = create(picked: nil)
        await empty.model.addLargeFileRoot()
        #expect(empty.model.largeFileRoots.isEmpty)
    }

    @Test func removeIsDisabledWithoutSelection() {
        let fixture = create(settings { $0.projectRoots = ["/a", "/b"] })
        #expect(!fixture.model.canRemoveProjectRoot)
        fixture.model.selectedProjectRoot = "/a"
        #expect(fixture.model.canRemoveProjectRoot)
        fixture.model.removeProjectRoot()
        #expect(fixture.model.projectRoots == ["/b"])
        #expect(!fixture.model.canRemoveProjectRoot)
    }

    @Test func unchangedThresholdKeepsExactBytes() {
        let bytes: Int64 = 500 * 1024 * 1024 + 123
        let fixture = create(settings { $0.largeFileThresholdBytes = bytes })
        fixture.model.save()
        #expect(fixture.store.current.largeFileThresholdBytes == bytes)
    }

    // Solo Swift: in C# `Save` riportava i valori nei limiti con Math.Max; nessun test lo fissava.
    @Test func saveClampsTheNumbersLikeTheCSharpModel() {
        let fixture = create()
        fixture.model.largeFileThresholdMegabytes = 0
        fixture.model.downloadsMinAgeDays = -3
        fixture.model.logsMinAgeDays = -1
        fixture.model.nuGetMinAgeDays = 7
        fixture.model.save()
        #expect(fixture.store.current.largeFileThresholdBytes == 1024 * 1024)
        #expect(fixture.store.current.downloadsMinAgeDays == 0)
        #expect(fixture.store.current.logsMinAgeDays == 0)
        #expect(fixture.store.current.nuGetMinAgeDays == 7)
    }

    // Solo Swift: in C# un errore di scrittura chiudeva l'app; qui lo sheet resta aperto e lo dice.
    @Test func failedSaveKeepsTheSheetOpenAndExplainsWhy() {
        let fixture = create()
        fixture.store.failSaves(with: UnexpectedTestError(description: "disco pieno"))
        fixture.model.appearance = .dark

        fixture.model.save()

        #expect(fixture.events.values.isEmpty)
        #expect(fixture.model.saveErrorText == "Impostazioni non salvate: disco pieno")
        #expect(fixture.model.hasSaveError)
        // Non salvato: chiudere ripristina l'aspetto di prima.
        fixture.model.dismiss()
        #expect(fixture.appearance.applied.last == .auto)
    }

    // Solo Swift: un secondo valore uguale non riapplica l'aspetto (il setter C# notificava solo i cambi).
    @Test func reapplyingTheSameAppearanceDoesNothing() {
        let fixture = create()
        fixture.model.appearance = .auto
        #expect(fixture.appearance.applied.isEmpty)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find type 'SettingsModel' in scope`.

- [ ] **Step 3: Implementare `SettingsModel`**

`Sources/CleanerFeatures/Settings/SettingsModel.swift`:

```swift
import CleanerCore
import Observation

/// Porting di `SettingsViewModel`: il contenuto dello sheet delle Impostazioni (spec §6.2). Lo
/// sheet esiste finché `MainModel.settings` non è `nil`; Salva e Annulla chiedono di chiuderlo con
/// `onClose`, che il modello principale collega all'azzeramento di quello stato.
@MainActor
@Observable
public final class SettingsModel: Identifiable {
    /// Limiti dei campi numerici della finestra C# (`Minimum`/`Maximum` dei `NumericUpDown`).
    public static let thresholdMegabytesRange = 1...100_000
    public static let minAgeDaysRange = 0...3650

    @ObservationIgnored private let store: any SettingsStoring
    @ObservationIgnored private let appearanceApplier: any AppearanceApplying
    @ObservationIgnored private let folders: any FolderPicking
    @ObservationIgnored private let onSaved: @MainActor () -> Void
    @ObservationIgnored private let onClose: @MainActor () -> Void
    @ObservationIgnored private let loadedAppearance: AppearancePreference
    @ObservationIgnored private var saved = false

    /// Byte esatti letti al caricamento, insieme al valore in MB troncato che ne deriva. Se al
    /// salvataggio il campo mostrato non è cambiato, si riscrivono questi byte invariati invece di
    /// ricalcolarli da MB: altrimenti un valore che non è multiplo esatto di un megabyte perderebbe
    /// precisione a ogni salvataggio, anche quando l'utente modifica un campo del tutto scorrelato.
    @ObservationIgnored private let loadedThresholdBytes: Int64
    @ObservationIgnored private let loadedThresholdMegabytes: Int

    /// L'aspetto scelto si vede subito: diventa definitivo solo con Salva.
    public var appearance: AppearancePreference {
        didSet {
            guard appearance != oldValue else { return }
            appearanceApplier.apply(appearance)
        }
    }

    public var projectRoots: [String]
    public var largeFileRoots: [String]
    public var selectedProjectRoot: String?
    public var selectedLargeFileRoot: String?
    public var largeFileThresholdMegabytes: Int
    public var downloadsMinAgeDays: Int
    public var logsMinAgeDays: Int
    public var nuGetMinAgeDays: Int

    /// Vuoto finché un salvataggio non fallisce. In C# l'eccezione di scrittura chiudeva l'app; qui
    /// lo sheet resta aperto e dice perché (registro di parità).
    public private(set) var saveErrorText = ""

    public var hasSaveError: Bool { !saveErrorText.isEmpty }
    public var canRemoveProjectRoot: Bool { selectedProjectRoot != nil }
    public var canRemoveLargeFileRoot: Bool { selectedLargeFileRoot != nil }

    public init(
        store: any SettingsStoring,
        appearance: any AppearanceApplying,
        folders: any FolderPicking,
        onSaved: @escaping @MainActor () -> Void,
        onClose: @escaping @MainActor () -> Void
    ) {
        self.store = store
        appearanceApplier = appearance
        self.folders = folders
        self.onSaved = onSaved
        self.onClose = onClose

        let settings = store.load()
        loadedAppearance = settings.appearance
        self.appearance = settings.appearance
        projectRoots = settings.projectRoots
        largeFileRoots = settings.largeFileRoots
        loadedThresholdBytes = settings.largeFileThresholdBytes
        loadedThresholdMegabytes = Int(settings.largeFileThresholdBytes / (1024 * 1024))
        largeFileThresholdMegabytes = loadedThresholdMegabytes
        downloadsMinAgeDays = settings.downloadsMinAgeDays
        logsMinAgeDays = settings.logsMinAgeDays
        nuGetMinAgeDays = settings.nuGetMinAgeDays
    }

    public func save() {
        // I megabyte restano nell'intervallo di un `int` del C#: il prodotto non trabocca mai.
        let megabytes = Int64(min(max(1, largeFileThresholdMegabytes), Int(Int32.max)))
        let thresholdBytes = largeFileThresholdMegabytes == loadedThresholdMegabytes
            ? loadedThresholdBytes
            : megabytes * 1024 * 1024

        var settings = store.load()
        settings.appearance = appearance
        settings.projectRoots = projectRoots
        settings.largeFileRoots = largeFileRoots
        settings.largeFileThresholdBytes = thresholdBytes
        settings.downloadsMinAgeDays = max(0, downloadsMinAgeDays)
        settings.logsMinAgeDays = max(0, logsMinAgeDays)
        settings.nuGetMinAgeDays = max(0, nuGetMinAgeDays)

        do {
            try store.save(settings)
        } catch {
            saveErrorText = String(localized: "Impostazioni non salvate: \(FeatureText.message(error))", bundle: .module)
            return
        }

        saveErrorText = ""
        saved = true
        onSaved()
        onClose()
    }

    public func cancel() {
        dismiss()
        onClose()
    }

    /// Chiusura senza salvare (Annulla o chiusura dello sheet): torna l'aspetto di prima. Idempotente.
    public func dismiss() {
        if !saved {
            appearanceApplier.apply(loadedAppearance)
        }
    }

    public func addProjectRoot() async {
        let title = String(localized: "Scegli una cartella di progetto", bundle: .module)
        if let path = await addFolder(to: \.projectRoots, title: title) {
            selectedProjectRoot = path
        }
    }

    public func removeProjectRoot() {
        if let root = selectedProjectRoot {
            remove(root, from: \.projectRoots)
        }
        selectedProjectRoot = nil
    }

    public func addLargeFileRoot() async {
        let title = String(localized: "Scegli una cartella in cui cercare file grandi", bundle: .module)
        if let path = await addFolder(to: \.largeFileRoots, title: title) {
            selectedLargeFileRoot = path
        }
    }

    public func removeLargeFileRoot() {
        if let root = selectedLargeFileRoot {
            remove(root, from: \.largeFileRoots)
        }
        selectedLargeFileRoot = nil
    }

    private func addFolder(to list: ReferenceWritableKeyPath<SettingsModel, [String]>, title: String) async -> String? {
        guard let path = await folders.pickFolder(title: title) else { return nil }
        if !self[keyPath: list].contains(where: { FeatureText.same($0, path) }) {
            self[keyPath: list].append(path)
        }
        return path
    }

    private func remove(_ root: String, from list: ReferenceWritableKeyPath<SettingsModel, [String]>) {
        if let index = self[keyPath: list].firstIndex(where: { FeatureText.same($0, root) }) {
            self[keyPath: list].remove(at: index)
        }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter SettingsViewModelTests`
Expected: `Test run with 11 tests in 1 suite passed` (8 portati, 3 solo Swift), nessun warning. Suite di `CleanerFeaturesTests`: 26.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `SettingsViewModelTests.cs` con:

```markdown
| SettingsViewModelTests.cs | 8 | SettingsViewModelTests.swift | 11 | 4a | 8 portati + 3 solo-Swift (`saveClampsTheNumbersLikeTheCSharpModel`, `failedSaveKeepsTheSheetOpenAndExplainsWhy`, `reapplyingTheSameAppearanceDoesNothing`); `IsDark = true` → `appearance = .dark`; `CloseRequested` → `onClose` |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Errore di scrittura di `settings.json` | eccezione non gestita da `Save`: l'app si chiude (Salva nelle Impostazioni e «Analizza» al passo 1) | Salva lascia aperto lo sheet con «Impostazioni non salvate: <motivo>» (testo nuovo, eccezione alla spec §12 decisa dall'utente); «Analizza» ignora l'errore e avvia l'analisi | voluta |
| Aspetto riapplicato con lo stesso valore | il setter generato non notifica se il valore non cambia | `didSet` controlla `oldValue` | identica |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/PlatformDoubles.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsViewModelTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the settings model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Storico

La pagina Storico: le ultime 50 pulizie con data locale, spazio, nomi leggibili delle categorie ed elementi, più il riepilogo nella barra.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/History/CategoryNames.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/History/HistoryModel.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/NavigationSpy.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryViewTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/HistoryViewModel.cs`, `CategoryNames.cs`; `tests/MjmCleaner.App.Tests/HistoryTests.cs`, `HistoryViewTests.cs`

**Interfaces:**
- Consumes: `CleanSessionSummary`, `CategoryCleanResult`, `CleanupCategory`, `DockerCategories` (Core); `AppEnvironment.history`, `categories()`, `Navigating` (Task 2); `Formatting`, `SafeSum`, `FeatureText` (Task 1); `TestHome`, `FakeHistory`, `makeEnvironment`, `UnexpectedTestError` (Task 2, test).
- Produces:
  - `public struct CategoryNames: Sendable` — `static func build(_ catalog: [CleanupCategory]) -> CategoryNames`, `func name(for categoryId: String) -> String`
  - `public struct HistoryRow: Identifiable, Sendable` — `init(session: CleanSessionSummary, names: CategoryNames, timeZone: TimeZone = .current)`; `id`, `when`, `startedAt`, `bytesFreed`, `freed`, `items`, `categoryNames`, `failed`
  - `@MainActor @Observable public final class HistoryModel` — `init(environment: AppEnvironment, navigation: (any Navigating)?)`; `rows`, `totalText`, `countText`, `hasSessions`, `initialLoad: Task<Void, Never>?`; `static func summarize(_ count: Int) -> String`; `close()`
  - test: `@MainActor class NavigationSpy: Navigating` — `events: [String]`, `record(_:)`, `refreshFailure: (any Error)?`

Note di porting:
- `HistoryRow.startedAt` resta accessibile perché la `Table` del piano 4b ordini per data decrescente (spec §6.2) senza riconvertire il testo.
- `LoadAsync` in C# non intercettava gli errori: il task falliva in silenzio e la pagina restava vuota. Qui `try?` produce lo stesso effetto visibile.
- Delle cinque prove di `HistoryViewTests.cs` due riguardano il modello e si portano su `hasSessions`, `countText` e `totalText`; le altre tre (toolbar senza «Chiudi», chevron di ordinamento, stile delle intestazioni) sono della vista e passano al piano 4b.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/Support/NavigationSpy.swift`:

```swift
import CleanerFeatures

/// Registra le richieste di navigazione di una pagina. Le sezioni (pulizia, Docker, Xcode)
/// aggiungono le proprie destinazioni in sottoclassi.
@MainActor
class NavigationSpy: Navigating {
    private(set) var events: [String] = []
    var refreshFailure: (any Error)?

    func record(_ event: String) {
        events.append(event)
    }

    func startOver() {
        record("startOver")
    }

    func refreshTotal() async throws {
        record("refreshTotal")
        if let refreshFailure {
            throw refreshFailure
        }
    }
}
```

`Tests/CleanerFeaturesTests/HistoryTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

struct HistoryTests {
    private static let names = CategoryNames.build([
        CleanupCategory(
            id: "system-caches", displayName: "Cache utente e di sistema", description: "", risk: .medium,
            selectedByDefault: true, parentId: nil, rules: []),
    ])

    /// Il 26 settembre 2026 alle 01:19 in ora locale, come `DateTimeKind.Local` nel test C#.
    private static func session(_ ids: String...) throws -> CleanSessionSummary {
        let local = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current, year: 2026, month: 9, day: 26, hour: 1, minute: 19)
        return CleanSessionSummary(
            id: 1,
            startedAt: try #require(local.date),
            duration: .seconds(3),
            bytesFreed: 10_200_547_328,
            itemsDeleted: 2117,
            itemsFailed: 0,
            categories: ids.map { CategoryCleanResult(categoryId: $0, bytesFreed: 1, itemsDeleted: 1) })
    }

    @Test func dateIsLocalisedItalian() throws {
        #expect(HistoryRow(session: try Self.session("system-caches"), names: Self.names).when == "26 set 2026, 01:19")
    }

    @Test func itemsUseThousandsSeparator() throws {
        #expect(HistoryRow(session: try Self.session("system-caches"), names: Self.names).items == "2.117")
    }

    @Test func categoriesShowReadableNames() throws {
        let row = HistoryRow(
            session: try Self.session("system-caches", "docker-images", "xcode-derived-data", "trash-downloads-large", "sconosciuta"),
            names: Self.names)
        #expect(row.categoryNames == ["Cache utente e di sistema", "Immagini Docker", "DerivedData", "Cestino, Download e file grandi", "sconosciuta"])
    }

    @Test(arguments: [(0, "nessuna pulizia"), (1, "in 1 pulizia"), (4, "in 4 pulizie")])
    @MainActor
    func summaryAgrees(count: Int, expected: String) {
        #expect(HistoryModel.summarize(count) == expected)
    }
}
```

`Tests/CleanerFeaturesTests/HistoryViewTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Le prove di `HistoryViewTests.cs` che riguardano il modello. Quelle sull'albero visuale
/// (toolbar, chevron, stile delle intestazioni) passano alla verifica dell'app (piano 4b, spec §9.4).
@MainActor
struct HistoryViewTests {
    @Test func emptyHistoryShowsOnlyNessunaPulizia() async throws {
        let home = try await TestHome.create()
        defer { home.remove() }
        let model = HistoryModel(environment: home.environment, navigation: nil)
        await model.initialLoad?.value

        #expect(!model.hasSessions)
        #expect(model.countText == "nessuna pulizia")
        #expect(model.totalText == "0 B")
    }

    @Test func amountIsVisibleWhenThereAreSessions() async throws {
        let history = FakeHistory()
        history.setSessions([
            CleanSessionSummary(
                id: 3, startedAt: Date(timeIntervalSince1970: 1_790_000_000), duration: .seconds(2),
                bytesFreed: 1_288_490_189, itemsDeleted: 10, itemsFailed: 0, categories: []),
        ])
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: nil)
        await model.initialLoad?.value

        #expect(model.hasSessions)
        #expect(model.totalText == "1,2 GB")
        #expect(model.countText == "in 1 pulizia")
    }

    // Solo Swift: totale senza trap, nomi del catalogo, righe falliti, chiusura e storico illeggibile.
    @Test func sessionsAreListedWithNamesAndASaturatedTotal() async throws {
        let history = FakeHistory()
        history.setSessions([
            CleanSessionSummary(
                id: 2, startedAt: Date(timeIntervalSince1970: 1_790_000_000), duration: .seconds(1),
                bytesFreed: Int64.max, itemsDeleted: 1, itemsFailed: 3,
                categories: [CategoryCleanResult(categoryId: "logs", bytesFreed: 1, itemsDeleted: 1)]),
            CleanSessionSummary(
                id: 1, startedAt: Date(timeIntervalSince1970: 1_780_000_000), duration: .seconds(1),
                bytesFreed: 1024, itemsDeleted: 1, itemsFailed: 0, categories: []),
        ])
        let navigation = NavigationSpy()
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: navigation)
        await model.initialLoad?.value

        #expect(model.rows.map(\.id) == [2, 1])
        #expect(model.rows.first?.categoryNames == ["Log e crash report"])
        #expect(model.rows.first?.failed == "3 falliti")
        #expect(model.rows.last?.failed == "")
        #expect(model.totalText == "8388608 TB")
        #expect(model.countText == "in 2 pulizie")

        model.close()
        #expect(navigation.events == ["startOver"])
    }

    @Test func unreadableHistoryLeavesThePageEmpty() async throws {
        let history = FakeHistory()
        history.failReads(with: UnexpectedTestError(description: "database bloccato"))
        let model = HistoryModel(environment: try makeEnvironment(history: history), navigation: nil)
        await model.initialLoad?.value

        #expect(model.rows.isEmpty)
        #expect(model.totalText == "—")
        #expect(model.countText == "")
        #expect(!model.hasSessions)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find 'CategoryNames' in scope`, `cannot find 'HistoryRow' in scope` e `cannot find 'HistoryModel' in scope`.

- [ ] **Step 3: Implementare i nomi delle categorie**

`Sources/CleanerFeatures/History/CategoryNames.swift`:

```swift
import CleanerCore

/// Nomi leggibili per gli identificativi salvati nello storico: il catalogo corrente, le
/// categorie di Docker e Xcode e gli ID di versioni precedenti del catalogo.
public struct CategoryNames: Sendable {
    private let names: [[UInt8]: String]

    private init(names: [[UInt8]: String]) {
        self.names = names
    }

    public static func build(_ catalog: [CleanupCategory]) -> CategoryNames {
        let fixed = [
            (DockerCategories.images, String(localized: "Immagini Docker", bundle: .module)),
            (DockerCategories.volumes, String(localized: "Volumi Docker", bundle: .module)),
            (DockerCategories.buildCache, String(localized: "Cache di build Docker", bundle: .module)),
            ("xcode-derived-data", String(localized: "DerivedData", bundle: .module)),
            ("xcode-device-support", String(localized: "Device Support", bundle: .module)),
            ("xcode-simulator-devices", String(localized: "Dispositivi simulati", bundle: .module)),
            ("xcode-runtimes", String(localized: "Runtime dei simulatori", bundle: .module)),
            ("trash-downloads-large", String(localized: "Cestino, Download e file grandi", bundle: .module)),
        ]

        var names: [[UInt8]: String] = [:]
        for (id, name) in fixed {
            names[FeatureText.ordinalKey(id)] = name
        }
        // Il catalogo corrente ha la precedenza, come l'assegnazione `names[category.Id]` del C#.
        for category in catalog {
            names[FeatureText.ordinalKey(category.id)] = category.displayName
        }
        return CategoryNames(names: names)
    }

    /// Il nome leggibile, o l'identificativo stesso se sconosciuto.
    public func name(for categoryId: String) -> String {
        names[FeatureText.ordinalKey(categoryId)] ?? categoryId
    }
}
```

- [ ] **Step 4: Implementare `HistoryModel`**

`Sources/CleanerFeatures/History/HistoryModel.swift`:

```swift
import CleanerCore
import Foundation
import Observation

/// Una riga della tabella Storico (spec §6.2: Data · Spazio · Categorie · Elementi).
public struct HistoryRow: Identifiable, Sendable {
    public let id: Int64
    /// I timestamp sono salvati in UTC e resi in ora locale: altrimenti il cambio d'ora riordina lo storico.
    public let when: String
    public let startedAt: Date
    public let bytesFreed: Int64
    public let freed: String
    public let items: String
    public let categoryNames: [String]
    public let failed: String

    public init(session: CleanSessionSummary, names: CategoryNames, timeZone: TimeZone = .current) {
        id = session.id
        startedAt = session.startedAt
        when = Formatting.historyDate(session.startedAt, timeZone: timeZone)
        bytesFreed = session.bytesFreed
        freed = Formatting.bytes(session.bytesFreed)
        items = Formatting.integer(session.itemsDeleted)
        categoryNames = session.categories.map { names.name(for: $0.categoryId) }
        failed = session.itemsFailed == 0
            ? ""
            : String(localized: "\(String(session.itemsFailed)) falliti", bundle: .module)
    }
}

/// Porting di `HistoryViewModel`: le ultime 50 pulizie, caricate alla creazione della pagina.
@MainActor
@Observable
public final class HistoryModel {
    @ObservationIgnored private weak var navigation: (any Navigating)?

    public private(set) var rows: [HistoryRow] = []
    public private(set) var totalText = "—"
    public private(set) var countText = ""
    /// Senza sessioni la barra mostra solo «nessuna pulizia»: «0 B» davanti sarebbe rumore.
    public private(set) var hasSessions = false

    /// Il caricamento parte alla creazione, come nel costruttore C#; i test lo attendono.
    @ObservationIgnored public private(set) var initialLoad: Task<Void, Never>?

    public init(environment: AppEnvironment, navigation: (any Navigating)?) {
        self.navigation = navigation
        initialLoad = Task { await self.load(environment) }
    }

    public static func summarize(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "nessuna pulizia", bundle: .module)
        case 1: String(localized: "in 1 pulizia", bundle: .module)
        default: String(localized: "in \(String(count)) pulizie", bundle: .module)
        }
    }

    public func close() {
        navigation?.startOver()
    }

    /// Uno storico illeggibile lascia la pagina vuota, come il task C# che falliva senza effetti visibili.
    private func load(_ environment: AppEnvironment) async {
        guard let sessions = try? await environment.history.sessions(limit: 50) else { return }
        let names = CategoryNames.build(environment.categories())

        rows = sessions.map { HistoryRow(session: $0, names: names) }
        totalText = Formatting.bytes(SafeSum.total(rows.map(\.bytesFreed)))
        countText = Self.summarize(rows.count)
        hasSessions = !rows.isEmpty
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "HistoryTests|HistoryViewTests"`
Expected: `Test run with 8 tests in 2 suites passed` (4 di `HistoryTests` con 3 casi in `summaryAgrees`, 4 di `HistoryViewTests`), nessun warning. Suite di `CleanerFeaturesTests`: 34.

- [ ] **Step 6: Registro di parità e commit**

Sostituire le righe `HistoryTests.cs` e `HistoryViewTests.cs` con:

```markdown
| HistoryTests.cs | 4 (3) | HistoryTests.swift | 4 (3) | 4a | la data del test si costruisce in ora locale, come `DateTimeKind.Local`; `IReadOnlyDictionary` dei nomi → `CategoryNames` con chiavi ordinali |
| HistoryViewTests.cs | 5 | HistoryViewTests.swift | 4 | 4a | 2 portati sul modello (`emptyHistoryShowsOnlyNessunaPulizia`, `amountIsVisibleWhenThereAreSessions`) + 2 solo-Swift (`sessionsAreListedWithNamesAndASaturatedTotal`, `unreadableHistoryLeavesThePageEmpty`); `HasToolbarAndNoCloseButton`, `SortChevronIsNinePixelsWithAThinStroke`, `ColumnHeadersShareOneStyle` sono della vista → piano 4b |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/History/CategoryNames.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/History/HistoryModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/NavigationSpy.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/HistoryViewTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the history model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: passo 1, scelta delle categorie

Le righe del passo 1 con rischio, tile e rientro dei figli, il conteggio delle selezioni e «Analizza», che ricorda la selezione e apre il passo 2. Qui nasce anche il protocollo di navigazione del wizard.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/CategoryVisuals.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/CleanupNavigationSpy.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/ChooseStepViewModel.cs` (`CategoryChoice` compreso), `CategoryVisuals.cs`; `tests/MjmCleaner.App.Tests/ChooseStepTests.cs`

**Interfaces:**
- Consumes: `CleanupCategory`, `RiskLevel`, `CategoryScanResult`, `CleanReport`, `PendingJournal` (Core); `AppEnvironment.settings`, `categories()`, `Navigating` (Task 2); `FeatureText` (Task 1); `TestHome`, `FakeSettingsStore`, `makeEnvironment`, `makeCategory` (Task 2, test); `NavigationSpy` (Task 4, test).
- Produces:
  - `@MainActor public protocol CleanupNavigating: Navigating` — `showScan(_ categories: [CleanupCategory])`, `showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult])`, `showDone(_ report: CleanReport, journal: PendingJournal?)`
  - `public struct CategoryVisual: Sendable, Equatable` — `tileColorName`, `designHex`, `symbolName`; `public enum CategoryVisuals` — `static func visual(for categoryId: String) -> CategoryVisual`
  - `extension RiskLevel` — `public var label: String`, `public var colorName: String`
  - `@MainActor @Observable public final class CategoryChoice: Identifiable` — `init(category:isSelected:showSeparator: Bool = false)`; `category`, `isSelected`, `showSeparator`, `displayName`, `description`, `risk`, `riskLabel`, `visual`, `isChild`
  - `@MainActor @Observable public final class ChooseStepModel` — `init(environment: AppEnvironment, navigation: (any CleanupNavigating)?)`; `choices`, `selectedCount`, `selectedCountText`, `canAnalyze`; `static func countText(_ count: Int) -> String`; `analyze()`; `weak var navigation` interno, impostato da `MainModel` (Task 11)
  - test: `@MainActor final class CleanupNavigationSpy: NavigationSpy, CleanupNavigating` — `scannedCategories`, `confirmedResults`, `doneReport`, `doneJournal`

Note di porting:
- I colori delle tile vanno nel catalogo asset del piano 4b, con varianti chiaro e scuro (spec §6.4). Qui restano il nome dell'asset e il colore del progetto (`designHex`, la variante chiara), su cui si porta `TilesUseTheDesignColors`. Le geometrie disegnate a mano diventano SF Symbols (spec §6.1: si usano i componenti nativi). `logs` e gli ID sconosciuti condividono la tile neutra, come in C#.
- `ChildRowsAreIndentedWithDeeperSeparator` verificava margini Avalonia (`Thickness`): resta `isChild`, rientri e separatori li disegna la vista del piano 4b.
- `AnalyzeIsDisabledWithoutSelectionAndFollowsTheToggles` contava anche le notifiche `CanExecuteChanged`, che non hanno equivalente: con Observation la vista rilegge `canAnalyze` da sola.
- `navigation` è `weak` e ha un setter interno: `MainModel` crea il passo 1 nel proprio `init`, prima di poter passare `self`.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/Support/CleanupNavigationSpy.swift`:

```swift
import CleanerCore
import CleanerFeatures

/// Le destinazioni del wizard: registra l'evento e conserva ciò che il passo ha consegnato.
@MainActor
final class CleanupNavigationSpy: NavigationSpy, CleanupNavigating {
    private(set) var scannedCategories: [CleanupCategory] = []
    private(set) var confirmedResults: [CategoryScanResult] = []
    private(set) var doneReport: CleanReport?
    private(set) var doneJournal: PendingJournal?

    func showScan(_ categories: [CleanupCategory]) {
        record("scan")
        scannedCategories = categories
    }

    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult]) {
        record("confirm")
        confirmedResults = results
    }

    func showDone(_ report: CleanReport, journal: PendingJournal?) {
        record("done")
        doneReport = report
        doneJournal = journal
    }
}
```

`Tests/CleanerFeaturesTests/ChooseStepTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

@MainActor
struct ChooseStepTests {
    @Test(arguments: [(0, "Nessuna categoria selezionata"), (1, "1 categoria selezionata"), (3, "3 categorie selezionate")])
    func countTextAgrees(count: Int, expected: String) {
        #expect(ChooseStepModel.countText(count) == expected)
    }

    /// Rientri e margini sono della vista (piano 4b): al modello resta sapere quali righe sono figlie.
    @Test func childRowsAreIndentedWithDeeperSeparator() {
        let child = CategoryChoice(category: makeCategory("nuget-packages", parent: "dev-caches"), isSelected: false, showSeparator: true)
        let root = CategoryChoice(category: makeCategory("logs"), isSelected: false, showSeparator: true)
        #expect(child.isChild)
        #expect(!root.isChild)
    }

    @Test(arguments: [(RiskLevel.low, "Rischio basso"), (.medium, "Rischio medio"), (.high, "Rischio alto")])
    func riskPillTextNamesTheLevel(risk: RiskLevel, expected: String) {
        #expect(CategoryChoice(category: makeCategory("logs", risk: risk), isSelected: false).riskLabel == expected)
    }

    @Test(arguments: [
        ("system-caches", "#66788F"), ("dev-caches", "#7457E8"), ("nuget-packages", "#3567D0"),
        ("project-build-output", "#1D8784"), ("logs", "#85858B"), ("trash", "#D2453A"), ("downloads-large", "#E8833A"),
    ])
    func tilesUseTheDesignColors(id: String, color: String) {
        #expect(CategoryVisuals.visual(for: id).designHex == color)
    }

    @Test func analyzeIsDisabledWithoutSelectionAndFollowsTheToggles() async throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = []
        let home = try await TestHome.create(settings: settings)
        defer { home.remove() }
        let model = ChooseStepModel(environment: home.environment, navigation: nil)

        #expect(!model.canAnalyze)
        #expect(model.selectedCountText == "Nessuna categoria selezionata")

        model.choices[0].isSelected = true

        #expect(model.canAnalyze)
        #expect(model.selectedCountText == "1 categoria selezionata")

        model.choices[0].isSelected = false

        #expect(!model.canAnalyze)
        #expect(model.selectedCountText == "Nessuna categoria selezionata")
    }

    // Solo Swift: selezione ricordata, colori sconosciuti, nomi degli asset del rischio.
    @Test func rememberedSelectionIsRestoredAndAnalyzeSavesItBeforeScanning() throws {
        var settings = CleanerSettings()
        settings.selectedCategoryIds = ["logs", "trash"]
        let store = FakeSettingsStore(settings)
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)

        #expect(model.choices.filter(\.isSelected).map(\.category.id) == ["logs", "trash"])
        #expect(model.choices.map(\.showSeparator) == [false, true, true, true, true, true, true])

        model.choices.first { $0.category.id == "trash" }?.isSelected = false
        model.choices.first { $0.category.id == "system-caches" }?.isSelected = true
        model.analyze()

        #expect(store.current.selectedCategoryIds == ["system-caches", "logs"])
        #expect(navigation.events == ["scan"])
        #expect(navigation.scannedCategories.map(\.id) == ["system-caches", "logs"])
    }

    @Test func analyzeStillScansWhenTheSelectionCannotBeSaved() throws {
        let store = FakeSettingsStore()
        store.failSaves(with: UnexpectedTestError(description: "sola lettura"))
        let navigation = CleanupNavigationSpy()
        let model = ChooseStepModel(environment: try makeEnvironment(settings: store), navigation: navigation)

        model.analyze()

        #expect(store.saves == 1)
        #expect(navigation.events == ["scan"])
    }

    @Test func unknownCategoriesGetTheNeutralTileAndRiskHasItsAsset() {
        #expect(CategoryVisuals.visual(for: "sconosciuta") == CategoryVisuals.visual(for: "logs"))
        #expect(CategoryVisuals.visual(for: "sconosciuta").tileColorName == "TileNeutral")
        #expect([RiskLevel.low, .medium, .high].map(\.colorName) == ["RiskLow", "RiskMedium", "RiskHigh"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find type 'CleanupNavigating' in scope` (possono seguire `ChooseStepModel` e `CategoryChoice`).

- [ ] **Step 3: Implementare tile e rischio**

`Sources/CleanerFeatures/Cleanup/CategoryVisuals.swift`:

```swift
import CleanerCore

/// Tile colorata e simbolo di una categoria, come nel redesign. Il colore vive nel catalogo asset
/// dell'app con le varianti chiaro/scuro (spec §6.4): qui c'è il nome dell'asset e il colore del
/// progetto nella variante chiara, da cui l'asset si costruisce.
public struct CategoryVisual: Sendable, Equatable {
    public let tileColorName: String
    public let designHex: String
    public let symbolName: String
}

public enum CategoryVisuals {
    /// ID sconosciuti ricevono la tile neutra, la stessa dei log.
    public static func visual(for categoryId: String) -> CategoryVisual {
        switch Array(categoryId.utf8) {
        case Array("system-caches".utf8): CategoryVisual(tileColorName: "TileSystemCaches", designHex: "#66788F", symbolName: "internaldrive")
        case Array("dev-caches".utf8): CategoryVisual(tileColorName: "TileDevCaches", designHex: "#7457E8", symbolName: "chevron.left.forwardslash.chevron.right")
        case Array("nuget-packages".utf8): CategoryVisual(tileColorName: "TileNuGet", designHex: "#3567D0", symbolName: "shippingbox")
        case Array("project-build-output".utf8): CategoryVisual(tileColorName: "TileBuildOutput", designHex: "#1D8784", symbolName: "folder")
        case Array("trash".utf8): CategoryVisual(tileColorName: "TileTrash", designHex: "#D2453A", symbolName: "trash")
        case Array("downloads-large".utf8): CategoryVisual(tileColorName: "TileDownloadsLarge", designHex: "#E8833A", symbolName: "arrow.down.to.line")
        default: CategoryVisual(tileColorName: "TileNeutral", designHex: "#85858B", symbolName: "doc.text")
        }
    }
}

extension RiskLevel {
    /// Il testo della pill: il rischio resta comunicato anche senza il colore (spec §6.6).
    public var label: String {
        switch self {
        case .low: String(localized: "Rischio basso", bundle: .module)
        case .medium: String(localized: "Rischio medio", bundle: .module)
        case .high: String(localized: "Rischio alto", bundle: .module)
        }
    }

    /// Il colore della pill nel catalogo asset dell'app, con varianti chiaro/scuro.
    public var colorName: String {
        switch self {
        case .low: "RiskLow"
        case .medium: "RiskMedium"
        case .high: "RiskHigh"
        }
    }
}
```

- [ ] **Step 4: Implementare il passo 1**

`Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift`:

```swift
import CleanerCore
import Observation

/// Le destinazioni del wizard di pulizia: ogni passo chiede il successivo alla finestra principale.
@MainActor
public protocol CleanupNavigating: Navigating {
    func showScan(_ categories: [CleanupCategory])
    func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult])
    func showDone(_ report: CleanReport, journal: PendingJournal?)
}

/// Una categoria del passo 1, con la casella di selezione.
@MainActor
@Observable
public final class CategoryChoice: Identifiable {
    public let category: CleanupCategory
    public var isSelected: Bool
    /// La prima riga del gruppo non ha separatore sopra.
    public let showSeparator: Bool

    public init(category: CleanupCategory, isSelected: Bool, showSeparator: Bool = false) {
        self.category = category
        self.isSelected = isSelected
        self.showSeparator = showSeparator
    }

    public var displayName: String { category.displayName }
    public var description: String { category.description }
    public var risk: RiskLevel { category.risk }
    public var riskLabel: String { category.risk.label }
    public var visual: CategoryVisual { CategoryVisuals.visual(for: category.id) }

    /// I pacchetti NuGet compaiono rientrati sotto le cache di sviluppo.
    public var isChild: Bool { category.parentId != nil }
}

/// Porting di `ChooseStepViewModel`: passo 1, scelta delle categorie.
@MainActor
@Observable
public final class ChooseStepModel {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored weak var navigation: (any CleanupNavigating)?

    public let choices: [CategoryChoice]

    public init(environment: AppEnvironment, navigation: (any CleanupNavigating)?) {
        self.environment = environment
        self.navigation = navigation

        let remembered = Set(environment.settings.load().selectedCategoryIds.map(FeatureText.ordinalKey))
        choices = environment.categories().enumerated().map { index, category in
            CategoryChoice(
                category: category,
                isSelected: remembered.contains(FeatureText.ordinalKey(category.id)),
                showSeparator: index > 0)
        }
    }

    public var selectedCount: Int { choices.filter(\.isSelected).count }
    public var selectedCountText: String { Self.countText(selectedCount) }
    public var canAnalyze: Bool { selectedCount > 0 }

    public static func countText(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "Nessuna categoria selezionata", bundle: .module)
        case 1: String(localized: "1 categoria selezionata", bundle: .module)
        default: String(localized: "\(String(count)) categorie selezionate", bundle: .module)
        }
    }

    public func analyze() {
        let selected = choices.filter(\.isSelected).map(\.category)
        guard !selected.isEmpty else { return }

        // La selezione viene ricordata: è ciò che rende sopportabili quattro passi ogni settimana.
        // È solo una comodità: se il file non si scrive l'analisi parte comunque (in C#
        // l'eccezione chiudeva l'app; registro di parità).
        var settings = environment.settings.load()
        settings.selectedCategoryIds = selected.map(\.id)
        try? environment.settings.save(settings)

        navigation?.showScan(selected)
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter ChooseStepTests`
Expected: `Test run with 8 tests in 1 suite passed` (5 portati con 3 + 3 + 7 casi, 3 solo Swift), nessun warning. Suite di `CleanerFeaturesTests`: 42.

- [ ] **Step 6: Registro di parità e commit**

Sostituire la riga `ChooseStepTests.cs` con:

```markdown
| ChooseStepTests.cs | 5 (13) | ChooseStepTests.swift | 8 (13) | 4a | 5 portati + 3 solo-Swift (`rememberedSelectionIsRestoredAndAnalyzeSavesItBeforeScanning`, `analyzeStillScansWhenTheSelectionCannotBeSaved`, `unknownCategoriesGetTheNeutralTileAndRiskHasItsAsset`); `childRowsAreIndentedWithDeeperSeparator` verifica `isChild` (margini e rientri della vista: piano 4b); `tilesUseTheDesignColors` su `CategoryVisual.designHex`; il conteggio di `CanExecuteChanged` non ha equivalente con Observation |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Tile e icone delle categorie | colore esadecimale e geometria disegnata a mano (`CategoryVisuals`) | nome dell'asset con varianti chiaro/scuro, colore del progetto (`designHex`) e SF Symbol | voluta (spec §6.1, §6.4) |
| Navigazione delle pagine | `GoTo(object)` sul ViewModel principale e `IXcodeNavigation`; riferimenti forti | protocolli `Navigating`/`CleanupNavigating`/`DockerNavigating`/`XcodeNavigating`, un metodo per destinazione; riferimento `weak` | per costruzione |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/CategoryVisuals.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/CleanupNavigationSpy.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the choose step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: passo 2, analisi

L'analisi in sola lettura delle categorie scelte, con lo stato per categoria, il percorso corrente, Annulla e la via d'uscita quando fallisce.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ScanStepModel.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ScanStepModelTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/ScanStepViewModel.cs`

**Interfaces:**
- Consumes: `ScanPerforming.scan(_:progress:)`, `ScanProgress`, `CategoryScanResult`, `CleanupCategory` (Core); `AppEnvironment.scan` (Task 2); `CleanupNavigating` (Task 5); `ProgressRelay`, `Formatting`, `FeatureText` (Task 1); `FakeScan`, `makeEnvironment`, `makeCategory`, `makeItem`, `UnexpectedTestError` (Task 2, test); `CleanupNavigationSpy` (Task 5, test).
- Produces:
  - `@MainActor @Observable public final class CategoryProgress: Identifiable` — `displayName`, `status`
  - `@MainActor @Observable public final class ScanStepModel` — `init(environment: AppEnvironment, navigation: (any CleanupNavigating)?, categories: [CleanupCategory])`; `progress`, `currentPath`, `isRunning`, `errorText`, `hasError`, `run: Task<Void, Never>?`; `cancel()`, `backToStart()`

Note di porting:
- Annulla annulla il `Task` dell'analisi (`run`); `ScanEngine` risponde con `CancellationError` e la pagina torna al passo 1, come il ramo `OperationCanceledException` del C#.
- Una riga si trova per identificativo di categoria e poi per nome visualizzato, con confronti ordinali, come `FirstOrDefault`/`First` del C#. Un aggiornamento di una categoria sconosciuta viene ignorato.
- Il C# non aveva prove per questo passo: i quattro test sono solo Swift.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/ScanStepModelTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 2.
@MainActor
struct ScanStepModelTests {
    private let categories = [makeCategory("logs", name: "Log e crash report"), makeCategory("trash", name: "Cestino")]

    @Test func progressUpdatesTheRowsAndASuccessfulScanShowsTheConfirmStep() async throws {
        let scan = FakeScan()
        let results = [CategoryScanResult(categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log")], totalBytes: 100, errors: [], exclusions: [])]
        scan.respond(with: results, progress: [
            ScanProgress(categoryId: "logs", currentPath: "/Users/tester/Library/Logs/a.log", itemsFound: 1, bytesFound: 100),
            ScanProgress(categoryId: "logs", currentPath: "", itemsFound: 2, bytesFound: 2048),
            ScanProgress(categoryId: "trash", currentPath: "/Users/tester/.Trash/x", itemsFound: 0, bytesFound: 0),
            ScanProgress(categoryId: "sconosciuta", currentPath: "/ignorato", itemsFound: 9, bytesFound: 9),
        ])
        let navigation = CleanupNavigationSpy()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)

        #expect(model.progress.map(\.status) == ["in attesa", "in attesa"])
        #expect(model.isRunning)

        await model.run?.value

        #expect(model.progress.map(\.displayName) == ["Log e crash report", "Cestino"])
        #expect(model.progress.map(\.status) == ["2 elementi · 2 KB", "in corso…"])
        #expect(model.currentPath == "/Users/tester/.Trash/x")
        #expect(!model.isRunning)
        #expect(!model.hasError)
        #expect(scan.scannedCategoryIds == [["logs", "trash"]])
        #expect(navigation.events == ["confirm"])
        #expect(navigation.confirmedResults == results)
    }

    @Test func cancelReturnsToTheFirstStep() async throws {
        let scan = FakeScan()
        scan.waitForCancellation()
        let navigation = CleanupNavigationSpy()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)
        await scan.started.wait()

        model.cancel()
        await model.run?.value

        #expect(navigation.events == ["startOver"])
        #expect(!model.isRunning)
        #expect(!model.hasError)
    }

    @Test func failureShowsTheReasonAndOnlyTheWayBack() async throws {
        let scan = FakeScan()
        scan.fail(with: UnexpectedTestError(description: "disco scollegato"))
        let navigation = CleanupNavigationSpy()
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: navigation, categories: categories)

        await model.run?.value

        #expect(model.errorText == "Analisi non riuscita: disco scollegato")
        #expect(model.hasError)
        #expect(!model.isRunning)
        #expect(navigation.events.isEmpty)

        model.backToStart()
        #expect(navigation.events == ["startOver"])
    }

    @Test func singleItemUsesTheSingularNoun() async throws {
        let scan = FakeScan()
        scan.respond(with: [], progress: [ScanProgress(categoryId: "trash", currentPath: "", itemsFound: 1, bytesFound: 10)])
        let model = ScanStepModel(environment: try makeEnvironment(scan: scan), navigation: nil, categories: categories)

        await model.run?.value

        #expect(model.progress.map(\.status) == ["in attesa", "1 elemento · 10 B"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find 'ScanStepModel' in scope`.

- [ ] **Step 3: Implementare il passo 2**

`Sources/CleanerFeatures/Cleanup/ScanStepModel.swift`:

```swift
import CleanerCore
import Observation

/// Lo stato di una categoria durante l'analisi.
@MainActor
@Observable
public final class CategoryProgress: Identifiable {
    public let displayName: String
    public fileprivate(set) var status = String(localized: "in attesa", bundle: .module)

    init(displayName: String) {
        self.displayName = displayName
    }
}

/// Porting di `ScanStepViewModel`: passo 2, analisi in sola lettura delle categorie scelte.
@MainActor
@Observable
public final class ScanStepModel {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private weak var navigation: (any CleanupNavigating)?
    @ObservationIgnored private let categories: [CleanupCategory]

    public let progress: [CategoryProgress]
    public private(set) var currentPath = ""
    public private(set) var isRunning = true

    /// Vuoto finché l'analisi non fallisce. Senza un errore diverso dall'annullamento catturato
    /// esplicitamente, `isRunning` resterebbe vero per sempre, Annulla non avrebbe più effetto e
    /// l'utente resterebbe intrappolato sul passo 2 senza via d'uscita.
    public private(set) var errorText = ""

    public var hasError: Bool { !errorText.isEmpty }

    /// L'analisi parte alla creazione della pagina; Annulla annulla questo task.
    @ObservationIgnored public private(set) var run: Task<Void, Never>?

    public init(environment: AppEnvironment, navigation: (any CleanupNavigating)?, categories: [CleanupCategory]) {
        self.environment = environment
        self.navigation = navigation
        self.categories = categories
        progress = categories.map { CategoryProgress(displayName: $0.displayName) }
        run = Task { await self.perform() }
    }

    public func cancel() {
        run?.cancel()
    }

    /// Unica via d'uscita quando l'analisi fallisce: non c'è nulla da annullare, si torna al passo 1.
    public func backToStart() {
        navigation?.startOver()
    }

    private func perform() async {
        let relay = ProgressRelay<ScanProgress> { [weak self] in self?.apply($0) }
        do {
            let results = try await environment.scan.scan(categories, progress: relay.report)
            await relay.finish()
            isRunning = false
            navigation?.showConfirm(categories, results: results)
        } catch is CancellationError {
            await relay.finish()
            isRunning = false
            navigation?.startOver()
        } catch {
            await relay.finish()
            isRunning = false
            errorText = String(localized: "Analisi non riuscita: \(FeatureText.message(error))", bundle: .module)
        }
    }

    private func apply(_ update: ScanProgress) {
        guard let category = categories.first(where: { FeatureText.same($0.id, update.categoryId) }),
              let row = progress.first(where: { FeatureText.same($0.displayName, category.displayName) })
        else { return }

        if update.currentPath.isEmpty {
            let noun = Formatting.plural(update.itemsFound, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
            row.status = "\(update.itemsFound) \(noun) · \(Formatting.bytes(update.bytesFound))"
        } else {
            row.status = String(localized: "in corso…", bundle: .module)
            currentPath = update.currentPath
        }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter ScanStepModelTests`
Expected: `Test run with 4 tests in 1 suite passed`, nessun warning. `cancelReturnsToTheFirstStep` finisce subito: se `cancel()` non annullasse l'analisi, `FakeScan` restituirebbe i risultati dopo 5 secondi e il test fallirebbe su `["confirm"]`. Suite di `CleanerFeaturesTests`: 46.

- [ ] **Step 5: Registro di parità e commit**

In fondo alla tabella «Test solo Swift di CleanerFeaturesTests», aggiungere:

```markdown
| ScanStepModelTests.swift | 4 | passo 2 (il C# non aveva prove): stato per categoria e percorso corrente dall'avanzamento, passaggio al passo 3, Annulla torna al passo 1, analisi fallita con la sola via d'uscita |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ScanStepModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ScanStepModelTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the scan step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: passo 3, conferma ed eliminazione con il diario

L'anteprima per percorso con deselezioni puntuali, le esclusioni del `PathGuard`, l'avviso delle app aperte e l'eliminazione. Prima di chiamare `CleanEngine` si apre il diario della pulizia (spec §8.2), che passa poi al passo 4.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/ConfirmStepViewModel.cs`; `swift/MjmCleanerKit/Sources/CleanerCore/Cleaning/ConfirmationRows.swift`, `History/SessionLogWriter.swift` (`openJournal`)

**Interfaces:**
- Consumes: `ConfirmationRows.build`, `CategorySelection`, `CleanPerforming.clean(_:progress:journal:)`, `CleanProgress`, `CleanReport`, `GuardExclusion`, `RunningAppsProbing.affectedApps`, `SessionLogWriting.openJournal(startedAt:)`, `PendingJournal` (Core); `AppEnvironment.clean`, `sessionLog`, `runningApps`, `clock` (Task 2); `CleanupNavigating` (Task 5); `ProgressRelay`, `Formatting`, `SafeSum`, `FeatureText` (Task 1); `FakeClean`, `FakeSessionLog`, `FakeRunningApps`, `TemporaryDirectory`, `makeEnvironment`, `makeReport`, `makeCategory`, `makeItem` (Task 2, test); `CleanupNavigationSpy` (Task 5, test).
- Produces:
  - `@MainActor @Observable public final class PathNode: Identifiable` — `item`, `isSelected`, `path`, `sizeBytes`, `sizeText`
  - `@MainActor @Observable public final class CategoryNode: Identifiable` — `categoryId`, `displayName`, `paths`, `summaryText`
  - `@MainActor @Observable public final class ConfirmStepModel` — `init(environment: AppEnvironment, navigation: (any CleanupNavigating)?, categories: [CleanupCategory], results: [CategoryScanResult])`; `nodes`, `exclusionsText`, `totalText`, `isDeleting`, `deleteProgressText`, `runningAppsWarning`, `runningAppsCheck: Task<Void, Never>?`, `canDelete`, `canCancelDelete`; `delete() async`, `cancelDelete()`, `restart()`; `static func runningAppsText(_ affected: [String]) -> String` (interno)

Note di porting:
- Il diario si apre con `sessionLog.openJournal(startedAt: clock.now)` prima di `clean` e passa sia a `clean` sia a `showDone`. Se la cartella dei log non è scrivibile, `openJournal` restituisce `nil` e la pulizia procede comunque, come in C# (test `withoutAJournalTheCleanupStillRuns`).
- `CleanEngine.clean` non lancia (piano 1): il ramo `catch` di `DeleteAsync` e il testo «Eliminazione non riuscita: …» non sono raggiungibili e non si portano (`DeleteErrorText`/`HasDeleteError` spariscono). L'annullamento restituisce il resoconto parziale, che va comunque al passo 4.
- La sonda delle app aperte non lancia (`RunningAppsProbing.affectedApps` è `async` senza `throws`): il `catch` del C#, che svuotava l'avviso, non ha equivalente.
- `CategoryNode.summaryText` in C# era calcolato sulla lista delle righe, che non cambia: qui si calcola una volta sola.
- Il C# non aveva prove per questo passo: gli otto test sono solo Swift.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 3. Il diario (spec §8.2) è nuovo.
@MainActor
struct ConfirmStepModelTests {
    private let categories = [makeCategory("logs", name: "Log e crash report"), makeCategory("downloads-large", name: "Download e file grandi")]

    private var results: [CategoryScanResult] {
        [
            CategoryScanResult(
                categoryId: "logs",
                items: [makeItem("/Users/tester/Library/Logs/a.log", size: 1024), makeItem("/Users/tester/Library/Logs/b.log", size: 2048)],
                totalBytes: 3072, errors: [], exclusions: []),
            // Lo stesso file proposto anche dai file grandi: una sola riga, nella prima categoria.
            CategoryScanResult(
                categoryId: "downloads-large",
                items: [makeItem("/Users/tester/Library/Logs/b.log", size: 2048), makeItem("/Users/tester/Downloads/big.iso", size: 1_048_576)],
                totalBytes: 1_050_624, errors: [], exclusions: []),
        ]
    }

    @Test func rowsArePerPathAcrossCategoriesWithSummariesAndTotal() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: results)

        #expect(model.nodes.map(\.displayName) == ["Log e crash report", "Download e file grandi"])
        #expect(model.nodes.map { $0.paths.map(\.path) } == [
            ["/Users/tester/Library/Logs/a.log", "/Users/tester/Library/Logs/b.log"],
            ["/Users/tester/Downloads/big.iso"],
        ])
        #expect(model.nodes.map(\.summaryText) == ["2 elementi · 3 KB", "1 elemento · 1 MB"])
        #expect(model.totalText == "1 MB · 3 elementi")
        #expect(model.exclusionsText == "")
        #expect(model.canDelete)
    }

    @Test func deselectingUpdatesTheTotalAndDisablesDeleteWhenNothingIsLeft() throws {
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: results)

        model.nodes[1].paths[0].isSelected = false
        #expect(model.totalText == "3 KB · 2 elementi")

        for node in model.nodes {
            for path in node.paths { path.isSelected = false }
        }
        #expect(model.totalText == "0 B · 0 elementi")
        #expect(!model.canDelete)
    }

    @Test func exclusionsShowTheCountAndTheFirstFive() throws {
        let exclusions = (1...6).map { GuardExclusion(path: "/Users/tester/Library/Caches/x\($0)", reason: "protetto") }
        let scanned = [CategoryScanResult(categoryId: "logs", items: [], totalBytes: 0, errors: [], exclusions: exclusions)]
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: nil, categories: categories, results: scanned)

        let lines = model.exclusionsText.split(separator: "\n").map(String.init)
        #expect(lines.first == "6 elementi esclusi dalle protezioni:")
        #expect(lines.dropFirst() == ["· /Users/tester/Library/Caches/x1 — protetto", "· /Users/tester/Library/Caches/x2 — protetto",
                                      "· /Users/tester/Library/Caches/x3 — protetto", "· /Users/tester/Library/Caches/x4 — protetto",
                                      "· /Users/tester/Library/Caches/x5 — protetto"])
    }

    @Test func runningAppsWarningNamesAtMostFiveApps() async throws {
        #expect(ConfirmStepModel.runningAppsText([]) == "")
        #expect(ConfirmStepModel.runningAppsText(["Safari"]) == "Safari in esecuzione: la sua cache potrebbe rigenerarsi subito.")
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E", "F"])
            == "A, B, C, D, E e un'altra in esecuzione: le loro cache potrebbero rigenerarsi subito.")
        #expect(ConfirmStepModel.runningAppsText(["A", "B", "C", "D", "E", "F", "G"])
            == "A, B, C, D, E e altre 2 in esecuzione: le loro cache potrebbero rigenerarsi subito.")

        let model = ConfirmStepModel(
            environment: try makeEnvironment(runningApps: FakeRunningApps(["Xcode", "Safari"])),
            navigation: nil, categories: categories, results: results)
        await model.runningAppsCheck?.value
        #expect(model.runningAppsWarning == "Xcode, Safari in esecuzione: le loro cache potrebbero rigenerarsi subito.")
    }

    @Test func deleteOpensTheJournalBeforeCleaningAndHandsItToTheDoneStep() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let sessionLog = FakeSessionLog(journalDirectory: directory.path)
        let clean = FakeClean()
        let partial = makeReport(bytesFreed: 1024, itemsDeleted: 1)
        clean.respond(with: partial)
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean, sessionLog: sessionLog),
            navigation: navigation, categories: categories, results: results)
        model.nodes[1].paths[0].isSelected = false

        await model.delete()

        #expect(sessionLog.events.values == ["open"])
        #expect(clean.receivedJournal == [true])
        #expect(clean.selections.first?.map(\.categoryId) == ["logs"])
        #expect(clean.selections.first?.first?.items.map(\.path) == ["/Users/tester/Library/Logs/a.log", "/Users/tester/Library/Logs/b.log"])
        #expect(model.deleteProgressText == "2 / 2 elementi · 0 B")
        #expect(!model.isDeleting)
        #expect(navigation.events == ["done"])
        #expect(navigation.doneReport == partial)

        let journal = try #require(navigation.doneJournal)
        let recorded = try String(contentsOfFile: journal.path, encoding: .utf8)
        #expect(recorded == "{\"path\":\"/Users/tester/Library/Logs/a.log\"}\n{\"path\":\"/Users/tester/Library/Logs/b.log\"}\n")
    }

    @Test func cancelDeleteStillShowsThePartialReport() async throws {
        let clean = FakeClean()
        clean.waitForCancellation()
        let partial = makeReport(itemsDeleted: 1)
        clean.respond(with: partial)
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean), navigation: navigation, categories: categories, results: results)

        let deleting = Task { await model.delete() }
        await clean.started.wait()

        #expect(model.isDeleting)
        #expect(model.canCancelDelete)
        #expect(!model.canDelete)

        model.cancelDelete()
        await deleting.value

        #expect(clean.observedCancellation == [true])
        #expect(navigation.events == ["done"])
        #expect(navigation.doneReport == partial)
        #expect(!model.isDeleting)
    }

    @Test func withoutAJournalTheCleanupStillRuns() async throws {
        let clean = FakeClean()
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(
            environment: try makeEnvironment(clean: clean), navigation: navigation, categories: categories, results: results)

        await model.delete()

        #expect(clean.receivedJournal == [false])
        #expect(navigation.events == ["done"])
        #expect(navigation.doneJournal == nil)
    }

    @Test func restartGoesBackToTheFirstStep() throws {
        let navigation = CleanupNavigationSpy()
        let model = ConfirmStepModel(environment: try makeEnvironment(), navigation: navigation, categories: categories, results: results)

        model.restart()

        #expect(navigation.events == ["startOver"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find 'ConfirmStepModel' in scope`.

- [ ] **Step 3: Implementare il passo 3**

`Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift`:

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
    public var isSelected = true

    init(item: ScanItem) {
        self.item = item
    }

    public var path: String { item.path }
    public var sizeBytes: Int64 { item.sizeBytes }
    public var sizeText: String { Formatting.bytes(item.sizeBytes) }
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

    init(categoryId: String, displayName: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.displayName = displayName
        paths = items.map(PathNode.init)
        let noun = Formatting.plural(items.count, String(localized: "elemento", bundle: .module), String(localized: "elementi", bundle: .module))
        summaryText = "\(Formatting.integer(items.count)) \(noun) · \(Formatting.bytes(SafeSum.total(items.map(\.sizeBytes))))"
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
        // due regole, anche di categorie diverse, possono coprire lo stesso file. La logica vive
        // nel Core (ConfirmationRows), pura e testata; qui si trasforma in nodi.
        nodes = ConfirmationRows.build(results).map { row in
            let name = categories.first { FeatureText.same($0.id, row.categoryId) }?.displayName ?? row.categoryId
            return CategoryNode(categoryId: row.categoryId, displayName: name, items: row.items)
        }

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

    private var selectedNodes: [PathNode] {
        nodes.flatMap { $0.paths.filter(\.isSelected) }
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

        let selections = nodes
            .map { CategorySelection(categoryId: $0.categoryId, items: $0.paths.filter(\.isSelected).map(\.item)) }
            .filter { !$0.items.isEmpty }

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
    /// impostazioni) invece di tornare al passo 2 conservando questa analisi.
    public func restart() {
        navigation?.startOver()
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

Run: `swift test -Xswiftc -warnings-as-errors --filter ConfirmStepModelTests`
Expected: `Test run with 8 tests in 1 suite passed`, nessun warning. Suite di `CleanerFeaturesTests`: 54.

- [ ] **Step 5: Registro di parità e commit**

In fondo alla tabella «Test solo Swift di CleanerFeaturesTests», aggiungere:

```markdown
| ConfirmStepModelTests.swift | 8 | passo 3 (il C# non aveva prove): righe per percorso deduplicate fra categorie, totali e deselezioni, esclusioni del `PathGuard`, avviso delle app aperte, diario aperto prima di `clean` e consegnato al passo 4 (spec §8.2), annullamento con resoconto parziale, pulizia senza diario |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Diario della pulizia nel wizard | assente | `ConfirmStepModel` apre il `PendingJournal` prima di `clean` e lo passa al passo 4, che lo scarta dopo il log di sessione | voluta (spec §8.2) |
| «Eliminazione non riuscita: …» (passo 3) e avviso delle app aperte svuotato da un'eccezione | rami `catch` di `ConfirmStepViewModel` | non portati: `CleanEngine.clean` e `RunningAppsProbing.affectedApps` non lanciano | per costruzione |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the confirm step with the cleanup journal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: passo 4, resoconto e salvataggio

Il resoconto della pulizia e il salvataggio, nell'ordine: storico, log di sessione, eliminazione del diario, contatore della sidebar. Il diario si scarta solo dopo che il log è stato scritto.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/DoneStepModel.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/DoneStepModelTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/DoneStepViewModel.cs`; registro di parità, riga «EACCES/EPERM da `rmdir`»

**Interfaces:**
- Consumes: `CleanReport`, `ScanError`, `ScanErrorKind`, `HistoryStoring.save`, `SessionLogWriting.write(sessionId:report:)`/`discard`, `PendingJournal` (Core); `AppEnvironment.history`, `sessionLog`, `categories()` (Task 2); `CleanupNavigating` (Task 5); `Formatting`, `FeatureText` (Task 1); `FakeHistory`, `FakeSessionLog`, `Recorder`, `TemporaryDirectory`, `makeEnvironment`, `makeReport` (Task 2, test); `CleanupNavigationSpy` (Task 5, test).
- Produces:
  - `@MainActor @Observable public final class DoneStepModel` — `init(environment: AppEnvironment, navigation: (any CleanupNavigating)?, report: CleanReport, journal: PendingJournal?)`; `freedText`, `summaryText`, `errorsText`, `rows`, `historyWarning`, `persistence: Task<Void, Never>?`; `newCleanup()`; `static func describeErrors(_ errors: [ScanError]) -> String` (interno)

Note di porting:
- `LooksLikePermissionError` riconosceva anche il testo inglese «Access to the path … is denied.», perché `Directory.Delete` su una cartella negata lanciava `IOException`. Il Core Swift classifica già EACCES/EPERM come `.accessDenied` anche da `rmdir` (registro di parità, piano 1): qui basta `kind == .accessDenied`, come annunciato in quella riga.
- `PersistAsync` intercettava solo `IOException`, `UnauthorizedAccessException` e `SqliteException`; gli altri errori lasciavano il task fallito in silenzio, senza avviso. Qui ogni errore produce l'avviso, sul lato sicuro.
- Il diario si scarta fra `write` e `refreshTotal`: un contatore non aggiornato non è un motivo per tenerlo.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/DoneStepModelTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il passo 4. L'ordine storico → log → diario è la regola
/// della spec §8.2.
@MainActor
struct DoneStepModelTests {
    @Test func textsDescribeTheReport() throws {
        let report = makeReport(
            bytesFreed: 2048, itemsDeleted: 3, duration: .milliseconds(2500),
            categories: [
                CategoryCleanResult(categoryId: "logs", bytesFreed: 2048, itemsDeleted: 3),
                CategoryCleanResult(categoryId: "trash", bytesFreed: 0, itemsDeleted: 0),
                CategoryCleanResult(categoryId: "sconosciuta", bytesFreed: 5, itemsDeleted: 1),
            ])
        let model = DoneStepModel(environment: try makeEnvironment(), navigation: nil, report: report, journal: nil)

        #expect(model.freedText == "2 KB liberati")
        #expect(model.summaryText == "in 3 secondi · 3 elementi eliminati")
        #expect(model.rows == ["Log e crash report — 2 KB", "sconosciuta — 5 B"])
        #expect(model.errorsText == "")
    }

    @Test(arguments: [
        ([ScanErrorKind.inUse, .accessDenied], "Alcuni richiedono l'Accesso completo al disco: Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco."),
        ([.notFound, .inUse], "Alcuni erano in uso da applicazioni aperte."),
        ([.notFound, .other], "Dettagli nel log della sessione."),
    ])
    func errorsTextPointsToTheLikelyCause(kinds: [ScanErrorKind], expected: String) throws {
        let errors = kinds.map { ScanError(path: "/x", kind: $0, message: "m") }
        let report = makeReport(itemsDeleted: 1, itemsFailed: errors.count, errors: errors)
        let model = DoneStepModel(environment: try makeEnvironment(), navigation: nil, report: report, journal: nil)

        #expect(model.errorsText == "2 elementi non eliminati. \(expected)")
    }

    @Test func persistenceSavesHistoryThenTheLogThenDiscardsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let navigation = CleanupNavigationSpy()
        let model = DoneStepModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: sessionLog),
            navigation: navigation, report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save", "write", "discard"])
        #expect(navigation.events == ["refreshTotal"])
        #expect(!FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "")
    }

    @Test func historyFailureKeepsTheJournalAndSaysTheCleanupHappened() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let history = FakeHistory(events: events)
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let model = DoneStepModel(
            environment: try makeEnvironment(history: history, sessionLog: sessionLog),
            navigation: CleanupNavigationSpy(), report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save"])
        #expect(FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: database bloccato")
    }

    @Test func sessionLogFailureKeepsTheJournal() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let sessionLog = FakeSessionLog(events: events, journalDirectory: directory.path)
        sessionLog.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let model = DoneStepModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: sessionLog),
            navigation: CleanupNavigationSpy(), report: makeReport(itemsDeleted: 1), journal: journal)

        await model.persistence?.value

        #expect(events.values == ["open", "save", "write"])
        #expect(sessionLog.discarded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: journal.path))
        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: disco pieno")
    }

    @Test func newCleanupStartsOver() throws {
        let navigation = CleanupNavigationSpy()
        let model = DoneStepModel(environment: try makeEnvironment(), navigation: navigation, report: makeReport(), journal: nil)

        model.newCleanup()

        #expect(navigation.events.contains("startOver"))
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find 'DoneStepModel' in scope`.

- [ ] **Step 3: Implementare il passo 4**

`Sources/CleanerFeatures/Cleanup/DoneStepModel.swift`:

```swift
import CleanerCore
import Observation

/// Porting di `DoneStepViewModel`: passo 4, resoconto e salvataggio nello storico.
@MainActor
@Observable
public final class DoneStepModel {
    @ObservationIgnored private weak var navigation: (any CleanupNavigating)?

    public let freedText: String
    public let summaryText: String
    public let errorsText: String
    public let rows: [String]
    public private(set) var historyWarning = ""

    /// Il salvataggio parte alla creazione, come nel costruttore C#; i test lo attendono.
    @ObservationIgnored public private(set) var persistence: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        navigation: (any CleanupNavigating)?,
        report: CleanReport,
        journal: PendingJournal?
    ) {
        self.navigation = navigation

        freedText = String(localized: "\(Formatting.bytes(report.bytesFreed)) liberati", bundle: .module)
        let deletedNoun = Formatting.plural(
            report.itemsDeleted,
            String(localized: "elemento eliminato", bundle: .module),
            String(localized: "elementi eliminati", bundle: .module))
        summaryText = String(
            localized: "in \(Formatting.seconds(report.duration)) secondi · \(Formatting.integer(report.itemsDeleted)) \(deletedNoun)",
            bundle: .module)

        // Il resoconto nomina le categorie per identificativo stabile ("project-build-output"),
        // non per il nome visualizzato: qui si traduce nel nome usato ovunque altrove nel wizard.
        // Il ripiego sull'identificativo è solo difensivo.
        let catalog = environment.categories()
        rows = report.categories
            .filter { $0.itemsDeleted > 0 }
            .map { result in
                let name = catalog.first { FeatureText.same($0.id, result.categoryId) }?.displayName ?? result.categoryId
                return "\(name) — \(Formatting.bytes(result.bytesFreed))"
            }

        if report.itemsFailed == 0 {
            errorsText = ""
        } else {
            let failedNoun = Formatting.plural(
                report.itemsFailed,
                String(localized: "elemento non eliminato", bundle: .module),
                String(localized: "elementi non eliminati", bundle: .module))
            errorsText = "\(report.itemsFailed) \(failedNoun). \(Self.describeErrors(report.errors))"
        }

        persistence = Task { await self.persist(environment, report, journal) }
    }

    public func newCleanup() {
        navigation?.startOver()
    }

    /// Il C# riconosceva un problema di permessi anche dal testo inglese del messaggio .NET
    /// (`LooksLikePermissionError`), perché `Directory.Delete` su una cartella negata lanciava
    /// `IOException`. Il Core Swift classifica già EACCES/EPERM come `.accessDenied` anche da
    /// `rmdir` (registro di parità), quindi basta il tipo: niente controlli sul testo.
    static func describeErrors(_ errors: [ScanError]) -> String {
        if errors.contains(where: { $0.kind == .accessDenied }) {
            return String(
                localized: "Alcuni richiedono l'Accesso completo al disco: Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco.",
                bundle: .module)
        }

        return errors.contains(where: { $0.kind == .inUse })
            ? String(localized: "Alcuni erano in uso da applicazioni aperte.", bundle: .module)
            : String(localized: "Dettagli nel log della sessione.", bundle: .module)
    }

    /// Se la scrittura dello storico fallisce la pulizia è comunque avvenuta: va detto, senza far
    /// credere che non abbia cancellato nulla. Il diario si scarta solo dopo che il log di
    /// sessione è stato scritto (spec §8.2): se qualcosa fallisce prima, resta in logs/.
    private func persist(_ environment: AppEnvironment, _ report: CleanReport, _ journal: PendingJournal?) async {
        do {
            let sessionId = try await environment.history.save(report)
            try await environment.sessionLog.write(sessionId: sessionId, report: report)
            if let journal {
                environment.sessionLog.discard(journal)
            }
            try await navigation?.refreshTotal()
        } catch {
            historyWarning = String(localized: "Pulizia completata, storico non aggiornato: \(FeatureText.message(error))", bundle: .module)
        }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DoneStepModelTests`
Expected: `Test run with 6 tests in 1 suite passed` (`errorsTextPointsToTheLikelyCause` con 3 casi), nessun warning. Suite di `CleanerFeaturesTests`: 60.

- [ ] **Step 5: Registro di parità e commit**

In fondo alla tabella «Test solo Swift di CleanerFeaturesTests», aggiungere:

```markdown
| DoneStepModelTests.swift | 6 | passo 4 (il C# non aveva prove): testi del resoconto, causa probabile degli errori (`.accessDenied` invece del testo .NET), ordine storico → log → diario → contatore, diario conservato quando storico o log falliscono |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Errori intercettati nel salvataggio dei resoconti (passo 4, Docker) | solo `IOException`, `UnauthorizedAccessException`, `SqliteException`; gli altri lasciavano il task fallito in silenzio | ogni errore produce l'avviso «Pulizia completata, storico non aggiornato: …» | accettata (lato sicuro) |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Cleanup/DoneStepModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/DoneStepModelTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the done step and discard the journal after the session log

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: pagina Docker e resoconto

L'analisi in sola lettura, i gruppi di conferma con la loro selezione, l'esecuzione e il resoconto con il salvataggio. La casella di un gruppo non seleziona mai un volume «named-unused» (follow-up del piano 2).

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/DockerViewModel.cs` (`DockerRow`, `DockerGroupNode` compresi), `DockerReportViewModel.cs`; `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerConfirmationGroups.swift`, `DockerCleanExecutor.swift` (`logEntry`)

**Interfaces:**
- Consumes: `DockerCandidate`, `DockerAnalysis`, `DockerSnapshot`, `DockerDiskUsage`, `DockerDfSummary`, `DockerDfEntry`, `DockerCleanResult`, `DockerConfirmationGroups.build`/`selection`/`requiresIndividualConfirmation`, `DockerConfirmationGroup`, `DockerGroupMode`, `DockerUnavailableError` (Core); `AppEnvironment.docker`, `expandedProjectRoots()`, `history`, `sessionLog`, `DockerCleanupServing`, `Navigating` (Task 2); `ProgressRelay`, `Formatting`, `SafeSum`, `FeatureText` (Task 1); `FakeDocker`, `FakeHistory`, `FakeSessionLog`, `FakeSettingsStore`, `Recorder`, `makeEnvironment`, `makeReport`, `UnexpectedTestError` (Task 2, test); `NavigationSpy` (Task 4, test).
- Produces:
  - `@MainActor public protocol DockerNavigating: Navigating` — `showDocker()`, `showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage)`
  - `@MainActor @Observable public final class DockerRow: Identifiable` — `candidate`, `showCheckBox`, `requiresIndividualConfirmation`, `isSelected`, `name`, `sizeText`, `kindLabel`, `detailText`
  - `@MainActor @Observable public final class DockerGroupNode: Identifiable` — `definition`, `rows`, `isSelected`, `title`, `description`, `isExpanded`, `showGroupCheckBox`, `groupCheckBoxLabel`, `summaryText`
  - `@MainActor @Observable public final class DockerModel` — `init(environment: AppEnvironment, navigation: (any DockerNavigating)?)`; `isLoading`, `errorText`, `hasError`, `isReady`, `serverText`, `diskText`, `dfText`, `groups`, `totalText`, `isDeleting`, `deleteProgressText`, `deleteErrorText`, `hasDeleteError`, `canRetry`, `canDelete`, `canCancelDelete`, `initialLoad: Task<Void, Never>?`; `retry() async`, `delete() async`, `cancelDelete()`, `close()`; interni `selection() -> [DockerCandidate]`, `static describeDisk(_:)`, `describeDf(_:)`, `typeLabel(_:)`
  - `@MainActor @Observable public final class DockerReportModel` — `init(environment: AppEnvironment, navigation: (any DockerNavigating)?, result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage)`; `freedText`, `summaryText`, `dfText`, `diskText`, `purgeHint`, `daemonLostText`, `deleted`, `failed`, `hasFailures`, `historyWarning`, `persistence: Task<Void, Never>?`; `analyzeAgain()`, `close()`; `static func describe(_ logEntry: String) -> String` (interno)
  - test: `DockerNavigationSpy: NavigationSpy, DockerNavigating`; `dockerCandidate(_:_:verdict:rule:size:cost:)`, `dockerAnalysis(_:version:disk:df:)`

Note di porting:
- La selezione resta decisa dal Core (`DockerConfirmationGroups.selection`). Il C# ritrovava gruppi e righe con `ReferenceEquals` sulle definizioni e sui candidati, che erano oggetti. In Swift sono valori `struct`: i gruppi si ritrovano per `id` e le righe per tipo + ID Docker, con chiavi ordinali (ID unici per tipo: immagini per digest, volumi per nome).
- Il follow-up del piano 2 è garantito dalla pagina: la casella di un gruppo selezionabile cambia solo le righe senza `requiresIndividualConfirmation`. `selection()` del Core non lo impone, come in C#. Un volume con nome scelto a mano entra comunque nella selezione: è la conferma singola voluta.
- Il gruppo «Da tenere» è in sola lettura: anche una riga KEEP spuntata a mano non arriva all'esecutore (lo esclude il Core).
- `describe` lavora sui byte UTF-8 come `StartsWith`/`IndexOf` ordinali. Una voce malformata che finisce con « (» in C# lanciava `ArgumentOutOfRangeException`; qui ripiega su «immagine <id>».
- Docker non ha diario della pulizia, come in C#: le rimozioni passano dalla CLI e non da `CleanEngine` (spec §8.2 riguarda la garanzia di `CleanEngine`).
- Il C# non aveva prove per la pagina e il resoconto Docker: i diciotto test sono solo Swift.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`:

```swift
import CleanerCore
import CleanerFeatures

@MainActor
final class DockerNavigationSpy: NavigationSpy, DockerNavigating {
    private(set) var reportResult: DockerCleanResult?
    private(set) var reportDiskBefore: DockerDiskUsage?
    private(set) var reportDiskAfter: DockerDiskUsage?

    func showDocker() {
        record("docker")
    }

    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {
        record("dockerReport")
        reportResult = result
        reportDiskBefore = diskBefore
        reportDiskAfter = diskAfter
    }
}

/// Candidati Docker per i test delle pagine: i campi che le pagine leggono, il resto fisso.
func dockerCandidate(
    _ kind: DockerResourceKind,
    _ id: String,
    verdict: DockerVerdict,
    rule: String = "rule",
    size: Int64? = 100 * 1024 * 1024,
    cost: String = ""
) -> DockerCandidate {
    DockerCandidate(kind: kind, id: id, displayName: "nome-\(id)", sizeBytes: size, verdict: verdict, ruleId: rule, reason: "motivo", cost: cost)
}

func dockerAnalysis(_ candidates: [DockerCandidate], version: String = "27.3.1", disk: DockerDiskUsage? = nil, df: DockerDfSummary = .empty) -> DockerAnalysis {
    DockerAnalysis(
        serverVersion: version,
        snapshot: DockerSnapshot(containers: [], images: [], volumes: [], df: df, existingComposeProjects: []),
        candidates: candidates,
        disk: disk ?? DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824))
}
```

`Tests/CleanerFeaturesTests/DockerModelTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per la pagina Docker. La selezione di gruppo che salta i
/// volumi con nome è il follow-up del registro del piano 2.
@MainActor
struct DockerModelTests {
    private static let mixed = [
        dockerCandidate(.image, "dangling", verdict: .delete),
        dockerCandidate(.image, "built", verdict: .ask),
        dockerCandidate(.image, "unused", verdict: .propose),
        dockerCandidate(.volume, "anonymous", verdict: .propose, rule: "anonymous-unused"),
        dockerCandidate(.volume, "named", verdict: .propose, rule: "named-unused"),
        dockerCandidate(.image, "running", verdict: .keep),
    ]

    /// Una pagina già caricata con un'analisi che restituisce `candidates`.
    private func loaded(_ candidates: [DockerCandidate] = mixed, docker: FakeDocker = FakeDocker(), navigation: DockerNavigationSpy? = nil) async throws -> DockerModel {
        docker.enqueue(.success(dockerAnalysis(candidates)))
        return try await opened(docker: docker, navigation: navigation)
    }

    /// Una pagina caricata con le analisi già preparate in `docker`.
    private func opened(docker: FakeDocker, navigation: DockerNavigationSpy? = nil) async throws -> DockerModel {
        let model = DockerModel(environment: try makeEnvironment(docker: docker), navigation: navigation)
        await model.initialLoad?.value
        return model
    }

    private func group(_ model: DockerModel, _ id: String) throws -> DockerGroupNode {
        try #require(model.groups.first { $0.definition.id == id })
    }

    @Test func analysisFillsTheSummaryAndTheGroups() async throws {
        var settings = CleanerSettings()
        settings.projectRoots = ["~/src"]
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed, df: DockerDfSummary(entries: [
            DockerDfEntry(type: "Images", sizeBytes: 2 * 1_073_741_824, reclaimableBytes: 1_073_741_824),
            DockerDfEntry(type: "Containers", sizeBytes: 10, reclaimableBytes: 0),
            DockerDfEntry(type: "Local Volumes", sizeBytes: 512 * 1_048_576, reclaimableBytes: 0),
            DockerDfEntry(type: "Build Cache", sizeBytes: 1_073_741_824, reclaimableBytes: 1_073_741_824),
        ]))))
        let model = DockerModel(environment: try makeEnvironment(settings: FakeSettingsStore(settings), docker: docker), navigation: nil)

        #expect(model.isLoading)
        await model.initialLoad?.value

        #expect(docker.analyzedRoots == [["/Users/tester/src"]])
        #expect(!model.isLoading)
        #expect(model.isReady)
        #expect(model.serverText == "Docker 27.3.1 in esecuzione")
        #expect(model.diskText == "Docker.raw occupa 4 GB sul disco (dimensione apparente 64 GB: è il limite massimo del disco virtuale, non lo spazio usato).")
        #expect(model.dfText == "Immagini 2 GB (recuperabili 1 GB) · Volumi 512 MB (recuperabili 0 B) · Cache di build 1 GB (recuperabili 1 GB)")
        #expect(model.groups.map(\.definition.id) == ["safe", "local-builds", "unused-images", "unused-volumes", "keep"])
        #expect(model.groups.map(\.isExpanded) == [true, true, true, true, false])
        #expect(model.groups.map(\.showGroupCheckBox) == [true, true, true, true, false])
        #expect(model.groups.map(\.groupCheckBoxLabel).prefix(2) == ["Elimina in blocco", "Seleziona tutte"])
        let volumes = try group(model, "unused-volumes")
        #expect(volumes.summaryText == "2 voci · 200 MB")
        // Solo le voci sicure partono selezionate.
        #expect(model.totalText == "100 MB · 1 voce")
        #expect(model.canDelete)
    }

    @Test func groupSelectionNeverPicksANamedVolume() async throws {
        let model = try await loaded()
        let volumes = try group(model, "unused-volumes")
        let anonymous = try #require(volumes.rows.first { $0.candidate.id == "anonymous" })
        let named = try #require(volumes.rows.first { $0.candidate.id == "named" })

        volumes.isSelected = true

        #expect(anonymous.isSelected)
        #expect(!named.isSelected)
        #expect(named.requiresIndividualConfirmation)
        #expect(model.selection().map(\.id) == ["dangling", "anonymous"])

        // Il volume con nome entra solo con la sua casella.
        named.isSelected = true
        #expect(model.selection().map(\.id) == ["dangling", "anonymous", "named"])
        #expect(volumes.isSelected)

        // Togliere il gruppo lascia il volume con nome com'è: lo si deseleziona solo a mano.
        volumes.isSelected = false
        #expect(!anonymous.isSelected)
        #expect(named.isSelected)
    }

    @Test func aGroupOfOnlyNamedVolumesHasNoGroupCheckBox() async throws {
        let model = try await loaded([dockerCandidate(.volume, "named", verdict: .propose, rule: "named-unused")])
        let volumes = try group(model, "unused-volumes")
        #expect(!volumes.showGroupCheckBox)
    }

    @Test func rowsAndTheirGroupStayInSync() async throws {
        let model = try await loaded([
            dockerCandidate(.image, "one", verdict: .propose),
            dockerCandidate(.image, "two", verdict: .propose),
        ])
        let images = try group(model, "unused-images")

        images.isSelected = true
        #expect(images.rows.map(\.isSelected) == [true, true])

        images.rows[0].isSelected = false
        #expect(!images.isSelected)
        #expect(images.rows[1].isSelected)

        images.rows[0].isSelected = true
        #expect(images.isSelected)
        #expect(model.totalText == "200 MB · 2 voci")
    }

    @Test func blockGroupCountsWholeAndKeptResourcesAreNeverSelected() async throws {
        let model = try await loaded()
        let safe = try group(model, "safe")
        let keep = try group(model, "keep")

        safe.isSelected = false
        #expect(model.selection().isEmpty)
        #expect(!model.canDelete)

        // Una voce KEEP spuntata a mano non arriva comunque all'esecutore.
        keep.rows[0].isSelected = true
        keep.isSelected = true
        #expect(model.selection().isEmpty)
        #expect(model.totalText == "0 B · 0 voci")
    }

    @Test func unavailableDockerShowsItsMessageAndRetryLoadsAgain() async throws {
        let docker = FakeDocker()
        docker.enqueue(.failure(DockerUnavailableError(DockerUnavailableError.notRunning)))
        docker.enqueue(.success(dockerAnalysis(Self.mixed)))
        let model = try await opened(docker: docker)

        #expect(model.errorText == "Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.")
        #expect(model.hasError)
        #expect(!model.isReady)
        #expect(model.canRetry)

        await model.retry()

        #expect(!model.hasError)
        #expect(model.isReady)
        #expect(model.groups.count == 5)
    }

    @Test func otherAnalysisFailuresArePrefixed() async throws {
        let docker = FakeDocker()
        docker.enqueue(.failure(UnexpectedTestError(description: "JSON non valido")))
        let model = try await opened(docker: docker)

        #expect(model.errorText == "Analisi di Docker non riuscita: JSON non valido")
    }

    @Test func deleteExecutesTheSelectionAndShowsTheReport() async throws {
        let docker = FakeDocker()
        let result = DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: nil, daemonLost: false)
        docker.respond(with: .success(result))
        let after = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 3 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824)
        docker.setDiskAfter(after)
        let navigation = DockerNavigationSpy()
        let model = try await loaded(docker: docker, navigation: navigation)

        await model.delete()

        #expect(docker.executed.map { $0.map(\.id) } == [["dangling"]])
        #expect(model.deleteProgressText == "1 / 1 · nome-dangling")
        #expect(navigation.events == ["dockerReport"])
        #expect(navigation.reportResult == result)
        #expect(navigation.reportDiskBefore == dockerAnalysis([]).disk)
        #expect(navigation.reportDiskAfter == after)
        #expect(!model.isDeleting)
    }

    @Test(arguments: [
        (DockerUnavailableError("Docker si è fermato.") as any Error, "Docker si è fermato."),
        (UnexpectedTestError(description: "timeout") as any Error, "Pulizia non riuscita: timeout"),
    ])
    func deleteFailuresAreShownOnThePage(error: any Error, expected: String) async throws {
        let docker = FakeDocker()
        docker.respond(with: .failure(error))
        let navigation = DockerNavigationSpy()
        let model = try await loaded(docker: docker, navigation: navigation)

        await model.delete()

        #expect(model.deleteErrorText == expected)
        #expect(model.hasDeleteError)
        #expect(!model.isDeleting)
        #expect(navigation.events.isEmpty)
    }

    @Test func diskDescriptionsCoverMissingAndUnmeasurableImages() {
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: nil))
            == "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.")
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: 10))
            == "Docker.raw trovato, ma lo spazio occupato non è misurabile.")
        #expect(DockerModel.typeLabel("Altro") == "Altro")
    }

    @Test func rowTextsNameKindSizeAndCost() async throws {
        let model = try await loaded([
            dockerCandidate(.volume, "named", verdict: .propose, rule: "named-unused", size: nil, cost: "dati persi"),
            dockerCandidate(.buildCache, "cache", verdict: .delete),
        ])
        let named = try #require(group(model, "unused-volumes").rows.first)
        let cache = try #require(group(model, "safe").rows.first)

        #expect(named.kindLabel == "volume")
        #expect(named.sizeText == "—")
        #expect(named.detailText == "motivo · costo: dati persi · si conferma solo singolarmente")
        #expect(named.showCheckBox)
        #expect(cache.kindLabel == "cache")
        #expect(cache.detailText == "motivo")
        #expect(!cache.showCheckBox)
    }

    @Test func closeGoesBackToTheFirstStep() async throws {
        let navigation = DockerNavigationSpy()
        let model = try await loaded(navigation: navigation)

        model.close()

        #expect(navigation.events == ["startOver"])
    }
}
```

`Tests/CleanerFeaturesTests/DockerReportModelTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Solo Swift: il C# non aveva prove per il resoconto Docker.
@MainActor
struct DockerReportModelTests {
    private static let gigabyte: Int64 = 1_073_741_824

    private func disk(_ allocated: Int64?) -> DockerDiskUsage {
        DockerDiskUsage(path: "/Docker.raw", allocatedBytes: allocated, apparentBytes: 64 * Self.gigabyte)
    }

    @Test func textsSummarizeTheCleanup() throws {
        let report = makeReport(
            bytesFreed: 3 * Self.gigabyte, itemsDeleted: 2, itemsFailed: 1,
            errors: [ScanError(path: "nome-volume", kind: .inUse, message: "volume is in use")],
            deletedPaths: ["docker:image:sha256:abc (nginx:1.27)", "docker:volume:dati"])
        let result = DockerCleanResult(
            report: report,
            before: DockerDfSummary(entries: [DockerDfEntry(type: "Images", sizeBytes: 5 * Self.gigabyte, reclaimableBytes: 0)]),
            after: DockerDfSummary(entries: [DockerDfEntry(type: "Images", sizeBytes: 2 * Self.gigabyte, reclaimableBytes: 0)]),
            daemonLost: true)

        let model = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result,
            diskBefore: disk(4 * Self.gigabyte), diskAfter: disk(4 * Self.gigabyte))

        #expect(model.freedText == "3 GB recuperati")
        #expect(model.summaryText == "2 voci eliminate · 1 non eliminata")
        #expect(model.dfText == "docker system df: 5 GB → 2 GB")
        #expect(model.diskText == "Docker.raw sul disco: 4 GB → 4 GB")
        #expect(model.purgeHint.hasPrefix("Docker.raw non si è ridotto"))
        #expect(model.daemonLostText == "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate.")
        #expect(model.deleted == ["immagine nginx:1.27", "volume dati"])
        #expect(model.failed == ["nome-volume — volume is in use"])
        #expect(model.hasFailures)
    }

    @Test func missingMeasuresAndAShrunkDiskNeedNoHint() throws {
        let result = DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: nil, daemonLost: false)

        let shrunk = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result,
            diskBefore: disk(4 * Self.gigabyte), diskAfter: disk(3 * Self.gigabyte))
        let unmeasured = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result, diskBefore: nil, diskAfter: disk(nil))

        #expect(shrunk.summaryText == "1 voce eliminata")
        #expect(shrunk.dfText == "docker system df: misura finale non disponibile.")
        #expect(shrunk.purgeHint == "")
        #expect(shrunk.daemonLostText == "")
        #expect(!shrunk.hasFailures)
        #expect(unmeasured.diskText == "Docker.raw sul disco: non misurabile.")
        #expect(unmeasured.purgeHint == "")
    }

    @Test(arguments: [
        ("docker:image:sha256:abc (nginx:1.27)", "immagine nginx:1.27"),
        ("docker:image:sha256:abc (nome (con parentesi))", "immagine nome (con parentesi)"),
        ("docker:image:sha256:abc", "immagine sha256:abc"),
        ("docker:image:x (", "immagine x ("),
        ("docker:volume:dati", "volume dati"),
        ("docker:build-cache", "cache di build"),
    ])
    func logEntriesBecomeReadableNames(entry: String, expected: String) {
        #expect(DockerReportModel.describe(entry) == expected)
    }

    @Test func persistenceSavesHistoryAndLogThenRefreshesTheTotal() async throws {
        let events = Recorder<String>()
        let navigation = DockerNavigationSpy()
        let model = DockerReportModel(
            environment: try makeEnvironment(history: FakeHistory(events: events), sessionLog: FakeSessionLog(events: events)),
            navigation: navigation,
            result: DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        await model.persistence?.value

        // Nessun diario per Docker: le rimozioni passano dalla CLI, come in C#.
        #expect(events.values == ["save", "write"])
        #expect(navigation.events == ["refreshTotal"])
        #expect(model.historyWarning == "")
    }

    @Test func persistenceFailureSaysTheCleanupHappened() async throws {
        let history = FakeHistory()
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let model = DockerReportModel(
            environment: try makeEnvironment(history: history), navigation: nil,
            result: DockerCleanResult(report: makeReport(), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        await model.persistence?.value

        #expect(model.historyWarning == "Pulizia completata, storico non aggiornato: database bloccato")
    }

    @Test func analyzeAgainAndCloseNavigate() throws {
        let navigation = DockerNavigationSpy()
        let model = DockerReportModel(
            environment: try makeEnvironment(), navigation: navigation,
            result: DockerCleanResult(report: makeReport(), before: .empty, after: .empty, daemonLost: false),
            diskBefore: nil, diskAfter: disk(nil))

        model.analyzeAgain()
        model.close()

        #expect(navigation.events.filter { $0 != "refreshTotal" } == ["docker", "startOver"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find type 'DockerNavigating' in scope` (possono seguire `DockerModel` e `DockerReportModel`).

- [ ] **Step 3: Implementare la pagina Docker**

`Sources/CleanerFeatures/Docker/DockerModel.swift`:

```swift
import CleanerCore
import Observation

/// Le destinazioni della sezione Docker.
@MainActor
public protocol DockerNavigating: Navigating {
    func showDocker()
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage)
}

/// Una risorsa Docker nella schermata di conferma.
@MainActor
@Observable
public final class DockerRow: Identifiable {
    public let candidate: DockerCandidate
    public let showCheckBox: Bool
    public let requiresIndividualConfirmation: Bool
    @ObservationIgnored fileprivate var onSelectionChanged: (@MainActor () -> Void)?

    public var isSelected: Bool {
        didSet {
            if isSelected != oldValue { onSelectionChanged?() }
        }
    }

    init(candidate: DockerCandidate, showCheckBox: Bool) {
        self.candidate = candidate
        self.showCheckBox = showCheckBox
        requiresIndividualConfirmation = DockerConfirmationGroups.requiresIndividualConfirmation(candidate)
        isSelected = candidate.selectedByDefault
    }

    public var name: String { candidate.displayName }
    public var sizeText: String { candidate.sizeBytes.map(Formatting.bytes) ?? "—" }

    public var kindLabel: String {
        switch candidate.kind {
        case .image: String(localized: "immagine", bundle: .module)
        case .volume: String(localized: "volume", bundle: .module)
        case .buildCache: String(localized: "cache", bundle: .module)
        }
    }

    public var detailText: String {
        let cost = candidate.cost.isEmpty ? "" : String(localized: " · costo: \(candidate.cost)", bundle: .module)
        let individual = requiresIndividualConfirmation
            ? String(localized: " · si conferma solo singolarmente", bundle: .module)
            : ""
        return candidate.reason + cost + individual
    }
}

@MainActor
@Observable
public final class DockerGroupNode: Identifiable {
    public let definition: DockerConfirmationGroup
    public let rows: [DockerRow]
    @ObservationIgnored private var syncing = false

    /// Per un gruppo selezionabile, la casella seleziona solo le voci che non richiedono una
    /// conferma singola: un volume con nome che nessuna regola sa ricondurre a un progetto non
    /// entra mai con la casella del gruppo (registro del piano 2, follow-up).
    public var isSelected: Bool {
        didSet {
            guard isSelected != oldValue, !syncing, definition.mode == .selectable else { return }
            syncing = true
            for row in rows where !row.requiresIndividualConfirmation {
                row.isSelected = isSelected
            }
            syncing = false
        }
    }

    init(_ definition: DockerConfirmationGroup) {
        self.definition = definition
        rows = definition.items.map { DockerRow(candidate: $0, showCheckBox: definition.mode == .selectable) }
        isSelected = definition.selectedByDefault
        for row in rows {
            row.onSelectionChanged = { [weak self] in self?.rowChanged() }
        }
    }

    public var title: String { definition.title }
    public var description: String { definition.description }

    /// Le voci da tenere restano chiuse: si guardano solo se servono.
    public var isExpanded: Bool { definition.mode != .readOnly }

    /// La casella del gruppo esiste per i blocchi e per i gruppi in cui almeno una voce si può
    /// selezionare insieme alle altre: un gruppo di soli volumi con nome non ne ha bisogno.
    public var showGroupCheckBox: Bool {
        switch definition.mode {
        case .block: true
        case .selectable: rows.contains { !$0.requiresIndividualConfirmation }
        case .readOnly: false
        }
    }

    public var groupCheckBoxLabel: String {
        definition.mode == .block
            ? String(localized: "Elimina in blocco", bundle: .module)
            : String(localized: "Seleziona tutte", bundle: .module)
    }

    public var summaryText: String {
        let noun = Formatting.plural(rows.count, String(localized: "voce", bundle: .module), String(localized: "voci", bundle: .module))
        let bytes = SafeSum.total(rows.map { $0.candidate.sizeBytes ?? 0 })
        return "\(Formatting.integer(rows.count)) \(noun) · \(Formatting.bytes(bytes))"
    }

    private func rowChanged() {
        guard !syncing else { return }
        syncing = true
        isSelected = rows.filter { !$0.requiresIndividualConfirmation }.allSatisfy(\.isSelected)
        syncing = false
    }
}

/// Porting di `DockerViewModel`: analisi in sola lettura, anteprima con selezione, esecuzione.
/// L'anteprima è il dry-run: nessun comando distruttivo parte prima di «Elimina».
@MainActor
@Observable
public final class DockerModel {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private weak var navigation: (any DockerNavigating)?
    @ObservationIgnored private var diskBefore: DockerDiskUsage?
    @ObservationIgnored private var deleteTask: Task<DockerCleanResult, any Error>?

    public private(set) var isLoading = true
    public private(set) var errorText = ""
    public private(set) var isReady = false
    public private(set) var serverText = ""
    public private(set) var diskText = ""
    public private(set) var dfText = ""
    public private(set) var groups: [DockerGroupNode] = []
    public private(set) var isDeleting = false
    public private(set) var deleteProgressText = ""
    public private(set) var deleteErrorText = ""

    @ObservationIgnored public private(set) var initialLoad: Task<Void, Never>?

    public init(environment: AppEnvironment, navigation: (any DockerNavigating)?) {
        self.environment = environment
        self.navigation = navigation
        initialLoad = Task { await self.load() }
    }

    public var hasError: Bool { !errorText.isEmpty }
    public var hasDeleteError: Bool { !deleteErrorText.isEmpty }
    public var canRetry: Bool { !isLoading }
    public var canDelete: Bool { isReady && !isDeleting && !selection().isEmpty }
    public var canCancelDelete: Bool { isDeleting }

    public var totalText: String {
        let selected = selection()
        let noun = Formatting.plural(selected.count, String(localized: "voce", bundle: .module), String(localized: "voci", bundle: .module))
        let bytes = SafeSum.total(selected.map { $0.sizeBytes ?? 0 })
        return "\(Formatting.bytes(bytes)) · \(Formatting.integer(selected.count)) \(noun)"
    }

    public func retry() async {
        await load()
    }

    public func delete() async {
        guard canDelete else { return }
        isDeleting = true
        deleteErrorText = ""

        let selected = selection()
        let relay = ProgressRelay<CleanProgress> { [weak self] progress in
            self?.deleteProgressText = "\(Formatting.integer(progress.itemsDone)) / \(Formatting.integer(progress.itemsTotal)) · \(progress.currentPath)"
        }
        let docker = environment.docker
        let report = relay.report
        let task = Task { try await docker.execute(selected, progress: report) }
        deleteTask = task

        do {
            let result = try await task.value
            await relay.finish()
            let diskAfter = try await docker.measureDisk()
            navigation?.showDockerReport(result, diskBefore: diskBefore, diskAfter: diskAfter)
        } catch let error as DockerUnavailableError {
            await relay.finish()
            deleteErrorText = error.message
        } catch {
            await relay.finish()
            deleteErrorText = String(localized: "Pulizia non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        deleteTask = nil
        isDeleting = false
    }

    public func cancelDelete() {
        deleteTask?.cancel()
    }

    public func close() {
        navigation?.startOver()
    }

    /// Le voci da consegnare all'esecutore, decise dal Core (`DockerConfirmationGroups.selection`).
    /// Gruppi e righe si ritrovano per identificativo con confronti ordinali: i valori `struct`
    /// non hanno l'identità di riferimento che il C# usava (`ReferenceEquals`).
    func selection() -> [DockerCandidate] {
        var groupsById: [[UInt8]: DockerGroupNode] = [:]
        var rowsByKey: [[UInt8]: DockerRow] = [:]
        for group in groups {
            if groupsById[FeatureText.ordinalKey(group.definition.id)] == nil {
                groupsById[FeatureText.ordinalKey(group.definition.id)] = group
            }
            for row in group.rows where rowsByKey[Self.rowKey(row.candidate)] == nil {
                rowsByKey[Self.rowKey(row.candidate)] = row
            }
        }

        return DockerConfirmationGroups.selection(
            groups.map(\.definition),
            isGroupSelected: { groupsById[FeatureText.ordinalKey($0.id)]?.isSelected ?? false },
            isItemSelected: { rowsByKey[Self.rowKey($0)]?.isSelected ?? false })
    }

    /// Tipo e identificativo: gli ID di Docker sono unici per tipo (immagini per digest, volumi per nome).
    private static func rowKey(_ candidate: DockerCandidate) -> [UInt8] {
        let kind = switch candidate.kind {
        case .image: "image"
        case .volume: "volume"
        case .buildCache: "build-cache"
        }
        return FeatureText.ordinalKey(kind + ":" + candidate.id)
    }

    private func load() async {
        isLoading = true
        isReady = false
        errorText = ""
        groups = []

        do {
            let analysis = try await environment.docker.analyze(environment.expandedProjectRoots())
            diskBefore = analysis.disk
            serverText = String(localized: "Docker \(analysis.serverVersion) in esecuzione", bundle: .module)
            diskText = Self.describeDisk(analysis.disk)
            dfText = Self.describeDf(analysis.snapshot.df)
            groups = DockerConfirmationGroups.build(analysis.candidates).map(DockerGroupNode.init)
            isReady = true
        } catch let error as DockerUnavailableError {
            // Messaggio già pensato per l'utente: Docker Desktop non viene avviato da qui, è
            // l'utente a deciderlo.
            errorText = error.message
        } catch {
            errorText = String(localized: "Analisi di Docker non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        isLoading = false
    }

    static func describeDisk(_ disk: DockerDiskUsage) -> String {
        guard disk.exists else {
            return String(
                localized: "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.",
                bundle: .module)
        }
        guard let allocated = disk.allocatedBytes, let apparent = disk.apparentBytes else {
            return String(localized: "Docker.raw trovato, ma lo spazio occupato non è misurabile.", bundle: .module)
        }
        return String(
            localized: "Docker.raw occupa \(Formatting.bytes(allocated)) sul disco (dimensione apparente \(Formatting.bytes(apparent)): è il limite massimo del disco virtuale, non lo spazio usato).",
            bundle: .module)
    }

    static func describeDf(_ df: DockerDfSummary) -> String {
        df.entries
            .filter { !FeatureText.same($0.type, "Containers") }
            .map { entry in
                String(
                    localized: "\(typeLabel(entry.type)) \(Formatting.bytes(entry.sizeBytes)) (recuperabili \(Formatting.bytes(entry.reclaimableBytes)))",
                    bundle: .module)
            }
            .joined(separator: " · ")
    }

    static func typeLabel(_ dfType: String) -> String {
        if FeatureText.same(dfType, DockerDfSummary.imagesType) { return String(localized: "Immagini", bundle: .module) }
        if FeatureText.same(dfType, DockerDfSummary.volumesType) { return String(localized: "Volumi", bundle: .module) }
        if FeatureText.same(dfType, DockerDfSummary.buildCacheType) { return String(localized: "Cache di build", bundle: .module) }
        return dfType
    }
}
```

- [ ] **Step 4: Implementare il resoconto Docker**

`Sources/CleanerFeatures/Docker/DockerReportModel.swift`:

```swift
import CleanerCore
import Observation

/// Porting di `DockerReportViewModel`: il resoconto di una pulizia Docker e il suo salvataggio.
/// Le rimozioni di Docker passano dalla CLI e non da `CleanEngine`: come in C# non hanno diario.
@MainActor
@Observable
public final class DockerReportModel {
    @ObservationIgnored private weak var navigation: (any DockerNavigating)?

    public let freedText: String
    public let summaryText: String
    public let dfText: String
    public let diskText: String
    public let purgeHint: String
    public let daemonLostText: String
    public let deleted: [String]
    public let failed: [String]
    public private(set) var historyWarning = ""

    @ObservationIgnored public private(set) var persistence: Task<Void, Never>?

    public init(
        environment: AppEnvironment,
        navigation: (any DockerNavigating)?,
        result: DockerCleanResult,
        diskBefore: DockerDiskUsage?,
        diskAfter: DockerDiskUsage
    ) {
        self.navigation = navigation
        let report = result.report

        freedText = String(localized: "\(Formatting.bytes(report.bytesFreed)) recuperati", bundle: .module)
        let deletedNoun = Formatting.plural(
            report.itemsDeleted,
            String(localized: "voce eliminata", bundle: .module),
            String(localized: "voci eliminate", bundle: .module))
        var summary = "\(Formatting.integer(report.itemsDeleted)) \(deletedNoun)"
        if report.itemsFailed > 0 {
            let failedNoun = Formatting.plural(
                report.itemsFailed,
                String(localized: "eliminata", bundle: .module),
                String(localized: "eliminate", bundle: .module))
            summary += String(localized: " · \(Formatting.integer(report.itemsFailed)) non \(failedNoun)", bundle: .module)
        }
        summaryText = summary

        if let after = result.after {
            dfText = String(
                localized: "docker system df: \(Formatting.bytes(result.before.total)) → \(Formatting.bytes(after.total))",
                bundle: .module)
        } else {
            dfText = String(localized: "docker system df: misura finale non disponibile.", bundle: .module)
        }

        if let before = diskBefore?.allocatedBytes, let after = diskAfter.allocatedBytes {
            diskText = String(localized: "Docker.raw sul disco: \(Formatting.bytes(before)) → \(Formatting.bytes(after))", bundle: .module)
        } else {
            diskText = String(localized: "Docker.raw sul disco: non misurabile.", bundle: .module)
        }

        // Docker Desktop restituisce lo spazio al Mac in modo differito: il disco virtuale può
        // restare grande anche dopo una pulizia riuscita. Purge è l'unico modo per forzarlo, e
        // cancella TUTTO: lo si suggerisce, mai lo si esegue.
        if report.itemsDeleted > 0,
           let rawBefore = diskBefore?.allocatedBytes,
           let rawAfter = diskAfter.allocatedBytes,
           rawAfter >= rawBefore {
            purgeHint = String(
                localized: "Docker.raw non si è ridotto: Docker Desktop restituisce lo spazio al Mac con calma. Per recuperarlo subito: Docker Desktop → Troubleshoot → Clean / Purge data. Attenzione: quell'operazione cancella tutte le immagini, i container e i volumi.",
                bundle: .module)
        } else {
            purgeHint = ""
        }

        daemonLostText = result.daemonLost
            ? String(localized: "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate.", bundle: .module)
            : ""

        deleted = report.deletedPaths.map(Self.describe)
        failed = report.errors.map { "\($0.path) — \($0.message)" }

        persistence = Task { await self.persist(environment, report) }
    }

    public var hasFailures: Bool { !failed.isEmpty }

    public func analyzeAgain() {
        navigation?.showDocker()
    }

    public func close() {
        navigation?.startOver()
    }

    /// "docker:image:sha256:… (nome)" → "immagine nome": l'identificativo completo resta nel log di
    /// sessione. Si lavora sui byte UTF-8, come `StartsWith`/`IndexOf` ordinali del C#.
    static func describe(_ logEntry: String) -> String {
        let image = "docker:image:"
        let volume = "docker:volume:"
        let bytes = Array(logEntry.utf8)

        if FeatureText.hasOrdinalPrefix(logEntry, image) {
            let open = (0..<max(0, bytes.count - 1)).first { bytes[$0] == UInt8(ascii: " ") && bytes[$0 + 1] == UInt8(ascii: "(") }
            if let open, open > 0, open + 2 <= bytes.count - 1 {
                let name = String(decoding: bytes[(open + 2)..<(bytes.count - 1)], as: UTF8.self)
                return String(localized: "immagine \(name)", bundle: .module)
            }
            let id = String(decoding: bytes.dropFirst(image.utf8.count), as: UTF8.self)
            return String(localized: "immagine \(id)", bundle: .module)
        }

        if FeatureText.hasOrdinalPrefix(logEntry, volume) {
            let name = String(decoding: bytes.dropFirst(volume.utf8.count), as: UTF8.self)
            return String(localized: "volume \(name)", bundle: .module)
        }

        return String(localized: "cache di build", bundle: .module)
    }

    /// Come per il wizard: la pulizia è avvenuta anche se lo storico non si aggiorna, e va detto.
    private func persist(_ environment: AppEnvironment, _ report: CleanReport) async {
        do {
            let sessionId = try await environment.history.save(report)
            try await environment.sessionLog.write(sessionId: sessionId, report: report)
            try await navigation?.refreshTotal()
        } catch {
            historyWarning = String(localized: "Pulizia completata, storico non aggiornato: \(FeatureText.message(error))", bundle: .module)
        }
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "DockerModelTests|DockerReportModelTests"`
Expected: `Test run with 18 tests in 2 suites passed` (12 di `DockerModelTests`, 6 di `DockerReportModelTests`), nessun warning. Suite di `CleanerFeaturesTests`: 78.

- [ ] **Step 6: Registro di parità e commit**

In fondo alla tabella «Test solo Swift di CleanerFeaturesTests», aggiungere:

```markdown
| DockerModelTests.swift | 12 | pagina Docker (il C# non aveva prove): riepilogo e gruppi dall'analisi, casella di gruppo che non seleziona mai un volume «named-unused» (follow-up del piano 2), righe e gruppo sincronizzati, gruppo a blocco e voci KEEP, Docker non raggiungibile e Riprova, esecuzione con misura finale e resoconto, errori di esecuzione |
| DockerReportModelTests.swift | 6 | resoconto Docker: testi, suggerimento di Purge, nomi leggibili delle voci del log, salvataggio senza diario e avviso se fallisce, navigazione |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Ricerca di gruppi e righe Docker nella selezione | `ReferenceEquals` fra definizioni e candidati (oggetti) | gruppi per `id`, righe per tipo + ID Docker, con chiavi ordinali | equivalente (ID unici per tipo) |
| Voce del log Docker malformata («docker:image:x (») | `ArgumentOutOfRangeException` nel resoconto | «immagine x (» | accettata (l'esecutore scrive sempre voci ben formate) |
| Diario delle rimozioni Docker | assente | assente: le rimozioni passano dalla CLI, non da `CleanEngine` | identica |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the Docker page and report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: pagina Xcode e resoconto

Analisi, selezione per gruppi e righe, anteprima obbligatoria, presa d'atto dei simulatori dipendenti, conferma finale con esecuzione unica e resoconto salvato una volta sola. Il diario si apre prima di `execute` e lo scarta il resoconto, dopo il log di sessione. Pagina e resoconto stanno nello stesso task, come in C#: è la pagina a creare il proprio resoconto.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Xcode/XcodeReportModel.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Xcode/XcodeModel.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Xcode/XcodeViewModelTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Xcode/XcodeReportViewModelTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Xcode/XcodeViewLayoutTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/XcodeViewModel.cs` (`XcodeRow`, `XcodeGroupNode`, `IXcodeNavigation` compresi), `XcodeReportViewModel.cs`; `tests/MjmCleaner.App.Tests/Xcode/XcodeViewModelTests.cs`, `XcodeReportViewModelTests.cs`, `XcodeViewLayoutTests.cs`; registro del piano 3, «Follow-ups»

**Interfaces:**
- Consumes: `XcodeCleanupServing.analyze()`/`execute(_:progress:journal:)`, `XcodeSnapshot`, `XcodeCandidate`, `XcodeResourceKind`, `XcodeInventoryWarning`, `XcodeSelection.preview(_:selectedKeys:)`/`confirm(_:acknowledgeDependencies:)`, `XcodeConfirmation`, `XcodeConfirmedPlan`, `XcodeCleanResult`, `XcodeItemResult`, `XcodeItemOutcome`, `XcodeUnavailableError`, `HistoryStoring`, `SessionLogWriting`, `PendingJournal`, `WallClock`, `CleanProgress` (Core); `Navigating` (Task 2); `ProgressRelay`, `Formatting`, `SafeSum`, `FeatureText` (Task 1); `FakeHistory`, `FakeSessionLog`, `Gate`, `Recorder`, `FixedWallClock`, `TemporaryDirectory`, `makeReport`, `UnexpectedTestError` (Task 2, test); `NavigationSpy` (Task 4, test).
- Produces:
  - `@MainActor public protocol XcodeNavigating: Navigating` — `showXcode()`, `showXcodeReport(_ report: XcodeReportModel)`
  - `public struct XcodeResultRow: Identifiable, Sendable` — `id`, `item`, `name`, `identity`, `detail`, `outcomeText`, `sizeText`
  - `@MainActor @Observable public final class XcodeReportModel` — `init(history: any HistoryStoring, sessionLog: any SessionLogWriting, navigation: (any XcodeNavigating)?, result: XcodeCleanResult, journal: PendingJournal?)`; `items`, `freedText`, `summaryText`, `freeSpaceText`, `warningsText`, `hasWarnings`, `historyWarning`, `hasHistoryWarning`, `persistence: Task<Void, Never>?`; `persist() async`, `analyzeAgain()`, `close()`
  - `@MainActor @Observable public final class XcodeRow: Identifiable` — `candidate`, `isSelected`, `name`, `sizeText`, `identityText`, `stateText`, `hasState`, `canSelect`
  - `@MainActor @Observable public final class XcodeGroupNode: Identifiable` — `init(kind:candidates:warnings:)`; `kind`, `rows`, `warnings`, `isSelected`, `title`, `isExpanded`, `showGroupCheckBox`, `summary`
  - `@MainActor @Observable public final class XcodeModel` — `init(xcode: any XcodeCleanupServing, history: any HistoryStoring, sessionLog: any SessionLogWriting, clock: any WallClock, navigation: (any XcodeNavigating)?)`; `isLoading`, `isDeleting`, `errorText`, `warningText`, `progressText`, `acknowledgeDependencies`, `confirmation`, `currentReport`, `groups`, `initialLoad: Task<Void, Never>?`, `hasError`, `hasWarnings`, `hasConfirmation`, `hasRetainedDependencies`, `hasSelectedDevices`, `hasSelectedRuntimes`, `previewSummaryText`, `previewEstimateText`, `totalText`, `canRetry`, `canPreview`, `canNavigate`, `canCancelDelete`, `canConfirmDelete`; `retry() async`, `preview()`, `confirmDelete() async`, `cancelDelete()`, `backToSelection()`, `close()`; interno `selectedKeys() -> Set<String>`
  - test: in `XcodeViewModelTests`, `FakeXcode` (`executionStarted`, `execution`, `executeCount`, `receivedJournal`, `observedCancellation`, `respondImmediately(with:)`, `returnWhenCancelled(_:)`, `failAnalysis(with:)`), `FakeNavigation: NavigationSpy, XcodeNavigating` (`navigationCount`), `clock`, `snapshot(_:)`, `candidate(_:_:dependencies:)`, `uuid(_:)`, `result()`, `create(_:_:)`, `group(_:_:)`, `onlyRow(_:_:)`

Note di porting:
- **Esecutore che non lancia.** `XcodeCleanupServing.execute` non lancia: anche annullata, restituisce un resoconto da salvare (follow-up del piano 3). L'unico errore possibile nella conferma è di `XcodeSelection.confirm` (per esempio dispositivi dipendenti non presi in carico). Il ramo `OperationCanceledException` e il testo «Operazione interrotta prima di poter produrre il report.» non sono raggiungibili e non si portano. `RetryAfterExecutionFailureCanConfirmAgain` provoca quindi il primo fallimento con la conferma senza presa d'atto invece che con un'eccezione dell'esecutore: il comportamento verificato (riprovare e confermare di nuovo) è lo stesso.
- **Identità delle righe.** Le righe si identificano come oggetti (`Identifiable` di `AnyObject`), mai con `==` su `XcodeCandidate`. Le chiavi selezionate vanno in un `Set<String>`, che unisce chiavi canonicamente equivalenti dove l'`HashSet` ordinale del C# le teneva distinte: si seleziona al più di meno, il lato sicuro, e `XcodeSelection` cerca ogni chiave con confronto ordinale (registro del piano 3, Task 3).
- **Anteprima.** Passa sempre da `XcodeSelection.preview` sullo snapshot dell'analisi. Con lo stato di Xcode ignoto l'analisi restituisce candidati non classificati, e `preview` li classifica (follow-up del piano 3).
- **Doppi.** `FakeXcode` e `FakeNavigation` restano annidati in `XcodeViewModelTests`, come le classi interne del C#. `FakeHistory` e `FakeLog` sono i doppi condivisi del Task 2. L'UUID dei candidati di prova si ricava dalla chiave con FNV-1a invece che con MD5: i valori cambiano, la proprietà (deterministico, forma "D" valida) no. Un `TaskCompletionSource` diventa `Gate`; la chiamata `ExecuteAsync` controllata subito diventa un `Task` più `await service.executionStarted.wait()`.
- **Riepiloghi.** «N voci» del riepilogo di gruppo resta senza concordanza («1 voci»), come il testo C#: candidato a miglioramento.
- Le quattro prove di `XcodeViewLayoutTests.cs` si portano sul modello (titoli, testo dell'anteprima, anteprime di 100 risorse, identità delle righe). Che i pulsanti restino nel viewport lo verificherà il piano 4b.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/Xcode/XcodeViewModelTests.swift`:

```swift
import CleanerCore
import Foundation
import Synchronization
import Testing
@testable import CleanerFeatures

@MainActor
struct XcodeViewModelTests {
    @Test func groupSelectionOnlyAffectsCaches() async throws {
        let service = FakeXcode(Self.snapshot(
            Self.candidate("dd", .derivedData), Self.candidate("support", .deviceSupport),
            Self.candidate("device", .device), Self.candidate("runtime", .runtime)))
        let model = Self.create(service)
        await model.initialLoad?.value
        #expect(model.groups.flatMap(\.rows).allSatisfy { !$0.isSelected })

        let cache = try Self.group(model, .derivedData)
        cache.isSelected = true
        #expect(cache.rows.allSatisfy { $0.isSelected })
        let support = try Self.group(model, .deviceSupport)
        support.isSelected = true
        #expect(support.rows.allSatisfy { $0.isSelected })

        let individual = model.groups.filter { $0.kind == .device || $0.kind == .runtime }
        #expect(individual.flatMap(\.rows).allSatisfy { !$0.isSelected })
        #expect(individual.allSatisfy { !$0.showGroupCheckBox })
    }

    @Test func deleteRequiresPreviewAndAcknowledgement() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        #expect(!model.canConfirmDelete)

        model.preview()
        #expect(model.confirmation?.retainedDependentDevices.count == 1)
        #expect(!model.canConfirmDelete)

        model.acknowledgeDependencies = true
        #expect(model.canConfirmDelete)
    }

    @Test func doubleClickExecutesOnce() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        let first = Task { await model.confirmDelete() }
        await service.executionStarted.wait()
        let second = Task { await model.confirmDelete() }
        await second.value
        #expect(service.executeCount == 1)

        service.execution.open(Self.result())
        await first.value

        #expect(service.executeCount == 1)
        #expect(!model.canConfirmDelete)
    }

    @Test func retryClearsOldSelection() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("one", .device)), Self.snapshot(Self.candidate("two", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true

        await model.retry()

        let row = try Self.onlyRow(model, .device)
        #expect(row.candidate.name == "two")
        #expect(!row.isSelected)
    }

    @Test func unknownOnlyGroupSummaryDoesNotDisplayZeroBytes() {
        var unknown = Self.candidate("unknown", .deviceSupport)
        unknown.sizeBytes = nil
        let group = XcodeGroupNode(kind: .deviceSupport, candidates: [unknown], warnings: [])

        #expect(group.summary.contains("dimensioni non disponibili"))
        #expect(!group.summary.contains("0 B"))
    }

    @Test func emptyGroupSummaryShowsZeroEntriesWithoutSizeWarning() {
        let group = XcodeGroupNode(kind: .deviceSupport, candidates: [], warnings: [])

        #expect(group.summary.contains("0 voci"))
        #expect(!group.summary.contains("dimensioni non disponibili"))
    }

    @Test func mixedGroupSummaryLabelsKnownEstimateAndUnknownCount() {
        var known = Self.candidate("known", .derivedData)
        known.sizeBytes = 2048
        var unknown = Self.candidate("unknown", .derivedData)
        unknown.sizeBytes = nil
        let group = XcodeGroupNode(kind: .derivedData, candidates: [known, unknown], warnings: [])

        #expect(group.summary.contains("noti"))
        #expect(group.summary.contains("1 dimensione non disponibile"))
    }

    @Test func cannotNavigateDuringDelete() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        let navigation = FakeNavigation()
        let model = Self.create(service, navigation)
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        let deleting = Task { await model.confirmDelete() }
        await service.executionStarted.wait()
        model.close()
        model.backToSelection()

        #expect(navigation.navigationCount == 0)
        #expect(!model.canNavigate)
        service.execution.open(Self.result())
        await deleting.value
    }

    @Test func cancelDeleteReturnsAndPersistsPartialReportOnce() async throws {
        let history = FakeHistory()
        let log = FakeSessionLog()
        let partial = XcodeCleanResult(
            historyReport: makeReport(),
            items: [XcodeItemResult(candidate: Self.candidate("device", .device), outcome: .skipped, reason: "annullata", verifiedEstimatedBytes: nil)],
            freeBytesBefore: 10, freeBytesAfter: 10, warnings: [])
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        service.returnWhenCancelled(partial)
        let model = XcodeModel(xcode: service, history: history, sessionLog: log, clock: Self.clock, navigation: FakeNavigation())
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        let deleting = Task { await model.confirmDelete() }
        await service.executionStarted.wait()
        model.cancelDelete()
        await deleting.value
        #expect(service.observedCancellation == [true])
        let report = try #require(model.currentReport)
        await report.persistence?.value
        await report.persist()

        #expect(report.items.count == 1)
        #expect(report.items.first?.outcomeText == "Saltata")
        #expect(history.saves == 1)
        #expect(log.writes == 1)
    }

    /// In C# il primo tentativo falliva perché l'esecutore lanciava un'eccezione. In Swift
    /// l'esecutore non lancia mai: l'unico fallimento possibile è la conferma, che rifiuta un piano
    /// con dispositivi dipendenti non presi in carico. Il comportamento verificato è lo stesso:
    /// dopo un fallimento si può riprovare e confermare di nuovo.
    @Test func retryAfterExecutionFailureCanConfirmAgain() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        service.respondImmediately(with: Self.result())
        let navigation = FakeNavigation()
        let model = Self.create(service, navigation)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()

        await model.confirmDelete()
        #expect(model.errorText.hasPrefix("Pulizia Xcode non riuscita: "))
        #expect(service.executeCount == 0)

        await model.retry()
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()
        model.acknowledgeDependencies = true
        #expect(model.canConfirmDelete)
        await model.confirmDelete()

        #expect(service.executeCount == 1)
        #expect(navigation.navigationCount == 1)
        #expect(model.currentReport != nil)
    }

    // Solo Swift: diario della pulizia (spec §8.2), avvisi, totali, anteprima scartata, errori.

    @Test func journalIsOpenedBeforeExecutionAndDiscardedByTheReport() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let events = Recorder<String>()
        let log = FakeSessionLog(events: events, journalDirectory: directory.path)
        let service = FakeXcode(Self.snapshot(Self.candidate("device", .device)))
        service.respondImmediately(with: Self.result())
        let model = XcodeModel(xcode: service, history: FakeHistory(events: events), sessionLog: log, clock: Self.clock, navigation: FakeNavigation())
        await model.initialLoad?.value
        try Self.onlyRow(model, .device).isSelected = true
        model.preview()

        await model.confirmDelete()
        await model.currentReport?.persistence?.value

        #expect(service.receivedJournal == [true])
        #expect(events.values == ["open", "save", "write", "discard"])
        #expect(log.discarded.count == 1)
    }

    @Test func warningsAreShownOnceAndPerGroup() async throws {
        let snapshot = XcodeSnapshot(
            candidates: [Self.candidate("device", .device)],
            warnings: [
                .completenessFailure(.device, "Inventario dei simulatori incompleto."),
                .advisory(.runtime, "Rimozione dei runtime non supportata."),
                .completenessFailure(.device, "Inventario dei simulatori incompleto."),
            ])
        let model = Self.create(FakeXcode(snapshot))
        await model.initialLoad?.value

        #expect(model.warningText == "Inventario dei simulatori incompleto.\nRimozione dei runtime non supportata.")
        #expect(model.hasWarnings)
        #expect(try Self.group(model, .device).warnings == ["Inventario dei simulatori incompleto.", "Inventario dei simulatori incompleto."])
        #expect(try Self.group(model, .runtime).warnings == ["Rimozione dei runtime non supportata."])
    }

    @Test func totalCountsKnownAndUnknownSizesWithoutOverflow() async throws {
        var huge = Self.candidate("huge", .derivedData)
        huge.sizeBytes = Int64.max
        var unknown = Self.candidate("unknown", .derivedData)
        unknown.sizeBytes = nil
        let model = Self.create(FakeXcode(Self.snapshot(huge, Self.candidate("small", .derivedData), unknown)))
        await model.initialLoad?.value
        #expect(model.totalText == "0 B stimati · 0 selezionate")

        try Self.group(model, .derivedData).isSelected = true

        #expect(model.totalText == "8388608 TB stimati · 3 selezionate · 1 non disponibili")
        #expect(try Self.group(model, .derivedData).summary == "3 voci · 8388608 TB stimati noti · 1 dimensione non disponibile")
    }

    @Test func changingTheSelectionDiscardsThePreview() async throws {
        let service = FakeXcode(Self.snapshot(Self.candidate("runtime", .runtime, dependencies: ["device"]), Self.candidate("device", .device)))
        let model = Self.create(service)
        await model.initialLoad?.value
        try Self.onlyRow(model, .runtime).isSelected = true
        model.preview()
        model.acknowledgeDependencies = true
        #expect(model.hasConfirmation)
        #expect(model.hasRetainedDependencies)
        #expect(model.hasSelectedRuntimes)
        #expect(!model.hasSelectedDevices)

        try Self.onlyRow(model, .device).isSelected = true

        #expect(!model.hasConfirmation)
        #expect(!model.acknowledgeDependencies)
        #expect(model.previewSummaryText == "")
    }

    @Test func analysisFailureIsShown() async throws {
        let service = FakeXcode()
        service.failAnalysis(with: XcodeUnavailableError("Xcode command line tools non trovati."))
        let model = Self.create(service)
        await model.initialLoad?.value

        #expect(model.errorText == "Analisi Xcode non riuscita: Xcode command line tools non trovati.")
        #expect(model.groups.isEmpty)
        #expect(model.canRetry)
    }

    // MARK: Doppi e fixture (in C# classi interne di questa classe di test)

    static let clock = FixedWallClock(now: Date(timeIntervalSince1970: 1_790_000_000))

    static func snapshot(_ candidates: XcodeCandidate...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: [])
    }

    /// Come il C#: un UUID deterministico ricavato dalla chiave (là con MD5, qui con FNV-1a: i
    /// valori cambiano, la proprietà no), chiave "runtime:<uuid>" per i runtime e l'UUID stesso per
    /// i simulatori.
    static func candidate(_ key: String, _ kind: XcodeResourceKind, dependencies: [String]? = nil) -> XcodeCandidate {
        let id = uuid(key)
        let identity = kind == .runtime ? "runtime:" + id : kind == .device ? id : key
        return XcodeCandidate(
            key: identity, kind: kind, name: key,
            cliId: kind == .device || kind == .runtime ? id : nil,
            state: kind == .device ? "Shutdown" : nil,
            sizeBytes: 100,
            dependencies: dependencies?.map(uuid))
    }

    static func uuid(_ key: String) -> String {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x8422_2325_cbf2_9ce4
        for byte in key.utf8 {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 &+ 1
        }
        let hex = Array(String(format: "%016llx%016llx", first, second))
        return [hex[0..<8], hex[8..<12], hex[12..<16], hex[16..<20], hex[20..<32]].map { String($0) }.joined(separator: "-")
    }

    static func result() -> XcodeCleanResult {
        XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: 100, freeBytesAfter: 120, warnings: [])
    }

    static func create(_ service: FakeXcode, _ navigation: FakeNavigation = FakeNavigation()) -> XcodeModel {
        XcodeModel(xcode: service, history: FakeHistory(), sessionLog: FakeSessionLog(), clock: clock, navigation: navigation)
    }

    static func group(_ model: XcodeModel, _ kind: XcodeResourceKind) throws -> XcodeGroupNode {
        try #require(model.groups.first { $0.kind == kind })
    }

    static func onlyRow(_ model: XcodeModel, _ kind: XcodeResourceKind) throws -> XcodeRow {
        let rows = try group(model, kind).rows
        #expect(rows.count == 1)
        return try #require(rows.first)
    }

    /// `FakeXcode`: le analisi si consumano in ordine (l'ultima resta); l'esecuzione attende
    /// `execution`, oppure risponde subito, oppure resta sospesa fino all'annullamento (al massimo
    /// 5 secondi, poi `observedCancellation` registra se è arrivato).
    final class FakeXcode: XcodeCleanupServing {
        private enum Behavior {
            case waitForGate
            case immediate(XcodeCleanResult)
            case untilCancelled(XcodeCleanResult)
        }

        private struct State {
            var snapshots: [XcodeSnapshot]
            var analysisFailure: (any Error)?
            var behavior = Behavior.waitForGate
            var executeCount = 0
            var receivedJournal: [Bool] = []
            var observedCancellation: [Bool] = []
        }

        let execution = Gate<XcodeCleanResult>()
        let executionStarted = Gate<Void>()
        private let state: Mutex<State>

        init(_ snapshots: XcodeSnapshot...) {
            state = Mutex(State(snapshots: snapshots))
        }

        var executeCount: Int { state.withLock { $0.executeCount } }
        var receivedJournal: [Bool] { state.withLock { $0.receivedJournal } }
        var observedCancellation: [Bool] { state.withLock { $0.observedCancellation } }

        func respondImmediately(with result: XcodeCleanResult) { state.withLock { $0.behavior = .immediate(result) } }
        func returnWhenCancelled(_ result: XcodeCleanResult) { state.withLock { $0.behavior = .untilCancelled(result) } }
        func failAnalysis(with error: any Error) { state.withLock { $0.analysisFailure = error } }

        func analyze() async throws -> XcodeSnapshot {
            try state.withLock { state in
                if let failure = state.analysisFailure { throw failure }
                return state.snapshots.count > 1 ? state.snapshots.removeFirst() : state.snapshots.first ?? .empty
            }
        }

        func execute(
            _ plan: XcodeConfirmedPlan,
            progress: (@Sendable (CleanProgress) -> Void)?,
            journal: (any DeletionRecording)?
        ) async -> XcodeCleanResult {
            let behavior = state.withLock { state -> Behavior in
                state.executeCount += 1
                state.receivedJournal.append(journal != nil)
                return state.behavior
            }
            executionStarted.open()
            switch behavior {
            case .waitForGate:
                return await execution.wait()
            case .immediate(let result):
                return result
            case .untilCancelled(let result):
                try? await Task.sleep(for: .seconds(5))
                let cancelled = Task.isCancelled
                state.withLock { $0.observedCancellation.append(cancelled) }
                return result
            }
        }
    }

    /// `FakeNavigation`: conta ogni cambio di pagina, come `NavigationCount` del C#.
    final class FakeNavigation: NavigationSpy, XcodeNavigating {
        var navigationCount: Int { events.filter { $0 != "refreshTotal" }.count }

        func showXcode() {
            record("xcode")
        }

        func showXcodeReport(_ report: XcodeReportModel) {
            record("xcodeReport")
        }
    }
}
```

`Tests/CleanerFeaturesTests/Xcode/XcodeReportViewModelTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

@MainActor
struct XcodeReportViewModelTests {
    private typealias Fixture = XcodeViewModelTests

    private static func partialResult() -> XcodeCleanResult {
        XcodeCleanResult(
            historyReport: makeReport(),
            items: [XcodeItemResult(candidate: Fixture.candidate("device", .device), outcome: .skipped, reason: "annullata", verifiedEstimatedBytes: nil)],
            freeBytesBefore: 100, freeBytesAfter: 110, warnings: [])
    }

    private static func create(
        _ result: XcodeCleanResult,
        history: FakeHistory = FakeHistory(),
        log: FakeSessionLog = FakeSessionLog(),
        navigation: Fixture.FakeNavigation = Fixture.FakeNavigation()
    ) -> XcodeReportModel {
        XcodeReportModel(history: history, sessionLog: log, navigation: navigation, result: result, journal: nil)
    }

    @Test func cancelledPartialReportIsSavedOnce() async {
        let history = FakeHistory()
        let log = FakeSessionLog()
        let model = Self.create(Self.partialResult(), history: history, log: log)

        await model.persistence?.value
        await model.persist()

        #expect(history.saves == 1)
        #expect(log.writes == 1)
        #expect(model.items.count == 1)
    }

    @Test func unknownSizeUsesUnavailableLabel() async {
        var runtime = Fixture.candidate("runtime", .runtime)
        runtime.sizeBytes = nil
        let item = XcodeItemResult(candidate: runtime, outcome: .deleted, reason: "verified", verifiedEstimatedBytes: nil)
        let model = Self.create(XcodeCleanResult(historyReport: makeReport(), items: [item], freeBytesBefore: nil, freeBytesAfter: nil, warnings: []))

        await model.persistence?.value

        #expect(model.items.map(\.sizeText) == ["non disponibile"])
    }

    @Test func persistenceFailureShowsReportAndError() async {
        let history = FakeHistory()
        history.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let model = Self.create(Self.partialResult(), history: history)

        await model.persistence?.value
        await model.persist()

        #expect(model.historyWarning.contains("storico"))
        #expect(model.hasHistoryWarning)
        #expect(model.items.count == 1)
        #expect(history.saves == 1)
    }

    // Solo Swift: testi del resoconto, messaggi per ogni punto di arresto, navigazione.

    @Test func textsDescribeOutcomesAndFreeSpace() {
        let items = [
            XcodeItemResult(candidate: Fixture.candidate("a", .device), outcome: .deleted, reason: "verificata", verifiedEstimatedBytes: 2048),
            XcodeItemResult(candidate: Fixture.candidate("b", .device), outcome: .skipped, reason: "annullata", verifiedEstimatedBytes: nil),
            XcodeItemResult(candidate: Fixture.candidate("c", .device), outcome: .failed, reason: "errore", verifiedEstimatedBytes: nil),
            XcodeItemResult(candidate: Fixture.candidate("d", .device), outcome: .uncertain, reason: "dubbio", verifiedEstimatedBytes: nil),
        ]
        let grew = Self.create(XcodeCleanResult(
            historyReport: makeReport(bytesFreed: 1_234_567, itemsDeleted: 1), items: items,
            freeBytesBefore: 1024, freeBytesAfter: 3072, warnings: ["uno", "due"]))
        let shrank = Self.create(XcodeCleanResult(
            historyReport: makeReport(), items: [], freeBytesBefore: 3072, freeBytesAfter: 1024, warnings: []))

        #expect(grew.freedText == "1.234.567 byte stimati conteggiati nella cronologia")
        #expect(grew.summaryText == "1 eliminate · 1 saltate · 1 non riuscite · 1 incerte")
        #expect(grew.items.map(\.outcomeText) == ["Eliminata", "Saltata", "Non riuscita", "Esito incerto"])
        #expect(grew.items.map(\.sizeText) == ["2 KB", "non disponibile", "non disponibile", "non disponibile"])
        #expect(grew.items.first?.detail == "verificata")
        #expect(grew.freeSpaceText == "Spazio libero rilevato: +2 KB (1 KB → 3 KB). Variazione separata dalle stime eliminate.")
        #expect(grew.warningsText == "uno\ndue")
        #expect(grew.hasWarnings)
        #expect(shrank.freeSpaceText == "Spazio libero rilevato: 3 KB → 1 KB. La variazione può dipendere da altre attività.")
        #expect(!shrank.hasWarnings)
        #expect(Self.create(Self.partialResult()).freeSpaceText.hasPrefix("Spazio libero rilevato: +"))
        #expect(Self.create(XcodeCleanResult(historyReport: makeReport(), items: [], freeBytesBefore: nil, freeBytesAfter: 1, warnings: [])).freeSpaceText
            == "Spazio libero prima o dopo: non disponibile.")
    }

    @Test func eachFailurePointHasItsOwnMessage() async {
        let logFails = FakeSessionLog()
        logFails.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let afterLog = Self.create(Self.partialResult(), log: logFails)
        await afterLog.persistence?.value
        #expect(afterLog.historyWarning == "Cronologia salvata, ma il log di sessione non è stato aggiornato: disco pieno")

        let navigation = Fixture.FakeNavigation()
        navigation.refreshFailure = UnexpectedTestError(description: "contatore illeggibile")
        let afterRefresh = Self.create(Self.partialResult(), navigation: navigation)
        await afterRefresh.persistence?.value
        #expect(afterRefresh.historyWarning == "Cronologia e log salvati, ma il contatore cumulativo non è stato aggiornato: contatore illeggibile")

        let historyFails = FakeHistory()
        historyFails.failSaves(with: UnexpectedTestError(description: "database bloccato"))
        let beforeHistory = Self.create(Self.partialResult(), history: historyFails)
        await beforeHistory.persistence?.value
        #expect(beforeHistory.historyWarning == "Pulizia completata, ma il report non è stato salvato nello storico: database bloccato")
    }

    @Test func journalSurvivesAFailedSessionLog() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let log = FakeSessionLog(journalDirectory: directory.path)
        log.failWrites(with: UnexpectedTestError(description: "disco pieno"))
        let journal = try #require(log.openJournal(startedAt: Fixture.clock.now))
        let model = XcodeReportModel(
            history: FakeHistory(), sessionLog: log, navigation: Fixture.FakeNavigation(), result: Self.partialResult(), journal: journal)

        await model.persistence?.value

        #expect(log.discarded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: journal.path))
    }

    @Test func analyzeAgainAndCloseNavigate() async {
        let navigation = Fixture.FakeNavigation()
        let model = Self.create(Self.partialResult(), navigation: navigation)
        await model.persistence?.value

        model.analyzeAgain()
        model.close()

        #expect(navigation.events == ["refreshTotal", "xcode", "startOver"])
    }
}
```

`Tests/CleanerFeaturesTests/Xcode/XcodeViewLayoutTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Le prove di `XcodeViewLayoutTests.cs` ridotte a ciò che il modello garantisce: i titoli dei
/// gruppi, il testo dell'anteprima, le anteprime grandi e l'identità delle righe del resoconto.
/// Che pulsanti e controlli restino nel viewport è della vista (piano 4b, spec §9.4).
@MainActor
struct XcodeViewLayoutTests {
    private typealias Fixture = XcodeViewModelTests

    @Test func nonEmptyPageRendersFourGroupsAndFinalConfirmationLabels() async throws {
        let model = Fixture.create(Fixture.FakeXcode(Fixture.snapshot(
            Fixture.candidate("derived", .derivedData), Fixture.candidate("support", .deviceSupport),
            Fixture.candidate("device", .device), Fixture.candidate("runtime", .runtime))))
        await model.initialLoad?.value
        try Fixture.onlyRow(model, .device).isSelected = true

        #expect(model.groups.map(\.title) == ["DerivedData", "Device Support", "Dispositivi simulati", "Runtime iOS, watchOS, tvOS e visionOS"])

        model.preview()

        #expect(model.previewSummaryText == "Risorse selezionate: 1")
        #expect(model.previewEstimateText == "Stima nota: 100 B")
    }

    @Test func largeConfirmationKeepsDestructiveAndBackControlsInViewport() async throws {
        let candidates = (0..<100).map { Fixture.candidate(String(format: "device-%03d", $0), .device) }
        let model = Fixture.create(Fixture.FakeXcode(XcodeSnapshot(candidates: candidates, warnings: [])))
        await model.initialLoad?.value
        for row in try Fixture.group(model, .device).rows { row.isSelected = true }

        model.preview()

        #expect(model.confirmation?.selectedCandidates.count == 100)
        #expect(model.canConfirmDelete)
    }

    @Test func largeRetainedDependencyListKeepsFinalControlsInViewport() async throws {
        let names = (0..<100).map { String(format: "dependent-%03d", $0) }
        let candidates = [Fixture.candidate("runtime", .runtime, dependencies: names)] + names.map { Fixture.candidate($0, .device) }
        let model = Fixture.create(Fixture.FakeXcode(XcodeSnapshot(candidates: candidates, warnings: [])))
        await model.initialLoad?.value
        try Fixture.onlyRow(model, .runtime).isSelected = true

        model.preview()

        #expect(model.confirmation?.retainedDependentDevices.count == 100)
        #expect(!model.canConfirmDelete)
    }

    @Test func reportRowsRenderResourceIdentity() async {
        let uuid = "11111111-1111-4111-8111-111111111111"
        let candidate = XcodeCandidate(key: "device:" + uuid, kind: .device, name: "iPhone 16", cliId: uuid)
        let result = XcodeCleanResult(
            historyReport: makeReport(),
            items: [XcodeItemResult(candidate: candidate, outcome: .deleted, reason: "verified", verifiedEstimatedBytes: 100)],
            freeBytesBefore: 100, freeBytesAfter: 120, warnings: [])
        let model = XcodeReportModel(
            history: FakeHistory(), sessionLog: FakeSessionLog(), navigation: Fixture.FakeNavigation(), result: result, journal: nil)
        await model.persistence?.value

        #expect(model.items.map(\.identity) == [uuid])
        #expect(model.items.map(\.name) == ["iPhone 16"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find type 'XcodeModel' in scope`, `cannot find type 'XcodeRow' in scope`, `cannot find type 'XcodeGroupNode' in scope` e `cannot find 'XcodeReportModel' in scope` (può comparire anche `XcodeNavigating`).

- [ ] **Step 3: Implementare il resoconto Xcode**

`Sources/CleanerFeatures/Xcode/XcodeReportModel.swift`:

```swift
import CleanerCore
import Observation

/// Le destinazioni della sezione Xcode (`IXcodeNavigation` del C#).
@MainActor
public protocol XcodeNavigating: Navigating {
    func showXcode()
    func showXcodeReport(_ report: XcodeReportModel)
}

/// Una riga del resoconto Xcode.
public struct XcodeResultRow: Identifiable, Sendable {
    public let id: Int
    public let item: XcodeItemResult

    public var name: String { item.candidate.name }
    public var identity: String { item.candidate.path ?? item.candidate.cliId ?? item.candidate.key }
    public var detail: String { item.reason }

    public var outcomeText: String {
        switch item.outcome {
        case .deleted: String(localized: "Eliminata", bundle: .module)
        case .skipped: String(localized: "Saltata", bundle: .module)
        case .failed: String(localized: "Non riuscita", bundle: .module)
        case .uncertain: String(localized: "Esito incerto", bundle: .module)
        }
    }

    public var sizeText: String {
        item.verifiedEstimatedBytes.map(Formatting.bytes) ?? String(localized: "non disponibile", bundle: .module)
    }
}

/// Porting di `XcodeReportViewModel`: il resoconto, salvato una sola volta nello storico.
@MainActor
@Observable
public final class XcodeReportModel {
    @ObservationIgnored private let history: any HistoryStoring
    @ObservationIgnored private let sessionLog: any SessionLogWriting
    @ObservationIgnored private weak var navigation: (any XcodeNavigating)?
    @ObservationIgnored private let result: XcodeCleanResult

    public let items: [XcodeResultRow]
    public let freedText: String
    public let summaryText: String
    public let freeSpaceText: String
    public let warningsText: String
    public private(set) var historyWarning = ""

    /// Il salvataggio parte alla creazione e avviene una volta sola: `persist()` lo attende soltanto.
    @ObservationIgnored public private(set) var persistence: Task<Void, Never>?

    public init(
        history: any HistoryStoring,
        sessionLog: any SessionLogWriting,
        navigation: (any XcodeNavigating)?,
        result: XcodeCleanResult,
        journal: PendingJournal?
    ) {
        self.history = history
        self.sessionLog = sessionLog
        self.navigation = navigation
        self.result = result

        items = result.items.enumerated().map { XcodeResultRow(id: $0.offset, item: $0.element) }
        let report = result.historyReport
        freedText = String(localized: "\(Formatting.integer(report.bytesFreed)) byte stimati conteggiati nella cronologia", bundle: .module)

        func count(_ outcome: XcodeItemOutcome) -> String {
            Formatting.integer(result.items.filter { $0.outcome == outcome }.count)
        }
        summaryText = String(
            localized: "\(Formatting.integer(report.itemsDeleted)) eliminate · \(count(.skipped)) saltate · \(count(.failed)) non riuscite · \(count(.uncertain)) incerte",
            bundle: .module)

        if let before = result.freeBytesBefore, let after = result.freeBytesAfter {
            freeSpaceText = after >= before
                ? String(
                    localized: "Spazio libero rilevato: +\(Formatting.bytes(SafeSum.difference(after, before))) (\(Formatting.bytes(before)) → \(Formatting.bytes(after))). Variazione separata dalle stime eliminate.",
                    bundle: .module)
                : String(
                    localized: "Spazio libero rilevato: \(Formatting.bytes(before)) → \(Formatting.bytes(after)). La variazione può dipendere da altre attività.",
                    bundle: .module)
        } else {
            freeSpaceText = String(localized: "Spazio libero prima o dopo: non disponibile.", bundle: .module)
        }

        warningsText = result.warnings.joined(separator: "\n")
        persistence = Task { await self.persistOnce(journal) }
    }

    public var hasWarnings: Bool { !warningsText.isEmpty }
    public var hasHistoryWarning: Bool { !historyWarning.isEmpty }

    public func persist() async {
        await persistence?.value
    }

    public func analyzeAgain() {
        navigation?.showXcode()
    }

    public func close() {
        navigation?.startOver()
    }

    /// Storico, poi log di sessione, poi contatore: il messaggio dice fin dove si è arrivati. Il
    /// diario si scarta solo dopo il log di sessione (spec §8.2).
    private func persistOnce(_ journal: PendingJournal?) async {
        var historySaved = false
        var logSaved = false
        do {
            let sessionId = try await history.save(result.historyReport)
            historySaved = true
            try await sessionLog.write(sessionId: sessionId, report: result.historyReport)
            logSaved = true
            if let journal {
                sessionLog.discard(journal)
            }
            try await navigation?.refreshTotal()
        } catch {
            let reason = FeatureText.message(error)
            historyWarning = switch (historySaved, logSaved) {
            case (true, true):
                String(localized: "Cronologia e log salvati, ma il contatore cumulativo non è stato aggiornato: \(reason)", bundle: .module)
            case (true, false):
                String(localized: "Cronologia salvata, ma il log di sessione non è stato aggiornato: \(reason)", bundle: .module)
            default:
                String(localized: "Pulizia completata, ma il report non è stato salvato nello storico: \(reason)", bundle: .module)
            }
        }
    }
}
```

- [ ] **Step 4: Implementare la pagina Xcode**

`Sources/CleanerFeatures/Xcode/XcodeModel.swift`:

```swift
import CleanerCore
import Observation

/// Una risorsa Xcode selezionabile. L'identità della riga è l'oggetto, non il candidato: due
/// candidati non si confrontano mai con `==` per decidere (registro del piano 3).
@MainActor
@Observable
public final class XcodeRow: Identifiable {
    public let candidate: XcodeCandidate
    @ObservationIgnored fileprivate var onSelectionChanged: (@MainActor () -> Void)?

    public var isSelected = false {
        didSet {
            if isSelected != oldValue { onSelectionChanged?() }
        }
    }

    init(candidate: XcodeCandidate) {
        self.candidate = candidate
    }

    public var name: String { candidate.name }
    public var sizeText: String { candidate.sizeBytes.map(Formatting.bytes) ?? String(localized: "non disponibile", bundle: .module) }
    public var identityText: String { candidate.path ?? candidate.cliId ?? candidate.key }
    public var stateText: String { candidate.blockReason ?? candidate.state ?? "" }
    public var hasState: Bool { !stateText.isEmpty }
    public var canSelect: Bool { candidate.canSelect }
}

@MainActor
@Observable
public final class XcodeGroupNode: Identifiable {
    public let kind: XcodeResourceKind
    public let rows: [XcodeRow]
    public let warnings: [String]
    @ObservationIgnored fileprivate var onSelectionChanged: (@MainActor () -> Void)?
    @ObservationIgnored private var syncing = false

    /// Solo le cache (DerivedData, Device Support) si selezionano in gruppo: simulatori e runtime
    /// si scelgono uno per uno.
    public var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            if !syncing && showGroupCheckBox {
                syncing = true
                for row in rows where row.canSelect {
                    row.isSelected = isSelected
                }
                syncing = false
            }
            onSelectionChanged?()
        }
    }

    public init(kind: XcodeResourceKind, candidates: [XcodeCandidate], warnings: [String]) {
        self.kind = kind
        rows = candidates.map(XcodeRow.init)
        self.warnings = warnings
        for row in rows {
            row.onSelectionChanged = { [weak self] in self?.rowChanged() }
        }
    }

    public var title: String {
        switch kind {
        case .derivedData: String(localized: "DerivedData", bundle: .module)
        case .deviceSupport: String(localized: "Device Support", bundle: .module)
        case .device: String(localized: "Dispositivi simulati", bundle: .module)
        case .runtime: String(localized: "Runtime iOS, watchOS, tvOS e visionOS", bundle: .module)
        }
    }

    public var isExpanded: Bool { kind == .derivedData || kind == .deviceSupport }
    public var showGroupCheckBox: Bool { kind == .derivedData || kind == .deviceSupport }

    /// Le dimensioni sono stime: quelle ignote non diventano «0 B» e si contano a parte.
    public var summary: String {
        let known = rows.compactMap(\.candidate.sizeBytes)
        let unknownCount = rows.count - known.count
        var size = known.isEmpty
            ? String(localized: "dimensioni non disponibili", bundle: .module)
            : String(localized: "\(Formatting.bytes(SafeSum.total(known))) stimati noti", bundle: .module)
        if !known.isEmpty && unknownCount > 0 {
            size += unknownCount == 1
                ? String(localized: " · 1 dimensione non disponibile", bundle: .module)
                : String(localized: " · \(String(unknownCount)) dimensioni non disponibili", bundle: .module)
        }
        return rows.isEmpty
            ? String(localized: "0 voci", bundle: .module)
            : String(localized: "\(Formatting.integer(rows.count)) voci · \(size)", bundle: .module)
    }

    private func rowChanged() {
        onSelectionChanged?()
        guard !syncing && showGroupCheckBox else { return }
        let selectable = rows.filter(\.canSelect)
        syncing = true
        isSelected = !selectable.isEmpty && selectable.allSatisfy(\.isSelected)
        syncing = false
    }
}

/// Porting di `XcodeViewModel`: analisi, selezione, anteprima obbligatoria, conferma finale ed
/// esecuzione. Mentre elimina, la finestra principale blocca la navigazione (`isDeleting`).
@MainActor
@Observable
public final class XcodeModel {
    @ObservationIgnored private let xcode: any XcodeCleanupServing
    @ObservationIgnored private let history: any HistoryStoring
    @ObservationIgnored private let sessionLog: any SessionLogWriting
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private weak var navigation: (any XcodeNavigating)?
    @ObservationIgnored private var deleteTask: Task<XcodeCleanResult, Never>?
    @ObservationIgnored private var snapshot: XcodeSnapshot?
    @ObservationIgnored private var executionStarted = false

    public private(set) var isLoading = true
    public private(set) var isDeleting = false
    public private(set) var errorText = ""
    public private(set) var warningText = ""
    public private(set) var progressText = ""
    public var acknowledgeDependencies = false
    public private(set) var confirmation: XcodeConfirmation?
    public private(set) var currentReport: XcodeReportModel?
    public private(set) var groups: [XcodeGroupNode] = []

    @ObservationIgnored public private(set) var initialLoad: Task<Void, Never>?

    public init(
        xcode: any XcodeCleanupServing,
        history: any HistoryStoring,
        sessionLog: any SessionLogWriting,
        clock: any WallClock,
        navigation: (any XcodeNavigating)?
    ) {
        self.xcode = xcode
        self.history = history
        self.sessionLog = sessionLog
        self.clock = clock
        self.navigation = navigation
        initialLoad = Task { await self.load() }
    }

    public var hasError: Bool { !errorText.isEmpty }
    public var hasWarnings: Bool { !warningText.isEmpty }
    public var hasConfirmation: Bool { confirmation != nil }
    public var hasRetainedDependencies: Bool { !(confirmation?.retainedDependentDevices.isEmpty ?? true) }
    public var hasSelectedDevices: Bool { confirmation?.selectedCandidates.contains { $0.kind == .device } ?? false }
    public var hasSelectedRuntimes: Bool { confirmation?.selectedCandidates.contains { $0.kind == .runtime } ?? false }

    public var previewSummaryText: String {
        guard let confirmation else { return "" }
        return String(localized: "Risorse selezionate: \(String(confirmation.selectedCandidates.count))", bundle: .module)
    }

    public var previewEstimateText: String {
        guard let confirmation else { return "" }
        let unknown = confirmation.unknownSizeCount > 0
            ? String(localized: " · \(String(confirmation.unknownSizeCount)) dimensioni non disponibili", bundle: .module)
            : ""
        return String(localized: "Stima nota: \(Formatting.bytes(confirmation.estimatedBytes))", bundle: .module) + unknown
    }

    public var totalText: String {
        let selected = selectedRows
        let known = SafeSum.total(selected.compactMap(\.candidate.sizeBytes))
        let unknown = selected.filter { $0.candidate.sizeBytes == nil }.count
        let suffix = unknown > 0 ? String(localized: " · \(String(unknown)) non disponibili", bundle: .module) : ""
        return String(localized: "\(Formatting.bytes(known)) stimati · \(String(selectedKeys().count)) selezionate", bundle: .module) + suffix
    }

    public var canRetry: Bool { !isLoading && !isDeleting }
    public var canPreview: Bool { !isDeleting && !selectedKeys().isEmpty }
    public var canNavigate: Bool { !isDeleting }
    public var canCancelDelete: Bool { isDeleting }

    public var canConfirmDelete: Bool {
        guard !isDeleting, !executionStarted, let confirmation, !confirmation.selectedCandidates.isEmpty else { return false }
        return confirmation.retainedDependentDevices.isEmpty || acknowledgeDependencies
    }

    public func retry() async {
        await load()
    }

    /// L'anteprima passa sempre da `XcodeSelection.preview` sullo snapshot dell'analisi: con lo
    /// stato di Xcode ignoto l'analisi restituisce candidati non classificati (registro del piano 3).
    public func preview() {
        guard let snapshot, !isDeleting else { return }
        do {
            confirmation = try XcodeSelection.preview(snapshot, selectedKeys: selectedKeys())
            acknowledgeDependencies = false
        } catch {
            errorText = FeatureText.message(error)
        }
    }

    public func confirmDelete() async {
        guard !executionStarted, let confirmation else { return }
        executionStarted = true
        isDeleting = true
        errorText = ""
        var executionReturnedReport = false

        do {
            let plan = try XcodeSelection.confirm(confirmation, acknowledgeDependencies: acknowledgeDependencies)

            // Il diario si apre prima dell'esecuzione e passa al resoconto, che lo scarta solo dopo
            // aver scritto il log di sessione (spec §8.2).
            let journal = sessionLog.openJournal(startedAt: clock.now)
            let relay = ProgressRelay<CleanProgress> { [weak self] progress in
                self?.progressText = "\(Formatting.integer(progress.itemsDone)) / \(Formatting.integer(progress.itemsTotal)) · \(progress.currentPath)"
            }
            let xcode = xcode
            let report = relay.report
            let task = Task { await xcode.execute(plan, progress: report, journal: journal) }
            deleteTask = task

            // L'esecutore non lancia: anche un'esecuzione annullata restituisce il resoconto
            // parziale, che va salvato.
            let result = await task.value
            await relay.finish()
            executionReturnedReport = true

            let reportModel = XcodeReportModel(
                history: history, sessionLog: sessionLog, navigation: navigation, result: result, journal: journal)
            currentReport = reportModel
            navigation?.showXcodeReport(reportModel)
        } catch {
            errorText = String(localized: "Pulizia Xcode non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        deleteTask = nil
        executionStarted = executionReturnedReport
        isDeleting = false
    }

    public func cancelDelete() {
        deleteTask?.cancel()
    }

    public func backToSelection() {
        guard !isDeleting else { return }
        confirmation = nil
        acknowledgeDependencies = false
    }

    public func close() {
        guard !isDeleting else { return }
        navigation?.startOver()
    }

    private var selectedRows: [XcodeRow] {
        groups.flatMap(\.rows).filter { $0.isSelected && $0.canSelect }
    }

    /// Le chiavi selezionate. Un `Set<String>` unisce due chiavi canonicamente equivalenti (NFC e
    /// NFD), dove l'`HashSet` ordinale del C# le teneva distinte: si seleziona al più di meno, il
    /// lato sicuro; `XcodeSelection` poi cerca ogni chiave con confronto ordinale.
    func selectedKeys() -> Set<String> {
        Set(selectedRows.map(\.candidate.key))
    }

    private func selectionChanged() {
        confirmation = nil
        acknowledgeDependencies = false
    }

    private func load() async {
        isLoading = true
        errorText = ""
        warningText = ""
        confirmation = nil
        acknowledgeDependencies = false
        groups = []
        snapshot = nil
        if !isDeleting {
            executionStarted = false
        }

        do {
            let snapshot = try await xcode.analyze()
            self.snapshot = snapshot
            var loaded: [XcodeGroupNode] = []
            for kind in [XcodeResourceKind.derivedData, .deviceSupport, .device, .runtime] {
                let group = XcodeGroupNode(
                    kind: kind,
                    candidates: snapshot.candidates.filter { $0.kind == kind },
                    warnings: snapshot.warnings.filter { $0.resourceGroup == kind }.map(\.message))
                group.onSelectionChanged = { [weak self] in self?.selectionChanged() }
                loaded.append(group)
            }
            groups = loaded
            warningText = FeatureText.distinct(snapshot.warnings.map(\.message)).joined(separator: "\n")
        } catch {
            errorText = String(localized: "Analisi Xcode non riuscita: \(FeatureText.message(error))", bundle: .module)
        }

        isLoading = false
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeViewModelTests|XcodeReportViewModelTests|XcodeViewLayoutTests"`
Expected: `Test run with 26 tests in 3 suites passed` (15 di `XcodeViewModelTests`, 7 di `XcodeReportViewModelTests`, 4 di `XcodeViewLayoutTests`), nessun warning. Suite di `CleanerFeaturesTests`: 104.

- [ ] **Step 6: Registro di parità e commit**

Sostituire le righe `Xcode/XcodeReportViewModelTests.cs`, `Xcode/XcodeViewLayoutTests.cs` e `Xcode/XcodeViewModelTests.cs` con:

```markdown
| Xcode/XcodeReportViewModelTests.cs | 3 | Xcode/XcodeReportViewModelTests.swift | 7 | 4a | 3 portati + 4 solo-Swift (`textsDescribeOutcomesAndFreeSpace`, `eachFailurePointHasItsOwnMessage`, `journalSurvivesAFailedSessionLog`, `analyzeAgainAndCloseNavigate`); `PersistenceTask`/`PersistCommand` → `persistence`/`persist()` |
| Xcode/XcodeViewLayoutTests.cs | 4 | Xcode/XcodeViewLayoutTests.swift | 4 | 4a | ridotte a ciò che garantisce il modello (titoli dei gruppi, testo dell'anteprima, anteprime di 100 risorse, identità delle righe del resoconto); controlli nel viewport → piano 4b |
| Xcode/XcodeViewModelTests.cs | 10 | Xcode/XcodeViewModelTests.swift | 15 | 4a | 10 portati + 5 solo-Swift (`journalIsOpenedBeforeExecutionAndDiscardedByTheReport`, `warningsAreShownOnceAndPerGroup`, `totalCountsKnownAndUnknownSizesWithoutOverflow`, `changingTheSelectionDiscardsThePreview`, `analysisFailureIsShown`); `retryAfterExecutionFailureCanConfirmAgain` provoca il primo fallimento con la conferma senza presa d'atto (l'esecutore Swift non lancia); `cancelDeleteReturnsAndPersistsPartialReportOnce` verifica anche che l'annullamento arrivi all'esecutore; UUID dei candidati da FNV-1a invece che da MD5 |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Diario delle rimozioni Xcode nella pagina | assente | `XcodeModel` apre il `PendingJournal` prima di `execute`; `XcodeReportModel` lo scarta dopo il log di sessione | voluta (spec §8.2) |
| «Operazione interrotta prima di poter produrre il report.» (pagina Xcode) | ramo `OperationCanceledException` di `ConfirmDeleteAsync` | non portato: `execute` non lancia e un annullamento restituisce il resoconto parziale | per costruzione |
| Chiavi Xcode selezionate | `HashSet<string>(StringComparer.Ordinal)` | `Set<String>`: due chiavi canonicamente equivalenti diventano una | accettata (lato sicuro: si seleziona di meno; `XcodeSelection` cerca per confronto ordinale) |
```

Tabella «Candidati a miglioramento», aggiungere in fondo:

```markdown
| «1 voci» nel riepilogo di un gruppo Xcode | `XcodeGroupNode.Summary` scrive sempre «voci» (testo C#, replicato) | concordanza «1 voce» come negli altri riepiloghi |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Xcode/XcodeReportModel.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Xcode/XcodeModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Xcode/XcodeViewModelTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Xcode/XcodeReportViewModelTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Xcode/XcodeViewLayoutTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the Xcode page and report with the cleanup journal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: finestra principale, sidebar e blocco della navigazione

La pagina corrente con il suo modello, la voce della sidebar ricavata dalla pagina, il contatore «Spazio liberato», lo sheet delle Impostazioni come stato e il blocco della navigazione mentre Xcode elimina (spec §6.3). `MainModel` implementa tutti i protocolli di navigazione dei task precedenti ed è l'unico a costruire le pagine.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/Page.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/SidebarSectionTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/NavigationLockTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsOpeningTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`
- Reference: `src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`, `SidebarSection.cs`; `tests/MjmCleaner.App.Tests/SidebarSectionTests.cs`, `NavigationLockTests.cs`, `SettingsOpeningTests.cs`

**Interfaces:**
- Consumes: tutti i modelli dei Task 3–10 e i loro inizializzatori; `AppEnvironment`, `FolderPicking`, `AppearanceApplying` (Task 2); `CleanupNavigating` (Task 5), `DockerNavigating` (Task 9), `XcodeNavigating` (Task 10); `Formatting` (Task 1); doppi del Task 2, `FakeAppearance`/`FakePicker` (Task 3), `XcodeViewModelTests.FakeXcode` e le sue fixture (Task 10).
- Produces:
  - `public enum SidebarSection: Sendable, Hashable, CaseIterable` — `cleanup`, `docker`, `xcode`, `history`
  - `public enum PageKind: Sendable, Hashable, CaseIterable` — `choose`, `scan`, `confirm`, `done`, `docker`, `dockerReport`, `xcode`, `xcodeReport`, `history`; `section`, `isWizardStep`
  - `@MainActor public enum Page` — un caso per pagina con il suo modello; `kind: PageKind`
  - `@MainActor @Observable public final class MainModel: CleanupNavigating, DockerNavigating, XcodeNavigating` — `init(environment: AppEnvironment, appearance: any AppearanceApplying, folders: any FolderPicking)`; `page`, `totalFreedAmount`, `settings: SettingsModel?`, `section`, `isXcodeBusy`, `canNavigateGlobally`, `canShowSettings`; `select(_ section: SidebarSection)`, `showCleanup()`, `showHistory()`, `showSettings()`, `startOver()`, `refreshTotal() async throws`, `showScan(_:)`, `showConfirm(_:results:)`, `showDone(_:journal:)`, `showDocker()`, `showDockerReport(_:diskBefore:diskAfter:)`, `showXcode()`, `showXcodeReport(_:)`

Note di porting:
- **Blocco.** Il C# disabilitava i comandi della sidebar e di ⌘, con `CanExecute`. Qui `select`, `showCleanup`, `showDocker`, `showXcode`, `showHistory` e `showSettings` rifiutano il cambio quando `isXcodeBusy`: il blocco è del modello, come chiede la spec §6.3, e la vista del piano 4b disabilita in più i controlli con `canNavigateGlobally`/`canShowSettings`. La navigazione chiesta dalla pagina Xcode stessa (il resoconto, a eliminazione finita) passa da `showXcodeReport`, che non è bloccato: in C# `GoTo(CurrentReport)` avveniva con `IsDeleting` ancora vero.
- **Impostazioni** (decisione dell'utente): `showSettings()` crea `SettingsModel` con `onSaved` = `startOver()` e `onClose` = azzeramento di `settings`. Un secondo `showSettings()` a sheet aperto non ne crea un altro, come l'`AsyncRelayCommand` del C#.
- **Test con doppi.** In C# `NavigationLockTests` usava `TestHome` (servizi veri) solo perché `MainWindowViewModel` richiedeva `AppServices`; qui bastano i doppi di `makeEnvironment`. La pagina Xcode si apre con `showXcode()` invece di `GoTo(new XcodeViewModel(…))`.
- **Sezione della sidebar.** In C# si ricavava dal tipo del ViewModel (`SidebarSections.For(object)`, testato con istanze non inizializzate). Qui si ricava da `PageKind`, quindi i test non costruiscono modelli.
- **Avvio.** Il passo 1 nasce nell'`init` e riceve la navigazione subito dopo (`first.navigation = self`): `self` non si può passare prima che tutte le proprietà siano inizializzate.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerFeaturesTests/SidebarSectionTests.swift`:

```swift
import Testing
@testable import CleanerFeatures

/// In C# la sezione si ricavava dal tipo del ViewModel (`SidebarSections.For(object)`); qui dal
/// tipo di pagina, senza costruire i modelli.
struct SidebarSectionTests {
    @Test func wizardPagesBelongToCleanup() {
        #expect([PageKind.choose, .scan, .confirm, .done].map(\.section) == [.cleanup, .cleanup, .cleanup, .cleanup])
    }

    @Test func reportsBelongToTheirTool() {
        #expect(PageKind.docker.section == .docker)
        #expect(PageKind.dockerReport.section == .docker)
        #expect(PageKind.xcode.section == .xcode)
        #expect(PageKind.xcodeReport.section == .xcode)
        #expect(PageKind.history.section == .history)
    }

    @Test func isWizardPageOnlyForTheFourSteps() {
        #expect(PageKind.allCases.filter(\.isWizardStep) == [.choose, .scan, .confirm, .done])
        #expect(!PageKind.docker.isWizardStep)
    }
}
```

`Tests/CleanerFeaturesTests/NavigationLockTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Il blocco della navigazione durante la cancellazione Xcode e il comportamento di «Pulizia» nella
/// sidebar (spec §6.3: il blocco è imposto dal modello, non solo dalla vista).
@MainActor
struct NavigationLockTests {
    private static func main(xcode: any XcodeCleanupServing = IdleXcode()) throws -> MainModel {
        MainModel(environment: try makeEnvironment(xcode: xcode), appearance: FakeAppearance(), folders: FakePicker())
    }

    private static func navigationIsOpen(_ main: MainModel) -> Bool {
        main.canNavigateGlobally && main.canShowSettings
    }

    @Test func sidebarCommandsAreDisabledWhileXcodeDeletesAndReenabledAfterwards() async throws {
        let service = XcodeViewModelTests.FakeXcode(XcodeViewModelTests.snapshot(XcodeViewModelTests.candidate("device", .device)))
        let main = try Self.main(xcode: service)
        main.showXcode()
        guard case .xcode(let xcode) = main.page else {
            Issue.record("La pagina Xcode non si è aperta")
            return
        }
        await xcode.initialLoad?.value
        #expect(Self.navigationIsOpen(main))

        try XcodeViewModelTests.onlyRow(xcode, .device).isSelected = true
        xcode.preview()
        let deleting = Task { await xcode.confirmDelete() }
        await service.executionStarted.wait()

        #expect(xcode.isDeleting)
        #expect(main.isXcodeBusy)
        #expect(!main.canNavigateGlobally)
        #expect(!main.canShowSettings)

        // Ogni richiesta di cambio pagina viene rifiutata: la pagina resta quella che elimina.
        for section in SidebarSection.allCases { main.select(section) }
        main.showSettings()
        #expect(main.page.kind == .xcode)
        #expect(main.section == .xcode)
        #expect(main.settings == nil)

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value

        #expect(!main.isXcodeBusy)
        #expect(main.page.kind == .xcodeReport)
        #expect(Self.navigationIsOpen(main))
    }

    @Test func showCleanupLeavesAWizardPageUntouched() throws {
        let main = try Self.main()
        guard case .choose(let wizardPage) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }

        main.showCleanup()

        // Un ciclo in corso non viene interrotto: stessa istanza, non una nuova pagina del passo 1.
        guard case .choose(let current) = main.page else {
            Issue.record("La pagina è cambiata")
            return
        }
        #expect(current === wizardPage)
    }

    @Test func showCleanupFromHistoryReturnsToStepOne() throws {
        let main = try Self.main()
        main.showHistory()
        #expect(main.page.kind == .history)

        main.showCleanup()

        #expect(main.page.kind == .choose)
    }
}
```

`Tests/CleanerFeaturesTests/SettingsOpeningTests.swift`:

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Le prove di `SettingsOpeningTests.cs` sul collegamento fra comando e sheet. Il clic sul pulsante
/// della sidebar, ⌘, e la voce del menu dell'app sono della vista (piano 4b).
@MainActor
struct SettingsOpeningTests {
    private static func main() throws -> MainModel {
        MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
    }

    @Test func showSettingsCommandOpensTheModalSettingsWindow() throws {
        let main = try Self.main()

        main.showSettings()

        #expect(main.settings != nil)
    }

    @Test func whileTheWindowIsOpenTheCommandIsDisabled() throws {
        let main = try Self.main()
        main.showSettings()
        let opened = try #require(main.settings)

        // Pulsante, ⌘, e voce di menu rispettano `canShowSettings`: finché lo sheet è aperto il comando è disabilitato.
        #expect(!main.canShowSettings)
        main.showSettings()
        #expect(main.settings === opened)

        opened.cancel()
        #expect(main.settings == nil)
        #expect(main.canShowSettings)
    }
}
```

`Tests/CleanerFeaturesTests/MainModelTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

/// Solo Swift: la finestra principale costruisce ogni pagina, aggiorna il contatore e collega lo
/// sheet delle Impostazioni.
@MainActor
struct MainModelTests {
    @Test func startsOnStepOneAndRefreshesTheTotal() async throws {
        let history = FakeHistory()
        history.setTotal(1_288_490_189)
        let main = MainModel(environment: try makeEnvironment(history: history), appearance: FakeAppearance(), folders: FakePicker())

        #expect(main.page.kind == .choose)
        #expect(main.section == .cleanup)
        #expect(main.totalFreedAmount == "—")

        try await main.refreshTotal()

        #expect(main.totalFreedAmount == "1,2 GB")
    }

    @Test func stepOneNavigatesThroughTheMainModel() throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
        guard case .choose(let choose) = main.page else {
            Issue.record("La finestra non parte dal passo 1")
            return
        }

        choose.choices.first?.isSelected = true
        choose.analyze()

        #expect(main.page.kind == .scan)
    }

    @Test func everyDestinationBuildsItsPage() throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())
        let logs = makeCategory("logs")

        main.showScan([logs])
        #expect(main.page.kind == .scan)
        main.showConfirm([logs], results: [])
        #expect(main.page.kind == .confirm)
        main.showDone(makeReport(), journal: nil)
        #expect(main.page.kind == .done)
        main.showDockerReport(
            DockerCleanResult(report: makeReport(), before: .empty, after: nil, daemonLost: false),
            diskBefore: nil, diskAfter: DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil))
        #expect(main.page.kind == .dockerReport)
        #expect(main.section == .docker)

        let report = XcodeReportModel(
            history: FakeHistory(), sessionLog: FakeSessionLog(), navigation: main,
            result: XcodeViewModelTests.result(), journal: nil)
        main.showXcodeReport(report)
        guard case .xcodeReport(let shown) = main.page else {
            Issue.record("Il resoconto Xcode non è la pagina corrente")
            return
        }
        #expect(shown === report)
        #expect(main.section == .xcode)

        main.startOver()
        #expect(main.page.kind == .choose)
    }

    @Test func theDoneStepReceivesTheJournalAndDiscardsItAfterTheLog() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let sessionLog = FakeSessionLog(journalDirectory: directory.path)
        let journal = try #require(sessionLog.openJournal(startedAt: Date(timeIntervalSince1970: 1_790_000_000)))
        let main = MainModel(environment: try makeEnvironment(sessionLog: sessionLog), appearance: FakeAppearance(), folders: FakePicker())

        main.showDone(makeReport(itemsDeleted: 1), journal: journal)
        guard case .done(let done) = main.page else {
            Issue.record("Il passo 4 non è la pagina corrente")
            return
        }
        await done.persistence?.value

        #expect(sessionLog.discarded == [journal.path])
        #expect(sessionLog.events.values == ["open", "write", "discard"])
    }

    @Test func sidebarSelectionCreatesANewPageEachTime() throws {
        let main = MainModel(environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker())

        main.select(.docker)
        guard case .docker(let first) = main.page else {
            Issue.record("Docker non si è aperto")
            return
        }
        main.select(.docker)
        guard case .docker(let second) = main.page else {
            Issue.record("Docker non si è riaperto")
            return
        }
        #expect(first !== second)

        main.select(.history)
        #expect(main.section == .history)
        main.select(.xcode)
        #expect(main.section == .xcode)
        main.select(.cleanup)
        #expect(main.page.kind == .choose)
    }

    @Test func savingSettingsReturnsToStepOneAndCancelKeepsThePage() throws {
        var initial = CleanerSettings()
        initial.appearance = .light
        let store = FakeSettingsStore(initial)
        let appearance = FakeAppearance()
        let main = MainModel(environment: try makeEnvironment(settings: store), appearance: appearance, folders: FakePicker())

        main.showHistory()
        main.showSettings()
        main.settings?.appearance = .dark
        main.settings?.cancel()
        #expect(main.settings == nil)
        #expect(main.page.kind == .history)
        #expect(appearance.applied == [.dark, .light])

        main.showSettings()
        main.settings?.appearance = .dark
        main.settings?.save()
        #expect(main.settings == nil)
        #expect(main.page.kind == .choose)
        #expect(store.current.appearance == .dark)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors`
Expected: la build fallisce con `cannot find type 'MainModel' in scope` e `cannot find 'MainModel' in scope` (può comparire anche `PageKind`).

- [ ] **Step 3: Implementare pagine e sezioni**

`Sources/CleanerFeatures/Shell/Page.swift`:

```swift
/// Le voci della sidebar (spec §6.2): Pulizia · Docker · Xcode · Storico.
public enum SidebarSection: Sendable, Hashable, CaseIterable {
    case cleanup
    case docker
    case xcode
    case history
}

/// Il tipo di pagina, senza il modello: la voce selezionata si ricava da qui, nessuno stato
/// separato da tenere allineato (`SidebarSections` del C#).
public enum PageKind: Sendable, Hashable, CaseIterable {
    case choose
    case scan
    case confirm
    case done
    case docker
    case dockerReport
    case xcode
    case xcodeReport
    case history

    public var section: SidebarSection {
        switch self {
        case .docker, .dockerReport: .docker
        case .xcode, .xcodeReport: .xcode
        case .history: .history
        case .choose, .scan, .confirm, .done: .cleanup
        }
    }

    /// I quattro passi del wizard di pulizia.
    public var isWizardStep: Bool {
        switch self {
        case .choose, .scan, .confirm, .done: true
        default: false
        }
    }
}

/// La pagina mostrata nella finestra principale, con il suo modello (spec §6.3).
@MainActor
public enum Page {
    case choose(ChooseStepModel)
    case scan(ScanStepModel)
    case confirm(ConfirmStepModel)
    case done(DoneStepModel)
    case docker(DockerModel)
    case dockerReport(DockerReportModel)
    case xcode(XcodeModel)
    case xcodeReport(XcodeReportModel)
    case history(HistoryModel)

    public var kind: PageKind {
        switch self {
        case .choose: .choose
        case .scan: .scan
        case .confirm: .confirm
        case .done: .done
        case .docker: .docker
        case .dockerReport: .dockerReport
        case .xcode: .xcode
        case .xcodeReport: .xcodeReport
        case .history: .history
        }
    }
}
```

- [ ] **Step 4: Implementare `MainModel`**

`Sources/CleanerFeatures/Shell/MainModel.swift`:

```swift
import CleanerCore
import Observation

/// Porting di `MainWindowViewModel`: la pagina corrente, la sidebar, il contatore «Spazio
/// liberato» e lo sheet delle Impostazioni. Il blocco della navigazione durante l'eliminazione
/// Xcode è imposto qui, non solo dalla vista con `.disabled`, così che i test lo verifichino
/// (spec §6.3).
@MainActor
@Observable
public final class MainModel: CleanupNavigating, DockerNavigating, XcodeNavigating {
    @ObservationIgnored private let environment: AppEnvironment
    @ObservationIgnored private let appearance: any AppearanceApplying
    @ObservationIgnored private let folders: any FolderPicking

    public private(set) var page: Page
    public private(set) var totalFreedAmount = "—"

    /// Lo sheet delle Impostazioni è presente finché questo valore non è `nil`: l'app lo presenta
    /// con `.sheet(item:)`. Salva e Annulla lo azzerano.
    public private(set) var settings: SettingsModel?

    public init(environment: AppEnvironment, appearance: any AppearanceApplying, folders: any FolderPicking) {
        self.environment = environment
        self.appearance = appearance
        self.folders = folders
        // Il passo 1 riceve la navigazione appena `self` è disponibile.
        let first = ChooseStepModel(environment: environment, navigation: nil)
        page = .choose(first)
        first.navigation = self
    }

    public var section: SidebarSection { page.kind.section }

    public var isXcodeBusy: Bool {
        if case .xcode(let model) = page { model.isDeleting } else { false }
    }

    public var canNavigateGlobally: Bool { !isXcodeBusy }

    /// ⌘, e «Impostazioni…»: disabilitati mentre Xcode elimina e mentre lo sheet è già aperto
    /// (in C# l'`AsyncRelayCommand` non ammetteva esecuzioni concorrenti).
    public var canShowSettings: Bool { canNavigateGlobally && settings == nil }

    // MARK: Sidebar e menu

    /// La voce scelta nella sidebar. Mentre Xcode elimina il cambio viene rifiutato e la voce
    /// selezionata resta quella della pagina corrente.
    public func select(_ section: SidebarSection) {
        switch section {
        case .cleanup: showCleanup()
        case .docker: showDocker()
        case .xcode: showXcode()
        case .history: showHistory()
        }
    }

    /// «Pulizia» non interrompe un ciclo in corso; dalle altre sezioni riparte dal passo 1.
    public func showCleanup() {
        guard canNavigateGlobally else { return }
        if !page.kind.isWizardStep {
            startOver()
        }
    }

    public func showHistory() {
        guard canNavigateGlobally else { return }
        page = .history(HistoryModel(environment: environment, navigation: self))
    }

    public func showSettings() {
        guard canShowSettings else { return }
        settings = SettingsModel(
            store: environment.settings,
            appearance: appearance,
            folders: folders,
            onSaved: { [weak self] in self?.startOver() },
            onClose: { [weak self] in self?.settings = nil })
    }

    // MARK: Navigating

    /// Torna al passo 1 del wizard: all'avvio e ogni volta che un ciclo si conclude o viene annullato.
    public func startOver() {
        page = .choose(ChooseStepModel(environment: environment, navigation: self))
    }

    public func refreshTotal() async throws {
        let total = try await environment.history.totalBytesFreed()
        totalFreedAmount = Formatting.bytes(total)
    }

    // MARK: CleanupNavigating

    public func showScan(_ categories: [CleanupCategory]) {
        page = .scan(ScanStepModel(environment: environment, navigation: self, categories: categories))
    }

    public func showConfirm(_ categories: [CleanupCategory], results: [CategoryScanResult]) {
        page = .confirm(ConfirmStepModel(environment: environment, navigation: self, categories: categories, results: results))
    }

    public func showDone(_ report: CleanReport, journal: PendingJournal?) {
        page = .done(DoneStepModel(environment: environment, navigation: self, report: report, journal: journal))
    }

    // MARK: DockerNavigating

    /// Docker, Xcode e Storico creano una pagina nuova a ogni selezione.
    public func showDocker() {
        guard canNavigateGlobally else { return }
        page = .docker(DockerModel(environment: environment, navigation: self))
    }

    public func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {
        page = .dockerReport(DockerReportModel(
            environment: environment, navigation: self, result: result, diskBefore: diskBefore, diskAfter: diskAfter))
    }

    // MARK: XcodeNavigating

    public func showXcode() {
        guard canNavigateGlobally else { return }
        page = .xcode(XcodeModel(
            xcode: environment.xcode,
            history: environment.history,
            sessionLog: environment.sessionLog,
            clock: environment.clock,
            navigation: self))
    }

    public func showXcodeReport(_ report: XcodeReportModel) {
        page = .xcodeReport(report)
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "SidebarSectionTests|NavigationLockTests|SettingsOpeningTests|MainModelTests"`
Expected: `Test run with 14 tests in 4 suites passed` (3 + 3 + 2 + 6), nessun warning. Suite di `CleanerFeaturesTests`: 118.

- [ ] **Step 6: Registro di parità e commit**

Sostituire le righe `NavigationLockTests.cs`, `SettingsOpeningTests.cs` e `SidebarSectionTests.cs` con:

```markdown
| NavigationLockTests.cs | 3 | NavigationLockTests.swift | 3 | 4a | `MainModel` con i doppi di `makeEnvironment` invece di `TestHome`; la pagina Xcode si apre con `showXcode()`; durante l'eliminazione si prova ogni voce della sidebar e ⌘, e si verifica che la pagina non cambi |
| SettingsOpeningTests.cs | 5 | SettingsOpeningTests.swift | 2 | 4a | 2 portati sullo stato `settings` (`showSettingsCommandOpensTheModalSettingsWindow`, `whileTheWindowIsOpenTheCommandIsDisabled`); `ClickingTheSidebarSettingsButtonOpensTheWindow`, `CommandCommaOpensTheWindow`, `TheApplicationMenuHasTheSettingsItemFromStartup` sono della vista e del menu → piano 4b |
| SidebarSectionTests.cs | 3 | SidebarSectionTests.swift | 3 | 4a | la sezione si ricava da `PageKind` invece che dal tipo di un ViewModel non inizializzato |
```

In fondo alla tabella «Test solo Swift di CleanerFeaturesTests», aggiungere:

```markdown
| MainModelTests.swift | 6 | finestra principale: avvio sul passo 1 e contatore, navigazione del passo 1 tramite `MainModel`, ogni destinazione costruisce la propria pagina, il diario arriva al passo 4 ed è scartato dopo il log, nuova pagina a ogni selezione della sidebar, Salva torna al passo 1 e Annulla lascia la pagina |
```

Tabella «Differenze rispetto al C#», aggiungere in fondo:

```markdown
| Apertura delle Impostazioni | `OpenSettingsWindow` assegnato dalla finestra, `ShowDialog`, `CloseRequested` | stato `MainModel.settings: SettingsModel?` presentato dall'app con `.sheet(item:)`; Salva e Annulla lo azzerano | voluta (decisione dell'utente; scostamento dalla lettera della spec §4.1, che elencava un protocollo per l'apertura delle Impostazioni) |
| Blocco della navigazione durante l'eliminazione Xcode | `CanExecute` dei comandi della sidebar e di ⌘, | i metodi di `MainModel` rifiutano il cambio di pagina (spec §6.3); la vista disabilita in più i controlli | equivalente |
```

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/Page.swift \
  swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/SidebarSectionTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/NavigationLockTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/SettingsOpeningTests.swift \
  swift/MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift \
  docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the main window model with the navigation lock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: verifica finale e chiusura del registro

Nessun codice nuovo: la suite completa, la stabilità dei test con concorrenza, i vincoli globali, i confini (Core e C# intatti) e il registro di parità chiuso per le righe dell'app.

**Files:**
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: l'intero modulo `CleanerFeatures` e i suoi test (Task 1–11).
- Produces: nessuna API nuova.

- [ ] **Step 1: Eseguire l'intera suite**

Run (da `swift/MjmCleanerKit`): `swift test -Xswiftc -warnings-as-errors`
Expected: due righe `Test run with …`, una per target: `118 tests in 20 suites passed` (`CleanerFeaturesTests`) e `496 tests in 47 suites passed` (`CleanerCoreTests`, invariato). Nessun warning. Il conteggio di `CleanerFeaturesTests` è la somma dei task: 10 + 5 + 11 + 8 + 8 + 4 + 8 + 6 + 18 + 26 + 14. Se una review ha aggiunto test, si usa il numero reale e lo si riporta.

- [ ] **Step 2: Verificare la stabilità dei test asincroni**

Run:

```bash
for i in $(seq 1 10); do swift test -Xswiftc -warnings-as-errors --filter CleanerFeaturesTests 2>&1 | grep -E 'Test run with|✘'; done | sed -E 's/ after .*//' | sort | uniq -c
```

Expected: una sola riga, `10 ✔ Test run with 118 tests in 20 suites passed`. Una riga con `✘` è un test instabile e va corretto prima di proseguire: i test attendono sempre un `Gate` o il `Task` del modello, mai un tempo fisso.

- [ ] **Step 3: Verificare i vincoli globali e i confini**

Run (da `swift/MjmCleanerKit`):

```bash
grep -rnE 'try!|as!|import (SwiftUI|AppKit)' Sources/CleanerFeatures || echo "nessuna violazione"
grep -rnE '[A-Za-z0-9_\)\]]!([^=]|$)' Sources/CleanerFeatures || echo "nessun forced unwrap"
grep -rnE '\.(hasPrefix|hasSuffix|lowercased|uppercased)\(' Sources/CleanerFeatures || echo "nessun confronto non ordinale"
echo "localized: $(grep -ro 'localized:' Sources/CleanerFeatures | wc -l) bundle: $(grep -ro 'bundle: \.module' Sources/CleanerFeatures | wc -l)"
git diff --name-only main...HEAD -- Sources/CleanerCore Tests/CleanerCoreTests ../../src ../../tests
```

Expected: le prime tre righe stampano il messaggio di nessuna violazione; la quarta stampa due numeri uguali (ogni `String(localized:)` ha `bundle: .module`; oggi 122 e 122); l'ultima non stampa nulla: il Core e il C# non sono stati toccati. Il secondo pattern può segnalare falsi positivi in commenti o stringhe: controllare a mano ogni riga segnalata. La negazione logica (`!x`) non corrisponde.

Controllare poi a mano, in `Sources/CleanerFeatures`, che nessun `==` o `!=` confronti due `String` per decidere: `grep -rnE '[!=]=' Sources/CleanerFeatures` elenca le righe. Sono ammessi i confronti su enum, numeri, `nil`, `[UInt8]` e `oldValue` di tipi non `String`.

- [ ] **Step 4: Chiudere il registro di parità**

Sostituire le righe `AccessibilityTests.cs`, `ApplicationIdentityTests.cs`, `MainWindowLayoutTests.cs`, `SettingsWindowTests.cs`, `ThemeTests.cs` e `ToolPagesLayoutTests.cs` con:

```markdown
| AccessibilityTests.cs | 3 | — | — | 4b | nomi accessibili dei controlli: li forniscono i controlli SwiftUI e gli `accessibilityLabel` dei pulsanti solo icona (spec §6.6); da verificare nell'app |
| ApplicationIdentityTests.cs | 1 | — | — | 4b | nome dell'app nei menu di sistema: `CFBundleName` del progetto Xcode |
| MainWindowLayoutTests.cs | 3 | — | — | — | layout Avalonia (pagina che non si allarga, footer nel viewport, struttura della shell): con `NavigationSplitView` e `safeAreaInset` il difetto non può verificarsi (spec §9.2); verifica manuale §9.4 |
| SettingsWindowTests.cs | 10 (3) | — | — | 4b | `ClosingTheWindowRestoresTheAppearance` è coperto da `closingFromTheTitleBarBehavesLikeCancel` (stesso `dismiss()`); i limiti dei campi numerici diventano `SettingsModel.thresholdMegabytesRange`/`minAgeDaysRange` per lo `Stepper`; altezza, didascalie, stepper compatto, anello dell'aspetto e cornice dei campi sono layout e tema Avalonia (spec §9.2) |
| ThemeTests.cs | 7 (9) | — | — | 4b | `PreferenceMapsToThemeVariant` e `ApplySetsApplicationVariant` diventano la mappatura `NSApp.appearance` dell'app (`nil`/`.aqua`/`.darkAqua`, spec §6.4); `StepIndicatorMarksOnlyTheCurrentStep` passa allo `StepIndicator` SwiftUI; token di colore, geometrie, ombre e anello di focus sono di Avalonia (spec §9.2) |
| ToolPagesLayoutTests.cs | 4 (12) | — | — | — | toolbar senza «Chiudi» e colori degli Expander di Avalonia (spec §9.2): in SwiftUI si usano toolbar e `DisclosureGroup` nativi; verifica manuale §9.4 |
```

Verificare che le sedici righe della tabella `MjmCleaner.App.Tests` abbiano tutte piano 4a, 4b o «—» con una ragione. Poi aggiungere in testa al file, sotto la riga del piano 3 e con la data del giorno in formato AAAA-MM-GG, la riga: «Piano 4a completato il AAAA-MM-GG: 44 prove C# dell'app portate in `CleanerFeaturesTests` (+ 74 nuove), suite Swift verde (496 + 118 test); le prove della vista restano al piano 4b.» Se le review hanno aggiunto test, i numeri sono quelli reali.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/porting/2026-10-13-parity.md
git commit -m "test(swift): verify CleanerFeatures and close plan 4a

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Dopo il piano 4a

Il piano 4b (app SwiftUI) si scrive sul codice reale di questo piano e usa:

- **Avvio.** `AppEnvironment.live(paths: AppEnvironment.defaultPaths(bundleIdentifier: Bundle.main.bundleIdentifier))`. Se lancia, la finestra mostra `StartupFailure.title` e `StartupFailure.message(paths:error:)` con il pulsante Esci (spec §6.2). Prima di mostrare la finestra si applica `environment.settings.load().appearance` (spec §6.4); poi si chiama `try? await main.refreshTotal()`.
- **Adattatori.** `FolderPicking` con `NSOpenPanel` (solo cartelle); `AppearanceApplying` con `NSApp.appearance = nil / .aqua / .darkAqua`.
- **Finestra.** `MainModel` in `@Environment`; sidebar con `List(selection:)` legata a `Binding(get: { main.section }, set: { main.select($0) })` e disabilitata con `canNavigateGlobally`; contenuto con uno `switch` su `main.page`; ⌘, e «Impostazioni…» con `canShowSettings` e `showSettings()`; `.sheet(item: settings)` con `onDismiss` che chiama `dismiss()`.
- **Asset e testi.** Tile `TileSystemCaches`, `TileDevCaches`, `TileNuGet`, `TileBuildOutput`, `TileTrash`, `TileDownloadsLarge` e `TileNeutral`, con variante chiara da `designHex`; pill `RiskLow`, `RiskMedium` e `RiskHigh`; SF Symbols da `CategoryVisual.symbolName`. Il catalogo dei testi dell'app è separato da quelli di `CleanerCore` e `CleanerFeatures`.
- **Campi e tabella.** `Stepper` con `SettingsModel.thresholdMegabytesRange` e `minAgeDaysRange`; `Table` dello Storico ordinata per `HistoryRow.startedAt` decrescente.
- **Prove della vista.** Restano al piano 4b le prove C# indicate nel registro: nomi accessibili, nome dell'app, clic su «Impostazioni…», ⌘, e voce di menu, toolbar e intestazioni dello Storico, controlli Xcode nel viewport, mappatura dell'aspetto, `StepIndicator`.

Fra il piano 4 e il piano 5 si inserisce il piano dedicato al buco APFS del ripiegamento (U+212A/ſ: `~/Des\u{212A}top/x` supera la deny-list testuale), deciso dall'utente il 2026-10-14: spike su come macOS restituisce il nome canonico, emendamento della spec §12 e correzione in `PathGuard` e nella giuntura `FileSystem`, con il C# ancora disponibile come riferimento.
