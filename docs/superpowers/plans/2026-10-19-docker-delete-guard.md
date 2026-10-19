# Eliminazione Docker solo sul motore analizzato — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** «Elimina» nella pagina Docker agisce solo sul motore che è stato analizzato, anche se nel frattempo il contesto attivo della CLI `docker` cambia o un altro daemon prende il posto di quello analizzato.

**Architecture:** L'analisi legge il contesto attivo una volta, all'inizio, e passa ogni comando con `docker --context <nome>` attraverso un decoratore interno, `DockerContextCli`. `DockerAnalysis` porta un bersaglio, `DockerTarget`: il contesto letto e il motore che vi ha risposto, con il nuovo `ID` del daemon. `DockerCleanExecutor.execute(_:on:progress:)` resta su quel contesto. Prima di qualunque misura o cancellazione rifiuta un daemon diverso, con il nuovo `DockerEngineChangedError`. La pagina mostra il rifiuto sotto «Elimina».

**Tech Stack:** Swift 6 language mode, macOS 15, Swift Testing, Xcode 27. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-19-docker-delete-guard-design.md`

Stato di partenza: `main` con questo piano (nessun push). Il codice è quello di `a20f74e` (merge di `feat/docker-engines`); `d7c3150` aggiunge solo la spec. `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **553** test in 50 suite (`CleanerCoreTests`) e **178** in 21 (`CleanerFeaturesTests`). Prima del Task 1 il controller crea il worktree `.claude/worktrees/docker-delete-guard` sul branch `feat/docker-delete-guard`, partendo da `main`.

Decisioni dell'utente (2026-10-19, nella spec):

- **Contesto fisso più identità del daemon.** Ogni comando di analisi ed esecuzione porta `--context <nome>`, con il contesto letto all'inizio dell'analisi. All'avvio dell'esecuzione il daemon di quel contesto deve essere lo stesso dell'analisi (ID, sistema, versione), altrimenti non si elimina nulla.
- **Rifiuto mostrato sotto «Elimina».** Elenco e selezione restano; un nuovo clic viene rifiutato di nuovo.
- **Contesto illeggibile: l'analisi fallisce.** «Docker non installato» resta com'è.

Decisioni prese durante la stesura, verificate rieseguendo il piano in una copia scratch di `d7c3150`:

- **`DockerContextReader.activeContext()` ora lancia, e `notRunningMessage()` senza argomenti sparisce.** La spec li teneva. Dopo il Task 3, però, nessuno li chiama più, perché analisi ed esecuzione nominano il contesto già letto con `notRunningMessage(for:)`. Il lettore non ingoia più errori: la decisione del registro di docker-engines («`activeContext()` ingoia ogni errore») è superata, perché ora un contesto illeggibile ferma l'analisi.
- **`DockerTarget` sta in `DockerCleanupService.swift`, accanto a `DockerAnalysis`**, che lo produce con la proprietà calcolata `target`.
- **`readEngine` è interna, non pubblica:** la usano solo `checkDaemon()` e l'esecutore, nello stesso modulo. Il collettore fissato, `pinned(to:)`, è interno anch'esso.
- **`shielded` e `tryReadDf` dell'esecutore diventano statiche e ricevono la CLI.** Dentro `execute` la CLI fissata è una costante locale, `cli`, che copre la proprietà: nessun comando può prendere per sbaglio quella non fissata.
- **Doppio `FakeDockerContexts` per i test del Core.** Instrada i comandi come la CLI vera. Nei test dell'esecutore il contesto attivo è `orbstack`, un motore che non risponde a nulla: un comando senza `--context desktop-linux` non raggiunge mai il motore del test, e anche i test esistenti uccidono la mutazione «CLI non fissata».
- **Il test di Features sull'elenco intatto passa già prima del Task 5:** protegge la scelta dell'utente («errore sotto Elimina»). Il passo rosso del Task 5 è l'argomento nuovo di `deleteFailuresAreShownOnThePage`.
- **Stringhe.** Le due frasi nuove sono in italiano con `String(localized:bundle: .module)`, come le esistenti. I `Localizable.xcstrings` non si toccano. Entreranno nella tabella del piano di localizzazione, che si scrive dopo il merge.

## Global Constraints

- Il codice vive in `MjmCleanerKit/` (package) e `MjmCleaner/` (app). Cambiano:
  - nel Core, solo `Docker/DockerCleanExecutor.swift`, `Docker/DockerCleanupService.swift`, `Docker/DockerContext.swift`, `Docker/DockerEngine.swift`, `Docker/DockerInventoryCollector.swift` e `Docker/DockerJson.swift`;
  - in `CleanerFeatures`, solo `Docker/DockerModel.swift` e `Environment/DockerCleanupServing.swift`;
  - nell'app, solo `Demo/DemoData.swift` e `Demo/DemoServices.swift`;
  - più `README.md`. Le viste SwiftUI non cambiano.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- Vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati.
- L'app non avvia né arresta alcun motore e non cancella file dei motori: Docker passa solo dalla CLI.
- Il contesto attivo non si cambia mai, nemmeno nelle prove: niente `docker context use`, mai. Per leggere un altro contesto si usa `docker --context <nome> …`.
- Testi nuovi: solo i due della spec, scritti esattamente come nel piano. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica, dalla radice del worktree:
  - package: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -E '✘|Test run with|(^|: )(warning|error): ')`;
  - compilazione (passo RED): `(cd MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | perl -pe 's/\e\[[0-9;]*m//g' | grep -oE 'error: .{0,100}' | grep -vE 'Build failed|SwiftCompile' | sort -u | head -8)`. L'output del compilatore è colorato anche in una pipe: senza `perl` le diagnostiche non si leggono;
  - app: `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -derivedDataPath "$TMPDIR/mjm-docker-delete-guard-dd" build 2>&1 | grep -E '(^|: )(warning|error): |BUILD (SUCCEEDED|FAILED)'`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/docker-delete-guard`, nessun push. In stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage `.zed/`, `mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` (`MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`).
- Mai input sintetico (CGEvent, osascript, AXPress, cliclick) e mai avviare l'app: le verifiche sono test, build e la prova in sola lettura del Task 6.

## Note per l'esecuzione (subagent-driven)

- Implementatori: haiku, perché ogni task contiene il codice completo; al massimo sonnet nei fix round. Report in `.txt`.
- Revisori: sonnet; **opus per i Task 3 e 4** (analisi ed esecuzione fissate: sono i componenti che decidono dove si cancella) e per la revisione finale. I Task 2, 3 e 4 si rivedono con mutazioni in una copia scratch.
- Mutazioni provate in stesura, tutte uccise dai test del piano, da ripetere nelle revisioni: vedi la tabella in fondo.

---

## Fatti misurati (2026-10-19, macOS 27.0, CLI 29.8.2, OrbStack in esecuzione, Docker Desktop installato e spento)

- `docker context ls`: `default` → `unix:///var/run/docker.sock`, `desktop-linux` (descrizione «Docker Desktop») → `unix:///Users/<utente>/.docker/run/docker.sock`, `orbstack *` (descrizione «OrbStack») → `unix:///Users/<utente>/.orbstack/run/docker.sock`.
- `/var/run/docker.sock` è un collegamento a `~/.orbstack/run/docker.sock` di proprietà di root, riscritto il 2026-10-18 alle 17:16: lo riscrive il motore avviato per ultimo.
- `docker info --format '{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}},"ID":{{json .ID}}}'` stampa `{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack","ID":"b2756783-e527-49e3-a6c6-cd7f4e49c9ff"}` ed esce con 0. Con `--context orbstack` e con `--context default` l'`ID` è lo stesso.
- `docker --context desktop-linux info --format …` stampa `{"ServerVersion":"","OperatingSystem":"","ID":""}` ed esce con 1, con lo stderr «failed to connect to the docker API at unix:///…/.docker/run/docker.sock; …», già riconosciuto da `DockerCliErrors.isDaemonUnavailable`.
- `docker --context <inesistente> info` esce con 1: «Failed to initialize: unable to resolve docker endpoint: context "<nome>": context not found: …».
- `docker --context orbstack context inspect --format '{{json .Name}}'` stampa `"orbstack"`: con `--context`, anche `context inspect` guarda quel contesto. `--context` va prima del sottocomando e non cambia il contesto attivo (`docker context show` resta `orbstack`).
- `ProcessRunner` unisce l'ambiente dell'app a quello passato da `DockerCli`, che aggiunge solo `PATH`: `DOCKER_HOST` e `DOCKER_CONTEXT`, se l'app li eredita, arrivano alla CLI. `--context` vince su entrambi.

---

### Task 1: L'identità del daemon in `DockerEngine`

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift` (`parseEngineInfo`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift` (`engineFormat`, `checkDaemon`, nuova `readEngine`)
- Test: modify `FakeDockerCli.swift`, `DockerInventoryCollectorTests.swift`, `DockerEngineTests.swift` (in `MjmCleanerKit/Tests/CleanerCoreTests/Docker/`)

**Interfaces:**
- Consumes: `DockerEngine(serverVersion:operatingSystem:)`, `DockerJson.parseEngineInfo`, `DockerInventoryCollector.engineFormat` di oggi.
- Produces:
  - `DockerEngine.id: String`;
  - `DockerEngine.init(serverVersion: String, operatingSystem: String, id: String = "")`, con l'uguaglianza sintetizzata che include `id`;
  - `DockerJson.parseEngineInfo(_:) -> (serverVersion: String, operatingSystem: String, id: String)`;
  - `static func DockerInventoryCollector.readEngine(_ cli: any DockerCommandRunning) async throws -> DockerEngine` (interna);
  - nei test, `FakeDockerCli.info(_ version: String, _ operatingSystem: String = "Docker Desktop", id: String? = nil) -> String`.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerCli.swift`, sostituire:

```swift
    /// La risposta di `docker info` di un daemon `version` che si presenta come `operatingSystem`.
    static func info(_ version: String, _ operatingSystem: String = "Docker Desktop") -> String {
        #"{"ServerVersion":"\#(version)","OperatingSystem":"\#(operatingSystem)"}"# + "\n"
    }
```

con:

```swift
    /// La risposta di `docker info` di un daemon `version` che si presenta come `operatingSystem`;
    /// con `id`, anche l'`ID` del daemon.
    static func info(_ version: String, _ operatingSystem: String = "Docker Desktop", id: String? = nil) -> String {
        let idField = id.map { #","ID":"\#($0)""# } ?? ""
        return #"{"ServerVersion":"\#(version)","OperatingSystem":"\#(operatingSystem)"\#(idField)}"# + "\n"
    }
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerInventoryCollectorTests.swift`, sostituire:

```swift
    @Test func unreadableInfoIsAnOutputError() async {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, "29.8.2")

        await #expect(throws: DockerOutputError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()
        }
    }
}
```

con:

```swift
    @Test func unreadableInfoIsAnOutputError() async {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, "29.8.2")

        await #expect(throws: DockerOutputError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()
        }
    }

    /// Solo Swift: l'`ID` del daemon arriva con la stessa chiamata `docker info`, nel formato misurato
    /// con OrbStack il 2026-10-19; l'esecutore lo usa per riconoscere un daemon diverso.
    @Test func theDaemonIdComesWithTheSameInfoCall() async throws {
        let cli = FakeDockerCli().on(
            FakeDockerCli.infoCommand,
            #"{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack","ID":"b2756783-e527-49e3-a6c6-cd7f4e49c9ff"}"#)

        let engine = try await DockerInventoryCollector.readEngine(cli)

        #expect(engine == DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack", id: "b2756783-e527-49e3-a6c6-cd7f4e49c9ff"))
        #expect(DockerInventoryCollector.engineFormat
            == #"{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}},"ID":{{json .ID}}}"#)
        #expect(cli.calls == [["info", "--format", DockerInventoryCollector.engineFormat]])
    }

    @Test(arguments: [
        #"{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack"}"#,
        #"{"ServerVersion":"29.8.2","OperatingSystem":"OrbStack","ID":null}"#,
    ])
    func aDaemonWithoutAnIdHasAnEmptyOne(output: String) async throws {
        let cli = FakeDockerCli().on(FakeDockerCli.infoCommand, output)

        let engine = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).checkDaemon()

        #expect(engine.id == "")
        #expect(engine.kind == .orbStack)
    }
}
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerEngineTests.swift`, sostituire:

```swift
        #expect(engine.serverVersion == "29.8.2")
    }
}
```

con:

```swift
        #expect(engine.serverVersion == "29.8.2")
    }

    /// Due daemon con lo stesso sistema e la stessa versione restano diversi se l'ID è diverso:
    /// l'esecutore confronta il motore intero.
    @Test func theIdTellsTwoDaemonsOfTheSameKindApart() {
        let colima = DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04", id: "a1")

        #expect(colima.id == "a1")
        #expect(colima == DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04", id: "a1"))
        #expect(colima != DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04", id: "b2"))
        #expect(DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack").id == "")
    }
}
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `extra argument 'id' in call` e `type 'DockerInventoryCollector' has no member 'readEngine'`.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift`, sostituire:

```swift
    public let serverVersion: String

    public init(serverVersion: String, operatingSystem: String) {
        let kind = Self.kind(named: operatingSystem)
        self.kind = kind
        self.serverVersion = serverVersion
        self.operatingSystem = operatingSystem
```

con:

```swift
    public let serverVersion: String
    /// L'`ID` del daemon, persistente per `dockerd`: distingue due daemon dello stesso tipo dietro
    /// lo stesso contesto (`default` segue `/var/run/docker.sock`, che il motore avviato per ultimo
    /// riscrive). Vuoto se il daemon non lo riporta.
    public let id: String

    public init(serverVersion: String, operatingSystem: String, id: String = "") {
        let kind = Self.kind(named: operatingSystem)
        self.kind = kind
        self.serverVersion = serverVersion
        self.operatingSystem = operatingSystem
        self.id = id
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift`, sostituire:

```swift
    public static func parseEngineInfo(_ json: String) throws -> (serverVersion: String, operatingSystem: String) {
        let root = try parse(json, "docker info")
        return (string(root, "ServerVersion") ?? "", string(root, "OperatingSystem") ?? "")
    }
```

con:

```swift
    public static func parseEngineInfo(_ json: String) throws -> (serverVersion: String, operatingSystem: String, id: String) {
        let root = try parse(json, "docker info")
        return (string(root, "ServerVersion") ?? "", string(root, "OperatingSystem") ?? "", string(root, "ID") ?? "")
    }
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift`, sostituire:

```swift
    /// Versione del server e motore con una sola chiamata `docker info`.
    static let engineFormat = #"{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}}}"#
```

con:

```swift
    /// Versione del server, motore e identità del daemon con una sola chiamata `docker info`.
    static let engineFormat = #"{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}},"ID":{{json .ID}}}"#
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift`, sostituire:

```swift
    /// Verifica che il daemon risponda e riconosce il motore che lo esegue.
    public func checkDaemon() async throws -> DockerEngine {
        let info = try DockerJson.parseEngineInfo(try await cli.runChecked(["info", "--format", Self.engineFormat]))
        let version = DockerText.trimmed(info.serverVersion)
```

con:

```swift
    /// Verifica che il daemon risponda e riconosce il motore che lo esegue.
    public func checkDaemon() async throws -> DockerEngine {
        try await Self.readEngine(cli)
    }

    /// Il motore che risponde dietro `cli`: condiviso con l'esecutore, che prima di cancellare
    /// controlla che il daemon sia ancora quello dell'analisi.
    static func readEngine(_ cli: any DockerCommandRunning) async throws -> DockerEngine {
        let info = try DockerJson.parseEngineInfo(try await cli.runChecked(["info", "--format", engineFormat]))
        let version = DockerText.trimmed(info.serverVersion)
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift`, sostituire:

```swift
        return DockerEngine(serverVersion: version, operatingSystem: info.operatingSystem)
```

con:

```swift
        return DockerEngine(serverVersion: version, operatingSystem: info.operatingSystem, id: info.id)
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 556 tests in 50 suites passed` e `Test run with 178 tests in 21 suites passed`, nessun warning.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerCli.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerInventoryCollectorTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerEngineTests.swift
git commit -F - <<'EOF'
feat(docker): read the daemon ID with the engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: Comandi fissati a un contesto

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift` (nuovo `DockerContextCli` in fondo)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift` (nuova `pinned(to:)`)
- Test: create `MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerContexts.swift` e `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerContextCliTests.swift`

**Interfaces:**
- Consumes: `DockerCommandRunning`, `DockerOutputError`, `DockerInventoryCollector.engineFormat`, `FakeDockerCli.info(_:_:id:)` (Task 1).
- Produces:
  - `struct DockerContextCli: DockerCommandRunning`, interna, con `init(_ base: any DockerCommandRunning, context name: String) throws`. Lancia `DockerOutputError("Nome del contesto Docker non valido: «‹nome›».")` e antepone `["--context", name]` a ogni comando;
  - `func DockerInventoryCollector.pinned(to name: String) throws -> DockerInventoryCollector` (interna);
  - nei test, `final class FakeDockerContexts: DockerCommandRunning` con:
    - `init(active: String, _ contexts: [(context: DockerContext, cli: FakeDockerCli)])`;
    - `calls: [[String]]` (prefisso compreso);
    - `activate(_ name: String)`;
    - `static let desktopLinux: DockerContext` e `static let orbstack: DockerContext`;
    - `static func json(_ context: DockerContext) -> String`.

- [ ] **Step 1: Test che falliscono**

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerContexts.swift`:

```swift
import Synchronization
@testable import CleanerCore

/// I contesti della CLI `docker`, ciascuno con il suo motore finto. Come la CLI vera, un comando
/// che comincia con `--context <nome>` va al motore di quel contesto, senza il prefisso; ogni altro
/// va al motore del contesto attivo; `context inspect` risponde con il contesto a cui è rivolto. Il
/// test può cambiare il contesto attivo in qualunque momento, come fa OrbStack quando si avvia.
final class FakeDockerContexts: DockerCommandRunning {
    static let desktopLinux = DockerContext(
        name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/tester/.docker/run/docker.sock")
    static let orbstack = DockerContext(
        name: "orbstack", description: "OrbStack", host: "unix:///Users/tester/.orbstack/run/docker.sock")

    private struct State {
        var active: String
        var calls: [[String]] = []
    }

    private let engines: [String: (context: DockerContext, cli: FakeDockerCli)]
    private let state: Mutex<State>

    init(active: String, _ contexts: [(context: DockerContext, cli: FakeDockerCli)]) {
        var engines: [String: (context: DockerContext, cli: FakeDockerCli)] = [:]
        for entry in contexts {
            engines[entry.context.name] = entry
        }
        self.engines = engines
        state = Mutex(State(active: active))
    }

    /// Ogni comando così come è arrivato, prefisso compreso.
    var calls: [[String]] { state.withLock { $0.calls } }

    func activate(_ name: String) {
        state.withLock { $0.active = name }
    }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        var name = state.withLock { state in
            state.calls.append(arguments)
            return state.active
        }

        var command = arguments
        if command.first == "--context", let pinned = command.dropFirst().first {
            name = pinned
            command = Array(command.dropFirst(2))
        }

        guard let engine = engines[name] else {
            return FakeDockerCli.fail(#"Failed to initialize: unable to resolve docker endpoint: context "\#(name)": context not found"#)
        }
        if command == ["context", "inspect", "--format", "{{json .}}"] {
            return FakeDockerCli.ok(Self.json(engine.context))
        }
        return try await engine.cli.run(command, timeout: timeout)
    }

    /// La riga di `docker context inspect --format '{{json .}}'`, con i soli campi che il Core legge.
    static func json(_ context: DockerContext) -> String {
        #"{"Name":"\#(context.name)","Metadata":{"Description":"\#(context.description)"},"Endpoints":{"docker":{"Host":"\#(context.host)"}}}"# + "\n"
    }
}
```

Creare `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerContextCliTests.swift`:

```swift
import Testing
@testable import CleanerCore

/// Solo Swift: ogni comando fissato al contesto letto all'analisi.
struct DockerContextCliTests {
    @Test func everyCommandGoesToTheNamedContext() async throws {
        let base = FakeDockerCli().on("--context desktop-linux volume rm old-data", "old-data")

        let result = try await DockerContextCli(base, context: "desktop-linux").run(["volume", "rm", "old-data"], timeout: .seconds(600))

        #expect(result.exitCode == 0)
        #expect(base.calls == [["--context", "desktop-linux", "volume", "rm", "old-data"]])
    }

    /// `runChecked` nomina il comando che l'analisi ha chiesto, non il prefisso.
    @Test func errorsNameTheCommandNotThePrefix() async throws {
        let base = FakeDockerCli().on("--context orbstack volume inspect x") { FakeDockerCli.fail("Error response from daemon: get x: no such volume") }

        let error = await #expect(throws: DockerCommandError.self) {
            try await DockerContextCli(base, context: "orbstack").runChecked(["volume", "inspect", "x"])
        }

        #expect(error == DockerCommandError("docker volume inspect: get x: no such volume"))
    }

    @Test(arguments: ["default", "desktop-linux", "orbstack", "colima", "rancher-desktop", "lab_2.local+x", "x"])
    func namesDockerAcceptsArePassedAsTheyAre(name: String) async throws {
        let base = FakeDockerCli()

        _ = try await DockerContextCli(base, context: name).run(["info"], timeout: nil)

        #expect(base.calls == [["--context", name, "info"]])
    }

    @Test(arguments: ["", "-H", "--host=tcp://10.0.0.1:2375", "a b", "orbstack\n", "ctx;rm", "_ctx", "dèsktop"])
    func namesDockerRejectsAreRefusedBeforeAnyCommand(name: String) {
        let base = FakeDockerCli()

        #expect(throws: DockerOutputError("Nome del contesto Docker non valido: «\(name)».")) {
            try DockerContextCli(base, context: name)
        }
        #expect(base.calls.isEmpty)
    }

    @Test func aPinnedCollectorReadsItsContextWhateverTheActiveOne() async throws {
        let desktop = FakeDockerCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0", id: "desktop-id"))
        let orbStack = FakeDockerCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack", id: "orbstack-id"))
        let docker = FakeDockerContexts(active: "orbstack", [
            (FakeDockerContexts.desktopLinux, desktop),
            (FakeDockerContexts.orbstack, orbStack),
        ])

        let engine = try await DockerInventoryCollector(cli: docker, fileSystem: InMemoryFileSystem()).pinned(to: "desktop-linux").checkDaemon()

        #expect(engine == DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop", id: "desktop-id"))
        #expect(docker.calls == [["--context", "desktop-linux", "info", "--format", DockerInventoryCollector.engineFormat]])
        #expect(orbStack.calls.isEmpty)
    }
}
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `cannot find 'DockerContextCli' in scope` e `value of type 'DockerInventoryCollector' has no member 'pinned'`.

- [ ] **Step 3: Implementazione**

In fondo a `MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift`, aggiungere:

```swift
/// Ogni comando va al daemon del contesto `name`, qualunque sia il contesto attivo. `--context`
/// vale per il singolo comando e non cambia il contesto dell'utente: analisi ed esecuzione restano
/// così sul motore analizzato anche se nel frattempo il contesto attivo cambia (OrbStack lo
/// reimposta quando si avvia).
struct DockerContextCli: DockerCommandRunning {
    private let base: any DockerCommandRunning
    private let name: String

    /// Lancia per un nome che Docker non accetta: vuoto, oppure che comincia con «-» e verrebbe
    /// letto come un'opzione.
    init(_ base: any DockerCommandRunning, context name: String) throws {
        guard name.firstMatch(of: /^[A-Za-z0-9][A-Za-z0-9_.+\-]*$/.matchingSemantics(.unicodeScalar)) != nil else {
            throw DockerOutputError(String(localized: "Nome del contesto Docker non valido: «\(name)».", bundle: .module))
        }
        self.base = base
        self.name = name
    }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        try await base.run(["--context", name] + arguments, timeout: timeout)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift`, sostituire:

```swift
    /// Verifica che il daemon risponda e riconosce il motore che lo esegue.
    public func checkDaemon() async throws -> DockerEngine {
```

con:

```swift
    /// Lo stesso collettore con ogni comando fissato al contesto `name` (`DockerContextCli`).
    func pinned(to name: String) throws -> DockerInventoryCollector {
        DockerInventoryCollector(cli: try DockerContextCli(cli, context: name), fileSystem: fileSystem)
    }

    /// Verifica che il daemon risponda e riconosce il motore che lo esegue.
    public func checkDaemon() async throws -> DockerEngine {
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 561 tests in 51 suites passed` e `Test run with 178 tests in 21 suites passed`, nessun warning.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerContexts.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerContextCliTests.swift
git commit -F - <<'EOF'
feat(docker): pin Docker commands to a context

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: L'analisi resta sul contesto letto all'inizio

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift` (`DockerContextReader`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` (`DockerTarget`, `DockerAnalysis`, `analyze`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift` (commento)
- Modify: `MjmCleaner/Demo/DemoData.swift` (contesto della demo)
- Test: replace `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift`; modify `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`

**Interfaces:**
- Consumes: `DockerInventoryCollector.pinned(to:)`, `FakeDockerContexts` (Task 2); `FakeDockerCli.info(_:_:id:)`, `DockerEngine.id` (Task 1).
- Produces:
  - `public struct DockerTarget: Sendable, Equatable`, con `context: DockerContext`, `engine: DockerEngine` e `init(context:engine:)`;
  - `DockerAnalysis.init(engine:context:snapshot:candidates:disk:)`, `DockerAnalysis.context` e `DockerAnalysis.target: DockerTarget`;
  - `DockerContextReader.activeContext() async throws -> DockerContext` e `DockerContextReader.notRunningMessage(for: DockerContext) -> String`. `notRunningMessage()` senza argomenti non esiste più;
  - nei test di Features, `let desktopLinux: DockerContext` e `dockerAnalysis(_:engine:context:disk:df:)`.

- [ ] **Step 1: Test che falliscono**

Sostituire l'intero contenuto di `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift` con:

```swift
import Testing
@testable import CleanerCore

struct DockerCleanupServiceTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    private static let contextCommand = "context inspect --format {{json .}}"
    private static let desktopEngine = DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop", id: "5f0d6c1e-desktop")
    private static let orbStackEngine = DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack", id: "b2756783-orbstack")

    private struct NoProcess: ProcessRunning {
        let calls = Recorder<[String]>()

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append([executable] + arguments)
            return ProcessResult(exitCode: 0, standardOutput: "16\t" + DockerCleanupServiceTests.rawPath, standardError: "", timedOut: false)
        }
    }

    /// Un servizio su `cli`, il motore del contesto attivo `desktop-linux`.
    private func service(
        _ fs: InMemoryFileSystem,
        _ cli: FakeDockerCli,
        du: NoProcess = NoProcess(),
        diskFiles: (any FileSystem)? = nil
    ) -> DockerCleanupService {
        service(fs, docker: FakeDockerContexts(active: "desktop-linux", [(FakeDockerContexts.desktopLinux, cli)]), du: du, diskFiles: diskFiles)
    }

    private func service(
        _ fs: InMemoryFileSystem,
        docker: any DockerCommandRunning,
        du: NoProcess = NoProcess(),
        diskFiles: (any FileSystem)? = nil
    ) -> DockerCleanupService {
        DockerCleanupService(
            collector: DockerInventoryCollector(cli: docker, fileSystem: fs),
            scanner: ProjectReferenceScanner(fileSystem: fs),
            disk: DiskUsageProbe(runner: du, fileSystem: diskFiles ?? fs, diskImagePath: Self.rawPath),
            executor: DockerCleanExecutor(cli: docker, clock: SystemWallClock()),
            contexts: DockerContextReader(cli: docker, homeDirectory: "/Users/tester"))
    }

    /// Docker Desktop (`desktop-linux`, attivo) con il caso reale delle fixture e OrbStack
    /// (`orbstack`) con lo stesso caso: un comando arrivato al motore sbagliato troverebbe risposta.
    private func twoEngines() throws -> (docker: FakeDockerContexts, desktop: FakeDockerCli, orbStack: FakeDockerCli) {
        let desktop = try FakeDockerCli.withRealCase()
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0", id: Self.desktopEngine.id))
        let orbStack = try FakeDockerCli.withRealCase()
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack", id: Self.orbStackEngine.id))
        let docker = FakeDockerContexts(active: "desktop-linux", [
            (FakeDockerContexts.desktopLinux, desktop),
            (FakeDockerContexts.orbstack, orbStack),
        ])
        return (docker, desktop, orbStack)
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

        #expect(analysis.engine == DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop"))
        #expect(analysis.disk?.allocatedBytes == Int64(16 * 1024))
        #expect(analysis.disk?.apparentBytes == 100)
        #expect(analysis.snapshot.df.images == 5_840_000_000)
    }

    /// Sul Mac dell'utente Docker Desktop ha lasciato un Docker.raw: con OrbStack non si misura, e
    /// il disco non viene nemmeno guardato (né `fileExists`/`itemInfo`, né `du`).
    @Test func orbStackHasNoDiskToMeasureEvenWithADockerRawLeftBehind() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 100)
        let diskFiles = AccessLogFileSystem(fs)
        let du = NoProcess()
        let cli = try FakeDockerCli.withRealCase().on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.2", "OrbStack"))
        let docker = service(fs, cli, du: du, diskFiles: diskFiles)

        let analysis = try await docker.analyze([])
        let after = try await docker.measureDisk(for: analysis.engine)

        #expect(analysis.engine.kind == .orbStack)
        #expect(analysis.disk == nil)
        #expect(after == nil)
        #expect(diskFiles.paths.values.isEmpty)
        #expect(du.calls.values.isEmpty)
    }

    @Test func aDaemonThatDoesNotAnswerNamesTheEngineOfTheActiveContext() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
    }

    /// Senza un contesto non si può fissare l'analisi: si ferma prima di parlare con un daemon.
    @Test func anUnreadableContextStopsTheAnalysis() async {
        let cli = FakeDockerCli()
            .on(Self.contextCommand) { FakeDockerCli.fail(#"context "gone": context not found"#) }

        let error = await #expect(throws: DockerCommandError.self) {
            try await service(InMemoryFileSystem(), docker: cli).analyze([])
        }

        #expect(error == DockerCommandError(#"docker context inspect: context "gone": context not found"#))
        #expect(cli.commandLines == [Self.contextCommand])
    }

    @Test func aContextWithoutAValidNameStopsTheAnalysis() async {
        let cli = FakeDockerCli()
            .on(Self.contextCommand, #"{"Name":"","Metadata":{},"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock"}}}"#)

        let error = await #expect(throws: DockerOutputError.self) {
            try await service(InMemoryFileSystem(), docker: cli).analyze([])
        }

        #expect(error == DockerOutputError("Nome del contesto Docker non valido: «»."))
        #expect(cli.commandLines == [Self.contextCommand])
    }

    @Test func aMissingDockerStopsAtTheContextRead() async {
        let cli = FakeDockerCli()
            .on(Self.contextCommand) { throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), docker: cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled))
        #expect(cli.commandLines == [Self.contextCommand])
    }

    @Test func aMissingDockerIsNeverRewritten() async {
        let cli = FakeDockerCli()
            .on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled) }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), cli).analyze([])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notInstalled, reason: .notInstalled))
    }

    /// OrbStack, avviandosi, cambia il contesto attivo subito dopo che l'analisi lo ha letto: ogni
    /// comando successivo resta su `desktop-linux`, e il bersaglio è Docker Desktop.
    @Test func everyAnalysisCommandStaysOnTheContextReadAtTheStart() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        desktop.on(FakeDockerCli.infoCommand) {
            docker.activate("orbstack")
            return FakeDockerCli.ok(FakeDockerCli.info("29.8.0", id: Self.desktopEngine.id))
        }

        let analysis = try await service(InMemoryFileSystem(), docker: docker).analyze([])

        #expect(analysis.target == DockerTarget(context: FakeDockerContexts.desktopLinux, engine: Self.desktopEngine))
        #expect(!analysis.candidates.isEmpty)
        #expect(docker.calls.first == ["context", "inspect", "--format", "{{json .}}"])
        #expect(docker.calls.dropFirst().allSatisfy { $0.starts(with: ["--context", "desktop-linux"]) })
        #expect(docker.calls.count > 2)
        #expect(orbStack.calls.isEmpty)
    }

    /// Docker Desktop si ferma e OrbStack prende il contesto attivo: l'errore nomina il motore
    /// analizzato, non quello che risponde ora.
    @Test func aStoppedEngineIsNamedFromTheContextReadAtTheStart() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        desktop.on(FakeDockerCli.infoCommand) {
            docker.activate("orbstack")
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await service(InMemoryFileSystem(), docker: docker).analyze([])
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
        #expect(orbStack.calls.isEmpty)
    }
}
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift`, sostituire:

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
        snapshot:
```

con:

```swift
/// Il motore delle analisi di prova, se il test non ne sceglie un altro.
let dockerDesktop = DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop")

/// Il contesto delle analisi di prova, se il test non ne sceglie un altro.
let desktopLinux = DockerContext(name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/tester/.docker/run/docker.sock")

func dockerAnalysis(
    _ candidates: [DockerCandidate],
    engine: DockerEngine = dockerDesktop,
    context: DockerContext = desktopLinux,
    disk: DockerDiskUsage? = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824),
    df: DockerDfSummary = .empty
) -> DockerAnalysis {
    DockerAnalysis(
        engine: engine,
        context: context,
        snapshot:
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `cannot find 'DockerTarget' in scope` e `value of type 'DockerAnalysis' has no member 'target'`. Gli errori del modulo di test di Features (`extra argument 'context' in call`) possono mancare: la build si ferma al primo modulo che non compila.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift`, sostituire:

```swift
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

con:

```swift
/// Legge il contesto attivo, a cui l'analisi resta fissata, e nomina il motore di un contesto
/// già letto quando il suo daemon non risponde.
public struct DockerContextReader: Sendable {
    private let cli: any DockerCommandRunning
    private let homeDirectory: String

    public init(cli: any DockerCommandRunning, homeDirectory: String) {
        self.cli = cli
        self.homeDirectory = homeDirectory
    }

    /// Lancia: senza un contesto non si può fissare l'analisi. «Non installato» risale com'è.
    public func activeContext() async throws -> DockerContext {
        try DockerJson.parseContext(try await cli.runChecked(["context", "inspect", "--format", "{{json .}}"]))
    }

    /// Il testo per un daemon che non risponde, per il contesto su cui si lavora: non quello attivo
    /// in quel momento, che può essere già un altro.
    public func notRunningMessage(for context: DockerContext) -> String {
        DockerUnavailableError.notRunningMessage(context, homeDirectory: homeDirectory)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift`, sostituire:

```swift
/// virtuale). Quale motore si pulisce lo decide il contesto attivo della CLI: qui lo si riconosce
/// soltanto, per i testi e per il disco virtuale.
```

con:

```swift
/// virtuale). Quale motore si pulisce lo decide il contesto attivo all'inizio dell'analisi: qui lo
/// si riconosce, per i testi e per il disco virtuale, e se ne conserva l'identità.
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift`, sostituire:

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
```

con:

```swift
/// Il motore su cui si è fatta l'analisi: il contesto letto al suo inizio e il daemon che ha
/// risposto lì. L'esecuzione resta su quel contesto e rifiuta un daemon diverso.
public struct DockerTarget: Sendable, Equatable {
    public let context: DockerContext
    public let engine: DockerEngine

    public init(context: DockerContext, engine: DockerEngine) {
        self.context = context
        self.engine = engine
    }
}

/// `engine`: il motore che ha risposto. `context`: il contesto a cui l'analisi è rimasta fissata.
/// `disk`: il disco virtuale del motore, `nil` per un motore che non ne ha uno da misurare
/// (`DiskUsageProbe.measure(for:)`).
public struct DockerAnalysis: Sendable, Equatable {
    public let engine: DockerEngine
    public let context: DockerContext
    public let snapshot: DockerSnapshot
    public let candidates: [DockerCandidate]
    public let disk: DockerDiskUsage?

    public init(engine: DockerEngine, context: DockerContext, snapshot: DockerSnapshot, candidates: [DockerCandidate], disk: DockerDiskUsage?) {
        self.engine = engine
        self.context = context
        self.snapshot = snapshot
        self.candidates = candidates
        self.disk = disk
    }

    /// Il bersaglio da consegnare all'esecuzione.
    public var target: DockerTarget {
        DockerTarget(context: context, engine: engine)
    }
}
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift`, sostituire:

```swift
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
```

con:

```swift
    /// L'analisi resta sul contesto attivo al suo inizio: ogni comando porta `--context`, e un
    /// cambio di contesto a metà non mescola due motori. «Non installato» e un contesto illeggibile
    /// risalgono così come sono; un daemon che non risponde diventa un errore che nomina il motore
    /// di quel contesto: l'utente sa quale avviare.
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let context = try await contexts.activeContext()
        let pinned = try collector.pinned(to: context.name)

        do {
            return try await analyzeRunningDaemon(projectRoots, pinned, context)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(contexts.notRunningMessage(for: context))
        }
    }
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift`, sostituire:

```swift
    @concurrent
    private func analyzeRunningDaemon(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let engine = try await collector.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure(for: engine)
        let snapshot = try await collector.collect()

        return DockerAnalysis(
            engine: engine,
            snapshot: snapshot,
```

con:

```swift
    @concurrent
    private func analyzeRunningDaemon(
        _ projectRoots: [String],
        _ pinned: DockerInventoryCollector,
        _ context: DockerContext
    ) async throws -> DockerAnalysis {
        let engine = try await pinned.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure(for: engine)
        let snapshot = try await pinned.collect()

        return DockerAnalysis(
            engine: engine,
            context: context,
            snapshot: snapshot,
```

In `MjmCleaner/Demo/DemoData.swift`, sostituire:

```swift
    static let dockerAnalysis = DockerAnalysis(
        engine: DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop"),
```

con:

```swift
    static let dockerAnalysis = DockerAnalysis(
        engine: DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop"),
        context: DockerContext(name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/demo/.docker/run/docker.sock"),
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 565 tests in 51 suites passed` e `Test run with 178 tests in 21 suites passed`, nessun warning.

Run: comando «app» delle Global Constraints.
Expected: `** BUILD SUCCEEDED **`, nessuna riga `warning:` o `error:`.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerContext.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerEngine.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift MjmCleaner/Demo/DemoData.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/DockerNavigationSpy.swift
git commit -F - <<'EOF'
feat(docker): keep the analysis on the context read at its start

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: L'esecuzione resta sul motore analizzato

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift` (`DockerEngineChangedError`, `execute(_:on:progress:)`, `shielded`, `tryReadDf`)
- Modify: `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift` (`execute(_:on:progress:)`)
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift`
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift` (`target` al posto di `engine`)
- Modify: `MjmCleaner/Demo/DemoServices.swift` (`DemoDocker.execute`)
- Test: modify `DockerCleanExecutorTests.swift`, `DockerCleanupServiceTests.swift` (in `MjmCleanerKit/Tests/CleanerCoreTests/Docker/`), `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`

**Interfaces:**
- Consumes:
  - `DockerContextCli`, `FakeDockerContexts` (Task 2);
  - `DockerInventoryCollector.readEngine(_:)` (Task 1);
  - `DockerTarget`, `DockerAnalysis.target`, `DockerContextReader.notRunningMessage(for:)`, `dockerAnalysis(_:engine:context:disk:df:)` (Task 3).
- Produces:
  - `public struct DockerEngineChangedError: Error, Equatable, Sendable, LocalizedError`, con `init(context: String)` e `message`;
  - `DockerCleanExecutor.execute(_ selected: [DockerCandidate], on target: DockerTarget, progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult`;
  - `DockerCleanupService.execute(_:on:progress:)` e `DockerCleanupServing.execute(_:on:progress:)`, con la stessa firma;
  - nei test di Features, `FakeDocker.targets: [DockerTarget]`.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
    private static let ryukId = DockerFixtures.ryukId
```

con:

```swift
    private static let ryukId = DockerFixtures.ryukId

    /// Il bersaglio dell'analisi: Docker Desktop su `desktop-linux`.
    private static let target = DockerTarget(
        context: FakeDockerContexts.desktopLinux,
        engine: DockerEngine(serverVersion: "29.8.0", operatingSystem: "Docker Desktop", id: "5f0d6c1e-desktop"))
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
    /// CLI che accetta ogni cancellazione e restituisce il df prima e dopo.
    private func succeedingCli() -> FakeDockerCli {
        let dfCalls = Shared(0)
        return FakeDockerCli()
            .on("system df --format {{json .}}")
```

con:

```swift
    /// CLI del motore analizzato: accetta ogni cancellazione e restituisce il df prima e dopo.
    private func succeedingCli() -> FakeDockerCli {
        let dfCalls = Shared(0)
        return FakeDockerCli()
            .on(FakeDockerCli.infoCommand, FakeDockerCli.info("29.8.0", id: Self.target.engine.id))
            .on("system df --format {{json .}}")
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
    private func executor(_ cli: FakeDockerCli) -> DockerCleanExecutor {
        DockerCleanExecutor(cli: cli, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
    }

    private func execute(_ cli: FakeDockerCli, _ selected: DockerCandidate...) async throws -> DockerCleanResult {
        try await executor(cli).execute(selected, progress: nil)
    }
```

con:

```swift
    /// `cli` è il motore di `desktop-linux`; il contesto attivo è `orbstack`, un motore che non
    /// risponde a nulla: un comando senza `--context desktop-linux` non arriva mai a `cli`.
    private static func contexts(_ cli: FakeDockerCli, orbStack: FakeDockerCli = FakeDockerCli()) -> FakeDockerContexts {
        FakeDockerContexts(active: "orbstack", [(FakeDockerContexts.desktopLinux, cli), (FakeDockerContexts.orbstack, orbStack)])
    }

    private func executor(_ cli: FakeDockerCli) -> DockerCleanExecutor {
        DockerCleanExecutor(cli: Self.contexts(cli), clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
    }

    private func execute(_ cli: FakeDockerCli, _ selected: DockerCandidate...) async throws -> DockerCleanResult {
        try await executor(cli).execute(selected, on: Self.target, progress: nil)
    }
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire le 2 occorrenze di:

```swift
            try await executor.execute(selected, progress: { _ in cancelCurrentTask() })
```

con:

```swift
            try await executor.execute(selected, on: Self.target, progress: { _ in cancelCurrentTask() })
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
        _ = try await executor(succeedingCli()).execute([image(Self.ryukId, "ryuk"), volume("old-data")], progress: reports.append)
```

con:

```swift
        _ = try await executor(succeedingCli()).execute([image(Self.ryukId, "ryuk"), volume("old-data")], on: Self.target, progress: reports.append)
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
        let executor = DockerCleanExecutor(
            cli: CancellationCheckingCli(inner: cli),
```

con:

```swift
        let executor = DockerCleanExecutor(
            cli: CancellationCheckingCli(inner: Self.contexts(cli)),
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
            return try await executor.execute(selected, progress: nil)
```

con:

```swift
            return try await executor.execute(selected, on: Self.target, progress: nil)
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
}

/// Come `ProcessRunner`: il comando risponde e solo dopo controlla l'annullamento del task che lo
```

con:

```swift

    /// Il contesto attivo è `orbstack`: ogni comando va comunque a `desktop-linux`, e prima della
    /// misura iniziale si legge il motore.
    @Test func everyCommandGoesToTheContextOfTheAnalysis() async throws {
        let cli = succeedingCli()
        let orbStack = FakeDockerCli()
        let docker = Self.contexts(cli, orbStack: orbStack)
        let executor = DockerCleanExecutor(cli: docker, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))

        let result = try await executor.execute(
            [image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache], on: Self.target, progress: nil)

        #expect(result.report.itemsDeleted == 3)
        #expect(docker.calls.allSatisfy { $0.starts(with: ["--context", "desktop-linux"]) })
        #expect(cli.commandLines.prefix(2) == ["info --format \(DockerInventoryCollector.engineFormat)", "system df --format {{json .}}"])
        #expect(orbStack.calls.isEmpty)
    }

    /// Lo stesso contesto ma un altro daemon: `default` riscritto da un altro motore, un motore
    /// aggiornato o sostituito. Dopo `docker info` non parte nessun comando.
    @Test(arguments: [
        ("9a8b7c6d-other", "29.8.0", "Docker Desktop"),
        ("5f0d6c1e-desktop", "29.9.0", "Docker Desktop"),
        ("5f0d6c1e-desktop", "29.8.0", "OrbStack"),
    ])
    func anotherDaemonBehindTheSameContextDeletesNothing(id: String, version: String, operatingSystem: String) async throws {
        let cli = succeedingCli().on(FakeDockerCli.infoCommand, FakeDockerCli.info(version, operatingSystem, id: id))

        let error = await #expect(throws: DockerEngineChangedError.self) {
            try await execute(cli, image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache)
        }

        #expect(error == DockerEngineChangedError(context: "desktop-linux"))
        #expect(error?.message == "Il motore Docker del contesto «desktop-linux» non è più quello analizzato: non è stato eliminato nulla. Premi Riprova per analizzarlo di nuovo.")
        #expect(cli.commandLines == ["info --format \(DockerInventoryCollector.engineFormat)"])
    }

    @Test func aTargetWithAnInvalidContextNameDeletesNothing() async throws {
        let cli = succeedingCli()
        let docker = Self.contexts(cli)
        let executor = DockerCleanExecutor(cli: docker, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
        let target = DockerTarget(
            context: DockerContext(name: "--host=tcp://10.0.0.1:2375", description: "", host: ""),
            engine: Self.target.engine)

        await #expect(throws: DockerOutputError("Nome del contesto Docker non valido: «--host=tcp://10.0.0.1:2375».")) {
            try await executor.execute([volume("old-data")], on: target, progress: nil)
        }
        #expect(docker.calls.isEmpty)
    }
}

/// Come `ProcessRunner`: il comando risponde e solo dopo controlla l'annullamento del task che lo
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`, sostituire:

```swift
private struct CancellationCheckingCli: DockerCommandRunning {
    let inner: FakeDockerCli
```

con:

```swift
private struct CancellationCheckingCli: DockerCommandRunning {
    let inner: any DockerCommandRunning
```

In `MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift`, sostituire:

```swift
        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
        #expect(orbStack.calls.isEmpty)
    }
}
```

con:

```swift
        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
        #expect(orbStack.calls.isEmpty)
    }

    /// Un'immagine, un volume e la cache di build dell'analisi, da cancellare.
    private func deletable(_ analysis: DockerAnalysis) throws -> (image: DockerCandidate, volume: DockerCandidate, buildCache: DockerCandidate) {
        (
            try #require(analysis.candidates.first { $0.kind == .image && $0.verdict != .keep }),
            try #require(analysis.candidates.first { $0.kind == .volume && $0.verdict != .keep }),
            try #require(analysis.candidates.first { $0.kind == .buildCache }))
    }

    /// I comandi che cancellano, fra quelli arrivati a `cli`.
    private func deletions(_ cli: FakeDockerCli) -> [String] {
        cli.commandLines.filter { $0.hasPrefix("rmi ") || $0.hasPrefix("volume rm ") || $0.hasPrefix("builder prune") }
    }

    /// Il caso del 2026-10-19: dopo l'analisi di Docker Desktop, OrbStack si avvia e prende il
    /// contesto attivo. «Elimina» cancella su Docker Desktop, ciò che l'utente ha confermato, e
    /// OrbStack non riceve nemmeno un comando, anche se accetterebbe ogni cancellazione.
    @Test func aContextSwitchBetweenAnalysisAndDeletionLeavesTheOtherEngineAlone() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        for cli in [desktop, orbStack] {
            cli.onPrefix("rmi ") { _ in FakeDockerCli.ok("Deleted") }
                .onPrefix("volume rm ") { arguments in FakeDockerCli.ok(arguments.last ?? "") }
                .on("builder prune -f", "Total reclaimed space: 106.9MB")
        }
        let cleanup = service(InMemoryFileSystem(), docker: docker)
        let analysis = try await cleanup.analyze([])
        let (image, volume, buildCache) = try deletable(analysis)

        docker.activate("orbstack")
        let result = try await cleanup.execute([image, volume, buildCache], on: analysis.target, progress: nil)

        #expect(result.report.itemsDeleted == 3)
        #expect(deletions(desktop) == ["rmi \(image.id)", "volume rm \(volume.id)", "builder prune -f"])
        #expect(orbStack.calls.isEmpty)
    }

    /// Dopo il cambio Docker Desktop è anche spento: non si cancella nulla, né lì né su OrbStack, e
    /// l'errore nomina Docker Desktop.
    @Test func aStoppedEngineAfterTheSwitchDeletesNothingAnywhere() async throws {
        let (docker, desktop, orbStack) = try twoEngines()
        let cleanup = service(InMemoryFileSystem(), docker: docker)
        let analysis = try await cleanup.analyze([])
        let (image, volume, buildCache) = try deletable(analysis)

        docker.activate("orbstack")
        desktop.on(FakeDockerCli.infoCommand) { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cleanup.execute([image, volume, buildCache], on: analysis.target, progress: nil)
        }

        #expect(error == DockerUnavailableError("Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."))
        #expect(deletions(desktop).isEmpty)
        #expect(orbStack.calls.isEmpty)
    }
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
        var targets: [DockerTarget] = []
    }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
    var executed: [[DockerCandidate]] { state.withLock { $0.executed } }
```

con:

```swift
    var executed: [[DockerCandidate]] { state.withLock { $0.executed } }
    var targets: [DockerTarget] { state.withLock { $0.targets } }
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift`, sostituire:

```swift
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        let result = state.withLock { state -> Result<DockerCleanResult, any Error> in
            state.executed.append(selected)
```

con:

```swift
    func execute(_ selected: [DockerCandidate], on target: DockerTarget, progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        let result = state.withLock { state -> Result<DockerCleanResult, any Error> in
            state.executed.append(selected)
            state.targets.append(target)
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`, sostituire le 2 occorrenze di:

```swift
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
```

con:

```swift
    func execute(_ selected: [DockerCandidate], on target: DockerTarget, progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`, sostituire:

```swift
    @Test func diskDescriptionsCoverMissingAndUnmeasurableImages() {
```

con:

```swift
    /// «Elimina» resta sul contesto e sul motore dell'ultima analisi riuscita, così come sono.
    @Test func deleteRunsOnTheTargetOfTheLatestAnalysis() async throws {
        let orbStack = DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack", id: "b2756783-e527-49e3-a6c6-cd7f4e49c9ff")
        let orbstack = DockerContext(name: "orbstack", description: "OrbStack", host: "unix:///Users/tester/.orbstack/run/docker.sock")
        let docker = FakeDocker()
        docker.enqueue(.success(dockerAnalysis(Self.mixed)))
        docker.enqueue(.success(dockerAnalysis(Self.mixed, engine: orbStack, context: orbstack, disk: nil)))
        let model = try await opened(docker: docker)
        await model.retry()

        await model.delete()

        #expect(docker.targets == [DockerTarget(context: orbstack, engine: orbStack)])
    }

    @Test func diskDescriptionsCoverMissingAndUnmeasurableImages() {
```

- [ ] **Step 2: Verificare che non compilino**

Run: comando «compilazione» delle Global Constraints.
Expected: errori di compilazione, fra cui `extra argument 'on' in call`. Gli errori degli altri file e del modulo di test di Features (`DockerEngineChangedError` sconosciuto, `FakeDocker` non conforme) possono mancare: la build si ferma al primo modulo che non compila.

- [ ] **Step 3: Implementazione del Core**

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift`, sostituire:

```swift
/// Esegue le sole cancellazioni confermate. Ogni garanzia di sicurezza è verificata qui, sul
/// singolo elemento, anche se l'interfaccia l'ha già applicata: la selezione arriva dall'interfaccia
/// e non va fidata, come in `CleanEngine`.
/// - immagini solo per ID completo (`docker rmi sha256:…`), mai per tag;
```

con:

```swift
/// Il daemon del contesto analizzato non è più quello dell'analisi: non si è eliminato nulla.
public struct DockerEngineChangedError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(context: String) {
        message = String(
            localized: "Il motore Docker del contesto «\(context)» non è più quello analizzato: non è stato eliminato nulla. Premi Riprova per analizzarlo di nuovo.",
            bundle: .module)
    }

    public var errorDescription: String? { message }
}

/// Esegue le sole cancellazioni confermate. Ogni garanzia di sicurezza è verificata qui, sul
/// singolo elemento, anche se l'interfaccia l'ha già applicata: la selezione arriva dall'interfaccia
/// e non va fidata, come in `CleanEngine`.
/// - ogni comando va al contesto dell'analisi, e solo se lì risponde ancora lo stesso daemon;
/// - immagini solo per ID completo (`docker rmi sha256:…`), mai per tag;
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift`, sostituire:

```swift
    /// Lancia solo se la misura iniziale fallisce (nulla è stato cancellato) o per un errore fuori
    /// contratto della CLI, come il C#. L'annullamento ferma la pulizia fra un elemento e l'altro e
    /// restituisce il resoconto parziale.
    @concurrent
    public func execute(
        _ selected: [DockerCandidate],
        progress: (@Sendable (CleanProgress) -> Void)?
    ) async throws -> DockerCleanResult {
        let startedAt = clock.now
        let start = ContinuousClock.now

```

con:

```swift
    /// Lancia prima di cancellare qualunque cosa se il nome del contesto non è valido, se lì non
    /// risponde più il daemon dell'analisi (`DockerEngineChangedError`) o se la misura iniziale
    /// fallisce; poi solo per un errore fuori contratto della CLI, come il C#. L'annullamento ferma
    /// la pulizia fra un elemento e l'altro e restituisce il resoconto parziale.
    @concurrent
    public func execute(
        _ selected: [DockerCandidate],
        on target: DockerTarget,
        progress: (@Sendable (CleanProgress) -> Void)?
    ) async throws -> DockerCleanResult {
        let startedAt = clock.now
        let start = ContinuousClock.now

        // Ogni comando va al contesto dell'analisi, anche se nel frattempo il contesto attivo è
        // cambiato. Prima di cancellare, lì deve rispondere lo stesso daemon: `default` segue
        // `/var/run/docker.sock`, che il motore avviato per ultimo riscrive.
        let cli = try DockerContextCli(self.cli, context: target.context.name)
        guard try await DockerInventoryCollector.readEngine(cli) == target.engine else {
            throw DockerEngineChangedError(context: target.context.name)
        }

```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift`, sostituire:

```swift
                    result = try await shielded(Self.command(candidate))
```

con:

```swift
                    result = try await Self.shielded(cli, Self.command(candidate))
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift`, sostituire:

```swift
        let after = daemonLost ? nil : try await tryReadDf()
```

con:

```swift
        let after = daemonLost ? nil : try await Self.tryReadDf(cli)
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift`, sostituire:

```swift
    private func shielded(_ arguments: [String]) async throws -> ProcessResult {
        let cli = self.cli
        return try await Task { try await cli.run(arguments, timeout: Self.deleteTimeout) }.value
    }

    private func tryReadDf() async throws -> DockerDfSummary? {
        let cli = self.cli
        do {
```

con:

```swift
    private static func shielded(_ cli: any DockerCommandRunning, _ arguments: [String]) async throws -> ProcessResult {
        try await Task { try await cli.run(arguments, timeout: deleteTimeout) }.value
    }

    private static func tryReadDf(_ cli: any DockerCommandRunning) async throws -> DockerDfSummary? {
        do {
```

In `MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift`, sostituire:

```swift
    public func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        try await executor.execute(selected, progress: progress)
    }
```

con:

```swift
    /// L'esecuzione resta sul bersaglio dell'analisi. Un daemon che non risponde prima di ogni
    /// cancellazione (quello perso a metà finisce nel resoconto) diventa l'errore che nomina il
    /// motore del contesto analizzato, anche se il contesto attivo ora è un altro.
    public func execute(
        _ selected: [DockerCandidate],
        on target: DockerTarget,
        progress: (@Sendable (CleanProgress) -> Void)?
    ) async throws -> DockerCleanResult {
        do {
            return try await executor.execute(selected, on: target, progress: progress)
        } catch let error as DockerUnavailableError where error.reason == .notRunning {
            throw DockerUnavailableError(contexts.notRunningMessage(for: target.context))
        }
    }
```

- [ ] **Step 4: Implementazione di Features e della demo**

In `MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift`, sostituire:

```swift
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult
```

con:

```swift
    /// Cancella sul bersaglio dell'analisi, `DockerAnalysis.target`.
    func execute(_ selected: [DockerCandidate], on target: DockerTarget, progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`, sostituire:

```swift
    @ObservationIgnored private var engine: DockerEngine?
```

con:

```swift
    /// Il contesto e il motore dell'ultima analisi riuscita: «Elimina» resta lì.
    @ObservationIgnored private var target: DockerTarget?
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`, sostituire:

```swift
        // `canDelete` richiede un'analisi riuscita, che ha fissato il motore.
        guard canDelete, let engine else { return }
```

con:

```swift
        // `canDelete` richiede un'analisi riuscita, che ha fissato il bersaglio.
        guard canDelete, let target else { return }
        let engine = target.engine
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`, sostituire:

```swift
        let task = Task { try await docker.execute(selected, progress: report) }
```

con:

```swift
        let task = Task { try await docker.execute(selected, on: target, progress: report) }
```

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`, sostituire:

```swift
            engine = analysis.engine
            diskBefore = analysis.disk
```

con:

```swift
            target = analysis.target
            diskBefore = analysis.disk
```

In `MjmCleaner/Demo/DemoServices.swift`, sostituire:

```swift
    func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
```

con:

```swift
    func execute(_ selected: [DockerCandidate], on target: DockerTarget, progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
```

- [ ] **Step 5: Verificare che passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 570 tests in 51 suites passed` e `Test run with 179 tests in 21 suites passed`, nessun warning.

Run: comando «app» delle Global Constraints.
Expected: `** BUILD SUCCEEDED **`, nessuna riga `warning:` o `error:`.

- [ ] **Step 6: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift MjmCleanerKit/Sources/CleanerFeatures/Environment/DockerCleanupServing.swift MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift MjmCleaner/Demo/DemoServices.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift MjmCleanerKit/Tests/CleanerFeaturesTests/Support/ServiceDoubles.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift
git commit -F - <<'EOF'
fix(docker): delete only on the analyzed engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: La pagina mostra il rifiuto sotto «Elimina»

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift` (`delete()`)
- Test: modify `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`

**Interfaces:**
- Consumes: `DockerEngineChangedError` (Task 4), `FakeDocker.respond(with:)`, `DockerModel.selection()`.
- Produces: `DockerModel.delete()` mette `DockerEngineChangedError.message` in `deleteErrorText` così com'è.

- [ ] **Step 1: Test che falliscono**

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`, sostituire:

```swift
        (DockerUnavailableError("Docker si è fermato.") as any Error, "Docker si è fermato."),
```

con:

```swift
        (DockerUnavailableError("Docker si è fermato.") as any Error, "Docker si è fermato."),
        (DockerEngineChangedError(context: "desktop-linux") as any Error,
         "Il motore Docker del contesto «desktop-linux» non è più quello analizzato: non è stato eliminato nulla. Premi Riprova per analizzarlo di nuovo."),
```

In `MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift`, sostituire:

```swift
    /// «Elimina» resta sul contesto e sul motore dell'ultima analisi riuscita, così come sono.
```

con:

```swift
    /// Il daemon è cambiato dopo l'analisi: la pagina resta com'era, con elenco e selezione, e un
    /// nuovo clic viene di nuovo consegnato all'esecuzione, che lo rifiuterà.
    @Test func aChangedEngineKeepsTheListAndTheSelection() async throws {
        let docker = FakeDocker()
        docker.respond(with: .failure(DockerEngineChangedError(context: "desktop-linux")))
        let navigation = DockerNavigationSpy()
        let model = try await loaded(docker: docker, navigation: navigation)
        let groups = model.groups.map(\.definition.id)
        let selection = model.selection()

        await model.delete()

        #expect(model.isReady)
        #expect(model.groups.map(\.definition.id) == groups)
        #expect(model.selection() == selection)
        #expect(model.canDelete)
        #expect(navigation.events.isEmpty)
    }

    /// «Elimina» resta sul contesto e sul motore dell'ultima analisi riuscita, così come sono.
```

- [ ] **Step 2: Verificare che falliscano**

Run: comando «una suite» delle Global Constraints con `<Suite>` = `DockerModelTests`.
Expected: `✘` sul caso di `deleteFailuresAreShownOnThePage` con `DockerEngineChangedError`, perché il testo arriva con il prefisso «Pulizia non riuscita: ». `aChangedEngineKeepsTheListAndTheSelection` passa già: protegge la scelta dell'utente.

- [ ] **Step 3: Implementazione**

In `MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift`, sostituire:

```swift
        } catch let error as DockerUnavailableError {
            await relay.finish()
            deleteErrorText = error.message
        } catch {
```

con:

```swift
        } catch let error as DockerUnavailableError {
            await relay.finish()
            deleteErrorText = error.message
        } catch let error as DockerEngineChangedError {
            // Non si è cancellato nulla e il messaggio dice già cosa fare: l'elenco resta com'è, e
            // un nuovo clic verrebbe rifiutato di nuovo.
            await relay.finish()
            deleteErrorText = error.message
        } catch {
```

- [ ] **Step 4: Verificare che passino**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 570 tests in 51 suites passed` e `Test run with 180 tests in 21 suites passed`, nessun warning.

- [ ] **Step 5: Commit**

```bash
git add MjmCleanerKit/Sources/CleanerFeatures/Docker/DockerModel.swift MjmCleanerKit/Tests/CleanerFeaturesTests/DockerModelTests.swift
git commit -F - <<'EOF'
feat(docker): show the changed-engine refusal under Delete

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 6: README, verifica completa e prova in sola lettura

**Files:**
- Modify: `README.md` (sezione «Docker»)
- Scratch, non committato: un file di test temporaneo in una copia del package

**Interfaces:**
- Consumes: tutto quanto prodotto dai Task 1–5.

- [ ] **Step 1: README**

In `README.md`, sostituire:

```markdown
inside `Docker.app` and `OrbStack.app`; a dangling link left by an uninstalled
engine is skipped.
```

con:

```markdown
inside `Docker.app` and `OrbStack.app`; a dangling link left by an uninstalled
engine is skipped.

The context is read once, when the analysis starts, and every command of the
analysis and of the cleanup runs with `docker --context <name>` on that context.
If the active context changes in the meantime (OrbStack, for example, makes its
own context active when it starts), the cleanup still deletes only on the
analyzed engine. Before deleting anything, the page checks that the daemon behind
that context is still the analyzed one (same ID, operating system, and version).
If it is not, nothing is deleted and the page asks you to analyze again. The
active context is never changed.
```

- [ ] **Step 2: Verifica completa**

Run: comando «package» delle Global Constraints.
Expected: `Test run with 570 tests in 51 suites passed` e `Test run with 180 tests in 21 suites passed`, nessun warning.

Run: comando «app» delle Global Constraints.
Expected: `** BUILD SUCCEEDED **`, nessuna riga `warning:` o `error:`.

Run: `git status --short`
Expected: solo `README.md`, più le modifiche locali di Xcode ai tre `Localizable.xcstrings` se la build le ha prodotte. Queste ultime non vanno in stage.

- [ ] **Step 3: Prova in sola lettura sul motore vero (copia scratch, non committata)**

Prerequisito: un motore Docker in esecuzione sul contesto attivo (sul Mac dell'utente, OrbStack). Se nessun motore risponde, saltare lo step e riportarlo. Nessun comando cambia il contesto attivo e nessun comando cancella: la selezione è vuota, quindi l'esecuzione lancia solo `info` e `system df`.

Da una cartella scratch esclusiva (non nel repository), indicata qui come `$SCRATCH`:

```bash
rm -rf "$SCRATCH/live" && mkdir -p "$SCRATCH/live" && git archive HEAD | tar -x -C "$SCRATCH/live"
```

Creare `$SCRATCH/live/MjmCleanerKit/Tests/CleanerCoreTests/LiveDockerGuardSmokeTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

/// Prova dal vivo in sola lettura: `context inspect`, `--context … info` e `--context … system df`,
/// con una selezione vuota. Non committare.
struct LiveDockerGuardSmokeTests {
    @Test func theGuardAcceptsTheAnalyzedDaemonAndRefusesAnother() async throws {
        let home = NSHomeDirectory()
        let cli = DockerCli(runner: ProcessRunner(), binaryPath: DockerBinaryLocator.find(homeDirectory: home))
        let reader = DockerContextReader(cli: cli, homeDirectory: home)

        let context = try await reader.activeContext()
        print("LIVE context:", context)
        let engine = try await DockerInventoryCollector(cli: cli, fileSystem: LocalFileSystem()).pinned(to: context.name).checkDaemon()
        print("LIVE engine:", engine)
        #expect(!engine.id.isEmpty)

        let executor = DockerCleanExecutor(cli: cli, clock: SystemWallClock())
        let result = try await executor.execute([], on: DockerTarget(context: context, engine: engine), progress: nil)
        print("LIVE empty run:", result.report.itemsDeleted, result.after != nil)
        #expect(result.report.itemsDeleted == 0)
        #expect(result.after != nil)

        let other = DockerEngine(serverVersion: engine.serverVersion, operatingSystem: engine.operatingSystem, id: "not-this-daemon")
        await #expect(throws: DockerEngineChangedError(context: context.name)) {
            try await executor.execute([], on: DockerTarget(context: context, engine: other), progress: nil)
        }

        let after = try await reader.activeContext()
        print("LIVE context after:", after.name)
        #expect(after == context)
    }
}
```

Run: `(cd "$SCRATCH/live/MjmCleanerKit" && swift test --filter LiveDockerGuardSmokeTests 2>&1 | grep -E 'LIVE|✘|Test run with')`
Expected: le righe `LIVE` (il contesto attivo, il motore con un `id` non vuoto, `LIVE empty run: 0 true`, lo stesso contesto alla fine) e `Test run with 1 test in 1 suite passed`. Riportare l'output nel report del task, poi cancellare `$SCRATCH/live`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -F - <<'EOF'
docs(docker): explain that cleanup stays on the analyzed engine

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

## Mutazioni provate in stesura

Ognuna applicata da sola alla copia scratch con i Task 1–5 completi; esito con il comando «package».

| # | Mutazione | Ucciso da |
|---|---|---|
| M1 | `DockerCleanExecutor.execute`: `let cli: any DockerCommandRunning = self.cli` (CLI non fissata) | `DockerCleanupServiceTests.aContextSwitchBetweenAnalysisAndDeletionLeavesTheOtherEngineAlone`, `DockerCleanExecutorTests.everyCommandGoesToTheContextOfTheAnalysis` e altri 22 test dell'esecutore |
| M2 | `DockerCleanExecutor`: solo le cancellazioni con `Self.shielded(self.cli, …)` | `aContextSwitchBetweenAnalysisAndDeletionLeavesTheOtherEngineAlone`, `everyCommandGoesToTheContextOfTheAnalysis` e altri 12 |
| M3 | `DockerCleanExecutor.execute`: togliere la `guard` sull'identità | `anotherDaemonBehindTheSameContextDeletesNothing`, `aStoppedEngineAfterTheSwitchDeletesNothingAnywhere`, `everyCommandGoesToTheContextOfTheAnalysis` |
| M4 | `DockerCleanExecutor.execute`: confrontare solo sistema e versione, non l'ID | `anotherDaemonBehindTheSameContextDeletesNothing` (primo caso) |
| M5 | `DockerCleanupService.analyze`: `let pinned = collector` (analisi non fissata) | `everyAnalysisCommandStaysOnTheContextReadAtTheStart`, `aContextWithoutAValidNameStopsTheAnalysis` |
| M6 | `DockerContextCli.init`: togliere la `guard` sul nome | `namesDockerRejectsAreRefusedBeforeAnyCommand`, `aContextWithoutAValidNameStopsTheAnalysis`, `aTargetWithAnInvalidContextNameDeletesNothing` |
| M7 | `DockerContextCli.init`: ammettere «-» come primo carattere | `namesDockerRejectsAreRefusedBeforeAnyCommand` |
| M8 | `DockerCleanupService.execute`: il messaggio rilegge il contesto attivo (`(try? await contexts.activeContext()) ?? target.context`) | `aStoppedEngineAfterTheSwitchDeletesNothingAnywhere` |
| M9 | `DockerCleanupService.analyze`: il messaggio rilegge il contesto attivo | `aStoppedEngineIsNamedFromTheContextReadAtTheStart` |
| M10 | `DockerCleanupService.execute`: inoltrare senza riscrivere «non in esecuzione» | `aStoppedEngineAfterTheSwitchDeletesNothingAnywhere` |
| M11 | `DockerModel.load`: tenere il bersaglio della prima analisi (`if target == nil { … }`) | `DockerModelTests.deleteRunsOnTheTargetOfTheLatestAnalysis` |
| M12 | `DockerModel.delete`: togliere il `catch` di `DockerEngineChangedError` | `DockerModelTests.deleteFailuresAreShownOnThePage` |
| M13 | `engineFormat` senza `"ID":{{json .ID}}` | `DockerInventoryCollectorTests.theDaemonIdComesWithTheSameInfoCall` |
| M14 | `DockerJson.parseEngineInfo`: `id` sempre vuoto | `theDaemonIdComesWithTheSameInfoCall` e tutti i test dell'esecutore |
| M15 | `DockerCleanExecutor`: misura finale con `Self.tryReadDf(self.cli)` | `aContextSwitchBetweenAnalysisAndDeletionLeavesTheOtherEngineAlone`, `everyCommandGoesToTheContextOfTheAnalysis`, `bytesFreedAreTheSystemDfDeltaPerType` e altri 3 |
| M16 | `DockerCleanupService.analyze`: contesto illeggibile → `default` invece dell'errore | `anUnreadableContextStopsTheAnalysis`, `aMissingDockerStopsAtTheContextRead` |

## Esito della riesecuzione in stesura

Il piano è stato rieseguito il 2026-10-19 in un clone pulito di `d7c3150`, sul branch `feat/docker-delete-guard`. Uno script ha applicato ogni blocco nell'ordine del piano («Creare», «Sostituire l'intero contenuto», «sostituire … con», «In fondo a … aggiungere») e ha lanciato i comandi dei passi «Verificare» e i commit così come sono scritti:

| Task | Passo rosso | Suite | App | Commit |
|---|---|---|---|---|
| 1 | `extra argument 'id' in call`, `no member 'readEngine'` | 556 + 178 | — | trailer corretto, `git status` pulito |
| 2 | `cannot find 'DockerContextCli'`, `no member 'pinned'` | 561 + 178 | — | idem |
| 3 | `cannot find 'DockerTarget'`, `no member 'target'` | 565 + 178 | `BUILD SUCCEEDED` | idem |
| 4 | `extra argument 'on' in call` | 570 + 179 | `BUILD SUCCEEDED` | idem |
| 5 | `✘ deleteFailuresAreShownOnThePage` (caso `DockerEngineChangedError`) | 570 + 180 | — | idem |
| 6 | — | 570 + 180 | `BUILD SUCCEEDED` | idem |

L'albero finale coincide con quello della copia di sviluppo su cui sono state provate le mutazioni (`git diff` vuoto). Nessun warning. Le build dell'app non hanno modificato i `Localizable.xcstrings`.

Prova in sola lettura del Task 6, eseguita sul Mac dell'utente con OrbStack attivo:

```
LIVE context: DockerContext(name: "orbstack", description: "OrbStack", host: "unix:///Users/mjm/.orbstack/run/docker.sock")
LIVE engine: DockerEngine(kind: CleanerCore.DockerEngineKind.orbStack, displayName: "OrbStack", operatingSystem: "OrbStack", serverVersion: "29.8.2", id: "b2756783-e527-49e3-a6c6-cd7f4e49c9ff")
LIVE empty run: 0 true
LIVE context after: orbstack
✔ Test run with 1 test in 1 suite passed after 0.693 seconds.
```

`docker context show` dava `orbstack` prima e dopo la prova.
