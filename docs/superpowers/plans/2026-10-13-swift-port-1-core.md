# Porting Swift — Piano 1: fondamenta e Core

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Creare il Swift Package `swift/MjmCleanerKit` con il modulo `CleanerCore`, che porta 1:1 la logica di `src/MjmCleaner.Core` esclusi Docker e Xcode (Platform, Safety, Settings, Categories, Scanning, Cleaning, History, Diagnostics), con i relativi 176 test C# portati in Swift Testing e verdi.

**Architecture:** Un package SwiftPM locale con un target `CleanerCore` (nessuna dipendenza da SwiftUI/AppKit), un target di sistema `CZlib` per gzip e un target di test. L'accesso al filesystem, ai collegamenti simbolici, all'orologio e ai processi passa da quattro protocolli (`FileSystem`, `LinkInspecting`, `WallClock`, `ProcessRunning`): sono le stesse giunture dei test C# e quelle che la fase 2 userà per la sandbox. Ogni classe C# ha la controparte Swift con lo stesso nome e la stessa responsabilità; il comportamento, non la sintassi, è ciò che si porta.

**Tech Stack:** Swift 6 language mode, `swift-tools-version: 6.2`, macOS 15, Swift Testing, `SQLite3` e zlib di sistema, `Synchronization.Mutex`. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`

Questo è il **primo di quattro piani** in sequenza: (1) fondamenta e Core, (2) Docker e Xcode, (3) Features e app SwiftUI, (4) verifica, release e rimozione del C#. Ciascuno produce software funzionante e testato. I piani 2–4 si scrivono a piano precedente completato, sul codice reale.

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
- Lavoro sul branch `feat/swift-port`.

---

## Convenzioni di porting (valgono per ogni task)

### Tipi

| C# | Swift |
|---|---|
| `record` immutabile | `struct` `Sendable, Equatable` con `public init` esplicito |
| `IReadOnlyList<T>` | `[T]` |
| `long` / `int` | `Int64` / `Int` |
| `TimeSpan` usato come età minima | `TimeInterval` (secondi) |
| `TimeSpan` usato come durata misurata | `Duration` |
| `DateTimeOffset` / `DateTime` UTC | `Date` |
| `string?` | `String?` |
| `ArgumentException` dal costruttore | `init(...) throws` che lancia `InvalidConfiguration` |
| `bool Metodo(x, out string reason)` | `func metodo(_ x) -> String?` (motivo, oppure `nil` se permesso) |
| `CancellationToken` | cancellazione cooperativa: `try Task.checkCancellation()` dove il C# chiama `ThrowIfCancellationRequested()`, `Task.isCancelled` dove legge `IsCancellationRequested` |
| `IProgress<T>?` | `(@Sendable (T) -> Void)?` |
| `TimeProvider` | `any WallClock` |
| `IFileSystem` | `any FileSystem` |
| `Path.GetFileName` / `GetDirectoryName` / `Combine` / `TrimEnd('/')` | `PathText.fileName` / `parent` / `join` / `trimmingTrailingSlashes` |
| `StringComparison.OrdinalIgnoreCase` su percorsi e nomi | `PathText.equalsIgnoringCase`, `hasPrefixIgnoringCase`, `isSameOrUnder` |
| `FileSystemName.MatchesSimpleExpression(p, n, ignoreCase: true)` | `SimpleGlob.matches(p, n)` |

### Nomi dei protocolli

| C# | Swift (protocollo) | Swift (implementazione) |
|---|---|---|
| `IFileSystem` | `FileSystem` | `LocalFileSystem` |
| `ILinkInspector` | `LinkInspecting` | `FileSystemLinkInspector` |
| `TimeProvider` | `WallClock` | `SystemWallClock` |
| `IProcessRunner` | `ProcessRunning` | `ProcessRunner` |
| `IPathGuard` | `PathGuarding` | `PathGuard` |
| `IScanEngine` | `ScanPerforming` | `ScanEngine` |
| `ICleanEngine` | `CleanPerforming` | `CleanEngine` |
| `IHistoryStore` | `HistoryStoring` | `HistoryStore` |
| `ISessionLogWriter` | `SessionLogWriting` | `SessionLogWriter` |
| `ISettingsStore` | `SettingsStoring` | `SettingsStore` |
| `IRunningAppsProbe` | `RunningAppsProbing` | `RunningAppsProbe` |

### Test

| xUnit | Swift Testing |
|---|---|
| `public class XTests` | `struct XTests` |
| `[Fact] public void Nome()` | `@Test func nome()` |
| `[Theory] [InlineData(a)] [InlineData(b)] void Nome(string x)` | `@Test(arguments: [a, b]) func nome(x: String)` |
| `[InlineData(null)]` | argomento `nil` in un array tipizzato `[String?]` |
| `Assert.True(x)` / `Assert.False(x)` | `#expect(x)` / `#expect(!x)` |
| `Assert.Equal(a, b)` | `#expect(b == a)` |
| `Assert.Contains(sub, text)` | `#expect(text.contains(sub))` |
| `Assert.Contains(list, i => …)` | `#expect(list.contains { … })` |
| `Assert.Single(list)` / `.Single()` | `let item = try #require(list.first); #expect(list.count == 1)` |
| `Assert.Empty(list)` | `#expect(list.isEmpty)` |
| `Assert.Throws<ArgumentException>(…)` | `#expect(throws: InvalidConfiguration.self) { try … }` |
| `await Assert.ThrowsAnyAsync<OperationCanceledException>(…)` | `await #expect(throws: CancellationError.self) { try await … }` |
| `MockFileSystem` | `InMemoryFileSystem` (Task 3) |
| `new MockFileData(new byte[n]) { LastWriteTime = t, LastAccessTime = t }` | `fs.addFile(path, size: n, stamp: t)` |
| `new MockFileData("testo")` | `fs.addFile(path, text: "testo")` |
| `fs.Directory.SetLastWriteTimeUtc(d, t)` + `SetLastAccessTimeUtc(d, t)` | `fs.setTimes(d, lastWrite: t, lastAccess: t)` |
| `TestTimeProvider(now)` | `FixedWallClock(now: now)` |
| `new DateTimeOffset(2026, 9, 15, 12, 0, 0, TimeSpan.Zero)` | `utc(2026, 9, 15, 12)` (Task 3) |
| `TimeSpan.FromDays(n)` | `days(n)` (Task 3) |
| `CancellationTokenSource` annullato prima della chiamata | `Task { cancelCurrentTask(); return try await … }` (Task 3) |
| `IProgress` che annulla alla prima segnalazione | `progress: { _ in cancelCurrentTask() }` |

I commenti C# che motivano un test si portano sopra il test Swift corrispondente. Un test C# che verifica un comportamento impossibile in Swift per costruzione (per esempio un argomento `null` dove il tipo Swift non è opzionale) si porta nella forma equivalente indicata nel task, e il registro di parità ne riporta la ragione.

### Fatti misurati su .NET 10 (2026-10-13) che il porting replica

Misurati con una console usa e getta, non presente nel repository:

- `FileInfo`/`DirectoryInfo` leggono **il collegamento stesso** (`lstat`): `Length` di un collegamento è la lunghezza del percorso di destinazione, le date sono quelle del collegamento. Il commento in `RuleScanner.cs` secondo cui «il timestamp letto è quello del bersaglio» è impreciso; in Swift va corretto.
- Su un percorso inesistente `LastWriteTimeUtc`/`LastAccessTimeUtc` non lanciano: restituiscono la sentinella `1601-01-01`. `Length` invece lancia `FileNotFoundException`, anche su una cartella.
- `File.Exists(collegamento a cartella)` = falso; `File.Exists(collegamento interrotto)` = vero; `Directory.Exists(collegamento a cartella)` = vero.
- `File.Delete` su un percorso inesistente non lancia.
- `Directory.Delete(path, recursive: true)` non segue i collegamenti e lancia l'errore del figlio che non riesce a eliminare (es. `UnauthorizedAccessException` su `sub/x.txt`).
- `ResolveLinkTarget(returnFinalTarget: true).FullName` risolve una destinazione relativa rispetto alla cartella del collegamento con normalizzazione testuale (`dir/../dir` → `dir`); per un collegamento interrotto restituisce comunque il percorso di destinazione.
- `Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)` **scende** nei collegamenti a cartelle. Questo è l'unico punto in cui il porting diverge di proposito (Task 9).

---

## Mappa dei file

```
swift/MjmCleanerKit/
├── Package.swift                                        Task 1
├── Sources/CZlib/module.modulemap, shim.h                Task 1
├── Sources/CleanerCore/
│   ├── Resources/Localizable.xcstrings                  Task 1
│   ├── Platform/
│   │   ├── PathText.swift                               Task 1
│   │   ├── SimpleGlob.swift                             Task 1
│   │   ├── FileSystem.swift                             Task 2
│   │   ├── LocalFileSystem.swift                        Task 2
│   │   ├── LinkInspecting.swift                         Task 2
│   │   ├── WallClock.swift                              Task 2
│   │   ├── InvalidConfiguration.swift                   Task 4
│   │   ├── Gzip.swift                                   Task 11
│   │   └── ProcessRunner.swift                          Task 12
│   ├── Safety/CanonicalPath.swift, DenyList.swift, PathGuard.swift          Task 4
│   ├── Settings/AppearancePreference.swift, CleanerSettings.swift,
│   │            AppPaths.swift, SettingsStore.swift                         Task 5
│   ├── Categories/CleanupRule.swift, CleanupCategory.swift,
│   │              PathExpander.swift, CategoryCatalog.swift                 Task 6
│   ├── Scanning/ScanModels.swift, RuleScanner.swift                         Task 7
│   ├── Scanning/ScanEngine.swift                                            Task 8
│   ├── Cleaning/CleanModels.swift, CleanEngine.swift, ConfirmationRows.swift Task 9
│   ├── History/SQLiteDatabase.swift, HistoryStore.swift                     Task 10
│   ├── History/SessionLogWriter.swift, PendingJournal.swift                 Task 11
│   └── Diagnostics/RunningAppsProbe.swift                                   Task 13
└── Tests/CleanerCoreTests/
    ├── Support/   (doppi e utilità di test)                                 Task 2–3
    ├── Platform/  Safety/  Settings/  Categories/  Scanning/
    ├── Cleaning/  History/  Diagnostics/  Integration/
docs/superpowers/porting/2026-10-13-parity.md                                Task 1, aggiornato da ogni task
```

---

### Task 1: Scaffold del package, `PathText`, `SimpleGlob` e registro di parità

**Files:**
- Modify: `.gitignore` (in fondo)
- Create: `swift/MjmCleanerKit/Package.swift`
- Create: `swift/MjmCleanerKit/Sources/CZlib/module.modulemap`
- Create: `swift/MjmCleanerKit/Sources/CZlib/shim.h`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Resources/Localizable.xcstrings`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/PathText.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/SimpleGlob.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/PathTextTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/SimpleGlobTests.swift`
- Create: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: niente.
- Produces:
  - `public enum PathText` con `static func fileName(_:) -> String`, `parent(_:) -> String?`, `join(_:_:) -> String`, `trimmingTrailingSlashes(_:) -> String`, `normalize(_:) -> String`, `equalsIgnoringCase(_:_:) -> Bool`, `hasPrefixIgnoringCase(_:_:) -> Bool`, `isSameOrUnder(_:_:) -> Bool`
  - `public enum SimpleGlob` con `static func matches(_ pattern: String, _ name: String) -> Bool`
  - prodotto SwiftPM `CleanerCore`, target `CZlib`, target di test `CleanerCoreTests`

- [ ] **Step 1: Aggiungere le esclusioni Swift a `.gitignore`**

Aggiungere in fondo a `.gitignore`:

```gitignore

# Swift
swift/**/.build/
swift/**/.swiftpm/
swift/**/xcuserdata/
swift/**/*.xcuserstate
```

- [ ] **Step 2: Creare `Package.swift`**

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
            dependencies: ["CleanerCore"]
        ),
    ]
)
```

- [ ] **Step 3: Creare il module map di zlib e il catalogo stringhe**

`Sources/CZlib/module.modulemap`:

```
module CZlib [system] {
    header "shim.h"
    link "z"
    export *
}
```

`Sources/CZlib/shim.h`:

```c
#include <zlib.h>
```

`Sources/CleanerCore/Resources/Localizable.xcstrings` (vuoto: la lingua di sviluppo è l'italiano e `String(localized:)` restituisce la chiave stessa; le voci le estrae Xcode quando servirà una traduzione):

```json
{
  "sourceLanguage" : "it",
  "strings" : {
  },
  "version" : "1.0"
}
```

- [ ] **Step 4: Scrivere i test di `PathText` e `SimpleGlob` (falliscono)**

`Tests/CleanerCoreTests/Platform/PathTextTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct PathTextTests {
    @Test(arguments: [
        ("/a/b", "b"), ("/a/b/", ""), ("/", ""), ("nome", "nome"), ("/Users/tester/.ssh", ".ssh"),
    ])
    func fileNameMatchesDotNetGetFileName(path: String, expected: String) {
        #expect(PathText.fileName(path) == expected)
    }

    @Test(arguments: [
        ("/a/b", "/a" as String?), ("/a", "/"), ("/", nil), ("", nil), ("/a/b/", "/a/b"), ("relativo", ""),
    ])
    func parentMatchesDotNetGetDirectoryNameOnUnix(path: String, expected: String?) {
        #expect(PathText.parent(path) == expected)
    }

    @Test(arguments: [
        ("/a", "b", "/a/b"), ("/a/", "b", "/a/b"), ("/a", "/b", "/b"), ("", "b", "b"), ("/a", "", "/a"), ("/", "b", "/b"),
    ])
    func joinMatchesDotNetCombine(base: String, component: String, expected: String) {
        #expect(PathText.join(base, component) == expected)
    }

    @Test(arguments: [("/a/b///", "/a/b"), ("///", ""), ("/a", "/a"), ("", "")])
    func trimmingTrailingSlashesMatchesTrimEnd(path: String, expected: String) {
        #expect(PathText.trimmingTrailingSlashes(path) == expected)
    }

    @Test(arguments: [
        ("/a/./b", "/a/b"), ("/a/b/../c", "/a/c"), ("//a//b//", "/a/b"), ("/../a", "/a"), ("/a/dir/../dir", "/a/dir"), ("/", "/"),
    ])
    func normalizeResolvesDotSegmentsTextually(path: String, expected: String) {
        #expect(PathText.normalize(path) == expected)
    }

    @Test func comparisonsIgnoreCase() {
        #expect(PathText.equalsIgnoringCase("/Users/TESTER", "/users/tester"))
        #expect(!PathText.equalsIgnoringCase("/a", "/ab"))
        #expect(PathText.hasPrefixIgnoringCase("/Users/Tester/Documents", "/users/tester/"))
        #expect(PathText.hasPrefixIgnoringCase("/qualunque", ""))
        #expect(!PathText.hasPrefixIgnoringCase("/a", "/ab"))
    }

    @Test func isSameOrUnderRespectsSegmentBoundaries() {
        #expect(PathText.isSameOrUnder("/Library/Caches", "/library/caches"))
        #expect(PathText.isSameOrUnder("/Library/Caches/x", "/Library/Caches"))
        #expect(!PathText.isSameOrUnder("/Library/CachesExtra", "/Library/Caches"))
    }
}
```

`Tests/CleanerCoreTests/Platform/SimpleGlobTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct SimpleGlobTests {
    @Test(arguments: [
        ("*", "qualunque.txt", true),
        ("*", "", true),
        ("bin", "BIN", true),
        ("bin", "binary", false),
        ("*.csproj", "App.CSPROJ", true),
        ("*.csproj", "App.csproj.user", false),
        ("?.txt", "a.txt", true),
        ("?.txt", "ab.txt", false),
        ("a*b*c", "aXXbYYc", true),
        ("a*b*c", "aXXbYY", false),
        ("[ab].txt", "a.txt", false),
        ("[ab].txt", "[ab].txt", true),
        ("", "", true),
        ("", "x", false),
    ])
    func matchesLikeDotNetSimpleExpression(pattern: String, name: String, expected: Bool) {
        #expect(SimpleGlob.matches(pattern, name) == expected)
    }
}
```

- [ ] **Step 5: Verificare che falliscano**

Run (da `swift/MjmCleanerKit`): `swift test -Xswiftc -warnings-as-errors --filter "PathTextTests|SimpleGlobTests"`
Expected: errore di compilazione `cannot find 'PathText' in scope` (e lo stesso per `SimpleGlob`).

- [ ] **Step 6: Implementare `PathText`**

`Sources/CleanerCore/Platform/PathText.swift`:

```swift
import Foundation

/// Operazioni testuali sui percorsi POSIX con la stessa semantica dei metodi .NET su Unix usati
/// dall'app C# (`Path.GetFileName`, `Path.GetDirectoryName`, `Path.Combine`, `TrimEnd('/')`,
/// `Path.GetFullPath`) e il confronto `OrdinalIgnoreCase`. Nessuna funzione tocca il filesystem.
public enum PathText {
    /// Come `Path.GetFileName`: il testo dopo l'ultimo "/", vuoto se il percorso termina con "/".
    public static func fileName(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// Come `Path.GetDirectoryName` su Unix: `nil` per "/" e per la stringa vuota, "/" per un
    /// figlio diretto della radice, altrimenti il testo prima dell'ultimo "/". Un percorso
    /// relativo senza "/" restituisce la stringa vuota.
    public static func parent(_ path: String) -> String? {
        if path.isEmpty || path == "/" { return nil }
        guard let slash = path.lastIndex(of: "/") else { return "" }
        if slash == path.startIndex { return "/" }
        return String(path[..<slash])
    }

    /// Come `Path.Combine` con due argomenti: un secondo argomento assoluto vince.
    public static func join(_ base: String, _ component: String) -> String {
        if component.hasPrefix("/") || base.isEmpty { return component }
        if component.isEmpty { return base }
        return base.hasSuffix("/") ? base + component : base + "/" + component
    }

    /// Come `TrimEnd('/')`: "///" diventa la stringa vuota, esattamente come in .NET.
    public static func trimmingTrailingSlashes(_ path: String) -> String {
        var result = Substring(path)
        while result.hasSuffix("/") { result = result.dropLast() }
        return String(result)
    }

    /// Normalizzazione testuale di un percorso assoluto, come `Path.GetFullPath` su Unix:
    /// separatori ripetuti ridotti, segmenti "." eliminati, ".." risolto sul segmento precedente
    /// SENZA seguire i collegamenti. Serve solo a riprodurre la `FullName` che .NET restituiva per
    /// la destinazione di un collegamento simbolico: non va mai usata per validare un percorso da
    /// eliminare (vedi `CanonicalPath`, che i segmenti "." e ".." li rifiuta).
    public static func normalize(_ absolutePath: String) -> String {
        var segments: [Substring] = []
        for segment in absolutePath.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty { segments.removeLast() }
            default:
                segments.append(segment)
            }
        }
        return "/" + segments.joined(separator: "/")
    }

    /// Confronto ordinale senza distinzione fra maiuscole e minuscole (`OrdinalIgnoreCase`): APFS
    /// è case-insensitive nella configurazione predefinita, quindi "~/documents" e "~/Documents"
    /// sono la stessa cartella.
    public static func equalsIgnoringCase(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .literal]) == .orderedSame
    }

    /// `StartsWith(prefix, OrdinalIgnoreCase)`; come in .NET, il prefisso vuoto è sempre presente.
    public static func hasPrefixIgnoringCase(_ text: String, _ prefix: String) -> Bool {
        if prefix.isEmpty { return true }
        return text.range(of: prefix, options: [.anchored, .caseInsensitive, .literal]) != nil
    }

    /// Vero se `path` coincide con `ancestor` o vi è contenuto, rispettando il confine di
    /// segmento ("/Library/CachesExtra" non è sotto "/Library/Caches").
    public static func isSameOrUnder(_ path: String, _ ancestor: String) -> Bool {
        equalsIgnoringCase(path, ancestor) || hasPrefixIgnoringCase(path, ancestor + "/")
    }
}
```

- [ ] **Step 7: Implementare `SimpleGlob`**

`Sources/CleanerCore/Platform/SimpleGlob.swift`:

```swift
/// Equivalente di `FileSystemName.MatchesSimpleExpression(pattern, name, ignoreCase: true)`:
/// `*` corrisponde a zero o più caratteri, `?` esattamente a uno, nessun altro carattere è
/// speciale. Niente `fnmatch`, che interpreterebbe anche `[…]` e `\` e accetterebbe nomi che il
/// C# rifiutava.
public enum SimpleGlob {
    public static func matches(_ pattern: String, _ name: String) -> Bool {
        let pattern = Array(pattern.lowercased())
        let name = Array(name.lowercased())
        var patternIndex = 0
        var nameIndex = 0
        var starIndex: Int?
        var starMatch = 0

        while nameIndex < name.count {
            if patternIndex < pattern.count,
               pattern[patternIndex] == "?" || pattern[patternIndex] == name[nameIndex] {
                patternIndex += 1
                nameIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                starMatch = nameIndex
                patternIndex += 1
            } else if let star = starIndex {
                patternIndex = star + 1
                starMatch += 1
                nameIndex = starMatch
            } else {
                return false
            }
        }

        while patternIndex < pattern.count, pattern[patternIndex] == "*" {
            patternIndex += 1
        }
        return patternIndex == pattern.count
    }
}
```

- [ ] **Step 8: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "PathTextTests|SimpleGlobTests"`
Expected: `Test run with 8 tests … passed`, nessun warning.

- [ ] **Step 9: Creare il registro di parità**

`docs/superpowers/porting/2026-10-13-parity.md`:

```markdown
# Registro di parità del porting Swift

Spec: `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` §9.3.

Ogni file di test C# ha il suo corrispondente Swift, oppure la ragione per cui non ce l'ha.
«Prove» conta i metodi `[Fact]`/`[Theory]`; fra parentesi i casi `InlineData`.

## MjmCleaner.Core.Tests

| File C# | Prove | File Swift | Portate | Piano | Note |
|---|---|---|---|---|---|
| Categories/CategoryCatalogTests.cs | 9 | — | — | 1 | |
| Categories/PathExpanderTests.cs | 8 (14) | — | — | 1 | |
| Cleaning/CleanEngineTests.cs | 18 | — | — | 1 | |
| Cleaning/ConfirmationRowsTests.cs | 7 | — | — | 1 | |
| Diagnostics/RunningAppsProbeTests.cs | 12 (12) | — | — | 1 | |
| History/HistoryStoreTests.cs | 6 | — | — | 1 | |
| History/SessionLogWriterTests.cs | 6 | — | — | 1 | |
| Safety/DenyListTests.cs | 17 (89) | — | — | 1 | |
| Safety/PathGuardTests.cs | 39 (13) | — | — | 1 | |
| Scanning/MatchingDirsTests.cs | 16 | — | — | 1 | |
| Scanning/RuleScannerTests.cs | 22 | — | — | 1 | |
| Scanning/ScanEngineTests.cs | 6 | — | — | 1 | |
| Settings/SettingsStoreTests.cs | 10 (16) | — | — | 1 | |
| Docker/DiskUsageProbeTests.cs | 6 (2) | — | — | 2 | |
| Docker/DockerClassifierTests.cs | 25 (16) | — | — | 2 | |
| Docker/DockerCleanExecutorTests.cs | 15 (6) | — | — | 2 | |
| Docker/DockerCleanupServiceTests.cs | 2 | — | — | 2 | |
| Docker/DockerCliTests.cs | 11 (7) | — | — | 2 | |
| Docker/DockerConfirmationGroupsTests.cs | 7 | — | — | 2 | |
| Docker/DockerInventoryCollectorTests.cs | 7 | — | — | 2 | |
| Docker/DockerJsonTests.cs | 9 | — | — | 2 | |
| Docker/DockerSizeTests.cs | 2 (12) | — | — | 2 | |
| Docker/ImageNameTests.cs | 2 (10) | — | — | 2 | |
| Docker/ProjectReferenceScannerTests.cs | 13 (4) | — | — | 2 | |
| Xcode/XcodeClassifierTests.cs | 6 | — | — | 2 | |
| Xcode/XcodeCleanExecutorTests.cs | 23 | — | — | 2 | |
| Xcode/XcodeCleanupServiceTests.cs | 3 (3) | — | — | 2 | |
| Xcode/XcodeCliTests.cs | 6 (4) | — | — | 2 | |
| Xcode/XcodeFileScannerTests.cs | 7 | — | — | 2 | |
| Xcode/XcodeInventoryCollectorTests.cs | 2 | — | — | 2 | |
| Xcode/XcodeJsonTests.cs | 15 | — | — | 2 | |
| Xcode/XcodeSelectionTests.cs | 9 | — | — | 2 | |
| Xcode/XcodeSizeProbeTests.cs | 3 | — | — | 2 | |

Doppi e utilità di test (nessuna prova propria): `Safety/FakeLinkInspector.cs`, `Scanning/TestTimeProvider.cs`, `Scanning/VanishingFileSystem.cs`, `Scanning/VanishingChildFileSystem.cs`, `Scanning/UnreadableDirectoryFileSystem.cs`, `Cleaning/ThrowingOnDeleteFileSystem.cs` (piano 1); `Docker/DockerFixtures.cs`, `Docker/FakeDockerCli.cs` (piano 2); `GlobalUsings.cs` (nessun equivalente necessario).

## MjmCleaner.App.Tests

| File C# | Prove | File Swift | Portate | Piano | Note |
|---|---|---|---|---|---|
| AccessibilityTests.cs | 3 | — | — | 3 | |
| ApplicationIdentityTests.cs | 1 | — | — | 3 | |
| ChooseStepTests.cs | 5 (13) | — | — | 3 | |
| HistoryTests.cs | 4 (3) | — | — | 3 | |
| HistoryViewTests.cs | 5 | — | — | 3 | |
| MainWindowLayoutTests.cs | 3 | — | — | 3 | |
| NavigationLockTests.cs | 3 | — | — | 3 | |
| SettingsOpeningTests.cs | 5 | — | — | 3 | |
| SettingsViewModelTests.cs | 8 | — | — | 3 | |
| SettingsWindowTests.cs | 10 (3) | — | — | 3 | |
| SidebarSectionTests.cs | 3 | — | — | 3 | |
| ThemeTests.cs | 7 (9) | — | — | 3 | |
| ToolPagesLayoutTests.cs | 4 (12) | — | — | 3 | |
| Xcode/XcodeReportViewModelTests.cs | 3 | — | — | 3 | |
| Xcode/XcodeViewLayoutTests.cs | 4 | — | — | 3 | |
| Xcode/XcodeViewModelTests.cs | 10 | — | — | 3 | |

Utilità (nessuna prova propria): `TestAppBuilder.cs`, `TestHome.cs` (piano 3).

## Differenze rispetto al C#

| Punto | C# | Swift | Tipo |
|---|---|---|---|

## Candidati a miglioramento (notati, non applicati)

Spec §12: si annotano qui e non si cambiano durante il porting.

| Punto | Comportamento attuale (replicato) | Proposta |
|---|---|---|
```

- [ ] **Step 10: Commit**

```bash
git add .gitignore swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): scaffold MjmCleanerKit with path and glob helpers

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Giunture della piattaforma: `FileSystem`, `LocalFileSystem`, `LinkInspecting`, `WallClock`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/LinkInspecting.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/WallClock.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/TemporaryDirectory.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/LocalFileSystemTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/FileSystemLinkInspectorTests.swift`

**Interfaces:**
- Consumes: `PathText` (Task 1).
- Produces:
  - `public struct FileSystemError: Error, Equatable, Sendable, CustomStringConvertible` — `init(code: Int32, path: String)`, `let code: Int32`, `let path: String`, `var message: String`
  - `public enum FileItemKind { case file, directory, symbolicLink, other }`
  - `public struct FileItemInfo: Sendable, Equatable` — `kind`, `size: Int64`, `lastWrite: Date`, `lastAccess: Date`, `newestStamp: Date`
  - `public protocol FileSystem: Sendable` — `directoryExists(_:) -> Bool`, `fileExists(_:) -> Bool`, `contentsOfDirectory(_:) throws -> [String]`, `itemInfo(_:) throws -> FileItemInfo`, `deleteFile(_:) throws`, `deleteDirectoryRecursively(_:) throws`, `readData(_:) throws -> Data`, `writeData(_:_:) throws`, `appendData(_:_:) throws`, `createDirectory(_:) throws`; in estensione `fileLength(_:) throws -> Int64`, `readText(_:) throws -> String`, `writeText(_:_:) throws`
  - `public struct LocalFileSystem: FileSystem` — `init()`
  - `public protocol LinkInspecting: Sendable` — `isSymbolicLink(_:) -> Bool`, `resolveLinkTarget(_:) -> String?`
  - `public struct FileSystemLinkInspector: LinkInspecting` — `init()`
  - `public protocol WallClock: Sendable` — `var now: Date { get }`; `public struct SystemWallClock: WallClock`
  - test: `struct TemporaryDirectory` — `init() throws`, `let path: String`, `func file(_ relative: String, contents: String = "") throws -> String`, `func directory(_ relative: String) throws -> String`, `func symlink(_ relative: String, to destination: String) throws -> String`, `func remove()`

- [ ] **Step 1: Scrivere l'utilità `TemporaryDirectory`**

`Tests/CleanerCoreTests/Support/TemporaryDirectory.swift`:

```swift
import Darwin
import Foundation

/// Cartella temporanea reale per i test di integrazione: il filesystem simulato non riproduce
/// collegamenti simbolici, permessi né il comportamento di APFS.
struct TemporaryDirectory {
    let path: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        path = (base.hasSuffix("/") ? base : base + "/") + "mjm-cleaner-test-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    @discardableResult
    func file(_ relative: String, contents: String = "") throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: URL(fileURLWithPath: full))
        return full
    }

    @discardableResult
    func directory(_ relative: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        return full
    }

    @discardableResult
    func symlink(_ relative: String, to destination: String) throws -> String {
        let full = path + "/" + relative
        try FileManager.default.createDirectory(
            atPath: (full as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: full, withDestinationPath: destination)
        return full
    }

    /// Ripristina i permessi prima di rimuovere: alcuni test tolgono la scrittura a una cartella.
    func remove() {
        if let enumerator = FileManager.default.enumerator(atPath: path) {
            for case let relative as String in enumerator {
                chmod(path + "/" + relative, 0o755)
            }
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}
```

- [ ] **Step 2: Scrivere i test di integrazione (falliscono)**

`Tests/CleanerCoreTests/Platform/LocalFileSystemTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Ogni test riproduce un comportamento misurato su .NET 10 (vedi «Fatti misurati» nel piano):
/// il porting deve vedere il filesystem come lo vedeva l'app C#.
struct LocalFileSystemTests {
    private let fs = LocalFileSystem()

    @Test func directoryExistsFollowsLinksLikeDotNet() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("dir")
        let link = try tmp.symlink("link", to: dir)
        #expect(fs.directoryExists(dir))
        #expect(fs.directoryExists(link))
        #expect(!fs.directoryExists(tmp.path + "/assente"))
    }

    @Test func fileExistsMirrorsDotNetForLinks() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("dir")
        let file = try tmp.file("dir/f.txt", contents: "12345")
        #expect(fs.fileExists(file))
        #expect(!fs.fileExists(dir))
        #expect(!fs.fileExists(try tmp.symlink("versoCartella", to: dir)))
        #expect(fs.fileExists(try tmp.symlink("versoFile", to: file)))
        #expect(fs.fileExists(try tmp.symlink("interrotto", to: tmp.path + "/manca")))
    }

    @Test func itemInfoReadsTheLinkItselfNotTheTarget() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let target = try tmp.file("vecchio.txt", contents: "12345")
        let old = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: target)
        let link = try tmp.symlink("link", to: target)

        let info = try fs.itemInfo(link)

        #expect(info.kind == .symbolicLink)
        #expect(info.size == Int64(target.utf8.count))
        #expect(info.lastWrite > old)
        #expect(try fs.itemInfo(target).size == 5)
    }

    @Test func itemInfoOnMissingPathThrowsNotFound() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/assente")) {
            try fs.itemInfo(tmp.path + "/assente")
        }
    }

    @Test func fileLengthOnADirectoryThrowsNotFoundLikeFileInfoLength() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("dir")
        #expect(throws: FileSystemError(code: ENOENT, path: dir)) { try fs.fileLength(dir) }
    }

    @Test func contentsOfDirectoryReturnsSortedFullPaths() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.file("b.txt"); try tmp.file("a.txt"); try tmp.directory("c")
        #expect(try fs.contentsOfDirectory(tmp.path) == [tmp.path + "/a.txt", tmp.path + "/b.txt", tmp.path + "/c"])
    }

    @Test func contentsOfMissingDirectoryThrowsNotFound() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/assente")) {
            try fs.contentsOfDirectory(tmp.path + "/assente")
        }
    }

    @Test func deleteFileIgnoresMissingPathLikeFileDelete() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try fs.deleteFile(tmp.path + "/assente")
    }

    @Test func deleteFileRemovesTheLinkNotTheTarget() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let target = try tmp.file("tesi.docx", contents: "x")
        let link = try tmp.symlink("link", to: target)
        try fs.deleteFile(link)
        #expect(!FileManager.default.fileExists(atPath: link))
        #expect(FileManager.default.fileExists(atPath: target))
    }

    @Test func deleteDirectoryRecursivelyNeverFollowsLinks() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let precious = try tmp.file("Documents/fatture/2026.pdf", contents: "dati")
        try tmp.file("cache/app/dati.bin", contents: "x")
        try tmp.symlink("cache/app/collegamento", to: tmp.path + "/Documents")

        try fs.deleteDirectoryRecursively(tmp.path + "/cache")

        #expect(!FileManager.default.fileExists(atPath: tmp.path + "/cache"))
        #expect(FileManager.default.fileExists(atPath: precious))
    }

    @Test func deleteDirectoryRecursivelyOnALinkRemovesOnlyTheLink() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let precious = try tmp.file("Documents/tesi.docx", contents: "dati")
        let link = try tmp.symlink("link", to: tmp.path + "/Documents")

        try fs.deleteDirectoryRecursively(link)

        #expect(!FileManager.default.fileExists(atPath: link))
        #expect(FileManager.default.fileExists(atPath: precious))
    }

    @Test func deleteDirectoryRecursivelyReportsTheChildAccessDenied() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let locked = try tmp.directory("locked/sub")
        try tmp.file("locked/sub/x.txt", contents: "x")
        try tmp.file("locked/y.txt", contents: "y")
        chmod(locked, 0o555)

        #expect(throws: FileSystemError(code: EACCES, path: locked + "/x.txt")) {
            try fs.deleteDirectoryRecursively(tmp.path + "/locked")
        }
        #expect(!FileManager.default.fileExists(atPath: tmp.path + "/locked/y.txt"))
    }

    @Test func writeDataReplacesAndAppendDataCreatesThenAppends() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = tmp.path + "/impostazioni.json"
        try fs.writeData(file, Data("uno".utf8))
        try fs.writeData(file, Data("due".utf8))
        #expect(try fs.readText(file) == "due")

        let journal = tmp.path + "/diario.jsonl"
        try fs.appendData(journal, Data("a\n".utf8))
        try fs.appendData(journal, Data("b\n".utf8))
        #expect(try fs.readText(journal) == "a\nb\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.path).sorted() == ["diario.jsonl", "impostazioni.json"])
    }

    @Test func createDirectoryCreatesIntermediatesAndToleratesExisting() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try fs.createDirectory(tmp.path + "/a/b/c")
        try fs.createDirectory(tmp.path + "/a/b/c")
        #expect(fs.directoryExists(tmp.path + "/a/b/c"))
    }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func defaultApfsVolumeIsCaseInsensitive() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.file("Documents/tesi.docx")
        #expect(fs.fileExists(tmp.path + "/documents/TESI.docx"))
    }
}

extension TemporaryDirectory {
    /// Vero sul volume dati predefinito di macOS; falso su un volume APFS case-sensitive.
    static var volumeIsCaseInsensitive: Bool {
        pathconf(FileManager.default.temporaryDirectory.path(percentEncoded: false), _PC_CASE_SENSITIVE) == 0
    }
}
```

`Tests/CleanerCoreTests/Platform/FileSystemLinkInspectorTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct FileSystemLinkInspectorTests {
    private let links = FileSystemLinkInspector()

    @Test func recognisesLinksIncludingBrokenOnes() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = try tmp.file("f.txt")
        #expect(links.isSymbolicLink(try tmp.symlink("l", to: file)))
        #expect(links.isSymbolicLink(try tmp.symlink("rotto", to: tmp.path + "/manca")))
        #expect(!links.isSymbolicLink(file))
        #expect(!links.isSymbolicLink(tmp.path + "/assente"))
    }

    @Test func resolvesRelativeChainWithTextualNormalizationLikeDotNet() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.directory("dir")
        let name = PathText.fileName(tmp.path)
        let first = try tmp.symlink("rel", to: "../\(name)/dir/../dir")
        let second = try tmp.symlink("catena", to: first)
        #expect(links.resolveLinkTarget(first) == tmp.path + "/dir")
        #expect(links.resolveLinkTarget(second) == tmp.path + "/dir")
    }

    @Test func brokenLinkResolvesToItsDestinationPath() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let broken = try tmp.symlink("rotto", to: tmp.path + "/manca")
        #expect(links.resolveLinkTarget(broken) == tmp.path + "/manca")
    }

    @Test func nonLinkAndCycleResolveToNil() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(links.resolveLinkTarget(try tmp.file("f.txt")) == nil)
        try tmp.symlink("a", to: tmp.path + "/b")
        try tmp.symlink("b", to: tmp.path + "/a")
        #expect(links.resolveLinkTarget(tmp.path + "/a") == nil)
    }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "LocalFileSystemTests|FileSystemLinkInspectorTests"`
Expected: errore di compilazione `cannot find 'LocalFileSystem' in scope`.

- [ ] **Step 4: Implementare `FileSystem.swift`**

`Sources/CleanerCore/Platform/FileSystem.swift`:

```swift
import Darwin
import Foundation

/// Errore del filesystem: il codice errno originale e il percorso coinvolto. La classificazione
/// mostrata all'utente (accesso negato, in uso, …) avviene in `RuleScanner.describe`.
public struct FileSystemError: Error, Equatable, Sendable, CustomStringConvertible {
    public let code: Int32
    public let path: String

    public init(code: Int32, path: String) {
        self.code = code
        self.path = path
    }

    /// Testo di sistema dell'errore (`strerror`): fa le veci del `Message` delle eccezioni .NET.
    public var message: String { String(cString: strerror(code)) }

    public var description: String { "\(message): \(path)" }
}

public enum FileItemKind: Sendable, Equatable {
    case file
    case directory
    case symbolicLink
    case other
}

/// Metadati letti con `lstat`, come `FileInfo`/`DirectoryInfo` di .NET su Unix: per un
/// collegamento simbolico valgono dimensione e date del collegamento stesso, non del bersaglio.
public struct FileItemInfo: Sendable, Equatable {
    public let kind: FileItemKind
    public let size: Int64
    public let lastWrite: Date
    public let lastAccess: Date

    public init(kind: FileItemKind, size: Int64, lastWrite: Date, lastAccess: Date) {
        self.kind = kind
        self.size = size
        self.lastWrite = lastWrite
        self.lastAccess = lastAccess
    }

    /// Il più recente fra accesso e scrittura: l'«età» di ogni regola.
    public var newestStamp: Date { max(lastWrite, lastAccess) }
}

/// Il sottoinsieme di `System.IO.Abstractions` che il Core usa, con la stessa semantica di .NET
/// su Unix. Ogni operazione che fallisce lancia `FileSystemError`. In fase 2 un'implementazione
/// sandbox aprirà l'accesso security-scoped attorno a queste stesse operazioni.
public protocol FileSystem: Sendable {
    /// Come `Directory.Exists`: segue i collegamenti; vero solo se la destinazione è una cartella.
    func directoryExists(_ path: String) -> Bool
    /// Come `File.Exists`: vero per ciò che esiste e non è una cartella. Un collegamento a una
    /// cartella vale falso, un collegamento interrotto vale vero.
    func fileExists(_ path: String) -> Bool
    /// Come `Directory.EnumerateFileSystemEntries` su un solo livello: percorsi completi, in
    /// ordine ordinale (l'ordine di `readdir` non è garantito; ordinare rende ripetibili i risultati).
    func contentsOfDirectory(_ path: String) throws -> [String]
    /// Metadati senza seguire i collegamenti (`lstat`). Un percorso inesistente lancia `ENOENT`.
    func itemInfo(_ path: String) throws -> FileItemInfo
    /// Come `File.Delete`: un percorso inesistente non è un errore; un collegamento si rimuove,
    /// la destinazione resta.
    func deleteFile(_ path: String) throws
    /// Come `Directory.Delete(path, recursive: true)`: non segue mai i collegamenti (su un
    /// collegamento rimuove solo il collegamento), prova a eliminare tutto e lancia il primo
    /// errore incontrato.
    func deleteDirectoryRecursively(_ path: String) throws
    func readData(_ path: String) throws -> Data
    /// Sostituisce il contenuto in modo atomico (file temporaneo accanto + rename).
    func writeData(_ path: String, _ data: Data) throws
    /// Aggiunge in coda, creando il file se manca.
    func appendData(_ path: String, _ data: Data) throws
    /// Come `Directory.CreateDirectory`: crea anche i livelli intermedi; una cartella esistente
    /// non è un errore.
    func createDirectory(_ path: String) throws
}

extension FileSystem {
    /// Come `FileInfo.Length`: dimensione logica; su una cartella lancia `ENOENT`, come .NET
    /// lancia `FileNotFoundException`.
    public func fileLength(_ path: String) throws -> Int64 {
        let info = try itemInfo(path)
        guard info.kind != .directory else { throw FileSystemError(code: ENOENT, path: path) }
        return info.size
    }

    public func readText(_ path: String) throws -> String {
        String(decoding: try readData(path), as: UTF8.self)
    }

    public func writeText(_ path: String, _ text: String) throws {
        try writeData(path, Data(text.utf8))
    }
}
```

- [ ] **Step 5: Implementare `LocalFileSystem.swift`**

`Sources/CleanerCore/Platform/LocalFileSystem.swift`:

```swift
import Darwin
import Foundation

/// Implementazione reale su chiamate POSIX. Non segue mai i collegamenti simbolici, salvo dove
/// la semantica .NET replicata lo richiede (`directoryExists`, `fileExists`).
public struct LocalFileSystem: FileSystem {
    public init() {}

    public func directoryExists(_ path: String) -> Bool {
        var status = stat()
        return Self.statFollowingLinks(path, &status) && (status.st_mode & S_IFMT) == S_IFDIR
    }

    public func fileExists(_ path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else { return false }
        guard (status.st_mode & S_IFMT) == S_IFLNK else {
            return (status.st_mode & S_IFMT) != S_IFDIR
        }
        // Collegamento: conta la destinazione; se è irraggiungibile .NET risponde comunque vero.
        var target = stat()
        guard Self.statFollowingLinks(path, &target) else { return true }
        return (target.st_mode & S_IFMT) != S_IFDIR
    }

    public func contentsOfDirectory(_ path: String) throws -> [String] {
        guard let directory = opendir(path) else { throw FileSystemError(code: errno, path: path) }
        defer { closedir(directory) }

        var entries: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                String(decoding: bytes.prefix(length), as: UTF8.self)
            }
            if name != "." && name != ".." {
                entries.append(PathText.join(path, name))
            }
        }
        if errno != 0 { throw FileSystemError(code: errno, path: path) }
        return entries.sorted()
    }

    public func itemInfo(_ path: String) throws -> FileItemInfo {
        var status = stat()
        guard lstat(path, &status) == 0 else { throw FileSystemError(code: errno, path: path) }

        let kind: FileItemKind
        switch status.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }

        return FileItemInfo(
            kind: kind,
            size: Int64(status.st_size),
            lastWrite: Self.date(status.st_mtimespec),
            lastAccess: Self.date(status.st_atimespec))
    }

    public func deleteFile(_ path: String) throws {
        guard unlink(path) != 0 else { return }
        let code = errno
        if code != ENOENT { throw FileSystemError(code: code, path: path) }
    }

    public func deleteDirectoryRecursively(_ path: String) throws {
        var status = stat()
        guard lstat(path, &status) == 0 else { throw FileSystemError(code: errno, path: path) }
        if (status.st_mode & S_IFMT) == S_IFLNK {
            // Come .NET: su un collegamento a cartella si rimuove il collegamento, mai il contenuto
            // della destinazione.
            if unlink(path) != 0 { throw FileSystemError(code: errno, path: path) }
            return
        }

        var firstError: FileSystemError?
        removeTree(path, firstError: &firstError)
        if let firstError { throw firstError }
    }

    public func readData(_ path: String) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw FileSystemError(code: errno, path: path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw FileSystemError(code: EIO, path: path)
        }
    }

    public func writeData(_ path: String, _ data: Data) throws {
        let temporary = path + ".tmp-" + UUID().uuidString
        try writeAll(temporary, data, flags: O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC)
        if rename(temporary, path) != 0 {
            let code = errno
            unlink(temporary)
            throw FileSystemError(code: code, path: path)
        }
    }

    public func appendData(_ path: String, _ data: Data) throws {
        try writeAll(path, data, flags: O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC)
    }

    public func createDirectory(_ path: String) throws {
        if directoryExists(path) { return }
        if let parent = PathText.parent(path), !parent.isEmpty, parent != path {
            try createDirectory(parent)
        }
        if mkdir(path, 0o755) != 0 {
            let code = errno
            if code == EEXIST && directoryExists(path) { return }
            throw FileSystemError(code: code, path: path)
        }
    }

    // MARK: - Privati

    /// Elimina tutto ciò che può sotto `path`, poi `path` stesso; ricorda solo il primo errore,
    /// che è quello che .NET avrebbe lanciato.
    private func removeTree(_ path: String, firstError: inout FileSystemError?) {
        let children: [String]
        do {
            children = try contentsOfDirectory(path)
        } catch let error as FileSystemError {
            if firstError == nil { firstError = error }
            return
        } catch {
            return
        }

        for child in children {
            var status = stat()
            guard lstat(child, &status) == 0 else {
                if firstError == nil { firstError = FileSystemError(code: errno, path: child) }
                continue
            }
            if (status.st_mode & S_IFMT) == S_IFDIR {
                removeTree(child, firstError: &firstError)
            } else if unlink(child) != 0, firstError == nil {
                firstError = FileSystemError(code: errno, path: child)
            }
        }

        if rmdir(path) != 0, firstError == nil {
            firstError = FileSystemError(code: errno, path: path)
        }
    }

    private func writeAll(_ path: String, _ data: Data, flags: Int32) throws {
        let descriptor = open(path, flags, 0o644)
        guard descriptor >= 0 else { throw FileSystemError(code: errno, path: path) }
        defer { close(descriptor) }

        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw FileSystemError(code: errno, path: path)
                }
                offset += written
            }
        }
    }

    /// `stat(2)`, che segue i collegamenti. In Swift il nome `stat` indica anche la struct, e
    /// `Darwin.stat(path, &buffer)` si risolve sul suo inizializzatore: `fstatat` con flag 0 è la
    /// stessa chiamata senza ambiguità.
    private static func statFollowingLinks(_ path: String, _ status: inout stat) -> Bool {
        fstatat(AT_FDCWD, path, &status, 0) == 0
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
```

- [ ] **Step 6: Implementare `LinkInspecting.swift` e `WallClock.swift`**

`Sources/CleanerCore/Platform/LinkInspecting.swift`:

```swift
import Darwin

/// Riconosce i collegamenti simbolici. Separato da `FileSystem` come `ILinkInspector` in C#: i
/// test del `PathGuard` e degli scanner simulano i collegamenti senza un filesystem che li modelli.
public protocol LinkInspecting: Sendable {
    func isSymbolicLink(_ path: String) -> Bool

    /// La destinazione finale del collegamento (catena seguita per intero), oppure `nil` se
    /// `path` non è un collegamento o la destinazione non è determinabile. Come
    /// `ResolveLinkTarget(returnFinalTarget: true).FullName`: una destinazione relativa si risolve
    /// rispetto alla cartella del collegamento con normalizzazione testuale, e la destinazione
    /// finale può anche non esistere.
    func resolveLinkTarget(_ path: String) -> String?
}

public struct FileSystemLinkInspector: LinkInspecting {
    /// Stesso ordine di grandezza di MAXSYMLINKS (32) su macOS: oltre, è un ciclo.
    private static let maxHops = 32

    public init() {}

    public func isSymbolicLink(_ path: String) -> Bool {
        var status = stat()
        return lstat(path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFLNK
    }

    public func resolveLinkTarget(_ path: String) -> String? {
        guard isSymbolicLink(path) else { return nil }

        var current = path
        for _ in 0..<Self.maxHops {
            guard isSymbolicLink(current) else { return current }
            guard let destination = readLink(current) else { return nil }
            let base = PathText.parent(current) ?? "/"
            current = PathText.normalize(destination.hasPrefix("/") ? destination : PathText.join(base, destination))
        }
        return nil
    }

    private func readLink(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX) + 1)
        let count = readlink(path, &buffer, buffer.count - 1)
        guard count >= 0 else { return nil }
        return String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
```

`Sources/CleanerCore/Platform/WallClock.swift`:

```swift
import Foundation

/// L'ora corrente, astratta per rendere deterministici i filtri di età nei test.
public protocol WallClock: Sendable {
    var now: Date { get }
}

public struct SystemWallClock: WallClock {
    public init() {}

    public var now: Date { Date() }
}
```

- [ ] **Step 7: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "LocalFileSystemTests|FileSystemLinkInspectorTests"`
Expected: `Test run with 19 tests … passed` (con un test saltato se il volume temporaneo è case-sensitive).

- [ ] **Step 8: Annotare le differenze nel registro di parità**

In `docs/superpowers/porting/2026-10-13-parity.md`, tabella «Differenze rispetto al C#», aggiungere:

```markdown
| Messaggio d'errore | `Exception.Message` di .NET | `strerror(errno)` | accettata (spec §5.3) |
| Lettura dei collegamenti | `FileInfo`/`DirectoryInfo` (lstat, misurato) | `itemInfo` con `lstat` | identica |
```

- [ ] **Step 9: Commit**

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): add filesystem, link inspector and clock seams

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Doppi di test: `InMemoryFileSystem`, decoratori di guasto, `FakeLinkInspector`, utilità

**Files:**
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/FaultInjectingFileSystems.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/FakeLinkInspector.swift`
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/TestSupport.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystemTests.swift`

**Interfaces:**
- Consumes: `FileSystem`, `FileSystemError`, `FileItemInfo`, `LinkInspecting`, `WallClock`, `PathText` (Task 1–2).
- Produces (solo nel target di test):
  - `final class InMemoryFileSystem: FileSystem` — `init()`, `addFile(_ path: String, size: Int64 = 0, stamp: Date = Date())`, `addFile(_ path: String, text: String, stamp: Date = Date())`, `addDirectory(_ path: String)`, `setTimes(_ path: String, lastWrite: Date, lastAccess: Date)`
  - `class ForwardingFileSystem: FileSystem, @unchecked Sendable` — `init(_ inner: any FileSystem)`, ogni metodo ridefinibile
  - `final class VanishingFileSystem` (`init(_ inner:, vanishedPath:)`), `final class VanishingChildFileSystem` (`init(_ inner:, vanishingPath:)`), `final class UnreadableDirectoryFileSystem` (`init(_ inner:, unreadablePath:, error: (any Error)? = nil)`), `final class ThrowingOnDeleteFileSystem` (`init(_ inner:, throwingPath:)`)
  - `struct UnexpectedTestError: Error, CustomStringConvertible`
  - `struct FakeLinkInspector: LinkInspecting` — `init(_ links: String...)`, `init(targets: [String: String?])`
  - `struct FixedWallClock: WallClock` — `init(now: Date)`
  - `func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date`
  - `func days(_ count: Double) -> TimeInterval`
  - `func cancelCurrentTask()`

- [ ] **Step 1: Scrivere i test del doppio (falliscono)**

`Tests/CleanerCoreTests/Support/InMemoryFileSystemTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Il doppio deve comportarsi come `MockFileSystem` nei punti su cui i test C# contavano.
struct InMemoryFileSystemTests {
    @Test func addFileCreatesParentDirectories() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/Library/Caches/app/dati.bin", size: 100)
        #expect(fs.directoryExists("/Users/tester/Library/Caches/app"))
        #expect(fs.fileExists("/Users/tester/Library/Caches/app/dati.bin"))
        #expect(try fs.contentsOfDirectory("/Users/tester/Library/Caches") == ["/Users/tester/Library/Caches/app"])
        #expect(try fs.fileLength("/Users/tester/Library/Caches/app/dati.bin") == 100)
    }

    @Test func filesCarryTheirStampsAndDirectoriesCanBeAged() throws {
        let fs = InMemoryFileSystem()
        let old = utc(2020, 1, 1)
        fs.addFile("/a/f.txt", size: 1, stamp: old)
        fs.setTimes("/a", lastWrite: old, lastAccess: old)
        #expect(try fs.itemInfo("/a/f.txt").newestStamp == old)
        #expect(try fs.itemInfo("/a").newestStamp == old)
        #expect(try fs.itemInfo("/a").kind == .directory)
    }

    @Test func missingPathsBehaveLikeDotNet() throws {
        let fs = InMemoryFileSystem()
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) { try fs.itemInfo("/manca") }
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) { try fs.contentsOfDirectory("/manca") }
        try fs.deleteFile("/manca")
    }

    @Test func deleteDirectoryRecursivelyRemovesTheWholeSubtree() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/c/app/a/1.bin", size: 1)
        fs.addFile("/c/altro.bin", size: 1)
        try fs.deleteDirectoryRecursively("/c/app")
        #expect(!fs.directoryExists("/c/app"))
        #expect(!fs.fileExists("/c/app/a/1.bin"))
        #expect(fs.fileExists("/c/altro.bin"))
    }

    @Test func textRoundTripsAndAppendCreates() throws {
        let fs = InMemoryFileSystem()
        try fs.createDirectory("/s/logs")
        try fs.writeText("/s/settings.json", "{}")
        try fs.appendData("/s/logs/p.jsonl", Data("a\n".utf8))
        try fs.appendData("/s/logs/p.jsonl", Data("b\n".utf8))
        #expect(try fs.readText("/s/settings.json") == "{}")
        #expect(try fs.readText("/s/logs/p.jsonl") == "a\nb\n")
    }

    @Test func writeIntoMissingDirectoryFailsLikeDotNet() {
        let fs = InMemoryFileSystem()
        #expect(throws: FileSystemError.self) { try fs.writeText("/manca/x.json", "{}") }
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter InMemoryFileSystemTests`
Expected: errore di compilazione `cannot find 'InMemoryFileSystem' in scope`.

- [ ] **Step 3: Implementare `InMemoryFileSystem`**

`Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`:

```swift
import CleanerCore
import Darwin
import Foundation
import Synchronization

/// Filesystem simulato con la semantica di `MockFileSystem` su cui contavano i test C#: le
/// cartelle intermedie nascono da sole con la data corrente, i collegamenti simbolici non
/// esistono (li simula `FakeLinkInspector`), i percorsi distinguono maiuscole e minuscole,
/// `deleteFile` su un percorso inesistente non è un errore. La dimensione di un file creato con
/// `size:` è solo dichiarata, senza allocare i byte: alcuni test usano file da centinaia di MB.
final class InMemoryFileSystem: FileSystem {
    private struct Node {
        var isDirectory: Bool
        var size: Int64
        var contents: Data
        var lastWrite: Date
        var lastAccess: Date

        static func directory(_ stamp: Date) -> Node {
            Node(isDirectory: true, size: 0, contents: Data(), lastWrite: stamp, lastAccess: stamp)
        }
    }

    private let nodes = Mutex<[String: Node]>(["/": .directory(Date())])

    init() {}

    // MARK: - Costruzione dello scenario

    func addFile(_ path: String, size: Int64 = 0, stamp: Date = Date()) {
        store(path, Node(isDirectory: false, size: size, contents: Data(), lastWrite: stamp, lastAccess: stamp))
    }

    func addFile(_ path: String, text: String, stamp: Date = Date()) {
        let data = Data(text.utf8)
        store(path, Node(isDirectory: false, size: Int64(data.count), contents: data, lastWrite: stamp, lastAccess: stamp))
    }

    func addDirectory(_ path: String) {
        let key = Self.key(path)
        nodes.withLock { nodes in
            Self.ensureParents(of: key, in: &nodes)
            if nodes[key] == nil { nodes[key] = .directory(Date()) }
        }
    }

    func setTimes(_ path: String, lastWrite: Date, lastAccess: Date) {
        let key = Self.key(path)
        nodes.withLock { nodes in
            nodes[key]?.lastWrite = lastWrite
            nodes[key]?.lastAccess = lastAccess
        }
    }

    // MARK: - FileSystem

    func directoryExists(_ path: String) -> Bool {
        nodes.withLock { $0[Self.key(path)]?.isDirectory == true }
    }

    func fileExists(_ path: String) -> Bool {
        nodes.withLock { $0[Self.key(path)]?.isDirectory == false }
    }

    func contentsOfDirectory(_ path: String) throws -> [String] {
        let key = Self.key(path)
        return try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            guard node.isDirectory else { throw FileSystemError(code: ENOTDIR, path: path) }
            return nodes.keys.filter { $0 != "/" && PathText.parent($0) == key }.sorted()
        }
    }

    func itemInfo(_ path: String) throws -> FileItemInfo {
        let key = Self.key(path)
        return try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            return FileItemInfo(
                kind: node.isDirectory ? .directory : .file,
                size: node.isDirectory ? 0 : node.size,
                lastWrite: node.lastWrite,
                lastAccess: node.lastAccess)
        }
    }

    func deleteFile(_ path: String) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            guard let node = nodes[key] else { return }
            guard !node.isDirectory else { throw FileSystemError(code: EPERM, path: path) }
            nodes[key] = nil
        }
    }

    func deleteDirectoryRecursively(_ path: String) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            guard node.isDirectory else { throw FileSystemError(code: ENOTDIR, path: path) }
            let doomed = nodes.keys.filter { $0 == key || $0.hasPrefix(key + "/") }
            for candidate in doomed {
                nodes[candidate] = nil
            }
        }
    }

    func readData(_ path: String) throws -> Data {
        let key = Self.key(path)
        return try nodes.withLock { nodes in
            guard let node = nodes[key] else { throw FileSystemError(code: ENOENT, path: path) }
            guard !node.isDirectory else { throw FileSystemError(code: EISDIR, path: path) }
            return node.contents
        }
    }

    func writeData(_ path: String, _ data: Data) throws {
        try write(path) { _ in data }
    }

    func appendData(_ path: String, _ data: Data) throws {
        try write(path) { existing in (existing ?? Data()) + data }
    }

    func createDirectory(_ path: String) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            if let node = nodes[key], !node.isDirectory { throw FileSystemError(code: EEXIST, path: path) }
            Self.ensureParents(of: key, in: &nodes)
            if nodes[key] == nil { nodes[key] = .directory(Date()) }
        }
    }

    // MARK: - Privati

    private func store(_ path: String, _ node: Node) {
        let key = Self.key(path)
        nodes.withLock { nodes in
            Self.ensureParents(of: key, in: &nodes)
            nodes[key] = node
        }
    }

    /// Come `File.WriteAllText` di .NET: la cartella padre deve esistere.
    private func write(_ path: String, _ transform: (Data?) -> Data) throws {
        let key = Self.key(path)
        try nodes.withLock { nodes in
            guard let parent = PathText.parent(key), nodes[parent]?.isDirectory == true else {
                throw FileSystemError(code: ENOENT, path: path)
            }
            if nodes[key]?.isDirectory == true { throw FileSystemError(code: EISDIR, path: path) }
            let data = transform(nodes[key]?.contents)
            nodes[key] = Node(isDirectory: false, size: Int64(data.count), contents: data, lastWrite: Date(), lastAccess: Date())
        }
    }

    private static func key(_ path: String) -> String {
        let trimmed = PathText.trimmingTrailingSlashes(path)
        return trimmed.isEmpty ? "/" : trimmed
    }

    private static func ensureParents(of key: String, in nodes: inout [String: Node]) {
        var missing: [String] = []
        var current = PathText.parent(key)
        while let directory = current, !directory.isEmpty, nodes[directory] == nil {
            missing.append(directory)
            current = PathText.parent(directory)
        }
        for directory in missing.reversed() {
            nodes[directory] = .directory(Date())
        }
    }
}
```

- [ ] **Step 4: Implementare decoratori, `FakeLinkInspector` e utilità**

`Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`:

```swift
import CleanerCore
import Foundation

/// Base dei doppi di guasto: inoltra ogni operazione al filesystem interno. Ogni doppio
/// ridefinisce solo il metodo in cui inietta il guasto (in C# lo faceva `DispatchProxy`).
class ForwardingFileSystem: FileSystem, @unchecked Sendable {
    let inner: any FileSystem

    init(_ inner: any FileSystem) {
        self.inner = inner
    }

    func directoryExists(_ path: String) -> Bool { inner.directoryExists(path) }
    func fileExists(_ path: String) -> Bool { inner.fileExists(path) }
    func contentsOfDirectory(_ path: String) throws -> [String] { try inner.contentsOfDirectory(path) }
    func itemInfo(_ path: String) throws -> FileItemInfo { try inner.itemInfo(path) }
    func deleteFile(_ path: String) throws { try inner.deleteFile(path) }
    func deleteDirectoryRecursively(_ path: String) throws { try inner.deleteDirectoryRecursively(path) }
    func readData(_ path: String) throws -> Data { try inner.readData(path) }
    func writeData(_ path: String, _ data: Data) throws { try inner.writeData(path, data) }
    func appendData(_ path: String, _ data: Data) throws { try inner.appendData(path, data) }
    func createDirectory(_ path: String) throws { try inner.createDirectory(path) }
}
```

`Tests/CleanerCoreTests/Support/FaultInjectingFileSystems.swift`:

```swift
import CleanerCore
import Darwin
import Foundation
import Synchronization

/// Errore fuori dal contratto del Core (non un `FileSystemError`): l'equivalente delle eccezioni
/// che in C# non rientravano in `RuleScanner.IsExpected`.
struct UnexpectedTestError: Error, CustomStringConvertible {
    let description: String
}

/// Porting di `VanishingFileSystem.cs`: un elemento che scompare fra l'enumerazione e la lettura
/// della sua dimensione. In C# lanciava solo `FileInfo.Length`; in Swift dimensione e date
/// arrivano dalla stessa chiamata, quindi lancia `itemInfo`. L'esito dei test non cambia: per un
/// percorso scomparso .NET restituiva comunque la sentinella 1601 come data, e il Core Swift
/// tratta `ENOENT` esattamente come quella sentinella.
final class VanishingFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let vanishedPath: String

    init(_ inner: any FileSystem, vanishedPath: String) {
        self.vanishedPath = vanishedPath
        super.init(inner)
    }

    override func itemInfo(_ path: String) throws -> FileItemInfo {
        if path == vanishedPath { throw FileSystemError(code: ENOENT, path: path) }
        return try super.itemInfo(path)
    }
}

/// Porting di `VanishingChildFileSystem.cs`: la prima volta che `directoryExists` risponde vero
/// per il percorso bersaglio, la cartella viene eliminata dal filesystem interno — sparisce fra
/// il momento in cui lo scanner la riconosce e quello in cui ne legge le statistiche.
final class VanishingChildFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let vanishingPath: String
    private let triggered = Mutex(false)

    init(_ inner: any FileSystem, vanishingPath: String) {
        self.vanishingPath = vanishingPath
        super.init(inner)
    }

    override func directoryExists(_ path: String) -> Bool {
        guard path == vanishingPath else { return super.directoryExists(path) }
        let existed = super.directoryExists(path)
        let shouldVanish = triggered.withLock { alreadyTriggered in
            guard existed, !alreadyTriggered else { return false }
            alreadyTriggered = true
            return true
        }
        if shouldVanish { try? inner.deleteDirectoryRecursively(path) }
        return existed
    }
}

/// Porting di `UnreadableDirectoryFileSystem.cs`: una cartella visibile ma non elencabile. Senza
/// `error` esplicito lancia `EACCES`; con un `UnexpectedTestError` simula i mount virtuali che in
/// C# rispondevano con eccezioni di tipo imprevedibile.
final class UnreadableDirectoryFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let unreadablePath: String
    private let error: any Error

    init(_ inner: any FileSystem, unreadablePath: String, error: (any Error)? = nil) {
        self.unreadablePath = unreadablePath
        self.error = error ?? FileSystemError(code: EACCES, path: unreadablePath)
        super.init(inner)
    }

    override func contentsOfDirectory(_ path: String) throws -> [String] {
        if path == unreadablePath { throw error }
        return try super.contentsOfDirectory(path)
    }
}

/// Porting di `ThrowingOnDeleteFileSystem.cs`: un errore fuori contratto durante la cancellazione
/// di un file specifico.
final class ThrowingOnDeleteFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let throwingPath: String

    init(_ inner: any FileSystem, throwingPath: String) {
        self.throwingPath = throwingPath
        super.init(inner)
    }

    override func deleteFile(_ path: String) throws {
        if path == throwingPath {
            throw UnexpectedTestError(description: "errore imprevisto durante la cancellazione di \(path)")
        }
        try super.deleteFile(path)
    }
}
```

`Tests/CleanerCoreTests/Support/FakeLinkInspector.swift`:

```swift
import CleanerCore

/// Porting di `FakeLinkInspector.cs`. L'inizializzatore a elenco marca ogni percorso come
/// collegamento con destinazione non specificata (`resolveLinkTarget` → `nil`); quello a mappa
/// indica la destinazione finale. Confronto senza distinzione fra maiuscole e minuscole, come
/// il dizionario `OrdinalIgnoreCase` del C#.
struct FakeLinkInspector: LinkInspecting {
    private let links: [String: String?]

    init(_ links: String...) {
        self.init(links)
    }

    init(_ links: [String]) {
        var map: [String: String?] = [:]
        for link in links { map[Self.key(link)] = .some(nil) }
        self.links = map
    }

    init(targets: [String: String?]) {
        var map: [String: String?] = [:]
        for (link, target) in targets { map[Self.key(link)] = .some(target) }
        self.links = map
    }

    func isSymbolicLink(_ path: String) -> Bool {
        links[Self.key(path)] != nil
    }

    func resolveLinkTarget(_ path: String) -> String? {
        links[Self.key(path)] ?? nil
    }

    private static func key(_ path: String) -> String {
        PathText.trimmingTrailingSlashes(path).lowercased()
    }
}
```

`Tests/CleanerCoreTests/Support/TestSupport.swift`:

```swift
import CleanerCore
import Foundation

/// Porting di `TestTimeProvider.cs`.
struct FixedWallClock: WallClock {
    let now: Date
}

/// `new DateTimeOffset(year, month, day, hour, minute, second, TimeSpan.Zero)`.
func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return calendar.date(from: components) ?? .distantPast
}

/// `TimeSpan.FromDays(count)`.
func days(_ count: Double) -> TimeInterval {
    count * 86_400
}

/// Annulla il task in cui viene chiamata. Equivale a un `CancellationTokenSource` annullato: usata
/// prima della chiamata sotto test (annullamento anticipato) o dentro un callback di avanzamento
/// (annullamento a metà, deterministico perché il callback gira nel task stesso).
func cancelCurrentTask() {
    withUnsafeCurrentTask { $0?.cancel() }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter InMemoryFileSystemTests`
Expected: `Test run with 6 tests … passed`.

- [ ] **Step 6: Registro di parità e commit**

Nella sezione dei doppi del registro, aggiungere sotto l'elenco: «Portati in `Tests/CleanerCoreTests/Support/`; `VanishingFileSystem` lancia da `itemInfo` invece che dalla sola `Length` (vedi commento nel file).»

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "test(swift): add in-memory filesystem and fault-injecting doubles

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Safety in TDD: `CanonicalPath`, `DenyList`, `PathGuard`

È il componente in cui un difetto non produce un errore visibile ma una perdita di dati: si porta per primo, test prima del codice, e i 56 test C# (102 casi) si portano **tutti** come scritti qui sotto.

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/InvalidConfiguration.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Safety/CanonicalPath.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Safety/DenyList.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/DenyListTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`
- Reference (sola lettura): `src/MjmCleaner.Core/Safety/*.cs`, `tests/MjmCleaner.Core.Tests/Safety/*.cs`

**Interfaces:**
- Consumes: `PathText` (Task 1), `LinkInspecting` (Task 2), `FakeLinkInspector` (Task 3).
- Produces:
  - `public struct InvalidConfiguration: Error, Equatable, Sendable, CustomStringConvertible` — `init(_ description: String)`
  - `enum CanonicalPath` — `static func canonical(_ path: String?) -> String?` (interno al modulo)
  - `public struct DenyList: Sendable` — `init(homeDirectory: String?) throws`, `let homeDirectory: String`, `func deniedReason(_ canonicalPath: String?) -> String?`, `func isDenied(_ canonicalPath: String?) -> Bool`, `func recursiveDeniedReason(_:) -> String?` (interno)
  - `public struct GuardVerdict: Sendable, Equatable` — `isAllowed`, `reason`, `canonicalPathValidated`, `static func allow(_:)`, `static func deny(_:_:)`
  - `public protocol PathGuarding: Sendable` — `validateRoot(_ declaredRoot: String) -> GuardVerdict`, `validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict`, `pruneReason(_ candidatePath: String) -> String?`
  - `public struct PathGuard: PathGuarding` — `init(denyList: DenyList, links: any LinkInspecting, homeDirectory: String?) throws`

- [ ] **Step 1: Scrivere i test della deny-list (falliscono)**

`Tests/CleanerCoreTests/Safety/DenyListTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct DenyListTests {
    private static let home = "/Users/tester"

    private func create() throws -> DenyList {
        try DenyList(homeDirectory: Self.home)
    }

    @Test(arguments: [
        "/System/Library/Fonts",
        "/usr/bin",
        "/bin",
        "/Applications/Safari.app",
        "/Users/tester",
        "/Users/tester/Documents",
        "/Users/tester/Documents/fatture/2026",
        "/Users/tester/Desktop",
        "/Users/tester/Library/Application Support/qualcosa",
        "/Users/tester/Library/Mobile Documents",
        "/Users/tester/.ssh/id_rsa",
        "/Users/tester/Library/Containers/com.docker.docker/Data",
    ])
    func deniesProtectedPaths(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/Users/tester/Library/Caches/com.apple.Safari",
        "/Users/tester/Library/Logs/qualcosa.log",
        "/Library/Caches/com.apple.qualcosa",
        "/Library/Logs/DiagnosticReports/report.crash",
        "/Users/tester/.nuget/packages/newtonsoft.json",
        "/Users/tester/projects/app/bin",
    ])
    func allowsCleanablePaths(path: String) throws {
        #expect(try !create().isDenied(path))
    }

    @Test(arguments: [
        "/Users/tester/documents/fatture",
        "/Users/TESTER/Documents",
        "/users/tester/.SSH/config",
    ])
    func deniesRegardlessOfCase(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test func deniesLibraryButAllowsItsCachesAndLogs() throws {
        let list = try create()
        #expect(list.isDenied("/Library/Preferences"))
        #expect(!list.isDenied("/Library/Caches/x"))
        #expect(!list.isDenied("/Library/Logs/x"))
    }

    @Test func reasonExplainsWhichRuleMatched() throws {
        let reason = try #require(try create().deniedReason("/Users/tester/Documents/x"))
        #expect(reason.contains("Documents"))
    }

    @Test(arguments: ["/", "//", "///", ""])
    func deniesRootInAllVariants(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: ["/Users", "/Users/altro-utente/Documents"])
    func deniesUsersDirectoryAndOtherUsersHomes(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/Library/Caches/../Preferences",
        "/Library/Caches/../../etc/passwd",
        "/Library/Logs/../Keychains",
        "~//Documents",
        "~/./Documents",
    ])
    func deniesNonCanonicalPathsWithExplicitReason(path: String) throws {
        #expect(try create().deniedReason(path) == "percorso non canonico")
    }

    @Test(arguments: ["/Volumes/Backup", "/Volumes/Time Machine/x"])
    func deniesVolumes(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/private/etc/hosts",
        "/private/var/db/something",
        "/private/var/root/.bash_history",
        "/Network/Servers",
        "/cores/core.123",
        "/opt/homebrew/bin/brew",
    ])
    func deniesAdditionalSystemPaths(path: String) throws {
        #expect(try create().isDenied(path))
    }

    @Test(arguments: [
        "/Users/tester/Library/Messages/chat.db",
        "/Users/tester/Library/Mail/V10",
        "/Users/tester/Library/Safari/Bookmarks.plist",
        "/Users/tester/Library/Preferences/com.apple.finder.plist",
        "/Users/tester/Library/Group Containers/group.com.apple.notes",
        "/Users/tester/Library/Application Scripts/com.apple.finder",
        "/Users/tester/Library/Containers/com.apple.mail",
        "/Users/tester/.aws/credentials",
        "/Users/tester/.kube/config",
        "/Users/tester/.docker/config.json",
        "/Users/tester/.config/gh/config.yml",
        "/Users/tester/.password-store/personal",
        "/Users/tester/.local/share/foo",
        "/Users/tester/Applications/Chrome.app",
        "/Users/tester/Public/Drop Box",
        "/Users/tester/Sites/index.html",
    ])
    func deniesNewHomeSubtrees(path: String) throws {
        #expect(try create().isDenied(path))
    }

    // IMPORTANT 3 della revisione del PathGuard: da macOS 12 OneDrive, Dropbox e Google Drive
    // montano qui i documenti dell'utente, e Xcode/UserData contiene identità di firma e
    // profili di provisioning. Proteggere iCloud (Mobile Documents) e non questi era
    // un'asimmetria arbitraria che costa dati.
    @Test(arguments: [
        "/Users/tester/Library/CloudStorage/OneDrive-Personal/report.docx",
        "/Users/tester/Library/Developer/Xcode/UserData/KeyBindings/Default.idekeybindings",
    ])
    func deniesNewlyAddedHomeSubtrees(path: String) throws {
        #expect(try create().isDenied(path))
    }

    // La voce aggiunta sopra è specifica a "Xcode/UserData": non deve intaccare DerivedData e
    // Archives, due categorie dell'app che devono restare pulibili.
    @Test(arguments: [
        "/Users/tester/Library/Developer/Xcode/DerivedData/App-abc123/Build",
        "/Users/tester/Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive",
    ])
    func keepsXcodeDerivedDataAndArchivesCleanable(path: String) throws {
        #expect(try !create().isDenied(path))
    }

    @Test func deniesDockerContainerWithSpecificReasonBeforeGenericContainers() throws {
        let reason = try #require(try create().deniedReason("/Users/tester/Library/Containers/com.docker.docker/Data"))
        #expect(reason.lowercased().contains("docker"))
    }

    @Test(arguments: [
        "/Users/tester/Library/Caches",
        "/Library/Caches",
        "/Users/tester/Library/Logs",
        "/Library/Logs",
        "/Users/tester/Library/Logs/DiagnosticReports",
        "/Users/tester/.Trash",
        "/Users/tester/Downloads",
        "/Users/tester/.nuget",
        "/Users/tester/.npm",
        "/Users/tester/.cache",
        "/Users/tester/Library/Developer",
        "/private/var/folders",
        "/tmp",
    ])
    func keepsAppCategoriesCleanable(path: String) throws {
        #expect(try !create().isDenied(path))
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///", "/Users"] as [String?])
    func constructorRejectsInvalidHomeDirectory(homeDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) { try DenyList(homeDirectory: homeDirectory) }
    }

    // La proprietà di sicurezza che conta è questa, non solo "lancia un'eccezione": se una
    // forma degenere di homeDirectory riuscisse comunque a costruire una DenyList, quella
    // istanza non deve MAI rispondere isDenied(".../Documents/x") == false.
    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///", "/Users"] as [String?])
    func degenerateHomeDirectoryNeverProducesADenyListThatAllowsProtectedPaths(homeDirectory: String?) {
        do {
            let list = try DenyList(homeDirectory: homeDirectory)
            #expect(list.isDenied("/Users/tester/Documents/x"))
        } catch {
            #expect(error is InvalidConfiguration)
        }
    }
}
```

- [ ] **Step 2: Scrivere i test del PathGuard (falliscono)**

`Tests/CleanerCoreTests/Safety/PathGuardTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct PathGuardTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"

    private func create(_ symlinks: String...) throws -> PathGuard {
        try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(symlinks), homeDirectory: Self.home)
    }

    private func create(targets: [String: String?]) throws -> PathGuard {
        try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(targets: targets), homeDirectory: Self.home)
    }

    @Test func allowsItemInsideDeclaredRoot() throws {
        #expect(try create().validate("\(Self.cacheRoot)/com.apple.Safari", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesItemOutsideDeclaredRoot() throws {
        let verdict = try create().validate("/Users/tester/projects/app/bin", declaredRoot: Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("contenimento"))
    }

    @Test func deniesTraversalEscapingDeclaredRoot() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/../../Documents/fatture", declaredRoot: Self.cacheRoot).isAllowed)
    }

    // Sostituisce il test del brief "CanonicalizesBeforeComparing": una canonicalizzazione
    // testuale risolve ".." prima di seguire un collegamento simbolico, mentre il kernel lo
    // risolve dopo. La correzione è rifiutare ogni percorso con un segmento "." o "..".
    @Test func deniesNonCanonicalPathWithDotSegments() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/./sub/../sub/file", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesDeniedPathEvenWhenInsideDeclaredRoot() throws {
        #expect(try !create().validate("\(Self.home)/Documents/x", declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesHomeItself() throws {
        #expect(try !create().validate(Self.home, declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesDirectChildOfHome() throws {
        let verdict = try create().validate("\(Self.home)/Downloads", declaredRoot: "\(Self.home)/Downloads")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("profondità"))
    }

    @Test func allowsGrandchildOfHome() throws {
        #expect(try create().validate("\(Self.home)/Downloads/vecchio.dmg", declaredRoot: "\(Self.home)/Downloads").isAllowed)
    }

    @Test func allowsSymlinkItselfSoTheLinkCanBeRemoved() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(guardrail.validate("\(Self.cacheRoot)/collegamento", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesItemWhoseAncestorIsSymlink() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        let verdict = guardrail.validate("\(Self.cacheRoot)/collegamento/vittima.txt", declaredRoot: Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("collegamento"))
    }

    @Test func deniesItemTwoLevelsBelowSymlinkedAncestor() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(!guardrail.validate("\(Self.cacheRoot)/collegamento/sub/vittima.txt", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesItemThreeLevelsBelowSymlinkedAncestor() throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(!guardrail.validate("\(Self.cacheRoot)/collegamento/sub/sub2/vittima.txt", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesRegardlessOfCase() throws {
        #expect(try !create().validate("\(Self.home)/documents/x", declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesDockerContainer() throws {
        let docker = "\(Self.home)/Library/Containers/com.docker.docker/Data/vms"
        #expect(try !create().validate(docker, declaredRoot: "\(Self.home)/Library/Containers").isAllowed)
    }

    @Test(arguments: ["/", "//"])
    func deniesFilesystemRoot(root: String) throws {
        #expect(try !create().validate(root, declaredRoot: "/").isAllowed)
    }

    @Test func deniesAnotherUsersHome() throws {
        #expect(try !create().validate("/Users/altro/Documents/fatture", declaredRoot: "/Users").isAllowed)
    }

    @Test func deniesExternalVolume() throws {
        #expect(try !create().validate("/Volumes/Backup/2026", declaredRoot: "/Volumes").isAllowed)
    }

    @Test(arguments: ["/", "//"])
    func deniesAnyPathWhenDeclaredRootIsDegenerate(root: String) throws {
        #expect(try !create().validate("/Users/tester/projects/app/bin", declaredRoot: root).isAllowed)
    }

    @Test(arguments: ["collegamento/..", "collegamento/../sub/file", "a/collegamento/../altro/x"])
    func deniesNonCanonicalPathThroughAlias(suffix: String) throws {
        let guardrail = try create("\(Self.cacheRoot)/collegamento")
        #expect(!guardrail.validate("\(Self.cacheRoot)/\(suffix)", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesEmptyCandidatePathWithoutThrowing() throws {
        #expect(try !create().validate("", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func deniesEmptyDeclaredRootWithoutThrowing() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/file", declaredRoot: "").isAllowed)
    }

    @Test func deniesPathWithEmbeddedNulCharacterWithoutThrowing() throws {
        #expect(try !create().validate("\(Self.cacheRoot)/file\0name", declaredRoot: Self.cacheRoot).isAllowed)
    }

    @Test func validateRootAllowsOrdinaryRoot() throws {
        #expect(try create().validateRoot(Self.cacheRoot).isAllowed)
    }

    @Test func validateRootDeniesWhenRootIsSymlink() throws {
        let verdict = try create(Self.cacheRoot).validateRoot(Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("collegamento"))
    }

    @Test func validateRootDeniesWhenAncestorOfRootIsSymlink() throws {
        #expect(try !create("\(Self.home)/Library").validateRoot(Self.cacheRoot).isAllowed)
    }

    @Test func validateRootDeniesWhenHomeIsSymlink() throws {
        #expect(try !create(Self.home).validateRoot(Self.cacheRoot).isAllowed)
    }

    @Test func validateAloneAllowsDirectChildOfSymlinkedRootButValidateRootDenies() throws {
        let guardrail = try create(Self.cacheRoot)
        #expect(guardrail.validate("\(Self.cacheRoot)/child.tmp", declaredRoot: Self.cacheRoot).isAllowed)
        #expect(!guardrail.validateRoot(Self.cacheRoot).isAllowed)
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//"] as [String?])
    func constructorRejectsInvalidHomeDirectory(homeDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) {
            try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(), homeDirectory: homeDirectory)
        }
    }

    @Test func constructorRejectsHomeThatDiffersFromDenyListHome() {
        #expect(throws: InvalidConfiguration.self) {
            try PathGuard(denyList: DenyList(homeDirectory: "/Users/altro"), links: FakeLinkInspector(), homeDirectory: Self.home)
        }
    }

    @Test func validateRootResolvesSymlinkedAncestorAndStillDeniesProtectedTarget() throws {
        let verdict = try create(targets: ["/etc": "/private/etc"]).validateRoot("/etc/qualcosa")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("/private/etc"))
        #expect(verdict.canonicalPathValidated == "/private/etc/qualcosa")
    }

    @Test func validateRootResolvesSymlinkedAncestorAndAllowsUnprotectedTarget() throws {
        let verdict = try create(targets: ["/var": "/private/var"]).validateRoot("/var/folders/xyz/T")
        #expect(verdict.isAllowed)
        #expect(verdict.canonicalPathValidated == "/private/var/folders/xyz/T")
    }

    @Test func validateRootStillDeniesCacheRootRelocatedToExternalVolume() throws {
        let verdict = try create(targets: [Self.cacheRoot: "/Volumes/SSD/Caches"]).validateRoot(Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("/Volumes"))
        #expect(verdict.canonicalPathValidated == "/Volumes/SSD/Caches")
    }

    @Test func shouldPruneReportsDeniedBranch() throws {
        let reason = try #require(try create().pruneReason("\(Self.home)/Documents"))
        #expect(reason.contains("Documents"))
    }

    @Test func shouldPruneAllowsOrdinaryBranch() throws {
        #expect(try create().pruneReason(Self.cacheRoot) == nil)
    }

    @Test func validateRootAllowsHomeItselfBecauseExactMatchEntriesDoNotApplyToRoots() throws {
        #expect(try create().validateRoot(Self.home).isAllowed)
    }

    @Test func validateRootStillDeniesUsersDirectoryViaRecursiveRule() throws {
        #expect(try !create().validateRoot("/Users").isAllowed)
    }

    @Test func validateStillDeniesProtectedPathUnderHomeEvenThoughValidateRootAllowsHome() throws {
        #expect(try create().validateRoot(Self.home).isAllowed)
        #expect(try !create().validate("\(Self.home)/Documents/fattura.pdf", declaredRoot: Self.home).isAllowed)
    }

    @Test func deniesItemThatCoincidesWithADeepDeclaredRoot() throws {
        let verdict = try create().validate(Self.cacheRoot, declaredRoot: Self.cacheRoot)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains(Self.cacheRoot))
    }

    @Test func directChildOfHomeRootStillReportsDepthReasonNotCoincidenceReason() throws {
        let verdict = try create().validate("\(Self.home)/Downloads", declaredRoot: "\(Self.home)/Downloads")
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("profondità"))
    }
}
```

Copiare sopra ciascun test Swift i commenti che in `tests/MjmCleaner.Core.Tests/Safety/PathGuardTests.cs` precedono il test C# omonimo (spiegano i casi di revisione da cui il test nasce).

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "DenyListTests|PathGuardTests"`
Expected: errore di compilazione `cannot find 'DenyList' in scope`.

- [ ] **Step 4: Implementare `InvalidConfiguration` e `CanonicalPath`**

`Sources/CleanerCore/Platform/InvalidConfiguration.swift`:

```swift
/// Configurazione rifiutata da un inizializzatore: l'equivalente di `ArgumentException` nei
/// costruttori C#. Viene sempre lanciata prima che l'istanza esista: una configurazione
/// degenere non deve mai produrre un oggetto che la accetti.
public struct InvalidConfiguration: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
```

`Sources/CleanerCore/Safety/CanonicalPath.swift`:

```swift
import Foundation

/// Un percorso è "canonico" quando è assoluto, non contiene il carattere NUL, e non richiede
/// alcuna risoluzione: nessun segmento "." o "..", nessun separatore ridondante.
///
/// Condiviso da `DenyList` e `PathGuard`, che devono rifiutare i percorsi non canonici con la
/// stessa identica definizione: un percorso che l'una accetta e l'altro respinge (o viceversa)
/// apre un varco fra le due linee di difesa. Non è usato da `PathExpander`, che riceve percorsi
/// con "~" e "$TMPDIR" — non percorsi già assoluti da validare.
enum CanonicalPath {
    /// La forma normalizzata (senza "/" finali; "/" per la radice), oppure `nil` se il percorso
    /// non è canonico.
    static func canonical(_ path: String?) -> String? {
        guard let path,
              !path.allSatisfy(\.isWhitespace),
              path.hasPrefix("/"),
              !path.contains("\0") else {
            return nil
        }

        if path.contains("//")
            || path.contains("/./")
            || path.contains("/../")
            || path.hasSuffix("/.")
            || path.hasSuffix("/..") {
            return nil
        }

        let trimmed = PathText.trimmingTrailingSlashes(path)
        return trimmed.isEmpty ? "/" : trimmed
    }
}
```

- [ ] **Step 5: Implementare `DenyList`**

`Sources/CleanerCore/Safety/DenyList.swift`:

```swift
import Foundation

/// Percorsi che non devono mai essere eliminati. Non configurabile dall'interfaccia: è l'ultima
/// linea di difesa, non una preferenza.
public struct DenyList: Sendable {
    /// La home configurata, normalizzata (assoluta, senza "/" finale). Esposta perché
    /// `PathGuard` verifichi, nel proprio inizializzatore, di riferirsi alla stessa home: due home
    /// diverse fra guard e deny-list proteggerebbero la home sbagliata.
    public let homeDirectory: String

    private let deniedExact: [String]
    private let denied: [String]
    private let exceptions: [String]

    public init(homeDirectory: String?) throws {
        guard let homeDirectory, homeDirectory.hasPrefix("/"), homeDirectory != "/" else {
            throw InvalidConfiguration("La home directory deve essere un percorso assoluto diverso dalla radice.")
        }

        let home = PathText.trimmingTrailingSlashes(homeDirectory)

        // Validato DOPO la normalizzazione, non prima: un argomento come "//" supera indisturbato
        // il controllo sul valore grezzo qui sopra (non è né vuoto né "/"), ma la rimozione dei
        // "/" finali lo riduce a "" — a quel punto la home smette di essere un confine e la regola
        // su "/Users" si autoannulla, perché isSameOrUnder(path, "") è vero per qualunque percorso
        // assoluto. "/Users" grezzo degenera la stessa regola allo stesso modo.
        guard !home.isEmpty, !PathText.equalsIgnoringCase(home, "/Users") else {
            throw InvalidConfiguration(
                "La home directory deve restare un percorso assoluto non degenere, e diverso da \"/Users\", dopo la normalizzazione.")
        }

        self.homeDirectory = home

        // Uguaglianza esatta: proteggono solo se stesse, non un intero sottoalbero. Un confronto
        // ricorsivo su "/" o "/Users" negherebbe rispettivamente l'intero filesystem o l'intera
        // home di ogni utente, incluse le eccezioni sotto la home dell'utente corrente.
        deniedExact = ["/", "/Users", home]

        denied = [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/Applications", "/Library",
            "/Volumes", "/private/etc", "/private/var/db", "/private/var/root", "/Network", "/cores", "/opt",
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Pictures",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Library/Application Support",
            "\(home)/Library/Mobile Documents",
            // Da macOS 12, OneDrive, Dropbox e Google Drive montano qui i documenti dell'utente:
            // proteggere iCloud (Mobile Documents) e non questi sarebbe un'asimmetria arbitraria
            // che costa dati.
            "\(home)/Library/CloudStorage",
            "\(home)/Library/Keychains",
            // Solo la sottocartella con le identità di firma e i profili di provisioning:
            // "Library/Developer" resta pulibile (DerivedData si gestisce dalla pagina Xcode), quindi
            // non va negato in blocco.
            "\(home)/Library/Developer/Xcode/UserData",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            // Deve restare prima della voce "Containers" in blocco qui sotto: essendo più
            // specifica, vince nel ciclo e la motivazione restituita nomina Docker invece della
            // cartella generica.
            "\(home)/Library/Containers/com.docker.docker",
            "\(home)/Library/Messages",
            "\(home)/Library/Mail",
            "\(home)/Library/Safari",
            "\(home)/Library/Preferences",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Containers",
            "\(home)/.aws",
            "\(home)/.kube",
            "\(home)/.docker",
            "\(home)/.config",
            "\(home)/.password-store",
            "\(home)/.local",
            "\(home)/Applications",
            "\(home)/Public",
            "\(home)/Sites",
        ]

        exceptions = ["/Library/Caches", "/Library/Logs"]
    }

    /// Il motivo per cui il percorso è negato, oppure `nil` se è permesso. Il percorso deve
    /// essere già canonico: un percorso nullo, vuoto, relativo o non canonico viene negato per
    /// sicurezza (fail-closed), perché altrimenti potrebbe scavalcare le eccezioni, che sono
    /// ricorsive e valutate per prime.
    public func deniedReason(_ canonicalPath: String?) -> String? {
        guard let path = CanonicalPath.canonical(canonicalPath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }

        for allowed in exceptions where PathText.isSameOrUnder(path, allowed) {
            return nil
        }

        for exact in deniedExact where PathText.equalsIgnoringCase(path, exact) {
            return String(localized: "percorso protetto: \(exact)", bundle: .module)
        }

        return otherUsersReason(path) ?? recursiveReason(path)
    }

    public func isDenied(_ canonicalPath: String?) -> Bool {
        deniedReason(canonicalPath) != nil
    }

    /// Come `deniedReason`, ma ignora le voci a uguaglianza esatta ("/", "/Users", la home): ha
    /// senso negare l'ELEMENTO "/Users/tester" stesso (non lo si può cancellare), ma non la ROOT
    /// di una scansione "/Users/tester", perché significherebbe vietare di guardare nell'intero
    /// albero sottostante, dove vivono percorsi legittimamente pulibili come "~/Downloads". Usato
    /// da `PathGuard.validateRoot`; `validate` continua a usare `deniedReason` per intero.
    func recursiveDeniedReason(_ canonicalPath: String?) -> String? {
        guard let path = CanonicalPath.canonical(canonicalPath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }

        for allowed in exceptions where PathText.isSameOrUnder(path, allowed) {
            return nil
        }

        return otherUsersReason(path) ?? recursiveReason(path)
    }

    /// "/Users" è protetto in blocco tranne il sottoalbero della home configurata: le home degli
    /// altri utenti del Mac non godono delle eccezioni di questo profilo.
    private func otherUsersReason(_ path: String) -> String? {
        guard PathText.isSameOrUnder(path, "/Users"), !PathText.isSameOrUnder(path, homeDirectory) else {
            return nil
        }
        return String(localized: "percorso protetto: /Users (home di un altro utente)", bundle: .module)
    }

    private func recursiveReason(_ path: String) -> String? {
        for entry in denied where PathText.isSameOrUnder(path, entry) {
            return String(localized: "percorso protetto: \(entry)", bundle: .module)
        }
        return nil
    }
}
```

- [ ] **Step 6: Implementare `PathGuard`**

`Sources/CleanerCore/Safety/PathGuard.swift`:

```swift
import Foundation

/// Esito di una validazione. `canonicalPathValidated` è il percorso su cui il verdetto è stato
/// effettivamente emesso: quando permesso, è quello che va eliminato, non l'argomento originale —
/// validare una stringa e cancellarne un'altra vanificherebbe ogni controllo precedente. È vuoto
/// quando il rifiuto è emesso prima che un percorso canonico fosse disponibile.
public struct GuardVerdict: Sendable, Equatable {
    public let isAllowed: Bool
    public let reason: String
    public let canonicalPathValidated: String

    public init(isAllowed: Bool, reason: String, canonicalPathValidated: String) {
        self.isAllowed = isAllowed
        self.reason = reason
        self.canonicalPathValidated = canonicalPathValidated
    }

    public static func allow(_ canonicalPath: String) -> GuardVerdict {
        GuardVerdict(isAllowed: true, reason: "", canonicalPathValidated: canonicalPath)
    }

    public static func deny(_ reason: String, _ canonicalPath: String = "") -> GuardVerdict {
        GuardVerdict(isAllowed: false, reason: reason, canonicalPathValidated: canonicalPath)
    }
}

public protocol PathGuarding: Sendable {
    /// Valida la root dichiarata da una regola, risalendo i suoi antenati fino alla radice: se la
    /// root o un antenato è un collegamento simbolico lo risolve alla destinazione finale invece di
    /// negarlo alla cieca (su macOS "/var", "/etc" e "/tmp" sono collegamenti, e negarli renderebbe
    /// "$TMPDIR" non pulibile), e al percorso risolto applica la canonicità e solo le voci
    /// RICORSIVE della deny-list. Va invocata una volta per regola, prima degli elementi.
    func validateRoot(_ declaredRoot: String) -> GuardVerdict

    /// Valida un singolo elemento contro la root dichiarata. Presuppone che `validateRoot` sia già
    /// stata invocata con successo sulla stessa root: il controllo sui collegamenti qui risale solo
    /// fino alla root.
    func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict

    /// Il motivo per cui una cartella va esclusa dalla discesa ricorsiva perché la deny-list la
    /// protegge, oppure `nil`. Così uno scanner pota l'intero ramo invece di produrre
    /// un'esclusione per ogni elemento al suo interno, che per "~/Documents" o "~/.ssh" ne
    /// rivelerebbe i nomi dei file. Applica solo la deny-list, non contenimento né profondità.
    func pruneReason(_ candidatePath: String) -> String?
}

/// Ultima linea di difesa: invocato immediatamente prima di ogni eliminazione, non solo quando si
/// definiscono le regole. Non lancia mai: un input malformato produce un rifiuto motivato, mai un
/// errore che un `catch` a monte potrebbe trasformare in un salto silenzioso. In Swift la regola
/// è imposta dalla firma: `validate` e `validateRoot` non sono `throws`.
public struct PathGuard: PathGuarding {
    /// Limite di sostituzioni successive durante la risoluzione dei collegamenti di una root: una
    /// catena più lunga è quasi certamente un ciclo — nega invece di girare all'infinito.
    private static let maxSymlinkResolutions = 32

    private let denyList: DenyList
    private let links: any LinkInspecting
    private let home: String

    public init(denyList: DenyList, links: any LinkInspecting, homeDirectory: String?) throws {
        guard let home = CanonicalPath.canonical(homeDirectory), home != "/" else {
            throw InvalidConfiguration("La home directory deve essere un percorso assoluto canonico diverso dalla radice.")
        }

        // Imposta, non solo documenta: con due home diverse fra guard e deny-list, la regola di
        // profondità (punto 4 di validate) proteggerebbe la home sbagliata.
        guard PathText.equalsIgnoringCase(home, denyList.homeDirectory) else {
            throw InvalidConfiguration("La home del PathGuard deve coincidere con quella della DenyList.")
        }

        self.denyList = denyList
        self.links = links
        self.home = home
    }

    public func validateRoot(_ declaredRoot: String) -> GuardVerdict {
        let root: String
        switch Self.canonicalRoot(declaredRoot) {
        case .success(let canonical): root = canonical
        case .failure(let verdict): return verdict
        }

        let resolved: String
        switch resolveSymlinkedAncestors(root) {
        case .success(let path): resolved = path
        case .failure(let verdict): return verdict
        }

        // Due cause distinte, due messaggi distinti: un percorso risolto non canonico non
        // "coincide con la radice del filesystem" — lo fa solo il caso verificato a parte.
        guard let canonicalResolved = CanonicalPath.canonical(resolved) else {
            return .deny(String(localized: "root risolta non canonica", bundle: .module))
        }

        if canonicalResolved == "/" {
            return .deny(String(localized: "root risolta degenere: coincide con la radice del filesystem", bundle: .module))
        }

        // Solo le voci ricorsive: quelle a uguaglianza esatta ("/", "/Users", la home) proteggono
        // solo se stesse, non il permesso di guardarci dentro.
        if let reason = denyList.recursiveDeniedReason(canonicalResolved) {
            return .deny(reason, canonicalResolved)
        }

        return .allow(canonicalResolved)
    }

    public func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict {
        // 1. Rifiuto dei percorsi non canonici, prima di qualsiasi confronto. Nessuna risoluzione
        //    testuale di "." o "..": il kernel risolve ".." DOPO aver attraversato un collegamento,
        //    una risoluzione testuale lo farebbe PRIMA, facendo sparire il collegamento dalla
        //    stringa prima che la regola 5 possa vederlo. Gli elementi da eliminare arrivano
        //    sempre dall'enumerazione del filesystem, che non produce mai "..".
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return .deny(String(localized: "percorso non canonico", bundle: .module))
        }

        let root: String
        switch Self.canonicalRoot(declaredRoot) {
        case .success(let canonical): root = canonical
        case .failure(let verdict): return verdict
        }

        // 2. Contenimento nella root dichiarata dalla regola che ha prodotto l'elemento.
        guard PathText.hasPrefixIgnoringCase(path, root + "/") || PathText.equalsIgnoringCase(path, root) else {
            return .deny(String(localized: "violazione del contenimento: fuori da \(root)", bundle: .module), path)
        }

        // 3. Deny-list.
        if let reason = denyList.deniedReason(path) {
            return .deny(reason, path)
        }

        // 4. Profondità minima: mai la home, mai un suo figlio diretto.
        if isHomeOrDirectChild(path) {
            return .deny(String(localized: "profondità insufficiente: figlio diretto della home", bundle: .module), path)
        }

        // 5. Collegamenti simbolici fra l'elemento e la root: la root e ciò che sta sopra sono già
        //    stati verificati da validateRoot, quindi qui si risale fino a lì, non oltre.
        var ancestor = PathText.parent(path)
        while let current = ancestor, current.utf16.count > root.utf16.count {
            if links.isSymbolicLink(current) {
                return .deny(String(localized: "antenato è un collegamento simbolico: \(current)", bundle: .module), path)
            }
            ancestor = PathText.parent(current)
        }

        // 6. Un elemento che coincide con la root dichiarata cancellerebbe la root invece di
        //    svuotarla. Lo scanner non lo produce mai, ma l'elenco è manipolabile fra scansione e
        //    conferma. Deliberatamente dopo il punto 4, che nega con un motivo più specifico quando
        //    la root è la home o un suo figlio diretto.
        if PathText.equalsIgnoringCase(path, root) {
            return .deny(String(localized: "l'elemento coincide con la root della regola: \(root)", bundle: .module), path)
        }

        return .allow(path)
    }

    public func pruneReason(_ candidatePath: String) -> String? {
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }
        return denyList.deniedReason(path)
    }

    // MARK: - Privati

    private enum Step<Value> {
        case success(Value)
        case failure(GuardVerdict)
    }

    /// Canonicalizza la root e ne rifiuta le forme degeneri: una root che coincide con la radice
    /// rende il contenimento vero per qualunque percorso assoluto, quindi privo di significato.
    private static func canonicalRoot(_ declaredRoot: String) -> Step<String> {
        guard let canonical = CanonicalPath.canonical(declaredRoot), canonical != "/" else {
            return .failure(.deny(String(localized: "root non canonica o degenere: coincide con la radice del filesystem", bundle: .module)))
        }
        return .success(canonical)
    }

    /// Risolve iterativamente i collegamenti fra gli antenati di `root` (se stessa inclusa),
    /// sostituendo ciascuno con la sua destinazione finale, finché non ne restano. Se la
    /// destinazione di un antenato non è determinabile nega, invece di proseguire alla cieca.
    private func resolveSymlinkedAncestors(_ root: String) -> Step<String> {
        var current = root

        for _ in 0..<Self.maxSymlinkResolutions {
            var substituted: String?
            var ancestor: String? = current

            while let candidate = ancestor {
                if links.isSymbolicLink(candidate) {
                    guard let target = links.resolveLinkTarget(candidate) else {
                        return .failure(.deny(
                            String(localized: "la root o un suo antenato è un collegamento simbolico la cui destinazione non è determinabile: \(candidate)", bundle: .module),
                            current))
                    }
                    let suffix = current.count > candidate.count ? String(current.dropFirst(candidate.count)) : ""
                    substituted = PathText.trimmingTrailingSlashes(target) + suffix
                    break
                }
                ancestor = PathText.parent(candidate)
            }

            guard let next = substituted else { return .success(current) }
            current = next
        }

        return .failure(.deny(String(localized: "troppi collegamenti simbolici annidati mentre si risolveva la root: \(root)", bundle: .module)))
    }

    private func isHomeOrDirectChild(_ path: String) -> Bool {
        if PathText.equalsIgnoringCase(path, home) { return true }
        guard PathText.hasPrefixIgnoringCase(path, home + "/") else { return false }
        return !path.dropFirst(home.count + 1).contains("/")
    }
}
```

- [ ] **Step 7: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "DenyListTests|PathGuardTests"`
Expected: `Test run with 56 tests … passed`.

- [ ] **Step 8: Registro di parità e commit**

Aggiornare le righe `Safety/DenyListTests.cs` (`Safety/DenyListTests.swift`, 17 (89)) e `Safety/PathGuardTests.cs` (`Safety/PathGuardTests.swift`, 39 (13)). Nella colonna Note di `PathGuardTests`: «`ShouldPrune(path, out reason)` → `pruneReason(_:) -> String?`».

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port PathGuard, DenyList and CanonicalPath with their tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Settings: `AppearancePreference`, `CleanerSettings`, `AppPaths`, `SettingsStore`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Settings/AppearancePreference.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Settings/CleanerSettings.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Settings/AppPaths.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Settings/SettingsStore.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift`
- Reference: `src/MjmCleaner.Core/Settings/*.cs`, `tests/MjmCleaner.Core.Tests/Settings/SettingsStoreTests.cs`

**Interfaces:**
- Consumes: `FileSystem`, `PathText` (Task 1–2); `InMemoryFileSystem` (Task 3).
- Produces:
  - `public enum AppearancePreference: String, Sendable, CaseIterable, Codable` — `.auto` ("Auto"), `.light` ("Light"), `.dark` ("Dark")
  - `public struct CleanerSettings: Sendable, Equatable, Codable` — `var projectRoots: [String]`, `var largeFileRoots: [String]`, `var largeFileThresholdBytes: Int64`, `var downloadsMinAgeDays: Int`, `var logsMinAgeDays: Int`, `var nuGetMinAgeDays: Int`, `var selectedCategoryIds: [String]`, `var appearance: AppearancePreference`; `init()`
  - `public struct AppPaths: Sendable, Equatable` — `init(supportDirectory:)`, `supportDirectory`, `databaseFile`, `settingsFile`, `logsDirectory`, `static func forBundleIdentifier(_:) -> AppPaths`
  - `public protocol SettingsStoring: Sendable` — `load() -> CleanerSettings`, `save(_:) throws`
  - `public struct SettingsStore: SettingsStoring` — `init(fileSystem: any FileSystem, paths: AppPaths)`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Settings/SettingsStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct SettingsStoreTests {
    private static let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")

    /// Legge il JSON salvato come dizionario: verifica il formato senza dipendere da spaziature
    /// (JSONEncoder scrive `"Chiave" : valore`, System.Text.Json scriveva `"Chiave": valore`).
    private func savedJSON(_ fs: InMemoryFileSystem) throws -> [String: Any] {
        let data = try fs.readData(Self.paths.settingsFile)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func loadReturnsDefaultsWhenFileMissing() {
        let settings = SettingsStore(fileSystem: InMemoryFileSystem(), paths: Self.paths).load()
        #expect(settings.projectRoots.isEmpty)
        #expect(settings.downloadsMinAgeDays == 90)
        #expect(settings.logsMinAgeDays == 30)
        #expect(settings.nuGetMinAgeDays == 180)
        #expect(settings.largeFileThresholdBytes == 500 * 1024 * 1024)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let store = SettingsStore(fileSystem: InMemoryFileSystem(), paths: Self.paths)
        var original = CleanerSettings()
        original.projectRoots = ["/Users/tester/projects"]
        original.downloadsMinAgeDays = 30
        original.selectedCategoryIds = ["system-caches", "dev-caches"]

        try store.save(original)
        let loaded = store.load()

        #expect(loaded.projectRoots == ["/Users/tester/projects"])
        #expect(loaded.downloadsMinAgeDays == 30)
        #expect(loaded.selectedCategoryIds == ["system-caches", "dev-caches"])
    }

    @Test func loadReturnsDefaultsWhenFileIsCorrupt() {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: "{ questo non è json")
        #expect(SettingsStore(fileSystem: fs, paths: Self.paths).load().downloadsMinAgeDays == 90)
    }

    @Test func appearanceDefaultsToAuto() {
        #expect(CleanerSettings().appearance == .auto)
    }

    @Test func legacyFileWithoutAppearanceLoadsAsAuto() {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "DownloadsMinAgeDays": 12 }"#)
        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()
        #expect(settings.downloadsMinAgeDays == 12)
        #expect(settings.appearance == .auto)
    }

    @Test func appearanceRoundTripsAsReadableString() throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.appearance = .dark

        try store.save(settings)

        #expect(try savedJSON(fs)["Appearance"] as? String == "Dark")
        #expect(store.load().appearance == .dark)
    }

    @Test(arguments: [#""Darkk""#, "7", "-1", "null", "true", #""""#, #""1""#, #"{ "x": 1 }"#, #"[ "Dark" ]"#])
    func unknownAppearanceValueFallsBackToAutoAndKeepsTheOtherSettings(appearanceJSON: String) {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "DownloadsMinAgeDays": 12, "Appearance": "# + appearanceJSON + #", "LogsMinAgeDays": 5 }"#)

        let settings = SettingsStore(fileSystem: fs, paths: Self.paths).load()

        #expect(settings.appearance == .auto)
        #expect(settings.downloadsMinAgeDays == 12)
        #expect(settings.logsMinAgeDays == 5)
    }

    @Test(arguments: [
        ("dark", AppearancePreference.dark),
        ("DARK", .dark),
        ("Light", .light),
        ("auto", .auto),
    ])
    func appearanceIsReadCaseInsensitively(text: String, expected: AppearancePreference) {
        let fs = InMemoryFileSystem()
        fs.addFile(Self.paths.settingsFile, text: #"{ "Appearance": ""# + text + #"" }"#)
        #expect(SettingsStore(fileSystem: fs, paths: Self.paths).load().appearance == expected)
    }

    @Test(arguments: AppearancePreference.allCases)
    func appearanceRoundTripsForEveryValue(preference: AppearancePreference) throws {
        let fs = InMemoryFileSystem()
        let store = SettingsStore(fileSystem: fs, paths: Self.paths)
        var settings = CleanerSettings()
        settings.appearance = preference
        settings.downloadsMinAgeDays = 7

        try store.save(settings)

        #expect(try savedJSON(fs)["Appearance"] as? String == preference.rawValue)
        let loaded = store.load()
        #expect(loaded.appearance == preference)
        #expect(loaded.downloadsMinAgeDays == 7)
    }

    @Test func appPathsLiveUnderApplicationSupport() {
        let paths = AppPaths.forBundleIdentifier("com.mjm.cleaner")
        #expect(paths.supportDirectory.hasSuffix("/Library/Application Support/com.mjm.cleaner"))
        #expect(paths.databaseFile.hasSuffix("history.db"))
        #expect(paths.settingsFile.hasSuffix("settings.json"))
        #expect(paths.logsDirectory.hasSuffix("logs"))
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter SettingsStoreTests`
Expected: errore di compilazione `cannot find 'AppPaths' in scope`.

- [ ] **Step 3: Implementare i quattro file**

`Sources/CleanerCore/Settings/AppearancePreference.swift`:

```swift
/// Aspetto dell'interfaccia: `auto` segue Impostazioni di Sistema.
public enum AppearancePreference: String, Sendable, CaseIterable {
    case auto = "Auto"
    case light = "Light"
    case dark = "Dark"
}

/// Legge l'aspetto senza mai far fallire il caricamento delle impostazioni: un file modificato a
/// mano o scritto da una versione diversa («Darkk», un numero, un oggetto) vale `auto` invece di
/// buttare via anche tutte le altre impostazioni. Si scrive il nome, così il file resta leggibile.
extension AppearancePreference: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let text = try? container.decode(String.self) else {
            self = .auto
            return
        }
        // Solo i nomi, senza distinzione fra maiuscole e minuscole: «1» non vale come numero.
        self = Self.allCases.first { PathText.equalsIgnoringCase($0.rawValue, text) } ?? .auto
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
```

`Sources/CleanerCore/Settings/CleanerSettings.swift`:

```swift
/// Preferenze persistite in `settings.json`. Chiavi e valori predefiniti identici al C#; un campo
/// mancante prende il valore predefinito, un campo di tipo sbagliato rende il file illeggibile
/// (e `SettingsStore` torna ai predefiniti), tranne l'aspetto, che è tollerante.
public struct CleanerSettings: Sendable, Equatable, Codable {
    public var projectRoots: [String] = []
    public var largeFileRoots: [String] = []
    public var largeFileThresholdBytes: Int64 = 500 * 1024 * 1024
    public var downloadsMinAgeDays = 90
    public var logsMinAgeDays = 30
    public var nuGetMinAgeDays = 180
    /// Selezione dell'ultimo utilizzo: riduce il costo dei quattro passi nella pulizia di routine.
    public var selectedCategoryIds = ["system-caches", "dev-caches", "project-build-output", "logs"]
    public var appearance = AppearancePreference.auto

    public init() {}

    enum CodingKeys: String, CodingKey {
        case projectRoots = "ProjectRoots"
        case largeFileRoots = "LargeFileRoots"
        case largeFileThresholdBytes = "LargeFileThresholdBytes"
        case downloadsMinAgeDays = "DownloadsMinAgeDays"
        case logsMinAgeDays = "LogsMinAgeDays"
        case nuGetMinAgeDays = "NuGetMinAgeDays"
        case selectedCategoryIds = "SelectedCategoryIds"
        case appearance = "Appearance"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CleanerSettings()
        projectRoots = try container.decodeIfPresent([String].self, forKey: .projectRoots) ?? defaults.projectRoots
        largeFileRoots = try container.decodeIfPresent([String].self, forKey: .largeFileRoots) ?? defaults.largeFileRoots
        largeFileThresholdBytes = try container.decodeIfPresent(Int64.self, forKey: .largeFileThresholdBytes) ?? defaults.largeFileThresholdBytes
        downloadsMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .downloadsMinAgeDays) ?? defaults.downloadsMinAgeDays
        logsMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .logsMinAgeDays) ?? defaults.logsMinAgeDays
        nuGetMinAgeDays = try container.decodeIfPresent(Int.self, forKey: .nuGetMinAgeDays) ?? defaults.nuGetMinAgeDays
        selectedCategoryIds = try container.decodeIfPresent([String].self, forKey: .selectedCategoryIds) ?? defaults.selectedCategoryIds
        appearance = try container.decodeIfPresent(AppearancePreference.self, forKey: .appearance) ?? defaults.appearance
    }
}
```

`Sources/CleanerCore/Settings/AppPaths.swift`:

```swift
import Foundation

/// I dati dell'applicazione vivono sotto Application Support, che la deny-list protegge:
/// l'applicazione non può eliminare il proprio storico.
public struct AppPaths: Sendable, Equatable {
    public let supportDirectory: String

    public init(supportDirectory: String) {
        self.supportDirectory = supportDirectory
    }

    public var databaseFile: String { PathText.join(supportDirectory, "history.db") }
    public var settingsFile: String { PathText.join(supportDirectory, "settings.json") }
    public var logsDirectory: String { PathText.join(supportDirectory, "logs") }

    /// `~/Library/Application Support/<bundle id>/`, ricavata da Foundation: diversa dalla
    /// `mjm.cleaner/` dell'app C#, così le due app convivono. In fase 2, sotto sandbox, la stessa
    /// chiamata punterà da sola al container dell'app.
    public static func forBundleIdentifier(_ bundleIdentifier: String) -> AppPaths {
        let directory = URL.applicationSupportDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .path(percentEncoded: false)
        return AppPaths(supportDirectory: PathText.trimmingTrailingSlashes(directory))
    }
}
```

`Sources/CleanerCore/Settings/SettingsStore.swift`:

```swift
import Foundation

public protocol SettingsStoring: Sendable {
    func load() -> CleanerSettings
    func save(_ settings: CleanerSettings) throws
}

public struct SettingsStore: SettingsStoring {
    private let fileSystem: any FileSystem
    private let paths: AppPaths

    public init(fileSystem: any FileSystem, paths: AppPaths) {
        self.fileSystem = fileSystem
        self.paths = paths
    }

    /// Preferenze illeggibili o corrotte non devono impedire l'avvio: si torna ai predefiniti.
    public func load() -> CleanerSettings {
        guard fileSystem.fileExists(paths.settingsFile) else { return CleanerSettings() }
        do {
            return try JSONDecoder().decode(CleanerSettings.self, from: fileSystem.readData(paths.settingsFile))
        } catch {
            return CleanerSettings()
        }
    }

    public func save(_ settings: CleanerSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try fileSystem.createDirectory(paths.supportDirectory)
        try fileSystem.writeData(paths.settingsFile, encoder.encode(settings))
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter SettingsStoreTests`
Expected: `Test run with 10 tests … passed`.

- [ ] **Step 5: Registro di parità e commit**

Riga `Settings/SettingsStoreTests.cs` → `Settings/SettingsStoreTests.swift`, 10 (16). Note: «le asserzioni sul testo JSON verificano la chiave decodificata invece della spaziatura; `AppPathsLiveUnderApplicationSupport` usa il bundle id». Tabella differenze: `| Cartella dati | ~/Library/Application Support/mjm.cleaner | …/<bundle id> | voluta (spec §4.4) |`.

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port settings, appearance preference and app paths

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Categories: regole, `PathExpander`, `CategoryCatalog`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Categories/CleanupCategory.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Categories/PathExpander.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Categories/CategoryCatalog.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Categories/PathExpanderTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`
- Reference: `src/MjmCleaner.Core/Categories/*.cs`, `tests/MjmCleaner.Core.Tests/Categories/*.cs`

**Interfaces:**
- Consumes: `PathText`, `InvalidConfiguration`, `CleanerSettings` (Task 1, 4, 5).
- Produces:
  - `public enum ScanMode: Sendable, Equatable { case clearContents, matchingDirs, matchingFiles }`
  - `public enum RiskLevel: Sendable, Equatable { case low, medium, high }`
  - `public struct CleanupRule: Sendable, Equatable` — `init(_ root: String, _ mode: ScanMode, include: [String], exclude: [String], minAge: TimeInterval? = nil, minSizeBytes: Int64? = nil, maxDepth: Int = .max, requiresProjectMarker: Bool = false)`; proprietà `root`, `mode`, `includeGlobs`, `excludeGlobs`, `minAge`, `minSizeBytes`, `maxDepth`, `requiresProjectMarker`
  - `public struct CleanupCategory: Sendable, Equatable, Identifiable` — `init(id:displayName:description:risk:selectedByDefault:parentId:rules:)`
  - `public struct PathExpander: Sendable` — `init(homeDirectory: String?, tempDirectory: String?) throws`, `func expand(_:) -> String`, `static func forCurrentUser() throws -> PathExpander`
  - `public enum CategoryCatalog` — `static func build(_ settings: CleanerSettings, _ expander: PathExpander) -> [CleanupCategory]`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Categories/PathExpanderTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct PathExpanderTests {
    private func create() throws -> PathExpander {
        try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/var/folders/ab/xyz/T/")
    }

    @Test func expandsTildePrefix() throws {
        #expect(try create().expand("~/Library/Caches") == "/Users/tester/Library/Caches")
    }

    @Test func expandsBareTilde() throws {
        #expect(try create().expand("~") == "/Users/tester")
    }

    @Test func expandsTmpdirVariable() throws {
        #expect(try create().expand("$TMPDIR") == "/var/folders/ab/xyz/T")
    }

    @Test func leavesAbsolutePathUnchanged() throws {
        #expect(try create().expand("/Library/Caches") == "/Library/Caches")
    }

    @Test func trimsTrailingSlash() throws {
        #expect(try create().expand("~/Downloads/") == "/Users/tester/Downloads")
    }

    @Test func doesNotExpandTildeOfAnotherUser() throws {
        #expect(try create().expand("~altro/Documents") == "~altro/Documents")
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///"] as [String?])
    func constructorRejectsInvalidHomeDirectory(homeDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) {
            try PathExpander(homeDirectory: homeDirectory, tempDirectory: "/var/folders/ab/xyz/T")
        }
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///"] as [String?])
    func constructorRejectsInvalidTempDirectory(tempDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) {
            try PathExpander(homeDirectory: "/Users/tester", tempDirectory: tempDirectory)
        }
    }
}
```

`Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct CategoryCatalogTests {
    private func build(_ settings: CleanerSettings = CleanerSettings()) throws -> [CleanupCategory] {
        CategoryCatalog.build(settings, try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/var/folders/ab/T"))
    }

    private func category(_ id: String, in categories: [CleanupCategory]) throws -> CleanupCategory {
        let matches = categories.filter { $0.id == id }
        #expect(matches.count == 1)
        return try #require(matches.first)
    }

    @Test func definesTheSevenCategories() throws {
        #expect(try build().map(\.id) == [
            "system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash", "downloads-large",
        ])
    }

    @Test func nuGetIsNestedUnderDevCachesAndNotSelectedByDefault() throws {
        let nuget = try category("nuget-packages", in: build())
        #expect(nuget.parentId == "dev-caches")
        #expect(!nuget.selectedByDefault)
    }

    @Test func highRiskCategoryIsNeverSelectedByDefault() throws {
        let risky = try category("trash", in: build())
        #expect(risky.risk == .high)
        #expect(!risky.selectedByDefault)
    }

    @Test func ruleRootsAreAlreadyExpanded() throws {
        let caches = try category("system-caches", in: build())
        #expect(caches.rules.contains { $0.root == "/Users/tester/Library/Caches" })
        #expect(caches.rules.contains { $0.root == "/Library/Caches" })
        #expect(!caches.rules.contains { $0.root.hasPrefix("~") })
    }

    @Test func projectBuildOutputHasOneRulePerConfiguredRoot() throws {
        var settings = CleanerSettings()
        settings.projectRoots = ["/Users/tester/projects", "/Users/tester/lavoro"]

        let projects = try category("project-build-output", in: build(settings))

        #expect(projects.rules.count == 2)
        #expect(projects.rules.allSatisfy { $0.requiresProjectMarker })
        #expect(projects.rules.allSatisfy { $0.mode == .matchingDirs })
        #expect(projects.rules.allSatisfy { $0.includeGlobs == ["bin", "obj"] })
    }

    @Test func projectBuildOutputHasNoRulesWhenNoRootConfigured() throws {
        #expect(try category("project-build-output", in: build()).rules.isEmpty)
    }

    @Test func ageThresholdsComeFromSettings() throws {
        var settings = CleanerSettings()
        settings.logsMinAgeDays = 7
        settings.downloadsMinAgeDays = 45
        settings.nuGetMinAgeDays = 60
        let categories = try build(settings)

        let logRule = try #require(try category("logs", in: categories).rules.first)
        let downloadsRule = try #require(try category("downloads-large", in: categories).rules.first { $0.root == "/Users/tester/Downloads" })
        let nugetRule = try #require(try category("nuget-packages", in: categories).rules.first)

        #expect(logRule.minAge == days(7))
        #expect(downloadsRule.minAge == days(45))
        #expect(nugetRule.minAge == days(60))
    }

    @Test func dockerIsNotReferencedByAnyRule() throws {
        #expect(!(try build()).flatMap(\.rules).contains { $0.root.lowercased().contains("docker") })
    }

    @Test func generalDevelopmentCacheCategoryDoesNotContainDerivedData() throws {
        let development = try category("dev-caches", in: build())
        #expect(!development.rules.contains { $0.root.lowercased().contains("deriveddata") })
        #expect(development.description.lowercased().contains("pagina xcode"))
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "PathExpanderTests|CategoryCatalogTests"`
Expected: errore di compilazione `cannot find 'PathExpander' in scope`.

- [ ] **Step 3: Implementare i modelli e `PathExpander`**

`Sources/CleanerCore/Categories/CleanupRule.swift`:

```swift
import Foundation

public enum ScanMode: Sendable, Equatable {
    /// Svuota il contenuto della root mantenendo la root stessa.
    case clearContents
    /// Cerca ricorsivamente cartelle il cui nome corrisponde ai pattern.
    case matchingDirs
    /// Cerca file per pattern, età e dimensione.
    case matchingFiles
}

public enum RiskLevel: Sendable, Equatable {
    case low
    case medium
    case high
}

/// Le regole sono dati, non codice: un solo scanner le interpreta.
public struct CleanupRule: Sendable, Equatable {
    public let root: String
    public let mode: ScanMode
    public let includeGlobs: [String]
    public let excludeGlobs: [String]
    public let minAge: TimeInterval?
    public let minSizeBytes: Int64?
    public let maxDepth: Int
    public let requiresProjectMarker: Bool

    public init(
        _ root: String,
        _ mode: ScanMode,
        include includeGlobs: [String],
        exclude excludeGlobs: [String],
        minAge: TimeInterval? = nil,
        minSizeBytes: Int64? = nil,
        maxDepth: Int = .max,
        requiresProjectMarker: Bool = false
    ) {
        self.root = root
        self.mode = mode
        self.includeGlobs = includeGlobs
        self.excludeGlobs = excludeGlobs
        self.minAge = minAge
        self.minSizeBytes = minSizeBytes
        self.maxDepth = maxDepth
        self.requiresProjectMarker = requiresProjectMarker
    }
}
```

`Sources/CleanerCore/Categories/CleanupCategory.swift`:

```swift
public struct CleanupCategory: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    public let risk: RiskLevel
    public let selectedByDefault: Bool
    public let parentId: String?
    public let rules: [CleanupRule]

    public init(
        id: String,
        displayName: String,
        description: String,
        risk: RiskLevel,
        selectedByDefault: Bool,
        parentId: String?,
        rules: [CleanupRule]
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.risk = risk
        self.selectedByDefault = selectedByDefault
        self.parentId = parentId
        self.rules = rules
    }
}
```

`Sources/CleanerCore/Categories/PathExpander.swift`:

```swift
import Foundation

/// Traduce i percorsi delle regole in percorsi assoluti.
public struct PathExpander: Sendable {
    private let home: String
    private let temp: String

    public init(homeDirectory: String?, tempDirectory: String?) throws {
        home = try Self.normalize(homeDirectory)
        temp = try Self.normalize(tempDirectory)
    }

    public func expand(_ path: String) -> String {
        let expanded: String
        if path == "~" {
            expanded = home
        } else if path == "$TMPDIR" {
            expanded = temp
        } else if path.hasPrefix("~/") {
            expanded = home + path.dropFirst()
        } else {
            expanded = path
        }
        return expanded.count > 1 ? PathText.trimmingTrailingSlashes(expanded) : expanded
    }

    /// Home reale e `$TMPDIR` dell'utente: fuori dalla sandbox `NSTemporaryDirectory()` è la
    /// cartella per-utente sotto /var/folders, come `Path.GetTempPath()` in .NET.
    public static func forCurrentUser() throws -> PathExpander {
        try PathExpander(homeDirectory: NSHomeDirectory(), tempDirectory: NSTemporaryDirectory())
    }

    // Validato DOPO la rimozione dei "/" finali, non prima: lo stesso difetto misurato in
    // DenyList. Un valore come "//" o "/" supera un controllo sul solo valore grezzo, ma ridotto
    // diventa "": expand("~") o expand("$TMPDIR") restituirebbero la stringa vuota.
    private static func normalize(_ directory: String?) throws -> String {
        guard let directory, directory.hasPrefix("/") else {
            throw InvalidConfiguration("Il percorso deve essere assoluto.")
        }
        let normalized = PathText.trimmingTrailingSlashes(directory)
        guard !normalized.isEmpty else {
            throw InvalidConfiguration("Il percorso deve restare un percorso assoluto non degenere dopo la normalizzazione.")
        }
        return normalized
    }
}
```

- [ ] **Step 4: Implementare `CategoryCatalog`**

`Sources/CleanerCore/Categories/CategoryCatalog.swift`:

```swift
import Foundation

public enum CategoryCatalog {
    private static let all = ["*"]

    public static func build(_ settings: CleanerSettings, _ expander: PathExpander) -> [CleanupCategory] {
        func expanded(_ path: String) -> String { expander.expand(path) }
        func days(_ count: Int) -> TimeInterval { TimeInterval(count) * 86_400 }

        return [
            CleanupCategory(
                id: "system-caches",
                displayName: String(localized: "Cache utente e di sistema", bundle: .module),
                description: String(localized: "Cache rigenerabili delle applicazioni e del sistema. Le app aperte potrebbero comportarsi in modo anomalo fino al riavvio.", bundle: .module),
                risk: .medium,
                selectedByDefault: true,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Library/Caches"), .clearContents, include: all, exclude: []),
                    CleanupRule(expanded("/Library/Caches"), .clearContents, include: all, exclude: []),
                    CleanupRule(expanded("$TMPDIR"), .clearContents, include: all, exclude: [], minAge: days(1)),
                ]),

            CleanupCategory(
                id: "dev-caches",
                displayName: String(localized: "Cache di sviluppo", bundle: .module),
                description: String(localized: "Cache di npm e Gradle. Xcode DerivedData si gestisce dalla pagina Xcode dedicata.", bundle: .module),
                risk: .low,
                selectedByDefault: true,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/.npm/_cacache"), .clearContents, include: all, exclude: []),
                    CleanupRule(expanded("~/.cache"), .clearContents, include: all, exclude: []),
                    // Niente regola su "Archives": a differenza di DerivedData (output di
                    // compilazione, rigenerabile), un archivio Xcode contiene il binario e il dSYM
                    // di una build già spedita. Senza quel dSYM non si simbolicano più i crash
                    // report di quella release.
                    CleanupRule(expanded("~/.gradle/caches"), .clearContents, include: all, exclude: []),
                ]),

            CleanupCategory(
                id: "nuget-packages",
                displayName: String(localized: "Pacchetti NuGet inutilizzati", bundle: .module),
                description: String(localized: "Svuotarla costa il ri-download di ogni pacchetto alla prossima compilazione e impedisce di compilare offline. L'età si basa sull'ultimo accesso: è un'euristica.", bundle: .module),
                risk: .low,
                selectedByDefault: false,
                parentId: "dev-caches",
                rules: [
                    CleanupRule(
                        expanded("~/.nuget/packages"), .matchingDirs, include: all, exclude: [],
                        minAge: days(settings.nuGetMinAgeDays), maxDepth: 1),
                ]),

            CleanupCategory(
                id: "project-build-output",
                displayName: String(localized: "Cartelle bin e obj nei progetti", bundle: .module),
                description: String(localized: "Output di compilazione .NET. Una cartella viene proposta solo se accanto a essa c'è un file di progetto.", bundle: .module),
                risk: .low,
                selectedByDefault: true,
                parentId: nil,
                rules: settings.projectRoots.map { root in
                    CleanupRule(expanded(root), .matchingDirs, include: ["bin", "obj"], exclude: [], requiresProjectMarker: true)
                }),

            CleanupCategory(
                id: "logs",
                displayName: String(localized: "Log e crash report", bundle: .module),
                description: String(localized: "Diari di bordo di sistema e applicazioni.", bundle: .module),
                risk: .low,
                selectedByDefault: true,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Library/Logs"), .matchingFiles, include: all, exclude: [], minAge: days(settings.logsMinAgeDays)),
                    CleanupRule(expanded("/Library/Logs"), .matchingFiles, include: all, exclude: [], minAge: days(settings.logsMinAgeDays)),
                ]),

            CleanupCategory(
                id: "trash",
                displayName: String(localized: "Cestino", bundle: .module),
                description: String(localized: "Contiene dati reali, non file rigenerabili. Va selezionato manualmente.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/.Trash"), .clearContents, include: all, exclude: []),
                ]),

            CleanupCategory(
                id: "downloads-large",
                displayName: String(localized: "Download e file grandi", bundle: .module),
                description: String(localized: "Contiene dati reali, non file rigenerabili. Ogni voce va selezionata manualmente.", bundle: .module),
                risk: .high,
                selectedByDefault: false,
                parentId: nil,
                rules: [
                    CleanupRule(expanded("~/Downloads"), .matchingFiles, include: all, exclude: [], minAge: days(settings.downloadsMinAgeDays)),
                ] + settings.largeFileRoots.map { root in
                    CleanupRule(expanded(root), .matchingFiles, include: all, exclude: [], minSizeBytes: settings.largeFileThresholdBytes)
                }),
        ]
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "PathExpanderTests|CategoryCatalogTests"`
Expected: `Test run with 17 tests … passed`.

- [ ] **Step 6: Registro di parità e commit**

Righe `Categories/PathExpanderTests.cs` (8 (14)) e `Categories/CategoryCatalogTests.cs` (9) compilate con i file Swift.

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port cleanup rules, path expander and category catalog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Scanning: modelli e `RuleScanner`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Scanning/ScanModels.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Scanning/RuleScanner.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/RuleScannerTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/MatchingDirsTests.swift`
- Reference: `src/MjmCleaner.Core/Scanning/RuleScanner.cs`, `ScanModels.cs`; `tests/MjmCleaner.Core.Tests/Scanning/RuleScannerTests.cs`, `MatchingDirsTests.cs`

**Interfaces:**
- Consumes: `FileSystem`, `FileSystemError`, `LinkInspecting`, `WallClock`, `PathText`, `SimpleGlob` (Task 1–2); `PathGuarding`, `PathGuard`, `DenyList` (Task 4); `CleanupRule`, `ScanMode` (Task 6); doppi del Task 3.
- Produces:
  - `public struct ScanItem: Sendable, Equatable, Hashable` — `path`, `sizeBytes: Int64`, `isDirectory: Bool`, `declaredRoot: String`; `init(path:sizeBytes:isDirectory:declaredRoot:)`
  - `public enum ScanErrorKind: Sendable, Equatable { case accessDenied, inUse, notFound, notEmpty, other }`
  - `public struct ScanError: Sendable, Equatable` — `path`, `kind`, `message`; `init(path:kind:message:)`
  - `public struct GuardExclusion: Sendable, Equatable` — `path`, `reason`; `init(path:reason:)`
  - `public struct RuleScanOutcome: Sendable, Equatable` — `items`, `errors`, `exclusions`
  - `public struct CategoryScanResult: Sendable, Equatable` — `categoryId`, `items`, `totalBytes: Int64`, `errors`, `exclusions`; `init(categoryId:items:totalBytes:errors:exclusions:)`
  - `public struct ScanProgress: Sendable, Equatable` — `categoryId`, `currentPath`, `itemsFound: Int`, `bytesFound: Int64`
  - `public struct RuleScanner: Sendable` — `init(fileSystem: any FileSystem, pathGuard: any PathGuarding, links: any LinkInspecting, clock: any WallClock)`, `func scan(_ rule: CleanupRule) throws -> RuleScanOutcome` (lancia solo `CancellationError`)
  - interni al modulo: `static func RuleScanner.describe(_ path: String, _ error: any Error) -> ScanError`, `static func RuleScanner.isExpected(_ error: any Error) -> Bool`

- [ ] **Step 1: Scrivere i test di `RuleScanner` (falliscono)**

`Tests/CleanerCoreTests/Scanning/RuleScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct RuleScannerTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]

    private func create(_ fs: any FileSystem, _ symlinks: String...) throws -> RuleScanner {
        let links = FakeLinkInspector(symlinks)
        return RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    /// `File(size, written)` del C#: data di scrittura e accesso uguali, per default "adesso".
    private func addFile(_ fs: InMemoryFileSystem, _ path: String, _ size: Int64, written: Date? = nil) {
        fs.addFile(path, size: size, stamp: written ?? Self.now)
    }

    private func single(_ outcome: RuleScanOutcome) throws -> ScanItem {
        #expect(outcome.items.count == 1)
        return try #require(outcome.items.first)
    }

    @Test func returnsNothingWhenRootDoesNotExist() throws {
        let outcome = try create(InMemoryFileSystem()).scan(
            CleanupRule("/Users/tester/Library/Developer/Xcode/DerivedData", .clearContents, include: Self.all, exclude: []))
        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.isEmpty)
    }

    @Test func clearContentsListsDirectChildrenNotTheRoot() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/app1/dati.bin", 100)
        addFile(fs, "\(Self.cacheRoot)/solo.tmp", 50)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(outcome.items.count == 2)
        #expect(!outcome.items.contains { $0.path == Self.cacheRoot })
        #expect(outcome.items.contains { $0.path == "\(Self.cacheRoot)/app1" && $0.isDirectory && $0.sizeBytes == 100 })
        #expect(outcome.items.contains { $0.path == "\(Self.cacheRoot)/solo.tmp" && !$0.isDirectory && $0.sizeBytes == 50 })
    }

    @Test func directorySizeIsSummedRecursively() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/app/a/1.bin", 100)
        addFile(fs, "\(Self.cacheRoot)/app/b/2.bin", 250)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(try single(outcome).sizeBytes == 350)
    }

    @Test func itemsCarryTheDeclaredRoot() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/x.tmp", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(try single(outcome).declaredRoot == Self.cacheRoot)
    }

    @Test func guardRejectionBecomesExclusionNotItem() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.home)/Documents/riservato.pdf", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.home, .clearContents, include: Self.all, exclude: []))

        #expect(outcome.items.isEmpty)
        #expect(!outcome.exclusions.isEmpty)
    }

    @Test func symlinkIsListedButItsTargetIsNotTraversed() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/collegamento/dentro.bin", 9999)

        let outcome = try create(fs, "\(Self.cacheRoot)/collegamento")
            .scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        let item = try single(outcome)
        #expect(item.path == "\(Self.cacheRoot)/collegamento")
        #expect(item.sizeBytes == 0)
    }

    @Test func matchingFilesHonoursMinAge() throws {
        let fs = InMemoryFileSystem()
        let logs = "\(Self.home)/Library/Logs"
        addFile(fs, "\(logs)/vecchio.log", 10, written: Self.now.addingTimeInterval(-days(60)))
        addFile(fs, "\(logs)/recente.log", 10, written: Self.now.addingTimeInterval(-days(2)))

        let outcome = try create(fs).scan(CleanupRule(logs, .matchingFiles, include: Self.all, exclude: [], minAge: days(30)))

        #expect(try single(outcome).path == "\(logs)/vecchio.log")
    }

    @Test func matchingFilesHonoursGlobsAndExclusions() throws {
        let fs = InMemoryFileSystem()
        let logs = "\(Self.home)/Library/Logs"
        addFile(fs, "\(logs)/a.log", 10)
        addFile(fs, "\(logs)/b.txt", 10)
        addFile(fs, "\(logs)/importante.log", 10)

        let outcome = try create(fs).scan(CleanupRule(logs, .matchingFiles, include: ["*.log"], exclude: ["importante.*"]))

        #expect(try single(outcome).path == "\(logs)/a.log")
    }

    @Test func matchingFilesHonoursMinSize() throws {
        let fs = InMemoryFileSystem()
        let downloads = "\(Self.home)/Downloads"
        addFile(fs, "\(downloads)/grande.dmg", 2000)
        addFile(fs, "\(downloads)/piccolo.txt", 10)

        let outcome = try create(fs).scan(CleanupRule(downloads, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 1000))

        #expect(try single(outcome).path == "\(downloads)/grande.dmg")
    }

    @Test func cancellationStopsTheScan() async throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/a.tmp", 10)
        let scanner = try create(fs)
        let rule = CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: [])

        let task = Task {
            cancelCurrentTask()
            return try scanner.scan(rule)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    // IMPORTANT 2 della revisione del Task 8: ClearContents ignorava IncludeGlobs, ExcludeGlobs
    // e MinSizeBytes, proponendo elementi che la regola dichiara di conservare.
    @Test func clearContentsHonoursExcludeGlobs() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/normale.tmp", 10)
        addFile(fs, "\(Self.cacheRoot)/da_conservare.keep", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: ["*.keep"]))

        #expect(try single(outcome).path == "\(Self.cacheRoot)/normale.tmp")
    }

    @Test func clearContentsHonoursMinSize() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/grande.tmp", 2_000_000)
        addFile(fs, "\(Self.cacheRoot)/piccolo.tmp", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: [], minSizeBytes: 1_000_000))

        #expect(try single(outcome).path == "\(Self.cacheRoot)/grande.tmp")
    }

    // IMPORTANT 3: l'età di una directory va calcolata sul timestamp più recente nell'albero,
    // non sul solo contenitore, il cui mtime non cambia quando un file interno viene riscritto.
    @Test func clearContentsDirectoryAgeReflectsNewestContainedFile() throws {
        let fs = InMemoryFileSystem()
        let dir = "\(Self.cacheRoot)/app"
        addFile(fs, "\(dir)/nuovo.bin", 10, written: Self.now.addingTimeInterval(-days(1)))
        let old = Self.now.addingTimeInterval(-days(200))
        fs.setTimes(dir, lastWrite: old, lastAccess: old)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: [], minAge: days(30)))

        #expect(outcome.items.isEmpty)
    }

    // IMPORTANT 4: MatchingFiles deve potare i rami negati dalla deny-list, non produrre
    // un'esclusione per ogni file privato al loro interno.
    @Test func matchingFilesPrunesDeniedBranchWithoutDescendingIntoIt() throws {
        let fs = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        addFile(fs, "\(library)/Keychains/login.keychain", 10)
        addFile(fs, "\(library)/Caches/normale.tmp", 10)

        let outcome = try create(fs).scan(CleanupRule(library, .matchingFiles, include: Self.all, exclude: []))

        #expect(outcome.exclusions.contains { $0.path == "\(library)/Keychains" })
        #expect(!outcome.exclusions.contains { $0.path == "\(library)/Keychains/login.keychain" })
        #expect(try single(outcome).path == "\(library)/Caches/normale.tmp")
    }

    @Test func matchingFilesDoesNotPruneOrdinaryBranches() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.cacheRoot)/app/sub/file.log", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.cacheRoot, .matchingFiles, include: Self.all, exclude: []))

        #expect(outcome.exclusions.isEmpty)
        #expect(try single(outcome).path == "\(Self.cacheRoot)/app/sub/file.log")
    }

    // Minor (caso E2): un elemento scomparso fra enumerazione e lettura della dimensione non deve
    // comparire sia fra gli errori sia fra gli elementi.
    @Test func matchingFilesDoesNotListAFileThatVanishesBeforeSizeRead() throws {
        let mock = InMemoryFileSystem()
        let logs = "\(Self.home)/Library/Logs"
        let vanished = "\(logs)/scomparso.log"
        addFile(mock, vanished, 10)

        let outcome = try create(VanishingFileSystem(mock, vanishedPath: vanished))
            .scan(CleanupRule(logs, .matchingFiles, include: Self.all, exclude: []))

        #expect(outcome.items.isEmpty)
        #expect(outcome.errors.contains { $0.path == vanished && $0.kind == .notFound })
    }

    @Test func matchingFilesFindsLegitimateLargeFilesInHomeWhilePruningProtectedBranches() throws {
        let fs = InMemoryFileSystem()
        addFile(fs, "\(Self.home)/Downloads/installer.dmg", 2_000_000)
        addFile(fs, "\(Self.home)/progetti/archivio.zip", 3_000_000)
        addFile(fs, "\(Self.home)/Documents/riservato.pdf", 5_000_000)
        addFile(fs, "\(Self.home)/.ssh/id_rsa", 10)

        let outcome = try create(fs).scan(CleanupRule(Self.home, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 1_000_000))

        #expect(outcome.items.count == 2)
        #expect(outcome.items.contains { $0.path == "\(Self.home)/Downloads/installer.dmg" })
        #expect(outcome.items.contains { $0.path == "\(Self.home)/progetti/archivio.zip" })
        #expect(outcome.exclusions.contains { $0.path == "\(Self.home)/Documents" })
        #expect(outcome.exclusions.contains { $0.path == "\(Self.home)/.ssh" })
    }

    // Minor (re-revisione): il guard deve escludere "Keychains" PRIMA di attraversarla; il file
    // interno, se letto, produrrebbe un errore.
    @Test func clearContentsValidatesBeforeTraversingADeniedDirectory() throws {
        let mock = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        let innerSecret = "\(library)/Keychains/login.keychain"
        addFile(mock, innerSecret, 10)
        addFile(mock, "\(library)/Caches/normale.tmp", 10)

        let outcome = try create(VanishingFileSystem(mock, vanishedPath: innerSecret))
            .scan(CleanupRule(library, .clearContents, include: Self.all, exclude: []))

        #expect(!outcome.errors.contains { $0.path == innerSecret })
        #expect(outcome.exclusions.contains { $0.path == "\(library)/Keychains" })
        #expect(outcome.items.contains { $0.path == "\(library)/Caches" })
    }

    // Minor (re-revisione): su una directory scomparsa .NET restituiva la sentinella 1601 invece
    // di "indeterminato"; la directory sembrava antichissima e veniva proposta.
    @Test func clearContentsDoesNotListADirectoryThatVanishesBeforeStatsRead() throws {
        let mock = InMemoryFileSystem()
        let vanished = "\(Self.cacheRoot)/scomparsa"
        addFile(mock, "\(vanished)/dentro.bin", 10)

        let outcome = try create(VanishingChildFileSystem(mock, vanishingPath: vanished))
            .scan(CleanupRule(Self.cacheRoot, .clearContents, include: Self.all, exclude: []))

        #expect(!outcome.items.contains { $0.path == vanished })
    }

    // IMPORTANT della revisione finale: la ricorsione non deve mai entrare in ".git", i cui pack
    // file sono indistinguibili da file grandi legittimi ma contengono l'intera storia.
    @Test func matchingFilesNeverEntersAGitDirectory() throws {
        let fs = InMemoryFileSystem()
        let projects = "\(Self.home)/projects"
        addFile(fs, "\(projects)/progetto/.git/objects/pack/grosso.pack", 200_000_000)
        addFile(fs, "\(projects)/progetto/dati.bin", 100_000_000)

        let outcome = try create(fs).scan(CleanupRule(projects, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 50_000_000))

        #expect(!outcome.items.contains { $0.path.contains(".git") })
        #expect(outcome.items.contains { $0.path == "\(projects)/progetto/dati.bin" })
        #expect(outcome.exclusions.contains { $0.path == "\(projects)/progetto/.git" })
    }

    @Test func matchingDirsNeverEntersOrMatchesAGitDirectory() throws {
        let fs = InMemoryFileSystem()
        let projects = "\(Self.home)/projects"
        fs.addFile("\(projects)/progetto/app.csproj", text: "<Project/>")
        addFile(fs, "\(projects)/progetto/bin/app.dll", 10)
        addFile(fs, "\(projects)/progetto/.git/objects/pack/grosso.pack", 200_000_000)

        let outcome = try create(fs).scan(
            CleanupRule(projects, .matchingDirs, include: ["bin", "obj"], exclude: [], requiresProjectMarker: true))

        #expect(!outcome.items.contains { $0.path.contains(".git") })
        #expect(outcome.items.contains { $0.path == "\(projects)/progetto/bin" })
        #expect(outcome.exclusions.contains { $0.path == "\(projects)/progetto/.git" })
    }

    // Mount virtuali (es. ~/Library/Developer/CoreDevice/DeviceFS) rispondono all'enumerazione
    // con errori fuori contratto: il ramo si registra come errore e la scansione continua.
    @Test func unexpectedEnumerationFailureIsRecordedAndScanContinues() throws {
        let mock = InMemoryFileSystem()
        let projects = "\(Self.home)/projects"
        let broken = "\(Self.home)/Library/Developer/CoreDevice/DeviceFS/device-1/DiagnosticReports"
        addFile(mock, "\(projects)/grosso.bin", 200_000_000)
        addFile(mock, "\(broken)/report.ips", 10)
        let fs = UnreadableDirectoryFileSystem(
            mock, unreadablePath: broken, error: UnexpectedTestError(description: "Invalid argument : '\(broken)'"))

        let outcome = try create(fs).scan(
            CleanupRule(Self.home, .matchingFiles, include: Self.all, exclude: [], minSizeBytes: 100_000_000, maxDepth: 12))

        #expect(outcome.items.contains { $0.path == "\(projects)/grosso.bin" })
        #expect(outcome.errors.contains { $0.path == broken })
    }
}
```

Riportare sopra ciascun test i commenti C# originali che ne motivano l'esistenza dove qui sono abbreviati.

- [ ] **Step 2: Scrivere i test della modalità `matchingDirs` (falliscono)**

`Tests/CleanerCoreTests/Scanning/MatchingDirsTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct MatchingDirsTests {
    private static let home = "/Users/tester"
    private static let projects = "/Users/tester/projects"
    private static let now = utc(2026, 9, 15, 12)

    private func create(_ fs: any FileSystem, _ symlinks: String...) throws -> RuleScanner {
        let links = FakeLinkInspector(symlinks)
        return RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
    }

    private func binObjRule(_ root: String = Self.projects, minSizeBytes: Int64? = nil) -> CleanupRule {
        CleanupRule(root, .matchingDirs, include: ["bin", "obj"], exclude: [], minSizeBytes: minSizeBytes, requiresProjectMarker: true)
    }

    private func single(_ outcome: RuleScanOutcome) throws -> ScanItem {
        #expect(outcome.items.count == 1)
        return try #require(outcome.items.first)
    }

    @Test func findsBinAndObjNextToProjectFile() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "<Project/>")
        fs.addFile("\(Self.projects)/app/bin/Debug/app.dll", size: 500)
        fs.addFile("\(Self.projects)/app/obj/project.assets.json", size: 100)

        let outcome = try create(fs).scan(binObjRule())

        #expect(outcome.items.count == 2)
        #expect(outcome.items.contains { $0.path == "\(Self.projects)/app/bin" && $0.sizeBytes == 500 })
        #expect(outcome.items.contains { $0.path == "\(Self.projects)/app/obj" && $0.sizeBytes == 100 })
    }

    @Test func skipsBinWithoutProjectFileAlongside() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/strumenti/bin/attrezzo", size: 10)
        #expect(try create(fs).scan(binObjRule()).items.isEmpty)
    }

    @Test func recognisesEveryProjectFileExtension() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/a/a.fsproj", text: "x")
        fs.addFile("\(Self.projects)/a/bin/x", size: 1)
        fs.addFile("\(Self.projects)/b/b.sln", text: "x")
        fs.addFile("\(Self.projects)/b/bin/x", size: 1)
        fs.addFile("\(Self.projects)/c/c.vbproj", text: "x")
        fs.addFile("\(Self.projects)/c/bin/x", size: 1)

        #expect(try create(fs).scan(binObjRule()).items.count == 3)
    }

    @Test func doesNotDescendIntoAFoundDirectory() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/app/bin/annidato/bin/x.dll", size: 10)

        #expect(try single(create(fs).scan(binObjRule())).path == "\(Self.projects)/app/bin")
    }

    @Test func withoutMarkerRequirementFindsDirectoriesByName() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        fs.addFile("\(nuget)/newtonsoft.json/13.0.3/pacchetto.nupkg", size: 42)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: [], maxDepth: 1))

        #expect(try single(outcome).path == "\(nuget)/newtonsoft.json")
    }

    @Test func honoursMaxDepth() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        fs.addFile("\(nuget)/pacchetto/1.0.0/dentro/file.bin", size: 5)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: [], maxDepth: 1))

        #expect(try single(outcome).path == "\(nuget)/pacchetto")
    }

    @Test func doesNotFollowSymlinkedDirectories() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/collegamento/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/collegamento/bin/x.dll", size: 10)

        #expect(try create(fs, "\(Self.projects)/collegamento").scan(binObjRule()).items.isEmpty)
    }

    // IMPORTANT 1 della revisione del Task 9: un nome escluso è un rifiuto esplicito, non un
    // mancato match: non si propone e non ci si scende dentro.
    @Test func excludedDirectoryIsSkippedEntirelyInsteadOfBeingTraversed() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        fs.addFile("\(nuget)/escluso.pacchetto/1.0.0/lib/a.dll", size: 10)
        fs.addFile("\(nuget)/normale/1.0.0/lib/b.dll", size: 20)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: ["escluso.*"], maxDepth: 1))

        #expect(try single(outcome).path == "\(nuget)/normale")
        #expect(!outcome.items.contains { $0.path.contains("escluso") })
    }

    // IMPORTANT 2 della revisione del Task 9: la potatura della deny-list in questa modalità.
    @Test func prunesDeniedBranchWithoutDescendingIntoIt() throws {
        let fs = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        fs.addFile("\(library)/Keychains/bin/segreto.pfx", size: 10)
        fs.addFile("\(library)/Caches/proj/bin/output.dll", size: 10)

        let outcome = try create(fs).scan(CleanupRule(library, .matchingDirs, include: ["bin"], exclude: []))

        #expect(outcome.exclusions.map(\.path) == ["\(library)/Keychains"])
        #expect(!outcome.exclusions.contains { $0.path.contains("bin") || $0.path.contains("segreto") })
        #expect(!outcome.errors.contains { $0.path.contains("segreto") })
        #expect(!outcome.items.contains { $0.path.contains("Keychains") })
        #expect(outcome.items.contains { $0.path == "\(library)/Caches/proj/bin" })
    }

    @Test func matchedDirectoryRejectedByGuardBecomesAnExclusionNotAnItem() throws {
        let fs = InMemoryFileSystem()
        let library = "\(Self.home)/Library"
        fs.addFile("\(library)/Keychains/login.keychain", size: 10)

        let outcome = try create(fs).scan(CleanupRule(library, .matchingDirs, include: ["Keychains"], exclude: []))

        #expect(outcome.items.isEmpty)
        #expect(outcome.exclusions.contains { $0.path == "\(library)/Keychains" })
    }

    @Test func honoursMinAgeUsingTheNewestTimestampInTheTree() throws {
        let fs = InMemoryFileSystem()
        let nuget = "\(Self.home)/.nuget/packages"
        let oldStamp = Self.now.addingTimeInterval(-days(200))
        let recentStamp = Self.now.addingTimeInterval(-days(1))

        let oldPackage = "\(nuget)/vecchio"
        fs.addFile("\(oldPackage)/lib.dll", size: 10, stamp: oldStamp)
        fs.setTimes(oldPackage, lastWrite: oldStamp, lastAccess: oldStamp)

        let recentlyUsedPackage = "\(nuget)/usato_di_recente"
        fs.addFile("\(recentlyUsedPackage)/lib.dll", size: 10, stamp: recentStamp)
        fs.setTimes(recentlyUsedPackage, lastWrite: oldStamp, lastAccess: oldStamp)

        let outcome = try create(fs).scan(CleanupRule(nuget, .matchingDirs, include: ["*"], exclude: [], minAge: days(30), maxDepth: 1))

        #expect(try single(outcome).path == oldPackage)
    }

    @Test func sumsSizeRecursivelyAcrossMultipleLevels() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/app/bin/a.dll", size: 100)
        fs.addFile("\(Self.projects)/app/bin/livello1/b.dll", size: 50)
        fs.addFile("\(Self.projects)/app/bin/livello1/livello2/c.dll", size: 25)

        let item = try single(create(fs).scan(binObjRule()))

        #expect(item.path == "\(Self.projects)/app/bin")
        #expect(item.sizeBytes == 175)
    }

    @Test func unreadableSubtreeDoesNotZeroTheTotalNorStopTheScan() throws {
        let mock = InMemoryFileSystem()
        mock.addFile("\(Self.projects)/app/app.csproj", text: "x")
        mock.addFile("\(Self.projects)/app/bin/livello1/a.dll", size: 100)
        mock.addFile("\(Self.projects)/app/bin/livello1/livello2/b.dll", size: 50)
        let unreadable = "\(Self.projects)/app/bin/protetta"
        mock.addFile("\(unreadable)/c.dll", size: 9999)

        let outcome = try create(UnreadableDirectoryFileSystem(mock, unreadablePath: unreadable)).scan(binObjRule())

        let item = try single(outcome)
        #expect(item.path == "\(Self.projects)/app/bin")
        #expect(item.sizeBytes == 150)
        #expect(outcome.errors.contains { $0.path == unreadable && $0.kind == .accessDenied })
    }

    @Test func doesNotListAMatchedDirectoryThatVanishesBeforeStatsRead() throws {
        let mock = InMemoryFileSystem()
        mock.addFile("\(Self.projects)/app/app.csproj", text: "x")
        let vanished = "\(Self.projects)/app/bin"
        mock.addFile("\(vanished)/dentro.dll", size: 10)
        mock.addFile("\(Self.projects)/app/obj/normale.bin", size: 20)

        let outcome = try create(VanishingChildFileSystem(mock, vanishingPath: vanished)).scan(binObjRule())

        #expect(!outcome.items.contains { $0.path == vanished })
        #expect(outcome.items.contains { $0.path == "\(Self.projects)/app/obj" && $0.sizeBytes == 20 })
        #expect(outcome.errors.contains { $0.path == vanished && $0.kind == .notFound })
    }

    @Test func honoursMinSizeBytes() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/app.csproj", text: "x")
        fs.addFile("\(Self.projects)/app/bin/grande.dll", size: 2000)
        fs.addFile("\(Self.projects)/app/obj/piccolo.bin", size: 10)

        #expect(try single(create(fs).scan(binObjRule(minSizeBytes: 1000))).path == "\(Self.projects)/app/bin")
    }

    @Test func projectMarkerMustBeAFileNotADirectory() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.projects)/app/x.sln/nota.txt", text: "x")
        fs.addFile("\(Self.projects)/app/bin/output.dll", size: 10)

        #expect(try create(fs).scan(binObjRule()).items.isEmpty)
    }
}
```

Riportare sopra ciascun test i commenti di revisione del file C# (`MatchingDirsTests.cs`) dove qui sono abbreviati o assenti.

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "RuleScannerTests|MatchingDirsTests"`
Expected: errore di compilazione `cannot find 'RuleScanner' in scope`.

- [ ] **Step 4: Implementare i modelli**

`Sources/CleanerCore/Scanning/ScanModels.swift`:

```swift
/// Un elemento eliminabile. `declaredRoot` serve al PathGuard per il contenimento.
public struct ScanItem: Sendable, Equatable, Hashable {
    public let path: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let declaredRoot: String

    public init(path: String, sizeBytes: Int64, isDirectory: Bool, declaredRoot: String) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.declaredRoot = declaredRoot
    }
}

public enum ScanErrorKind: Sendable, Equatable {
    case accessDenied
    case inUse
    case notFound
    case notEmpty
    case other
}

public struct ScanError: Sendable, Equatable {
    public let path: String
    public let kind: ScanErrorKind
    public let message: String

    public init(path: String, kind: ScanErrorKind, message: String) {
        self.path = path
        self.kind = kind
        self.message = message
    }
}

public struct GuardExclusion: Sendable, Equatable {
    public let path: String
    public let reason: String

    public init(path: String, reason: String) {
        self.path = path
        self.reason = reason
    }
}

public struct RuleScanOutcome: Sendable, Equatable {
    public let items: [ScanItem]
    public let errors: [ScanError]
    public let exclusions: [GuardExclusion]

    public init(items: [ScanItem], errors: [ScanError], exclusions: [GuardExclusion]) {
        self.items = items
        self.errors = errors
        self.exclusions = exclusions
    }
}

public struct CategoryScanResult: Sendable, Equatable {
    public let categoryId: String
    public let items: [ScanItem]
    public let totalBytes: Int64
    public let errors: [ScanError]
    public let exclusions: [GuardExclusion]

    public init(categoryId: String, items: [ScanItem], totalBytes: Int64, errors: [ScanError], exclusions: [GuardExclusion]) {
        self.categoryId = categoryId
        self.items = items
        self.totalBytes = totalBytes
        self.errors = errors
        self.exclusions = exclusions
    }
}

public struct ScanProgress: Sendable, Equatable {
    public let categoryId: String
    public let currentPath: String
    public let itemsFound: Int
    public let bytesFound: Int64

    public init(categoryId: String, currentPath: String, itemsFound: Int, bytesFound: Int64) {
        self.categoryId = categoryId
        self.currentPath = currentPath
        self.itemsFound = itemsFound
        self.bytesFound = bytesFound
    }
}
```

- [ ] **Step 5: Implementare `RuleScanner`**

`Sources/CleanerCore/Scanning/RuleScanner.swift`:

```swift
import Darwin
import Foundation

/// Interpreta una singola regola. Non segue mai i collegamenti simbolici.
public struct RuleScanner: Sendable {
    private let fileSystem: any FileSystem
    private let pathGuard: any PathGuarding
    private let links: any LinkInspecting
    private let clock: any WallClock

    private static let projectMarkers = ["*.csproj", "*.fsproj", "*.vbproj", "*.sln", "*.slnx"]

    /// Nomi di cartelle di metadati dei sistemi di controllo versione: mai attraversate.
    private static let vcsDirectoryNames = [".git", ".hg", ".svn"]

    /// Prima data considerata un vero timestamp anziché una sentinella (1990-01-01 UTC).
    private static let minDeterminableStamp = Date(timeIntervalSince1970: 631_152_000)

    public init(fileSystem: any FileSystem, pathGuard: any PathGuarding, links: any LinkInspecting, clock: any WallClock) {
        self.fileSystem = fileSystem
        self.pathGuard = pathGuard
        self.links = links
        self.clock = clock
    }

    /// Lancia solo `CancellationError`: ogni altro problema diventa un errore o un'esclusione
    /// dell'esito.
    public func scan(_ rule: CleanupRule) throws -> RuleScanOutcome {
        var accumulator = Accumulator()

        // Root assente: categoria vuota, non errore.
        guard fileSystem.directoryExists(rule.root) else { return accumulator.outcome }

        // La root si valida una volta sola, risalendo fino alla radice del filesystem: se la root
        // o un suo antenato è un collegamento, ogni elemento trovato sotto punterebbe altrove. È
        // il caso di chi sposta ~/Library/Caches su un disco esterno con un collegamento.
        let rootVerdict = pathGuard.validateRoot(rule.root)
        guard rootVerdict.isAllowed else {
            accumulator.exclusions.append(GuardExclusion(path: rule.root, reason: rootVerdict.reason))
            return accumulator.outcome
        }

        switch rule.mode {
        case .clearContents:
            try scanContents(rule, &accumulator)
        case .matchingFiles:
            try scanFiles(rule, rule.root, depth: 0, &accumulator)
        case .matchingDirs:
            try scanDirectories(rule, rule.root, depth: 0, &accumulator)
        }

        return accumulator.outcome
    }

    // MARK: - Classificazione degli errori

    /// Stessa mappatura di `RuleScanner.Describe` in C#, applicata all'errno da cui .NET ricavava
    /// il tipo di eccezione: EACCES/EPERM/EBADF → accesso negato (UnauthorizedAccessException),
    /// ENOENT → non trovato, ENOTEMPTY → non vuota, qualunque altro errno → in uso (in C# ogni
    /// IOException residua cadeva lì). Un errore che non viene dal filesystem è "altro".
    static func describe(_ path: String, _ error: any Error) -> ScanError {
        guard let fileSystemError = error as? FileSystemError else {
            return ScanError(path: path, kind: .other, message: String(describing: error))
        }

        let kind: ScanErrorKind
        switch fileSystemError.code {
        case EACCES, EPERM, EBADF: kind = .accessDenied
        case ENOENT: kind = .notFound
        case ENOTEMPTY: kind = .notEmpty
        default: kind = .inUse
        }
        return ScanError(path: path, kind: kind, message: fileSystemError.message)
    }

    /// Gli errori "previsti" (in C#: `UnauthorizedAccessException` o `IOException`).
    static func isExpected(_ error: any Error) -> Bool {
        error is FileSystemError
    }

    // MARK: - Modalità

    private func scanContents(_ rule: CleanupRule, _ accumulator: inout Accumulator) throws {
        for entry in enumerate(rule.root, &accumulator.errors) {
            try Task.checkCancellation()

            guard Self.matchesGlobs(PathText.fileName(entry), rule) else { continue }

            // Il verdetto del guard precede qualunque lettura di statistiche: per una cartella
            // negata (es. "~/Library/Keychains") calcolarle richiederebbe di attraversarla, e gli
            // errori di lettura sui file privati al suo interno finirebbero nell'elenco mostrato
            // all'utente prima ancora che l'elemento risulti escluso.
            let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
            guard verdict.isAllowed else {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                continue
            }

            let isLink = links.isSymbolicLink(entry)
            let isDirectory = !isLink && fileSystem.directoryExists(entry)
            let size: Int64

            if isLink {
                // Non si attraversa mai il bersaglio per calcolarne la dimensione (resta 0). Il
                // filtro di età legge le date del collegamento stesso (lstat), come FileInfo e
                // DirectoryInfo di .NET: il commento C# che parlava del bersaglio era impreciso.
                guard accept(entry, rule, &accumulator.errors) else { continue }
                size = 0
            } else if isDirectory {
                // Età e dimensione nello stesso attraversamento: l'mtime di una cartella non cambia
                // quando un file interno viene riscritto sul posto, quindi conta il timestamp più
                // recente dell'albero.
                let stats = try directoryStats(entry, &accumulator.errors)
                // Scomparsa o illeggibile fra l'enumerazione e questo punto: non va proposta,
                // altrimenti comparirebbe sia fra gli errori sia fra gli elementi.
                guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { continue }
                size = stats.size
            } else {
                // Un file scomparso fra enumerazione e lettura della dimensione va annotato come
                // errore, non proposto con dimensione 0.
                guard let fileSize = tryFileSize(entry, &accumulator.errors) else { continue }
                guard accept(entry, rule, &accumulator.errors) else { continue }
                size = fileSize
            }

            if let minSize = rule.minSizeBytes, size < minSize { continue }

            accumulator.items.append(ScanItem(path: entry, sizeBytes: size, isDirectory: isDirectory, declaredRoot: rule.root))
        }
    }

    private func scanFiles(_ rule: CleanupRule, _ directory: String, depth: Int, _ accumulator: inout Accumulator) throws {
        guard depth <= rule.maxDepth else { return }

        for entry in enumerate(directory, &accumulator.errors) {
            try Task.checkCancellation()

            if links.isSymbolicLink(entry) { continue }

            if fileSystem.directoryExists(entry) {
                // Ramo saltato per intero: sotto ".git" vivono i pack file con l'intera storia del
                // repository, indistinguibili da un file grande legittimo. Non è nella deny-list,
                // che ragiona per percorsi assoluti fissi, non per nomi che compaiono ovunque.
                if Self.isVersionControlDirectory(PathText.fileName(entry)) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: Self.vcsExclusionReason))
                    continue
                }

                // Pota il ramo intero: un'esclusione per cartella protetta invece di una per file,
                // che ne rivelerebbe i nomi. Solo la deny-list: la regola di profondità di validate
                // poterebbe ogni cartella legittima di primo livello sotto la home.
                if let pruneReason = pathGuard.pruneReason(entry) {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: pruneReason))
                    continue
                }

                try scanFiles(rule, entry, depth: depth + 1, &accumulator)
                continue
            }

            guard Self.matchesGlobs(PathText.fileName(entry), rule), accept(entry, rule, &accumulator.errors) else { continue }
            guard let size = tryFileSize(entry, &accumulator.errors) else { continue }
            if let minSize = rule.minSizeBytes, size < minSize { continue }

            let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
            guard verdict.isAllowed else {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                continue
            }

            accumulator.items.append(ScanItem(path: entry, sizeBytes: size, isDirectory: false, declaredRoot: rule.root))
        }
    }

    /// Cerca ricorsivamente cartelle il cui nome corrisponde ai pattern (bin/obj, pacchetti NuGet).
    /// Una cartella trovata non viene mai attraversata oltre: sarà eliminata per intero.
    private func scanDirectories(_ rule: CleanupRule, _ directory: String, depth: Int, _ accumulator: inout Accumulator) throws {
        guard depth <= rule.maxDepth else { return }

        for entry in enumerate(directory, &accumulator.errors) {
            try Task.checkCancellation()

            if links.isSymbolicLink(entry) || !fileSystem.directoryExists(entry) { continue }

            let name = PathText.fileName(entry)

            // Stesso ramo saltato di scanFiles, prima di ogni altra valutazione: non si entra mai
            // in ".git"/".hg"/".svn" e non li si propone, anche se il nome corrispondesse.
            if Self.isVersionControlDirectory(name) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: Self.vcsExclusionReason))
                continue
            }

            // Un'esclusione è un rifiuto esplicito, non un "continua a cercare più in basso":
            // scendervi proporrebbe una singola versione di un pacchetto escluso.
            if Self.matchesAnyGlob(name, rule.excludeGlobs) { continue }

            var matches = Self.matchesAnyGlob(name, rule.includeGlobs)
            if matches && rule.requiresProjectMarker {
                matches = hasProjectMarker(directory, &accumulator.errors)
            }

            if matches {
                // Il verdetto del guard precede la lettura di dimensione ed età, come in scanContents.
                let verdict = pathGuard.validate(entry, declaredRoot: rule.root)
                guard verdict.isAllowed else {
                    accumulator.exclusions.append(GuardExclusion(path: entry, reason: verdict.reason))
                    continue
                }

                let stats = try directoryStats(entry, &accumulator.errors)
                guard stats.determinable, acceptStamp(stats.newest, rule.minAge) else { continue }
                if let minSize = rule.minSizeBytes, stats.size < minSize { continue }

                accumulator.items.append(ScanItem(path: entry, sizeBytes: stats.size, isDirectory: true, declaredRoot: rule.root))
                // Trovata: non si scende oltre, l'intera cartella verrà eliminata.
                continue
            }

            if let pruneReason = pathGuard.pruneReason(entry) {
                accumulator.exclusions.append(GuardExclusion(path: entry, reason: pruneReason))
                continue
            }

            try scanDirectories(rule, entry, depth: depth + 1, &accumulator)
        }
    }

    // MARK: - Supporto

    private struct Accumulator {
        var items: [ScanItem] = []
        var errors: [ScanError] = []
        var exclusions: [GuardExclusion] = []

        var outcome: RuleScanOutcome { RuleScanOutcome(items: items, errors: errors, exclusions: exclusions) }
    }

    private static var vcsExclusionReason: String {
        String(localized: "repository di controllo versione: ramo saltato per non cancellare la storia del progetto", bundle: .module)
    }

    private static func isVersionControlDirectory(_ name: String) -> Bool {
        vcsDirectoryNames.contains { PathText.equalsIgnoringCase($0, name) }
    }

    /// Vera se la cartella che contiene il candidato ospita un file di progetto. Senza questo
    /// vincolo una root mal configurata (es. "/usr") porterebbe a proporre "/usr/bin": il
    /// PathGuard la bloccherebbe comunque, ma questo è il primo filtro.
    private func hasProjectMarker(_ parentDirectory: String, _ errors: inout [ScanError]) -> Bool {
        for sibling in enumerate(parentDirectory, &errors) {
            // Un marcatore è sempre un file: una cartella chiamata "x.sln" non deve soddisfarlo.
            if fileSystem.directoryExists(sibling) { continue }
            let name = PathText.fileName(sibling)
            if Self.projectMarkers.contains(where: { SimpleGlob.matches($0, name) }) { return true }
        }
        return false
    }

    /// Filtro di età sul percorso stesso (file o collegamento), mai per le cartelle in
    /// clearContents, la cui età si calcola sull'albero con `acceptStamp`.
    private func accept(_ path: String, _ rule: CleanupRule, _ errors: inout [ScanError]) -> Bool {
        guard let minAge = rule.minAge else { return true }
        do {
            return acceptStamp(try fileSystem.itemInfo(path).newestStamp, minAge)
        } catch let error as FileSystemError where error.code == ENOENT {
            // .NET restituiva la sentinella 1601-01-01 senza lanciare: età massima, filtro superato.
            return true
        } catch {
            errors.append(Self.describe(path, error))
            return false
        }
    }

    private func acceptStamp(_ stamp: Date, _ minAge: TimeInterval?) -> Bool {
        guard let minAge else { return true }
        return clock.now.timeIntervalSince(stamp) >= minAge
    }

    private static func matchesGlobs(_ name: String, _ rule: CleanupRule) -> Bool {
        !matchesAnyGlob(name, rule.excludeGlobs) && matchesAnyGlob(name, rule.includeGlobs)
    }

    private static func matchesAnyGlob(_ name: String, _ globs: [String]) -> Bool {
        globs.contains { SimpleGlob.matches($0, name) }
    }

    /// Elenca una cartella senza mai far fallire l'intera scansione per un ramo illeggibile: mount
    /// virtuali come "~/Library/Developer/CoreDevice/DeviceFS" rispondono con errori imprevedibili,
    /// e l'utente non può essere tenuto a escludere a mano ogni percorso problematico.
    private func enumerate(_ directory: String, _ errors: inout [ScanError]) -> [String] {
        do {
            return try fileSystem.contentsOfDirectory(directory)
        } catch {
            errors.append(Self.describe(directory, error))
            return []
        }
    }

    /// Dimensione totale, timestamp più recente e determinabilità di una cartella in un solo
    /// attraversamento, saltando i collegamenti. La determinabilità riguarda solo il timestamp
    /// della cartella passata: una sottocartella scomparsa contribuisce 0 e non invalida il totale.
    private func directoryStats(_ directory: String, _ errors: inout [ScanError]) throws -> (size: Int64, newest: Date, determinable: Bool) {
        var total: Int64 = 0
        let ownStamp = readDirectoryStamp(directory, &errors)
        var newest = ownStamp ?? .distantPast

        for entry in enumerate(directory, &errors) {
            try Task.checkCancellation()

            if links.isSymbolicLink(entry) { continue }

            if fileSystem.directoryExists(entry) {
                let child = try directoryStats(entry, &errors)
                total += child.size
                if child.newest > newest { newest = child.newest }
            } else {
                let file = fileSizeAndStamp(entry, &errors)
                total += file.size
                if file.stamp > newest { newest = file.stamp }
            }
        }

        return (total, newest, ownStamp != nil)
    }

    /// Il timestamp più recente di una cartella, o `nil` se non è determinabile. Su una cartella
    /// scomparsa .NET non lanciava ma restituiva la sentinella 1601-01-01: per questo `ENOENT`
    /// produce `nil` senza registrare errori. Le date precedenti al 1990 restano trattate come
    /// sentinelle, come in C#.
    private func readDirectoryStamp(_ path: String, _ errors: inout [ScanError]) -> Date? {
        do {
            let stamp = try fileSystem.itemInfo(path).newestStamp
            return stamp < Self.minDeterminableStamp ? nil : stamp
        } catch let error as FileSystemError where error.code == ENOENT {
            return nil
        } catch {
            errors.append(Self.describe(path, error))
            return nil
        }
    }

    /// Dimensione e timestamp di un file sommato dentro una cartella, in un solo accesso, per non
    /// registrare due errori per lo stesso motivo.
    private func fileSizeAndStamp(_ path: String, _ errors: inout [ScanError]) -> (size: Int64, stamp: Date) {
        do {
            let info = try fileSystem.itemInfo(path)
            // Come FileInfo.Length di .NET su una cartella.
            guard info.kind != .directory else { throw FileSystemError(code: ENOENT, path: path) }
            return (info.size, info.newestStamp)
        } catch {
            errors.append(Self.describe(path, error))
            return (0, clock.now)
        }
    }

    /// Dimensione di un file che diventerà esso stesso un elemento. Un fallimento "non trovato"
    /// restituisce `nil` (l'elemento non va proposto); ogni altro fallimento è registrato e
    /// l'elemento resta proposto con dimensione 0, come in C#.
    private func tryFileSize(_ path: String, _ errors: inout [ScanError]) -> Int64? {
        do {
            return try fileSystem.fileLength(path)
        } catch {
            let scanError = Self.describe(path, error)
            errors.append(scanError)
            return scanError.kind == .notFound ? nil : 0
        }
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "RuleScannerTests|MatchingDirsTests"`
Expected: `Test run with 38 tests … passed`.

- [ ] **Step 7: Registro di parità e commit**

Righe `Scanning/RuleScannerTests.cs` (22) e `Scanning/MatchingDirsTests.cs` (16) compilate. Tabella differenze: `| Commento sull'età dei collegamenti in ClearContents | diceva «timestamp del bersaglio» | corretto: lstat del collegamento, come .NET misurato | solo commento |`.

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port RuleScanner with scan models and matching-dirs tests

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `ScanEngine`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Scanning/ScanEngine.swift`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/TestSupport.swift` (aggiungere `Recorder`)
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ScanEngineTests.swift`
- Reference: `src/MjmCleaner.Core/Scanning/ScanEngine.cs`, `tests/MjmCleaner.Core.Tests/Scanning/ScanEngineTests.cs`

**Interfaces:**
- Consumes: `RuleScanner`, modelli di scansione (Task 7); `CleanupCategory`, `CleanupRule` (Task 6).
- Produces:
  - `public protocol ScanPerforming: Sendable` — `func scan(_ categories: [CleanupCategory], progress: (@Sendable (ScanProgress) -> Void)?) async throws -> [CategoryScanResult]`
  - `public struct ScanEngine: ScanPerforming` — `init(scanner: RuleScanner)`
  - test: `final class Recorder<Value: Sendable>: Sendable` — `func append(_:)`, `var values: [Value]`

- [ ] **Step 1: Aggiungere `Recorder` a `TestSupport.swift`**

In fondo a `Tests/CleanerCoreTests/Support/TestSupport.swift` (aggiungere anche `import Synchronization` in testa al file):

```swift
/// Raccoglie valori da callback `@Sendable` (avanzamento, diario): l'equivalente della lista
/// protetta da `lock` nei test C#.
final class Recorder<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}
```

- [ ] **Step 2: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Scanning/ScanEngineTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct ScanEngineTests {
    private static let home = "/Users/tester"
    private static let now = utc(2026, 9, 15, 12)
    private static let all = ["*"]

    private func create(_ fs: InMemoryFileSystem) throws -> ScanEngine {
        let links = FakeLinkInspector()
        let scanner = RuleScanner(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            links: links,
            clock: FixedWallClock(now: Self.now))
        return ScanEngine(scanner: scanner)
    }

    private func category(_ id: String, _ rules: CleanupRule...) -> CleanupCategory {
        CleanupCategory(id: id, displayName: id, description: "", risk: .low, selectedByDefault: true, parentId: nil, rules: rules)
    }

    private func clearContents(_ root: String) -> CleanupRule {
        CleanupRule(root, .clearContents, include: Self.all, exclude: [])
    }

    @Test func aggregatesBytesPerCategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 100)
        fs.addFile("\(Self.home)/Library/Caches/b.tmp", size: 50)

        let results = try await create(fs).scan([category("caches", clearContents("\(Self.home)/Library/Caches"))], progress: nil)

        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.categoryId == "caches")
        #expect(result.totalBytes == 150)
        #expect(result.items.count == 2)
    }

    @Test func mergesItemsFromAllRulesOfACategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        fs.addFile("\(Self.home)/.cache/b.tmp", size: 20)

        let results = try await create(fs).scan(
            [category("misto", clearContents("\(Self.home)/Library/Caches"), clearContents("\(Self.home)/.cache"))],
            progress: nil)

        #expect(results.map(\.totalBytes) == [30])
    }

    @Test func returnsOneResultPerCategoryInInputOrder() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        fs.addFile("\(Self.home)/.cache/b.tmp", size: 10)

        let results = try await create(fs).scan(
            [category("uno", clearContents("\(Self.home)/Library/Caches")), category("due", clearContents("\(Self.home)/.cache"))],
            progress: nil)

        #expect(results.map(\.categoryId) == ["uno", "due"])
    }

    @Test func reportsProgressForEachCategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        let reported = Recorder<ScanProgress>()

        _ = try await create(fs).scan(
            [category("caches", clearContents("\(Self.home)/Library/Caches"))],
            progress: { reported.append($0) })

        #expect(reported.values.contains { $0.categoryId == "caches" })
    }

    @Test func cancellationPropagates() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Library/Caches/a.tmp", size: 10)
        let engine = try create(fs)
        let categories = [category("caches", clearContents("\(Self.home)/Library/Caches"))]

        let task = Task {
            cancelCurrentTask()
            return try await engine.scan(categories, progress: nil)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func categoryWithoutRulesYieldsEmptyResult() async throws {
        let results = try await create(InMemoryFileSystem()).scan([category("vuota")], progress: nil)

        let result = try #require(results.first)
        #expect(result.totalBytes == 0)
        #expect(result.items.isEmpty)
    }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter ScanEngineTests`
Expected: errore di compilazione `cannot find 'ScanEngine' in scope`.

- [ ] **Step 4: Implementare `ScanEngine`**

`Sources/CleanerCore/Scanning/ScanEngine.swift`:

```swift
public protocol ScanPerforming: Sendable {
    func scan(
        _ categories: [CleanupCategory],
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [CategoryScanResult]
}

/// Scansiona le categorie in parallelo: attraversare ~/Library/Caches significa centinaia di
/// migliaia di file e l'interfaccia deve restare reattiva. `@concurrent` garantisce che il lavoro
/// non giri mai sul main actor del chiamante.
public struct ScanEngine: ScanPerforming {
    private let scanner: RuleScanner

    public init(scanner: RuleScanner) {
        self.scanner = scanner
    }

    @concurrent
    public func scan(
        _ categories: [CleanupCategory],
        progress: (@Sendable (ScanProgress) -> Void)?
    ) async throws -> [CategoryScanResult] {
        try Task.checkCancellation()

        return try await withThrowingTaskGroup(of: (Int, CategoryScanResult).self) { group in
            for (index, category) in categories.enumerated() {
                group.addTask {
                    let result = try scanCategory(category, progress)
                    return (index, result)
                }
            }

            var collected: [(Int, CategoryScanResult)] = []
            for try await result in group {
                collected.append(result)
            }
            // L'ordine dei risultati è quello delle categorie in ingresso, come Task.WhenAll in C#.
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func scanCategory(
        _ category: CleanupCategory,
        _ progress: (@Sendable (ScanProgress) -> Void)?
    ) throws -> CategoryScanResult {
        var items: [ScanItem] = []
        var errors: [ScanError] = []
        var exclusions: [GuardExclusion] = []

        for rule in category.rules {
            try Task.checkCancellation()

            let outcome = try scanner.scan(rule)
            items += outcome.items
            errors += outcome.errors
            exclusions += outcome.exclusions

            progress?(ScanProgress(
                categoryId: category.id,
                currentPath: rule.root,
                itemsFound: items.count,
                bytesFound: items.reduce(0) { $0 + $1.sizeBytes }))
        }

        let total = items.reduce(0) { $0 + $1.sizeBytes }
        progress?(ScanProgress(categoryId: category.id, currentPath: "", itemsFound: items.count, bytesFound: total))

        return CategoryScanResult(categoryId: category.id, items: items, totalBytes: total, errors: errors, exclusions: exclusions)
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter ScanEngineTests`
Expected: `Test run with 6 tests … passed`.

- [ ] **Step 6: Registro di parità e commit**

Riga `Scanning/ScanEngineTests.cs` (6) compilata. Nota: «`Progress<T>` + `Task.Delay(50)` → callback sincrono raccolto da `Recorder`».

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port ScanEngine with parallel category scanning

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Cleaning: `CleanEngine`, `ConfirmationRows`, aggancio del diario

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Cleaning/CleanModels.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Cleaning/CleanEngine.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Cleaning/ConfirmationRows.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/CleanEngineTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/ConfirmationRowsTests.swift`
- Reference: `src/MjmCleaner.Core/Cleaning/*.cs`, `tests/MjmCleaner.Core.Tests/Cleaning/*.cs`

**Interfaces:**
- Consumes: `FileSystem`, `FileSystemError`, `WallClock`, `PathText` (Task 1–2); `PathGuarding`, `GuardVerdict`, `PathGuard`, `DenyList` (Task 4); `ScanItem`, `ScanError`, `CategoryScanResult`, `RuleScanner.describe` (Task 7); doppi e `Recorder` (Task 3, 8).
- Produces:
  - `public struct CategorySelection: Sendable, Equatable` — `categoryId`, `items: [ScanItem]`; `init(categoryId:items:)`
  - `public struct CategoryCleanResult: Sendable, Equatable` — `categoryId`, `bytesFreed: Int64`, `itemsDeleted: Int`
  - `public struct CleanProgress: Sendable, Equatable` — `currentPath`, `itemsDone`, `itemsTotal`, `bytesFreed: Int64`
  - `public struct CleanReport: Sendable, Equatable` — `startedAt: Date`, `duration: Duration`, `bytesFreed: Int64`, `itemsDeleted: Int`, `itemsFailed: Int`, `categories: [CategoryCleanResult]`, `errors: [ScanError]`, `deletedPaths: [String]`; `init(...)` con tutti i campi
  - `public protocol DeletionRecording: Sendable` — `func recordDeleted(_ path: String)`
  - `public protocol CleanPerforming: Sendable` — `func clean(_ selections: [CategorySelection], progress: (@Sendable (CleanProgress) -> Void)?, journal: (any DeletionRecording)?) async -> CleanReport`
  - `public struct CleanEngine: CleanPerforming` — `init(fileSystem: any FileSystem, pathGuard: any PathGuarding, clock: any WallClock)`
  - `public struct ConfirmationCategory: Sendable, Equatable` — `categoryId`, `items`; `public enum ConfirmationRows` — `static func build(_ results: [CategoryScanResult]) -> [ConfirmationCategory]`

- [ ] **Step 1: Scrivere i test di `CleanEngine` (falliscono)**

`Tests/CleanerCoreTests/Cleaning/CleanEngineTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct CleanEngineTests {
    private static let home = "/Users/tester"
    private static let cacheRoot = "/Users/tester/Library/Caches"
    private static let now = utc(2026, 9, 15, 12)

    private func create(_ fs: any FileSystem, _ symlinks: String...) throws -> CleanEngine {
        let links = FakeLinkInspector(symlinks)
        return CleanEngine(
            fileSystem: fs,
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
            clock: FixedWallClock(now: Self.now))
    }

    private func create(_ fs: any FileSystem, targets: [String: String?]) throws -> CleanEngine {
        CleanEngine(
            fileSystem: fs,
            pathGuard: try PathGuard(
                denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(targets: targets), homeDirectory: Self.home),
            clock: FixedWallClock(now: Self.now))
    }

    private func selection(_ id: String, _ items: ScanItem...) -> CategorySelection {
        CategorySelection(categoryId: id, items: items)
    }

    private func item(_ path: String, _ size: Int64, isDirectory: Bool = false, root: String = Self.cacheRoot) -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: isDirectory, declaredRoot: root)
    }

    /// Porting di `RedirectingPathGuard`: ammette sempre, ma `validate` restituisce di proposito un
    /// percorso DIVERSO dall'argomento. Ancora "si valida un percorso, si cancella QUEL percorso".
    private struct RedirectingPathGuard: PathGuarding {
        let root: String
        let redirectTarget: String

        func validateRoot(_ declaredRoot: String) -> GuardVerdict { .allow(root) }
        func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict { .allow(redirectTarget) }
        func pruneReason(_ candidatePath: String) -> String? { nil }
    }

    @Test func deletesFilesAndCountsBytes() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 100)

        let report = try await create(fs).clean([selection("caches", item("\(Self.cacheRoot)/a.tmp", 100))], progress: nil, journal: nil)

        #expect(!fs.fileExists("\(Self.cacheRoot)/a.tmp"))
        #expect(report.bytesFreed == 100)
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
    }

    @Test func deletesDirectoriesRecursively() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/app/dentro/x.bin", size: 40)

        let report = try await create(fs).clean(
            [selection("caches", item("\(Self.cacheRoot)/app", 40, isDirectory: true))], progress: nil, journal: nil)

        #expect(!fs.directoryExists("\(Self.cacheRoot)/app"))
        #expect(report.bytesFreed == 40)
    }

    @Test func guardRejectionPreventsDeletion() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.home)/Documents/riservato.pdf", size: 10)

        // Elemento fabbricato a mano: simula una regola sbagliata che arriva fino all'eliminazione.
        let report = try await create(fs).clean(
            [selection("bug", item("\(Self.home)/Documents/riservato.pdf", 10, root: Self.home))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(Self.home)/Documents/riservato.pdf"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
    }

    @Test func missingFileIsRecordedButNotFatal() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/esiste.tmp", size: 10)

        let report = try await create(fs).clean(
            [selection("caches", item("\(Self.cacheRoot)/sparito.tmp", 999), item("\(Self.cacheRoot)/esiste.tmp", 10))],
            progress: nil, journal: nil)

        #expect(report.bytesFreed == 10)
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 1)
        #expect(report.errors.contains { $0.kind == .notFound })
    }

    @Test func onlyActuallyFreedBytesAreCounted() async throws {
        let report = try await create(InMemoryFileSystem()).clean(
            [selection("caches", item("\(Self.cacheRoot)/mai-esistito.tmp", 5_000))], progress: nil, journal: nil)
        #expect(report.bytesFreed == 0)

        // Dimensione dichiarata falsa: il resoconto riporta i byte MISURATI subito prima della
        // cancellazione, non quelli dichiarati dall'interfaccia.
        let lied = InMemoryFileSystem()
        lied.addFile("\(Self.cacheRoot)/piccola/dentro/x.bin", size: 10)

        let liedReport = try await create(lied).clean(
            [selection("caches", item("\(Self.cacheRoot)/piccola", 5_000_000_000, isDirectory: true))], progress: nil, journal: nil)

        #expect(!lied.directoryExists("\(Self.cacheRoot)/piccola"))
        #expect(liedReport.bytesFreed == 10)
    }

    @Test func resultsAreGroupedByCategory() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.home)/.cache/b.tmp", size: 20)

        let report = try await create(fs).clean(
            [
                selection("uno", item("\(Self.cacheRoot)/a.tmp", 10)),
                selection("due", item("\(Self.home)/.cache/b.tmp", 20, root: "\(Self.home)/.cache")),
            ],
            progress: nil, journal: nil)

        #expect(report.categories.filter { $0.categoryId == "uno" }.map(\.bytesFreed) == [10])
        #expect(report.categories.filter { $0.categoryId == "due" }.map(\.bytesFreed) == [20])
        #expect(report.bytesFreed == 30)
    }

    @Test func deletedPathsAreRecordedForTheSessionLog() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)

        let report = try await create(fs).clean([selection("caches", item("\(Self.cacheRoot)/a.tmp", 10))], progress: nil, journal: nil)

        #expect(report.deletedPaths == ["\(Self.cacheRoot)/a.tmp"])
    }

    @Test func cancellationReturnsPartialReportInsteadOfThrowing() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        let engine = try create(fs)
        let selections = [selection("caches", item("\(Self.cacheRoot)/a.tmp", 10))]

        let report = await Task {
            cancelCurrentTask()
            return await engine.clean(selections, progress: nil, journal: nil)
        }.value

        #expect(report.itemsDeleted == 0)
        #expect(fs.fileExists("\(Self.cacheRoot)/a.tmp"))
    }

    // CRITICAL: l'elenco arriva dall'interfaccia dopo la conferma, quindi è manipolabile. Una root
    // fabbricata che è in realtà un collegamento verso una cartella protetta deve fallire alla
    // convalida della ROOT, perché validate da solo si ferma proprio alla root quando questa è
    // il genitore diretto dell'elemento — il caso di ogni elemento clearContents.
    @Test func fabricatedDeclaredRootResolvingToProtectedPathIsRejected() async throws {
        let fakeRoot = "\(Self.cacheRoot)/finto"
        let fs = InMemoryFileSystem()
        fs.addFile("\(fakeRoot)/contratto.pdf", size: 10)

        let report = try await create(fs, targets: [fakeRoot: "\(Self.home)/Documents"]).clean(
            [selection("bug", item("\(fakeRoot)/contratto.pdf", 10, root: fakeRoot))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(fakeRoot)/contratto.pdf"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.deletedPaths.isEmpty)
    }

    @Test func fabricatedDeclaredRootResolvingToProtectedPathRejectsDirectoryRecursively() async throws {
        let fakeRoot = "\(Self.cacheRoot)/finto2"
        let fs = InMemoryFileSystem()
        fs.addFile("\(fakeRoot)/fatture2026/gennaio.pdf", size: 10)

        let report = try await create(fs, targets: [fakeRoot: "\(Self.home)/Documents"]).clean(
            [selection("bug", item("\(fakeRoot)/fatture2026", 10, isDirectory: true, root: fakeRoot))], progress: nil, journal: nil)

        #expect(fs.directoryExists("\(fakeRoot)/fatture2026"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.deletedPaths.isEmpty)
    }

    // Fra la scansione e la conferma ~/Library/Caches è stata sostituita da un collegamento verso
    // ~/Documents: validateRoot viene richiamato qui, subito prima della cancellazione, apposta.
    @Test func rootReplacedBySymlinkAfterScanRejectsOtherwiseLegitimateItem() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/tesi.docx", size: 10)

        let report = try await create(fs, targets: [Self.cacheRoot: "\(Self.home)/Documents"]).clean(
            [selection("caches", item("\(Self.cacheRoot)/tesi.docx", 10))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(Self.cacheRoot)/tesi.docx"))
        #expect(report.bytesFreed == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.deletedPaths.isEmpty)
    }

    // IMPORTANT 2: un errore fuori contratto non deve far perdere il resoconto: l'elenco di ciò
    // che è già stato cancellato è l'unica ricostruzione possibile di cosa è sparito.
    @Test func unexpectedExceptionDuringDeletionReturnsPartialReportInsteadOfThrowing() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/uno.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/due.tmp", size: 20)
        fs.addFile("\(Self.cacheRoot)/tre.tmp", size: 30)

        let report = try await create(ThrowingOnDeleteFileSystem(fs, throwingPath: "\(Self.cacheRoot)/due.tmp")).clean(
            [selection("caches",
                       item("\(Self.cacheRoot)/uno.tmp", 10),
                       item("\(Self.cacheRoot)/due.tmp", 20),
                       item("\(Self.cacheRoot)/tre.tmp", 30))],
            progress: nil, journal: nil)

        // Il primo elemento, cancellato prima del guasto, resta nel resoconto...
        #expect(report.deletedPaths.contains("\(Self.cacheRoot)/uno.tmp"))
        #expect(report.bytesFreed == 10)
        #expect(report.itemsDeleted == 1)
        // ...l'errore imprevisto compare fra gli errori invece di propagare...
        #expect(report.itemsFailed == 1)
        #expect(!report.errors.isEmpty)
        // ...e il terzo elemento, mai raggiunto, non risulta né eliminato né tentato.
        #expect(fs.fileExists("\(Self.cacheRoot)/due.tmp"))
        #expect(fs.fileExists("\(Self.cacheRoot)/tre.tmp"))
    }

    // MINOR 1: due selezioni con lo stesso identificativo producono UNA voce con i totali sommati.
    @Test func duplicateCategoryIdsAreMergedIntoOneReportEntry() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/b.tmp", size: 20)

        let report = try await create(fs).clean(
            [selection("caches", item("\(Self.cacheRoot)/a.tmp", 10)), selection("caches", item("\(Self.cacheRoot)/b.tmp", 20))],
            progress: nil, journal: nil)

        #expect(report.categories == [CategoryCleanResult(categoryId: "caches", bytesFreed: 30, itemsDeleted: 2)])
    }

    // MINOR 2: un elemento respinto dal guard non salta la segnalazione di avanzamento.
    @Test func progressReachesTheEndEvenWithRejectedItems() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.home)/Documents/riservato.pdf", size: 10)
        let progress = Recorder<CleanProgress>()

        _ = try await create(fs).clean(
            [selection("misto", item("\(Self.cacheRoot)/a.tmp", 10), item("\(Self.home)/Documents/riservato.pdf", 10, root: Self.home))],
            progress: { progress.append($0) }, journal: nil)

        let last = try #require(progress.values.last)
        #expect(last.itemsDone == 2)
        #expect(last.itemsTotal == 2)
    }

    // IMPORTANT: se validateRoot risolve la root a una stringa diversa ($TMPDIR: "/var" è un
    // collegamento a "/private/var" su ogni Mac), l'elemento va riportato nello stesso sistema di
    // riferimento PRIMA di validarlo, altrimenti la categoria $TMPDIR sarebbe inservibile.
    @Test func itemUnderRootThatResolvesToADifferentStringIsStillDeletable() async throws {
        let declaredTmpRoot = "/var/folders/xyz/T"
        let resolvedTmpRoot = "/private/var/folders/xyz/T"
        let fs = InMemoryFileSystem()
        fs.addFile("\(resolvedTmpRoot)/temp123.tmp", size: 15)

        let report = try await create(fs, targets: ["/var": "/private/var"]).clean(
            [selection("tmp", item("\(declaredTmpRoot)/temp123.tmp", 15, root: declaredTmpRoot))], progress: nil, journal: nil)

        #expect(report.bytesFreed == 15)
        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 0)
        // Si cancella il percorso RISOLTO restituito dal guard, non quello dichiarato.
        #expect(report.deletedPaths == ["\(resolvedTmpRoot)/temp123.tmp"])
        #expect(!fs.fileExists("\(resolvedTmpRoot)/temp123.tmp"))
    }

    // Porting di MalformedItemWithNullDeclaredRootDoesNotAbortTheWholeRun: in Swift una root nulla
    // è impossibile per tipo; l'equivalente malformato è la root vuota. Solo quell'elemento fallisce.
    @Test func malformedItemWithEmptyDeclaredRootDoesNotAbortTheWholeRun() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/uno.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/tre.tmp", size: 30)

        let report = try await create(fs).clean(
            [selection("caches",
                       item("\(Self.cacheRoot)/uno.tmp", 10),
                       item("qualunque/percorso", 20, root: ""),
                       item("\(Self.cacheRoot)/tre.tmp", 30))],
            progress: nil, journal: nil)

        #expect(report.itemsDeleted == 2)
        #expect(report.itemsFailed == 1)
        #expect(report.bytesFreed == 40)
        #expect(!fs.fileExists("\(Self.cacheRoot)/uno.tmp"))
        #expect(!fs.fileExists("\(Self.cacheRoot)/tre.tmp"))
    }

    // Annullamento A METÀ (dopo la prima categoria): le categorie mai iniziate non compaiono nel
    // resoconto nemmeno a zero.
    @Test func cancellationMidRunDoesNotAddUnprocessedCategoriesToTheReport() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/uno.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/due.tmp", size: 20)
        fs.addFile("\(Self.cacheRoot)/tre.tmp", size: 30)
        let engine = try create(fs)
        let selections = [
            selection("uno", item("\(Self.cacheRoot)/uno.tmp", 10)),
            selection("due", item("\(Self.cacheRoot)/due.tmp", 20)),
            selection("tre", item("\(Self.cacheRoot)/tre.tmp", 30)),
        ]

        let report = await Task {
            await engine.clean(selections, progress: { _ in cancelCurrentTask() }, journal: nil)
        }.value

        #expect(report.categories.map(\.categoryId) == ["uno"])
        #expect(report.bytesFreed == 10)
        #expect(fs.fileExists("\(Self.cacheRoot)/due.tmp"))
        #expect(fs.fileExists("\(Self.cacheRoot)/tre.tmp"))
    }

    @Test func deletesThePathTheGuardReturnsNotThePathItWasGiven() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/richiesto.tmp", size: 999) // non va toccato
        fs.addFile("\(Self.cacheRoot)/reale.tmp", size: 7)       // quello che il guard restituisce
        let engine = CleanEngine(
            fileSystem: fs,
            pathGuard: RedirectingPathGuard(root: Self.cacheRoot, redirectTarget: "\(Self.cacheRoot)/reale.tmp"),
            clock: FixedWallClock(now: Self.now))

        let report = await engine.clean([selection("caches", item("\(Self.cacheRoot)/richiesto.tmp", 999))], progress: nil, journal: nil)

        #expect(fs.fileExists("\(Self.cacheRoot)/richiesto.tmp"))
        #expect(!fs.fileExists("\(Self.cacheRoot)/reale.tmp"))
        #expect(report.bytesFreed == 7)
        #expect(report.deletedPaths == ["\(Self.cacheRoot)/reale.tmp"])
    }

    // Nuovo (spec §8.2): il diario riceve ogni percorso nel momento in cui viene eliminato, e solo
    // quelli eliminati davvero.
    @Test func journalReceivesEveryDeletedPathAsItHappens() async throws {
        let fs = InMemoryFileSystem()
        fs.addFile("\(Self.cacheRoot)/a.tmp", size: 10)
        fs.addFile("\(Self.cacheRoot)/b.tmp", size: 10)
        let journal = RecordingJournal()

        _ = try await create(fs).clean(
            [selection("caches",
                       item("\(Self.cacheRoot)/a.tmp", 10),
                       item("\(Self.cacheRoot)/sparito.tmp", 10),
                       item("\(Self.cacheRoot)/b.tmp", 10))],
            progress: nil, journal: journal)

        #expect(journal.paths.values == ["\(Self.cacheRoot)/a.tmp", "\(Self.cacheRoot)/b.tmp"])
    }

    private final class RecordingJournal: DeletionRecording {
        let paths = Recorder<String>()
        func recordDeleted(_ path: String) { paths.append(path) }
    }
}
```

- [ ] **Step 2: Scrivere i test di `ConfirmationRows` (falliscono)**

`Tests/CleanerCoreTests/Cleaning/ConfirmationRowsTests.swift`:

```swift
import Testing
@testable import CleanerCore

struct ConfirmationRowsTests {
    private func item(_ path: String, _ size: Int64 = 10) -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: false, declaredRoot: "/root")
    }

    private func result(_ categoryId: String, _ items: ScanItem...) -> CategoryScanResult {
        CategoryScanResult(categoryId: categoryId, items: items, totalBytes: items.reduce(0) { $0 + $1.sizeBytes }, errors: [], exclusions: [])
    }

    // IMPORTANT della revisione finale: lo stesso percorso in due categorie produceva due righe.
    // Una riga sola in tutto il passo, non solo dentro ciascuna categoria.
    @Test func samePathInTwoCategoriesProducesOnlyOneRowInTotal() {
        let built = ConfirmationRows.build([
            result("cat-a", item("/Users/tester/Downloads/x.zip", 100)),
            result("cat-b", item("/Users/tester/Downloads/x.zip", 100)),
        ])

        #expect(built.flatMap(\.items).filter { $0.path == "/Users/tester/Downloads/x.zip" }.count == 1)
    }

    // La prima categoria a proporlo se lo tiene: deselezionarne la riga lo esclude davvero.
    @Test func duplicateIsAttributedToTheFirstCategoryOnlyAndDeselectingItsRowRemovesItEntirely() throws {
        let built = ConfirmationRows.build([
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
        let built = ConfirmationRows.build([
            result("cat-a", item("/x/dup", 500)),
            result("cat-b", item("/x/dup", 500), item("/x/other", 50)),
        ])

        #expect(built.flatMap(\.items).reduce(0) { $0 + $1.sizeBytes } == 550)
    }

    @Test func deduplicatesWithinTheSameCategoryToo() {
        let built = ConfirmationRows.build([result("cat-a", item("/x/dup", 10), item("/x/dup", 10))])
        #expect(built.map(\.items.count) == [1])
    }

    @Test func categoryWithAllItemsClaimedByAnEarlierCategoryIsOmitted() {
        let built = ConfirmationRows.build([result("cat-a", item("/x/dup", 10)), result("cat-b", item("/x/dup", 10))])
        #expect(!built.contains { $0.categoryId == "cat-b" })
    }

    @Test func categoryWithNoItemsIsOmitted() {
        #expect(ConfirmationRows.build([result("cat-empty")]).isEmpty)
    }

    @Test func distinctPathsAcrossCategoriesAreAllKept() {
        let built = ConfirmationRows.build([result("cat-a", item("/x/a", 10)), result("cat-b", item("/x/b", 20))])
        #expect(built.flatMap(\.items).count == 2)
    }
}
```

- [ ] **Step 3: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "CleanEngineTests|ConfirmationRowsTests"`
Expected: errore di compilazione `cannot find 'CleanEngine' in scope`.

- [ ] **Step 4: Implementare i modelli e `ConfirmationRows`**

`Sources/CleanerCore/Cleaning/CleanModels.swift`:

```swift
import Foundation

public struct CategorySelection: Sendable, Equatable {
    public let categoryId: String
    public let items: [ScanItem]

    public init(categoryId: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.items = items
    }
}

public struct CategoryCleanResult: Sendable, Equatable {
    public let categoryId: String
    public let bytesFreed: Int64
    public let itemsDeleted: Int

    public init(categoryId: String, bytesFreed: Int64, itemsDeleted: Int) {
        self.categoryId = categoryId
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
    }
}

public struct CleanProgress: Sendable, Equatable {
    public let currentPath: String
    public let itemsDone: Int
    public let itemsTotal: Int
    public let bytesFreed: Int64

    public init(currentPath: String, itemsDone: Int, itemsTotal: Int, bytesFreed: Int64) {
        self.currentPath = currentPath
        self.itemsDone = itemsDone
        self.itemsTotal = itemsTotal
        self.bytesFreed = bytesFreed
    }
}

public struct CleanReport: Sendable, Equatable {
    public let startedAt: Date
    public let duration: Duration
    public let bytesFreed: Int64
    public let itemsDeleted: Int
    public let itemsFailed: Int
    public let categories: [CategoryCleanResult]
    public let errors: [ScanError]
    public let deletedPaths: [String]

    public init(
        startedAt: Date,
        duration: Duration,
        bytesFreed: Int64,
        itemsDeleted: Int,
        itemsFailed: Int,
        categories: [CategoryCleanResult],
        errors: [ScanError],
        deletedPaths: [String]
    ) {
        self.startedAt = startedAt
        self.duration = duration
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
        self.itemsFailed = itemsFailed
        self.categories = categories
        self.errors = errors
        self.deletedPaths = deletedPaths
    }
}

/// Riceve ogni percorso nel momento in cui viene eliminato (spec §8.2, diario della pulizia).
public protocol DeletionRecording: Sendable {
    func recordDeleted(_ path: String)
}
```

`Sources/CleanerCore/Cleaning/ConfirmationRows.swift`:

```swift
/// Gli elementi di una categoria dopo la deduplicazione: una categoria il cui contenuto è stato
/// interamente riassorbito da una precedente non compare, non avrebbe righe da mostrare.
public struct ConfirmationCategory: Sendable, Equatable {
    public let categoryId: String
    public let items: [ScanItem]

    public init(categoryId: String, items: [ScanItem]) {
        self.categoryId = categoryId
        self.items = items
    }
}

/// Le righe del passo di conferma: un percorso, una riga, in tutto il passo.
public enum ConfirmationRows {
    /// Deduplica GLOBALMENTE per percorso (confronto esatto): lo stesso percorso proposto da due
    /// categorie (cartelle dei file grandi sovrapposte a una root del catalogo) produceva due righe,
    /// il totale lo contava due volte e deselezionarlo in una categoria non lo escludeva dall'altra.
    /// Si tiene il primo incontrato, nell'ordine del catalogo: stesso file, stessa dimensione.
    public static func build(_ results: [CategoryScanResult]) -> [ConfirmationCategory] {
        var seenPaths = Set<String>()
        var categories: [ConfirmationCategory] = []

        for result in results {
            let items = result.items.filter { seenPaths.insert($0.path).inserted }
            if !items.isEmpty {
                categories.append(ConfirmationCategory(categoryId: result.categoryId, items: items))
            }
        }

        return categories
    }
}
```

- [ ] **Step 5: Implementare `CleanEngine`**

`Sources/CleanerCore/Cleaning/CleanEngine.swift`:

```swift
import Darwin
import Foundation

public protocol CleanPerforming: Sendable {
    func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport
}

/// Eliminazione definitiva. Sequenziale: su un singolo volume il parallelismo non accelera e
/// renderebbe il resoconto meno prevedibile. Non lancia mai: l'annullamento restituisce un
/// resoconto parziale, perché ciò che è già stato eliminato deve finire comunque nello storico.
public struct CleanEngine: CleanPerforming {
    private let fileSystem: any FileSystem
    private let pathGuard: any PathGuarding
    private let clock: any WallClock

    public init(fileSystem: any FileSystem, pathGuard: any PathGuarding, clock: any WallClock) {
        self.fileSystem = fileSystem
        self.pathGuard = pathGuard
        self.clock = clock
    }

    @concurrent
    public func clean(
        _ selections: [CategorySelection],
        progress: (@Sendable (CleanProgress) -> Void)?,
        journal: (any DeletionRecording)?
    ) async -> CleanReport {
        let startedAt = clock.now
        let start = ContinuousClock.now

        var categories: [CategoryCleanResult] = []
        var errors: [ScanError] = []
        var deleted: [String] = []
        var totalBytes: Int64 = 0
        var totalDeleted = 0
        var totalFailed = 0
        var done = 0
        let total = selections.reduce(0) { $0 + $1.items.count }
        var lastSeenPath = ""

        // Due selezioni con lo stesso identificativo confluiscono in un'unica voce del resoconto.
        func addToCategory(_ categoryId: String, bytes: Int64, items: Int) {
            if let index = categories.firstIndex(where: { $0.categoryId == categoryId }) {
                let existing = categories[index]
                categories[index] = CategoryCleanResult(
                    categoryId: categoryId,
                    bytesFreed: existing.bytesFreed + bytes,
                    itemsDeleted: existing.itemsDeleted + items)
            } else {
                categories.append(CategoryCleanResult(categoryId: categoryId, bytesFreed: bytes, itemsDeleted: items))
            }
        }

        func fail(_ error: ScanError, _ path: String) {
            errors.append(error)
            totalFailed += 1
            progress?(CleanProgress(currentPath: path, itemsDone: done, itemsTotal: total, bytesFreed: totalBytes))
        }

        // Un errore fuori contratto (non un FileSystemError) non deve far perdere il resoconto:
        // per un'app che cancella senza Cestino, l'elenco di ciò che è già stato eliminato è
        // l'unica ricostruzione possibile. Meglio un resoconto con un errore ignoto che nessuno.
        do {
            // Ultima linea di difesa: ogni root distinta va validata con validateRoot, una volta
            // sola, PRIMA dei singoli elementi. validate da solo presuppone una root già validata
            // e, quando la root è il genitore diretto dell'elemento (ogni regola clearContents),
            // non vedrebbe un collegamento sulla root stessa. L'elenco arriva dall'interfaccia dopo
            // la conferma (manipolabile) e può essere scaduto (root sostituita da un collegamento
            // fra scansione e conferma): richiamare validateRoot qui copre entrambi i casi.
            var rootVerdicts: [String: GuardVerdict] = [:]
            for item in selections.flatMap(\.items) {
                let key = item.declaredRoot.lowercased()
                if rootVerdicts[key] == nil {
                    rootVerdicts[key] = pathGuard.validateRoot(item.declaredRoot)
                }
            }

            categoryLoop: for selection in selections {
                // Una categoria non ancora iniziata non entra nel resoconto, nemmeno a zero.
                if Task.isCancelled { break categoryLoop }

                if !categories.contains(where: { $0.categoryId == selection.categoryId }) {
                    categories.append(CategoryCleanResult(categoryId: selection.categoryId, bytesFreed: 0, itemsDeleted: 0))
                }

                for item in selection.items {
                    if Task.isCancelled { break categoryLoop }

                    done += 1
                    lastSeenPath = item.path

                    // Root negata: fallisce solo QUESTO elemento, non l'intera pulizia. In Swift una
                    // root nulla è impossibile per tipo; una root vuota viene negata da validateRoot.
                    guard let rootVerdict = rootVerdicts[item.declaredRoot.lowercased()], rootVerdict.isAllowed else {
                        let reason = rootVerdicts[item.declaredRoot.lowercased()]?.reason
                            ?? String(localized: "root dichiarata non riconosciuta", bundle: .module)
                        fail(ScanError(path: item.path, kind: .other, message: reason), item.path)
                        continue
                    }

                    // Lo scanner enumera dalla root DICHIARATA, mentre validateRoot può averla
                    // risolta a una stringa diversa ($TMPDIR: "/var" → "/private/var"). L'elemento
                    // va riportato nel sistema di riferimento RISOLTO PRIMA di validarlo: prima si
                    // riscrive, poi si valida, poi si cancella il percorso che il guard restituisce.
                    let resolvedRoot = rootVerdict.canonicalPathValidated
                    let rewrittenPath = Self.rewriteToResolvedRoot(item.path, declaredRoot: item.declaredRoot, resolvedRoot: resolvedRoot)

                    let verdict = pathGuard.validate(rewrittenPath, declaredRoot: resolvedRoot)
                    guard verdict.isAllowed else {
                        fail(ScanError(path: item.path, kind: .other, message: verdict.reason), item.path)
                        continue
                    }

                    // Si elimina il percorso che il guard ha VALIDATO, non quello di partenza.
                    let target = verdict.canonicalPathValidated

                    do {
                        // Si contano solo i byte davvero liberati, rimisurati subito prima.
                        let size = measureRealSize(target, isDirectory: item.isDirectory)

                        if item.isDirectory {
                            try fileSystem.deleteDirectoryRecursively(target)
                        } else {
                            // File.Exists di .NET: falso anche per un collegamento a una cartella
                            // (vedi registro di parità, candidati a miglioramento).
                            guard fileSystem.fileExists(target) else {
                                throw FileSystemError(code: ENOENT, path: target)
                            }
                            try fileSystem.deleteFile(target)
                        }

                        totalBytes += size
                        totalDeleted += 1
                        deleted.append(target)
                        journal?.recordDeleted(target)
                        addToCategory(selection.categoryId, bytes: size, items: 1)
                    } catch let error as FileSystemError {
                        errors.append(RuleScanner.describe(item.path, error))
                        totalFailed += 1
                    }

                    progress?(CleanProgress(currentPath: item.path, itemsDone: done, itemsTotal: total, bytesFreed: totalBytes))
                }
            }
        } catch {
            errors.append(ScanError(path: lastSeenPath, kind: .other, message: String(describing: error)))
            totalFailed += 1
        }

        return CleanReport(
            startedAt: startedAt,
            duration: ContinuousClock.now - start,
            bytesFreed: totalBytes,
            itemsDeleted: totalDeleted,
            itemsFailed: totalFailed,
            categories: categories,
            errors: errors,
            deletedPaths: deleted)
    }

    /// Riporta `path` dal sistema di riferimento della root DICHIARATA a quello della sua
    /// risoluzione. Se `path` non comincia con la root dichiarata (confine di segmento, senza
    /// distinzione fra maiuscole e minuscole) non c'è nulla da riscrivere: validate lo rileverà.
    static func rewriteToResolvedRoot(_ path: String, declaredRoot: String, resolvedRoot: String) -> String {
        if PathText.equalsIgnoringCase(declaredRoot, resolvedRoot) { return path }
        if PathText.equalsIgnoringCase(path, declaredRoot) { return resolvedRoot }
        if PathText.hasPrefixIgnoringCase(path, declaredRoot + "/") {
            return resolvedRoot + path.dropFirst(declaredRoot.count)
        }
        return path
    }

    /// Dimensione reale letta subito prima di cancellare, mai quella dichiarata dall'interfaccia.
    /// Se la lettura fallisce vale zero: il tentativo di cancellazione che segue registrerà
    /// l'errore con la classificazione corretta.
    ///
    /// Differenza voluta rispetto al C#: `EnumerateFiles(…, AllDirectories)` scendeva anche nei
    /// collegamenti a cartelle (misurato su .NET 10), accreditando byte che la cancellazione — che
    /// non segue i collegamenti — non libera. Qui non si scende mai in un collegamento, come
    /// prescrive la spec originale (§7: «I symlink non vengono mai seguiti»).
    private func measureRealSize(_ path: String, isDirectory: Bool) -> Int64 {
        do {
            return isDirectory ? try sumOfFiles(under: path) : try fileSystem.fileLength(path)
        } catch {
            return 0
        }
    }

    private func sumOfFiles(under directory: String) throws -> Int64 {
        var total: Int64 = 0
        for entry in try fileSystem.contentsOfDirectory(directory) {
            let info = try fileSystem.itemInfo(entry)
            switch info.kind {
            case .directory:
                total += try sumOfFiles(under: entry)
            case .symbolicLink where fileSystem.directoryExists(entry):
                continue
            default:
                // Un file, o un collegamento a file: come FileInfo.Length, conta la dimensione del
                // collegamento stesso.
                total += info.size
            }
        }
        return total
    }
}
```

- [ ] **Step 6: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "CleanEngineTests|ConfirmationRowsTests"`
Expected: `Test run with 26 tests … passed` (19 di `CleanEngineTests`, 7 di `ConfirmationRowsTests`).

- [ ] **Step 7: Registro di parità e commit**

Righe `Cleaning/CleanEngineTests.cs` (18 → 19: +1 nuovo per il diario) e `Cleaning/ConfirmationRowsTests.cs` (7). Note su `CleanEngineTests`: «`MalformedItemWithNullDeclaredRoot…` → `…WithEmptyDeclaredRoot…` (null impossibile per tipo)».

Tabella differenze, aggiungere:

```markdown
| Misura reale di una cartella prima di cancellarla | `EnumerateFiles(…, AllDirectories)` scende nei collegamenti a cartelle | non scende nei collegamenti (spec originale §7) | voluta |
| Root dichiarata nulla | ramo dedicato «root dichiarata mancante» | impossibile per tipo; la root vuota è negata da validateRoot | per costruzione |
```

Tabella candidati a miglioramento, aggiungere:

```markdown
| Collegamento a cartella dentro una cache (clearContents) | `File.Exists` lo vede come assente: l'elemento fallisce come «non trovato» e il collegamento resta | eliminare il collegamento con `deleteFile` quando `itemInfo` dice `.symbolicLink` |
| Byte accreditati per un collegamento a file | la dimensione del collegamento stesso (lunghezza del percorso di destinazione) | accreditare 0: eliminare il collegamento non libera lo spazio del bersaglio |
| errno residui (EROFS, ENOSPC, EIO…) | classificati «in uso», come ogni IOException .NET | categoria dedicata o «altro» |
```

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port CleanEngine and ConfirmationRows with deletion journal hook

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: History: `SQLiteDatabase` e `HistoryStore`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/History/SQLiteDatabase.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/History/HistoryStore.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/History/HistoryStoreTests.swift`
- Reference: `src/MjmCleaner.Core/History/HistoryStore.cs`, `tests/MjmCleaner.Core.Tests/History/HistoryStoreTests.cs`

**Interfaces:**
- Consumes: `LocalFileSystem`, `PathText` (Task 1–2); `CleanReport`, `CategoryCleanResult` (Task 9); `TemporaryDirectory`, `utc` (Task 2–3).
- Produces:
  - `public struct CleanSessionSummary: Sendable, Equatable` — `id: Int64`, `startedAt: Date`, `duration: Duration`, `bytesFreed: Int64`, `itemsDeleted: Int`, `itemsFailed: Int`, `categories: [CategoryCleanResult]`
  - `public protocol HistoryStoring: Sendable` — `initialize() async throws`, `save(_ report: CleanReport) async throws -> Int64`, `sessions(limit: Int) async throws -> [CleanSessionSummary]`, `totalBytesFreed() async throws -> Int64`
  - `public actor HistoryStore: HistoryStoring` — `init(databaseFile: String)`
  - interni: `final class SQLiteDatabase`, `enum SQLiteValue`, `struct SQLiteError`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/History/HistoryStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

/// Test di integrazione su un database SQLite reale in una cartella temporanea, come in C#.
struct HistoryStoreTests {
    private func report(_ bytes: Int64, deleted: Int = 1, failed: Int = 0, _ categories: CategoryCleanResult...) -> CleanReport {
        CleanReport(
            startedAt: utc(2026, 9, 15, 10, 30),
            duration: .seconds(38),
            bytesFreed: bytes,
            itemsDeleted: deleted,
            itemsFailed: failed,
            categories: categories.isEmpty ? [CategoryCleanResult(categoryId: "caches", bytesFreed: bytes, itemsDeleted: deleted)] : categories,
            errors: [],
            deletedPaths: [])
    }

    @Test func initializeCreatesSchemaAndIsIdempotent() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let databaseFile = tmp.path + "/dati/history.db"
        let store = HistoryStore(databaseFile: databaseFile)

        try await store.initialize()
        try await store.initialize()

        #expect(FileManager.default.fileExists(atPath: databaseFile))
        #expect(try await store.totalBytesFreed() == 0)
    }

    @Test func saveThenReadBackSession() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        let id = try await store.save(report(1_500))

        let sessions = try await store.sessions(limit: 10)
        let session = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(session.id == id)
        #expect(session.bytesFreed == 1_500)
        #expect(session.duration == .seconds(38))
        #expect(session.startedAt == utc(2026, 9, 15, 10, 30))
        #expect(session.categories.map(\.categoryId) == ["caches"])
    }

    @Test func totalIsTheSumOfAllSessions() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        _ = try await store.save(report(1_000))
        _ = try await store.save(report(2_500))

        #expect(try await store.totalBytesFreed() == 3_500)
    }

    @Test func sessionsAreReturnedNewestFirstAndLimited() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        let first = try await store.save(report(10))
        let second = try await store.save(report(20))
        let third = try await store.save(report(30))

        let sessions = try await store.sessions(limit: 2)

        #expect(sessions.map(\.id) == [third, second])
        #expect(!sessions.contains { $0.id == first })
    }

    @Test func categoryBreakdownIsPersisted() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        _ = try await store.save(report(300, deleted: 3, failed: 0,
                                        CategoryCleanResult(categoryId: "caches", bytesFreed: 100, itemsDeleted: 1),
                                        CategoryCleanResult(categoryId: "logs", bytesFreed: 200, itemsDeleted: 2)))

        let session = try #require(try await store.sessions(limit: 1).first)
        #expect(session.categories.count == 2)
        #expect(session.categories.first { $0.categoryId == "logs" }?.bytesFreed == 200)
    }

    @Test func failedItemsAreRecorded() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let store = HistoryStore(databaseFile: tmp.path + "/history.db")
        try await store.initialize()

        _ = try await store.save(report(10, deleted: 1, failed: 4))

        #expect(try await store.sessions(limit: 1).first?.itemsFailed == 4)
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter HistoryStoreTests`
Expected: errore di compilazione `cannot find 'HistoryStore' in scope`.

- [ ] **Step 3: Implementare `SQLiteDatabase`**

`Sources/CleanerCore/History/SQLiteDatabase.swift`:

```swift
import SQLite3

struct SQLiteError: Error, Equatable, Sendable, CustomStringConvertible {
    let code: Int32
    let description: String
}

enum SQLiteValue: Equatable, Sendable {
    case integer(Int64)
    case text(String)
    case null

    var integer: Int64? {
        if case .integer(let value) = self { value } else { nil }
    }

    var text: String? {
        if case .text(let value) = self { value } else { nil }
    }
}

/// `SQLITE_TRANSIENT` non è importato in Swift: chiede a SQLite di copiare subito il testo legato.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Wrapper minimo sulla libreria SQLite di sistema: apertura, SQL diretto, statement preparati con
/// parametri posizionali. Una connessione per operazione, come in C#: due tabelle non giustificano
/// un ORM né una connessione condivisa.
final class SQLiteDatabase {
    private let handle: OpaquePointer

    init(path: String) throws {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 fallita"
            sqlite3_close(database)
            throw SQLiteError(code: status, description: message)
        }
        handle = database
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw error(status) }
    }

    /// Esegue `sql` legando i parametri nell'ordine e restituisce tutte le righe.
    @discardableResult
    func query(_ sql: String, _ parameters: [SQLiteValue] = []) throws -> [[SQLiteValue]] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw error(prepared) }
        defer { sqlite3_finalize(statement) }

        for (offset, value) in parameters.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .integer(let number): status = sqlite3_bind_int64(statement, index, number)
            case .text(let text): status = sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else { throw error(status) }
        }

        var rows: [[SQLiteValue]] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return rows }
            guard step == SQLITE_ROW else { throw error(step) }

            rows.append((0..<sqlite3_column_count(statement)).map { column in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER:
                    return .integer(sqlite3_column_int64(statement, column))
                case SQLITE_NULL:
                    return .null
                default:
                    return .text(sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "")
                }
            })
        }
    }

    var lastInsertRowId: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private func error(_ status: Int32) -> SQLiteError {
        SQLiteError(code: status, description: String(cString: sqlite3_errmsg(handle)))
    }
}
```

- [ ] **Step 4: Implementare `HistoryStore`**

`Sources/CleanerCore/History/HistoryStore.swift`:

```swift
import Foundation
import SQLite3

public struct CleanSessionSummary: Sendable, Equatable {
    public let id: Int64
    public let startedAt: Date
    public let duration: Duration
    public let bytesFreed: Int64
    public let itemsDeleted: Int
    public let itemsFailed: Int
    public let categories: [CategoryCleanResult]

    public init(id: Int64, startedAt: Date, duration: Duration, bytesFreed: Int64, itemsDeleted: Int, itemsFailed: Int, categories: [CategoryCleanResult]) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.bytesFreed = bytesFreed
        self.itemsDeleted = itemsDeleted
        self.itemsFailed = itemsFailed
        self.categories = categories
    }
}

public protocol HistoryStoring: Sendable {
    func initialize() async throws
    func save(_ report: CleanReport) async throws -> Int64
    func sessions(limit: Int) async throws -> [CleanSessionSummary]
    func totalBytesFreed() async throws -> Int64
}

/// Storico delle pulizie su SQLite. Il dettaglio per elemento NON va qui ma nel log di sessione:
/// una pulizia delle cache tocca centinaia di migliaia di file.
public actor HistoryStore: HistoryStoring {
    private static let schemaVersion = 1
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    private let databaseFile: String

    public init(databaseFile: String) {
        self.databaseFile = databaseFile
    }

    public func initialize() throws {
        if let directory = PathText.parent(databaseFile), !directory.isEmpty {
            try LocalFileSystem().createDirectory(directory)
        }

        try SQLiteDatabase(path: databaseFile).execute("""
            CREATE TABLE IF NOT EXISTS CleanSession (
              Id           INTEGER PRIMARY KEY AUTOINCREMENT,
              StartedAtUtc TEXT    NOT NULL,
              DurationMs   INTEGER NOT NULL,
              BytesFreed   INTEGER NOT NULL,
              ItemsDeleted INTEGER NOT NULL,
              ItemsFailed  INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS SessionCategory (
              SessionId    INTEGER NOT NULL REFERENCES CleanSession(Id) ON DELETE CASCADE,
              CategoryId   TEXT    NOT NULL,
              BytesFreed   INTEGER NOT NULL,
              ItemsDeleted INTEGER NOT NULL,
              PRIMARY KEY (SessionId, CategoryId)
            );

            PRAGMA user_version = \(Self.schemaVersion);
            """)
    }

    public func save(_ report: CleanReport) throws -> Int64 {
        let database = try SQLiteDatabase(path: databaseFile)
        try database.execute("BEGIN IMMEDIATE;")
        do {
            try database.query(
                "INSERT INTO CleanSession (StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed) VALUES (?, ?, ?, ?, ?);",
                [
                    .text(report.startedAt.formatted(Self.timestampStyle)),
                    .integer(Self.milliseconds(report.duration)),
                    .integer(report.bytesFreed),
                    .integer(Int64(report.itemsDeleted)),
                    .integer(Int64(report.itemsFailed)),
                ])
            let sessionId = database.lastInsertRowId

            for category in report.categories {
                try database.query(
                    "INSERT INTO SessionCategory (SessionId, CategoryId, BytesFreed, ItemsDeleted) VALUES (?, ?, ?, ?);",
                    [.integer(sessionId), .text(category.categoryId), .integer(category.bytesFreed), .integer(Int64(category.itemsDeleted))])
            }

            try database.execute("COMMIT;")
            return sessionId
        } catch {
            try? database.execute("ROLLBACK;")
            throw error
        }
    }

    public func sessions(limit: Int) throws -> [CleanSessionSummary] {
        let database = try SQLiteDatabase(path: databaseFile)

        var categories: [Int64: [CategoryCleanResult]] = [:]
        let categoryRows = try database.query(
            """
            SELECT SessionId, CategoryId, BytesFreed, ItemsDeleted
            FROM SessionCategory
            WHERE SessionId IN (SELECT Id FROM CleanSession ORDER BY Id DESC LIMIT ?);
            """,
            [.integer(Int64(limit))])
        for row in categoryRows {
            guard row.count == 4,
                  let sessionId = row[0].integer, let categoryId = row[1].text,
                  let bytes = row[2].integer, let deleted = row[3].integer else {
                throw Self.malformedRow()
            }
            categories[sessionId, default: []].append(CategoryCleanResult(categoryId: categoryId, bytesFreed: bytes, itemsDeleted: Int(deleted)))
        }

        let sessionRows = try database.query(
            """
            SELECT Id, StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed
            FROM CleanSession
            ORDER BY Id DESC
            LIMIT ?;
            """,
            [.integer(Int64(limit))])

        return try sessionRows.map { row in
            guard row.count == 6,
                  let id = row[0].integer, let startedText = row[1].text, let durationMs = row[2].integer,
                  let bytes = row[3].integer, let deleted = row[4].integer, let failed = row[5].integer else {
                throw Self.malformedRow()
            }
            return CleanSessionSummary(
                id: id,
                startedAt: try Self.timestampStyle.parse(startedText),
                duration: .milliseconds(durationMs),
                bytesFreed: bytes,
                itemsDeleted: Int(deleted),
                itemsFailed: Int(failed),
                categories: categories[id] ?? [])
        }
    }

    /// Somma calcolata, non un contatore memorizzato: un contatore prima o poi diverge dalle righe.
    public func totalBytesFreed() throws -> Int64 {
        let rows = try SQLiteDatabase(path: databaseFile).query("SELECT COALESCE(SUM(BytesFreed), 0) FROM CleanSession;")
        guard let total = rows.first?.first?.integer else { throw Self.malformedRow() }
        return total
    }

    /// Millisecondi interi, troncati come `(long)TimeSpan.TotalMilliseconds` in C#.
    private static func milliseconds(_ duration: Duration) -> Int64 {
        let (seconds, attoseconds) = duration.components
        return seconds * 1_000 + attoseconds / 1_000_000_000_000_000
    }

    private static func malformedRow() -> SQLiteError {
        SQLiteError(code: SQLITE_MISMATCH, description: String(localized: "riga dello storico non valida", bundle: .module))
    }
}
```

Gli accessi `row[0]`…`row[5]` sono verificati dalla guardia `row.count == …` che li precede.

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter HistoryStoreTests`
Expected: `Test run with 6 tests … passed`.

- [ ] **Step 6: Registro di parità e commit**

Riga `History/HistoryStoreTests.cs` (6) compilata. Tabella differenze: `| Formato di StartedAtUtc | "O" di .NET (7 decimali) | ISO 8601 con millisecondi | accettata: dati nuovi (spec §2) |`.

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port HistoryStore on system SQLite

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: `Gzip`, `SessionLogWriter` e diario `PendingJournal`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/Gzip.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/History/SessionLogWriter.swift`
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/History/PendingJournal.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/GzipTests.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/History/SessionLogWriterTests.swift`
- Reference: `src/MjmCleaner.Core/History/SessionLogWriter.cs`, `tests/MjmCleaner.Core.Tests/History/SessionLogWriterTests.cs`; spec §8.2

**Interfaces:**
- Consumes: `CZlib` (Task 1); `FileSystem`, `PathText` (Task 1–2); `AppPaths` (Task 5); `CleanReport`, `DeletionRecording` (Task 9); `InMemoryFileSystem`, `ForwardingFileSystem` (Task 3).
- Produces:
  - `public enum Gzip` — `static func compress(_:) throws -> Data`, `static func decompress(_:) throws -> Data`; `public enum GzipError: Error { case zlib(Int32) }`
  - `public protocol SessionLogWriting: Sendable` — `write(sessionId: Int64, report: CleanReport) async throws`, `openJournal(startedAt: Date) -> PendingJournal?`, `discard(_ journal: PendingJournal)`
  - `public struct SessionLogWriter: SessionLogWriting` — `init(fileSystem: any FileSystem, paths: AppPaths, retention: Int = 20)`; `static func jsonLine(_ path: String) -> String`
  - `public final class PendingJournal: DeletionRecording` — `let path: String`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Platform/GzipTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct GzipTests {
    @Test func roundTripsAndIsReadableByTheGzipCommand() throws {
        let text = String(repeating: #"{"path":"/Users/tester/Library/Caches/x"}"# + "\n", count: 5_000)
        let compressed = try Gzip.compress(Data(text.utf8))

        #expect(compressed.count < text.utf8.count / 10)
        #expect(compressed.prefix(2) == Data([0x1f, 0x8b]))
        #expect(String(decoding: try Gzip.decompress(compressed), as: UTF8.self) == text)

        // Su macOS `zcat` legge solo il formato `.Z`: il comando di riferimento è `gzip -dc`.
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = tmp.path + "/log.jsonl.gz"
        try compressed.write(to: URL(fileURLWithPath: file))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc", file]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let decoded = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(String(decoding: decoded, as: UTF8.self) == text)
    }

    @Test func emptyInputProducesAValidEmptyArchive() throws {
        #expect(try Gzip.decompress(try Gzip.compress(Data())).isEmpty)
    }

    @Test func truncatedDataIsRejected() throws {
        let compressed = try Gzip.compress(Data(String(repeating: "abc", count: 10_000).utf8))
        #expect(throws: GzipError.self) { try Gzip.decompress(compressed.prefix(compressed.count / 2)) }
    }

    @Test func largeInputSpansManyChunks() throws {
        var bytes = [UInt8](repeating: 0, count: 1_000_000)
        for index in bytes.indices { bytes[index] = UInt8(truncatingIfNeeded: index &* 2_654_435_761 >> 13) }
        let data = Data(bytes)
        #expect(try Gzip.decompress(try Gzip.compress(data)) == data)
    }
}
```

`Tests/CleanerCoreTests/History/SessionLogWriterTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

struct SessionLogWriterTests {
    private static let paths = AppPaths(supportDirectory: "/Users/tester/Library/Application Support/com.mjm.cleaner")

    private func report(_ deletedPaths: String...) -> CleanReport {
        CleanReport(startedAt: Date(timeIntervalSince1970: 0), duration: .zero, bytesFreed: 0,
                    itemsDeleted: deletedPaths.count, itemsFailed: 0, categories: [], errors: [], deletedPaths: deletedPaths)
    }

    private func logNames(_ fs: InMemoryFileSystem) throws -> [String] {
        try fs.contentsOfDirectory(Self.paths.logsDirectory).map(PathText.fileName).sorted()
    }

    private func lines(_ fs: InMemoryFileSystem, _ file: String) throws -> [String] {
        String(decoding: try Gzip.decompress(fs.readData(file)), as: UTF8.self)
            .split(separator: "\n").map(String.init)
    }

    /// Doppio locale: la scrittura del log principale fallisce con accesso negato (in C# il file
    /// veniva marcato ReadOnly su MockFileSystem, che il doppio Swift non modella).
    private final class FailingWriteFileSystem: ForwardingFileSystem, @unchecked Sendable {
        override func writeData(_ path: String, _ data: Data) throws {
            throw FileSystemError(code: EACCES, path: path)
        }
    }

    @Test func writesOneLinePerDeletedPath() async throws {
        let fs = InMemoryFileSystem()
        try await SessionLogWriter(fileSystem: fs, paths: Self.paths).write(sessionId: 7, report: report("/a/uno.tmp", "/a/due.tmp"))

        let file = PathText.join(Self.paths.logsDirectory, "session-000007.jsonl.gz")
        #expect(fs.fileExists(file))
        let content = try lines(fs, file)
        #expect(content.count == 2)
        #expect(content.first?.contains("/a/uno.tmp") == true)
        #expect(content.last?.contains("/a/due.tmp") == true)
    }

    @Test func keepsOnlyTheMostRecentSessions() async throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths, retention: 3)

        for id in Int64(1)...5 {
            try await writer.write(sessionId: id, report: report("/a/\(id).tmp"))
        }

        #expect(try logNames(fs) == ["session-000003.jsonl.gz", "session-000004.jsonl.gz", "session-000005.jsonl.gz"])
    }

    @Test func createsTheLogsDirectoryWhenMissing() async throws {
        let fs = InMemoryFileSystem()
        try await SessionLogWriter(fileSystem: fs, paths: Self.paths).write(sessionId: 1, report: report("/a/x.tmp"))
        #expect(fs.directoryExists(Self.paths.logsDirectory))
    }

    // Oltre le sei cifre l'ordinamento lessicografico capovolge l'ordine ("1000000" < "999999"):
    // la rotazione deve ordinare sul valore numerico, o cancellerebbe la sessione appena scritta.
    @Test func ordersRotationByNumericSessionIdNotByString() async throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths, retention: 3)

        for id: Int64 in [999_997, 999_998, 999_999, 1_000_000] {
            try await writer.write(sessionId: id, report: report("/a/\(id).tmp"))
        }

        #expect(try logNames(fs) == ["session-1000000.jsonl.gz", "session-999998.jsonl.gz", "session-999999.jsonl.gz"])
    }

    // Una pulizia che non ha eliminato nulla scrive comunque un gzip valido con zero righe. Il
    // test C# fissava anche la lunghezza (15 byte) del gzip di .NET: è un dettaglio della libreria,
    // non un comportamento, e non si porta.
    @Test func writesAValidEmptyLogFileWhenNothingWasDeleted() async throws {
        let fs = InMemoryFileSystem()
        try await SessionLogWriter(fileSystem: fs, paths: Self.paths).write(sessionId: 1, report: report())

        let file = PathText.join(Self.paths.logsDirectory, "session-000001.jsonl.gz")
        #expect(fs.fileExists(file))
        #expect(try Gzip.decompress(fs.readData(file)).isEmpty)
    }

    // Solo la rotazione ignora i propri errori: un fallimento della scrittura principale deve
    // arrivare al chiamante.
    @Test func propagatesFailuresFromTheMainWriteInsteadOfSwallowingThem() async throws {
        let writer = SessionLogWriter(fileSystem: FailingWriteFileSystem(InMemoryFileSystem()), paths: Self.paths)

        await #expect(throws: FileSystemError.self) {
            try await writer.write(sessionId: 1, report: report("/a/x.tmp"))
        }
    }

    // MARK: - Nuovi (spec §8.2): diario della pulizia

    @Test func jsonLineEscapesQuotesBackslashesAndControlCharacters() throws {
        let path = "/a/\"strano\"\\nome\n\tfine"
        let line = SessionLogWriter.jsonLine(path)
        #expect(line.hasSuffix("\n"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String])
        #expect(object == ["path": path])
    }

    @Test func journalAppendsOneLinePerDeletedPathAndSurvivesWithoutTheSessionLog() throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths)
        let journal = try #require(writer.openJournal(startedAt: utc(2026, 9, 15, 10, 30)))

        journal.recordDeleted("/a/uno.tmp")
        journal.recordDeleted("/a/due.tmp")

        #expect(PathText.fileName(journal.path) == "pending-20260915T103000Z.jsonl")
        let lines = try fs.readText(journal.path).split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first?.contains("/a/uno.tmp") == true)
    }

    @Test func discardRemovesTheJournal() throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths)
        let journal = try #require(writer.openJournal(startedAt: utc(2026, 9, 15)))

        writer.discard(journal)

        #expect(!fs.fileExists(journal.path))
    }

    @Test func rotationNeverTouchesPendingJournals() async throws {
        let fs = InMemoryFileSystem()
        let writer = SessionLogWriter(fileSystem: fs, paths: Self.paths, retention: 1)
        let journal = try #require(writer.openJournal(startedAt: utc(2026, 9, 15)))
        journal.recordDeleted("/a/sopravvissuto.tmp")

        try await writer.write(sessionId: 1, report: report("/a/1.tmp"))
        try await writer.write(sessionId: 2, report: report("/a/2.tmp"))

        #expect(try logNames(fs) == ["pending-20260915T000000Z.jsonl", "session-000002.jsonl.gz"])
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter "GzipTests|SessionLogWriterTests"`
Expected: errore di compilazione `cannot find 'Gzip' in scope`.

- [ ] **Step 3: Implementare `Gzip`** (prototipato e verificato con `gzip -dc` durante la stesura del piano)

`Sources/CleanerCore/Platform/Gzip.swift`:

```swift
import CZlib
import Foundation

public enum GzipError: Error, Equatable, Sendable {
    case zlib(Int32)
}

/// Formato gzip (RFC 1952) tramite la zlib di sistema: Foundation non scrive gzip, e il log di
/// sessione deve restare leggibile con `gzip -dc` (su macOS `zcat` legge solo il formato `.Z`).
public enum Gzip {
    private static let chunkSize = 64 * 1024

    public static func compress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // windowBits 15 + 16: intestazione e coda gzip invece del formato zlib.
        let initStatus = deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY,
                                       ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw GzipError.zlib(initStatus) }
        defer { deflateEnd(&stream) }
        return try pump(&stream, input: data) { deflate(&$0, Z_FINISH) }
    }

    public static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        // windowBits 15 + 32: riconosce da sé l'intestazione gzip.
        let initStatus = inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { throw GzipError.zlib(initStatus) }
        defer { inflateEnd(&stream) }
        return try pump(&stream, input: data) { inflate(&$0, Z_NO_FLUSH) }
    }

    /// Fa scorrere `input` attraverso `step` a blocchi finché zlib non segnala la fine dello
    /// stream. Qualunque altro esito (dati troncati o corrotti) è un errore.
    private static func pump(
        _ stream: inout z_stream,
        input: Data,
        step: (inout z_stream) -> Int32
    ) throws -> Data {
        var source = [UInt8](input)
        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var output = Data()
        let inputCount = source.count

        let status: Int32 = source.withUnsafeMutableBufferPointer { inputPointer in
            stream.next_in = inputPointer.baseAddress
            stream.avail_in = uInt(inputCount)
            var result = Z_OK
            while result == Z_OK {
                result = buffer.withUnsafeMutableBufferPointer { outputPointer in
                    guard let base = outputPointer.baseAddress else { return Z_MEM_ERROR }
                    stream.next_out = base
                    stream.avail_out = uInt(chunkSize)
                    let stepResult = step(&stream)
                    output.append(base, count: chunkSize - Int(stream.avail_out))
                    return stepResult
                }
            }
            return result
        }

        guard status == Z_STREAM_END else { throw GzipError.zlib(status) }
        return output
    }
}
```

- [ ] **Step 4: Implementare `SessionLogWriter` e `PendingJournal`**

`Sources/CleanerCore/History/PendingJournal.swift`:

```swift
import Foundation

/// Diario della pulizia (spec §8.2). In C# `CleanEngine` intercettava qualunque eccezione per non
/// perdere l'elenco di ciò che era già stato cancellato; in Swift un errore di programmazione
/// termina il processo senza possibilità di intercettarlo. Ogni percorso eliminato viene quindi
/// aggiunto subito in coda a `logs/pending-<timestamp>.jsonl`, in chiaro: dopo un arresto
/// improvviso il file resta leggibile. A fine sessione, scritto il log compresso, viene rimosso.
public final class PendingJournal: DeletionRecording {
    public let path: String
    private let fileSystem: any FileSystem

    init(path: String, fileSystem: any FileSystem) {
        self.path = path
        self.fileSystem = fileSystem
    }

    public func recordDeleted(_ deletedPath: String) {
        // Il diario è una rete di sicurezza: un suo errore non deve mai fermare la pulizia.
        try? fileSystem.appendData(path, Data(SessionLogWriter.jsonLine(deletedPath).utf8))
    }
}
```

`Sources/CleanerCore/History/SessionLogWriter.swift`:

```swift
import Foundation

public protocol SessionLogWriting: Sendable {
    func write(sessionId: Int64, report: CleanReport) async throws
    func openJournal(startedAt: Date) -> PendingJournal?
    func discard(_ journal: PendingJournal)
}

/// Elenco completo dei percorsi eliminati, una riga JSON per elemento, compresso. Non va in
/// SQLite: una pulizia delle cache tocca centinaia di migliaia di file e il database crescerebbe
/// più in fretta dello spazio liberato.
public struct SessionLogWriter: SessionLogWriting {
    private let fileSystem: any FileSystem
    private let paths: AppPaths
    private let retention: Int

    public init(fileSystem: any FileSystem, paths: AppPaths, retention: Int = 20) {
        self.fileSystem = fileSystem
        self.paths = paths
        self.retention = retention
    }

    @concurrent
    public func write(sessionId: Int64, report: CleanReport) async throws {
        try fileSystem.createDirectory(paths.logsDirectory)

        var text = ""
        for path in report.deletedPaths {
            try Task.checkCancellation()
            text += Self.jsonLine(path)
        }

        let file = PathText.join(paths.logsDirectory, Self.fileName(sessionId))
        try fileSystem.writeData(file, Gzip.compress(Data(text.utf8)))
        try prune()
    }

    public func openJournal(startedAt: Date) -> PendingJournal? {
        do {
            try fileSystem.createDirectory(paths.logsDirectory)
            let path = PathText.join(paths.logsDirectory, "pending-\(Self.journalStamp(startedAt)).jsonl")
            try fileSystem.appendData(path, Data())
            return PendingJournal(path: path, fileSystem: fileSystem)
        } catch {
            // Senza diario la pulizia procede comunque, come in C#.
            return nil
        }
    }

    public func discard(_ journal: PendingJournal) {
        try? fileSystem.deleteFile(journal.path)
    }

    /// `{"path":"…"}` più "\n", lo stesso record che scriveva il C#. L'escape è scritto a mano: un
    /// `JSONEncoder` per ciascuna di centinaia di migliaia di righe costerebbe senza motivo.
    public static func jsonLine(_ path: String) -> String {
        var escaped = ""
        for scalar in path.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case _ where scalar.value < 0x20: escaped += String(format: "\\u%04x", scalar.value)
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "{\"path\":\"\(escaped)\"}\n"
    }

    private static func fileName(_ sessionId: Int64) -> String {
        String(format: "session-%06lld.jsonl.gz", sessionId)
    }

    /// "20260915T103000Z": data e ora UTC del diario, leggibili e ordinabili.
    private static func journalStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(
            format: "%04d%02d%02dT%02d%02d%02dZ",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// Ordina sul valore NUMERICO del nome: oltre le sei cifre l'ordine lessicografico metterebbe
    /// "1…" prima di "9…" e la rotazione cancellerebbe la sessione più recente. I nomi che non
    /// corrispondono a `session-<cifre>.jsonl.gz` (diari compresi) non sono toccati mai.
    private func prune() throws {
        let stale = try fileSystem.contentsOfDirectory(paths.logsDirectory)
            .filter { fileSystem.fileExists($0) }
            .compactMap { path in Self.sessionId(of: PathText.fileName(path)).map { (path: path, id: $0) } }
            .sorted { $0.id > $1.id }
            .dropFirst(retention)

        for entry in stale {
            // La rotazione dei log non deve far fallire una pulizia riuscita.
            try? fileSystem.deleteFile(entry.path)
        }
    }

    private static func sessionId(of name: String) -> Int64? {
        guard let match = name.wholeMatch(of: /session-(\d+)\.jsonl\.gz/) else { return nil }
        return Int64(match.1)
    }
}
```

- [ ] **Step 5: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter "GzipTests|SessionLogWriterTests"`
Expected: `Test run with 14 tests … passed` (4 `GzipTests`, 10 `SessionLogWriterTests`).

- [ ] **Step 6: Registro di parità e commit**

Riga `History/SessionLogWriterTests.cs` (6 → 10: +4 nuovi per il diario). Note: «lunghezza esatta del gzip vuoto (15 byte, dettaglio di .NET) non portata; il file in sola lettura diventa `FailingWriteFileSystem`». Tabella differenze: `| Diario pending-*.jsonl | assente (catch-all in CleanEngine) | presente | voluta (spec §8.2) |`.

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port session log writer with gzip and pending journal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: `ProcessRunner`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/ProcessRunner.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/ProcessRunnerTests.swift`
- Reference: `src/MjmCleaner.Core/Docker/ProcessRunner.cs` (in Swift sta in `Platform/`: lo usano anche Diagnostics e Xcode)

**Interfaces:**
- Consumes: niente oltre Foundation/Darwin.
- Produces:
  - `public struct ProcessResult: Sendable, Equatable` — `exitCode: Int32`, `standardOutput: String`, `standardError: String`, `timedOut: Bool`; `init(exitCode:standardOutput:standardError:timedOut:)`
  - `public struct ProcessLaunchError: Error, Equatable, Sendable` — `executable: String`, `code: Int32`; `init(executable:code:)`
  - `public protocol ProcessRunning: Sendable` — `func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult`; in estensione `run(_:_:timeout:)`
  - `public final class ProcessRunner: ProcessRunning` — `init()`

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Platform/ProcessRunnerTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Test su processi reali e innocui: argomenti senza shell, timeout, annullamento, terminazione
/// dell'intero process group.
struct ProcessRunnerTests {
    private let runner = ProcessRunner()

    @Test func passesArgumentsVerbatimWithoutAShell() async throws {
        let result = try await runner.run("/bin/echo", ["a b", "{{json .}}", "$HOME"], timeout: .seconds(5))
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "a b {{json .}} $HOME\n")
        #expect(!result.timedOut)
    }

    @Test func resolvesBareNamesFromPathAndCapturesStandardError() async throws {
        let result = try await runner.run("ls", ["/definitely/missing"], timeout: .seconds(5))
        #expect(result.exitCode != 0)
        #expect(!result.standardError.isEmpty)
    }

    @Test func timeoutKillsTheWholeProcessGroup() async throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let pidFile = tmp.path + "/nipote.pid"
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await runner.run("/bin/sh", ["-c", "sleep 30 & echo $! > \(pidFile); wait"], timeout: .milliseconds(300))

        #expect(result.timedOut)
        #expect(clock.now - start < .seconds(5))
        try await Task.sleep(for: .milliseconds(200))
        let grandchild = try #require(pid_t(try String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(kill(grandchild, 0) == -1)
    }

    @Test func callerCancellationPropagatesAsCancellation() async throws {
        let task = Task { try await runner.run("/bin/sleep", ["30"], timeout: .seconds(60)) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func environmentOverridesAreVisibleToTheChild() async throws {
        let result = try await runner.run("/bin/sh", ["-c", "printf %s \"$MJM_PROBE\""], timeout: .seconds(5), environment: ["MJM_PROBE": "valore"])
        #expect(result.standardOutput == "valore")
    }

    @Test func missingExecutableThrowsLaunchError() async {
        await #expect(throws: ProcessLaunchError.self) {
            _ = try await runner.run("/no/such/binary", [], timeout: .seconds(5))
        }
    }
}
```

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter ProcessRunnerTests`
Expected: errore di compilazione `cannot find 'ProcessRunner' in scope`.

- [ ] **Step 3: Implementare `ProcessRunner`** (prototipato e verificato con gli stessi test durante la stesura del piano)

`Sources/CleanerCore/Platform/ProcessRunner.swift`:

```swift
import Darwin
import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool

    public init(exitCode: Int32, standardOutput: String, standardError: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }
}

public struct ProcessLaunchError: Error, Equatable, Sendable {
    public let executable: String
    public let code: Int32

    public init(executable: String, code: Int32) {
        self.executable = executable
        self.code = code
    }
}

public protocol ProcessRunning: Sendable {
    func run(
        _ executable: String,
        _ arguments: [String],
        timeout: Duration,
        environment: [String: String]?
    ) async throws -> ProcessResult
}

extension ProcessRunning {
    public func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> ProcessResult {
        try await run(executable, arguments, timeout: timeout, environment: nil)
    }
}

/// Avvia un processo con gli argomenti in un array, senza una shell che li reinterpreti: un nome
/// di volume o un template `{{json .}}` non possono diventare un comando diverso da quello scritto.
/// Un nome senza "/" si cerca nel PATH, come `ProcessStartInfo` in .NET.
public final class ProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        _ executable: String,
        _ arguments: [String],
        timeout: Duration,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let child = try SpawnedProcess.launch(executable, arguments, environment: environment)

        let outcome: WaitOutcome = await withTaskCancellationHandler {
            await withTaskGroup(of: WaitOutcome.self) { group in
                group.addTask { await child.waitForExit() }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                if case .timedOut = first {
                    child.killGroup()
                }
                group.cancelAll()
                return first
            }
        } onCancel: {
            child.killGroup()
        }

        // L'annullamento richiesto dal chiamante si propaga come tale; il timeout no.
        try Task.checkCancellation()

        switch outcome {
        case .timedOut:
            // Come in C#: al timeout non si attende l'output, che un nipote sopravvissuto potrebbe
            // tenere aperto indefinitamente.
            return ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)
        case .exited(let status):
            let output = await child.collectOutput()
            return ProcessResult(exitCode: status, standardOutput: output.stdout, standardError: output.stderr, timedOut: false)
        }
    }
}

enum WaitOutcome: Sendable {
    case exited(Int32)
    case timedOut
}

/// Processo figlio avviato con `posix_spawnp` in un proprio process group: al timeout o
/// all'annullamento si termina l'intero gruppo, come `Kill(entireProcessTree: true)` in C#.
/// Foundation `Process` terminerebbe solo il figlio diretto, lasciando vivo `simctl` dietro `xcrun`.
final class SpawnedProcess: @unchecked Sendable {
    let pid: pid_t
    private let stdoutTask: Task<Data, Never>
    private let stderrTask: Task<Data, Never>
    private let exitTask: Task<Int32, Never>

    private init(pid: pid_t, stdout: Int32, stderr: Int32) {
        self.pid = pid
        stdoutTask = Task.detached { await SpawnedProcess.readToEnd(stdout) }
        stderrTask = Task.detached { await SpawnedProcess.readToEnd(stderr) }
        exitTask = Task.detached { await SpawnedProcess.reap(pid) }
    }

    static func launch(_ executable: String, _ arguments: [String], environment: [String: String]?) throws -> SpawnedProcess {
        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { throw ProcessLaunchError(executable: executable, code: errno) }
        guard pipe(&errPipe) == 0 else {
            let code = errno
            close(outPipe[0])
            close(outPipe[1])
            throw ProcessLaunchError(executable: executable, code: code)
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)

        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment ?? [:] { merged[key] = value }

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = merged.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let status = posix_spawnp(&pid, executable, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])

        guard status == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw ProcessLaunchError(executable: executable, code: status)
        }

        return SpawnedProcess(pid: pid, stdout: outPipe[0], stderr: errPipe[0])
    }

    func waitForExit() async -> WaitOutcome {
        .exited(await exitTask.value)
    }

    func killGroup() {
        // Il gruppo può essere già terminato fra il timeout e il kill: non è un errore.
        _ = killpg(pid, SIGKILL)
    }

    func collectOutput() async -> (stdout: String, stderr: String) {
        _ = await exitTask.value
        let out = await stdoutTask.value
        let err = await stderrTask.value
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    private static func readToEnd(_ descriptor: Int32) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }

    private static func reap(_ pid: pid_t) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var status: Int32 = 0
                while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
                // WIFEXITED/WEXITSTATUS e WTERMSIG sono macro C, non importate in Swift.
                let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                continuation.resume(returning: exitCode)
            }
        }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter ProcessRunnerTests`
Expected: `Test run with 6 tests … passed`.

- [ ] **Step 5: Commit**

```bash
git add swift/MjmCleanerKit
git commit -m "feat(swift): add posix_spawn process runner with group termination

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Diagnostics: `RunningAppsProbe`

**Files:**
- Create: `swift/MjmCleanerKit/Sources/CleanerCore/Diagnostics/RunningAppsProbe.swift`
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Diagnostics/RunningAppsProbeTests.swift`
- Reference: `src/MjmCleaner.Core/Diagnostics/RunningAppsProbe.cs`, `tests/MjmCleaner.Core.Tests/Diagnostics/RunningAppsProbeTests.cs`

**Interfaces:**
- Consumes: `PathText` (Task 1); `ProcessRunning`, `ProcessResult` (Task 12).
- Produces:
  - `public protocol RunningAppsProbing: Sendable` — `func affectedApps(_ paths: [String]) async -> [String]`
  - `public struct RunningAppsProbe: RunningAppsProbing` — `init(processNames: @escaping @Sendable () async -> [String])`, `static func extractApplicationNames(_ processPaths: [String], home: String = NSHomeDirectory()) -> [String]`, `static func forCurrentMachine(runner: any ProcessRunning = ProcessRunner(), home: String = NSHomeDirectory()) -> RunningAppsProbe`

`affectedApps` diventa `async` rispetto al C#: la raccolta dei processi passa da `ProcessRunner`, che è asincrono.

- [ ] **Step 1: Scrivere i test (falliscono)**

`Tests/CleanerCoreTests/Diagnostics/RunningAppsProbeTests.swift`:

```swift
import Foundation
import Testing
@testable import CleanerCore

struct RunningAppsProbeTests {
    private func create(_ processes: String...) -> RunningAppsProbe {
        RunningAppsProbe(processNames: { processes })
    }

    @Test func matchesBundleIdentifierAgainstProcessName() async {
        #expect(await create("Safari", "Finder").affectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]) == ["Safari"])
    }

    @Test func ignoresProcessesNotInvolved() async {
        #expect(await create("Mail").affectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]).isEmpty)
    }

    @Test func reportsEachApplicationOnlyOnce() async {
        let affected = await create("Safari").affectedApps([
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.apple.Safari.WebKit",
        ])
        #expect(affected == ["Safari"])
    }

    @Test func ignoresVeryShortProcessNamesToAvoidFalsePositives() async {
        #expect(await create("ls").affectedApps(["/Users/tester/Library/Caches/com.apple.Tools"]).isEmpty)
    }

    // Confronto per parole intere, non per sottostringa: "Dock" (macOS Dock) non deve
    // corrispondere a "com.docker.docker" né a "Docker Desktop".
    @Test(arguments: [
        ("Safari", "/Users/tester/Library/Caches/com.apple.Safari", true),
        ("Google Chrome", "/Users/tester/Library/Caches/com.google.Chrome", true),
        ("Docker", "/Users/tester/Library/Caches/Docker Desktop", true),
        ("Dock", "/Users/tester/Library/Caches/com.docker.docker", false),
        ("Dock", "/Users/tester/Library/Caches/Docker Desktop", false),
    ])
    func matchesWholeWordsNotSubstrings(processName: String, path: String, expectMatch: Bool) async {
        let affected = await create(processName).affectedApps([path])
        #expect(affected == (expectMatch ? [processName] : []))
    }

    @Test func systemDaemonsDoNotMatchRealisticCacheFolders() async {
        let affected = await create("accountsd", "secd", "tipsd").affectedApps([
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.google.Chrome",
            "/Users/tester/Library/Caches/JetBrains",
            "/Users/tester/Library/Caches/Homebrew",
            "/Users/tester/Library/Caches/Docker Desktop",
        ])
        #expect(affected.isEmpty)
    }

    @Test func reportsFullProcessNameWhenOnlyOneWordMatches() async {
        #expect(await create("Docker Desktop").affectedApps(["/Users/tester/Library/Caches/Docker"]) == ["Docker Desktop"])
    }

    @Test(arguments: [
        ("/Applications/Safari.app/Contents/MacOS/Safari", "Safari"),
        ("/System/Applications/Calendar.app/Contents/MacOS/Calendar", "Calendar"),
    ])
    func extractApplicationNamesRecognizesSimpleBundlesInStandardLocations(path: String, expectedName: String) {
        #expect(RunningAppsProbe.extractApplicationNames([path]) == [expectedName])
    }

    @Test func extractApplicationNamesRecognizesBundlesUnderTheUserHomeDirectory() {
        let home = NSHomeDirectory()
        let path = "\(home)/Applications/HomeBrewedApp.app/Contents/MacOS/HomeBrewedApp"
        #expect(RunningAppsProbe.extractApplicationNames([path], home: home) == ["HomeBrewedApp"])
    }

    @Test func extractApplicationNamesReturnsTheOutermostBundleNameForNestedHelperProcesses() {
        let names = RunningAppsProbe.extractApplicationNames([
            "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
        ])
        #expect(names == ["Claude"])
    }

    @Test(arguments: [
        "/usr/libexec/secd",
        "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        "",
        "   ",
        "not a path at all",
    ])
    func extractApplicationNamesDiscardsPathsOutsideUserFacingApplications(path: String) {
        #expect(RunningAppsProbe.extractApplicationNames([path]).isEmpty)
    }

    @Test func extractApplicationNamesIgnoresRealisticSystemDaemonPaths() {
        let names = RunningAppsProbe.extractApplicationNames([
            "/usr/libexec/secd",
            "/System/Library/Frameworks/Accounts.framework/Versions/A/Support/accountsd",
            "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter",
        ])
        #expect(names.isEmpty)
    }

    // MARK: - Nuovi: raccolta tramite ProcessRunning

    private struct FakeProcessRunner: ProcessRunning {
        let outcome: Result<ProcessResult, any Error>

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            #expect(executable == "ps")
            #expect(arguments == ["-axo", "comm="])
            return try outcome.get()
        }
    }

    @Test func forCurrentMachineReadsApplicationNamesFromPs() async {
        let output = """
            /usr/libexec/secd
            /Applications/Safari.app/Contents/MacOS/Safari
              /Applications/Mail.app/Contents/MacOS/Mail\u{20}\u{20}

            """
        let probe = RunningAppsProbe.forCurrentMachine(
            runner: FakeProcessRunner(outcome: .success(ProcessResult(exitCode: 0, standardOutput: output, standardError: "", timedOut: false))),
            home: "/Users/tester")

        #expect(await probe.affectedApps(["/Users/tester/Library/Caches/com.apple.Safari", "/Users/tester/Library/Caches/com.apple.mail"]) == ["Mail", "Safari"])
    }

    // Un avviso che non si può calcolare non deve mai impedire una pulizia.
    @Test(arguments: [
        Result<ProcessResult, any Error>.success(ProcessResult(exitCode: 1, standardOutput: "/Applications/Safari.app/Contents/MacOS/Safari", standardError: "", timedOut: false)),
        .success(ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)),
        .failure(ProcessLaunchError(executable: "ps", code: 2)),
    ])
    func forCurrentMachineDegradesToNoWarningOnFailure(outcome: Result<ProcessResult, any Error>) async {
        let probe = RunningAppsProbe.forCurrentMachine(runner: FakeProcessRunner(outcome: outcome), home: "/Users/tester")
        #expect(await probe.affectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]).isEmpty)
    }
}
```

Se `Result<ProcessResult, any Error>` non è accettato come argomento di `@Test(arguments:)` perché non `Sendable`, sostituire nel test parametrico l'enumerazione con un `enum PsFailure: Sendable, CaseIterable { case nonZeroExit, timedOut, launchError }` e costruire il `Result` dentro il test.

- [ ] **Step 2: Verificare che falliscano**

Run: `swift test -Xswiftc -warnings-as-errors --filter RunningAppsProbeTests`
Expected: errore di compilazione `cannot find 'RunningAppsProbe' in scope`.

- [ ] **Step 3: Implementare `RunningAppsProbe`**

`Sources/CleanerCore/Diagnostics/RunningAppsProbe.swift`:

```swift
import Foundation

public protocol RunningAppsProbing: Sendable {
    func affectedApps(_ paths: [String]) async -> [String]
}

/// Euristica: svuotare la cache di un'applicazione aperta può farla comportare in modo anomalo
/// fino al riavvio, quindi conviene avvisare prima di eliminare.
public struct RunningAppsProbe: RunningAppsProbing {
    private static let minimumWordLength = 4
    private static let bundleMarker = ".app/"
    private static let executableMarker = ".app/Contents/MacOS/"
    private static let psTimeout: Duration = .seconds(5)

    private let processNames: @Sendable () async -> [String]

    public init(processNames: @escaping @Sendable () async -> [String]) {
        self.processNames = processNames
    }

    public func affectedApps(_ paths: [String]) async -> [String] {
        var seenProcesses = Set<String>()
        var candidates: [(fullName: String, significantWords: [String])] = []
        for name in await processNames() where seenProcesses.insert(name.lowercased()).inserted {
            let words = Self.splitIntoWords(name).filter { $0.utf16.count >= Self.minimumWordLength }
            if !words.isEmpty { candidates.append((name, words)) }
        }

        guard !candidates.isEmpty else { return [] }

        var folderWords = Set<String>()
        for path in paths {
            for word in Self.splitIntoWords(PathText.fileName(path)) {
                folderWords.insert(word.lowercased())
            }
        }

        var affected: [String: String] = [:]
        for candidate in candidates where candidate.significantWords.contains(where: { folderWords.contains($0.lowercased()) }) {
            let key = candidate.fullName.lowercased()
            if affected[key] == nil { affected[key] = candidate.fullName }
        }

        return affected.values.sorted { $0.compare($1, options: [.caseInsensitive, .literal]) == .orderedAscending }
    }

    /// Scompone un nome nelle sue parole (separatori: punto, spazio, trattino, trattino basso),
    /// per confrontare parole intere: "Dock" non deve corrispondere a "com.docker.docker".
    private static func splitIntoWords(_ value: String) -> [String] {
        value.split(whereSeparator: { ".- _".contains($0) }).map(String.init)
    }

    // Raccolta dei nomi sulla macchina reale: non basta il nome breve del processo. Conta che sia
    // un'applicazione che l'utente può chiudere: si chiede a `ps` il percorso completo e si tengono
    // solo gli eseguibili dentro un bundle .app in /Applications, /System/Applications o sotto la
    // home — non sotto /System/Library, dove vivono agenti di sistema (ControlCenter, WiFiAgent)
    // che l'utente non percepisce come "un'app aperta".

    public static func forCurrentMachine(runner: any ProcessRunning = ProcessRunner(), home: String = NSHomeDirectory()) -> RunningAppsProbe {
        RunningAppsProbe {
            RunningAppsProbe.extractApplicationNames(await RunningAppsProbe.collectProcessPaths(runner), home: home)
        }
    }

    /// Dai percorsi completi dei processi (forma di `ps -axo comm=`) ai nomi delle applicazioni
    /// utente: per ciascuno, il nome del primo bundle .app nel percorso, cioè l'app visibile e non un
    /// suo Helper annidato (".../Claude.app/.../Claude Helper.app/..." → "Claude").
    public static func extractApplicationNames(_ processPaths: [String], home: String = NSHomeDirectory()) -> [String] {
        let allowedRoots = ["/Applications/", "/System/Applications/", PathText.trimmingTrailingSlashes(home) + "/"]
        var seen = Set<String>()
        var names: [String] = []

        for path in processPaths {
            guard !path.allSatisfy(\.isWhitespace),
                  path.contains(executableMarker),
                  allowedRoots.contains(where: { path.hasPrefix($0) }),
                  let bundleName = firstBundleName(path) else {
                continue
            }
            if seen.insert(bundleName.lowercased()).inserted {
                names.append(bundleName)
            }
        }

        return names
    }

    private static func firstBundleName(_ path: String) -> String? {
        guard let bundle = path.range(of: bundleMarker) else { return nil }
        let beforeBundle = path[..<bundle.lowerBound]
        let name = beforeBundle.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? String(beforeBundle)
        return name.isEmpty ? nil : name
    }

    /// L'unico punto che dipende da un comando esterno. Un avviso che non si può calcolare non deve
    /// mai impedire una pulizia: qualunque fallimento restituisce un elenco vuoto.
    static func collectProcessPaths(_ runner: any ProcessRunning) async -> [String] {
        do {
            let result = try await runner.run("ps", ["-axo", "comm="], timeout: psTimeout)
            guard !result.timedOut, result.exitCode == 0 else { return [] }
            return result.standardOutput
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
}
```

- [ ] **Step 4: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter RunningAppsProbeTests`
Expected: `Test run with 14 tests … passed`.

- [ ] **Step 5: Registro di parità e commit**

Riga `Diagnostics/RunningAppsProbeTests.cs` (12 (12) → 14: +2 nuovi per la raccolta via `ps`). Note: «`AffectedApps` diventa `async`; `ExtractApplicationNames` riceve la home come parametro con valore predefinito».

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "feat(swift): port RunningAppsProbe on the process runner

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Integrazione sul filesystem reale, chiusura del piano

Il filesystem simulato non riproduce collegamenti, permessi né la topologia `/var` → `/private/var` di macOS: questo task verifica la catena reale `RuleScanner` → `CleanEngine` → `SessionLogWriter` con `LocalFileSystem`, `FileSystemLinkInspector` e `PathGuard`, e chiude il piano.

**Files:**
- Test: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift`
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: tutto il modulo (Task 1–13).
- Produces: nessuna API nuova.

- [ ] **Step 1: Scrivere i test di integrazione**

`Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift`:

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Catena reale scansione → pulizia → log su una cartella temporanea. La "home" di prova vive
/// sotto $TMPDIR (/var/folders/…), quindi ogni root passa davvero per la risoluzione
/// /var → /private/var che in produzione riguarda la categoria $TMPDIR.
struct RealFileSystemCleanupTests {
    private struct Fixture {
        let tmp: TemporaryDirectory
        let home: String
        let caches: String
        let scanner: RuleScanner
        let engine: CleanEngine

        init() throws {
            tmp = try TemporaryDirectory()
            home = try tmp.directory("home")
            caches = try tmp.directory("home/Library/Caches")
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
            scanner = RuleScanner(fileSystem: LocalFileSystem(), pathGuard: pathGuard, links: links, clock: SystemWallClock())
            engine = CleanEngine(fileSystem: LocalFileSystem(), pathGuard: pathGuard, clock: SystemWallClock())
        }

        func cleanAll(_ outcome: RuleScanOutcome, journal: (any DeletionRecording)? = nil) async -> CleanReport {
            await engine.clean([CategorySelection(categoryId: "caches", items: outcome.items)], progress: nil, journal: journal)
        }
    }

    @Test func linkToAFileIsRemovedButItsTargetSurvives() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let thesis = try fixture.tmp.file("home/Documents/tesi.docx", contents: "dati preziosi")
        try fixture.tmp.file("home/Library/Caches/app/dati.bin", contents: String(repeating: "x", count: 100))
        try fixture.tmp.file("home/Library/Caches/solo.tmp", contents: String(repeating: "y", count: 50))
        let link = try fixture.tmp.symlink("home/Library/Caches/collegamento", to: thesis)

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        #expect(outcome.items.count == 3)

        let report = await fixture.cleanAll(outcome)

        #expect(report.itemsDeleted == 3)
        #expect(report.itemsFailed == 0)
        #expect(FileManager.default.fileExists(atPath: thesis))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == nil)
        // Accreditati: 100 + 50 + la dimensione del collegamento stesso (come FileInfo.Length).
        #expect(report.bytesFreed == 150 + Int64(thesis.utf8.count))
    }

    @Test func accessDeniedInsideACacheFolderFailsOnlyThatItemWithTheRightKind() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let locked = try fixture.tmp.directory("home/Library/Caches/bloccata/sub")
        try fixture.tmp.file("home/Library/Caches/bloccata/sub/x.bin", contents: "x")
        try fixture.tmp.file("home/Library/Caches/libera.tmp", contents: "y")
        chmod(locked, 0o555)

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        let report = await fixture.cleanAll(outcome)

        #expect(report.itemsDeleted == 1)
        #expect(report.itemsFailed == 1)
        #expect(report.errors.contains { $0.kind == .accessDenied })
    }

    // Comportamento C# replicato alla lettera (registro di parità, candidati a miglioramento):
    // un collegamento a una cartella, in clearContents, non viene eliminato.
    @Test func linkToADirectoryIsReportedAsNotFoundAndLeftInPlace() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Documents/fatture/2026.pdf", contents: "dati")
        let link = try fixture.tmp.symlink("home/Library/Caches/versoCartella", to: fixture.home + "/Documents")

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        let report = await fixture.cleanAll(outcome)

        #expect(report.itemsFailed == 1)
        #expect(report.errors.contains { $0.kind == .notFound })
        #expect(FileManager.default.fileExists(atPath: fixture.home + "/Documents/fatture/2026.pdf"))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) != nil)
    }

    @Test func deletedPathsAreResolvedUnderPrivateVarAndReachTheJournalAndTheSessionLog() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        try fixture.tmp.file("home/Library/Caches/a.tmp", contents: "a")
        let support = try fixture.tmp.directory("support")
        let writer = SessionLogWriter(fileSystem: LocalFileSystem(), paths: AppPaths(supportDirectory: support))
        let journal = try #require(writer.openJournal(startedAt: Date()))

        let outcome = try fixture.scanner.scan(CleanupRule(fixture.caches, .clearContents, include: ["*"], exclude: []))
        let report = await fixture.cleanAll(outcome, journal: journal)

        // La root dichiarata è sotto /var/folders; il percorso eliminato è quello risolto dal guard.
        let deleted = try #require(report.deletedPaths.first)
        #expect(deleted.hasPrefix("/private/var/"))
        #expect(try LocalFileSystem().readText(journal.path).contains(deleted))

        try await writer.write(sessionId: 1, report: report)
        writer.discard(journal)

        let log = try LocalFileSystem().readData(PathText.join(AppPaths(supportDirectory: support).logsDirectory, "session-000001.jsonl.gz"))
        #expect(String(decoding: try Gzip.decompress(log), as: UTF8.self).contains(deleted))
        #expect(!FileManager.default.fileExists(atPath: journal.path))
    }
}
```

- [ ] **Step 2: Verificare che passino**

Run: `swift test -Xswiftc -warnings-as-errors --filter RealFileSystemCleanupTests`
Expected: `Test run with 4 tests … passed`. Se `deletedPathsAreResolved…` fallisce sul prefisso, verificare con `ls -ld /var` che `/var` sia un collegamento a `private/var` (vero su ogni macOS di serie) prima di toccare il codice.

- [ ] **Step 3: Eseguire l'intera suite**

Run (da `swift/MjmCleanerKit`): `swift test -Xswiftc -warnings-as-errors`
Expected: tutti i test passano, nessun warning. Conteggio atteso: 8 (Task 1) + 19 (Task 2) + 6 (Task 3) + 56 (Task 4) + 10 (Task 5) + 17 (Task 6) + 38 (Task 7) + 6 (Task 8) + 26 (Task 9) + 6 (Task 10) + 14 (Task 11) + 6 (Task 12) + 14 (Task 13) + 4 (Task 14) = **230 test**.

- [ ] **Step 4: Verificare i vincoli globali**

Run (da `swift/MjmCleanerKit`):

```bash
grep -rnE 'try!|as!|import (SwiftUI|AppKit)' Sources/CleanerCore || echo "nessuna violazione"
grep -rnE '[A-Za-z0-9_\)\]]!([^=]|$)' Sources/CleanerCore || echo "nessun forced unwrap"
```

Expected: entrambe le righe stampano il messaggio di nessuna violazione. Il secondo pattern può segnalare falsi positivi dentro stringhe o commenti: controllare a mano ogni riga segnalata. Un `!` di negazione logica (`!x`) non corrisponde al pattern.

- [ ] **Step 5: Chiudere il registro di parità**

Verificare che tutte le righe del piano 1 abbiano file Swift e conteggio compilati, e aggiungere in testa al file, con la data del giorno in formato AAAA-MM-GG, la riga: «Piano 1 completato il AAAA-MM-GG: 176 prove C# portate (+ 54 nuove), suite Swift verde.»

- [ ] **Step 6: Commit**

```bash
git add swift/MjmCleanerKit docs/superpowers/porting/2026-10-13-parity.md
git commit -m "test(swift): verify the real-filesystem cleanup chain and close plan 1

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Dopo il piano 1

Il piano 2 (Docker e Xcode) si scrive a piano 1 completato, sul codice reale. Consumerà `ProcessRunning`, `FileSystem`, `PathGuard`, `CleanEngine`, `RuleScanner` e i modelli di questo piano, e dovrà aggiungere a `FileSystem` lo spazio libero del volume (`DriveInfo` in C#, usato da `XcodeSizeProbe` e `DiskUsageProbe`).
