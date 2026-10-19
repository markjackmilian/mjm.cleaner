# Pagina Docker indipendente dal motore — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La pagina Docker riconosce il motore che risponde (Docker Desktop, OrbStack o un altro compatibile) e adatta errori, misura del disco virtuale, testi e resoconto. Il binario `docker` di OrbStack viene trovato e `~/.orbstack` entra nella deny-list.

**Architecture:** Il Core riconosce il motore da `docker info` (`OperatingSystem`) con il nuovo `DockerEngine`. A daemon spento, il nuovo `DockerContextReader` legge il contesto attivo (`docker context inspect`) e nomina il motore da avviare. `DockerAnalysis` porta il motore e un disco opzionale: si misura solo `Docker.raw` di Docker Desktop. `CleanerFeatures` sceglie i testi della pagina e del resoconto in base al motore; le viste SwiftUI non cambiano.

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-19-docker-engines-design.md`

Stato di partenza: `main` a `6fecad9` più il commit di questo piano (nessun push). `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **536** test in 48 suite (`CleanerCoreTests`) e **173** in 21 (`CleanerFeaturesTests`). Il controller crea il branch `feat/docker-engines` da `main` prima del Task 1.

Decisioni dell'utente (2026-10-19, nella spec):

- Si pulisce il motore del **contesto attivo**: nessun selettore e nessun ripiego automatico su un altro motore.
- Con OrbStack il disco virtuale **non si misura**.
- Motore letto dal daemon; il contesto serve solo a nominare il motore nell'errore (approccio A).
- Demo invariata (Docker Desktop), nessuno screenshot nuovo.

Decisioni prese durante la stesura, verificate rieseguendo il piano in una copia scratch (`git archive` di `6fecad9`):

- **`DiskUsageProbe` tiene il percorso nel costruttore.** La spec dice che il percorso arriva alla misura. Il percorso del costruttore è già solo quello di Docker Desktop, quindi basta aggiungere `measure(for engine:)`, che restituisce `nil` senza toccare nulla per ogni altro motore. L'effetto è lo stesso, ma `AppEnvironment` e i test esistenti della sonda non cambiano.
- **Nessun tipo «profilo del disco».** La tabella della spec (disco misurato / rilascio) si riduce a `engine.kind`: `DiskUsageProbe.measure(for:)` decide la misura e i testi scelgono con `switch engine.kind`.
- **`DockerUnavailableError.reason` ha `.notRunning` come valore predefinito.** Solo `DockerCli` lancia «non installato», e i due punti in cui lo fa passano `.notInstalled` esplicitamente; i test lo verificano. Così gli altri punti che costruiscono l'errore restano come sono.
- **Riconoscimento con `PathText.equalsIgnoringCase`** sull'intero valore, che è il confronto `OrdinalIgnoreCase` già usato nel Core.
- **`DockerContextReader` non lancia.** Un contesto illeggibile, anche per annullamento, lascia il testo generico: il messaggio d'errore non deve diventare a sua volta un errore.
- **`DockerBinaryLocator.find` riceve un predicato** `isExecutable` invece del `FileSystem`. Il predicato predefinito, `isExecutableFile`, usa `stat` (segue i collegamenti) più `access(X_OK)`. Il filesystem in memoria dei test non ha collegamenti: il caso del collegamento orfano si prova sul disco vero.
- **Due task per Features.** Il Task 4 porta il motore alla pagina e rende opzionale `diskAfter`, senza cambiare i testi del resoconto. Il Task 5 aggiunge il motore al resoconto. Ogni task lascia verdi package e app.
- **Stringhe.** Le nuove stringhe sono in italiano con `String(localized:bundle: .module)`, come le esistenti. I `Localizable.xcstrings` non si toccano: `String(localized:)` ricade sulla chiave, e in `main` i cataloghi sono modificati da Xcode e non vanno in stage.

## Global Constraints

- Il codice vive in `MjmCleanerKit/` (package) e `MjmCleaner/` (app). Nel Core cambiano solo i file `Docker/*` indicati e `Safety/DenyList.swift`; in `CleanerFeatures` solo `Docker/*`, `Environment/AppEnvironment.swift`, `Environment/DockerCleanupServing.swift` e `Shell/MainModel.swift`; nell'app solo `Demo/DemoData.swift`, `Demo/DemoServices.swift` e `Demo/DemoLaunch.swift`. Le viste SwiftUI non cambiano.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati.
- L'app non avvia né arresta alcun motore e non cancella file dei motori: Docker passa solo dalla CLI.
- Il contesto attivo non si cambia mai, nemmeno nelle prove: per leggere un altro contesto si usa `docker --context <nome> …`.
- Testi nuovi: solo quelli della spec, scritti esattamente come nel piano. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica, dalla radice del repository:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E '✘|Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-docker-engines-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/docker-engines`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` (`MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`).
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick) e mai avviare l'app: le viste non cambiano, le verifiche sono test, build e la prova in sola lettura del Task 6.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: sonnet; **opus per il Task 3** (deny-list e binario) e per la revisione finale. Il Task 3 si rivede con mutazioni in una copia scratch.
- Mutazioni provate in stesura (tutte uccise dai test del piano), da ripetere nelle revisioni: vedi la tabella in fondo.

---

## Fatti misurati (2026-10-19, macOS 27.0, OrbStack in esecuzione, Docker Desktop installato e spento)

- `docker info --format '{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}}}'` con OrbStack stampa `{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack"}` ed esce con 0. Con il contesto `desktop-linux` (Docker Desktop spento) stampa `{"ServerVersion":"","OperatingSystem":""}` ed esce con 1. Lo stderr, «failed to connect to the docker API at unix:///…/.docker/run/docker.sock; … connect: no such file or directory», è già riconosciuto da `DockerCliErrors.isDaemonUnavailable`.
- `docker context inspect --format '{{json .}}'` non contatta il daemon. Per il contesto attivo stampa una riga come `{"Name":"orbstack","Metadata":{"Description":"OrbStack"},"Endpoints":{"docker":{"Host":"unix:///Users/<utente>/.orbstack/run/docker.sock","SkipTLSVerify":false}},"TLSMaterial":{},"Storage":{…}}`. Docker Desktop ha `"Description":"Docker Desktop"` e l'endpoint `unix:///Users/<utente>/.docker/run/docker.sock`; `default` ha `"Metadata":{}` e l'endpoint `unix:///var/run/docker.sock`, che su questo Mac è un collegamento a OrbStack. Con un nome inesistente esce con 1 («context not found»).
- `docker --context <nome> context inspect` mostra quel contesto senza cambiare l'attivo.
- Il contesto attivo può cambiare da solo: alle 08:40 è passato da `desktop-linux` a `orbstack`, probabilmente perché OrbStack lo reimposta (`docker.set_context: true`).
- OrbStack installa `~/.orbstack/bin/docker` → `/Applications/OrbStack.app/Contents/MacOS/xbin/docker` e, con i permessi di amministratore, `/usr/local/bin/docker` → lo stesso binario. Docker Desktop lascia `~/.docker/bin/docker` → `/Applications/Docker.app/Contents/Resources/bin/docker`.
- Il disco di OrbStack è `data.img.raw`, un file sparse che secondo i testi di OrbStack «si riduce automaticamente quando cancelli dati». Sta in `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/`, dove un processo senza permesso riceve «Operation not permitted».
- `LocalFileSystem.fileExists` restituisce vero per un collegamento orfano, come `File.Exists` di .NET.

---

### Task 1: Riconoscere il motore da `docker info`

**Files:**
- Create: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift` (`DockerUnavailableError`, due `throw` in `DockerCli.run`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift` (nuovo `parseEngineInfo`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift` (`checkDaemon`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` (due righe)
- Test: create `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerEngineTests.swift`; modify `FakeDockerCli.swift`, `DockerInventoryCollectorTests.swift`, `DockerCliTests.swift` (in `MjmCleanerKit/Tests/CleanerCoreTests/Docker/`) e `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift` (un testo)

**Interfaces:**
- Produces:
  - `public enum DockerEngineKind: Sendable, Equatable { case dockerDesktop, orbStack, other }`
  - `public struct DockerEngine: Sendable, Equatable` con `kind`, `displayName`, `operatingSystem`, `serverVersion` e `public init(serverVersion: String, operatingSystem: String)`
  - `static func DockerEngine.kind(named: String) -> DockerEngineKind` (interna al Core: la usa anche il Task 2)
  - `DockerUnavailableError.Reason` (`.notInstalled`, `.notRunning`), proprietà `reason`, `init(_ message: String, reason: Reason = .notRunning)`
  - `DockerInventoryCollector.checkDaemon() async throws -> DockerEngine`; `static let DockerInventoryCollector.engineFormat`
  - `DockerJson.parseEngineInfo(_:) throws -> (serverVersion: String, operatingSystem: String)`
  - nei test: `FakeDockerCli.infoCommand`, `FakeDockerCli.info(_ version:, _ operatingSystem: = "Docker Desktop")`

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerEngineTests.swift`:

```swift
import Testing
@testable import CleanerCore

/// Solo Swift: il motore dietro la CLI si riconosce dall'`OperatingSystem` del daemon.
struct DockerEngineTests {
    @Test(arguments: [
        ("Docker Desktop", DockerEngineKind.dockerDesktop, "Docker Desktop"),
        ("docker desktop", .dockerDesktop, "Docker Desktop"),
        ("OrbStack", .orbStack, "OrbStack"),
        ("orbstack", .orbStack, "OrbStack"),
        ("Ubuntu 24.04.1 LTS", .other, "Docker"),
        ("OrbStack Linux", .other, "Docker"),
        ("", .other, "Docker"),
    ])
    func recognizesTheEngineFromTheWholeOperatingSystemName(operatingSystem: String, kind: DockerEngineKind, name: String) {
        let engine = DockerEngine(serverVersion: "29.8.2", operatingSystem: operatingSystem)

        #expect(engine.kind == kind)
        #expect(engine.displayName == name)
        #expect(engine.operatingSystem == operatingSystem)
        #expect(engine.serverVersion == "29.8.2")
    }
}
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerCli.swift`, subito prima di `/// Una CLI che risponde con l'intero caso reale delle fixture.`, aggiungere:

```swift
    /// La riga di `docker info` con cui `DockerInventoryCollector.checkDaemon` riconosce il motore.
    static let infoCommand = "info --format " + DockerInventoryCollector.engineFormat

    /// La risposta di `docker info` di un daemon `version` che si presenta come `operatingSystem`.
    static func info(_ version: String, _ operatingSystem: String = "Docker Desktop") -> String {
        #"{"ServerVersion":"\#(version)","OperatingSystem":"\#(operatingSystem)"}"# + "\n"
    }

```

e, nello stesso file, sostituire in `withRealCase()`

```swift
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"\n")
```

con

```swift
            .on(infoCommand, info("29.8.0"))
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerInventoryCollectorTests.swift`:

1. Sostituire le due occorrenze di

```swift
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"")
```

con

```swift
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0"))
```

2. In `daemonThatDoesNotAnswerStopsTheCollection`, sostituire

```swift
            .on("info --format {{json .ServerVersion}}") { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
```

con

```swift
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
```

3. Sostituire l'intero test `emptyServerVersionMeansTheDaemonIsNotRunning` (dalla riga `@Test func emptyServerVersionMeansTheDaemonIsNotRunning() async {` alla sua `}` di chiusura) con:

```swift
    @Test(arguments: [
        #"{"ServerVersion":"","OperatingSystem":""}"#,
        #"{"ServerVersion":null,"OperatingSystem":"OrbStack"}"#,
        #"{"OperatingSystem":"Docker Desktop"}"#,
    ])
    func emptyServerVersionMeansTheDaemonIsNotRunning(output: String) async {
        // Senza daemon, "docker info" può comunque stampare la parte client e uscire con 0.
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, output)

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }

        #expect(error?.reason == .notRunning)
    }

    @Test func checkDaemonRecognizesTheEngineWithOneInfoCall() async throws {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack"))

        let engine = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()

        #expect(engine == DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"))
        #expect(engine.kind == .orbStack)
        #expect(cli.calls == [["info", "--format", DockerInventoryCollector.engineFormat]])
    }

    @Test func unreadableInfoIsAnOutputError() async {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, "29.8.2")

        await #expect(throws: DockerOutputError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()
        }
    }
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCliTests.swift`:

1. In `unreachableDaemonBecomesAReadableException`, sostituire

```swift
        #expect(error?.message.contains("Docker non è in esecuzione") == true)
```

con

```swift
        #expect(error == DockerUnavailableError(DockerUnavailableError.notRunning, reason: .notRunning))
        #expect(error?.message.contains("Avvia il motore Docker") == true)
```

2. In `missingBinaryBecomesAReadableException`, subito dopo `#expect(error?.message.contains("non è stato trovato") == true)`, aggiungere:

```swift
        #expect(error?.reason == .notInstalled)
```

3. Sostituire l'intero test `binaryThatCannotStartBecomesAReadableException` con:

```swift
    @Test func binaryThatCannotStartBecomesAReadableException() async {
        let cli = DockerCli(runner: FakeRunner { _, _ in throw ProcessLaunchError(executable: "/usr/local/bin/docker", code: ENOENT) }, binaryPath: "/usr/local/bin/docker")

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }

        #expect(error?.reason == .notInstalled)
    }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`, in `unavailableDockerShowsItsMessageAndRetryLoadsAgain`, sostituire

```swift
        #expect(model.errorText == "Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.")
```

con

```swift
        #expect(model.errorText == "Docker non è in esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova.")
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `cannot find 'DockerEngine' in scope` e `type 'DockerInventoryCollector' has no member 'engineFormat'`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift`:

```swift
/// Il motore che risponde dietro la CLI `docker`, riconosciuto dall'`OperatingSystem` del daemon
/// («Docker Desktop», «OrbStack»; Colima, per esempio, riporta la distribuzione della sua macchina
/// virtuale). Quale motore si pulisce lo decide il contesto attivo della CLI: qui lo si riconosce
/// soltanto, per i testi e per il disco virtuale.
public enum DockerEngineKind: Sendable, Equatable {
    case dockerDesktop
    case orbStack
    case other
}

public struct DockerEngine: Sendable, Equatable {
    public let kind: DockerEngineKind
    /// «Docker Desktop», «OrbStack» oppure «Docker» per ogni altro motore.
    public let displayName: String
    /// L'`OperatingSystem` del daemon così com'è; può essere vuoto.
    public let operatingSystem: String
    public let serverVersion: String

    public init(serverVersion: String, operatingSystem: String) {
        let kind = Self.kind(named: operatingSystem)
        self.kind = kind
        self.serverVersion = serverVersion
        self.operatingSystem = operatingSystem
        displayName = switch kind {
        case .dockerDesktop: "Docker Desktop"
        case .orbStack: "OrbStack"
        case .other: "Docker"
        }
    }

    /// Il motore che porta questo nome. Il confronto è sull'intero valore, senza distinguere
    /// maiuscole e minuscole: un testo più lungo che contiene «OrbStack» non basta. Vale per
    /// l'`OperatingSystem` del daemon e per la descrizione di un contesto.
    static func kind(named name: String) -> DockerEngineKind {
        if PathText.equalsIgnoringCase(name, "Docker Desktop") { return .dockerDesktop }
        if PathText.equalsIgnoringCase(name, "OrbStack") { return .orbStack }
        return .other
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift`, sostituire l'intera dichiarazione di `DockerUnavailableError` (dal commento `/// Docker non raggiungibile: binario assente, …` alla `}` che chiude la struttura) con:

```swift
/// Docker non raggiungibile: binario assente, daemon spento, socket chiuso. Il messaggio è già
/// pensato per l'utente — l'interfaccia lo mostra così com'è. Porting di `DockerUnavailableException`.
public struct DockerUnavailableError: Error, Equatable, Sendable, LocalizedError {
    /// Perché Docker non risponde. Solo per «non in esecuzione» ha senso nominare il motore del
    /// contesto attivo: il motivo non si deduce più dal testo.
    public enum Reason: Sendable, Equatable {
        case notInstalled
        case notRunning
    }

    /// Testo generico: quando il contesto attivo dice quale motore è, l'analisi lo sostituisce con
    /// un testo che lo nomina.
    public static var notRunning: String {
        String(localized: "Docker non è in esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova.", bundle: .module)
    }

    public static var notInstalled: String {
        String(localized: "Docker non è installato o non è stato trovato.", bundle: .module)
    }

    public let message: String
    public let reason: Reason

    /// Il motivo predefinito è «non in esecuzione»: solo `DockerCli` lancia «non installato».
    public init(_ message: String, reason: Reason = .notRunning) {
        self.message = message
        self.reason = reason
    }

    public var errorDescription: String? { message }
}
```

Nello stesso file, in `DockerCli.run`, sostituire **entrambe** le occorrenze di

```swift
            throw DockerUnavailableError(DockerUnavailableError.notInstalled)
```

con

```swift
            throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled)
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift`, subito prima di `/// Un valore per riga: \`docker ps -aq\`.`, aggiungere:

```swift
    /// `docker info --format` con l'oggetto di `DockerInventoryCollector.engineFormat`. Campi
    /// assenti o `null` valgono stringa vuota.
    public static func parseEngineInfo(_ json: String) throws -> (serverVersion: String, operatingSystem: String) {
        let root = try parse(json, "docker info")
        return (string(root, "ServerVersion") ?? "", string(root, "OperatingSystem") ?? "")
    }

```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift`:

1. Sotto `private static let composeWorkingDirLabel = "com.docker.compose.project.working_dir"` aggiungere:

```swift
    /// Versione del server e motore con una sola chiamata `docker info`.
    static let engineFormat = #"{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}}}"#
```

2. Sostituire l'intero metodo `checkDaemon()` (dal commento `/// Verifica che il daemon risponda. Restituisce la versione del server.` alla sua `}` di chiusura) con:

```swift
    /// Verifica che il daemon risponda e riconosce il motore che lo esegue.
    public func checkDaemon() async throws -> DockerEngine {
        let info = try DockerJson.parseEngineInfo(try await cli.runChecked(["info", "--format", Self.engineFormat]))
        let version = DockerText.trimmed(info.serverVersion)

        // Senza daemon "docker info" può stampare comunque la parte client e uscire con 0: una
        // versione del server vuota è l'unico segnale affidabile.
        if version.isEmpty {
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        return DockerEngine(serverVersion: version, operatingSystem: info.operatingSystem)
    }
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift`, in `analyze`, sostituire

```swift
        let version = try await collector.checkDaemon()
```

con

```swift
        let engine = try await collector.checkDaemon()
```

e

```swift
            serverVersion: version,
```

con

```swift
            serverVersion: engine.serverVersion,
```

- [ ] **Step 4: Verificare che i test passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 539 tests in 49 suites passed` e `Test run with 173 tests in 21 suites passed`, nessun warning.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerEngineTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerCli.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerInventoryCollectorTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCliTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift
git commit -F - <<'EOF'
feat(docker): recognize the engine behind the docker CLI

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Nominare il motore del contesto attivo quando il daemon non risponde

**Files:**
- Create: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift` (nuovo `parseContext`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` (file intero)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift` (costruzione del servizio)
- Test: create `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerContextTests.swift`; modify `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift` (file intero)

**Interfaces:**
- Consumes: `DockerEngine.kind(named:)`, `DockerEngineKind`, `DockerUnavailableError.reason` (Task 1)
- Produces:
  - `public struct DockerContext: Sendable, Equatable` con `name`, `description`, `host`, `init(name:description:host:)` e `func engineKind(homeDirectory: String) -> DockerEngineKind`
  - `DockerUnavailableError.notRunningMessage(_ context: DockerContext?, homeDirectory: String) -> String`
  - `public struct DockerContextReader: Sendable` con `init(cli: any DockerCommandRunning, homeDirectory: String)`, `func activeContext() async -> DockerContext?` e `func notRunningMessage() async -> String`
  - `DockerJson.parseContext(_:) throws -> DockerContext`
  - `DockerCleanupService.init(collector:scanner:disk:executor:contexts:)`

- [ ] **Step 1: Scrivere i test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerContextTests.swift`:

```swift
import Testing
@testable import CleanerCore

/// Solo Swift: il motore del contesto attivo, per l'errore di un daemon che non risponde.
struct DockerContextTests {
    private static let home = "/Users/tester"
    /// Non privata: la usano gli argomenti di `@Test`.
    static let generic = "Docker non è in esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova."

    @Test func parsesTheActiveContextAsPrintedByTheCli() throws {
        // Misurato con OrbStack il 2026-10-19: `docker context inspect --format '{{json .}}'`.
        let json = #"{"Name":"orbstack","Metadata":{"Description":"OrbStack"},"Endpoints":{"docker":{"Host":"unix:///Users/tester/.orbstack/run/docker.sock","SkipTLSVerify":false}},"TLSMaterial":{},"Storage":{"MetadataPath":"/Users/tester/.docker/contexts/meta/2d89","TLSPath":"/Users/tester/.docker/contexts/tls/2d89"}}"#

        #expect(try DockerJson.parseContext(json) == DockerContext(
            name: "orbstack", description: "OrbStack", host: "unix:///Users/tester/.orbstack/run/docker.sock"))
    }

    @Test func theDefaultContextHasNoDescription() throws {
        let json = #"{"Name":"default","Metadata":{},"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock","SkipTLSVerify":false}}}"#

        #expect(try DockerJson.parseContext(json) == DockerContext(name: "default", description: "", host: "unix:///var/run/docker.sock"))
    }

    @Test(arguments: [
        ("Docker Desktop", "unix:///Users/tester/.orbstack/run/docker.sock", DockerEngineKind.dockerDesktop),
        ("OrbStack", "unix:///Users/tester/.docker/run/docker.sock", .orbStack),
        ("", "unix:///Users/tester/.docker/run/docker.sock", .dockerDesktop),
        ("", "unix:///Users/tester/.orbstack/run/docker.sock", .orbStack),
        ("", "unix:///var/run/docker.sock", .other),
        ("", "tcp://127.0.0.1:2375", .other),
        ("", "unix:///Users/altro/.orbstack/run/docker.sock", .other),
        ("", "unix:///Users/tester/.orbstack/runtime/docker.sock", .other),
        ("Colima", "unix:///Users/tester/.colima/default/docker.sock", .other),
    ])
    func recognizesTheEngineFromDescriptionThenEndpoint(description: String, host: String, expected: DockerEngineKind) {
        let context = DockerContext(name: "ctx", description: description, host: host)

        #expect(context.engineKind(homeDirectory: Self.home + "/") == expected)
    }

    @Test(arguments: [
        (DockerContext(name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/tester/.docker/run/docker.sock") as DockerContext?,
         "Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."),
        (DockerContext(name: "orbstack", description: "", host: "unix:///Users/tester/.orbstack/run/docker.sock"),
         "OrbStack non è in esecuzione (contesto «orbstack»). Avvialo e premi Riprova."),
        (DockerContext(name: "default", description: "", host: "unix:///var/run/docker.sock"),
         "Il motore Docker del contesto «default» non risponde. Avvialo e premi Riprova."),
        (DockerContext(name: " ", description: "OrbStack", host: ""), DockerContextTests.generic),
        (nil, DockerContextTests.generic),
    ])
    func notRunningMessageNamesTheEngineOfTheContext(context: DockerContext?, expected: String) {
        #expect(DockerUnavailableError.notRunningMessage(context, homeDirectory: Self.home) == expected)
    }
}
```

Sostituire l'intero contenuto di `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift` con:

```swift
import Testing
@testable import CleanerCore

struct DockerCleanupServiceTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    private static let contextCommand = "context inspect --format {{json .}}"

    private struct NoProcess: ProcessRunning {
        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            ProcessResult(exitCode: 0, standardOutput: "16\t" + DockerCleanupServiceTests.rawPath, standardError: "", timedOut: false)
        }
    }

    private func service(_ fs: InMemoryFileSystem, _ cli: FakeDockerCli) -> DockerCleanupService {
        DockerCleanupService(
            collector: DockerInventoryCollector(cli: cli, fileSystem: fs),
            scanner: ProjectReferenceScanner(fileSystem: fs),
            disk: DiskUsageProbe(runner: NoProcess(), fileSystem: fs, diskImagePath: Self.rawPath),
            executor: DockerCleanExecutor(cli: cli, clock: SystemWallClock()),
            contexts: DockerContextReader(cli: cli, homeDirectory: "/Users/tester"))
    }

    @Test func analysisClassifiesWithTheReferencesFoundInTheProjects() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/projects/orbit/Orbit.AppHost/Program.cs", text: """
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddKeycloak("keycloak").WithImageTag("26.6");
            """)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze(["/Users/tester/projects"])

        let keycloak = try #require(analysis.candidates.first { $0.displayName == "quay.io/keycloak/keycloak:26.6" })
        #expect(keycloak.verdict == .keep)
        #expect(keycloak.reason.contains("Program.cs:2"))
    }

    @Test func analysisMeasuresTheDiskImage() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze([])

        #expect(analysis.disk.allocatedBytes == Int64(16 * 1024))
        #expect(analysis.disk.apparentBytes == 100)
        #expect(analysis.snapshot.df.images == 5_840_000_000)
    }

    @Test func aDaemonThatDoesNotAnswerNamesTheEngineOfTheActiveContext() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
            .on(Self.contextCommand, #"{"Name":"desktop-linux","Metadata":{"Description":"Docker Desktop"},"Endpoints":{"docker":{"Host":"unix:///Users/tester/.docker/run/docker.sock"}}}"#)

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
    }

    @Test func anUnreadableContextKeepsTheGenericMessage() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notRunning))
        #expect(cli.commandLines.last == Self.contextCommand)
    }

    @Test func aMissingDockerIsNeverRewritten() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled))
        #expect(!cli.commandLines.contains { $0.hasPrefix("context") })
    }
}
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `cannot find 'DockerContext' in scope` e `type 'DockerJson' has no member 'parseContext'`.

- [ ] **Step 3: Implementare**

Creare `MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift`:

```swift
/// Il contesto attivo della CLI, letto con `docker context inspect`, che non contatta il daemon: a
/// daemon spento è l'unico modo di dire quale motore l'utente deve avviare.
public struct DockerContext: Sendable, Equatable {
    public let name: String
    public let description: String
    /// L'endpoint Docker come lo scrive la CLI, per esempio `unix:///Users/x/.orbstack/run/docker.sock`.
    public let host: String

    public init(name: String, description: String, host: String) {
        self.name = name
        self.description = description
        self.host = host
    }

    /// Il motore del contesto: decide la descrizione («Docker Desktop», «OrbStack»), poi l'endpoint,
    /// riconosciuto solo nella forma `unix://` sotto la home. `/var/run/docker.sock` non si risolve:
    /// è un collegamento che l'ultimo motore installato può riscrivere.
    public func engineKind(homeDirectory: String) -> DockerEngineKind {
        let named = DockerEngine.kind(named: description)
        if named != .other { return named }

        let scheme = "unix://"
        guard DockerText.hasPrefix(host, scheme) else { return .other }
        let socket = String(decoding: host.utf8.dropFirst(scheme.utf8.count), as: UTF8.self)
        let home = PathText.trimmingTrailingSlashes(homeDirectory)

        if PathText.isSameOrUnder(socket, home + "/.docker/run") { return .dockerDesktop }
        if PathText.isSameOrUnder(socket, home + "/.orbstack/run") { return .orbStack }
        return .other
    }
}

extension DockerUnavailableError {
    /// Il testo per un daemon che non risponde, con il motore del contesto attivo quando lo si
    /// conosce; senza contesto, o con un contesto senza nome, il testo generico.
    public static func notRunningMessage(_ context: DockerContext?, homeDirectory: String) -> String {
        guard let context, !DockerText.isBlank(context.name) else { return notRunning }

        return switch context.engineKind(homeDirectory: homeDirectory) {
        case .dockerDesktop:
            String(localized: "Docker Desktop non è in esecuzione (contesto «\(context.name)»). Avvialo e premi Riprova.", bundle: .module)
        case .orbStack:
            String(localized: "OrbStack non è in esecuzione (contesto «\(context.name)»). Avvialo e premi Riprova.", bundle: .module)
        case .other:
            String(localized: "Il motore Docker del contesto «\(context.name)» non risponde. Avvialo e premi Riprova.", bundle: .module)
        }
    }
}

/// Legge il contesto attivo. Non lancia: un contesto illeggibile, anche per annullamento, lascia
/// il testo generico, e il messaggio d'errore non deve diventare a sua volta un errore.
public struct DockerContextReader: Sendable {
    private let cli: any DockerCommandRunning
    private let homeDirectory: String

    public init(cli: any DockerCommandRunning, homeDirectory: String) {
        self.cli = cli
        self.homeDirectory = homeDirectory
    }

    public func activeContext() async -> DockerContext? {
        do {
            return try DockerJson.parseContext(try await cli.runChecked(["context", "inspect", "--format", "{{json .}}"]))
        } catch {
            return nil
        }
    }

    public func notRunningMessage() async -> String {
        DockerUnavailableError.notRunningMessage(await activeContext(), homeDirectory: homeDirectory)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift`, subito prima di `/// Un valore per riga: \`docker ps -aq\`.`, aggiungere:

```swift
    /// `docker context inspect --format {{json .}}`: nome, descrizione ed endpoint Docker. Campi
    /// assenti valgono stringa vuota (il contesto `default` non ha descrizione).
    public static func parseContext(_ json: String) throws -> DockerContext {
        let root = try parse(json, "docker context inspect")
        return DockerContext(
            name: string(root, "Name") ?? "",
            description: string(child(root, "Metadata"), "Description") ?? "",
            host: string(child(child(root, "Endpoints"), "docker"), "Host") ?? "")
    }

```

Sostituire l'intero contenuto di `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` con:

```swift
/// `serverVersion`: versione del daemon che ha risposto.
public struct DockerAnalysis: Sendable, Equatable {
    public let serverVersion: String
    public let snapshot: DockerSnapshot
    public let candidates: [DockerCandidate]
    public let disk: DockerDiskUsage

    public init(serverVersion: String, snapshot: DockerSnapshot, candidates: [DockerCandidate], disk: DockerDiskUsage) {
        self.serverVersion = serverVersion
        self.snapshot = snapshot
        self.candidates = candidates
        self.disk = disk
    }
}

/// Il flusso completo per l'interfaccia: analisi in sola lettura, esecuzione, misura del disco.
public struct DockerCleanupService: Sendable {
    private let collector: DockerInventoryCollector
    private let scanner: ProjectReferenceScanner
    private let disk: DiskUsageProbe
    private let executor: DockerCleanExecutor
    private let contexts: DockerContextReader

    public init(
        collector: DockerInventoryCollector,
        scanner: ProjectReferenceScanner,
        disk: DiskUsageProbe,
        executor: DockerCleanExecutor,
        contexts: DockerContextReader
    ) {
        self.collector = collector
        self.scanner = scanner
        self.disk = disk
        self.executor = executor
        self.contexts = contexts
    }

    /// Un daemon che non risponde diventa un errore che nomina il motore del contesto attivo:
    /// l'utente sa quale avviare. «Non installato» resta com'è.
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        do {
            return try await analyzeRunningDaemon(projectRoots)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(await contexts.notRunningMessage())
        }
    }

    public func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        try await executor.execute(selected, progress: progress)
    }

    public func measureDisk() async throws -> DockerDiskUsage {
        try await disk.measure()
    }

    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI. Le attività figlie di `async let`
    /// girano sull'executor globale, mai su quello del chiamante (`Task.Run` nel C#).
    @concurrent
    private func analyzeRunningDaemon(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let engine = try await collector.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure()
        let snapshot = try await collector.collect()

        return DockerAnalysis(
            serverVersion: engine.serverVersion,
            snapshot: snapshot,
            candidates: try DockerClassifier.classify(snapshot, try await references),
            disk: try await usage)
    }
}
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire

```swift
            executor: DockerCleanExecutor(cli: dockerCli, clock: clock))
```

con

```swift
            executor: DockerCleanExecutor(cli: dockerCli, clock: clock),
            contexts: DockerContextReader(cli: dockerCli, homeDirectory: home))
```

- [ ] **Step 4: Verificare che i test passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 546 tests in 50 suites passed` e `Test run with 173 tests in 21 suites passed`, nessun warning.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerContextTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift
git commit -F - <<'EOF'
feat(docker): name the engine of the active context when the daemon is down

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Binario di OrbStack, collegamenti orfani e deny-list

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift` (`DockerBinaryLocator`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Safety/DenyList.swift` (una voce)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift` (commento e chiamata del locator)
- Test: modify `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCliTests.swift` e `MjmCleanerKit/Tests/CleanerCoreTests/Safety/DenyListTests.swift`

**Interfaces:**
- Produces:
  - `DockerBinaryLocator.candidates(homeDirectory: String) -> [String]`
  - `DockerBinaryLocator.find(homeDirectory: String, isExecutable: (String) -> Bool = DockerBinaryLocator.isExecutableFile) -> String?` (sostituisce `find(_:homeDirectory:)`)
  - `DockerBinaryLocator.isExecutableFile(_ path: String) -> Bool`

- [ ] **Step 1: Scrivere i test che falliscono**

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCliTests.swift`, sostituire i tre test `locatorPrefersTheDockerDesktopUserBinary`, `locatorFallsBackToTheAppBundle` e `locatorReturnsNullWhenDockerIsNotInstalled` (dal primo `@Test func locatorPrefersTheDockerDesktopUserBinary() {` alla `}` di chiusura di `locatorReturnsNullWhenDockerIsNotInstalled`, prima della `}` che chiude la struttura) con:

```swift
    @Test func candidatesKeepTheirOrder() {
        #expect(DockerBinaryLocator.candidates(homeDirectory: "/Users/tester") == [
            "/Users/tester/.docker/bin/docker",
            "/Users/tester/.orbstack/bin/docker",
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ])
    }

    @Test(arguments: [
        (["/usr/local/bin/docker", "/Users/tester/.orbstack/bin/docker", "/Users/tester/.docker/bin/docker"], "/Users/tester/.docker/bin/docker"),
        (["/usr/local/bin/docker", "/Users/tester/.orbstack/bin/docker"], "/Users/tester/.orbstack/bin/docker"),
        (["/Applications/OrbStack.app/Contents/MacOS/xbin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"], "/Applications/Docker.app/Contents/Resources/bin/docker"),
        (["/Applications/OrbStack.app/Contents/MacOS/xbin/docker"], "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"),
    ])
    func locatorTakesTheFirstExecutableCandidate(executables: [String], expected: String) {
        #expect(DockerBinaryLocator.find(homeDirectory: "/Users/tester", isExecutable: Set(executables).contains) == expected)
    }

    @Test func locatorReturnsNilWhenDockerIsNotInstalled() {
        #expect(DockerBinaryLocator.find(homeDirectory: "/Users/tester", isExecutable: { _ in false }) == nil)
    }

    /// Solo Swift: conta un file regolare eseguibile, raggiunto seguendo i collegamenti; un
    /// collegamento orfano non è un binario.
    @Test func onlyAnExecutableFileReachedThroughItsLinksCounts() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let binary = try directory.file("bin/docker")
        #expect(chmod(binary, 0o755) == 0)
        let plain = try directory.file("bin/plain")
        let link = try directory.symlink("links/docker", to: binary)
        let orphan = try directory.symlink("links/orphan", to: directory.path + "/missing/docker")
        let folder = try directory.directory("folder")

        #expect(DockerBinaryLocator.isExecutableFile(binary))
        #expect(DockerBinaryLocator.isExecutableFile(link))
        #expect(!DockerBinaryLocator.isExecutableFile(orphan))
        #expect(!DockerBinaryLocator.isExecutableFile(plain))
        #expect(!DockerBinaryLocator.isExecutableFile(folder))
        #expect(!DockerBinaryLocator.isExecutableFile(directory.path + "/missing/docker"))
    }

    /// Solo Swift: disinstallare Docker Desktop può lasciare `~/.docker/bin/docker` orfano; con il
    /// predicato predefinito il locator passa al binario di OrbStack.
    @Test func locatorSkipsAnOrphanedDockerDesktopLink() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try home.symlink(".docker/bin/docker", to: "/Applications/Docker.app/Contents/Resources/bin/docker-uninstalled")
        let orbStack = try home.file(".orbstack/bin/docker")
        #expect(chmod(orbStack, 0o755) == 0)

        #expect(DockerBinaryLocator.find(homeDirectory: home.path) == orbStack)
    }
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Safety/DenyListTests.swift`, subito prima di `@Test func deniesDockerContainerWithSpecificReasonBeforeGenericContainers() throws {`, aggiungere:

```swift
    @Test(arguments: [
        "/Users/tester/.orbstack",
        "/Users/tester/.orbstack/run/docker.sock",
        "/Users/tester/.orbstack/ssh/id_ed25519",
    ])
    func deniesTheOrbStackFolder(path: String) throws {
        #expect(try create().deniedReason(path) == "percorso protetto: /Users/tester/.orbstack")
    }

```

- [ ] **Step 2: Verificare che i test falliscano**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `type 'DockerBinaryLocator' has no member 'candidates'`.

- [ ] **Step 3: Implementare**

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift`, sostituire l'intera dichiarazione di `DockerBinaryLocator` (da `public enum DockerBinaryLocator {` alla sua `}` di chiusura, in fondo al file) con:

```swift
public enum DockerBinaryLocator {
    /// Percorsi noti, in ordine: Docker Desktop e OrbStack per l'utente, installazione di sistema,
    /// Homebrew, bundle delle due app. Il binario non sceglie il motore (lo fa il contesto attivo
    /// della CLI): basta che si avvii.
    public static func candidates(homeDirectory: String) -> [String] {
        [
            PathText.join(PathText.join(PathText.join(homeDirectory, ".docker"), "bin"), "docker"),
            PathText.join(PathText.join(PathText.join(homeDirectory, ".orbstack"), "bin"), "docker"),
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ]
    }

    /// Il primo candidato che si può eseguire. Disinstallare Docker Desktop può lasciare
    /// `~/.docker/bin/docker` come collegamento orfano: `FileSystem.fileExists` lo darebbe per
    /// presente e l'app direbbe «Docker non è installato» anche con OrbStack acceso.
    public static func find(homeDirectory: String, isExecutable: (String) -> Bool = DockerBinaryLocator.isExecutableFile) -> String? {
        candidates(homeDirectory: homeDirectory).first(where: isExecutable)
    }

    /// Un file regolare eseguibile, raggiunto seguendo i collegamenti (`stat`, non `lstat`).
    public static func isExecutableFile(_ path: String) -> Bool {
        var status = stat()
        guard stat(path, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else { return false }
        return access(path, X_OK) == 0
    }
}
```

Nello stesso file, nel commento di `environment(_:)` sopra `private static func environment`, sostituire

```swift
    /// Un'app aperta dal Finder riceve un PATH minimo (/usr/bin:/bin:…): la CLI di Docker Desktop
    /// cerca accanto a sé i propri helper (credential helper, plugin), quindi la sua cartella va in
    /// testa.
```

con

```swift
    /// Un'app aperta dal Finder riceve un PATH minimo (/usr/bin:/bin:…): la CLI, di Docker Desktop
    /// come di OrbStack, cerca accanto a sé i propri helper (credential helper, plugin), quindi la
    /// sua cartella va in testa.
```

In `MjmCleanerKit/Sources/CleanerCore/Safety/DenyList.swift`, sostituire

```swift
            "\(home)/.docker",
```

con

```swift
            "\(home)/.docker",
            // OrbStack: socket, configurazione e chiavi SSH della sua macchina virtuale. Il suo
            // group container è già coperto da "Library/Group Containers".
            "\(home)/.orbstack",
```

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire

```swift
        // Docker passa solo dalla CLI: nessun file sotto la cartella di Docker Desktop viene mai
        // cancellato (la deny-list resta invariata); di Docker.raw si legge soltanto la dimensione.
        let processes = ProcessRunner()
        let dockerCli = DockerCli(runner: processes, binaryPath: DockerBinaryLocator.find(fileSystem, homeDirectory: home))
```

con

```swift
        // Docker passa solo dalla CLI: nessun file sotto le cartelle dei motori (Docker Desktop,
        // OrbStack) viene mai cancellato, perché la deny-list le protegge; di Docker.raw si legge
        // soltanto la dimensione.
        let processes = ProcessRunner()
        let dockerCli = DockerCli(runner: processes, binaryPath: DockerBinaryLocator.find(homeDirectory: home))
```

- [ ] **Step 4: Verificare che i test passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 549 tests in 50 suites passed` e `Test run with 173 tests in 21 suites passed`, nessun warning.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift MjmCleanerKit/Sources/CleanerCore/Safety/DenyList.swift MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCliTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Safety/DenyListTests.swift
git commit -F - <<'EOF'
feat(docker): find the OrbStack CLI, skip orphaned links, protect ~/.orbstack

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: Il motore arriva alla pagina Docker

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DiskUsageProbe.swift` (nuovo `measure(for:)`, un commento)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` (file intero)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift` (file intero)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift` (`diskAfter` opzionale)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift` (`diskAfter` opzionale)
- Modify: `MjmCleaner/Demo/DemoData.swift`, `MjmCleaner/Demo/DemoServices.swift`
- Test: modify `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DiskUsageProbeTests.swift`, `DockerCleanupServiceTests.swift`; `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, `Support/DockerNavigationSpy.swift`, `DockerModelTests.swift`, `DockerReportModelTests.swift`

**Interfaces:**
- Consumes: `DockerEngine`, `DockerEngineKind` (Task 1); `DockerCleanupService.init(…, contexts:)` (Task 2)
- Produces:
  - `DiskUsageProbe.measure(for engine: DockerEngine) async throws -> DockerDiskUsage?`
  - `DockerAnalysis(engine: DockerEngine, snapshot:, candidates:, disk: DockerDiskUsage?)`, proprietà `engine` e `disk: DockerDiskUsage?` (al posto di `serverVersion`)
  - `DockerCleanupService.measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage?` e lo stesso requisito in `DockerCleanupServing`
  - `DockerNavigating.showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)`
  - `DockerReportModel.init(…, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)`
  - `DockerModel.describeServer(_ engine: DockerEngine) -> String`, `DockerModel.describeDisk(_ disk: DockerDiskUsage?, engine: DockerEngine) -> String`
  - nei test di Features: `let dockerDesktop: DockerEngine`, `dockerAnalysis(_:engine:disk:df:)`, `FakeDocker.measuredEngines`, `FakeDocker.setDiskAfter(_: DockerDiskUsage?)`

- [ ] **Step 1: Scrivere i test che falliscono (Core)**

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DiskUsageProbeTests.swift`, subito prima di `@Test func failingDuLeavesOnlyTheApparentSize() async throws {`, aggiungere:

```swift
    @Test func onlyDockerDesktopHasADiskToMeasure() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 4096)
        let du = DuRunner(standardOutput: "8\t" + Self.rawPath + "\n")
        let probe = DiskUsageProbe(runner: du, fileSystem: fs, diskImagePath: Self.rawPath)

        // Un Docker.raw lasciato da Docker Desktop non riguarda OrbStack né un altro motore.
        let orbStack = try await probe.measure(for: DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"))
        let colima = try await probe.measure(for: DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04"))
        #expect(orbStack == nil)
        #expect(colima == nil)
        #expect(du.calls.values.isEmpty)

        let desktop = try await probe.measure(for: DockerEngine(serverVersion: "29.8.2", operatingSystem: "Docker Desktop"))
        #expect(desktop?.allocatedBytes == Int64(8 * 1024))
        #expect(du.calls.values == [["du", "-k", Self.rawPath]])
    }

```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift`:

1. Sostituire l'intero test `analysisMeasuresTheDiskImage` con:

```swift
    @Test func analysisMeasuresTheDiskImage() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)

        let analysis = try await service(fs, FakeDockerCli.withRealCase()).analyze([])

        #expect(analysis.engine == DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop"))
        #expect(analysis.disk?.allocatedBytes == Int64(16 * 1024))
        #expect(analysis.disk?.apparentBytes == 100)
        #expect(analysis.snapshot.df.images == 5_840_000_000)
    }

    /// Sul Mac dell'utente Docker Desktop ha lasciato un Docker.raw: con OrbStack non si misura.
    @Test func orbStackHasNoDiskToMeasureEvenWithADockerRawLeftBehind() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)
        let cli = try FakeDockerCli.withRealCase().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack"))
        let docker = service(fs, cli)

        let analysis = try await docker.analyze([])
        let after = try await docker.measureDisk(for: analysis.engine)

        #expect(analysis.engine.kind == .orbStack)
        #expect(analysis.disk == nil)
        #expect(after == nil)
    }
```

- [ ] **Step 2: Scrivere i test che falliscono (Features)**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`:

1. Sostituire

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {
```

con

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
```

2. Sostituire l'intera funzione `dockerAnalysis` (da `func dockerAnalysis(` alla sua `}` di chiusura, in fondo al file) con:

```swift
/// Il motore delle analisi di prova, se il test non ne sceglie un altro.
let dockerDesktop = DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop")

func dockerAnalysis(
    _ candidates: [DockerCandidate],
    engine: DockerEngine = dockerDesktop,
    disk: DockerDiskUsage? = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824),
    df: DockerDfSummary = .empty
) -> DockerAnalysis {
    DockerAnalysis(
        engine: engine,
        snapshot: DockerSnapshot(containers: [], images: [], volumes: [], df: df, existingComposeProjects: []),
        candidates: candidates,
        disk: disk)
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, nella classe `FakeDocker`:

1. Nello `struct State`, sostituire

```swift
        var disk = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
```

con

```swift
        var disk: DockerDiskUsage? = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
        var measuredEngines: [DockerEngine] = []
```

2. Sostituire

```swift
    func setDiskAfter(_ disk: DockerDiskUsage) { state.withLock { $0.disk = disk } }
```

con

```swift
    var measuredEngines: [DockerEngine] { state.withLock { $0.measuredEngines } }
    func setDiskAfter(_ disk: DockerDiskUsage?) { state.withLock { $0.disk = disk } }
```

3. Sostituire

```swift
    func measureDisk() async throws -> DockerDiskUsage {
        state.withLock { $0.disk }
    }
```

con

```swift
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        state.withLock { state in
            state.measuredEngines.append(engine)
            return state.disk
        }
    }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift`, in `SharedEventsNavigation` in fondo al file, sostituire

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {}
```

con

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`:

1. In `analysisFillsTheSummaryAndTheGroups`, sostituire

```swift
        #expect(model.serverText == "Docker 27.3.1 in esecuzione")
```

con

```swift
        #expect(model.serverText == "Docker Desktop · Docker 27.3.1 in esecuzione")
```

2. In `deleteExecutesTheSelectionAndShowsTheReport`, subito dopo `#expect(docker.executed.map { $0.map(\.id) } == [["dangling"]])`, aggiungere:

```swift
        #expect(docker.measuredEngines == [dockerDesktop])
```

3. Sostituire l'intero test `diskDescriptionsCoverMissingAndUnmeasurableImages` con:

```swift
    @Test func diskDescriptionsCoverMissingAndUnmeasurableImages() {
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: nil), engine: dockerDesktop)
            == "Disco virtuale di Docker Desktop non trovato: lo spazio occupato sul Mac non è misurabile.")
        #expect(DockerModel.describeDisk(DockerDiskUsage(path: "/x", allocatedBytes: nil, apparentBytes: 10), engine: dockerDesktop)
            == "Docker.raw trovato, ma lo spazio occupato non è misurabile.")
        #expect(DockerModel.typeLabel("Altro") == "Altro")
    }

    @Test(arguments: [
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"),
         "OrbStack · Docker 29.8.2 in esecuzione",
         "OrbStack restituisce da solo al Mac lo spazio liberato: il suo disco virtuale non viene misurato."),
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04"),
         "Docker 29.8.2 in esecuzione su «Ubuntu 24.04»",
         "Disco virtuale di questo motore non misurato: fa fede docker system df."),
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: ""),
         "Docker 29.8.2 in esecuzione",
         "Disco virtuale di questo motore non misurato: fa fede docker system df."),
    ])
    func summaryNamesTheEngineAndItsDisk(engine: DockerEngine, server: String, disk: String) async throws {
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed, engine: engine, disk: nil)))
        let model = try await opened(docker: docker)

        #expect(model.serverText == server)
        #expect(model.diskText == disk)
    }

    /// Dopo la pulizia il disco si misura per il motore dell'analisi: con OrbStack non c'è nulla da
    /// misurare e il resoconto non riceve misure.
    @Test func theDiskAfterTheCleanupBelongsToTheEngineOfTheAnalysis() async throws {
        let orbStack = DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack")
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed, engine: orbStack, disk: nil)))
        docker.setDiskAfter(nil)
        let navigation = DockerNavigationSpy()
        let model = try await opened(docker: docker, navigation: navigation)

        await model.delete()

        #expect(docker.measuredEngines == [orbStack])
        #expect(navigation.events == ["dockerReport"])
        #expect(navigation.reportDiskBefore == nil)
        #expect(navigation.reportDiskAfter == nil)
    }
```

4. In `SlowFirstAnalysisDocker`, sostituire

```swift
    func measureDisk() async throws -> DockerDiskUsage {
        DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
    }
```

con

```swift
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        DockerDiskUsage(path: "/Docker.raw", allocatedBytes: nil, apparentBytes: nil)
    }
```

5. In `SequencedDocker`, sostituire

```swift
    func measureDisk() async throws -> DockerDiskUsage {
        // Come `DiskUsageProbe`: `ProcessRunner.run` comincia con `Task.checkCancellation()`.
```

con

```swift
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        // Come `DiskUsageProbe`: `ProcessRunner.run` comincia con `Task.checkCancellation()`.
```

- [ ] **Step 3: Verificare che i test falliscano**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `value of type 'DockerAnalysis' has no member 'engine'` e `cannot use optional chaining on non-optional value of type 'DockerDiskUsage'`.

- [ ] **Step 4: Implementare il Core**

In `MjmCleanerKit/Sources/CleanerCore/Docker/DiskUsageProbe.swift`:

1. Subito dopo il metodo `defaultPath(_:)` (dopo la sua `}` di chiusura), aggiungere:

```swift

    /// Il disco virtuale del motore che risponde. Si misura solo `Docker.raw` di Docker Desktop:
    /// OrbStack riduce da solo il suo `data.img.raw`, che sta in un group container protetto da
    /// macOS (leggerlo chiederebbe all'utente l'accesso ai dati di altre app), e degli altri motori
    /// non si sa dove sia il disco. `nil`: nessun accesso al filesystem, nessun `du`.
    @concurrent
    public func measure(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        guard engine.kind == .dockerDesktop else { return nil }
        return try await measure()
    }
```

2. Sostituire

```swift
        // Altre piattaforme, Docker non Desktop (Colima, OrbStack) o un disco spostato altrove: il
        // file può non esistere, e allora non c'è nulla da misurare.
```

con

```swift
        // Altre piattaforme o un disco spostato altrove: il file può non esistere, e allora non c'è
        // nulla da misurare.
```

Sostituire l'intero contenuto di `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` con:

```swift
/// `engine`: il motore che ha risposto. `disk`: il suo disco virtuale, `nil` per un motore che non
/// ne ha uno da misurare (`DiskUsageProbe.measure(for:)`).
public struct DockerAnalysis: Sendable, Equatable {
    public let engine: DockerEngine
    public let snapshot: DockerSnapshot
    public let candidates: [DockerCandidate]
    public let disk: DockerDiskUsage?

    public init(engine: DockerEngine, snapshot: DockerSnapshot, candidates: [DockerCandidate], disk: DockerDiskUsage?) {
        self.engine = engine
        self.snapshot = snapshot
        self.candidates = candidates
        self.disk = disk
    }
}

/// Il flusso completo per l'interfaccia: analisi in sola lettura, esecuzione, misura del disco.
public struct DockerCleanupService: Sendable {
    private let collector: DockerInventoryCollector
    private let scanner: ProjectReferenceScanner
    private let disk: DiskUsageProbe
    private let executor: DockerCleanExecutor
    private let contexts: DockerContextReader

    public init(
        collector: DockerInventoryCollector,
        scanner: ProjectReferenceScanner,
        disk: DiskUsageProbe,
        executor: DockerCleanExecutor,
        contexts: DockerContextReader
    ) {
        self.collector = collector
        self.scanner = scanner
        self.disk = disk
        self.executor = executor
        self.contexts = contexts
    }

    /// Un daemon che non risponde diventa un errore che nomina il motore del contesto attivo:
    /// l'utente sa quale avviare. «Non installato» resta com'è.
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        do {
            return try await analyzeRunningDaemon(projectRoots)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(await contexts.notRunningMessage())
        }
    }

    public func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        try await executor.execute(selected, progress: progress)
    }

    /// Il disco del motore dell'analisi dopo la pulizia; `nil` se quel motore non ne ha uno da misurare.
    public func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        try await disk.measure(for: engine)
    }

    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI. Le attività figlie di `async let`
    /// girano sull'executor globale, mai su quello del chiamante (`Task.Run` nel C#).
    @concurrent
    private func analyzeRunningDaemon(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let engine = try await collector.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure(for: engine)
        let snapshot = try await collector.collect()

        return DockerAnalysis(
            engine: engine,
            snapshot: snapshot,
            candidates: try DockerClassifier.classify(snapshot, try await references),
            disk: try await usage)
    }
}
```

- [ ] **Step 5: Implementare Features e demo**

Sostituire l'intero contenuto di `MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift` con:

```swift
import CleanerCore

/// Il servizio Docker visto dalla pagina. In C# la pagina usava la classe concreta
/// `DockerCleanupService` e nessun test la esercitava; il protocollo permette di verificare la
/// pagina con un doppio, senza toccare il Core.
public protocol DockerCleanupServing: Sendable {
    func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult
    /// Il disco virtuale del motore dell'analisi dopo la pulizia; `nil` se quel motore non ne ha
    /// uno da misurare.
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage?
}

extension DockerCleanupService: DockerCleanupServing {}
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`:

1. Nel protocollo `DockerNavigating`, sostituire

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage)
```

con

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)
```

2. Nella classe `DockerModel`, sotto `@ObservationIgnored private var diskBefore: DockerDiskUsage?`, aggiungere:

```swift
    @ObservationIgnored private var engine: DockerEngine?
```

3. In `delete()`, sostituire

```swift
    public func delete() async {
        guard canDelete else { return }
```

con

```swift
    public func delete() async {
        // `canDelete` richiede un'analisi riuscita, che ha fissato il motore.
        guard canDelete, let engine else { return }
```

e

```swift
            let diskAfter = try await Task { try await docker.measureDisk() }.value
```

con

```swift
            let diskAfter = try await Task { try await docker.measureDisk(for: engine) }.value
```

4. In `load()`, sostituire

```swift
            diskBefore = analysis.disk
            serverText = String(localized: "Docker \(analysis.serverVersion) in esecuzione", bundle: .module)
            diskText = Self.describeDisk(analysis.disk)
```

con

```swift
            engine = analysis.engine
            diskBefore = analysis.disk
            serverText = Self.describeServer(analysis.engine)
            diskText = Self.describeDisk(analysis.disk, engine: analysis.engine)
```

e

```swift
            // Messaggio già pensato per l'utente: Docker Desktop non viene avviato da qui, è
            // l'utente a deciderlo.
```

con

```swift
            // Messaggio già pensato per l'utente: nessun motore viene avviato da qui, è l'utente a
            // deciderlo.
```

5. Sostituire

```swift
    static func describeDisk(_ disk: DockerDiskUsage) -> String {
        guard disk.exists else {
```

con

```swift
    static func describeServer(_ engine: DockerEngine) -> String {
        switch engine.kind {
        case .dockerDesktop, .orbStack:
            String(localized: "\(engine.displayName) · Docker \(engine.serverVersion) in esecuzione", bundle: .module)
        case .other where engine.operatingSystem.isEmpty:
            String(localized: "Docker \(engine.serverVersion) in esecuzione", bundle: .module)
        case .other:
            String(localized: "Docker \(engine.serverVersion) in esecuzione su «\(engine.operatingSystem)»", bundle: .module)
        }
    }

    /// Solo Docker Desktop ha un disco misurato (`DiskUsageProbe.measure(for:)`): OrbStack lo riduce
    /// da solo, per gli altri motori fa fede `docker system df`.
    static func describeDisk(_ disk: DockerDiskUsage?, engine: DockerEngine) -> String {
        if engine.kind == .orbStack {
            return String(
                localized: "OrbStack restituisce da solo al Mac lo spazio liberato: il suo disco virtuale non viene misurato.",
                bundle: .module)
        }
        guard let disk else {
            return String(localized: "Disco virtuale di questo motore non misurato: fa fede docker system df.", bundle: .module)
        }
        guard disk.exists else {
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift`:

1. Nell'inizializzatore, sostituire

```swift
        diskAfter: DockerDiskUsage
    ) {
```

con

```swift
        diskAfter: DockerDiskUsage?
    ) {
```

2. Sostituire

```swift
        if let before = diskBefore?.allocatedBytes, let after = diskAfter.allocatedBytes {
```

con

```swift
        if let before = diskBefore?.allocatedBytes, let after = diskAfter?.allocatedBytes {
```

3. Sostituire

```swift
           let rawAfter = diskAfter.allocatedBytes,
```

con

```swift
           let rawAfter = diskAfter?.allocatedBytes,
```

In `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`, sostituire

```swift
    public func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {
```

con

```swift
    public func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
```

In `MjmCleaner/Demo/DemoData.swift`, sostituire

```swift
    static let dockerAnalysis = DockerAnalysis(
        serverVersion: "27.3.1",
```

con

```swift
    static let dockerAnalysis = DockerAnalysis(
        engine: DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop"),
```

In `MjmCleaner/Demo/DemoServices.swift`, in `DemoDocker`, sostituire

```swift
    func measureDisk() async throws -> DockerDiskUsage {
```

con

```swift
    func measureDisk(for engine: DockerEngine) async throws -> DockerDiskUsage? {
```

- [ ] **Step 6: Verificare che i test passino e che l'app compili**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 551 tests in 50 suites passed` e `Test run with 175 tests in 21 suites passed`, nessun warning.

Run: comando «app» delle Global Constraints.
Expected: `** BUILD SUCCEEDED **`, nessuna riga `warning:` o `error:`.

- [ ] **Step 7: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DiskUsageProbe.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift MjmCleaner/Demo/DemoData.swift MjmCleaner/Demo/DemoServices.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DiskUsageProbeTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift
git commit -F - <<'EOF'
feat(docker): show the engine on the Docker page and measure only its own disk

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: Il resoconto Docker per motore

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift` (protocollo e `delete()`)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift` (inizializzatore e testi del disco)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`
- Modify: `MjmCleaner/Demo/DemoLaunch.swift`
- Test: modify `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`, `DockerReportModelTests.swift`, `DockerModelTests.swift`, `MainModelTests.swift`

**Interfaces:**
- Consumes: `DockerEngine` (Task 1); `dockerDesktop`, `dockerAnalysis(_:engine:disk:df:)`, `diskAfter` opzionale (Task 4)
- Produces:
  - `DockerNavigating.showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)`
  - `MainModel.showDockerReport(_:engine:diskBefore:diskAfter:)`
  - `DockerReportModel.init(environment:navigation:result:engine:diskBefore:diskAfter:)`
  - nei test: `DockerNavigationSpy.reportEngine`

- [ ] **Step 1: Scrivere i test che falliscono**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`, sostituire

```swift
    private(set) var reportResult: DockerCleanResult?
```

con

```swift
    private(set) var reportResult: DockerCleanResult?
    private(set) var reportEngine: DockerEngine?
```

e

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
        record("dockerReport")
        reportResult = result
```

con

```swift
    func showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
        record("dockerReport")
        reportResult = result
        reportEngine = engine
```

Aggiungere `engine: dockerDesktop,` prima di `diskBefore:` in ogni costruzione del resoconto di `DockerReportModelTests.swift` (10 occorrenze) e in ogni chiamata a `showDockerReport` di `MainModelTests.swift` (5 occorrenze). Dalla radice del repository:

```bash
sed -E -i '' 's/diskBefore: (nil|disk\()/engine: dockerDesktop, diskBefore: \1/g' MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift
sed -E -i '' 's/diskBefore: (nil|DockerDiskUsage\()/engine: dockerDesktop, diskBefore: \1/g' MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift
grep -c 'engine: dockerDesktop, diskBefore:' MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift
```

Expected dal `grep -c`: `DockerReportModelTests.swift:10` e `MainModelTests.swift:5`.

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift`:

1. In `textsSummarizeTheCleanup`, sostituire

```swift
        #expect(model.daemonLostText == "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate.")
```

con

```swift
        #expect(model.daemonLostText == "Docker Desktop si è fermato durante la pulizia: le voci restanti non sono state eliminate.")
```

2. Subito prima di `@Test func persistenceWritesTheLogUnderTheSavedIdBeforeRefreshingTheTotal() async throws {`, aggiungere:

```swift
    @Test(arguments: [
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"),
         "Disco virtuale: OrbStack restituisce lo spazio al Mac automaticamente.",
         "OrbStack si è fermato durante la pulizia: le voci restanti non sono state eliminate."),
        (DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04"),
         "Disco virtuale: non misurato per questo motore.",
         "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate."),
    ])
    func otherEnginesDescribeTheirDiskWithoutMeasures(engine: DockerEngine, diskText: String, daemonLostText: String) throws {
        let result = DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: nil, daemonLost: true)

        let model = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result,
            engine: engine, diskBefore: nil, diskAfter: nil)

        #expect(model.diskText == diskText)
        #expect(model.daemonLostText == daemonLostText)
        #expect(model.purgeHint == "")
    }

    /// Il Purge è un comando di Docker Desktop: anche con due misure di un disco che non cala, gli
    /// altri motori non lo suggeriscono.
    @Test(arguments: [
        DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack"),
        DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04"),
    ])
    func purgeIsSuggestedOnlyForDockerDesktop(engine: DockerEngine) throws {
        let result = DockerCleanResult(report: makeReport(itemsDeleted: 1), before: .empty, after: .empty, daemonLost: false)

        let model = DockerReportModel(
            environment: try makeEnvironment(), navigation: nil, result: result,
            engine: engine, diskBefore: disk(4 * Self.gigabyte), diskAfter: disk(4 * Self.gigabyte))

        #expect(model.purgeHint == "")
    }

```

3. In `SharedEventsNavigation`, sostituire

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {}
```

con

```swift
    func showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift`, sostituire

```swift
        #expect(report.daemonLostText == "Docker si è fermato durante la pulizia: le voci restanti non sono state eliminate.")
```

con

```swift
        #expect(report.daemonLostText == "Docker Desktop si è fermato durante la pulizia: le voci restanti non sono state eliminate.")
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`:

1. In `deleteExecutesTheSelectionAndShowsTheReport`, subito dopo `#expect(navigation.reportResult == result)`, aggiungere:

```swift
        #expect(navigation.reportEngine == dockerDesktop)
```

2. In `theDiskAfterTheCleanupBelongsToTheEngineOfTheAnalysis`, subito dopo `#expect(navigation.events == ["dockerReport"])`, aggiungere:

```swift
        #expect(navigation.reportEngine == orbStack)
```

- [ ] **Step 2: Verificare che i test falliscano**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `type 'DockerNavigationSpy' does not conform to protocol 'DockerNavigating'`.

- [ ] **Step 3: Implementare**

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`:

1. Nel protocollo `DockerNavigating`, sostituire

```swift
    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)
```

con

```swift
    func showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?)
```

2. In `delete()`, sostituire

```swift
            navigation?.showDockerReport(result, diskBefore: diskBefore, diskAfter: diskAfter)
```

con

```swift
            navigation?.showDockerReport(result, engine: engine, diskBefore: diskBefore, diskAfter: diskAfter)
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift`:

1. Nell'inizializzatore, sostituire

```swift
        result: DockerCleanResult,
        diskBefore: DockerDiskUsage?,
```

con

```swift
        result: DockerCleanResult,
        engine: DockerEngine,
        diskBefore: DockerDiskUsage?,
```

2. Sostituire il blocco che va da `if let before = diskBefore?.allocatedBytes, let after = diskAfter?.allocatedBytes {` fino alla riga `: ""` che chiude l'assegnazione di `daemonLostText` (compresi il commento sul Purge e l'assegnazione di `purgeHint`) con:

```swift
        // Solo Docker Desktop ha un disco misurato (`DiskUsageProbe.measure(for:)`).
        switch engine.kind {
        case .dockerDesktop:
            if let before = diskBefore?.allocatedBytes, let after = diskAfter?.allocatedBytes {
                diskText = String(localized: "Docker.raw sul disco: \(Formatting.bytes(before)) → \(Formatting.bytes(after))", bundle: .module)
            } else {
                diskText = String(localized: "Docker.raw sul disco: non misurabile.", bundle: .module)
            }
        case .orbStack:
            diskText = String(localized: "Disco virtuale: OrbStack restituisce lo spazio al Mac automaticamente.", bundle: .module)
        case .other:
            diskText = String(localized: "Disco virtuale: non misurato per questo motore.", bundle: .module)
        }

        // Docker Desktop restituisce lo spazio al Mac in modo differito: il disco virtuale può
        // restare grande anche dopo una pulizia riuscita. Purge è l'unico modo per forzarlo, e
        // cancella TUTTO: lo si suggerisce, mai lo si esegue. È un comando di Docker Desktop: gli
        // altri motori non lo hanno.
        if engine.kind == .dockerDesktop,
           report.itemsDeleted > 0,
           let rawBefore = diskBefore?.allocatedBytes,
           let rawAfter = diskAfter?.allocatedBytes,
           rawAfter >= rawBefore {
            purgeHint = String(
                localized: "Docker.raw non si è ridotto: Docker Desktop restituisce lo spazio al Mac con calma. Per recuperarlo subito: Docker Desktop → Troubleshoot → Clean / Purge data. Attenzione: quell'operazione cancella tutte le immagini, i container e i volumi.",
                bundle: .module)
        } else {
            purgeHint = ""
        }

        daemonLostText = result.daemonLost
            ? String(localized: "\(engine.displayName) si è fermato durante la pulizia: le voci restanti non sono state eliminate.", bundle: .module)
            : ""
```

In `MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift`, sostituire

```swift
    public func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
        let report = DockerReportModel(
            environment: environment, navigation: self, result: result, diskBefore: diskBefore, diskAfter: diskAfter)
```

con

```swift
    public func showDockerReport(_ result: DockerCleanResult, engine: DockerEngine, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
        let report = DockerReportModel(
            environment: environment, navigation: self, result: result, engine: engine, diskBefore: diskBefore, diskAfter: diskAfter)
```

In `MjmCleaner/Demo/DemoLaunch.swift`, sostituire

```swift
            main.showDockerReport(DemoData.dockerResult, diskBefore: DemoData.diskBefore, diskAfter: DemoData.diskAfter)
```

con

```swift
            main.showDockerReport(
                DemoData.dockerResult, engine: DemoData.dockerAnalysis.engine,
                diskBefore: DemoData.diskBefore, diskAfter: DemoData.diskAfter)
```

- [ ] **Step 4: Verificare che i test passino e che l'app compili**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 551 tests in 50 suites passed` e `Test run with 177 tests in 21 suites passed`, nessun warning.

Run: comando «app» delle Global Constraints.
Expected: `** BUILD SUCCEEDED **`, nessuna riga `warning:` o `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerReportModel.swift MjmCleanerKit/Sources/CleanerFeatures/Shell/MainModel.swift MjmCleaner/Demo/DemoLaunch.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerReportModelTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/MainModelTests.swift
git commit -F - <<'EOF'
feat(docker): describe the disk and the purge hint per engine in the report

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: README, verifica completa e prova in sola lettura

**Files:**
- Modify: `README.md` (sezione «Docker» e punto sulla sicurezza dei file Docker)
- Scratch, non committato: un file di test temporaneo in una copia del package

**Interfaces:**
- Consumes: tutto quanto prodotto dai Task 1–5

- [ ] **Step 1: README**

In `README.md`, sostituire il primo paragrafo della sezione `### Docker`

```markdown
The **Docker** page cleans images, volumes, and build cache through the `docker`
CLI only — no file under Docker Desktop's folder is ever deleted. It never starts
Docker Desktop: if the daemon is not running it says so and offers **Retry**.
```

con

```markdown
The **Docker** page cleans images, volumes, and build cache through the `docker`
CLI only, on the engine of the active Docker context: Docker Desktop, OrbStack,
or any other Docker-compatible engine (Colima, Rancher Desktop, …). The page
names the engine that answered `docker info`. No file under an engine's own
folders is ever deleted, and no engine is ever started: if the daemon is not
running, the page names the engine of the active context (read with
`docker context inspect`) and offers **Retry**. The `docker` binary is looked up
in `~/.docker/bin`, `~/.orbstack/bin`, `/usr/local/bin`, `/opt/homebrew/bin`, and
inside `Docker.app` and `OrbStack.app`; a dangling link left by an uninstalled
engine is skipped.
```

e l'ultimo paragrafo della stessa sezione

```markdown
Images are removed by full ID (`docker rmi sha256:…`), never by tag and never
with `-f`; `docker system prune` is never used. The report shows what was
deleted, what failed and why, and the space recovered according to
`docker system df` and to the real allocated size of `Docker.raw` (a sparse
file: its apparent size is only the disk limit). If `Docker.raw` does not shrink,
the report suggests **Docker Desktop → Troubleshoot → Clean / Purge data**, which
deletes all Docker data and is never run automatically.
```

con

```markdown
Images are removed by full ID (`docker rmi sha256:…`), never by tag and never
with `-f`; `docker system prune` is never used. The report shows what was
deleted, what failed and why, and the space recovered according to
`docker system df`. With Docker Desktop it also shows the real allocated size of
`Docker.raw` (a sparse file: its apparent size is only the disk limit); if
`Docker.raw` does not shrink, the report suggests **Docker Desktop →
Troubleshoot → Clean / Purge data**, which deletes all Docker data and is never
run automatically. OrbStack shrinks its disk image on its own, and macOS
protects the folder that holds it, so the app does not measure it; the disk
image of any other engine is not measured either.
```

Poi sostituire

```markdown
- **Docker files are never deleted:** `~/Library/Containers/com.docker.docker`
  and `~/.docker` stay on the deny list. Docker space is reclaimed only from the
  **Docker** page, through the `docker` CLI.
```

con

```markdown
- **Docker engine files are never deleted:**
  `~/Library/Containers/com.docker.docker`, `~/.docker`, and `~/.orbstack` stay on
  the deny list (OrbStack's group container is covered by
  `~/Library/Group Containers`). Docker space is reclaimed only from the
  **Docker** page, through the `docker` CLI.
```

- [ ] **Step 2: Verifica completa**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 551 tests in 50 suites passed` e `Test run with 177 tests in 21 suites passed`, nessun warning.

Run: comando «app» delle Global Constraints.
Expected: `** BUILD SUCCEEDED **`, nessuna riga `warning:` o `error:`.

Run: `git status --short`
Expected: oltre a `README.md`, solo le modifiche preesistenti (i tre `Localizable.xcstrings`, `.zed/`, `mjm-cleaner-ui-handoff.md`).

- [ ] **Step 3: Prova in sola lettura sul motore vero (copia scratch, non committata)**

Prerequisiti: OrbStack in esecuzione, Docker Desktop installato e spento, contesti `orbstack` e `desktop-linux` presenti (`docker context ls`). Se mancano, saltare lo step e riportarlo. Nessun comando cambia il contesto attivo.

Da una cartella scratch esclusiva (non nel repository), indicata qui come `$SCRATCH`:

```bash
rm -rf "$SCRATCH/live" && mkdir -p "$SCRATCH/live" && git archive HEAD | tar -x -C "$SCRATCH/live"
```

Creare `$SCRATCH/live/MjmCleanerKit/Tests/CleanerCoreTests/LiveDockerSmokeTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

/// Prova dal vivo in sola lettura: solo `docker info` e `docker context inspect`. Non committare.
struct LiveDockerSmokeTests {
    /// Antepone `--context <nome>` a ogni comando: legge un contesto senza cambiare quello attivo.
    private struct ContextCli: DockerCommandRunning {
        let inner: DockerCli
        let context: String

        func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
            try await inner.run(["--context", context] + arguments, timeout: timeout)
        }
    }

    @Test func recognizesOrbStackAndNamesAStoppedDockerDesktop() async throws {
        let home = NSHomeDirectory()
        let binary = DockerBinaryLocator.find(homeDirectory: home)
        let cli = DockerCli(runner: ProcessRunner(), binaryPath: binary)
        print("LIVE binary:", binary ?? "nil")
        print("LIVE active context:", await DockerContextReader(cli: cli, homeDirectory: home).activeContext() as Any)

        let orbStack = ContextCli(inner: cli, context: "orbstack")
        let engine = try await DockerInventoryCollector(cli: orbStack, fileSystem: LocalFileSystem()).checkDaemon()
        print("LIVE orbstack engine:", engine)
        #expect(engine.kind == .orbStack)

        let desktop = ContextCli(inner: cli, context: "desktop-linux")
        let stopped = await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: desktop, fileSystem: LocalFileSystem()).checkDaemon()
        }
        #expect(stopped?.reason == .notRunning)
        let message = await DockerContextReader(cli: desktop, homeDirectory: home).notRunningMessage()
        print("LIVE desktop-linux message:", message)
        #expect(message == "Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova.")
    }
}
```

Run: `(cd "$SCRATCH/live/MjmCleanerKit" && swift test --filter LiveDockerSmokeTests 2>&1 | grep -E 'LIVE|✘|Test run with')`
Expected: le righe `LIVE` (il binario trovato, il contesto attivo, `DockerEngine(kind: .orbStack, displayName: "OrbStack", …)`, il messaggio per `desktop-linux`) e `Test run with 1 test in 1 suite passed`. Riportare l'output nel report del task, poi cancellare `$SCRATCH/live`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -F - <<'EOF'
docs(docker): describe the engine-aware Docker page

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

## Mutazioni provate in stesura

Ognuna applicata da sola alla copia scratch con i Task 1–5 completi; esito con il comando «package».

| # | Mutazione | Ucciso da |
|---|---|---|
| M1 | `DenyList`: togliere la voce `"\(home)/.orbstack"` | `DenyListTests.deniesTheOrbStackFolder` |
| M2 | `DiskUsageProbe.measure(for:)`: misurare per ogni motore (togliere la `guard`) | `DiskUsageProbeTests.onlyDockerDesktopHasADiskToMeasure`, `DockerCleanupServiceTests.orbStackHasNoDiskToMeasureEvenWithADockerRawLeftBehind` |
| M3 | `DockerReportModel`: togliere `engine.kind == .dockerDesktop,` dalla condizione del Purge | `DockerReportModelTests.purgeIsSuggestedOnlyForDockerDesktop` |
| M4 | `DockerBinaryLocator.isExecutableFile`: `lstat` al posto di `stat` | `DockerCliTests.onlyAnExecutableFileReachedThroughItsLinksCounts` |
| M5 | `DockerBinaryLocator.isExecutableFile`: togliere il controllo `S_IFREG` | `DockerCliTests.onlyAnExecutableFileReachedThroughItsLinksCounts` |
| M6 | `DockerBinaryLocator.find`: predicato predefinito `{ LocalFileSystem().fileExists($0) }`, il controllo di oggi (`FileManager.fileExists` invece segue i collegamenti e non è una mutazione utile) | `DockerCliTests.locatorSkipsAnOrphanedDockerDesktopLink` |
| M7 | `DockerCli.run`: togliere `reason: .notInstalled` dal binario mancante | `DockerCliTests.missingBinaryBecomesAReadableException` |
| M8 | `DockerCleanupService.analyze`: riscrivere ogni `DockerUnavailableError` (togliere `where error.reason == .notRunning`) | `DockerCleanupServiceTests.aMissingDockerIsNeverRewritten` |
| M9 | `DockerEngine.kind(named:)`: «contiene» invece di «uguale» | `DockerEngineTests.recognizesTheEngineFromTheWholeOperatingSystemName` («OrbStack Linux») |
| M10 | `DockerContext.engineKind`: endpoint prima della descrizione (la descrizione resta solo come ultimo ripiego) | `DockerContextTests.recognizesTheEngineFromDescriptionThenEndpoint` |
| M11 | `DockerContext.engineKind`: `hasPrefix(socket, home + "/.orbstack/run")` senza confine di segmento | `DockerContextTests.recognizesTheEngineFromDescriptionThenEndpoint` («runtime») |

## Esito della riesecuzione in stesura

Ogni blocco del piano è stato applicato in ordine, per indice, alla copia scratch di `6fecad9` (script `replay_plan.py` nella cartella scratch della sessione, non committato). Per ogni task: passo RED con i soli test (sorgenti del task precedente) e passo GREEN con il comando «package».

| Task | RED (prima diagnostica utile) | GREEN `CleanerCoreTests` | GREEN `CleanerFeaturesTests` | App |
|---|---|---|---|---|
| 1 | `cannot find 'DockerEngine' in scope` | 539 test, 49 suite | 173, 21 | — |
| 2 | `cannot find 'DockerContext' in scope` | 546, 50 | 173, 21 | — |
| 3 | `type 'DockerBinaryLocator' has no member 'candidates'` | 549, 50 | 173, 21 | — |
| 4 | `value of type 'DockerAnalysis' has no member 'engine'` | 551, 50 | 175, 21 | `BUILD SUCCEEDED` |
| 5 | `type 'DockerNavigationSpy' does not conform to protocol 'DockerNavigating'` | 551, 50 | 177, 21 | `BUILD SUCCEEDED` |

Nessun warning con `-warnings-as-errors`. I `sed` del Task 5 danno 10 e 5 sostituzioni.

Prova del Task 6 sul Mac dell'utente (OrbStack acceso, Docker Desktop spento), contesto attivo `orbstack` prima e dopo:

```text
LIVE binary: /Users/mjm/.docker/bin/docker
LIVE active context: Optional(CleanerCore.DockerContext(name: "orbstack", description: "OrbStack", host: "unix:///Users/mjm/.orbstack/run/docker.sock"))
LIVE orbstack engine: DockerEngine(kind: CleanerCore.DockerEngineKind.orbStack, displayName: "OrbStack", operatingSystem: "OrbStack", serverVersion: "29.8.2")
LIVE desktop-linux message: Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova.
✔ Test run with 1 test in 1 suite passed
```

Il binario trovato è ancora quello di Docker Desktop (`~/.docker/bin/docker`, collegamento valido perché `Docker.app` è installato): parla con OrbStack attraverso il contesto, come previsto dalla spec.

