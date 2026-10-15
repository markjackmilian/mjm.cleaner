# Porting Swift — Piano 4b: app SwiftUI

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Creare l'app macOS SwiftUI di mjm.cleaner sopra `CleanerFeatures`: progetto Xcode `swift/MjmCleaner.xcodeproj`, avvio con la vista d'errore, adattatori AppKit, finestra principale con sidebar e pagine (wizard, Docker, Xcode, Storico, Impostazioni), asset e testi, un ambiente dimostrativo solo Debug e uno script che fotografa ogni schermata in chiaro e in scuro.

**Architecture:** Il target app contiene solo viste SwiftUI e adattatori AppKit (spec §4.1): ogni decisione resta nei modelli `@MainActor @Observable` di `CleanerFeatures`, già coperti da test e mutazioni nel piano 4a; la vista legge i `canX` e chiama i metodi, che ripetono le proprie guardie. Ciò che il C# teneva nelle viste e che decide qualcosa (nome dell'aspetto, passo segnato dall'indicatore) diventa una funzione pura di `CleanerFeatures` con i test portati. Le viste si verificano compilando con `xcodebuild` e guardando gli screenshot dell'ambiente dimostrativo (`-MJMDemo <pagina>`), che usa servizi finti e non tocca il disco.

**Tech Stack:** Swift 6 language mode, SwiftUI e AppKit su macOS 15, Xcode 27 (progetto `objectVersion = 77` con cartella sincronizzata e package locale), Swift Testing per le funzioni pure, `screencapture` e `CGWindowListCopyWindowInfo` per gli screenshot. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` (soprattutto §2, §4, §6, §8.2, §9.2, §9.4, §10.1)

Questo è il **secondo pezzo del piano 4** (il 4a ha portato `CleanerFeatures`). Dopo il 4b vengono il piano dedicato al buco APFS del ripiegamento e il piano 5 (verifica fianco a fianco con il C#, workflow di release, rimozione del C#), fuori da questo piano.

Stato di partenza: branch `feat/swift-port-app` a `bab0daa` (nessun push), `swift test -Xswiftc -warnings-as-errors` da `swift/MjmCleanerKit` dà **163** test in 20 suite (`CleanerFeaturesTests`) e **496** in 47 (`CleanerCoreTests`). Il registro delle decisioni del 4a (`docs/superpowers/decisions/2026-10-14-registro-decisioni-swift-piano-4a.md`, riga «Note per il 4b») chiede: `delete()`/`confirmDelete()` da `Task` non legati alla vista e «Annulla» su `cancelDelete()`; `refreshTotal()` all'avvio; il binding dello sheet che chiama `settings?.cancel()`; attenzione a `canConfirmDelete`, che legge `executionStarted` (`@ObservationIgnored`).

Decisioni prese con l'utente prima della stesura (2026-10-15):

- **Verifica delle viste: viste sottili più screenshot.** Nessun XCUITest (spec §9.2). Le decisioni stanno nei modelli; le due funzioni pure nuove (`AppearancePreference.appKitAppearanceName`, `PageKind.wizardStep`) si testano con `swift test`. Ogni task di vista finisce con `xcodebuild` e gli screenshot che il revisore guarda; le 27 prove C# di vista hanno ciascuna un metodo di verifica nel registro (Task 11).
- **Ambiente demo solo Debug.** `-MJMDemo <pagina>` e `-MJMAppearance light|dark` aprono una pagina con servizi finti e dati fissi (`swift/MjmCleaner/Demo/`, tutto sotto `#if DEBUG`). Lo script `swift/Scripts/screenshots.sh` fotografa ogni pagina in chiaro e in scuro; il Release non contiene la demo (controllo nel Task 3).
- **Perimetro.** Dentro: progetto, avvio, adattatori, viste, asset, catalogo dei testi, demo e screenshot. Fuori (piano 5): workflow di release (§10.2), collaudo fianco a fianco e confronto con gli screenshot del redesign (§9.4), rimozione del C# (§10.3).
- **Ordine dei task.** Funzioni pure → progetto e avvio → demo e screenshot → finestra principale → wizard (due task) → Docker → Xcode → Storico → Impostazioni → chiusura con gli screenshot e il registro.

Decisioni prese durante la stesura, verificate in una copia scratch (ognuna con il motivo nel task che la applica):

- `StepperNames` del C# non si porta: lo `Stepper` nativo prende il nome accessibile dalla propria etichetta (la riga del campo).
- Le pagine con liste lunghe (passo 3, Docker, Xcode) usano card con `DisclosureGroup` e uno scorrimento interno lazy alto al più 360 punti, come il `ListBox` con `MaxHeight="360"` del C#.
- Tutti gli asset (accento, tile, pill di rischio, icona) nascono nel Task 2 con un solo script, `swift/Scripts/make-assets.py`.

## Global Constraints

Dai piani 1–4a, invariati:

- Il codice Swift vive in `swift/`. Il C# (`src/`, `tests/`) **non si modifica**: è il riferimento eseguibile.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna. Librerie di sistema ammesse nell'app: SwiftUI, AppKit, Foundation, Observation, CoreGraphics (solo nello script degli screenshot), `Synchronization`.
- **Nessun file sotto `swift/MjmCleanerKit/Sources/CleanerCore` o `swift/MjmCleanerKit/Tests/CleanerCoreTests` cambia.** In `CleanerFeatures` cambiano solo le due funzioni pure e i test del Task 1 (emendato dopo l'esecuzione: il fix round del Task 10 e la fix wave finale hanno aggiunto test solo Swift e tre guardie nei modelli, vedi «Emendamenti dopo l'esecuzione»).
- In tutto il codice Swift del piano, app compresa: vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati.
- Testi visibili: in italiano, identici al C#. Nell'app i testi letterali passano dal catalogo dell'app (`Text("…")`, `LocalizedStringKey`, `String(localized: "…")`, file `swift/MjmCleaner/Localizable.xcstrings`, lingua di sviluppo `it`); i testi dei modelli, già localizzati, si mostrano con `Text(model.x)`. I numeri si interpolano come `String`.
- **Nessuna garanzia vive solo nella vista.** Ogni `.disabled(...)` ha la stessa guardia nel metodo del modello che il pulsante chiama (`delete()` → `canDelete`, sidebar → `select`, ⌘, → `showSettings()`); i pulsanti distruttivi chiamano solo il metodo del modello.
- Le operazioni lunghe partono da un `Task { await model.x() }` nell'azione del pulsante, non da `.task`: un cambio di vista non le annulla; «Interrompi» chiama `cancelDelete()`.
- La demo esiste solo sotto `#if DEBUG`, non legge né scrive il disco e non entra nel Release.
- Comandi di verifica standard, dalla radice del repository:
  - package: `(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)`;
  - app: `xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1; grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"; grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"` — Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica` (gli avvisi Swift sono già errori: `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`);
  - screenshot (dal Task 3): `swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" <pagine…>` — rifiuta le pagine sconosciute (uscita 2), non cattura senza la demo nel binario ed esce con 1 se una cattura non riesce.
- Commit frequenti; ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/swift-port-app`, nessun push. Si mettono in stage solo percorsi espliciti: mai `git add -A`, `git add .` o una cartella intera. `.zed/` e `mjm-cleaner-ui-handoff.md` nella radice sono file dell'utente e non vanno mai in stage.

---

## Convenzioni

Valgono quelle dei piani 1–4a. Si aggiungono queste.

| Avalonia (C#) | SwiftUI (Swift) |
|---|---|
| `MainWindow` con sidebar a pulsanti | `NavigationSplitView`, `List(selection:)` legata a `main.section`/`main.select(_:)`, `.disabled(!main.canNavigateGlobally)` |
| `ContentControl` sulla pagina corrente | `PageView`: `switch` su `main.page`, `.id(ObjectIdentifier(model))` per ogni pagina |
| Toolbar 52 px con titolo e sottotitolo | `.navigationTitle` e `.navigationSubtitle` della toolbar nativa; `StepIndicator` come `ToolbarItem(placement: .primaryAction)` |
| `Border.ActionBar` in fondo | `.actionBar { … }` (`safeAreaInset(edge: .bottom)` con `.bar` e un `Divider`) |
| `Button Classes="Primary"` / `"Destructive"` | `.buttonStyle(.borderedProminent)`; distruttivo con `role: .destructive` e `.tint(.red)` |
| `Expander` + `ListBox MaxHeight="360"` | `CollapsibleCard`: `DisclosureGroup` in una card, righe in `ScrollView { LazyVStack }` alto al più 360 |
| `Command="{Binding XCommand}"` con `CanExecute` | `Button(action: model.x)` + `.disabled(!model.canX)`; `Task { await model.x() }` per i metodi `async` |
| `IsVisible="{Binding Testo, Converter=IsNotNullOrEmpty}"` | `OptionalText(text:)` o `if !model.x.isEmpty` |
| `SettingsWindow` modale | `.sheet(item:)` su `main.settings`; il `set` a `nil` chiama `main.settings?.cancel()` |
| `NumericUpDown` compatto | `TextField(value:format:)` + unità + `Stepper` nativo, valore limitato all'intervallo del C# |
| `FatalErrorWindow` | `StartupFailureView` nella finestra principale, con «Esci» |
| `AppearanceController.Apply` | `AppKitAppearance.apply`: `NSApp.appearance` dal nome di `appKitAppearanceName` |
| `StorageFolderPicker` | `AppKitFolderPicker`: `NSOpenPanel`, solo cartelle |

### Fatti misurati (2026-10-15, Xcode 27.0, SDK macOS 27)

- `xcodebuild` compila il progetto scritto a mano (`objectVersion = 77`, `PBXFileSystemSynchronizedRootGroup` per `swift/MjmCleaner/`, `XCLocalSwiftPackageReference` per `MjmCleanerKit`) senza diagnostica, in Debug e in Release universale (`lipo -archs`: `x86_64 arm64`).
- Un `Info.plist` generato (`GENERATE_INFOPLIST_FILE = YES`) sovrascrive `CFBundleName` con `PRODUCT_NAME` anche se `INFOPLIST_FILE` lo definisce: per avere «mjm.cleaner» nei menu serve un `Info.plist` completo e `GENERATE_INFOPLIST_FILE = NO`.
- Icona da un solo PNG 1024: `"idiom" : "mac", "scale" : "2x", "size" : "512x512"`. La forma `"idiom" : "universal", "platform" : "macos"` dà gli avvisi «Unknown platform value "macos"» e «unassigned child».
- Senza `ALWAYS_SEARCH_USER_PATHS = NO` compare l'avviso «Traditional headermap style is no longer supported».
- Nei build puliti `appintentsmetadataprocessor` stampa `… appintentsmetadataprocessor[pid:tid] warning: Metadata extraction skipped, no AppIntents.framework dependency found`: è un log dello strumento, non una diagnostica. Il controllo `grep -E '(^|: )(warning|error): '` prende le diagnostiche del compilatore e degli asset (`<percorso>: warning: …`) e quelle del build system senza percorso (`warning: Traditional headermap style …`), non quella riga (preceduta da `] `).
- `codesign -dv` dice `Signature=adhoc` anche quando Xcode non firma (`CODE_SIGNING_ALLOWED = NO`: firma automatica del linker, senza risorse sigillate). La firma «Sign to Run Locally» si riconosce da `codesign --verify --strict` valido e da `Sealed Resources version=2`.
- `xcodebuild` non modifica il catalogo dei testi dell'app: resta `{"sourceLanguage":"it","strings":{}}` come quelli dei package. Un build da Xcode IDE può riempirlo: è atteso.
- L'app avviata come processo figlio della shell dell'agente non ottiene finestre (`sandbox_extension_issue_file_to_process failed`); avviata con `open -n <app> --args …` (LaunchServices) sì. `screencapture -x -o -l<id>` cattura la finestra, sheet compreso; il permesso di registrazione dello schermo è concesso (`CGPreflightScreenCaptureAccess()` → `true`).
- Con lo schermo bloccato o il display spento (`CGSSessionScreenIsLocked = 1`, `CGDisplayIsAsleep`) `screencapture -l` dice «could not create image from window» e la cattura a schermo intero è nera, anche con il permesso concesso: lo script lo segnala ed esce con 1.
- `.fixedSize(horizontal: false, vertical: true)` su un testo dentro un `safeAreaInset(edge: .bottom)` rompe il layout della finestra (pagina vuota, sidebar spostata o vuota): nei testi delle fasce in basso non si usa.
- `List(selection:)` non chiama il `set` del binding se si riclicca la voce già selezionata.
- `XcodeSelection.preview` su un candidato DerivedData o Device Support richiede la voce nell'inventario dei file dello snapshot (`fileInventory`): la demo anteprima solo il runtime.
- Release: `strings` del binario non trova nulla che corrisponda a `MJMDemo|Demo[A-Z]|/Users/demo` (né i nomi delle pagine o i dati della demo); nel binario Debug (`MjmCleaner.debug.dylib`) sì.
- Con un'altra app in primo piano (Mac in uso) `open` non porta l'app davanti (attivazione cooperativa di macOS): la finestra resta inattiva, con i pulsanti in tinta grigi; quando invece arriva davanti riceve i tasti di chi sta scrivendo. Le catture si fanno con il Mac fermo.
- Lo stato salvato della finestra prevale su `.defaultSize`; con `-ApplePersistenceIgnoreState YES` la finestra si apre alla misura predefinita (provato con `.defaultSize(900, 600)`: finestra 900×652, sheet delle Impostazioni intero).

---

## Mappa dei file

```
swift/
├── MjmCleaner.xcodeproj/
│   ├── project.pbxproj                                   Task 2
│   └── xcshareddata/xcschemes/MjmCleaner.xcscheme        Task 2
├── Config/Base.xcconfig, Debug.xcconfig,
│          Release.xcconfig, Info.plist                   Task 2
├── Scripts/make-assets.py                                Task 2
├── Scripts/screenshots.sh, window-id.swift               Task 3
├── MjmCleaner/
│   ├── Assets.xcassets/ (generato), Localizable.xcstrings Task 2
│   ├── App/MjmCleanerApp.swift, AppStartup.swift,
│   │       AppKitServices.swift, StartupFailureView.swift Task 2 (AppStartup: demo nel Task 3)
│   ├── Demo/DemoLaunch.swift, DemoServices.swift,
│   │        DemoData.swift                               Task 3
│   ├── Shell/MainView.swift                              Task 2 (provvisoria), Task 4
│   ├── Shell/SidebarView.swift, StepIndicator.swift,
│   │         PageComponents.swift, PendingPages.swift    Task 4 (PendingPages si svuota nei Task 5–10)
│   ├── Cleanup/CategoryBadges.swift, ChooseStepView.swift,
│   │           ScanStepView.swift                        Task 5
│   ├── Cleanup/ConfirmStepView.swift, DoneStepView.swift Task 6
│   ├── Docker/DockerView.swift, DockerReportView.swift   Task 7
│   ├── Xcode/XcodeView.swift, XcodeReportView.swift      Task 8
│   ├── History/HistoryView.swift                         Task 9
│   └── Settings/SettingsView.swift                       Task 10
└── MjmCleanerKit/
    ├── Sources/CleanerFeatures/Shell/Page.swift,
    │   Environment/PlatformServices.swift                Task 1
    └── Tests/CleanerFeaturesTests/ThemeTests.swift,
        Support/TestSupport.swift                         Task 1
docs/superpowers/porting/2026-10-13-parity.md             Task 1, 2, 4, 6, 10, 11
docs/superpowers/verification/<data>-swift-4b/            Task 11
```

Le modifiche a file esistenti sono scritte come «In `file`, sostituire» un blocco esatto con un altro: il blocco da sostituire compare una sola volta nel file. Un file creato in un task e riscritto in un task successivo è indicato come «Sostituire l'intero contenuto».

---
### Task 1: funzioni pure per le viste (aspetto e passo del wizard)

Due decisioni che il C# prendeva nelle viste diventano funzioni pure di `CleanerFeatures`, con i test C# portati: il nome dell'`NSAppearance` per ogni preferenza (`AppearanceController.ThemeVariantFor`) e il passo che lo `StepIndicator` segna come corrente. Si toglie anche `Gate.isOpen`, rimasto senza chiamanti dopo `bab0daa`.

**Files:**
- Create: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ThemeTests.swift`
- Modify: `swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/Page.swift` (dopo `isWizardStep`)
- Modify: `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift` (dopo `AppearanceApplying`)
- Modify: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift` (`Gate.isOpen`)
- Modify: `docs/superpowers/porting/2026-10-13-parity.md` (riga `ThemeTests.cs`)

**Interfaces:**
- Consumes: `AppearancePreference` (`CleanerCore`: `.auto`, `.light`, `.dark`), `PageKind` (`CleanerFeatures`).
- Produces: `extension AppearancePreference { public var appKitAppearanceName: String? }` (`nil`, `"NSAppearanceNameAqua"`, `"NSAppearanceNameDarkAqua"`); `PageKind.wizardStep: Int?` (1–4 sui passi del wizard, altrimenti `nil`). Il Task 2 (`AppKitAppearance`) e il Task 4 (`WizardChrome`) li usano.

- [ ] **Step 1: Scrivere i test portati**

**Creare `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ThemeTests.swift`:**

```swift
import CleanerCore
import Testing
@testable import CleanerFeatures

/// Le prove di `ThemeTests.cs` che non dipendono da Avalonia: la mappatura dell'aspetto e il passo
/// segnato dall'indicatore. Token di colore, geometrie, ombre e anello di focus erano del tema
/// Avalonia (spec §9.2).
struct ThemeTests {
    @Test(arguments: [
        (AppearancePreference.auto, String?.none),
        (.light, "NSAppearanceNameAqua"),
        (.dark, "NSAppearanceNameDarkAqua"),
    ])
    func preferenceMapsToThemeVariant(preference: AppearancePreference, expected: String?) {
        #expect(preference.appKitAppearanceName == expected)
    }

    @Test func stepIndicatorMarksOnlyTheCurrentStep() {
        #expect([PageKind.choose, .scan, .confirm, .done].map(\.wizardStep) == [1, 2, 3, 4])
        #expect(PageKind.allCases.filter { !$0.isWizardStep }.allSatisfy { $0.wizardStep == nil })
    }
}
```

- [ ] **Step 2: Verificare che la build dei test fallisca**

Run: `(cd swift/MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | grep -E 'error:' | sort -u)`
Expected: tre diagnostiche con due messaggi distinti (`wizardStep` compare in due punti del test), `value of type 'AppearancePreference' has no member 'appKitAppearanceName'` e `value of type 'PageKind' has no member 'wizardStep'`.

- [ ] **Step 3: Scrivere le due funzioni**

**In `swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/Page.swift`, sostituire:**

```swift
    /// I quattro passi del wizard di pulizia.
    public var isWizardStep: Bool {
        switch self {
        case .choose, .scan, .confirm, .done: true
        default: false
        }
    }
}
```

**con:**

```swift
    /// I quattro passi del wizard di pulizia.
    public var isWizardStep: Bool { wizardStep != nil }

    /// Il passo (1–4) che lo `StepIndicator` segna come corrente; `nil` fuori dal wizard.
    public var wizardStep: Int? {
        switch self {
        case .choose: 1
        case .scan: 2
        case .confirm: 3
        case .done: 4
        case .docker, .dockerReport, .xcode, .xcodeReport, .history: nil
        }
    }
}
```

**In `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift`, sostituire:**

```swift
@MainActor
public protocol AppearanceApplying {
    func apply(_ preference: AppearancePreference)
}
```

**con:**

```swift
@MainActor
public protocol AppearanceApplying {
    func apply(_ preference: AppearancePreference)
}

extension AppearancePreference {
    /// Il nome dell'`NSAppearance` che l'app assegna a `NSApp.appearance` (spec §6.4); `nil` segue
    /// Impostazioni di Sistema e ne riprende i cambi in tempo reale. È `ThemeVariantFor` del C#,
    /// qui senza AppKit: l'adattatore dell'app converte solo il nome.
    public var appKitAppearanceName: String? {
        switch self {
        case .auto: nil
        case .light: "NSAppearanceNameAqua"
        case .dark: "NSAppearanceNameDarkAqua"
        }
    }
}
```

- [ ] **Step 4: Togliere `Gate.isOpen`**

`isOpen` non ha più chiamanti dopo `bab0daa` (revisione di quel commit, Minor 4).

**In `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift`, sostituire:**

```swift
    private let state = Mutex(State())

    var isOpen: Bool {
        state.withLock { $0.value != nil }
    }

```

**con:**

```swift
    private let state = Mutex(State())

```

- [ ] **Step 5: Eseguire i test**

Run: `(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter ThemeTests 2>&1 | grep -E 'Test run with')`
Expected: `Test run with 2 tests in 1 suite passed` (il test parametrico conta come uno, con 3 casi).

Run: `(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')`
Expected: `Test run with 165 tests in 21 suites passed` (`CleanerFeaturesTests`, 163 + 2) e `Test run with 496 tests in 47 suites passed` (`CleanerCoreTests`, invariato), nessun warning.

- [ ] **Step 6: Registro di parità**

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| ThemeTests.cs | 7 (9) | — | — | 4b | `PreferenceMapsToThemeVariant` e `ApplySetsApplicationVariant` diventano la mappatura `NSApp.appearance` dell'app (`nil`/`.aqua`/`.darkAqua`, spec §6.4); `StepIndicatorMarksOnlyTheCurrentStep` passa allo `StepIndicator` SwiftUI; token di colore, geometrie, ombre e anello di focus sono di Avalonia (spec §9.2) |
```

**con:**

```markdown
| ThemeTests.cs | 7 (9) | ThemeTests.swift | 2 (3) | 4b | 2 portati sulle funzioni pure che le viste usano: `preferenceMapsToThemeVariant` (3 casi) sul nome dell'`NSAppearance` (`appKitAppearanceName`: `nil`, `NSAppearanceNameAqua`, `NSAppearanceNameDarkAqua`; spec §6.4) e `stepIndicatorMarksOnlyTheCurrentStep` su `PageKind.wizardStep`; `ApplySetsApplicationVariant` diventa l'adattatore `AppKitAppearance`, verificato dagli screenshot in chiaro e in scuro (Task 11); token di colore, geometrie, ombre e anello di focus sono di Avalonia (spec §9.2) |
```

- [ ] **Step 7: Commit**

```bash
git add swift/MjmCleanerKit/Sources/CleanerFeatures/Shell/Page.swift \
    swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/PlatformServices.swift \
    swift/MjmCleanerKit/Tests/CleanerFeaturesTests/ThemeTests.swift \
    swift/MjmCleanerKit/Tests/CleanerFeaturesTests/Support/TestSupport.swift \
    docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
feat(swift): map the appearance and the wizard step for the app views

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 2: progetto Xcode, avvio e adattatori AppKit

Il target app nasce con il progetto scritto a mano, la configurazione in xcconfig, l'`Info.plist`, gli asset e il catalogo dei testi. L'avvio porta `App.OnFrameworkInitializationCompleted`: aspetto applicato prima della finestra, `AppEnvironment.live` oppure la vista d'errore, contatore letto all'avvio, «Impostazioni… ⌘,» come comando di menu. La finestra principale è provvisoria fino al Task 4.

**Files:**
- Create: `swift/MjmCleaner.xcodeproj/project.pbxproj`, `swift/MjmCleaner.xcodeproj/xcshareddata/xcschemes/MjmCleaner.xcscheme`
- Create: `swift/Config/Base.xcconfig`, `swift/Config/Debug.xcconfig`, `swift/Config/Release.xcconfig`, `swift/Config/Info.plist`
- Create: `swift/Scripts/make-assets.py` e, generati, i `Contents.json` sotto `swift/MjmCleaner/Assets.xcassets/` più `AppIcon.appiconset/AppIcon-1024.png` (copiato dal C#)
- Create: `swift/MjmCleaner/Localizable.xcstrings`
- Create: `swift/MjmCleaner/App/MjmCleanerApp.swift`, `AppStartup.swift`, `AppKitServices.swift`, `StartupFailureView.swift`
- Create: `swift/MjmCleaner/Shell/MainView.swift` (provvisoria, sostituita nel Task 4)
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: `AppEnvironment.live(paths:)`, `AppEnvironment.defaultPaths(bundleIdentifier:)`, `MainModel(environment:appearance:folders:)`, `MainModel.refreshTotal()`, `.showSettings()`, `.canShowSettings`, `StartupFailure.title`/`.message(paths:error:)`, `SettingsStore(fileSystem:paths:)`, `LocalFileSystem()`, `AppearancePreference.appKitAppearanceName` (Task 1), `FolderPicking`, `AppearanceApplying`.
- Produces: `AppStartup` (`@MainActor @Observable`: `state: State` con `.loading`/`.ready(MainModel)`/`.failed(String)`, `main: MainModel?`, `static paths`, `static savedAppearance()`, `start() async`, `show(_:)`, `fail(_:)`), `RootView(startup:)`, `MainView(main:)`, `AppKitAppearance`, `AppKitFolderPicker`, `StartupFailureView(message:)`. Il Task 3 aggiunge la demo ad `AppStartup`; il Task 4 sostituisce `MainView`.

- [ ] **Step 1: Progetto e schema**

Il progetto ha un solo target app. `swift/MjmCleaner/` è una cartella sincronizzata (`PBXFileSystemSynchronizedRootGroup`): ogni file Swift o di risorse aggiunto lì entra nel target senza toccare il progetto. `MjmCleanerKit` è un package locale con i prodotti `CleanerCore` e `CleanerFeatures`. Le impostazioni stanno tutte negli xcconfig del target; le configurazioni di progetto restano vuote. Gli identificativi sono fissi e leggibili (`4B00…`).

**Creare `swift/MjmCleaner.xcodeproj/project.pbxproj`:**

```text
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXBuildFile section */
		4B0000000000000000000033 /* CleanerCore in Frameworks */ = {isa = PBXBuildFile; productRef = 4B0000000000000000000031 /* CleanerCore */; };
		4B0000000000000000000034 /* CleanerFeatures in Frameworks */ = {isa = PBXBuildFile; productRef = 4B0000000000000000000032 /* CleanerFeatures */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		4B0000000000000000000006 /* MjmCleaner.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = MjmCleaner.app; sourceTree = BUILT_PRODUCTS_DIR; };
		4B0000000000000000000007 /* Base.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; sourceTree = "<group>"; };
		4B0000000000000000000008 /* Debug.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Debug.xcconfig; sourceTree = "<group>"; };
		4B0000000000000000000009 /* Release.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Release.xcconfig; sourceTree = "<group>"; };
		4B000000000000000000000A /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		4B0000000000000000000035 /* MjmCleanerKit */ = {isa = PBXFileReference; lastKnownFileType = wrapper; path = MjmCleanerKit; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		4B0000000000000000000005 /* MjmCleaner */ = {isa = PBXFileSystemSynchronizedRootGroup; path = MjmCleaner; sourceTree = "<group>"; };
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		4B0000000000000000000012 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				4B0000000000000000000033 /* CleanerCore in Frameworks */,
				4B0000000000000000000034 /* CleanerFeatures in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		4B0000000000000000000002 = {
			isa = PBXGroup;
			children = (
				4B0000000000000000000005 /* MjmCleaner */,
				4B0000000000000000000004 /* Config */,
				4B0000000000000000000035 /* MjmCleanerKit */,
				4B0000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		4B0000000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				4B0000000000000000000006 /* MjmCleaner.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
		4B0000000000000000000004 /* Config */ = {
			isa = PBXGroup;
			children = (
				4B0000000000000000000007 /* Base.xcconfig */,
				4B0000000000000000000008 /* Debug.xcconfig */,
				4B0000000000000000000009 /* Release.xcconfig */,
				4B000000000000000000000A /* Info.plist */,
			);
			path = Config;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		4B0000000000000000000010 /* MjmCleaner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 4B0000000000000000000023 /* Build configuration list for PBXNativeTarget "MjmCleaner" */;
			buildPhases = (
				4B0000000000000000000011 /* Sources */,
				4B0000000000000000000012 /* Frameworks */,
				4B0000000000000000000013 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				4B0000000000000000000005 /* MjmCleaner */,
			);
			name = MjmCleaner;
			packageProductDependencies = (
				4B0000000000000000000031 /* CleanerCore */,
				4B0000000000000000000032 /* CleanerFeatures */,
			);
			productName = MjmCleaner;
			productReference = 4B0000000000000000000006 /* MjmCleaner.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		4B0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2700;
				LastUpgradeCheck = 2700;
				TargetAttributes = {
					4B0000000000000000000010 = {
						CreatedOnToolsVersion = 27.0;
					};
				};
			};
			buildConfigurationList = 4B0000000000000000000020 /* Build configuration list for PBXProject "MjmCleaner" */;
			developmentRegion = it;
			hasScannedForEncodings = 0;
			knownRegions = (
				it,
				Base,
			);
			mainGroup = 4B0000000000000000000002;
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				4B0000000000000000000030 /* XCLocalSwiftPackageReference "MjmCleanerKit" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = 4B0000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				4B0000000000000000000010 /* MjmCleaner */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		4B0000000000000000000013 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		4B0000000000000000000011 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		4B0000000000000000000021 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
			};
			name = Debug;
		};
		4B0000000000000000000022 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
			};
			name = Release;
		};
		4B0000000000000000000024 /* Debug */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = 4B0000000000000000000008 /* Debug.xcconfig */;
			buildSettings = {
			};
			name = Debug;
		};
		4B0000000000000000000025 /* Release */ = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = 4B0000000000000000000009 /* Release.xcconfig */;
			buildSettings = {
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		4B0000000000000000000020 /* Build configuration list for PBXProject "MjmCleaner" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				4B0000000000000000000021 /* Debug */,
				4B0000000000000000000022 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		4B0000000000000000000023 /* Build configuration list for PBXNativeTarget "MjmCleaner" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				4B0000000000000000000024 /* Debug */,
				4B0000000000000000000025 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		4B0000000000000000000030 /* XCLocalSwiftPackageReference "MjmCleanerKit" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = MjmCleanerKit;
		};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		4B0000000000000000000031 /* CleanerCore */ = {
			isa = XCSwiftPackageProductDependency;
			package = 4B0000000000000000000030 /* XCLocalSwiftPackageReference "MjmCleanerKit" */;
			productName = CleanerCore;
		};
		4B0000000000000000000032 /* CleanerFeatures */ = {
			isa = XCSwiftPackageProductDependency;
			package = 4B0000000000000000000030 /* XCLocalSwiftPackageReference "MjmCleanerKit" */;
			productName = CleanerFeatures;
		};
/* End XCSwiftPackageProductDependency section */
	};
	rootObject = 4B0000000000000000000001 /* Project object */;
}
```

**Creare `swift/MjmCleaner.xcodeproj/xcshareddata/xcschemes/MjmCleaner.xcscheme`:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "4B0000000000000000000010"
               BuildableName = "MjmCleaner.app"
               BlueprintName = "MjmCleaner"
               ReferencedContainer = "container:MjmCleaner.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "4B0000000000000000000010"
            BuildableName = "MjmCleaner.app"
            BlueprintName = "MjmCleaner"
            ReferencedContainer = "container:MjmCleaner.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "4B0000000000000000000010"
            BuildableName = "MjmCleaner.app"
            BlueprintName = "MjmCleaner"
            ReferencedContainer = "container:MjmCleaner.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 2: Configurazione e `Info.plist`**

**Creare `swift/Config/Base.xcconfig`:**

```text
// Impostazioni del target app (spec §10.1). Versione e build si sovrascrivono da riga di comando:
// xcodebuild … MARKETING_VERSION=1.2.0 CURRENT_PROJECT_VERSION=42

// Identità. Il bundle id è provvisorio: quello definitivo va fissato prima della fase 2 (spec §4.4).
PRODUCT_NAME = MjmCleaner
PRODUCT_BUNDLE_IDENTIFIER = com.mjm.cleaner
MARKETING_VERSION = 0.1.0
CURRENT_PROJECT_VERSION = 1

// Info.plist scritto a mano: il nome nei menu di sistema è «mjm.cleaner» (CFBundleName), che un
// Info.plist generato sostituirebbe con PRODUCT_NAME.
GENERATE_INFOPLIST_FILE = NO
INFOPLIST_FILE = Config/Info.plist

// Piattaforma e linguaggio.
SDKROOT = macosx
MACOSX_DEPLOYMENT_TARGET = 15.0
SWIFT_VERSION = 6.0
SWIFT_TREAT_WARNINGS_AS_ERRORS = YES
GCC_TREAT_WARNINGS_AS_ERRORS = YES

// Firma «Sign to Run Locally»: ad hoc, nessuna identità né team (spec §3, §10.1).
CODE_SIGN_IDENTITY = -
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM =

// Risorse: icona, accento e testi in italiano.
ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon
ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor
LOCALIZATION_PREFERS_STRING_CATALOGS = YES
SWIFT_EMIT_LOC_STRINGS = YES

LD_RUNPATH_SEARCH_PATHS = $(inherited) @executable_path/../Frameworks
ENABLE_USER_SCRIPT_SANDBOXING = YES

// Solo le header map moderne: evita l'avviso «Traditional headermap style».
ALWAYS_SEARCH_USER_PATHS = NO
```

**Creare `swift/Config/Debug.xcconfig`:**

```text
#include "Base.xcconfig"

// DEBUG abilita l'ambiente demo per gli screenshot (MjmCleaner/Demo): mai nel Release.
SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG
SWIFT_OPTIMIZATION_LEVEL = -Onone
GCC_OPTIMIZATION_LEVEL = 0
ONLY_ACTIVE_ARCH = YES
DEBUG_INFORMATION_FORMAT = dwarf
ENABLE_TESTABILITY = YES
```

**Creare `swift/Config/Release.xcconfig`:**

```text
#include "Base.xcconfig"

// Una sola build universale arm64 + x86_64 (spec §10.2).
SWIFT_COMPILATION_MODE = wholemodule
SWIFT_OPTIMIZATION_LEVEL = -O
ONLY_ACTIVE_ARCH = NO
DEBUG_INFORMATION_FORMAT = dwarf-with-dsym
```

**Creare `swift/Config/Info.plist`:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>it</string>
	<key>CFBundleDisplayName</key>
	<string>mjm.cleaner</string>
	<key>CFBundleExecutable</key>
	<string>$(EXECUTABLE_NAME)</string>
	<key>CFBundleIdentifier</key>
	<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>mjm.cleaner</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>$(MARKETING_VERSION)</string>
	<key>CFBundleVersion</key>
	<string>$(CURRENT_PROJECT_VERSION)</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>$(MACOSX_DEPLOYMENT_TARGET)</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
```

- [ ] **Step 3: Asset e catalogo dei testi**

Lo script scrive i `Contents.json` del catalogo asset: accento `#0A66D8`; tile delle categorie con lo stesso colore in chiaro e in scuro (`CategoryVisuals.designHex`); pill di rischio con testo e fondo, in chiaro e in scuro (`MacTheme.axaml`). L'icona è il PNG 1024 dell'app C#.

**Creare `swift/Scripts/make-assets.py`:**

```python
"""Scrive il catalogo asset dell'app (spec §6.4): accento, tile delle categorie, pill di rischio e la
voce dell'icona (il PNG si copia a parte). I file Contents.json generati sono quelli da committare.

Uso, dalla radice del repository: python3 -I swift/Scripts/make-assets.py swift/MjmCleaner/Assets.xcassets
"""
import json
import os
import sys

root = sys.argv[1]
INFO = {"author": "xcode", "version": 1}


def write(path, content):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Contents.json"), "w", encoding="utf-8") as f:
        json.dump(content, f, indent=2)
        f.write("\n")


def color(argb):
    """"#RRGGBB" o "#AARRGGBB" → componenti sRGB."""
    hex = argb.lstrip("#")
    alpha = int(hex[:2], 16) / 255 if len(hex) == 8 else 1.0
    rgb = hex[-6:]
    return {
        "color-space": "srgb",
        "components": {
            "alpha": f"{alpha:.3f}",
            "red": "0x" + rgb[0:2],
            "green": "0x" + rgb[2:4],
            "blue": "0x" + rgb[4:6],
        },
    }


def colorset(name, light, dark=None):
    colors = [{"color": color(light), "idiom": "universal"}]
    if dark is not None:
        colors.append({
            "appearances": [{"appearance": "luminosity", "value": "dark"}],
            "color": color(dark),
            "idiom": "universal",
        })
    write(os.path.join(root, name + ".colorset"), {"colors": colors, "info": INFO})


write(root, {"info": INFO})
write(os.path.join(root, "AppIcon.appiconset"), {
    "images": [{"filename": "AppIcon-1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"}],
    "info": INFO,
})

# Accento del progetto: macOS lo usa con l'accento di sistema «multicolore».
colorset("AccentColor", "#0A66D8")

# Tile delle categorie: lo stesso colore in chiaro e in scuro, con il simbolo bianco.
for name, value in [
    ("TileSystemCaches", "#66788F"),
    ("TileDevCaches", "#7457E8"),
    ("TileNuGet", "#3567D0"),
    ("TileBuildOutput", "#1D8784"),
    ("TileTrash", "#D2453A"),
    ("TileDownloadsLarge", "#E8833A"),
    ("TileNeutral", "#85858B"),
]:
    colorset(name, value)

# Pill di rischio: testo e fondo, chiaro e scuro (MacTheme.axaml del C#).
for name, light, dark in [
    ("RiskLow", "#55555A", "#C7C7CC"),
    ("RiskLowBackground", "#0E000000", "#14FFFFFF"),
    ("RiskMedium", "#9E4700", "#FFB04D"),
    ("RiskMediumBackground", "#FFF0DE", "#29FF9F0A"),
    ("RiskHigh", "#B42318", "#FF8A80"),
    ("RiskHighBackground", "#FDECEA", "#2BFF453A"),
]:
    colorset(name, light, dark)
```

```bash
# passo di generazione
python3 -I swift/Scripts/make-assets.py swift/MjmCleaner/Assets.xcassets
cp src/MjmCleaner.App/Assets/AppIcon-1024.png swift/MjmCleaner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
find swift/MjmCleaner/Assets.xcassets -type f | sort
```

Expected: 17 file: il `Contents.json` della radice, quello di `AccentColor.colorset`, quello di `AppIcon.appiconset` con `AppIcon-1024.png`, e quelli di sei `Risk*.colorset` e sette `Tile*.colorset`.

**Creare `swift/MjmCleaner/Localizable.xcstrings`:**

```json
{
  "sourceLanguage" : "it",
  "strings" : {
  },
  "version" : "1.0"
}
```

- [ ] **Step 4: Avvio, adattatori e vista d'errore**

`AppDelegate.applicationWillFinishLaunching` applica l'aspetto salvato prima che la finestra compaia, come il C# prima di creare la `MainWindow`. `AppStartup.start()` compone l'ambiente; se fallisce mostra `StartupFailureView` con percorso e motivo. Il contatore si legge una volta all'avvio (`show(_:)`). `AppKitFolderPicker` apre il pannello come foglio della finestra attiva (lo sheet delle Impostazioni), come `StorageFolderPicker(window)` del C#: un pannello libero lascerebbe chiudere le Impostazioni e perderebbe la cartella scelta dopo.

**Creare `swift/MjmCleaner/App/MjmCleanerApp.swift`:**

```swift
import AppKit
import CleanerFeatures
import SwiftUI

/// Una sola finestra (spec §6.2): 1120×700 all'apertura, almeno 900×600. «Impostazioni… ⌘,» apre
/// lo sheet della finestra principale al posto della scena `Settings` standard, che non è modale e
/// non ha Annulla.
@main
struct MjmCleanerApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var startup = AppStartup()

    var body: some Scene {
        Window(Text(verbatim: "mjm.cleaner"), id: "main") {
            RootView(startup: startup)
                .frame(minWidth: 900, minHeight: 600)
                .task { await startup.start() }
        }
        .defaultSize(width: 1120, height: 700)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Impostazioni…") { startup.main?.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
                    .disabled(!(startup.main?.canShowSettings ?? false))
            }
        }
    }
}

/// L'aspetto si applica prima che la finestra compaia, così non lampeggia quello sbagliato
/// (`App.axaml.cs`). L'ambiente nasce in modo asincrono: qui si legge solo la preferenza salvata.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        AppKitAppearance().apply(AppStartup.savedAppearance())
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Il contenuto della finestra: niente finché l'ambiente non è pronto, poi la finestra principale
/// oppure la vista d'errore (`FatalErrorWindow`).
struct RootView: View {
    let startup: AppStartup

    var body: some View {
        switch startup.state {
        case .loading:
            Color.clear
        case .ready(let main):
            MainView(main: main)
        case .failed(let message):
            StartupFailureView(message: message)
        }
    }
}
```

**Creare `swift/MjmCleaner/App/AppStartup.swift`:**

```swift
import CleanerCore
import CleanerFeatures
import Foundation
import Observation

/// L'avvio dell'app (`App.OnFrameworkInitializationCompleted`): compone l'ambiente, crea la finestra
/// principale e legge il contatore; se la composizione fallisce (cartella dati non scrivibile,
/// database corrotto) mostra la vista d'errore con il percorso e il motivo.
@MainActor
@Observable
final class AppStartup {
    enum State {
        case loading
        case ready(MainModel)
        case failed(String)
    }

    private(set) var state = State.loading
    @ObservationIgnored private var started = false

    var main: MainModel? {
        if case .ready(let main) = state { main } else { nil }
    }

    /// La cartella dati dell'app (spec §4.4).
    static var paths: AppPaths {
        AppEnvironment.defaultPaths(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    /// La stessa lettura di `environment.settings.load()`, fatta prima che l'ambiente esista.
    static func savedAppearance() -> AppearancePreference {
        SettingsStore(fileSystem: LocalFileSystem(), paths: paths).load().appearance
    }

    func start() async {
        guard !started else { return }
        started = true

        let paths = Self.paths
        do {
            let environment = try await AppEnvironment.live(paths: paths)
            show(MainModel(environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker()))
        } catch {
            fail(StartupFailure.message(paths: paths, error: error))
        }
    }

    /// Mostra la finestra principale e legge il contatore «Spazio liberato». Se lo storico non si
    /// legge il contatore resta «—», come in C#.
    func show(_ main: MainModel) {
        state = .ready(main)
        Task { try? await main.refreshTotal() }
    }

    func fail(_ message: String) {
        state = .failed(message)
    }
}
```

**Creare `swift/MjmCleaner/App/AppKitServices.swift`:**

```swift
import AppKit
import CleanerCore
import CleanerFeatures

/// `AppearanceController`: l'aspetto vale per tutta l'app, quindi per ogni finestra e per gli
/// sheet. Con `nil` macOS segue Impostazioni di Sistema in tempo reale (spec §6.4).
@MainActor
struct AppKitAppearance: AppearanceApplying {
    func apply(_ preference: AppearancePreference) {
        NSApp.appearance = preference.appKitAppearanceName.flatMap { NSAppearance(named: NSAppearance.Name($0)) }
    }
}

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
        panel.canCreateDirectories = false
        // Come `StorageFolderPicker(window)` del C#: un foglio della finestra attiva (lo sheet delle
        // Impostazioni), che resta bloccata finché non si sceglie o si annulla. Senza finestra attiva,
        // un pannello modale. Un pannello libero lascerebbe chiudere le Impostazioni e perderebbe la
        // cartella scelta dopo.
        let response = if let window = NSApp.keyWindow {
            await panel.beginSheetModal(for: window)
        } else {
            panel.runModal()
        }
        guard response == .OK, let url = panel.url else { return nil }
        return url.path(percentEncoded: false)
    }
}
```

**Creare `swift/MjmCleaner/App/StartupFailureView.swift`:**

```swift
import AppKit
import CleanerFeatures
import SwiftUI

/// `FatalErrorWindow`: la composizione è fallita e l'app non può fare altro che dire cosa e dove.
struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(StartupFailure.title)
                .font(.title2.bold())
            Text(message)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Esci") { NSApp.terminate(nil) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

**Creare `swift/MjmCleaner/Shell/MainView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Provvisoria: la finestra principale, con sidebar e pagine, arriva con il Task 4.
struct MainView: View {
    let main: MainModel

    var body: some View {
        Text(verbatim: main.totalFreedAmount)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Build Debug e Release**

Run (Debug):

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

Run (Release universale e identità dell'app):

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-release" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-release.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-release.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-release.log" || echo "nessuna diagnostica"
app="${TMPDIR:-/tmp}/mjm-cleaner-release/Build/Products/Release/MjmCleaner.app"
lipo -archs "$app/Contents/MacOS/MjmCleaner"
/usr/libexec/PlistBuddy -c 'Print :CFBundleName' -c 'Print :CFBundleIdentifier' -c 'Print :LSMinimumSystemVersion' "$app/Contents/Info.plist"
codesign --verify --strict "$app" && echo "firma valida"
codesign -dv "$app" 2>&1 | grep -E '^Signature=adhoc|^Sealed Resources version=2'
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Release -showBuildSettings 2>/dev/null \
    | grep -E '^ *SWIFT_VERSION = '
```

Expected: `** BUILD SUCCEEDED **`, `nessuna diagnostica`, `x86_64 arm64`, poi `mjm.cleaner`, `com.mjm.cleaner`, `15.0`, `firma valida`, `Signature=adhoc`, `Sealed Resources version=2 …` (firma di Xcode, non quella automatica del linker) e `SWIFT_VERSION = 6.0`.

- [ ] **Step 6: Registro di parità**

`ApplicationIdentityTests` è verificato dallo Step 5; quattro differenze nuove in fondo alle «Differenze rispetto al C#».

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| ApplicationIdentityTests.cs | 1 | — | — | 4b | nome dell'app nei menu di sistema: `CFBundleName` del progetto Xcode |
```

**con:**

```markdown
| ApplicationIdentityTests.cs | 1 | — | — | 4b | nome dell'app nei menu di sistema: `CFBundleName` = «mjm.cleaner» in `swift/Config/Info.plist`, scritto a mano perché un `Info.plist` generato lo sostituirebbe con `PRODUCT_NAME`; verificato con `PlistBuddy` sull'app compilata (Task 2) |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Nome della categoria di una riga del passo 3 | `categories.First(c => c.Id == row.CategoryId)`: lancia se la categoria manca | `?? row.categoryId`: la riga mostra l'identificativo (irraggiungibile: le righe vengono dalle categorie analizzate) | accettata |
```

**con:**

```markdown
| Nome della categoria di una riga del passo 3 | `categories.First(c => c.Id == row.CategoryId)`: lancia se la categoria manca | `?? row.categoryId`: la riga mostra l'identificativo (irraggiungibile: le righe vengono dalle categorie analizzate) | accettata |
| Vista d'errore all'avvio | finestra separata (`FatalErrorWindow`) con «Chiudi» | vista nella finestra principale (`StartupFailureView`) con «Esci» | voluta (spec §6.2) |
| Aspetto all'avvio | applicato dopo la composizione asincrona dei servizi, prima di creare la finestra; non applicato se la composizione falliva (la `FatalErrorWindow` seguiva il sistema) | applicato in `applicationWillFinishLaunching` leggendo `settings.json` con un `SettingsStore` proprio, prima che l'ambiente esista, anche quando la composizione poi fallisce | accettata |
| Contatore «Spazio liberato» all'avvio | `await RefreshTotalAsync()` in un `async void`: un errore di lettura dello storico non era intercettato | `try? await main.refreshTotal()`: il contatore resta «—» | accettata (lato sicuro) |
| Errori intercettati all'avvio | solo `IOException`, `UnauthorizedAccessException` e `SqliteException` mostravano la `FatalErrorWindow`; gli altri chiudevano l'app | ogni errore di `AppEnvironment.live` mostra la vista d'errore | accettata (lato sicuro) |
```

- [ ] **Step 7: Commit**

```bash
git add swift/MjmCleaner.xcodeproj/project.pbxproj \
    swift/MjmCleaner.xcodeproj/xcshareddata/xcschemes/MjmCleaner.xcscheme \
    swift/Config/Base.xcconfig \
    swift/Config/Debug.xcconfig \
    swift/Config/Release.xcconfig \
    swift/Config/Info.plist \
    swift/Scripts/make-assets.py \
    swift/MjmCleaner/Assets.xcassets/AccentColor.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png \
    swift/MjmCleaner/Assets.xcassets/AppIcon.appiconset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/Contents.json \
    swift/MjmCleaner/Assets.xcassets/RiskHigh.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/RiskHighBackground.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/RiskLow.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/RiskLowBackground.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/RiskMedium.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/RiskMediumBackground.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileBuildOutput.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileDevCaches.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileDownloadsLarge.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileNeutral.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileNuGet.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileSystemCaches.colorset/Contents.json \
    swift/MjmCleaner/Assets.xcassets/TileTrash.colorset/Contents.json \
    swift/MjmCleaner/Localizable.xcstrings \
    swift/MjmCleaner/App/MjmCleanerApp.swift \
    swift/MjmCleaner/App/AppStartup.swift \
    swift/MjmCleaner/App/AppKitServices.swift \
    swift/MjmCleaner/App/StartupFailureView.swift \
    swift/MjmCleaner/Shell/MainView.swift \
    docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
feat(swift): add the Xcode project, the app startup and the AppKit adapters

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 3: ambiente demo e screenshot

Uno strumento di verifica, solo Debug: `-MJMDemo <pagina>` apre una pagina con servizi finti e dati fissi, passando dai metodi di `MainModel` come farebbe l'utente; `-MJMAppearance light|dark` sceglie l'aspetto. Lo script `screenshots.sh` compila in Debug, avvia l'app con `open` per ogni pagina e aspetto e cattura la finestra. Nessun servizio finto legge o scrive il disco: un clic su «Elimina» nella demo restituisce un resoconto inventato.

Pagine: `choose`, `scan`, `confirm`, `done`, `docker`, `docker-unavailable`, `docker-report`, `xcode`, `xcode-preview`, `xcode-report`, `history`, `settings`, `startup-failure`.

**Files:**
- Create: `swift/MjmCleaner/Demo/DemoLaunch.swift`, `DemoServices.swift`, `DemoData.swift`
- Modify: `swift/MjmCleaner/App/AppStartup.swift` (due blocchi `#if DEBUG`)
- Create: `swift/Scripts/screenshots.sh` (eseguibile), `swift/Scripts/window-id.swift`

**Interfaces:**
- Consumes: `AppStartup.show(_:)`, `.fail(_:)` (Task 2); `MainModel.showScan`, `.showConfirm`, `.showDone`, `.select`, `.showDockerReport`, `.showXcodeReport`, `.showSettings`, `.page`; `XcodeModel.initialLoad`, `.groups`, `.preview()`; i protocolli di servizio del Core (`ScanPerforming`, `CleanPerforming`, `HistoryStoring`, `SessionLogWriting`, `SettingsStoring`, `RunningAppsProbing`, `XcodeCleanupServing`) e `DockerCleanupServing`.
- Produces: `DemoLaunch.current: DemoLaunch?`, `DemoLaunch.Page` (13 pagine), `DemoLaunch.open(into:)`; `swift/Scripts/screenshots.sh <cartella> [pagina…]` che scrive `<pagina>-light.png` e `<pagina>-dark.png`. I Task 4–11 lo usano per verificare le viste.

- [ ] **Step 1: Servizi finti e dati**

**Creare `swift/MjmCleaner/Demo/DemoLaunch.swift`:**

```swift
#if DEBUG
import AppKit
import CleanerCore
import CleanerFeatures
import Foundation

/// Avvio dimostrativo per gli screenshot (spec §9.4), solo in Debug: `-MJMDemo <pagina>` apre la
/// pagina con servizi finti e dati fissi, `-MJMAppearance light|dark` sceglie l'aspetto. Nessun
/// servizio finto tocca il disco: un clic su «Elimina» restituisce un resoconto inventato.
struct DemoLaunch: Sendable {
    enum Page: String, CaseIterable, Sendable {
        case choose
        case scan
        case confirm
        case done
        case docker
        case dockerUnavailable = "docker-unavailable"
        case dockerReport = "docker-report"
        case xcode
        case xcodePreview = "xcode-preview"
        case xcodeReport = "xcode-report"
        case history
        case settings
        case startupFailure = "startup-failure"
    }

    let page: Page
    let appearance: AppearancePreference

    static let current = parse(ProcessInfo.processInfo.arguments)

    /// `-MJMDemo` fra gli argomenti, con qualunque pagina: chi lancia vuole la demo, mai l'app vera.
    static let isRequested = ProcessInfo.processInfo.arguments.contains("-MJMDemo")

    /// Il testo della vista d'errore per una pagina che `Page` non conosce.
    static var unknownPageMessage: String {
        let page = value(after: "-MJMDemo", in: ProcessInfo.processInfo.arguments) ?? "nessuna"
        let known = Page.allCases.map(\.rawValue).joined(separator: ", ")
        return "Pagina demo sconosciuta: \(page). Pagine: \(known)."
    }

    static func parse(_ arguments: [String]) -> DemoLaunch? {
        guard let page = value(after: "-MJMDemo", in: arguments).flatMap(Page.init(rawValue:)) else { return nil }
        let appearance: AppearancePreference = switch value(after: "-MJMAppearance", in: arguments) {
        case "light": .light
        case "dark": .dark
        default: .auto
        }
        return DemoLaunch(page: page, appearance: appearance)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Apre la pagina chiesta passando dai metodi di `MainModel`, come farebbe l'utente.
    @MainActor
    func open(into startup: AppStartup) {
        // In primo piano, così gli screenshot mostrano la finestra attiva.
        NSApp.activate()
        guard page != .startupFailure else {
            let denied = FileSystemError(code: EACCES, path: DemoServices.paths.databaseFile)
            startup.fail(StartupFailure.message(paths: DemoServices.paths, error: denied))
            return
        }

        let environment: AppEnvironment
        do {
            environment = try DemoServices.environment(page: page, appearance: appearance)
        } catch {
            startup.fail(StartupFailure.message(paths: DemoServices.paths, error: error))
            return
        }
        let main = MainModel(environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker())
        startup.show(main)
        let categories = environment.categories().filter { DemoData.analyzedCategoryIds.contains($0.id) }

        switch page {
        case .choose, .startupFailure:
            break
        case .scan:
            main.showScan(categories)
        case .confirm:
            main.showConfirm(categories, results: DemoData.scanResults)
        case .done:
            main.showDone(DemoData.cleanReport, journal: nil)
        case .docker, .dockerUnavailable:
            main.select(.docker)
        case .dockerReport:
            main.showDockerReport(DemoData.dockerResult, diskBefore: DemoData.diskBefore, diskAfter: DemoData.diskAfter)
        case .xcode:
            main.select(.xcode)
        case .xcodePreview:
            main.select(.xcode)
            if case .xcode(let xcode) = main.page {
                Task {
                    await xcode.initialLoad?.value
                    for row in xcode.groups.flatMap(\.rows) where DemoData.previewedXcodeKeys.contains(row.candidate.key) {
                        row.isSelected = true
                    }
                    xcode.preview()
                }
            }
        case .xcodeReport:
            main.showXcodeReport(XcodeReportModel(
                history: environment.history, sessionLog: environment.sessionLog, navigation: main,
                result: DemoData.xcodeResult, journal: nil))
        case .history:
            main.select(.history)
        case .settings:
            main.showSettings()
        }
    }
}
#endif
```

**Creare `swift/MjmCleaner/Demo/DemoServices.swift`:**

```swift
#if DEBUG
import CleanerCore
import CleanerFeatures
import Foundation
import Synchronization

/// I servizi finti dell'avvio dimostrativo: rispondono con `DemoData` e non leggono né scrivono
/// mai il disco. Lo storico e le impostazioni restano in memoria.
enum DemoServices {
    static let paths = AppPaths(supportDirectory: "/Users/demo/Library/Application Support/com.mjm.cleaner")

    static func environment(page: DemoLaunch.Page, appearance: AppearancePreference) throws -> AppEnvironment {
        var settings = CleanerSettings()
        settings.appearance = appearance
        settings.projectRoots = ["~/Progetti", "~/Lavoro/clienti"]
        settings.largeFileRoots = ["~/Downloads"]
        return AppEnvironment(
            scan: DemoScan(),
            clean: DemoClean(),
            history: DemoHistory(),
            sessionLog: DemoSessionLog(),
            settings: DemoSettings(settings),
            runningApps: DemoRunningApps(),
            docker: DemoDocker(available: page != .dockerUnavailable),
            xcode: DemoXcode(),
            paths: paths,
            clock: SystemWallClock(),
            // L'espansione di «~» è solo testo: serve alle regole delle categorie, non al disco.
            expander: try PathExpander(homeDirectory: "/Users/demo", tempDirectory: "/private/var/folders/demo/T"))
    }
}

/// Segnala l'avanzamento delle prime categorie e poi resta in analisi finché non si annulla.
private struct DemoScan: ScanPerforming {
    func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult] {
        for update in DemoData.scanProgress {
            progress?(update)
        }
        try await Task.sleep(for: .seconds(3600))
        return DemoData.scanResults
    }
}

private struct DemoClean: CleanPerforming {
    func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport {
        DemoData.cleanReport
    }
}

private final class DemoHistory: HistoryStoring {
    private let saved = Mutex<Int64>(0)

    func initialize() async throws {}

    func save(_ report: CleanReport) async throws -> Int64 {
        saved.withLock { count in
            count += 1
            return Int64(DemoData.sessions.count) + count
        }
    }

    func sessions(limit: Int) async throws -> [CleanSessionSummary] {
        Array(DemoData.sessions.prefix(limit))
    }

    func totalBytesFreed() async throws -> Int64 {
        DemoData.sessions.reduce(0) { $0 + $1.bytesFreed }
    }
}

private struct DemoSessionLog: SessionLogWriting {
    func write(sessionId: Int64, report: CleanReport) async throws {}
    func openJournal(startedAt: Date) -> PendingJournal? { nil }
    func discard(_ journal: PendingJournal) {}
}

private final class DemoSettings: SettingsStoring {
    private let current: Mutex<CleanerSettings>

    init(_ settings: CleanerSettings) {
        current = Mutex(settings)
    }

    func load() -> CleanerSettings {
        current.withLock { $0 }
    }

    func save(_ settings: CleanerSettings) throws {
        current.withLock { $0 = settings }
    }
}

private struct DemoRunningApps: RunningAppsProbing {
    func affectedApps(_ paths: [String]) async -> [String] {
        ["Google Chrome"]
    }
}

private struct DemoDocker: DockerCleanupServing {
    let available: Bool

    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        guard available else { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
        return DemoData.dockerAnalysis
    }

    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        DemoData.dockerResult
    }

    func measureDisk() async throws -> DockerDiskUsage {
        DemoData.diskAfter
    }
}

private struct DemoXcode: XcodeCleanupServing {
    func analyze() async throws -> XcodeSnapshot {
        DemoData.xcodeSnapshot
    }

    func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult {
        DemoData.xcodeResult
    }
}
#endif
```

**Creare `swift/MjmCleaner/Demo/DemoData.swift`:**

```swift
#if DEBUG
import CleanerCore
import Foundation

/// I dati fissi dell'avvio dimostrativo: plausibili, mai letti dal disco.
enum DemoData {
    private static let gigabyte: Int64 = 1_073_741_824
    private static let megabyte: Int64 = 1_048_576
    private static let startedAt = Date(timeIntervalSince1970: 1_790_000_000)

    // MARK: Pulizia

    static let analyzedCategoryIds = ["system-caches", "dev-caches", "nuget-packages", "logs"]

    static let scanProgress = [
        ScanProgress(categoryId: "system-caches", currentPath: "/Users/demo/Library/Caches/com.apple.Safari", itemsFound: 214, bytesFound: 3 * gigabyte),
        ScanProgress(categoryId: "dev-caches", currentPath: "/Users/demo/Library/Caches/org.swift.swiftpm", itemsFound: 38, bytesFound: 2 * gigabyte),
    ]

    static let scanResults = [
        result("system-caches", [
            item("/Users/demo/Library/Caches/com.apple.Safari", 1_350 * megabyte),
            item("/Users/demo/Library/Caches/com.spotify.client", 820 * megabyte),
            item("/Users/demo/Library/Caches/Google/Chrome", 640 * megabyte),
        ]),
        result("dev-caches", [
            item("/Users/demo/Library/Caches/org.swift.swiftpm", 1_100 * megabyte),
            item("/Users/demo/.npm/_cacache", 730 * megabyte),
        ]),
        result("nuget-packages", [
            item("/Users/demo/.nuget/packages/newtonsoft.json/12.0.3", 18 * megabyte),
        ]),
        result("logs", [
            item("/Users/demo/Library/Logs/DiagnosticReports", 96 * megabyte),
        ]),
    ]

    static let cleanReport = CleanReport(
        startedAt: startedAt,
        duration: .seconds(12),
        bytesFreed: 4_754 * megabyte,
        itemsDeleted: 7,
        itemsFailed: 1,
        categories: [
            CategoryCleanResult(categoryId: "system-caches", bytesFreed: 2_810 * megabyte, itemsDeleted: 3),
            CategoryCleanResult(categoryId: "dev-caches", bytesFreed: 1_830 * megabyte, itemsDeleted: 2),
            CategoryCleanResult(categoryId: "logs", bytesFreed: 96 * megabyte, itemsDeleted: 1),
            CategoryCleanResult(categoryId: "nuget-packages", bytesFreed: 18 * megabyte, itemsDeleted: 1),
        ],
        errors: [ScanError(path: "/Users/demo/Library/Caches/com.apple.Safari/WebKit", kind: .inUse, message: "risorsa occupata")],
        deletedPaths: [])

    static let sessions = [
        CleanSessionSummary(
            id: 3, startedAt: startedAt, duration: .seconds(12), bytesFreed: 4_754 * megabyte, itemsDeleted: 7, itemsFailed: 1,
            categories: cleanReport.categories),
        CleanSessionSummary(
            id: 2, startedAt: startedAt.addingTimeInterval(-6 * 86_400), duration: .seconds(40), bytesFreed: 3 * gigabyte, itemsDeleted: 2_117, itemsFailed: 0,
            categories: [
                CategoryCleanResult(categoryId: "project-build-output", bytesFreed: 2 * gigabyte, itemsDeleted: 2_100),
                CategoryCleanResult(categoryId: "trash", bytesFreed: gigabyte, itemsDeleted: 17),
            ]),
        CleanSessionSummary(
            id: 1, startedAt: startedAt.addingTimeInterval(-20 * 86_400), duration: .seconds(5), bytesFreed: 1_843 * megabyte, itemsDeleted: 3, itemsFailed: 0,
            categories: [
                CategoryCleanResult(categoryId: DockerCategories.images, bytesFreed: 1_200 * megabyte, itemsDeleted: 2),
                CategoryCleanResult(categoryId: DockerCategories.buildCache, bytesFreed: 643 * megabyte, itemsDeleted: 1),
            ]),
    ]

    // MARK: Docker

    static let diskBefore = DockerDiskUsage(path: "/Users/demo/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", allocatedBytes: 24 * gigabyte, apparentBytes: 64 * gigabyte)
    static let diskAfter = DockerDiskUsage(path: diskBefore.path, allocatedBytes: 24 * gigabyte, apparentBytes: 64 * gigabyte)

    static let dockerAnalysis = DockerAnalysis(
        serverVersion: "27.3.1",
        snapshot: DockerSnapshot(
            containers: [], images: [], volumes: [],
            df: DockerDfSummary(entries: [
                DockerDfEntry(type: DockerDfSummary.imagesType, sizeBytes: 14 * gigabyte, reclaimableBytes: 9 * gigabyte),
                DockerDfEntry(type: DockerDfSummary.volumesType, sizeBytes: 3 * gigabyte, reclaimableBytes: 2 * gigabyte),
                DockerDfEntry(type: DockerDfSummary.buildCacheType, sizeBytes: 2 * gigabyte, reclaimableBytes: 2 * gigabyte),
            ]),
            existingComposeProjects: []),
        candidates: [
            docker(.image, "sha256:4f1c", "<none>:<none>", 1_200 * megabyte, .delete, "dangling", "Immagine dangling: nessun tag la nomina."),
            docker(.buildCache, "build-cache", "cache di build", 2 * gigabyte, .delete, "build-cache", "Cache di build: si rigenera alla prossima build."),
            docker(.image, "sha256:9a2b", "shop-api:dev", 850 * megabyte, .ask, "local-build", "Costruita in locale dal Dockerfile di ~/Progetti/shop."),
            docker(.image, "sha256:77c0", "postgres:15", 412 * megabyte, .propose, "unused-image", "Nessun container la usa.", cost: "riscaricarla"),
            docker(.volume, "a1b2c3d4", "a1b2c3d4", 300 * megabyte, .propose, "anonymous-unused", "Volume anonimo non montato."),
            docker(.volume, "shop_pgdata", "shop_pgdata", 1_100 * megabyte, .propose, "named-unused", "Nessuna regola lo riconduce a un progetto."),
            docker(.image, "sha256:c3d4", "redis:7", 140 * megabyte, .keep, "in-use", "In uso da un container."),
        ],
        disk: diskBefore)

    static let dockerResult = DockerCleanResult(
        report: CleanReport(
            startedAt: startedAt, duration: .seconds(9), bytesFreed: 3_200 * megabyte, itemsDeleted: 2, itemsFailed: 1,
            categories: [], errors: [ScanError(path: "docker:image:sha256:9a2b", kind: .inUse, message: "image is being used by a stopped container")],
            deletedPaths: ["docker:image:sha256:4f1c (<none>:<none>)", "docker:build-cache"]),
        before: dockerAnalysis.snapshot.df,
        after: DockerDfSummary(entries: [
            DockerDfEntry(type: DockerDfSummary.imagesType, sizeBytes: 12 * gigabyte, reclaimableBytes: 7 * gigabyte),
        ]),
        daemonLost: false)

    // MARK: Xcode

    /// Il runtime usato da un dispositivo che resta: l'anteprima mostra la presa d'atto. Le cartelle
    /// (DerivedData, Device Support) non entrano nell'anteprima demo, che non ha l'inventario dei file.
    static let previewedXcodeKeys = [runtime.key]

    private static let shopDerivedData = XcodeCandidate(
        key: "DerivedData/ShopApp", kind: .derivedData, name: "ShopApp-abcdefgh",
        path: "/Users/demo/Library/Developer/Xcode/DerivedData/ShopApp-abcdefgh", sizeBytes: 3 * gigabyte)
    private static let widgetsDerivedData = XcodeCandidate(
        key: "DerivedData/Widgets", kind: .derivedData, name: "Widgets-ijklmnop",
        path: "/Users/demo/Library/Developer/Xcode/DerivedData/Widgets-ijklmnop", sizeBytes: 900 * megabyte)
    private static let deviceSupport = XcodeCandidate(
        key: "DeviceSupport/17.4", kind: .deviceSupport, name: "iOS 17.4 (21E219)",
        path: "/Users/demo/Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)", sizeBytes: 4 * gigabyte)
    private static let iPhone = XcodeCandidate(
        key: "8C1F0B6E-0000-4000-8000-000000000001", kind: .device, name: "iPhone 15",
        cliId: "8C1F0B6E-0000-4000-8000-000000000001", state: "Shutdown", sizeBytes: 2 * gigabyte)
    private static let iPad = XcodeCandidate(
        key: "2A7E0B6E-0000-4000-8000-000000000002", kind: .device, name: "iPad Air",
        cliId: "2A7E0B6E-0000-4000-8000-000000000002", state: "Booted", sizeBytes: 1_500 * megabyte,
        blockReason: "In esecuzione: chiudilo per eliminarlo.")
    private static let runtime = XcodeCandidate(
        key: "runtime:5D1E0B6E-0000-4000-8000-000000000003", kind: .runtime, name: "iOS 17.4",
        cliId: "5D1E0B6E-0000-4000-8000-000000000003", sizeBytes: 7 * gigabyte,
        dependencies: ["8C1F0B6E-0000-4000-8000-000000000001"])

    static let xcodeSnapshot = XcodeSnapshot(
        candidates: [shopDerivedData, widgetsDerivedData, deviceSupport, iPhone, iPad, runtime],
        warnings: [])

    static let xcodeResult = XcodeCleanResult(
        historyReport: CleanReport(
            startedAt: startedAt, duration: .seconds(31), bytesFreed: 10 * gigabyte, itemsDeleted: 2, itemsFailed: 0,
            categories: [], errors: [], deletedPaths: []),
        items: [
            XcodeItemResult(candidate: shopDerivedData, outcome: .deleted, reason: "Cartella eliminata.", verifiedEstimatedBytes: 3 * gigabyte),
            XcodeItemResult(candidate: runtime, outcome: .deleted, reason: "Runtime rimosso da simctl.", verifiedEstimatedBytes: 7 * gigabyte),
            XcodeItemResult(candidate: iPad, outcome: .skipped, reason: "In esecuzione: chiudilo per eliminarlo.", verifiedEstimatedBytes: nil),
        ],
        freeBytesBefore: 120 * gigabyte,
        freeBytesAfter: 131 * gigabyte,
        warnings: [])

    // MARK: Costruttori

    private static func item(_ path: String, _ size: Int64) -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: true, declaredRoot: path)
    }

    private static func result(_ categoryId: String, _ items: [ScanItem]) -> CategoryScanResult {
        CategoryScanResult(
            categoryId: categoryId, items: items, totalBytes: items.reduce(0) { $0 + $1.sizeBytes },
            errors: [], exclusions: [])
    }

    private static func docker(
        _ kind: DockerResourceKind, _ id: String, _ name: String, _ size: Int64, _ verdict: DockerVerdict,
        _ rule: String, _ reason: String, cost: String = ""
    ) -> DockerCandidate {
        DockerCandidate(kind: kind, id: id, displayName: name, sizeBytes: size, verdict: verdict, ruleId: rule, reason: reason, cost: cost)
    }
}
#endif
```

- [ ] **Step 2: Collegare la demo all'avvio**

**In `swift/MjmCleaner/App/AppStartup.swift`, sostituire:**

```swift
    static func savedAppearance() -> AppearancePreference {
        SettingsStore(fileSystem: LocalFileSystem(), paths: paths).load().appearance
    }
```

**con:**

```swift
    static func savedAppearance() -> AppearancePreference {
        #if DEBUG
        if let demo = DemoLaunch.current { return demo.appearance }
        // Una pagina demo sconosciuta non legge le impostazioni vere: `start()` la rifiuta.
        if DemoLaunch.isRequested { return .auto }
        #endif
        return SettingsStore(fileSystem: LocalFileSystem(), paths: paths).load().appearance
    }
```

**In `swift/MjmCleaner/App/AppStartup.swift`, sostituire:**

```swift
        started = true

        let paths = Self.paths
```

**con:**

```swift
        started = true

        #if DEBUG
        if let demo = DemoLaunch.current {
            demo.open(into: self)
            return
        }
        // Chi chiede la demo non ottiene mai l'app vera, nemmeno con una pagina che non esiste.
        if DemoLaunch.isRequested {
            fail(DemoLaunch.unknownPageMessage)
            return
        }
        #endif

        let paths = Self.paths
```

- [ ] **Step 3: Script degli screenshot**

L'app si avvia con `open -n` (LaunchServices): come processo figlio della shell non riceverebbe finestre. `window-id` trova la finestra in primo piano del processo (uno sheet aperto viene catturato con la sua finestra). Lo script non avvia mai l'app vera: rifiuta le pagine che `DemoLaunch.Page` non conosce (uscita 2) e controlla che la demo sia nel binario Debug (uscita 1); chiude l'app anche se si interrompe ed esce con 1 se una cattura non riesce o se la finestra non è in primo piano (Mac in uso). Anche l'app rifiuta una pagina sconosciuta: con `-MJMDemo` mostra la vista d'errore e non diventa mai l'app vera.

**Creare `swift/Scripts/window-id.swift`:**

```swift
import CoreGraphics
import Foundation

// Stampa l'identificativo della finestra in primo piano del processo indicato (uno sheet aperto
// viene prima della sua finestra), attendendo che compaia per al massimo <secondi>.
// Uso: window-id <pid> <secondi>

let arguments = CommandLine.arguments
guard arguments.count == 3, let pid = Int(arguments[1]), let seconds = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("uso: window-id <pid> <secondi>\n".utf8))
    exit(2)
}

let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let front = windows.first { window in
        window[kCGWindowOwnerPID as String] as? Int == pid && window[kCGWindowLayer as String] as? Int == 0
    }
    if let id = front?[kCGWindowNumber as String] as? Int {
        print(id)
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.2)
}
exit(1)
```

**Creare `swift/Scripts/screenshots.sh`:**

```zsh
#!/bin/zsh
# Screenshot delle pagine dell'avvio dimostrativo (solo Debug), in chiaro e in scuro (spec §9.4).
# Uso: swift/Scripts/screenshots.sh <cartella di uscita> [pagina…]
# Senza pagine le cattura tutte. Durante la cattura si aprono e si chiudono finestre dell'app: non
# usare il Mac finché lo script non finisce (con Claude in primo piano), perché ogni finestra prende il
# primo piano e i tasti premuti finirebbero nella demo.
# Esce con 1 se una cattura non riesce (schermo bloccato o spento, oppure Mac in uso: una finestra
# che non arriva in primo piano non si cattura).
set -euo pipefail

here=${0:A:h}
project=${here:h}/MjmCleaner.xcodeproj
out=${1:?"uso: screenshots.sh <cartella di uscita> [pagina…]"}
shift

# Le pagine di `DemoLaunch.Page`. Con una pagina sconosciuta l'app partirebbe senza la demo, cioè
# con i dati veri dell'utente: si rifiuta prima di avviare qualunque cosa.
all=(choose scan confirm done docker docker-unavailable docker-report xcode xcode-preview xcode-report history settings startup-failure)
if (( $# )); then
    pages=("$@")
else
    pages=($all)
fi
for page in $pages; do
    if (( ! ${all[(Ie)$page]} )); then
        print -u2 "pagina demo sconosciuta: $page"
        exit 2
    fi
done

# Percorso risolto (/private/var/…): `pgrep -f` lo confronta con quello del processo avviato.
build=${${TMPDIR:-/tmp}:A}/mjm-cleaner-screenshots

mkdir -p "$out" "$build"
xcodebuild -project "$project" -scheme MjmCleaner -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$build" -quiet build
swiftc -O "$here/window-id.swift" -o "$build/window-id"
bundle="$build/Build/Products/Debug/MjmCleaner.app"
binary="$bundle/Contents/MacOS/MjmCleaner"

# Senza la demo nel binario (un Debug senza la condizione DEBUG) ogni avvio sarebbe l'app vera.
demo=0
for file in "$binary" "$binary.debug.dylib"; do
    if [[ -f $file ]] && (( $(strings "$file" | grep -c MJMDemo || true) > 0 )); then
        demo=1
    fi
done
if (( ! demo )); then
    print -u2 "la demo non è nel binario Debug: nessuno screenshot"
    exit 1
fi

# Il pid dell'app in primo piano; `lsappinfo` legge soltanto, non attiva nulla.
front_pid() {
    local info
    info=$(lsappinfo info -only pid "$(lsappinfo front)" 2>/dev/null) || return 1
    [[ $info =~ 'pid = ([0-9]+)' ]] && print -r -- $match[1]
}

# L'app aperta si chiude anche se lo script si interrompe (Ctrl-C compreso) o se `pgrep` non l'ha
# trovata: `pkill` cerca il binario di questa build, mai l'app installata.
pid=""
trap 'pkill -f "$binary" 2>/dev/null; true' EXIT
trap 'exit 130' INT TERM

failed=0
for page in $pages; do
    for appearance in light dark; do
        # `open` avvia l'app da LaunchServices, come il Finder: un processo figlio di questa shell
        # potrebbe non ricevere finestre.
        # `-ApplePersistenceIgnoreState`: la finestra si apre alla misura predefinita, non a quella salvata.
        open -n "$bundle" --args -MJMDemo "$page" -MJMAppearance "$appearance" -ApplePersistenceIgnoreState YES
        # Il tempo per caricare la pagina e, per le Impostazioni, aprire lo sheet.
        sleep 3
        pid=$(pgrep -n -f "$binary" || true)
        if [[ -n $pid ]] && id=$("$build/window-id" "$pid" 10); then
            # Con il Mac in uso macOS non porta l'app davanti (attivazione cooperativa): la finestra
            # inattiva ha i pulsanti in tinta grigi e non vale come base del confronto.
            if [[ $(front_pid || true) != "$pid" ]]; then
                print -u2 "finestra non attiva per $page ($appearance): il Mac è in uso? nessuna cattura"
                failed=1
            elif screencapture -x -o -l"$id" "$out/$page-$appearance.png"; then
                print "$out/$page-$appearance.png"
            else
                print -u2 "cattura non riuscita per $page ($appearance): lo schermo è bloccato o spento?"
                failed=1
            fi
        else
            print -u2 "nessuna finestra per $page ($appearance)"
            failed=1
        fi
        pkill -f "$binary" 2>/dev/null || true
        pid=""
        sleep 1
    done
done
exit $failed
```

```bash
# passo di generazione
chmod +x swift/Scripts/screenshots.sh
```

- [ ] **Step 4: Build e prima cattura**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" choose startup-failure
```

Poi una pagina sconosciuta, che non deve avviare niente:

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" chose; echo "uscita $?"
```

Expected: `pagina demo sconosciuta: chose` e `uscita 2`, nessuna build e nessuna finestra.

Expected della cattura: quattro percorsi stampati (`choose-light.png`, `choose-dark.png`, `startup-failure-light.png`, `startup-failure-dark.png`), nessun «nessuna finestra per …» né «cattura non riuscita…», uscita 0 (con lo schermo bloccato o spento ogni cattura non riesce e lo script esce con 1: va rifatto a schermo sbloccato). Durante la cattura si aprono e si chiudono finestre dell'app. Negli screenshot di `choose` la finestra provvisoria mostra al centro il contatore della demo, «9,4 GB»; in quelli di `startup-failure` compaiono «Impossibile accedere ai dati dell'applicazione», «Percorso: /Users/demo/Library/Application Support/com.mjm.cleaner», «Motivo: Permission denied» e il pulsante «Esci», in chiaro e in scuro.

- [ ] **Step 5: La demo non entra nel Release**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-release" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-release.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-release.log"
strings "${TMPDIR:-/tmp}/mjm-cleaner-release/Build/Products/Release/MjmCleaner.app/Contents/MacOS/MjmCleaner" | grep -c -E 'MJMDemo|Demo[A-Z]|/Users/demo' || true
strings "${TMPDIR:-/tmp}/mjm-cleaner-build/Build/Products/Debug/MjmCleaner.app/Contents/MacOS/MjmCleaner.debug.dylib" | grep -c -E 'MJMDemo|Demo[A-Z]|/Users/demo' || true
grep -nE 'LocalFileSystem|SettingsStore|HistoryStore|SessionLogWriter|CleanEngine|ScanEngine|RuleScanner|ProcessRunner|AppEnvironment\.live|AppStartup\.paths'     swift/MjmCleaner/Demo/*.swift || echo "la demo non usa servizi su disco"
```

Expected: `** BUILD SUCCEEDED **`, poi `0` (Release, nessuna traccia della demo: né i nomi dei tipi, né le classi dei servizi finti, né i dati sotto `/Users/demo`), un numero maggiore di zero (Debug: il controllo trova davvero le stringhe quando ci sono) e `la demo non usa servizi su disco`.

- [ ] **Step 6: Commit**

Nessuna riga nel registro: la demo è uno strumento di verifica, non un comportamento dell'app (il metodo di verifica delle viste entra nel registro con il Task 11).

```bash
git add swift/MjmCleaner/Demo/DemoLaunch.swift \
    swift/MjmCleaner/Demo/DemoServices.swift \
    swift/MjmCleaner/Demo/DemoData.swift \
    swift/MjmCleaner/App/AppStartup.swift \
    swift/Scripts/screenshots.sh \
    swift/Scripts/window-id.swift
git commit -F - <<'MSG'
feat(swift): add the debug demo environment and the screenshot script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 4: finestra principale, sidebar e indicatore dei passi

La `MainView` vera: `NavigationSplitView` con la sidebar (spec §6.2) e la pagina corrente. La voce selezionata si ricava da `main.section`; scegliere una voce chiama `main.select(_:)`, che rifiuta il cambio mentre Xcode elimina; la lista è anche disabilitata con `canNavigateGlobally`. In fondo alla sidebar: la card «Spazio liberato» e «Impostazioni… ⌘,», disabilitato con `canShowSettings`. I passi del wizard hanno in toolbar «Pulizia», «Passo N di 4» e l'indicatore, dal passo di `PageKind.wizardStep` (Task 1). Le pagine sono provvisorie (`PendingPages.swift`) fino ai Task 5–10, che le sostituiscono una alla volta.

`PageComponents.swift` contiene i pezzi condivisi dalle pagine: barra azioni, card, intestazione, avviso, testo facoltativo e `CollapsibleCard`. Nelle fasce in basso (`safeAreaInset`) i testi non usano `fixedSize` verticale: rompe il layout della finestra (Fatti misurati).

**Files:**
- Modify (sostituzione completa): `swift/MjmCleaner/Shell/MainView.swift`
- Create: `swift/MjmCleaner/Shell/SidebarView.swift`, `StepIndicator.swift`, `PageComponents.swift`, `PendingPages.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: `MainModel.page`, `.section`, `.select(_:)`, `.canNavigateGlobally`, `.totalFreedAmount`, `.showSettings()`, `.canShowSettings`, `.settings`; `SettingsModel.cancel()`; `Page`, `PageKind.wizardStep` (Task 1), `SidebarSection.allCases`.
- Produces: `PageView(page:)`, `WizardChrome(step:)`, `SidebarView(main:)`, `StepIndicator(current:)`, `ActionBar`, `View.actionBar(_:)`, `View.card(padding:)`, `PageHeader(title:subtitle:)`, `Banner(text:emphasized:)`, `OptionalText(text:style:)`, `CollapsibleCard(items:isExpanded:label:header:row:)`; le pagine provvisorie `ChooseStepView(model:)` … `SettingsView(model:)`, con gli stessi nomi e inizializzatori delle viste vere dei Task 5–10.

- [ ] **Step 1: Finestra principale e sidebar**

**Sostituire l'intero contenuto di `swift/MjmCleaner/Shell/MainView.swift` con:**

```swift
import CleanerFeatures
import SwiftUI

/// `MainWindow`: la sidebar e la pagina corrente (spec §6.2, §6.3). Lo sheet delle Impostazioni
/// esiste finché `main.settings` non è `nil`.
struct MainView: View {
    let main: MainModel

    var body: some View {
        NavigationSplitView {
            SidebarView(main: main)
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        } detail: {
            PageView(page: main.page)
        }
        .sheet(item: settingsSheet) { settings in
            SettingsView(model: settings)
        }
    }

    /// Se lo sheet lo chiude il sistema (Esc), vale come Annulla: torna l'aspetto di prima
    /// (`ClosingTheWindowRestoresTheAppearance`). Salva e Annulla azzerano già `main.settings`.
    private var settingsSheet: Binding<SettingsModel?> {
        Binding(get: { main.settings }, set: { if $0 == nil { main.settings?.cancel() } })
    }
}

/// La pagina corrente. Ogni modello ha la propria identità: una pagina nuova dello stesso tipo
/// (Docker riselezionato, un nuovo ciclo del wizard) riparte con lo stato della vista azzerato.
struct PageView: View {
    let page: Page

    var body: some View {
        content
            .modifier(WizardChrome(step: page.kind.wizardStep))
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .choose(let model): ChooseStepView(model: model).id(ObjectIdentifier(model))
        case .scan(let model): ScanStepView(model: model).id(ObjectIdentifier(model))
        case .confirm(let model): ConfirmStepView(model: model).id(ObjectIdentifier(model))
        case .done(let model): DoneStepView(model: model).id(ObjectIdentifier(model))
        case .docker(let model): DockerView(model: model).id(ObjectIdentifier(model))
        case .dockerReport(let model): DockerReportView(model: model).id(ObjectIdentifier(model))
        case .xcode(let model): XcodeView(model: model).id(ObjectIdentifier(model))
        case .xcodeReport(let model): XcodeReportView(model: model).id(ObjectIdentifier(model))
        case .history(let model): HistoryView(model: model).id(ObjectIdentifier(model))
        }
    }
}

/// La toolbar dei quattro passi del wizard: «Pulizia», «Passo N di 4» e l'indicatore.
struct WizardChrome: ViewModifier {
    let step: Int?

    func body(content: Content) -> some View {
        if let step {
            content
                .navigationTitle("Pulizia")
                .navigationSubtitle("Passo \(String(step)) di 4")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        StepIndicator(current: step)
                    }
                }
        } else {
            content
        }
    }
}
```

**Creare `swift/MjmCleaner/Shell/SidebarView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// La sidebar (spec §6.2): Pulizia · Docker · Xcode · Storico, poi in fondo il contatore «Spazio
/// liberato» e «Impostazioni… ⌘,». La voce selezionata si ricava dalla pagina; mentre Xcode
/// elimina la lista è disabilitata e il modello rifiuta comunque il cambio di pagina.
struct SidebarView: View {
    let main: MainModel

    var body: some View {
        List(selection: selection) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
        }
        .disabled(!main.canNavigateGlobally)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                FreedSpaceCard(amount: main.totalFreedAmount)
                Button(action: main.showSettings) {
                    HStack {
                        Label("Impostazioni…", systemImage: "gearshape")
                        Spacer()
                        Text(verbatim: "⌘,")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                // Il nome del C#, senza la scorciatoia scritta accanto.
                .accessibilityLabel("Impostazioni…")
                .disabled(!main.canShowSettings)
            }
            .padding(12)
        }
    }

    private var selection: Binding<SidebarSection?> {
        Binding(get: { main.section }, set: { if let section = $0 { main.select(section) } })
    }
}

/// La card «Spazio liberato» in fondo alla sidebar.
private struct FreedSpaceCard: View {
    let amount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spazio liberato")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            Text("liberati finora")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

extension SidebarSection {
    var title: LocalizedStringKey {
        switch self {
        case .cleanup: "Pulizia"
        case .docker: "Docker"
        case .xcode: "Xcode"
        case .history: "Storico"
        }
    }

    var symbolName: String {
        switch self {
        case .cleanup: "sparkles"
        case .docker: "cube"
        case .xcode: "hammer"
        case .history: "clock"
        }
    }
}
```

**Creare `swift/MjmCleaner/Shell/StepIndicator.swift`:**

```swift
import SwiftUI

/// L'indicatore dei quattro passi del wizard: cerchio pieno sul passo corrente.
struct StepIndicator: View {
    let current: Int

    private static let labels: [LocalizedStringKey] = ["Scegli", "Analizza", "Conferma", "Fatto"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.labels.enumerated()), id: \.offset) { index, label in
                if index > 0 {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 18, height: 1)
                }
                step(index + 1, label)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Avanzamento")
    }

    private func step(_ number: Int, _ label: LocalizedStringKey) -> some View {
        let isCurrent = number == current
        return HStack(spacing: 6) {
            Text(verbatim: String(number))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .background {
                    if isCurrent {
                        Circle().fill(Color.accentColor)
                    } else {
                        Circle().strokeBorder(.separator)
                    }
                }
            Text(label)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }
}
```

**Creare `swift/MjmCleaner/Shell/PageComponents.swift`:**

```swift
import SwiftUI

/// La barra azioni in fondo alla pagina (spec §6.2): resta visibile qualunque sia l'altezza del
/// contenuto, perché sta nell'area sicura e non nello scorrimento.
struct ActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension View {
    func actionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar(content: content)
        }
    }

    /// Una card: superficie dei controlli, angoli 10, contorno sottile.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }
}

/// Titolo e sottotitolo in testa alla pagina.
struct PageHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// L'avviso in evidenza («Eliminazione definitiva…», Docker fermato, Purge).
struct Banner: View {
    let text: String
    var emphasized = true

    var body: some View {
        Label {
            Text(text)
                .fontWeight(emphasized ? .semibold : .regular)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Un testo che compare solo se non è vuoto.
struct OptionalText: View {
    let text: String
    var style: Style = .secondary

    enum Style {
        case secondary
        case danger
    }

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.callout)
                .foregroundStyle(style == .danger ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Un gruppo richiudibile in una card, con le righe in uno scorrimento proprio alto al più 360
/// punti: come il `ListBox` del C#, anche una categoria con migliaia di voci crea solo le righe
/// visibili.
struct CollapsibleCard<Title: View, Header: View, Row: View, Item: Identifiable>: View {
    let items: [Item]
    @Binding var isExpanded: Bool
    @ViewBuilder let label: () -> Title
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                header()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        } label: {
            label()
        }
        .card(padding: 12)
    }
}
```

- [ ] **Step 2: Pagine provvisorie**

**Creare `swift/MjmCleaner/Shell/PendingPages.swift`:**

```swift
import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct ChooseStepView: View {
    let model: ChooseStepModel

    var body: some View {
        Text(verbatim: "Scegli")
    }
}

struct ScanStepView: View {
    let model: ScanStepModel

    var body: some View {
        Text(verbatim: "Analizza")
    }
}

struct ConfirmStepView: View {
    let model: ConfirmStepModel

    var body: some View {
        Text(verbatim: "Conferma")
    }
}

struct DoneStepView: View {
    let model: DoneStepModel

    var body: some View {
        Text(verbatim: "Fatto")
    }
}

struct DockerView: View {
    let model: DockerModel

    var body: some View {
        Text(verbatim: "Docker")
    }
}

struct DockerReportView: View {
    let model: DockerReportModel

    var body: some View {
        Text(verbatim: "Resoconto Docker")
    }
}

struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        Text(verbatim: "Xcode")
    }
}

struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        Text(verbatim: "Resoconto Xcode")
    }
}

struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        Text(verbatim: "Storico")
    }
}

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" choose history settings
```

Expected: sei file. Sidebar con Pulizia, Docker, Xcode e Storico (voce selezionata: Pulizia in `choose` e in `settings`, Storico in `history`), card «Spazio liberato» con «9,4 GB» e «liberati finora», «Impostazioni… ⌘,» in fondo. In `choose` la toolbar mostra «Pulizia», «Passo 1 di 4» e l'indicatore con il passo 1 pieno; il contenuto è il testo provvisorio «Scegli». In `history` la toolbar non ha l'indicatore e il contenuto è «Storico». In `settings` sopra la finestra c'è uno sheet con «Impostazioni».

- [ ] **Step 4: Registro di parità**

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Errori intercettati all'avvio | solo `IOException`, `UnauthorizedAccessException` e `SqliteException` mostravano la `FatalErrorWindow`; gli altri chiudevano l'app | ogni errore di `AppEnvironment.live` mostra la vista d'errore | accettata (lato sicuro) |
```

**con:**

```markdown
| Errori intercettati all'avvio | solo `IOException`, `UnauthorizedAccessException` e `SqliteException` mostravano la `FatalErrorWindow`; gli altri chiudevano l'app | ogni errore di `AppEnvironment.live` mostra la vista d'errore | accettata (lato sicuro) |
| Riselezione della voce corrente nella sidebar | un clic su Docker, Xcode o Storico già selezionati ricreava la pagina | `List(selection:)` non notifica una selezione invariata: la pagina resta (si ricarica con «Riprova», «Riprova analisi» o «Nuova analisi») | accettata |
```

- [ ] **Step 5: Commit**

```bash
git add swift/MjmCleaner/Shell/MainView.swift \
    swift/MjmCleaner/Shell/SidebarView.swift \
    swift/MjmCleaner/Shell/StepIndicator.swift \
    swift/MjmCleaner/Shell/PageComponents.swift \
    swift/MjmCleaner/Shell/PendingPages.swift \
    docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
feat(swift): build the main window with the sidebar and the step indicator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 5: wizard, passi 1 e 2 (Scegli e Analizza)

Il passo 1 (`ChooseStepView`): una card con le categorie, ogni riga con casella, tile, nome e descrizione, pill di rischio; tutta la riga commuta la casella e «Pacchetti NuGet inutilizzati» è una riga figlia indentata con il separatore che rientra di più. Barra azioni: scudo, «L'analisi non elimina alcun file.», il contatore e «Analizza ›», disabilitato senza selezione (`analyze()` ripete la guardia). Il passo 2 (`ScanStepView`): l'analisi per categoria, il percorso corrente e «Annulla», oppure «Torna al passo 1» dopo un errore. Tile e pill leggono i colori del catalogo asset (Task 2).

**Files:**
- Create: `swift/MjmCleaner/Cleanup/CategoryBadges.swift`
- Create: `swift/MjmCleaner/Cleanup/ChooseStepView.swift`
- Create: `swift/MjmCleaner/Cleanup/ScanStepView.swift`
- Modify (sostituzione completa): `swift/MjmCleaner/Shell/PendingPages.swift` (tolte `ChooseStepView`, `ScanStepView`)

**Interfaces:**
- Consumes: `ChooseStepModel` (`choices`, `selectedCountText`, `canAnalyze`, `analyze()`), `CategoryChoice` (`isSelected`, `showSeparator`, `isChild`, `displayName`, `description`, `risk`, `visual`), `CategoryVisual` (`tileColorName`, `symbolName`), `RiskLevel.label`/`.colorName`, `ScanStepModel` (`progress`, `currentPath`, `isRunning`, `errorText`, `hasError`, `cancel()`, `backToStart()`); `PageHeader`, `View.card`, `View.actionBar`, `OptionalText` (Task 4).
- Produces: `CategoryTile(visual:)`, `RiskPill(risk:)`, `TrailingIconLabelStyle`, `ChooseStepView(model:)`, `ScanStepView(model:)`.

- [ ] **Step 1: Viste**

**Creare `swift/MjmCleaner/Cleanup/CategoryBadges.swift`:**

```swift
import CleanerCore
import CleanerFeatures
import SwiftUI

/// La tile 28×28 di una categoria: colore dal catalogo asset, simbolo bianco (spec §6.4).
struct CategoryTile: View {
    let visual: CategoryVisual

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(visual.tileColorName))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: visual.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// La pill del rischio: il livello resta scritto, non solo colorato (spec §6.6).
struct RiskPill: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(risk.colorName))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(risk.colorName + "Background"), in: Capsule())
    }
}
```

**Creare `swift/MjmCleaner/Cleanup/ChooseStepView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Passo 1 (`ChooseStepView`): le categorie da analizzare. Tutta la riga commuta la casella;
/// «Pacchetti NuGet inutilizzati» è una riga figlia indentata.
struct ChooseStepView: View {
    let model: ChooseStepModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    title: "Cosa vuoi pulire?",
                    subtitle: String(localized: "Seleziona solo ciò che vuoi analizzare. Vedrai ogni elemento prima della rimozione."))
                VStack(spacing: 0) {
                    ForEach(model.choices) { choice in
                        if choice.showSeparator {
                            Divider()
                                .padding(.leading, choice.isChild ? 116 : 72)
                        }
                        ChoiceRow(choice: choice)
                    }
                }
                .card(padding: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .actionBar {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("L'analisi non elimina alcun file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.selectedCountText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(action: model.analyze) {
                Label("Analizza", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canAnalyze)
        }
    }
}

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

/// «Analizza ›»: il testo prima, la freccia dopo.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
```

**Creare `swift/MjmCleaner/Cleanup/ScanStepView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Passo 2 (`ScanStepView`): l'analisi in corso, categoria per categoria. Nessun file viene toccato.
struct ScanStepView: View {
    let model: ScanStepModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Analisi in corso…")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stiamo controllando le categorie selezionate.")
                        .fontWeight(.semibold)
                    if model.isRunning {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(model.currentPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    OptionalText(text: model.errorText, style: .danger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text("CATEGORIE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(Array(model.progress.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        HStack {
                            Text(row.displayName)
                            Spacer()
                            Text(row.status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    }
                }
                .card(padding: 0)
                Text("Nessun file è stato ancora toccato.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .actionBar {
            Spacer()
            if model.hasError {
                Button("Torna al passo 1", action: model.backToStart)
            } else {
                Button("Annulla", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
```

- [ ] **Step 2: Togliere le pagine provvisorie sostituite**

**Sostituire l'intero contenuto di `swift/MjmCleaner/Shell/PendingPages.swift` con:**

```swift
import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct ConfirmStepView: View {
    let model: ConfirmStepModel

    var body: some View {
        Text(verbatim: "Conferma")
    }
}

struct DoneStepView: View {
    let model: DoneStepModel

    var body: some View {
        Text(verbatim: "Fatto")
    }
}

struct DockerView: View {
    let model: DockerModel

    var body: some View {
        Text(verbatim: "Docker")
    }
}

struct DockerReportView: View {
    let model: DockerReportModel

    var body: some View {
        Text(verbatim: "Resoconto Docker")
    }
}

struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        Text(verbatim: "Xcode")
    }
}

struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        Text(verbatim: "Resoconto Xcode")
    }
}

struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        Text(verbatim: "Storico")
    }
}

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" choose scan
```

Expected: quattro file. `choose`: «Cosa vuoi pulire?» e il sottotitolo, sette righe con tile colorate e pill «Rischio medio»/«Rischio basso»/«Rischio alto», «Pacchetti NuGet inutilizzati» rientrata sotto «Cache di sviluppo», quattro caselle spuntate (selezione predefinita), barra azioni con «4 categorie selezionate» e «Analizza ›» blu. `scan`: «Analisi in corso…», barra d'avanzamento, il percorso `/Users/demo/Library/Caches/org.swift.swiftpm`, le categorie con «in corso…» o «in attesa», «Nessun file è stato ancora toccato.» e «Annulla»; toolbar con il passo 2 pieno. In scuro le pill hanno testo chiaro su fondo scuro.

- [ ] **Step 4: Commit**

```bash
git add swift/MjmCleaner/Cleanup/CategoryBadges.swift \
    swift/MjmCleaner/Cleanup/ChooseStepView.swift \
    swift/MjmCleaner/Cleanup/ScanStepView.swift \
    swift/MjmCleaner/Shell/PendingPages.swift
git commit -F - <<'MSG'
feat(swift): show the first two wizard steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 6: wizard, passi 3 e 4 (Conferma e Fatto)

Il passo 3 (`ConfirmStepView`): ogni percorso da eliminare, una card richiudibile per categoria con le caselle per le deselezioni (`CollapsibleCard`, scorrimento proprio alto al più 360 come il `ListBox` del C#), l'avviso «Eliminazione definitiva…», le app aperte e le esclusioni. «Elimina <totale>» è distruttivo, disabilitato con `canDelete` (che `delete()` ripete) e parte da un `Task` non legato alla vista; «Interrompi» chiama `cancelDelete()`; «Ricomincia» è disabilitato durante l'eliminazione e il contenuto con lui. Il passo 4 (`DoneStepView`): spazio liberato, righe per categoria, errori e avviso dello storico, «Nuova pulizia».

**Files:**
- Create: `swift/MjmCleaner/Cleanup/ConfirmStepView.swift`
- Create: `swift/MjmCleaner/Cleanup/DoneStepView.swift`
- Modify (sostituzione completa): `swift/MjmCleaner/Shell/PendingPages.swift` (tolte `ConfirmStepView`, `DoneStepView`)
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: `ConfirmStepModel` (`nodes`, `totalText`, `exclusionsText`, `runningAppsWarning`, `isDeleting`, `deleteProgressText`, `canDelete`, `canCancelDelete`, `delete()`, `cancelDelete()`, `restart()`), `CategoryNode` (`displayName`, `summaryText`, `paths`), `PathNode` (`isSelected`, `path`, `sizeText`), `DoneStepModel` (`freedText`, `summaryText`, `rows`, `errorsText`, `historyWarning`, `newCleanup()`); `CollapsibleCard`, `Banner`, `OptionalText`, `PageHeader`, `View.card`, `View.actionBar` (Task 4).
- Produces: `ConfirmStepView(model:)`, `DoneStepView(model:)`.

- [ ] **Step 1: Viste**

**Creare `swift/MjmCleaner/Cleanup/ConfirmStepView.swift`:**

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
    let node: CategoryNode
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
            EmptyView()
        } row: { path in
            PathRow(path: path)
        }
    }
}

private struct PathRow: View {
    @Bindable var path: PathNode

    var body: some View {
        HStack(spacing: 8) {
            Toggle(path.path, isOn: $path.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(path.path)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(path.sizeText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
```

**Creare `swift/MjmCleaner/Cleanup/DoneStepView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Passo 4 (`DoneStepView`): quanto si è liberato, per categoria, e gli eventuali avvisi.
struct DoneStepView: View {
    let model: DoneStepModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 48, height: 48)
                        .background(.green.opacity(0.15), in: Circle())
                        .accessibilityHidden(true)
                    Text("Pulizia completata")
                        .font(.system(size: 22, weight: .bold))
                    Text(model.freedText)
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                    Text(model.summaryText)
                        .foregroundStyle(.secondary)
                }
                if !model.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                        }
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .card(padding: 14)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                OptionalText(text: model.errorsText, style: .danger)
                OptionalText(text: model.historyWarning)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
            .background(.background)
        }
        .actionBar {
            Spacer()
            Button("Nuova pulizia", action: model.newCleanup)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
```

- [ ] **Step 2: Togliere le pagine provvisorie sostituite**

**Sostituire l'intero contenuto di `swift/MjmCleaner/Shell/PendingPages.swift` con:**

```swift
import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct DockerView: View {
    let model: DockerModel

    var body: some View {
        Text(verbatim: "Docker")
    }
}

struct DockerReportView: View {
    let model: DockerReportModel

    var body: some View {
        Text(verbatim: "Resoconto Docker")
    }
}

struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        Text(verbatim: "Xcode")
    }
}

struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        Text(verbatim: "Resoconto Xcode")
    }
}

struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        Text(verbatim: "Storico")
    }
}

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" confirm done
```

Expected: quattro file. `confirm`: «Verifica prima di eliminare», «4,6 GB · 7 elementi», le card delle quattro categorie con i percorsi spuntati e le dimensioni, l'avviso arancione «Eliminazione definitiva: questi file non finiscono nel Cestino e non sono recuperabili.», «Google Chrome in esecuzione…», «Ricomincia» e «Elimina 4,6 GB · 7 elementi» rosso; toolbar con il passo 3 pieno. `done`: il segno di spunta verde, «Pulizia completata», «4,6 GB liberati», «in 12 secondi · 7 elementi eliminati», le quattro righe per categoria, in rosso «1 elemento non eliminato. Alcuni erano in uso da applicazioni aperte.» e «Nuova pulizia»; toolbar con il passo 4 pieno.

- [ ] **Step 4: Registro di parità**

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Riselezione della voce corrente nella sidebar | un clic su Docker, Xcode o Storico già selezionati ricreava la pagina | `List(selection:)` non notifica una selezione invariata: la pagina resta (si ricarica con «Riprova», «Riprova analisi» o «Nuova analisi») | accettata |
```

**con:**

```markdown
| Riselezione della voce corrente nella sidebar | un clic su Docker, Xcode o Storico già selezionati ricreava la pagina | `List(selection:)` non notifica una selezione invariata: la pagina resta (si ricarica con «Riprova», «Riprova analisi» o «Nuova analisi») | accettata |
| Liste lunghe del passo 3, di Docker e di Xcode | `Expander` con un `ListBox` virtualizzato alto al più 360 | `DisclosureGroup` in una card con uno scorrimento proprio di `LazyVStack` alto al più 360 (`CollapsibleCard`) | equivalente |
```

- [ ] **Step 5: Commit**

```bash
git add swift/MjmCleaner/Cleanup/ConfirmStepView.swift \
    swift/MjmCleaner/Cleanup/DoneStepView.swift \
    swift/MjmCleaner/Shell/PendingPages.swift \
    docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
feat(swift): show the confirmation and the done steps

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 7: Docker e resoconto

La pagina Docker (`DockerView`): mentre analizza, la barra d'avanzamento; se Docker non è raggiungibile, lo stato vuoto con il messaggio del Core, «Riprova» e la pill «Motore non raggiungibile» in toolbar (l'app non avvia mai Docker Desktop); pronta, il riepilogo del motore e del disco e i gruppi richiudibili, con la casella di gruppo («Elimina in blocco» o «Seleziona tutte») e le caselle per riga. I volumi con nome che si confermano singolarmente lo dice il modello (`detailText`); la casella di gruppo non li seleziona (Task 9 del 4a). «Elimina <totale>» è distruttivo, disabilitato con `canDelete` e parte da un `Task` non legato alla vista; «Interrompi» chiama `cancelDelete()`. Il resoconto (`DockerReportView`): recuperato, misure prima e dopo, Docker fermato, suggerimento di Purge, voci eliminate e non, «Nuova analisi».

**Files:**
- Create: `swift/MjmCleaner/Docker/DockerView.swift`
- Create: `swift/MjmCleaner/Docker/DockerReportView.swift`
- Modify (sostituzione completa): `swift/MjmCleaner/Shell/PendingPages.swift` (tolte `DockerView`, `DockerReportView`)

**Interfaces:**
- Consumes: `DockerModel` (`isLoading`, `hasError`, `errorText`, `isReady`, `serverText`, `diskText`, `dfText`, `groups`, `isDeleting`, `deleteProgressText`, `deleteErrorText`, `canRetry`, `canDelete`, `canCancelDelete`, `totalText`, `retry()`, `delete()`, `cancelDelete()`), `DockerGroupNode` (`title`, `summaryText`, `description`, `isExpanded`, `showGroupCheckBox`, `groupCheckBoxLabel`, `isSelected`, `rows`), `DockerRow` (`showCheckBox`, `isSelected`, `name`, `detailText`, `kindLabel`, `sizeText`), `DockerReportModel` (`freedText`, `summaryText`, `dfText`, `diskText`, `daemonLostText`, `purgeHint`, `deleted`, `failed`, `hasFailures`, `historyWarning`, `analyzeAgain()`); componenti del Task 4.
- Produces: `DockerView(model:)`, `DockerReportView(model:)`, `StatusPillLabelStyle`.

- [ ] **Step 1: Viste**

**Creare `swift/MjmCleaner/Docker/DockerView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// La pagina Docker (`DockerView`): anteprima a gruppi, nulla viene eliminato prima di «Elimina».
/// Docker non raggiungibile mostra il messaggio del Core e Riprova; l'app non avvia mai Docker
/// Desktop. «Elimina» parte da un `Task` non legato alla vista e lo ferma solo «Interrompi».
struct DockerView: View {
    let model: DockerModel

    var body: some View {
        content
            .navigationTitle("Pulizia Docker")
            .navigationSubtitle("Anteprima: nulla viene eliminato finché non premi «Elimina».")
            .toolbar {
                if model.hasError {
                    ToolbarItem(placement: .primaryAction) {
                        Label("Motore non raggiungibile", systemImage: "circle.fill")
                            .labelStyle(StatusPillLabelStyle())
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Analisi di Docker e delle cartelle progetto in corso…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.hasError {
            VStack(spacing: 14) {
                Image(systemName: "cube")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(model.errorText)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Riprova") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canRetry)
                    .padding(.top, 6)
            }
            .frame(width: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isReady {
            ready
        }
    }

    private var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.serverText)
                        .fontWeight(.semibold)
                    Group {
                        Text(model.diskText)
                        Text(model.dfText)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
                ForEach(model.groups) { group in
                    DockerGroupView(group: group)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            // Le caselle si fermano, lo scorrimento no.
            .disabled(model.isDeleting)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Banner(text: String(localized: "Eliminazione definitiva: immagini e volumi eliminati non sono recuperabili. I volumi contengono dati."))
                OptionalText(text: model.deleteErrorText, style: .danger)
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
                    .truncationMode(.middle)
            }
            Spacer()
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

private struct DockerGroupView: View {
    @Bindable var group: DockerGroupNode
    @State private var isExpanded: Bool

    init(group: DockerGroupNode) {
        self.group = group
        _isExpanded = State(initialValue: group.isExpanded)
    }

    var body: some View {
        CollapsibleCard(items: group.rows, isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                Text(group.title)
                    .fontWeight(.semibold)
                Text(group.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(group.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if group.showGroupCheckBox {
                    Toggle(group.groupCheckBoxLabel, isOn: $group.isSelected)
                        .toggleStyle(.checkbox)
                }
            }
        } row: { row in
            DockerRowView(row: row)
        }
    }
}

private struct DockerRowView: View {
    @Bindable var row: DockerRow

    var body: some View {
        HStack(spacing: 8) {
            if row.showCheckBox {
                Toggle(row.name, isOn: $row.isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(row.kindLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(row.sizeText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

/// La pill di stato della toolbar («Motore non raggiungibile»): pallino grigio e testo.
struct StatusPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(.gray)
            configuration.title
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}
```

**Creare `swift/MjmCleaner/Docker/DockerReportView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Il resoconto Docker (`DockerReportView`): quanto si è recuperato, le misure prima e dopo, le
/// voci eliminate e quelle no. Il salvataggio nello storico è partito con il modello.
struct DockerReportView: View {
    let model: DockerReportModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text("Pulizia Docker completata")
                        .font(.system(size: 22, weight: .bold))
                    Text(model.freedText)
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.dfText)
                    Text(model.diskText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
                if !model.daemonLostText.isEmpty {
                    Banner(text: model.daemonLostText)
                }
                if !model.purgeHint.isEmpty {
                    Banner(text: model.purgeHint, emphasized: false)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Eliminate")
                        .fontWeight(.semibold)
                    ForEach(Array(model.deleted.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
                if model.hasFailures {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Non eliminate")
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        ForEach(Array(model.failed.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OptionalText(text: model.historyWarning)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
                .background(.background)
        }
        .actionBar {
            Spacer()
            Button("Nuova analisi", action: model.analyzeAgain)
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Pulizia Docker")
        .navigationSubtitle(model.summaryText)
    }
}
```

- [ ] **Step 2: Togliere le pagine provvisorie sostituite**

**Sostituire l'intero contenuto di `swift/MjmCleaner/Shell/PendingPages.swift` con:**

```swift
import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        Text(verbatim: "Xcode")
    }
}

struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        Text(verbatim: "Resoconto Xcode")
    }
}

struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        Text(verbatim: "Storico")
    }
}

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" docker docker-unavailable docker-report
```

Expected: sei file. `docker`: «Pulizia Docker» e il sottotitolo «Anteprima: nulla viene eliminato finché non premi «Elimina».», la card «Docker 27.3.1 in esecuzione» con le misure, i gruppi «Eliminabili in sicurezza» (casella «Elimina in blocco» spuntata, righe senza casella), «Costruite in locale», «Immagini non usate», «Volumi non montati» (riga `shop_pgdata` con «si conferma solo singolarmente»), «Da tenere» chiuso; avviso «Eliminazione definitiva: immagini e volumi…» e «Elimina 3,2 GB · 2 voci» rosso. `docker-unavailable`: la tile con il cubo, «Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.», «Riprova» e la pill «Motore non raggiungibile». `docker-report`: «Pulizia Docker completata», «3,1 GB recuperati», le misure, l'avviso di Purge, «Eliminate» con due voci, «Non eliminate» in rosso, «Nuova analisi».

- [ ] **Step 4: Commit**

```bash
git add swift/MjmCleaner/Docker/DockerView.swift \
    swift/MjmCleaner/Docker/DockerReportView.swift \
    swift/MjmCleaner/Shell/PendingPages.swift
git commit -F - <<'MSG'
feat(swift): show the Docker page and report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 8: Xcode e resoconto

La pagina Xcode (`XcodeView`): voci tutte deselezionate, gruppi richiudibili (la casella «Seleziona tutte le voci di cache» solo per DerivedData e Device Support, le righe bloccate con la casella disabilitata), «Anteprima selezione» disabilitata con `canPreview`. Dopo l'anteprima, in basso, la conferma finale: risorse, stima, avvertenze, dispositivi che restano e la presa d'atto; «Conferma ed elimina» è disabilitato con `canConfirmDelete` (che `confirmDelete()` ripete con `executionStarted`) e parte da un `Task` non legato alla vista. `canConfirmDelete` legge anche `executionStarted`, che non è osservato: ogni sua scrittura coincide con un cambio di `isDeleting`, `isLoading` o `confirmation`, che invece lo sono, quindi il pulsante si aggiorna. Mentre elimina la lista è disabilitata e la finestra blocca la navigazione. Il resoconto (`XcodeReportView`): l'esito di ogni voce, la stima nello storico e lo spazio libero rilevato, «Nuova analisi Xcode».

**Files:**
- Create: `swift/MjmCleaner/Xcode/XcodeView.swift`
- Create: `swift/MjmCleaner/Xcode/XcodeReportView.swift`
- Modify (sostituzione completa): `swift/MjmCleaner/Shell/PendingPages.swift` (tolte `XcodeView`, `XcodeReportView`)

**Interfaces:**
- Consumes: `XcodeModel` (`isLoading`, `groups`, `totalText`, `warningText`, `confirmation`, `hasConfirmation`, `previewSummaryText`, `previewEstimateText`, `hasSelectedDevices`, `hasSelectedRuntimes`, `hasRetainedDependencies`, `acknowledgeDependencies`, `isDeleting`, `progressText`, `errorText`, `canRetry`, `canPreview`, `canConfirmDelete`, `canCancelDelete`, `retry()`, `preview()`, `backToSelection()`, `confirmDelete()`, `cancelDelete()`), `XcodeConfirmation` (`selectedCandidates`, `retainedDependentDevices`), `XcodeCandidate` (`name`, `path`, `cliId`), `XcodeGroupNode` (`title`, `summary`, `warnings`, `isExpanded`, `showGroupCheckBox`, `isSelected`, `rows`), `XcodeRow` (`isSelected`, `canSelect`, `name`, `identityText`, `stateText`, `hasState`, `sizeText`), `XcodeReportModel` (`items`, `freedText`, `freeSpaceText`, `warningsText`, `historyWarning`, `summaryText`, `analyzeAgain()`), `XcodeResultRow`; componenti del Task 4.
- Produces: `XcodeView(model:)`, `XcodeReportView(model:)`.

- [ ] **Step 1: Viste**

**Creare `swift/MjmCleaner/Xcode/XcodeView.swift`:**

```swift
import CleanerCore
import CleanerFeatures
import SwiftUI

/// La pagina Xcode (`XcodeView`): voci tutte deselezionate, anteprima obbligatoria, conferma
/// finale e, se servono, presa d'atto dei dispositivi che restano. Mentre elimina, la finestra
/// blocca la navigazione; «Conferma ed elimina» parte da un `Task` non legato alla vista.
struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        content
            .navigationTitle("Pulizia cache e simulatori")
            .navigationSubtitle("Tutte le voci partono deselezionate. L’anteprima non elimina nulla.")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    OptionalText(text: model.warningText)
                    if let confirmation = model.confirmation {
                        XcodeConfirmationPanel(model: model, confirmation: confirmation)
                    }
                    OptionalText(text: model.errorText, style: .danger)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.background)
            }
            .actionBar {
                if model.isDeleting {
                    Text(model.progressText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if model.canCancelDelete {
                    Button("Interrompi", action: model.cancelDelete)
                }
                Button("Riprova analisi") { Task { await model.retry() } }
                    .disabled(!model.canRetry)
                if !model.hasConfirmation {
                    Button("Anteprima selezione", action: model.preview)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canPreview)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Analisi delle cartelle Xcode e dei simulatori…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.totalText)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 12)
                    ForEach(model.groups) { group in
                        XcodeGroupView(group: group)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                // Le caselle si fermano, lo scorrimento no.
                .disabled(model.isDeleting)
            }
        }
    }
}

/// La conferma finale: cosa verrà eliminato, le avvertenze e, se un runtime è usato da dispositivi
/// che restano, la presa d'atto senza la quale «Conferma ed elimina» resta disabilitato.
private struct XcodeConfirmationPanel: View {
    @Bindable var model: XcodeModel
    let confirmation: XcodeConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conferma finale")
                        .fontWeight(.bold)
                    Text(model.previewSummaryText)
                    Text(model.previewEstimateText)
                        .foregroundStyle(.secondary)
                    ForEach(Array(confirmation.selectedCandidates.enumerated()), id: \.offset) { _, candidate in
                        CandidateLines(candidate: candidate, showsPath: true)
                    }
                    if model.hasSelectedDevices {
                        Text("Eliminare un dispositivo rimuove anche le sue app e i dati di test.")
                    }
                    if model.hasSelectedRuntimes {
                        Text("Rimuovere un runtime può rendere indisponibili i dispositivi che lo usano.")
                    }
                    if model.hasRetainedDependencies {
                        Text("I dispositivi elencati resteranno sul disco, ma potrebbero non avviarsi se rimuovi il runtime.")
                        ForEach(Array(confirmation.retainedDependentDevices.enumerated()), id: \.offset) { _, candidate in
                            CandidateLines(candidate: candidate, showsPath: false)
                        }
                        Toggle(
                            "Ho capito che i dispositivi elencati potrebbero non essere più disponibili finché non reinstallo il runtime.",
                            isOn: $model.acknowledgeDependencies)
                            .toggleStyle(.checkbox)
                            .disabled(model.isDeleting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack {
                Spacer()
                Button("Torna alla selezione", action: model.backToSelection)
                    .disabled(model.isDeleting)
                Button("Conferma ed elimina", role: .destructive) {
                    Task { await model.confirmDelete() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!model.canConfirmDelete)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CandidateLines: View {
    let candidate: XcodeCandidate
    let showsPath: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name)
                .fontWeight(.semibold)
            if showsPath, let path = candidate.path {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let cliId = candidate.cliId {
                Text(cliId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct XcodeGroupView: View {
    @Bindable var group: XcodeGroupNode
    @State private var isExpanded: Bool

    init(group: XcodeGroupNode) {
        self.group = group
        _isExpanded = State(initialValue: group.isExpanded)
    }

    var body: some View {
        CollapsibleCard(items: group.rows, isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                Text(group.title)
                    .fontWeight(.semibold)
                Text(group.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            ForEach(Array(group.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if group.showGroupCheckBox {
                Toggle("Seleziona tutte le voci di cache", isOn: $group.isSelected)
                    .toggleStyle(.checkbox)
            }
        } row: { row in
            XcodeRowView(row: row)
        }
    }
}

private struct XcodeRowView: View {
    @Bindable var row: XcodeRow

    var body: some View {
        HStack(spacing: 8) {
            Toggle(row.name, isOn: $row.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!row.canSelect)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.identityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if row.hasState {
                    Text(row.stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(row.sizeText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
```

**Creare `swift/MjmCleaner/Xcode/XcodeReportView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Il resoconto Xcode (`XcodeReportView`): l'esito di ogni voce, la stima conteggiata nello storico
/// e lo spazio libero rilevato prima e dopo, tenuti separati.
struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.items) { row in
                    if row.id > 0 {
                        Divider().padding(.leading, 16)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.name)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(row.outcomeText)
                                .foregroundStyle(.secondary)
                            Text(row.sizeText)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        Text(row.identity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .card(padding: 0)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.freedText)
                    .fontWeight(.semibold)
                Text(model.freeSpaceText)
                    .foregroundStyle(.secondary)
                OptionalText(text: model.warningsText)
                OptionalText(text: model.historyWarning, style: .danger)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.background)
        }
        .actionBar {
            Spacer()
            Button("Nuova analisi Xcode", action: model.analyzeAgain)
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Report pulizia")
        .navigationSubtitle(model.summaryText)
    }
}
```

- [ ] **Step 2: Togliere le pagine provvisorie sostituite**

**Sostituire l'intero contenuto di `swift/MjmCleaner/Shell/PendingPages.swift` con:**

```swift
import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct HistoryView: View {
    let model: HistoryModel

    var body: some View {
        Text(verbatim: "Storico")
    }
}

struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" xcode xcode-preview xcode-report
```

Expected: sei file. `xcode`: «Pulizia cache e simulatori», «Tutte le voci partono deselezionate. L’anteprima non elimina nulla.», la card del totale, DerivedData e Device Support aperti con la casella di gruppo, «Dispositivi simulati» e «Runtime iOS, watchOS, tvOS e visionOS» chiusi, «Riprova analisi» e «Anteprima selezione». `xcode-preview`: «7 GB stimati · 1 selezionate», in basso la conferma finale con «Risorse selezionate: 1», «Stima nota: 7 GB», «iOS 17.4», le due avvertenze sul runtime, «iPhone 15» tra i dispositivi che restano, la casella «Ho capito che…» non spuntata, «Torna alla selezione» e «Conferma ed elimina» rosso ma disabilitato (attenuato). `xcode-report`: «Report pulizia», «2 eliminate · 1 saltate · 0 non riuscite · 0 incerte», tre righe con esito e dimensione, «10.737.418.240 byte stimati conteggiati nella cronologia», lo spazio libero «+11 GB», «Nuova analisi Xcode».

- [ ] **Step 4: Commit**

```bash
git add swift/MjmCleaner/Xcode/XcodeView.swift \
    swift/MjmCleaner/Xcode/XcodeReportView.swift \
    swift/MjmCleaner/Shell/PendingPages.swift
git commit -F - <<'MSG'
feat(swift): show the Xcode page and report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 9: Storico

Lo Storico (`HistoryView`, spec §6.2): una `Table` nativa a righe alterne ordinata per data decrescente (`KeyPathComparator(\.startedAt, order: .reverse)`, l'utente può cambiare ordine dalle intestazioni), con Data, Spazio (in grassetto, a destra), Categorie (chip con il nome leggibile, in uno scorrimento orizzontale che le taglia al bordo della colonna come il `ClipToBounds` del C#: dentro una cella di `Table` un semplice `.clipped()` non basta) ed Elementi (a destra). In toolbar il totale, solo se ci sono sessioni, e il conteggio.

**Files:**
- Create: `swift/MjmCleaner/History/HistoryView.swift`
- Modify (sostituzione completa): `swift/MjmCleaner/Shell/PendingPages.swift` (tolte `HistoryView`)

**Interfaces:**
- Consumes: `HistoryModel` (`rows`, `totalText`, `countText`, `hasSessions`), `HistoryRow` (`startedAt`, `when`, `bytesFreed`, `freed`, `categoryNames`, `items`).
- Produces: `HistoryView(model:)`.

- [ ] **Step 1: Viste**

**Creare `swift/MjmCleaner/History/HistoryView.swift`:**

```swift
import CleanerFeatures
import SwiftUI

/// Lo Storico (`HistoryView`, spec §6.2): una `Table` a righe alterne, dalla pulizia più recente;
/// le categorie con il nome leggibile, non con l'identificativo.
struct HistoryView: View {
    let model: HistoryModel
    @State private var sortOrder = [KeyPathComparator(\HistoryRow.startedAt, order: .reverse)]

    var body: some View {
        Table(model.rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Data", value: \.startedAt) { row in
                Text(row.when)
                    .monospacedDigit()
            }
            .width(min: 150, ideal: 190, max: 220)
            TableColumn("Spazio", value: \.bytesFreed) { row in
                Text(row.freed)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100, max: 120)
            .alignment(.trailing)
            // Categorie prende lo spazio che le altre colonne, a larghezza limitata, lasciano libero.
            TableColumn("Categorie") { row in
                CategoryChips(names: row.categoryNames)
            }
            TableColumn("Elementi") { row in
                Text(row.items)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 90, max: 120)
            .alignment(.trailing)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Storico delle pulizie")
        .navigationSubtitle("Le pulizie completate e lo spazio effettivamente recuperato.")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    if model.hasSessions {
                        Text(model.totalText)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(model.countText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

private struct CategoryChips: View {
    let names: [String]

    // Le chip restano intere e quelle che non entrano si tagliano al bordo della colonna
    // (`ClipToBounds` del C#): lo scorrimento orizzontale prende la larghezza della colonna.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}
```

- [ ] **Step 2: Togliere le pagine provvisorie sostituite**

**Sostituire l'intero contenuto di `swift/MjmCleaner/Shell/PendingPages.swift` con:**

```swift
import CleanerFeatures
import SwiftUI

// Pagine provvisorie: i Task 5–10 sostituiscono ciascuna con la vista vera e la tolgono da qui;
// il Task 10 cancella il file.


struct SettingsView: View {
    let model: SettingsModel

    var body: some View {
        Text(verbatim: "Impostazioni")
    }
}
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" history
```

Expected: due file. «Storico delle pulizie», «Le pulizie completate e lo spazio effettivamente recuperato.», in toolbar «9,4 GB» e «in 3 pulizie»; tre righe dalla più recente (21 set, 15 set, 1 set 2026) con 4,6 GB, 3 GB, 1,8 GB; nella colonna Categorie chip intere («Cache utente e di sistema», «Cartelle bin e obj nei progetti», «Immagini Docker») e l'ultima che non entra tagliata al bordo della colonna; elementi «7», «2.117», «3»; nessuna chip sopra la colonna Elementi.

- [ ] **Step 4: Commit**

```bash
git add swift/MjmCleaner/History/HistoryView.swift \
    swift/MjmCleaner/Shell/PendingPages.swift
git commit -F - <<'MSG'
feat(swift): show the history table

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 10: Impostazioni

Lo sheet delle Impostazioni (`SettingsView`): titolo «Impostazioni», un `Form` raggruppato con Aspetto (radio Automatico/Chiaro/Scuro, l'anteprima si vede subito), Progetti .NET e File grandi (liste di cartelle con «+» e «−», «−» disabilitato senza selezione, `accessibilityLabel` sui pulsanti solo icona), soglia ed età minime (campo, unità e `Stepper`, valore limitato agli intervalli del C#), le didascalie come `footer`; in basso l'errore di salvataggio, «Annulla» (Esc) e «Salva» (Invio). È largo 700 come la finestra C# e alto 560, così entra anche nella finestra minima 900×600. «+» parte da un `Task`: il pannello è asincrono. Il file delle pagine provvisorie non serve più.

**Files:**
- Create: `swift/MjmCleaner/Settings/SettingsView.swift`
- Delete: `swift/MjmCleaner/Shell/PendingPages.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: `SettingsModel` (`appearance`, `projectRoots`, `selectedProjectRoot`, `canRemoveProjectRoot`, `addProjectRoot()`, `removeProjectRoot()`, `largeFileRoots`, `selectedLargeFileRoot`, `canRemoveLargeFileRoot`, `addLargeFileRoot()`, `removeLargeFileRoot()`, `largeFileThresholdMegabytes`, `downloadsMinAgeDays`, `logsMinAgeDays`, `nuGetMinAgeDays`, `thresholdMegabytesRange`, `minAgeDaysRange`, `saveErrorText`, `cancel()`, `save()`), `AppearancePreference`; `OptionalText` (Task 4).
- Produces: `SettingsView(model:)`.

- [ ] **Step 1: Viste**

**Creare `swift/MjmCleaner/Settings/SettingsView.swift`:**

```swift
import CleanerCore
import CleanerFeatures
import SwiftUI

/// Le Impostazioni (`SettingsWindow`): uno sheet largo 700 sulla finestra principale, con
/// Annulla e Salva in basso a destra (spec §6.2). L'aspetto scelto si vede subito; Annulla lo
/// ripristina.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Impostazioni")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Personalizza i percorsi e le soglie usate durante l'analisi.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            Divider()
            Form {
                Section {
                    Picker("Aspetto", selection: $model.appearance) {
                        Text("Automatico").tag(AppearancePreference.auto)
                        Text("Chiaro").tag(AppearancePreference.light)
                        Text("Scuro").tag(AppearancePreference.dark)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                } header: {
                    Text("Aspetto")
                } footer: {
                    Text("Automatico segue l'aspetto scelto in Impostazioni di Sistema.")
                }

                Section {
                    FolderList(
                        roots: model.projectRoots,
                        selection: $model.selectedProjectRoot,
                        canRemove: model.canRemoveProjectRoot,
                        add: model.addProjectRoot,
                        remove: model.removeProjectRoot)
                } header: {
                    Text("Progetti .NET")
                } footer: {
                    Text("Cartelle di progetto in cui cercare bin e obj.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cartelle in cui cercare")
                        FolderList(
                            roots: model.largeFileRoots,
                            selection: $model.selectedLargeFileRoot,
                            canRemove: model.canRemoveLargeFileRoot,
                            add: model.addLargeFileRoot,
                            remove: model.removeLargeFileRoot)
                    }
                    NumberRow(
                        title: "Soglia file grandi", unit: "MB",
                        value: $model.largeFileThresholdMegabytes, range: SettingsModel.thresholdMegabytesRange)
                } header: {
                    Text("File grandi")
                } footer: {
                    Text("Vengono proposti solo i file più grandi della soglia.")
                }

                Section {
                    NumberRow(
                        title: "Download", accessibilityName: "Età minima dei download", unit: "giorni",
                        value: $model.downloadsMinAgeDays, range: SettingsModel.minAgeDaysRange)
                    NumberRow(
                        title: "Log", accessibilityName: "Età minima dei log", unit: "giorni",
                        value: $model.logsMinAgeDays, range: SettingsModel.minAgeDaysRange)
                    NumberRow(
                        title: "Pacchetti NuGet", accessibilityName: "Età minima dei pacchetti NuGet", unit: "giorni",
                        value: $model.nuGetMinAgeDays, range: SettingsModel.minAgeDaysRange)
                } header: {
                    Text("Età minima")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I file più recenti restano esclusi dall'analisi.")
                        Text("L'età dei pacchetti NuGet si basa sull'ultimo accesso registrato dal filesystem: è un'euristica, non una certezza.")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 10) {
                OptionalText(text: model.saveErrorText, style: .danger)
                Spacer()
                Button("Annulla", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Salva", action: model.save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
        }
        // Larga 700 come la finestra C#; alta 560 così entra anche nella finestra minima (900×600).
        .frame(width: 700, height: 560)
    }
}

/// Una lista di cartelle con la barra «+ / −» (spec §6.6): «−» è disabilitato senza selezione.
private struct FolderList: View {
    let roots: [String]
    @Binding var selection: String?
    let canRemove: Bool
    let add: () async -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if roots.isEmpty {
                Text("Nessuna cartella. Premi + per aggiungerne una.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else {
                List(selection: $selection) {
                    ForEach(roots, id: \.self) { root in
                        Text(root)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(root)
                    }
                }
                .frame(height: 84)
            }
            Divider()
            HStack(spacing: 0) {
                Button {
                    Task { await add() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .accessibilityLabel("Aggiungi cartella")
                Divider()
                    .frame(height: 14)
                Button(action: remove) {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 22)
                }
                .accessibilityLabel("Rimuovi cartella selezionata")
                .disabled(!canRemove)
                Spacer()
            }
            .buttonStyle(.borderless)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

/// Un campo numerico con unità e stepper. Il valore resta nei limiti della finestra C#
/// (`Minimum`/`Maximum` dei `NumericUpDown`), anche quando si scrive nel campo.
private struct NumberRow: View {
    let title: LocalizedStringKey
    /// Il nome di campo e stepper per VoiceOver, come `AutomationProperties.Name` del C#; senza, il titolo.
    var accessibilityName: LocalizedStringKey?
    let unit: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                // Il titolo resta il segnaposto corto del campo; VoiceOver legge il nome del C#.
                TextField(title, value: clamped, format: .number)
                    .labelsHidden()
                    .accessibilityLabel(accessibilityName ?? title)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(unit)
                    .foregroundStyle(.secondary)
                Stepper(accessibilityName ?? title, value: clamped, in: range)
                    .labelsHidden()
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}
```

- [ ] **Step 2: Togliere le pagine provvisorie sostituite**

**Cancellare `swift/MjmCleaner/Shell/PendingPages.swift`.**

```bash
git rm --quiet swift/MjmCleaner/Shell/PendingPages.swift
```

- [ ] **Step 3: Build e screenshot**

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
swift/Scripts/screenshots.sh "${TMPDIR:-/tmp}/mjm-cleaner-shots" settings
```

Expected: due file. Sopra la finestra del passo 1, lo sheet «Impostazioni» con sotto il titolo la riga grigia «Personalizza i percorsi e le soglie usate durante l'analisi.»: sezione «Aspetto» con «Chiaro» selezionato in `settings-light` e «Scuro» in `settings-dark`, la didascalia «Automatico segue l'aspetto scelto in Impostazioni di Sistema.», «Progetti .NET» con `~/Progetti` e `~/Lavoro/clienti`, la barra «+ −», «Cartelle di progetto in cui cercare bin e obj.», «File grandi» con «Cartelle in cui cercare» e `~/Downloads`; in basso «Annulla» e «Salva» blu. Le sezioni sotto si raggiungono scorrendo.

- [ ] **Step 4: Registro di parità**

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Liste lunghe del passo 3, di Docker e di Xcode | `Expander` con un `ListBox` virtualizzato alto al più 360 | `DisclosureGroup` in una card con uno scorrimento proprio di `LazyVStack` alto al più 360 (`CollapsibleCard`) | equivalente |
```

**con:**

```markdown
| Liste lunghe del passo 3, di Docker e di Xcode | `Expander` con un `ListBox` virtualizzato alto al più 360 | `DisclosureGroup` in una card con uno scorrimento proprio di `LazyVStack` alto al più 360 (`CollapsibleCard`) | equivalente |
| Impostazioni | finestra modale 700×680 (limitata all'area di lavoro), anteprime dell'aspetto disegnate, campi numerici con lo stepper compatto e i pulsanti nominati da `StepperNames` | sheet 700×560 con un `Form` raggruppato, `Picker` a pulsanti radio, `TextField` più `Stepper` nativo con il nome della riga (`StepperNames` non si porta) | voluta (spec §6.1, §6.2) |
```

- [ ] **Step 5: Commit**

```bash
git add swift/MjmCleaner/Settings/SettingsView.swift \
    docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
feat(swift): show the settings sheet

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

---

### Task 11: verifica finale e chiusura del registro

Nessun codice nuovo: la suite, i build, i vincoli globali, gli screenshot di tutte le pagine (che restano nel repository come base per il confronto del piano 5) e le prove C# di vista chiuse nel registro, ciascuna con il proprio metodo di verifica.

**Files:**
- Create: `docs/superpowers/verification/<data>-swift-4b/` con 26 PNG (`<pagina>-light.png`, `<pagina>-dark.png`)
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: l'intera app (Task 1–10), `swift/Scripts/screenshots.sh` (Task 3).
- Produces: nessuna API.

- [ ] **Step 1: Suite e build**

```bash
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')
```

Expected: `Test run with 172 tests in 21 suites passed` (165 dopo il Task 1, più 2 del fix round del Task 10 e 5 della fix wave finale) e `Test run with 496 tests in 47 suites passed`, nessun warning.

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `** BUILD SUCCEEDED **` e `nessuna diagnostica`.

```bash
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-release" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-release.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-release.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-release.log" || echo "nessuna diagnostica"
app="${TMPDIR:-/tmp}/mjm-cleaner-release/Build/Products/Release/MjmCleaner.app"
lipo -archs "$app/Contents/MacOS/MjmCleaner"
strings "$app/Contents/MacOS/MjmCleaner" | grep -c -E 'MJMDemo|Demo[A-Z]|/Users/demo' || true
codesign --verify --strict "$app" && echo "firma valida"
codesign -dv "$app" 2>&1 | grep -E '^Signature=adhoc|^Sealed Resources version=2'
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Release -showBuildSettings 2>/dev/null \
    | grep -E '^ *SWIFT_VERSION = '
```

Expected: `** BUILD SUCCEEDED **`, `nessuna diagnostica`, `x86_64 arm64`, `0`, `firma valida`, `Signature=adhoc`, `Sealed Resources version=2 …`, `SWIFT_VERSION = 6.0`.

- [ ] **Step 2: Vincoli globali e confini**

```bash
grep -rnE 'try!|as!' swift/MjmCleaner swift/Scripts || echo "nessuna violazione"
grep -rnE '[A-Za-z0-9_\)\]]!([^=]|$)' swift/MjmCleaner swift/Scripts --include='*.swift' || echo "nessun forced unwrap"
grep -rn 'fixedSize' swift/MjmCleaner
grep -rn 'accessibilityLabel' swift/MjmCleaner
grep -n -A3 'CommandGroup(replacing: .appSettings)' swift/MjmCleaner/App/MjmCleanerApp.swift
grep -n 'settings?.cancel()' swift/MjmCleaner/Shell/MainView.swift
grep -nE 'LocalFileSystem|SettingsStore|HistoryStore|SessionLogWriter|CleanEngine|ScanEngine|RuleScanner|ProcessRunner|AppEnvironment\.live|AppStartup\.paths'     swift/MjmCleaner/Demo/*.swift || echo "la demo non usa servizi su disco"
grep -nE 'DemoLaunch\.|AppEnvironment\.live' swift/MjmCleaner/App/AppStartup.swift
git diff --name-only main...HEAD -- swift/MjmCleanerKit/Sources/CleanerCore swift/MjmCleanerKit/Tests/CleanerCoreTests src tests
```

Expected: «nessuna violazione», «nessun forced unwrap» (il secondo pattern può segnalare falsi positivi in commenti e stringhe: controllare ogni riga), nessun `fixedSize` dentro un `safeAreaInset` o un `actionBar` (sono ammessi nel contenuto delle pagine, stato vuoto di Docker compreso, nelle chip dello Storico e nella vista d'errore), `accessibilityLabel` per «Avanzamento», «Aggiungi cartella» e «Rimuovi cartella selezionata», il comando «Impostazioni…» con `.keyboardShortcut(",", modifiers: .command)`, `showSettings()` e `.disabled(!(startup.main?.canShowSettings ?? false))`, il binding dello sheet con `main.settings?.cancel()`, «la demo non usa servizi su disco»; in `AppStartup.swift` le righe con `DemoLaunch.` (pagina nota, pagina sconosciuta) vengono prima di `AppEnvironment.live`; l'ultimo comando non stampa nulla.

- [ ] **Step 3: Screenshot di tutte le pagine**

```bash
dir="docs/superpowers/verification/$(date +%F)-swift-4b"
swift/Scripts/screenshots.sh "$dir"
ls "$dir" | wc -l
```

Expected: 26 percorsi stampati, uscita 0, poi `26` (con lo schermo bloccato o spento le catture non riescono e lo script esce con 1: sbloccare il Mac è un'azione dell'utente, quindi il task si ferma qui finché lo schermo non è disponibile; lo stesso se il Mac è in uso: con un'altra app in primo piano lo script non cattura, «finestra non attiva…», e la cattura chiede all'utente un paio di minuti con Claude in primo piano, senza tastiera né mouse). Con il Mac ancora fermo, provare che la demo rifiuta una pagina che non conosce (lo script la scarterebbe prima con uscita 2): `open -n "$(cd "${TMPDIR:-/tmp}" && pwd -P)/mjm-cleaner-screenshots/Build/Products/Debug/MjmCleaner.app" --args -MJMDemo pagina-inesistente -ApplePersistenceIgnoreState YES`; la finestra mostra la vista d'errore con «Pagina demo sconosciuta: pagina-inesistente.» e nessun dato vero; poi `pkill -f mjm-cleaner-screenshots/Build/Products/Debug/MjmCleaner.app`. Guardare ogni immagine: stesse schermate descritte negli Expected dei Task 4–10, in chiaro e in scuro, testo leggibile in entrambi, barra azioni e avvisi interi in fondo, nessuna pagina vuota o spostata.

- [ ] **Step 4: Registro di parità**

Sostituire `AAAA-MM-GG` con la data di oggi (`date +%F`) nella riga nuova e aggiungerla sotto quella del piano 4a.

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
Piano 4a completato il 2026-10-15: 44 prove C# dell'app portate in `CleanerFeaturesTests` (+ 119 nuove), suite Swift verde (496 + 163 test); le prove della vista restano al piano 4b.
```

**con:**

```markdown
Piano 4a completato il 2026-10-15: 44 prove C# dell'app portate in `CleanerFeaturesTests` (+ 119 nuove), suite Swift verde (496 + 163 test); le prove della vista restano al piano 4b.

Piano 4b completato il AAAA-MM-GG: app SwiftUI in `swift/MjmCleaner.xcodeproj`, 13 pagine dell'ambiente dimostrativo fotografate in chiaro e in scuro in `docs/superpowers/verification/AAAA-MM-GG-swift-4b/`, suite Swift verde (496 + 172 test); ogni prova C# di vista ha il proprio metodo di verifica.
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| AccessibilityTests.cs | 3 | — | — | 4b | nomi accessibili dei controlli: li forniscono i controlli SwiftUI e gli `accessibilityLabel` dei pulsanti solo icona (spec §6.6); da verificare nell'app |
```

**con:**

```markdown
| AccessibilityTests.cs | 3 | — | — | 4b | verificate nel codice (Task 11 e revisione finale): le voci della sidebar sono `Label` con il titolo e il pulsante delle Impostazioni si chiama «Impostazioni…» (`accessibilityLabel`, senza «⌘,»); i pulsanti hanno il proprio testo; + e − hanno «Aggiungi cartella» e «Rimuovi cartella selezionata» (spec §6.6); i campi numerici hanno i nomi del C# («Soglia file grandi», «Età minima dei download», «Età minima dei log», «Età minima dei pacchetti NuGet»); l'indicatore dei passi si legge «Avanzamento»; le caselle delle righe hanno il nome della riga, che al passo 1 non si ripete; tile e icone decorative sono nascoste a VoiceOver; la prova con VoiceOver resta al collaudo del piano 5 |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire il testo (dentro la riga):**

```markdown
`HasToolbarAndNoCloseButton`, `SortChevronIsNinePixelsWithAThinStroke`, `ColumnHeadersShareOneStyle` sono della vista → piano 4b
```

**con:**

```markdown
`HasToolbarAndNoCloseButton`, `SortChevronIsNinePixelsWithAThinStroke`, `ColumnHeadersShareOneStyle` sono della vista: nel 4b la `Table` nativa ha intestazioni uniformi e l'indicatore d'ordinamento di sistema, la toolbar ha titolo e totale e nessun «Chiudi» (screenshot `history-*.png`, Task 11)
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire il testo (dentro la riga):**

```markdown
`ClickingTheSidebarSettingsButtonOpensTheWindow`, `CommandCommaOpensTheWindow`, `TheApplicationMenuHasTheSettingsItemFromStartup` sono della vista e del menu → piano 4b
```

**con:**

```markdown
`ClickingTheSidebarSettingsButtonOpensTheWindow`, `CommandCommaOpensTheWindow`, `TheApplicationMenuHasTheSettingsItemFromStartup` sono della vista e del menu: nel 4b il pulsante «Impostazioni…» della sidebar e la voce di menu ⌘, (`CommandGroup(replacing: .appSettings)`, presente dall'avvio) chiamano `showSettings()` e si disabilitano con `canShowSettings` (verificati nel codice, Task 11)
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire il testo (dentro la riga):**

```markdown
(margini e rientri della vista: piano 4b)
```

**con:**

```markdown
(margini e rientri della vista: screenshot `choose-*.png`, Task 11)
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire il testo (dentro la riga):**

```markdown
controlli nel viewport → piano 4b
```

**con:**

```markdown
controlli nel viewport: la barra azioni e la conferma stanno nell'area sicura in basso, sempre visibili (screenshot `xcode-*.png`, Task 11)
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| SettingsWindowTests.cs | 10 (3) | — | — | 4b | `ClosingTheWindowRestoresTheAppearance` è coperto da `closingFromTheTitleBarBehavesLikeCancel` (stesso `dismiss()`), ma il collegamento della vista (`.sheet(onDismiss:)` → `dismiss()`) va provato nel 4b; `ShowsTheFourSectionsAndTheEmptyFolderState` (titoli delle quattro sezioni, «Nessuna cartella. Premi + per aggiungerne una.», larghezza) va provato nel 4b; i limiti dei campi numerici diventano `SettingsModel.thresholdMegabytesRange`/`minAgeDaysRange` per lo `Stepper`; altezza, didascalie, stepper compatto, anello dell'aspetto e cornice dei campi sono layout e tema Avalonia (spec §9.2) |
```

**con:**

```markdown
| SettingsWindowTests.cs | 10 (3) | — | — | 4b | `ShowsTheFourSectionsAndTheEmptyFolderState`: le quattro sezioni negli screenshot `settings-*.png` e «Nessuna cartella. Premi + per aggiungerne una.» nel codice di `FolderList`; `DefaultHeightFitsA13InchDisplay` e `HeightIsCappedToTheWorkingAreaOfTheScreen`: lo sheet è 700×560 ed entra nella finestra minima 900×600; `ClosingTheWindowRestoresTheAppearance`: chiudere lo sheet dal sistema chiama `main.settings?.cancel()`, che ripristina l'aspetto (`closingFromTheTitleBarBehavesLikeCancel` lo prova sul modello, il collegamento della vista è stato provato a mano con la demo nel Task 4); `AppearanceCaptionSitsBelowTheCard` e `AllSectionCaptionsUseTheSameSize`: didascalie come `footer` delle sezioni del `Form`; `NumericFieldsUseTheCompactStepperWithNamedButtons`: `Stepper` nativo con il nome della riga, o il nome accessibile del C# per i tre campi d'età, `StepperNames` non si porta (differenza registrata); `SteppingStillChangesTheBoundValueAndClamps`: campo e stepper restano in `thresholdMegabytesRange` e `minAgeDaysRange`; anello dell'aspetto e cornice dei campi (`SelectedAppearancePreviewHasAnUnclippedAccentRing`, `CompactFieldDoesNotPaintFluentTextBoxChrome`) sono tema Avalonia (spec §9.2) |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| MainWindowLayoutTests.cs | 3 | — | — | — | layout Avalonia (pagina che non si allarga, footer nel viewport, struttura della shell): con `NavigationSplitView` e `safeAreaInset` il difetto non può verificarsi (spec §9.2); verifica manuale §9.4 |
```

**con:**

```markdown
| MainWindowLayoutTests.cs | 3 | — | — | — | layout Avalonia (pagina che non si allarga, footer nel viewport, struttura della shell): con `NavigationSplitView` e `safeAreaInset` il difetto non può verificarsi (spec §9.2); screenshot del Task 11, verifica manuale §9.4 nel piano 5 |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| ToolPagesLayoutTests.cs | 4 (12) | — | — | — | toolbar senza «Chiudi» e colori degli Expander di Avalonia (spec §9.2): in SwiftUI si usano toolbar e `DisclosureGroup` nativi; verifica manuale §9.4 |
```

**con:**

```markdown
| ToolPagesLayoutTests.cs | 4 (12) | — | — | — | toolbar senza «Chiudi» e colori degli Expander di Avalonia (spec §9.2): in SwiftUI toolbar e `DisclosureGroup` nativi, senza «Chiudi» (screenshot `docker-*.png` e `xcode-*.png`, Task 11); verifica manuale §9.4 nel piano 5 |
```

Verificare poi che le sedici righe della tabella `MjmCleaner.App.Tests` abbiano tutte piano 4a, 4b o «—» con il metodo di verifica o la ragione.

- [ ] **Step 5: Commit**

```bash
dir="docs/superpowers/verification/$(date +%F)-swift-4b"
git add "$dir/choose-light.png" \
    "$dir/choose-dark.png" \
    "$dir/scan-light.png" \
    "$dir/scan-dark.png" \
    "$dir/confirm-light.png" \
    "$dir/confirm-dark.png" \
    "$dir/done-light.png" \
    "$dir/done-dark.png" \
    "$dir/docker-light.png" \
    "$dir/docker-dark.png" \
    "$dir/docker-unavailable-light.png" \
    "$dir/docker-unavailable-dark.png" \
    "$dir/docker-report-light.png" \
    "$dir/docker-report-dark.png" \
    "$dir/xcode-light.png" \
    "$dir/xcode-dark.png" \
    "$dir/xcode-preview-light.png" \
    "$dir/xcode-preview-dark.png" \
    "$dir/xcode-report-light.png" \
    "$dir/xcode-report-dark.png" \
    "$dir/history-light.png" \
    "$dir/history-dark.png" \
    "$dir/settings-light.png" \
    "$dir/settings-dark.png" \
    "$dir/startup-failure-light.png" \
    "$dir/startup-failure-dark.png" \
    docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
docs(swift): verify the app screens and close plan 4b

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
git status --short
```

Expected: il commit con il trailer; `git status --short` mostra solo `?? .zed/` e `?? mjm-cleaner-ui-handoff.md`.

## Emendamenti dopo l'esecuzione

Piano eseguito il 2026-10-15; il ledger con ogni ruling è in `docs/superpowers/decisions/2026-10-15-registro-decisioni-swift-piano-4b.md`. I blocchi di codice dei task riportano i file finali; qui ciò che è cambiato rispetto al testo approvato e ciò che non sta nei blocchi.

- **Task 2** (fix round): grep delle diagnostiche `(^|: )(warning|error): `, firma verificata con `codesign --verify --strict` e `Sealed Resources version=2`, `SWIFT_VERSION = 6.0`, pannello delle cartelle come foglio della finestra attiva (nel piano dal commit ec65a83).
- **Task 3** (fix round): lo script rifiuta le pagine sconosciute e controlla la demo nel binario (nel piano dal commit e2caea2).
- **Task 9** (fix round): larghezze massime di Data, Spazio ed Elementi e colonne numeriche allineate a destra, così Categorie prende lo spazio rimasto.
- **Task 10** (fix round): la frase introduttiva del C# sotto il titolo, titolo `.isHeader`; due test solo Swift in `SettingsViewModelTests` (`removingWithoutSelectionKeepsBothLists`, `removeLargeFileRootIsDisabledWithoutSelection`) e la riga del registro (non sono blocchi di questo piano).
- **Fix wave della revisione finale:**
  - guardie nei modelli, perché nessuna garanzia viva solo nella vista: `ConfirmStepModel.restart()` rifiuta durante l'eliminazione, `DockerModel.retry()` e `XcodeModel.retry()` rispettano `canRetry`; test solo Swift `restartWhileDeletingStaysOnTheStep`, `retryWhileLoadingDoesNothing`, `retryIsIgnoredWhileDeleting`, `onlySelectableGroupsHaveRowCheckBoxes`, `rowsKeepTheSessionStartForSorting` e l'attesa su `canPreview` senza selezione (non sono blocchi di questo piano); `PageKind.wizardStep` con uno switch esaustivo (blocco del Task 1);
  - demo: con `-MJMDemo` e una pagina sconosciuta l'app mostra la vista d'errore e non legge le impostazioni vere (blocchi del Task 3); lo script non cattura una finestra che non è in primo piano, chiude l'app anche con Ctrl-C e apre la finestra alla misura predefinita;
  - accessibilità: il pulsante «Impostazioni…» senza «⌘,», i nomi dei campi numerici del C#, il nome della categoria letto una volta al passo 1, icone decorative nascoste;
  - `.disabled` durante l'eliminazione sul contenuto e non sullo scorrimento; sfondo alle fasce in basso del passo 4 e del resoconto Docker; parametro generico `Title` in `CollapsibleCard`; celle dello Storico senza `frame` ridondante;
  - registro di parità: conteggi dei test solo Swift, riga «Riselezione…» corretta, nove differenze e due candidati nuovi;
  - un commento in `XcodeModel.load()`: il ramo `if !isDeleting` resta come difesa in profondità.
- **Dopo la re-review della fix wave:** il segnaposto dei campi d'età torna il titolo corto (il nome del C# resta a VoiceOver con `accessibilityLabel`), il commento del doppio `SequencedDocker` torna sulla sua classe, la riga «Intestazione della sidebar» del registro dice dove compare il nome (menu dell'app e Dock) e il Task 11 prova il rifiuto di una pagina demo sconosciuta.
- **CleanerFeatures:** il vincolo «cambiano solo le due funzioni pure e i test del Task 1» non vale più dopo il Task 10 e la fix wave; il Core resta intatto.
- **Task 11:** suite, build e vincoli verificati prima della fix wave e di nuovo dopo; la cattura dei 26 screenshot si fa dopo la fix wave con il Mac fermo (con un'altra app in primo piano le finestre restano inattive e i tasti dell'utente finiscono nella demo); conteggi finali 172 + 496.

---

## Dopo il piano 4b

- **Piano APFS** (deciso dall'utente il 2026-10-14): il buco del ripiegamento U+212A/ſ nella deny-list, con spike sul nome canonico, emendamento della spec §12 e correzione in `PathGuard` e nella giuntura `FileSystem`.
- **Piano 5**: collaudo fianco a fianco con l'app C# e confronto con gli screenshot del redesign (§9.4, base: `docs/superpowers/verification/<data>-swift-4b/`), workflow di release (§10.2: `swift test` + `xcodebuild`, build Release universale, firma ad hoc, zip), rimozione del C# (§10.3). Da decidere lì: un bundle id distinto per il Debug (oggi la demo usa `com.mjm.cleaner` come l'app C#, scrive nel suo dominio defaults e LaunchServices registra il bundle di prova), il nome del bundle (`MjmCleaner.app` contro `mjm.cleaner.app`) e `ONLY_ACTIVE_ARCH`.
- Dal registro: l'avvio legge `settings.json` due volte (per l'aspetto prima della finestra e nell'ambiente); i candidati a miglioramento del 4a restano non applicati (spec §12).
