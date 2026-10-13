# Porting Swift — Piano 2: Docker

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portare in `CleanerCore` la pulizia Docker di `src/MjmCleaner.Core/Docker` — tutto tranne `ProcessRunner.cs`, già portato nel piano 1 in `Platform/` — cioè modelli, dimensioni e nomi delle immagini, parsing JSON, CLI e ricerca del binario, raccolta dell'inventario, regole e classificazione, gruppi di conferma, misura di `Docker.raw`, ricerca dei riferimenti nei progetti, esecutore e servizio, con le 99 prove C# di `tests/MjmCleaner.Core.Tests/Docker` portate in Swift Testing (più 15 solo-Swift che fissano le equivalenze con .NET) e verdi: 356 test in tutto.

**Architecture:** Un file Swift per ogni file C#, in `Sources/CleanerCore/Docker/`, con gli stessi tipi e le stesse responsabilità. La classificazione resta una funzione pura dello snapshot (`DockerClassifier`), verificata con le fixture JSON del caso reale copiate dal C#; tutto l'I/O passa da tre giunture: `DockerCommandRunning` (porting di `IDockerCli`, implementato da `DockerCli` sopra `ProcessRunning` del piano 1), `FileSystem` e `ProcessRunning`. Le operazioni sul testo che in C# erano metodi .NET su unità UTF-16 passano da un helper interno, `DockerText`, che lavora su scalari e byte come `PathText`; le regex generate del C# diventano letterali `Regex` tradotti con la semantica di .NET 10, misurata durante la stesura e fissata da test solo-Swift.

**Tech Stack:** Swift 6 language mode, `swift-tools-version: 6.2`, macOS 15, Swift Testing, Foundation (`JSONDecoder`, `Decimal`), `Regex` della libreria standard, `Synchronization.Mutex` nei doppi di test. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`

Questo è il **piano 2 di 5**: (1) fondamenta e Core — completato; (2) Docker; (3) Xcode; (4) Features e app SwiftUI; (5) verifica, release e rimozione del C#. Ciascuno produce software funzionante e testato e si scrive a piano precedente completato, sul codice reale. La spec (in particolare §5.2–5.3, §5.6, §8, §9) resta l'autorità vincolante; la spec della funzione Docker (`docs/superpowers/specs/2026-10-01-docker-cleanup-design.md`) ne descrive l'intento.

Durante la stesura ogni blocco di codice di questo piano è stato estratto in una copia del package e compilato con `swift build --build-tests -Xswiftc -warnings-as-errors`: 356 test verdi con `swift test -Xswiftc -warnings-as-errors`, conteggi per task uguali agli «Expected», errori di compilazione dei passi «falliscono» verificati task per task. Gli esiti attesi dei test solo-Swift che fissano un'equivalenza sono quelli di .NET 10 o del C# reale, eseguito con un harness sugli stessi input; quelli che fissano una differenza voluta sono annotati nel registro di parità.

## Global Constraints

- Il codice Swift vive in `swift/`; il package in `swift/MjmCleanerKit/`. Il C# (`src/`, `tests/`) **non si modifica**: è il riferimento eseguibile.
- `swift-tools-version: 6.2`, `platforms: [.macOS(.v15)]`, `defaultLocalization: "it"`, Swift 6 language mode (concorrenza stretta).
- Nessuna dipendenza esterna. Librerie di sistema ammesse: Foundation, Darwin, `SQLite3`, zlib (via `CZlib`), `Synchronization`.
- `CleanerCore` non importa SwiftUI né AppKit.
- Nel codice di `CleanerCore`: vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati.
- Testi visibili all'utente prodotti dal Core: sempre `String(localized: "…", bundle: .module)`, in italiano, identici al C#.
- Ogni test C# portato mantiene il nome (in lowerCamelCase) e il file di origine (stessa cartella relativa sotto `Tests/CleanerCoreTests/`).
- Comando di verifica standard, da `swift/MjmCleanerKit`: `swift test -Xswiftc -warnings-as-errors` (equivale al `TreatWarningsAsErrors` del C#).
- Il PathGuard (`Safety`) si implementa in TDD prima di ogni altro componente che elimina file.
- Commit frequenti; ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Lavoro su un branch dedicato creato da `main`, dove il piano 1 è già integrato (il branch `feat/swift-port` del piano 1 non esiste più).

Vincoli aggiunti per Docker:

- **Nessun file di Docker si cancella dal disco.** La deny-list non cambia, nulla sotto `~/Library/Containers/com.docker.docker` passa per `CleanEngine`, di `Docker.raw` si legge solo la dimensione. Il Core non avvia mai Docker Desktop.
- **Comandi Docker identici al C#**, sempre come array di argomenti tramite `ProcessRunner`: immagini solo con `docker rmi sha256:<64 cifre esadecimali>` (mai per tag), volumi con `docker volume rm <nome>`, cache con `docker builder prune -f` (l'unico `-f`, che salta solo la conferma interattiva). Mai `rmi -f`/`--force`, mai `system prune`, mai `--all`/`--volumes`. Le voci KEEP non arrivano mai a un comando: l'esecutore ricontrolla ogni voce anche se l'interfaccia l'ha già filtrata.
- Il binario `docker` si avvia sempre per percorso assoluto, quello trovato da `DockerBinaryLocator`: `posix_spawnp` cerca un nome semplice nel PATH dell'app, che dal Finder è `/usr/bin:/bin:/usr/sbin:/sbin`. `du` resta per nome, come in C# (sta in `/usr/bin`).
- Timeout identici al C#: 60 secondi per comando (`DockerCli`), 10 minuti per ogni cancellazione, 20 secondi per `du`. Un timeout si riconosce da `ProcessResult.timedOut`, mai da `exitCode == -1`.
- I comandi che il C# lanciava con `CancellationToken.None` (le cancellazioni e la misura finale dell'esecutore) girano in un `Task` non strutturato, che non eredita l'annullamento: l'annullamento ferma la pulizia solo fra un elemento e l'altro e restituisce il resoconto parziale.
- Il testo di Docker e dei progetti si tratta solo con `DockerText` (Task 1) e `PathText`, su scalari e byte UTF-8. In `Sources/CleanerCore/Docker` sono vietati `hasPrefix`, `hasSuffix`, `lowercased`, `contains(_: String)` e `split` di `String` sui `Character`; i confronti senza maiuscole passano solo da `PathText.folded` (`OrdinalIgnoreCase`).
- Le regex sono letterali `Regex` con `.matchingSemantics(.unicodeScalar)`, tradotti con la tabella delle convenzioni. Nessuna `Regex` in una proprietà `static` (`Regex` non è `Sendable`): si costruisce nella funzione che la usa, una volta per chiamata o per file.
- Le funzioni pubbliche asincrone che fanno I/O bloccante sul filesystem sono `@concurrent`, come `ScanEngine` e `CleanEngine`.
- Le fixture JSON si copiano byte per byte dal C# in `Tests/CleanerCoreTests/Docker/Fixtures/` e si leggono dal percorso del sorgente (`#filePath`); in `Package.swift` nessuna risorsa, solo l'`exclude` della cartella (Task 2). I doppi di test di Docker (`FakeDockerCli`, `Shared`, i runner finti) vivono in `Tests/CleanerCoreTests/Docker/`, non in `Support/`.

---

## Convenzioni di porting (valgono per ogni task)

Valgono le **Convenzioni di porting del piano 1** (tipi, nomi dei protocolli, test, fatti misurati su .NET 10), in `docs/superpowers/plans/2026-10-13-swift-port-1-core.md`, e i ruling del registro decisioni del piano 1 (`docs/superpowers/decisions/2026-10-13-registro-decisioni-swift-piano-1.md`): testo dei percorsi solo con `PathText` su byte e scalari, mai tagli per `Character` né `hasPrefix` sui percorsi; confronti senza maiuscole solo con `PathText.equalsIgnoringCase`, `hasPrefixIgnoringCase` o `folded`; timeout di `ProcessRunner` solo da `timedOut`; `@concurrent` per il lavoro bloccante; correttezza `Sendable` di Swift 6. Per Docker si aggiunge quanto segue.

### Tipi e API

| C# | Swift |
|---|---|
| `DockerUnavailableException`, `DockerCommandException`, `DockerOutputException` | `struct DockerUnavailableError`, `DockerCommandError`, `DockerOutputError`: `Error, Equatable, Sendable, LocalizedError`, con `message` (anche come `errorDescription`), senza eccezione interna |
| `const string NotRunning` / `NotInstalled` | `static var notRunning` / `notInstalled`, localizzate |
| `IDockerCli.RunAsync(args, ct, timeout)` | protocollo `DockerCommandRunning`: `run(_:timeout:)`; `run(_:)` e `runChecked(_:)` in estensione |
| `record` modificato con `with` nei test (`DockerSnapshot`) | campi `public var`: la struct resta un valore |
| proprietà calcolate dei record (`IsDangling`, `Names`, `DisplayName`, `SelectedByDefault`, `Exists`) | `var` calcolate con lo stesso nome in lowerCamelCase |
| `IReadOnlySet<string>` / `IReadOnlyDictionary<string, …>` di ID, nomi ed etichette | `Set<String>` / `[String: …]` |
| `ImageRule(Id, Func<…>)`, `VolumeRule(Id, Func<…>)` | `ImageRule(_ id:, _ evaluate:)`, `VolumeRule(_ id:, _ evaluate:)` con chiusura `@Sendable` |
| `InvalidOperationException` di `FirstMatch` | `DockerRuleError`; `DockerClassifier.classify` è `throws` |
| `JsonDocument` / `JsonElement` | `JSONDecoder` → `DockerJsonValue` (le categorie di `JsonValueKind`), letto campo per campo |
| `CancellationToken.None` | `try await Task { … }.value`: un task non strutturato non eredita l'annullamento di chi lo attende |
| `Task.Run(() => scanner.Scan(…))` | `async let` in una funzione `@concurrent` |
| `HashSet<T>(ReferenceEqualityComparer.Instance)` | insieme delle posizioni nella selezione |
| `DockerCategories.For(kind)` | `DockerCategories.category(for:)` (`for` è una parola chiave) |
| `ImageRules.Default` / `VolumeRules.Default` | `ImageRules.default` / `VolumeRules.default` |

### Testo: metodi .NET → `DockerText`

| C# | Swift |
|---|---|
| `s.Split('\n', RemoveEmptyEntries \| TrimEntries)` | `DockerText.lines(s)` |
| `s.Split('\n')` | `DockerText.rawLines(s)` |
| `s.Trim()`, `Trim(c)`, `TrimStart(c)`, `TrimEnd(c)` | `DockerText.trimmed(s)`, `trimmed(s, c)`, `trimmedLeading(s, c)`, `trimmedTrailing(s, c)` |
| `string.IsNullOrWhiteSpace(s)` | `DockerText.isBlank(s)` |
| `Contains`, `StartsWith`, `EndsWith` con `Ordinal` | `DockerText.contains`, `hasPrefix`, `hasSuffix` |
| `Contains`, `EndsWith` con `OrdinalIgnoreCase` | `DockerText.containsIgnoringCase`, `hasSuffixIgnoringCase` |
| `HashSet<string>(StringComparer.OrdinalIgnoreCase)` | `Set` di valori passati da `PathText.folded`, cercati ripiegati |
| `Distinct(StringComparer.Ordinal)` | `DockerText.distinct` |
| `Order(StringComparer.Ordinal)` | `DockerText.ordinalSorted` |
| `ToLowerInvariant()` | `DockerText.lowercasedInvariant` |
| `File.ReadAllText` | `DockerText.decodeLikeReadAllText(try fileSystem.readData(…))` |
| `IndexOf`/`LastIndexOf` di un carattere ASCII e taglio della stringa | ricerca e taglio sui byte UTF-8 |
| `Path.GetFileName`, `GetDirectoryName`, `Combine` | `PathText.fileName`, `parent`, `join` (anche per `ImageName.ShortName`) |

### Regex generate di .NET → `Regex` di Swift

Ogni regex si scrive come letterale con `.matchingSemantics(.unicodeScalar)`: .NET confronta unità UTF-16, mai grafemi. Traduzione dei costrutti (misurata, vedi i fatti sotto):

| .NET | Swift | Perché |
|---|---|---|
| `.` | `[^\n]` | il `.` di Swift esclude anche `\r`, `\v`, `\f`, U+0085, U+2028, U+2029 |
| `$` senza `Multiline` | `\n?$` | il `$` di .NET accetta un `\n` finale, quello di Swift no. Eccezione: nelle guardie dell'esecutore resta `$` (Task 9). Nelle righe già divise su `\n` il `\n?` non serve |
| `^` con `Multiline` | `DockerText.lineStarts` + `prefixMatch` | le ancore di riga di Swift scattano anche dopo `\r`, `\v`, `\f`, U+0085, U+2028, U+2029 |
| `\w` | `[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]` | `\w` di Swift è un'altra classe; .NET non conta mai un carattere fuori dal piano base |
| `\b` dopo una lettera | `(?![[\p{L}\p{Mn}\p{Nd}\p{Pc}\u{200C}\u{200D}]&&[\x{0}-\x{FFFF}]])` | il `\b` di Swift segue UAX #29 o la propria `\w` |
| `\d` seguito da `decimal.TryParse` | `[0-9]` | .NET accetta le cifre non ASCII nella regex e le rifiuta nel parsing: l'esito è lo stesso |
| `\s` | `\s` | stessa classe (White_Space) |
| `RegexOptions.IgnoreCase` (regex generate, cultura invariante) | `.ignoresCase()` | stesse equivalenze sulle lettere ASCII, compreso U+212A per la "k" |
| gruppo senza nome | `(?:…)` | niente campi in più nell'output tipizzato |
| `Match`, `Matches`, `IsMatch` | `firstMatch(of:)`, `matches(of:)`, `firstMatch(of:) != nil` | |

### Test

| xUnit | Swift Testing |
|---|---|
| `Assert.Throws<T>(…)` / `ThrowsAsync<T>(…)` seguito da `error.Message` | `let error = #expect(throws: T.self) { … }` (o `await #expect`), poi `error?.message` |
| `Snapshot() with { Containers = … }` | `var snapshot = try DockerFixtures.snapshot(); snapshot.containers = …` |
| `named with { Id = …, … }` | un nuovo `DockerCandidate` con gli stessi campi |
| `Assert.Single(list, predicato)` | `filter` + `#expect(… .count == 1)` + `#require(… .first)` |
| `MockFileSystem` + `MockFileData("testo")` / `MockFileData(new byte[n])` | `InMemoryFileSystem.addFile(_:text:)` / `addFile(_:size:)` |
| `TimeProvider.System` / `TestTimeProvider(DateTimeOffset.UnixEpoch)` | `SystemWallClock()` / `FixedWallClock(now: Date(timeIntervalSince1970: 0))` |
| variabile locale modificata da una lambda (`dfCalls++`, `childDeleted = true`) | `Shared<Value>` (Task 5) |
| `List<CleanProgress>` riempita da un `IProgress` sincrono | `Recorder<CleanProgress>` del piano 1 e `progress: reports.append` |
| `.Order()` su tuple `(Repository, Tag)` | struct `Found: Equatable` e ordinamento esplicito (`nil` per primo) |
| confronto di un `Int64?` con un prodotto di letterali | `Int64(8 * 1024)`: senza la conversione l'espansione di `#expect` confronta tipi diversi e fallisce anche con valori uguali (misurato) |

### Fatti misurati (2026-10-13) che il porting replica

Misurati con una console .NET 10 usa e getta e con un harness che esegue il `MjmCleaner.Core` reale sugli stessi input dei test solo-Swift; nessuno dei due è nel repository.

.NET 10:

- `$` senza `Multiline` corrisponde alla fine o prima di un `\n` finale (`^sha256:[0-9a-f]{64}$` accetta `"sha256:…\n"`); `.` esclude solo `\n`; con `Multiline` `^` vale solo all'inizio e dopo `\n`, e `\s*` dopo `name:` prosegue sulla riga seguente.
- `\w` = categorie L, Mn, Nd, Pc del piano base, mai un carattere supplementare (le due unità surrogate non sono lettere); il confine `\b` tratta come lettere anche U+200C e U+200D; `\s` = White_Space = `char.IsWhiteSpace`; `\d` = Nd.
- `IgnoreCase` delle regex generate (cultura invariante): ogni lettera ASCII equivale solo alla propria maiuscola o minuscola, più U+212A (segno Kelvin) per la "k". U+0130 non equivale a "i", U+017F non equivale a "s". Una `new Regex(…, IgnoreCase)` nella cultura corrente equipara invece "i" e U+0130: le regex del C# sono tutte generate.
- `ToLowerInvariant` usa la mappatura semplice per carattere: 1487 scalari cambiano, U+0130 resta.
- `decimal.TryParse` + `Math.Round` arrotondano al pari ("2.5B" vale 2, "0.5B" vale 0); il cast a `long` di un valore oltre Int64 lancia `OverflowException` ("99999999999PB").
- `long.TryParse(…, NumberStyles.None, …)` rifiuta segno e cifre non ASCII; `Split(separatori, 2, RemoveEmptyEntries)` salta i separatori iniziali.
- `JsonElement.GetInt64`/`GetInt32` su un numero non intero o fuori intervallo lanciano `FormatException`; `TryGetProperty` su un elemento che non è un oggetto lancia `InvalidOperationException`; `ToDictionary` su etichette con chiavi duplicate lancia `ArgumentException`. Nessuna delle tre è una `DockerOutputException`.
- `File.ReadAllText` toglie il BOM UTF-8, decodifica UTF-16 e UTF-32 dal BOM e sostituisce con U+FFFD le sequenze non valide o tronche.

Swift 6.4:

- `Regex` non è `Sendable`: una `static let` di tipo `Regex` non compila in Swift 6.
- `$` vale solo alla fine del testo; `.` esclude anche `\r`, `\v`, `\f`, U+0085, U+2028 e U+2029, e `anchorsMatchLineEndings()` scatta anche dopo ciascuno di essi; il `\b` predefinito segue UAX #29 (in "5MB.x" non vede un confine dopo la "B").
- Con `.unicodeScalar`, `\w` e `\d` di Swift non coincidono con quelli di .NET (`\d` comprende "²", `\w` esclude molte Mn e Nd). La classe `[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]` coincide con `\w` di .NET, e il confine di `DockerSize` con il suo `\b`, salvo 35 punti di codice assegnati in Unicode dopo i dati di .NET 10 (confronto esaustivo sul piano base).
- `.ignoresCase()` coincide con l'`IgnoreCase` invariante di .NET su tutte le lettere ASCII: confronto esaustivo sul piano base con una `new Regex` di .NET, unica differenza U+0130 per la "i", che le regex generate non equiparano (verificato sul C# reale).
- `lowercaseMapping`, preso quando è di un solo scalare, coincide con `ToLowerInvariant` su tutti gli scalari; `Unicode.Scalar.Properties.isWhitespace` coincide con `char.IsWhiteSpace`.
- `JSONDecoder` accetta i frammenti JSON al primo livello e, con chiavi duplicate, tiene la prima.

---

## Mappa dei file

```
swift/MjmCleanerKit/
├── Package.swift                                                       Task 2 (exclude delle fixture)
├── Sources/CleanerCore/Docker/
│   ├── DockerText.swift  DockerModels.swift  DockerSize.swift  ImageName.swift      Task 1
│   ├── DockerJson.swift                                                             Task 2
│   ├── ImageRules.swift  VolumeRules.swift  DockerClassifier.swift                  Task 3
│   ├── DockerConfirmationGroups.swift                                               Task 4
│   ├── DockerCli.swift                                                              Task 5
│   ├── DockerInventoryCollector.swift                                               Task 6
│   ├── DiskUsageProbe.swift                                                         Task 7
│   ├── ProjectReferenceScanner.swift                                                Task 8
│   ├── DockerCleanExecutor.swift                                                    Task 9
│   └── DockerCleanupService.swift                                                   Task 10
└── Tests/CleanerCoreTests/Docker/
    ├── DockerTextTests.swift  DockerSizeTests.swift  ImageNameTests.swift           Task 1
    ├── Fixtures/ (5 file copiati dal C#)  DockerFixtures.swift  DockerJsonTests.swift   Task 2
    ├── DockerClassifierTests.swift                                                  Task 3
    ├── DockerConfirmationGroupsTests.swift                                          Task 4
    ├── FakeDockerCli.swift (con Shared)  DockerCliTests.swift                       Task 5
    ├── DockerInventoryCollectorTests.swift                                          Task 6
    ├── DiskUsageProbeTests.swift                                                    Task 7
    ├── ProjectReferenceScannerTests.swift                                           Task 8
    ├── DockerCleanExecutorTests.swift                                               Task 9
    └── DockerCleanupServiceTests.swift                                              Task 10
docs/superpowers/porting/2026-10-13-parity.md                                      ogni task; chiusura nel Task 11
```

Ogni file Swift porta il file C# con lo stesso nome. `DockerText.swift` è nuovo: raccoglie i metodi .NET sul testo. Come in C#, `DockerOutputError` e `DockerDfVerbose` stanno in `DockerJson.swift`; gli errori della CLI, `DockerCliErrors` e `DockerBinaryLocator` in `DockerCli.swift`; `DockerCategories` e `DockerCleanResult` in `DockerCleanExecutor.swift`; `DockerAnalysis` in `DockerCleanupService.swift`. `ProcessRunner.cs` è già portato (`Platform/ProcessRunner.swift`, piano 1). Tutti i comandi dei task si eseguono da `swift/MjmCleanerKit`, salvo `cp`, `diff`, `git` (dalla radice del repository).

---

### Task 1: Modelli, `DockerText`, `DockerSize`, `ImageName`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerText.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerModels.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerSize.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/ImageName.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerTextTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerSizeTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/ImageNameTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerModels.cs`, `DockerSize.cs`, `ImageName.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerSizeTests.cs`, `ImageNameTests.cs`

**Interfaces:**
- Consumes (piano 1): `PathText.fileName(_:) -> String`, `PathText.folded(_:) -> String` (interna al modulo).
- Produces:
  - `enum DockerText` (interna) — `lines(_: String) -> [String]`, `rawLines(_: String) -> [Substring]`, `trimmed(_: String) -> String`, `trimmed(_: String, _: Unicode.Scalar) -> String`, `trimmedLeading(_:_:) -> String`, `trimmedTrailing(_:_:) -> String`, `isBlank(_: String?) -> Bool`, `contains(_:_:) -> Bool`, `containsIgnoringCase(_:_:) -> Bool`, `hasPrefix(_:_:) -> Bool`, `hasSuffix(_:_:) -> Bool`, `hasSuffixIgnoringCase(_:_:) -> Bool`, `distinct(_: [String]) -> [String]`, `ordinalSorted(_: some Sequence<String>) -> [String]`, `lowercasedInvariant(_: String) -> String`, `decodeLikeReadAllText(_: Data) -> String`, `lineStarts(_: String) -> [String.Index]`
  - `public enum DockerVerdict { case keep, delete, propose, ask }`, `public enum DockerResourceKind { case image, volume, buildCache }`, `public enum ImageOrigin { case unknown, pulled, built }` — tutti `Sendable, Equatable, Hashable`
  - `public struct DockerContainer` — `id`, `name`, `imageId`, `state: String`, `exitCode: Int`, `volumeNames: [String]`, `labels: [String: String]`; `init(id:name:imageId:state:exitCode:volumeNames:labels:)`
  - `public struct DockerImage` — `id`, `repoTags`, `repoDigests`, `sizeBytes: Int64`, `uniqueSizeBytes: Int64?`, `labels`, `origin`; `init(id:repoTags:repoDigests:sizeBytes:uniqueSizeBytes:labels:origin:)`; `isDangling`, `names: [ImageName]`, `displayName`; `static func shortId(_:) -> String`
  - `public struct DockerVolume` — `name`, `labels`, `sizeBytes: Int64?`; `init(name:labels:sizeBytes:)`
  - `public struct DockerDfEntry` — `type`, `sizeBytes`, `reclaimableBytes: Int64`; `init(type:sizeBytes:reclaimableBytes:)`
  - `public struct DockerDfSummary` — `entries`; `static let imagesType`, `volumesType`, `buildCacheType`, `empty`; `init(entries:)`; `images`, `volumes`, `buildCache`, `total`, `sizeOf(_:) -> Int64`
  - `public struct DockerSnapshot` — `var containers`, `images`, `volumes`, `df`, `existingComposeProjects: Set<String>`; `init(containers:images:volumes:df:existingComposeProjects:)`
  - `public struct DockerCandidate: Hashable` — `kind`, `id`, `displayName`, `sizeBytes: Int64?`, `verdict`, `ruleId`, `reason`, `cost`; `init(kind:id:displayName:sizeBytes:verdict:ruleId:reason:cost:)`; `selectedByDefault`
  - `public struct ImageReference: Hashable` — `repository`, `tag: String?`, `file`, `line: Int`; `init(repository:tag:file:line:)`
  - `public struct ProjectReferences` — `images: [ImageReference]`, `composeProjects: Set<String>`; `static let empty`; `init(images:composeProjects:)`
  - `public enum DockerSize` — `static func parse(_: String?) -> Int64?`
  - `public struct ImageName: Hashable` — `repository`, `tag: String?`, `shortName`; `init(repository:tag:)`; `static func parse(_: String) -> ImageName`

- [ ] **Step 1: Scrivere i test (falliscono)**

`DockerTextTests` è solo-Swift: fissa le equivalenze con i metodi .NET su cui si appoggiano tutti i task seguenti. `DockerSizeTests` porta le due prove C# e ne aggiunge una solo-Swift sul confine di parola e sull'arrotondamento, con gli esiti del C# reale.

`Tests/CleanerCoreTests/Docker/DockerTextTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

/// Solo Swift: le equivalenze con i metodi .NET su cui si appoggia il porting di Docker, misurate
/// su .NET 10 durante la stesura del piano 2.
struct DockerTextTests {
    @Test func linesSplitOnlyOnNewlineAndTrimUnicodeWhitespace() {
        // `Split('\n', RemoveEmptyEntries | TrimEntries)`: "\r" e U+2028 non dividono, `Trim` li toglie.
        #expect(DockerText.lines("a\r\nb\n\n c \u{2028}x\n \u{A0}\n") == ["a", "b", "c \u{2028}x"])
        #expect(DockerText.rawLines("a\n\nb\n").map(String.init) == ["a", "", "b", ""])
        // U+FEFF e U+200B non sono spazi per `char.IsWhiteSpace`.
        #expect(DockerText.trimmed("\u{FEFF}x\u{200B}") == "\u{FEFF}x\u{200B}")
        #expect(DockerText.trimmed("\"\"29.8.0\"", "\"") == "29.8.0")
    }

    @Test func ordinalComparisonsWorkOnBytesNotGraphemes() {
        // Uno scalare «prepend» (U+0600) si fonde con il "/" in un solo grafema: per `String` di
        // Swift il suffisso non c'è, per `EndsWith(Ordinal)` di .NET sì.
        #expect(DockerText.hasSuffix("x\u{600}/testcontainers/ryuk", "/testcontainers/ryuk"))
        #expect(DockerText.hasPrefix("dcptun_\u{301}x", "dcptun_"))
        #expect(DockerText.contains("abc;\u{301}def", ";"))
        #expect(!DockerText.contains("ab", "abc"))
        #expect(DockerText.containsIgnoringCase("Error: CANNOT CONNECT to the Docker daemon", "cannot connect"))
        #expect(!DockerText.containsIgnoringCase("\u{131}", "I"))
        #expect(DockerText.hasSuffixIgnoringCase("Program.CS", ".cs"))
    }

    @Test func distinctAndOrderAreOrdinal() {
        // NFC e NFD dello stesso testo sono distinti per `StringComparer.Ordinal`.
        #expect(DockerText.distinct(["e\u{301}", "\u{E9}", "e\u{301}"]) == ["e\u{301}", "\u{E9}"])
        // Ordine per unità UTF-16: U+10000 (D800 DC00) precede U+FF61.
        #expect(DockerText.ordinalSorted(["\u{FF61}", "\u{10000}", "B", "a"]) == ["B", "a", "\u{10000}", "\u{FF61}"])
    }

    @Test func lowercasedInvariantUsesTheSimpleMapping() {
        // U+0130 resta (la sua minuscola completa è di due scalari); il segno Kelvin diventa "k".
        #expect(DockerText.lowercasedInvariant("\u{C0}B\u{130}\u{212A}\u{10400}") == "\u{E0}b\u{130}k\u{10428}")
    }

    // Gli esiti di `File.ReadAllText` misurati su .NET 10 con gli stessi byte.
    @Test(arguments: [
        ([0xEF, 0xBB, 0xBF, 0x6E, 0x61] as [UInt8], "na"),
        ([0xFF, 0xFE, 0x6E, 0x00, 0x61, 0x00], "na"),
        ([0xFE, 0xFF, 0x00, 0x6E, 0x00, 0x61], "na"),
        ([0xFF, 0xFE, 0x00, 0x00, 0x6E, 0x00, 0x00, 0x00], "n"),
        ([0xFF, 0xFE, 0x6E, 0x00, 0x61], "n\u{FFFD}"),
        ([0xFF, 0xFE, 0x00, 0x00, 0x6E, 0x00, 0x00, 0x00, 0x61], "n\u{FFFD}"),
        ([0x6E, 0xFF], "n\u{FFFD}"),
        ([0x6E, 0xE2, 0x82], "n\u{FFFD}"),
    ])
    func fileContentsAreDecodedLikeReadAllText(bytes: [UInt8], expected: String) {
        #expect(DockerText.decodeLikeReadAllText(Data(bytes)) == expected)
    }

    @Test func lineStartsFollowTheDotNetMultilineAnchor() {
        let text = "a\rb\u{2028}c\nd\n"
        let starts = DockerText.lineStarts(text).map { String(text[$0...]) }
        #expect(starts == ["a\rb\u{2028}c\nd\n", "d\n", ""])
    }
}
```

`Tests/CleanerCoreTests/Docker/DockerSizeTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DockerSizeTests {
    @Test(arguments: [
        ("0B", Int64(0)),
        ("57.3kB", 57_300),
        ("1.131kB", 1_131),
        ("195MB", 195_000_000),
        ("2.42GB", 2_420_000_000),
        ("1.5TB", 1_500_000_000_000),
        ("76.74MB (2%)", 76_740_000),
        (" 106.9MB ", 106_900_000),
    ])
    func parsesTheDecimalUnitsPrintedByDocker(text: String, expected: Int64) {
        #expect(DockerSize.parse(text) == expected)
    }

    @Test(arguments: ["N/A", "", nil, "molto"] as [String?])
    func returnsNullWhenTheSizeIsUnknown(text: String?) {
        #expect(DockerSize.parse(text) == nil)
    }

    // Solo Swift: il confine di parola dopo l'unità e l'arrotondamento seguono .NET 10, misurato
    // durante la stesura del piano 2 ("5MB.x" e "5MBⅫ" valgono 5 MB; "5MBx", "5MB" + U+0301 e
    // "5MB" + U+200D non sono dimensioni; 2.5 B si arrotonda al pari).
    @Test(arguments: [
        ("5MB.x", Int64(5_000_000) as Int64?),
        ("5MB\u{216B}", 5_000_000),
        ("5MB\u{1D400}", 5_000_000),
        ("5MBx", nil),
        ("5MB_", nil),
        ("5MB\u{301}", nil),
        ("5MB\u{200D}", nil),
        ("2.5B", 2),
        ("3.5B", 4),
        ("\u{663}MB", nil),
    ])
    func wordBoundaryAndRoundingFollowDotNet(text: String, expected: Int64?) {
        #expect(DockerSize.parse(text) == expected)
    }
}
```

`Tests/CleanerCoreTests/Docker/ImageNameTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct ImageNameTests {
    @Test(arguments: [
        ("alpine:3.20", "docker.io/library/alpine", "3.20" as String?),
        ("docker.io/library/alpine:3.20", "docker.io/library/alpine", "3.20"),
        ("testcontainers/ryuk:0.14.0", "docker.io/testcontainers/ryuk", "0.14.0"),
        ("mcr.microsoft.com/mssql/server:2025-latest", "mcr.microsoft.com/mssql/server", "2025-latest"),
        ("localhost:5000/app:1", "localhost:5000/app", "1"),
        ("localhost/app", "localhost/app", nil),
        ("quay.io/keycloak/keycloak", "quay.io/keycloak/keycloak", nil),
        ("redis@sha256:abc", "docker.io/library/redis", nil),
        ("redis:7@sha256:abc", "docker.io/library/redis", "7"),
        ("Dcptun_Developer_MS:0.25.13", "docker.io/library/dcptun_developer_ms", "0.25.13"),
    ])
    func normalizesRepositoryAndSeparatesTheTag(reference: String, repository: String, tag: String?) {
        let name = ImageName.parse(reference)

        #expect(name.repository == repository)
        #expect(name.tag == tag)
    }

    @Test func shortNameIsTheLastRepositorySegment() {
        #expect(ImageName.parse("testcontainers/ryuk:0.14.0").shortName == "ryuk")
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "DockerTextTests|DockerSizeTests|ImageNameTests"`
Expected: errore di compilazione `cannot find 'ImageName' in scope`, oppure lo stesso errore per `DockerText` o `DockerSize`: il compilatore si ferma al primo file di test che non compila.

- [ ] **Step 3: Implementare `DockerText`**

`Sources/CleanerCore/Docker/DockerText.swift`:

```swift
import Foundation

/// Operazioni sul testo di Docker (output della CLI, nomi, file dei progetti) con la semantica dei
/// metodi .NET che il C# usava: `Split`/`Trim` sui caratteri, confronti `Ordinal` e
/// `OrdinalIgnoreCase`, `ToLowerInvariant`, `File.ReadAllText`. Lavorano su scalari e byte UTF-8,
/// mai sui `Character` di Swift: un segno combinante o uno scalare «prepend» formerebbero con il
/// separatore un solo grafema e lo nasconderebbero (registro decisioni del piano 1, Task 4).
enum DockerText {
    /// `text.Split('\n', RemoveEmptyEntries | TrimEntries)`: divide solo su "\n" (un "\r\n" lascia
    /// "\r", che `Trim` toglie), toglie gli spazi Unicode ai lati e scarta le righe vuote.
    static func lines(_ text: String) -> [String] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimmed(String(Substring($0))) }
            .filter { !$0.isEmpty }
    }

    /// `text.Split('\n')` senza opzioni: anche le righe vuote, anche l'ultima.
    static func rawLines(_ text: String) -> [Substring] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { Substring($0) }
    }

    /// `string.Trim()`: toglie ai lati gli scalari con la proprietà White_Space, lo stesso insieme
    /// di `char.IsWhiteSpace` (verificato su tutti gli scalari del piano base).
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
              let last = scalars.lastIndex(where: { !$0.properties.isWhitespace }) else { return "" }
        return String(scalars[first...last])
    }

    /// `string.Trim(character)`: toglie ai lati tutte le ripetizioni di un solo carattere.
    static func trimmed(_ text: String, _ character: Unicode.Scalar) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { $0 != character }),
              let last = scalars.lastIndex(where: { $0 != character }) else { return "" }
        return String(scalars[first...last])
    }

    /// `string.TrimStart(character)`.
    static func trimmedLeading(_ text: String, _ character: Unicode.Scalar) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { $0 != character }) else { return "" }
        return String(scalars[first...])
    }

    /// `string.TrimEnd(character)`.
    static func trimmedTrailing(_ text: String, _ character: Unicode.Scalar) -> String {
        let scalars = text.unicodeScalars
        guard let last = scalars.lastIndex(where: { $0 != character }) else { return "" }
        return String(scalars[...last])
    }

    /// `IsNullOrWhiteSpace`.
    static func isBlank(_ text: String?) -> Bool {
        text?.unicodeScalars.allSatisfy(\.properties.isWhitespace) ?? true
    }

    /// `Contains(needle, StringComparison.Ordinal)`, sui byte UTF-8: per testi validi l'esito
    /// coincide con il confronto per unità UTF-16 di .NET.
    static func contains(_ text: String, _ needle: String) -> Bool {
        var remainder = text.utf8[...]
        while true {
            if remainder.starts(with: needle.utf8) { return true }
            if remainder.isEmpty { return false }
            remainder = remainder.dropFirst()
        }
    }

    /// `Contains(needle, StringComparison.OrdinalIgnoreCase)`: lo stesso ripiegamento di `PathText`.
    static func containsIgnoringCase(_ text: String, _ needle: String) -> Bool {
        contains(PathText.folded(text), PathText.folded(needle))
    }

    /// `StartsWith(prefix, StringComparison.Ordinal)`.
    static func hasPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// `EndsWith(suffix, StringComparison.Ordinal)`.
    static func hasSuffix(_ text: String, _ suffix: String) -> Bool {
        text.utf8.reversed().starts(with: suffix.utf8.reversed())
    }

    /// `EndsWith(suffix, StringComparison.OrdinalIgnoreCase)`.
    static func hasSuffixIgnoringCase(_ text: String, _ suffix: String) -> Bool {
        hasSuffix(PathText.folded(text), PathText.folded(suffix))
    }

    /// `Distinct(StringComparer.Ordinal)`: conserva la prima occorrenza e l'ordine. La chiave sono i
    /// byte UTF-8, non `String`: l'equivalenza canonica di Swift unirebbe valori che .NET distingue.
    static func distinct(_ values: [String]) -> [String] {
        var seen = Set<[UInt8]>()
        return values.filter { seen.insert(Array($0.utf8)).inserted }
    }

    /// `Order(StringComparer.Ordinal)`: per unità UTF-16, come .NET.
    static func ordinalSorted(_ values: some Sequence<String>) -> [String] {
        values.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
    }

    /// `ToLowerInvariant`: mappatura semplice scalare per scalare, lunghezza invariata. Coincide con
    /// .NET 10 su tutti gli scalari (1487 mappature, confronto esaustivo durante la stesura del
    /// piano 2): dove la minuscola completa è di più scalari (per esempio U+0130) lo scalare resta.
    static func lowercasedInvariant(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let lower = scalar.properties.lowercaseMapping.unicodeScalars
            if lower.count == 1, let mapped = lower.first {
                scalars.append(mapped)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// Il contenuto di un file come `File.ReadAllText`: UTF-8 salvo un BOM che indichi UTF-16 o
    /// UTF-32; il BOM non fa parte del testo. Le sequenze non valide diventano U+FFFD.
    static func decodeLikeReadAllText(_ data: Data) -> String {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
            return decodeUTF32(bytes.dropFirst(4), bigEndian: false)
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return decodeUTF32(bytes.dropFirst(4), bigEndian: true)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            return decodeUTF16(bytes.dropFirst(2), bigEndian: false)
        }
        if bytes.starts(with: [0xFE, 0xFF]) {
            return decodeUTF16(bytes.dropFirst(2), bigEndian: true)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: bytes.dropFirst(3), as: UTF8.self)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        var units: [UInt16] = []
        var iterator = bytes.makeIterator()
        while let first = iterator.next() {
            guard let second = iterator.next() else {
                // Byte dispari in fondo: .NET lo sostituisce con U+FFFD.
                units.append(0xFFFD)
                break
            }
            units.append(bigEndian ? UInt16(first) << 8 | UInt16(second) : UInt16(second) << 8 | UInt16(first))
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func decodeUTF32(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        var units: [UInt32] = []
        var group: [UInt8] = []
        for byte in bytes {
            group.append(byte)
            guard group.count == 4 else { continue }
            let ordered = bigEndian ? group : group.reversed()
            units.append(ordered.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            group.removeAll()
        }
        if !group.isEmpty { units.append(0xFFFD) }
        return String(decoding: units, as: UTF32.self)
    }

    /// Le posizioni in cui un'ancora `^` di .NET con `RegexOptions.Multiline` può corrispondere:
    /// l'inizio del testo e ogni scalare dopo un "\n". Le ancore di riga di Swift scattano anche
    /// dopo "\r", "\u{B}", "\u{C}", U+0085, U+2028 e U+2029.
    static func lineStarts(_ text: String) -> [String.Index] {
        var starts = [text.startIndex]
        var index = text.unicodeScalars.startIndex
        for scalar in text.unicodeScalars {
            index = text.unicodeScalars.index(after: index)
            if scalar == "\n" { starts.append(index) }
        }
        return starts
    }
}
```

- [ ] **Step 4: Implementare i modelli**

`Sources/CleanerCore/Docker/DockerModels.swift`:

```swift
public enum DockerVerdict: Sendable, Equatable, Hashable {
    case keep
    case delete
    case propose
    case ask
}

public enum DockerResourceKind: Sendable, Equatable, Hashable {
    case image
    case volume
    case buildCache
}

/// Da dove viene un'immagine. Con il containerd image store `RepoDigests` è valorizzato anche per
/// le immagini costruite in locale: l'origine si legge da `.Identity`.
public enum ImageOrigin: Sendable, Equatable, Hashable {
    case unknown
    case pulled
    case built
}

/// Un container, anche fermo: un container fermo tiene in uso immagine e volumi quanto uno attivo.
public struct DockerContainer: Sendable, Equatable, Hashable {
    public let id: String
    public let name: String
    public let imageId: String
    public let state: String
    public let exitCode: Int
    public let volumeNames: [String]
    public let labels: [String: String]

    public init(id: String, name: String, imageId: String, state: String, exitCode: Int, volumeNames: [String], labels: [String: String]) {
        self.id = id
        self.name = name
        self.imageId = imageId
        self.state = state
        self.exitCode = exitCode
        self.volumeNames = volumeNames
        self.labels = labels
    }
}

public struct DockerImage: Sendable, Equatable, Hashable {
    /// Il segnaposto che Docker mostra al posto di un tag assente.
    static let noTag = "<none>:<none>"

    public let id: String
    public let repoTags: [String]
    public let repoDigests: [String]
    public let sizeBytes: Int64
    public let uniqueSizeBytes: Int64?
    public let labels: [String: String]
    public let origin: ImageOrigin

    public init(
        id: String,
        repoTags: [String],
        repoDigests: [String],
        sizeBytes: Int64,
        uniqueSizeBytes: Int64?,
        labels: [String: String],
        origin: ImageOrigin
    ) {
        self.id = id
        self.repoTags = repoTags
        self.repoDigests = repoDigests
        self.sizeBytes = sizeBytes
        self.uniqueSizeBytes = uniqueSizeBytes
        self.labels = labels
        self.origin = origin
    }

    /// Senza tag, o con il solo segnaposto "<none>:<none>".
    public var isDangling: Bool { repoTags.allSatisfy { $0 == Self.noTag } }

    public var names: [ImageName] { repoTags.filter { $0 != Self.noTag }.map(ImageName.parse) }

    public var displayName: String { repoTags.first { $0 != Self.noTag } ?? Self.shortId(id) }

    /// Le prime 12 cifre dell'identificativo, senza "sha256:". La lunghezza si conta in unità
    /// UTF-16 come `string.Length` (gli ID di Docker sono esadecimali ASCII).
    public static func shortId(_ id: String) -> String {
        let hex = DockerText.hasPrefix(id, "sha256:") ? String(decoding: id.utf8.dropFirst(7), as: UTF8.self) : id
        return hex.utf16.count > 12 ? String(decoding: Array(hex.utf16.prefix(12)), as: UTF16.self) : hex
    }
}

public struct DockerVolume: Sendable, Equatable, Hashable {
    public let name: String
    public let labels: [String: String]
    public let sizeBytes: Int64?

    public init(name: String, labels: [String: String], sizeBytes: Int64?) {
        self.name = name
        self.labels = labels
        self.sizeBytes = sizeBytes
    }
}

/// Una riga di `docker system df`: "Images", "Containers", "Local Volumes", "Build Cache".
public struct DockerDfEntry: Sendable, Equatable, Hashable {
    public let type: String
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64

    public init(type: String, sizeBytes: Int64, reclaimableBytes: Int64) {
        self.type = type
        self.sizeBytes = sizeBytes
        self.reclaimableBytes = reclaimableBytes
    }
}

public struct DockerDfSummary: Sendable, Equatable, Hashable {
    public static let imagesType = "Images"
    public static let volumesType = "Local Volumes"
    public static let buildCacheType = "Build Cache"

    public static let empty = DockerDfSummary(entries: [])

    public let entries: [DockerDfEntry]

    public init(entries: [DockerDfEntry]) {
        self.entries = entries
    }

    public var images: Int64 { sizeOf(Self.imagesType) }
    public var volumes: Int64 { sizeOf(Self.volumesType) }
    public var buildCache: Int64 { sizeOf(Self.buildCacheType) }
    public var total: Int64 { entries.reduce(0) { $0 + $1.sizeBytes } }

    public func sizeOf(_ type: String) -> Int64 {
        entries.first { $0.type == type }?.sizeBytes ?? 0
    }
}

/// Tutto ciò che la classificazione deve sapere, raccolto una volta sola. Privo di dipendenze dalla
/// CLI: le regole lo leggono senza poter lanciare comandi né toccare il disco. I campi sono `var`
/// per replicare l'espressione `with` dei record C# nei test: la struct resta un valore.
///
/// `existingComposeProjects`: progetti compose la cui cartella esiste ancora, verificato dal
/// collector (la verifica su disco è I/O, quindi non può stare nelle regole).
public struct DockerSnapshot: Sendable, Equatable {
    public var containers: [DockerContainer]
    public var images: [DockerImage]
    public var volumes: [DockerVolume]
    public var df: DockerDfSummary
    public var existingComposeProjects: Set<String>

    public init(
        containers: [DockerContainer],
        images: [DockerImage],
        volumes: [DockerVolume],
        df: DockerDfSummary,
        existingComposeProjects: Set<String>
    ) {
        self.containers = containers
        self.images = images
        self.volumes = volumes
        self.df = df
        self.existingComposeProjects = existingComposeProjects
    }
}

/// Esito della classificazione di una singola risorsa: cosa fare, perché, e quanto costa ricrearla.
public struct DockerCandidate: Sendable, Equatable, Hashable {
    public let kind: DockerResourceKind
    public let id: String
    public let displayName: String
    public let sizeBytes: Int64?
    public let verdict: DockerVerdict
    public let ruleId: String
    public let reason: String
    public let cost: String

    public init(
        kind: DockerResourceKind,
        id: String,
        displayName: String,
        sizeBytes: Int64?,
        verdict: DockerVerdict,
        ruleId: String,
        reason: String,
        cost: String
    ) {
        self.kind = kind
        self.id = id
        self.displayName = displayName
        self.sizeBytes = sizeBytes
        self.verdict = verdict
        self.ruleId = ruleId
        self.reason = reason
        self.cost = cost
    }

    /// Solo le voci sicure (DELETE) partono selezionate. PROPOSE e ASK richiedono un gesto esplicito
    /// dell'utente; KEEP non è mai selezionabile.
    public var selectedByDefault: Bool { verdict == .delete }
}

/// Un'immagine citata in un file di progetto. `tag` nullo: il file nomina solo il repository.
public struct ImageReference: Sendable, Equatable, Hashable {
    public let repository: String
    public let tag: String?
    public let file: String
    public let line: Int

    public init(repository: String, tag: String?, file: String, line: Int) {
        self.repository = repository
        self.tag = tag
        self.file = file
        self.line = line
    }
}

/// Ciò che la ricerca nei progetti ha trovato: immagini citate e progetti compose esistenti.
public struct ProjectReferences: Sendable, Equatable {
    public static let empty = ProjectReferences(images: [], composeProjects: [])

    public let images: [ImageReference]
    public let composeProjects: Set<String>

    public init(images: [ImageReference], composeProjects: Set<String>) {
        self.images = images
        self.composeProjects = composeProjects
    }
}
```

- [ ] **Step 5: Implementare `DockerSize` e `ImageName`**

`Sources/CleanerCore/Docker/DockerSize.swift`:

```swift
import Foundation

/// Converte le dimensioni testuali stampate dalla CLI ("195MB", "1.131kB", "76.74MB (2%)").
/// Docker usa unità DECIMALI (go-units HumanSize: 1 kB = 1000 B), non binarie: interpretarle come
/// potenze di 1024 gonfierebbe del 7% ogni dimensione in GB mostrata all'utente.
public enum DockerSize {
    /// `nil` per "N/A", vuoto o testo non riconosciuto: una dimensione ignota non è zero.
    public static func parse(_ text: String?) -> Int64? {
        guard let text, !DockerText.isBlank(text) else { return nil }

        // Porting di `^\s*(?<value>\d+(?:\.\d+)?)\s*(?<unit>[kKMGTP]?B)\b` di .NET:
        // - `[0-9]` al posto di `\d`: .NET accetta anche le cifre non ASCII, ma poi
        //   `decimal.TryParse` le rifiuta, quindi l'esito è comunque nullo;
        // - `\b` dopo una "B" diventa «il carattere seguente non è una lettera di parola di .NET»:
        //   lettere (L), segni Mn, cifre Nd, connettori Pc, U+200C e U+200D, solo nel piano base
        //   (.NET confronta unità UTF-16 e un surrogato non è mai lettera). Il `\b` di Swift segue
        //   regole diverse, anche con `.wordBoundaryKind(.simple)`.
        let pattern = /^\s*(?<value>[0-9]+(?:\.[0-9]+)?)\s*(?<unit>[kKMGTP]?B)(?![[\p{L}\p{Mn}\p{Nd}\p{Pc}\u{200C}\u{200D}]&&[\x{0}-\x{FFFF}]])/
            .matchingSemantics(.unicodeScalar)

        guard let match = text.firstMatch(of: pattern),
              let value = Decimal(string: String(match.output.value), locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }

        var product = value * Decimal(multiplier(String(match.output.unit)))
        var rounded = Decimal()
        // `Math.Round(decimal)` di .NET arrotonda al pari (MidpointRounding.ToEven).
        NSDecimalRound(&rounded, &product, 0, .bankers)
        // Oltre Int64 il C# lanciava OverflowException dal cast: qui la dimensione resta ignota.
        return Int64(rounded.description)
    }

    /// La tabella `B`/`kB`/`MB`/`GB`/`TB`/`PB` del C#, senza distinzione fra maiuscole e minuscole.
    private static func multiplier(_ unit: String) -> Int64 {
        switch unit.utf8.first {
        case UInt8(ascii: "k"), UInt8(ascii: "K"): 1_000
        case UInt8(ascii: "M"): 1_000_000
        case UInt8(ascii: "G"): 1_000_000_000
        case UInt8(ascii: "T"): 1_000_000_000_000
        case UInt8(ascii: "P"): 1_000_000_000_000_000
        default: 1
        }
    }
}
```

`Sources/CleanerCore/Docker/ImageName.swift`:

```swift
/// Riferimento a un'immagine ridotto a repository normalizzato e tag. Docker mostra lo stesso
/// repository in forme diverse ("alpine", "docker.io/library/alpine"): confrontare le stringhe
/// grezze farebbe sembrare diverse due immagini identiche, e una regola come "versione superata" o
/// "citata nei progetti" non scatterebbe mai.
public struct ImageName: Sendable, Equatable, Hashable {
    private static let defaultRegistry = "docker.io"

    public let repository: String
    public let tag: String?

    public init(repository: String, tag: String?) {
        self.repository = repository
        self.tag = tag
    }

    /// Ultimo segmento del repository: "testcontainers/ryuk" → "ryuk".
    public var shortName: String { PathText.fileName(repository) }

    /// I separatori "@", ":" e "/" sono ASCII: si cercano e si taglia sui byte UTF-8, come gli
    /// `IndexOf`/`LastIndexOf` del C# sulle unità UTF-16.
    public static func parse(_ reference: String) -> ImageName {
        var value = Array(DockerText.trimmed(reference).utf8)

        // Il digest identifica il contenuto, non il nome: per il confronto conta solo repository:tag.
        if let at = value.firstIndex(of: UInt8(ascii: "@")) {
            value = Array(value.prefix(upTo: at))
        }

        // Il tag è dopo l'ultimo ":" che segue l'ultimo "/": in "localhost:5000/app" i due punti
        // appartengono al registro, non al tag.
        var tag: String?
        let slash = value.lastIndex(of: UInt8(ascii: "/")) ?? -1
        if let colon = value.lastIndex(of: UInt8(ascii: ":")), colon > slash {
            tag = String(decoding: value.suffix(from: colon + 1), as: UTF8.self)
            value = Array(value.prefix(upTo: colon))
        }

        let repository = normalizeRepository(String(decoding: value, as: UTF8.self))
        return ImageName(repository: repository, tag: tag?.isEmpty == false ? tag : nil)
    }

    private static func normalizeRepository(_ repository: String) -> String {
        let lower = DockerText.lowercasedInvariant(repository)
        let bytes = Array(lower.utf8)

        guard let slash = bytes.firstIndex(of: UInt8(ascii: "/")) else {
            return "\(defaultRegistry)/library/\(lower)"
        }

        let first = bytes.prefix(upTo: slash)
        let hasRegistry = first.contains(UInt8(ascii: "."))
            || first.contains(UInt8(ascii: ":"))
            || first.elementsEqual("localhost".utf8)

        return hasRegistry ? lower : "\(defaultRegistry)/\(lower)"
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "DockerTextTests|DockerSizeTests|ImageNameTests"`
Expected: `Test run with 11 tests … passed` (6 di `DockerTextTests`, 3 di `DockerSizeTests`, 2 di `ImageNameTests`), nessun warning.

- [ ] **Step 7: Registro di parità e commit**

In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire le righe `Docker/DockerSizeTests.cs` e `Docker/ImageNameTests.cs` con:

```markdown
| Docker/DockerSizeTests.cs | 2 (12) | Docker/DockerSizeTests.swift | 3 (22) | 2 | 2 (12) portati + 1 solo-Swift (`wordBoundaryAndRoundingFollowDotNet`, 10 casi: confine dopo l'unità e arrotondamento al pari, esiti del C# reale) |
| Docker/ImageNameTests.cs | 2 (10) | Docker/ImageNameTests.swift | 2 (10) | 2 | |
```

Nella tabella «Test solo Swift», aggiungere:

```markdown
| Docker/DockerTextTests.swift | 6 | equivalenze con i metodi .NET sul testo: `Split`, `Trim`, confronti `Ordinal` e `OrdinalIgnoreCase`, `Distinct`, `Order`, `ToLowerInvariant`, `File.ReadAllText`, ancora `^` multilinea |
```

Nella tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Testo di Docker e dei progetti | metodi .NET su unità UTF-16 (`Split`, `Trim`, `Contains`/`StartsWith`/`EndsWith` `Ordinal` e `OrdinalIgnoreCase`, `Distinct`, `Order`, `ToLowerInvariant`) | `DockerText` su scalari e byte UTF-8, con il ripiegamento di `PathText`; test solo-Swift in DockerTextTests | equivalente (White_Space e `ToLowerInvariant` confrontati su tutti gli scalari) |
| Dimensione Docker oltre Int64 (es. «99999999999PB») | `OverflowException` dal cast del decimal: analisi fallita | `nil`: dimensione ignota | accettata (valori irraggiungibili) |
| Chiavi di ID, nomi, tag ed etichette di Docker | `Dictionary`/`HashSet` con `StringComparer.Ordinal` | `[String: …]`/`Set<String>` (equivalenza canonica) | equivalente sui valori che Docker ammette (ID esadecimali, nomi e tag ASCII); le chiavi cercate nelle etichette e nei JSON non hanno forme canoniche alternative |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): add Docker models, text helpers, size and image name parsing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `DockerJson` e fixture del caso reale

Il parsing tollerante del C# legge i campi uno per uno e ignora quelli assenti, `null` o del tipo sbagliato: un `Codable` dichiarativo fallirebbe al primo campo inatteso. `JSONDecoder` produce quindi un albero (`DockerJsonValue`, le categorie di `JsonValueKind`) che si legge con le stesse funzioni di utilità del C# (`Child`, `String`, `Items`, `Strings`, `Labels`).

**Files:**
- Modify: `swift/MjmCleanerKit/Package.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/Fixtures/` (copia di `tests/MjmCleaner.Core.Tests/Docker/Fixtures/`)
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerJson.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerFixtures.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerJsonTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerJson.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerJsonTests.cs`, `DockerFixtures.cs`, `Fixtures/`

**Interfaces:**
- Consumes: i modelli, `DockerSize.parse(_:)`, `DockerText.lines`, `distinct`, `trimmedLeading` (Task 1).
- Produces:
  - `public struct DockerOutputError: Error, Equatable, Sendable, LocalizedError` — `message`; `init(_:)`
  - `public struct DockerDfVerbose` — `imageUniqueSizes: [String: Int64]`, `volumeSizes: [String: Int64]`; `init(imageUniqueSizes:volumeSizes:)`
  - `public enum DockerJson` — `static func parseContainers(_: String) throws -> [DockerContainer]`, `parseImages(_: String, uniqueSizes: [String: Int64]? = nil) throws -> [DockerImage]`, `parseVolumes(_: String, sizes: [String: Int64]? = nil) throws -> [DockerVolume]`, `parseDfVerbose(_: String) throws -> DockerDfVerbose`, `parseDfSummary(_: String) throws -> DockerDfSummary`, `parseLines(_: String) -> [String]`, `parseJsonLinesProperty(_: String, _ property: String) throws -> [String]` (lanciano solo `DockerOutputError`)
  - `enum DockerJsonValue: Decodable, Equatable` (interna)
  - test: `enum DockerFixtures` — gli ID del caso reale (`mssql2025Id`, `azuriteId`, `dcptunId`, `azureLinuxId`, `mssql2022Id`, `keycloakId`, `mssqlToolsId`, `alpineId`, `ryukId`, `localBuildId`), `anonymousVolume`, `static func read(_: String) throws -> String`, `static func snapshot(existingComposeProjects: Set<String> = []) throws -> DockerSnapshot`

- [ ] **Step 1: Escludere le fixture dal target di test**

Con `swift-tools-version: 6.2` un file non dichiarato dentro un target è un errore di SwiftPM (`found 5 file(s) which are unhandled; explicitly declare them as resources or exclude from the target`). Le fixture non vanno nel bundle dei test, si leggono dal sorgente: basta escluderle. Sostituire `Package.swift` con:

`Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MjmCleanerKit",
    defaultLocalization: "it",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
    ],
    targets: [
        // Module map verso la zlib di sistema: Foundation non sa scrivere gzip.
        .systemLibrary(name: "CZlib", path: "Sources/CZlib"),
        .target(
            name: "CleanerCore",
            dependencies: ["CZlib"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"],
            // Le fixture JSON di Docker si leggono dal sorgente dei test (`#filePath`), non da un
            // bundle: escluderle evita che SwiftPM le rifiuti come file non gestiti.
            exclude: ["Docker/Fixtures"]
        ),
    ]
)
```

- [ ] **Step 2: Copiare le fixture byte per byte**

Run (dalla radice del repository):

```bash
mkdir -p swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/Fixtures
cp tests/MjmCleaner.Core.Tests/Docker/Fixtures/* swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/Fixtures/
diff -r tests/MjmCleaner.Core.Tests/Docker/Fixtures swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/Fixtures && echo "fixture identiche"
```

Expected: `fixture identiche`; la cartella contiene `containers.json`, `df-verbose.json`, `df.jsonl`, `images.json`, `volumes.json`.

- [ ] **Step 3: Scrivere `DockerFixtures` e i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DockerFixtures.swift`:

```swift
import Foundation
@testable import CleanerCore

/// Il caso reale da cui è nata la funzione: due container fermi (exit code 137) di SQL Server e di
/// Azurite avviati da un AppHost Aspire, più le immagini e i volumi che si erano accumulati attorno.
/// Gli ID di mssql 2025, azurite, dcptun e azurelinux sono quelli misurati; gli altri sono fittizi ma
/// nella stessa forma (sha256 di 64 caratteri esadecimali).
///
/// Le fixture JSON stanno accanto a questo file, in `Fixtures/`, copiate byte per byte dal C#: si
/// leggono dal percorso del sorgente (`#filePath`), senza risorse nel bundle dei test.
enum DockerFixtures {
    static let mssql2025Id = "sha256:2b5b581621126574f3d1f75e78d3eebe8d05aedb59ad0cfdf9aa42cb0634d726"
    static let azuriteId = "sha256:647c63a91102a9d8e8000aab803436e1fc85fbb285e7ce830a82ee5d6661cf37"
    static let dcptunId = "sha256:c1a077005187d683004cabff17b02f174db19515ec56327f38d8e3d7e2e8c04a"
    static let azureLinuxId = "sha256:34a22db497ff34a0f35ca5fc54bd38711d04238a2c1b2f65d35dc9d45dd82584"
    static let mssql2022Id = fake("a1")
    static let keycloakId = fake("b2")
    static let mssqlToolsId = fake("c3")
    static let alpineId = fake("d4")
    static let ryukId = fake("e5")
    static let localBuildId = fake("f6")

    static let anonymousVolume = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    static func read(_ name: String) throws -> String {
        let directory = PathText.join(PathText.parent(#filePath) ?? ".", "Fixtures")
        return try String(contentsOfFile: PathText.join(directory, name), encoding: .utf8)
    }

    static func snapshot(existingComposeProjects: Set<String> = []) throws -> DockerSnapshot {
        let verbose = try DockerJson.parseDfVerbose(read("df-verbose.json"))

        return DockerSnapshot(
            containers: try DockerJson.parseContainers(read("containers.json")),
            images: try DockerJson.parseImages(read("images.json"), uniqueSizes: verbose.imageUniqueSizes),
            volumes: try DockerJson.parseVolumes(read("volumes.json"), sizes: verbose.volumeSizes),
            df: try DockerJson.parseDfSummary(read("df.jsonl")),
            existingComposeProjects: existingComposeProjects)
    }

    private static func fake(_ pair: String) -> String {
        "sha256:" + String(repeating: pair, count: 32)
    }
}
```

`Tests/CleanerCoreTests/Docker/DockerJsonTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DockerJsonTests {
    @Test func containersKeepFullImageIdStateAndOnlyNamedVolumeMounts() throws {
        let containers = try DockerJson.parseContainers(DockerFixtures.read("containers.json"))

        let storage = try #require(containers.first { $0.name == "storage-bedaxjvn" })
        #expect(containers.filter { $0.name == "storage-bedaxjvn" }.count == 1)
        #expect(storage.imageId == DockerFixtures.azuriteId)
        #expect(storage.state == "exited")
        #expect(storage.exitCode == 137)
        #expect(storage.volumeNames == ["orbit.apphost-48d90b1972-storage-data"])
        #expect(storage.labels["com.microsoft.developer.usvc-dev.name"] == "storage-bedaxjvn")
    }

    @Test func imagesReadTagsDigestsSizeLabelsAndOrigin() throws {
        let images = try DockerJson.parseImages(
            DockerFixtures.read("images.json"),
            uniqueSizes: [DockerFixtures.dcptunId: 76_740_000])

        let dcptun = try #require(images.first { $0.id == DockerFixtures.dcptunId })
        #expect(dcptun.repoTags == ["dcptun_developer_ms:0.25.13"])
        #expect(dcptun.repoDigests.count == 1)
        #expect(dcptun.sizeBytes == 195_234_351)
        #expect(dcptun.uniqueSizeBytes == 76_740_000)
        #expect(dcptun.origin == .built)
        #expect(dcptun.labels["com.microsoft.developer.usvc-dev.base-image-digest"] == DockerFixtures.azureLinuxId)

        let mssql = try #require(images.first { $0.id == DockerFixtures.mssql2025Id })
        #expect(mssql.origin == .pulled)
        #expect(mssql.uniqueSizeBytes == nil)
    }

    @Test func missingLabelsAndIdentityAreTolerated() throws {
        let json = """
            [{"Id":"sha256:1","RepoTags":null,"RepoDigests":[],"Size":10,"Config":null},
             {"Id":"sha256:2","RepoTags":["a:1"],"RepoDigests":null,"Size":20,"Config":{"Labels":null}}]
            """

        let images = try DockerJson.parseImages(json)

        #expect(images.allSatisfy { $0.labels.isEmpty })
        #expect(images.allSatisfy { $0.origin == .unknown })
        let first = try #require(images.first)
        let second = try #require(images.last)
        #expect(images.count == 2)
        #expect(first.repoTags.isEmpty)
        #expect(first.isDangling)
        #expect(second.repoDigests.isEmpty)
    }

    @Test func identityWithBothBuildAndPullCountsAsPulled() throws {
        let json = """
            [{"Id":"sha256:1","RepoTags":["a:1"],"Size":1,"Identity":{"Build":[{"Ref":"x"}],"Pull":[{"Repository":"a"}]}}]
            """

        #expect(try DockerJson.parseImages(json).first?.origin == .pulled)
    }

    @Test func volumesTakeLabelsFromInspectAndSizeFromSystemDf() throws {
        let verbose = try DockerJson.parseDfVerbose(DockerFixtures.read("df-verbose.json"))
        let volumes = try DockerJson.parseVolumes(DockerFixtures.read("volumes.json"), sizes: verbose.volumeSizes)

        let sql = try #require(volumes.first { $0.name == "orbit.apphost-48d90b1972-sql-data" })
        #expect(sql.sizeBytes == 158_300_000)
        #expect(sql.labels.isEmpty)
        let anonymous = try #require(volumes.first { $0.name == DockerFixtures.anonymousVolume })
        #expect(anonymous.sizeBytes == nil)
    }

    @Test func dfVerboseReadsUniqueImageSizes() throws {
        let verbose = try DockerJson.parseDfVerbose(DockerFixtures.read("df-verbose.json"))

        #expect(verbose.imageUniqueSizes[DockerFixtures.azureLinuxId] == 1_131)
    }

    @Test func dfSummaryReadsOneEntryPerType() throws {
        let df = try DockerJson.parseDfSummary(DockerFixtures.read("df.jsonl"))

        #expect(df.images == 5_840_000_000)
        #expect(df.volumes == 558_500_000)
        #expect(df.buildCache == 106_900_000)
        let cache = df.entries.filter { $0.type == DockerDfSummary.buildCacheType }
        #expect(cache.count == 1)
        #expect(cache.first?.reclaimableBytes == 106_900_000)
    }

    @Test func jsonLinesPropertyIgnoresBlankLines() throws {
        let lines = """
            {"ID":"sha256:1","Repository":"a"}

            {"ID":"sha256:2","Repository":"b"}
            """

        #expect(try DockerJson.parseJsonLinesProperty(lines, "ID") == ["sha256:1", "sha256:2"])
    }

    // Solo Swift: dove .NET lanciava un'eccezione diversa da DockerOutputException (`GetInt64` o
    // `GetInt32` su un numero non intero o fuori intervallo, `TryGetProperty` su un elemento che non
    // è un oggetto) il campo vale come assente, come quando manca.
    @Test func pathologicalFieldsAreReadAsAbsent() throws {
        let images = try DockerJson.parseImages(#"[{"Id":"sha256:1","Size":1.5},{"Id":"sha256:2","Size":true},"x"]"#)
        #expect(images.map(\.sizeBytes) == [0, 0, 0])
        #expect(images.map(\.id) == ["sha256:1", "sha256:2", ""])

        let containers = try DockerJson.parseContainers(#"[{"Id":"1","State":{"ExitCode":4294967296}},{"Id":"2","State":"exited"}]"#)
        #expect(containers.map(\.exitCode) == [0, 0])
    }

    @Test func invalidJsonBecomesAReadableError() {
        let error = #expect(throws: DockerOutputError.self) {
            try DockerJson.parseContainers("Error response from daemon")
        }

        #expect(error?.message.lowercased().contains("container") == true)
    }
}
```

- [ ] **Step 4: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerJsonTests`
Expected: errore di compilazione `cannot find 'DockerJson' in scope`.

- [ ] **Step 5: Implementare `DockerJson`**

`Sources/CleanerCore/Docker/DockerJson.swift`:

```swift
import Foundation

/// L'output della CLI non è nel formato atteso: nessuna classificazione è possibile. Porting di
/// `DockerOutputException`.
public struct DockerOutputError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Dimensioni che solo `docker system df -v` conosce: esclusiva per immagine, totale per volume.
public struct DockerDfVerbose: Sendable, Equatable {
    public let imageUniqueSizes: [String: Int64]
    public let volumeSizes: [String: Int64]

    public init(imageUniqueSizes: [String: Int64], volumeSizes: [String: Int64]) {
        self.imageUniqueSizes = imageUniqueSizes
        self.volumeSizes = volumeSizes
    }
}

/// Parsing puro dell'output JSON della CLI, mai delle tabelle: le colonne cambiano larghezza e
/// ordine fra le versioni, il JSON no. Tollerante verso campi assenti o `null` — misurato:
/// `Config.Labels` manca del tutto su alcune immagini (azurelinux) e `Labels` di un volume senza
/// etichette è `null`, non un oggetto vuoto.
public enum DockerJson {
    public static func parseContainers(_ inspectJson: String) throws -> [DockerContainer] {
        try parseArray(inspectJson, "container") { element in
            let state = child(element, "State")
            return DockerContainer(
                id: string(element, "Id") ?? "",
                name: DockerText.trimmedLeading(string(element, "Name") ?? "", "/"),
                imageId: string(element, "Image") ?? "",
                state: string(state, "Status") ?? "",
                exitCode: integer(child(state, "ExitCode")).flatMap { Int32(exactly: $0) }.map(Int.init) ?? 0,
                volumeNames: items(element, "Mounts")
                    .filter { string($0, "Type") == "volume" }
                    .compactMap { string($0, "Name") },
                labels: labels(child(element, "Config")))
        }
    }

    public static func parseImages(_ inspectJson: String, uniqueSizes: [String: Int64]? = nil) throws -> [DockerImage] {
        try parseArray(inspectJson, "immagine") { element in
            let id = string(element, "Id") ?? ""
            return DockerImage(
                id: id,
                repoTags: strings(element, "RepoTags"),
                repoDigests: strings(element, "RepoDigests"),
                sizeBytes: integer(child(element, "Size")) ?? 0,
                uniqueSizeBytes: uniqueSizes?[id],
                labels: labels(child(element, "Config")),
                origin: origin(child(element, "Identity")))
        }
    }

    public static func parseVolumes(_ inspectJson: String, sizes: [String: Int64]? = nil) throws -> [DockerVolume] {
        try parseArray(inspectJson, "volume") { element in
            let name = string(element, "Name") ?? ""
            return DockerVolume(name: name, labels: labels(element), sizeBytes: sizes?[name])
        }
    }

    public static func parseDfVerbose(_ json: String) throws -> DockerDfVerbose {
        let root = try parse(json, "docker system df -v")
        return DockerDfVerbose(
            imageUniqueSizes: sizes(root, "Images", key: "ID", size: "UniqueSize"),
            volumeSizes: sizes(root, "Volumes", key: "Name", size: "Size"))
    }

    /// Una riga JSON per tipo di risorsa: `docker system df --format '{{json .}}'`.
    public static func parseDfSummary(_ jsonLines: String) throws -> DockerDfSummary {
        DockerDfSummary(entries: try parseJsonLines(jsonLines, "docker system df").map { line in
            DockerDfEntry(
                type: string(line, "Type") ?? "",
                sizeBytes: DockerSize.parse(string(line, "Size")) ?? 0,
                reclaimableBytes: DockerSize.parse(string(line, "Reclaimable")) ?? 0)
        })
    }

    /// Un valore per riga: `docker ps -aq`.
    public static func parseLines(_ output: String) -> [String] {
        DockerText.distinct(DockerText.lines(output))
    }

    /// Un campo da ciascuna riga di un output `--format '{{json .}}'`.
    public static func parseJsonLinesProperty(_ jsonLines: String, _ property: String) throws -> [String] {
        DockerText.distinct(try parseJsonLines(jsonLines, property).compactMap { string($0, property) })
    }

    // MARK: - Utilità

    private static func parseArray<T>(_ json: String, _ what: String, _ map: (DockerJsonValue) -> T) throws -> [T] {
        guard case .array(let elements) = try parse(json, what) else {
            throw DockerOutputError(String(localized: "Risposta di Docker inattesa per \(what): atteso un elenco JSON.", bundle: .module))
        }
        return elements.map(map)
    }

    private static func parseJsonLines(_ jsonLines: String, _ what: String) throws -> [DockerJsonValue] {
        try DockerText.lines(jsonLines).map { try parse($0, what) }
    }

    private static func parse(_ json: String, _ what: String) throws -> DockerJsonValue {
        do {
            return try JSONDecoder().decode(DockerJsonValue.self, from: Data(json.utf8))
        } catch {
            throw DockerOutputError(String(localized: "Risposta di Docker non leggibile per \(what).", bundle: .module))
        }
    }

    private static func sizes(_ root: DockerJsonValue, _ array: String, key: String, size: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for item in items(root, array) {
            if let id = string(item, key), let bytes = DockerSize.parse(string(item, size)) {
                sizes[id] = bytes
            }
        }
        return sizes
    }

    private static func origin(_ identity: DockerJsonValue?) -> ImageOrigin {
        guard let identity else { return .unknown }

        // Pull vince su Build: un'immagine scaricata e poi ritaggata da una build resta
        // riscaricabile, che è ciò che la regola "costruita in locale" vuole sapere.
        if !items(identity, "Pull").isEmpty {
            return .pulled
        }

        return items(identity, "Build").isEmpty ? .unknown : .built
    }

    private static func labels(_ owner: DockerJsonValue?) -> [String: String] {
        guard case .object(let members)? = child(owner, "Labels") else { return [:] }

        var labels: [String: String] = [:]
        for (name, value) in members {
            if case .string(let text) = value { labels[name] = text }
        }
        return labels
    }

    /// Il campo `name` di un oggetto, se presente e non `null`.
    private static func child(_ owner: DockerJsonValue?, _ name: String) -> DockerJsonValue? {
        guard case .object(let members)? = owner, let value = members[name] else { return nil }
        if case .null = value { return nil }
        return value
    }

    private static func string(_ owner: DockerJsonValue?, _ name: String) -> String? {
        guard case .string(let text)? = child(owner, name) else { return nil }
        return text
    }

    /// Un numero intero rappresentabile in 64 bit, come `TryGetInt64`.
    private static func integer(_ value: DockerJsonValue?) -> Int64? {
        guard case .number(let integer)? = value else { return nil }
        return integer
    }

    private static func items(_ owner: DockerJsonValue?, _ name: String) -> [DockerJsonValue] {
        guard case .array(let values)? = child(owner, name) else { return [] }
        return values
    }

    private static func strings(_ owner: DockerJsonValue, _ name: String) -> [String] {
        items(owner, name).compactMap { value in
            guard case .string(let text) = value else { return nil }
            return text
        }
    }
}

/// Un documento JSON con le stesse categorie di `JsonValueKind`: la lettura tollerante del C#
/// esamina i campi uno per uno e ignora quelli del tipo sbagliato, cosa che un `Codable`
/// dichiarativo non consente.
enum DockerJsonValue: Decodable, Equatable {
    case object([String: DockerJsonValue])
    case array([DockerJsonValue])
    case string(String)
    /// Un numero: il valore se è un intero a 64 bit (come `TryGetInt64`), altrimenti `nil`.
    case number(Int64?)
    case bool
    case null

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    init(from decoder: any Decoder) throws {
        if let object = try? decoder.container(keyedBy: Key.self) {
            var members: [String: DockerJsonValue] = [:]
            for key in object.allKeys {
                members[key.stringValue] = try object.decode(DockerJsonValue.self, forKey: key)
            }
            self = .object(members)
        } else if var array = try? decoder.unkeyedContainer() {
            var values: [DockerJsonValue] = []
            while !array.isAtEnd {
                values.append(try array.decode(DockerJsonValue.self))
            }
            self = .array(values)
        } else {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() {
                self = .null
            } else if (try? value.decode(Bool.self)) != nil {
                self = .bool
            } else if let integer = try? value.decode(Int64.self) {
                self = .number(integer)
            } else if (try? value.decode(Double.self)) != nil {
                self = .number(nil)
            } else {
                self = .string(try value.decode(String.self))
            }
        }
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerJsonTests`
Expected: `Test run with 10 tests … passed` (9 portati, 1 solo-Swift), nessun warning.

- [ ] **Step 7: Registro di parità e commit**

Sostituire la riga `Docker/DockerJsonTests.cs` con:

```markdown
| Docker/DockerJsonTests.cs | 9 | Docker/DockerJsonTests.swift | 10 | 2 | 9 portati + 1 solo-Swift (`pathologicalFieldsAreReadAsAbsent`); `Assert.Single(…)` → `filter` + `#require`; le fixture si leggono da `#filePath` (`Package.swift` le esclude dal target) |
```

Nella tabella «Differenze rispetto al C#», aggiungere:

```markdown
| JSON patologico di Docker | `GetInt64`/`GetInt32` su un numero non intero o fuori intervallo → `FormatException`; `TryGetProperty` su un elemento che non è un oggetto → `InvalidOperationException`; etichette con chiavi duplicate → `ArgumentException`: analisi fallita | il campo vale come assente (0, elenco vuoto; con chiavi duplicate vale la prima) | accettata (più tollerante; Docker non produce questi JSON) |
| Eccezioni di Docker | `DockerUnavailableException`, `DockerCommandException`, `DockerOutputException`, con eccezione interna | `struct …Error: LocalizedError` con `message`, senza errore interno | per costruzione |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port DockerJson with the real-case fixtures

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Regole e `DockerClassifier`

La classificazione è pura: stesso snapshot, stessi riferimenti, stesso risultato, verificato sulle sole fixture. Le regole sono elenchi ordinati in cui vince la prima che si applica; l'ordine e i testi (motivo e costo) sono quelli del C#, parola per parola.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/ImageRules.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/VolumeRules.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerClassifier.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerClassifierTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/ImageRules.cs`, `VolumeRules.cs`, `DockerClassifier.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerClassifierTests.cs`

**Interfaces:**
- Consumes: modelli, `ImageName`, `DockerText.hasPrefix`/`hasSuffix`/`ordinalSorted` (Task 1); `DockerFixtures` (Task 2).
- Produces:
  - `public struct RuleMatch: Sendable, Equatable` — `verdict`, `reason`, `cost`; `init(verdict:reason:cost:)`
  - `public struct ImageRule: Sendable` — `id`, `evaluate: @Sendable (DockerImage, ImageRuleContext) -> RuleMatch?`; `init(_:_:)`
  - `public struct ImageRuleContext: Sendable` — `static let aspireBaseImageLabel`, `testcontainersLabel`; `references`, `usersByImageId: [String: [DockerContainer]]`, `inUseTagsByRepository: [String: Set<String>]`, `toolBaseImages: [String: String]`; `init(snapshot:references:)`; `static func isCreatedByTool(_:) -> Bool`; `func toolDeclaringAsBase(_:) -> String?`
  - `public enum ImageRules` — `static let default: [ImageRule]`; interna `static func describeContainers(_: [DockerContainer]) -> String`
  - `public struct VolumeRule: Sendable` — `id`, `evaluate: @Sendable (DockerVolume, VolumeRuleContext) -> RuleMatch?`; `init(_:_:)`
  - `public struct AspireVolumeName: Sendable, Equatable, Hashable` — `app`, `hash`, `resource`; `init(app:hash:resource:)`; `static func tryParse(_:) -> AspireVolumeName?`
  - `public struct VolumeRuleContext: Sendable` — `static let composeProjectLabel`; `mountedBy`, `composeProjects`, `aspireHashesInUse`; `init(snapshot:references:)`
  - `public enum VolumeRules` — `static let default: [VolumeRule]`
  - `public struct DockerRuleError: Error, Equatable, Sendable, LocalizedError` — `message`; `init(_:)`
  - `public enum DockerClassifier` — `static let buildCacheId = "build-cache"`; `static func classify(_: DockerSnapshot, _: ProjectReferences) throws -> [DockerCandidate]`; `static func classify(_:_:imageRules:volumeRules:) throws -> [DockerCandidate]`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DockerClassifierTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DockerClassifierTests {
    private func classifyRealCase(_ references: ProjectReferences = .empty) throws -> [DockerCandidate] {
        try DockerClassifier.classify(DockerFixtures.snapshot(), references)
    }

    private func find(_ candidates: [DockerCandidate], _ displayName: String) throws -> DockerCandidate {
        let matching = candidates.filter { $0.displayName == displayName }
        #expect(matching.count == 1)
        return try #require(matching.first)
    }

    // MARK: - Il caso reale: l'esito atteso dal brief, risorsa per risorsa

    @Test(arguments: [
        ("mcr.microsoft.com/mssql/server:2025-latest", DockerVerdict.keep, "in-use"),
        ("mcr.microsoft.com/azure-storage/azurite:3.35.0", .keep, "in-use"),
        ("testcontainers/ryuk:0.14.0", .delete, "tool-recreated"),
        ("dcptun_developer_ms:0.25.13", .delete, "tool-recreated"),
        ("mcr.microsoft.com/azurelinux/base/core:3.0", .delete, "tool-recreated"),
        ("mcr.microsoft.com/mssql/server:2022-latest", .propose, "superseded"),
        ("quay.io/keycloak/keycloak:26.6", .propose, "unused"),
        ("mcr.microsoft.com/mssql-tools:latest", .propose, "unused"),
        ("alpine:3.20", .propose, "unused"),
        ("orbit-api:dev", .ask, "locally-built"),
        ("mssql2025-data", .keep, "mounted"),
        ("orbit.apphost-48d90b1972-storage-data", .keep, "mounted"),
        ("orbit.apphost-48d90b1972-sql-data", .keep, "aspire-current"),
        ("orbit.apphost-48d90b1972-keycloak-data", .keep, "aspire-current"),
        ("orbit.apphost-751ef8e8e6-storage-data", .propose, "aspire-stale"),
        (DockerFixtures.anonymousVolume, .propose, "anonymous"),
    ])
    func realCaseMatchesTheExpectedOutcome(displayName: String, verdict: DockerVerdict, ruleId: String) throws {
        let candidate = try find(classifyRealCase(), displayName)

        #expect(candidate.verdict == verdict)
        #expect(candidate.ruleId == ruleId)
    }

    @Test func everyResourceOfTheRealCaseIsClassifiedOnce() throws {
        let candidates = try classifyRealCase()

        // 10 immagini + 6 volumi + la cache di build.
        #expect(candidates.count == 17)
        #expect(Set(candidates.map { "\($0.kind)|\($0.id)" }).count == candidates.count)
    }

    @Test func supersededVersionNamesTheTagInUse() throws {
        let mssql2022 = try find(classifyRealCase(), "mcr.microsoft.com/mssql/server:2022-latest")

        #expect(mssql2022.reason.contains("versione superata"))
        #expect(mssql2022.reason.contains("2025-latest"))
        #expect(mssql2022.cost.contains("riscaricare"))
    }

    @Test func stoppedContainerWithExitCode137StillKeepsItsImage() throws {
        let mssql2025 = try find(classifyRealCase(), "mcr.microsoft.com/mssql/server:2025-latest")

        #expect(mssql2025.reason.contains("sqlserver2025"))
        #expect(mssql2025.reason.contains("fermo"))
    }

    @Test func staleAspireHashMentionsTheHashInUse() throws {
        let stale = try find(classifyRealCase(), "orbit.apphost-751ef8e8e6-storage-data")

        #expect(stale.reason.contains("hash AppHost vecchio"))
        #expect(stale.reason.contains("48d90b1972"))
    }

    @Test func imageInUseIsMatchedByIdNotByTag() throws {
        // Lo stesso tag di un'immagine in uso, ma un ID diverso: un'immagine sostituita da un pull
        // successivo e rimasta senza container non è "in uso" solo perché ne condivide il nome.
        var snapshot = try DockerFixtures.snapshot()
        snapshot.containers = [container("web", imageId: "sha256:" + String(repeating: "9", count: 64))]

        let mssql2025 = try find(DockerClassifier.classify(snapshot, .empty), "mcr.microsoft.com/mssql/server:2025-latest")

        #expect(mssql2025.verdict != .keep)
    }

    // MARK: - Riferimenti nei progetti

    @Test func imageCitedWithRepositoryAndTagIsKeptAndNamesTheFile() throws {
        let references = self.references(ImageReference(repository: "quay.io/keycloak/keycloak", tag: "26.6", file: "/p/Orbit.AppHost/Program.cs", line: 12))

        let keycloak = try find(classifyRealCase(references), "quay.io/keycloak/keycloak:26.6")

        #expect(keycloak.verdict == .keep)
        #expect(keycloak.ruleId == "referenced")
        #expect(keycloak.reason.contains("/p/Orbit.AppHost/Program.cs:12"))
    }

    @Test func referenceWithoutTagIsOnlyAPossibleReference() throws {
        let references = self.references(ImageReference(repository: "quay.io/keycloak/keycloak", tag: nil, file: "/p/Orbit.AppHost/Program.cs", line: 12))

        let keycloak = try find(classifyRealCase(references), "quay.io/keycloak/keycloak:26.6")

        #expect(keycloak.verdict == .propose)
        #expect(!keycloak.selectedByDefault)
        #expect(keycloak.reason.contains("possibile riferimento"))
        #expect(keycloak.reason.contains("/p/Orbit.AppHost/Program.cs"))
    }

    @Test func referenceWithAnotherTagDoesNotKeepTheImage() throws {
        let references = self.references(ImageReference(repository: "mcr.microsoft.com/mssql/server", tag: "2025-latest", file: "/p/compose.yaml", line: 3))

        let mssql2022 = try find(classifyRealCase(references), "mcr.microsoft.com/mssql/server:2022-latest")

        #expect(mssql2022.verdict == .propose)
    }

    @Test func locallyBuiltWinsOverAProjectReference() throws {
        let references = self.references(ImageReference(repository: "docker.io/library/orbit-api", tag: "dev", file: "/p/compose.yaml", line: 3))

        let local = try find(classifyRealCase(references), "orbit-api:dev")

        #expect(local.verdict == .ask)
    }

    // MARK: - Immagini: casi fuori dal caso reale

    @Test func danglingImageIsSafeToDelete() throws {
        let dangling = try classifyImage(image("sha256:" + String(repeating: "7", count: 64), tags: ["<none>:<none>"]))

        #expect(dangling.verdict == .delete)
        #expect(dangling.ruleId == "dangling")
        #expect(dangling.selectedByDefault)
    }

    @Test func imageLabelledByTestcontainersIsRecreatedByTheTool() throws {
        let built = try classifyImage(image(
            "sha256:" + String(repeating: "8", count: 64),
            tags: ["testcontainers/abcdef:latest"],
            labels: ["org.testcontainers": "true"],
            origin: .built))

        #expect(built.verdict == .delete)
        #expect(built.ruleId == "tool-recreated")
    }

    @Test func withoutIdentityAnImageWithoutDigestsIsLocallyBuilt() throws {
        let classic = try classifyImage(image("sha256:" + String(repeating: "6", count: 64), tags: ["my/app:1"], digests: []))

        #expect(classic.verdict == .ask)
        #expect(classic.ruleId == "locally-built")
    }

    @Test func creationDateIsNotACriterion() throws {
        // alpine:3.20 ha la data zero di Unix (build riproducibile): resta una normale immagine non
        // usata, non "vecchissima, quindi da cancellare".
        let alpine = try find(classifyRealCase(), "alpine:3.20")

        #expect(!alpine.selectedByDefault)
        #expect(!alpine.reason.contains("1970"))
    }

    // MARK: - Volumi

    @Test func composeVolumeOfAnExistingProjectIsKept() throws {
        var snapshot = try DockerFixtures.snapshot(existingComposeProjects: ["shop"])
        snapshot.volumes = [volume("shop_pgdata", compose: "shop")]

        let volume = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.id == "shop_pgdata" })

        #expect(volume.verdict == .keep)
        #expect(volume.ruleId == "compose-project")
    }

    @Test func composeProjectFoundInTheProjectFoldersAlsoKeepsTheVolume() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.volumes = [volume("shop_pgdata", compose: "shop")]
        let references = ProjectReferences(images: [], composeProjects: ["shop"])

        let volume = try #require(DockerClassifier.classify(snapshot, references).first { $0.id == "shop_pgdata" })

        #expect(volume.verdict == .keep)
    }

    @Test func composeVolumeOfAVanishedProjectNeedsExplicitConfirmation() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.volumes = [volume("old_pgdata", compose: "old")]

        let volume = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.id == "old_pgdata" })

        #expect(volume.verdict == .propose)
        #expect(volume.ruleId == "named-unused")
        #expect(!volume.selectedByDefault)
    }

    @Test func aspireVolumeOfAnAppWithNoHashInUseNeedsExplicitConfirmation() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.volumes = [volume("shop.apphost-1234567890-redis-data")]

        let volume = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.id == "shop.apphost-1234567890-redis-data" })

        #expect(volume.ruleId == "named-unused")
    }

    @Test func noVolumeIsEverDeleteNorPreselected() throws {
        for volume in try classifyRealCase() where volume.kind == .volume {
            #expect(volume.verdict != .delete)
            #expect(!volume.selectedByDefault)
        }
    }

    @Test func onlyDeleteVerdictsArePreselected() throws {
        for candidate in try classifyRealCase() {
            #expect(candidate.selectedByDefault == (candidate.verdict == .delete))
        }
    }

    // MARK: - Cache di build

    @Test func buildCacheIsASingleSafeDeletion() throws {
        let caches = try classifyRealCase().filter { $0.kind == .buildCache }
        let cache = try #require(caches.first)

        #expect(caches.count == 1)
        #expect(cache.verdict == .delete)
        #expect(cache.sizeBytes == 106_900_000)
    }

    @Test func buildCacheSharedWithImagesSaysItMayNotBeFreedYet() throws {
        // Misurato: 101,9 MB di cache, 0 B recuperabili — i layer sono condivisi con l'immagine
        // dcptun ancora presente. Presentarla come spazio sicuramente recuperabile sarebbe falso.
        var snapshot = try DockerFixtures.snapshot()
        snapshot.df = DockerDfSummary(entries: [DockerDfEntry(type: DockerDfSummary.buildCacheType, sizeBytes: 101_900_000, reclaimableBytes: 0)])

        let cache = try #require(DockerClassifier.classify(snapshot, .empty).first { $0.kind == .buildCache })

        #expect(cache.reason.contains("condivisa con immagini presenti"))
    }

    @Test func fullyReclaimableBuildCacheHasNoSharingNote() throws {
        let cache = try #require(classifyRealCase().first { $0.kind == .buildCache })

        #expect(!cache.reason.contains("condivisa"))
    }

    @Test func emptyBuildCacheIsNotProposed() throws {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.df = .empty

        #expect(!(try DockerClassifier.classify(snapshot, .empty)).contains { $0.kind == .buildCache })
    }

    // MARK: - Regole

    @Test func rulesAreDeclaredInPriorityOrder() {
        #expect(ImageRules.default.map(\.id) == ["in-use", "dangling", "tool-recreated", "locally-built", "referenced", "superseded", "unused"])
        #expect(VolumeRules.default.map(\.id) == ["mounted", "anonymous", "compose-project", "aspire-current", "aspire-stale", "named-unused"])
    }

    // MARK: - Solo Swift

    // L'eccezione del C# per un elenco personalizzato senza regola finale diventa un errore lanciato.
    @Test func customRulesWithoutAFallbackAreAProgrammingError() throws {
        let snapshot = try DockerFixtures.snapshot()

        #expect(throws: DockerRuleError.self) {
            try DockerClassifier.classify(snapshot, .empty, imageRules: [], volumeRules: VolumeRules.default)
        }
    }

    // Le regex dei nomi di volume seguono .NET: il suo "." accetta "\r" e il suo "$" un "\n" finale.
    @Test func volumeNamePatternsFollowDotNetSemantics() {
        #expect(AspireVolumeName.tryParse("shop.apphost-abcdef-redis-data\n") == AspireVolumeName(app: "shop", hash: "abcdef", resource: "redis"))
        #expect(AspireVolumeName.tryParse("shop\r.apphost-abcdef-redis-data")?.app == "shop\r")
        #expect(AspireVolumeName.tryParse("shop.apphost-abcdef-redis-data\n\n") == nil)
        #expect(AspireVolumeName.tryParse("shop.apphost-ABCDEF-redis-data") == nil)
    }

    // MARK: - Utilità

    private func classifyImage(_ image: DockerImage) throws -> DockerCandidate {
        var snapshot = try DockerFixtures.snapshot()
        snapshot.containers = []
        snapshot.images = [image]
        snapshot.volumes = []
        snapshot.df = .empty

        let candidates = try DockerClassifier.classify(snapshot, .empty)
        #expect(candidates.count == 1)
        return try #require(candidates.first)
    }

    private func references(_ images: ImageReference...) -> ProjectReferences {
        ProjectReferences(images: images, composeProjects: [])
    }

    private func container(_ name: String, imageId: String) -> DockerContainer {
        DockerContainer(id: name, name: name, imageId: imageId, state: "running", exitCode: 0, volumeNames: [], labels: [:])
    }

    private func image(
        _ id: String,
        tags: [String],
        digests: [String] = [],
        labels: [String: String] = [:],
        origin: ImageOrigin = .unknown
    ) -> DockerImage {
        DockerImage(id: id, repoTags: tags, repoDigests: digests, sizeBytes: 1_000, uniqueSizeBytes: nil, labels: labels, origin: origin)
    }

    private func volume(_ name: String, compose: String? = nil) -> DockerVolume {
        DockerVolume(name: name, labels: compose.map { ["com.docker.compose.project": $0] } ?? [:], sizeBytes: 1_000)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerClassifierTests`
Expected: errore di compilazione `cannot find 'DockerClassifier' in scope` (e lo stesso per `ImageRules`, `VolumeRules`, `AspireVolumeName`).

- [ ] **Step 3: Implementare le regole sulle immagini**

`Sources/CleanerCore/Docker/ImageRules.swift`:

```swift
/// Esito di una regola che si applica: verdetto, motivo mostrato all'utente e costo per ricreare
/// la risorsa.
public struct RuleMatch: Sendable, Equatable {
    public let verdict: DockerVerdict
    public let reason: String
    public let cost: String

    public init(verdict: DockerVerdict, reason: String, cost: String) {
        self.verdict = verdict
        self.reason = reason
        self.cost = cost
    }
}

/// Una regola: restituisce `nil` quando non si applica, e la valutazione passa alla successiva.
public struct ImageRule: Sendable {
    public let id: String
    public let evaluate: @Sendable (DockerImage, ImageRuleContext) -> RuleMatch?

    public init(_ id: String, _ evaluate: @escaping @Sendable (DockerImage, ImageRuleContext) -> RuleMatch?) {
        self.id = id
        self.evaluate = evaluate
    }
}

/// Fatti ricavati una sola volta dallo snapshot e condivisi da tutte le regole sulle immagini.
public struct ImageRuleContext: Sendable {
    public static let aspireBaseImageLabel = "com.microsoft.developer.usvc-dev.base-image-digest"
    public static let testcontainersLabel = "org.testcontainers"

    public let references: ProjectReferences

    /// Container (anche fermi) per ID COMPLETO dell'immagine: mai per tag.
    public let usersByImageId: [String: [DockerContainer]]

    public let inUseTagsByRepository: [String: Set<String>]

    /// Digest dell'immagine base → nome dell'immagine dello strumento che la dichiara.
    public let toolBaseImages: [String: String]

    public init(snapshot: DockerSnapshot, references: ProjectReferences) {
        self.references = references

        let users = Dictionary(grouping: snapshot.containers, by: \.imageId)
        usersByImageId = users

        var inUseTags: [String: Set<String>] = [:]
        for image in snapshot.images where users[image.id] != nil {
            for name in image.names {
                if let tag = name.tag {
                    inUseTags[name.repository, default: []].insert(tag)
                }
            }
        }
        inUseTagsByRepository = inUseTags

        // Le immagini base dichiarate dagli strumenti (il tunnel dcptun di Aspire indica la sua in
        // un'etichetta): lo strumento le riscarica da solo quando ricostruisce la derivata.
        var toolBases: [String: String] = [:]
        for tool in snapshot.images where Self.isCreatedByTool(tool) {
            if let digest = tool.labels[Self.aspireBaseImageLabel], toolBases[digest] == nil {
                toolBases[digest] = tool.displayName
            }
        }
        toolBaseImages = toolBases
    }

    public static func isCreatedByTool(_ image: DockerImage) -> Bool {
        image.labels[testcontainersLabel] == "true"
            || image.names.contains { name in
                DockerText.hasSuffix(name.repository, "/testcontainers/ryuk")
                    || DockerText.hasPrefix(name.shortName, "dcptun_")
            }
    }

    /// L'etichetta dello strumento contiene un digest: con il containerd store coincide con l'ID,
    /// con lo store classico è quello del manifest, che compare in `RepoDigests`.
    public func toolDeclaringAsBase(_ image: DockerImage) -> String? {
        if let tool = toolBaseImages[image.id] {
            return tool
        }

        for repoDigest in image.repoDigests {
            let bytes = Array(repoDigest.utf8)
            if let at = bytes.firstIndex(of: UInt8(ascii: "@")),
               let tool = toolBaseImages[String(decoding: bytes.suffix(from: at + 1), as: UTF8.self)] {
                return tool
            }
        }

        return nil
    }
}

/// Regole sulle immagini in ordine di priorità: vince la prima che si applica. Per aggiungere un
/// caso si aggiunge una riga, nel punto giusto dell'elenco.
public enum ImageRules {
    private static var redownload: String { String(localized: "riscaricare", bundle: .module) }

    public static let `default`: [ImageRule] = [
        ImageRule("in-use") { image, context in
            guard let users = context.usersByImageId[image.id] else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "usata da \(describeContainers(users))", bundle: .module),
                cost: "")
        },

        ImageRule("dangling") { image, _ in
            guard image.isDangling else { return nil }
            return RuleMatch(
                verdict: .delete,
                reason: String(localized: "immagine dangling, senza tag", bundle: .module),
                cost: String(localized: "nessuno", bundle: .module))
        },

        // Prima di "locally-built": il tunnel dcptun è costruito in locale da Aspire, ma è Aspire a
        // ricostruirlo al prossimo avvio — "non si può riscaricare" non è un costo per l'utente.
        ImageRule("tool-recreated") { image, context in
            if image.labels[ImageRuleContext.testcontainersLabel] == "true"
                || image.names.contains(where: { DockerText.hasSuffix($0.repository, "/testcontainers/ryuk") }) {
                return RuleMatch(
                    verdict: .delete,
                    reason: String(localized: "ricreata automaticamente da Testcontainers", bundle: .module),
                    cost: String(localized: "nessuno: la riscarica Testcontainers", bundle: .module))
            }

            if image.names.contains(where: { DockerText.hasPrefix($0.shortName, "dcptun_") }) {
                return RuleMatch(
                    verdict: .delete,
                    reason: String(localized: "tunnel di .NET Aspire, ricreato a ogni avvio", bundle: .module),
                    cost: String(localized: "nessuno: la ricostruisce Aspire", bundle: .module))
            }

            guard let tool = context.toolDeclaringAsBase(image) else { return nil }
            return RuleMatch(
                verdict: .delete,
                reason: String(localized: "immagine base di \(tool)", bundle: .module),
                cost: String(localized: "nessuno: la riscarica lo strumento", bundle: .module))
        },

        ImageRule("locally-built") { image, _ in
            guard isLocallyBuilt(image) else { return nil }
            return RuleMatch(
                verdict: .ask,
                reason: String(localized: "costruita in locale: non si può riscaricare", bundle: .module),
                cost: String(localized: "ricostruire dal Dockerfile", bundle: .module))
        },

        ImageRule("referenced") { image, context in
            guard let reference = exactReference(image, context) else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "citata in \(reference.file):\(String(reference.line))", bundle: .module),
                cost: "")
        },

        ImageRule("superseded") { image, context in
            for name in image.names {
                if let tags = context.inUseTagsByRepository[name.repository], tags.contains(where: { $0 != name.tag }) {
                    let inUse = DockerText.ordinalSorted(tags).joined(separator: ", ")
                    return RuleMatch(
                        verdict: .propose,
                        reason: String(localized: "versione superata: in uso \(inUse)", bundle: .module),
                        cost: redownload)
                }
            }

            return nil
        },

        ImageRule("unused") { _, _ in
            RuleMatch(
                verdict: .propose,
                reason: String(localized: "non usata da alcun container", bundle: .module),
                cost: redownload)
        },
    ]

    /// Con `Identity` (Docker 29, containerd store) l'origine è esplicita; senza, ricade sul
    /// criterio dello store classico: nessun digest di registro.
    private static func isLocallyBuilt(_ image: DockerImage) -> Bool {
        switch image.origin {
        case .built: true
        case .pulled: false
        case .unknown: image.repoDigests.isEmpty
        }
    }

    private static func exactReference(_ image: DockerImage, _ context: ImageRuleContext) -> ImageReference? {
        context.references.images.first { reference in
            reference.tag != nil
                && image.names.contains { $0.repository == reference.repository && $0.tag == reference.tag }
        }
    }

    static func describeContainers(_ containers: [DockerContainer]) -> String {
        containers.map { container in
            let state = container.state == "running"
                ? String(localized: "in esecuzione", bundle: .module)
                : String(localized: "fermo", bundle: .module)
            return "\(container.name) (\(state))"
        }.joined(separator: ", ")
    }
}
```

- [ ] **Step 4: Implementare le regole sui volumi**

`Sources/CleanerCore/Docker/VolumeRules.swift`:

```swift
public struct VolumeRule: Sendable {
    public let id: String
    public let evaluate: @Sendable (DockerVolume, VolumeRuleContext) -> RuleMatch?

    public init(_ id: String, _ evaluate: @escaping @Sendable (DockerVolume, VolumeRuleContext) -> RuleMatch?) {
        self.id = id
        self.evaluate = evaluate
    }
}

/// Nome di un volume creato da .NET Aspire: `<app>.apphost-<hash>-<risorsa>-data`. L'hash deriva
/// dal percorso dell'AppHost: spostare o rinominare la cartella del progetto produce un hash nuovo,
/// e i volumi con il vecchio restano orfani.
public struct AspireVolumeName: Sendable, Equatable, Hashable {
    public let app: String
    public let hash: String
    public let resource: String

    public init(app: String, hash: String, resource: String) {
        self.app = app
        self.hash = hash
        self.resource = resource
    }

    public static func tryParse(_ volumeName: String) -> AspireVolumeName? {
        // `^(?<app>.+?)\.apphost-(?<hash>[0-9a-f]{6,64})-(?<resource>.+)-data$` di .NET: il "." di
        // .NET esclude solo "\n" (quello di Swift anche "\r" e U+2028) e il suo "$" accetta un "\n"
        // finale (quello di Swift no).
        let pattern = /^(?<app>[^\n]+?)\.apphost-(?<hash>[0-9a-f]{6,64})-(?<resource>[^\n]+)-data\n?$/
            .matchingSemantics(.unicodeScalar)
        guard let match = volumeName.firstMatch(of: pattern) else { return nil }
        return AspireVolumeName(app: String(match.output.app), hash: String(match.output.hash), resource: String(match.output.resource))
    }
}

public struct VolumeRuleContext: Sendable {
    public static let composeProjectLabel = "com.docker.compose.project"

    public let mountedBy: [String: [DockerContainer]]
    public let composeProjects: Set<String>
    public let aspireHashesInUse: [String: Set<String>]

    public init(snapshot: DockerSnapshot, references: ProjectReferences) {
        var mounted: [String: [DockerContainer]] = [:]
        for container in snapshot.containers {
            for volume in container.volumeNames {
                mounted[volume, default: []].append(container)
            }
        }
        mountedBy = mounted

        composeProjects = snapshot.existingComposeProjects.union(references.composeProjects)

        // Un hash è "in uso" per un'app quando un suo volume è montato da un container, anche
        // fermo: Aspire lo ricollegherà al prossimo avvio insieme agli altri volumi con lo stesso hash.
        var hashes: [String: Set<String>] = [:]
        for name in mounted.keys.compactMap(AspireVolumeName.tryParse) {
            hashes[name.app, default: []].insert(name.hash)
        }
        aspireHashesInUse = hashes
    }
}

/// Regole sui volumi in ordine di priorità. Un volume contiene dati: nessuna regola produce DELETE,
/// e nel dubbio si tiene.
public enum VolumeRules {
    private static var dataLost: String { String(localized: "dati persi", bundle: .module) }

    public static let `default`: [VolumeRule] = [
        VolumeRule("mounted") { volume, context in
            guard let users = context.mountedBy[volume.name] else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "montato da \(ImageRules.describeContainers(users))", bundle: .module),
                cost: "")
        },

        VolumeRule("anonymous") { volume, _ in
            guard isAnonymous(volume.name) else { return nil }
            return RuleMatch(
                verdict: .propose,
                reason: String(localized: "volume anonimo non montato", bundle: .module),
                cost: dataLost)
        },

        VolumeRule("compose-project") { volume, context in
            guard let project = volume.labels[VolumeRuleContext.composeProjectLabel],
                  context.composeProjects.contains(project) else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "progetto compose «\(project)» ancora presente", bundle: .module),
                cost: "")
        },

        VolumeRule("aspire-current") { volume, context in
            guard let name = AspireVolumeName.tryParse(volume.name),
                  let hashes = context.aspireHashesInUse[name.app],
                  hashes.contains(name.hash) else { return nil }
            return RuleMatch(
                verdict: .keep,
                reason: String(localized: "AppHost «\(name.app)» in uso con lo stesso hash: Aspire lo ricollega al prossimo avvio", bundle: .module),
                cost: "")
        },

        VolumeRule("aspire-stale") { volume, context in
            guard let name = AspireVolumeName.tryParse(volume.name),
                  let hashes = context.aspireHashesInUse[name.app] else { return nil }
            let inUse = DockerText.ordinalSorted(hashes).joined(separator: ", ")
            return RuleMatch(
                verdict: .propose,
                reason: String(localized: "hash AppHost vecchio (in uso: \(inUse))", bundle: .module),
                cost: dataLost)
        },

        VolumeRule("named-unused") { _, _ in
            RuleMatch(
                verdict: .propose,
                reason: String(localized: "volume con nome non montato: va confermato esplicitamente", bundle: .module),
                cost: dataLost)
        },
    ]

    /// `^[0-9a-f]{64}$` di .NET, il cui "$" accetta un "\n" finale.
    private static func isAnonymous(_ name: String) -> Bool {
        name.firstMatch(of: /^[0-9a-f]{64}\n?$/.matchingSemantics(.unicodeScalar)) != nil
    }
}
```

- [ ] **Step 5: Implementare `DockerClassifier`**

`Sources/CleanerCore/Docker/DockerClassifier.swift`:

```swift
import Foundation

/// Un elenco di regole personalizzato senza una regola finale che si applica sempre: è un errore di
/// programmazione, non di dati. Porting della `InvalidOperationException` di `FirstMatch`.
public struct DockerRuleError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Classificazione pura: stesso snapshot, stessi riferimenti, stesso risultato. Nessuna chiamata a
/// Docker né al disco — è ciò che permette di verificarla con le sole fixture JSON.
public enum DockerClassifier {
    public static let buildCacheId = "build-cache"

    public static func classify(_ snapshot: DockerSnapshot, _ references: ProjectReferences) throws -> [DockerCandidate] {
        try classify(snapshot, references, imageRules: ImageRules.default, volumeRules: VolumeRules.default)
    }

    public static func classify(
        _ snapshot: DockerSnapshot,
        _ references: ProjectReferences,
        imageRules: [ImageRule],
        volumeRules: [VolumeRule]
    ) throws -> [DockerCandidate] {
        let imageContext = ImageRuleContext(snapshot: snapshot, references: references)
        let volumeContext = VolumeRuleContext(snapshot: snapshot, references: references)
        var candidates: [DockerCandidate] = []

        for image in snapshot.images {
            let (ruleId, match) = try firstMatch(imageRules.lazy.map { ($0.id, $0.evaluate(image, imageContext)) })
            candidates.append(DockerCandidate(
                kind: .image,
                id: image.id,
                displayName: image.displayName,
                sizeBytes: image.sizeBytes,
                verdict: match.verdict,
                ruleId: ruleId,
                reason: withPossibleReference(match, image, references),
                cost: match.cost))
        }

        for volume in snapshot.volumes {
            let (ruleId, match) = try firstMatch(volumeRules.lazy.map { ($0.id, $0.evaluate(volume, volumeContext)) })
            candidates.append(DockerCandidate(
                kind: .volume,
                id: volume.name,
                displayName: volume.name,
                sizeBytes: volume.sizeBytes,
                verdict: match.verdict,
                ruleId: ruleId,
                reason: match.reason,
                cost: match.cost))
        }

        if snapshot.df.buildCache > 0 {
            // La parte condivisa con immagini ancora presenti non si libera finché quelle restano:
            // la dimensione mostrata è un massimo, non una promessa.
            let cache = snapshot.df.entries.first { $0.type == DockerDfSummary.buildCacheType }
            let reason = if let cache, cache.reclaimableBytes < cache.sizeBytes {
                String(localized: "cache di BuildKit, in parte condivisa con immagini presenti: si libera del tutto solo se anche quelle vengono eliminate", bundle: .module)
            } else {
                String(localized: "cache di BuildKit", bundle: .module)
            }

            candidates.append(DockerCandidate(
                kind: .buildCache,
                id: buildCacheId,
                displayName: String(localized: "Cache di build", bundle: .module),
                sizeBytes: snapshot.df.buildCache,
                verdict: .delete,
                ruleId: buildCacheId,
                reason: reason,
                cost: String(localized: "solo tempo alla build successiva", bundle: .module)))
        }

        return candidates
    }

    /// La prima regola che si applica, valutando le successive solo se serve (come il `foreach` del C#).
    private static func firstMatch(_ evaluations: some Sequence<(String, RuleMatch?)>) throws -> (String, RuleMatch) {
        for (id, match) in evaluations {
            if let match {
                return (id, match)
            }
        }

        // Ogni elenco termina con una regola che si applica sempre: arrivare qui vuol dire che un
        // elenco personalizzato l'ha omessa, ed è un errore di programmazione, non di dati.
        throw DockerRuleError(String(localized: "Nessuna regola si applica: l'ultima regola dell'elenco deve applicarsi sempre.", bundle: .module))
    }

    /// Un file che cita il repository senza tag ("AddKeycloak()") non basta a tenere un'immagine —
    /// terrebbe ogni versione del repository — ma l'utente deve saperlo prima di decidere.
    private static func withPossibleReference(_ match: RuleMatch, _ image: DockerImage, _ references: ProjectReferences) -> String {
        guard match.verdict == .propose || match.verdict == .ask else { return match.reason }

        let names = image.names
        guard let possible = references.images.first(where: { reference in
            reference.tag == nil && names.contains { $0.repository == reference.repository }
        }) else {
            return match.reason
        }

        return String(localized: "\(match.reason) · possibile riferimento in \(possible.file):\(String(possible.line))", bundle: .module)
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerClassifierTests`
Expected: `Test run with 27 tests … passed` (25 portati, 2 solo-Swift), nessun warning.

- [ ] **Step 7: Registro di parità e commit**

Sostituire la riga `Docker/DockerClassifierTests.cs` con:

```markdown
| Docker/DockerClassifierTests.cs | 25 (16) | Docker/DockerClassifierTests.swift | 27 (16) | 2 | 25 (16) portati + 2 solo-Swift (`customRulesWithoutAFallbackAreAProgrammingError`, `volumeNamePatternsFollowDotNetSemantics`); `classify` è `throws`; `with` → copia `var` dello snapshot |
```

Nella tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Elenco di regole senza una regola finale che si applica sempre | `InvalidOperationException` | `DockerRuleError` lanciato: `classify` è `throws` | per costruzione |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port Docker image and volume rules and the classifier

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `DockerConfirmationGroups`

Ciò che decide cosa viene cancellato va coperto dai test, non solo esercitato nell'interfaccia: gruppi e selezione restano logica pura del Core, come `ConfirmationRows`.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerConfirmationGroups.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerConfirmationGroupsTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerConfirmationGroups.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerConfirmationGroupsTests.cs`

**Interfaces:**
- Consumes: `DockerCandidate`, `DockerVerdict`, `DockerResourceKind`, `DockerText.ordinalSorted` (Task 1); `DockerFixtures` (Task 2); `DockerClassifier.classify(_:_:)` (Task 3).
- Produces:
  - `public enum DockerGroupMode: Sendable, Equatable, Hashable { case block, selectable, readOnly }`
  - `public struct DockerConfirmationGroup: Sendable, Equatable` — `id`, `title`, `description`, `mode`, `items: [DockerCandidate]`; `init(id:title:description:mode:items:)`; `selectedByDefault`
  - `public enum DockerConfirmationGroups` — `static let safeId`, `localBuildsId`, `unusedImagesId`, `unusedVolumesId`, `keepId`; `static func build(_: [DockerCandidate]) -> [DockerConfirmationGroup]`; `static func requiresIndividualConfirmation(_: DockerCandidate) -> Bool`; `static func selection(_: [DockerConfirmationGroup], isGroupSelected: (DockerConfirmationGroup) -> Bool, isItemSelected: (DockerCandidate) -> Bool) -> [DockerCandidate]`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DockerConfirmationGroupsTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DockerConfirmationGroupsTests {
    private func realCaseGroups() throws -> [DockerConfirmationGroup] {
        DockerConfirmationGroups.build(try DockerClassifier.classify(DockerFixtures.snapshot(), .empty))
    }

    @Test func groupsFollowTheRiskOrderAndSkipEmptyOnes() throws {
        #expect(try realCaseGroups().map(\.id) == [
            DockerConfirmationGroups.safeId,
            DockerConfirmationGroups.localBuildsId,
            DockerConfirmationGroups.unusedImagesId,
            DockerConfirmationGroups.unusedVolumesId,
            DockerConfirmationGroups.keepId,
        ])

        let onlyKeep = DockerConfirmationGroups.build([
            DockerCandidate(kind: .image, id: "sha256:1", displayName: "a", sizeBytes: 1, verdict: .keep, ruleId: "in-use", reason: "r", cost: "c"),
        ])
        #expect(onlyKeep.map(\.id) == [DockerConfirmationGroups.keepId])
    }

    @Test func safeDeletionsAreConfirmedAsABlock() throws {
        let safe = try #require(realCaseGroups().first { $0.id == DockerConfirmationGroups.safeId })

        #expect(safe.mode == .block)
        #expect(safe.selectedByDefault)
        #expect(DockerText.ordinalSorted(safe.items.map(\.displayName)) == [
            "Cache di build",
            "dcptun_developer_ms:0.25.13",
            "mcr.microsoft.com/azurelinux/base/core:3.0",
            "testcontainers/ryuk:0.14.0",
        ])
    }

    @Test func proposeAndAskGroupsStartUnselected() throws {
        for group in try realCaseGroups() where group.mode == .selectable {
            #expect(!group.selectedByDefault)
        }
    }

    @Test func keptResourcesAreReadOnly() throws {
        let keep = try #require(realCaseGroups().first { $0.id == DockerConfirmationGroups.keepId })

        #expect(keep.mode == .readOnly)
        #expect(keep.items.allSatisfy { $0.verdict == .keep })
    }

    @Test func unusedNamedVolumesNeedIndividualConfirmation() {
        let named = DockerCandidate(kind: .volume, id: "old", displayName: "old", sizeBytes: 1, verdict: .propose, ruleId: "named-unused", reason: "r", cost: "c")
        // `named with { Id = "anon", DisplayName = "anon", RuleId = "anonymous" }` del C#.
        let anonymous = DockerCandidate(kind: .volume, id: "anon", displayName: "anon", sizeBytes: 1, verdict: .propose, ruleId: "anonymous", reason: "r", cost: "c")

        #expect(DockerConfirmationGroups.requiresIndividualConfirmation(named))
        #expect(!DockerConfirmationGroups.requiresIndividualConfirmation(anonymous))
    }

    @Test func selectionNeverContainsKeptResources() throws {
        let groups = try realCaseGroups()
        let everything = Set(groups.flatMap(\.items))

        let selection = DockerConfirmationGroups.selection(groups, isGroupSelected: { _ in true }, isItemSelected: everything.contains)

        #expect(!selection.contains { $0.verdict == .keep })
        #expect(selection.count == groups.filter { $0.mode != .readOnly }.reduce(0) { $0 + $1.items.count })
    }

    @Test func blockGroupIsAllOrNothing() throws {
        let groups = try realCaseGroups()

        // Le righe di un blocco non si selezionano singolarmente: conta solo la casella del gruppo.
        let withBlock = DockerConfirmationGroups.selection(groups, isGroupSelected: { $0.mode == .block }, isItemSelected: { _ in false })
        let withoutBlock = DockerConfirmationGroups.selection(groups, isGroupSelected: { _ in false }, isItemSelected: { _ in false })

        #expect(withBlock.count == 4)
        #expect(withoutBlock.isEmpty)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerConfirmationGroupsTests`
Expected: errore di compilazione `cannot find type 'DockerConfirmationGroup' in scope` (e lo stesso per `DockerConfirmationGroups`).

- [ ] **Step 3: Implementare `DockerConfirmationGroups`**

`Sources/CleanerCore/Docker/DockerConfirmationGroups.swift`:

```swift
public enum DockerGroupMode: Sendable, Equatable, Hashable {
    /// Si conferma in blocco con un'unica casella: le voci sicure.
    case block

    /// Si confermano le singole voci, o tutte insieme dal gruppo.
    case selectable

    /// Solo da leggere: le voci KEEP non si possono selezionare.
    case readOnly
}

public struct DockerConfirmationGroup: Sendable, Equatable {
    public let id: String
    public let title: String
    public let description: String
    public let mode: DockerGroupMode
    public let items: [DockerCandidate]

    public init(id: String, title: String, description: String, mode: DockerGroupMode, items: [DockerCandidate]) {
        self.id = id
        self.title = title
        self.description = description
        self.mode = mode
        self.items = items
    }

    public var selectedByDefault: Bool { mode == .block }
}

/// Raggruppa i candidati per la schermata di conferma e ricava la selezione da consegnare
/// all'esecutore. Logica pura nel Core, come `ConfirmationRows` per il wizard: ciò che decide cosa
/// viene cancellato va coperto dai test, non solo esercitato a mano nell'interfaccia.
public enum DockerConfirmationGroups {
    public static let safeId = "safe"
    public static let localBuildsId = "local-builds"
    public static let unusedImagesId = "unused-images"
    public static let unusedVolumesId = "unused-volumes"
    public static let keepId = "keep"

    public static func build(_ candidates: [DockerCandidate]) -> [DockerConfirmationGroup] {
        let groups = [
            DockerConfirmationGroup(
                id: safeId,
                title: String(localized: "Eliminabili in sicurezza", bundle: .module),
                description: String(localized: "Immagini dangling, immagini che Testcontainers e Aspire ricreano da soli, cache di build. Si confermano in blocco.", bundle: .module),
                mode: .block,
                items: candidates.filter { $0.verdict == .delete }),

            DockerConfirmationGroup(
                id: localBuildsId,
                title: String(localized: "Costruite in locale", bundle: .module),
                description: String(localized: "Non si possono riscaricare: dopo la cancellazione vanno ricostruite dal loro Dockerfile.", bundle: .module),
                mode: .selectable,
                items: candidates.filter { $0.verdict == .ask }),

            DockerConfirmationGroup(
                id: unusedImagesId,
                title: String(localized: "Immagini non usate", bundle: .module),
                description: String(localized: "Nessun container le usa. Costo: riscaricarle al prossimo utilizzo.", bundle: .module),
                mode: .selectable,
                items: candidates.filter { $0.verdict == .propose && $0.kind == .image }),

            DockerConfirmationGroup(
                id: unusedVolumesId,
                title: String(localized: "Volumi non montati", bundle: .module),
                description: String(localized: "I volumi contengono dati: cancellarli li perde per sempre. Quelli con nome si confermano uno alla volta.", bundle: .module),
                mode: .selectable,
                items: candidates.filter { $0.verdict == .propose && $0.kind == .volume }),

            DockerConfirmationGroup(
                id: keepId,
                title: String(localized: "Da tenere", bundle: .module),
                description: String(localized: "In uso, citate nei progetti o ricollegate da Aspire al prossimo avvio.", bundle: .module),
                mode: .readOnly,
                items: candidates.filter { $0.verdict == .keep }),
        ]

        return groups.filter { !$0.items.isEmpty }
    }

    /// Un volume con nome che nessuna regola sa ricondurre a un progetto è il caso più rischioso: non
    /// lo seleziona la casella del gruppo, solo la sua.
    public static func requiresIndividualConfirmation(_ candidate: DockerCandidate) -> Bool {
        candidate.kind == .volume && candidate.ruleId == "named-unused"
    }

    /// Le voci da consegnare all'esecutore. I gruppi a blocco contano per intero o per niente; i
    /// gruppi in sola lettura mai; le voci KEEP sono escluse comunque, qualunque cosa dica
    /// l'interfaccia.
    public static func selection(
        _ groups: [DockerConfirmationGroup],
        isGroupSelected: (DockerConfirmationGroup) -> Bool,
        isItemSelected: (DockerCandidate) -> Bool
    ) -> [DockerCandidate] {
        groups
            .flatMap { group -> [DockerCandidate] in
                switch group.mode {
                case .block: isGroupSelected(group) ? group.items : []
                case .selectable: group.items.filter(isItemSelected)
                case .readOnly: []
                }
            }
            .filter { $0.verdict != .keep }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerConfirmationGroupsTests`
Expected: `Test run with 7 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/DockerConfirmationGroupsTests.cs` con:

```markdown
| Docker/DockerConfirmationGroupsTests.cs | 7 | Docker/DockerConfirmationGroupsTests.swift | 7 | 2 | «`named with { … }` → nuovo `DockerCandidate` con gli stessi campi» |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port Docker confirmation groups

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `DockerCli`, `DockerCliErrors`, `DockerBinaryLocator` e la CLI finta

`DockerCli` è l'unico punto che esegue `docker`. Traduce in `DockerUnavailableError` il binario assente o non avviabile (`ProcessLaunchError` del piano 1) e il daemon irraggiungibile, controllato a ogni chiamata. `FakeDockerCli` porta il doppio C# e in più rifiuta di avviare un comando da un task annullato, come `ProcessRunner`: è ciò che permette al Task 9 di verificare l'isolamento dall'annullamento.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerCli.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/FakeDockerCli.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCliTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerCli.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerCliTests.cs`, `FakeDockerCli.cs`

**Interfaces:**
- Consumes (piano 1): `ProcessRunning`, `ProcessResult`, `ProcessLaunchError`, `FileSystem`, `PathText.parent`/`join`; test: `InMemoryFileSystem`, `Recorder`. Task 1: `DockerText.lines`, `hasPrefix`, `containsIgnoringCase`, `trimmedTrailing`. Task 2: `DockerJson`, `DockerFixtures`.
- Produces:
  - `public struct DockerUnavailableError: Error, Equatable, Sendable, LocalizedError` — `static var notRunning`, `notInstalled`; `message`; `init(_:)`
  - `public struct DockerCommandError: Error, Equatable, Sendable, LocalizedError` — `message`; `init(_:)`
  - `public protocol DockerCommandRunning: Sendable` — `func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult`; in estensione `run(_:) async throws -> ProcessResult` e `runChecked(_:) async throws -> String`
  - `public enum DockerCliErrors` — `static func isDaemonUnavailable(_: String) -> Bool`, `static func describe(_: ProcessResult) -> String`
  - `public struct DockerCli: DockerCommandRunning` — `init(runner: any ProcessRunning, binaryPath: String?)`
  - `public enum DockerBinaryLocator` — `static func find(_: any FileSystem, homeDirectory: String) -> String?`
  - test: `final class FakeDockerCli: DockerCommandRunning` — `calls: [[String]]`, `commandLines: [String]`, `on(_:_:)`, `on(_:respond:)`, `onPrefix(_:respond:)` (restituiscono `self`), `static func ok(_:)`, `fail(_:)`, `withRealCase() throws`
  - test: `final class Shared<Value: Sendable>: Sendable` — `value`, `set(_:)`; per `Int`: `increment() -> Int`

- [ ] **Step 1: Scrivere la CLI finta e i test (falliscono)**

`Tests/CleanerCoreTests/Docker/FakeDockerCli.swift`:

```swift
import Synchronization
@testable import CleanerCore

/// CLI finta: risponde con le fixture per comando (argomenti uniti da spazi) e registra ogni
/// invocazione, così i test possono verificare COSA verrebbe eseguito su un Docker vero.
///
/// Diversamente dal doppio C#, che ignorava il `CancellationToken`, rifiuta di avviare un comando da
/// un task annullato, come `ProcessRunner`: così i test verificano anche che l'esecutore isoli
/// dall'annullamento i comandi che il C# lanciava con `CancellationToken.None`.
final class FakeDockerCli: DockerCommandRunning {
    typealias Respond = @Sendable ([String]) throws -> ProcessResult

    private struct State {
        var responses: [String: Respond] = [:]
        var prefixResponses: [(prefix: String, respond: Respond)] = []
        var calls: [[String]] = []
    }

    private let state = Mutex(State())

    var calls: [[String]] { state.withLock { $0.calls } }

    var commandLines: [String] { calls.map { $0.joined(separator: " ") } }

    @discardableResult
    func on(_ commandLine: String, _ standardOutput: String) -> FakeDockerCli {
        on(commandLine) { Self.ok(standardOutput) }
    }

    @discardableResult
    func on(_ commandLine: String, respond: @escaping @Sendable () throws -> ProcessResult) -> FakeDockerCli {
        state.withLock { $0.responses[commandLine] = { _ in try respond() } }
        return self
    }

    @discardableResult
    func onPrefix(_ prefix: String, respond: @escaping Respond) -> FakeDockerCli {
        state.withLock { $0.prefixResponses.append((prefix, respond)) }
        return self
    }

    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        try Task.checkCancellation()
        let line = arguments.joined(separator: " ")

        let respond: Respond? = state.withLock { state in
            state.calls.append(arguments)
            if let exact = state.responses[line] {
                return exact
            }
            // L'ultima registrata vince: un test può restringere una risposta generica ("rmi ") a un
            // caso specifico ("rmi sha256:d4…") aggiungendola dopo.
            return state.prefixResponses.last { DockerText.hasPrefix(line, $0.prefix) }?.respond
        }

        guard let respond else {
            return ProcessResult(exitCode: 1, standardOutput: "", standardError: "comando non previsto dal test: \(line)", timedOut: false)
        }
        return try respond(arguments)
    }

    static func ok(_ standardOutput: String = "") -> ProcessResult {
        ProcessResult(exitCode: 0, standardOutput: standardOutput, standardError: "", timedOut: false)
    }

    static func fail(_ standardError: String) -> ProcessResult {
        ProcessResult(exitCode: 1, standardOutput: "", standardError: standardError, timedOut: false)
    }

    /// Una CLI che risponde con l'intero caso reale delle fixture.
    static func withRealCase() throws -> FakeDockerCli {
        let json = "{{json .}}"
        let images = try DockerJson.parseImages(DockerFixtures.read("images.json"))
            .map { #"{"ID":"\#($0.id)","Repository":"x","Tag":"y"}"# }
            .joined(separator: "\n")
        let volumes = try DockerJson.parseVolumes(DockerFixtures.read("volumes.json"))
            .map { #"{"Name":"\#($0.name)","Driver":"local"}"# }
            .joined(separator: "\n")
        let containerIds = try DockerJson.parseContainers(DockerFixtures.read("containers.json")).map(\.id)
        let containersJson = try DockerFixtures.read("containers.json")
        let imagesJson = try DockerFixtures.read("images.json")
        let volumesJson = try DockerFixtures.read("volumes.json")

        return FakeDockerCli()
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"\n")
            .on("ps -aq --no-trunc", containerIds.joined(separator: "\n") + "\n")
            .onPrefix("container inspect ") { _ in ok(containersJson) }
            .on("images --no-trunc --format \(json)", images)
            .onPrefix("image inspect ") { _ in ok(imagesJson) }
            .on("volume ls --format \(json)", volumes)
            .onPrefix("volume inspect ") { _ in ok(volumesJson) }
            .on("system df -v --format \(json)", try DockerFixtures.read("df-verbose.json"))
            .on("system df --format \(json)", try DockerFixtures.read("df.jsonl"))
    }
}

/// Un valore condiviso fra il test e i callback `@Sendable` della CLI finta: l'equivalente delle
/// variabili locali catturate dalle lambda C# (`int dfCalls = 0; … dfCalls++`).
final class Shared<Value: Sendable>: Sendable {
    private let storage: Mutex<Value>

    init(_ value: Value) {
        storage = Mutex(value)
    }

    var value: Value { storage.withLock { $0 } }

    func set(_ value: Value) {
        storage.withLock { $0 = value }
    }
}

extension Shared where Value == Int {
    /// `++counter` del C#: incrementa e restituisce il nuovo valore.
    func increment() -> Int {
        storage.withLock { value in
            value += 1
            return value
        }
    }
}
```

`Tests/CleanerCoreTests/Docker/DockerCliTests.swift`:

```swift
import Darwin
import Testing
@testable import CleanerCore

struct DockerCliTests {
    private struct Call: Sendable {
        let file: String
        let arguments: [String]
        let environment: [String: String]?
    }

    private struct FakeRunner: ProcessRunning {
        let calls = Recorder<Call>()
        let respond: @Sendable (String, [String]) throws -> ProcessResult

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append(Call(file: executable, arguments: arguments, environment: environment))
            return try respond(executable, arguments)
        }
    }

    @Test(arguments: [
        "Cannot connect to the Docker daemon at unix:///Users/tester/.docker/run/docker.sock. Is the docker daemon running?",
        "error during connect: Get \"http://%2FUsers%2Ftester%2F.docker%2Frun%2Fdocker.sock/v1.47/info\": EOF",
        "failed to connect to the docker API at unix:///Users/tester/.docker/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /Users/tester/.docker/run/docker.sock: connect: no such file or directory",
        "dial unix /var/run/docker.sock: connect: connection refused",
    ])
    func recognizesAnUnreachableDaemon(standardError: String) {
        #expect(DockerCliErrors.isDaemonUnavailable(standardError))
    }

    @Test(arguments: [
        "Error response from daemon: conflict: unable to delete 2b5b58162112 (cannot be forced) - image is being used by running container e20bf2607c5b",
        "Error: No such image: testcontainers/ryuk:0.14.0",
        "",
    ])
    func ordinaryErrorsAreNotADaemonOutage(standardError: String) {
        #expect(!DockerCliErrors.isDaemonUnavailable(standardError))
    }

    @Test func argumentsArePassedVerbatimToTheLocatedBinary() async throws {
        let runner = FakeRunner { _, _ in ProcessResult(exitCode: 0, standardOutput: "ok", standardError: "", timedOut: false) }
        let cli = DockerCli(runner: runner, binaryPath: "/Users/tester/.docker/bin/docker")

        let result = try await cli.run(["images", "--format", "{{json .}}"])

        #expect(result.standardOutput == "ok")
        let call = try #require(runner.calls.values.first)
        #expect(runner.calls.values.count == 1)
        #expect(call.file == "/Users/tester/.docker/bin/docker")
        #expect(call.arguments == ["images", "--format", "{{json .}}"])
        // Un'app aperta dal Finder non eredita il PATH della shell: i plugin e gli helper della CLI
        // (buildx, credential helper) vanno resi raggiungibili esplicitamente.
        let path = try #require(call.environment?["PATH"])
        #expect(path.hasPrefix("/Users/tester/.docker/bin:"))
    }

    @Test func unreachableDaemonBecomesAReadableException() async {
        let runner = FakeRunner { _, _ in
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "Cannot connect to the Docker daemon at unix:///x.sock. Is the docker daemon running?", timedOut: false)
        }
        let cli = DockerCli(runner: runner, binaryPath: "/usr/local/bin/docker")

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }

        #expect(error?.message.contains("Docker non è in esecuzione") == true)
    }

    @Test func missingBinaryBecomesAReadableException() async {
        let cli = DockerCli(runner: FakeRunner { _, _ in throw ProcessLaunchError(executable: "docker", code: ENOENT) }, binaryPath: nil)

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }

        #expect(error?.message.contains("non è stato trovato") == true)
    }

    @Test func binaryThatCannotStartBecomesAReadableException() async {
        let cli = DockerCli(runner: FakeRunner { _, _ in throw ProcessLaunchError(executable: "/usr/local/bin/docker", code: ENOENT) }, binaryPath: "/usr/local/bin/docker")

        await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }
    }

    @Test func checkedRunFailsWithTheDockerErrorText() async {
        let cli = FakeDockerCli().on("volume inspect x") { FakeDockerCli.fail("Error response from daemon: get x: no such volume") }

        let error = await #expect(throws: DockerCommandError.self) {
            try await cli.runChecked(["volume", "inspect", "x"])
        }

        #expect(error?.message.contains("no such volume") == true)
    }

    @Test func checkedRunReportsATimeout() async {
        let cli = FakeDockerCli().on("system df") { ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true) }

        let error = await #expect(throws: DockerCommandError.self) {
            try await cli.runChecked(["system", "df"])
        }

        #expect(error?.message.contains("tempo") == true)
    }

    @Test func locatorPrefersTheDockerDesktopUserBinary() {
        let fs = InMemoryFileSystem()
        fs.addFile("/usr/local/bin/docker")
        fs.addFile("/Users/tester/.docker/bin/docker")

        #expect(DockerBinaryLocator.find(fs, homeDirectory: "/Users/tester") == "/Users/tester/.docker/bin/docker")
    }

    @Test func locatorFallsBackToTheAppBundle() {
        let fs = InMemoryFileSystem()
        fs.addFile("/Applications/Docker.app/Contents/Resources/bin/docker")

        #expect(DockerBinaryLocator.find(fs, homeDirectory: "/Users/tester") == "/Applications/Docker.app/Contents/Resources/bin/docker")
    }

    @Test func locatorReturnsNullWhenDockerIsNotInstalled() {
        #expect(DockerBinaryLocator.find(InMemoryFileSystem(), homeDirectory: "/Users/tester") == nil)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerCliTests`
Expected: errore di compilazione `cannot find type 'DockerCommandRunning' in scope` (e `cannot find 'DockerCli' in scope`).

- [ ] **Step 3: Implementare `DockerCli`**

`Sources/CleanerCore/Docker/DockerCli.swift`:

```swift
import Foundation

/// Docker non raggiungibile: binario assente, daemon spento, socket chiuso. Il messaggio è già
/// pensato per l'utente — l'interfaccia lo mostra così com'è. Porting di `DockerUnavailableException`.
public struct DockerUnavailableError: Error, Equatable, Sendable, LocalizedError {
    public static var notRunning: String {
        String(localized: "Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.", bundle: .module)
    }

    public static var notInstalled: String {
        String(localized: "Docker non è installato o non è stato trovato.", bundle: .module)
    }

    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Un comando Docker è fallito: il messaggio riporta il testo d'errore della CLI. Porting di
/// `DockerCommandException`.
public struct DockerCommandError: Error, Equatable, Sendable, LocalizedError {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Porting di `IDockerCli`: l'unico modo in cui il Core parla con Docker.
public protocol DockerCommandRunning: Sendable {
    /// `timeout` nullo: il limite predefinito della CLI (60 secondi).
    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult
}

extension DockerCommandRunning {
    public func run(_ arguments: [String]) async throws -> ProcessResult {
        try await run(arguments, timeout: nil)
    }

    /// Esegue e restituisce lo stdout; qualunque uscita diversa da zero diventa un errore leggibile.
    /// Il timeout si riconosce da `timedOut`, non dal codice di uscita.
    public func runChecked(_ arguments: [String]) async throws -> String {
        let result = try await run(arguments)

        if result.timedOut || result.exitCode != 0 {
            throw DockerCommandError("docker \(arguments.prefix(2).joined(separator: " ")): \(DockerCliErrors.describe(result))")
        }

        return result.standardOutput
    }
}

public enum DockerCliErrors {
    // Messaggi misurati sulle CLI 24–29: il testo cambia fra le versioni, il socket irraggiungibile no.
    private static let daemonUnavailableMarkers = [
        "Cannot connect to the Docker daemon",
        "Is the docker daemon running",
        "error during connect",
        "failed to connect to the docker API",
        "docker.sock: connect:",
    ]

    public static func isDaemonUnavailable(_ standardError: String) -> Bool {
        daemonUnavailableMarkers.contains { DockerText.containsIgnoringCase(standardError, $0) }
    }

    /// La prima riga utile dell'errore della CLI, senza il prefisso ripetuto dal daemon.
    public static func describe(_ result: ProcessResult) -> String {
        if result.timedOut {
            return String(localized: "Docker non ha risposto entro il tempo massimo", bundle: .module)
        }

        let line = DockerText.lines(result.standardError).first
            ?? String(localized: "codice di uscita \(String(result.exitCode))", bundle: .module)

        let prefix = "Error response from daemon: "
        return DockerText.hasPrefix(line, prefix)
            ? String(decoding: line.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
            : line
    }
}

/// Unico punto dell'applicazione che esegue il binario `docker`, sempre per percorso assoluto
/// (quello trovato da `DockerBinaryLocator`): `posix_spawnp` cerca un nome semplice nel PATH
/// dell'app, che dal Finder è solo `/usr/bin:/bin:/usr/sbin:/sbin`.
public struct DockerCli: DockerCommandRunning {
    private static let defaultTimeout: Duration = .seconds(60)

    private let runner: any ProcessRunning
    private let binaryPath: String?

    public init(runner: any ProcessRunning, binaryPath: String?) {
        self.runner = runner
        self.binaryPath = binaryPath
    }

    public func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult {
        guard let binaryPath else {
            throw DockerUnavailableError(DockerUnavailableError.notInstalled)
        }

        let result: ProcessResult
        do {
            result = try await runner.run(binaryPath, arguments, timeout: timeout ?? Self.defaultTimeout, environment: Self.environment(binaryPath))
        } catch is ProcessLaunchError {
            throw DockerUnavailableError(DockerUnavailableError.notInstalled)
        }

        // Il daemon può spegnersi in qualunque momento, anche fra un comando e l'altro di una
        // pulizia: ogni chiamata lo verifica, non solo la prima.
        if result.exitCode != 0 && DockerCliErrors.isDaemonUnavailable(result.standardError) {
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        return result
    }

    /// Un'app aperta dal Finder riceve un PATH minimo (/usr/bin:/bin:…): la CLI di Docker Desktop
    /// cerca accanto a sé i propri helper (credential helper, plugin), quindi la sua cartella va in
    /// testa.
    private static func environment(_ binary: String) -> [String: String] {
        let directory = PathText.parent(binary) ?? "/usr/local/bin"
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let path = "\(directory):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\(inherited)"
        return ["PATH": DockerText.trimmedTrailing(path, ":")]
    }
}

public enum DockerBinaryLocator {
    /// Percorsi noti, in ordine: Docker Desktop per l'utente, installazione di sistema, Homebrew,
    /// bundle dell'app.
    public static func find(_ fileSystem: any FileSystem, homeDirectory: String) -> String? {
        let candidates = [
            PathText.join(PathText.join(PathText.join(homeDirectory, ".docker"), "bin"), "docker"),
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]

        return candidates.first(where: fileSystem.fileExists)
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerCliTests`
Expected: `Test run with 11 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/DockerCliTests.cs` con:

```markdown
| Docker/DockerCliTests.cs | 11 (7) | Docker/DockerCliTests.swift | 11 (7) | 2 | «`Win32Exception`/`InvalidOperationException` del runner finto → `ProcessLaunchError`; `MockFileSystem` → `InMemoryFileSystem`» |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port the Docker CLI wrapper and binary locator

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `DockerInventoryCollector`

Solo comandi di lettura, solo JSON. Anche la verifica su disco della cartella di un progetto compose avviene qui, così che le regole restino funzioni pure dello snapshot.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerInventoryCollector.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerInventoryCollectorTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerInventoryCollector.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerInventoryCollectorTests.cs`

**Interfaces:**
- Consumes: `FileSystem` (piano 1); `DockerSnapshot`, `DockerText.trimmed` (Task 1); `DockerJson` (Task 2); `VolumeRuleContext.composeProjectLabel` (Task 3); `DockerCommandRunning`, `runChecked(_:)`, `DockerUnavailableError`, `FakeDockerCli` (Task 5).
- Produces:
  - `public struct DockerInventoryCollector: Sendable` — `init(cli: any DockerCommandRunning, fileSystem: any FileSystem)`; `func checkDaemon() async throws -> String`; `@concurrent func collect() async throws -> DockerSnapshot`; `static func readDf(_: any DockerCommandRunning) async throws -> DockerDfSummary`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DockerInventoryCollectorTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DockerInventoryCollectorTests {
    @Test func collectsTheWholeInventoryFromJsonOutput() async throws {
        let snapshot = try await DockerInventoryCollector(cli: FakeDockerCli.withRealCase(), fileSystem: InMemoryFileSystem()).collect()

        #expect(snapshot.containers.count == 2)
        #expect(snapshot.images.count == 10)
        #expect(snapshot.volumes.count == 6)
        #expect(snapshot.images.first { $0.id == DockerFixtures.dcptunId }?.uniqueSizeBytes == 76_740_000)
        #expect(snapshot.volumes.first { $0.name == "orbit.apphost-48d90b1972-sql-data" }?.sizeBytes == 158_300_000)
        #expect(snapshot.df.buildCache == 106_900_000)
    }

    @Test func inspectsAllImagesInOneCallById() async throws {
        let cli = try FakeDockerCli.withRealCase()

        _ = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()

        let inspects = cli.calls.filter { $0.first == "image" }
        let inspect = try #require(inspects.first)
        #expect(inspects.count == 1)
        #expect(inspect.count == 12)
        #expect(inspect.dropFirst(2).allSatisfy { $0.hasPrefix("sha256:") })
    }

    @Test func onlyReadOnlyCommandsAreUsed() async throws {
        let cli = try FakeDockerCli.withRealCase()

        _ = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()

        let readOnly = ["info", "ps", "container inspect", "images", "image inspect", "volume ls", "volume inspect", "system df"]
        for line in cli.commandLines {
            #expect(readOnly.contains { line.hasPrefix($0) })
        }
    }

    @Test func emptyListsAreNotInspected() async throws {
        let cli = FakeDockerCli()
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"")
            .on("ps -aq --no-trunc", "")
            .on("images --no-trunc --format {{json .}}", "")
            .on("volume ls --format {{json .}}", "")
            .on("system df -v --format {{json .}}", #"{"Images":[],"Containers":[],"Volumes":[],"BuildCache":[]}"#)
            .on("system df --format {{json .}}", "")

        let snapshot = try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()

        #expect(snapshot.images.isEmpty)
        #expect(!cli.commandLines.contains { $0.contains("inspect") })
    }

    @Test func composeProjectExistsWhenItsWorkingDirectoryIsStillOnDisk() async throws {
        let containers = """
            [{"Id":"1","Name":"/shop-db-1","Image":"sha256:1","State":{"Status":"exited","ExitCode":0},"Mounts":[],
              "Config":{"Labels":{"com.docker.compose.project":"shop","com.docker.compose.project.working_dir":"/Users/tester/projects/shop"}}},
             {"Id":"2","Name":"/old-db-1","Image":"sha256:1","State":{"Status":"exited","ExitCode":0},"Mounts":[],
              "Config":{"Labels":{"com.docker.compose.project":"old","com.docker.compose.project.working_dir":"/Users/tester/projects/old"}}}]
            """
        let cli = FakeDockerCli()
            .on("info --format {{json .ServerVersion}}", "\"29.8.0\"")
            .on("ps -aq --no-trunc", "1\n2\n")
            .on("container inspect 1 2", containers)
            .on("images --no-trunc --format {{json .}}", "")
            .on("volume ls --format {{json .}}", "")
            .on("system df -v --format {{json .}}", "{}")
            .on("system df --format {{json .}}", "")
        let fs = InMemoryFileSystem()
        fs.addDirectory("/Users/tester/projects/shop")

        let snapshot = try await DockerInventoryCollector(cli: cli, fileSystem: fs).collect()

        #expect(snapshot.existingComposeProjects == ["shop"])
    }

    @Test func daemonThatDoesNotAnswerStopsTheCollection() async {
        let cli = FakeDockerCli()
            .on("info --format {{json .ServerVersion}}") { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }
        #expect(cli.calls.count == 1)
    }

    @Test func emptyServerVersionMeansTheDaemonIsNotRunning() async {
        // Senza daemon, "docker info" può comunque stampare la parte client e uscire con 0.
        let cli = FakeDockerCli().on("info --format {{json .ServerVersion}}", "\"\"")

        await #expect(throws: DockerUnavailableError.self) {
            try await DockerInventoryCollector(cli: cli, fileSystem: InMemoryFileSystem()).collect()
        }
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerInventoryCollectorTests`
Expected: errore di compilazione `cannot find 'DockerInventoryCollector' in scope`.

- [ ] **Step 3: Implementare `DockerInventoryCollector`**

`Sources/CleanerCore/Docker/DockerInventoryCollector.swift`:

```swift
/// Raccoglie lo stato di Docker con soli comandi di lettura e in formato JSON. Ogni I/O che la
/// classificazione richiede (incluso controllare che la cartella di un progetto compose esista)
/// avviene qui, così che le regole restino funzioni pure dello snapshot.
public struct DockerInventoryCollector: Sendable {
    private static let json = "{{json .}}"
    private static let composeWorkingDirLabel = "com.docker.compose.project.working_dir"

    private let cli: any DockerCommandRunning
    private let fileSystem: any FileSystem

    public init(cli: any DockerCommandRunning, fileSystem: any FileSystem) {
        self.cli = cli
        self.fileSystem = fileSystem
    }

    /// Verifica che il daemon risponda. Restituisce la versione del server.
    public func checkDaemon() async throws -> String {
        let output = try await cli.runChecked(["info", "--format", "{{json .ServerVersion}}"])
        let version = DockerText.trimmed(DockerText.trimmed(output), "\"")

        // Senza daemon "docker info" può stampare comunque la parte client e uscire con 0: una
        // versione del server vuota è l'unico segnale affidabile.
        if version.isEmpty || version == "null" {
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        return version
    }

    @concurrent
    public func collect() async throws -> DockerSnapshot {
        _ = try await checkDaemon()

        // Container compresi quelli fermi (-a): un container fermo tiene in uso immagine e volumi.
        let containerIds = DockerJson.parseLines(try await cli.runChecked(["ps", "-aq", "--no-trunc"]))
        let containers: [DockerContainer] = if containerIds.isEmpty {
            []
        } else {
            try DockerJson.parseContainers(try await cli.runChecked(["container", "inspect"] + containerIds))
        }

        let imageIds = try DockerJson.parseJsonLinesProperty(
            try await cli.runChecked(["images", "--no-trunc", "--format", Self.json]), "ID")
        let volumeNames = try DockerJson.parseJsonLinesProperty(
            try await cli.runChecked(["volume", "ls", "--format", Self.json]), "Name")

        let verbose = try DockerJson.parseDfVerbose(try await cli.runChecked(["system", "df", "-v", "--format", Self.json]))

        let images: [DockerImage] = if imageIds.isEmpty {
            []
        } else {
            try DockerJson.parseImages(try await cli.runChecked(["image", "inspect"] + imageIds), uniqueSizes: verbose.imageUniqueSizes)
        }
        let volumes: [DockerVolume] = if volumeNames.isEmpty {
            []
        } else {
            try DockerJson.parseVolumes(try await cli.runChecked(["volume", "inspect"] + volumeNames), sizes: verbose.volumeSizes)
        }

        let df = try await Self.readDf(cli)

        return DockerSnapshot(
            containers: containers,
            images: images,
            volumes: volumes,
            df: df,
            existingComposeProjects: existingComposeProjects(containers))
    }

    /// Riepilogo di `docker system df`: condiviso con l'esecutore per la misura prima/dopo.
    public static func readDf(_ cli: any DockerCommandRunning) async throws -> DockerDfSummary {
        try DockerJson.parseDfSummary(try await cli.runChecked(["system", "df", "--format", json]))
    }

    /// I volumi compose portano solo il nome del progetto; la sua cartella si legge dalle etichette
    /// dei container dello stesso progetto. Le cartelle trovate nei progetti dell'utente si
    /// aggiungono in fase di classificazione (`ProjectReferences.composeProjects`).
    private func existingComposeProjects(_ containers: [DockerContainer]) -> Set<String> {
        var projects = Set<String>()

        for container in containers {
            if let project = container.labels[VolumeRuleContext.composeProjectLabel],
               let directory = container.labels[Self.composeWorkingDirLabel],
               fileSystem.directoryExists(directory) {
                projects.insert(project)
            }
        }

        return projects
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerInventoryCollectorTests`
Expected: `Test run with 7 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/DockerInventoryCollectorTests.cs` con:

```markdown
| Docker/DockerInventoryCollectorTests.cs | 7 | Docker/DockerInventoryCollectorTests.swift | 7 | 2 | «`MockFileSystem` → `InMemoryFileSystem`» |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port DockerInventoryCollector

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `DiskUsageProbe`

`Docker.raw` è un file sparse: la dimensione apparente è il limite del disco virtuale, solo i blocchi allocati (`du -k`) dicono quanto si è recuperato. Il file si legge e basta.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DiskUsageProbe.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DiskUsageProbeTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DiskUsageProbe.cs`; `tests/MjmCleaner.Core.Tests/Docker/DiskUsageProbeTests.cs`

**Interfaces:**
- Consumes (piano 1): `ProcessRunning` e `run(_:_:timeout:)`, `FileSystem.fileExists`, `fileLength`, `FileSystemError`, `PathText.trimmingTrailingSlashes`; test: `InMemoryFileSystem`, `Recorder`.
- Produces:
  - `public struct DockerDiskUsage: Sendable, Equatable` — `path`, `allocatedBytes: Int64?`, `apparentBytes: Int64?`; `init(path:allocatedBytes:apparentBytes:)`; `exists`
  - `public struct DiskUsageProbe: Sendable` — `init(runner: any ProcessRunning, fileSystem: any FileSystem, diskImagePath: String)`; `static func defaultPath(_ homeDirectory: String) -> String`; `@concurrent func measure() async throws -> DockerDiskUsage` (lancia solo `CancellationError`); `static func parseDuKilobytes(_: String) -> Int64?`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DiskUsageProbeTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DiskUsageProbeTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

    private struct DuRunner: ProcessRunning {
        let standardOutput: String
        var exitCode: Int32 = 0
        let calls = Recorder<[String]>()

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append([executable] + arguments)
            return ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: "", timedOut: false)
        }
    }

    @Test(arguments: [
        ("8677192\t/Users/tester/Docker.raw\n", Int64(8_677_192) * 1024),
        ("0\t/x\n", 0),
    ])
    func parsesTheKilobytesPrintedByDu(output: String, expected: Int64) {
        #expect(DiskUsageProbe.parseDuKilobytes(output) == expected)
    }

    @Test func unreadableDuOutputIsUnknown() {
        #expect(DiskUsageProbe.parseDuKilobytes("du: Docker.raw: Operation not permitted") == nil)
    }

    @Test func defaultPathIsTheDockerDesktopDiskOnMacOS() {
        #expect(DiskUsageProbe.defaultPath("/Users/tester") == Self.rawPath)
    }

    @Test func sparseFileReportsBothAllocatedAndApparentSize() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 4096)
        let du = DuRunner(standardOutput: "8\t" + Self.rawPath + "\n")

        let usage = try await DiskUsageProbe(runner: du, fileSystem: fs, diskImagePath: Self.rawPath).measure()

        #expect(usage.exists)
        #expect(usage.allocatedBytes == Int64(8 * 1024))
        #expect(usage.apparentBytes == 4096)
        #expect(du.calls.values == [["du", "-k", Self.rawPath]])
    }

    @Test func missingDiskImageIsReportedWithoutRunningDu() async throws {
        let du = DuRunner(standardOutput: "")

        let usage = try await DiskUsageProbe(runner: du, fileSystem: InMemoryFileSystem(), diskImagePath: Self.rawPath).measure()

        #expect(!usage.exists)
        #expect(usage.allocatedBytes == nil)
        #expect(du.calls.values.isEmpty)
    }

    @Test func failingDuLeavesOnlyTheApparentSize() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.rawPath, size: 10)

        let usage = try await DiskUsageProbe(runner: DuRunner(standardOutput: "", exitCode: 1), fileSystem: fs, diskImagePath: Self.rawPath).measure()

        #expect(usage.allocatedBytes == nil)
        #expect(usage.apparentBytes == 10)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DiskUsageProbeTests`
Expected: errore di compilazione `cannot find 'DiskUsageProbe' in scope`.

- [ ] **Step 3: Implementare `DiskUsageProbe`**

`Sources/CleanerCore/Docker/DiskUsageProbe.swift`:

```swift
/// `allocatedBytes`: spazio realmente occupato sul disco (blocchi allocati, come `du`).
/// `apparentBytes`: dimensione apparente; per un file sparse è solo il limite massimo del disco
/// virtuale.
public struct DockerDiskUsage: Sendable, Equatable {
    public let path: String
    public let allocatedBytes: Int64?
    public let apparentBytes: Int64?

    public init(path: String, allocatedBytes: Int64?, apparentBytes: Int64?) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.apparentBytes = apparentBytes
    }

    public var exists: Bool { apparentBytes != nil }
}

/// Misura il disco virtuale di Docker Desktop. `Docker.raw` è un file sparse: la sua dimensione
/// apparente (misurata: 994 GB) è il limite configurato, non lo spazio occupato (8,3 GB nello stesso
/// momento). Solo i blocchi allocati dicono quanto disco si è recuperato. Il file si legge e basta:
/// la deny-list continua a proteggere l'intera cartella di Docker.
public struct DiskUsageProbe: Sendable {
    private static let duTimeout: Duration = .seconds(20)

    private let runner: any ProcessRunning
    private let fileSystem: any FileSystem
    private let diskImagePath: String

    public init(runner: any ProcessRunning, fileSystem: any FileSystem, diskImagePath: String) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.diskImagePath = diskImagePath
    }

    public static func defaultPath(_ homeDirectory: String) -> String {
        "\(PathText.trimmingTrailingSlashes(homeDirectory))/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    }

    /// Lancia solo `CancellationError`: una misura non disponibile non deve impedire né l'analisi né
    /// la pulizia.
    @concurrent
    public func measure() async throws -> DockerDiskUsage {
        // Altre piattaforme, Docker non Desktop (Colima, OrbStack) o un disco spostato altrove: il
        // file può non esistere, e allora non c'è nulla da misurare.
        guard fileSystem.fileExists(diskImagePath) else {
            return DockerDiskUsage(path: diskImagePath, allocatedBytes: nil, apparentBytes: nil)
        }

        let apparent: Int64
        do {
            apparent = try fileSystem.fileLength(diskImagePath)
        } catch is FileSystemError {
            return DockerDiskUsage(path: diskImagePath, allocatedBytes: nil, apparentBytes: nil)
        }

        var allocated: Int64?
        do {
            // `du` per nome, come in C#: sta in /usr/bin, che è nel PATH anche di un'app aperta dal Finder.
            let du = try await runner.run("du", ["-k", diskImagePath], timeout: Self.duTimeout)
            if du.exitCode == 0 && !du.timedOut {
                allocated = Self.parseDuKilobytes(du.standardOutput)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            // Una misura non disponibile non deve impedire né l'analisi né la pulizia.
        }

        return DockerDiskUsage(path: diskImagePath, allocatedBytes: allocated, apparentBytes: apparent)
    }

    /// Prima colonna dell'output di `du -k`: blocchi da 1 KiB.
    public static func parseDuKilobytes(_ output: String) -> Int64? {
        // `output.Split(['\t', ' ', '\n'], 2, RemoveEmptyEntries).FirstOrDefault()`.
        let separators: Set<UInt8> = [UInt8(ascii: "\t"), UInt8(ascii: " "), UInt8(ascii: "\n")]
        let first = output.utf8.drop { separators.contains($0) }.prefix { !separators.contains($0) }

        // `long.TryParse(…, NumberStyles.None, …)`: solo cifre ASCII, niente segno né spazi.
        guard !first.isEmpty,
              first.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
              let kilobytes = Int64(String(decoding: first, as: UTF8.self)) else {
            return nil
        }
        // Come l'aritmetica non verificata del C#: nessuna trappola su un valore assurdo.
        return kilobytes &* 1024
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DiskUsageProbeTests`
Expected: `Test run with 6 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/DiskUsageProbeTests.cs` con:

```markdown
| Docker/DiskUsageProbeTests.cs | 6 (2) | Docker/DiskUsageProbeTests.swift | 6 (2) | 2 | «`MockFileData(new byte[n])` → `addFile(_:size:)`» |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port DiskUsageProbe for Docker.raw

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `ProjectReferenceScanner`

Il componente con più regex: ognuna è tradotta con la tabella delle convenzioni, e i quattro test solo-Swift riproducono gli esiti del C# reale (harness .NET 10) dove Swift e .NET divergerebbero con una traduzione ingenua: classi `\w`, `IgnoreCase`, ancora `^` multilinea, BOM, separatori fra scalari. L'attraversamento è quello del C#: pila esplicita, profondità massima 12, cartelle escluse confrontate senza maiuscole, collegamenti non seguiti, file oltre 1 MB ignorati.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/ProjectReferenceScanner.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/ProjectReferenceScannerTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/ProjectReferenceScanner.cs`; `tests/MjmCleaner.Core.Tests/Docker/ProjectReferenceScannerTests.cs`

**Interfaces:**
- Consumes (piano 1): `FileSystem` (`directoryExists`, `contentsOfDirectory`, `itemInfo`, `fileLength`, `readData`, `writeData` nei test), `FileSystemError`, `PathText.fileName`/`parent`/`folded`; test: `InMemoryFileSystem`. Task 1: `ImageName`, `ImageReference`, `ProjectReferences`, `DockerText` (`rawLines`, `lineStarts`, `lowercasedInvariant`, `decodeLikeReadAllText`, `contains`, `hasPrefix`, `hasSuffixIgnoringCase`, `isBlank`, `trimmedTrailing`).
- Produces:
  - `public struct ProjectReferenceScanner: Sendable` — `init(fileSystem: any FileSystem)`; `func scan(_ roots: [String]) throws -> ProjectReferences` (lancia solo `CancellationError`)

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/ProjectReferenceScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct ProjectReferenceScannerTests {
    /// `(Repository, Tag)` del C#: le tuple Swift non sono `Equatable` dentro un array.
    private struct Found: Equatable, CustomStringConvertible {
        let repository: String
        let tag: String?

        init(_ repository: String, _ tag: String?) {
            self.repository = repository
            self.tag = tag
        }

        var description: String { "(\(repository), \(tag ?? "nil"))" }
    }

    private func scan(_ files: (path: String, content: String)...) throws -> ProjectReferences {
        let fs = InMemoryFileSystem()
        fs.addDirectory("/p")
        for (path, content) in files {
            fs.addFile(path, text: content)
        }

        return try ProjectReferenceScanner(fileSystem: fs).scan(["/p"])
    }

    /// `.Order()` del C# sulle tuple: repository, poi tag con `nil` per primo.
    private func images(_ references: ProjectReferences) -> [Found] {
        references.images.map { Found($0.repository, $0.tag) }.sorted { lhs, rhs in
            if lhs.repository != rhs.repository { return lhs.repository < rhs.repository }
            switch (lhs.tag, rhs.tag) {
            case let (left?, right?): return left < right
            case (nil, _?): return true
            default: return false
            }
        }
    }

    @Test func composeImagesAreReadWithFileAndLine() throws {
        let found = try scan(("/p/shop/compose.yaml", """
            services:
              db:
                image: postgres:16
              cache:
                image: "redis"
            """))

        #expect(images(found) == [Found("docker.io/library/postgres", "16"), Found("docker.io/library/redis", nil)])
        let postgres = try #require(found.images.first { $0.tag == "16" })
        #expect(postgres.file == "/p/shop/compose.yaml")
        #expect(postgres.line == 3)
    }

    @Test func composeProjectNameComesFromTheFolderWhenNotDeclared() throws {
        let found = try scan(("/p/My Shop/docker-compose.override.yml", "services: {}\n"))

        #expect(found.composeProjects == ["myshop"])
    }

    @Test func composeProjectNameDeclaredInTheFileWins() throws {
        let found = try scan(("/p/shop/compose.yml", "name: Orbit-Stack\nservices: {}\n"))

        #expect(found.composeProjects == ["orbit-stack"])
    }

    @Test func dockerfileFromLinesSkipStageNamesAndScratch() throws {
        let found = try scan(("/p/api/Dockerfile", """
            FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0 AS build
            RUN dotnet publish
            FROM build AS publish
            FROM scratch AS empty
            from mcr.microsoft.com/dotnet/aspnet:9.0
            """))

        #expect(images(found) == [Found("mcr.microsoft.com/dotnet/aspnet", "9.0"), Found("mcr.microsoft.com/dotnet/sdk", "9.0")])
    }

    @Test func aspireAppHostResourcesMapToTheirImages() throws {
        let found = try scan(("/p/Orbit.AppHost/Program.cs", """
            var builder = DistributedApplication.CreateBuilder(args);

            var sql = builder.AddSqlServer("sql")
                .WithImageTag("2025-latest")
                .WithDataVolume();

            var keycloak = builder.AddKeycloak("keycloak", 8080);

            var storage = builder.AddAzureStorage("storage")
                .RunAsEmulator(emulator => emulator.WithImageTag("3.35.0"));

            var mail = builder.AddContainer("mail", "axllent/mailpit", "v1.20");

            var custom = builder.AddRedis("cache").WithImage("quay.io/opstree/redis", "7.2");

            builder.Build().Run();
            """))

        #expect(images(found) == [
            Found("docker.io/axllent/mailpit", "v1.20"),
            Found("mcr.microsoft.com/azure-storage/azurite", "3.35.0"),
            Found("mcr.microsoft.com/mssql/server", "2025-latest"),
            Found("quay.io/keycloak/keycloak", nil),
            Found("quay.io/opstree/redis", "7.2"),
        ])
        #expect(found.images.first { $0.tag == "2025-latest" }?.line == 3)
    }

    @Test func withImageRegistryPrefixesTheRepository() throws {
        let found = try scan(("/p/Orbit.AppHost/Program.cs", """
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddContainer("api", "acme/api").WithImageRegistry("ghcr.io").WithImageTag("2.0");
            """))

        #expect(images(found) == [Found("ghcr.io/acme/api", "2.0")])
    }

    @Test func testcontainersBuildersAndExplicitImagesAreFound() throws {
        let found = try scan(("/p/Tests/Fixture.cs", """
            using Testcontainers.MsSql;

            var sql = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();
            var plain = new ContainerBuilder().WithImage("alpine:3.20").Build();
            var redis = new RedisBuilder().Build();
            """))

        #expect(images(found) == [
            Found("docker.io/library/alpine", "3.20"),
            Found("docker.io/library/redis", nil),
            Found("mcr.microsoft.com/mssql/server", "2022-latest"),
        ])
    }

    @Test func ordinaryCSharpFilesAreNotScanned() throws {
        let found = try scan(("/p/Api/Service.cs", """
            var name = "postgres:16";
            var x = something.WithImage("alpine:3.20");
            """))

        #expect(found.images.isEmpty)
    }

    @Test func kubernetesAndHelmManifestsAreRead() throws {
        let found = try scan(
            ("/p/deploy/deployment.yaml", """
                spec:
                  containers:
                    - name: web
                      image: nginx:1.27
                """),
            ("/p/deploy/chart/values.yaml", """
                image:
                  repository: ghcr.io/acme/api
                  pullPolicy: IfNotPresent
                  tag: "1.4.2"
                """))

        #expect(images(found) == [Found("docker.io/library/nginx", "1.27"), Found("ghcr.io/acme/api", "1.4.2")])
    }

    @Test func templatedValuesAreIgnored() throws {
        let found = try scan(("/p/shop/compose.yaml", """
            services:
              api:
                image: ${REGISTRY}/api:${TAG}
              web:
                image: "{{ .Values.image }}"
            """))

        #expect(found.images.isEmpty)
    }

    @Test(arguments: ["node_modules", "bin", "obj", ".git"])
    func excludedFoldersAreSkipped(folder: String) throws {
        let found = try scan(("/p/web/\(folder)/pkg/docker-compose.yml", "services:\n  x:\n    image: postgres:16\n"))

        #expect(found.images.isEmpty)
        #expect(found.composeProjects.isEmpty)
    }

    @Test func filesLargerThanOneMegabyteAreSkipped() throws {
        let found = try scan(("/p/deploy/huge.yaml", "image: nginx:1.27\n" + String(repeating: "#", count: 1_100_000)))

        #expect(found.images.isEmpty)
    }

    // MARK: - Solo Swift: esiti del C# reale (harness .NET 10 durante la stesura del piano 2)

    @Test func fileNamesAreClassifiedLikeTheGeneratedDotNetRegexes() throws {
        // Un carattere fuori dal piano base non è `\w` per .NET: il file resta un YAML qualunque.
        let supplementary = try scan(("/p/a/compose\u{1D400}.yml", "image: nginx:1\n"))
        #expect(images(supplementary) == [Found("docker.io/library/nginx", "1")])
        #expect(supplementary.composeProjects.isEmpty)

        // Il segno Kelvin equivale a "k" anche per l'IgnoreCase di .NET.
        #expect(try scan(("/p/a/doc\u{212A}er-compose.yml", "image: nginx:1\n")).composeProjects == ["a"])

        // U+0130 non equivale a "i" nella cultura invariante delle regex generate.
        #expect(try scan(("/p/a/Dockerf\u{130}le", "FROM alpine:3.20\n")).images.isEmpty)
    }

    @Test func composeNameFollowsTheDotNetMultilineAnchor() throws {
        // "^" vale solo dopo "\n", e `\s*` prosegue sulla riga seguente.
        #expect(try scan(("/p/b/compose.yml", "x: 1\rname: bad\nname:\n  good\n")).composeProjects == ["good"])
        #expect(try scan(("/p/b/compose.yml", "x: 1\u{2028}name: bad\n")).composeProjects == ["b"])
    }

    @Test func projectFilesAreDecodedLikeReadAllText() throws {
        let fs = InMemoryFileSystem()
        fs.addDirectory("/p/c")
        fs.addDirectory("/p/w")
        try fs.writeData("/p/c/compose.yml", Data([0xEF, 0xBB, 0xBF]) + Data("name: Bom\nservices:\n  x:\n    image: redis:7\n".utf8))
        try fs.writeData("/p/w/compose.yml", Data([0xFF, 0xFE]) + Data("name: Wide\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }))

        let found = try ProjectReferenceScanner(fileSystem: fs).scan(["/p"])

        #expect(found.composeProjects == ["bom", "wide"])
        #expect(found.images.map(\.line) == [4])
    }

    @Test func cSharpStatementsAreSplitOnScalars() throws {
        // Un segno combinante dopo ";" non nasconde la fine dell'istruzione; U+2028 è uno spazio
        // per `TrimStart` ma non conta come riga.
        let combining = try scan(("/p/d/AppHost.cs", "var b = DistributedApplication.CreateBuilder(args);\u{301}builder.AddRedis(\"r\");"))
        #expect(combining.images.map(\.line) == [1])

        let separator = try scan(("/p/d/AppHost.cs", "DistributedApplication;\n\u{2028}\n  builder.AddRedis(\"x\");"))
        #expect(separator.images.map(\.line) == [3])
    }

    @Test func missingRootProducesNoReferences() throws {
        let found = try ProjectReferenceScanner(fileSystem: InMemoryFileSystem()).scan(["/nope"])

        #expect(found.images.isEmpty)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter ProjectReferenceScannerTests`
Expected: errore di compilazione `cannot find 'ProjectReferenceScanner' in scope`.

- [ ] **Step 3: Implementare `ProjectReferenceScanner`**

`Sources/CleanerCore/Docker/ProjectReferenceScanner.swift`:

```swift
/// Cerca nei file dei progetti le immagini che vi sono citate: un'immagine che un compose, un
/// Dockerfile o un AppHost useranno al prossimo avvio non va proposta per la cancellazione solo
/// perché oggi nessun container la usa. Regex per riga o per istruzione, non un parser YAML/C#: deve
/// restare veloce su un'intera cartella di progetti, e un riferimento mancato costa al massimo una
/// voce PROPOSE che l'utente vede e può lasciare deselezionata.
///
/// Le regex sono il porting di quelle generate del C# con la semantica di .NET 10 (misurata durante
/// la stesura del piano 2): corrispondenza per scalare (`.unicodeScalar`), `.` di .NET come `[^\n]`,
/// `\w` di .NET come `[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]`, `$` di .NET come `\n?$`, e
/// per `IgnoreCase` la "i" anche come U+0130, che .NET le equipara e Swift no. `Regex` non è
/// `Sendable`: le regex si costruiscono a ogni ricerca, una volta per file.
public struct ProjectReferenceScanner: Sendable {
    private static let maxFileBytes: Int64 = 1024 * 1024
    private static let maxDepth = 12

    /// Confronto `OrdinalIgnoreCase`: i nomi sono già ripiegati, come le chiavi cercate.
    private static let excludedDirectories = Set([
        "node_modules", "bin", "obj", ".git", ".hg", ".svn", ".vs", ".idea", "packages",
        ".venv", "venv", "__pycache__", "dist", "target", ".gradle", "Pods", "DerivedData",
    ].map(PathText.folded))

    /// Metodi di hosting di .NET Aspire → repository dell'immagine che avviano.
    private static let aspireResources: [String: String] = [
        "SqlServer": "mcr.microsoft.com/mssql/server",
        "Keycloak": "quay.io/keycloak/keycloak",
        "AzureStorage": "mcr.microsoft.com/azure-storage/azurite",
        "AzureCosmosDB": "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator",
        "AzureServiceBus": "mcr.microsoft.com/azure-messaging/servicebus-emulator",
        "AzureEventHubs": "mcr.microsoft.com/azure-messaging/eventhubs-emulator",
        "Redis": "redis",
        "Valkey": "valkey/valkey",
        "Garnet": "ghcr.io/microsoft/garnet",
        "Postgres": "postgres",
        "MySql": "mysql",
        "MongoDB": "mongo",
        "RabbitMQ": "rabbitmq",
        "Kafka": "confluentinc/confluent-local",
        "Nats": "nats",
        "Seq": "datalust/seq",
        "Elasticsearch": "docker.elastic.co/elasticsearch/elasticsearch",
        "Qdrant": "qdrant/qdrant",
        "Milvus": "milvusdb/milvus",
        "Oracle": "container-registry.oracle.com/database/free",
    ]

    /// Builder dei moduli Testcontainers → repository predefinito.
    private static let testcontainersBuilders: [String: String] = [
        "MsSqlBuilder": "mcr.microsoft.com/mssql/server",
        "PostgreSqlBuilder": "postgres",
        "RedisBuilder": "redis",
        "AzuriteBuilder": "mcr.microsoft.com/azure-storage/azurite",
        "KeycloakBuilder": "quay.io/keycloak/keycloak",
        "RabbitMqBuilder": "rabbitmq",
        "MongoDbBuilder": "mongo",
        "MySqlBuilder": "mysql",
        "KafkaBuilder": "confluentinc/cp-kafka",
        "ElasticsearchBuilder": "docker.elastic.co/elasticsearch/elasticsearch",
    ]

    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    /// Lancia solo `CancellationError`. Sincrona come in C#: chi la chiama da codice asincrono la
    /// esegue fuori dal proprio executor (`DockerCleanupService.analyze`).
    public func scan(_ roots: [String]) throws -> ProjectReferences {
        var images: [ImageReference] = []
        var composeProjects = Set<String>()

        for root in roots {
            try forEachFile(under: root) { file in
                try Task.checkCancellation()

                let kind = Self.classify(PathText.fileName(file))
                guard kind != .none, let text = read(file) else { return }

                switch kind {
                case .compose:
                    images += Self.yamlImageLines(file, text)
                    composeProjects.insert(composeProjectName(file, text))
                case .dockerfile:
                    images += Self.dockerfileFromLines(file, text)
                case .cSharp:
                    images += Self.cSharpReferences(file, text)
                case .yaml:
                    images += Self.yamlImageLines(file, text)
                    images += Self.helmRepositoryTags(file, text)
                case .none:
                    break
                }
            }
        }

        return ProjectReferences(images: images, composeProjects: composeProjects)
    }

    // MARK: - Attraversamento

    /// Visita in profondità con una pila esplicita, come il C#: i file di una cartella, poi le
    /// sottocartelle in ordine inverso. L'elenco di una cartella è in ordine ordinale (il C# seguiva
    /// l'ordine di `readdir`, che non è garantito).
    private func forEachFile(under root: String, _ visit: (String) throws -> Void) throws {
        guard fileSystem.directoryExists(root) else { return }

        var pending: [(path: String, depth: Int)] = [(root, 0)]

        while let (directory, depth) = pending.popLast() {
            try Task.checkCancellation()

            let entries: [String]
            do {
                entries = try fileSystem.contentsOfDirectory(directory)
            } catch is FileSystemError {
                continue
            }

            // Come `EnumerateFiles`/`EnumerateDirectories`: un collegamento a una cartella conta
            // come cartella (e poi si scarta sotto), tutto il resto come file.
            let children = entries.filter(fileSystem.directoryExists)
            for file in entries where !fileSystem.directoryExists(file) {
                try visit(file)
            }

            if depth >= Self.maxDepth {
                continue
            }

            for child in children where !Self.excludedDirectories.contains(PathText.folded(PathText.fileName(child))) && !isLink(child) {
                pending.append((child, depth + 1))
            }
        }
    }

    /// I collegamenti non si seguono: un link a "/" o a un'altra cartella progetto renderebbe la
    /// ricerca lenta o ciclica.
    private func isLink(_ directory: String) -> Bool {
        do {
            return try fileSystem.itemInfo(directory).kind == .symbolicLink
        } catch {
            return true
        }
    }

    /// Come `FileInfo.Length` (del collegamento stesso, `lstat`) e poi `File.ReadAllText`.
    private func read(_ file: String) -> String? {
        do {
            if try fileSystem.fileLength(file) > Self.maxFileBytes {
                return nil
            }
            return DockerText.decodeLikeReadAllText(try fileSystem.readData(file))
        } catch {
            return nil
        }
    }

    private enum FileKind {
        case none
        case compose
        case dockerfile
        case cSharp
        case yaml
    }

    private static func classify(_ name: String) -> FileKind {
        // `^(docker-)?compose[\w.-]*\.ya?ml$`, IgnoreCase.
        let composeFileName = /^(?:docker-)?compose[[\p{L}\p{Mn}\p{Nd}\p{Pc}.\-]&&[\x{0}-\x{FFFF}]]*\.ya?ml\n?$/
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)
        // `^((Dockerfile|Containerfile)[\w.-]*|[\w.-]+\.Dockerfile)$`, IgnoreCase.
        let dockerfileName = /^(?:(?:Dockerfile|Containerfile)[[\p{L}\p{Mn}\p{Nd}\p{Pc}.\-]&&[\x{0}-\x{FFFF}]]*|[[\p{L}\p{Mn}\p{Nd}\p{Pc}.\-]&&[\x{0}-\x{FFFF}]]+\.Dockerfile)\n?$/
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)

        if name.firstMatch(of: composeFileName) != nil {
            return .compose
        }

        if name.firstMatch(of: dockerfileName) != nil {
            return .dockerfile
        }

        if DockerText.hasSuffixIgnoringCase(name, ".cs") {
            return .cSharp
        }

        return DockerText.hasSuffixIgnoringCase(name, ".yaml") || DockerText.hasSuffixIgnoringCase(name, ".yml") ? .yaml : .none
    }

    // MARK: - YAML (compose, Kubernetes, Helm)

    // Le righe sono già divise su "\n": il "$" di .NET non ha un "\n" finale da accettare.

    private static func yamlImageLines(_ file: String, _ text: String) -> [ImageReference] {
        let yamlImageLine = /^\s*(?:-\s*)?image:\s*["']?(?<ref>[^"'\s#]+)["']?\s*(?:#[^\n]*)?\r?$/
            .matchingSemantics(.unicodeScalar)

        var references: [ImageReference] = []
        for (index, line) in DockerText.rawLines(text).enumerated() {
            if let match = line.firstMatch(of: yamlImageLine),
               let reference = reference(String(match.output.ref), nil, file, index + 1) {
                references.append(reference)
            }
        }
        return references
    }

    /// Valori Helm: `repository:` seguito a breve distanza dal suo `tag:`.
    private static func helmRepositoryTags(_ file: String, _ text: String) -> [ImageReference] {
        let yamlRepositoryLine = /^\s*repository:\s*["']?(?<value>[^"'\s#]+)["']?\s*(?:#[^\n]*)?\r?$/
            .matchingSemantics(.unicodeScalar)
        let yamlTagLine = /^\s*tag:\s*["']?(?<value>[^"'\s#]+)["']?\s*(?:#[^\n]*)?\r?$/
            .matchingSemantics(.unicodeScalar)

        let lines = DockerText.rawLines(text)
        var references: [ImageReference] = []
        for (index, line) in lines.enumerated() {
            guard let repository = line.firstMatch(of: yamlRepositoryLine),
                  !DockerText.contains(String(repository.output.value), "://") else {
                continue
            }

            let tag = lines.dropFirst(index + 1).prefix(4)
                .lazy
                .compactMap { $0.firstMatch(of: yamlTagLine) }
                .first
                .map { String($0.output.value) }

            if let reference = reference(String(repository.output.value), tag, file, index + 1) {
                references.append(reference)
            }
        }
        return references
    }

    /// Il nome che Compose dà al progetto: `name:` se dichiarato, altrimenti la cartella.
    private func composeProjectName(_ file: String, _ text: String) -> String {
        // `^name:\s*["']?(?<value>[^"'\s#]+)` con `RegexOptions.Multiline`: "^" vale all'inizio del
        // testo e dopo ogni "\n", e solo lì; `\s*` può proseguire sulle righe seguenti.
        let composeNameLine = /name:\s*["']?(?<value>[^"'\s#]+)/
            .matchingSemantics(.unicodeScalar)

        let declared = DockerText.lineStarts(text).lazy
            .compactMap { text[$0...].prefixMatch(of: composeNameLine) }
            .first
            .map { String($0.output.value) }
        let raw = declared ?? PathText.parent(file).map(PathText.fileName) ?? ""

        var name = String.UnicodeScalarView()
        for scalar in DockerText.lowercasedInvariant(raw).unicodeScalars
        where scalar.isASCII && (scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) || scalar == "_" || scalar == "-") {
            name.append(scalar)
        }
        return String(name)
    }

    // MARK: - Dockerfile

    private static func dockerfileFromLines(_ file: String, _ text: String) -> [ImageReference] {
        // `^\s*FROM\s+(?:--\S+\s+)*(?<ref>\S+)(?:\s+AS\s+(?<alias>\S+))?`, IgnoreCase: "FROM" e "AS"
        // non hanno la "i" né la "k", quindi `ignoresCase` di Swift coincide con .NET.
        let dockerfileFrom = /^\s*FROM\s+(?:--\S+\s+)*(?<ref>\S+)(?:\s+AS\s+(?<alias>\S+))?/
            .ignoresCase()
            .matchingSemantics(.unicodeScalar)

        // `HashSet(StringComparer.OrdinalIgnoreCase)`: si conservano i nomi ripiegati.
        var stages: Set<String> = [PathText.folded("scratch")]
        var references: [ImageReference] = []

        for (index, line) in DockerText.rawLines(text).enumerated() {
            guard let match = line.firstMatch(of: dockerfileFrom) else { continue }

            let image = String(match.output.ref)
            if !stages.contains(PathText.folded(image)), let reference = reference(image, nil, file, index + 1) {
                references.append(reference)
            }

            if let alias = match.output.alias {
                stages.insert(PathText.folded(String(alias)))
            }
        }
        return references
    }

    // MARK: - C# (AppHost di Aspire, Testcontainers)

    /// Per istruzione (testo fra due ";"), non per riga: `AddSqlServer("sql")` e il suo
    /// `.WithImageTag("2025-latest")` stanno di solito su righe diverse della stessa catena. Solo i
    /// file che sono un AppHost o usano Testcontainers: un "postgres:16" in una stringa qualunque non
    /// è un riferimento.
    private static func cSharpReferences(_ file: String, _ text: String) -> [ImageReference] {
        guard DockerText.contains(text, "DistributedApplication") || DockerText.contains(text, "Testcontainers") else {
            return []
        }

        let withImageTag = /\.WithImageTag\(\s*"(?<tag>[^"]+)"/.matchingSemantics(.unicodeScalar)
        let withImageRegistry = /\.WithImageRegistry\(\s*"(?<registry>[^"]+)"/.matchingSemantics(.unicodeScalar)
        let withImage = /\.WithImage\(\s*"(?<image>[^"]+)"(?:\s*,\s*"(?<tag>[^"]+)")?/.matchingSemantics(.unicodeScalar)
        let addContainer = /\.AddContainer\(\s*"[^"]*"\s*,\s*"(?<image>[^"]+)"(?:\s*,\s*"(?<tag>[^"]+)")?/.matchingSemantics(.unicodeScalar)
        let builderWithImage = /new\s+[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]+Builder\(\s*"(?<image>[^"]+)"/.matchingSemantics(.unicodeScalar)
        let emptyBuilder = /new\s+(?<builder>[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]+Builder)\(\s*\)/.matchingSemantics(.unicodeScalar)
        let aspireResource = /\.Add(?<resource>[[\p{L}\p{Mn}\p{Nd}\p{Pc}]&&[\x{0}-\x{FFFF}]]+)\(/.matchingSemantics(.unicodeScalar)

        func statementReference(_ statement: Substring, line: Int) -> ImageReference? {
            let tagOverride = statement.firstMatch(of: withImageTag).map { String($0.output.tag) }
            let registry = statement.firstMatch(of: withImageRegistry).map { String($0.output.registry) }

            let explicitImage: (image: Substring, tag: Substring?)? =
                statement.firstMatch(of: withImage).map { ($0.output.image, $0.output.tag) }
                ?? statement.firstMatch(of: addContainer).map { ($0.output.image, $0.output.tag) }
                ?? statement.firstMatch(of: builderWithImage).map { ($0.output.image, nil) }

            var image: String?
            let tag: String?

            if let explicitImage {
                image = String(explicitImage.image)
                tag = explicitImage.tag.map(String.init) ?? tagOverride
            } else {
                image = statement.matches(of: aspireResource).lazy
                    .compactMap { aspireResources[String($0.output.resource)] }
                    .first
                    ?? statement.firstMatch(of: emptyBuilder).flatMap { testcontainersBuilders[String($0.output.builder)] }
                tag = tagOverride
            }

            guard var image else { return nil }

            if let registry, DockerText.hasPrefix(ImageName.parse(image).repository, "docker.io/") {
                image = "\(DockerText.trimmedTrailing(registry, "/"))/\(image)"
            }

            return reference(image, tag, file, line)
        }

        var references: [ImageReference] = []
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        var line = 1

        while start < scalars.endIndex {
            let end = scalars[start...].firstIndex(of: ";") ?? scalars.endIndex
            let statement = Substring(scalars[start..<end])

            // Riga del primo carattere non bianco dell'istruzione: `text.AsSpan(0, firstChar).Count('\n')`.
            let firstChar = scalars[start..<end].firstIndex { !$0.properties.isWhitespace } ?? end
            let statementLine = line + scalars[start..<firstChar].filter { $0 == "\n" }.count

            if let reference = statementReference(statement, line: statementLine) {
                references.append(reference)
            }

            line += scalars[start..<end].filter { $0 == "\n" }.count
            start = end < scalars.endIndex ? scalars.index(after: end) : end
        }

        return references
    }

    /// Valori con template (`${TAG}`, `{{ .Values.image }}`) non sono confrontabili: si scartano.
    private static func reference(_ image: String, _ tag: String?, _ file: String, _ line: Int) -> ImageReference? {
        if DockerText.isBlank(image) || DockerText.contains(image, "$") || DockerText.contains(image, "{") {
            return nil
        }
        if let tag, DockerText.contains(tag, "$") || DockerText.contains(tag, "{") {
            return nil
        }

        let name = ImageName.parse(image)
        return ImageReference(repository: name.repository, tag: tag ?? name.tag, file: file, line: line)
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter ProjectReferenceScannerTests`
Expected: `Test run with 17 tests … passed` (13 portati, 4 solo-Swift), nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/ProjectReferenceScannerTests.cs` con:

```markdown
| Docker/ProjectReferenceScannerTests.cs | 13 (4) | Docker/ProjectReferenceScannerTests.swift | 17 (4) | 2 | 13 (4) portati + 4 solo-Swift con gli esiti del C# reale (`fileNamesAreClassifiedLikeTheGeneratedDotNetRegexes`, `composeNameFollowsTheDotNetMultilineAnchor`, `projectFilesAreDecodedLikeReadAllText`, `cSharpStatementsAreSplitOnScalars`); `.Order()` sulle tuple → struct `Found` |
```

Nella tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Regex del C# (`ProjectReferenceScanner`, `VolumeRules`, `DockerSize`, `DockerCleanExecutor`) | regex generate di .NET 10 | letterali `Regex` per scalare, tradotti con la tabella delle convenzioni del piano 2; esiti del C# reale fissati da test solo-Swift | equivalente, salvo 35 punti di codice assegnati in Unicode dopo i dati di .NET 10 (classe `\w` e confine `\b`) |
| Ordine di visita delle cartelle dei progetti | ordine di `readdir` (non garantito) | ordine ordinale di `contentsOfDirectory` | accettata: cambia solo quale file:riga si cita quando più file nominano la stessa immagine |
| Lettura dei file dei progetti | `File.ReadAllText` (BOM UTF-8, UTF-16, UTF-32; U+FFFD per le sequenze non valide) | `DockerText.decodeLikeReadAllText` su `readData` | equivalente (stessi esiti misurati) |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port ProjectReferenceScanner with .NET regex semantics

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `DockerCleanExecutor`

Ogni garanzia di sicurezza si verifica qui, voce per voce, anche se l'interfaccia l'ha già applicata. Le fasi e il resoconto sono quelli del C#: immagini, ritentativo delle basi con immagini figlie, poi volumi e cache; un daemon sparito ferma la pulizia e le voci restanti risultano «non eseguite»; i byte liberati sono il delta di `docker system df` per le sole categorie in cui si è cancellato qualcosa.

Due punti nuovi rispetto al C#, entrambi per mantenere una sua garanzia:
- **Isolamento dall'annullamento.** In C# le cancellazioni e la misura finale usano `CancellationToken.None`. In Swift l'annullamento è del task: `ProcessRunner` ucciderebbe `docker rmi` a metà, e la misura finale lancerebbe `CancellationError` perdendo il resoconto. Entrambe girano quindi in un `Task` non strutturato, che non eredita l'annullamento. Il test C# che annullava dentro la risposta di `rmi` annulla qui dal callback di avanzamento dello stesso elemento, che arriva subito dopo: la CLI finta, che come `ProcessRunner` rifiuta i comandi da un task annullato, verifica l'isolamento.
- **Guardie con `$` stretto.** Il `$` di .NET accettava `"sha256:…\n"`; quello di Swift no. Si tiene il `$` di Swift: è la regola dichiarata dalla spec Docker (§7, «rifiuta qualunque identificativo che non sia un sha256: di 64 caratteri esadecimali») e nessun ID di Docker contiene `\n`.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanExecutor.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerCleanExecutor.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerCleanExecutorTests.cs`

**Interfaces:**
- Consumes (piano 1): `CleanReport`, `CategoryCleanResult`, `CleanProgress`, `ScanError`, `ScanErrorKind`, `WallClock`, `ProcessResult`; test: `FixedWallClock`, `Recorder`, `cancelCurrentTask()`. Task 1: modelli, `DockerText.containsIgnoringCase`. Task 2: `DockerOutputError`, `DockerFixtures`. Task 3: `DockerClassifier.buildCacheId`. Task 5: `DockerCommandRunning`, `DockerCliErrors.describe`, `DockerUnavailableError`, `DockerCommandError`, `FakeDockerCli`, `Shared`. Task 6: `DockerInventoryCollector.readDf(_:)`.
- Produces:
  - `public enum DockerCategories` — `static let images = "docker-images"`, `volumes = "docker-volumes"`, `buildCache = "docker-build-cache"`; `static func category(for: DockerResourceKind) -> String`
  - `public struct DockerCleanResult: Sendable, Equatable` — `report: CleanReport`, `before: DockerDfSummary`, `after: DockerDfSummary?`, `daemonLost: Bool`; `init(report:before:after:daemonLost:)`
  - `public struct DockerCleanExecutor: Sendable` — `init(cli: any DockerCommandRunning, clock: any WallClock)`; `@concurrent func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DockerCleanExecutorTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct DockerCleanExecutorTests {
    private static let dfBefore = """
        {"Type":"Images","Size":"5.84GB","Reclaimable":"1GB"}
        {"Type":"Local Volumes","Size":"558.5MB","Reclaimable":"159MB"}
        {"Type":"Build Cache","Size":"106.9MB","Reclaimable":"106.9MB"}
        """

    private static let dfAfter = """
        {"Type":"Images","Size":"5.5GB","Reclaimable":"0B"}
        {"Type":"Local Volumes","Size":"470MB","Reclaimable":"0B"}
        {"Type":"Build Cache","Size":"0B","Reclaimable":"0B"}
        """

    private static let ryukId = DockerFixtures.ryukId

    private static let buildCache = DockerCandidate(
        kind: .buildCache, id: DockerClassifier.buildCacheId, displayName: "Cache di build", sizeBytes: 1_000,
        verdict: .delete, ruleId: "build-cache", reason: "m", cost: "c")

    private func image(_ id: String, _ name: String, _ verdict: DockerVerdict = .delete) -> DockerCandidate {
        DockerCandidate(kind: .image, id: id, displayName: name, sizeBytes: 1_000, verdict: verdict, ruleId: "rule", reason: "motivo", cost: "costo")
    }

    private func volume(_ name: String, _ verdict: DockerVerdict = .propose) -> DockerCandidate {
        DockerCandidate(kind: .volume, id: name, displayName: name, sizeBytes: 1_000, verdict: verdict, ruleId: "rule", reason: "motivo", cost: "costo")
    }

    /// CLI che accetta ogni cancellazione e restituisce il df prima e dopo.
    private func succeedingCli() -> FakeDockerCli {
        let dfCalls = Shared(0)
        return FakeDockerCli()
            .on("system df --format {{json .}}") { FakeDockerCli.ok(dfCalls.increment() == 1 ? Self.dfBefore : Self.dfAfter) }
            .onPrefix("rmi ") { _ in FakeDockerCli.ok("Deleted") }
            .onPrefix("volume rm ") { arguments in FakeDockerCli.ok(arguments.last ?? "") }
            .on("builder prune -f", "Total reclaimed space: 106.9MB")
    }

    private func executor(_ cli: FakeDockerCli) -> DockerCleanExecutor {
        DockerCleanExecutor(cli: cli, clock: FixedWallClock(now: Date(timeIntervalSince1970: 0)))
    }

    private func execute(_ cli: FakeDockerCli, _ selected: DockerCandidate...) async throws -> DockerCleanResult {
        try await executor(cli).execute(selected, progress: nil)
    }

    @Test func imagesAreRemovedByIdNeverByTag() async throws {
        let cli = succeedingCli()

        _ = try await execute(cli, image(Self.ryukId, "testcontainers/ryuk:0.14.0"))

        #expect(cli.commandLines.contains("rmi \(Self.ryukId)"))
        #expect(!cli.commandLines.contains { $0.contains("ryuk:0.14.0") })
    }

    @Test func noCommandIsEverForcedOrAGlobalPrune() async throws {
        let cli = succeedingCli()

        _ = try await execute(cli, image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache)

        for call in cli.calls where call.first == "rmi" || call.first == "volume" {
            #expect(!call.contains("-f"))
            #expect(!call.contains("--force"))
        }
        #expect(!cli.commandLines.contains { $0.hasPrefix("system prune") })
        #expect(!cli.commandLines.contains { $0.contains("--volumes") })
        #expect(!cli.commandLines.contains { $0.contains("-a") && $0.contains("prune") })
    }

    @Test func volumesAndBuildCacheUseTheirOwnCommands() async throws {
        let cli = succeedingCli()

        let result = try await execute(cli, volume("orbit.apphost-751ef8e8e6-storage-data"), Self.buildCache)

        #expect(cli.commandLines.contains("volume rm orbit.apphost-751ef8e8e6-storage-data"))
        #expect(cli.commandLines.contains("builder prune -f"))
        #expect(result.report.itemsDeleted == 2)
    }

    @Test func keepVerdictsAreRefusedWithoutRunningAnything() async throws {
        let cli = succeedingCli()

        let result = try await execute(cli,
            image(DockerFixtures.mssql2025Id, "mssql 2025", .keep),
            volume("mssql2025-data", .keep))

        #expect(!cli.calls.contains { $0.first == "rmi" || $0.first == "volume" })
        #expect(result.report.itemsFailed == 2)
        #expect(result.report.errors.allSatisfy { $0.message.contains("KEEP") })
    }

    @Test(arguments: ["testcontainers/ryuk:0.14.0", "sha256:abc", "-f"])
    func imageIdentifiersThatAreNotFullIdsAreRefused(id: String) async throws {
        let cli = succeedingCli()

        let result = try await execute(cli, image(id, id))

        #expect(!cli.calls.contains { $0.first == "rmi" })
        #expect(result.report.itemsFailed == 1)
    }

    @Test(arguments: ["-f", "--all", ""])
    func volumeNamesThatLookLikeFlagsAreRefused(name: String) async throws {
        let cli = succeedingCli()

        let result = try await execute(cli, volume(name))

        #expect(!cli.calls.contains { $0.first == "volume" })
        #expect(result.report.itemsFailed == 1)
    }

    @Test func refusedImageIsReportedWithDockersReason() async throws {
        let cli = succeedingCli()
            .onPrefix("rmi \(DockerFixtures.alpineId)") { _ in
                FakeDockerCli.fail("Error response from daemon: conflict: unable to delete d4d4d4d4d4d4 (must be forced) - image is referenced in multiple repositories")
            }

        let result = try await execute(cli, image(DockerFixtures.alpineId, "alpine:3.20"), image(Self.ryukId, "ryuk"))

        let error = try #require(result.report.errors.first)
        #expect(result.report.errors.count == 1)
        #expect(error.path == "alpine:3.20")
        #expect(error.message.contains("referenced in multiple repositories"))
        #expect(result.report.itemsDeleted == 1)
    }

    @Test func imageWithDependentChildrenIsRetriedAfterTheOthers() async throws {
        let baseAttempts = Shared(0)
        let childDeleted = Shared(false)
        let cli = succeedingCli()
            .on("rmi \(DockerFixtures.azureLinuxId)") {
                baseAttempts.increment() == 1 && !childDeleted.value
                    ? FakeDockerCli.fail("Error response from daemon: conflict: unable to delete 34a22db497ff (cannot be forced) - image has dependent child images")
                    : FakeDockerCli.ok("Deleted")
            }
            .on("rmi \(DockerFixtures.dcptunId)") {
                childDeleted.set(true)
                return FakeDockerCli.ok("Deleted")
            }

        let result = try await execute(cli,
            image(DockerFixtures.azureLinuxId, "azurelinux/base/core:3.0"),
            image(DockerFixtures.dcptunId, "dcptun_developer_ms:0.25.13"))

        #expect(baseAttempts.value == 2)
        #expect(result.report.itemsDeleted == 2)
        #expect(result.report.errors.isEmpty)
    }

    @Test func daemonLostMidwayStopsAndReportsWhatIsLeft() async throws {
        let cli = succeedingCli()
            .on("rmi \(DockerFixtures.alpineId)") { throw DockerUnavailableError(DockerUnavailableError.notRunning) }

        let result = try await execute(cli,
            image(Self.ryukId, "ryuk"),
            image(DockerFixtures.alpineId, "alpine:3.20"),
            volume("old-data"))

        #expect(result.daemonLost)
        #expect(result.report.itemsDeleted == 1)
        #expect(result.report.itemsFailed == 2)
        #expect(!cli.commandLines.contains("volume rm old-data"))
        #expect(result.after == nil)
        #expect(result.report.errors.allSatisfy { $0.message.contains("Docker") })
    }

    @Test func daemonLostDuringARetryStillAccountsForEveryItem() async throws {
        // La base fallisce per le immagini figlie; al ritentativo il daemon è sparito.
        let attempts = Shared(0)
        let cli = succeedingCli()
            .on("rmi \(DockerFixtures.azureLinuxId)") {
                guard attempts.increment() == 1 else { throw DockerUnavailableError(DockerUnavailableError.notRunning) }
                return FakeDockerCli.fail("conflict: image has dependent child images")
            }

        let result = try await execute(cli,
            image(DockerFixtures.azureLinuxId, "azurelinux"),
            image(DockerFixtures.dcptunId, "dcptun"),
            volume("old-data"),
            Self.buildCache)

        #expect(result.report.itemsDeleted == 1)
        #expect(result.report.errors.map(\.path) == ["azurelinux", "old-data", "Cache di build"])
    }

    @Test func bytesFreedAreTheSystemDfDeltaPerType() async throws {
        let result = try await execute(succeedingCli(), image(Self.ryukId, "ryuk"), volume("old-data"), Self.buildCache)

        #expect(result.report.categories.first { $0.categoryId == DockerCategories.images }?.bytesFreed == 340_000_000)
        #expect(result.report.categories.first { $0.categoryId == DockerCategories.volumes }?.bytesFreed == 88_500_000)
        #expect(result.report.categories.first { $0.categoryId == DockerCategories.buildCache }?.bytesFreed == 106_900_000)
        #expect(result.report.bytesFreed == Int64(340_000_000 + 88_500_000 + 106_900_000))
    }

    @Test func categoriesWithoutDeletionsGetNoBytes() async throws {
        // Solo un volume cancellato: se nel frattempo un'immagine sparisce per altri motivi, quel
        // delta non va attribuito a questa pulizia.
        let result = try await execute(succeedingCli(), volume("old-data"))

        #expect(result.report.categories.map(\.categoryId) == [DockerCategories.volumes])
        #expect(result.report.bytesFreed == 88_500_000)
    }

    @Test func deletedResourcesAreLoggedWithTheirIdentity() async throws {
        let result = try await execute(succeedingCli(), image(Self.ryukId, "testcontainers/ryuk:0.14.0"), volume("old-data"), Self.buildCache)

        #expect(result.report.deletedPaths == [
            "docker:image:\(Self.ryukId) (testcontainers/ryuk:0.14.0)",
            "docker:volume:old-data",
            "docker:build-cache",
        ])
    }

    // Il C# annullava il token dentro la risposta di `rmi`; qui il comando gira isolato
    // dall'annullamento (come con `CancellationToken.None`), quindi si annulla il task dell'esecutore
    // dal callback di avanzamento, che arriva subito dopo la stessa cancellazione.
    @Test func cancellationReturnsAPartialReport() async throws {
        let cli = succeedingCli()
        let executor = executor(cli)
        let selected = [image(Self.ryukId, "ryuk"), image(DockerFixtures.alpineId, "alpine")]

        let result = try await Task {
            try await executor.execute(selected, progress: { _ in cancelCurrentTask() })
        }.value

        #expect(result.report.itemsDeleted == 1)
        #expect(!cli.commandLines.contains("rmi \(DockerFixtures.alpineId)"))
    }

    @Test func progressIsReportedForEveryItem() async throws {
        let reports = Recorder<CleanProgress>()

        _ = try await executor(succeedingCli()).execute([image(Self.ryukId, "ryuk"), volume("old-data")], progress: reports.append)

        #expect(reports.values.map(\.itemsDone) == [1, 2])
    }

    // Solo Swift: la misura finale usa `CancellationToken.None` nel C#; qui il comando gira in un
    // task che non eredita l'annullamento, e la CLI finta, come `ProcessRunner`, rifiuterebbe di
    // avviarlo da un task annullato.
    @Test func cancelledCleanupStillMeasuresAfterwards() async throws {
        let executor = executor(succeedingCli())
        let selected = [image(Self.ryukId, "ryuk"), volume("old-data")]

        let result = try await Task {
            try await executor.execute(selected, progress: { _ in cancelCurrentTask() })
        }.value

        #expect(result.report.itemsDeleted == 1)
        #expect(result.after != nil)
        #expect(result.report.bytesFreed == 340_000_000)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerCleanExecutorTests`
Expected: errore di compilazione `cannot find type 'DockerCleanExecutor' in scope` (e lo stesso per `DockerCleanResult` e `DockerCategories`).

- [ ] **Step 3: Implementare `DockerCleanExecutor`**

`Sources/CleanerCore/Docker/DockerCleanExecutor.swift`:

```swift
import Foundation

/// Identificativi stabili delle categorie Docker nello storico.
public enum DockerCategories {
    public static let images = "docker-images"
    public static let volumes = "docker-volumes"
    public static let buildCache = "docker-build-cache"

    /// `DockerCategories.For(kind)` del C#.
    public static func category(for kind: DockerResourceKind) -> String {
        switch kind {
        case .image: images
        case .volume: volumes
        case .buildCache: buildCache
        }
    }
}

/// `after`: `nil` quando la misura finale non è stata possibile (daemon spento a metà).
public struct DockerCleanResult: Sendable, Equatable {
    public let report: CleanReport
    public let before: DockerDfSummary
    public let after: DockerDfSummary?
    public let daemonLost: Bool

    public init(report: CleanReport, before: DockerDfSummary, after: DockerDfSummary?, daemonLost: Bool) {
        self.report = report
        self.before = before
        self.after = after
        self.daemonLost = daemonLost
    }
}

/// Esegue le sole cancellazioni confermate. Ogni garanzia di sicurezza è verificata qui, sul
/// singolo elemento, anche se l'interfaccia l'ha già applicata: la selezione arriva dall'interfaccia
/// e non va fidata, come in `CleanEngine`.
/// - immagini solo per ID completo (`docker rmi sha256:…`), mai per tag;
/// - mai `-f`/`--force`, mai `docker system prune`;
/// - le voci KEEP non arrivano mai a un comando.
///
/// Sequenziale: il daemon serializza comunque le cancellazioni, e un ordine prevedibile rende il
/// resoconto leggibile.
public struct DockerCleanExecutor: Sendable {
    private static let deleteTimeout: Duration = .seconds(600)

    private let cli: any DockerCommandRunning
    private let clock: any WallClock

    public init(cli: any DockerCommandRunning, clock: any WallClock) {
        self.cli = cli
        self.clock = clock
    }

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

        // Senza la misura iniziale non si può dire quanto si è recuperato: se il daemon non
        // risponde nemmeno a questa, non si è cancellato nulla e l'errore risale all'interfaccia.
        let before = try await DockerInventoryCollector.readDf(cli)

        var deleted: [String] = []
        var errors: [ScanError] = []
        var deletedByCategory: [(category: String, count: Int)] = []
        // Per posizione nella selezione, come il `ReferenceEqualityComparer` del C#: due voci
        // identiche restano due voci.
        var handled = Set<Int>()
        var retry: [(offset: Int, element: DockerCandidate)] = []
        var daemonLost = false

        func countDeleted(_ category: String) {
            if let index = deletedByCategory.firstIndex(where: { $0.category == category }) {
                deletedByCategory[index].count += 1
            } else {
                deletedByCategory.append((category, 1))
            }
        }

        // Un passo per elemento. Restituisce false quando la pulizia va interrotta (daemon sparito o
        // annullamento): l'elemento non viene allora contato come gestito.
        func step(_ entry: (offset: Int, element: DockerCandidate), allowRetry: Bool) async throws -> Bool {
            let candidate = entry.element
            if daemonLost || Task.isCancelled {
                return false
            }

            if let refusal = Self.refusal(candidate) {
                errors.append(ScanError(path: candidate.displayName, kind: .other, message: refusal))
            } else {
                let result: ProcessResult
                do {
                    result = try await shielded(Self.command(candidate))
                } catch let error as DockerUnavailableError {
                    daemonLost = true
                    handled.insert(entry.offset)
                    errors.append(ScanError(path: candidate.displayName, kind: .other, message: error.message))
                    return false
                }

                if result.exitCode == 0 && !result.timedOut {
                    deleted.append(Self.logEntry(candidate))
                    countDeleted(DockerCategories.category(for: candidate.kind))
                } else if allowRetry && Self.hasDependentChildren(result) {
                    // Una base può precedere la propria derivata nell'elenco: si riprova una volta,
                    // dopo che le altre immagini sono state rimosse.
                    retry.append(entry)
                    return true
                } else {
                    errors.append(ScanError(path: candidate.displayName, kind: Self.classify(result), message: DockerCliErrors.describe(result)))
                }
            }

            handled.insert(entry.offset)
            progress?(CleanProgress(currentPath: candidate.displayName, itemsDone: handled.count, itemsTotal: selected.count, bytesFreed: 0))
            return true
        }

        func phase(_ entries: [(offset: Int, element: DockerCandidate)], allowRetry: Bool) async throws -> Bool {
            for entry in entries {
                if !(try await step(entry, allowRetry: allowRetry)) {
                    return false
                }
            }
            return true
        }

        // Fasi: immagini, ritentativi delle immagini con figlie, poi volumi e cache di build
        // (`OrderBy(c => c.Kind)`: ordinamento stabile, prima i volumi).
        let entries = Array(selected.enumerated())
        if try await phase(entries.filter { $0.element.kind == .image }, allowRetry: true),
           try await phase(retry, allowRetry: false) {
            _ = try await phase(
                entries.filter { $0.element.kind == .volume } + entries.filter { $0.element.kind == .buildCache },
                allowRetry: false)
        }

        if daemonLost {
            // L'elemento in corso ha già il suo errore; quelli rimasti non sono stati tentati, e il
            // resoconto deve dirlo invece di lasciarli sparire.
            for entry in entries where !handled.contains(entry.offset) {
                errors.append(ScanError(
                    path: entry.element.displayName,
                    kind: .other,
                    message: String(localized: "non eseguito: \(DockerUnavailableError.notRunning)", bundle: .module)))
            }
        }

        let after = daemonLost ? nil : try await tryReadDf()

        let categories = deletedByCategory.map { entry in
            CategoryCleanResult(
                categoryId: entry.category,
                bytesFreed: after.map { max(0, Self.size(before, entry.category) - Self.size($0, entry.category)) } ?? 0,
                itemsDeleted: entry.count)
        }

        let report = CleanReport(
            startedAt: startedAt,
            duration: ContinuousClock.now - start,
            bytesFreed: categories.reduce(0) { $0 + $1.bytesFreed },
            itemsDeleted: deleted.count,
            itemsFailed: errors.count,
            categories: categories,
            errors: errors,
            deletedPaths: deleted)

        return DockerCleanResult(report: report, before: before, after: after, daemonLost: daemonLost)
    }

    /// Come `CancellationToken.None` nel C#: un comando avviato non viene interrotto dall'annullamento
    /// del chiamante (si fermerebbe a metà una cancellazione che il daemon porta comunque a termine).
    /// Un task non strutturato non eredita l'annullamento del task che ne attende il risultato.
    private func shielded(_ arguments: [String]) async throws -> ProcessResult {
        let cli = self.cli
        return try await Task { try await cli.run(arguments, timeout: Self.deleteTimeout) }.value
    }

    private func tryReadDf() async throws -> DockerDfSummary? {
        let cli = self.cli
        do {
            return try await Task { try await DockerInventoryCollector.readDf(cli) }.value
        } catch is DockerUnavailableError {
            return nil
        } catch is DockerCommandError {
            return nil
        } catch is DockerOutputError {
            return nil
        }
    }

    private static func refusal(_ candidate: DockerCandidate) -> String? {
        if candidate.verdict == .keep {
            return String(localized: "esito KEEP: non si cancella", bundle: .module)
        }

        // "$" di Swift vale solo alla fine del testo: a differenza di .NET non accetta un "\n"
        // finale, che la regola dichiarata ("sha256:" e 64 cifre esadecimali) comunque esclude.
        switch candidate.kind {
        case .image where candidate.id.firstMatch(of: /^sha256:[0-9a-f]{64}$/.matchingSemantics(.unicodeScalar)) == nil:
            return String(localized: "identificativo non valido: le immagini si cancellano solo per ID completo", bundle: .module)
        // Stessa forma accettata da Docker per i nomi dei volumi: non può iniziare con "-", quindi
        // non può essere scambiato per un'opzione del comando.
        case .volume where candidate.id.firstMatch(of: /^[A-Za-z0-9][A-Za-z0-9_.\-]*$/.matchingSemantics(.unicodeScalar)) == nil:
            return String(localized: "nome di volume non valido", bundle: .module)
        default:
            return nil
        }
    }

    private static func command(_ candidate: DockerCandidate) -> [String] {
        switch candidate.kind {
        case .image: ["rmi", candidate.id]
        case .volume: ["volume", "rm", candidate.id]
        // Qui -f salta solo la domanda interattiva di conferma: senza --all restano le voci della
        // cache ancora referenziate.
        case .buildCache: ["builder", "prune", "-f"]
        }
    }

    private static func logEntry(_ candidate: DockerCandidate) -> String {
        switch candidate.kind {
        case .image: "docker:image:\(candidate.id) (\(candidate.displayName))"
        case .volume: "docker:volume:\(candidate.id)"
        case .buildCache: "docker:build-cache"
        }
    }

    private static func hasDependentChildren(_ result: ProcessResult) -> Bool {
        DockerText.containsIgnoringCase(result.standardError, "dependent child images")
    }

    private static func classify(_ result: ProcessResult) -> ScanErrorKind {
        let text = result.standardError
        if DockerText.containsIgnoringCase(text, "No such") {
            return .notFound
        }

        return DockerText.containsIgnoringCase(text, "in use") || DockerText.containsIgnoringCase(text, "being used") ? .inUse : .other
    }

    private static func size(_ df: DockerDfSummary, _ category: String) -> Int64 {
        switch category {
        case DockerCategories.images: df.images
        case DockerCategories.volumes: df.volumes
        default: df.buildCache
        }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerCleanExecutorTests`
Expected: `Test run with 16 tests … passed` (15 portati, 1 solo-Swift), nessun warning. Prova facoltativa dell'isolamento: sostituendo in `tryReadDf` il `Task { … }.value` con la chiamata diretta, `cancellationReturnsAPartialReport` e `cancelledCleanupStillMeasuresAfterwards` falliscono con `CancellationError` (verificato durante la stesura); ripristinare il codice prima del commit.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/DockerCleanExecutorTests.cs` con:

```markdown
| Docker/DockerCleanExecutorTests.cs | 15 (6) | Docker/DockerCleanExecutorTests.swift | 16 (6) | 2 | 15 (6) portati + 1 solo-Swift (`cancelledCleanupStillMeasuresAfterwards`); in `cancellationReturnsAPartialReport` l'annullamento arriva dal callback di avanzamento dello stesso elemento invece che dalla risposta di `rmi` (il comando gira isolato dall'annullamento); `FakeDockerCli` rifiuta i comandi da un task annullato |
```

Nella tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Guardie dell'esecutore (`^sha256:[0-9a-f]{64}$`, nome di volume) | il `$` di .NET accetta un `\n` finale: `"sha256:…\n"` arrivava a `docker rmi`, che lo rifiuta | rifiutato prima di eseguire («identificativo non valido…») | voluta: è la regola dichiarata (spec Docker §7); nessun ID di Docker contiene `\n` |
| Comandi lanciati con `CancellationToken.None` (cancellazioni, misura finale) | token nullo | `Task` non strutturato, che non eredita l'annullamento | equivalente |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port DockerCleanExecutor with cancellation-shielded deletions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `DockerCleanupService`

Il flusso per l'interfaccia: analisi in sola lettura, esecuzione, misura del disco. Raccolta da Docker, ricerca nei progetti e misura del disco procedono in parallelo.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Docker/DockerCleanupService.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`
- Reference: `src/MjmCleaner.Core/Docker/DockerCleanupService.cs`; `tests/MjmCleaner.Core.Tests/Docker/DockerCleanupServiceTests.cs`

**Interfaces:**
- Consumes: `SystemWallClock`, `ProcessRunning`, `CleanProgress` (piano 1); `DockerClassifier` (Task 3); `DockerInventoryCollector` (Task 6); `DiskUsageProbe`, `DockerDiskUsage` (Task 7); `ProjectReferenceScanner` (Task 8); `DockerCleanExecutor`, `DockerCleanResult` (Task 9); test: `InMemoryFileSystem`, `FakeDockerCli`.
- Produces:
  - `public struct DockerAnalysis: Sendable, Equatable` — `serverVersion`, `snapshot`, `candidates`, `disk`; `init(serverVersion:snapshot:candidates:disk:)`
  - `public struct DockerCleanupService: Sendable` — `init(collector:scanner:disk:executor:)`; `@concurrent func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis`; `func execute(_: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult`; `func measureDisk() async throws -> DockerDiskUsage`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Docker/DockerCleanupServiceTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DockerCleanupServiceTests {
    private static let rawPath = "/Users/tester/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"

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
            executor: DockerCleanExecutor(cli: cli, clock: SystemWallClock()))
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
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerCleanupServiceTests`
Expected: errore di compilazione `cannot find 'DockerCleanupService' in scope`.

- [ ] **Step 3: Implementare `DockerCleanupService`**

`Sources/CleanerCore/Docker/DockerCleanupService.swift`:

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

    public init(collector: DockerInventoryCollector, scanner: ProjectReferenceScanner, disk: DiskUsageProbe, executor: DockerCleanExecutor) {
        self.collector = collector
        self.scanner = scanner
        self.disk = disk
        self.executor = executor
    }

    /// Raccolta da Docker e ricerca nei progetti procedono in parallelo: sono indipendenti, e la
    /// seconda attraversa il disco mentre la prima attende la CLI. Le attività figlie di `async let`
    /// girano sull'executor globale, mai su quello del chiamante (`Task.Run` nel C#).
    @concurrent
    public func analyze(_ projectRoots: [String]) async throws -> DockerAnalysis {
        let version = try await collector.checkDaemon()

        async let references = scanner.scan(projectRoots)
        async let usage = disk.measure()
        let snapshot = try await collector.collect()

        return DockerAnalysis(
            serverVersion: version,
            snapshot: snapshot,
            candidates: try DockerClassifier.classify(snapshot, try await references),
            disk: try await usage)
    }

    public func execute(_ selected: [DockerCandidate], progress: (@Sendable (CleanProgress) -> Void)?) async throws -> DockerCleanResult {
        try await executor.execute(selected, progress: progress)
    }

    public func measureDisk() async throws -> DockerDiskUsage {
        try await disk.measure()
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter DockerCleanupServiceTests`
Expected: `Test run with 2 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Docker/DockerCleanupServiceTests.cs` con:

```markdown
| Docker/DockerCleanupServiceTests.cs | 2 | Docker/DockerCleanupServiceTests.swift | 2 | 2 | «`Task.Run` della ricerca nei progetti → `async let` in `analyze` (`@concurrent`)» |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port DockerCleanupService

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Verifica completa e chiusura del piano

**Files:**
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: tutto il modulo (piano 1 e Task 1–10).
- Produces: nessuna API nuova.

- [ ] **Step 1: Eseguire l'intera suite**

Run: `swift build --build-tests -Xswiftc -warnings-as-errors && swift test -Xswiftc -warnings-as-errors`
Expected: build senza warning; tutti i test passano. Conteggio atteso: 242 (piano 1) + 11 (Task 1) + 10 (Task 2) + 27 (Task 3) + 7 (Task 4) + 11 (Task 5) + 7 (Task 6) + 6 (Task 7) + 17 (Task 8) + 16 (Task 9) + 2 (Task 10) = **356 test** (`Test run with 356 tests in 33 suites passed`).

- [ ] **Step 2: Verificare i vincoli globali**

Run:

```bash
grep -rnE 'try!|as!|import (SwiftUI|AppKit)' Sources/CleanerCore || echo "nessuna violazione"
grep -rnE '[A-Za-z0-9_\)\]]!([^=]|$)' Sources/CleanerCore || echo "nessun forced unwrap"
grep -nE '\.(hasPrefix|hasSuffix|lowercased|uppercased)\(' Sources/CleanerCore/Docker/*.swift | grep -v 'DockerText\.' || echo "nessun confronto sui Character"
grep -nE '\.contains\("|\.range\(of:|\.components\(' Sources/CleanerCore/Docker/*.swift || echo "nessuna ricerca sui Character"
grep -nE 'static (let|var) [A-Za-z]+ *(:[^=]*)?= */' Sources/CleanerCore/Docker/*.swift || echo "nessuna regex statica"
grep -nE '"(--force|--all|--volumes)"|"system", "prune"' Sources/CleanerCore/Docker/*.swift || echo "nessun comando vietato"
grep -n '"-f"' Sources/CleanerCore/Docker/*.swift
```

Expected: le prime sei righe stampano il rispettivo messaggio di nessuna violazione; l'ultima trova una sola riga, `case .buildCache: ["builder", "prune", "-f"]` in `DockerCleanExecutor.swift`. Il secondo pattern può segnalare falsi positivi dentro stringhe o commenti: controllare a mano ogni riga segnalata.

- [ ] **Step 3: Chiudere il registro di parità**

In `docs/superpowers/porting/2026-10-13-parity.md`:

1. Verificare che tutte le righe `Docker/…` abbiano file Swift e conteggio compilati (Task 1–10).
2. Aggiornare la colonna «Piano» alla nuova numerazione in cinque piani: righe `Xcode/…` di `MjmCleaner.Core.Tests` da `2` a `3`; tutte le righe di `MjmCleaner.App.Tests` da `3` a `4`; nella riga «Utilità (nessuna prova propria): `TestAppBuilder.cs`, `TestHome.cs` (piano 3)» scrivere `(piano 4)`.
3. Nella frase «Doppi e utilità di test (nessuna prova propria): …», sostituire `` `Docker/DockerFixtures.cs`, `Docker/FakeDockerCli.cs` (piano 2) `` con `` `Docker/DockerFixtures.cs`, `Docker/FakeDockerCli.cs` (piano 2: portati in `Tests/CleanerCoreTests/Docker/`; `DockerFixtures.swift` legge le fixture da `#filePath`, `FakeDockerCli.swift` rifiuta i comandi da un task annullato e contiene `Shared`) ``.
4. Correggere la riga «Decodifica di `settings.json`» della tabella «Differenze rispetto al C#» (fatto rimasto in sospeso dal piano 1) sostituendola con:

```markdown
| Decodifica di `settings.json` | un campo intero `null`, `12.0` o un valore oltre Int32 rendono il file illeggibile (tutti i default); `"ProjectRoots": null` è accettato (la proprietà diventa null, gli altri campi restano) e `[null]` è accettato (l'elenco conserva un elemento null) | `null` → default del solo campo (anche `ProjectRoots` → `[]`); `12.0` e valori a 64 bit accettati; `[null]` → tutti i default | mista: più tollerante su campi null e numeri, più severa su elementi null |
```

5. Correggere la riga «`SimpleGlob` senza maiuscole» (fatto rimasto in sospeso dal piano 1) sostituendola con:

```markdown
| `SimpleGlob` senza maiuscole | `MatchesSimpleExpression` usa `ToUpperInvariant` per unità UTF-16: «ı» resta invariata (`MatchesSimpleExpression("I", "ı", true)` è falso) e «ſ» diventa «S» | stesso ripiegamento `OrdinalIgnoreCase` di `PathText` (ı e ſ invariati) | accettata: diverge solo «ſ» (lato sicuro per include e marcatori); da rivedere se si useranno glob di esclusione non ASCII |
```

6. Aggiungere in testa al file, sotto la riga del piano 1 e con la data del giorno in formato AAAA-MM-GG: «Piano 2 completato il AAAA-MM-GG: 99 prove C# di Docker portate (+ 15 nuove), suite Swift verde (356 test).»

- [ ] **Step 4: Commit**

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "docs(swift): close plan 2 in the parity register

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Dopo il piano 2

Il piano 3 (Xcode) si scrive a piano 2 completato, sul codice reale. Consumerà `ProcessRunning`, `FileSystem`, `PathText` e, dove le regole sul testo coincidono, `DockerText` (da valutare se generalizzarlo con un nome neutro); dovrà aggiungere a `FileSystem` lo spazio libero del volume (`DriveInfo` in C#, usato da `XcodeSizeProbe`) e passare `xcrun` per percorso assoluto (`/usr/bin/xcrun`) o per nome, verificando che stia nel PATH dell'app aperta dal Finder.

Per il piano 4 (Features e app): `AppEnvironment` costruisce `DockerCli(runner: ProcessRunner(), binaryPath: DockerBinaryLocator.find(LocalFileSystem(), homeDirectory: home))` e `DiskUsageProbe(…, diskImagePath: DiskUsageProbe.defaultPath(home))`; il modello della pagina Docker mostra `DockerUnavailableError.message` così com'è e, per ogni altro errore, «Analisi di Docker non riuscita: …» / «Pulizia non riuscita: …» con `localizedDescription` (tutti gli errori Docker sono `LocalizedError`). Il diario della pulizia (spec §8.2) riguarda `CleanEngine`: per Docker storico e log di sessione si scrivono dal resoconto dopo l'esecuzione, come in C#.
