# Porting Swift — Piano 3: Xcode

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portare in `CleanerCore` la pulizia Xcode di `src/MjmCleaner.Core/Xcode` (modelli, classificatore, selezione, parser dell'inventario `simctl`, CLI, sonde di dimensione e di esecuzione, scanner delle cartelle, raccolta, esecutore e servizio) con le 74 prove C# di `tests/MjmCleaner.Core.Tests/Xcode` in Swift Testing, aggiungendo a `FileSystem` lo spazio libero del volume e la data di creazione e collegando il diario della pulizia (spec §8.2) anche alle rimozioni Xcode.

**Architecture:** Un file Swift per ogni file C# in `Sources/CleanerCore/Xcode/`, più `XcodeText.swift` (confronti, spazi e UUID con la semantica .NET) e `XcodeJsonReader.swift` (lettore JSON che conserva l'ordine delle proprietà, come `JsonDocument`). Ogni interfaccia C# diventa un protocollo `…ing` come nel piano 1, così CLI, raccolta, scanner, sonde ed esecutore si sostituiscono nei test con doppi annidati. I processi esterni passano da `ProcessRunning` con gli stessi argomenti e timeout del C# (`/usr/bin/xcrun` assoluto, `ps`, `du`); le cartelle si eliminano solo tramite il `CleanEngine` del piano 1, che riceve il diario; simulatori e runtime solo con `xcrun simctl … <UUID>`.

**Tech Stack:** Swift 6 language mode, `swift-tools-version: 6.2`, macOS 15, Swift Testing, `Synchronization.Mutex`, `statfs`. Nessuna dipendenza esterna; niente `JSONSerialization`, che restituisce dizionari senza ordine.

**Spec:** `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`

Questo è il **terzo di cinque piani**: (1) fondamenta e Core — completato; (2) Docker; (3) Xcode; (4) Features e app SwiftUI; (5) verifica, release e rimozione del C#. Si esegue **dopo il piano 2** ma non ne usa nulla: il piano 2 aggiunge solo file sotto `Sources/CleanerCore/Docker` e `Tests/CleanerCoreTests/Docker` e righe del registro di parità. L'unico punto di contatto è il `testTarget` di `Package.swift`: il Task 4 aggiunge le fixture Xcode all'`exclude` che il piano 2 ha introdotto per quelle Docker.

Stato di partenza: la suite del piano 1 (242 test) più quelli del piano 2, tutti verdi. Questo piano ne aggiunge 107: 74 portati dal C# e 33 solo Swift.

## Global Constraints

Dal piano 1, invariati salvo la riga del branch:

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
- Branch: quello indicato da chi esegue il piano (il piano 1 è stato integrato in `main`; non si crea un branch di propria iniziativa).

Vincoli specifici di Xcode, che applicano le decisioni del registro del piano 1 (`docs/superpowers/decisions/2026-10-13-registro-decisioni-swift-piano-1.md`):

- **Testo dei percorsi e delle chiavi** solo a livello di byte UTF-8 o di scalari: `PathText` (piano 1) e `XcodeText` (Task 2). Mai tagli per `Character`, mai `hasPrefix`/`hasSuffix`/`lowercased()` sul codice di `CleanerCore`. I confronti senza maiuscole (`OrdinalIgnoreCase`) passano solo da `PathText.equalsIgnoringCase`, `hasPrefixIgnoringCase` e `folded`; quelli `Ordinal` da `XcodeText.same`/`ordinalKey`, perché `==` fra `String` confronta per equivalenza canonica. Fanno eccezione solo gli UUID canonici prodotti da `XcodeUuid`, che sono ASCII.
- **Processi:** il timeout si riconosce da `ProcessResult.timedOut`, mai da `exitCode == -1` (due origini). `xcrun` si passa con il percorso assoluto `/usr/bin/xcrun`: `posix_spawnp` cerca un nome semplice nel PATH dell'app, che lanciata dal Finder è solo `/usr/bin:/bin:/usr/sbin:/sbin`. `ps` e `du` restano per nome come in C# (sono in quel PATH). Argomenti e timeout identici al C#: inventario 30 s (`simctl list --json`, `simctl runtime`, `simctl runtime list --json`), rimozioni 5 min (`simctl delete <UUID>`, `simctl runtime delete <UUID>`), `ps -axo comm=` 5 s, `du -k -s -P <percorso>` 30 s, verifica dopo un comando 15 s.
- **Solo rimozioni mirate per UUID:** un alias di `simctl` (`all`, `booted`, `unavailable`) o un'opzione non arrivano mai alla riga di comando; la rimozione dei runtime non supportata dalla CLI produce lo stesso avviso e lo stesso blocco del C#.
- **Swift 6:** tipi `Sendable`; `@concurrent` sui metodi che fanno lavoro bloccante (filesystem, `statfs`, parsing); nei doppi di test lo stato mutabile sta in `Mutex` o `Recorder` (piano 1, `Tests/CleanerCoreTests/Support/TestSupport.swift`).
- **Diario (spec §8.2):** l'esecutore riceve un `(any DeletionRecording)?` e lo inoltra a `CleanEngine.clean`; chi orchestra la pulizia (piano 4) scarta il `PendingJournal` solo dopo che la scrittura del log di sessione è riuscita.
- **Confini:** nessun file sotto `Sources/CleanerCore/Docker` o `Tests/CleanerCoreTests/Docker`. Ogni tipo a livello di file ha il prefisso `Xcode` (lo stesso modulo ospita il piano 2); i doppi di test sono annidati nei test che li usano.
- **Fixture:** i quattro JSON di `tests/MjmCleaner.Core.Tests/Xcode/Fixtures/` si copiano byte per byte e si leggono dal disco accanto ai test (`#filePath`), senza risorse nel bundle.

---

## Convenzioni di porting

Valgono le tre tabelle del piano 1 (Tipi, Nomi dei protocolli, Test). Si aggiungono queste.

### Tipi

| C# | Swift |
|---|---|
| `record` usato con `with { … }` | `struct` con proprietà `var`: `var copia = x; copia.campo = …` (semantica di valore) |
| `DateTime` lasciato a `default` («non rilevato») | `Date?` con `nil` |
| `Guid.TryParseExact(x, "D", …)` / `Guid.TryParse(x, …)` | `XcodeUuid.canonicalExact(x)` / `XcodeUuid.canonical(x)`: forma "D" minuscola oppure `nil` |
| `string.Equals(a, b, StringComparison.Ordinal)`, `a == b` fra stringhe | `XcodeText.same(a, b)` |
| `HashSet`/`Dictionary` con `StringComparer.Ordinal` | chiavi `[UInt8]` da `XcodeText.ordinalKey` |
| `HashSet`/`GroupBy` con `StringComparer.OrdinalIgnoreCase` | chiavi `[UInt8]` da `XcodeText.caseInsensitiveKey` |
| `Distinct(StringComparer.Ordinal)` | `XcodeText.distinct` |
| `StartsWith(p, Ordinal)` / `Contains(f, OrdinalIgnoreCase)` | `XcodeText.hasOrdinalPrefix` / `XcodeText.containsIgnoringCase` |
| `Trim()`, `string.IsNullOrWhiteSpace`, `Split('\n', RemoveEmptyEntries \| TrimEntries)` | `XcodeText.trimmed`, `isNullOrWhiteSpace`, `lines` |
| `ex.Message` | `XcodeText.message(error)` |
| `ArgumentException` (fuori dai costruttori) | `XcodeArgumentError` |
| `InvalidOperationException` | `XcodeOperationError` |
| `XcodeUnavailableException` | `XcodeUnavailableError` |
| `JsonDocument` / `JsonElement` | `XcodeJsonReader.parse` / `XcodeJsonValue` |
| `XcodeFileInventory : IReadOnlyDictionary<string, XcodeFileEntry>` | `struct XcodeFileInventory` con `subscript`, `keys`, `values`, `count`, `contains` |
| `fileSystem.DriveInfo.New(home).AvailableFreeSpace` | `fileSystem.availableFreeSpace(forVolumeContaining: home)` (Task 1) |
| `DirectoryInfo.CreationTimeUtc` | `FileItemInfo.creation` (Task 1) |
| `CancellationToken.None` o un `CancellationTokenSource` proprio | un `Task { … }` non strutturato, che non eredita l'annullamento |

### Nomi dei protocolli e dei metodi

| C# | Swift (protocollo) | Swift (implementazione) |
|---|---|---|
| `IXcodeCli` | `XcodeCliInvoking` | `XcodeCli` |
| `IXcodeInventoryCollector` | `XcodeInventoryCollecting` | `XcodeInventoryCollector` |
| `IXcodeFileScanner` | `XcodeFileScanning` | `XcodeFileScanner` |
| `IXcodeSizeProbe` | `XcodeSizeProbing` | `XcodeSizeProbe` |
| `IXcodeRunningProbe` | `XcodeRunningProbing` | `XcodeRunningProbe` |
| `IXcodeCleanExecutor` | `XcodeCleanExecuting` | `XcodeCleanExecutor` |
| `IXcodeCleanupService` | `XcodeCleanupServing` | `XcodeCleanupService` |

I metodi perdono il suffisso `Async` e il `CancellationToken`: `ReadInventoryAsync` → `readInventory()`, `DeleteDeviceAsync(uuid, ct)` → `deleteDevice(_:)`, `CollectAsync` → `collect()`, `ScanAsync` → `scan()`, `MeasureRuntimeBackingImagesAsync` → `measureRuntimeBackingImages(_:)`, `MeasureAsync` → `measure(_:)`, `GetFreeBytesAsync` → `freeBytes()`, `GetStateAsync` → `state()`, `ExecuteAsync(plan, progress, ct)` → `execute(_:progress:journal:)`, `AnalyzeAsync` → `analyze()`, `XcodeJson.ParseInventory` → `parseInventory(_:_:runtimeDeleteSupported:)`.

### Test

| xUnit | Swift Testing |
|---|---|
| `Assert.Throws<ArgumentException>(…)` | `#expect(throws: XcodeArgumentError.self) { try … }` |
| `Assert.Throws<InvalidOperationException>(…)` | `#expect(throws: XcodeOperationError.self) { try … }` |
| `Assert.Single(list, predicato)` | `let matching = list.filter { … }; #expect(matching.count == 1); let x = try #require(matching.first)` |
| `x with { Campo = v }` | `var x = …; x.campo = v` |
| `File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Xcode", "Fixtures", nome))` | `try XcodeFixtures.text(nome)` (Task 4) |
| `CancellationTokenSource.Cancel()` dentro un doppio o un `IProgress` | `cancelCurrentTask()`, con la chiamata sotto test dentro `await Task { … }.value` |
| liste e contatori nei doppi | `Recorder<T>` e `Mutex` |
| `new InvalidOperationException("…")` lanciata da un doppio | `UnexpectedTestError(description: "…")` |
| `new UnauthorizedAccessException()` lanciata da un runner | `FileSystemError(code: EACCES, path: …)` |
| `TimeProvider.System` | `SystemWallClock()` |
| `DateTime.UnixEpoch.AddDays(n)` | `Date(timeIntervalSince1970: n * 86_400)` |
| `[InlineData(..., XcodeRunningState.Running)]` | `@Test(arguments: [(…, XcodeRunningState.running), …])` |

I doppi C# privati restano privati e annidati nel test Swift corrispondente, con lo stesso nome.

### Fatti misurati su .NET 10 (2026-10-13) che il porting replica

Misurati con una console usa e getta (.NET 10.0.401, non presente nel repository):

- `Guid.TryParseExact(x, "D")` toglie gli spazi esterni di `char.IsWhiteSpace` (anche U+00A0), accetta cifre maiuscole e minuscole e restituisce la forma minuscola. Dentro i gruppi accetta anche `+` e `0x` (`"+1111111-…"` → `"01111111-…"`): **Swift non lo replica** e accetta solo cifre esadecimali (lato sicuro). `Guid.TryParse` accetta anche le forme N, B, P e X; Swift riconosce N, B e P.
- `JsonElement.TryGetProperty` con un nome ripetuto restituisce **l'ultima** occorrenza; `EnumerateObject` le elenca tutte, nell'ordine del documento.
- `TryGetInt64` è vero solo per un intero scritto senza parte decimale né esponente e rappresentabile in 64 bit: `"100.0"`, `"1e2"`, `"1E+2"`, `"0.5"` e `9223372036854775808` danno falso, `"-0"` dà 0.
- `JsonDocument.Parse` rifiuta: testo vuoto o di soli spazi, BOM, commenti, virgole finali, zeri iniziali, apici singoli, testo dopo il valore. Accetta un escape `\ud800` isolato, ma poi `GetString` lancia `InvalidOperationException`.
- `new DriveInfo(home).AvailableFreeSpace` coincide con `statfs(home)`: `f_bavail × f_bsize` (letture ravvicinate: 590 356 348 928 contro 590 356 353 024 byte). `volumeAvailableCapacityForImportantUsage` di Foundation dava circa 30 GB in più (spazio eliminabile). Su un percorso inesistente lancia `DriveNotFoundException`, una `IOException`.
- `DirectoryInfo.CreationTimeUtc` è la data di nascita (`st_birthtimespec`); su un percorso inesistente non lancia e restituisce la sentinella 1601-01-01.
- `Directory.EnumerateFileSystemEntries` lancia `DirectoryNotFoundException` per un percorso inesistente (ENOENT) e per un file o un percorso sotto un file (ENOTDIR); `UnauthorizedAccessException` per una cartella illeggibile o un genitore non attraversabile (EACCES).
- La regex `(?m)^\s*delete\s+\(<identifier>` riconosce un inizio di riga solo dopo `"\n"` (non dopo `"\r"`), il suo `\s` attraversa gli a capo e comprende U+0085, U+00A0 e U+2028; `"Delete"` maiuscolo non corrisponde.
- La regex `/(?:Xcode|Xcode-beta)\.app/Contents/MacOS/` con `IgnoreCase` non equipara `ſ` (U+017F) a `s`, come `PathText.folded`.
- `Split('\n', TrimEntries | RemoveEmptyEntries)` toglie anche il `"\r"` finale delle righe; `long.TryParse(…, NumberStyles.None, …)` rifiuta `"+5"` e le cifre non ASCII.

---

## Mappa dei file

```
swift/MjmCleanerKit/
├── Package.swift                                         Task 4 (exclude delle fixture)
├── Sources/CleanerCore/Platform/FileSystem.swift          Task 1 (modifica)
├── Sources/CleanerCore/Platform/LocalFileSystem.swift     Task 1 (modifica)
├── Sources/CleanerCore/Xcode/
│   ├── XcodeModels.swift, XcodeText.swift                Task 2
│   ├── XcodeClassifier.swift, XcodeSelection.swift        Task 3
│   ├── XcodeJsonReader.swift, XcodeJson.swift             Task 4
│   ├── XcodeCli.swift                                     Task 5
│   ├── XcodeSizeProbe.swift, XcodeRunningProbe.swift      Task 6
│   ├── XcodeFileScanner.swift                             Task 7
│   ├── XcodeInventoryCollector.swift                      Task 8
│   ├── XcodeCleanExecutor.swift                           Task 9
│   └── XcodeCleanupService.swift                          Task 10
└── Tests/CleanerCoreTests/
    ├── Support/InMemoryFileSystem.swift, ForwardingFileSystem.swift     Task 1 (modifica)
    ├── Platform/FileSystemVolumeTests.swift                              Task 1
    ├── Xcode/XcodeTextTests.swift, XcodeModelsTests.swift                Task 2
    ├── Xcode/XcodeClassifierTests.swift, XcodeSelectionTests.swift       Task 3
    ├── Xcode/Fixtures/*.json, XcodeFixtures.swift                        Task 4
    ├── Xcode/XcodeJsonTests.swift, XcodeJsonReaderTests.swift            Task 4
    ├── Xcode/XcodeCliTests.swift                                         Task 5
    ├── Xcode/XcodeSizeProbeTests.swift                                   Task 6
    ├── Xcode/XcodeCleanupServiceTests.swift                              Task 6, completato al Task 10
    ├── Xcode/XcodeFileScannerTests.swift                                 Task 7
    ├── Xcode/XcodeInventoryCollectorTests.swift                          Task 8
    ├── Xcode/XcodeCleanExecutorTests.swift                               Task 9
    └── Integration/XcodeRealFileSystemTests.swift                        Task 11
docs/superpowers/porting/2026-10-13-parity.md                             ogni task
```

Ogni task termina con l'aggiornamento delle proprie righe nel registro di parità. Le nove righe `Xcode/…Tests.cs` della tabella `MjmCleaner.Core.Tests` oggi hanno «—» e piano 2: ogni task **sostituisce l'intera riga** del proprio file con quella indicata, qualunque sia il valore attuale della colonna Piano (il piano 2 potrebbe averla rinumerata).

---

### Task 1: `FileSystem`: spazio libero del volume e data di creazione

`XcodeSizeProbe` legge lo spazio libero del volume della home (`DriveInfo.AvailableFreeSpace`) e lo scanner cattura la data di creazione di ogni cartella (`DirectoryInfo.CreationTimeUtc`) per riconoscerla prima di eliminarla. Il protocollo `FileSystem` del piano 1 non ha né l'una né l'altra.

**Files:**
- Modify: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift`
- Modify: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/FileSystemVolumeTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeSizeProbe.cs` (`GetFreeBytesAsync`), `XcodeFileScanner.cs` (`CreationTimeUtc`)

**Interfaces:**
- Consumes: `FileSystem`, `FileSystemError`, `FileItemInfo`, `LocalFileSystem` (piano 1, Task 2); `InMemoryFileSystem`, `ForwardingFileSystem`, `TemporaryDirectory`, `utc` (piano 1, Task 2–3).
- Produces:
  - nuovo requisito `FileSystem.availableFreeSpace(forVolumeContaining path: String) throws -> Int64`, implementato da `LocalFileSystem` con `statfs` (`f_bavail × f_bsize`, come `DriveInfo.AvailableFreeSpace`; un percorso inesistente lancia `FileSystemError(code: ENOENT, …)`)
  - `FileItemInfo.creation: Date` e `FileItemInfo.init(kind:size:lastWrite:lastAccess:creation: Date? = nil)` (senza `creation` vale `lastWrite`: i chiamanti esistenti non cambiano); `LocalFileSystem.itemInfo` la legge da `st_birthtimespec`
  - test: `InMemoryFileSystem.setAvailableFreeSpace(_ bytes: Int64)` e `availableFreeSpace(forVolumeContaining:)` (ENOENT su un percorso inesistente); ogni nodo ricorda la propria data di creazione; `ForwardingFileSystem.availableFreeSpace(forVolumeContaining:)` inoltra

Scelta dell'API: `statfs` e non `URLResourceValues.volumeAvailableCapacityForImportantUsage`. .NET calcola `AvailableFreeSpace` su Unix come blocchi disponibili ai processi senza privilegi per dimensione del blocco (`statfs`), e lo stesso numero è quello che il collaudo fianco a fianco (spec §9.4) confronterà; la capacità «per uso importante» include lo spazio eliminabile e sul Mac di sviluppo vale circa 30 GB in più (vedi «Fatti misurati»). `volumeAvailableCapacity` coincide con `statfs`, ma passa da `URL` e Foundation senza aggiungere nulla.

- [ ] **Step 1: Verificare chi implementa `FileSystem`**

Il nuovo requisito va implementato da ogni tipo conforme. Run (da `swift/MjmCleanerKit`):

```bash
grep -rnE '(struct|class) [A-Za-z]+[^{]*: [^{]*FileSystem\b' Sources Tests | grep -vE ': ForwardingFileSystem'
```

Expected: solo `LocalFileSystem` (Sources/CleanerCore/Platform/LocalFileSystem.swift), `InMemoryFileSystem` e `ForwardingFileSystem` (Tests/CleanerCoreTests/Support). I decoratori di guasto derivano da `ForwardingFileSystem` e ereditano l'inoltro. Se compare un altro tipo (per esempio un doppio aggiunto dal piano 2), fermarsi e segnalarlo: non va modificato da questo piano.

- [ ] **Step 2: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Platform/FileSystemVolumeTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Spazio libero del volume e data di creazione: le due letture che il piano 3 aggiunge a
/// `FileSystem` per `XcodeSizeProbe` (`DriveInfo.AvailableFreeSpace`) e per l'identità delle
/// cartelle Xcode (`DirectoryInfo.CreationTimeUtc`).
struct FileSystemVolumeTests {
    @Test func localFreeSpaceIsStatfsAvailableBlocksOfTheContainingVolume() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let nested = try tmp.directory("a/b")

        let free = try LocalFileSystem().availableFreeSpace(forVolumeContaining: nested)

        var volume = statfs()
        #expect(statfs(tmp.path, &volume) == 0)
        let expected = Int64(volume.f_bsize) * Int64(volume.f_bavail)
        // Lo spazio libero cambia mentre il test gira: basta che le due letture siano vicine.
        #expect(free > 0)
        #expect(abs(free - expected) < 1_073_741_824)
    }

    @Test func localFreeSpaceOfAMissingPathThrowsNotFound() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/assente")) {
            try LocalFileSystem().availableFreeSpace(forVolumeContaining: tmp.path + "/assente")
        }
    }

    @Test func localCreationIsTheBirthTimeAndDoesNotFollowLaterWrites() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("DerivedData/App-abc")
        let before = try LocalFileSystem().itemInfo(dir)
        // Una data futura: impostarne una anteriore alla creazione sposterebbe indietro anche
        // la data di nascita (semantica BSD di utimes).
        let later = Date().addingTimeInterval(86_400)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: dir)

        let after = try LocalFileSystem().itemInfo(dir)
        let birth = try #require(FileManager.default.attributesOfItem(atPath: dir)[.creationDate] as? Date)

        #expect(after.creation == before.creation)
        #expect(abs(after.creation.timeIntervalSince(birth)) < 0.001)
        #expect(abs(after.lastWrite.timeIntervalSince(later)) < 0.001)
    }

    @Test func inMemoryFreeSpaceIsSettableAndMissingPathsThrow() throws {
        let fs = InMemoryFileSystem()
        fs.addDirectory("/Users/tester")
        fs.setAvailableFreeSpace(1234)

        #expect(try fs.availableFreeSpace(forVolumeContaining: "/Users/tester") == 1234)
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) {
            try fs.availableFreeSpace(forVolumeContaining: "/manca")
        }
    }

    @Test func inMemoryCreationIsTheFirstStampAndSurvivesSetTimes() throws {
        let fs = InMemoryFileSystem()
        let created = utc(2026, 1, 2)
        fs.addFile("/a/f.bin", size: 1, stamp: created)
        fs.setTimes("/a/f.bin", lastWrite: utc(2026, 3, 4), lastAccess: utc(2026, 3, 4))

        let info = try fs.itemInfo("/a/f.bin")

        #expect(info.creation == created)
        #expect(info.lastWrite == utc(2026, 3, 4))
    }

    @Test func forwardingFileSystemForwardsFreeSpace() throws {
        let inner = InMemoryFileSystem()
        inner.addDirectory("/Users/tester")
        inner.setAvailableFreeSpace(4096)

        #expect(try ForwardingFileSystem(inner).availableFreeSpace(forVolumeContaining: "/Users/tester") == 4096)
    }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter FileSystemVolumeTests`
Expected: errore di compilazione `value of type 'LocalFileSystem' has no member 'availableFreeSpace'`.

- [ ] **Step 4: Estendere `FileItemInfo` e il protocollo**

`Sources/CleanerCore/Platform/FileSystem.swift`, sostituire:

```swift
    public let lastWrite: Date
    public let lastAccess: Date

    public init(kind: FileItemKind, size: Int64, lastWrite: Date, lastAccess: Date) {
        self.kind = kind
        self.size = size
        self.lastWrite = lastWrite
        self.lastAccess = lastAccess
    }
```

con:

```swift
    public let lastWrite: Date
    public let lastAccess: Date
    /// Data di creazione (`st_birthtimespec`), come `CreationTimeUtc` di .NET su macOS: a
    /// differenza di `lastWrite` non cambia quando il contenuto viene riscritto. Chi non la conosce
    /// la omette e vale `lastWrite`.
    public let creation: Date

    public init(kind: FileItemKind, size: Int64, lastWrite: Date, lastAccess: Date, creation: Date? = nil) {
        self.kind = kind
        self.size = size
        self.lastWrite = lastWrite
        self.lastAccess = lastAccess
        self.creation = creation ?? lastWrite
    }
```

`Sources/CleanerCore/Platform/FileSystem.swift`, sostituire:

```swift
    /// non è un errore.
    func createDirectory(_ path: String) throws
}
```

con:

```swift
    /// non è un errore.
    func createDirectory(_ path: String) throws
    /// Come `DriveInfo.AvailableFreeSpace` del volume che contiene `path`: i byte disponibili a un
    /// processo senza privilegi (`statfs`: `f_bavail × f_bsize`), senza lo spazio eliminabile
    /// che macOS libererebbe su richiesta.
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64
}
```

- [ ] **Step 5: Implementare in `LocalFileSystem`**

`Sources/CleanerCore/Platform/LocalFileSystem.swift`, sostituire:

```swift
            lastWrite: Self.date(status.st_mtimespec),
            lastAccess: Self.date(status.st_atimespec))
    }
```

con:

```swift
            lastWrite: Self.date(status.st_mtimespec),
            lastAccess: Self.date(status.st_atimespec),
            creation: Self.date(status.st_birthtimespec))
    }
```

`Sources/CleanerCore/Platform/LocalFileSystem.swift`, sostituire:

```swift
    // MARK: - Privati
```

con:

```swift
    public func availableFreeSpace(forVolumeContaining path: String) throws -> Int64 {
        var volume = statfs()
        guard statfs(path, &volume) == 0 else { throw FileSystemError(code: errno, path: path) }
        // Come DriveInfo.AvailableFreeSpace su Unix: blocchi disponibili ai processi senza
        // privilegi per la dimensione del blocco. `volumeAvailableCapacityForImportantUsage`
        // aggiungerebbe lo spazio eliminabile e darebbe un numero diverso dall'app C#.
        let (bytes, overflow) = Int64(volume.f_bsize).multipliedReportingOverflow(by: Int64(clamping: volume.f_bavail))
        guard !overflow else { throw FileSystemError(code: EOVERFLOW, path: path) }
        return bytes
    }

    // MARK: - Privati
```

- [ ] **Step 6: Aggiornare i doppi di test**

`Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:

```swift
        var lastWrite: Date
        var lastAccess: Date

        static func directory(_ stamp: Date) -> Node {
            Node(isDirectory: true, size: 0, contents: Data(), lastWrite: stamp, lastAccess: stamp)
        }
    }

    private let nodes = Mutex<[String: Node]>(["/": .directory(Date())])
```

con:

```swift
        var lastWrite: Date
        var lastAccess: Date
        var creation: Date

        static func directory(_ stamp: Date) -> Node {
            Node(isDirectory: true, size: 0, contents: Data(), lastWrite: stamp, lastAccess: stamp, creation: stamp)
        }
    }

    private let nodes = Mutex<[String: Node]>(["/": .directory(Date())])
    private let freeSpace = Mutex<Int64>(0)
```

`Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:

```swift
    func addFile(_ path: String, size: Int64 = 0, stamp: Date = Date()) {
        store(path, Node(isDirectory: false, size: size, contents: Data(), lastWrite: stamp, lastAccess: stamp))
    }

    func addFile(_ path: String, text: String, stamp: Date = Date()) {
        let data = Data(text.utf8)
        store(path, Node(isDirectory: false, size: Int64(data.count), contents: data, lastWrite: stamp, lastAccess: stamp))
    }
```

con:

```swift
    func addFile(_ path: String, size: Int64 = 0, stamp: Date = Date()) {
        store(path, Node(isDirectory: false, size: size, contents: Data(), lastWrite: stamp, lastAccess: stamp, creation: stamp))
    }

    func addFile(_ path: String, text: String, stamp: Date = Date()) {
        let data = Data(text.utf8)
        store(path, Node(isDirectory: false, size: Int64(data.count), contents: data, lastWrite: stamp, lastAccess: stamp, creation: stamp))
    }

    /// Lo spazio libero che `availableFreeSpace` riporta per ogni percorso esistente.
    func setAvailableFreeSpace(_ bytes: Int64) {
        freeSpace.withLock { $0 = bytes }
    }
```

`Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:

```swift
                lastWrite: node.lastWrite,
                lastAccess: node.lastAccess)
        }
    }
```

con:

```swift
                lastWrite: node.lastWrite,
                lastAccess: node.lastAccess,
                creation: node.creation)
        }
    }
```

`Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:

```swift
            if nodes[key] == nil { nodes[key] = .directory(Date()) }
        }
    }

    // MARK: - Privati
```

con:

```swift
            if nodes[key] == nil { nodes[key] = .directory(Date()) }
        }
    }

    /// Come `statfs`: un percorso inesistente lancia `ENOENT`.
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64 {
        let key = Self.key(path)
        guard nodes.withLock({ $0[key] != nil }) else { throw FileSystemError(code: ENOENT, path: path) }
        return freeSpace.withLock { $0 }
    }

    // MARK: - Privati
```

`Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:

```swift
            let data = transform(nodes[key]?.contents)
            nodes[key] = Node(isDirectory: false, size: Int64(data.count), contents: data, lastWrite: Date(), lastAccess: Date())
```

con:

```swift
            let data = transform(nodes[key]?.contents)
            let now = Date()
            nodes[key] = Node(
                isDirectory: false, size: Int64(data.count), contents: data,
                lastWrite: now, lastAccess: now, creation: nodes[key]?.creation ?? now)
```

`Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`, sostituire:

```swift
    func createDirectory(_ path: String) throws { try inner.createDirectory(path) }
}
```

con:

```swift
    func createDirectory(_ path: String) throws { try inner.createDirectory(path) }
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64 {
        try inner.availableFreeSpace(forVolumeContaining: path)
    }
}
```

- [ ] **Step 7: Verificare che passino, e che il resto della suite non cambi**

Run: `swift test -Xswiftc -warnings-as-errors --filter FileSystemVolumeTests`
Expected: `Test run with 6 tests … passed`, nessun warning.

Run: `swift test -Xswiftc -warnings-as-errors`
Expected: tutti i test passano (242 del piano 1, quelli del piano 2 e i 6 nuovi).

- [ ] **Step 8: Registro di parità e commit**

Sezione «Test solo Swift», aggiungere la riga:

```markdown
| Platform/FileSystemVolumeTests.swift | 6 | spazio libero del volume (`statfs`, come `DriveInfo.AvailableFreeSpace`) e data di creazione (`st_birthtimespec`) su disco reale, nel filesystem in memoria e nell'inoltro |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Spazio libero del volume (`XcodeSizeProbe`) | `DriveInfo.AvailableFreeSpace` | `FileSystem.availableFreeSpace(forVolumeContaining:)` con `statfs` (`f_bavail × f_bsize`), misurato uguale | identica |
| Data di creazione delle cartelle Xcode | `DirectoryInfo.CreationTimeUtc` (data di nascita) | `FileItemInfo.creation` da `st_birthtimespec` | identica |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): add volume free space and creation date to FileSystem

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Modelli Xcode e primitive di testo e UUID

I modelli di `XcodeModels.cs` più le due interfacce che il C# dichiara nello stesso file (`IXcodeCli`, `IXcodeInventoryCollector`), e le primitive che sostituiscono `string`, `StringComparison` e `Guid` con la stessa semantica. Nessun test C# corrisponde a questo task: i test sono solo Swift e fissano i comportamenti misurati su .NET.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeModels.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeText.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeTextTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeModelsTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeModels.cs`, `XcodeCli.cs` (`XcodeUnavailableException`)

**Interfaces:**
- Consumes: `ScanItem`, `CleanReport`, `ProcessResult`, `ProcessLaunchError`, `FileSystemError`, `PathText` (piano 1).
- Produces:
  - `public enum XcodeResourceKind: Sendable, Equatable, Hashable { case derivedData, deviceSupport, device, runtime }`
  - `public struct XcodeCandidate: Sendable, Equatable` — `var key: String`, `kind`, `name: String`, `path`, `cliId`, `runtimeIdentifier`, `build`, `state: String?`, `sizeBytes: Int64?`, `blockReason: String?`, `dependencies: [String]?`; `init(key:kind:name:path:cliId:runtimeIdentifier:build:state:sizeBytes:blockReason:dependencies:)` con i facoltativi a `nil`; `var canSelect: Bool`; `var dependentDeviceKeys: [String]`
  - `public enum XcodeInventoryWarningKind { case completenessFailure, advisory }`; `public struct XcodeInventoryWarning: Sendable, Equatable` — `resourceGroup`, `message`, `kind`; `init(resourceGroup:message:kind: = .completenessFailure)`; `static func completenessFailure(_:_:)`, `static func advisory(_:_:)`
  - `public struct XcodeSnapshot: Sendable, Equatable` — `var candidates`, `var warnings`, `var fileInventory`; `init(candidates:warnings:fileInventory: = .empty)`; `static let empty`
  - `public struct XcodeFileIdentity: Sendable, Equatable` — `canonicalPath`, `isDirectory`, `creationTime: Date?`, `lastWriteTime: Date?`, `logicalSizeBytes: Int64?`; `init(canonicalPath:isDirectory:creationTime:lastWriteTime:logicalSizeBytes:)`
  - `public struct XcodeFileEntry: Sendable, Equatable` — `item: ScanItem`, `identity`; `init(item:identity:)`
  - `public enum XcodeItemOutcome { case deleted, skipped, failed, uncertain }`; `public struct XcodeItemResult` — `candidate`, `outcome`, `reason`, `verifiedEstimatedBytes: Int64?`; `public struct XcodeCleanResult` — `historyReport: CleanReport`, `items`, `freeBytesBefore: Int64?`, `freeBytesAfter: Int64?`, `warnings: [String]` (entrambi con `init` a etichette uguali ai campi)
  - `public struct XcodeFileInventory: Sendable, Equatable` — `init(_ items: [(key: String, entry: XcodeFileEntry)])`, `static let empty`, `subscript(key: String) -> XcodeFileEntry?`, `keys: [String]`, `values: [XcodeFileEntry]`, `count: Int`, `contains(_:) -> Bool`
  - `public struct XcodeArgumentError`, `XcodeOperationError`, `XcodeUnavailableError` — `Error, Equatable, Sendable, CustomStringConvertible`, `init(_ description: String)`
  - `public protocol XcodeCliInvoking: Sendable` — `readInventory() async throws -> XcodeSnapshot`, `deleteDevice(_ uuid: String) async throws -> ProcessResult`, `deleteRuntime(_ uuid: String) async throws -> ProcessResult`
  - `public protocol XcodeInventoryCollecting: Sendable` — `collect() async throws -> XcodeSnapshot`
  - interni: `enum XcodeText` — `same(_:_:)`, `ordinalKey(_:)`, `caseInsensitiveKey(_:)`, `distinct(_:)`, `hasOrdinalPrefix(_:_:)`, `containsIgnoringCase(_:_:)`, `isWhiteSpace(_:)`, `trimmed(_:)`, `isNullOrWhiteSpace(_:)`, `lines(_:)`, `message(_:)`; `enum XcodeUuid` — `canonicalExact(_:) -> String?`, `canonical(_:) -> String?`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeTextTests.swift`:

```swift
import Darwin
import Testing
@testable import CleanerCore

/// Test solo Swift: le primitive su testo e UUID che sostituiscono `string`, `StringComparison` e
/// `Guid` del C#. I casi riproducono quanto misurato su .NET 10 (vedi «Fatti misurati» del piano 3).
struct XcodeTextTests {
    private static let uuid = "11111111-1111-4111-8111-111111111111"

    @Test(arguments: [
        ("11111111-1111-4111-8111-111111111111", "11111111-1111-4111-8111-111111111111" as String?),
        ("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
        (" \t11111111-1111-4111-8111-111111111111\n", "11111111-1111-4111-8111-111111111111"),
        ("\u{00A0}11111111-1111-4111-8111-111111111111", "11111111-1111-4111-8111-111111111111"),
        ("11111111111141118111111111111111", nil),
        ("{11111111-1111-4111-8111-111111111111}", nil),
        ("11111111-1111-4111-8111-11111111111", nil),
        ("11111111-1111-4111-8111-11111111111g", nil),
        ("\u{FF11}1111111-1111-4111-8111-111111111111", nil),
        ("+1111111-1111-4111-8111-111111111111", nil),
        ("all", nil),
        ("", nil),
    ])
    func canonicalExactAcceptsOnlyTheDFormatLikeTryParseExact(text: String, expected: String?) {
        #expect(XcodeUuid.canonicalExact(text) == expected)
    }

    @Test(arguments: [
        ("11111111111141118111111111111111", "11111111-1111-4111-8111-111111111111" as String?),
        ("{11111111-1111-4111-8111-111111111111}", "11111111-1111-4111-8111-111111111111"),
        ("(AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE)", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
        (" 11111111-1111-4111-8111-111111111111 ", "11111111-1111-4111-8111-111111111111"),
        ("{11111111-1111-4111-8111-111111111111)", nil),
        ("{11111111111141118111111111111111}", nil),
        ("{0x11111111,0x1111,0x4111,{0x81,0x11,0x11,0x11,0x11,0x11,0x11,0x11}}", nil),
        ("runtime:11111111-1111-4111-8111-111111111111", nil),
    ])
    func canonicalAcceptsTheFormatsOfGuidTryParse(text: String, expected: String?) {
        #expect(XcodeUuid.canonical(text) == expected)
    }

    @Test func whiteSpaceMatchesDotNetIsWhiteSpace() {
        for scalar: Unicode.Scalar in ["\t", "\n", "\u{0B}", "\u{0C}", "\r", " ", "\u{85}", "\u{A0}", "\u{2028}", "\u{2029}", "\u{3000}"] {
            #expect(XcodeText.isWhiteSpace(scalar))
        }
        for scalar: Unicode.Scalar in ["a", "\u{200B}", "\u{FEFF}", "-"] {
            #expect(!XcodeText.isWhiteSpace(scalar))
        }
        #expect(XcodeText.trimmed(" \u{2028}x y\u{A0}\r") == "x y")
        #expect(XcodeText.isNullOrWhiteSpace(nil))
        #expect(XcodeText.isNullOrWhiteSpace(" \t"))
        #expect(!XcodeText.isNullOrWhiteSpace(" x "))
    }

    @Test func linesSplitOnlyOnLineFeedAndTrimLikeDotNet() {
        #expect(XcodeText.lines(" a \r\n\n b\t\n") == ["a", "b"])
        #expect(XcodeText.lines("x\ry") == ["x\ry"])
        #expect(XcodeText.lines("").isEmpty)
    }

    @Test func ordinalComparisonDistinguishesCanonicallyEquivalentForms() {
        #expect(!XcodeText.same("caf\u{E9}", "cafe\u{301}"))
        #expect(XcodeText.same(nil, nil))
        #expect(!XcodeText.same("a", nil))
        #expect(XcodeText.distinct(["b", "a", "b", "cafe\u{301}", "caf\u{E9}"]) == ["b", "a", "cafe\u{301}", "caf\u{E9}"])
        #expect(XcodeText.hasOrdinalPrefix("runtime:x", "runtime:"))
        #expect(!XcodeText.hasOrdinalPrefix("Runtime:x", "runtime:"))
    }

    @Test func containsIgnoringCaseIsOrdinalIgnoreCase() {
        #expect(XcodeText.containsIgnoringCase("Associazione runtime AMBIGUA: x", "ambigua"))
        #expect(XcodeText.containsIgnoringCase("/Applications/XCODE.app/contents/macos/Xcode", "/xcode.app/contents/macos/"))
        // Come la regex .NET con IgnoreCase: "ſ" (U+017F) non equivale a "s".
        #expect(!XcodeText.containsIgnoringCase("/Applications/Xcode.app/Contents/MacO\u{17F}/x", "/xcode.app/contents/macos/"))
        #expect(XcodeText.containsIgnoringCase("abc", ""))
        #expect(!XcodeText.containsIgnoringCase("", "a"))
    }

    @Test func messageMapsErrorsLikeExceptionMessage() {
        #expect(XcodeText.message(FileSystemError(code: EACCES, path: "/x")) == String(cString: strerror(EACCES)))
        #expect(XcodeText.message(CancellationError()) == "operazione annullata")
        #expect(XcodeText.message(XcodeUnavailableError("Xcode command line tools non trovati.")) == "Xcode command line tools non trovati.")
        #expect(XcodeText.message(ProcessLaunchError(executable: "/usr/bin/xcrun", code: ENOENT)) == String(cString: strerror(ENOENT)))
    }
}
```

`Tests/CleanerCoreTests/Xcode/XcodeModelsTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

/// Test solo Swift: le proprietà dei modelli che in C# derivavano da record e `IReadOnlyDictionary`.
struct XcodeModelsTests {
    private func entry(_ path: String) -> XcodeFileEntry {
        XcodeFileEntry(
            item: ScanItem(path: path, sizeBytes: 1, isDirectory: true, declaredRoot: "/r"),
            identity: XcodeFileIdentity(canonicalPath: path, isDirectory: true, creationTime: Date(timeIntervalSince1970: 0),
                                        lastWriteTime: Date(timeIntervalSince1970: 0), logicalSizeBytes: 1))
    }

    @Test func fileInventoryComparesKeysOrdinallyAndKeepsInsertionOrder() {
        let nfc = "derived-data:/r/Caf\u{E9}"
        let nfd = "derived-data:/r/Cafe\u{301}"
        let inventory = XcodeFileInventory([(nfd, entry("/r/b")), (nfc, entry("/r/a")), (nfd, entry("/r/c"))])

        #expect(inventory.keys == [nfd, nfc])
        #expect(inventory.count == 2)
        #expect(inventory[nfd] == entry("/r/b"))
        #expect(inventory[nfc] == entry("/r/a"))
        #expect(!inventory.contains("derived-data:/r/caf\u{E9}"))
        #expect(inventory.values == [entry("/r/b"), entry("/r/a")])
    }

    @Test func warningsDefaultToCompletenessFailureAndCandidatesDeriveTheirState() {
        #expect(XcodeInventoryWarning(resourceGroup: .device, message: "x").kind == .completenessFailure)
        #expect(XcodeInventoryWarning.advisory(.runtime, "y").kind == .advisory)

        var candidate = XcodeCandidate(key: "k", kind: .runtime, name: "iOS 18")
        #expect(candidate.canSelect)
        #expect(candidate.dependentDeviceKeys.isEmpty)
        candidate.blockReason = "bloccato"
        candidate.dependencies = ["d"]
        #expect(!candidate.canSelect)
        #expect(candidate.dependentDeviceKeys == ["d"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeTextTests|XcodeModelsTests"`
Expected: errore di compilazione `cannot find 'XcodeUuid' in scope` o `cannot find 'XcodeFileEntry' in scope` (il primo dei due file che il compilatore esamina; poi gli altri tipi mancanti).

- [ ] **Step 3: Implementare i modelli**

`Sources/CleanerCore/Xcode/XcodeModels.swift`:

```swift
import Foundation

public enum XcodeResourceKind: Sendable, Equatable, Hashable {
    case derivedData
    case deviceSupport
    case device
    case runtime
}

/// Una riga dell'inventario Xcode. Le proprietà sono `var` perché i `with` del C# diventano copie
/// modificate: la semantica di valore garantisce che la copia non tocchi l'originale.
public struct XcodeCandidate: Sendable, Equatable {
    public var key: String
    public var kind: XcodeResourceKind
    public var name: String
    public var path: String?
    public var cliId: String?
    public var runtimeIdentifier: String?
    public var build: String?
    public var state: String?
    public var sizeBytes: Int64?
    public var blockReason: String?
    public var dependencies: [String]?

    public init(
        key: String,
        kind: XcodeResourceKind,
        name: String,
        path: String? = nil,
        cliId: String? = nil,
        runtimeIdentifier: String? = nil,
        build: String? = nil,
        state: String? = nil,
        sizeBytes: Int64? = nil,
        blockReason: String? = nil,
        dependencies: [String]? = nil
    ) {
        self.key = key
        self.kind = kind
        self.name = name
        self.path = path
        self.cliId = cliId
        self.runtimeIdentifier = runtimeIdentifier
        self.build = build
        self.state = state
        self.sizeBytes = sizeBytes
        self.blockReason = blockReason
        self.dependencies = dependencies
    }

    public var canSelect: Bool { blockReason == nil }

    public var dependentDeviceKeys: [String] { dependencies ?? [] }
}

public enum XcodeInventoryWarningKind: Sendable, Equatable {
    case completenessFailure
    case advisory
}

public struct XcodeInventoryWarning: Sendable, Equatable {
    public let resourceGroup: XcodeResourceKind
    public let message: String
    /// Prudente per chi non classifica il proprio avviso: come in C#, il default è un difetto di
    /// completezza, che blocca la verifica di quel gruppo.
    public let kind: XcodeInventoryWarningKind

    public init(resourceGroup: XcodeResourceKind, message: String, kind: XcodeInventoryWarningKind = .completenessFailure) {
        self.resourceGroup = resourceGroup
        self.message = message
        self.kind = kind
    }

    public static func completenessFailure(_ group: XcodeResourceKind, _ message: String) -> XcodeInventoryWarning {
        XcodeInventoryWarning(resourceGroup: group, message: message, kind: .completenessFailure)
    }

    public static func advisory(_ group: XcodeResourceKind, _ message: String) -> XcodeInventoryWarning {
        XcodeInventoryWarning(resourceGroup: group, message: message, kind: .advisory)
    }
}

public struct XcodeSnapshot: Sendable, Equatable {
    public var candidates: [XcodeCandidate]
    public var warnings: [XcodeInventoryWarning]
    public var fileInventory: XcodeFileInventory

    public init(candidates: [XcodeCandidate], warnings: [XcodeInventoryWarning], fileInventory: XcodeFileInventory = .empty) {
        self.candidates = candidates
        self.warnings = warnings
        self.fileInventory = fileInventory
    }

    public static let empty = XcodeSnapshot(candidates: [], warnings: [])
}

/// Metadati portabili catturati insieme a una cartella validata, per riverificarla subito prima di
/// eliminarla. Le date valgono `nil` dove il C# aveva `default(DateTime)`, cioè «non rilevata».
public struct XcodeFileIdentity: Sendable, Equatable {
    public let canonicalPath: String
    public let isDirectory: Bool
    public let creationTime: Date?
    public let lastWriteTime: Date?
    public let logicalSizeBytes: Int64?

    public init(canonicalPath: String, isDirectory: Bool, creationTime: Date?, lastWriteTime: Date?, logicalSizeBytes: Int64?) {
        self.canonicalPath = canonicalPath
        self.isDirectory = isDirectory
        self.creationTime = creationTime
        self.lastWriteTime = lastWriteTime
        self.logicalSizeBytes = logicalSizeBytes
    }
}

public struct XcodeFileEntry: Sendable, Equatable {
    public let item: ScanItem
    public let identity: XcodeFileIdentity

    public init(item: ScanItem, identity: XcodeFileIdentity) {
        self.item = item
        self.identity = identity
    }
}

public enum XcodeItemOutcome: Sendable, Equatable {
    case deleted
    case skipped
    case failed
    case uncertain
}

public struct XcodeItemResult: Sendable, Equatable {
    public let candidate: XcodeCandidate
    public let outcome: XcodeItemOutcome
    public let reason: String
    public let verifiedEstimatedBytes: Int64?

    public init(candidate: XcodeCandidate, outcome: XcodeItemOutcome, reason: String, verifiedEstimatedBytes: Int64?) {
        self.candidate = candidate
        self.outcome = outcome
        self.reason = reason
        self.verifiedEstimatedBytes = verifiedEstimatedBytes
    }
}

public struct XcodeCleanResult: Sendable, Equatable {
    public let historyReport: CleanReport
    public let items: [XcodeItemResult]
    public let freeBytesBefore: Int64?
    public let freeBytesAfter: Int64?
    public let warnings: [String]

    public init(historyReport: CleanReport, items: [XcodeItemResult], freeBytesBefore: Int64?, freeBytesAfter: Int64?, warnings: [String]) {
        self.historyReport = historyReport
        self.items = items
        self.freeBytesBefore = freeBytesBefore
        self.freeBytesAfter = freeBytesAfter
        self.warnings = warnings
    }
}

/// Mappa immutabile chiave del candidato → cartella validata. Chiavi confrontate in modo ordinale
/// (`StringComparer.Ordinal`): sui byte UTF-8, non con l'equivalenza canonica di `String`.
/// Conserva l'ordine di inserimento; a parità di chiave vale la prima voce (i chiamanti non ne
/// passano mai due: lo scanner le scarta e `XcodeSelection` parte da chiavi già verificate).
public struct XcodeFileInventory: Sendable, Equatable {
    public static let empty = XcodeFileInventory([])

    public let keys: [String]
    private let entries: [[UInt8]: XcodeFileEntry]

    public init(_ items: [(key: String, entry: XcodeFileEntry)]) {
        var keys: [String] = []
        var entries: [[UInt8]: XcodeFileEntry] = [:]
        for item in items {
            let ordinal = XcodeText.ordinalKey(item.key)
            if entries[ordinal] != nil { continue }
            entries[ordinal] = item.entry
            keys.append(item.key)
        }
        self.keys = keys
        self.entries = entries
    }

    public subscript(key: String) -> XcodeFileEntry? {
        entries[XcodeText.ordinalKey(key)]
    }

    public var count: Int { keys.count }

    public var values: [XcodeFileEntry] { keys.compactMap { self[$0] } }

    public func contains(_ key: String) -> Bool { self[key] != nil }
}

/// Equivalente di `ArgumentException`: un inventario o una selezione che il chiamante non doveva
/// produrre. Il testo è quello del C# (in inglese, senza il suffisso «(Parameter '…')» di .NET).
public struct XcodeArgumentError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Equivalente di `InvalidOperationException`: una conferma che non può procedere.
public struct XcodeOperationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Equivalente di `XcodeUnavailableException`: `xcrun` assente o non avviabile.
public struct XcodeUnavailableError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// `IXcodeCli`: solo comandi d'inventario in lettura e rimozioni mirate per UUID.
public protocol XcodeCliInvoking: Sendable {
    func readInventory() async throws -> XcodeSnapshot
    func deleteDevice(_ uuid: String) async throws -> ProcessResult
    func deleteRuntime(_ uuid: String) async throws -> ProcessResult
}

/// `IXcodeInventoryCollector`: il confine verso l'applicazione.
public protocol XcodeInventoryCollecting: Sendable {
    func collect() async throws -> XcodeSnapshot
}
```

- [ ] **Step 4: Implementare le primitive di testo e UUID**

`Sources/CleanerCore/Xcode/XcodeText.swift`:

```swift
import Darwin

/// Le operazioni sul testo che il C# di Xcode faceva con `string` e `StringComparison`, con la
/// stessa semantica: confronti ordinali sui byte UTF-8 (una `String` Swift confronterebbe per
/// equivalenza canonica), spazi come `char.IsWhiteSpace` e `\s` di .NET, righe divise solo su
/// "\n" (in Swift "\r\n" è un solo `Character` e non verrebbe diviso).
enum XcodeText {
    /// `string.Equals(a, b, StringComparison.Ordinal)`: due `nil` sono uguali.
    static func same(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case let (left?, right?): left.utf8.elementsEqual(right.utf8)
        default: false
        }
    }

    /// Chiave per insiemi e dizionari con `StringComparer.Ordinal`.
    static func ordinalKey(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    /// Chiave per insiemi e dizionari con `StringComparer.OrdinalIgnoreCase`.
    static func caseInsensitiveKey(_ text: String) -> [UInt8] {
        Array(PathText.folded(text).utf8)
    }

    /// `Distinct(StringComparer.Ordinal)`: conserva la prima occorrenza e l'ordine.
    static func distinct(_ texts: [String]) -> [String] {
        var seen = Set<[UInt8]>()
        return texts.filter { seen.insert(ordinalKey($0)).inserted }
    }

    /// `text.StartsWith(prefix, StringComparison.Ordinal)`.
    static func hasOrdinalPrefix(_ text: String, _ prefix: String) -> Bool {
        text.utf8.starts(with: prefix.utf8)
    }

    /// `text.Contains(fragment, StringComparison.OrdinalIgnoreCase)`: ricerca sui testi ripiegati
    /// da `PathText.folded`, che non cambia mai il numero di scalari.
    static func containsIgnoringCase(_ text: String, _ fragment: String) -> Bool {
        let haystack = Array(PathText.folded(text).unicodeScalars)
        let needle = Array(PathText.folded(fragment).unicodeScalars)
        guard needle.count <= haystack.count else { return false }
        guard !needle.isEmpty else { return true }
        for start in 0...(haystack.count - needle.count)
        where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return true
        }
        return false
    }

    /// Gli spazi di `char.IsWhiteSpace` e di `\s` nelle regex .NET: U+0009–U+000D, U+0085 e le
    /// categorie Unicode Zs, Zl, Zp.
    static func isWhiteSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x09...0x0D, 0x85:
            return true
        default:
            switch scalar.properties.generalCategory {
            case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
            default: return false
            }
        }
    }

    /// `string.Trim()`.
    static func trimmed(_ text: String) -> String {
        let scalars = text.unicodeScalars
        guard let first = scalars.firstIndex(where: { !isWhiteSpace($0) }),
              let last = scalars.lastIndex(where: { !isWhiteSpace($0) }) else { return "" }
        return String(scalars[first...last])
    }

    /// `string.IsNullOrWhiteSpace`.
    static func isNullOrWhiteSpace(_ text: String?) -> Bool {
        guard let text else { return true }
        return text.unicodeScalars.allSatisfy(isWhiteSpace)
    }

    /// `text.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)`.
    static func lines(_ text: String) -> [String] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { trimmed(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// `Exception.Message` per gli errori che arrivano fino all'utente.
    static func message(_ error: any Error) -> String {
        switch error {
        case let error as FileSystemError:
            return error.message
        case let error as ProcessLaunchError:
            return String(cString: strerror(error.code))
        case is CancellationError:
            return String(localized: "operazione annullata", bundle: .module)
        default:
            return String(describing: error)
        }
    }
}

/// Riconoscimento degli UUID come `Guid` in .NET, restituiti nella forma canonica "D" minuscola.
enum XcodeUuid {
    private static let hyphenOffsets: Set<Int> = [8, 13, 18, 23]

    /// `Guid.TryParseExact(text, "D", …)`: 8-4-4-4-12 cifre esadecimali, spazi esterni ignorati.
    /// Più rigoroso di .NET, che dentro i gruppi accetta anche "+" e "0x" (misurato su .NET 10:
    /// "+1111111-…" diventa "01111111-…").
    static func canonicalExact(_ text: String) -> String? {
        exactD(Array(XcodeText.trimmed(text).utf8))
    }

    /// `Guid.TryParse`: forme "D", "N" (32 cifre), "B" ({…}) e "P" ((…)). La forma "X"
    /// ({0x…,{0x…}}) non è riconosciuta: la chiave resta testo e non corrisponde a nessun UUID.
    static func canonical(_ text: String) -> String? {
        let bytes = Array(XcodeText.trimmed(text).utf8)
        switch bytes.count {
        case 36:
            return exactD(bytes)
        case 32:
            let digits = bytes.compactMap(lowercaseHexDigit)
            return digits.count == 32 ? format(digits) : nil
        case 38:
            guard let open = bytes.first, let close = bytes.last,
                  (open == UInt8(ascii: "{") && close == UInt8(ascii: "}"))
                    || (open == UInt8(ascii: "(") && close == UInt8(ascii: ")")) else { return nil }
            return exactD(Array(bytes.dropFirst().dropLast()))
        default:
            return nil
        }
    }

    /// Lavora sui byte UTF-8: ogni carattere ammesso è ASCII, quindi un carattere non ASCII
    /// fallisce comunque il controllo di cifra o di lunghezza.
    private static func exactD(_ bytes: [UInt8]) -> String? {
        guard bytes.count == 36 else { return nil }
        var digits: [UInt8] = []
        for (offset, byte) in bytes.enumerated() {
            if hyphenOffsets.contains(offset) {
                guard byte == UInt8(ascii: "-") else { return nil }
            } else {
                guard let digit = lowercaseHexDigit(byte) else { return nil }
                digits.append(digit)
            }
        }
        return format(digits)
    }

    private static func lowercaseHexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "f"): byte
        case UInt8(ascii: "A")...UInt8(ascii: "F"): byte + 32
        default: nil
        }
    }

    /// 32 cifre esadecimali minuscole → "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx".
    private static func format(_ digits: [UInt8]) -> String {
        var result: [UInt8] = []
        for (offset, digit) in digits.enumerated() {
            if offset == 8 || offset == 12 || offset == 16 || offset == 20 { result.append(UInt8(ascii: "-")) }
            result.append(digit)
        }
        return String(decoding: result, as: UTF8.self)
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeTextTests|XcodeModelsTests"`
Expected: `Test run with 9 tests … passed`, nessun warning.

- [ ] **Step 6: Registro di parità e commit**

Sezione «Test solo Swift», aggiungere:

```markdown
| Xcode/XcodeTextTests.swift | 7 | UUID come `Guid` di .NET (forme D, N, B, P; spazi esterni), spazi e righe come .NET, confronti ordinali, `ex.Message` |
| Xcode/XcodeModelsTests.swift | 2 | inventario delle cartelle con chiavi ordinali e ordine di inserimento; avvisi e stato derivato dei candidati |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Riconoscimento degli UUID | `Guid.TryParseExact("D")` accetta anche "+" e "0x" nei gruppi ("+1111111-…" → "01111111-…"); `Guid.TryParse` accetta la forma X | solo cifre esadecimali; forme D, N, B, P | accettata (lato sicuro: una chiave non riconosciuta non seleziona nulla) |
| Testo degli errori di selezione e conferma | `ArgumentException.Message` con il suffisso «(Parameter '…')» | stesso testo, senza suffisso | accettata |
| Testo di un annullamento mostrato come motivo | `OperationCanceledException.Message` («The operation was canceled.») | «operazione annullata» | accettata (come i messaggi di sistema, spec §5.3) |
| `with` sui record Xcode | copia immutabile | `struct` con proprietà `var`: la copia modificata non tocca l'originale | equivalente |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): add Xcode models and .NET-equivalent text and UUID helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `XcodeClassifier` e `XcodeSelection`

Il classificatore applica i blocchi di sicurezza correnti; la selezione costruisce l'anteprima e il piano confermato. Stanno nello stesso task perché `XcodeSelection.preview` riclassifica l'inventario e il primo test del classificatore passa dall'anteprima.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeClassifier.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeSelection.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeClassifierTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeSelectionTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeClassifier.cs`, `XcodeSelection.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeClassifierTests.cs`, `XcodeSelectionTests.cs`

**Interfaces:**
- Consumes: modelli, errori, `XcodeText`, `XcodeUuid` (Task 2); `PathText`, `ScanItem` (piano 1).
- Produces:
  - `public enum XcodeClassifier` — `static func classify(_ snapshot: XcodeSnapshot, xcodeRunning: Bool) throws -> XcodeSnapshot` (lancia `XcodeArgumentError` per chiavi mancanti o ripetute); interni `static func normalizeSelectionKey(_:) -> String`, `static func isRunning(_: String?) -> Bool`, `isShutdown(_:)`, `isUnavailable(_:)`
  - `public struct XcodeConfirmation: Sendable, Equatable` — `selectedCandidates`, `retainedDependentDevices`, `estimatedBytes: Int64`, `unknownSizeCount: Int`; interni `sourceSnapshot` e `init(sourceSnapshot:selectedCandidates:retainedDependentDevices:estimatedBytes:unknownSizeCount:)`
  - `public struct XcodeConfirmedPlan: Sendable, Equatable` — `candidates`, `fileInventory`, `sourceSnapshot`; `init(sourceSnapshot:candidates:fileInventory:)` interno
  - `public enum XcodeSelection` — `static func preview(_ snapshot: XcodeSnapshot, selectedKeys: Set<String>) throws -> XcodeConfirmation` (`XcodeArgumentError`), `static func confirm(_ preview: XcodeConfirmation, acknowledgeDependencies: Bool) throws -> XcodeConfirmedPlan` (`XcodeOperationError`)

Note di porting:
- Gli inizializzatori di `XcodeConfirmation` e `XcodeConfirmedPlan` restano interni, come i costruttori `internal` del C#: solo `XcodeSelection` produce un'anteprima o un piano.
- `selectedKeys` è un `Set<String>` come l'`IReadOnlySet<string>` del C#. Un `Set` Swift non ha l'ordine di inserimento dell'`HashSet`: le chiavi si esaminano in ordine di byte, così con più chiavi non valide l'errore riportato è sempre lo stesso.
- La chiave `null` in una selezione («Selection contains an empty key.») è impossibile per tipo e non ha un ramo.
- Il test C# `ConfirmationCopiesCandidatesAndGuardedInventory` verificava che la lista del piano fosse di sola lettura (`NotSupportedException` su `Add`); in Swift la lista è un valore e il test verifica che modificarne una copia non tocchi il piano.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeClassifierTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct XcodeClassifierTests {
    private func snapshot(_ candidates: XcodeCandidate...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: [])
    }

    private func file(_ key: String, _ kind: XcodeResourceKind = .derivedData) -> XcodeCandidate {
        XcodeCandidate(key: key, kind: kind, name: key, sizeBytes: 5)
    }

    private func device(_ key: String, state: String = "Shutdown") -> XcodeCandidate {
        XcodeCandidate(key: key, kind: .device, name: "iPhone", cliId: key, runtimeIdentifier: "iOS 18", state: state, sizeBytes: 7)
    }

    private func runtime(_ key: String, dependencies: [String]? = nil) -> XcodeCandidate {
        XcodeCandidate(key: key, kind: .runtime, name: "iOS 18", cliId: "22222222-2222-4222-8222-222222222222", sizeBytes: 9, dependencies: dependencies)
    }

    private func single(_ candidates: [XcodeCandidate], _ kind: XcodeResourceKind? = nil) throws -> XcodeCandidate {
        let matching = candidates.filter { kind == nil || $0.kind == kind }
        #expect(matching.count == 1)
        return try #require(matching.first)
    }

    @Test func allRowsStartDeselected() throws {
        let classified = try XcodeClassifier.classify(snapshot(
            file("derived-data:/dd"), device("11111111-1111-4111-8111-111111111111"), runtime("runtime:22222222-2222-4222-8222-222222222222")), xcodeRunning: false)

        let preview = try XcodeSelection.preview(classified, selectedKeys: [])
        #expect(preview.selectedCandidates.isEmpty)
    }

    @Test func bootedDeviceAndItsRuntimeAreBlocked() throws {
        let booted = device("11111111-1111-4111-8111-111111111111", state: "Booted")
        let dependent = runtime("runtime:22222222-2222-4222-8222-222222222222", dependencies: [booted.key])

        let classified = try XcodeClassifier.classify(snapshot(booted, dependent), xcodeRunning: false)

        #expect(try !single(classified.candidates, .device).canSelect)
        #expect(try !single(classified.candidates, .runtime).canSelect)
    }

    @Test func unavailableDeviceWithVerifiedUuidRemainsSelectable() throws {
        var unavailable = device("11111111-1111-4111-8111-111111111111", state: "Unavailable")
        unavailable.blockReason = "Stato del dispositivo non verificato: Unavailable; ripeti l'analisi."

        let classified = try XcodeClassifier.classify(snapshot(unavailable), xcodeRunning: false)

        #expect(try single(classified.candidates).canSelect)
    }

    @Test func unavailableDevicePreservesUnrelatedSafetyBlock() throws {
        var unavailable = device("11111111-1111-4111-8111-111111111111", state: "Unavailable")
        unavailable.blockReason = "UUID duplicato con metadati in conflitto."

        let classified = try XcodeClassifier.classify(snapshot(unavailable), xcodeRunning: false)

        #expect(try single(classified.candidates).blockReason == "UUID duplicato con metadati in conflitto.")
    }

    @Test func deviceWithoutMatchingCliUuidIsBlocked() throws {
        var mismatched = device("11111111-1111-4111-8111-111111111111")
        mismatched.cliId = "33333333-3333-4333-8333-333333333333"

        let classified = try XcodeClassifier.classify(snapshot(mismatched), xcodeRunning: false)

        #expect(try !single(classified.candidates).canSelect)
    }

    @Test func xcodeRunningBlocksFileCleanup() throws {
        let classified = try XcodeClassifier.classify(
            snapshot(file("derived-data:/dd"), file("device-support:/ds", .deviceSupport)), xcodeRunning: true)

        #expect(classified.candidates.allSatisfy { !$0.canSelect })
    }
}
```

`Tests/CleanerCoreTests/Xcode/XcodeSelectionTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct XcodeSelectionTests {
    private static let deviceKey = "11111111-1111-4111-8111-111111111111"
    private static let runtimeKey = "runtime:22222222-2222-4222-8222-222222222222"

    private func createSnapshot(_ candidates: XcodeCandidate...) throws -> XcodeSnapshot {
        try XcodeClassifier.classify(XcodeSnapshot(candidates: candidates, warnings: []), xcodeRunning: false)
    }

    private func device() -> XcodeCandidate {
        XcodeCandidate(key: Self.deviceKey, kind: .device, name: "iPhone 16", cliId: Self.deviceKey, state: "Shutdown", sizeBytes: 10)
    }

    private func runtime(_ dependencies: [String]?) -> XcodeCandidate {
        XcodeCandidate(key: Self.runtimeKey, kind: .runtime, name: "iOS 18", cliId: "22222222-2222-4222-8222-222222222222", sizeBytes: 20, dependencies: dependencies)
    }

    /// `XcodeFileIdentity(path, true, time, time, size)`: `nil` sta per `default(DateTime)`.
    private func entry(_ itemPath: String, identityPath: String, time: Date?, logicalSize: Int64?) -> XcodeFileEntry {
        XcodeFileEntry(
            item: ScanItem(path: itemPath, sizeBytes: 3, isDirectory: true, declaredRoot: "/"),
            identity: XcodeFileIdentity(canonicalPath: identityPath, isDirectory: true, creationTime: time, lastWriteTime: time, logicalSizeBytes: logicalSize))
    }

    @Test func unknownKeyIsRejected() throws {
        let snapshot = try createSnapshot(device(), runtime([Self.deviceKey]))
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: ["unknown"]) }
    }

    @Test func duplicateNormalizedUuidSelectionsCollapse() throws {
        let snapshot = try createSnapshot(device())
        let preview = try XcodeSelection.preview(snapshot, selectedKeys: [Self.deviceKey, Self.deviceKey.uppercased()])
        #expect(preview.selectedCandidates.count == 1)
    }

    @Test func directSelectionOfBlockedRowIsRejected() {
        var blocked = device()
        blocked.state = "Booted"
        let snapshot = XcodeSnapshot(candidates: [blocked], warnings: [])
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: [Self.deviceKey]) }
    }

    @Test func selectedFileWithoutGuardedInventoryIsRejected() throws {
        let file = XcodeCandidate(key: "derived-data:/one", kind: .derivedData, name: "One", path: "/one", sizeBytes: 3)
        let snapshot = try createSnapshot(file)
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: [file.key]) }
    }

    @Test func selectedFileWithIncompleteGuardedInventoryIsRejected() throws {
        let file = XcodeCandidate(key: "derived-data:/one", kind: .derivedData, name: "One", path: "/one", sizeBytes: 3)
        var snapshot = try createSnapshot(file)
        snapshot.fileInventory = XcodeFileInventory([(file.key, entry("/elsewhere", identityPath: "/one", time: nil, logicalSize: 3))])
        #expect(throws: XcodeArgumentError.self) { try XcodeSelection.preview(snapshot, selectedKeys: [file.key]) }
    }

    @Test func retainedDependenciesRequireAcknowledgement() throws {
        let preview = try XcodeSelection.preview(try createSnapshot(device(), runtime([Self.deviceKey])), selectedKeys: [Self.runtimeKey])
        #expect(preview.retainedDependentDevices.contains { $0.key == Self.deviceKey })
        #expect(throws: XcodeOperationError.self) { try XcodeSelection.confirm(preview, acknowledgeDependencies: false) }
        #expect(try XcodeSelection.confirm(preview, acknowledgeDependencies: true).candidates.count == 1)
    }

    @Test func confirmDoesNotSelectDependentDevices() throws {
        let preview = try XcodeSelection.preview(try createSnapshot(device(), runtime([Self.deviceKey])), selectedKeys: [Self.runtimeKey])
        let plan = try XcodeSelection.confirm(preview, acknowledgeDependencies: true)
        #expect(!plan.candidates.contains { $0.key == Self.deviceKey })
        #expect(plan.candidates.count == 1)
        #expect(plan.candidates.first?.key == Self.runtimeKey)
    }

    @Test func unknownSizesRemainVisible() throws {
        let unknown = XcodeCandidate(key: "derived-data:/unknown", kind: .derivedData, name: "Unknown", path: "/unknown", sizeBytes: nil)
        var snapshot = try createSnapshot(unknown)
        snapshot.fileInventory = XcodeFileInventory([(unknown.key, entry("/unknown", identityPath: "/unknown", time: Date(timeIntervalSince1970: 0), logicalSize: nil))])

        let preview = try XcodeSelection.preview(snapshot, selectedKeys: [unknown.key])

        #expect(preview.unknownSizeCount == 1)
        #expect(preview.estimatedBytes == 0)
        #expect(preview.selectedCandidates.count == 1)
        #expect(preview.selectedCandidates.first?.sizeBytes == nil)
    }

    // In C# la lista dei candidati del piano era di sola lettura (NotSupportedException su Add).
    // In Swift è un valore: si verifica che modificarne una copia non tocchi il piano.
    @Test func confirmationCopiesCandidatesAndGuardedInventory() throws {
        let file = XcodeCandidate(key: "derived-data:/one", kind: .derivedData, name: "One", path: "/one", sizeBytes: 3)
        let guarded = entry("/one", identityPath: "/one", time: Date(timeIntervalSince1970: 0), logicalSize: 3)
        var snapshot = try createSnapshot(file)
        snapshot.fileInventory = XcodeFileInventory([(file.key, guarded)])

        let preview = try XcodeSelection.preview(snapshot, selectedKeys: [file.key])
        let plan = try XcodeSelection.confirm(preview, acknowledgeDependencies: true)

        #expect(plan.fileInventory[file.key] == guarded)
        var candidates = plan.candidates
        candidates.append(file)
        #expect(plan.candidates.count == 1)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeClassifierTests|XcodeSelectionTests"`
Expected: errore di compilazione `cannot find 'XcodeClassifier' in scope` o `cannot find 'XcodeSelection' in scope`, secondo il file che il compilatore esamina per primo.

- [ ] **Step 3: Implementare `XcodeClassifier`**

`Sources/CleanerCore/Xcode/XcodeClassifier.swift`:

```swift
/// Applica le classificazioni di sicurezza correnti senza introdurre alcuno stato di selezione.
public enum XcodeClassifier {
    private static let runtimePrefix = "runtime:"

    public static func classify(_ snapshot: XcodeSnapshot, xcodeRunning: Bool) throws -> XcodeSnapshot {
        var keys = Set<[UInt8]>()
        for candidate in snapshot.candidates {
            guard !XcodeText.isNullOrWhiteSpace(candidate.key),
                  keys.insert(XcodeText.ordinalKey(normalizeSelectionKey(candidate.key))).inserted else {
                throw XcodeArgumentError(String(localized: "Xcode inventory contains a missing or duplicate candidate key.", bundle: .module))
            }
        }

        var byKey: [[UInt8]: XcodeCandidate] = [:]
        for candidate in snapshot.candidates {
            byKey[XcodeText.ordinalKey(normalizeSelectionKey(candidate.key))] = candidate
        }

        let classified = snapshot.candidates.map { classifyCandidate($0, byKey, xcodeRunning) }
        return XcodeSnapshot(candidates: classified, warnings: snapshot.warnings, fileInventory: snapshot.fileInventory)
    }

    private static func classifyCandidate(
        _ candidate: XcodeCandidate,
        _ byKey: [[UInt8]: XcodeCandidate],
        _ xcodeRunning: Bool
    ) -> XcodeCandidate {
        var block = candidate.blockReason
        switch candidate.kind {
        case .derivedData, .deviceSupport:
            if xcodeRunning {
                block = block ?? String(localized: "Chiudi Xcode e ripeti l'analisi prima di rimuovere file.", bundle: .module)
            }
        case .device:
            let identityVerified = isMatchingUuid(candidate.key, candidate.cliId)
            if !identityVerified {
                block = block ?? String(localized: "Identità UUID del dispositivo non verificata.", bundle: .module)
            } else if isRunning(candidate.state) {
                block = String(localized: "Arresta il dispositivo in Xcode prima di rimuoverlo.", bundle: .module)
            } else if let state = candidate.state, isUnavailable(state) {
                // Si allenta solo l'avviso che il parser ricava dallo stato "Unavailable": ogni
                // altro avviso d'inventario o d'identità resta un blocco.
                let unavailableStateWarning = String(localized: "Stato del dispositivo non verificato: \(state); ripeti l'analisi.", bundle: .module)
                if let current = block, PathText.equalsIgnoringCase(current, unavailableStateWarning) {
                    block = nil
                }
            } else if !isShutdown(candidate.state) {
                block = block ?? String(localized: "Stato del dispositivo non verificato; ripeti l'analisi.", bundle: .module)
            }
        case .runtime:
            if !isRuntimeIdentityVerified(candidate) {
                block = block ?? String(localized: "Identità del runtime non verificata.", bundle: .module)
            }

            for dependencyKey in candidate.dependentDeviceKeys {
                guard let dependency = byKey[XcodeText.ordinalKey(normalizeSelectionKey(dependencyKey))],
                      dependency.kind == .device else {
                    block = block ?? String(localized: "Dipendenze del runtime non verificate; ripeti l'analisi.", bundle: .module)
                    continue
                }

                if isRunning(dependency.state) {
                    block = String(localized: "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo.", bundle: .module)
                    break
                }

                if !isShutdown(dependency.state) && !isUnavailable(dependency.state) {
                    block = block ?? String(localized: "Lo stato di un dispositivo che usa questo runtime non è verificato.", bundle: .module)
                }
            }
        }

        var classified = candidate
        classified.blockReason = block
        classified.dependencies = candidate.dependentDeviceKeys
        return classified
    }

    /// Un UUID, anche con prefisso "runtime:", nella forma canonica minuscola: due grafie dello
    /// stesso UUID selezionano la stessa riga. Ogni altra chiave resta com'è.
    static func normalizeSelectionKey(_ key: String) -> String {
        if let uuid = XcodeUuid.canonical(key) { return uuid }

        if PathText.hasPrefixIgnoringCase(key, runtimePrefix) {
            // Il prefisso riconosciuto occupa in `key` lo stesso numero di scalari di "runtime:".
            let rest = String(String.UnicodeScalarView(key.unicodeScalars.dropFirst(runtimePrefix.unicodeScalars.count)))
            if let uuid = XcodeUuid.canonical(rest) { return runtimePrefix + uuid }
        }

        return key
    }

    static func isRunning(_ state: String?) -> Bool {
        guard let state else { return false }
        return PathText.equalsIgnoringCase(state, "Booted")
            || PathText.equalsIgnoringCase(state, "Booting")
            || PathText.equalsIgnoringCase(state, "Starting")
    }

    static func isShutdown(_ state: String?) -> Bool {
        state.map { PathText.equalsIgnoringCase($0, "Shutdown") } ?? false
    }

    static func isUnavailable(_ state: String?) -> Bool {
        state.map { PathText.equalsIgnoringCase($0, "Unavailable") } ?? false
    }

    private static func isMatchingUuid(_ key: String, _ cliId: String?) -> Bool {
        guard let keyUuid = XcodeUuid.canonical(key), let cliId, let cliUuid = XcodeUuid.canonical(cliId) else { return false }
        return keyUuid == cliUuid
    }

    private static func isRuntimeIdentityVerified(_ candidate: XcodeCandidate) -> Bool {
        guard let cliId = candidate.cliId, let cliUuid = XcodeUuid.canonical(cliId),
              XcodeText.hasOrdinalPrefix(candidate.key, runtimePrefix) else { return false }
        let rest = String(decoding: candidate.key.utf8.dropFirst(runtimePrefix.utf8.count), as: UTF8.self)
        guard let keyUuid = XcodeUuid.canonical(rest) else { return false }
        return keyUuid == cliUuid
    }
}
```

- [ ] **Step 4: Implementare `XcodeSelection`**

`Sources/CleanerCore/Xcode/XcodeSelection.swift`:

```swift
/// L'anteprima di una selezione: cosa verrà rimosso, cosa resta e quanto spazio si stima.
public struct XcodeConfirmation: Sendable, Equatable {
    public let selectedCandidates: [XcodeCandidate]
    public let retainedDependentDevices: [XcodeCandidate]
    public let estimatedBytes: Int64
    public let unknownSizeCount: Int
    let sourceSnapshot: XcodeSnapshot

    /// Interno come il costruttore C#: solo `XcodeSelection` produce un'anteprima.
    init(
        sourceSnapshot: XcodeSnapshot,
        selectedCandidates: [XcodeCandidate],
        retainedDependentDevices: [XcodeCandidate],
        estimatedBytes: Int64,
        unknownSizeCount: Int
    ) {
        self.sourceSnapshot = sourceSnapshot
        self.selectedCandidates = selectedCandidates
        self.retainedDependentDevices = retainedDependentDevices
        self.estimatedBytes = estimatedBytes
        self.unknownSizeCount = unknownSizeCount
    }
}

/// Il piano confermato dall'utente: le sole risorse approvate e le identità delle cartelle da
/// riverificare prima di eliminarle.
public struct XcodeConfirmedPlan: Sendable, Equatable {
    public let candidates: [XcodeCandidate]
    public let fileInventory: XcodeFileInventory
    public let sourceSnapshot: XcodeSnapshot

    init(sourceSnapshot: XcodeSnapshot, candidates: [XcodeCandidate], fileInventory: XcodeFileInventory) {
        self.sourceSnapshot = sourceSnapshot
        self.candidates = candidates
        self.fileInventory = fileInventory
    }
}

public enum XcodeSelection {
    /// Le chiavi si esaminano in ordine ordinale: con più chiavi non valide l'errore riportato è
    /// sempre lo stesso (un `Set` Swift non ha l'ordine di inserimento dell'`HashSet` C#).
    public static func preview(_ snapshot: XcodeSnapshot, selectedKeys: Set<String>) throws -> XcodeConfirmation {
        let classified = try XcodeClassifier.classify(snapshot, xcodeRunning: false)

        var ordered: [(key: [UInt8], candidate: XcodeCandidate)] = []
        var candidatesByKey: [[UInt8]: XcodeCandidate] = [:]
        for candidate in classified.candidates {
            let normalized = XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey(candidate.key))
            guard candidatesByKey[normalized] == nil else {
                throw XcodeArgumentError(String(localized: "Xcode inventory contains duplicate candidate keys.", bundle: .module))
            }
            candidatesByKey[normalized] = candidate
            ordered.append((normalized, candidate))
        }

        var selected = Set<[UInt8]>()
        for rawKey in selectedKeys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            let key = XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey(rawKey))
            guard selected.insert(key).inserted else { continue }

            guard let candidate = candidatesByKey[key] else {
                throw XcodeArgumentError(String(localized: "Unknown Xcode candidate key: \(rawKey)", bundle: .module))
            }

            if let reason = candidate.blockReason {
                throw XcodeArgumentError(String(localized: "Xcode candidate is blocked: \(candidate.name): \(reason)", bundle: .module))
            }

            if isFileCandidate(candidate) && completeFileGuard(classified.fileInventory, candidate) == nil {
                throw XcodeArgumentError(String(localized: "Selected file candidate has no complete guarded inventory entry: \(candidate.name)", bundle: .module))
            }
        }

        let chosen = ordered.filter { selected.contains($0.key) }.map { copyCandidate($0.candidate) }
        let chosenKeys = Set(chosen.map { XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey($0.key)) })

        var retained: [XcodeCandidate] = []
        var retainedKeys = Set<[UInt8]>()
        for runtime in chosen where runtime.kind == .runtime {
            for dependencyKey in runtime.dependentDeviceKeys {
                let key = XcodeText.ordinalKey(XcodeClassifier.normalizeSelectionKey(dependencyKey))
                guard !chosenKeys.contains(key),
                      let device = candidatesByKey[key], device.kind == .device,
                      retainedKeys.insert(key).inserted else { continue }
                retained.append(copyCandidate(device))
            }
        }

        let unknownCount = chosen.filter { $0.sizeBytes == nil }.count
        let knownBytes = chosen.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        return XcodeConfirmation(
            sourceSnapshot: copySnapshot(classified),
            selectedCandidates: chosen,
            retainedDependentDevices: retained,
            estimatedBytes: knownBytes,
            unknownSizeCount: unknownCount)
    }

    public static func confirm(_ preview: XcodeConfirmation, acknowledgeDependencies: Bool) throws -> XcodeConfirmedPlan {
        guard !preview.selectedCandidates.isEmpty else {
            throw XcodeOperationError(String(localized: "No Xcode resources were selected.", bundle: .module))
        }

        if !preview.retainedDependentDevices.isEmpty && !acknowledgeDependencies {
            throw XcodeOperationError(String(localized: "Acknowledge the retained devices that depend on the selected runtime.", bundle: .module))
        }

        let copied = preview.selectedCandidates.map(copyCandidate)
        var inventory: [(key: String, entry: XcodeFileEntry)] = []
        for candidate in copied where isFileCandidate(candidate) {
            guard let entry = completeFileGuard(preview.sourceSnapshot.fileInventory, candidate) else {
                throw XcodeOperationError(String(localized: "Selected file candidate lost its guarded inventory entry: \(candidate.name)", bundle: .module))
            }
            inventory.append((candidate.key, entry))
        }

        return XcodeConfirmedPlan(sourceSnapshot: preview.sourceSnapshot, candidates: copied, fileInventory: XcodeFileInventory(inventory))
    }

    private static func isFileCandidate(_ candidate: XcodeCandidate) -> Bool {
        candidate.kind == .derivedData || candidate.kind == .deviceSupport
    }

    /// La voce dell'inventario se è completa e coerente con la riga, altrimenti `nil`.
    private static func completeFileGuard(_ inventory: XcodeFileInventory, _ candidate: XcodeCandidate) -> XcodeFileEntry? {
        guard let path = candidate.path, let found = inventory[candidate.key] else { return nil }

        let identity = found.identity
        let complete = !XcodeText.isNullOrWhiteSpace(identity.canonicalPath)
            && XcodeText.same(path, identity.canonicalPath)
            && XcodeText.same(found.item.path, identity.canonicalPath)
            && found.item.isDirectory
            && identity.isDirectory
            && !XcodeText.isNullOrWhiteSpace(found.item.declaredRoot)
            && identity.creationTime != nil
            && identity.lastWriteTime != nil
        return complete ? found : nil
    }

    private static func copySnapshot(_ source: XcodeSnapshot) -> XcodeSnapshot {
        XcodeSnapshot(candidates: source.candidates.map(copyCandidate), warnings: source.warnings, fileInventory: source.fileInventory)
    }

    private static func copyCandidate(_ candidate: XcodeCandidate) -> XcodeCandidate {
        var copy = candidate
        copy.dependencies = candidate.dependentDeviceKeys
        return copy
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeClassifierTests|XcodeSelectionTests"`
Expected: `Test run with 15 tests … passed`, nessun warning.

- [ ] **Step 6: Registro di parità e commit**

Sostituire le righe `Xcode/XcodeClassifierTests.cs` e `Xcode/XcodeSelectionTests.cs` con:

```markdown
| Xcode/XcodeClassifierTests.cs | 6 | Xcode/XcodeClassifierTests.swift | 6 | 3 | |
| Xcode/XcodeSelectionTests.cs | 9 | Xcode/XcodeSelectionTests.swift | 9 | 3 | «lista del piano di sola lettura (`NotSupportedException`) → valore: modificarne una copia non tocca il piano»; chiave `null` impossibile per tipo |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Ordine di esame delle chiavi selezionate | ordine di inserimento dell'`HashSet` del chiamante | ordine dei byte UTF-8 (un `Set` Swift non ha ordine) | accettata (con più chiavi non valide l'errore è deterministico) |
```

Tabella «Candidati a miglioramento», aggiungere:

```markdown
| Errori di selezione, conferma e classificazione | in inglese come nel C# («Unknown Xcode candidate key: …», «Acknowledge the retained devices…»), mostrati dalla pagina Xcode | testi italiani nel catalogo |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeClassifier and XcodeSelection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `XcodeJson` con un lettore JSON che conserva l'ordine

`XcodeJson.ParseInventory` legge i due formati di `simctl` con `JsonDocument`, che conserva l'ordine delle proprietà: l'ordine dei gruppi di dispositivi decide quale copia di un UUID ripetuto si considera la prima e l'ordine delle righe mostrate. `JSONSerialization` restituirebbe dizionari senza ordine e `JSONDecoder` non garantisce l'ordine di `allKeys`; serve un lettore proprio, rigoroso come `JsonDocument` con le opzioni predefinite. La tolleranza del C# (dispositivi malformati, UUID mancanti, radice non oggetto) resta identica e le stesse fixture danno gli stessi esiti.

**Files:**
- Modify: `swift/MjmCleanerKit/Package.swift` (esclusione delle fixture dal target di test)
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/Fixtures/{malformed-devices,runtime-list-missing-uuid,runtime-list,simctl-list}.json` (copia)
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeFixtures.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeJsonReader.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeJson.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeJsonTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeJsonReaderTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeJson.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeJsonTests.cs`, `Fixtures/*.json`

**Interfaces:**
- Consumes: modelli, `XcodeText`, `XcodeUuid` (Task 2); `XcodeClassifier.isRunning`/`isShutdown`/`isUnavailable` e `classify` (Task 3).
- Produces:
  - `public enum XcodeJson` — `static func parseInventory(_ simctlJson: String?, _ runtimeJson: String?, runtimeDeleteSupported: Bool) -> XcodeSnapshot` (non lancia mai)
  - interni: `enum XcodeJsonValue: Sendable` (`object([XcodeJsonMember])`, `array`, `string`, `number(String)`, `bool`, `null`) con `property(_:)`, `string(_:)`, `bool(_:)`, `optionalInt64(_:) -> (value: Int64?, malformed: Bool)`; `struct XcodeJsonMember` (`name`, `value`); `struct XcodeJsonSyntaxError: Error` (`offset`); `struct XcodeJsonReader` con `static func parse(_ text: String) throws -> XcodeJsonValue`
  - test: `enum XcodeFixtures` — `static func text(_ name: String) throws -> String`

- [ ] **Step 1: Copiare le fixture e predisporne la lettura**

Run (da `swift/MjmCleanerKit`):

```bash
mkdir -p Tests/CleanerCoreTests/Xcode/Fixtures
cp ../../tests/MjmCleaner.Core.Tests/Xcode/Fixtures/*.json Tests/CleanerCoreTests/Xcode/Fixtures/
for f in ../../tests/MjmCleaner.Core.Tests/Xcode/Fixtures/*.json; do cmp "$f" "Tests/CleanerCoreTests/Xcode/Fixtures/$(basename "$f")"; done && echo "fixture identiche"
```

Expected: `fixture identiche` (quattro file: `malformed-devices.json`, `runtime-list-missing-uuid.json`, `runtime-list.json`, `simctl-list.json`).

SwiftPM segnala ogni file non sorgente in un target come «unhandled» e con `-warnings-as-errors` la segnalazione diventa un errore di build (verificato). Le fixture non sono risorse del bundle: si escludono dal target e i test le leggono dal disco.

`Package.swift`: il piano 2 (Docker), eseguito prima di questo, ha già escluso le proprie fixture. Sostituire:

```swift
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"],
            // Le fixture JSON di Docker si leggono dal sorgente dei test (`#filePath`), non da un
            // bundle: escluderle evita che SwiftPM le rifiuti come file non gestiti.
            exclude: ["Docker/Fixtures"]
        ),
```

con:

```swift
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"],
            // Le fixture JSON di Docker e di Xcode si leggono dal sorgente dei test (`#filePath`),
            // non da un bundle: escluderle evita che SwiftPM le rifiuti come file non gestiti, un
            // errore con -warnings-as-errors.
            exclude: ["Docker/Fixtures", "Xcode/Fixtures"]
        ),
```

`Tests/CleanerCoreTests/Xcode/XcodeFixtures.swift`:

```swift
import Foundation

/// Le fixture JSON dei test C# (`tests/MjmCleaner.Core.Tests/Xcode/Fixtures`), copiate byte per
/// byte in `Fixtures/` accanto a questo file e lette dal disco: nessuna risorsa nel bundle.
enum XcodeFixtures {
    private static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
```

- [ ] **Step 2: Scrivere i test (falliscono)**

I test portati dal C#:

`Tests/CleanerCoreTests/Xcode/XcodeJsonTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct XcodeJsonTests {
    private func fixture(_ name: String) throws -> String {
        try XcodeFixtures.text(name)
    }

    private func single(_ snapshot: XcodeSnapshot, _ kind: XcodeResourceKind) throws -> XcodeCandidate {
        let matching = snapshot.candidates.filter { $0.kind == kind }
        #expect(matching.count == 1)
        return try #require(matching.first)
    }

    @Test func malformedDevicesProducesWarningAndBlocksRuntimes() throws {
        let snapshot = XcodeJson.parseInventory(try fixture("malformed-devices.json"), try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .completenessFailure && !$0.message.isEmpty })
        let runtime = try single(snapshot, .runtime)
        #expect(!runtime.canSelect)
        #expect(XcodeText.containsIgnoringCase(try #require(runtime.blockReason), "simulatori"))
    }

    @Test func sameVersionDifferentBuildDoesNotGuess() throws {
        let simctl = """
            {"devices":{},"runtimes":[
              {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A4000","platform":"iOS"}]}
            """
        let images = """
            {
              "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A4000","deletable":true},
              "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF":{"identifier":"BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A5000","deletable":true}
            }
            """

        let snapshot = XcodeJson.parseInventory(simctl, images, runtimeDeleteSupported: true)

        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime })
        let runtimes = snapshot.candidates.filter { $0.kind == .runtime }
        #expect(runtimes.count == 2)
        #expect(runtimes.allSatisfy { !$0.canSelect && $0.runtimeIdentifier == nil })
    }

    @Test func missingRemovalUuidBlocksRuntime() throws {
        let snapshot = XcodeJson.parseInventory(try fixture("simctl-list.json"), try fixture("runtime-list-missing-uuid.json"), runtimeDeleteSupported: true)

        let runtime = try single(snapshot, .runtime)
        #expect(!runtime.canSelect)
        #expect(XcodeText.containsIgnoringCase(try #require(runtime.blockReason), "UUID"))
    }

    @Test func malformedDeviceSourceStillKeepsRuntimeVisible() throws {
        let snapshot = XcodeJson.parseInventory("{", try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        #expect(snapshot.candidates.contains { $0.kind == .runtime })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
    }

    @Test func emptyJsonInventoryIsSuccessful() {
        let snapshot = XcodeJson.parseInventory(#"{"runtimes":[],"devices":{}}"#, "{}", runtimeDeleteSupported: true)

        #expect(snapshot.candidates.isEmpty)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test func missingRuntimeMetadataKeepsValidDeviceEntry() throws {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown"}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        let device = try single(snapshot, .device)
        #expect(device.cliId == "11111111-1111-4111-8111-111111111111")
        #expect(device.canSelect)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime })
        #expect(try !single(snapshot, .runtime).canSelect)
    }

    @Test func malformedDeviceSiblingPreservesKnownDeviceButBlocksDeletion() throws {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown"},
              {"udid":"invalid","name":"Broken device","state":"Shutdown"}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)

        let device = try single(snapshot, .device)
        #expect(device.cliId == "11111111-1111-4111-8111-111111111111")
        #expect(!device.canSelect)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
    }

    @Test func unknownDeviceStateBlocksDeviceAndDependentRuntime() throws {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"MysteryState"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """

        let snapshot = XcodeJson.parseInventory(simctl, try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        #expect(try !single(snapshot, .device).canSelect)
        #expect(try !single(snapshot, .runtime).canSelect)
    }

    @Test func unavailableDeviceIsKnownNonrunningAndDoesNotBlockRuntime() throws {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """

        let snapshot = XcodeJson.parseInventory(simctl, try fixture("runtime-list.json"), runtimeDeleteSupported: true)

        let classified = try XcodeClassifier.classify(snapshot, xcodeRunning: false)
        let device = try single(classified, .device)
        let runtime = try single(classified, .runtime)
        #expect(!snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .completenessFailure })
        #expect(runtime.canSelect)
        #expect(runtime.dependentDeviceKeys.contains(device.key))
    }

    @Test func unavailableDeviceRetainsIndependentIdentityBlock() throws {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"},
              {"udid":"11111111-1111-4111-8111-111111111111","name":"Different device","state":"Unavailable"}]}}
            """

        let classified = try XcodeClassifier.classify(XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true), xcodeRunning: false)

        let device = try single(classified, .device)
        #expect(!device.canSelect)
        #expect(XcodeText.containsIgnoringCase(try #require(device.blockReason), "conflitto"))
    }

    @Test func nonObjectJsonRootReturnsWarningsWithoutThrowing() {
        let snapshot = XcodeJson.parseInventory("[]", "{}", runtimeDeleteSupported: true)

        #expect(snapshot.candidates.isEmpty)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime })
    }

    @Test func nonnumericDeviceSizePreservesSiblingWithUnknownSizeAndWarning() {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Shutdown","dataPathSize":100},
              {"udid":"22222222-2222-4222-8222-222222222222","name":"iPhone 16 Pro","state":"Shutdown","dataPathSize":[]}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)

        let devices = snapshot.candidates.filter { $0.kind == .device }
        #expect(devices.count == 2)
        #expect(devices.first?.sizeBytes == 100)
        #expect(devices.last?.sizeBytes == nil)
        #expect(devices.allSatisfy { $0.canSelect })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .advisory })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
    }

    @Test func deviceSizeAdvisoryDoesNotMaskIncompleteDeviceInventory() {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"33333333-3333-4333-8333-333333333333","name":"iPhone 16","state":"Shutdown","dataPathSize":[]},
              {"name":"missing UUID","state":"Shutdown"}]}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)

        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .advisory })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && $0.kind == .completenessFailure })
    }

    @Test func runtimeCandidateKeepsBackingPathAndLeavesAllocatedSizeUnknownUntilProbed() throws {
        let path = "/System/Library/AssetsV2/runtime.asset/AssetData"
        let simctl = #"{"runtimes":[],"devices":{}}"#
        let images = """
            {"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A4000","deletable":true,"path":"/System/Library/AssetsV2/runtime.asset/AssetData","mountPath":"/private/var/run/mounted-runtime","sizeBytes":999999}}
            """

        let snapshot = XcodeJson.parseInventory(simctl, images, runtimeDeleteSupported: true)

        let runtime = try single(snapshot, .runtime)
        #expect(runtime.path == path)
        #expect(runtime.sizeBytes == nil)
        #expect(runtime.key == "runtime:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
        #expect(runtime.cliId == "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
    }

    @Test func conflictingRepeatedDeviceUuidIsDeduplicatedAndBlocked() throws {
        let uuid = "abcdefab-cdef-4abc-8def-abcdefabcdef"
        let simctl = """
            {"devices":{
              "com.apple.CoreSimulator.SimRuntime.iOS-18-0":[{"udid":"abcdefab-cdef-4abc-8def-abcdefabcdef","name":"iPhone 16","state":"Shutdown","dataPathSize":100}],
              "com.apple.CoreSimulator.SimRuntime.watchOS-11-0":[{"udid":"ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF","name":"iPhone 16","state":"Shutdown","dataPathSize":200}]},
             "runtimes":[
               {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18.0","version":"18.0","buildversion":"22A000","platform":"iOS"},
               {"identifier":"com.apple.CoreSimulator.SimRuntime.watchOS-11-0","name":"watchOS 11.0","version":"11.0","buildversion":"22B000","platform":"watchOS"}]}
            """
        let runtimeJson = """
            {
              "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE":{"identifier":"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A000","deletable":true},
              "BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF":{"identifier":"BBBBBBBB-CCCC-4DDD-8EEE-FFFFFFFFFFFF","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.watchOS-11-0","version":"11.0","build":"22B000","deletable":true}
            }
            """

        let snapshot = XcodeJson.parseInventory(simctl, runtimeJson, runtimeDeleteSupported: true)

        let device = try single(snapshot, .device)
        #expect(device.key == uuid)
        #expect(device.cliId == uuid)
        #expect(!device.canSelect)
        #expect(device.sizeBytes == nil)
        #expect(snapshot.warnings.contains { $0.resourceGroup == .device && XcodeText.containsIgnoringCase($0.message, "UUID") })
        let runtimes = snapshot.candidates.filter { $0.kind == .runtime }
        #expect(runtimes.count == 2)
        #expect(runtimes.allSatisfy { XcodeText.containsIgnoringCase($0.blockReason ?? "", "UUID") })
        #expect(runtimes.flatMap(\.dependentDeviceKeys).allSatisfy { $0 == uuid })
    }
}
```

I test solo Swift del lettore, con i casi misurati su .NET:

`Tests/CleanerCoreTests/Xcode/XcodeJsonReaderTests.swift`:

```swift
import Testing
@testable import CleanerCore

/// Test solo Swift: il lettore JSON che sostituisce `JsonDocument`. I casi non validi sono quelli
/// che .NET 10 rifiuta (misurati), più il surrogato isolato che Swift rifiuta per costruzione.
struct XcodeJsonReaderTests {
    @Test func objectsKeepMemberOrderAndTheLastDuplicateWins() throws {
        let value = try XcodeJsonReader.parse(#"{"b":1,"a":"x","b":2}"#)

        guard case .object(let members) = value else {
            Issue.record("atteso un oggetto")
            return
        }
        #expect(members.map(\.name) == ["b", "a", "b"])
        #expect(value.optionalInt64("b").value == 2)
        #expect(value.string("a") == "x")
        #expect(value.string("b") == nil)
    }

    @Test(arguments: [
        "", " ", "{", "{}x", "\u{FEFF}{}", "{'a':1}", #"{"a":01}"#, #"{"a":1,}"#, "/*c*/{}",
        #"{"a":"\ud800"}"#, #"{"a":"\udc00x"}"#, "[\"\u{01}\"]", "[1.]", "[-]", "[1e]", "tru", "[\"\\x\"]",
    ])
    func invalidDocumentsAreRejectedLikeJsonDocument(text: String) {
        #expect(throws: XcodeJsonSyntaxError.self) { try XcodeJsonReader.parse(text) }
    }

    @Test func validDocumentsDecodeEscapesAndNumbers() throws {
        let value = try XcodeJsonReader.parse(#" {"s":"a\"\\\/\b\f\n\r\t\u00e9\ud83d\ude00","n":-0,"f":1.5e3,"t":true,"z":null,"l":[]} "#)

        #expect(value.string("s") == "a\"\\/\u{08}\u{0C}\n\r\t\u{E9}\u{1F600}")
        #expect(value.optionalInt64("n").value == 0)
        #expect(value.optionalInt64("f").malformed)
        #expect(value.bool("t") == true)
        guard case .null? = value.property("z"), case .array(let list)? = value.property("l") else {
            Issue.record("null e array attesi")
            return
        }
        #expect(list.isEmpty)
    }

    @Test func optionalInt64FollowsTryGetInt64() throws {
        let value = try XcodeJsonReader.parse(
            #"{"a":100,"b":100.0,"c":1e2,"d":9223372036854775807,"e":9223372036854775808,"f":"100","g":[]}"#)

        #expect(value.optionalInt64("a").value == 100)
        #expect(value.optionalInt64("b").malformed)
        #expect(value.optionalInt64("c").malformed)
        #expect(value.optionalInt64("d").value == Int64.max)
        #expect(value.optionalInt64("e").malformed)
        #expect(value.optionalInt64("f").malformed)
        #expect(value.optionalInt64("g").malformed)
        #expect(value.optionalInt64("assente").value == nil)
        #expect(!value.optionalInt64("assente").malformed)
    }

    @Test func nestingDeeperThanSixtyFourLevelsIsRejected() throws {
        let deepest = String(repeating: "[", count: 64) + String(repeating: "]", count: 64)
        let tooDeep = String(repeating: "[", count: 65) + String(repeating: "]", count: 65)

        _ = try XcodeJsonReader.parse(deepest)
        #expect(throws: XcodeJsonSyntaxError.self) { try XcodeJsonReader.parse(tooDeep) }
    }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeJsonTests|XcodeJsonReaderTests"`
Expected: errore di compilazione `cannot find 'XcodeJsonReader' in scope` o `cannot find 'XcodeJson' in scope`, secondo il file che il compilatore esamina per primo.

- [ ] **Step 4: Implementare il lettore JSON**

`Sources/CleanerCore/Xcode/XcodeJsonReader.swift`:

```swift
/// Valore JSON letto da `XcodeJsonReader`. Gli oggetti conservano l'ordine e le ripetizioni delle
/// proprietà come `JsonDocument`: l'ordine dei gruppi di dispositivi e delle immagini runtime
/// decide quale duplicato si considera per primo e l'ordine delle righe mostrate.
/// `JSONSerialization` restituirebbe un dizionario senza ordine.
enum XcodeJsonValue: Sendable {
    case object([XcodeJsonMember])
    case array([XcodeJsonValue])
    case string(String)
    /// Il numero com'è scritto nel documento: l'interpretazione spetta a chi legge.
    case number(String)
    case bool(Bool)
    case null

    /// `JsonElement.TryGetProperty`: confronto ordinale del nome; con nomi ripetuti vince l'ultimo
    /// (misurato su .NET 10). `nil` se il valore non è un oggetto o la proprietà manca.
    func property(_ name: String) -> XcodeJsonValue? {
        guard case .object(let members) = self else { return nil }
        return members.last { XcodeText.same($0.name, name) }?.value
    }

    /// Il testo di una proprietà stringa, altrimenti `nil` (helper `String` del C#).
    func string(_ name: String) -> String? {
        guard case .string(let text)? = property(name) else { return nil }
        return text
    }

    /// Un booleano, altrimenti `nil` (helper `Bool` del C#).
    func bool(_ name: String) -> Bool? {
        guard case .bool(let value)? = property(name) else { return nil }
        return value
    }

    /// Helper `OptionalInt64` del C#: proprietà assente → (`nil`, false); numero intero
    /// rappresentabile in 64 bit → (valore, false); qualunque altra cosa → (`nil`, true). Come
    /// `TryGetInt64`, "100.0" e "1e2" non sono interi.
    func optionalInt64(_ name: String) -> (value: Int64?, malformed: Bool) {
        guard let value = property(name) else { return (nil, false) }
        guard case .number(let literal) = value, let number = Int64(literal) else { return (nil, true) }
        return (number, false)
    }
}

struct XcodeJsonMember: Sendable {
    let name: String
    let value: XcodeJsonValue
}

/// JSON non valido: l'equivalente di `JsonException`. Il testo differisce da quello inglese di
/// .NET, come per gli errori di sistema (spec §5.3).
struct XcodeJsonSyntaxError: Error, Equatable, Sendable, CustomStringConvertible {
    let offset: Int

    var description: String {
        String(localized: "JSON non valido al byte \(offset)", bundle: .module)
    }
}

/// Lettore JSON rigoroso come `JsonDocument.Parse` con le opzioni predefinite: niente commenti,
/// niente virgole finali, niente zeri iniziali, profondità massima 64, un solo valore per
/// documento. Una sequenza `\u` con un surrogato isolato rende il documento non valido (.NET lo
/// accetta e lancia solo leggendo la stringa).
struct XcodeJsonReader {
    private static let maxDepth = 64

    private let bytes: [UInt8]
    private var position = 0

    private init(_ text: String) {
        bytes = Array(text.utf8)
    }

    static func parse(_ text: String) throws -> XcodeJsonValue {
        var reader = XcodeJsonReader(text)
        reader.skipWhiteSpace()
        let value = try reader.readValue(depth: 0)
        reader.skipWhiteSpace()
        guard reader.peek() == nil else { throw reader.failure() }
        return value
    }

    // MARK: - Valori

    private mutating func readValue(depth: Int) throws -> XcodeJsonValue {
        switch peek() {
        case UInt8(ascii: "{"):
            return try readObject(depth: depth + 1)
        case UInt8(ascii: "["):
            return try readArray(depth: depth + 1)
        case UInt8(ascii: "\""):
            return .string(try readString())
        case UInt8(ascii: "t"):
            try expect("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expect("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expect("null")
            return .null
        default:
            return .number(try readNumber())
        }
    }

    private mutating func readObject(depth: Int) throws -> XcodeJsonValue {
        guard depth <= Self.maxDepth else { throw failure() }
        position += 1
        var members: [XcodeJsonMember] = []
        skipWhiteSpace()
        if peek() == UInt8(ascii: "}") {
            position += 1
            return .object(members)
        }
        while true {
            skipWhiteSpace()
            guard peek() == UInt8(ascii: "\"") else { throw failure() }
            let name = try readString()
            skipWhiteSpace()
            guard peek() == UInt8(ascii: ":") else { throw failure() }
            position += 1
            skipWhiteSpace()
            members.append(XcodeJsonMember(name: name, value: try readValue(depth: depth)))
            skipWhiteSpace()
            switch peek() {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "}"):
                position += 1
                return .object(members)
            default:
                throw failure()
            }
        }
    }

    private mutating func readArray(depth: Int) throws -> XcodeJsonValue {
        guard depth <= Self.maxDepth else { throw failure() }
        position += 1
        var elements: [XcodeJsonValue] = []
        skipWhiteSpace()
        if peek() == UInt8(ascii: "]") {
            position += 1
            return .array(elements)
        }
        while true {
            skipWhiteSpace()
            elements.append(try readValue(depth: depth))
            skipWhiteSpace()
            switch peek() {
            case UInt8(ascii: ","):
                position += 1
            case UInt8(ascii: "]"):
                position += 1
                return .array(elements)
            default:
                throw failure()
            }
        }
    }

    private mutating func readString() throws -> String {
        position += 1
        var output: [UInt8] = []
        while true {
            guard let byte = peek() else { throw failure() }
            position += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: output, as: UTF8.self)
            case UInt8(ascii: "\\"):
                try readEscape(into: &output)
            case 0x00..<0x20:
                // Un carattere di controllo non escapato non è JSON valido.
                throw failure()
            default:
                // Il testo arriva da una String Swift: i byte non ASCII formano già UTF-8 valido.
                output.append(byte)
            }
        }
    }

    private mutating func readEscape(into output: inout [UInt8]) throws {
        guard let escape = peek() else { throw failure() }
        position += 1
        switch escape {
        case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): output.append(escape)
        case UInt8(ascii: "b"): output.append(0x08)
        case UInt8(ascii: "f"): output.append(0x0C)
        case UInt8(ascii: "n"): output.append(0x0A)
        case UInt8(ascii: "r"): output.append(0x0D)
        case UInt8(ascii: "t"): output.append(0x09)
        case UInt8(ascii: "u"):
            let unit = try readHexUnit()
            let scalarValue: UInt32
            switch unit {
            case 0xD800...0xDBFF:
                guard peek() == UInt8(ascii: "\\") else { throw failure() }
                position += 1
                guard peek() == UInt8(ascii: "u") else { throw failure() }
                position += 1
                let low = try readHexUnit()
                guard (0xDC00...0xDFFF).contains(low) else { throw failure() }
                scalarValue = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
            case 0xDC00...0xDFFF:
                throw failure()
            default:
                scalarValue = unit
            }
            guard let scalar = Unicode.Scalar(scalarValue) else { throw failure() }
            output.append(contentsOf: Array(String(Character(scalar)).utf8))
        default:
            throw failure()
        }
    }

    private mutating func readHexUnit() throws -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = peek() else { throw failure() }
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw failure()
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

    /// `-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?`, restituito com'è scritto.
    private mutating func readNumber() throws -> String {
        let start = position
        if peek() == UInt8(ascii: "-") { position += 1 }
        if peek() == UInt8(ascii: "0") {
            position += 1
        } else {
            guard isDigit(peek()) else { throw failure() }
            skipDigits()
        }
        if peek() == UInt8(ascii: ".") {
            position += 1
            guard isDigit(peek()) else { throw failure() }
            skipDigits()
        }
        if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
            position += 1
            if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") { position += 1 }
            guard isDigit(peek()) else { throw failure() }
            skipDigits()
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

    // MARK: - Supporto

    private func peek() -> UInt8? {
        position < bytes.count ? bytes[position] : nil
    }

    private func isDigit(_ byte: UInt8?) -> Bool {
        guard let byte else { return false }
        return (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private mutating func skipDigits() {
        while isDigit(peek()) { position += 1 }
    }

    /// Spazi ammessi fra i token JSON: spazio, tabulazione, a capo, ritorno carrello.
    private mutating func skipWhiteSpace() {
        while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            position += 1
        }
    }

    private mutating func expect(_ literal: String) throws {
        for expected in literal.utf8 {
            guard peek() == expected else { throw failure() }
            position += 1
        }
    }

    private func failure() -> XcodeJsonSyntaxError {
        XcodeJsonSyntaxError(offset: position)
    }
}
```

- [ ] **Step 5: Implementare `XcodeJson`**

Nel C# l'identificatore del runtime si nascondeva quando il motivo di blocco conteneva «ambigua»; il porting usa un indicatore impostato dagli stessi due rami, che non dipende dal testo tradotto.

`Sources/CleanerCore/Xcode/XcodeJson.swift`:

```swift
/// Interpreta i due formati d'inventario di `simctl`, indipendenti e in sola lettura.
public enum XcodeJson {
    private struct LogicalRuntime {
        let identifier: String
        let build: String
        let name: String
        let version: String?
        let platform: String?
    }

    private struct RuntimeImage {
        let id: String
        let cliId: String?
        let runtimeIdentifier: String?
        let build: String?
        let version: String?
        let state: String?
        let backingPath: String?
        let deletable: Bool?
    }

    /// Errore di struttura con un testo proprio: l'equivalente dei `JsonException` lanciati dal C#.
    private struct StructureError: Error, CustomStringConvertible {
        let description: String
    }

    public static func parseInventory(_ simctlJson: String?, _ runtimeJson: String?, runtimeDeleteSupported: Bool) -> XcodeSnapshot {
        var candidates: [XcodeCandidate] = []
        var warnings: [XcodeInventoryWarning] = []
        var logicalRuntimes: [LogicalRuntime] = []
        var devices: [XcodeCandidate] = []
        var conflictingDeviceRuntimes = Set<[UInt8]>()
        var deviceInventorySafe = true
        var logicalRuntimeInventorySafe = true
        var runtimeInventorySafe = true

        func hasWarning(_ group: XcodeResourceKind, _ kind: XcodeInventoryWarningKind) -> Bool {
            warnings.contains { $0.resourceGroup == group && $0.kind == kind }
        }

        var simctlRoot: XcodeJsonValue?
        do {
            let document = try XcodeJsonReader.parse(simctlJson ?? "")
            guard case .object = document else {
                throw StructureError(description: String(localized: "L'inventario simulatori non è un oggetto JSON.", bundle: .module))
            }
            simctlRoot = document
        } catch {
            deviceInventorySafe = false
            logicalRuntimeInventorySafe = false
            warnings.append(.completenessFailure(.device, String(localized: "Inventario simulatori non leggibile: \(XcodeText.message(error))", bundle: .module)))
            warnings.append(.completenessFailure(.runtime, String(localized: "Inventario dei runtime logici non leggibile.", bundle: .module)))
        }

        if let root = simctlRoot {
            if case .array(let runtimeArray)? = root.property("runtimes") {
                for runtime in runtimeArray {
                    guard let identifier = runtime.string("identifier"),
                          let build = runtime.string("buildversion") ?? runtime.string("buildVersion") else {
                        logicalRuntimeInventorySafe = false
                        continue
                    }

                    logicalRuntimes.append(LogicalRuntime(
                        identifier: identifier,
                        build: build,
                        name: runtime.string("name") ?? identifier,
                        version: runtime.string("version"),
                        platform: runtime.string("platform")))
                }

                if !logicalRuntimeInventorySafe && !hasWarning(.runtime, .completenessFailure) {
                    warnings.append(.completenessFailure(.runtime, String(localized: "Metadati dei runtime logici incompleti.", bundle: .module)))
                }
            } else {
                logicalRuntimeInventorySafe = false
                warnings.append(.completenessFailure(.runtime, String(localized: "Metadati dei runtime logici mancanti o non validi.", bundle: .module)))
            }

            if case .object(let deviceGroups)? = root.property("devices") {
                for group in deviceGroups {
                    guard case .array(let groupDevices) = group.value else {
                        deviceInventorySafe = false
                        continue
                    }

                    for device in groupDevices {
                        let canonicalUuid = device.string("udid").flatMap(XcodeUuid.canonicalExact)
                        let name = device.string("name")
                        let state = device.string("state")
                        guard let canonicalUuid, let name else {
                            deviceInventorySafe = false
                            continue
                        }

                        let blockReason = deviceBlockReason(state)
                        if state == nil || (!XcodeClassifier.isRunning(state) && !XcodeClassifier.isShutdown(state) && !XcodeClassifier.isUnavailable(state)) {
                            deviceInventorySafe = false
                        }

                        let size = device.optionalInt64("dataPathSize")
                        if size.malformed && !hasWarning(.device, .advisory) {
                            warnings.append(.advisory(.device, String(localized: "La dimensione di un dispositivo non è leggibile e resta sconosciuta.", bundle: .module)))
                        }

                        devices.append(XcodeCandidate(
                            key: canonicalUuid,
                            kind: .device,
                            name: name,
                            cliId: canonicalUuid,
                            runtimeIdentifier: group.name,
                            state: state,
                            sizeBytes: size.value,
                            blockReason: blockReason))
                    }
                }
            } else {
                deviceInventorySafe = false
                warnings.append(.completenessFailure(.device, String(localized: "Elenco dispositivi mancante o non valido.", bundle: .module)))
            }
        }

        if !deviceInventorySafe && !hasWarning(.device, .completenessFailure) {
            warnings.append(.completenessFailure(.device, String(localized: "Inventario simulatori incompleto; la rimozione dei simulatori e dei runtime è disabilitata.", bundle: .module)))
        }

        // Raggruppamento per UUID senza distinzione fra maiuscole e minuscole, nell'ordine della
        // prima occorrenza, come GroupBy(…, OrdinalIgnoreCase).
        var groupOrder: [[UInt8]] = []
        var groups: [[UInt8]: [XcodeCandidate]] = [:]
        for device in devices {
            let key = XcodeText.caseInsensitiveKey(device.key)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(device)
        }

        var uniqueDevices: [XcodeCandidate] = []
        for key in groupOrder {
            guard let sameUuid = groups[key], var first = sameUuid.first else { continue }
            let conflicts = sameUuid.dropFirst().contains { other in
                !XcodeText.same(other.name, first.name)
                    || !XcodeText.same(other.runtimeIdentifier, first.runtimeIdentifier)
                    || !XcodeText.same(other.state, first.state)
                    || other.sizeBytes != first.sizeBytes
            }

            if conflicts {
                for runtimeIdentifier in sameUuid.compactMap(\.runtimeIdentifier) {
                    conflictingDeviceRuntimes.insert(XcodeText.ordinalKey(runtimeIdentifier))
                }

                first.sizeBytes = nil
                first.blockReason = String(localized: "UUID dispositivo ripetuto con metadati in conflitto; ripeti l'analisi prima di rimuoverlo.", bundle: .module)
                warnings.append(.completenessFailure(.device, String(localized: "UUID dispositivo ripetuto con metadati in conflitto: \(first.key).", bundle: .module)))
            }

            uniqueDevices.append(first)
        }

        devices = uniqueDevices

        if !deviceInventorySafe {
            devices = devices.map { device in
                var blocked = device
                blocked.blockReason = device.blockReason
                    ?? String(localized: "Inventario simulatori incompleto; ripeti l'analisi prima di rimuovere simulatori.", bundle: .module)
                return blocked
            }
        }

        candidates.append(contentsOf: devices)

        var images: [RuntimeImage] = []
        do {
            let document = try XcodeJsonReader.parse(runtimeJson ?? "")
            guard case .object(let properties) = document else {
                throw StructureError(description: String(localized: "Il JSON delle immagini runtime non è un oggetto.", bundle: .module))
            }

            for property in properties {
                let image = property.value
                let id = image.string("identifier") ?? property.name
                let runtimeIdentifier = image.string("runtimeIdentifier")
                let build = image.string("build")
                let canonicalId = XcodeUuid.canonicalExact(id)

                if canonicalId == nil || runtimeIdentifier == nil || build == nil {
                    runtimeInventorySafe = false
                }

                images.append(RuntimeImage(
                    id: canonicalId ?? id,
                    cliId: canonicalId,
                    runtimeIdentifier: runtimeIdentifier,
                    build: build,
                    version: image.string("version"),
                    state: image.string("state"),
                    backingPath: image.string("path") ?? image.string("diskImagePath"),
                    deletable: image.bool("deletable")))
            }
        } catch {
            runtimeInventorySafe = false
            warnings.append(.completenessFailure(.runtime, String(localized: "Inventario immagini runtime non leggibile: \(XcodeText.message(error))", bundle: .module)))
        }

        if !runtimeInventorySafe && !hasWarning(.runtime, .completenessFailure) {
            warnings.append(.completenessFailure(.runtime, String(localized: "Alcune immagini runtime non hanno identificatori verificabili.", bundle: .module)))
        }

        for image in images {
            var blockReason: String?
            // In C# l'identificatore del runtime veniva nascosto quando il motivo conteneva
            // "ambigua": sono esattamente i due rami che impostano questo indicatore.
            var ambiguous = false
            let exactMatches: [LogicalRuntime] = image.runtimeIdentifier == nil || image.build == nil
                ? []
                : logicalRuntimes.filter { XcodeText.same($0.identifier, image.runtimeIdentifier) && XcodeText.same($0.build, image.build) }

            if image.cliId == nil {
                blockReason = String(localized: "UUID di rimozione non disponibile.", bundle: .module)
            } else if !runtimeDeleteSupported {
                blockReason = String(localized: "Questa versione di Xcode non espone la rimozione dei runtime; gestiscili in Xcode Settings.", bundle: .module)
            } else if !runtimeInventorySafe {
                blockReason = String(localized: "Inventario immagini runtime incompleto; ripeti l'analisi.", bundle: .module)
            } else if !deviceInventorySafe {
                blockReason = String(localized: "Inventario simulatori incompleto; non è possibile verificare l'uso del runtime.", bundle: .module)
            } else if !logicalRuntimeInventorySafe {
                blockReason = String(localized: "Metadati dei runtime logici incompleti; ripeti l'analisi.", bundle: .module)
            } else if let runtimeIdentifier = image.runtimeIdentifier, conflictingDeviceRuntimes.contains(XcodeText.ordinalKey(runtimeIdentifier)) {
                blockReason = String(localized: "Dipendenza non verificabile: un UUID dispositivo ripetuto ha metadati in conflitto.", bundle: .module)
            } else if image.runtimeIdentifier == nil || image.build == nil || exactMatches.count != 1 {
                blockReason = String(localized: "Associazione tra runtime e build ambigua o non verificabile.", bundle: .module)
                ambiguous = true
            } else if image.deletable == false {
                blockReason = String(localized: "Xcode segnala che questa immagine runtime non è rimovibile.", bundle: .module)
            } else if images.filter({ XcodeText.same($0.runtimeIdentifier, image.runtimeIdentifier) && XcodeText.same($0.version, image.version) }).count > 1
                || logicalRuntimes.filter({ XcodeText.same($0.identifier, image.runtimeIdentifier) && XcodeText.same($0.version, image.version) }).count > 1 {
                blockReason = String(localized: "Associazione runtime ambigua: più immagini hanno la stessa versione e le dipendenze dei simulatori non sono distinguibili con certezza.", bundle: .module)
                ambiguous = true
                if !hasWarning(.runtime, .completenessFailure) {
                    warnings.append(.completenessFailure(.runtime, String(localized: "Associazione runtime/build ambigua: immagini con la stessa versione hanno build diverse.", bundle: .module)))
                }
            }

            let dependentDevices: [XcodeCandidate] = image.runtimeIdentifier == nil
                ? []
                : devices.filter { XcodeText.same($0.runtimeIdentifier, image.runtimeIdentifier) }
            if blockReason == nil && dependentDevices.contains(where: { XcodeClassifier.isRunning($0.state) }) {
                blockReason = String(localized: "Un dispositivo che usa questo runtime è avviato; arrestalo in Xcode prima di rimuoverlo.", bundle: .module)
            } else if blockReason == nil && dependentDevices.contains(where: { !XcodeClassifier.isShutdown($0.state) && !XcodeClassifier.isUnavailable($0.state) }) {
                blockReason = String(localized: "Lo stato di un dispositivo che usa questo runtime non è verificato.", bundle: .module)
            }

            let runtimeName: String
            if exactMatches.count == 1, let match = exactMatches.first {
                runtimeName = match.name
            } else {
                let identifier = image.runtimeIdentifier ?? String(localized: "Runtime sconosciuto", bundle: .module)
                runtimeName = XcodeText.trimmed("\(identifier) \(image.version ?? image.build ?? "")")
            }

            candidates.append(XcodeCandidate(
                key: "runtime:\(image.cliId ?? image.id)",
                kind: .runtime,
                name: runtimeName,
                path: image.backingPath,
                cliId: image.cliId,
                runtimeIdentifier: ambiguous ? nil : image.runtimeIdentifier,
                build: image.build,
                state: image.state,
                // Il sizeBytes della CLI è una stima logica dell'immagine: i byte allocati si
                // misurano a parte, sul percorso dell'immagine che la CLI riporta.
                sizeBytes: nil,
                blockReason: blockReason,
                dependencies: dependentDevices.map(\.key)))
        }

        return XcodeSnapshot(candidates: candidates, warnings: warnings)
    }

    /// Il motivo di blocco di un dispositivo appena letto: nessuno se spento.
    private static func deviceBlockReason(_ state: String?) -> String? {
        if XcodeClassifier.isShutdown(state) { return nil }
        if XcodeClassifier.isRunning(state) {
            return String(localized: "Arresta il dispositivo in Xcode prima di rimuoverlo.", bundle: .module)
        }
        guard let state else {
            return String(localized: "Stato del dispositivo non verificato; ripeti l'analisi.", bundle: .module)
        }
        return String(localized: "Stato del dispositivo non verificato: \(state); ripeti l'analisi.", bundle: .module)
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeJsonTests|XcodeJsonReaderTests"`
Expected: `Test run with 20 tests … passed` (15 di `XcodeJsonTests`, 5 di `XcodeJsonReaderTests`), nessun warning.

- [ ] **Step 7: Registro di parità e commit**

Sostituire la riga `Xcode/XcodeJsonTests.cs` con:

```markdown
| Xcode/XcodeJsonTests.cs | 15 | Xcode/XcodeJsonTests.swift | 15 | 3 | fixture copiate byte per byte in `Xcode/Fixtures/`, lette con `XcodeFixtures` (#filePath) ed escluse dal target in `Package.swift` |
```

Sezione «Test solo Swift», aggiungere:

```markdown
| Xcode/XcodeJsonReaderTests.swift | 5 | lettore JSON: ordine e ripetizioni delle proprietà, documenti rifiutati come da `JsonDocument`, interi come `TryGetInt64`, profondità 64 |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Lettura dell'inventario `simctl` | `JsonDocument` (ordine delle proprietà; con nomi ripetuti `TryGetProperty` dà l'ultimo) | `XcodeJsonReader`, stesse regole e stesso ordine; testo dell'errore di sintassi diverso | equivalente |
| Escape `\u` con surrogato isolato | `JsonDocument` accetta il documento e `GetString` lancia `InvalidOperationException`: nella sezione simulatori non era intercettata e l'analisi falliva | documento non leggibile: avviso di completezza, gruppo bloccato | accettata (lato sicuro) |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeJson with an order-preserving JSON reader

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `XcodeCli`

Solo comandi d'inventario in lettura e rimozioni mirate per UUID, sul `ProcessRunning` del piano 1. Stessi argomenti, timeout, ambiente e avvisi del C#.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeCli.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeCliTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeCli.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeCliTests.cs`; composizione in `src/MjmCleaner.App/Services/AppServices.cs` (`/usr/bin/xcrun` se esiste)

**Interfaces:**
- Consumes: `ProcessRunning`, `ProcessResult`, `ProcessLaunchError`, `FileSystem`, `PathText` (piano 1); modelli ed errori, `XcodeText`, `XcodeUuid` (Task 2); `XcodeJson.parseInventory` (Task 4); `XcodeFixtures` (Task 4, test); `Recorder`, `InMemoryFileSystem` (piano 1, test).
- Produces:
  - `public struct XcodeCli: XcodeCliInvoking` — `init(runner: any ProcessRunning, binaryPath: String?)`, `static let defaultBinaryPath = "/usr/bin/xcrun"`, `static func locateBinary(_ fileSystem: any FileSystem) -> String?`, `readInventory()`, `deleteDevice(_:)`, `deleteRuntime(_:)`
  - interno: `static func listsRuntimeDelete(_ helpText: String) -> Bool` (equivalente della regex del C#)

Note di porting:
- `RunAsync` del C# trasformava `Win32Exception`, `FileNotFoundException` e `InvalidOperationException` del runner in `XcodeUnavailableException`; il `ProcessRunner` Swift segnala un avvio fallito solo con `ProcessLaunchError`, che diventa `XcodeUnavailableError` con lo stesso testo. L'annullamento si propaga.
- `locateBinary` riproduce la scelta di `AppServices` (`File.Exists("/usr/bin/xcrun") ? "/usr/bin/xcrun" : null`), così il piano 4 non deve ripeterla.
- La regex `(?m)^\s*delete\s+\(<identifier>` diventa una scansione esplicita con gli stessi inizi di riga e lo stesso `\s` di .NET (vedi «Fatti misurati»): la `Regex` di Swift riconosce gli inizi di riga anche dopo `"\r"` e U+2028.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeCliTests.swift`:

```swift
import Darwin
import Testing
@testable import CleanerCore

struct XcodeCliTests {
    /// Porting di `FakeRunner`: registra argomenti, timeout, eseguibile e ambiente di ogni avvio.
    private struct FakeRunner: ProcessRunning {
        struct Call: Sendable {
            let executable: String
            let arguments: [String]
            let timeout: Duration
            let environment: [String: String]?
        }

        let calls = Recorder<Call>()
        let respond: @Sendable ([String]) throws -> ProcessResult

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append(Call(executable: executable, arguments: arguments, timeout: timeout, environment: environment))
            return try respond(arguments)
        }
    }

    private static func result(_ exitCode: Int32, _ standardOutput: String, _ standardError: String, timedOut: Bool = false) -> ProcessResult {
        ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError, timedOut: timedOut)
    }

    @Test func deleteUsesOnlyValidatedUuid() async throws {
        let runner = FakeRunner { _ in Self.result(0, "ok", "") }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")
        let uuid = "11111111-1111-4111-8111-111111111111"

        _ = try await cli.deleteDevice(uuid)
        _ = try await cli.deleteRuntime("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")

        let calls = runner.calls.values
        #expect(calls.map(\.arguments) == [
            ["simctl", "delete", uuid],
            ["simctl", "runtime", "delete", "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"],
        ])
        #expect(calls.allSatisfy { $0.timeout == .seconds(300) })
    }

    @Test(arguments: ["all", "unavailable", "not-a-uuid", "--unusable"])
    func invalidDeleteIdentifiersNeverLaunchAProcess(id: String) async {
        let runner = FakeRunner { _ in Self.result(0, "", "") }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")

        await #expect(throws: XcodeArgumentError.self) { try await cli.deleteRuntime(id) }
        await #expect(throws: XcodeArgumentError.self) { try await cli.deleteDevice(id) }

        #expect(runner.calls.values.isEmpty)
    }

    @Test func runtimeDeleteUnsupportedIsReported() async throws {
        let runner = FakeRunner { arguments in
            arguments == ["simctl", "runtime"] ? Self.result(1, "", "unknown operation") : Self.result(0, "{}", "")
        }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")

        let snapshot = try await cli.readInventory()

        #expect(snapshot.warnings.contains { $0.resourceGroup == .runtime && XcodeText.containsIgnoringCase($0.message, "Settings") })
        #expect(snapshot.candidates.isEmpty)
    }

    @Test func inventoryCommandsUseThirtySecondTimeoutAndSeparateArguments() async throws {
        let runner = FakeRunner { _ in Self.result(0, "{}", "") }
        let cli = XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun")

        _ = try await cli.readInventory()

        let calls = runner.calls.values
        #expect(calls.contains { $0.arguments == ["simctl", "list", "--json"] })
        #expect(calls.contains { $0.arguments == ["simctl", "runtime", "list", "--json"] })
        #expect(calls.allSatisfy { $0.timeout == .seconds(30) })
    }

    @Test func runtimeInventoryIsStillReadWhenSimulatorInventoryCommandFails() async throws {
        let runner = FakeRunner { arguments in
            if arguments == ["simctl", "list", "--json"] { return Self.result(1, "", "simulator service unavailable") }
            if arguments == ["simctl", "runtime"] { return Self.result(0, "delete (<identifier>)", "") }
            return Self.result(0, "{}", "")
        }

        let snapshot = try await XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun").readInventory()

        #expect(snapshot.warnings.contains { $0.resourceGroup == .device })
        #expect(runner.calls.values.contains { $0.arguments == ["simctl", "runtime", "list", "--json"] })
    }

    @Test func runtimeDeleteIsSupportedWhenHelpPrintsSyntaxWithUsageExitCode() async throws {
        let simctlJson = try XcodeFixtures.text("simctl-list.json")
        let runtimeJson = try XcodeFixtures.text("runtime-list.json")
        let runner = FakeRunner { arguments in
            if arguments == ["simctl", "list", "--json"] { return Self.result(0, simctlJson, "") }
            if arguments == ["simctl", "runtime"] { return Self.result(117, "", "delete (<identifier>|--unusable)") }
            return Self.result(0, runtimeJson, "")
        }

        let snapshot = try await XcodeCli(runner: runner, binaryPath: "/usr/bin/xcrun").readInventory()

        let runtimes = snapshot.candidates.filter { $0.kind == .runtime }
        #expect(runtimes.count == 1)
        #expect(runtimes.first?.canSelect == true)
    }

    // Solo Swift: la scansione che sostituisce la regex `(?m)^\s*delete\s+\(<identifier>` dà gli
    // stessi esiti misurati su .NET 10.
    @Test(arguments: [
        ("delete (<identifier>)", true),
        ("  delete  (<identifier>|--unusable)", true),
        ("x\n delete\n(<identifier>", true),
        ("x\r delete (<identifier>", false),
        ("xdelete (<identifier>", false),
        ("\u{2028}delete (<identifier>", true),
        ("\u{A0}delete\u{A0}(<identifier>", true),
        ("\u{85}delete (<identifier>", true),
        ("Delete (<identifier>", false),
        ("delete(<identifier>", false),
    ])
    func runtimeDeleteSyntaxIsRecognizedLikeTheDotNetRegex(helpText: String, expected: Bool) {
        #expect(XcodeCli.listsRuntimeDelete(helpText) == expected)
    }

    // Solo Swift: xcrun si avvia per percorso assoluto, con la sua cartella in testa al PATH.
    @Test func commandsRunXcrunByAbsolutePathWithItsDirectoryFirstInPath() async throws {
        let runner = FakeRunner { _ in Self.result(0, "{}", "") }

        _ = try await XcodeCli(runner: runner, binaryPath: XcodeCli.defaultBinaryPath).readInventory()

        let calls = runner.calls.values
        #expect(calls.count == 3)
        #expect(calls.allSatisfy { $0.executable == "/usr/bin/xcrun" })
        #expect(calls.allSatisfy {
            XcodeText.hasOrdinalPrefix($0.environment?["PATH"] ?? "", "/usr/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin")
        })
    }

    // Solo Swift: xcrun assente o non avviabile produce gli avvisi di oggi (spec §8.1) e nessun
    // candidato; l'eseguibile si cerca solo in /usr/bin/xcrun, come nella composizione C#.
    @Test func missingOrUnlaunchableXcrunIsReportedAsUnavailable() async throws {
        let unlaunchable = FakeRunner { _ in throw ProcessLaunchError(executable: "/usr/bin/xcrun", code: ENOENT) }
        let fs = InMemoryFileSystem()

        let missing = try await XcodeCli(runner: unlaunchable, binaryPath: XcodeCli.locateBinary(fs)).readInventory()
        let broken = try await XcodeCli(runner: unlaunchable, binaryPath: "/usr/bin/xcrun").readInventory()

        for snapshot in [missing, broken] {
            #expect(snapshot.candidates.isEmpty)
            #expect(snapshot.warnings.filter { $0.message == "Xcode command line tools non trovati." }.count == 3)
        }
        fs.addFile("/usr/bin/xcrun", size: 1)
        #expect(XcodeCli.locateBinary(fs) == "/usr/bin/xcrun")
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeCliTests`
Expected: errore di compilazione `cannot find 'XcodeCli' in scope`.

- [ ] **Step 3: Implementare `XcodeCli`**

`Sources/CleanerCore/Xcode/XcodeCli.swift`:

```swift
import Foundation

/// Esegue solo i comandi d'inventario di `simctl` in lettura e le rimozioni mirate per UUID.
public struct XcodeCli: XcodeCliInvoking {
    private static let inventoryTimeout: Duration = .seconds(30)
    private static let deleteTimeout: Duration = .seconds(5 * 60)

    /// Il percorso che l'app C# usava se esiste. Va passato assoluto: `posix_spawnp` cercherebbe
    /// un nome semplice nel PATH dell'app, che lanciata dal Finder è solo /usr/bin:/bin:/usr/sbin:/sbin.
    public static let defaultBinaryPath = "/usr/bin/xcrun"

    private let runner: any ProcessRunning
    private let binaryPath: String?

    public init(runner: any ProcessRunning, binaryPath: String?) {
        self.runner = runner
        self.binaryPath = binaryPath
    }

    /// Come la composizione C#: `xcrun` solo se `/usr/bin/xcrun` esiste, altrimenti nessuno.
    public static func locateBinary(_ fileSystem: any FileSystem) -> String? {
        fileSystem.fileExists(defaultBinaryPath) ? defaultBinaryPath : nil
    }

    @concurrent
    public func readInventory() async throws -> XcodeSnapshot {
        var simctlJson: String?
        var runtimeJson: String?
        var runtimeDeleteSupported = false
        var warnings: [XcodeInventoryWarning] = []

        do {
            let simctl = try await run(["simctl", "list", "--json"], timeout: Self.inventoryTimeout)
            if simctl.timedOut || simctl.exitCode != 0 {
                warnings.append(.completenessFailure(.device, String(localized: "Inventario simulatori non disponibile: \(Self.describe(simctl))", bundle: .module)))
            } else {
                simctlJson = simctl.standardOutput
            }
        } catch let error as XcodeUnavailableError {
            warnings.append(.completenessFailure(.device, error.description))
        }

        do {
            let help = try await run(["simctl", "runtime"], timeout: Self.inventoryTimeout)
            runtimeDeleteSupported = !help.timedOut && Self.listsRuntimeDelete("\(help.standardOutput)\n\(help.standardError)")
        } catch let error as XcodeUnavailableError {
            warnings.append(.completenessFailure(.runtime, error.description))
        }

        do {
            let runtime = try await run(["simctl", "runtime", "list", "--json"], timeout: Self.inventoryTimeout)
            if runtime.timedOut || runtime.exitCode != 0 {
                warnings.append(.completenessFailure(.runtime, String(localized: "Inventario immagini runtime non disponibile: \(Self.describe(runtime))", bundle: .module)))
            } else {
                runtimeJson = runtime.standardOutput
            }

            if !runtimeDeleteSupported {
                warnings.append(.advisory(.runtime, String(localized: "Questa versione di Xcode non supporta la rimozione dei runtime dalla CLI; gestiscili in Xcode Settings.", bundle: .module)))
            }
        } catch let error as XcodeUnavailableError {
            warnings.append(.completenessFailure(.runtime, error.description))
        }

        let parsed = XcodeJson.parseInventory(simctlJson, runtimeJson, runtimeDeleteSupported: runtimeDeleteSupported)
        return XcodeSnapshot(candidates: parsed.candidates, warnings: warnings + parsed.warnings)
    }

    public func deleteDevice(_ uuid: String) async throws -> ProcessResult {
        try Self.validateUuid(uuid)
        return try await run(["simctl", "delete", uuid], timeout: Self.deleteTimeout)
    }

    public func deleteRuntime(_ uuid: String) async throws -> ProcessResult {
        try Self.validateUuid(uuid)
        return try await run(["simctl", "runtime", "delete", uuid], timeout: Self.deleteTimeout)
    }

    private func run(_ arguments: [String], timeout: Duration) async throws -> ProcessResult {
        guard let binaryPath else {
            throw XcodeUnavailableError(String(localized: "Xcode command line tools non trovati.", bundle: .module))
        }

        do {
            return try await runner.run(binaryPath, arguments, timeout: timeout, environment: Self.environment(binaryPath))
        } catch is ProcessLaunchError {
            throw XcodeUnavailableError(String(localized: "Xcode command line tools non trovati.", bundle: .module))
        }
    }

    /// La cartella di `xcrun` e i percorsi abituali davanti al PATH ereditato, come in C#.
    private static func environment(_ binary: String) -> [String: String] {
        let directory = PathText.parent(binary) ?? "/usr/bin"
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var path = Array("\(directory):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:\(inherited)".utf8)
        while path.last == UInt8(ascii: ":") { path.removeLast() }
        return ["PATH": String(decoding: path, as: UTF8.self)]
    }

    /// `Guid.TryParseExact(uuid, "D")`: un alias di simctl ("all", "booted", "unavailable") o
    /// un'opzione ("--unusable") non arrivano mai alla riga di comando.
    private static func validateUuid(_ uuid: String) throws {
        guard XcodeUuid.canonicalExact(uuid) != nil else {
            throw XcodeArgumentError(String(localized: "È richiesto un UUID esplicito; gli alias simctl non sono consentiti.", bundle: .module))
        }
    }

    private static func describe(_ result: ProcessResult) -> String {
        if result.timedOut {
            return String(localized: "timeout dopo 30 secondi", bundle: .module)
        }
        return XcodeText.lines(result.standardError).first
            ?? String(localized: "codice di uscita \(result.exitCode)", bundle: .module)
    }

    /// Equivalente della regex `(?m)^\s*delete\s+\(<identifier>` del C#: da un inizio di riga
    /// (inizio del testo o dopo "\n", mai dopo "\r"), spazi facoltativi — anche a capo, come `\s` —
    /// poi "delete", almeno uno spazio e "(<identifier>".
    static func listsRuntimeDelete(_ helpText: String) -> Bool {
        let scalars = Array(helpText.unicodeScalars)
        let keyword = Array("delete".unicodeScalars)
        let argument = Array("(<identifier>".unicodeScalars)

        func matches(_ expected: [Unicode.Scalar], at offset: Int) -> Bool {
            offset + expected.count <= scalars.count && scalars[offset..<(offset + expected.count)].elementsEqual(expected)
        }

        func skipWhiteSpace(from offset: Int) -> Int {
            var position = offset
            while position < scalars.count, XcodeText.isWhiteSpace(scalars[position]) { position += 1 }
            return position
        }

        var lineStart = 0
        while lineStart <= scalars.count {
            let keywordStart = skipWhiteSpace(from: lineStart)
            if matches(keyword, at: keywordStart) {
                let afterKeyword = keywordStart + keyword.count
                let argumentStart = skipWhiteSpace(from: afterKeyword)
                if argumentStart > afterKeyword && matches(argument, at: argumentStart) { return true }
            }
            guard let newline = scalars[lineStart...].firstIndex(of: "\n") else { return false }
            lineStart = newline + 1
        }
        return false
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeCliTests`
Expected: `Test run with 9 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Xcode/XcodeCliTests.cs` con:

```markdown
| Xcode/XcodeCliTests.cs | 6 (4) | Xcode/XcodeCliTests.swift | 9 (4) | 3 | 6 portati + 3 solo-Swift: `runtimeDeleteSyntaxIsRecognizedLikeTheDotNetRegex` (casi misurati su .NET), `commandsRunXcrunByAbsolutePathWithItsDirectoryFirstInPath`, `missingOrUnlaunchableXcrunIsReportedAsUnavailable` (spec §8.1) |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Supporto della rimozione dei runtime | `Regex` `(?m)^\s*delete\s+\(<identifier>` | scansione equivalente (inizi di riga solo dopo "\n", `\s` di .NET), stessi esiti sui casi misurati | identica |
| Avvio fallito di `xcrun` | `Win32Exception`/`FileNotFoundException`/`InvalidOperationException` → `XcodeUnavailableException` | `ProcessLaunchError` → `XcodeUnavailableError`, stesso testo | identica |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeCli on the process runner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `XcodeSizeProbe` e `XcodeRunningProbe`

Le due sonde in sola lettura: dimensione allocata con `du` e spazio libero del volume della home; stato di Xcode dai percorsi dei processi. In C# i test della sonda di esecuzione stanno in `XcodeCleanupServiceTests.cs`: il file Swift omonimo nasce qui con quei test e riceve il terzo al Task 10.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeSizeProbe.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeRunningProbe.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeSizeProbeTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeCleanupServiceTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeSizeProbe.cs`, `XcodeRunningProbe.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeSizeProbeTests.cs`, `XcodeCleanupServiceTests.cs`

**Interfaces:**
- Consumes: `FileSystem.availableFreeSpace(forVolumeContaining:)` (Task 1); `ProcessRunning`, `ProcessResult`, `ProcessLaunchError`, `LinkInspecting`, `FileSystemLinkInspector`, `LocalFileSystem` (piano 1); errori e `XcodeText` (Task 2); `TemporaryDirectory`, `Recorder`, `InMemoryFileSystem`, `FakeLinkInspector` (piano 1, test).
- Produces:
  - `public protocol XcodeSizeProbing: Sendable` — `measure(_ path: String) async throws -> Int64?`, `freeBytes() async throws -> Int64?`
  - `public struct XcodeSizeProbe: XcodeSizeProbing` — `init(fileSystem: any FileSystem, runner: any ProcessRunning, links: any LinkInspecting, homeDirectory: String)`
  - `public enum XcodeRunningState: Sendable, Equatable { case unknown, notRunning, running }`
  - `public protocol XcodeRunningProbing: Sendable` — `state() async throws -> XcodeRunningState` (lancia solo `CancellationError`)
  - `public struct XcodeRunningProbe: XcodeRunningProbing` — `init(runner: any ProcessRunning)`

Note di porting:
- `MeasureAsync` intercettava `IOException`, `UnauthorizedAccessException`, `InvalidOperationException`, `ArgumentException` e `Win32Exception` e lasciava passare il resto: in Swift diventano `FileSystemError`, `XcodeOperationError`, `XcodeArgumentError` e `ProcessLaunchError`; l'annullamento e gli errori fuori contratto risalgono. Il test `AccessDeniedSizeIsUnknown` lancia quindi `FileSystemError(code: EACCES, …)` al posto di `UnauthorizedAccessException`.
- `freeBytes` legge `availableFreeSpace(forVolumeContaining: home)`; qualunque `FileSystemError` dà «sconosciuto», come le eccezioni intercettate in C#.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeSizeProbeTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

struct XcodeSizeProbeTests {
    private struct ThrowingRunner: ProcessRunning {
        let error: any Error

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            throw error
        }
    }

    private struct ReturningRunner: ProcessRunning {
        let result: ProcessResult
        let calls = Recorder<[String]>()

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append([executable] + arguments)
            return result
        }
    }

    private static func result(_ exitCode: Int32, _ standardOutput: String, _ standardError: String) -> ProcessResult {
        ProcessResult(exitCode: exitCode, standardOutput: standardOutput, standardError: standardError, timedOut: false)
    }

    @Test func accessDeniedSizeIsUnknown() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let directory = try tmp.directory("cache")
        let probe = XcodeSizeProbe(
            fileSystem: LocalFileSystem(), runner: ThrowingRunner(error: FileSystemError(code: EACCES, path: "du")),
            links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure(directory) == nil)
    }

    @Test func partialDuMeasurementIsUnknown() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let probe = XcodeSizeProbe(
            fileSystem: LocalFileSystem(), runner: ReturningRunner(result: Self.result(1, "12\tcache", "permission denied")),
            links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure(tmp.path) == nil)
    }

    @Test func freeBytesComeFromTheVolumeContainingHome() async throws {
        let probe = XcodeSizeProbe(
            fileSystem: LocalFileSystem(), runner: ReturningRunner(result: Self.result(0, "1\tunused", "")),
            links: FileSystemLinkInspector(), homeDirectory: NSHomeDirectory())

        let free = try await probe.freeBytes()

        #expect(free != nil)
        #expect((free ?? -1) >= 0)
    }

    // Solo Swift: le regole di lettura dell'output di du (una sola riga, solo cifre ASCII nel
    // primo campo, nessun errore) e il comando esatto.
    @Test(arguments: [
        (Self.result(0, "12\t/x\n", ""), 12_288 as Int64?),
        (Self.result(0, "  7 /x", ""), 7_168 as Int64?),
        (Self.result(0, "12\t/x\n3\t/y", ""), nil),
        (Self.result(0, "+12\t/x", ""), nil),
        (Self.result(0, "\u{0661}\t/x", ""), nil),
        (Self.result(0, "9007199254740992\t/x", ""), nil),
        (Self.result(0, "12\t/x", "du: x: Permission denied"), nil),
        (Self.result(1, "12\t/x", ""), nil),
        (ProcessResult(exitCode: 0, standardOutput: "12\t/x", standardError: "", timedOut: true), nil),
    ])
    func measureParsesOnlyASingleCleanDuRow(output: ProcessResult, expected: Int64?) async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let runner = ReturningRunner(result: output)
        let probe = XcodeSizeProbe(fileSystem: LocalFileSystem(), runner: runner, links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure(tmp.path) == expected)
        #expect(runner.calls.values == [["du", "-k", "-s", "-P", tmp.path]])
    }

    // Solo Swift: percorsi relativi, collegamenti e percorsi assenti non avviano du.
    @Test func measureRefusesLinksRelativeAndMissingPathsWithoutLaunchingDu() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let target = try tmp.directory("target")
        let link = try tmp.symlink("link", to: target)
        let runner = ReturningRunner(result: Self.result(0, "1\t/x", ""))
        let probe = XcodeSizeProbe(fileSystem: LocalFileSystem(), runner: runner, links: FileSystemLinkInspector(), homeDirectory: tmp.path)

        #expect(try await probe.measure("relativo/cartella") == nil)
        #expect(try await probe.measure(link) == nil)
        #expect(try await probe.measure(tmp.path + "/assente") == nil)
        #expect(runner.calls.values.isEmpty)
    }

    // Solo Swift: un volume illeggibile dà spazio sconosciuto, non un errore.
    @Test func freeBytesAreUnknownWhenTheVolumeCannotBeRead() async throws {
        let probe = XcodeSizeProbe(
            fileSystem: InMemoryFileSystem(), runner: ReturningRunner(result: Self.result(0, "", "")),
            links: FakeLinkInspector(), homeDirectory: "/Users/tester")

        #expect(try await probe.freeBytes() == nil)
    }
}
```

`Tests/CleanerCoreTests/Xcode/XcodeCleanupServiceTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct XcodeCleanupServiceTests {
    private struct ProcessListingRunner: ProcessRunning {
        let outcome: Result<ProcessResult, any Error>

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            try outcome.get()
        }
    }

    @Test(arguments: [
        ("/Applications/Xcode.app/Contents/MacOS/Xcode", XcodeRunningState.running),
        ("/Applications/Xcode-beta.app/Contents/MacOS/Xcode-beta", .running),
        ("/usr/bin/simctl", .notRunning),
    ])
    func runningProbeClassifiesProcessListing(processPath: String, expected: XcodeRunningState) async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(
            outcome: .success(ProcessResult(exitCode: 0, standardOutput: processPath, standardError: "", timedOut: false))))

        #expect(try await probe.state() == expected)
    }

    @Test func runningProbeReturnsUnknownWhenListingFails() async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(
            outcome: .success(ProcessResult(exitCode: 1, standardOutput: "", standardError: "denied", timedOut: false))))

        #expect(try await probe.state() == .unknown)
    }

    // Solo Swift: timeout, avvio fallito e stderr non vuoto non vengono mai scambiati per
    // «Xcode chiuso», anche quando lo stdout elenca processi qualunque.
    @Test(arguments: [
        Result<ProcessResult, any Error>.success(ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)),
        .success(ProcessResult(exitCode: 0, standardOutput: "/usr/bin/simctl", standardError: "ps: warning", timedOut: false)),
        .failure(ProcessLaunchError(executable: "ps", code: 2)),
    ])
    func runningProbeIsUnknownWhenTheListingIsNotReliable(outcome: Result<ProcessResult, any Error>) async throws {
        let probe = XcodeRunningProbe(runner: ProcessListingRunner(outcome: outcome))

        #expect(try await probe.state() == .unknown)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeSizeProbeTests|XcodeCleanupServiceTests"`
Expected: errore di compilazione `cannot find 'XcodeRunningProbe' in scope` o `cannot find 'XcodeSizeProbe' in scope`, secondo il file che il compilatore esamina per primo.

- [ ] **Step 3: Implementare `XcodeSizeProbe`**

`Sources/CleanerCore/Xcode/XcodeSizeProbe.swift`:

```swift
/// `IXcodeSizeProbe`: stime in sola lettura, `nil` quando la misura non è affidabile.
public protocol XcodeSizeProbing: Sendable {
    /// Byte allocati sotto `path`, o `nil`. Lancia solo `CancellationError` e gli errori fuori
    /// contratto del runner (in C# le eccezioni non elencate nel filtro).
    func measure(_ path: String) async throws -> Int64?
    /// Spazio libero del volume della home, o `nil`. Lancia solo `CancellationError`.
    func freeBytes() async throws -> Int64?
}

/// Dimensione allocata (via `du`) e spazio libero del volume che contiene la home.
public struct XcodeSizeProbe: XcodeSizeProbing {
    private static let measureTimeout: Duration = .seconds(30)

    private let fileSystem: any FileSystem
    private let runner: any ProcessRunning
    private let links: any LinkInspecting
    private let homeDirectory: String

    public init(fileSystem: any FileSystem, runner: any ProcessRunning, links: any LinkInspecting, homeDirectory: String) {
        self.fileSystem = fileSystem
        self.runner = runner
        self.links = links
        self.homeDirectory = homeDirectory
    }

    @concurrent
    public func measure(_ path: String) async throws -> Int64? {
        guard path.utf8.first == UInt8(ascii: "/"), !links.isSymbolicLink(path),
              fileSystem.fileExists(path) || fileSystem.directoryExists(path) else {
            return nil
        }

        let result: ProcessResult
        do {
            // Il du di BSD non segue i collegamenti simbolici per default; -P lo rende esplicito.
            // Un'uscita non nulla, un timeout o un output parziale non sono una stima utilizzabile.
            result = try await runner.run("du", ["-k", "-s", "-P", path], timeout: Self.measureTimeout)
        } catch is FileSystemError, is ProcessLaunchError, is XcodeArgumentError, is XcodeOperationError {
            // Gli errori che il C# filtrava (IOException, UnauthorizedAccessException,
            // Win32Exception, ArgumentException, InvalidOperationException): misura sconosciuta.
            return nil
        }

        guard result.exitCode == 0, !result.timedOut, XcodeText.isNullOrWhiteSpace(result.standardError) else { return nil }

        let rows = XcodeText.lines(result.standardOutput)
        guard rows.count == 1, let row = rows.first else { return nil }

        // Il primo campo, fino al primo tab o spazio; solo cifre ASCII (NumberStyles.None).
        let first = String(String.UnicodeScalarView(row.unicodeScalars.prefix { $0 != "\t" && $0 != " " }))
        guard !first.isEmpty, first.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let kilobytes = Int64(first), kilobytes <= Int64.max / 1024 else {
            return nil
        }
        return kilobytes * 1024
    }

    @concurrent
    public func freeBytes() async throws -> Int64? {
        try Task.checkCancellation()
        do {
            return try fileSystem.availableFreeSpace(forVolumeContaining: homeDirectory)
        } catch {
            return nil
        }
    }
}
```

- [ ] **Step 4: Implementare `XcodeRunningProbe`**

`Sources/CleanerCore/Xcode/XcodeRunningProbe.swift`:

```swift
public enum XcodeRunningState: Sendable, Equatable {
    case unknown
    case notRunning
    case running
}

/// `IXcodeRunningProbe`.
public protocol XcodeRunningProbing: Sendable {
    /// Lancia solo `CancellationError`.
    func state() async throws -> XcodeRunningState
}

/// Legge direttamente i percorsi dei processi: un elenco non disponibile non deve mai essere
/// scambiato per «Xcode chiuso».
public struct XcodeRunningProbe: XcodeRunningProbing {
    private static let timeout: Duration = .seconds(5)
    private static let bundleMarkers = ["/Xcode.app/Contents/MacOS/", "/Xcode-beta.app/Contents/MacOS/"]

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func state() async throws -> XcodeRunningState {
        do {
            let result = try await runner.run("ps", ["-axo", "comm="], timeout: Self.timeout)
            guard !result.timedOut, result.exitCode == 0, XcodeText.isNullOrWhiteSpace(result.standardError) else {
                return .unknown
            }

            // Equivalente della regex `/(?:Xcode|Xcode-beta)\.app/Contents/MacOS/` con IgnoreCase.
            let running = XcodeText.lines(result.standardOutput).contains { path in
                Self.bundleMarkers.contains { XcodeText.containsIgnoringCase(path, $0) }
            }
            return running ? .running : .notRunning
        } catch is CancellationError where Task.isCancelled {
            throw CancellationError()
        } catch {
            return .unknown
        }
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "XcodeSizeProbeTests|XcodeCleanupServiceTests"`
Expected: `Test run with 9 tests … passed` (6 di `XcodeSizeProbeTests`, 3 di `XcodeCleanupServiceTests`), nessun warning.

- [ ] **Step 6: Registro di parità e commit**

Sostituire le righe `Xcode/XcodeSizeProbeTests.cs` e `Xcode/XcodeCleanupServiceTests.cs` con:

```markdown
| Xcode/XcodeCleanupServiceTests.cs | 3 (3) | Xcode/XcodeCleanupServiceTests.swift | 2 di 3 (3) | 3 | il terzo (`analyzeBlocksFilesWhenXcodeStateCannotBeVerified`) arriva con `XcodeCleanupService` al Task 10; + 1 solo-Swift `runningProbeIsUnknownWhenTheListingIsNotReliable` |
| Xcode/XcodeSizeProbeTests.cs | 3 | Xcode/XcodeSizeProbeTests.swift | 6 | 3 | 3 portati + 3 solo-Swift (`measureParsesOnlyASingleCleanDuRow`, `measureRefusesLinksRelativeAndMissingPathsWithoutLaunchingDu`, `freeBytesAreUnknownWhenTheVolumeCannotBeRead`); `UnauthorizedAccessException` del runner → `FileSystemError(EACCES)` |
```

Tabella «Candidati a miglioramento», aggiungere:

```markdown
| `ps` e `du` avviati per nome | risolti nel PATH dell'app, come in C# (il PATH minimo del Finder li contiene) | percorsi assoluti `/bin/ps` e `/usr/bin/du` |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port Xcode size and running probes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: `XcodeFileScanner`

Scansiona solo DerivedData e i Device Support delle quattro piattaforme, con il `RuleScanner` e il `PathGuard` del piano 1, e misura le immagini runtime dichiarate dalla CLI. Archives e UserData non sono mai candidati.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeFileScanner.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeFileScannerTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeFileScanner.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeFileScannerTests.cs`

**Interfaces:**
- Consumes: `FileSystem`, `FileSystemError`, `FileItemInfo.creation` (Task 1); `RuleScanner`, `CleanupRule`, `ScanItem`, `PathGuarding`, `PathGuard`, `DenyList`, `LinkInspecting`, `PathText`, `SystemWallClock` (piano 1); modelli e `XcodeText` (Task 2); `XcodeSizeProbing` (Task 6); `InMemoryFileSystem`, `ForwardingFileSystem`, `UnreadableDirectoryFileSystem`, `FakeLinkInspector`, `Recorder` (piano 1, test).
- Produces:
  - `public protocol XcodeFileScanning: Sendable` — `scan() async throws -> XcodeSnapshot`, `measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot`
  - `public struct XcodeFileScanner: XcodeFileScanning` — `init(fileSystem: any FileSystem, ruleScanner: RuleScanner, pathGuard: any PathGuarding, links: any LinkInspecting, sizeProbe: any XcodeSizeProbing, homeDirectory: String)`

Note di porting:
- Una root che `directoryExists` non vede si elenca per distinguere l'assenza dall'accesso negato. Gli errori .NET misurati diventano errno: ENOENT e ENOTDIR (`DirectoryNotFoundException`) → assente, nessun avviso; EACCES, EPERM, EBADF (`UnauthorizedAccessException`) → «Root Xcode non accessibile»; ogni altro errno (`IOException`) → «Impossibile verificare la root Xcode».
- Le date dell'identità vengono da un solo `itemInfo` (`creation` e `lastWrite`). Su una cartella scomparsa fra il controllo e questa lettura .NET restituiva la sentinella 1601 e la riga proseguiva; in Swift `itemInfo` lancia e la cartella si salta con l'avviso «metadati non leggibili» (solo in una corsa, lato sicuro).
- `InaccessibleRootFileSystem` del C# usava `DispatchProxy`; qui deriva da `ForwardingFileSystem` come gli altri decoratori di guasto.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeFileScannerTests.swift`:

```swift
import Darwin
import Testing
@testable import CleanerCore

struct XcodeFileScannerTests {
    private static let home = "/Users/tester"
    private static let xcode = home + "/Library/Developer/Xcode"

    /// Porting di `FakeSizeProbe`: dimensioni prestabilite per percorso, registro delle misure.
    private struct FakeSizeProbe: XcodeSizeProbing {
        let values: [String: Int64?]
        let measuredPaths = Recorder<String>()

        init(_ values: (String, Int64?)...) {
            var map: [String: Int64?] = [:]
            for (path, bytes) in values { map[path] = .some(bytes) }
            self.values = map
        }

        func measure(_ path: String) async throws -> Int64? {
            measuredPaths.append(path)
            return values[path] ?? nil
        }

        func freeBytes() async throws -> Int64? { 1234 }
    }

    /// Porting di `InaccessibleRootFileSystem`: la root risulta assente a `directoryExists` ed
    /// elencarla lancia accesso negato, come una cartella senza permesso di lettura.
    private final class InaccessibleRootFileSystem: ForwardingFileSystem, @unchecked Sendable {
        private let path: String

        init(_ inner: any FileSystem, path: String) {
            self.path = path
            super.init(inner)
        }

        override func directoryExists(_ path: String) -> Bool {
            path == self.path ? false : super.directoryExists(path)
        }

        override func contentsOfDirectory(_ path: String) throws -> [String] {
            if path == self.path { throw FileSystemError(code: EACCES, path: path) }
            return try super.contentsOfDirectory(path)
        }
    }

    private func create(_ fs: any FileSystem, _ sizes: FakeSizeProbe, links: FakeLinkInspector = FakeLinkInspector()) throws -> XcodeFileScanner {
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home)
        let rules = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock())
        return XcodeFileScanner(fileSystem: fs, ruleScanner: rules, pathGuard: pathGuard, links: links, sizeProbe: sizes, homeDirectory: Self.home)
    }

    @Test func derivedDataIsGroupedByProjectFolder() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/DerivedData/App-abc/Build/Products/app", size: 17)
        fs.addFile(Self.xcode + "/DerivedData/Tool-xyz/Index.noindex/store", size: 29)
        fs.addFile(Self.xcode + "/DerivedData/loose-file", text: "ignore")
        let sizes = FakeSizeProbe((Self.xcode + "/DerivedData/App-abc", 100), (Self.xcode + "/DerivedData/Tool-xyz", 200))

        let snapshot = try await create(fs, sizes).scan()

        let candidates = snapshot.candidates.filter { $0.kind == .derivedData }.sorted { $0.name < $1.name }
        #expect(candidates.map(\.name) == ["App-abc", "Tool-xyz"])
        #expect(candidates.map(\.sizeBytes) == [100, 200])
        #expect(snapshot.fileInventory.count == 2)
        for entry in snapshot.fileInventory.values {
            #expect(entry.item.isDirectory)
            #expect(entry.item.path == entry.identity.canonicalPath)
            #expect(entry.identity.creationTime != nil)
            #expect(entry.identity.lastWriteTime != nil)
        }
    }

    @Test func archivesAndUserDataAreNeverCandidates() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/Archives/release.xcarchive/Products/app", size: 50)
        fs.addFile(Self.xcode + "/UserData/Provisioning Profiles/profile", size: 50)

        let snapshot = try await create(fs, FakeSizeProbe()).scan()

        #expect(snapshot.candidates.isEmpty)
        #expect(!snapshot.fileInventory.values.contains { $0.item.path.contains("Archives") })
        #expect(!snapshot.fileInventory.values.contains { $0.item.path.contains("UserData") })
    }

    @Test func absentSupportFolderIsEmpty() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/DerivedData/App/Build/file", size: 1)

        let snapshot = try await create(fs, FakeSizeProbe()).scan()

        #expect(!snapshot.warnings.contains { $0.resourceGroup == .deviceSupport })
        #expect(!snapshot.candidates.contains { $0.kind == .deviceSupport })
    }

    @Test func linkedRootIsRejected() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.xcode + "/DerivedData/App/Build/file", size: 1)

        let snapshot = try await create(fs, FakeSizeProbe(), links: FakeLinkInspector(Self.xcode + "/DerivedData")).scan()

        #expect(!snapshot.candidates.contains { $0.kind == .derivedData })
        #expect(snapshot.warnings.contains { $0.resourceGroup == .derivedData })
    }

    @Test func partialLogicalTraversalBlocksAffectedCandidateAndMarksLogicalSizeUnknown() async throws {
        let mock = InMemoryFileSystem()
        let app = Self.xcode + "/DerivedData/App-abc"
        let unreadable = app + "/Build"
        mock.addFile(unreadable + "/Products/app", size: 17)

        let snapshot = try await create(UnreadableDirectoryFileSystem(mock, unreadablePath: unreadable), FakeSizeProbe((app, 100))).scan()

        let candidates = snapshot.candidates.filter { $0.kind == .derivedData }
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(!candidate.canSelect)
        #expect(snapshot.fileInventory[candidate.key]?.identity.logicalSizeBytes == nil)
    }

    @Test func rootHiddenByAccessDeniedExistsCheckProducesWarning() async throws {
        let mock = InMemoryFileSystem()
        mock.addFile(Self.xcode + "/DerivedData/App-abc/Build/app", size: 1)
        let fs = InaccessibleRootFileSystem(mock, path: Self.xcode + "/DerivedData")

        let snapshot = try await create(fs, FakeSizeProbe()).scan()

        #expect(snapshot.warnings.contains { $0.resourceGroup == .derivedData })
    }

    @Test func sharedBackingImageCountedOnce() async throws {
        let backing = Self.home + "/Library/Developer/CoreSimulator/Images/shared.dmg"
        let original = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: backing),
            XcodeCandidate(key: "runtime:22222222-2222-4222-8222-222222222222", kind: .runtime, name: "iOS 18 duplicate", path: backing),
        ], warnings: [])
        let fs = InMemoryFileSystem()
        fs.addFile(backing, size: 1)
        let sizes = FakeSizeProbe((backing, 4096))

        let measured = try await create(fs, sizes).measureRuntimeBackingImages(original)

        #expect(measured.candidates.first { XcodeText.hasOrdinalPrefix($0.key, "runtime:111") }?.sizeBytes == 4096)
        #expect(measured.candidates.first { XcodeText.hasOrdinalPrefix($0.key, "runtime:222") }?.sizeBytes == nil)
        #expect(measured.warnings.contains { $0.resourceGroup == .runtime && XcodeText.containsIgnoringCase($0.message, "condivis") })
        #expect(sizes.measuredPaths.values.count == 1)
    }

    // Solo Swift: le righe Device Support portano la piattaforma nella chiave e nel nome.
    @Test func deviceSupportRowsCarryThePlatformInKeyAndName() async throws {
        let fs = InMemoryFileSystem()
        let folder = Self.xcode + "/iOS DeviceSupport/iPhone16,2 18.0 (22A3354)"
        fs.addFile(folder + "/Symbols/dyld", size: 5)

        let snapshot = try await create(fs, FakeSizeProbe((folder, 4096))).scan()

        let candidate = try #require(snapshot.candidates.first)
        #expect(snapshot.candidates.count == 1)
        #expect(candidate.kind == .deviceSupport)
        #expect(candidate.key == "device-support:iOS:" + folder)
        #expect(candidate.name == "iOS: iPhone16,2 18.0 (22A3354)")
        #expect(candidate.sizeBytes == 4096)
        #expect(snapshot.fileInventory[candidate.key]?.item.declaredRoot == Self.xcode + "/iOS DeviceSupport")
        #expect(snapshot.fileInventory[candidate.key]?.identity.logicalSizeBytes == 5)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeFileScannerTests`
Expected: errore di compilazione `cannot find type 'XcodeFileScanner' in scope`.

- [ ] **Step 3: Implementare `XcodeFileScanner`**

`Sources/CleanerCore/Xcode/XcodeFileScanner.swift`:

```swift
import Darwin

/// `IXcodeFileScanner`.
public protocol XcodeFileScanning: Sendable {
    func scan() async throws -> XcodeSnapshot
    func measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot
}

/// Scansiona solo le cartelle approvate della cache utente di Xcode: DerivedData e i Device
/// Support delle quattro piattaforme. Archives e UserData non sono mai candidati.
public struct XcodeFileScanner: XcodeFileScanning {
    private static let platforms = ["iOS", "watchOS", "tvOS", "visionOS"]

    private let fileSystem: any FileSystem
    private let ruleScanner: RuleScanner
    private let pathGuard: any PathGuarding
    private let links: any LinkInspecting
    private let sizeProbe: any XcodeSizeProbing
    private let homeDirectory: String

    public init(
        fileSystem: any FileSystem,
        ruleScanner: RuleScanner,
        pathGuard: any PathGuarding,
        links: any LinkInspecting,
        sizeProbe: any XcodeSizeProbing,
        homeDirectory: String
    ) {
        self.fileSystem = fileSystem
        self.ruleScanner = ruleScanner
        self.pathGuard = pathGuard
        self.links = links
        self.sizeProbe = sizeProbe
        self.homeDirectory = homeDirectory
    }

    private struct ScanState {
        var candidates: [XcodeCandidate] = []
        var warnings: [XcodeInventoryWarning] = []
        var inventory: [(key: String, entry: XcodeFileEntry)] = []
        var inventoryKeys = Set<[UInt8]>()
    }

    @concurrent
    public func scan() async throws -> XcodeSnapshot {
        var state = ScanState()
        let xcodeRoot = PathText.join(PathText.join(PathText.join(homeDirectory, "Library"), "Developer"), "Xcode")

        try await scanRoot(PathText.join(xcodeRoot, "DerivedData"), .derivedData, platform: nil, &state)
        for platform in Self.platforms {
            try await scanRoot(PathText.join(xcodeRoot, "\(platform) DeviceSupport"), .deviceSupport, platform: platform, &state)
        }

        return XcodeSnapshot(candidates: state.candidates, warnings: state.warnings, fileInventory: XcodeFileInventory(state.inventory))
    }

    private func scanRoot(_ root: String, _ kind: XcodeResourceKind, platform: String?, _ state: inout ScanState) async throws {
        try Task.checkCancellation()

        if !fileSystem.directoryExists(root) {
            // Directory.Exists è falso anche per una cartella che non si può leggere: elencarla
            // distingue l'assenza vera (nessun avviso) dall'accesso negato (inventario incompleto).
            do {
                _ = try fileSystem.contentsOfDirectory(root)
            } catch let error as FileSystemError {
                switch error.code {
                case ENOENT, ENOTDIR:
                    // La root nota è davvero assente.
                    break
                case EACCES, EPERM, EBADF:
                    state.warnings.append(.completenessFailure(kind, String(localized: "Root Xcode non accessibile: \(root)", bundle: .module)))
                default:
                    state.warnings.append(.completenessFailure(kind, String(localized: "Impossibile verificare la root Xcode: \(root)", bundle: .module)))
                }
            }
            return
        }

        if links.isSymbolicLink(root) {
            state.warnings.append(.completenessFailure(kind, String(localized: "La root Xcode è un collegamento simbolico e non viene scansionata: \(root)", bundle: .module)))
            return
        }

        let outcome = try ruleScanner.scan(CleanupRule(root, .matchingDirs, include: ["*"], exclude: [], maxDepth: 1))
        if !outcome.errors.isEmpty || !outcome.exclusions.isEmpty {
            state.warnings.append(.completenessFailure(kind, String(localized: "Inventario incompleto: alcune cartelle non sono leggibili o non superano i controlli di percorso.", bundle: .module)))
        }

        for item in outcome.items {
            try Task.checkCancellation()
            // La regola dei figli diretti produce solo cartelle, ma il confine dei collegamenti si
            // ricontrolla subito prima di leggere metadati e dimensione.
            let verdict = pathGuard.validate(item.path, declaredRoot: root)
            guard verdict.isAllowed, !links.isSymbolicLink(item.path), fileSystem.directoryExists(item.path) else {
                state.warnings.append(.completenessFailure(kind, String(localized: "Una cartella Xcode è stata saltata perché è cambiata o non è sicura: \(PathText.fileName(item.path))", bundle: .module)))
                continue
            }

            let canonical = verdict.canonicalPathValidated
            let key = kind == .derivedData ? "derived-data:\(canonical)" : "device-support:\(platform ?? ""):\(canonical)"
            guard !state.inventoryKeys.contains(XcodeText.ordinalKey(key)) else { continue }

            let info: FileItemInfo
            do {
                info = try fileSystem.itemInfo(canonical)
            } catch is FileSystemError {
                state.warnings.append(.completenessFailure(kind, String(localized: "Una cartella Xcode è stata saltata perché i metadati non sono leggibili: \(PathText.fileName(item.path))", bundle: .module)))
                continue
            }

            let allocated = try await sizeProbe.measure(canonical)
            let partial = outcome.errors.contains { Self.isAtOrBelow($0.path, canonical) }
            let identity = XcodeFileIdentity(
                canonicalPath: canonical,
                isDirectory: true,
                creationTime: info.creation,
                lastWriteTime: info.lastWrite,
                logicalSizeBytes: partial ? nil : item.sizeBytes)
            let guardedItem = ScanItem(path: canonical, sizeBytes: item.sizeBytes, isDirectory: item.isDirectory, declaredRoot: root)
            state.inventory.append((key, XcodeFileEntry(item: guardedItem, identity: identity)))
            state.inventoryKeys.insert(XcodeText.ordinalKey(key))

            let name = PathText.fileName(canonical)
            state.candidates.append(XcodeCandidate(
                key: key,
                kind: kind,
                name: platform.map { "\($0): \(name)" } ?? name,
                path: canonical,
                sizeBytes: allocated,
                blockReason: partial
                    ? String(localized: "Scansione parziale: impossibile verificare l'identità completa della cartella.", bundle: .module)
                    : nil))
        }
    }

    private static func isAtOrBelow(_ candidatePath: String, _ rootPath: String) -> Bool {
        PathText.equalsIgnoringCase(candidatePath, rootPath)
            || PathText.hasPrefixIgnoringCase(candidatePath, PathText.trimmingTrailingSlashes(rootPath) + "/")
    }

    /// Misura le immagini runtime dichiarate dalla CLI, mai i percorsi dei volumi montati.
    @concurrent
    public func measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot {
        var warnings = snapshot.warnings
        var candidates = snapshot.candidates
        var seenPaths = Set<[UInt8]>()
        var firstPath: String?

        for (index, candidate) in snapshot.candidates.enumerated() where candidate.kind == .runtime {
            try Task.checkCancellation()
            var measured = candidate
            measured.sizeBytes = nil

            guard let path = candidate.path, !XcodeText.isNullOrWhiteSpace(path), path.utf8.first == UInt8(ascii: "/") else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Dimensione sconosciuta per \(candidate.name): percorso dell'immagine runtime non disponibile.", bundle: .module)))
                continue
            }

            guard let root = PathText.parent(path) else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Dimensione sconosciuta per \(candidate.name): percorso dell'immagine runtime non valido.", bundle: .module)))
                continue
            }

            let rootVerdict = pathGuard.validateRoot(root)
            let verdict = rootVerdict.isAllowed ? pathGuard.validate(path, declaredRoot: root) : rootVerdict
            guard verdict.isAllowed, !links.isSymbolicLink(path) else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Dimensione sconosciuta per \(candidate.name): il percorso dell'immagine non supera i controlli di sicurezza.", bundle: .module)))
                continue
            }

            let canonical = verdict.canonicalPathValidated
            measured.path = canonical
            guard seenPaths.insert(XcodeText.ordinalKey(canonical)).inserted else {
                candidates[index] = measured
                warnings.append(.advisory(.runtime, String(localized: "Immagine runtime condivisa con \(firstPath ?? ""): la dimensione viene conteggiata una sola volta.", bundle: .module)))
                continue
            }

            firstPath = canonical
            measured.sizeBytes = try await sizeProbe.measure(canonical)
            candidates[index] = measured
        }

        return XcodeSnapshot(candidates: candidates, warnings: warnings, fileInventory: snapshot.fileInventory)
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeFileScannerTests`
Expected: `Test run with 8 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Xcode/XcodeFileScannerTests.cs` con:

```markdown
| Xcode/XcodeFileScannerTests.cs | 7 | Xcode/XcodeFileScannerTests.swift | 8 | 3 | 7 portati + 1 solo-Swift (`deviceSupportRowsCarryThePlatformInKeyAndName`); `InaccessibleRootFileSystem` deriva da `ForwardingFileSystem` invece di usare `DispatchProxy` |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Cartella Xcode scomparsa fra il controllo e la lettura dei metadati | `DirectoryInfo` restituisce la sentinella 1601 e la riga prosegue | riga saltata con l'avviso «metadati non leggibili» | accettata (solo in una corsa, lato sicuro) |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeFileScanner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `XcodeInventoryCollector`

Il confine dell'inventario verso l'applicazione: righe della CLI, poi righe delle cartelle, poi misura delle immagini runtime.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeInventoryCollector.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeInventoryCollectorTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeInventoryCollector.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeInventoryCollectorTests.cs`

**Interfaces:**
- Consumes: `XcodeCliInvoking`, `XcodeInventoryCollecting`, modelli (Task 2); `XcodeFileScanning` (Task 7).
- Produces: `public struct XcodeInventoryCollector: XcodeInventoryCollecting` — `init(cli: any XcodeCliInvoking, fileScanner: (any XcodeFileScanning)? = nil)`, `collect() async throws -> XcodeSnapshot`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeInventoryCollectorTests.swift`:

```swift
import Synchronization
import Testing
@testable import CleanerCore

struct XcodeInventoryCollectorTests {
    private struct FakeCli: XcodeCliInvoking {
        let snapshot: XcodeSnapshot

        func readInventory() async throws -> XcodeSnapshot { snapshot }
        func deleteDevice(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non supportato") }
        func deleteRuntime(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non supportato") }
    }

    private final class FakeFileScanner: XcodeFileScanning {
        private let files: XcodeSnapshot
        private let runtimeBytes: Int64
        private let calls = Mutex<(scan: Bool, measure: Bool)>((false, false))

        init(_ files: XcodeSnapshot, runtimeBytes: Int64) {
            self.files = files
            self.runtimeBytes = runtimeBytes
        }

        var scanCalled: Bool { calls.withLock { $0.scan } }
        var measureCalled: Bool { calls.withLock { $0.measure } }

        func scan() async throws -> XcodeSnapshot {
            calls.withLock { $0.scan = true }
            return files
        }

        func measureRuntimeBackingImages(_ snapshot: XcodeSnapshot) async throws -> XcodeSnapshot {
            calls.withLock { $0.measure = true }
            var measured = snapshot
            measured.candidates = snapshot.candidates.map { candidate in
                var copy = candidate
                if candidate.kind == .runtime { copy.sizeBytes = runtimeBytes }
                return copy
            }
            return measured
        }
    }

    @Test func emptyInventoryIsSuccessful() async throws {
        let snapshot = try await XcodeInventoryCollector(cli: FakeCli(snapshot: .empty)).collect()

        #expect(snapshot.candidates.isEmpty)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test func collectorAddsFileRowsAndMeasuresRuntimeBackingSize() async throws {
        let cliSnapshot = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "runtime:11111111-1111-4111-8111-111111111111", kind: .runtime, name: "iOS 18", path: "/backing/AssetData"),
        ], warnings: [])
        let fileSnapshot = XcodeSnapshot(candidates: [
            XcodeCandidate(key: "derived-data:/Users/tester/Library/Developer/Xcode/DerivedData/App", kind: .derivedData, name: "App"),
        ], warnings: [])
        let scanner = FakeFileScanner(fileSnapshot, runtimeBytes: 4096)

        let collected = try await XcodeInventoryCollector(cli: FakeCli(snapshot: cliSnapshot), fileScanner: scanner).collect()

        #expect(scanner.scanCalled)
        #expect(scanner.measureCalled)
        #expect(collected.candidates.first { $0.kind == .runtime }?.sizeBytes == 4096)
        #expect(collected.candidates.contains { $0.kind == .derivedData })
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeInventoryCollectorTests`
Expected: errore di compilazione `cannot find 'XcodeInventoryCollector' in scope`.

- [ ] **Step 3: Implementare `XcodeInventoryCollector`**

`Sources/CleanerCore/Xcode/XcodeInventoryCollector.swift`:

```swift
/// Il confine dell'inventario verso l'applicazione: la gestione della CLI resta in
/// `XcodeCliInvoking`, le cartelle in `XcodeFileScanning`.
public struct XcodeInventoryCollector: XcodeInventoryCollecting {
    private let cli: any XcodeCliInvoking
    private let fileScanner: (any XcodeFileScanning)?

    public init(cli: any XcodeCliInvoking, fileScanner: (any XcodeFileScanning)? = nil) {
        self.cli = cli
        self.fileScanner = fileScanner
    }

    public func collect() async throws -> XcodeSnapshot {
        let cliSnapshot = try await cli.readInventory()
        guard let fileScanner else { return cliSnapshot }

        let fileSnapshot = try await fileScanner.scan()
        let combined = XcodeSnapshot(
            candidates: cliSnapshot.candidates + fileSnapshot.candidates,
            warnings: cliSnapshot.warnings + fileSnapshot.warnings,
            fileInventory: fileSnapshot.fileInventory)
        return try await fileScanner.measureRuntimeBackingImages(combined)
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeInventoryCollectorTests`
Expected: `Test run with 2 tests … passed`, nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Xcode/XcodeInventoryCollectorTests.cs` con:

```markdown
| Xcode/XcodeInventoryCollectorTests.cs | 2 | Xcode/XcodeInventoryCollectorTests.swift | 2 | 3 | |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeInventoryCollector

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: `XcodeCleanExecutor` e diario della pulizia

Esegue solo le risorse confermate, riverificando ciascuna subito prima della rimozione: inventario fresco, stato di Xcode, identità e dipendenze. Le cartelle passano dal `CleanEngine` del piano 1 con il diario; simulatori e runtime dalla CLI, con una verifica dell'inventario dopo il comando.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeCleanExecutor.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeCleanExecutorTests.swift`
- Reference: `src/MjmCleaner.Core/Xcode/XcodeCleanExecutor.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeCleanExecutorTests.cs`

**Interfaces:**
- Consumes: `CleanPerforming`, `CleanEngine`, `CategorySelection`, `CleanProgress`, `CleanReport`, `CategoryCleanResult`, `ScanError`, `DeletionRecording`, `WallClock`, `SystemWallClock`, `PathGuard`, `DenyList`, `RuleScanner` (piano 1); modelli, errori, `XcodeText`, `XcodeUuid` (Task 2); `XcodeClassifier`, `XcodeSelection` (Task 3); `XcodeJson` (Task 4); `XcodeSizeProbing`, `XcodeRunningProbing` (Task 6); `XcodeFileScanner` (Task 7); `XcodeInventoryCollector` (Task 8); `InMemoryFileSystem`, `FakeLinkInspector`, `Recorder`, `cancelCurrentTask`, `UnexpectedTestError` (piano 1, test).
- Produces:
  - `public protocol XcodeCleanExecuting: Sendable` — `execute(_ plan: XcodeConfirmedPlan, progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> XcodeCleanResult`
  - `public struct XcodeCleanExecutor: XcodeCleanExecuting` — `init(cli: any XcodeCliInvoking, collector: any XcodeInventoryCollecting, cleanEngine: any CleanPerforming, measures: any XcodeSizeProbing, runningProbe: any XcodeRunningProbing, clock: any WallClock)`

Note di porting:
- `execute` non lancia, come il C# che trasformava ogni eccezione in un esito dell'elemento. `catch (OperationCanceledException) when (ct.IsCancellationRequested)` diventa `catch is CancellationError where Task.isCancelled`.
- Dove il C# usava `CancellationToken.None` (spazio libero finale) o un `CancellationTokenSource` proprio da 15 s (verifica dopo un comando) si usa un `Task { … }` non strutturato, che non eredita l'annullamento: un comando già lanciato va sempre verificato. Il limite dei 15 s è una corsa fra la raccolta e `Task.sleep` in un task group.
- `current!` dopo `CompareIdentity` diventa un `guard let current` che produce lo stesso motivo («La risorsa approvata non è più presente nell'inventario.»), che nel C# era il primo controllo di `CompareIdentity`.
- `candidate.CliId!` diventa `candidate.cliId ?? ""`: un identificativo mancante arriva alla CLI vuoto e viene respinto da `validateUuid` senza avviare processi, con lo stesso esito del C#.
- **Diario (spec §8.2, assente nel C#).** Il `journal` passa a `CleanEngine.clean`, che registra ogni cartella eliminata con il percorso validato dal `PathGuard`. Un simulatore o un runtime con esito «rimosso» dopo la verifica si registra subito con `path ?? key`, lo stesso testo che finisce in `deletedPaths` dello storico: il diario copre così tutto ciò che il log di sessione riporterà. Esiti falliti, incerti o saltati non vi entrano mai.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Xcode/XcodeCleanExecutorTests.swift`:

```swift
import Foundation
import Synchronization
import Testing
@testable import CleanerCore

struct XcodeCleanExecutorTests {
    private static let deviceId = "11111111-1111-4111-8111-111111111111"
    private static let otherDeviceId = "33333333-3333-4333-8333-333333333333"
    private static let runtimeId = "22222222-2222-4222-8222-222222222222"
    private static let success = ProcessResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false)

    // MARK: - Doppi

    /// Porting di `QueueCollector`: restituisce gli inventari in ordine, poi ripete l'ultimo.
    private final class QueueCollector: XcodeInventoryCollecting {
        private let snapshots: [XcodeSnapshot]
        private let index = Mutex(0)

        init(_ snapshots: XcodeSnapshot...) {
            self.snapshots = snapshots
        }

        func collect() async throws -> XcodeSnapshot {
            let position = index.withLock { value in
                defer { value += 1 }
                return min(value, snapshots.count - 1)
            }
            return snapshots[position]
        }
    }

    private struct FakeCli: XcodeCliInvoking {
        let deletedDevices = Recorder<String>()
        let operationOrder = Recorder<String>()
        var deviceResult = XcodeCleanExecutorTests.success
        var deviceResultForSecond = XcodeCleanExecutorTests.success
        var onDeviceDelete: (@Sendable (String) -> Void)?
        var deviceError: (any Error)?

        func readInventory() async throws -> XcodeSnapshot { .empty }

        func deleteDevice(_ uuid: String) async throws -> ProcessResult {
            deletedDevices.append(uuid)
            operationOrder.append("device")
            onDeviceDelete?(uuid)
            if let deviceError { throw deviceError }
            return deletedDevices.values.count == 1 ? deviceResult : deviceResultForSecond
        }

        func deleteRuntime(_ uuid: String) async throws -> ProcessResult {
            operationOrder.append("runtime")
            return XcodeCleanExecutorTests.success
        }
    }

    /// Porting di `FakeCleanEngine`. Con `journals` registra nel diario ogni elemento ricevuto,
    /// come fa `CleanEngine` per ciò che elimina.
    private struct FakeCleanEngine: CleanPerforming {
        let calls = Recorder<[CategorySelection]>()
        var bytesFreed: Int64 = 0
        var itemsDeleted = 0
        var journals = false

        func clean(_ selections: [CategorySelection], progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> CleanReport {
            calls.append(selections)
            if journals {
                for item in selections.flatMap(\.items) { journal?.recordDeleted(item.path) }
            }
            return CleanReport(startedAt: Date(timeIntervalSince1970: 0), duration: .zero, bytesFreed: bytesFreed,
                               itemsDeleted: itemsDeleted, itemsFailed: 0, categories: [], errors: [], deletedPaths: [])
        }
    }

    private struct FakeSizeProbe: XcodeSizeProbing {
        func measure(_ path: String) async throws -> Int64? { nil }
        func freeBytes() async throws -> Int64? { 1000 }
    }

    private final class QueueRunningProbe: XcodeRunningProbing {
        private let states: [XcodeRunningState]
        private let index = Mutex(0)

        init(_ states: XcodeRunningState...) {
            self.states = states
        }

        func state() async throws -> XcodeRunningState {
            let position = index.withLock { value in
                defer { value += 1 }
                return min(value, states.count - 1)
            }
            return states[position]
        }
    }

    private struct JournalRecorder: DeletionRecording {
        let paths = Recorder<String>()

        func recordDeleted(_ path: String) {
            paths.append(path)
        }
    }

    // MARK: - Costruzione

    private func create(_ cli: FakeCli, _ collector: any XcodeInventoryCollecting, _ clean: FakeCleanEngine = FakeCleanEngine()) -> XcodeCleanExecutor {
        XcodeCleanExecutor(cli: cli, collector: collector, cleanEngine: clean, measures: FakeSizeProbe(),
                           runningProbe: QueueRunningProbe(.notRunning), clock: SystemWallClock())
    }

    private func snapshot(_ candidates: XcodeCandidate...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: [])
    }

    private func snapshot(_ candidates: [XcodeCandidate], _ warnings: XcodeInventoryWarning...) -> XcodeSnapshot {
        XcodeSnapshot(candidates: candidates, warnings: warnings)
    }

    private func device(_ id: String = Self.deviceId, size: Int64? = 100) -> XcodeCandidate {
        XcodeCandidate(key: id, kind: .device, name: "iPhone", cliId: id, build: "build-1", state: "Shutdown", sizeBytes: size)
    }

    private func runtime(_ dependencies: [String]) -> XcodeCandidate {
        XcodeCandidate(key: "runtime:" + Self.runtimeId, kind: .runtime, name: "iOS 18", cliId: Self.runtimeId,
                       runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0", build: "runtime-build", sizeBytes: 200,
                       dependencies: dependencies)
    }

    private func confirm(_ source: XcodeSnapshot, _ selected: String...) throws -> XcodeConfirmedPlan {
        try XcodeSelection.confirm(XcodeSelection.preview(source, selectedKeys: Set(selected)), acknowledgeDependencies: true)
    }

    private func parseUnavailableDevice(includeRuntime: Bool = false) -> XcodeSnapshot {
        let simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """
        let images = """
            {"22222222-2222-4222-8222-222222222222":{"identifier":"22222222-2222-4222-8222-222222222222","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A3351","deletable":true}}
            """
        return XcodeJson.parseInventory(simctl, includeRuntime ? images : "{}", runtimeDeleteSupported: true)
    }

    private static let derivedDataRoot = "/Users/test/Library/Developer/Xcode/DerivedData"
    private static let appPath = derivedDataRoot + "/App-abc"
    private static let appKey = "derived-data:" + appPath

    /// `FileSnapshot` del C#: una cartella DerivedData con identità completa.
    private func fileSnapshot(allocatedBytes: Int64?, logicalBytes: Int64 = 10 * 1024 * 1024 * 1024) -> XcodeSnapshot {
        let scan = ScanItem(path: Self.appPath, sizeBytes: logicalBytes, isDirectory: true, declaredRoot: Self.derivedDataRoot)
        let identity = XcodeFileIdentity(canonicalPath: Self.appPath, isDirectory: true, creationTime: Date(timeIntervalSince1970: 86_400),
                                         lastWriteTime: Date(timeIntervalSince1970: 2 * 86_400), logicalSizeBytes: logicalBytes)
        return XcodeSnapshot(
            candidates: [XcodeCandidate(key: Self.appKey, kind: .derivedData, name: "App-abc", path: Self.appPath, sizeBytes: allocatedBytes)],
            warnings: [],
            fileInventory: XcodeFileInventory([(Self.appKey, XcodeFileEntry(item: scan, identity: identity))]))
    }

    private func single(_ result: XcodeCleanResult) throws -> XcodeItemResult {
        #expect(result.items.count == 1)
        return try #require(result.items.first)
    }

    // MARK: - Test portati

    @Test func revalidationNeverAddsItems() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), Self.deviceId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = create(cli, QueueCollector(snapshot(device(), device(Self.otherDeviceId)), snapshot(device(Self.otherDeviceId))), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values == [Self.deviceId])
        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .deleted)
    }

    @Test func changedIdentityIsSkipped() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        let cli = FakeCli()
        var rebuilt = device()
        rebuilt.build = "new-build"

        let result = await create(cli, QueueCollector(snapshot(rebuilt))).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func deviceBootedAfterConfirmationIsSkipped() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        let cli = FakeCli()
        var booted = device()
        booted.state = "Booted"

        let result = await create(cli, QueueCollector(snapshot(booted))).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func devicesRunBeforeRuntimes() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), Self.deviceId, "runtime:" + Self.runtimeId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = create(cli, QueueCollector(
            snapshot(device(), runtime([Self.deviceId])),
            snapshot(runtime([])),
            snapshot(runtime([])),
            snapshot()), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["device", "runtime"])
        #expect(result.items.allSatisfy { $0.outcome == .deleted })
        #expect(clean.calls.values.isEmpty)
    }

    @Test func deviceFailureSkipsDependentRuntime() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), Self.deviceId, "runtime:" + Self.runtimeId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "in use", timedOut: false)

        let result = await create(cli, QueueCollector(snapshot(device(), runtime([Self.deviceId])))).execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["device"])
        #expect(result.items.map(\.outcome) == [.failed, .skipped])
    }

    @Test func newRuntimeDependencyAfterConfirmationSkipsRuntime() async throws {
        let plan = try confirm(snapshot(device(), runtime([Self.deviceId])), "runtime:" + Self.runtimeId)
        let cli = FakeCli()

        let result = await create(cli, QueueCollector(snapshot(device(), device(Self.otherDeviceId), runtime([Self.deviceId, Self.otherDeviceId]))))
            .execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
    }

    @Test func timeoutWithUnreadableInventoryIsUncertain() async throws {
        let plan = try confirm(snapshot(device()), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)
        let collector = QueueCollector(snapshot(device()), snapshot([], XcodeInventoryWarning(resourceGroup: .device, message: "unavailable")))

        let result = await create(cli, collector).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .uncertain)
        #expect(cli.deletedDevices.values.count == 1)
    }

    @Test func incompletePostCommandInventoryCannotVerifyAbsence() async throws {
        let malformedSimctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"33333333-3333-4333-8333-333333333333","name":"iPhone 16","state":"Shutdown","dataPathSize":[]},
              {"name":"missing UUID","state":"Shutdown"}]}}
            """
        let incomplete = XcodeJson.parseInventory(malformedSimctl, "{}", runtimeDeleteSupported: true)
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), incomplete), clean).execute(plan, progress: nil, journal: nil)

        #expect(!incomplete.candidates.contains { $0.key == Self.deviceId })
        #expect(try single(result).outcome == .uncertain)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(cli.deletedDevices.values.count == 1)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func failedCommandAndAbsentResourceIsNotCredited() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "failed", timedOut: false)
        let clean = FakeCleanEngine()

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), snapshot()), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .failed)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func timedOutCommandAndAbsentResourceIsUncertainWithoutCredit() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: true)
        let clean = FakeCleanEngine()

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), snapshot()), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).outcome == .uncertain)
        #expect(result.historyReport.bytesFreed == 0)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func cancelledCommandAndAbsentResourceIsUncertainWithoutCredit() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.onDeviceDelete = { _ in cancelCurrentTask() }
        let executor = create(cli, QueueCollector(snapshot(device(size: 500)), snapshot()))

        let result = await Task { await executor.execute(plan, progress: nil, journal: nil) }.value

        #expect(try single(result).outcome == .uncertain)
        #expect(result.historyReport.bytesFreed == 0)
    }

    @Test func commandExceptionAndAbsentResourceIsNotCredited() async throws {
        let plan = try confirm(snapshot(device(size: 500)), Self.deviceId)
        var cli = FakeCli()
        cli.deviceError = UnexpectedTestError(description: "runner failed")

        let result = await create(cli, QueueCollector(snapshot(device(size: 500)), snapshot())).execute(plan, progress: nil, journal: nil)

        let item = try single(result)
        #expect(item.outcome == .failed)
        #expect(item.reason == "runner failed")
        #expect(result.historyReport.bytesFreed == 0)
    }

    @Test func advisoryRuntimeSizeWarningDoesNotBlockDeleteOrVerification() async throws {
        let plan = try confirm(snapshot(runtime([])), "runtime:" + Self.runtimeId)
        let advisory = XcodeInventoryWarning(resourceGroup: .runtime, message: "runtime size unknown", kind: .advisory)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = create(cli, QueueCollector(snapshot([runtime([])], advisory), snapshot([], advisory)), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["runtime"])
        #expect(try single(result).outcome == .deleted)
        #expect(result.historyReport.bytesFreed == 200)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func completenessWarningStillBlocksRuntimeDelete() async throws {
        let plan = try confirm(snapshot(runtime([])), "runtime:" + Self.runtimeId)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let incomplete = XcodeInventoryWarning(resourceGroup: .runtime, message: "runtime inventory incomplete")
        let executor = create(cli, QueueCollector(snapshot([runtime([])], incomplete)), clean)

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
        #expect(clean.calls.values.isEmpty)
    }

    @Test func cancellationRetainsCompletedResults() async throws {
        let cli = FakeCli()
        let plan = try confirm(snapshot(device(), device(Self.otherDeviceId)), Self.deviceId, Self.otherDeviceId)
        let executor = create(cli, QueueCollector(snapshot(device(), device(Self.otherDeviceId)), snapshot(device(Self.otherDeviceId))))

        let result = await Task {
            await executor.execute(plan, progress: { if $0.itemsDone == 1 { cancelCurrentTask() } }, journal: nil)
        }.value

        #expect(result.items.map(\.outcome) == [.deleted, .skipped])
        #expect(cli.deletedDevices.values.count == 1)
    }

    @Test func failedAndUnknownSizesDoNotIncreaseHistoryBytes() async throws {
        let unknown = device(Self.otherDeviceId, size: nil)
        let plan = try confirm(snapshot(device(size: 500), unknown), Self.deviceId, Self.otherDeviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "failure", timedOut: false)

        let result = await create(cli, QueueCollector(
            snapshot(device(size: 500), unknown), snapshot(device(size: 500), unknown),
            snapshot(device(size: 500), unknown), snapshot(unknown))).execute(plan, progress: nil, journal: nil)

        #expect(result.historyReport.bytesFreed == 0)
        #expect(result.items.first?.verifiedEstimatedBytes == nil)
    }

    @Test func independentFailureDoesNotStopOtherItems() async throws {
        let plan = try confirm(snapshot(device(), device(Self.otherDeviceId)), Self.deviceId, Self.otherDeviceId)
        var cli = FakeCli()
        cli.deviceResult = ProcessResult(exitCode: 1, standardOutput: "", standardError: "failure", timedOut: false)
        let executor = create(cli, QueueCollector(
            snapshot(device(), device(Self.otherDeviceId)), snapshot(device(), device(Self.otherDeviceId)),
            snapshot(device(), device(Self.otherDeviceId)), snapshot(device())))

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values == [Self.deviceId, Self.otherDeviceId])
        #expect(result.items.map(\.outcome) == [.failed, .deleted])
    }

    @Test func xcodeStartedAfterConfirmationBlocksFilesWithoutCallingCleanEngine() async throws {
        let source = fileSnapshot(allocatedBytes: 10, logicalBytes: 50)
        let plan = try confirm(source, Self.appKey)
        let cli = FakeCli()
        let clean = FakeCleanEngine()
        let executor = XcodeCleanExecutor(cli: cli, collector: QueueCollector(source), cleanEngine: clean, measures: FakeSizeProbe(),
                                          runningProbe: QueueRunningProbe(.running), clock: SystemWallClock())

        let result = await executor.execute(plan, progress: nil, journal: nil)

        #expect(clean.calls.values.isEmpty)
        #expect(try single(result).outcome == .skipped)
        #expect(cli.deletedDevices.values.isEmpty)
    }

    @Test func parsedUnavailableDeviceCanBeDeletedThroughExecutor() async throws {
        let unavailable = parseUnavailableDevice()
        let plan = try confirm(unavailable, Self.deviceId)
        let cli = FakeCli()
        let after = XcodeJson.parseInventory(#"{"runtimes":[],"devices":{}}"#, "{}", runtimeDeleteSupported: true)

        let result = await create(cli, QueueCollector(unavailable, after)).execute(plan, progress: nil, journal: nil)

        #expect(cli.deletedDevices.values == [Self.deviceId])
        #expect(try single(result).outcome == .deleted)
    }

    @Test func parsedUnavailableDependencyDoesNotBlockRuntimeDelete() async throws {
        let unavailable = parseUnavailableDevice(includeRuntime: true)
        let plan = try confirm(unavailable, "runtime:" + Self.runtimeId)
        let cli = FakeCli()
        let after = XcodeJson.parseInventory(#"{"runtimes":[],"devices":{}}"#, "{}", runtimeDeleteSupported: true)

        let result = await create(cli, QueueCollector(unavailable, after)).execute(plan, progress: nil, journal: nil)

        #expect(cli.operationOrder.values == ["runtime"])
        #expect(try single(result).outcome == .deleted)
    }

    @Test func parsedUnknownDeviceStateRemainsBlockedAtExecutor() {
        let simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"MysteryState"}]}}
            """
        let unknown = XcodeJson.parseInventory(simctl, "{}", runtimeDeleteSupported: true)
        let cli = FakeCli()

        #expect(throws: XcodeArgumentError.self) { try confirm(unknown, Self.deviceId) }
        #expect(cli.deletedDevices.values.isEmpty)
    }

    @Test func fileHistoryUsesFreshAllocatedSizeInsteadOfLogicalBytesFreed() async throws {
        let allocatedBytes: Int64 = 1_048_576
        let plan = try confirm(fileSnapshot(allocatedBytes: 4_194_304), Self.appKey)
        let clean = FakeCleanEngine(bytesFreed: 10 * 1024 * 1024 * 1024, itemsDeleted: 1)

        let result = await create(FakeCli(), QueueCollector(fileSnapshot(allocatedBytes: allocatedBytes)), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).verifiedEstimatedBytes == allocatedBytes)
        #expect(result.historyReport.bytesFreed == allocatedBytes)
    }

    @Test func fileHistoryLeavesSizeUnknownWhenFreshAllocatedMeasureIsUnavailable() async throws {
        let plan = try confirm(fileSnapshot(allocatedBytes: 4_194_304), Self.appKey)
        let clean = FakeCleanEngine(bytesFreed: 10 * 1024 * 1024 * 1024, itemsDeleted: 1)

        let result = await create(FakeCli(), QueueCollector(fileSnapshot(allocatedBytes: nil)), clean).execute(plan, progress: nil, journal: nil)

        #expect(try single(result).verifiedEstimatedBytes == nil)
        #expect(result.historyReport.bytesFreed == 0)
    }

    // MARK: - Solo Swift: diario della pulizia (spec §8.2)

    // Le cartelle arrivano al diario tramite CleanEngine, che riceve lo stesso journal; i
    // simulatori rimossi con verifica vi entrano con il testo che lo storico registra (la chiave,
    // perché un simulatore non ha percorso). Un comando fallito non vi entra mai.
    @Test func journalReceivesVerifiedCliDeletionsAndIsForwardedToTheCleanEngine() async throws {
        var files = fileSnapshot(allocatedBytes: 10, logicalBytes: 50)
        let both = XcodeSnapshot(candidates: [device(), device(Self.otherDeviceId)] + files.candidates, warnings: [], fileInventory: files.fileInventory)
        files.candidates.append(device(Self.otherDeviceId))
        let plan = try confirm(both, Self.deviceId, Self.otherDeviceId, Self.appKey)
        var cli = FakeCli()
        cli.deviceResultForSecond = ProcessResult(exitCode: 1, standardOutput: "", standardError: "in use", timedOut: false)
        let clean = FakeCleanEngine(itemsDeleted: 1, journals: true)
        let journal = JournalRecorder()

        let result = await create(cli, QueueCollector(both, files), clean).execute(plan, progress: nil, journal: journal)

        #expect(result.items.map(\.outcome) == [.deleted, .failed, .deleted])
        #expect(journal.paths.values == [Self.deviceId, Self.appPath])
        #expect(clean.calls.values.flatMap { $0.map(\.categoryId) } == ["xcode-derived-data"])
    }

    // La catena reale: identità catturata dallo scanner, riverifica e cancellazione da parte di
    // CleanEngine con PathGuard, diario compreso.
    @Test func realCleanEngineDeletesTheRevalidatedFolderAndJournalsIt() async throws {
        let home = "/Users/test"
        let fs = InMemoryFileSystem()
        fs.addFile(Self.appPath + "/Build/Products/app", size: 64)
        let links = FakeLinkInspector()
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
        let scanner = XcodeFileScanner(
            fileSystem: fs, ruleScanner: RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock()),
            pathGuard: pathGuard, links: links, sizeProbe: FakeSizeProbe(), homeDirectory: home)
        let collector = XcodeInventoryCollector(cli: FakeCli(), fileScanner: scanner)
        let plan = try confirm(try await collector.collect(), Self.appKey)
        let executor = XcodeCleanExecutor(
            cli: FakeCli(), collector: collector, cleanEngine: CleanEngine(fileSystem: fs, pathGuard: pathGuard, clock: SystemWallClock()),
            measures: FakeSizeProbe(), runningProbe: QueueRunningProbe(.notRunning), clock: SystemWallClock())
        let journal = JournalRecorder()

        let result = await executor.execute(plan, progress: nil, journal: journal)

        #expect(try single(result).outcome == .deleted)
        #expect(!fs.directoryExists(Self.appPath))
        #expect(fs.directoryExists(Self.derivedDataRoot))
        #expect(journal.paths.values == [Self.appPath])
        #expect(result.historyReport.deletedPaths == [Self.appPath])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeCleanExecutorTests`
Expected: errore di compilazione `cannot find 'XcodeCleanExecutor' in scope`.

- [ ] **Step 3: Implementare `XcodeCleanExecutor`**

`Sources/CleanerCore/Xcode/XcodeCleanExecutor.swift`:

```swift
import Foundation

/// `IXcodeCleanExecutor`.
public protocol XcodeCleanExecuting: Sendable {
    func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult
}

/// Esegue solo le risorse confermate, riverificando ciascuna subito prima della rimozione. Non
/// lancia mai: l'annullamento e gli errori diventano esiti dei singoli elementi.
///
/// Diario (spec §8.2, assente nel C#): le cartelle passano da `CleanEngine`, che registra ogni
/// percorso eliminato nel `journal`; simulatori e runtime rimossi con verifica vi si registrano
/// con lo stesso testo che finisce fra i percorsi eliminati dello storico.
public struct XcodeCleanExecutor: XcodeCleanExecuting {
    private static let verificationTimeout: Duration = .seconds(15)

    private let cli: any XcodeCliInvoking
    private let collector: any XcodeInventoryCollecting
    private let cleanEngine: any CleanPerforming
    private let measures: any XcodeSizeProbing
    private let runningProbe: any XcodeRunningProbing
    private let clock: any WallClock

    public init(
        cli: any XcodeCliInvoking,
        collector: any XcodeInventoryCollecting,
        cleanEngine: any CleanPerforming,
        measures: any XcodeSizeProbing,
        runningProbe: any XcodeRunningProbing,
        clock: any WallClock
    ) {
        self.cli = cli
        self.collector = collector
        self.cleanEngine = cleanEngine
        self.measures = measures
        self.runningProbe = runningProbe
        self.clock = clock
    }

    @concurrent
    public func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult {
        let started = clock.now
        let start = ContinuousClock.now
        var results: [XcodeItemResult] = []
        var warnings: [String] = []
        let freeBefore = await tryFreeBytes()
        let ordered = plan.candidates.filter { $0.kind == .device }
            + plan.candidates.filter { $0.kind == .runtime }
            + plan.candidates.filter { Self.isFile($0.kind) }
        var deletedDevices = Set<[UInt8]>()

        for approved in ordered {
            if Task.isCancelled {
                results.append(Self.result(approved, .skipped, String(localized: "Operazione annullata prima della rimozione.", bundle: .module), nil))
                continue
            }

            do {
                let running = try await runningProbe.state()
                let fresh = try await collector.collect()
                warnings.append(contentsOf: XcodeText.distinct(fresh.warnings.map(\.message)))
                guard Self.isInventoryReadable(fresh, approved.kind) else {
                    results.append(Self.result(approved, .skipped, String(localized: "Inventario non disponibile per verificare la risorsa.", bundle: .module), nil))
                    continue
                }

                let classified = try XcodeClassifier.classify(fresh, xcodeRunning: running == .running)
                if running == .unknown && Self.isFile(approved.kind) {
                    results.append(Self.result(approved, .skipped, String(localized: "Impossibile verificare se Xcode è in esecuzione.", bundle: .module), nil))
                    continue
                }

                guard let current = classified.candidates.first(where: { Self.sameKey($0.key, approved.key) }) else {
                    results.append(Self.result(approved, .skipped, String(localized: "La risorsa approvata non è più presente nell'inventario.", bundle: .module), nil))
                    continue
                }

                if let changed = Self.compareIdentity(plan, fresh, approved, current, deletedDevices) {
                    results.append(Self.result(approved, .skipped, changed, nil))
                    continue
                }

                if let blockReason = current.blockReason {
                    results.append(Self.result(approved, .skipped, blockReason, nil))
                    continue
                }

                if approved.kind == .runtime {
                    let dependentSelected = approved.dependentDeviceKeys.filter { key in
                        plan.candidates.contains { $0.kind == .device && Self.sameKey($0.key, key) }
                    }
                    if dependentSelected.contains(where: { !deletedDevices.contains(XcodeText.caseInsensitiveKey($0)) }) {
                        results.append(Self.result(approved, .skipped, String(localized: "Un dispositivo dipendente selezionato non è stato rimosso con verifica.", bundle: .module), nil))
                        continue
                    }
                }

                if Self.isFile(approved.kind) {
                    await executeFile(plan, approved, freshAllocatedBytes: current.sizeBytes, progress, journal, &results, &warnings)
                    continue
                }

                await executeCli(approved, progress, journal, &results, &warnings)
                if approved.kind == .device, results.last?.outcome == .deleted {
                    deletedDevices.insert(XcodeText.caseInsensitiveKey(XcodeClassifier.normalizeSelectionKey(approved.key)))
                }
            } catch is CancellationError where Task.isCancelled {
                results.append(Self.result(approved, .skipped, String(localized: "Operazione annullata prima della rimozione.", bundle: .module), nil))
            } catch {
                results.append(Self.result(approved, .failed, XcodeText.message(error), nil))
            }

            progress?(CleanProgress(currentPath: approved.path ?? approved.name, itemsDone: results.count, itemsTotal: ordered.count, bytesFreed: 0))
        }

        // Come CancellationToken.None in C#: lo spazio finale si legge anche dopo un annullamento.
        let freeAfter = await Task { await tryFreeBytes() }.value
        let report = Self.makeHistory(started, ContinuousClock.now - start, results)
        return XcodeCleanResult(
            historyReport: report,
            items: results,
            freeBytesBefore: freeBefore,
            freeBytesAfter: freeAfter,
            warnings: XcodeText.distinct(warnings))
    }

    private func executeFile(
        _ plan: XcodeConfirmedPlan,
        _ candidate: XcodeCandidate,
        freshAllocatedBytes: Int64?,
        _ progress: (@Sendable (CleanProgress) -> Void)?,
        _ journal: (any DeletionRecording)?,
        _ results: inout [XcodeItemResult],
        _ warnings: inout [String]
    ) async {
        guard let approvedEntry = plan.fileInventory[candidate.key], approvedEntry.identity.logicalSizeBytes != nil else {
            results.append(Self.result(candidate, .skipped, String(localized: "Identità della cartella incompleta.", bundle: .module), nil))
            return
        }

        let report = await cleanEngine.clean(
            [CategorySelection(categoryId: Self.category(candidate.kind), items: [approvedEntry.item])],
            progress: progress,
            journal: journal)
        if report.itemsDeleted == 1 {
            results.append(Self.result(candidate, .deleted, String(localized: "Cartella rimossa e verificata dal motore di pulizia.", bundle: .module), freshAllocatedBytes))
        } else if let error = report.errors.first {
            results.append(Self.result(candidate, .failed, error.message, nil))
        } else {
            results.append(Self.result(candidate, .skipped, String(localized: "La cartella non è stata rimossa.", bundle: .module), nil))
        }

        if report.itemsFailed > 0 {
            warnings.append(contentsOf: report.errors.map(\.message))
        }
    }

    private func executeCli(
        _ candidate: XcodeCandidate,
        _ progress: (@Sendable (CleanProgress) -> Void)?,
        _ journal: (any DeletionRecording)?,
        _ results: inout [XcodeItemResult],
        _ warnings: inout [String]
    ) async {
        var command: ProcessResult?
        var commandError: (any Error)?
        do {
            // Il classificatore ha già verificato l'UUID; un identificativo mancante arriva vuoto e
            // viene respinto dalla CLI come in C#, senza avviare alcun processo.
            let uuid = candidate.cliId ?? ""
            command = candidate.kind == .device ? try await cli.deleteDevice(uuid) : try await cli.deleteRuntime(uuid)
        } catch {
            commandError = error
        }

        let verified = await tryVerifyAfterCommand(&warnings)
        if let verified {
            warnings.append(contentsOf: XcodeText.distinct(verified.warnings.map(\.message)))
        }

        let failedFallback = String(localized: "Il comando di rimozione non è riuscito.", bundle: .module)
        if let verified, Self.isInventoryReadable(verified, candidate.kind) {
            if commandError is CancellationError || command?.timedOut == true || Task.isCancelled {
                results.append(Self.result(candidate, .uncertain, String(localized: "Il comando è stato interrotto; l'assenza successiva non viene attribuita a questa pulizia.", bundle: .module), nil))
            } else if commandError != nil || command == nil || command?.exitCode != 0 {
                let reason = commandError.map(XcodeText.message) ?? command.map { XcodeText.trimmed($0.standardError) } ?? ""
                results.append(Self.result(candidate, .failed, XcodeText.isNullOrWhiteSpace(reason) ? failedFallback : reason, nil))
            } else if !verified.candidates.contains(where: { Self.sameKey($0.key, candidate.key) }) {
                let estimate = candidate.sizeBytes
                let reason = estimate == nil
                    ? String(localized: "Risorsa assente dopo il comando; dimensione stimata sconosciuta.", bundle: .module)
                    : String(localized: "Risorsa assente dopo il comando.", bundle: .module)
                results.append(Self.result(candidate, .deleted, reason, estimate))
                journal?.recordDeleted(candidate.path ?? candidate.key)
            } else {
                // Qui il comando è riuscito (uscita 0, nessun errore): la risorsa è ancora presente.
                let reason = String(localized: "Il comando è riuscito ma la risorsa è ancora presente.", bundle: .module)
                results.append(Self.result(candidate, .failed, reason, nil))
            }
        } else {
            results.append(Self.result(candidate, .uncertain, String(localized: "Il comando è terminato senza poter verificare l'inventario successivo.", bundle: .module), nil))
        }

        progress?(CleanProgress(currentPath: candidate.name, itemsDone: results.count, itemsTotal: results.count, bytesFreed: 0))
    }

    /// Inventario di verifica con un proprio limite di 15 secondi e indipendente dall'annullamento
    /// del chiamante, come il `CancellationTokenSource` dedicato del C#: un comando già lanciato va
    /// sempre verificato. Un task non strutturato non eredita l'annullamento.
    private func tryVerifyAfterCommand(_ warnings: inout [String]) async -> XcodeSnapshot? {
        let collector = self.collector
        let bounded = Task { () async throws -> XcodeSnapshot in
            try await withThrowingTaskGroup(of: XcodeSnapshot?.self) { group in
                group.addTask { try await collector.collect() }
                group.addTask {
                    try await Task.sleep(for: Self.verificationTimeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let snapshot = first else { throw CancellationError() }
                return snapshot
            }
        }

        do {
            return try await bounded.value
        } catch {
            warnings.append(String(localized: "Verifica successiva non disponibile: \(XcodeText.message(error))", bundle: .module))
            return nil
        }
    }

    private func tryFreeBytes() async -> Int64? {
        do {
            return try await measures.freeBytes()
        } catch {
            return nil
        }
    }

    private static func isInventoryReadable(_ snapshot: XcodeSnapshot, _ kind: XcodeResourceKind) -> Bool {
        !snapshot.warnings.contains { $0.resourceGroup == kind && $0.kind == .completenessFailure }
    }

    /// Il motivo per cui la risorsa non è più quella approvata, oppure `nil`.
    private static func compareIdentity(
        _ plan: XcodeConfirmedPlan,
        _ fresh: XcodeSnapshot,
        _ approved: XcodeCandidate,
        _ current: XcodeCandidate,
        _ deletedDevices: Set<[UInt8]>
    ) -> String? {
        if current.kind != approved.kind {
            return String(localized: "Il tipo della risorsa è cambiato dall'analisi.", bundle: .module)
        }

        if isFile(approved.kind) {
            guard let approvedPath = approved.path, let currentPath = current.path, XcodeText.same(approvedPath, currentPath),
                  let captured = plan.fileInventory[approved.key],
                  let observed = fresh.fileInventory[approved.key],
                  sameFileIdentity(captured, observed) else {
                return String(localized: "Il percorso o i metadati della cartella sono cambiati dall'analisi.", bundle: .module)
            }
            return nil
        }

        guard let oldId = approved.cliId.flatMap(XcodeUuid.canonical),
              let newId = current.cliId.flatMap(XcodeUuid.canonical), oldId == newId,
              XcodeText.same(approved.build, current.build),
              approved.kind != .runtime || XcodeText.same(approved.runtimeIdentifier, current.runtimeIdentifier) else {
            return String(localized: "L'identità o la build della risorsa è cambiata dall'analisi.", bundle: .module)
        }

        if approved.kind == .runtime {
            let expected = approved.dependentDeviceKeys.map(XcodeClassifier.normalizeSelectionKey)
                .filter { !deletedDevices.contains(XcodeText.caseInsensitiveKey($0)) }
                .map(XcodeText.ordinalKey)
                .sorted { $0.lexicographicallyPrecedes($1) }
            let actual = current.dependentDeviceKeys.map(XcodeClassifier.normalizeSelectionKey)
                .map(XcodeText.ordinalKey)
                .sorted { $0.lexicographicallyPrecedes($1) }
            if expected != actual {
                return String(localized: "Le dipendenze del runtime sono cambiate dall'analisi.", bundle: .module)
            }
        }

        return nil
    }

    private static func sameFileIdentity(_ captured: XcodeFileEntry, _ observed: XcodeFileEntry) -> Bool {
        captured.identity.logicalSizeBytes != nil
            && observed.identity.logicalSizeBytes != nil
            && XcodeText.same(captured.identity.canonicalPath, observed.identity.canonicalPath)
            && captured.identity.isDirectory == observed.identity.isDirectory
            && captured.identity.creationTime == observed.identity.creationTime
            && captured.identity.lastWriteTime == observed.identity.lastWriteTime
            && captured.identity.logicalSizeBytes == observed.identity.logicalSizeBytes
            && captured.item.isDirectory == observed.item.isDirectory
            && XcodeText.same(captured.item.path, observed.item.path)
            && XcodeText.same(captured.item.declaredRoot, observed.item.declaredRoot)
    }

    private static func sameKey(_ left: String, _ right: String) -> Bool {
        XcodeText.same(XcodeClassifier.normalizeSelectionKey(left), XcodeClassifier.normalizeSelectionKey(right))
    }

    private static func isFile(_ kind: XcodeResourceKind) -> Bool {
        kind == .derivedData || kind == .deviceSupport
    }

    private static func category(_ kind: XcodeResourceKind) -> String {
        switch kind {
        case .derivedData: "xcode-derived-data"
        case .deviceSupport: "xcode-device-support"
        case .device: "xcode-simulator-devices"
        case .runtime: "xcode-runtimes"
        }
    }

    private static func result(_ candidate: XcodeCandidate, _ outcome: XcodeItemOutcome, _ reason: String, _ bytes: Int64?) -> XcodeItemResult {
        XcodeItemResult(candidate: candidate, outcome: outcome, reason: reason, verifiedEstimatedBytes: bytes)
    }

    /// Lo storico conta solo le rimozioni verificate e, per ciascuna, la stima allocata fresca.
    private static func makeHistory(_ started: Date, _ duration: Duration, _ results: [XcodeItemResult]) -> CleanReport {
        let deleted = results.filter { $0.outcome == .deleted }
        let bytes = deleted.reduce(Int64(0)) { $0 + ($1.verifiedEstimatedBytes ?? 0) }

        var categories: [CategoryCleanResult] = []
        for result in deleted {
            let id = category(result.candidate.kind)
            let freed = result.verifiedEstimatedBytes ?? 0
            if let index = categories.firstIndex(where: { $0.categoryId == id }) {
                let existing = categories[index]
                categories[index] = CategoryCleanResult(categoryId: id, bytesFreed: existing.bytesFreed + freed, itemsDeleted: existing.itemsDeleted + 1)
            } else {
                categories.append(CategoryCleanResult(categoryId: id, bytesFreed: freed, itemsDeleted: 1))
            }
        }

        let errors = results.filter { $0.outcome != .deleted }
            .map { ScanError(path: $0.candidate.path ?? $0.candidate.name, kind: .other, message: $0.reason) }
        return CleanReport(
            startedAt: started,
            duration: duration,
            bytesFreed: bytes,
            itemsDeleted: deleted.count,
            itemsFailed: errors.count,
            categories: categories,
            errors: errors,
            deletedPaths: deleted.map { $0.candidate.path ?? $0.candidate.key })
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeCleanExecutorTests`
Expected: `Test run with 25 tests … passed` (23 portati, 2 sul diario), nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Xcode/XcodeCleanExecutorTests.cs` con:

```markdown
| Xcode/XcodeCleanExecutorTests.cs | 23 | Xcode/XcodeCleanExecutorTests.swift | 25 | 3 | 23 portati + 2 solo-Swift sul diario (spec §8.2): `journalReceivesVerifiedCliDeletionsAndIsForwardedToTheCleanEngine`, `realCleanEngineDeletesTheRevalidatedFolderAndJournalsIt`; `commandExceptionAndAbsentResourceIsNotCredited` verifica anche il motivo; gli annullamenti girano in un `Task` dedicato |
```

Tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Diario delle rimozioni Xcode | assente | cartelle registrate da `CleanEngine`; simulatori e runtime rimossi con verifica registrati con `path ?? key`, come in `deletedPaths` | voluta (spec §8.2) |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeCleanExecutor with the deletion journal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: `XcodeCleanupService`

Il punto d'ingresso della pagina Xcode: analisi con una verifica dello stato di Xcode che, nel dubbio, blocca le cartelle; esecuzione delegata all'esecutore con il diario.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Xcode/XcodeCleanupService.swift`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeCleanupServiceTests.swift` (in fondo)
- Reference: `src/MjmCleaner.Core/Xcode/XcodeCleanupService.cs`; `tests/MjmCleaner.Core.Tests/Xcode/XcodeCleanupServiceTests.cs` (`AnalyzeBlocksFilesWhenXcodeStateCannotBeVerified`)

**Interfaces:**
- Consumes: `XcodeInventoryCollecting` (Task 2), `XcodeClassifier`, `XcodeSelection` (Task 3), `XcodeRunningProbing` (Task 6), `XcodeCleanExecuting` (Task 9); `CleanProgress`, `CleanReport`, `DeletionRecording`, `Recorder` (piano 1).
- Produces:
  - `public protocol XcodeCleanupServing: Sendable` — `analyze() async throws -> XcodeSnapshot`, `execute(_ plan: XcodeConfirmedPlan, progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> XcodeCleanResult`
  - `public struct XcodeCleanupService: XcodeCleanupServing` — `init(collector: any XcodeInventoryCollecting, runningProbe: any XcodeRunningProbing, executor: any XcodeCleanExecuting)`

Il `RecordingExecutor` del C# lanciava `NotSupportedException` perché il test non lo chiamava; qui registra la chiamata, così il test solo Swift verifica anche l'inoltro del diario.

- [ ] **Step 1: Scrivere i test (falliscono)**

In fondo a `Tests/CleanerCoreTests/Xcode/XcodeCleanupServiceTests.swift` aggiungere:

```swift
extension XcodeCleanupServiceTests {
    private struct FixedCollector: XcodeInventoryCollecting {
        let snapshot: XcodeSnapshot

        func collect() async throws -> XcodeSnapshot { snapshot }
    }

    private struct FixedRunningProbe: XcodeRunningProbing {
        let value: XcodeRunningState

        func state() async throws -> XcodeRunningState { value }
    }

    /// Porting di `RecordingExecutor`, che in C# lanciava sempre: qui registra la chiamata, così
    /// il test solo Swift verifica anche l'inoltro del diario.
    private struct RecordingExecutor: XcodeCleanExecuting {
        let journals = Recorder<Bool>()

        func execute(_ plan: XcodeConfirmedPlan, progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> XcodeCleanResult {
            journals.append(journal != nil)
            let report = CleanReport(startedAt: .distantPast, duration: .zero, bytesFreed: 0, itemsDeleted: 0, itemsFailed: 0,
                                     categories: [], errors: [], deletedPaths: [])
            return XcodeCleanResult(historyReport: report, items: [], freeBytesBefore: nil, freeBytesAfter: nil, warnings: [])
        }
    }

    private struct NoJournal: DeletionRecording {
        func recordDeleted(_ path: String) {}
    }

    @Test func analyzeBlocksFilesWhenXcodeStateCannotBeVerified() async throws {
        let path = "/Users/test/Library/Developer/Xcode/DerivedData/App"
        let raw = XcodeSnapshot(candidates: [XcodeCandidate(key: "derived-data:" + path, kind: .derivedData, name: "App", path: path)], warnings: [])
        let service = XcodeCleanupService(collector: FixedCollector(snapshot: raw), runningProbe: FixedRunningProbe(value: .unknown), executor: RecordingExecutor())

        let analyzed = try await service.analyze()

        #expect(analyzed.candidates.count == 1)
        #expect(analyzed.candidates.first?.blockReason != nil)
    }

    // Solo Swift: l'esecuzione passa all'esecutore piano, avanzamento e diario.
    @Test func executeForwardsThePlanAndTheJournalToTheExecutor() async throws {
        let device = XcodeCandidate(key: "11111111-1111-4111-8111-111111111111", kind: .device, name: "iPhone",
                                    cliId: "11111111-1111-4111-8111-111111111111", state: "Shutdown")
        let plan = try XcodeSelection.confirm(
            XcodeSelection.preview(XcodeSnapshot(candidates: [device], warnings: []), selectedKeys: [device.key]), acknowledgeDependencies: true)
        let executor = RecordingExecutor()
        let service = XcodeCleanupService(collector: FixedCollector(snapshot: .empty), runningProbe: FixedRunningProbe(value: .notRunning), executor: executor)

        _ = await service.execute(plan, progress: nil, journal: NoJournal())

        #expect(executor.journals.values == [true])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeCleanupServiceTests`
Expected: errore di compilazione `cannot find 'XcodeCleanupService' in scope`.

- [ ] **Step 3: Implementare `XcodeCleanupService`**

`Sources/CleanerCore/Xcode/XcodeCleanupService.swift`:

```swift
/// `IXcodeCleanupService`: il punto d'ingresso della pagina Xcode.
public protocol XcodeCleanupServing: Sendable {
    func analyze() async throws -> XcodeSnapshot
    func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult
}

/// Unisce l'inventario corrente a una verifica dello stato di Xcode che, nel dubbio, blocca.
public struct XcodeCleanupService: XcodeCleanupServing {
    private let collector: any XcodeInventoryCollecting
    private let runningProbe: any XcodeRunningProbing
    private let executor: any XcodeCleanExecuting

    public init(collector: any XcodeInventoryCollecting, runningProbe: any XcodeRunningProbing, executor: any XcodeCleanExecuting) {
        self.collector = collector
        self.runningProbe = runningProbe
        self.executor = executor
    }

    public func analyze() async throws -> XcodeSnapshot {
        let snapshot = try await collector.collect()
        let state = try await runningProbe.state()
        if state == .unknown {
            let blocked = snapshot.candidates.map { candidate in
                guard candidate.kind == .derivedData || candidate.kind == .deviceSupport else { return candidate }
                var copy = candidate
                copy.blockReason = candidate.blockReason
                    ?? String(localized: "Impossibile verificare se Xcode è in esecuzione; ripeti l'analisi.", bundle: .module)
                return copy
            }
            return XcodeSnapshot(candidates: blocked, warnings: snapshot.warnings, fileInventory: snapshot.fileInventory)
        }

        return try XcodeClassifier.classify(snapshot, xcodeRunning: state == .running)
    }

    /// Il chiamante scarta il diario solo dopo aver scritto il log di sessione (spec §8.2).
    public func execute(
        _ plan: XcodeConfirmedPlan,
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> XcodeCleanResult {
        await executor.execute(plan, progress: progress, journal: journal)
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeCleanupServiceTests`
Expected: `Test run with 5 tests … passed` (3 dal Task 6, 2 nuovi), nessun warning.

- [ ] **Step 5: Registro di parità e commit**

Sostituire la riga `Xcode/XcodeCleanupServiceTests.cs` con:

```markdown
| Xcode/XcodeCleanupServiceTests.cs | 3 (3) | Xcode/XcodeCleanupServiceTests.swift | 5 (3) | 3 | 3 portati + 2 solo-Swift (`runningProbeIsUnknownWhenTheListingIsNotReliable`, `executeForwardsThePlanAndTheJournalToTheExecutor`); `RecordingExecutor` registra la chiamata invece di lanciare |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port XcodeCleanupService

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Integrazione sul filesystem reale, chiusura del piano

Il filesystem in memoria non ha date di nascita reali, collegamenti né la topologia `/var` → `/private/var`: questo task verifica la catena Xcode completa su una cartella temporanea con `LocalFileSystem`, `du` vero, `PathGuard` e `CleanEngine`, poi chiude il piano.

**Files:**
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/XcodeRealFileSystemTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: tutto il modulo Xcode (Task 1–10) e `TemporaryDirectory`, `Recorder` (piano 1).
- Produces: nessuna API nuova.

- [ ] **Step 1: Scrivere i test di integrazione**

`Tests/CleanerCoreTests/Integration/XcodeRealFileSystemTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

/// Catena Xcode reale su una cartella temporanea: scansione con `du` vero, identità letta da
/// APFS (data di nascita e di modifica), riverifica, cancellazione tramite `CleanEngine` e diario.
/// La home di prova vive sotto $TMPDIR, quindi la root passa per la risoluzione /var → /private/var.
struct XcodeRealFileSystemTests {
    private struct EmptyCli: XcodeCliInvoking {
        func readInventory() async throws -> XcodeSnapshot { .empty }
        func deleteDevice(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non usato") }
        func deleteRuntime(_ uuid: String) async throws -> ProcessResult { throw XcodeOperationError("non usato") }
    }

    /// Xcode può essere aperto sulla macchina che esegue i test: lo stato è fissato.
    private struct ClosedXcode: XcodeRunningProbing {
        func state() async throws -> XcodeRunningState { .notRunning }
    }

    private struct JournalRecorder: DeletionRecording {
        let paths = Recorder<String>()

        func recordDeleted(_ path: String) {
            paths.append(path)
        }
    }

    private struct Fixture {
        let tmp: TemporaryDirectory
        let derivedData: String
        let collector: XcodeInventoryCollector
        let executor: XcodeCleanExecutor

        init() throws {
            tmp = try TemporaryDirectory()
            let home = try tmp.directory("home")
            derivedData = try tmp.directory("home/Library/Developer/Xcode/DerivedData")
            let fs = LocalFileSystem()
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
            let sizes = XcodeSizeProbe(fileSystem: fs, runner: ProcessRunner(), links: links, homeDirectory: home)
            let scanner = XcodeFileScanner(
                fileSystem: fs, ruleScanner: RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock()),
                pathGuard: pathGuard, links: links, sizeProbe: sizes, homeDirectory: home)
            collector = XcodeInventoryCollector(cli: EmptyCli(), fileScanner: scanner)
            executor = XcodeCleanExecutor(
                cli: EmptyCli(), collector: collector, cleanEngine: CleanEngine(fileSystem: fs, pathGuard: pathGuard, clock: SystemWallClock()),
                measures: sizes, runningProbe: ClosedXcode(), clock: SystemWallClock())
        }

        func plan(for name: String) async throws -> XcodeConfirmedPlan {
            let snapshot = try await collector.collect()
            let key = try #require(snapshot.candidates.first { $0.name == name }?.key)
            return try XcodeSelection.confirm(XcodeSelection.preview(snapshot, selectedKeys: [key]), acknowledgeDependencies: true)
        }
    }

    @Test func derivedDataFolderIsScannedRevalidatedDeletedAndJournaled() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/App-abc/Build/Products/app", contents: String(repeating: "x", count: 100))
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/Keep-xyz/Index/store", contents: "y")
        let journal = JournalRecorder()

        let plan = try await fixture.plan(for: "App-abc")
        let result = await fixture.executor.execute(plan, progress: nil, journal: journal)

        let item = try #require(result.items.first)
        #expect(result.items.count == 1)
        #expect(item.outcome == .deleted)
        #expect((item.verifiedEstimatedBytes ?? 0) > 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.derivedData + "/App-abc"))
        #expect(FileManager.default.fileExists(atPath: fixture.derivedData + "/Keep-xyz/Index/store"))
        // Il diario riceve il percorso che CleanEngine ha eliminato: quello risolto dal guard.
        let journaled = try #require(journal.paths.values.first)
        #expect(journal.paths.values.count == 1)
        #expect(XcodeText.hasOrdinalPrefix(journaled, "/private/var/"))
        #expect(PathText.fileName(journaled) == "App-abc")
        #expect(result.historyReport.itemsDeleted == 1)
    }

    @Test func folderChangedAfterAnalysisIsSkippedAndKept() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/App-abc/Build/app", contents: "x")
        let journal = JournalRecorder()

        let plan = try await fixture.plan(for: "App-abc")
        try fixture.tmp.file("home/Library/Developer/Xcode/DerivedData/App-abc/nuovo.bin", contents: String(repeating: "z", count: 4096))
        let result = await fixture.executor.execute(plan, progress: nil, journal: journal)

        let item = try #require(result.items.first)
        #expect(item.outcome == .skipped)
        #expect(item.reason == "Il percorso o i metadati della cartella sono cambiati dall'analisi.")
        #expect(FileManager.default.fileExists(atPath: fixture.derivedData + "/App-abc/Build/app"))
        #expect(journal.paths.values.isEmpty)
    }
}
```

- [ ] **Step 2: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter XcodeRealFileSystemTests`
Expected: `Test run with 2 tests … passed`. Se il prefisso `/private/var/` non corrisponde, verificare con `ls -ld /var` che `/var` sia un collegamento a `private/var` (vero su ogni macOS di serie) prima di toccare il codice.

- [ ] **Step 3: Eseguire l'intera suite**

Run (da `swift/MjmCleanerKit`): `swift test -Xswiftc -warnings-as-errors`
Expected: tutti i test passano, nessun warning. Conteggio atteso: 242 (piano 1) + i test del piano 2 + 107 di questo piano (6 + 9 + 15 + 20 + 9 + 9 + 8 + 2 + 25 + 2 + 2). Senza il piano 2 sarebbero **349**.

- [ ] **Step 4: Verificare i vincoli globali**

Run (da `swift/MjmCleanerKit`):

```bash
grep -rnE 'try!|as!|import (SwiftUI|AppKit)' Sources/CleanerCore || echo "nessuna violazione"
grep -rnE '[A-Za-z0-9_\)\]]!([^=]|$)' Sources/CleanerCore || echo "nessun forced unwrap"
grep -rnE '\.(hasPrefix|hasSuffix|lowercased|uppercased)\(|exitCode == -1' Sources/CleanerCore/Xcode || echo "nessun confronto non ordinale"
grep -rn '"xcrun"' Sources/CleanerCore/Xcode || echo "xcrun solo per percorso assoluto"
git diff --name-only "$(git log --format=%H --grep='add volume free space and creation date to FileSystem' -1)~1" -- Sources/CleanerCore/Docker Tests/CleanerCoreTests/Docker
```

Expected: le prime quattro righe stampano il messaggio di nessuna violazione; l'ultima non stampa nulla (nessun file Docker toccato da questo piano). Il secondo pattern può segnalare falsi positivi dentro stringhe o commenti: controllare a mano ogni riga segnalata. Un `!` di negazione logica (`!x`) non corrisponde al pattern.

- [ ] **Step 5: Chiudere il registro di parità**

Sezione «Test solo Swift», aggiungere:

```markdown
| Integration/XcodeRealFileSystemTests.swift | 2 | catena Xcode reale: `du`, identità APFS (nascita e modifica), riverifica, `CleanEngine` e diario; una cartella cambiata dopo l'analisi resta al suo posto |
```

Dopo il paragrafo «Doppi e utilità di test …» della tabella `MjmCleaner.Core.Tests`, aggiungere:

```markdown
Piano 3: i doppi dei test Xcode C# erano classi private e restano annidati nei test Swift; `Xcode/XcodeFixtures.swift` legge dal disco le fixture copiate byte per byte in `Xcode/Fixtures/`.
```

Verificare che le nove righe `Xcode/…Tests.cs` abbiano file Swift, conteggio e piano 3 compilati, e aggiungere in testa al file, sotto la riga del piano 1 e con la data del giorno in formato AAAA-MM-GG, la riga: «Piano 3 completato il AAAA-MM-GG: 74 prove C# Xcode portate (+ 33 nuove), suite Swift verde.»

- [ ] **Step 6: Commit**

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "test(swift): verify the real-filesystem Xcode chain and close plan 3

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Dopo il piano 3

Il piano 4 (Features e app SwiftUI) compone il grafo Xcode in `AppEnvironment` come `AppServices.CreateAsync`: `XcodeCli(runner: ProcessRunner(), binaryPath: XcodeCli.locateBinary(LocalFileSystem()))`, `XcodeSizeProbe`, `XcodeFileScanner` sullo stesso `RuleScanner` e `PathGuard` della pulizia, `XcodeInventoryCollector`, `XcodeRunningProbe`, `XcodeCleanExecutor` con un proprio `CleanEngine`, infine `XcodeCleanupService`. Per il diario: aprire il `PendingJournal` prima di `execute`, passarlo, scrivere il log di sessione con `historyReport` e chiamare `discard` solo se la scrittura è riuscita (registro del piano 1, nota al Task 11).
