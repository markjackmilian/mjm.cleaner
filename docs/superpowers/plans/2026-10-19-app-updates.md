# Aggiornamenti dell'app dalle release GitHub — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** L'app Release controlla le release GitHub all'avvio e ogni 24 ore, scarica e verifica la versione più recente in background e propone «Installa e riavvia», che sostituisce il bundle sul posto e riapre l'app.

**Architecture:** Nel Core, `CleanerCore/Update/` contiene le parti pure e testabili: versione (`AppVersion`), contesto dell'app in esecuzione (`UpdateContext`), lettura del feed GitHub (`GitHubReleaseFeed`), download con verifica SHA-256 (`UpdateDownloader`), controlli del bundle estratto (`UpdateVerifier`) e avvio dello script di sostituzione (`UpdateInstaller`, con lo script `Resources/update-install.sh`). La facciata `AppUpdater` (protocollo `AppUpdating`) li compone. In `CleanerFeatures`, `UpdateModel` tiene stato, pianificazione e azioni del banner; `MainModel` lo crea solo se l'ambiente ha un updater e l'app un `UpdateHosting`. L'app aggiunge banner, sezione delle Impostazioni, comando di menu e l'host AppKit.

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, CryptoKit, `URLSession`, `/bin/sh`, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-19-app-updates-design.md`

Stato di partenza: `main` con questo piano (nessun push). Il codice è quello di `b151dc7` (spec degli aggiornamenti). `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **536** test in 48 suite (`CleanerCoreTests`) e **173** in 21 (`CleanerFeaturesTests`). Il controller crea il branch `feat/app-updates` da `main` prima del Task 1.

Decisioni dell'utente (2026-10-19, nella spec):

- Proposta **«Installa e riavvia» / «Più tardi»**: l'app si chiude, il bundle si sostituisce sul posto, l'app si riapre.
- Controllo **all'avvio e ogni 24 ore**, disattivabile, con «Controlla ora».
- Verifica con il **digest SHA-256 di GitHub** e controlli del bundle, senza EdDSA né segreti in CI.
- **Updater nativo**: niente Sparkle, nessuna dipendenza, nessuna modifica al packaging delle release.

Decisioni prese durante la stesura, verificate rieseguendo il piano in una copia scratch (worktree staccato su `b151dc7`):

- **L'updater lavora con `FileManager`, non con il protocollo `FileSystem`.** Serve rinominare file e cartelle, operazione che `FileSystem` non offre, e la cartella `updates/` è dell'app (Application Support, già protetta dalla deny-list). I test usano cartelle temporanee vere (`TemporaryDirectory`).
- **Lo script è una risorsa di `CleanerCore`** (`Resources/update-install.sh`, copiata dalla regola `.process`). `UpdateInstaller` lo copia in una cartella temporanea propria prima di avviarlo, perché lo script sopravvive al bundle che sostituisce. Lo script riceve tutto come argomenti posizionali e gira con `PATH=/usr/bin:/bin:/usr/sbin:/sbin`. Il suo test (`Scripts/update-install.test.sh`) sostituisce `open` e `mv` con shim messi in testa al `PATH`.
- **Il controllo vale per tutta la catena.** In automatico è silenzioso anche un download o una verifica che fallisce, non solo la lettura del feed; `LastUpdateCheck` si salva appena il feed risponde, quindi un asset difettoso si riprova dopo 24 ore e non a ogni tick.
- **Un tag fuori formato è `invalidRelease`.** La spec non lo diceva: una release `latest` con tag non `vX.Y.Z` non si confronta e viene segnalata come release non valida.
- **«Controlla aggiornamenti…» apre le Impostazioni** e avvia il controllo: stato ed esito si leggono nella sezione «Aggiornamenti», senza un secondo avviso.
- **`UpdateContext.make` decide chi si aggiorna**: solo il bundle id `com.mjm.cleaner` con una versione leggibile. Toglie anche la `/` finale che `Bundle.main.bundleURL` aggiunge al percorso.
- **`MainModel.isCleaning`** riunisce le tre cancellazioni (passo 3, Docker, Xcode). `FakeDocker` riceve `holdExecution()` per provare il caso Docker.
- **L'avviso di installazione fallita nomina `install.log` «nella cartella updates dei dati dell'app»** invece del percorso completo chiesto dalla spec: il modello non conosce i percorsi, e il README li indica.
- **Il tick orario sta in `AppStartup.show`**: un `Task` che chiama `start()` e poi `checkIfDue()` ogni ora. La decisione resta nel modello, che è testato.
- **`URLSessionHTTPClient` e `DetachedProcessLauncher` non hanno test unitari** (rete vera, processo staccato): li prova il collaudo end-to-end del Task 10.
- **Stringhe.** Le nuove stringhe sono in italiano, con `String(localized:bundle: .module)` nel package e chiavi letterali nelle viste, come le esistenti. I `Localizable.xcstrings` non si toccano. Come il piano Docker, questo piano va eseguito **prima** di quello della localizzazione (`docs/superpowers/specs/2026-10-19-localization-design.md`).
- **Piano Docker.** `feat/docker-engines` è in esecuzione e cambia `AppEnvironment.live`, `MainModel.showDockerReport`, `FakeDocker` e gli helper Docker dei test. Questo piano non tocca quelle righe: applicato per intero sopra `feat/docker-engines` (`662621d`, 552 + 177 test) dà 616 + 207, gli stessi incrementi, con script e app verdi. L'ordine fra i due piani è libero; se il piano Docker arriva prima, i conteggi attesi crescono di 16 (Core) e 4 (Features) in ogni task.

## Global Constraints

- Il codice vive in `MjmCleanerKit/` (package) e `MjmCleaner/` (app). File nuovi solo in `CleanerCore/Update/`, `CleanerCore/Resources/update-install.sh`, `CleanerFeatures/Update/`, `MjmCleaner/Update/`, nei test indicati e in `Scripts/update-install.test.sh`. File esistenti modificati: solo quelli elencati nei task.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati.
- Indirizzo del feed: `https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/latest`. Nome dell'asset: `mjm.cleaner-<tag>-macos-universal.zip`. Bundle id che si aggiorna: `com.mjm.cleaner`. Cartella: `~/Library/Application Support/<bundle id>/updates/`, mai `~/Library/Caches`.
- L'updater non rimuove attributi estesi (quarantena compresa) e non usa `sudo`.
- Testi nuovi: solo quelli del piano, scritti esattamente così. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica, dalla radice del repository:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - script: `bash Scripts/update-install.test.sh`;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-app-updates-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/app-updates`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` (`MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`).
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick). Nei Task 1–9 l'app non si avvia: le verifiche sono test, script e build. Il collaudo del Task 10 lo fa il controller con l'utente, che fa i clic.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: sonnet; **opus per i Task 3, 4, 5 e 6** (download, verifica del bundle, script che sostituisce l'app, installer) e per la revisione finale. Quei task si rivedono con mutazioni in una copia scratch: vedi la tabella in fondo.
- Il Task 10 non va a un subagent: lo esegue il controller con l'utente.

---

### Task 1: Versioni, contesto dell'app e impostazioni degli aggiornamenti

<!-- verifica: package -->

`AppVersion` legge e confronta `vMAJOR.MINOR.PATCH`; `UpdateContext.make` esiste solo per la build Release; `AppPaths.updatesDirectory` e due campi nuovi di `CleanerSettings` (`AutomaticUpdateChecks`, `LastUpdateCheck`).

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/AppVersionTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/AppVersion.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/UpdateContext.swift`
- Modify: `MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Settings/AppPaths.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`

**Interfaces:**
- Produces: `AppVersion(_ text: String) -> AppVersion?`, `AppVersion(major:minor:patch:)`, `.description` (`"1.2.3"`), `.tag` (`"v1.2.3"`), `Comparable`, `Codable`.
- Produces: `UpdateContext(currentVersion:bundlePath:processIdentifier:)`, `UpdateContext.make(bundleIdentifier:shortVersion:bundlePath:processIdentifier:) -> UpdateContext?`, `UpdateContext.releaseBundleIdentifier`.
- Produces: `AppPaths.updatesDirectory: String`; `CleanerSettings.automaticUpdateChecks: Bool` (predefinito `true`), `CleanerSettings.lastUpdateCheck: Date?`.

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/AppVersionTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct AppVersionTests {
    @Test(arguments: ["1.2.3", "v1.2.3"])
    func parsesWithAndWithoutTheTagPrefix(text: String) throws {
        let version = try #require(AppVersion(text))
        #expect(version == AppVersion(major: 1, minor: 2, patch: 3))
        #expect(version.description == "1.2.3")
        #expect(version.tag == "v1.2.3")
    }

    @Test(arguments: [
        "", "v", "1.2", "1.2.3.4", "1..3", "v1.2.3-rc1", "1.2.3+5", " 1.2.3", "1.2.3 ", "V1.2.3",
        "vv1.2.3", "1.-2.3", "1.+2.3", "1.2.x", "1234567890.0.0", "١.2.3",
    ])
    func rejectsEverythingElse(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func comparesFieldsAsNumbers() throws {
        let older = try #require(AppVersion("0.9.0"))
        let newer = try #require(AppVersion("0.10.0"))
        #expect(older < newer)
        #expect(try #require(AppVersion("1.0.0")) > newer)
        #expect(try #require(AppVersion("0.10.1")) > newer)
        #expect(!(newer < newer))
    }
}

struct UpdateContextTests {
    @Test func existsOnlyForTheReleaseBundle() throws {
        let context = try #require(UpdateContext.make(
            bundleIdentifier: "com.mjm.cleaner", shortVersion: "0.1.0",
            bundlePath: "/Applications/mjm.cleaner.app", processIdentifier: 42))
        #expect(context.currentVersion == AppVersion(major: 0, minor: 1, patch: 0))
        #expect(context.bundlePath == "/Applications/mjm.cleaner.app")
        #expect(context.processIdentifier == 42)
    }

    @Test(arguments: [("com.mjm.cleaner.debug", "0.1.0"), ("com.mjm.cleaner", "1.0"), ("com.mjm.cleaner", nil)] as [(String?, String?)])
    func debugBuildsAndUnreadableVersionsNeverUpdate(identifier: String?, version: String?) {
        #expect(UpdateContext.make(bundleIdentifier: identifier, shortVersion: version, bundlePath: "/x.app", processIdentifier: 1) == nil)
    }

    @Test func bundlePathLosesTheTrailingSlashOfDirectoryURLs() {
        let context = UpdateContext.make(
            bundleIdentifier: "com.mjm.cleaner", shortVersion: "0.1.0", bundlePath: "/Applications/mjm.cleaner.app/", processIdentifier: 1)
        #expect(context?.bundlePath == "/Applications/mjm.cleaner.app")
    }

    @Test func missingBundleIdentifierNeverUpdates() {
        #expect(UpdateContext.make(bundleIdentifier: nil, shortVersion: "0.1.0", bundlePath: "/x.app", processIdentifier: 1) == nil)
    }

    @Test func updatesLiveUnderApplicationSupportNotCaches() {
        let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")
        #expect(paths.updatesDirectory == "/Users/tester/Library/Application Support/com.mjm.cleaner/updates")
    }
}
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift`, sostituire:

```swift
        #expect(paths.logsDirectory.hasSuffix("logs"))
    }
}
```
con:
```swift
        #expect(paths.logsDirectory.hasSuffix("logs"))
    }

    @Test func updateChecksAreOnByDefaultWithNoPreviousCheck() {
        let settings = CleanerSettings()
        #expect(settings.automaticUpdateChecks)
        #expect(settings.lastUpdateCheck == nil)
    }

    @Test func legacyFileWithoutUpdateFieldsKeepsItsValuesAndChecksUpdates() {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "LogsMinAgeDays": 7 }"#)
        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()
        #expect(settings.logsMinAgeDays == 7)
        #expect(settings.automaticUpdateChecks)
        #expect(settings.lastUpdateCheck == nil)
    }

    @Test func updateFieldsRoundTripUnderTheirKeys() throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.automaticUpdateChecks = false
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 1_790_000_000)
        try store.save(settings)

        let json = try savedJSON(fs)
        #expect(json["AutomaticUpdateChecks"] as? Bool == false)
        #expect(json["LastUpdateCheck"] != nil)
        let loaded = store.load()
        #expect(loaded.automaticUpdateChecks == false)
        #expect(loaded.lastUpdateCheck == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func neverCheckedLeavesNoLastCheckKey() throws {
        let fs = InMemoryFileSystem()
        try SettingsStore(fileSystem: fs, paths: Self.paths).save(CleanerSettings())
        #expect(try savedJSON(fs)["LastUpdateCheck"] == nil)
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find 'AppVersion' in scope`, `cannot find 'UpdateContext' in scope` e `value of type 'AppPaths' has no member 'updatesDirectory'`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Update/AppVersion.swift`:

```swift
/// La versione `MAJOR.MINOR.PATCH` dell'app e dei tag delle release (`vMAJOR.MINOR.PATCH`, lo
/// stesso formato che il workflow di release accetta). Si confronta campo per campo come numeri:
/// `0.10.0` è più recente di `0.9.0`. Un testo diverso non produce una versione.
public struct AppVersion: Sendable, Equatable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `1.2.3` o `v1.2.3`; niente prerelease, metadati, spazi o segni.
    public init?(_ text: String) {
        let digits = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let major = Self.number(parts[0]), let minor = Self.number(parts[1]),
              let patch = Self.number(parts[2]) else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    /// Da una a nove cifre ASCII: il valore entra sempre in un `Int`.
    private static func number(_ part: Substring) -> Int? {
        guard (1...9).contains(part.utf8.count), part.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(part)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// Il tag della release: `v` + versione.
    public var tag: String { "v" + description }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
```

Creare `MjmCleanerKit/Sources/CleanerCore/Update/UpdateContext.swift`:

```swift
/// Ciò che l'updater sa dell'app in esecuzione. Esiste solo per la build Release: le build Debug
/// (`com.mjm.cleaner.debug`) e la demo non si aggiornano mai, così una build di sviluppo non viene
/// sostituita da quella pubblicata.
public struct UpdateContext: Sendable, Equatable {
    public static let releaseBundleIdentifier = "com.mjm.cleaner"

    public let currentVersion: AppVersion
    /// Il bundle `.app` in esecuzione, quello che l'installazione sostituisce.
    public let bundlePath: String
    /// Il PID dell'app: lo script di sostituzione attende che termini.
    public let processIdentifier: Int32

    public init(currentVersion: AppVersion, bundlePath: String, processIdentifier: Int32) {
        self.currentVersion = currentVersion
        self.bundlePath = bundlePath
        self.processIdentifier = processIdentifier
    }

    /// `nil` per ogni bundle id diverso da quello della release e per una versione illeggibile. Il
    /// percorso perde la `/` finale che `Bundle.main.bundleURL` aggiunge alle cartelle.
    public static func make(
        bundleIdentifier: String?,
        shortVersion: String?,
        bundlePath: String,
        processIdentifier: Int32
    ) -> UpdateContext? {
        guard bundleIdentifier == releaseBundleIdentifier,
              let shortVersion, let version = AppVersion(shortVersion) else { return nil }
        return UpdateContext(
            currentVersion: version, bundlePath: PathText.trimmingTrailingSlashes(bundlePath), processIdentifier: processIdentifier)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Settings/AppPaths.swift`, sostituire:

```swift
    public var logsDirectory: String { PathText.join(supportDirectory, "logs") }
```
con:
```swift
    public var logsDirectory: String { PathText.join(supportDirectory, "logs") }
    /// Download, bundle estratti ed esito dell'ultima installazione degli aggiornamenti. Non sta in
    /// `~/Library/Caches`: la categoria «Cache di sistema» dell'app la cancellerebbe.
    public var updatesDirectory: String { PathText.join(supportDirectory, "updates") }
```

In `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`, sostituire:

```swift
/// Preferenze persistite in `settings.json`. Chiavi e valori predefiniti identici al C#; un campo
```
con:
```swift
import Foundation

/// Preferenze persistite in `settings.json`. Chiavi e valori predefiniti identici al C#; un campo
```

In `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`, sostituire:

```swift
    public var appearance = AppearancePreference.auto

    public init() {}
```
con:
```swift
    public var appearance = AppearancePreference.auto
    /// Controllo automatico delle release su GitHub: all'avvio e ogni 24 ore.
    public var automaticUpdateChecks = true
    /// L'ultimo controllo riuscito (con o senza novità); `nil` finché non ce n'è stato uno.
    public var lastUpdateCheck: Date?

    public init() {}
```

In `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`, sostituire:

```swift
        case appearance = "Appearance"
    }
```
con:
```swift
        case appearance = "Appearance"
        case automaticUpdateChecks = "AutomaticUpdateChecks"
        case lastUpdateCheck = "LastUpdateCheck"
    }
```

In `MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`, sostituire:

```swift
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? defaults.appearance
```
con:
```swift
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? defaults.appearance
        automaticUpdateChecks = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks) ?? defaults.automaticUpdateChecks
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck) ?? defaults.lastUpdateCheck
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 173 tests in 21 suites passed` e `Test run with 548 tests in 50 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerCoreTests/Update/AppVersionTests.swift \
  MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/AppVersion.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/UpdateContext.swift \
  MjmCleanerKit/Sources/CleanerCore/Settings/AppPaths.swift \
  MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift
git commit -m "feat(update): parse release versions and keep the update settings

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 2: Lettura della release più recente da GitHub

<!-- verifica: package -->

`HTTPClient` astrae la rete (implementazione `URLSessionHTTPClient`, effimera). `GitHubReleaseFeed` legge `/releases/latest` e restituisce una `AvailableRelease` solo se il tag è più recente e l'unico asset atteso ha un digest `sha256:`. La fixture è la risposta vera di `v0.1.0`, catturata il 2026-10-19 con `gh api` (campi `uploader` tolti).

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/Fixtures/latest-v0.1.0.json`
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift`
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/GitHubReleaseFeedTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/UpdateError.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/HTTPClient.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/ReleaseFeed.swift`
- Modify: `MjmCleanerKit/Package.swift`

**Interfaces:**
- Consumes: `AppVersion` (Task 1).
- Produces: `UpdateError` (`httpStatus(Int)`, `invalidResponse`, `invalidRelease(String)`, `digestMismatch`, `invalidBundle(String)`, `installFailed(String)`, `LocalizedError`).
- Produces: `HTTPResponse(statusCode:body:)`; `protocol HTTPClient { get(_:headers:) async throws -> HTTPResponse; download(_:to:progress:) async throws -> Int }`; `URLSessionHTTPClient()`.
- Produces: `AvailableRelease(version:pageURL:assetName:assetURL:size:sha256:)`, `.tag`, `AvailableRelease.assetName(for:)`; `protocol ReleaseFeed { latestRelease(newerThan:) async throws -> AvailableRelease? }`; `GitHubReleaseFeed(http:currentVersion:)`.
- Produces (test): `UpdateFixtures.data(_:)`, `releaseJSON(tag:assets:htmlURL:)`, `asset(_:url:size:digest:)`, `FakeHTTP`.

- [ ] **Step 1: Scrivere i test che falliscono**

In `MjmCleanerKit/Package.swift`, sostituire:

```swift
            // Le fixture JSON di Docker e di Xcode si leggono dal sorgente dei test (`#filePath`),
```
con:
```swift
            // Le fixture JSON di Docker, Xcode e aggiornamenti si leggono dal sorgente dei test (`#filePath`),
```

In `MjmCleanerKit/Package.swift`, sostituire:

```swift
exclude: ["Docker/Fixtures", "Xcode/Fixtures"]
```
con:
```swift
exclude: ["Docker/Fixtures", "Xcode/Fixtures", "Update/Fixtures"]
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/Fixtures/latest-v0.1.0.json`:

```json
{
  "url": "https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/416658184",
  "html_url": "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.1.0",
  "id": 416658184,
  "tag_name": "v0.1.0",
  "target_commitish": "main",
  "name": "v0.1.0",
  "draft": false,
  "prerelease": false,
  "created_at": "2026-10-18T19:27:15Z",
  "published_at": "2026-10-18T19:34:02Z",
  "assets": [
    {
      "url": "https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/assets/654300809",
      "id": 654300809,
      "node_id": "RA_kwDOUcI_H84m_9aJ",
      "name": "mjm.cleaner-v0.1.0-macos-universal.zip",
      "label": "",
      "content_type": "application/zip",
      "state": "uploaded",
      "size": 3188840,
      "digest": "sha256:6c1dfc5c886b1cbc8a0849770fe66c4da07247f1e82094aeaa29cddf48154d07",
      "download_count": 1,
      "created_at": "2026-10-18T19:34:01Z",
      "updated_at": "2026-10-18T19:34:01Z",
      "browser_download_url": "https://github.com/markjackmilian/mjm.cleaner/releases/download/v0.1.0/mjm.cleaner-v0.1.0-macos-universal.zip"
    }
  ],
  "tarball_url": "https://api.github.com/repos/markjackmilian/mjm.cleaner/tarball/v0.1.0",
  "zipball_url": "https://api.github.com/repos/markjackmilian/mjm.cleaner/zipball/v0.1.0",
  "body": "**Full Changelog**: https://github.com/markjackmilian/mjm.cleaner/compare/v0.0.4...v0.1.0"
}
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift`:

```swift
import Foundation
@testable import CleanerCore

/// Le fixture dell'updater, lette dal sorgente dei test come quelle di Docker e Xcode.
enum UpdateFixtures {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

/// Il JSON di `/releases/latest` con i soli campi che l'updater legge.
func releaseJSON(
    tag: String,
    assets: [[String: Any]]? = nil,
    htmlURL: String? = nil
) -> Data {
    let defaultAsset: [String: Any] = [
        "name": "mjm.cleaner-\(tag)-macos-universal.zip",
        "browser_download_url": "https://github.com/markjackmilian/mjm.cleaner/releases/download/\(tag)/mjm.cleaner-\(tag)-macos-universal.zip",
        "size": 3_188_840,
        "digest": "sha256:" + String(repeating: "ab", count: 32),
    ]
    let object: [String: Any] = [
        "tag_name": tag,
        "html_url": htmlURL ?? "https://github.com/markjackmilian/mjm.cleaner/releases/tag/\(tag)",
        "assets": assets ?? [defaultAsset],
    ]
    // Gli oggetti sono costruiti qui sopra: la serializzazione non può fallire.
    return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
}

func asset(_ name: String, url: String? = nil, size: Int64 = 10, digest: String? = "sha256:" + String(repeating: "ab", count: 32)) -> [String: Any] {
    var asset: [String: Any] = [
        "name": name,
        "browser_download_url": url ?? "https://github.com/markjackmilian/mjm.cleaner/releases/download/x/\(name)",
        "size": size,
    ]
    if let digest { asset["digest"] = digest }
    return asset
}

/// Rete finta: risponde a `get` con una risposta fissa e a `download` scrivendo `payload`.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    private let lock = NSLock()
    private var response: Result<HTTPResponse, any Error>
    private var payload: Data
    private var downloadStatus: Int
    private var failDownloadAfterWriting: (any Error)?
    private(set) var requests: [(URL, [String: String])] = []
    private(set) var downloads: [URL] = []

    init(status: Int = 200, body: Data = Data(), payload: Data = Data(), downloadStatus: Int = 200) {
        response = .success(HTTPResponse(statusCode: status, body: body))
        self.payload = payload
        self.downloadStatus = downloadStatus
    }

    func failGets(with error: any Error) {
        lock.withLock { response = .failure(error) }
    }

    func failDownloads(afterWriting error: any Error) {
        lock.withLock { failDownloadAfterWriting = error }
    }

    var downloadCount: Int { lock.withLock { downloads.count } }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try lock.withLock {
            requests.append((url, headers))
            return try response.get()
        }
    }

    func download(_ url: URL, to destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int {
        let (payload, status, failure) = lock.withLock { () -> (Data, Int, (any Error)?) in
            downloads.append(url)
            return (self.payload, downloadStatus, failDownloadAfterWriting)
        }
        try payload.write(to: URL(fileURLWithPath: destination))
        progress(Int64(payload.count))
        if let failure { throw failure }
        return status
    }
}
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/GitHubReleaseFeedTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct GitHubReleaseFeedTests {
    private static let v010 = AppVersion(major: 0, minor: 1, patch: 0)
    private static let v009 = AppVersion(major: 0, minor: 0, patch: 9)

    private func latest(_ body: Data, current: AppVersion = v009, status: Int = 200) async throws -> AvailableRelease? {
        try await GitHubReleaseFeed(http: FakeHTTP(status: status, body: body), currentVersion: current)
            .latestRelease(newerThan: current)
    }

    private func invalidRelease(_ body: Data) async {
        await #expect {
            try await latest(body, current: AppVersion(major: 0, minor: 0, patch: 1))
        } throws: { error in
            if case .invalidRelease = error as? UpdateError { true } else { false }
        }
    }

    @Test func readsTheRealResponseOfTheLatestRelease() async throws {
        let release = try #require(try await latest(try UpdateFixtures.data("latest-v0.1.0.json")))
        #expect(release.version == Self.v010)
        #expect(release.tag == "v0.1.0")
        #expect(release.assetName == "mjm.cleaner-v0.1.0-macos-universal.zip")
        #expect(release.assetURL.absoluteString
            == "https://github.com/markjackmilian/mjm.cleaner/releases/download/v0.1.0/mjm.cleaner-v0.1.0-macos-universal.zip")
        #expect(release.pageURL.absoluteString == "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.1.0")
        #expect(release.size == 3_188_840)
        #expect(release.sha256 == "6c1dfc5c886b1cbc8a0849770fe66c4da07247f1e82094aeaa29cddf48154d07")
    }

    @Test func sendsTheGitHubHeadersToTheLatestReleaseEndpoint() async throws {
        let http = FakeHTTP(body: releaseJSON(tag: "v0.1.0"))
        _ = try await GitHubReleaseFeed(http: http, currentVersion: Self.v009).latestRelease(newerThan: Self.v009)
        let (url, headers) = try #require(http.requests.first)
        #expect(url.absoluteString == "https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/latest")
        #expect(headers["Accept"] == "application/vnd.github+json")
        #expect(headers["User-Agent"] == "mjm.cleaner/0.0.9")
    }

    @Test(arguments: ["0.1.0", "0.1.1", "1.0.0"])
    func sameOrOlderReleaseMeansUpToDate(current: String) async throws {
        let version = try #require(AppVersion(current))
        #expect(try await latest(try UpdateFixtures.data("latest-v0.1.0.json"), current: version) == nil)
    }

    @Test func sameReleaseIsUpToDateEvenWithoutItsAsset() async throws {
        #expect(try await latest(releaseJSON(tag: "v0.1.0", assets: []), current: Self.v010) == nil)
    }

    @Test func uppercaseDigestIsNormalized() async throws {
        let body = releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", digest: "sha256:" + String(repeating: "AB", count: 32))])
        #expect(try await latest(body)?.sha256 == String(repeating: "ab", count: 32))
    }

    @Test func missingAssetIsAnInvalidRelease() async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: []))
    }

    @Test func assetOfAnotherTagIsAnInvalidRelease() async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.1.0-macos-universal.zip")]))
    }

    @Test func duplicatedAssetIsAnInvalidRelease() async {
        let name = "mjm.cleaner-v0.2.0-macos-universal.zip"
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset(name), asset(name)]))
    }

    @Test(arguments: [nil, "sha512:" + String(repeating: "ab", count: 32), "sha256:abc", "sha256:" + String(repeating: "zz", count: 32)] as [String?])
    func missingOrMalformedDigestIsAnInvalidRelease(digest: String?) async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", digest: digest)]))
    }

    @Test func plainHTTPDownloadIsAnInvalidRelease() async {
        let name = "mjm.cleaner-v0.2.0-macos-universal.zip"
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset(name, url: "http://github.com/\(name)")]))
    }

    @Test func emptyAssetIsAnInvalidRelease() async {
        await invalidRelease(releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", size: 0)]))
    }

    @Test(arguments: ["0.2.0", "v0.2", "v0.2.0-rc1", "nightly"])
    func tagOutsideTheReleaseFormatIsAnInvalidRelease(tag: String) async {
        await invalidRelease(releaseJSON(tag: tag))
    }

    @Test(arguments: [403, 404, 500])
    func nonOKStatusIsReported(status: Int) async {
        await #expect(throws: UpdateError.httpStatus(status)) {
            try await latest(releaseJSON(tag: "v0.2.0"), status: status)
        }
    }

    @Test func unreadableBodyIsAnInvalidResponse() async {
        await #expect(throws: UpdateError.invalidResponse) {
            try await latest(Data("<html>".utf8))
        }
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find type 'HTTPClient' in scope` e `cannot find type 'HTTPResponse' in scope`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Update/UpdateError.swift`:

```swift
import Foundation

/// Perché un controllo, un download, una verifica o un'installazione non sono riusciti. Il testo è
/// quello che l'app mostra (Impostazioni, avviso dopo un'installazione fallita).
public enum UpdateError: Error, Equatable, Sendable, LocalizedError {
    /// GitHub ha risposto con uno stato diverso da 200 (403 per il limite di richieste, 404, …).
    case httpStatus(Int)
    /// La risposta non è il JSON di una release.
    case invalidResponse
    /// La release più recente non rispetta il formato delle release dell'app.
    case invalidRelease(String)
    /// Lo SHA-256 del file scaricato è diverso dal digest pubblicato.
    case digestMismatch
    /// Il bundle estratto non è una build di mjm.cleaner per la versione attesa.
    case invalidBundle(String)
    /// L'installazione non è partita.
    case installFailed(String)

    public var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            String(localized: "GitHub ha risposto con lo stato HTTP \(status)", bundle: .module)
        case .invalidResponse:
            String(localized: "risposta di GitHub illeggibile", bundle: .module)
        case .invalidRelease(let reason):
            String(localized: "release non valida: \(reason)", bundle: .module)
        case .digestMismatch:
            String(localized: "il file scaricato non corrisponde al digest pubblicato", bundle: .module)
        case .invalidBundle(let reason):
            String(localized: "aggiornamento non valido: \(reason)", bundle: .module)
        case .installFailed(let reason):
            String(localized: "installazione non avviata: \(reason)", bundle: .module)
        }
    }
}
```

Creare `MjmCleanerKit/Sources/CleanerCore/Update/HTTPClient.swift`:

```swift
import Foundation

public struct HTTPResponse: Sendable, Equatable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

/// La rete dell'updater, astratta perché i test non la usino mai.
public protocol HTTPClient: Sendable {
    /// Una richiesta `GET`, con il corpo intero in memoria.
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse

    /// Scarica `url` nel file `destination`, che crea o sostituisce, e restituisce lo stato HTTP.
    /// `progress` riceve i byte scritti finora. Con uno stato diverso da 200 il file può restare
    /// parziale: lo cancella il chiamante.
    func download(_ url: URL, to destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int
}

/// `URLSession` effimera: niente cookie, cache o credenziali condivise con il resto del sistema.
public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration: configuration)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        return HTTPResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: data)
    }

    public func download(_ url: URL, to destination: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> Int {
        let (bytes, response) = try await session.bytes(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { return status }
        guard FileManager.default.createFile(atPath: destination, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: destination])
        }
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: destination))
        defer { try? handle.close() }
        var buffer = Data()
        buffer.reserveCapacity(1 << 16)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count == 1 << 16 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                progress(written)
            }
        }
        try handle.write(contentsOf: buffer)
        written += Int64(buffer.count)
        progress(written)
        return status
    }
}
```

Creare `MjmCleanerKit/Sources/CleanerCore/Update/ReleaseFeed.swift`:

```swift
import Foundation

/// Una release più recente dell'app, con l'unico asset da scaricare. Si salva in `release.json`
/// accanto allo ZIP scaricato, per riproporre l'aggiornamento al riavvio senza rete.
public struct AvailableRelease: Sendable, Equatable, Codable {
    public let version: AppVersion
    /// La pagina della release su GitHub («Novità»).
    public let pageURL: URL
    public let assetName: String
    public let assetURL: URL
    public let size: Int64
    /// Lo SHA-256 dell'asset in esadecimale minuscolo, dal campo `digest` dell'API.
    public let sha256: String

    public init(version: AppVersion, pageURL: URL, assetName: String, assetURL: URL, size: Int64, sha256: String) {
        self.version = version
        self.pageURL = pageURL
        self.assetName = assetName
        self.assetURL = assetURL
        self.size = size
        self.sha256 = sha256
    }

    public var tag: String { version.tag }

    /// Il nome dell'unico asset che il workflow di release pubblica per un tag.
    public static func assetName(for tag: String) -> String {
        "mjm.cleaner-\(tag)-macos-universal.zip"
    }
}

public protocol ReleaseFeed: Sendable {
    /// La release pubblicata più recente se è più recente di `current`, altrimenti `nil`.
    func latestRelease(newerThan current: AppVersion) async throws -> AvailableRelease?
}

/// `GET /repos/markjackmilian/mjm.cleaner/releases/latest`: GitHub esclude da sé bozze e
/// prerelease. Senza autenticazione il limite è di 60 richieste all'ora per indirizzo.
public struct GitHubReleaseFeed: ReleaseFeed {
    public static let latestAddress = "https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/latest"

    private let http: any HTTPClient
    private let userAgent: String

    public init(http: any HTTPClient, currentVersion: AppVersion) {
        self.http = http
        userAgent = "mjm.cleaner/\(currentVersion)"
    }

    public func latestRelease(newerThan current: AppVersion) async throws -> AvailableRelease? {
        guard let url = URL(string: Self.latestAddress) else { throw UpdateError.invalidResponse }
        let response = try await http.get(url, headers: [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": userAgent,
        ])
        guard response.statusCode == 200 else { throw UpdateError.httpStatus(response.statusCode) }
        return try Self.parse(response.body, newerThan: current)
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]
    }

    private struct Asset: Decodable {
        let name: String
        let browser_download_url: String
        let size: Int64
        let digest: String?
    }

    static func parse(_ body: Data, newerThan current: AppVersion) throws -> AvailableRelease? {
        let release: Release
        do {
            release = try JSONDecoder().decode(Release.self, from: body)
        } catch {
            throw UpdateError.invalidResponse
        }
        guard let version = AppVersion(release.tag_name), release.tag_name.hasPrefix("v") else {
            throw UpdateError.invalidRelease(String(localized: "tag «\(release.tag_name)» non nel formato vX.Y.Z", bundle: .module))
        }
        guard version > current else { return nil }

        let expectedName = AvailableRelease.assetName(for: version.tag)
        let matching = release.assets.filter { $0.name.utf8.elementsEqual(expectedName.utf8) }
        guard matching.count == 1, let asset = matching.first else {
            throw UpdateError.invalidRelease(String(localized: "manca l'asset \(expectedName)", bundle: .module))
        }
        guard let assetURL = httpsURL(asset.browser_download_url), let pageURL = httpsURL(release.html_url) else {
            throw UpdateError.invalidRelease(String(localized: "indirizzo non HTTPS", bundle: .module))
        }
        guard asset.size > 0 else {
            throw UpdateError.invalidRelease(String(localized: "asset vuoto", bundle: .module))
        }
        guard let sha256 = sha256Hex(asset.digest) else {
            throw UpdateError.invalidRelease(String(localized: "digest SHA-256 assente", bundle: .module))
        }
        return AvailableRelease(
            version: version, pageURL: pageURL, assetName: expectedName, assetURL: assetURL,
            size: asset.size, sha256: sha256)
    }

    private static func httpsURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.host() != nil else { return nil }
        return url
    }

    /// `sha256:` seguito da 64 cifre esadecimali, restituite in minuscolo.
    private static func sha256Hex(_ digest: String?) -> String? {
        guard let digest, digest.hasPrefix("sha256:") else { return nil }
        let hex = digest.dropFirst("sha256:".count).lowercased()
        guard hex.utf8.count == 64, hex.utf8.allSatisfy({ (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }) else {
            return nil
        }
        return hex
    }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 173 tests in 21 suites passed` e `Test run with 562 tests in 51 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Package.swift \
  MjmCleanerKit/Tests/CleanerCoreTests/Update/Fixtures/latest-v0.1.0.json \
  MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift \
  MjmCleanerKit/Tests/CleanerCoreTests/Update/GitHubReleaseFeedTests.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/UpdateError.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/HTTPClient.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/ReleaseFeed.swift
git commit -m "feat(update): read the latest GitHub release and its asset digest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Download con verifica SHA-256 e cache

<!-- verifica: package -->

`UpdateDownloader` scarica in `<updates>/<tag>/download.partial`, accetta il file solo se lo SHA-256 coincide, lo rinomina e salva `release.json`. Tiene una sola release in cache e la ritrova al riavvio con `cached(newerThan:)`.

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateDownloaderTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/UpdateDownloader.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `AvailableRelease`, `UpdateError` (Task 2), `AppVersion` (Task 1).
- Produces: `DownloadedUpdate(release:directory:zipPath:)`; `UpdateDownloader(http:updatesDirectory:)` con `download(_:progress:) async throws -> DownloadedUpdate`, `cached(newerThan:) -> DownloadedUpdate?`, `removeTagDirectories(keeping:)`, `static sha256(of:) throws -> String`.

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateDownloaderTests.swift`:

```swift
import CryptoKit
import Foundation
import Testing
@testable import CleanerCore

struct UpdateDownloaderTests {
    private static let payload = Data("contenuto dello zip".utf8)
    private static let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()

    private static func release(_ tag: String = "v0.2.0", sha256: String = payloadDigest) throws -> AvailableRelease {
        let version = try #require(AppVersion(tag))
        let name = AvailableRelease.assetName(for: tag)
        return AvailableRelease(
            version: version,
            pageURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/tag/\(tag)")),
            assetName: name,
            assetURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/download/\(tag)/\(name)")),
            size: Int64(payload.count),
            sha256: sha256)
    }

    private static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    @Test func hashesFilesAsLowercaseHex() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let file = try temp.file("a.zip", contents: "contenuto dello zip")
        #expect(try UpdateDownloader.sha256(of: file) == Self.payloadDigest)
    }

    @Test func keepsTheZipAndItsReleaseWhenTheDigestMatches() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let release = try Self.release()
        let progress = Recorder<Double>()
        let downloaded = try await UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
            .download(release) { progress.append($0) }

        #expect(downloaded.directory == temp.path + "/v0.2.0")
        #expect(downloaded.zipPath == temp.path + "/v0.2.0/mjm.cleaner-v0.2.0-macos-universal.zip")
        #expect(try Data(contentsOf: URL(fileURLWithPath: downloaded.zipPath)) == Self.payload)
        #expect(!Self.exists(temp.path + "/v0.2.0/download.partial"))
        let saved = try JSONDecoder().decode(AvailableRelease.self, from: Data(contentsOf: URL(fileURLWithPath: temp.path + "/v0.2.0/release.json")))
        #expect(saved == release)
        #expect(progress.values.last == 1)
    }

    @Test func wrongDigestDeletesTheDownload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let release = try Self.release(sha256: String(repeating: "0", count: 64))
        await #expect(throws: UpdateError.digestMismatch) {
            try await UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path).download(release) { _ in }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path + "/v0.2.0").isEmpty)
    }

    @Test func nonOKStatusDeletesThePartialFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        await #expect(throws: UpdateError.httpStatus(404)) {
            try await UpdateDownloader(http: FakeHTTP(payload: Self.payload, downloadStatus: 404), updatesDirectory: temp.path)
                .download(try Self.release()) { _ in }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path + "/v0.2.0").isEmpty)
    }

    @Test func interruptedDownloadDeletesThePartialFile() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let http = FakeHTTP(payload: Self.payload)
        http.failDownloads(afterWriting: CocoaError(.fileWriteOutOfSpace))
        await #expect(throws: CocoaError.self) {
            try await UpdateDownloader(http: http, updatesDirectory: temp.path).download(try Self.release()) { _ in }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: temp.path + "/v0.2.0").isEmpty)
    }

    @Test func verifiedZipAlreadyOnDiskIsNotDownloadedAgain() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let http = FakeHTTP(payload: Self.payload)
        let downloader = UpdateDownloader(http: http, updatesDirectory: temp.path)
        _ = try await downloader.download(try Self.release()) { _ in }
        _ = try await downloader.download(try Self.release()) { _ in }
        #expect(http.downloadCount == 1)
    }

    @Test func corruptedZipOnDiskIsDownloadedAgain() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("v0.2.0/mjm.cleaner-v0.2.0-macos-universal.zip", contents: "alterato")
        let http = FakeHTTP(payload: Self.payload)
        let downloaded = try await UpdateDownloader(http: http, updatesDirectory: temp.path).download(try Self.release()) { _ in }
        #expect(http.downloadCount == 1)
        #expect(try UpdateDownloader.sha256(of: downloaded.zipPath) == Self.payloadDigest)
    }

    @Test func downloadingARemovesOtherReleasesButKeepsInstallFiles() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("v0.1.5/mjm.cleaner-v0.1.5-macos-universal.zip", contents: "vecchio")
        try temp.file("install-result", contents: "ok v0.1.5")
        try temp.directory("non-un-tag")
        _ = try await UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path).download(try Self.release()) { _ in }
        #expect(!Self.exists(temp.path + "/v0.1.5"))
        #expect(Self.exists(temp.path + "/install-result"))
        #expect(Self.exists(temp.path + "/non-un-tag"))
    }

    @Test func cachedReturnsTheVerifiedNewerDownload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        let downloaded = try await downloader.download(try Self.release()) { _ in }
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == downloaded)
    }

    @Test func cachedDropsReleasesThatAreNoLongerNewer() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        _ = try await downloader.download(try Self.release()) { _ in }
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 2, patch: 0)) == nil)
        #expect(!Self.exists(temp.path + "/v0.2.0"))
    }

    @Test func cachedDropsAZipAlteredAfterTheDownload() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        let downloaded = try await downloader.download(try Self.release()) { _ in }
        try Data("alterato".utf8).write(to: URL(fileURLWithPath: downloaded.zipPath))
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == nil)
        #expect(!Self.exists(downloaded.directory))
    }

    @Test func cachedIgnoresAReleaseFileFromAnotherTag() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let downloader = UpdateDownloader(http: FakeHTTP(payload: Self.payload), updatesDirectory: temp.path)
        let downloaded = try await downloader.download(try Self.release()) { _ in }
        try FileManager.default.moveItem(atPath: downloaded.directory, toPath: temp.path + "/v0.3.0")
        #expect(downloader.cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == nil)
    }

    @Test func cachedWithoutAnUpdatesDirectoryIsNil() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        #expect(UpdateDownloader(http: FakeHTTP(), updatesDirectory: temp.path + "/manca").cached(newerThan: AppVersion(major: 0, minor: 1, patch: 0)) == nil)
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find 'UpdateDownloader' in scope`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Update/UpdateDownloader.swift`:

```swift
import CryptoKit
import Foundation

/// Uno ZIP scaricato il cui SHA-256 coincide con il digest pubblicato.
public struct DownloadedUpdate: Sendable, Equatable {
    public let release: AvailableRelease
    /// `<updates>/<tag>/`: tutto ciò che riguarda questa release.
    public let directory: String
    public let zipPath: String

    public init(release: AvailableRelease, directory: String, zipPath: String) {
        self.release = release
        self.directory = directory
        self.zipPath = zipPath
    }
}

/// Scarica l'asset in `<updates>/<tag>/`, lo accetta solo se lo SHA-256 coincide con il digest e
/// tiene una sola release in cache. Lavora sul disco vero con `FileManager`: la cartella è
/// dell'app (Application Support, protetta dalla deny-list) e serve rinominare, cosa che il
/// protocollo `FileSystem` del Core non offre.
public struct UpdateDownloader: Sendable {
    static let partialName = "download.partial"
    static let releaseFileName = "release.json"

    private let http: any HTTPClient
    private let updatesDirectory: String

    public init(http: any HTTPClient, updatesDirectory: String) {
        self.http = http
        self.updatesDirectory = updatesDirectory
    }

    /// `progress` riceve la frazione scaricata, fra 0 e 1.
    public func download(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> DownloadedUpdate {
        removeTagDirectories(keeping: release.tag)
        let directory = PathText.join(updatesDirectory, release.tag)
        let zipPath = PathText.join(directory, release.assetName)
        let partial = PathText.join(directory, Self.partialName)
        let manager = FileManager.default
        try manager.createDirectory(atPath: directory, withIntermediateDirectories: true)

        if manager.fileExists(atPath: zipPath), (try? Self.sha256(of: zipPath)) == release.sha256 {
            try writeRelease(release, in: directory)
            progress(1)
            return DownloadedUpdate(release: release, directory: directory, zipPath: zipPath)
        }
        try? manager.removeItem(atPath: zipPath)
        try? manager.removeItem(atPath: partial)

        let total = Double(max(release.size, 1))
        do {
            let status = try await http.download(release.assetURL, to: partial) { written in
                progress(min(Double(written) / total, 1))
            }
            guard status == 200 else { throw UpdateError.httpStatus(status) }
            guard try Self.sha256(of: partial) == release.sha256 else { throw UpdateError.digestMismatch }
            try manager.moveItem(atPath: partial, toPath: zipPath)
            try writeRelease(release, in: directory)
        } catch {
            try? manager.removeItem(atPath: partial)
            try? manager.removeItem(atPath: zipPath)
            throw error
        }
        return DownloadedUpdate(release: release, directory: directory, zipPath: zipPath)
    }

    /// Lo ZIP già scaricato di una release più recente di `current`, se `release.json` è leggibile
    /// e il digest coincide ancora. Le cartelle di ogni altra release si cancellano.
    public func cached(newerThan current: AppVersion) -> DownloadedUpdate? {
        let manager = FileManager.default
        var best: DownloadedUpdate?
        for tag in tagDirectories() {
            let directory = PathText.join(updatesDirectory, tag)
            guard let data = manager.contents(atPath: PathText.join(directory, Self.releaseFileName)),
                  let release = try? JSONDecoder().decode(AvailableRelease.self, from: data),
                  release.tag == tag, release.version > current,
                  release.assetName == AvailableRelease.assetName(for: tag) else { continue }
            let zipPath = PathText.join(directory, release.assetName)
            guard (try? Self.sha256(of: zipPath)) == release.sha256 else { continue }
            if best.map({ release.version > $0.release.version }) ?? true {
                best = DownloadedUpdate(release: release, directory: directory, zipPath: zipPath)
            }
        }
        removeTagDirectories(keeping: best?.release.tag)
        return best
    }

    /// Cancella le cartelle di tutte le release tranne `tag`; i file come `install-result` restano.
    public func removeTagDirectories(keeping tag: String?) {
        for other in tagDirectories() where other != tag {
            try? FileManager.default.removeItem(atPath: PathText.join(updatesDirectory, other))
        }
    }

    /// Le sottocartelle il cui nome è un tag `vX.Y.Z`: solo quelle sono dell'updater.
    private func tagDirectories() -> [String] {
        let manager = FileManager.default
        let names = (try? manager.contentsOfDirectory(atPath: updatesDirectory)) ?? []
        return names.sorted().filter { name in
            var isDirectory: ObjCBool = false
            return name.hasPrefix("v") && AppVersion(name) != nil
                && manager.fileExists(atPath: PathText.join(updatesDirectory, name), isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private func writeRelease(_ release: AvailableRelease, in directory: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(release).write(to: URL(fileURLWithPath: PathText.join(directory, Self.releaseFileName)), options: .atomic)
    }

    /// SHA-256 in esadecimale minuscolo, letto a blocchi da 1 MB.
    public static func sha256(of path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 173 tests in 21 suites passed` e `Test run with 575 tests in 52 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateDownloaderTests.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/UpdateDownloader.swift
git commit -m "feat(update): download the release asset and accept it only by its digest

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 4: Verifica del bundle estratto

<!-- verifica: package -->

`UpdateVerifier` estrae lo ZIP con `ditto` e accetta solo un unico `.app` con bundle id `com.mjm.cleaner`, versione uguale al tag, eseguibile in `Contents/MacOS`, firma valida (`codesign --verify --deep --strict`) e slice `arm64` e `x86_64` (`lipo -archs`). Ogni rifiuto cancella la cartella della release. Lo ZIP vero di `v0.1.0` contiene solo `mjm.cleaner.app` (nessuna `__MACOSX`), eseguibile `MjmCleaner`, `lipo` stampa `x86_64 arm64`.

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateVerifierTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/UpdateVerifier.swift`
- Modify: `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift`

**Interfaces:**
- Consumes: `ProcessRunning` (Core), `DownloadedUpdate` (Task 3), `UpdateContext.releaseBundleIdentifier` (Task 1).
- Produces: `VerifiedUpdate(release:bundlePath:)`; `UpdateVerifier(runner:)` con `verify(_:) async throws -> VerifiedUpdate`.
- Produces (test): `FakeUpdateTools`, `makeFakeBundle(name:identifier:version:executable:executableIsPresent:)`.

- [ ] **Step 1: Scrivere i test che falliscono**

In fondo a `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift`, aggiungere:

```swift

/// `ditto` finto: invece di estrarre crea il bundle descritto da `bundle`; `codesign` e `lipo`
/// rispondono con i valori indicati.
struct FakeUpdateTools: ProcessRunning {
    var bundle: @Sendable (String) throws -> Void
    var dittoExit: Int32 = 0
    var codesignExit: Int32 = 0
    var codesignTimesOut = false
    var archs = "x86_64 arm64\n"
    let calls = Recorder<[String]>()

    func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
        calls.append([executable] + arguments)
        switch executable {
        case "/usr/bin/ditto":
            if dittoExit == 0, let destination = arguments.last { try bundle(destination) }
            return ProcessResult(exitCode: dittoExit, standardOutput: "", standardError: "", timedOut: false)
        case "/usr/bin/codesign":
            return ProcessResult(exitCode: codesignTimesOut ? -1 : codesignExit, standardOutput: "", standardError: "", timedOut: codesignTimesOut)
        case "/usr/bin/lipo":
            return ProcessResult(exitCode: 0, standardOutput: archs, standardError: "", timedOut: false)
        default:
            return ProcessResult(exitCode: 127, standardOutput: "", standardError: "", timedOut: false)
        }
    }
}

/// Scrive in `destination` un bundle `name` con l'Info.plist e l'eseguibile indicati.
func makeFakeBundle(
    name: String = "mjm.cleaner.app",
    identifier: String = "com.mjm.cleaner",
    version: String = "0.2.0",
    executable: String = "MjmCleaner",
    executableIsPresent: Bool = true
) -> @Sendable (String) throws -> Void {
    { destination in
        let contents = destination + "/" + name + "/Contents"
        try FileManager.default.createDirectory(atPath: contents + "/MacOS", withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": identifier, "CFBundleShortVersionString": version, "CFBundleExecutable": executable,
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: URL(fileURLWithPath: contents + "/Info.plist"))
        if executableIsPresent {
            FileManager.default.createFile(atPath: contents + "/MacOS/MjmCleaner", contents: Data("bin".utf8), attributes: [.posixPermissions: 0o755])
        }
    }
}
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateVerifierTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct UpdateVerifierTests {
    private static func download(in temp: TemporaryDirectory) throws -> DownloadedUpdate {
        let name = AvailableRelease.assetName(for: "v0.2.0")
        let release = AvailableRelease(
            version: AppVersion(major: 0, minor: 2, patch: 0),
            pageURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.2.0")),
            assetName: name,
            assetURL: try #require(URL(string: "https://github.com/x/\(name)")),
            size: 3, sha256: String(repeating: "a", count: 64))
        let zip = try temp.file("v0.2.0/" + name, contents: "zip")
        return DownloadedUpdate(release: release, directory: temp.path + "/v0.2.0", zipPath: zip)
    }

    private func rejects(_ tools: FakeUpdateTools, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let download = try Self.download(in: temp)
        await #expect(sourceLocation: sourceLocation) {
            try await UpdateVerifier(runner: tools).verify(download)
        } throws: { error in
            if case .invalidBundle = error as? UpdateError { true } else { false }
        }
        #expect(!FileManager.default.fileExists(atPath: download.directory), "la cartella della release va cancellata", sourceLocation: sourceLocation)
    }

    @Test func acceptsTheUniversalReleaseBundleOfTheTag() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let download = try Self.download(in: temp)
        let tools = FakeUpdateTools(bundle: makeFakeBundle())
        let verified = try await UpdateVerifier(runner: tools).verify(download)

        let bundle = temp.path + "/v0.2.0/expanded/mjm.cleaner.app"
        #expect(verified == VerifiedUpdate(release: download.release, bundlePath: bundle))
        #expect(tools.calls.values == [
            ["/usr/bin/ditto", "-x", "-k", download.zipPath, temp.path + "/v0.2.0/expanded"],
            ["/usr/bin/codesign", "--verify", "--deep", "--strict", bundle],
            ["/usr/bin/lipo", "-archs", bundle + "/Contents/MacOS/MjmCleaner"],
        ])
    }

    @Test func zipThatDoesNotExtractIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), dittoExit: 1))
    }

    @Test func zipWithTwoItemsIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: { destination in
            try makeFakeBundle()(destination)
            FileManager.default.createFile(atPath: destination + "/extra", contents: Data())
        }))
    }

    @Test func zipWithoutAnAppIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(name: "mjm.cleaner")))
    }

    /// Il collegamento punta a un bundle che supererebbe ogni altro controllo: solo il tipo lo rifiuta.
    @Test func linkNamedLikeAnAppIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: { destination in
            let elsewhere = destination + "/../elsewhere"
            try makeFakeBundle()(elsewhere)
            try FileManager.default.createSymbolicLink(atPath: destination + "/mjm.cleaner.app", withDestinationPath: elsewhere + "/mjm.cleaner.app")
        }))
    }

    @Test func missingInfoPlistIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: { destination in
            try FileManager.default.createDirectory(atPath: destination + "/mjm.cleaner.app/Contents", withIntermediateDirectories: true)
        }))
    }

    @Test(arguments: ["com.mjm.cleaner.debug", "com.example.other"])
    func otherBundleIdentifierIsRejected(identifier: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(identifier: identifier)))
    }

    @Test(arguments: ["0.1.0", "0.2.1", "v0.2.0"])
    func versionOtherThanTheTagIsRejected(version: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(version: version)))
    }

    @Test func missingExecutableIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(executableIsPresent: false)))
    }

    @Test func executableOutsideMacOSIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(executable: "../MacOS/MjmCleaner")))
    }

    @Test func invalidSignatureIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), codesignExit: 1))
    }

    @Test func signatureCheckThatTimesOutIsRejected() async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), codesignTimesOut: true))
    }

    @Test(arguments: ["arm64\n", "x86_64\n", "", "arm64e x86_64\n"])
    func singleArchitectureBundleIsRejected(archs: String) async throws {
        try await rejects(FakeUpdateTools(bundle: makeFakeBundle(), archs: archs))
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find 'UpdateVerifier' in scope` e `cannot find 'VerifiedUpdate' in scope`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Update/UpdateVerifier.swift`:

```swift
import Foundation

/// Un bundle estratto da uno ZIP verificato, pronto da installare.
public struct VerifiedUpdate: Sendable, Equatable {
    public let release: AvailableRelease
    /// `<updates>/<tag>/expanded/<nome>.app`.
    public let bundlePath: String

    public init(release: AvailableRelease, bundlePath: String) {
        self.release = release
        self.bundlePath = bundlePath
    }
}

/// Estrae lo ZIP e accetta il bundle solo se è una build Release di mjm.cleaner per la versione
/// del tag, con firma valida e universale. Ogni controllo che fallisce cancella la cartella della
/// release (ZIP compreso): al giro successivo si riscarica da capo.
public struct UpdateVerifier: Sendable {
    static let expandedName = "expanded"

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func verify(_ download: DownloadedUpdate) async throws -> VerifiedUpdate {
        do {
            return try await check(download)
        } catch {
            try? FileManager.default.removeItem(atPath: download.directory)
            throw error
        }
    }

    private func check(_ download: DownloadedUpdate) async throws -> VerifiedUpdate {
        let manager = FileManager.default
        let expanded = PathText.join(download.directory, Self.expandedName)
        try? manager.removeItem(atPath: expanded)
        try manager.createDirectory(atPath: expanded, withIntermediateDirectories: true)

        guard try await succeeds("/usr/bin/ditto", ["-x", "-k", download.zipPath, expanded], timeout: .seconds(120)) else {
            throw invalid(String(localized: "lo ZIP non si estrae", bundle: .module))
        }

        let entries = try manager.contentsOfDirectory(atPath: expanded)
        guard entries.count == 1, let name = entries.first, name.hasSuffix(".app"),
              (try? manager.attributesOfItem(atPath: PathText.join(expanded, name))[.type] as? FileAttributeType) == .typeDirectory
        else {
            throw invalid(String(localized: "lo ZIP non contiene un solo bundle .app", bundle: .module))
        }
        let bundle = PathText.join(expanded, name)

        guard let data = manager.contents(atPath: PathText.join(bundle, "Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw invalid(String(localized: "Info.plist illeggibile", bundle: .module))
        }
        guard (info["CFBundleIdentifier"] as? String) == UpdateContext.releaseBundleIdentifier else {
            throw invalid(String(localized: "bundle id diverso da \(UpdateContext.releaseBundleIdentifier)", bundle: .module))
        }
        guard (info["CFBundleShortVersionString"] as? String) == download.release.version.description else {
            throw invalid(String(localized: "versione del bundle diversa da \(download.release.version.description)", bundle: .module))
        }
        guard let executableName = info["CFBundleExecutable"] as? String, !executableName.isEmpty,
              !executableName.contains("/"),
              manager.isExecutableFile(atPath: PathText.join(bundle, "Contents/MacOS/" + executableName))
        else {
            throw invalid(String(localized: "eseguibile mancante", bundle: .module))
        }
        let executable = PathText.join(bundle, "Contents/MacOS/" + executableName)

        guard try await succeeds("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle], timeout: .seconds(120)) else {
            throw invalid(String(localized: "firma del codice non valida", bundle: .module))
        }

        let archs = try await runner.run("/usr/bin/lipo", ["-archs", executable], timeout: .seconds(30))
        let found = Set(archs.standardOutput.split(whereSeparator: \.isWhitespace).map(String.init))
        guard archs.exitCode == 0, !archs.timedOut, found.isSuperset(of: ["arm64", "x86_64"]) else {
            throw invalid(String(localized: "il bundle non è universale (arm64 e x86_64)", bundle: .module))
        }

        return VerifiedUpdate(release: download.release, bundlePath: bundle)
    }

    private func succeeds(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> Bool {
        let result = try await runner.run(executable, arguments, timeout: timeout)
        return result.exitCode == 0 && !result.timedOut
    }

    private func invalid(_ reason: String) -> UpdateError {
        .invalidBundle(reason)
    }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 173 tests in 21 suites passed` e `Test run with 588 tests in 53 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift \
  MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateVerifierTests.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/UpdateVerifier.swift
git commit -m "feat(update): accept only the signed universal release bundle of the tag

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 5: Script di sostituzione del bundle

<!-- verifica: script -->

Lo script attende la fine dell'app, copia il bundle nuovo accanto a quello attuale, scambia i due con due `mv` (ripristinando il vecchio se il secondo fallisce), scrive `install-result` e `install.log` e riapre l'app. Il test usa bundle finti e percorsi con spazi e apostrofo. Il workflow di release lo esegue con gli altri test degli script.

**Files:**
- Create: `Scripts/update-install.test.sh`
- Create: `MjmCleanerKit/Sources/CleanerCore/Resources/update-install.sh`
- Modify: `.github/workflows/release-macos.yml`

**Interfaces:**
- Produces: `update-install.sh PID BUNDLE_ATTUALE BUNDLE_NUOVO TAG CARTELLA_UPDATES PASSI_DI_ATTESA`; esito `ok <tag>` o `failed <copy|move-old|move-new|rollback|wait>` in `CARTELLA_UPDATES/install-result`.

- [ ] **Step 1: Scrivere il test che fallisce**

Creare `Scripts/update-install.test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
INSTALL_SCRIPT="$SCRIPT_DIR/../MjmCleanerKit/Sources/CleanerCore/Resources/update-install.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/private/tmp}/update-install-test.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

[[ -f "$INSTALL_SCRIPT" ]] || fail "update-install.sh missing"

# Shim: `open` registra il percorso invece di aprire un'app; `mv` fallisce quando il primo
# argomento contiene FAIL_MV_MATCH. Tutto il resto viene dai comandi di sistema.
SHIMS="$TMP_ROOT/shims"
mkdir -p "$SHIMS"
cat > "$SHIMS/open" <<'SH'
#!/bin/sh
printf '%s\n' "$1" >> "$OPENED"
SH
cat > "$SHIMS/mv" <<'SH'
#!/bin/sh
case "$1" in
  *"${FAIL_MV_MATCH:-<none>}"*) echo "mv: simulated failure" >&2; exit 1 ;;
esac
exec /bin/mv "$@"
SH
chmod +x "$SHIMS/open" "$SHIMS/mv"

# Un caso: cartella «Applications» con il bundle attuale, cartella updates con il nuovo bundle.
# Gli spazi e l'apostrofo nei percorsi verificano che nulla venga reinterpretato dalla shell.
setup() {
  CASE="$TMP_ROOT/$1/l'utente con spazi"
  APPS="$CASE/Applications"
  UPDATES="$CASE/updates"
  TARGET="$APPS/mjm.cleaner.app"
  SOURCE="$UPDATES/v0.2.0/expanded/mjm.cleaner.app"
  mkdir -p "$TARGET/Contents" "$SOURCE/Contents"
  printf 'vecchio\n' > "$TARGET/Contents/version"
  printf 'nuovo\n' > "$SOURCE/Contents/version"
  export OPENED="$CASE/opened"
  : > "$OPENED"
}

run_install() {
  PATH="$SHIMS:/usr/bin:/bin:/usr/sbin:/sbin" /bin/sh "$INSTALL_SCRIPT" "$1" "$TARGET" "$SOURCE" v0.2.0 "$UPDATES" "${2:-150}"
}

# Un PID sicuramente terminato: quello di un processo appena atteso.
dead_pid() {
  /usr/bin/true &
  local pid=$!
  wait "$pid"
  printf '%s' "$pid"
}

# Sostituzione riuscita, dopo che il processo atteso è terminato.
setup success
sleep 1 &
waiting=$!
run_install "$waiting"
kill -0 "$waiting" 2>/dev/null && fail "installed before the process exited"
[[ "$(cat "$TARGET/Contents/version")" == nuovo ]] || fail "bundle not replaced"
[[ "$(cat "$UPDATES/install-result")" == "ok v0.2.0" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ ! -e "$UPDATES/v0.2.0" ]] || fail "release directory left behind"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging or old bundle left behind"
[[ "$(cat "$OPENED")" == "$TARGET" ]] || fail "app not reopened at its path"
grep -q "aggiornamento a v0.2.0" "$UPDATES/install.log" || fail "log not written"
printf 'PASS: replace and reopen\n'

# La seconda rinomina fallisce: torna il bundle vecchio, che viene riaperto.
setup rollback
FAIL_MV_MATCH=".mjm.cleaner-update-" run_install "$(dead_pid)"
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "old bundle not restored"
[[ "$(cat "$UPDATES/install-result")" == "failed move-new" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging left behind after rollback"
[[ -d "$SOURCE" ]] || fail "verified bundle removed after a failed install"
[[ "$(cat "$OPENED")" == "$TARGET" ]] || fail "old app not reopened"
printf 'PASS: rollback\n'

# La prima rinomina fallisce: il bundle attuale non viene toccato.
setup move_old
FAIL_MV_MATCH="Applications/mjm.cleaner.app" run_install "$(dead_pid)"
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched"
[[ "$(cat "$UPDATES/install-result")" == "failed move-old" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ -z "$(find "$APPS" -name '.mjm.cleaner-*' -maxdepth 1)" ]] || fail "staging left behind"
printf 'PASS: current bundle kept\n'

# Il nuovo bundle non si copia: niente cambia.
setup copy
rm -rf "$SOURCE"
run_install "$(dead_pid)" || true
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "current bundle touched"
[[ "$(cat "$UPDATES/install-result")" == "failed copy" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
printf 'PASS: copy failure\n'

# Il processo non termina entro il limite: nessuna modifica e nessuna riapertura.
setup timeout
sleep 30 &
alive=$!
if run_install "$alive" 3; then fail "timeout reported success"; fi
kill "$alive"
wait "$alive" 2>/dev/null || true
[[ "$(cat "$TARGET/Contents/version")" == vecchio ]] || fail "bundle replaced while the app was running"
[[ "$(cat "$UPDATES/install-result")" == "failed wait" ]] || fail "wrong result: $(cat "$UPDATES/install-result")"
[[ ! -s "$OPENED" ]] || fail "app reopened after a timeout"
printf 'PASS: wait timeout\n'
```

- [ ] **Step 2: Verificare che il test fallisca**

Run: `bash Scripts/update-install.test.sh`

Expected: `FAIL: update-install.sh missing`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Resources/update-install.sh`:

```bash
#!/bin/sh
# Sostituisce il bundle di mjm.cleaner con quello verificato e riapre l'app (spec
# 2026-10-19-app-updates-design.md, «Installazione»). Lo avvia l'app un attimo prima di chiudersi,
# con PATH=/usr/bin:/bin:/usr/sbin:/sbin; i percorsi arrivano solo come argomenti.
#
#   update-install.sh PID BUNDLE_ATTUALE BUNDLE_NUOVO TAG CARTELLA_UPDATES PASSI_DI_ATTESA
#
# Esito in CARTELLA_UPDATES/install-result («ok TAG» o «failed PASSO»), log in install.log.
set -u
trap '' HUP

pid=$1
target=$2
source=$3
tag=$4
updates=$5
limit=$6

log="$updates/install.log"
result="$updates/install-result"
parent=$(dirname -- "$target")
staging="$parent/.mjm.cleaner-update-$tag.app"
old="$parent/.mjm.cleaner-old-$tag.app"

note() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >>"$log"
}

# Scrive l'esito e riapre il bundle al percorso originale: il nuovo, o il vecchio dopo un ripristino.
finish() {
  printf '%s\n' "$1" >"$result"
  note "$1"
  open "$target" >>"$log" 2>&1 || note "riapertura non riuscita"
  exit 0
}

note "aggiornamento a $tag: attesa della fine del processo $pid"
steps=0
while kill -0 "$pid" 2>/dev/null; do
  steps=$((steps + 1))
  if [ "$steps" -ge "$limit" ]; then
    # L'app è ancora aperta: niente da toccare e niente da riaprire.
    printf 'failed wait\n' >"$result"
    note "il processo $pid non è terminato: aggiornamento annullato"
    exit 1
  fi
  sleep 0.2
done

rm -rf "$staging" "$old"
if ! ditto "$source" "$staging" >>"$log" 2>&1; then
  rm -rf "$staging"
  finish "failed copy"
fi
if ! mv "$target" "$old" >>"$log" 2>&1; then
  rm -rf "$staging"
  finish "failed move-old"
fi
if ! mv "$staging" "$target" >>"$log" 2>&1; then
  if mv "$old" "$target" >>"$log" 2>&1; then
    rm -rf "$staging"
    finish "failed move-new"
  fi
  finish "failed rollback"
fi
rm -rf "$old" "$updates/$tag"
finish "ok $tag"
```

In `.github/workflows/release-macos.yml`, sostituire:

```yaml
          bash Scripts/demo-xcode-preview.test.sh
```
con:
```yaml
          bash Scripts/demo-xcode-preview.test.sh
          bash Scripts/update-install.test.sh
```

- [ ] **Step 4: Verificare che il test passi**

Run: `bash Scripts/update-install.test.sh`

Expected, esattamente:

```
PASS: replace and reopen
PASS: rollback
PASS: current bundle kept
PASS: copy failure
PASS: wait timeout
```

Poi `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`: ancora `588` e `173`, perché lo script entra nel bundle delle risorse ma nessun test Swift lo usa ancora.

- [ ] **Step 5: Commit**

```bash
git add Scripts/update-install.test.sh \
  MjmCleanerKit/Sources/CleanerCore/Resources/update-install.sh \
  .github/workflows/release-macos.yml
git commit -m "feat(update): swap the app bundle in place with a rollback script

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 6: Prerequisiti e avvio dell'installazione

<!-- verifica: package -->

`UpdateInstaller.mode()` decide fra installazione sul posto e «Mostra nel Finder» (bundle non `.app`, App Translocation, cartella non scrivibile). `launch(_:)` copia lo script in una cartella temporanea e lo avvia staccato con `DetachedProcessLauncher`; `takeOutcome()` legge `install-result` una volta sola.

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateInstallerTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/UpdateInstaller.swift`
- Modify: `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift`

**Interfaces:**
- Consumes: `UpdateContext` (Task 1), `VerifiedUpdate` (Task 4), `update-install.sh` (Task 5).
- Produces: `InstallMode` (`.inPlace`, `.manual(reason:)`); `InstallOutcome` (`.succeeded(AppVersion)`, `.failed(step:)`); `protocol DetachedLaunching {{ launch(_:_:environment:) throws }}`; `DetachedProcessLauncher()`; `UpdateInstaller(context:updatesDirectory:launcher:)` con `mode()`, `launch(_:) throws`, `takeOutcome() -> InstallOutcome?`.
- Produces (test): `RecordingLauncher`.

- [ ] **Step 1: Scrivere i test che falliscono**

In fondo a `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift`, aggiungere:

```swift

/// Registra gli avvii staccati invece di eseguirli.
final class RecordingLauncher: DetachedLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private var launches: [(String, [String], [String: String])] = []

    var recorded: [(String, [String], [String: String])] { lock.withLock { launches } }

    func launch(_ executable: String, _ arguments: [String], environment: [String: String]) throws {
        lock.withLock { launches.append((executable, arguments, environment)) }
    }
}
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateInstallerTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

struct UpdateInstallerTests {
    private static func installer(bundle: String, updates: String, launcher: any DetachedLaunching = RecordingLauncher()) -> UpdateInstaller {
        UpdateInstaller(
            context: UpdateContext(currentVersion: AppVersion(major: 0, minor: 1, patch: 0), bundlePath: bundle, processIdentifier: 4242),
            updatesDirectory: updates,
            launcher: launcher)
    }

    private static func update(bundle: String) throws -> VerifiedUpdate {
        let name = AvailableRelease.assetName(for: "v0.2.0")
        let release = AvailableRelease(
            version: AppVersion(major: 0, minor: 2, patch: 0),
            pageURL: try #require(URL(string: "https://github.com/markjackmilian/mjm.cleaner/releases/tag/v0.2.0")),
            assetName: name, assetURL: try #require(URL(string: "https://github.com/x/\(name)")),
            size: 1, sha256: String(repeating: "a", count: 64))
        return VerifiedUpdate(release: release, bundlePath: bundle)
    }

    @Test func writableFolderInstallsInPlace() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        #expect(Self.installer(bundle: bundle, updates: temp.path + "/updates").mode() == .inPlace)
    }

    @Test func readOnlyFolderNeedsAManualInstall() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        chmod(temp.path + "/Applications", 0o555)
        guard case .manual = Self.installer(bundle: bundle, updates: temp.path + "/updates").mode() else {
            Issue.record("una cartella in sola lettura non permette l'installazione sul posto")
            return
        }
    }

    @Test func translocatedAppNeedsAManualInstall() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("AppTranslocation/ABC/d/mjm.cleaner.app")
        guard case .manual = Self.installer(bundle: bundle, updates: temp.path + "/updates").mode() else {
            Issue.record("un'app in App Translocation non si sostituisce sul posto")
            return
        }
    }

    @Test func executableOutsideABundleNeedsAManualInstall() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let binary = try temp.file("bin/MjmCleaner")
        guard case .manual = Self.installer(bundle: binary, updates: temp.path + "/updates").mode() else {
            Issue.record("senza bundle .app non c'è nulla da sostituire")
            return
        }
    }

    @Test func launchesACopyOfTheBundledScriptWithItsArgumentsOnly() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        let updates = try temp.directory("updates")
        try temp.file("updates/install-result", contents: "ok v0.1.0")
        let launcher = RecordingLauncher()
        let fresh = updates + "/v0.2.0/expanded/mjm.cleaner.app"
        try Self.installer(bundle: bundle, updates: updates, launcher: launcher).launch(try Self.update(bundle: fresh))

        let (executable, arguments, environment) = try #require(launcher.recorded.first)
        #expect(executable == "/bin/sh")
        #expect(Array(arguments.dropFirst()) == ["4242", bundle, fresh, "v0.2.0", updates, "150"])
        #expect(environment == ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"])
        let script = try #require(arguments.first)
        #expect(script.hasSuffix("/update-install.sh"))
        let bundled = try #require(Bundle.module.url(forResource: "update-install", withExtension: "sh"))
        #expect(try Data(contentsOf: URL(fileURLWithPath: script)) == Data(contentsOf: bundled))
        #expect(!FileManager.default.fileExists(atPath: updates + "/install-result"), "un esito vecchio va cancellato")
    }

    @Test func manualModeNeverLaunchesTheScript() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let bundle = try temp.directory("AppTranslocation/x/mjm.cleaner.app")
        let launcher = RecordingLauncher()
        #expect(throws: UpdateError.self) {
            try Self.installer(bundle: bundle, updates: temp.path, launcher: launcher).launch(try Self.update(bundle: "/x.app"))
        }
        #expect(launcher.recorded.isEmpty)
    }

    @Test(arguments: [
        ("ok v0.2.0\n", InstallOutcome.succeeded(AppVersion(major: 0, minor: 2, patch: 0))),
        ("failed move-new\n", InstallOutcome.failed(step: "move-new")),
    ])
    func readsTheOutcomeOnceAndDeletesIt(text: String, expected: InstallOutcome) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("install-result", contents: text)
        let installer = Self.installer(bundle: "/Applications/mjm.cleaner.app", updates: temp.path)
        #expect(installer.takeOutcome() == expected)
        #expect(installer.takeOutcome() == nil)
    }

    @Test(arguments: ["", "ok", "ok 0.2", "boh v0.2.0", "failed a b"])
    func unreadableOutcomeIsIgnored(text: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("install-result", contents: text)
        #expect(Self.installer(bundle: "/Applications/mjm.cleaner.app", updates: temp.path).takeOutcome() == nil)
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find type 'DetachedLaunching' in scope`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Update/UpdateInstaller.swift`:

```swift
import Foundation

/// Come si può installare l'aggiornamento verificato.
public enum InstallMode: Sendable, Equatable {
    /// «Installa e riavvia»: lo script sostituisce il bundle sul posto.
    case inPlace
    /// «Mostra nel Finder»: il bundle va sostituito a mano, per il motivo indicato.
    case manual(reason: String)
}

/// L'esito dell'ultima installazione, scritto dallo script in `install-result`.
public enum InstallOutcome: Sendable, Equatable {
    case succeeded(AppVersion)
    /// Il passo dello script che non è riuscito (`copy`, `move-old`, `move-new`, `rollback`, `wait`).
    case failed(step: String)
}

/// Avvia un processo senza attenderlo: deve sopravvivere alla chiusura dell'app.
public protocol DetachedLaunching: Sendable {
    func launch(_ executable: String, _ arguments: [String], environment: [String: String]) throws
}

/// `Process` con input e output su `/dev/null`: alla chiusura dell'app il figlio passa a launchd e
/// continua; lo script ignora anche SIGHUP.
public struct DetachedProcessLauncher: DetachedLaunching {
    public init() {}

    public func launch(_ executable: String, _ arguments: [String], environment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}

/// Prerequisiti, avvio dello script di sostituzione (`Resources/update-install.sh`) ed esito.
public struct UpdateInstaller: Sendable {
    static let resultFileName = "install-result"
    /// Passi da 0,2 s con cui lo script attende la fine dell'app: 30 secondi.
    static let waitSteps = 150
    /// Il PATH dello script: solo i comandi di sistema, mai quelli dell'ambiente dell'utente.
    static let scriptEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    private let context: UpdateContext
    private let updatesDirectory: String
    private let launcher: any DetachedLaunching

    public init(context: UpdateContext, updatesDirectory: String, launcher: any DetachedLaunching) {
        self.context = context
        self.updatesDirectory = updatesDirectory
        self.launcher = launcher
    }

    public func mode() -> InstallMode {
        let bundle = context.bundlePath
        guard bundle.hasSuffix(".app"), let parent = PathText.parent(bundle) else {
            return .manual(reason: String(localized: "l'app non gira da un bundle .app", bundle: .module))
        }
        if bundle.contains("/AppTranslocation/") {
            return .manual(reason: String(
                localized: "macOS esegue l'app da una posizione temporanea (App Translocation): spostala nella cartella Applicazioni",
                bundle: .module))
        }
        guard FileManager.default.isWritableFile(atPath: parent) else {
            return .manual(reason: String(localized: "la cartella \(parent) non è scrivibile", bundle: .module))
        }
        return .inPlace
    }

    /// Copia lo script in una cartella temporanea propria e lo avvia staccato; poi l'app deve
    /// chiudersi entro 30 secondi.
    public func launch(_ update: VerifiedUpdate) throws {
        if case .manual(let reason) = mode() { throw UpdateError.installFailed(reason) }
        guard let source = Bundle.module.url(forResource: "update-install", withExtension: "sh") else {
            throw UpdateError.installFailed(String(localized: "script di installazione mancante", bundle: .module))
        }
        let manager = FileManager.default
        let directory = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: URL(fileURLWithPath: updatesDirectory, isDirectory: true), create: true)
        let script = directory.appendingPathComponent("update-install.sh")
        try manager.copyItem(at: source, to: script)

        // Un esito vecchio non deve passare per quello di questa installazione.
        try? manager.removeItem(atPath: PathText.join(updatesDirectory, Self.resultFileName))
        try launcher.launch("/bin/sh", [
            script.path(percentEncoded: false),
            String(context.processIdentifier),
            context.bundlePath,
            update.bundlePath,
            update.release.tag,
            updatesDirectory,
            String(Self.waitSteps),
        ], environment: Self.scriptEnvironment)
    }

    /// L'esito lasciato dall'ultima installazione, letto una volta sola: il file si cancella.
    public func takeOutcome() -> InstallOutcome? {
        let path = PathText.join(updatesDirectory, Self.resultFileName)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        try? FileManager.default.removeItem(atPath: path)
        let words = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count == 2 else { return nil }
        switch words[0] {
        case "ok": return AppVersion(words[1]).map(InstallOutcome.succeeded)
        case "failed": return .failed(step: words[1])
        default: return nil
        }
    }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 173 tests in 21 suites passed` e `Test run with 596 tests in 54 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateTestSupport.swift \
  MjmCleanerKit/Tests/CleanerCoreTests/Update/UpdateInstallerTests.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/UpdateInstaller.swift
git commit -m "feat(update): check the install location and launch the swap script detached

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 7: La facciata `AppUpdater`

<!-- verifica: package -->

Compone feed, downloader, verificatore e installer per l'app in esecuzione. Le parti sono provate nei propri test; qui si prova il collegamento, compresa la ripresa al riavvio e la pulizia quando l'app è aggiornata.

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerCoreTests/Update/AppUpdaterTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerCore/Update/AppUpdater.swift`

**Interfaces:**
- Consumes: tutto il Core dei Task 1–6.
- Produces: `protocol AppUpdating: Sendable` con `currentVersion`, `takeInstallOutcome()`, `cachedUpdate() async -> VerifiedUpdate?`, `check() async throws -> AvailableRelease?`, `prepare(_:progress:) async throws -> VerifiedUpdate`, `installMode() -> InstallMode`, `install(_:) throws`; `AppUpdater(context:paths:http:runner:launcher:)`.

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Update/AppUpdaterTests.swift`:

```swift
import CryptoKit
import Foundation
import Testing
@testable import CleanerCore

/// La composizione: le parti sono verificate nei propri test, qui si controlla che siano collegate.
struct AppUpdaterTests {
    private static let payload = Data("zip della v0.2.0".utf8)

    private static func feedBody() -> Data {
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return releaseJSON(tag: "v0.2.0", assets: [asset("mjm.cleaner-v0.2.0-macos-universal.zip", size: Int64(payload.count), digest: "sha256:" + digest)])
    }

    private static func updater(in temp: TemporaryDirectory, current: AppVersion = AppVersion(major: 0, minor: 1, patch: 0), launcher: RecordingLauncher = RecordingLauncher()) throws -> AppUpdater {
        let bundle = try temp.directory("Applications/mjm.cleaner.app")
        return AppUpdater(
            context: UpdateContext(currentVersion: current, bundlePath: bundle, processIdentifier: 7),
            paths: AppPaths(supportDirectory: temp.path + "/support"),
            http: FakeHTTP(body: feedBody(), payload: payload),
            runner: FakeUpdateTools(bundle: makeFakeBundle()),
            launcher: launcher)
    }

    @Test func checkDownloadVerifyAndInstallTheNewerRelease() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let launcher = RecordingLauncher()
        let updater = try Self.updater(in: temp, launcher: launcher)

        let release = try #require(try await updater.check())
        #expect(release.tag == "v0.2.0")
        let verified = try await updater.prepare(release) { _ in }
        #expect(verified.bundlePath == temp.path + "/support/updates/v0.2.0/expanded/mjm.cleaner.app")
        #expect(updater.installMode() == .inPlace)
        try updater.install(verified)
        #expect(launcher.recorded.count == 1)
    }

    @Test func cachedUpdateSurvivesARestart() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let first = try Self.updater(in: temp)
        let release = try #require(try await first.check())
        let verified = try await first.prepare(release) { _ in }

        #expect(await (try Self.updater(in: temp)).cachedUpdate() == verified)
    }

    @Test func upToDateCheckClearsLeftoverDownloads() async throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let old = try Self.updater(in: temp)
        _ = try await old.prepare(try #require(try await old.check())) { _ in }

        let current = try Self.updater(in: temp, current: AppVersion(major: 0, minor: 2, patch: 0))
        #expect(try await current.check() == nil)
        #expect(!FileManager.default.fileExists(atPath: temp.path + "/support/updates/v0.2.0"))
    }

    @Test func installOutcomeIsReadFromTheUpdatesDirectory() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.file("support/updates/install-result", contents: "failed copy\n")
        #expect(try Self.updater(in: temp).takeInstallOutcome() == .failed(step: "copy"))
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find 'AppUpdater' in scope`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Update/AppUpdater.swift`:

```swift
import Foundation

/// Ciò che il modello degli aggiornamenti chiede al Core: un protocollo, così i test delle
/// Features usano un doppio.
public protocol AppUpdating: Sendable {
    var currentVersion: AppVersion { get }
    /// L'esito dell'installazione precedente, una volta sola.
    func takeInstallOutcome() -> InstallOutcome?
    /// Un aggiornamento già scaricato in una sessione precedente, verificato di nuovo.
    func cachedUpdate() async -> VerifiedUpdate?
    /// La release più recente, se è più recente della versione in uso.
    func check() async throws -> AvailableRelease?
    /// Download e verifica; `progress` riceve la frazione scaricata.
    func prepare(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> VerifiedUpdate
    func installMode() -> InstallMode
    /// Avvia lo script di sostituzione; subito dopo l'app deve chiudersi.
    func install(_ update: VerifiedUpdate) throws
}

/// La composizione di feed, downloader, verificatore e installer per l'app in esecuzione.
public struct AppUpdater: AppUpdating {
    private let context: UpdateContext
    private let feed: any ReleaseFeed
    private let downloader: UpdateDownloader
    private let verifier: UpdateVerifier
    private let installer: UpdateInstaller

    public init(
        context: UpdateContext,
        paths: AppPaths,
        http: any HTTPClient,
        runner: any ProcessRunning,
        launcher: any DetachedLaunching
    ) {
        self.context = context
        feed = GitHubReleaseFeed(http: http, currentVersion: context.currentVersion)
        downloader = UpdateDownloader(http: http, updatesDirectory: paths.updatesDirectory)
        verifier = UpdateVerifier(runner: runner)
        installer = UpdateInstaller(context: context, updatesDirectory: paths.updatesDirectory, launcher: launcher)
    }

    public var currentVersion: AppVersion { context.currentVersion }

    public func takeInstallOutcome() -> InstallOutcome? {
        installer.takeOutcome()
    }

    public func cachedUpdate() async -> VerifiedUpdate? {
        guard let download = downloader.cached(newerThan: context.currentVersion) else { return nil }
        return try? await verifier.verify(download)
    }

    public func check() async throws -> AvailableRelease? {
        let release = try await feed.latestRelease(newerThan: context.currentVersion)
        if release == nil {
            downloader.removeTagDirectories(keeping: nil)
        }
        return release
    }

    public func prepare(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> VerifiedUpdate {
        try await verifier.verify(try await downloader.download(release, progress: progress))
    }

    public func installMode() -> InstallMode {
        installer.mode()
    }

    public func install(_ update: VerifiedUpdate) throws {
        try installer.launch(update)
    }
}
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 173 tests in 21 suites passed` e `Test run with 600 tests in 55 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerCoreTests/Update/AppUpdaterTests.swift \
  MjmCleanerKit/Sources/CleanerCore/Update/AppUpdater.swift
git commit -m "feat(update): compose feed, download, verification and install

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 8: Modello degli aggiornamenti e collegamento a ambiente, finestra e Impostazioni

<!-- verifica: package -->

`UpdateModel` tiene stato e pianificazione e offre le azioni del banner. `AppEnvironment` riceve un `updater` opzionale (`live(paths:update:…)`), `MainModel` crea il modello solo con updater e host e gli passa `isCleaning`, `SettingsModel` salva l'interruttore.

**Files:**
- Create: `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/UpdateDoubles.swift`
- Create: `MjmCleanerKit/Tests/CleanerFeaturesTests/UpdateModelTests.swift`
- Create: `MjmCleanerKit/Sources/CleanerFeatures/Update/UpdateModel.swift`
- Modify: `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`

**Interfaces:**
- Consumes: `AppUpdating`, `VerifiedUpdate`, `AvailableRelease`, `InstallMode`, `InstallOutcome`, `UpdateContext`, `AppUpdater`, `URLSessionHTTPClient`, `DetachedProcessLauncher` (Core).
- Produces: `@MainActor protocol UpdateHosting {{ terminate(); reveal(_ path: String); open(_ url: URL) }}`.
- Produces: `UpdateModel(updater:settings:clock:host:)` con `state`, `isBannerDismissed`, `installFailureText`, `isCleaning`, `currentVersionText`, `lastCheckText`, `isBusy`, `readyUpdate`, `isBannerVisible`, `installMode`, `installBlockedReason`, `bannerTitle`, `statusText`, `hasFailed`, `start()`, `checkIfDue()`, `checkNow()`, `later()`, `install()`, `revealUpdate()`, `openReleaseNotes()`, `dismissInstallFailure()`.
- Produces: `AppEnvironment.updater`, `AppEnvironment.live(paths:update:home:tempDirectory:)`; `MainModel(environment:appearance:folders:updateHost:)`, `MainModel.updates`, `MainModel.isCleaning`; `SettingsModel.automaticUpdateChecks`.

- [ ] **Step 1: Scrivere i test che falliscono**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
    xcode: any XcodeCleanupServing = IdleXcode()
) throws -> AppEnvironment {
```
con:
```swift
    xcode: any XcodeCleanupServing = IdleXcode(),
    updater: (any AppUpdating)? = nil
) throws -> AppEnvironment {
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
        expander: try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/private/var/folders/zz/T"))
}
```
con:
```swift
        expander: try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/private/var/folders/zz/T"),
        updater: updater)
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
        var executed: [[DockerCandidate]] = []
    }
```
con:
```swift
        var executed: [[DockerCandidate]] = []
        var holdsExecution = false
    }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
    func respond(with result: Result<DockerCleanResult, any Error>) { state.withLock { $0.executeResult = result } }
```
con:
```swift
    func respond(with result: Result<DockerCleanResult, any Error>) { state.withLock { $0.executeResult = result } }

    /// Con `holdExecution()` l'esecuzione apre `executionStarted` e resta sospesa finché il test non
    /// apre `executionReleased` (al massimo 5 secondi).
    let executionStarted = Gate<Void>()
    let executionReleased = Gate<Void>()
    func holdExecution() { state.withLock { $0.holdsExecution = true } }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
        let result = state.withLock { state -> Result<DockerCleanResult, any Error> in
            state.executed.append(selected)
            return state.executeResult
        }
```
con:
```swift
        let (result, holds) = state.withLock { state -> (Result<DockerCleanResult, any Error>, Bool) in
            state.executed.append(selected)
            return (state.executeResult, state.holdsExecution)
        }
        executionStarted.open()
        if holds { _ = await executionReleased.wait(within: .seconds(5)) }
```

Creare `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/UpdateDoubles.swift`:

```swift
import CleanerCore
import CleanerFeatures
import Foundation
import Synchronization
import Testing

/// Updater finto: risponde con i valori impostati e conta le chiamate. Con `holdChecks` il
/// controllo resta sospeso finché il test non apre `checkReleased`.
final class FakeUpdater: AppUpdating {
    private struct State {
        var outcome: InstallOutcome?
        var cached: VerifiedUpdate?
        var check: Result<AvailableRelease?, UpdateError> = .success(nil)
        var prepare: Result<VerifiedUpdate, UpdateError>?
        var mode = InstallMode.inPlace
        var installFailure: UpdateError?
        var checks = 0
        var installs: [VerifiedUpdate] = []
        var holdChecks = false
    }

    private let state = Mutex(State())
    let checkStarted = Gate<Void>()
    let checkReleased = Gate<Void>()

    var currentVersion: AppVersion { AppVersion(major: 0, minor: 1, patch: 0) }

    var checks: Int { state.withLock { $0.checks } }
    var installs: [VerifiedUpdate] { state.withLock { $0.installs } }

    func setOutcome(_ outcome: InstallOutcome?) { state.withLock { $0.outcome = outcome } }
    func setCached(_ update: VerifiedUpdate?) { state.withLock { $0.cached = update } }
    func setCheck(_ result: Result<AvailableRelease?, UpdateError>) { state.withLock { $0.check = result } }
    func setPrepare(_ result: Result<VerifiedUpdate, UpdateError>) { state.withLock { $0.prepare = result } }
    func setMode(_ mode: InstallMode) { state.withLock { $0.mode = mode } }
    func failInstalls(with error: UpdateError) { state.withLock { $0.installFailure = error } }
    func holdChecks() { state.withLock { $0.holdChecks = true } }

    func takeInstallOutcome() -> InstallOutcome? {
        state.withLock { state in
            defer { state.outcome = nil }
            return state.outcome
        }
    }

    func cachedUpdate() async -> VerifiedUpdate? {
        state.withLock { $0.cached }
    }

    func check() async throws -> AvailableRelease? {
        let (result, hold) = state.withLock { state in
            state.checks += 1
            return (state.check, state.holdChecks)
        }
        checkStarted.open()
        if hold { try await checkReleased.wait() }
        return try result.get()
    }

    func prepare(_ release: AvailableRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> VerifiedUpdate {
        progress(0.5)
        let result = state.withLock { $0.prepare } ?? .success(VerifiedUpdate(release: release, bundlePath: "/tmp/updates/\(release.tag)/expanded/mjm.cleaner.app"))
        return try result.get()
    }

    func installMode() -> InstallMode {
        state.withLock { $0.mode }
    }

    func install(_ update: VerifiedUpdate) throws {
        try state.withLock { state in
            if let failure = state.installFailure { throw failure }
            state.installs.append(update)
        }
    }
}

@MainActor
final class FakeUpdateHost: UpdateHosting {
    private(set) var terminations = 0
    private(set) var revealed: [String] = []
    private(set) var opened: [URL] = []

    func terminate() { terminations += 1 }
    func reveal(_ path: String) { revealed.append(path) }
    func open(_ url: URL) { opened.append(url) }
}

/// Una release `v0.2.0` per i test dei modelli.
func makeRelease(_ tag: String = "v0.2.0") -> AvailableRelease {
    let version = AppVersion(tag) ?? AppVersion(major: 0, minor: 2, patch: 0)
    let name = AvailableRelease.assetName(for: tag)
    return AvailableRelease(
        version: version,
        pageURL: URL(fileURLWithPath: "/").appending(path: "release-\(tag)"),
        assetName: name,
        assetURL: URL(fileURLWithPath: "/").appending(path: name),
        size: 10,
        sha256: String(repeating: "a", count: 64))
}

func makeVerified(_ tag: String = "v0.2.0") -> VerifiedUpdate {
    VerifiedUpdate(release: makeRelease(tag), bundlePath: "/tmp/updates/\(tag)/expanded/mjm.cleaner.app")
}
```

Creare `MjmCleanerKit/Tests/CleanerFeaturesTests/UpdateModelTests.swift`:

```swift
import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

@MainActor
struct UpdateModelTests {
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private struct Fixture {
        let model: UpdateModel
        let updater: FakeUpdater
        let store: FakeSettingsStore
        let host: FakeUpdateHost
    }

    private func create(_ change: (inout CleanerSettings) -> Void = { _ in }, updater: FakeUpdater = FakeUpdater()) -> Fixture {
        var settings = CleanerSettings()
        change(&settings)
        let store = FakeSettingsStore(settings)
        let host = FakeUpdateHost()
        let model = UpdateModel(updater: updater, settings: store, clock: FixedWallClock(now: Self.now), host: host)
        return Fixture(model: model, updater: updater, store: store, host: host)
    }

    private func newerRelease() -> FakeUpdater {
        let updater = FakeUpdater()
        updater.setCheck(.success(makeRelease()))
        return updater
    }

    // MARK: Avvio e pianificazione

    @Test func firstLaunchChecksDownloadsAndProposesTheUpdate() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()

        #expect(fixture.model.state == .ready(makeVerified()))
        #expect(fixture.model.isBannerVisible)
        #expect(fixture.store.current.lastUpdateCheck == Self.now)
    }

    @Test func startRunsOnlyOnce() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        await fixture.model.start()
        #expect(fixture.updater.checks == 1)
    }

    @Test func automaticCheckWaitsTwentyFourHours() async {
        let fixture = create({ $0.lastUpdateCheck = Self.now.addingTimeInterval(-23 * 3600) }, updater: newerRelease())
        await fixture.model.checkIfDue()
        #expect(fixture.updater.checks == 0)
    }

    @Test func automaticCheckRunsAfterTwentyFourHours() async {
        let fixture = create({ $0.lastUpdateCheck = Self.now.addingTimeInterval(-24 * 3600) }, updater: newerRelease())
        await fixture.model.checkIfDue()
        #expect(fixture.updater.checks == 1)
    }

    @Test func disabledAutomaticChecksNeverRunButCheckNowDoes() async {
        let fixture = create({ $0.automaticUpdateChecks = false })
        await fixture.model.start()
        #expect(fixture.updater.checks == 0)

        await fixture.model.checkNow()
        #expect(fixture.updater.checks == 1)
        #expect(fixture.model.state == .upToDate)
    }

    @Test func automaticUpToDateStaysQuietAndRecordsTheCheck() async {
        let fixture = create()
        await fixture.model.checkIfDue()
        #expect(fixture.model.state == .idle)
        #expect(fixture.store.current.lastUpdateCheck == Self.now)
    }

    @Test func automaticFailureStaysQuietAndRetriesNextTime() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.checkIfDue()

        #expect(fixture.model.state == .idle)
        #expect(fixture.store.current.lastUpdateCheck == nil)
        await fixture.model.checkIfDue()
        #expect(updater.checks == 2)
    }

    @Test func manualFailureShowsTheReason() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.checkNow()
        #expect(fixture.model.state == .failed(UpdateError.httpStatus(403).errorDescription ?? ""))
    }

    @Test func automaticDownloadFailureStaysQuietButTheCheckCounts() async {
        let updater = newerRelease()
        updater.setPrepare(.failure(.digestMismatch))
        let fixture = create(updater: updater)
        await fixture.model.checkIfDue()
        #expect(fixture.model.state == .idle)
        #expect(fixture.store.current.lastUpdateCheck == Self.now)
    }

    @Test func manualDownloadFailureShowsTheReason() async {
        let updater = newerRelease()
        updater.setPrepare(.failure(.invalidBundle("firma del codice non valida")))
        let fixture = create(updater: updater)
        await fixture.model.checkNow()
        #expect(fixture.model.state == .failed(UpdateError.invalidBundle("firma del codice non valida").errorDescription ?? ""))
    }

    @Test func onlyOneCheckAtATime() async throws {
        let updater = newerRelease()
        updater.holdChecks()
        let fixture = create(updater: updater)
        let first = Task { await fixture.model.checkNow() }
        try await updater.checkStarted.wait()

        #expect(fixture.model.isBusy)
        await fixture.model.checkNow()
        await fixture.model.checkIfDue()
        updater.checkReleased.open()
        await first.value
        #expect(updater.checks == 1)
    }

    @Test func downloadedUpdateFromAPreviousSessionIsProposedWithoutChecking() async {
        let updater = newerRelease()
        updater.setCached(makeVerified("v0.3.0"))
        let fixture = create(updater: updater)
        await fixture.model.start()
        #expect(fixture.model.state == .ready(makeVerified("v0.3.0")))
        #expect(updater.checks == 0)
    }

    @Test func failedInstallIsReportedOnceAtLaunch() async {
        let updater = FakeUpdater()
        updater.setOutcome(.failed(step: "move-new"))
        let fixture = create(updater: updater)
        await fixture.model.start()

        let text = fixture.model.installFailureText ?? ""
        #expect(text.contains("move-new"))
        #expect(text.contains("0.1.0"))
        fixture.model.dismissInstallFailure()
        #expect(fixture.model.installFailureText == nil)
    }

    @Test func successfulInstallIsSilent() async {
        let updater = FakeUpdater()
        updater.setOutcome(.succeeded(AppVersion(major: 0, minor: 1, patch: 0)))
        let fixture = create(updater: updater)
        await fixture.model.start()
        #expect(fixture.model.installFailureText == nil)
    }

    // MARK: Banner

    @Test func laterHidesTheBannerAndCheckNowShowsItAgainWithoutDownloading() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.later()
        #expect(!fixture.model.isBannerVisible)

        await fixture.model.checkNow()
        #expect(fixture.model.isBannerVisible)
        #expect(fixture.updater.checks == 1)
    }

    @Test func automaticChecksPauseWhileAnUpdateIsReady() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        await fixture.model.checkIfDue()
        #expect(fixture.updater.checks == 1)
    }

    @Test func installLaunchesTheScriptAndQuits() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.install()

        #expect(fixture.updater.installs == [makeVerified()])
        #expect(fixture.model.state == .installing)
        #expect(fixture.host.terminations == 1)
    }

    @Test func installIsRefusedWhileCleaning() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.isCleaning = { true }

        #expect(fixture.model.installBlockedReason != nil)
        fixture.model.install()
        #expect(fixture.updater.installs.isEmpty)
        #expect(fixture.host.terminations == 0)
    }

    @Test func manualInstallModeNeverLaunchesTheScript() async {
        let updater = newerRelease()
        updater.setMode(.manual(reason: "la cartella /Applications non è scrivibile"))
        let fixture = create(updater: updater)
        await fixture.model.start()
        fixture.model.install()
        #expect(updater.installs.isEmpty)

        fixture.model.revealUpdate()
        #expect(fixture.host.revealed == [makeVerified().bundlePath])
    }

    @Test func installThatCannotStartKeepsTheAppOpen() async {
        let updater = newerRelease()
        updater.failInstalls(with: .installFailed("script di installazione mancante"))
        let fixture = create(updater: updater)
        await fixture.model.start()
        fixture.model.install()

        #expect(fixture.model.state == .failed(UpdateError.installFailed("script di installazione mancante").errorDescription ?? ""))
        #expect(fixture.host.terminations == 0)
    }

    @Test func releaseNotesOpenTheReleasePage() async {
        let fixture = create(updater: newerRelease())
        await fixture.model.start()
        fixture.model.openReleaseNotes()
        #expect(fixture.host.opened == [makeRelease().pageURL])
    }

    @Test func statusTextFollowsTheState() async {
        let fixture = create()
        #expect(fixture.model.statusText.isEmpty)
        await fixture.model.checkNow()
        #expect(fixture.model.statusText == "Hai già l'ultima versione.")

        let ready = create(updater: newerRelease())
        await ready.model.start()
        #expect(ready.model.statusText == "La versione 0.2.0 è pronta da installare.")
        #expect(ready.model.bannerTitle == "mjm.cleaner 0.2.0 è pronto da installare.")
    }

    @Test func failureStatusCarriesTheReason() async {
        let updater = FakeUpdater()
        updater.setCheck(.failure(.httpStatus(403)))
        let fixture = create(updater: updater)
        await fixture.model.checkNow()
        #expect(fixture.model.hasFailed)
        #expect(fixture.model.statusText == "Aggiornamento non riuscito: GitHub ha risposto con lo stato HTTP 403")
    }

    @Test func showsTheCurrentVersionAndTheLastCheck() {
        let fixture = create({ $0.lastUpdateCheck = Self.now })
        #expect(fixture.model.currentVersionText == "0.1.0")
        #expect(fixture.model.lastCheckText == Formatting.historyDate(Self.now))
    }
}

@MainActor
struct UpdateWiringTests {
    @Test func mainModelHasUpdatesOnlyWithAnUpdaterAndAHost() throws {
        let withBoth = MainModel(
            environment: try makeEnvironment(updater: FakeUpdater()), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        #expect(withBoth.updates != nil)

        let withoutUpdater = MainModel(
            environment: try makeEnvironment(), appearance: FakeAppearance(), folders: FakePicker(), updateHost: FakeUpdateHost())
        #expect(withoutUpdater.updates == nil)

        let withoutHost = MainModel(environment: try makeEnvironment(updater: FakeUpdater()), appearance: FakeAppearance(), folders: FakePicker())
        #expect(withoutHost.updates == nil)
    }

    @Test func installWaitsForAnXcodeDeletionToFinish() async throws {
        let service = XcodeViewModelTests.FakeXcode(XcodeViewModelTests.snapshot(XcodeViewModelTests.candidate("device", .device)))
        let updater = FakeUpdater()
        updater.setCached(makeVerified())
        let main = MainModel(
            environment: try makeEnvironment(xcode: service, updater: updater), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        let updates = try #require(main.updates)
        await updates.start()
        main.showXcode()
        guard case .xcode(let xcode) = main.page else {
            Issue.record("La pagina Xcode non si è aperta")
            return
        }
        await xcode.initialLoad?.value
        #expect(updates.installBlockedReason == nil)

        try XcodeViewModelTests.onlyRow(xcode, .device).isSelected = true
        xcode.preview()
        let deleting = Task { await xcode.confirmDelete() }
        try await service.executionStarted.wait()

        #expect(main.isCleaning)
        #expect(updates.installBlockedReason != nil)
        updates.install()
        #expect(updater.installs.isEmpty)

        service.execution.open(XcodeViewModelTests.result())
        await deleting.value
        #expect(!main.isCleaning)
        #expect(updates.installBlockedReason == nil)
    }

    @Test func installWaitsForAWizardDeletionToFinish() async throws {
        let clean = FakeClean()
        clean.waitForCancellation()
        let updater = FakeUpdater()
        updater.setCached(makeVerified())
        let main = MainModel(
            environment: try makeEnvironment(clean: clean, updater: updater), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        let updates = try #require(main.updates)
        await updates.start()
        main.showConfirm(
            [makeCategory("logs")],
            results: [CategoryScanResult(categoryId: "logs", items: [makeItem("/Users/tester/Library/Logs/a.log")], totalBytes: 100, errors: [], exclusions: [])])
        guard case .confirm(let confirm) = main.page else {
            Issue.record("Il passo 3 non si è aperto")
            return
        }
        #expect(!main.isCleaning)

        let deleting = Task { await confirm.delete() }
        try await clean.started.wait()
        #expect(main.isCleaning)
        #expect(updates.installBlockedReason != nil)

        confirm.cancelDelete()
        await deleting.value
        #expect(!main.isCleaning)
    }

    @Test func installWaitsForADockerDeletionToFinish() async throws {
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis([dockerCandidate(.image, "dangling", verdict: .delete)])))
        docker.holdExecution()
        let updater = FakeUpdater()
        updater.setCached(makeVerified())
        let main = MainModel(
            environment: try makeEnvironment(docker: docker, updater: updater), appearance: FakeAppearance(), folders: FakePicker(),
            updateHost: FakeUpdateHost())
        let updates = try #require(main.updates)
        await updates.start()
        main.showDocker()
        guard case .docker(let page) = main.page else {
            Issue.record("La pagina Docker non si è aperta")
            return
        }
        await page.initialLoad?.value
        #expect(!main.isCleaning)

        let deleting = Task { await page.delete() }
        try await docker.executionStarted.wait()
        #expect(main.isCleaning)
        #expect(updates.installBlockedReason != nil)

        docker.executionReleased.open()
        await deleting.value
        #expect(!main.isCleaning)
    }

    @Test func settingsSaveTheAutomaticCheckSwitch() {
        let store = FakeSettingsStore()
        let model = SettingsModel(store: store, appearance: FakeAppearance(), folders: FakePicker(), onSaved: {}, onClose: {})
        #expect(model.automaticUpdateChecks)
        model.automaticUpdateChecks = false
        model.save()
        #expect(store.current.automaticUpdateChecks == false)
    }

    @Test func savingSettingsKeepsTheLastCheck() {
        var settings = CleanerSettings()
        settings.lastUpdateCheck = Date(timeIntervalSince1970: 1_790_000_000)
        let store = FakeSettingsStore(settings)
        SettingsModel(store: store, appearance: FakeAppearance(), folders: FakePicker(), onSaved: {}, onClose: {}).save()
        #expect(store.current.lastUpdateCheck == Date(timeIntervalSince1970: 1_790_000_000))
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`

Expected: la compilazione dei test fallisce, fra gli altri con
`cannot find type 'UpdateHosting' in scope` e `extra argument 'updater' in call`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerFeatures/Update/UpdateModel.swift`:

```swift
import CleanerCore
import Foundation
import Observation

/// Ciò che il modello degli aggiornamenti chiede all'app (AppKit): chiudersi, mostrare un file nel
/// Finder, aprire la pagina della release nel browser.
@MainActor
public protocol UpdateHosting {
    func terminate()
    func reveal(_ path: String)
    func open(_ url: URL)
}

/// Gli aggiornamenti dalle release GitHub (spec 2026-10-19-app-updates-design.md): controllo
/// all'avvio e ogni 24 ore, download e verifica in background, proposta «Installa e riavvia».
/// Un controllo automatico che fallisce non mostra nulla e si ripete al giro dopo; uno manuale
/// mostra il motivo.
@MainActor
@Observable
public final class UpdateModel {
    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case downloading(Double)
        case ready(VerifiedUpdate)
        case installing
        case failed(String)
    }

    /// Il controllo automatico parte quando l'ultimo riuscito ha almeno 24 ore.
    public static let checkInterval: TimeInterval = 24 * 60 * 60

    @ObservationIgnored private let updater: any AppUpdating
    @ObservationIgnored private let settings: any SettingsStoring
    @ObservationIgnored private let clock: any WallClock
    @ObservationIgnored private let host: any UpdateHosting
    /// Vero mentre una pulizia cancella: l'installazione chiuderebbe l'app a metà. Lo imposta `MainModel`.
    @ObservationIgnored public var isCleaning: @MainActor () -> Bool = { false }
    @ObservationIgnored private var started = false

    public private(set) var state = State.idle
    /// «Più tardi»: il banner resta nascosto fino al prossimo avvio.
    public private(set) var isBannerDismissed = false
    /// Un'installazione precedente non riuscita: l'app lo dice una volta, poi si azzera.
    public private(set) var installFailureText: String?

    public init(updater: any AppUpdating, settings: any SettingsStoring, clock: any WallClock, host: any UpdateHosting) {
        self.updater = updater
        self.settings = settings
        self.clock = clock
        self.host = host
    }

    public var currentVersionText: String { updater.currentVersion.description }

    public var lastCheckText: String? {
        settings.load().lastUpdateCheck.map { Formatting.historyDate($0) }
    }

    public var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: true
        default: false
        }
    }

    public var readyUpdate: VerifiedUpdate? {
        if case .ready(let update) = state { update } else { nil }
    }

    public var isBannerVisible: Bool { readyUpdate != nil && !isBannerDismissed }

    public var installMode: InstallMode { updater.installMode() }

    /// Il titolo del banner.
    public var bannerTitle: String {
        guard let update = readyUpdate else { return "" }
        return String(localized: "mjm.cleaner \(update.release.version.description) è pronto da installare.", bundle: .module)
    }

    /// Lo stato mostrato nelle Impostazioni, vuoto quando non c'è nulla da dire.
    public var statusText: String {
        switch state {
        case .idle, .installing:
            ""
        case .checking:
            String(localized: "Controllo in corso…", bundle: .module)
        case .downloading(let fraction):
            String(localized: "Download dell'aggiornamento: \(Int((fraction * 100).rounded()))%", bundle: .module)
        case .ready(let update):
            String(localized: "La versione \(update.release.version.description) è pronta da installare.", bundle: .module)
        case .upToDate:
            String(localized: "Hai già l'ultima versione.", bundle: .module)
        case .failed(let message):
            String(localized: "Aggiornamento non riuscito: \(message)", bundle: .module)
        }
    }

    public var hasFailed: Bool {
        if case .failed = state { true } else { false }
    }

    /// Il motivo per cui «Installa e riavvia» è disabilitato, o `nil`.
    public var installBlockedReason: String? {
        isCleaning() ? String(localized: "Attendi la fine della pulizia in corso.", bundle: .module) : nil
    }

    // MARK: Pianificazione

    /// All'avvio: l'esito dell'installazione precedente, poi un aggiornamento già scaricato, poi il
    /// controllo automatico se è dovuto. Le chiamate successive non fanno nulla.
    public func start() async {
        guard !started else { return }
        started = true
        if case .failed(let step) = updater.takeInstallOutcome() {
            installFailureText = String(
                localized: "Aggiornamento non riuscito (passo «\(step)»): è rimasta la versione \(currentVersionText). Il dettaglio è in install.log nella cartella updates dei dati dell'app.",
                bundle: .module)
        }
        if let cached = await updater.cachedUpdate() {
            state = .ready(cached)
            return
        }
        await checkIfDue()
    }

    /// Il controllo automatico, se attivo e dovuto: all'avvio e a ogni tick orario dell'app.
    public func checkIfDue() async {
        let saved = settings.load()
        guard saved.automaticUpdateChecks, !isBusy, readyUpdate == nil else { return }
        if let last = saved.lastUpdateCheck, clock.now.timeIntervalSince(last) < Self.checkInterval { return }
        await run(manual: false)
    }

    /// «Controlla ora»: ignora interruttore e soglia e mostra l'esito.
    public func checkNow() async {
        guard !isBusy else { return }
        if readyUpdate != nil {
            isBannerDismissed = false
            return
        }
        await run(manual: true)
    }

    private func run(manual: Bool) async {
        state = .checking
        do {
            let release = try await updater.check()
            var saved = settings.load()
            saved.lastUpdateCheck = clock.now
            try? settings.save(saved)
            guard let release else {
                state = manual ? .upToDate : .idle
                return
            }
            state = .downloading(0)
            let update = try await updater.prepare(release) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            isBannerDismissed = false
            state = .ready(update)
        } catch {
            state = manual ? .failed(FeatureText.message(error)) : .idle
        }
    }

    // MARK: Azioni del banner

    public func later() {
        isBannerDismissed = true
    }

    /// «Installa e riavvia»: avvia lo script e chiude l'app. Rifiutato mentre una pulizia cancella.
    public func install() {
        guard let update = readyUpdate, installBlockedReason == nil, installMode == .inPlace else { return }
        do {
            try updater.install(update)
        } catch {
            state = .failed(FeatureText.message(error))
            return
        }
        state = .installing
        host.terminate()
    }

    /// «Mostra nel Finder», quando il bundle non si può sostituire sul posto.
    public func revealUpdate() {
        guard let update = readyUpdate else { return }
        host.reveal(update.bundlePath)
    }

    /// «Novità»: la pagina della release su GitHub.
    public func openReleaseNotes() {
        guard let update = readyUpdate else { return }
        host.open(update.release.pageURL)
    }

    public func dismissInstallFailure() {
        installFailureText = nil
    }
}
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
    public let clock: any WallClock
    private let expander: PathExpander
```
con:
```swift
    public let clock: any WallClock
    /// `nil` per le build Debug, la demo e i test che non lo chiedono: niente aggiornamenti.
    public let updater: (any AppUpdating)?
    private let expander: PathExpander
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
        clock: any WallClock,
        expander: PathExpander
    ) {
```
con:
```swift
        clock: any WallClock,
        expander: PathExpander,
        updater: (any AppUpdating)? = nil
    ) {
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
        self.expander = expander
    }
```
con:
```swift
        self.expander = expander
        self.updater = updater
    }
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
    /// aprono: l'app mostra allora la vista d'errore (`StartupFailure`).
    public static func live(
        paths: AppPaths,
        home: String = NSHomeDirectory(),
```
con:
```swift
    /// aprono: l'app mostra allora la vista d'errore (`StartupFailure`). Senza `update`, come nelle
    /// build Debug, l'app non si aggiorna.
    public static func live(
        paths: AppPaths,
        update: UpdateContext? = nil,
        home: String = NSHomeDirectory(),
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:

```swift
            expander: try PathExpander(homeDirectory: home, tempDirectory: tempDirectory))
    }
```
con:
```swift
            expander: try PathExpander(homeDirectory: home, tempDirectory: tempDirectory),
            updater: update.map {
                AppUpdater(context: $0, paths: paths, http: URLSessionHTTPClient(), runner: processes, launcher: DetachedProcessLauncher())
            })
    }
```

In `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`, sostituire:

```swift
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
```
con:
```swift
    public private(set) var settings: SettingsModel?

    /// Gli aggiornamenti: esistono solo se l'ambiente ha un updater e l'app un `UpdateHosting`.
    public let updates: UpdateModel?

    public init(
        environment: AppEnvironment,
        appearance: any AppearanceApplying,
        folders: any FolderPicking,
        updateHost: (any UpdateHosting)? = nil
    ) {
        self.environment = environment
        self.appearance = appearance
        self.folders = folders
        if let updater = environment.updater, let updateHost {
            updates = UpdateModel(updater: updater, settings: environment.settings, clock: environment.clock, host: updateHost)
        } else {
            updates = nil
        }
        // Il passo 1 riceve la navigazione appena `self` è disponibile.
        let first = ChooseStepModel(environment: environment, navigation: nil)
        page = .choose(first)
        first.navigation = self
        updates?.isCleaning = { [weak self] in self?.isCleaning ?? false }
    }
```

In `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`, sostituire:

```swift
    public var canNavigateGlobally: Bool { !isXcodeBusy }
```
con:
```swift
    public var canNavigateGlobally: Bool { !isXcodeBusy }

    /// Vero mentre una pulizia cancella (wizard, Docker o Xcode): l'aggiornamento non chiude l'app
    /// a metà.
    public var isCleaning: Bool {
        switch page {
        case .confirm(let model): model.isDeleting
        case .docker(let model): model.isDeleting
        case .xcode(let model): model.isDeleting
        default: false
        }
    }
```

In `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`, sostituire:

```swift
    public var nuGetMinAgeDays: Int
```
con:
```swift
    public var nuGetMinAgeDays: Int
    /// Controllo automatico degli aggiornamenti; il pulsante «Controlla ora» è di `UpdateModel`.
    public var automaticUpdateChecks: Bool
```

In `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`, sostituire:

```swift
        nuGetMinAgeDays = settings.nuGetMinAgeDays
    }
```
con:
```swift
        nuGetMinAgeDays = settings.nuGetMinAgeDays
        automaticUpdateChecks = settings.automaticUpdateChecks
    }
```

In `MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift`, sostituire:

```swift
        settings.nuGetMinAgeDays = max(0, nuGetMinAgeDays)
```
con:
```swift
        settings.nuGetMinAgeDays = max(0, nuGetMinAgeDays)
        settings.automaticUpdateChecks = automaticUpdateChecks
```

- [ ] **Step 4: Verificare che i test passino**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: `Test run with 203 tests in 23 suites passed` e `Test run with 600 tests in 55 suites passed`, nessun warning né errore.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/Support/UpdateDoubles.swift \
  MjmCleanerKit/Tests/CleanerFeaturesTests/UpdateModelTests.swift \
  MjmCleanerKit/Sources/CleanerFeatures/Update/UpdateModel.swift \
  MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift \
  MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift \
  MjmCleanerKit/Sources/CleanerFeatures/Settings/SettingsModel.swift
git commit -m "feat(update): schedule checks and propose the update from the main window

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 9: Banner, Impostazioni, menu e host AppKit

<!-- verifica: app -->

Le viste sono sottili: testi e decisioni stanno in `UpdateModel`. Il banner usa `safeAreaInset` sopra la pagina corrente; «Installa e riavvia…» chiede conferma con l'avviso sull'Accesso completo al disco. Nelle build Debug `main.updates` è `nil`: banner, sezione e comando non compaiono o sono disabilitati.

**Files:**
- Create: `MjmCleaner/Update/UpdateBanner.swift`
- Modify: `MjmCleaner/App/AppKitServices.swift`
- Modify: `MjmCleaner/App/AppStartup.swift`
- Modify: `MjmCleaner/Shell/MainView.swift`
- Modify: `MjmCleaner/Settings/SettingsView.swift`
- Modify: `MjmCleaner/App/MjmCleanerApp.swift`

**Interfaces:**
- Consumes: `UpdateModel`, `UpdateHosting`, `MainModel.updates`, `SettingsModel.automaticUpdateChecks` (Task 8); `UpdateContext.make` (Task 1); `AppEnvironment.live(paths:update:)` (Task 8).
- Produces: `UpdateBanner(model:)`, `UpdateSettingsSection(settings:model:)`, `AppKitUpdateHost`, `AppStartup.updateContext`, `SettingsView(model:updates:)`.

- [ ] **Step 1: Implementare**

Creare `MjmCleaner/Update/UpdateBanner.swift`:

```swift
import CleanerCore
import CleanerFeatures
import SwiftUI

/// Il banner in cima alla finestra quando un aggiornamento è scaricato e verificato. «Installa e
/// riavvia» chiede conferma, perché l'app si chiude e il permesso di Accesso completo al disco va
/// concesso di nuovo; se il bundle non si può sostituire sul posto, «Mostra nel Finder».
struct UpdateBanner: View {
    let model: UpdateModel
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.bannerTitle)
                    .fontWeight(.semibold)
                if let reason = model.installBlockedReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if case .manual(let reason) = model.installMode {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Novità", action: model.openReleaseNotes)
                .buttonStyle(.link)
            Button("Più tardi", action: model.later)
            if case .manual = model.installMode {
                Button("Mostra nel Finder", action: model.revealUpdate)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Installa e riavvia…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.installBlockedReason != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .alert("Installare l'aggiornamento?", isPresented: $confirming) {
            Button("Annulla", role: .cancel) {}
            Button("Installa e riavvia", action: model.install)
        } message: {
            Text("mjm.cleaner si chiuderà e si riaprirà con la nuova versione. Dopo l'aggiornamento dovrai concedere di nuovo l'Accesso completo al disco, se lo usi (serve solo per il Cestino).")
        }
    }
}

/// La sezione «Aggiornamenti» delle Impostazioni: l'interruttore si salva con Salva, «Controlla
/// ora» agisce subito.
struct UpdateSettingsSection: View {
    @Bindable var settings: SettingsModel
    let model: UpdateModel

    var body: some View {
        Section {
            Toggle("Controlla automaticamente", isOn: $settings.automaticUpdateChecks)
            LabeledContent("Versione installata", value: model.currentVersionText)
            LabeledContent("Ultimo controllo") {
                if let last = model.lastCheckText {
                    Text(verbatim: last)
                } else {
                    Text("mai")
                }
            }
            HStack(spacing: 10) {
                OptionalText(text: model.statusText, style: model.hasFailed ? .danger : .secondary)
                Spacer()
                Button("Controlla ora") {
                    Task { await model.checkNow() }
                }
                .disabled(model.isBusy)
            }
        } header: {
            Text("Aggiornamenti")
        } footer: {
            Text("Cerca le nuove versioni fra le release di GitHub all'avvio e una volta al giorno.")
        }
    }
}
```

In fondo a `MjmCleaner/App/AppKitServices.swift`, aggiungere:

```swift

/// Gli aggiornamenti chiedono all'app di chiudersi (lo script attende la fine del processo), di
/// mostrare il bundle scaricato nel Finder e di aprire la pagina della release.
@MainActor
struct AppKitUpdateHost: UpdateHosting {
    func terminate() {
        NSApp.terminate(nil)
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
```

In `MjmCleaner/App/AppStartup.swift`, sostituire:

```swift
    /// La stessa lettura di `environment.settings.load()`, fatta prima che l'ambiente esista.
```
con:
```swift
    /// L'app in esecuzione per l'updater: `nil` per le build Debug (`com.mjm.cleaner.debug`).
    static var updateContext: UpdateContext? {
        UpdateContext.make(
            bundleIdentifier: Bundle.main.bundleIdentifier,
            shortVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
            bundlePath: Bundle.main.bundleURL.path(percentEncoded: false),
            processIdentifier: ProcessInfo.processInfo.processIdentifier)
    }

    /// La stessa lettura di `environment.settings.load()`, fatta prima che l'ambiente esista.
```

In `MjmCleaner/App/AppStartup.swift`, sostituire:

```swift
            let environment = try await AppEnvironment.live(paths: paths)
            show(MainModel(environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker()))
```
con:
```swift
            let environment = try await AppEnvironment.live(paths: paths, update: Self.updateContext)
            show(MainModel(
                environment: environment, appearance: AppKitAppearance(), folders: AppKitFolderPicker(),
                updateHost: AppKitUpdateHost()))
```

In `MjmCleaner/App/AppStartup.swift`, sostituire:

```swift
    func show(_ main: MainModel) {
        state = .ready(main)
        Task { try? await main.refreshTotal() }
    }
```
con:
```swift
    func show(_ main: MainModel) {
        state = .ready(main)
        Task { try? await main.refreshTotal() }
        // Aggiornamenti: all'avvio, poi un tick all'ora; il modello decide se il controllo è dovuto.
        if let updates = main.updates {
            Task {
                await updates.start()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                    await updates.checkIfDue()
                }
            }
        }
    }
```

In `MjmCleaner/Shell/MainView.swift`, sostituire:

```swift
        } detail: {
            PageView(page: main.page)
        }
        .sheet(item: settingsSheet) { settings in
            SettingsView(model: settings)
        }
    }
```
con:
```swift
        } detail: {
            PageView(page: main.page)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let updates = main.updates, updates.isBannerVisible {
                        UpdateBanner(model: updates)
                    }
                }
        }
        .sheet(item: settingsSheet) { settings in
            SettingsView(model: settings, updates: main.updates)
        }
        .alert("Aggiornamento non riuscito", isPresented: installFailureAlert) {
            Button("OK") { main.updates?.dismissInstallFailure() }
        } message: {
            Text(verbatim: main.updates?.installFailureText ?? "")
        }
    }

    private var installFailureAlert: Binding<Bool> {
        Binding(
            get: { main.updates?.installFailureText != nil },
            set: { if !$0 { main.updates?.dismissInstallFailure() } })
    }
```

In `MjmCleaner/Settings/SettingsView.swift`, sostituire:

```swift
struct SettingsView: View {
    @Bindable var model: SettingsModel
```
con:
```swift
struct SettingsView: View {
    @Bindable var model: SettingsModel
    /// `nil` nelle build Debug e nella demo: la sezione «Aggiornamenti» non compare.
    var updates: UpdateModel?
```

In `MjmCleaner/Settings/SettingsView.swift`, sostituire:

```swift
                        Text("L'età dei pacchetti NuGet si basa sull'ultimo accesso registrato dal filesystem: è un'euristica, non una certezza.")
                    }
                }
```
con:
```swift
                        Text("L'età dei pacchetti NuGet si basa sull'ultimo accesso registrato dal filesystem: è un'euristica, non una certezza.")
                    }
                }

                if let updates {
                    UpdateSettingsSection(settings: model, model: updates)
                }
```

In `MjmCleaner/App/MjmCleanerApp.swift`, sostituire:

```swift
        .commands {
            CommandGroup(replacing: .appSettings) {
```
con:
```swift
        .commands {
            // Apre le Impostazioni, dove compaiono stato ed esito del controllo.
            CommandGroup(after: .appInfo) {
                Button("Controlla aggiornamenti…") {
                    guard let main = startup.main, let updates = main.updates else { return }
                    main.showSettings()
                    Task { await updates.checkNow() }
                }
                .disabled(!(startup.main?.canShowSettings ?? false) || startup.main?.updates == nil)
            }
            CommandGroup(replacing: .appSettings) {
```

- [ ] **Step 2: Verificare package e app**

Run: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`

Expected: ancora `600` e `203`.

Run: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-app-updates-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`

Expected: `** BUILD SUCCEEDED **` e nessuna altra riga (l'avviso «Metadata extraction skipped» di `appintentsmetadataprocessor` non passa dal filtro). Non avviare l'app.

- [ ] **Step 3: Commit**

```bash
git add MjmCleaner/Update/UpdateBanner.swift \
  MjmCleaner/App/AppKitServices.swift \
  MjmCleaner/App/AppStartup.swift \
  MjmCleaner/Shell/MainView.swift \
  MjmCleaner/Settings/SettingsView.swift \
  MjmCleaner/App/MjmCleanerApp.swift
git commit -m "feat(update): show the update banner, settings section and menu command

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 10: README e collaudo end-to-end

<!-- verifica: none -->

Il README descrive gli aggiornamenti. Poi il controller, **non un subagent**, fa il collaudo con l'utente: una Release costruita con versione `0.0.9` trova `v0.1.0` su GitHub, la scarica, la verifica e si sostituisce. `v0.1.0` non contiene l'updater, quindi si prova il ramo vecchia → nuova, l'unico che conta. Nessuna release viene pubblicata.

**Files:**
- Modify: `README.md`
- Create: `docs/superpowers/verification/2026-10-19-app-updates-e2e.md`

- [ ] **Step 1: README**

In `README.md`, sostituire:

```markdown
## Documentation
```
con:
```markdown
## Updates

The release app checks the GitHub releases at launch and then once a day
(**Settings → Updates** turns this off; **Check for Updates…** in the app menu
checks right away). When a newer release exists, it downloads
`mjm.cleaner-vX.Y.Z-macos-universal.zip` into
`~/Library/Application Support/com.mjm.cleaner/updates/`, accepts it only if its
SHA-256 matches the digest GitHub publishes for the asset, extracts it and checks
the bundle id, the version, the signature and both architectures. A banner then
offers **Install and Relaunch**: the app quits, a small script swaps the bundle
in place (restoring the old one if the swap fails) and reopens it; the outcome
is in `updates/install-result` and `updates/install.log`. If the folder that
holds the app is not writable, the banner offers **Show in Finder** instead.

Because the bundle is ad hoc signed, **Full Disk Access must be granted again
after every update** (see Warnings). Debug builds never check for updates.

## Documentation
```

In `README.md`, sostituire:

```markdown
  `docs/superpowers/verification/2026-10-16-swift-port-5-gate.md`
```
con:
```markdown
  `docs/superpowers/verification/2026-10-16-swift-port-5-gate.md`
- In-app updates design: `docs/superpowers/specs/2026-10-19-app-updates-design.md`
```

- [ ] **Step 2: Commit del README**

```bash
git add README.md
git commit -m "docs(update): describe in-app updates

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Preparare la build di collaudo (controller)**

Chiedere prima all'utente il momento del collaudo: l'app si avvia davvero, legge e scrive `~/Library/Application Support/com.mjm.cleaner/` (impostazioni e storico della Release vera) e scarica da GitHub.

```bash
E2E="$TMPDIR/mjm-app-updates-e2e"
rm -rf "$E2E" && mkdir -p "$E2E/Applications"
bash Scripts/package-release.sh --tag v0.0.9 --build-number 1 --output-dir "$E2E/out"
ditto "$E2E/out/mjm.cleaner.app" "$E2E/Applications/mjm.cleaner.app"
ls "$HOME/Library/Application Support/com.mjm.cleaner/updates" 2>/dev/null
plutil -p "$E2E/Applications/mjm.cleaner.app/Contents/Info.plist" | grep -E 'CFBundleShortVersionString|CFBundleIdentifier'
```

Expected: `"CFBundleShortVersionString" => "0.0.9"`, `"CFBundleIdentifier" => "com.mjm.cleaner"`; la cartella `updates` non esiste (se esiste, annotarne il contenuto nel verbale prima di proseguire). Se `settings.json` ha `"AutomaticUpdateChecks" : false` o un `LastUpdateCheck` di meno di 24 ore, il controllo si avvia con «Controlla aggiornamenti…» al punto successivo.

- [ ] **Step 4: Collaudo guidato (l'utente fa i clic)**

1. Il controller avvia la build: `open "$E2E/Applications/mjm.cleaner.app"`.
2. Atteso entro qualche secondo il banner «mjm.cleaner 0.1.0 è pronto da installare.». In `updates/v0.1.0/` ci sono `mjm.cleaner-v0.1.0-macos-universal.zip`, `release.json` ed `expanded/mjm.cleaner.app`; il controller verifica `shasum -a 256` dello ZIP = `6c1dfc5c886b1cbc8a0849770fe66c4da07247f1e82094aeaa29cddf48154d07`.
3. L'utente apre **Impostazioni**: la sezione «Aggiornamenti» mostra versione `0.0.9`, l'ultimo controllo e «La versione 0.1.0 è pronta da installare.».
4. L'utente preme **Più tardi**: il banner sparisce. Chiude l'app (⌘Q) e il controller la riapre: il banner torna subito, senza un nuovo download (la data di `release.json` non cambia).
5. L'utente preme **Installa e riavvia…**, legge l'avviso sull'Accesso completo al disco e conferma. L'app si chiude e si riapre.
6. Il controller verifica:

```bash
plutil -p "$E2E/Applications/mjm.cleaner.app/Contents/Info.plist" | grep CFBundleShortVersionString
cat "$HOME/Library/Application Support/com.mjm.cleaner/updates/install-result" 2>/dev/null || echo "install-result letto e cancellato"
cat "$HOME/Library/Application Support/com.mjm.cleaner/updates/install.log"
ls -a "$E2E/Applications"
codesign --verify --deep --strict "$E2E/Applications/mjm.cleaner.app" && echo firma-ok
xattr -l "$E2E/Applications/mjm.cleaner.app"
```

Expected: versione `0.1.0`; `install.log` con «aggiornamento a v0.1.0» e «ok v0.1.0»; in `Applications` solo `mjm.cleaner.app` (nessun `.mjm.cleaner-update-*` o `.mjm.cleaner-old-*`); `firma-ok`. La v0.1.0 riaperta non ha l'updater, quindi non legge `install-result`, che resta su disco con `ok v0.1.0`. Annotare se macOS ha bloccato l'apertura (Gatekeeper) e gli attributi estesi del bundle.

7. Fine: l'utente chiude l'app. Il controller rimuove `$E2E` e `updates/` (`rm -rf "$HOME/Library/Application Support/com.mjm.cleaner/updates"`) solo con il suo consenso.

- [ ] **Step 5: Verbale e commit**

Scrivere `docs/superpowers/verification/2026-10-19-app-updates-e2e.md` con data, macOS, comandi ed esiti dei punti 1–7, scostamenti ed eventuale blocco di Gatekeeper. Poi:

```bash
git add docs/superpowers/verification/2026-10-19-app-updates-e2e.md
git commit -m "docs(update): record the end-to-end update from 0.0.9 to 0.1.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Mutazioni provate in stesura

Ognuna è stata applicata da sola alla copia scratch e ha fatto fallire almeno il test indicato (comandi: la suite del file mutato, o `bash Scripts/update-install.test.sh` per lo script). M14 sopravviveva alla prima versione del test sul collegamento simbolico, che puntava a `/Applications` e veniva rifiutato più avanti per l'`Info.plist` mancante; il test ora punta a un bundle finto valido, e M14 viene eliminata. I revisori dei Task 3–6 le ripetono e ne aggiungono di proprie.

| # | Task | Mutazione | Test che la elimina |
|---|---|---|---|
| M1 | 2 | feed: una release uguale vale come più recente | `sameOrOlderReleaseMeansUpToDate` |
| M2 | 2 | feed: accetta un asset anche se duplicato | `duplicatedAssetIsAnInvalidRelease` |
| M3 | 2 | feed: accetta indirizzi http | `plainHTTPDownloadIsAnInvalidRelease` |
| M4 | 2 | feed: digest non obbligatorio | `missingOrMalformedDigestIsAnInvalidRelease` |
| M5 | 3 | download: niente confronto del digest | `wrongDigestDeletesTheDownload` |
| M6 | 3 | download: il file parziale resta dopo un errore | `nonOKStatusDeletesThePartialFile` |
| M7 | 3 | cache: niente nuova verifica del digest | `cachedDropsAZipAlteredAfterTheDownload` |
| M8 | 3 | cache: accetta release non più recenti | `cachedDropsReleasesThatAreNoLongerNewer` |
| M9 | 4 | verifica: niente controllo del bundle id | `otherBundleIdentifierIsRejected` |
| M10 | 4 | verifica: niente controllo della versione | `versionOtherThanTheTagIsRejected` |
| M11 | 4 | verifica: firma ignorata | `invalidSignatureIsRejected` |
| M12 | 4 | verifica: basta arm64 | `singleArchitectureBundleIsRejected` |
| M13 | 4 | verifica: più elementi nello ZIP | `zipWithTwoItemsIsRejected` |
| M14 | 4 | verifica: un collegamento passa per bundle | `linkNamedLikeAnAppIsRejected` |
| M15 | 4 | verifica: un rifiuto non cancella i file | `zipWithTwoItemsIsRejected` |
| M16 | 6 | installer: App Translocation sul posto | `translocatedAppNeedsAManualInstall` |
| M17 | 6 | installer: cartella non scrivibile sul posto | `readOnlyFolderNeedsAManualInstall` |
| M18 | 6 | installer: PATH dell'utente | `launchesACopyOfTheBundledScriptWithItsArgumentsOnly` |
| M19 | 6 | installer: modalità manuale avvia lo script | `manualModeNeverLaunchesTheScript` |
| M20 | 6 | installer: esito vecchio non cancellato | `launchesACopyOfTheBundledScriptWithItsArgumentsOnly` |
| M21 | 1 | contesto: build Debug aggiornabile | `debugBuildsAndUnreadableVersionsNeverUpdate` |
| M22 | 5 | script: non attende la fine dell'app | `update-install.test.sh`: «installed before the process exited» |
| M23 | 5 | script: al timeout prosegue | `update-install.test.sh` |
| M24 | 5 | script: niente ripristino | `update-install.test.sh` |
| M25 | 5 | script: il vecchio bundle resta | `update-install.test.sh`: «staging or old bundle left behind» |
| M26 | 8 | modello: fallimento automatico visibile | `automaticFailureStaysQuietAndRetriesNextTime` |
| M27 | 8 | modello: soglia ignorata | `automaticCheckWaitsTwentyFourHours` |
| M28 | 8 | modello: interruttore ignorato | `disabledAutomaticChecksNeverRunButCheckNowDoes` |
| M29 | 8 | modello: installa durante una pulizia | `installIsRefusedWhileCleaning` |
| M30 | 8 | modello: si chiude anche se lo script non parte | `installThatCannotStartKeepsTheAppOpen` |
| M31 | 8 | finestra: pulizia del passo 3 ignorata | `installWaitsForAWizardDeletionToFinish` |
| M32 | 8 | finestra: pulizia Docker ignorata | `installWaitsForADockerDeletionToFinish` |
| M33 | 8 | finestra: pulizia Xcode ignorata | `installWaitsForAnXcodeDeletionToFinish` |
