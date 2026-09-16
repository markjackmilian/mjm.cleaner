# mjm.cleaner — Piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Applicazione macOS con interfaccia Avalonia che elimina file temporanei rigenerabili per categoria, con anteprima obbligatoria, storico delle pulizie e contatore cumulativo dei gigabyte liberati.

**Architecture:** Un core in C# senza dipendenze dall'interfaccia (`MjmCleaner.Core`) contiene regole, scansione, eliminazione, protezioni e persistenza; un progetto Avalonia (`MjmCleaner.App`) lo pilota attraverso un wizard a quattro passi. Scansione ed eliminazione sono fasi separate: la seconda consuma l'elenco prodotto dalla prima senza ri-scansionare. Ogni eliminazione passa per un `PathGuard` che convalida il percorso immediatamente prima dell'operazione.

**Tech Stack:** .NET 10 (SDK 10.0.401), Avalonia 12.1.2, CommunityToolkit.Mvvm 8.4.2, Microsoft.Data.Sqlite 10.0.12, System.IO.Abstractions 22.2.0, xunit.v3 4.0.1.

**Spec:** `docs/superpowers/specs/2026-09-15-mjm-cleaner-design.md`

## Global Constraints

- **Target framework:** `net10.0` per tutti i progetti. `dotnet` non è nel PATH della shell non interattiva: usare `export PATH="/usr/local/share/dotnet:$PATH"` a inizio sessione.
- **`MjmCleaner.Core` non referenzia Avalonia.** Vincolo architetturale verificato dal Task 1: nessun `PackageReference` ad Avalonia nel `.csproj` del Core.
- **Ogni accesso al filesystem nel Core passa da `IFileSystem`** (System.IO.Abstractions), mai da `System.IO` statico. Serve a rendere le regole testabili senza toccare dati reali.
- **Nessuna elevazione di privilegi.** Niente `sudo`, niente helper privilegiati. Gli elementi di proprietà di `root` falliscono con accesso negato e finiscono nel riepilogo errori.
- **I symlink non vengono mai seguiti.** Si elimina il collegamento, mai il bersaglio.
- **Confronti fra percorsi case-insensitive** (`StringComparison.OrdinalIgnoreCase`): APFS è case-insensitive nella configurazione predefinita.
- **Lingua:** interfaccia e documentazione in italiano; codice, nomi di simboli e messaggi di commit in inglese.
- **Ogni messaggio di commit termina con la riga** `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>` (riga vuota prima).
- **Nessun `Avalonia.Diagnostics`:** l'ultima versione stabile è la 11.3.22, non allineata ad Avalonia 12.

---

## Struttura dei file

| File | Responsabilità |
|---|---|
| `src/MjmCleaner.Core/Safety/ILinkInspector.cs` | Astrazione per riconoscere i collegamenti simbolici |
| `src/MjmCleaner.Core/Safety/FileSystemLinkInspector.cs` | Implementazione reale di `ILinkInspector` |
| `src/MjmCleaner.Core/Safety/PathGuard.cs` | Le cinque regole di protezione |
| `src/MjmCleaner.Core/Safety/DenyList.cs` | Elenco dei percorsi non eliminabili |
| `src/MjmCleaner.Core/Settings/CleanerSettings.cs` | Record delle preferenze utente |
| `src/MjmCleaner.Core/Settings/SettingsStore.cs` | Lettura/scrittura `settings.json` |
| `src/MjmCleaner.Core/Settings/AppPaths.cs` | Percorsi dell'applicazione in Application Support |
| `src/MjmCleaner.Core/Categories/CleanupRule.cs` | Record regola + enum `ScanMode`, `RiskLevel` |
| `src/MjmCleaner.Core/Categories/CleanupCategory.cs` | Record categoria |
| `src/MjmCleaner.Core/Categories/PathExpander.cs` | Espansione di `~` e `$TMPDIR` |
| `src/MjmCleaner.Core/Categories/CategoryCatalog.cs` | Definizione delle cinque categorie |
| `src/MjmCleaner.Core/Scanning/ScanModels.cs` | `ScanItem`, `ScanError`, `GuardExclusion`, `CategoryScanResult`, `ScanProgress` |
| `src/MjmCleaner.Core/Scanning/RuleScanner.cs` | Interpreta una singola regola nelle tre modalità |
| `src/MjmCleaner.Core/Scanning/ScanEngine.cs` | Orchestrazione parallela, progresso, annullamento |
| `src/MjmCleaner.Core/Cleaning/CleanModels.cs` | `CategorySelection`, `CleanReport`, `CategoryCleanResult`, `CleanProgress` |
| `src/MjmCleaner.Core/Cleaning/CleanEngine.cs` | Eliminazione con errori per elemento |
| `src/MjmCleaner.Core/History/HistoryStore.cs` | Schema e query SQLite |
| `src/MjmCleaner.Core/History/SessionLogWriter.cs` | Log JSON Lines per sessione + retention |
| `src/MjmCleaner.Core/Diagnostics/RunningAppsProbe.cs` | Applicazioni in esecuzione interessate dalla pulizia |
| `src/MjmCleaner.App/ViewModels/*.cs` | Un ViewModel per passo del wizard, più toolbar, storico, impostazioni |
| `src/MjmCleaner.App/Views/*.axaml` | Le viste corrispondenti |
| `build/bundle.sh` | Pubblicazione, bundle `.app`, firma ad-hoc |

**Ordine di costruzione:** protezioni → regole → scansione → eliminazione → persistenza → interfaccia. Il `PathGuard` è il primo componente perché è quello in cui un difetto costa dati.

---

## Task 1: Scaffolding della soluzione

**Files:**
- Create: `mjm.cleaner.sln`, `Directory.Build.props`
- Create: `src/MjmCleaner.Core/MjmCleaner.Core.csproj`
- Create: `src/MjmCleaner.App/MjmCleaner.App.csproj`
- Create: `tests/MjmCleaner.Core.Tests/MjmCleaner.Core.Tests.csproj`

**Interfaces:**
- Consumes: niente (primo task)
- Produces: soluzione compilabile; `dotnet test` eseguibile; namespace radice `MjmCleaner.Core` e `MjmCleaner.App`

- [ ] **Step 1: Creare soluzione e progetti**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
cd /Users/mjm/projects/mjm.cleaner
dotnet new sln -n mjm.cleaner
dotnet new classlib -n MjmCleaner.Core -o src/MjmCleaner.Core -f net10.0
dotnet new xunit -n MjmCleaner.Core.Tests -o tests/MjmCleaner.Core.Tests -f net10.0
rm -f src/MjmCleaner.Core/Class1.cs
dotnet sln add src/MjmCleaner.Core tests/MjmCleaner.Core.Tests
dotnet add tests/MjmCleaner.Core.Tests reference src/MjmCleaner.Core
```

- [ ] **Step 2: Creare `Directory.Build.props`**

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <InvariantGlobalization>false</InvariantGlobalization>
  </PropertyGroup>
</Project>
```

- [ ] **Step 3: Allineare i pacchetti di test a xunit v3**

Aprire `tests/MjmCleaner.Core.Tests/MjmCleaner.Core.Tests.csproj`. Se contiene riferimenti a `xunit` 2.x, sostituire l'intero `ItemGroup` dei pacchetti con:

```xml
<ItemGroup>
  <PackageReference Include="xunit.v3" Version="4.0.1" />
  <PackageReference Include="xunit.runner.visualstudio" Version="4.0.0" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.10.1" />
  <PackageReference Include="System.IO.Abstractions.TestingHelpers" Version="22.2.0" />
</ItemGroup>
```

Se il file generato contiene già `xunit.v3`, aggiungere solo `System.IO.Abstractions.TestingHelpers`.

- [ ] **Step 4: Aggiungere le dipendenze del Core**

```bash
dotnet add src/MjmCleaner.Core package System.IO.Abstractions --version 22.2.0
dotnet add src/MjmCleaner.Core package Microsoft.Data.Sqlite --version 10.0.12
```

- [ ] **Step 5: Verificare che la soluzione compili e i test girino**

```bash
dotnet build && dotnet test
```
Atteso: build riuscita, 0 test falliti. Il template xunit può generare un test di esempio: se presente, eliminare il file `UnitTest1.cs`.

- [ ] **Step 6: Verificare il vincolo architetturale**

```bash
grep -i avalonia src/MjmCleaner.Core/MjmCleaner.Core.csproj; echo "exit=$?"
```
Atteso: nessuna riga trovata (`exit=1`). Il Core non deve dipendere da Avalonia.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: scaffold solution with Core and test projects"
```

---

## Task 2: Spike — accessibilità dei percorsi e Full Disk Access

**Obiettivo:** rispondere a due domande prima di scrivere codice di produzione. L'esito può modificare le categorie del Task 7. **Il codice di questo task è usa e getta e non viene mantenuto.**

**Files:**
- Create: `spikes/fda-probe/fda-probe.csproj`, `spikes/fda-probe/Program.cs` (temporanei)
- Create: `docs/superpowers/spikes/2026-09-15-full-disk-access.md` (permanente)

**Interfaces:**
- Consumes: niente
- Produces: documento con l'elenco dei percorsi che richiedono Full Disk Access; alimenta le note utente del Task 7

- [ ] **Step 1: Creare la sonda**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet new console -n fda-probe -o spikes/fda-probe -f net10.0
```

- [ ] **Step 2: Scrivere il programma di sonda**

`spikes/fda-probe/Program.cs`:

```csharp
string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
string tmp = Path.GetTempPath();

string[] targets =
[
    Path.Combine(home, "Library/Caches"),
    "/Library/Caches",
    Path.Combine(home, "Library/Logs"),
    "/Library/Logs",
    Path.Combine(home, "Library/Logs/DiagnosticReports"),
    "/Library/Logs/DiagnosticReports",
    Path.Combine(home, ".Trash"),
    Path.Combine(home, "Downloads"),
    Path.Combine(home, ".nuget/packages"),
    Path.Combine(home, ".npm"),
    Path.Combine(home, ".cache"),
    tmp,
];

foreach (string target in targets)
{
    string status;
    int count = 0;
    try
    {
        foreach (string _ in Directory.EnumerateFileSystemEntries(target))
        {
            count++;
            if (count >= 5) break;
        }
        status = count > 0 ? "OK" : "OK (vuota)";
    }
    catch (UnauthorizedAccessException) { status = "ACCESSO NEGATO"; }
    catch (DirectoryNotFoundException) { status = "ASSENTE"; }
    catch (Exception ex) { status = $"ERRORE: {ex.GetType().Name}"; }

    Console.WriteLine($"{status,-16} {target}");
}
```

- [ ] **Step 3: Eseguire dal terminale e annotare l'esito**

```bash
dotnet run --project spikes/fda-probe
```

Eseguire **senza** concedere Full Disk Access al terminale. Annotare quali percorsi rispondono `ACCESSO NEGATO`: sono quelli che richiederanno il permesso.

- [ ] **Step 4: Ripetere dopo aver concesso il permesso**

Concedere Full Disk Access all'applicazione Terminale in *Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco*, riavviare il terminale e rieseguire il comando dello Step 3. Confrontare i due esiti.

- [ ] **Step 5: Documentare le conclusioni**

Creare `docs/superpowers/spikes/2026-09-15-full-disk-access.md` con: tabella percorso → esito senza permesso → esito con permesso; elenco dei percorsi che richiedono Full Disk Access; nota su `~/.Trash` (durante il brainstorming non ha risposto al calcolo dimensioni, va chiarito se per permessi o per altro).

- [ ] **Step 6: Rimuovere il codice usa e getta e fare commit**

```bash
rm -rf spikes/fda-probe
git add docs/superpowers/spikes/
git commit -m "docs: record full disk access spike findings"
```

---

## Task 3: `ILinkInspector` e `DenyList`

**Files:**
- Create: `src/MjmCleaner.Core/Safety/ILinkInspector.cs`
- Create: `src/MjmCleaner.Core/Safety/FileSystemLinkInspector.cs`
- Create: `src/MjmCleaner.Core/Safety/DenyList.cs`
- Test: `tests/MjmCleaner.Core.Tests/Safety/DenyListTests.cs`

**Interfaces:**
- Consumes: niente
- Produces:
  - `bool ILinkInspector.IsSymbolicLink(string path)`
  - `DenyList(string homeDirectory)` con `bool IsDenied(string canonicalPath, out string reason)`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Safety/DenyListTests.cs`:

```csharp
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

public class DenyListTests
{
    private const string Home = "/Users/tester";
    private static DenyList Create() => new(Home);

    [Theory]
    [InlineData("/System/Library/Fonts")]
    [InlineData("/usr/bin")]
    [InlineData("/bin")]
    [InlineData("/Applications/Safari.app")]
    [InlineData("/Users/tester")]
    [InlineData("/Users/tester/Documents")]
    [InlineData("/Users/tester/Documents/fatture/2026")]
    [InlineData("/Users/tester/Desktop")]
    [InlineData("/Users/tester/Library/Application Support/qualcosa")]
    [InlineData("/Users/tester/Library/Mobile Documents")]
    [InlineData("/Users/tester/.ssh/id_rsa")]
    [InlineData("/Users/tester/Library/Containers/com.docker.docker/Data")]
    public void DeniesProtectedPaths(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/Library/Caches/com.apple.Safari")]
    [InlineData("/Users/tester/Library/Logs/qualcosa.log")]
    [InlineData("/Library/Caches/com.apple.qualcosa")]
    [InlineData("/Library/Logs/DiagnosticReports/report.crash")]
    [InlineData("/Users/tester/.nuget/packages/newtonsoft.json")]
    [InlineData("/Users/tester/projects/app/bin")]
    public void AllowsCleanablePaths(string path)
    {
        Assert.False(Create().IsDenied(path, out _));
    }

    [Theory]
    [InlineData("/Users/tester/documents/fatture")]
    [InlineData("/Users/TESTER/Documents")]
    [InlineData("/users/tester/.SSH/config")]
    public void DeniesRegardlessOfCase(string path)
    {
        Assert.True(Create().IsDenied(path, out _));
    }

    [Fact]
    public void DeniesLibraryButAllowsItsCachesAndLogs()
    {
        DenyList list = Create();
        Assert.True(list.IsDenied("/Library/Preferences", out _));
        Assert.False(list.IsDenied("/Library/Caches/x", out _));
        Assert.False(list.IsDenied("/Library/Logs/x", out _));
    }

    [Fact]
    public void ReasonExplainsWhichRuleMatched()
    {
        Create().IsDenied("/Users/tester/Documents/x", out string reason);
        Assert.Contains("Documents", reason);
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test --filter FullyQualifiedName~DenyListTests
```
Atteso: errore di compilazione, `DenyList` non esiste.

- [ ] **Step 3: Implementare `ILinkInspector` e `FileSystemLinkInspector`**

`src/MjmCleaner.Core/Safety/ILinkInspector.cs`:

```csharp
namespace MjmCleaner.Core.Safety;

/// <summary>Riconosce i collegamenti simbolici. Astratto per rendere deterministici i test del PathGuard.</summary>
public interface ILinkInspector
{
    bool IsSymbolicLink(string path);
}
```

`src/MjmCleaner.Core/Safety/FileSystemLinkInspector.cs`:

```csharp
using System.IO.Abstractions;

namespace MjmCleaner.Core.Safety;

public sealed class FileSystemLinkInspector(IFileSystem fileSystem) : ILinkInspector
{
    public bool IsSymbolicLink(string path)
    {
        try
        {
            if (fileSystem.Directory.Exists(path))
            {
                return fileSystem.DirectoryInfo.New(path).LinkTarget is not null;
            }

            return fileSystem.File.Exists(path)
                && fileSystem.FileInfo.New(path).LinkTarget is not null;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
```

- [ ] **Step 4: Implementare `DenyList`**

`src/MjmCleaner.Core/Safety/DenyList.cs`:

```csharp
namespace MjmCleaner.Core.Safety;

/// <summary>
/// Percorsi che non devono mai essere eliminati. Non configurabile dall'interfaccia:
/// è l'ultima linea di difesa, non una preferenza.
/// </summary>
public sealed class DenyList
{
    private const StringComparison Cmp = StringComparison.OrdinalIgnoreCase;

    private readonly string[] _denied;
    private readonly string[] _exceptions;
    private readonly string _home;

    public DenyList(string homeDirectory)
    {
        string home = homeDirectory.TrimEnd('/');
        _home = home;

        _denied =
        [
            "/System", "/usr", "/bin", "/sbin", "/etc", "/Applications", "/Library",
            $"{home}/Documents",
            $"{home}/Desktop",
            $"{home}/Pictures",
            $"{home}/Movies",
            $"{home}/Music",
            $"{home}/Library/Application Support",
            $"{home}/Library/Mobile Documents",
            $"{home}/Library/Keychains",
            $"{home}/.ssh",
            $"{home}/.gnupg",
            $"{home}/Library/Containers/com.docker.docker",
        ];

        _exceptions =
        [
            "/Library/Caches",
            "/Library/Logs",
        ];
    }

    /// <summary>Il percorso deve essere già canonicalizzato (vedi PathGuard).</summary>
    public bool IsDenied(string canonicalPath, out string reason)
    {
        string path = canonicalPath.TrimEnd('/');

        foreach (string allowed in _exceptions)
        {
            if (IsSameOrUnder(path, allowed))
            {
                reason = string.Empty;
                return false;
            }
        }

        // La home è protetta solo come blocco esatto: un confronto ricorsivo negherebbe
        // l'intero albero sotto la home, rendendo non pulibile ~/Library/Caches. I figli
        // diretti della home li protegge la regola 4 del PathGuard (Task 4).
        if (path.Equals(_home, Cmp))
        {
            reason = $"percorso protetto: {_home}";
            return true;
        }

        foreach (string denied in _denied)
        {
            if (IsSameOrUnder(path, denied))
            {
                reason = $"percorso protetto: {denied}";
                return true;
            }
        }

        reason = string.Empty;
        return false;
    }

    private static bool IsSameOrUnder(string path, string ancestor)
        => path.Equals(ancestor, Cmp)
           || path.StartsWith(ancestor + "/", Cmp);
}
```

- [ ] **Step 5: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~DenyListTests
```
Atteso: tutti i test passano. `/Library` è negato ma `/Library/Caches` no, perché le eccezioni si valutano prima.

- [ ] **Step 6: Commit**

```bash
git add src/MjmCleaner.Core/Safety tests/MjmCleaner.Core.Tests/Safety
git commit -m "feat: add deny list and symlink inspector abstraction"
```

---

## Task 4: `PathGuard` — le cinque regole

Il componente in cui un difetto non produce un errore visibile ma una perdita di dati. Va sviluppato in TDD e con i casi cattivi scritti per primi.

**Files:**
- Create: `src/MjmCleaner.Core/Safety/PathGuard.cs`
- Test: `tests/MjmCleaner.Core.Tests/Safety/PathGuardTests.cs`
- Test: `tests/MjmCleaner.Core.Tests/Safety/FakeLinkInspector.cs`

**Interfaces:**
- Consumes: `DenyList`, `ILinkInspector` (Task 3)
- Produces:
  - `GuardVerdict` con `bool IsAllowed` e `string Reason`
  - `IPathGuard.Validate(string candidatePath, string declaredRoot)` → `GuardVerdict`

- [ ] **Step 1: Scrivere il doppio di test per i collegamenti**

`tests/MjmCleaner.Core.Tests/Safety/FakeLinkInspector.cs`:

```csharp
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

internal sealed class FakeLinkInspector(params string[] links) : ILinkInspector
{
    private readonly HashSet<string> _links = new(links, StringComparer.OrdinalIgnoreCase);

    public bool IsSymbolicLink(string path) => _links.Contains(path.TrimEnd('/'));
}
```

- [ ] **Step 2: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Safety/PathGuardTests.cs`:

```csharp
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

public class PathGuardTests
{
    private const string Home = "/Users/tester";
    private const string CacheRoot = "/Users/tester/Library/Caches";

    private static PathGuard Create(params string[] symlinks)
        => new(new DenyList(Home), new FakeLinkInspector(symlinks), Home);

    [Fact]
    public void AllowsItemInsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/com.apple.Safari", CacheRoot);
        Assert.True(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesItemOutsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate("/Users/tester/projects/app/bin", CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("contenimento", verdict.Reason);
    }

    [Fact]
    public void DeniesTraversalEscapingDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/../../Documents/fatture", CacheRoot);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void CanonicalizesBeforeComparing()
    {
        GuardVerdict verdict = Create().Validate($"{CacheRoot}/./sub/../sub/file", CacheRoot);
        Assert.True(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesDeniedPathEvenWhenInsideDeclaredRoot()
    {
        GuardVerdict verdict = Create().Validate($"{Home}/Documents/x", Home);
        Assert.False(verdict.IsAllowed);
    }

    [Fact]
    public void DeniesHomeItself()
    {
        Assert.False(Create().Validate(Home, Home).IsAllowed);
    }

    [Fact]
    public void DeniesDirectChildOfHome()
    {
        GuardVerdict verdict = Create().Validate($"{Home}/Downloads", $"{Home}/Downloads");
        Assert.False(verdict.IsAllowed);
        Assert.Contains("profondità", verdict.Reason);
    }

    [Fact]
    public void AllowsGrandchildOfHome()
    {
        Assert.True(Create().Validate($"{Home}/Downloads/vecchio.dmg", $"{Home}/Downloads").IsAllowed);
    }

    [Fact]
    public void AllowsSymlinkItselfSoTheLinkCanBeRemoved()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        Assert.True(guard.Validate($"{CacheRoot}/collegamento", CacheRoot).IsAllowed);
    }

    [Fact]
    public void DeniesItemWhoseAncestorIsSymlink()
    {
        PathGuard guard = Create($"{CacheRoot}/collegamento");
        GuardVerdict verdict = guard.Validate($"{CacheRoot}/collegamento/vittima.txt", CacheRoot);
        Assert.False(verdict.IsAllowed);
        Assert.Contains("collegamento", verdict.Reason);
    }

    [Fact]
    public void DeniesRegardlessOfCase()
    {
        Assert.False(Create().Validate($"{Home}/documents/x", Home).IsAllowed);
    }

    [Fact]
    public void DeniesDockerContainer()
    {
        string docker = $"{Home}/Library/Containers/com.docker.docker/Data/vms";
        Assert.False(Create().Validate(docker, $"{Home}/Library/Containers").IsAllowed);
    }

    // I tre casi seguenti nascono dalla revisione del Task 3, che li aveva misurati
    // come passanti: la radice si riduceva a stringa vuota e sfuggiva a ogni confronto.
    [Theory]
    [InlineData("/")]
    [InlineData("//")]
    public void DeniesFilesystemRoot(string root)
    {
        Assert.False(Create().Validate(root, "/").IsAllowed);
    }

    [Fact]
    public void DeniesAnotherUsersHome()
    {
        Assert.False(Create().Validate("/Users/altro/Documents/fatture", "/Users").IsAllowed);
    }

    [Fact]
    public void DeniesExternalVolume()
    {
        Assert.False(Create().Validate("/Volumes/Backup/2026", "/Volumes").IsAllowed);
    }
}
```

- [ ] **Step 3: Eseguire i test e verificare che falliscano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test --filter FullyQualifiedName~PathGuardTests
```
Atteso: errore di compilazione, `PathGuard` e `GuardVerdict` non esistono.

- [ ] **Step 4: Implementare `PathGuard`**

`src/MjmCleaner.Core/Safety/PathGuard.cs`:

```csharp
namespace MjmCleaner.Core.Safety;

public sealed record GuardVerdict(bool IsAllowed, string Reason)
{
    public static GuardVerdict Allow() => new(true, string.Empty);
    public static GuardVerdict Deny(string reason) => new(false, reason);
}

public interface IPathGuard
{
    GuardVerdict Validate(string candidatePath, string declaredRoot);
}

/// <summary>
/// Ultima linea di difesa: invocato immediatamente prima di ogni eliminazione,
/// non solo quando si definiscono le regole.
/// </summary>
public sealed class PathGuard(DenyList denyList, ILinkInspector links, string homeDirectory)
    : IPathGuard
{
    private const StringComparison Cmp = StringComparison.OrdinalIgnoreCase;
    private readonly string _home = homeDirectory.TrimEnd('/');

    public GuardVerdict Validate(string candidatePath, string declaredRoot)
    {
        // 1. Canonicalizzazione: risolve "." e ".." prima di qualsiasi confronto.
        string path = Path.GetFullPath(candidatePath).TrimEnd('/');
        string root = Path.GetFullPath(declaredRoot).TrimEnd('/');

        // 2. Contenimento nella root dichiarata dalla regola che ha prodotto l'elemento.
        if (!path.StartsWith(root + "/", Cmp) && !path.Equals(root, Cmp))
        {
            return GuardVerdict.Deny($"violazione del contenimento: fuori da {root}");
        }

        // 3. Deny-list.
        if (denyList.IsDenied(path, out string reason))
        {
            return GuardVerdict.Deny(reason);
        }

        // 4. Profondità minima: mai la home, mai un suo figlio diretto.
        if (IsHomeOrDirectChild(path))
        {
            return GuardVerdict.Deny("profondità insufficiente: figlio diretto della home");
        }

        // 5. Collegamenti simbolici: l'elemento stesso può essere un link (si elimina
        //    il link), ma un antenato che sia un link romperebbe il contenimento.
        for (string? ancestor = Path.GetDirectoryName(path);
             ancestor is not null && ancestor.Length > root.Length;
             ancestor = Path.GetDirectoryName(ancestor))
        {
            if (links.IsSymbolicLink(ancestor))
            {
                return GuardVerdict.Deny($"antenato è un collegamento simbolico: {ancestor}");
            }
        }

        return GuardVerdict.Allow();
    }

    private bool IsHomeOrDirectChild(string path)
    {
        if (path.Equals(_home, Cmp))
        {
            return true;
        }

        if (!path.StartsWith(_home + "/", Cmp))
        {
            return false;
        }

        string relative = path[(_home.Length + 1)..];
        return !relative.Contains('/');
    }
}
```

- [ ] **Step 5: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~PathGuardTests
```
Atteso: tutti i test passano, compresi quelli di attraversamento e di collegamento simbolico.

- [ ] **Step 6: Commit**

```bash
git add src/MjmCleaner.Core/Safety tests/MjmCleaner.Core.Tests/Safety
git commit -m "feat: add PathGuard with containment, deny list and symlink rules"
```

---

## Task 5: Percorsi applicativi e preferenze

**Files:**
- Create: `src/MjmCleaner.Core/Settings/AppPaths.cs`
- Create: `src/MjmCleaner.Core/Settings/CleanerSettings.cs`
- Create: `src/MjmCleaner.Core/Settings/SettingsStore.cs`
- Test: `tests/MjmCleaner.Core.Tests/Settings/SettingsStoreTests.cs`

**Interfaces:**
- Consumes: niente
- Produces:
  - `AppPaths(string homeDirectory)` con `string SupportDirectory`, `string DatabaseFile`, `string SettingsFile`, `string LogsDirectory`
  - `CleanerSettings` (record con `ProjectRoots`, `LargeFileRoots`, `LargeFileThresholdBytes`, `DownloadsMinAgeDays`, `LogsMinAgeDays`, `NuGetMinAgeDays`, `SelectedCategoryIds`)
  - `ISettingsStore` con `CleanerSettings Load()` e `void Save(CleanerSettings settings)`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Settings/SettingsStoreTests.cs`:

```csharp
using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Tests.Settings;

public class SettingsStoreTests
{
    private const string Home = "/Users/tester";

    [Fact]
    public void LoadReturnsDefaultsWhenFileMissing()
    {
        MockFileSystem fs = new();
        SettingsStore store = new(fs, new AppPaths(Home));

        CleanerSettings settings = store.Load();

        Assert.Empty(settings.ProjectRoots);
        Assert.Equal(90, settings.DownloadsMinAgeDays);
        Assert.Equal(30, settings.LogsMinAgeDays);
        Assert.Equal(180, settings.NuGetMinAgeDays);
        Assert.Equal(500L * 1024 * 1024, settings.LargeFileThresholdBytes);
    }

    [Fact]
    public void SaveThenLoadRoundTrips()
    {
        MockFileSystem fs = new();
        SettingsStore store = new(fs, new AppPaths(Home));
        CleanerSettings original = new()
        {
            ProjectRoots = ["/Users/tester/projects"],
            DownloadsMinAgeDays = 30,
            SelectedCategoryIds = ["system-caches", "dev-caches"],
        };

        store.Save(original);
        CleanerSettings loaded = store.Load();

        Assert.Equal(["/Users/tester/projects"], loaded.ProjectRoots);
        Assert.Equal(30, loaded.DownloadsMinAgeDays);
        Assert.Equal(["system-caches", "dev-caches"], loaded.SelectedCategoryIds);
    }

    [Fact]
    public void LoadReturnsDefaultsWhenFileIsCorrupt()
    {
        MockFileSystem fs = new();
        AppPaths paths = new(Home);
        fs.AddFile(paths.SettingsFile, new MockFileData("{ questo non è json"));
        SettingsStore store = new(fs, paths);

        CleanerSettings settings = store.Load();

        Assert.Equal(90, settings.DownloadsMinAgeDays);
    }

    [Fact]
    public void AppPathsLiveUnderApplicationSupport()
    {
        AppPaths paths = new(Home);

        Assert.Equal("/Users/tester/Library/Application Support/mjm.cleaner", paths.SupportDirectory);
        Assert.EndsWith("history.db", paths.DatabaseFile);
        Assert.EndsWith("settings.json", paths.SettingsFile);
        Assert.EndsWith("logs", paths.LogsDirectory);
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
dotnet test --filter FullyQualifiedName~SettingsStoreTests
```
Atteso: errore di compilazione, i tipi non esistono.

- [ ] **Step 3: Implementare `AppPaths`**

`src/MjmCleaner.Core/Settings/AppPaths.cs`:

```csharp
namespace MjmCleaner.Core.Settings;

/// <summary>
/// I dati dell'applicazione vivono sotto Application Support, che la deny-list
/// protegge: l'applicazione non può eliminare il proprio storico.
/// </summary>
public sealed class AppPaths(string homeDirectory)
{
    public string SupportDirectory { get; } =
        Path.Combine(homeDirectory, "Library", "Application Support", "mjm.cleaner");

    public string DatabaseFile => Path.Combine(SupportDirectory, "history.db");
    public string SettingsFile => Path.Combine(SupportDirectory, "settings.json");
    public string LogsDirectory => Path.Combine(SupportDirectory, "logs");

    public static AppPaths ForCurrentUser()
        => new(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
}
```

- [ ] **Step 4: Implementare `CleanerSettings`**

`src/MjmCleaner.Core/Settings/CleanerSettings.cs`:

```csharp
namespace MjmCleaner.Core.Settings;

public sealed record CleanerSettings
{
    public IReadOnlyList<string> ProjectRoots { get; init; } = [];
    public IReadOnlyList<string> LargeFileRoots { get; init; } = [];
    public long LargeFileThresholdBytes { get; init; } = 500L * 1024 * 1024;
    public int DownloadsMinAgeDays { get; init; } = 90;
    public int LogsMinAgeDays { get; init; } = 30;
    public int NuGetMinAgeDays { get; init; } = 180;

    /// <summary>Selezione dell'ultimo utilizzo: riduce il costo dei quattro passi nella pulizia di routine.</summary>
    public IReadOnlyList<string> SelectedCategoryIds { get; init; } =
        ["system-caches", "dev-caches", "project-build-output", "logs"];
}
```

- [ ] **Step 5: Implementare `SettingsStore`**

`src/MjmCleaner.Core/Settings/SettingsStore.cs`:

```csharp
using System.IO.Abstractions;
using System.Text.Json;

namespace MjmCleaner.Core.Settings;

public interface ISettingsStore
{
    CleanerSettings Load();
    void Save(CleanerSettings settings);
}

public sealed class SettingsStore(IFileSystem fileSystem, AppPaths paths) : ISettingsStore
{
    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    /// <summary>Preferenze illeggibili o corrotte non devono impedire l'avvio: si torna ai valori predefiniti.</summary>
    public CleanerSettings Load()
    {
        try
        {
            if (!fileSystem.File.Exists(paths.SettingsFile))
            {
                return new CleanerSettings();
            }

            string json = fileSystem.File.ReadAllText(paths.SettingsFile);
            return JsonSerializer.Deserialize<CleanerSettings>(json, Options) ?? new CleanerSettings();
        }
        catch (Exception ex) when (ex is JsonException or IOException or UnauthorizedAccessException)
        {
            return new CleanerSettings();
        }
    }

    public void Save(CleanerSettings settings)
    {
        fileSystem.Directory.CreateDirectory(paths.SupportDirectory);
        fileSystem.File.WriteAllText(
            paths.SettingsFile,
            JsonSerializer.Serialize(settings, Options));
    }
}
```

- [ ] **Step 6: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~SettingsStoreTests
```
Atteso: tutti i test passano.

- [ ] **Step 7: Commit**

```bash
git add src/MjmCleaner.Core/Settings tests/MjmCleaner.Core.Tests/Settings
git commit -m "feat: add app paths and user settings store"
```

---

## Task 6: `PathExpander`

**Files:**
- Create: `src/MjmCleaner.Core/Categories/PathExpander.cs`
- Test: `tests/MjmCleaner.Core.Tests/Categories/PathExpanderTests.cs`

**Interfaces:**
- Consumes: niente
- Produces: `PathExpander(string homeDirectory, string tempDirectory)` con `string Expand(string path)`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Categories/PathExpanderTests.cs`:

```csharp
using MjmCleaner.Core.Categories;

namespace MjmCleaner.Core.Tests.Categories;

public class PathExpanderTests
{
    private static PathExpander Create()
        => new("/Users/tester", "/var/folders/ab/xyz/T/");

    [Fact]
    public void ExpandsTildePrefix()
        => Assert.Equal("/Users/tester/Library/Caches", Create().Expand("~/Library/Caches"));

    [Fact]
    public void ExpandsBareTilde()
        => Assert.Equal("/Users/tester", Create().Expand("~"));

    [Fact]
    public void ExpandsTmpdirVariable()
        => Assert.Equal("/var/folders/ab/xyz/T", Create().Expand("$TMPDIR"));

    [Fact]
    public void LeavesAbsolutePathUnchanged()
        => Assert.Equal("/Library/Caches", Create().Expand("/Library/Caches"));

    [Fact]
    public void TrimsTrailingSlash()
        => Assert.Equal("/Users/tester/Downloads", Create().Expand("~/Downloads/"));

    [Fact]
    public void DoesNotExpandTildeOfAnotherUser()
        => Assert.Equal("~altro/Documents", Create().Expand("~altro/Documents"));
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test --filter FullyQualifiedName~PathExpanderTests
```
Atteso: errore di compilazione, `PathExpander` non esiste.

- [ ] **Step 3: Implementare**

`src/MjmCleaner.Core/Categories/PathExpander.cs`:

```csharp
namespace MjmCleaner.Core.Categories;

/// <summary>Traduce i percorsi delle regole in percorsi assoluti.</summary>
public sealed class PathExpander(string homeDirectory, string tempDirectory)
{
    private readonly string _home = homeDirectory.TrimEnd('/');
    private readonly string _temp = tempDirectory.TrimEnd('/');

    public string Expand(string path)
    {
        string expanded = path switch
        {
            "~" => _home,
            "$TMPDIR" => _temp,
            _ when path.StartsWith("~/", StringComparison.Ordinal) => _home + path[1..],
            _ => path,
        };

        return expanded.Length > 1 ? expanded.TrimEnd('/') : expanded;
    }

    public static PathExpander ForCurrentUser()
        => new(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            Path.GetTempPath());
}
```

- [ ] **Step 4: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~PathExpanderTests
```
Atteso: tutti i test passano. `~altro` resta invariato perché non corrisponde né a `~` né al prefisso `~/`.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.Core/Categories tests/MjmCleaner.Core.Tests/Categories
git commit -m "feat: add path expander for ~ and \$TMPDIR"
```

---

## Task 7: Modello delle regole e catalogo delle categorie

**Files:**
- Create: `src/MjmCleaner.Core/Categories/CleanupRule.cs`
- Create: `src/MjmCleaner.Core/Categories/CleanupCategory.cs`
- Create: `src/MjmCleaner.Core/Categories/CategoryCatalog.cs`
- Test: `tests/MjmCleaner.Core.Tests/Categories/CategoryCatalogTests.cs`

**Interfaces:**
- Consumes: `PathExpander` (Task 6), `CleanerSettings` (Task 5)
- Produces:
  - `enum ScanMode { ClearContents, MatchingDirs, MatchingFiles }`
  - `enum RiskLevel { Low, Medium, High }`
  - `record CleanupRule(string Root, ScanMode Mode, string[] IncludeGlobs, string[] ExcludeGlobs, TimeSpan? MinAge, long? MinSizeBytes, int MaxDepth, bool RequiresProjectMarker)`
  - `record CleanupCategory(string Id, string DisplayName, string Description, RiskLevel Risk, bool SelectedByDefault, string? ParentId, IReadOnlyList<CleanupRule> Rules)`
  - `CategoryCatalog.Build(CleanerSettings settings, PathExpander expander)` → `IReadOnlyList<CleanupCategory>`

**Nota di progettazione:** i pacchetti NuGet sono una categoria a sé (`nuget-packages`) con `ParentId = "dev-caches"`. L'interfaccia la mostra annidata e deselezionata, come previsto dalla specifica; tenerla separata nel modello evita di introdurre un secondo livello di selezione dentro la singola categoria.

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Categories/CategoryCatalogTests.cs`:

```csharp
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Tests.Categories;

public class CategoryCatalogTests
{
    private static readonly PathExpander Expander = new("/Users/tester", "/var/folders/ab/T");

    private static IReadOnlyList<CleanupCategory> Build(CleanerSettings? settings = null)
        => CategoryCatalog.Build(settings ?? new CleanerSettings(), Expander);

    [Fact]
    public void DefinesTheSixCategories()
    {
        string[] ids = [.. Build().Select(c => c.Id)];

        Assert.Equal(
            ["system-caches", "dev-caches", "nuget-packages", "project-build-output", "logs", "trash-downloads-large"],
            ids);
    }

    [Fact]
    public void NuGetIsNestedUnderDevCachesAndNotSelectedByDefault()
    {
        CleanupCategory nuget = Build().Single(c => c.Id == "nuget-packages");

        Assert.Equal("dev-caches", nuget.ParentId);
        Assert.False(nuget.SelectedByDefault);
    }

    [Fact]
    public void HighRiskCategoryIsNeverSelectedByDefault()
    {
        CleanupCategory risky = Build().Single(c => c.Id == "trash-downloads-large");

        Assert.Equal(RiskLevel.High, risky.Risk);
        Assert.False(risky.SelectedByDefault);
    }

    [Fact]
    public void RuleRootsAreAlreadyExpanded()
    {
        CleanupCategory caches = Build().Single(c => c.Id == "system-caches");

        Assert.Contains(caches.Rules, r => r.Root == "/Users/tester/Library/Caches");
        Assert.Contains(caches.Rules, r => r.Root == "/Library/Caches");
        Assert.DoesNotContain(caches.Rules, r => r.Root.StartsWith('~'));
    }

    [Fact]
    public void ProjectBuildOutputHasOneRulePerConfiguredRoot()
    {
        CleanerSettings settings = new()
        {
            ProjectRoots = ["/Users/tester/projects", "/Users/tester/lavoro"],
        };

        CleanupCategory projects = Build(settings).Single(c => c.Id == "project-build-output");

        Assert.Equal(2, projects.Rules.Count);
        Assert.All(projects.Rules, r => Assert.True(r.RequiresProjectMarker));
        Assert.All(projects.Rules, r => Assert.Equal(ScanMode.MatchingDirs, r.Mode));
        Assert.All(projects.Rules, r => Assert.Equal(["bin", "obj"], r.IncludeGlobs));
    }

    [Fact]
    public void ProjectBuildOutputHasNoRulesWhenNoRootConfigured()
        => Assert.Empty(Build().Single(c => c.Id == "project-build-output").Rules);

    [Fact]
    public void AgeThresholdsComeFromSettings()
    {
        CleanerSettings settings = new() { LogsMinAgeDays = 7, DownloadsMinAgeDays = 45, NuGetMinAgeDays = 60 };
        IReadOnlyList<CleanupCategory> categories = Build(settings);

        CleanupRule logRule = categories.Single(c => c.Id == "logs").Rules[0];
        CleanupRule downloadsRule = categories
            .Single(c => c.Id == "trash-downloads-large").Rules
            .Single(r => r.Root == "/Users/tester/Downloads");
        CleanupRule nugetRule = categories.Single(c => c.Id == "nuget-packages").Rules[0];

        Assert.Equal(TimeSpan.FromDays(7), logRule.MinAge);
        Assert.Equal(TimeSpan.FromDays(45), downloadsRule.MinAge);
        Assert.Equal(TimeSpan.FromDays(60), nugetRule.MinAge);
    }

    [Fact]
    public void DockerIsNotReferencedByAnyRule()
    {
        Assert.DoesNotContain(
            Build().SelectMany(c => c.Rules),
            r => r.Root.Contains("docker", StringComparison.OrdinalIgnoreCase));
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
dotnet test --filter FullyQualifiedName~CategoryCatalogTests
```
Atteso: errore di compilazione, i tipi non esistono.

- [ ] **Step 3: Implementare i record**

`src/MjmCleaner.Core/Categories/CleanupRule.cs`:

```csharp
namespace MjmCleaner.Core.Categories;

public enum ScanMode
{
    /// <summary>Svuota il contenuto della root mantenendo la root stessa.</summary>
    ClearContents,

    /// <summary>Cerca ricorsivamente directory il cui nome corrisponde ai pattern.</summary>
    MatchingDirs,

    /// <summary>Cerca file per pattern, età e dimensione.</summary>
    MatchingFiles,
}

public enum RiskLevel { Low, Medium, High }

public sealed record CleanupRule(
    string Root,
    ScanMode Mode,
    string[] IncludeGlobs,
    string[] ExcludeGlobs,
    TimeSpan? MinAge = null,
    long? MinSizeBytes = null,
    int MaxDepth = int.MaxValue,
    bool RequiresProjectMarker = false);
```

`src/MjmCleaner.Core/Categories/CleanupCategory.cs`:

```csharp
namespace MjmCleaner.Core.Categories;

public sealed record CleanupCategory(
    string Id,
    string DisplayName,
    string Description,
    RiskLevel Risk,
    bool SelectedByDefault,
    string? ParentId,
    IReadOnlyList<CleanupRule> Rules);
```

- [ ] **Step 4: Implementare il catalogo**

`src/MjmCleaner.Core/Categories/CategoryCatalog.cs`:

```csharp
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Categories;

public static class CategoryCatalog
{
    private static readonly string[] All = ["*"];

    public static IReadOnlyList<CleanupCategory> Build(CleanerSettings settings, PathExpander expander)
    {
        string E(string path) => expander.Expand(path);

        return
        [
            new CleanupCategory(
                Id: "system-caches",
                DisplayName: "Cache utente e di sistema",
                Description: "Cache rigenerabili delle applicazioni e del sistema. Le app aperte potrebbero comportarsi in modo anomalo fino al riavvio.",
                Risk: RiskLevel.Medium,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/Library/Caches"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("/Library/Caches"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("$TMPDIR"), ScanMode.ClearContents, All, [], MinAge: TimeSpan.FromDays(1)),
                ]),

            new CleanupCategory(
                Id: "dev-caches",
                DisplayName: "Cache di sviluppo",
                Description: "Cache di npm, Xcode e Gradle. Tutto rigenerabile alla prossima compilazione.",
                Risk: RiskLevel.Low,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/.npm/_cacache"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/.cache"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/Library/Developer/Xcode/DerivedData"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/Library/Developer/Xcode/Archives"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/.gradle/caches"), ScanMode.ClearContents, All, []),
                ]),

            new CleanupCategory(
                Id: "nuget-packages",
                DisplayName: "Pacchetti NuGet inutilizzati",
                Description: "Svuotarla costa il ri-download di ogni pacchetto alla prossima compilazione e impedisce di compilare offline. L'età si basa sull'ultimo accesso: è un'euristica.",
                Risk: RiskLevel.Low,
                SelectedByDefault: false,
                ParentId: "dev-caches",
                Rules:
                [
                    new CleanupRule(
                        E("~/.nuget/packages"),
                        ScanMode.MatchingDirs,
                        All,
                        [],
                        MinAge: TimeSpan.FromDays(settings.NuGetMinAgeDays),
                        MaxDepth: 1),
                ]),

            new CleanupCategory(
                Id: "project-build-output",
                DisplayName: "Cartelle bin e obj nei progetti",
                Description: "Output di compilazione .NET. Una cartella viene proposta solo se accanto a essa c'è un file di progetto.",
                Risk: RiskLevel.Low,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    .. settings.ProjectRoots.Select(root => new CleanupRule(
                        E(root),
                        ScanMode.MatchingDirs,
                        ["bin", "obj"],
                        [],
                        RequiresProjectMarker: true)),
                ]),

            new CleanupCategory(
                Id: "logs",
                DisplayName: "Log e crash report",
                Description: "Diari di bordo di sistema e applicazioni.",
                Risk: RiskLevel.Low,
                SelectedByDefault: true,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/Library/Logs"), ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(settings.LogsMinAgeDays)),
                    new CleanupRule(E("/Library/Logs"), ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(settings.LogsMinAgeDays)),
                ]),

            new CleanupCategory(
                Id: "trash-downloads-large",
                DisplayName: "Cestino, Download e file grandi",
                Description: "Contiene dati reali, non file rigenerabili. Ogni voce va selezionata manualmente.",
                Risk: RiskLevel.High,
                SelectedByDefault: false,
                ParentId: null,
                Rules:
                [
                    new CleanupRule(E("~/.Trash"), ScanMode.ClearContents, All, []),
                    new CleanupRule(E("~/Downloads"), ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(settings.DownloadsMinAgeDays)),
                    .. settings.LargeFileRoots.Select(root => new CleanupRule(
                        E(root),
                        ScanMode.MatchingFiles,
                        All,
                        [],
                        MinSizeBytes: settings.LargeFileThresholdBytes)),
                ]),
        ];
    }
}
```

- [ ] **Step 5: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~CategoryCatalogTests
```
Atteso: tutti i test passano. In particolare `DockerIsNotReferencedByAnyRule`: Docker non compare in nessuna regola, e la deny-list lo blocca comunque.

- [ ] **Step 6: Commit**

```bash
git add src/MjmCleaner.Core/Categories tests/MjmCleaner.Core.Tests/Categories
git commit -m "feat: add cleanup rule model and category catalog"
```

---

## Task 8: Modelli di scansione e `RuleScanner` (ClearContents, MatchingFiles)

**Files:**
- Create: `src/MjmCleaner.Core/Scanning/ScanModels.cs`
- Create: `src/MjmCleaner.Core/Scanning/RuleScanner.cs`
- Test: `tests/MjmCleaner.Core.Tests/Scanning/TestTimeProvider.cs`
- Test: `tests/MjmCleaner.Core.Tests/Scanning/RuleScannerTests.cs`

**Interfaces:**
- Consumes: `CleanupRule` (Task 7), `IPathGuard` (Task 4), `ILinkInspector` (Task 3)
- Produces:
  - `record ScanItem(string Path, long SizeBytes, bool IsDirectory, string DeclaredRoot)`
  - `enum ScanErrorKind { AccessDenied, InUse, NotFound, NotEmpty, Other }`
  - `record ScanError(string Path, ScanErrorKind Kind, string Message)`
  - `record GuardExclusion(string Path, string Reason)`
  - `record RuleScanOutcome(IReadOnlyList<ScanItem> Items, IReadOnlyList<ScanError> Errors, IReadOnlyList<GuardExclusion> Exclusions)`
  - `record CategoryScanResult(string CategoryId, IReadOnlyList<ScanItem> Items, long TotalBytes, IReadOnlyList<ScanError> Errors, IReadOnlyList<GuardExclusion> Exclusions)`
  - `record ScanProgress(string CategoryId, string CurrentPath, int ItemsFound, long BytesFound)`
  - `RuleScanner(IFileSystem, IPathGuard, ILinkInspector, TimeProvider)` con `RuleScanOutcome Scan(CleanupRule rule, CancellationToken ct)`

- [ ] **Step 1: Scrivere il doppio di test per il tempo**

`tests/MjmCleaner.Core.Tests/Scanning/TestTimeProvider.cs`:

```csharp
namespace MjmCleaner.Core.Tests.Scanning;

internal sealed class TestTimeProvider(DateTimeOffset now) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => now;
}
```

- [ ] **Step 2: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Scanning/RuleScannerTests.cs`:

```csharp
using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;

namespace MjmCleaner.Core.Tests.Scanning;

public class RuleScannerTests
{
    private const string Home = "/Users/tester";
    private const string CacheRoot = "/Users/tester/Library/Caches";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);
    private static readonly string[] All = ["*"];

    private static RuleScanner Create(MockFileSystem fs, params string[] symlinks)
    {
        FakeLinkInspector links = new(symlinks);
        return new RuleScanner(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));
    }

    private static MockFileData File(long size, DateTime? written = null)
    {
        MockFileData data = new(new byte[size]);
        DateTime stamp = written ?? Now.UtcDateTime;
        data.LastWriteTime = stamp;
        data.LastAccessTime = stamp;
        return data;
    }

    [Fact]
    public void ReturnsNothingWhenRootDoesNotExist()
    {
        MockFileSystem fs = new();
        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule("/Users/tester/Library/Developer/Xcode/DerivedData", ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
        Assert.Empty(outcome.Errors);
    }

    [Fact]
    public void ClearContentsListsDirectChildrenNotTheRoot()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/app1/dati.bin", File(100));
        fs.AddFile($"{CacheRoot}/solo.tmp", File(50));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Equal(2, outcome.Items.Count);
        Assert.DoesNotContain(outcome.Items, i => i.Path == CacheRoot);
        Assert.Contains(outcome.Items, i => i.Path == $"{CacheRoot}/app1" && i.IsDirectory && i.SizeBytes == 100);
        Assert.Contains(outcome.Items, i => i.Path == $"{CacheRoot}/solo.tmp" && !i.IsDirectory && i.SizeBytes == 50);
    }

    [Fact]
    public void DirectorySizeIsSummedRecursively()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/app/a/1.bin", File(100));
        fs.AddFile($"{CacheRoot}/app/b/2.bin", File(250));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Equal(350, outcome.Items.Single().SizeBytes);
    }

    [Fact]
    public void ItemsCarryTheDeclaredRoot()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/x.tmp", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Equal(CacheRoot, outcome.Items.Single().DeclaredRoot);
    }

    [Fact]
    public void GuardRejectionBecomesExclusionNotItem()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Documents/riservato.pdf", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(Home, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
        Assert.NotEmpty(outcome.Exclusions);
    }

    [Fact]
    public void SymlinkIsListedButItsTargetIsNotTraversed()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/collegamento/dentro.bin", File(9999));

        RuleScanOutcome outcome = Create(fs, $"{CacheRoot}/collegamento").Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        ScanItem item = outcome.Items.Single();
        Assert.Equal($"{CacheRoot}/collegamento", item.Path);
        Assert.Equal(0, item.SizeBytes);
    }

    [Fact]
    public void MatchingFilesHonoursMinAge()
    {
        MockFileSystem fs = new();
        string logs = $"{Home}/Library/Logs";
        fs.AddFile($"{logs}/vecchio.log", File(10, Now.UtcDateTime.AddDays(-60)));
        fs.AddFile($"{logs}/recente.log", File(10, Now.UtcDateTime.AddDays(-2)));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(logs, ScanMode.MatchingFiles, All, [], MinAge: TimeSpan.FromDays(30)),
            CancellationToken.None);

        Assert.Equal($"{logs}/vecchio.log", outcome.Items.Single().Path);
    }

    [Fact]
    public void MatchingFilesHonoursGlobsAndExclusions()
    {
        MockFileSystem fs = new();
        string logs = $"{Home}/Library/Logs";
        fs.AddFile($"{logs}/a.log", File(10));
        fs.AddFile($"{logs}/b.txt", File(10));
        fs.AddFile($"{logs}/importante.log", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(logs, ScanMode.MatchingFiles, ["*.log"], ["importante.*"]),
            CancellationToken.None);

        Assert.Equal($"{logs}/a.log", outcome.Items.Single().Path);
    }

    [Fact]
    public void MatchingFilesHonoursMinSize()
    {
        MockFileSystem fs = new();
        string downloads = $"{Home}/Downloads";
        fs.AddFile($"{downloads}/grande.dmg", File(2000));
        fs.AddFile($"{downloads}/piccolo.txt", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(downloads, ScanMode.MatchingFiles, All, [], MinSizeBytes: 1000),
            CancellationToken.None);

        Assert.Equal($"{downloads}/grande.dmg", outcome.Items.Single().Path);
    }

    [Fact]
    public void CancellationStopsTheScan()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/a.tmp", File(10));
        using CancellationTokenSource cts = new();
        cts.Cancel();

        Assert.Throws<OperationCanceledException>(() =>
            Create(fs).Scan(new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []), cts.Token));
    }
}
```

- [ ] **Step 3: Eseguire i test e verificare che falliscano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test --filter FullyQualifiedName~RuleScannerTests
```
Atteso: errore di compilazione, i tipi di scansione non esistono.

- [ ] **Step 4: Implementare i modelli**

`src/MjmCleaner.Core/Scanning/ScanModels.cs`:

```csharp
namespace MjmCleaner.Core.Scanning;

/// <summary>Un elemento eliminabile. <paramref name="DeclaredRoot"/> serve al PathGuard per il contenimento.</summary>
public sealed record ScanItem(string Path, long SizeBytes, bool IsDirectory, string DeclaredRoot);

public enum ScanErrorKind { AccessDenied, InUse, NotFound, NotEmpty, Other }

public sealed record ScanError(string Path, ScanErrorKind Kind, string Message);

public sealed record GuardExclusion(string Path, string Reason);

public sealed record RuleScanOutcome(
    IReadOnlyList<ScanItem> Items,
    IReadOnlyList<ScanError> Errors,
    IReadOnlyList<GuardExclusion> Exclusions);

public sealed record CategoryScanResult(
    string CategoryId,
    IReadOnlyList<ScanItem> Items,
    long TotalBytes,
    IReadOnlyList<ScanError> Errors,
    IReadOnlyList<GuardExclusion> Exclusions);

public sealed record ScanProgress(string CategoryId, string CurrentPath, int ItemsFound, long BytesFound);
```

- [ ] **Step 5: Implementare `RuleScanner`**

`src/MjmCleaner.Core/Scanning/RuleScanner.cs`:

```csharp
using System.IO.Abstractions;
using System.IO.Enumeration;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Scanning;

/// <summary>Interpreta una singola regola. Non segue mai i collegamenti simbolici.</summary>
public sealed class RuleScanner(
    IFileSystem fileSystem,
    IPathGuard guard,
    ILinkInspector links,
    TimeProvider clock)
{
    public RuleScanOutcome Scan(CleanupRule rule, CancellationToken ct)
    {
        List<ScanItem> items = [];
        List<ScanError> errors = [];
        List<GuardExclusion> exclusions = [];

        // Root assente: categoria vuota, non errore.
        if (!fileSystem.Directory.Exists(rule.Root))
        {
            return new RuleScanOutcome(items, errors, exclusions);
        }

        // La root si valida una volta sola, e la validazione risale fino alla radice del
        // filesystem: se la root stessa o un suo antenato è un collegamento simbolico,
        // ogni elemento trovato sotto di essa punterebbe altrove. È il caso di chi sposta
        // ~/Library/Caches su un disco esterno con un collegamento.
        GuardVerdict rootVerdict = guard.ValidateRoot(rule.Root);
        if (!rootVerdict.IsAllowed)
        {
            exclusions.Add(new GuardExclusion(rule.Root, rootVerdict.Reason));
            return new RuleScanOutcome(items, errors, exclusions);
        }

        switch (rule.Mode)
        {
            case ScanMode.ClearContents:
                ScanContents(rule, items, errors, exclusions, ct);
                break;
            case ScanMode.MatchingFiles:
                ScanFiles(rule, rule.Root, depth: 0, items, errors, exclusions, ct);
                break;
            case ScanMode.MatchingDirs:
                throw new NotSupportedException("MatchingDirs viene implementato nel Task 9.");
            default:
                throw new ArgumentOutOfRangeException(nameof(rule));
        }

        return new RuleScanOutcome(items, errors, exclusions);
    }

    private void ScanContents(
        CleanupRule rule,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        foreach (string entry in Enumerate(rule.Root, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (!Accept(entry, rule, isDirectoryCandidate: true, errors))
            {
                continue;
            }

            GuardVerdict verdict = guard.Validate(entry, rule.Root);
            if (!verdict.IsAllowed)
            {
                exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                continue;
            }

            bool isLink = links.IsSymbolicLink(entry);
            bool isDirectory = !isLink && fileSystem.Directory.Exists(entry);
            long size = isLink ? 0 : isDirectory ? DirectorySize(entry, errors, ct) : FileSize(entry, errors);

            items.Add(new ScanItem(entry, size, isDirectory, rule.Root));
        }
    }

    private void ScanFiles(
        CleanupRule rule,
        string directory,
        int depth,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        if (depth > rule.MaxDepth)
        {
            return;
        }

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry))
            {
                continue;
            }

            if (fileSystem.Directory.Exists(entry))
            {
                ScanFiles(rule, entry, depth + 1, items, errors, exclusions, ct);
                continue;
            }

            string name = fileSystem.Path.GetFileName(entry);
            if (!MatchesGlobs(name, rule) || !Accept(entry, rule, isDirectoryCandidate: false, errors))
            {
                continue;
            }

            long size = FileSize(entry, errors);
            if (rule.MinSizeBytes is { } minSize && size < minSize)
            {
                continue;
            }

            GuardVerdict verdict = guard.Validate(entry, rule.Root);
            if (!verdict.IsAllowed)
            {
                exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                continue;
            }

            items.Add(new ScanItem(entry, size, false, rule.Root));
        }
    }

    /// <summary>Applica il filtro di età. Per le directory si usa il timestamp più recente fra accesso e scrittura.</summary>
    private bool Accept(string path, CleanupRule rule, bool isDirectoryCandidate, List<ScanError> errors)
    {
        if (rule.MinAge is not { } minAge)
        {
            return true;
        }

        try
        {
            IFileSystemInfo info = isDirectoryCandidate && fileSystem.Directory.Exists(path)
                ? fileSystem.DirectoryInfo.New(path)
                : fileSystem.FileInfo.New(path);

            DateTime stamp = info.LastAccessTimeUtc > info.LastWriteTimeUtc
                ? info.LastAccessTimeUtc
                : info.LastWriteTimeUtc;

            return clock.GetUtcNow().UtcDateTime - stamp >= minAge;
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return false;
        }
    }

    private static bool MatchesGlobs(string name, CleanupRule rule)
    {
        foreach (string excluded in rule.ExcludeGlobs)
        {
            if (FileSystemName.MatchesSimpleExpression(excluded, name, ignoreCase: true))
            {
                return false;
            }
        }

        foreach (string included in rule.IncludeGlobs)
        {
            if (FileSystemName.MatchesSimpleExpression(included, name, ignoreCase: true))
            {
                return true;
            }
        }

        return false;
    }

    private IEnumerable<string> Enumerate(string directory, List<ScanError> errors)
    {
        try
        {
            return fileSystem.Directory.EnumerateFileSystemEntries(directory);
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(directory, ex));
            return [];
        }
    }

    private long DirectorySize(string directory, List<ScanError> errors, CancellationToken ct)
    {
        long total = 0;

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry))
            {
                continue;
            }

            total += fileSystem.Directory.Exists(entry)
                ? DirectorySize(entry, errors, ct)
                : FileSize(entry, errors);
        }

        return total;
    }

    private long FileSize(string path, List<ScanError> errors)
    {
        try
        {
            return fileSystem.FileInfo.New(path).Length;
        }
        catch (Exception ex) when (IsExpected(ex))
        {
            errors.Add(Describe(path, ex));
            return 0;
        }
    }

    internal static bool IsExpected(Exception ex)
        => ex is UnauthorizedAccessException or IOException;

    internal static ScanError Describe(string path, Exception ex) => ex switch
    {
        UnauthorizedAccessException => new ScanError(path, ScanErrorKind.AccessDenied, ex.Message),
        FileNotFoundException or DirectoryNotFoundException => new ScanError(path, ScanErrorKind.NotFound, ex.Message),
        IOException io when io.Message.Contains("not empty", StringComparison.OrdinalIgnoreCase)
            => new ScanError(path, ScanErrorKind.NotEmpty, io.Message),
        IOException => new ScanError(path, ScanErrorKind.InUse, ex.Message),
        _ => new ScanError(path, ScanErrorKind.Other, ex.Message),
    };
}
```

- [ ] **Step 6: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~RuleScannerTests
```
Atteso: tutti i test passano. Se `MockFileSystem` non applica `LastAccessTime` come impostato, correggere l'helper `File(...)` del test impostando il timestamp dopo `AddFile` tramite `fs.FileInfo.New(path).LastAccessTime = ...`; la logica di produzione non va modificata.

- [ ] **Step 7: Commit**

```bash
git add src/MjmCleaner.Core/Scanning tests/MjmCleaner.Core.Tests/Scanning
git commit -m "feat: add rule scanner for clear-contents and matching-files modes"
```

---

## Task 9: `RuleScanner` — modalità MatchingDirs con marcatore di progetto

Senza il vincolo del marcatore, una root configurata male porterebbe a proporre l'eliminazione di `/usr/bin`. È il motivo per cui questa modalità ha un task dedicato.

**Files:**
- Modify: `src/MjmCleaner.Core/Scanning/RuleScanner.cs`
- Test: `tests/MjmCleaner.Core.Tests/Scanning/MatchingDirsTests.cs`

**Interfaces:**
- Consumes: tutto il Task 8
- Produces: `ScanMode.MatchingDirs` funzionante; nessuna nuova firma pubblica

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Scanning/MatchingDirsTests.cs`:

```csharp
using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;

namespace MjmCleaner.Core.Tests.Scanning;

public class MatchingDirsTests
{
    private const string Home = "/Users/tester";
    private const string Projects = "/Users/tester/projects";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);

    private static RuleScanner Create(MockFileSystem fs, params string[] symlinks)
    {
        FakeLinkInspector links = new(symlinks);
        return new RuleScanner(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));
    }

    private static CleanupRule BinObjRule(string root = Projects)
        => new(root, ScanMode.MatchingDirs, ["bin", "obj"], [], RequiresProjectMarker: true);

    [Fact]
    public void FindsBinAndObjNextToProjectFile()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/app.csproj", new MockFileData("<Project/>"));
        fs.AddFile($"{Projects}/app/bin/Debug/app.dll", new MockFileData(new byte[500]));
        fs.AddFile($"{Projects}/app/obj/project.assets.json", new MockFileData(new byte[100]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Equal(2, outcome.Items.Count);
        Assert.Contains(outcome.Items, i => i.Path == $"{Projects}/app/bin" && i.SizeBytes == 500);
        Assert.Contains(outcome.Items, i => i.Path == $"{Projects}/app/obj" && i.SizeBytes == 100);
    }

    [Fact]
    public void SkipsBinWithoutProjectFileAlongside()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/strumenti/bin/attrezzo", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Empty(outcome.Items);
    }

    [Fact]
    public void RecognisesEveryProjectFileExtension()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/a/a.fsproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/a/bin/x", new MockFileData(new byte[1]));
        fs.AddFile($"{Projects}/b/b.sln", new MockFileData("x"));
        fs.AddFile($"{Projects}/b/bin/x", new MockFileData(new byte[1]));
        fs.AddFile($"{Projects}/c/c.vbproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/c/bin/x", new MockFileData(new byte[1]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Equal(3, outcome.Items.Count);
    }

    [Fact]
    public void DoesNotDescendIntoAFoundDirectory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/app.csproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/app/bin/annidato/bin/x.dll", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Equal($"{Projects}/app/bin", outcome.Items.Single().Path);
    }

    [Fact]
    public void WithoutMarkerRequirementFindsDirectoriesByName()
    {
        MockFileSystem fs = new();
        string nuget = $"{Home}/.nuget/packages";
        fs.AddFile($"{nuget}/newtonsoft.json/13.0.3/pacchetto.nupkg", new MockFileData(new byte[42]));

        CleanupRule rule = new(nuget, ScanMode.MatchingDirs, ["*"], [], MaxDepth: 1);
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Equal($"{nuget}/newtonsoft.json", outcome.Items.Single().Path);
    }

    [Fact]
    public void HonoursMaxDepth()
    {
        MockFileSystem fs = new();
        string nuget = $"{Home}/.nuget/packages";
        fs.AddFile($"{nuget}/pacchetto/1.0.0/dentro/file.bin", new MockFileData(new byte[5]));

        CleanupRule rule = new(nuget, ScanMode.MatchingDirs, ["*"], [], MaxDepth: 1);
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Single(outcome.Items);
        Assert.Equal($"{nuget}/pacchetto", outcome.Items.Single().Path);
    }

    [Fact]
    public void DoesNotFollowSymlinkedDirectories()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/collegamento/app.csproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/collegamento/bin/x.dll", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs, $"{Projects}/collegamento").Scan(BinObjRule(), CancellationToken.None);

        Assert.Empty(outcome.Items);
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
dotnet test --filter FullyQualifiedName~MatchingDirsTests
```
Atteso: `NotSupportedException` con il messaggio del Task 8.

- [ ] **Step 3: Sostituire il ramo non supportato**

In `src/MjmCleaner.Core/Scanning/RuleScanner.cs`, sostituire:

```csharp
            case ScanMode.MatchingDirs:
                throw new NotSupportedException("MatchingDirs viene implementato nel Task 9.");
```

con:

```csharp
            case ScanMode.MatchingDirs:
                ScanDirectories(rule, rule.Root, depth: 1, items, errors, exclusions, ct);
                break;
```

- [ ] **Step 4: Aggiungere i metodi `ScanDirectories` e `HasProjectMarker`**

Inserire in `RuleScanner`, dopo `ScanFiles`:

```csharp
    private static readonly string[] ProjectMarkers =
        ["*.csproj", "*.fsproj", "*.vbproj", "*.sln", "*.slnx"];

    private void ScanDirectories(
        CleanupRule rule,
        string directory,
        int depth,
        List<ScanItem> items,
        List<ScanError> errors,
        List<GuardExclusion> exclusions,
        CancellationToken ct)
    {
        if (depth > rule.MaxDepth)
        {
            return;
        }

        foreach (string entry in Enumerate(directory, errors))
        {
            ct.ThrowIfCancellationRequested();

            if (links.IsSymbolicLink(entry) || !fileSystem.Directory.Exists(entry))
            {
                continue;
            }

            string name = fileSystem.Path.GetFileName(entry);
            bool matches = MatchesGlobs(name, rule)
                           && (!rule.RequiresProjectMarker || HasProjectMarker(directory, errors))
                           && Accept(entry, rule, isDirectoryCandidate: true, errors);

            if (matches)
            {
                GuardVerdict verdict = guard.Validate(entry, rule.Root);
                if (!verdict.IsAllowed)
                {
                    exclusions.Add(new GuardExclusion(entry, verdict.Reason));
                    continue;
                }

                items.Add(new ScanItem(entry, DirectorySize(entry, errors, ct), true, rule.Root));

                // Trovata: non si scende oltre, l'intera cartella verrà eliminata.
                continue;
            }

            ScanDirectories(rule, entry, depth + 1, items, errors, exclusions, ct);
        }
    }

    /// <summary>
    /// Vera se la directory che contiene il candidato ospita un file di progetto.
    /// Senza questo vincolo una root mal configurata proporrebbe l'eliminazione di /usr/bin.
    /// </summary>
    private bool HasProjectMarker(string parentDirectory, List<ScanError> errors)
    {
        foreach (string sibling in Enumerate(parentDirectory, errors))
        {
            string name = fileSystem.Path.GetFileName(sibling);

            foreach (string marker in ProjectMarkers)
            {
                if (FileSystemName.MatchesSimpleExpression(marker, name, ignoreCase: true))
                {
                    return true;
                }
            }
        }

        return false;
    }
```

- [ ] **Step 5: Eseguire tutti i test**

```bash
dotnet test
```
Atteso: tutti i test passano, compresi quelli del Task 8.

- [ ] **Step 6: Commit**

```bash
git add src/MjmCleaner.Core/Scanning tests/MjmCleaner.Core.Tests/Scanning
git commit -m "feat: add matching-dirs scan mode with project marker requirement"
```

---

## Task 10: `ScanEngine` — orchestrazione parallela

**Files:**
- Create: `src/MjmCleaner.Core/Scanning/ScanEngine.cs`
- Test: `tests/MjmCleaner.Core.Tests/Scanning/ScanEngineTests.cs`

**Interfaces:**
- Consumes: `RuleScanner` (Task 8-9), `CleanupCategory` (Task 7)
- Produces: `IScanEngine.ScanAsync(IReadOnlyList<CleanupCategory> categories, IProgress<ScanProgress>? progress, CancellationToken ct)` → `Task<IReadOnlyList<CategoryScanResult>>`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Scanning/ScanEngineTests.cs`:

```csharp
using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;

namespace MjmCleaner.Core.Tests.Scanning;

public class ScanEngineTests
{
    private const string Home = "/Users/tester";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);
    private static readonly string[] All = ["*"];

    private static ScanEngine Create(MockFileSystem fs)
    {
        FakeLinkInspector links = new();
        RuleScanner scanner = new(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));
        return new ScanEngine(scanner);
    }

    private static CleanupCategory Category(string id, params CleanupRule[] rules)
        => new(id, id, string.Empty, RiskLevel.Low, true, null, rules);

    [Fact]
    public async Task AggregatesBytesPerCategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[100]));
        fs.AddFile($"{Home}/Library/Caches/b.tmp", new MockFileData(new byte[50]));

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [Category("caches", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []))],
            progress: null,
            CancellationToken.None);

        CategoryScanResult result = results.Single();
        Assert.Equal("caches", result.CategoryId);
        Assert.Equal(150, result.TotalBytes);
        Assert.Equal(2, result.Items.Count);
    }

    [Fact]
    public async Task MergesItemsFromAllRulesOfACategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        fs.AddFile($"{Home}/.cache/b.tmp", new MockFileData(new byte[20]));

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [Category(
                "misto",
                new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []),
                new CleanupRule($"{Home}/.cache", ScanMode.ClearContents, All, []))],
            progress: null,
            CancellationToken.None);

        Assert.Equal(30, results.Single().TotalBytes);
    }

    [Fact]
    public async Task ReturnsOneResultPerCategoryInInputOrder()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        fs.AddFile($"{Home}/.cache/b.tmp", new MockFileData(new byte[10]));

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [
                Category("uno", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, [])),
                Category("due", new CleanupRule($"{Home}/.cache", ScanMode.ClearContents, All, [])),
            ],
            progress: null,
            CancellationToken.None);

        Assert.Equal(["uno", "due"], results.Select(r => r.CategoryId));
    }

    [Fact]
    public async Task ReportsProgressForEachCategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        List<ScanProgress> reported = [];

        await Create(fs).ScanAsync(
            [Category("caches", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []))],
            new Progress<ScanProgress>(p => { lock (reported) { reported.Add(p); } }),
            CancellationToken.None);

        await Task.Delay(50); // Progress<T> consegna sul contesto di sincronizzazione
        Assert.Contains(reported, p => p.CategoryId == "caches");
    }

    [Fact]
    public async Task CancellationPropagates()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Library/Caches/a.tmp", new MockFileData(new byte[10]));
        using CancellationTokenSource cts = new();
        await cts.CancelAsync();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            Create(fs).ScanAsync(
                [Category("caches", new CleanupRule($"{Home}/Library/Caches", ScanMode.ClearContents, All, []))],
                progress: null,
                cts.Token));
    }

    [Fact]
    public async Task CategoryWithoutRulesYieldsEmptyResult()
    {
        MockFileSystem fs = new();

        IReadOnlyList<CategoryScanResult> results = await Create(fs).ScanAsync(
            [Category("vuota")],
            progress: null,
            CancellationToken.None);

        Assert.Equal(0, results.Single().TotalBytes);
        Assert.Empty(results.Single().Items);
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test --filter FullyQualifiedName~ScanEngineTests
```
Atteso: errore di compilazione, `ScanEngine` non esiste.

- [ ] **Step 3: Implementare**

`src/MjmCleaner.Core/Scanning/ScanEngine.cs`:

```csharp
using MjmCleaner.Core.Categories;

namespace MjmCleaner.Core.Scanning;

public interface IScanEngine
{
    Task<IReadOnlyList<CategoryScanResult>> ScanAsync(
        IReadOnlyList<CleanupCategory> categories,
        IProgress<ScanProgress>? progress,
        CancellationToken ct);
}

/// <summary>
/// Scansiona le categorie in parallelo: attraversare ~/Library/Caches significa
/// centinaia di migliaia di file e l'interfaccia deve restare reattiva.
/// </summary>
public sealed class ScanEngine(RuleScanner scanner) : IScanEngine
{
    public async Task<IReadOnlyList<CategoryScanResult>> ScanAsync(
        IReadOnlyList<CleanupCategory> categories,
        IProgress<ScanProgress>? progress,
        CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();

        CategoryScanResult[] results = await Task.WhenAll(
            categories.Select(category => Task.Run(() => ScanCategory(category, progress, ct), ct)));

        return results;
    }

    private CategoryScanResult ScanCategory(
        CleanupCategory category,
        IProgress<ScanProgress>? progress,
        CancellationToken ct)
    {
        List<ScanItem> items = [];
        List<ScanError> errors = [];
        List<GuardExclusion> exclusions = [];

        foreach (CleanupRule rule in category.Rules)
        {
            ct.ThrowIfCancellationRequested();

            RuleScanOutcome outcome = scanner.Scan(rule, ct);
            items.AddRange(outcome.Items);
            errors.AddRange(outcome.Errors);
            exclusions.AddRange(outcome.Exclusions);

            progress?.Report(new ScanProgress(
                category.Id,
                rule.Root,
                items.Count,
                items.Sum(i => i.SizeBytes)));
        }

        long total = items.Sum(i => i.SizeBytes);

        progress?.Report(new ScanProgress(category.Id, string.Empty, items.Count, total));

        return new CategoryScanResult(category.Id, items, total, errors, exclusions);
    }
}
```

- [ ] **Step 4: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~ScanEngineTests
```
Atteso: tutti i test passano. `Task.WhenAll` preserva l'ordine dell'input, quindi il test sull'ordine passa anche con esecuzione parallela.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.Core/Scanning tests/MjmCleaner.Core.Tests/Scanning
git commit -m "feat: add parallel scan engine with progress reporting"
```

---

## Task 11: `CleanEngine` — eliminazione

**Files:**
- Create: `src/MjmCleaner.Core/Cleaning/CleanModels.cs`
- Create: `src/MjmCleaner.Core/Cleaning/CleanEngine.cs`
- Test: `tests/MjmCleaner.Core.Tests/Cleaning/CleanEngineTests.cs`

**Interfaces:**
- Consumes: `ScanItem`, `ScanError` (Task 8), `IPathGuard` (Task 4)
- Produces:
  - `record CategorySelection(string CategoryId, IReadOnlyList<ScanItem> Items)`
  - `record CategoryCleanResult(string CategoryId, long BytesFreed, int ItemsDeleted)`
  - `record CleanProgress(string CurrentPath, int ItemsDone, int ItemsTotal, long BytesFreed)`
  - `record CleanReport(DateTimeOffset StartedAtUtc, TimeSpan Duration, long BytesFreed, int ItemsDeleted, int ItemsFailed, IReadOnlyList<CategoryCleanResult> Categories, IReadOnlyList<ScanError> Errors, IReadOnlyList<string> DeletedPaths)`
  - `ICleanEngine.CleanAsync(IReadOnlyList<CategorySelection>, IProgress<CleanProgress>?, CancellationToken)` → `Task<CleanReport>`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Cleaning/CleanEngineTests.cs`:

```csharp
using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Tests.Safety;
using MjmCleaner.Core.Tests.Scanning;

namespace MjmCleaner.Core.Tests.Cleaning;

public class CleanEngineTests
{
    private const string Home = "/Users/tester";
    private const string CacheRoot = "/Users/tester/Library/Caches";
    private static readonly DateTimeOffset Now = new(2026, 9, 15, 12, 0, 0, TimeSpan.Zero);

    private static CleanEngine Create(MockFileSystem fs, params string[] symlinks)
    {
        FakeLinkInspector links = new(symlinks);
        return new CleanEngine(fs, new PathGuard(new DenyList(Home), links, Home), new TestTimeProvider(Now));
    }

    private static CategorySelection Selection(string id, params ScanItem[] items) => new(id, items);

    [Fact]
    public async Task DeletesFilesAndCountsBytes()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/a.tmp", new MockFileData(new byte[100]));

        CleanReport report = await Create(fs).CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/a.tmp", 100, false, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.False(fs.File.Exists($"{CacheRoot}/a.tmp"));
        Assert.Equal(100, report.BytesFreed);
        Assert.Equal(1, report.ItemsDeleted);
        Assert.Equal(0, report.ItemsFailed);
    }

    [Fact]
    public async Task DeletesDirectoriesRecursively()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/app/dentro/x.bin", new MockFileData(new byte[40]));

        CleanReport report = await Create(fs).CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/app", 40, true, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.False(fs.Directory.Exists($"{CacheRoot}/app"));
        Assert.Equal(40, report.BytesFreed);
    }

    [Fact]
    public async Task GuardRejectionPreventsDeletion()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Documents/riservato.pdf", new MockFileData(new byte[10]));

        // Elemento fabbricato a mano: simula una regola sbagliata che arriva fino all'eliminazione.
        CleanReport report = await Create(fs).CleanAsync(
            [Selection("bug", new ScanItem($"{Home}/Documents/riservato.pdf", 10, false, Home))],
            progress: null,
            CancellationToken.None);

        Assert.True(fs.File.Exists($"{Home}/Documents/riservato.pdf"));
        Assert.Equal(0, report.BytesFreed);
        Assert.Equal(1, report.ItemsFailed);
    }

    [Fact]
    public async Task MissingFileIsRecordedButNotFatal()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/esiste.tmp", new MockFileData(new byte[10]));

        CleanReport report = await Create(fs).CleanAsync(
            [Selection(
                "caches",
                new ScanItem($"{CacheRoot}/sparito.tmp", 999, false, CacheRoot),
                new ScanItem($"{CacheRoot}/esiste.tmp", 10, false, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.Equal(10, report.BytesFreed);
        Assert.Equal(1, report.ItemsDeleted);
        Assert.Equal(1, report.ItemsFailed);
        Assert.Contains(report.Errors, e => e.Kind == ScanErrorKind.NotFound);
    }

    [Fact]
    public async Task OnlyActuallyFreedBytesAreCounted()
    {
        MockFileSystem fs = new();

        CleanReport report = await Create(fs).CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/mai-esistito.tmp", 5_000, false, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.Equal(0, report.BytesFreed);
    }

    [Fact]
    public async Task ResultsAreGroupedByCategory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/a.tmp", new MockFileData(new byte[10]));
        fs.AddFile($"{Home}/.cache/b.tmp", new MockFileData(new byte[20]));

        CleanReport report = await Create(fs).CleanAsync(
            [
                Selection("uno", new ScanItem($"{CacheRoot}/a.tmp", 10, false, CacheRoot)),
                Selection("due", new ScanItem($"{Home}/.cache/b.tmp", 20, false, $"{Home}/.cache")),
            ],
            progress: null,
            CancellationToken.None);

        Assert.Equal(10, report.Categories.Single(c => c.CategoryId == "uno").BytesFreed);
        Assert.Equal(20, report.Categories.Single(c => c.CategoryId == "due").BytesFreed);
        Assert.Equal(30, report.BytesFreed);
    }

    [Fact]
    public async Task DeletedPathsAreRecordedForTheSessionLog()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/a.tmp", new MockFileData(new byte[10]));

        CleanReport report = await Create(fs).CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/a.tmp", 10, false, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.Equal([$"{CacheRoot}/a.tmp"], report.DeletedPaths);
    }

    [Fact]
    public async Task CancellationReturnsPartialReportInsteadOfThrowing()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/a.tmp", new MockFileData(new byte[10]));
        using CancellationTokenSource cts = new();
        await cts.CancelAsync();

        CleanReport report = await Create(fs).CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/a.tmp", 10, false, CacheRoot))],
            progress: null,
            cts.Token);

        Assert.Equal(0, report.ItemsDeleted);
        Assert.True(fs.File.Exists($"{CacheRoot}/a.tmp"));
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
dotnet test --filter FullyQualifiedName~CleanEngineTests
```
Atteso: errore di compilazione, i tipi di eliminazione non esistono.

- [ ] **Step 3: Implementare i modelli**

`src/MjmCleaner.Core/Cleaning/CleanModels.cs`:

```csharp
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Cleaning;

public sealed record CategorySelection(string CategoryId, IReadOnlyList<ScanItem> Items);

public sealed record CategoryCleanResult(string CategoryId, long BytesFreed, int ItemsDeleted);

public sealed record CleanProgress(string CurrentPath, int ItemsDone, int ItemsTotal, long BytesFreed);

public sealed record CleanReport(
    DateTimeOffset StartedAtUtc,
    TimeSpan Duration,
    long BytesFreed,
    int ItemsDeleted,
    int ItemsFailed,
    IReadOnlyList<CategoryCleanResult> Categories,
    IReadOnlyList<ScanError> Errors,
    IReadOnlyList<string> DeletedPaths);
```

- [ ] **Step 4: Implementare `CleanEngine`**

`src/MjmCleaner.Core/Cleaning/CleanEngine.cs`:

```csharp
using System.Diagnostics;
using System.IO.Abstractions;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Cleaning;

public interface ICleanEngine
{
    Task<CleanReport> CleanAsync(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct);
}

/// <summary>
/// Eliminazione definitiva. Sequenziale: su un singolo volume il parallelismo non
/// accelera e renderebbe il resoconto meno prevedibile.
/// </summary>
public sealed class CleanEngine(IFileSystem fileSystem, IPathGuard guard, TimeProvider clock)
    : ICleanEngine
{
    public Task<CleanReport> CleanAsync(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
        => Task.Run(() => Clean(selections, progress, ct), CancellationToken.None);

    private CleanReport Clean(
        IReadOnlyList<CategorySelection> selections,
        IProgress<CleanProgress>? progress,
        CancellationToken ct)
    {
        DateTimeOffset startedAt = clock.GetUtcNow();
        long stamp = Stopwatch.GetTimestamp();

        List<CategoryCleanResult> categories = [];
        List<ScanError> errors = [];
        List<string> deleted = [];
        long totalBytes = 0;
        int totalDeleted = 0;
        int totalFailed = 0;
        int done = 0;
        int total = selections.Sum(s => s.Items.Count);

        foreach (CategorySelection selection in selections)
        {
            long categoryBytes = 0;
            int categoryDeleted = 0;

            foreach (ScanItem item in selection.Items)
            {
                // L'annullamento restituisce un resoconto parziale: ciò che è già stato
                // eliminato deve comunque finire nello storico.
                if (ct.IsCancellationRequested)
                {
                    break;
                }

                done++;

                GuardVerdict verdict = guard.Validate(item.Path, item.DeclaredRoot);
                if (!verdict.IsAllowed)
                {
                    errors.Add(new ScanError(item.Path, ScanErrorKind.Other, verdict.Reason));
                    totalFailed++;
                    continue;
                }

                // Si elimina il percorso che il guard ha VALIDATO, non quello di partenza:
                // validare una stringa e cancellarne un'altra è il difetto che renderebbe
                // aggirabile ogni controllo a monte.
                string target = verdict.CanonicalPathValidated;

                try
                {
                    if (item.IsDirectory)
                    {
                        fileSystem.Directory.Delete(target, recursive: true);
                    }
                    else
                    {
                        if (!fileSystem.File.Exists(target))
                        {
                            throw new FileNotFoundException("elemento non più presente", target);
                        }

                        fileSystem.File.Delete(target);
                    }

                    categoryBytes += item.SizeBytes;
                    categoryDeleted++;
                    deleted.Add(target);
                }
                catch (Exception ex) when (RuleScanner.IsExpected(ex))
                {
                    errors.Add(RuleScanner.Describe(item.Path, ex));
                    totalFailed++;
                }

                progress?.Report(new CleanProgress(item.Path, done, total, totalBytes + categoryBytes));
            }

            categories.Add(new CategoryCleanResult(selection.CategoryId, categoryBytes, categoryDeleted));
            totalBytes += categoryBytes;
            totalDeleted += categoryDeleted;
        }

        return new CleanReport(
            startedAt,
            Stopwatch.GetElapsedTime(stamp),
            totalBytes,
            totalDeleted,
            totalFailed,
            categories,
            errors,
            deleted);
    }
}
```

- [ ] **Step 5: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~CleanEngineTests
```
Atteso: tutti i test passano. Nota: `FileNotFoundException` deriva da `IOException`, quindi rientra in `RuleScanner.IsExpected` e viene classificata `NotFound`.

- [ ] **Step 6: Commit**

```bash
git add src/MjmCleaner.Core/Cleaning tests/MjmCleaner.Core.Tests/Cleaning
git commit -m "feat: add clean engine with per-item error isolation"
```

---

## Task 12: `HistoryStore` — persistenza SQLite

**Nota sul vincolo globale:** questo è l'unico componente che non passa da `IFileSystem`. SQLite apre il file da sé e non conosce le astrazioni di .NET; i test di questo task sono quindi test di integrazione su un file temporaneo reale.

**Files:**
- Create: `src/MjmCleaner.Core/History/HistoryStore.cs`
- Test: `tests/MjmCleaner.Core.Tests/History/HistoryStoreTests.cs`

**Interfaces:**
- Consumes: `CleanReport`, `CategoryCleanResult` (Task 11)
- Produces:
  - `record CleanSessionSummary(long Id, DateTimeOffset StartedAtUtc, TimeSpan Duration, long BytesFreed, int ItemsDeleted, int ItemsFailed, IReadOnlyList<CategoryCleanResult> Categories)`
  - `IHistoryStore` con `InitializeAsync(CancellationToken)`, `Task<long> SaveAsync(CleanReport, CancellationToken)`, `Task<IReadOnlyList<CleanSessionSummary>> GetSessionsAsync(int limit, CancellationToken)`, `Task<long> GetTotalBytesFreedAsync(CancellationToken)`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/History/HistoryStoreTests.cs`:

```csharp
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Tests.History;

public sealed class HistoryStoreTests : IDisposable
{
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), $"mjm-cleaner-test-{Guid.NewGuid():N}");

    private string DatabaseFile => Path.Combine(_directory, "history.db");

    public void Dispose()
    {
        // Senza questo il pool di connessioni tiene aperto il file e la cancellazione fallisce.
        Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();

        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private static CleanReport Report(long bytes, int deleted = 1, int failed = 0, params CategoryCleanResult[] categories)
        => new(
            new DateTimeOffset(2026, 9, 15, 10, 30, 0, TimeSpan.Zero),
            TimeSpan.FromSeconds(38),
            bytes,
            deleted,
            failed,
            categories.Length > 0 ? categories : [new CategoryCleanResult("caches", bytes, deleted)],
            [],
            []);

    [Fact]
    public async Task InitializeCreatesSchemaAndIsIdempotent()
    {
        HistoryStore store = new(DatabaseFile);

        await store.InitializeAsync(CancellationToken.None);
        await store.InitializeAsync(CancellationToken.None);

        Assert.True(File.Exists(DatabaseFile));
        Assert.Equal(0, await store.GetTotalBytesFreedAsync(CancellationToken.None));
    }

    [Fact]
    public async Task SaveThenReadBackSession()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        long id = await store.SaveAsync(Report(1_500), CancellationToken.None);

        CleanSessionSummary session = (await store.GetSessionsAsync(10, CancellationToken.None)).Single();
        Assert.Equal(id, session.Id);
        Assert.Equal(1_500, session.BytesFreed);
        Assert.Equal(TimeSpan.FromSeconds(38), session.Duration);
        Assert.Equal(new DateTimeOffset(2026, 9, 15, 10, 30, 0, TimeSpan.Zero), session.StartedAtUtc);
        Assert.Equal("caches", session.Categories.Single().CategoryId);
    }

    [Fact]
    public async Task TotalIsTheSumOfAllSessions()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        await store.SaveAsync(Report(1_000), CancellationToken.None);
        await store.SaveAsync(Report(2_500), CancellationToken.None);

        Assert.Equal(3_500, await store.GetTotalBytesFreedAsync(CancellationToken.None));
    }

    [Fact]
    public async Task SessionsAreReturnedNewestFirstAndLimited()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        long first = await store.SaveAsync(Report(10), CancellationToken.None);
        long second = await store.SaveAsync(Report(20), CancellationToken.None);
        long third = await store.SaveAsync(Report(30), CancellationToken.None);

        IReadOnlyList<CleanSessionSummary> sessions = await store.GetSessionsAsync(2, CancellationToken.None);

        Assert.Equal([third, second], sessions.Select(s => s.Id));
        Assert.DoesNotContain(sessions, s => s.Id == first);
    }

    [Fact]
    public async Task CategoryBreakdownIsPersisted()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        await store.SaveAsync(
            Report(300, 3, 0, new CategoryCleanResult("caches", 100, 1), new CategoryCleanResult("logs", 200, 2)),
            CancellationToken.None);

        CleanSessionSummary session = (await store.GetSessionsAsync(1, CancellationToken.None)).Single();

        Assert.Equal(2, session.Categories.Count);
        Assert.Equal(200, session.Categories.Single(c => c.CategoryId == "logs").BytesFreed);
    }

    [Fact]
    public async Task FailedItemsAreRecorded()
    {
        HistoryStore store = new(DatabaseFile);
        await store.InitializeAsync(CancellationToken.None);

        await store.SaveAsync(Report(10, deleted: 1, failed: 4), CancellationToken.None);

        Assert.Equal(4, (await store.GetSessionsAsync(1, CancellationToken.None)).Single().ItemsFailed);
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test --filter FullyQualifiedName~HistoryStoreTests
```
Atteso: errore di compilazione, `HistoryStore` non esiste.

- [ ] **Step 3: Implementare**

`src/MjmCleaner.Core/History/HistoryStore.cs`:

```csharp
using Microsoft.Data.Sqlite;
using MjmCleaner.Core.Cleaning;

namespace MjmCleaner.Core.History;

public sealed record CleanSessionSummary(
    long Id,
    DateTimeOffset StartedAtUtc,
    TimeSpan Duration,
    long BytesFreed,
    int ItemsDeleted,
    int ItemsFailed,
    IReadOnlyList<CategoryCleanResult> Categories);

public interface IHistoryStore
{
    Task InitializeAsync(CancellationToken ct);
    Task<long> SaveAsync(CleanReport report, CancellationToken ct);
    Task<IReadOnlyList<CleanSessionSummary>> GetSessionsAsync(int limit, CancellationToken ct);
    Task<long> GetTotalBytesFreedAsync(CancellationToken ct);
}

public sealed class HistoryStore(string databaseFile) : IHistoryStore
{
    private const int SchemaVersion = 1;

    private string ConnectionString => new SqliteConnectionStringBuilder
    {
        DataSource = databaseFile,
        Mode = SqliteOpenMode.ReadWriteCreate,
    }.ToString();

    public async Task InitializeAsync(CancellationToken ct)
    {
        string? directory = Path.GetDirectoryName(databaseFile);
        if (!string.IsNullOrEmpty(directory))
        {
            Directory.CreateDirectory(directory);
        }

        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);

        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = $"""
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

            PRAGMA user_version = {SchemaVersion};
            """;

        await command.ExecuteNonQueryAsync(ct);
    }

    public async Task<long> SaveAsync(CleanReport report, CancellationToken ct)
    {
        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);
        await using SqliteTransaction transaction = (SqliteTransaction)await connection.BeginTransactionAsync(ct);

        await using SqliteCommand insertSession = connection.CreateCommand();
        insertSession.Transaction = transaction;
        insertSession.CommandText = """
            INSERT INTO CleanSession (StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed)
            VALUES ($startedAt, $duration, $bytes, $deleted, $failed);
            SELECT last_insert_rowid();
            """;
        insertSession.Parameters.AddWithValue("$startedAt", report.StartedAtUtc.UtcDateTime.ToString("O"));
        insertSession.Parameters.AddWithValue("$duration", (long)report.Duration.TotalMilliseconds);
        insertSession.Parameters.AddWithValue("$bytes", report.BytesFreed);
        insertSession.Parameters.AddWithValue("$deleted", report.ItemsDeleted);
        insertSession.Parameters.AddWithValue("$failed", report.ItemsFailed);

        long sessionId = (long)(await insertSession.ExecuteScalarAsync(ct))!;

        foreach (CategoryCleanResult category in report.Categories)
        {
            await using SqliteCommand insertCategory = connection.CreateCommand();
            insertCategory.Transaction = transaction;
            insertCategory.CommandText = """
                INSERT INTO SessionCategory (SessionId, CategoryId, BytesFreed, ItemsDeleted)
                VALUES ($session, $category, $bytes, $deleted);
                """;
            insertCategory.Parameters.AddWithValue("$session", sessionId);
            insertCategory.Parameters.AddWithValue("$category", category.CategoryId);
            insertCategory.Parameters.AddWithValue("$bytes", category.BytesFreed);
            insertCategory.Parameters.AddWithValue("$deleted", category.ItemsDeleted);
            await insertCategory.ExecuteNonQueryAsync(ct);
        }

        await transaction.CommitAsync(ct);
        return sessionId;
    }

    public async Task<IReadOnlyList<CleanSessionSummary>> GetSessionsAsync(int limit, CancellationToken ct)
    {
        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);

        Dictionary<long, List<CategoryCleanResult>> categories = [];

        await using (SqliteCommand categoryCommand = connection.CreateCommand())
        {
            categoryCommand.CommandText = """
                SELECT SessionId, CategoryId, BytesFreed, ItemsDeleted
                FROM SessionCategory
                WHERE SessionId IN (SELECT Id FROM CleanSession ORDER BY Id DESC LIMIT $limit);
                """;
            categoryCommand.Parameters.AddWithValue("$limit", limit);

            await using SqliteDataReader reader = await categoryCommand.ExecuteReaderAsync(ct);
            while (await reader.ReadAsync(ct))
            {
                long sessionId = reader.GetInt64(0);
                if (!categories.TryGetValue(sessionId, out List<CategoryCleanResult>? list))
                {
                    list = [];
                    categories[sessionId] = list;
                }

                list.Add(new CategoryCleanResult(reader.GetString(1), reader.GetInt64(2), reader.GetInt32(3)));
            }
        }

        List<CleanSessionSummary> sessions = [];

        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            SELECT Id, StartedAtUtc, DurationMs, BytesFreed, ItemsDeleted, ItemsFailed
            FROM CleanSession
            ORDER BY Id DESC
            LIMIT $limit;
            """;
        command.Parameters.AddWithValue("$limit", limit);

        await using SqliteDataReader sessionReader = await command.ExecuteReaderAsync(ct);
        while (await sessionReader.ReadAsync(ct))
        {
            long id = sessionReader.GetInt64(0);
            sessions.Add(new CleanSessionSummary(
                id,
                DateTimeOffset.Parse(sessionReader.GetString(1), null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal),
                TimeSpan.FromMilliseconds(sessionReader.GetInt64(2)),
                sessionReader.GetInt64(3),
                sessionReader.GetInt32(4),
                sessionReader.GetInt32(5),
                categories.TryGetValue(id, out List<CategoryCleanResult>? list) ? list : []));
        }

        return sessions;
    }

    /// <summary>Somma calcolata, non un contatore memorizzato: un contatore prima o poi diverge dalle righe.</summary>
    public async Task<long> GetTotalBytesFreedAsync(CancellationToken ct)
    {
        await using SqliteConnection connection = new(ConnectionString);
        await connection.OpenAsync(ct);

        await using SqliteCommand command = connection.CreateCommand();
        command.CommandText = "SELECT COALESCE(SUM(BytesFreed), 0) FROM CleanSession;";

        return (long)(await command.ExecuteScalarAsync(ct))!;
    }
}
```

- [ ] **Step 4: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~HistoryStoreTests
```
Atteso: tutti i test passano.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.Core/History tests/MjmCleaner.Core.Tests/History
git commit -m "feat: add sqlite history store with computed cumulative total"
```

---

## Task 13: `SessionLogWriter` — tracciabilità dei percorsi eliminati

Con l'eliminazione definitiva questo log è l'unica ricostruzione possibile di cosa sia stato cancellato.

**Files:**
- Create: `src/MjmCleaner.Core/History/SessionLogWriter.cs`
- Test: `tests/MjmCleaner.Core.Tests/History/SessionLogWriterTests.cs`

**Interfaces:**
- Consumes: `CleanReport` (Task 11), `AppPaths` (Task 5)
- Produces: `ISessionLogWriter.WriteAsync(long sessionId, CleanReport report, CancellationToken ct)`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/History/SessionLogWriterTests.cs`:

```csharp
using System.IO.Abstractions.TestingHelpers;
using System.IO.Compression;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.Tests.History;

public class SessionLogWriterTests
{
    private static readonly AppPaths Paths = new("/Users/tester");

    private static CleanReport Report(params string[] deletedPaths)
        => new(
            DateTimeOffset.UnixEpoch,
            TimeSpan.Zero,
            0,
            deletedPaths.Length,
            0,
            [],
            [],
            deletedPaths);

    [Fact]
    public async Task WritesOneLinePerDeletedPath()
    {
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths);

        await writer.WriteAsync(7, Report("/a/uno.tmp", "/a/due.tmp"), CancellationToken.None);

        string file = fs.Path.Combine(Paths.LogsDirectory, "session-000007.jsonl.gz");
        Assert.True(fs.File.Exists(file));

        using Stream raw = fs.File.OpenRead(file);
        using GZipStream unzipped = new(raw, CompressionMode.Decompress);
        using StreamReader reader = new(unzipped);
        string content = await reader.ReadToEndAsync();

        string[] lines = content.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        Assert.Equal(2, lines.Length);
        Assert.Contains("/a/uno.tmp", lines[0]);
        Assert.Contains("/a/due.tmp", lines[1]);
    }

    [Fact]
    public async Task KeepsOnlyTheMostRecentSessions()
    {
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths, retention: 3);

        for (long id = 1; id <= 5; id++)
        {
            await writer.WriteAsync(id, Report($"/a/{id}.tmp"), CancellationToken.None);
        }

        string[] remaining = [.. fs.Directory
            .EnumerateFiles(Paths.LogsDirectory)
            .Select(fs.Path.GetFileName)
            .Order()];

        Assert.Equal(
            ["session-000003.jsonl.gz", "session-000004.jsonl.gz", "session-000005.jsonl.gz"],
            remaining);
    }

    [Fact]
    public async Task CreatesTheLogsDirectoryWhenMissing()
    {
        MockFileSystem fs = new();
        SessionLogWriter writer = new(fs, Paths);

        await writer.WriteAsync(1, Report("/a/x.tmp"), CancellationToken.None);

        Assert.True(fs.Directory.Exists(Paths.LogsDirectory));
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
dotnet test --filter FullyQualifiedName~SessionLogWriterTests
```
Atteso: errore di compilazione, `SessionLogWriter` non esiste.

- [ ] **Step 3: Implementare**

`src/MjmCleaner.Core/History/SessionLogWriter.cs`:

```csharp
using System.IO.Abstractions;
using System.IO.Compression;
using System.Text.Json;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.Core.History;

public interface ISessionLogWriter
{
    Task WriteAsync(long sessionId, CleanReport report, CancellationToken ct);
}

/// <summary>
/// Elenco completo dei percorsi eliminati, una riga JSON per elemento, compresso.
/// Non va in SQLite: una pulizia delle cache tocca centinaia di migliaia di file e
/// il database crescerebbe più in fretta dello spazio liberato.
/// </summary>
public sealed class SessionLogWriter(IFileSystem fileSystem, AppPaths paths, int retention = 20)
    : ISessionLogWriter
{
    public async Task WriteAsync(long sessionId, CleanReport report, CancellationToken ct)
    {
        fileSystem.Directory.CreateDirectory(paths.LogsDirectory);

        string file = fileSystem.Path.Combine(paths.LogsDirectory, FileName(sessionId));

        await using (Stream raw = fileSystem.File.Create(file))
        await using (GZipStream zipped = new(raw, CompressionLevel.Optimal))
        await using (StreamWriter writer = new(zipped))
        {
            foreach (string path in report.DeletedPaths)
            {
                ct.ThrowIfCancellationRequested();
                await writer.WriteLineAsync(JsonSerializer.Serialize(new { path }));
            }
        }

        Prune();
    }

    private static string FileName(long sessionId) => $"session-{sessionId:D6}.jsonl.gz";

    private void Prune()
    {
        string[] files = [.. fileSystem.Directory
            .EnumerateFiles(paths.LogsDirectory, "session-*.jsonl.gz")
            .OrderDescending()];

        foreach (string stale in files.Skip(retention))
        {
            try
            {
                fileSystem.File.Delete(stale);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // La rotazione dei log non deve far fallire una pulizia riuscita.
            }
        }
    }
}
```

- [ ] **Step 4: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~SessionLogWriterTests
```
Atteso: tutti i test passano. I nomi con numerazione a sei cifre rendono l'ordinamento alfabetico equivalente a quello numerico.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.Core/History tests/MjmCleaner.Core.Tests/History
git commit -m "feat: add compressed per-session deletion log with retention"
```

---

## Task 14: `RunningAppsProbe` — avviso sulle applicazioni aperte

**Files:**
- Create: `src/MjmCleaner.Core/Diagnostics/RunningAppsProbe.cs`
- Test: `tests/MjmCleaner.Core.Tests/Diagnostics/RunningAppsProbeTests.cs`

**Interfaces:**
- Consumes: niente
- Produces: `IRunningAppsProbe.AffectedApps(IEnumerable<string> paths)` → `IReadOnlyList<string>`

- [ ] **Step 1: Scrivere i test falliti**

`tests/MjmCleaner.Core.Tests/Diagnostics/RunningAppsProbeTests.cs`:

```csharp
using MjmCleaner.Core.Diagnostics;

namespace MjmCleaner.Core.Tests.Diagnostics;

public class RunningAppsProbeTests
{
    private static RunningAppsProbe Create(params string[] processes)
        => new(() => processes);

    [Fact]
    public void MatchesBundleIdentifierAgainstProcessName()
    {
        IReadOnlyList<string> affected = Create("Safari", "Finder")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]);

        Assert.Equal(["Safari"], affected);
    }

    [Fact]
    public void IgnoresProcessesNotInvolved()
    {
        IReadOnlyList<string> affected = Create("Mail")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Safari"]);

        Assert.Empty(affected);
    }

    [Fact]
    public void ReportsEachApplicationOnlyOnce()
    {
        IReadOnlyList<string> affected = Create("Safari").AffectedApps(
        [
            "/Users/tester/Library/Caches/com.apple.Safari",
            "/Users/tester/Library/Caches/com.apple.Safari.WebKit",
        ]);

        Assert.Equal(["Safari"], affected);
    }

    [Fact]
    public void IgnoresVeryShortProcessNamesToAvoidFalsePositives()
    {
        IReadOnlyList<string> affected = Create("ls")
            .AffectedApps(["/Users/tester/Library/Caches/com.apple.Tools"]);

        Assert.Empty(affected);
    }
}
```

- [ ] **Step 2: Eseguire i test e verificare che falliscano**

```bash
dotnet test --filter FullyQualifiedName~RunningAppsProbeTests
```
Atteso: errore di compilazione, `RunningAppsProbe` non esiste.

- [ ] **Step 3: Implementare**

`src/MjmCleaner.Core/Diagnostics/RunningAppsProbe.cs`:

```csharp
using System.Diagnostics;

namespace MjmCleaner.Core.Diagnostics;

public interface IRunningAppsProbe
{
    IReadOnlyList<string> AffectedApps(IEnumerable<string> paths);
}

/// <summary>
/// Euristica: svuotare la cache di un'applicazione aperta può farla comportare in modo
/// anomalo fino al riavvio, quindi conviene avvisare prima di eliminare.
/// </summary>
public sealed class RunningAppsProbe(Func<IReadOnlyList<string>> processNames) : IRunningAppsProbe
{
    private const int MinimumNameLength = 4;

    public IReadOnlyList<string> AffectedApps(IEnumerable<string> paths)
    {
        string[] candidates = [.. processNames()
            .Where(name => name.Length >= MinimumNameLength)
            .Distinct(StringComparer.OrdinalIgnoreCase)];

        if (candidates.Length == 0)
        {
            return [];
        }

        HashSet<string> affected = new(StringComparer.OrdinalIgnoreCase);

        foreach (string path in paths)
        {
            string name = Path.GetFileName(path);

            foreach (string candidate in candidates)
            {
                if (name.Contains(candidate, StringComparison.OrdinalIgnoreCase))
                {
                    affected.Add(candidate);
                }
            }
        }

        return [.. affected.Order(StringComparer.OrdinalIgnoreCase)];
    }

    public static RunningAppsProbe ForCurrentMachine()
        => new(() =>
        {
            try
            {
                return [.. Process.GetProcesses().Select(p => p.ProcessName)];
            }
            catch (InvalidOperationException)
            {
                return [];
            }
        });
}
```

- [ ] **Step 4: Eseguire i test e verificare che passino**

```bash
dotnet test --filter FullyQualifiedName~RunningAppsProbeTests
```
Atteso: tutti i test passano. La soglia di quattro caratteri evita che processi dal nome brevissimo generino corrispondenze spurie.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.Core/Diagnostics tests/MjmCleaner.Core.Tests/Diagnostics
git commit -m "feat: add running apps probe for pre-deletion warning"
```

---

## Task 15: Progetto Avalonia e bundle `.app`

Incorpora il secondo spike della specifica: meglio scoprire ora se il confezionamento ha attrito, non a funzionalità finite.

**Files:**
- Create: `src/MjmCleaner.App/` (da template Avalonia)
- Create: `build/bundle.sh`
- Create: `build/Info.plist`
- Modify: `mjm.cleaner.sln`

**Interfaces:**
- Consumes: `MjmCleaner.Core` (riferimento di progetto)
- Produces: applicazione avviabile con `dotnet run`; `build/bundle.sh` che produce `artifacts/mjm.cleaner.app`

- [ ] **Step 1: Installare i template e creare il progetto**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
cd /Users/mjm/projects/mjm.cleaner
dotnet new install Avalonia.Templates::12.1.2
dotnet new avalonia.app -n MjmCleaner.App -o src/MjmCleaner.App
dotnet sln add src/MjmCleaner.App
dotnet add src/MjmCleaner.App reference src/MjmCleaner.Core
dotnet add src/MjmCleaner.App package CommunityToolkit.Mvvm --version 8.4.2
dotnet add src/MjmCleaner.App package System.IO.Abstractions --version 22.2.0
```

- [ ] **Step 2: Verificare che l'applicazione si avvii**

```bash
dotnet run --project src/MjmCleaner.App
```
Atteso: si apre una finestra vuota. Chiuderla. Se il template genera file diversi da quelli attesi nei task successivi (`App.axaml`, `MainWindow.axaml`, `Program.cs`), prendere per buono ciò che ha generato e adattare i percorsi: i task seguenti presuppongono `App.axaml`, `Views/MainWindow.axaml` e `ViewModels/`.

Se il progetto non compila perché il generatore XAML o quello di CommunityToolkit emettono avvisi, aggiungere `<TreatWarningsAsErrors>false</TreatWarningsAsErrors>` nel solo `MjmCleaner.App.csproj`: il vincolo resta attivo dove conta, cioè sul Core.

- [ ] **Step 3: Creare `build/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>mjm.cleaner</string>
    <key>CFBundleDisplayName</key>
    <string>mjm.cleaner</string>
    <key>CFBundleIdentifier</key>
    <string>com.mjm.cleaner</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MjmCleaner.App</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Creare `build/bundle.sh`**

```bash
#!/usr/bin/env bash
# Costruisce artifacts/mjm.cleaner.app a partire dalla pubblicazione self-contained.
set -euo pipefail

export PATH="/usr/local/share/dotnet:$PATH"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/artifacts/mjm.cleaner.app"
ARCH="$(uname -m)"
RID="osx-arm64"
[ "$ARCH" = "x86_64" ] && RID="osx-x64"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

dotnet publish "$ROOT/src/MjmCleaner.App" \
    --configuration Release \
    --runtime "$RID" \
    --self-contained true \
    --output "$APP/Contents/MacOS"

cp "$ROOT/build/Info.plist" "$APP/Contents/Info.plist"

# Firma ad-hoc: senza una firma macOS rifiuta di avviare il bundle.
codesign --force --deep --sign - "$APP"

echo "Creato: $APP"
echo "Nota: dopo ogni ricompilazione può essere necessario riconcedere l'Accesso completo al disco."
```

Renderlo eseguibile:

```bash
chmod +x build/bundle.sh
```

- [ ] **Step 5: Eseguire il bundle e verificare l'avvio**

```bash
./build/bundle.sh
open artifacts/mjm.cleaner.app
```
Atteso: si apre la stessa finestra vuota, avviata dal bundle e non da `dotnet run`. Se macOS blocca l'avvio, annotare il messaggio esatto: serve al Task 22.

- [ ] **Step 6: Escludere gli artefatti dal repository**

Verificare che `.gitignore` contenga `artifacts/`; in caso contrario aggiungerlo.

- [ ] **Step 7: Commit**

```bash
git add src/MjmCleaner.App build .gitignore mjm.cleaner.sln
git commit -m "feat: add avalonia app shell and macOS bundle script"
```

---

## Task 16: Composizione dei servizi e struttura del wizard

**Files:**
- Create: `src/MjmCleaner.App/Services/AppServices.cs`
- Create: `src/MjmCleaner.App/ViewModels/ViewModelBase.cs`
- Create: `src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`
- Modify: `src/MjmCleaner.App/Views/MainWindow.axaml`
- Modify: `src/MjmCleaner.App/App.axaml`, `src/MjmCleaner.App/App.axaml.cs`

**Interfaces:**
- Consumes: tutto il Core (Task 3-14)
- Produces:
  - `AppServices` con `IScanEngine Scan`, `ICleanEngine Clean`, `IHistoryStore History`, `ISessionLogWriter SessionLog`, `ISettingsStore Settings`, `IRunningAppsProbe RunningApps`, `IReadOnlyList<CleanupCategory> Categories`, `Task<AppServices> CreateAsync()`
  - `MainWindowViewModel` con `object? CurrentPage`, `string TotalFreedText`, `Task RefreshTotalAsync()`, `void GoTo(object page)`

- [ ] **Step 1: Comporre i servizi**

`src/MjmCleaner.App/Services/AppServices.cs`:

```csharp
using System.IO.Abstractions;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Diagnostics;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Safety;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.Services;

/// <summary>
/// Composizione manuale delle dipendenze: per un'applicazione con un solo grafo di
/// oggetti un contenitore di inversione del controllo aggiungerebbe solo indirezione.
/// </summary>
public sealed class AppServices
{
    private AppServices(
        IScanEngine scan,
        ICleanEngine clean,
        IHistoryStore history,
        ISessionLogWriter sessionLog,
        ISettingsStore settings,
        IRunningAppsProbe runningApps,
        AppPaths paths)
    {
        Scan = scan;
        Clean = clean;
        History = history;
        SessionLog = sessionLog;
        Settings = settings;
        RunningApps = runningApps;
        Paths = paths;
    }

    public IScanEngine Scan { get; }
    public ICleanEngine Clean { get; }
    public IHistoryStore History { get; }
    public ISessionLogWriter SessionLog { get; }
    public ISettingsStore Settings { get; }
    public IRunningAppsProbe RunningApps { get; }
    public AppPaths Paths { get; }

    public IReadOnlyList<CleanupCategory> BuildCategories()
        => CategoryCatalog.Build(Settings.Load(), PathExpander.ForCurrentUser());

    public static async Task<AppServices> CreateAsync()
    {
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        FileSystem fileSystem = new();
        AppPaths paths = AppPaths.ForCurrentUser();

        FileSystemLinkInspector links = new(fileSystem);
        PathGuard guard = new(new DenyList(home), links, home);
        RuleScanner scanner = new(fileSystem, guard, links, TimeProvider.System);

        HistoryStore history = new(paths.DatabaseFile);
        await history.InitializeAsync(CancellationToken.None);

        return new AppServices(
            new ScanEngine(scanner),
            new CleanEngine(fileSystem, guard, TimeProvider.System),
            history,
            new SessionLogWriter(fileSystem, paths),
            new SettingsStore(fileSystem, paths),
            RunningAppsProbe.ForCurrentMachine(),
            paths);
    }
}
```

- [ ] **Step 2: Creare la base dei ViewModel e il formattatore delle dimensioni**

`src/MjmCleaner.App/ViewModels/ViewModelBase.cs`:

```csharp
using CommunityToolkit.Mvvm.ComponentModel;

namespace MjmCleaner.App.ViewModels;

public abstract class ViewModelBase : ObservableObject
{
    /// <summary>Formato leggibile con separatore decimale italiano: 11,3 GB.</summary>
    public static string FormatBytes(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double value = bytes;
        int unit = 0;

        while (value >= 1024 && unit < units.Length - 1)
        {
            value /= 1024;
            unit++;
        }

        return unit == 0
            ? $"{bytes} {units[unit]}"
            : string.Format(new System.Globalization.CultureInfo("it-IT"), "{0:0.#} {1}", value, units[unit]);
    }
}
```

- [ ] **Step 3: Creare `MainWindowViewModel`**

`src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`:

```csharp
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;

namespace MjmCleaner.App.ViewModels;

// Nota: l'using di CommunityToolkit.Mvvm.Input serve dal Task 21, quando arrivano i comandi
// della barra strumenti. Se il compilatore segnala un using inutilizzato, rimuoverlo ora e
// riaggiungerlo allora.
public sealed partial class MainWindowViewModel : ViewModelBase
{
    private readonly AppServices _services;

    [ObservableProperty]
    private object? _currentPage;

    [ObservableProperty]
    private string _totalFreedText = "—";

    public MainWindowViewModel(AppServices services) => _services = services;

    public AppServices Services => _services;

    /// <summary>Naviga a una pagina. Il Task 17 imposta qui il primo passo del wizard.</summary>
    public void GoTo(object page) => CurrentPage = page;

    public async Task RefreshTotalAsync()
    {
        long total = await _services.History.GetTotalBytesFreedAsync(CancellationToken.None);
        TotalFreedText = $"{FormatBytes(total)} liberati finora";
    }
}
```

- [ ] **Step 4: Scrivere la shell con la barra strumenti**

`src/MjmCleaner.App/Views/MainWindow.axaml`:

```xml
<Window xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
        x:Class="MjmCleaner.App.Views.MainWindow"
        x:DataType="vm:MainWindowViewModel"
        Title="mjm.cleaner"
        Width="900" Height="640"
        MinWidth="720" MinHeight="520">

    <DockPanel>
        <Border DockPanel.Dock="Top"
                Padding="14,10"
                BorderThickness="0,0,0,1"
                BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}">
            <Grid ColumnDefinitions="Auto,*,Auto">
                <TextBlock Grid.Column="0"
                           Text="{Binding TotalFreedText}"
                           FontWeight="SemiBold"
                           VerticalAlignment="Center" />
                <!-- I comandi vengono collegati nel Task 21, quando le pagine esistono. -->
                <StackPanel Grid.Column="2" Orientation="Horizontal" Spacing="8">
                    <Button Content="Storico" IsEnabled="False" />
                    <Button Content="Impostazioni" IsEnabled="False" />
                </StackPanel>
            </Grid>
        </Border>

        <ContentControl Content="{Binding CurrentPage}" Margin="16" />
    </DockPanel>
</Window>
```

- [ ] **Step 5: Predisporre i modelli di dati e avviare con i servizi**

In `src/MjmCleaner.App/App.axaml` aggiungere l'elemento vuoto, che i Task 17-21 popoleranno una riga per volta man mano che le viste esistono:

```xml
<Application.DataTemplates>
</Application.DataTemplates>
```

Aggiungere in testa all'elemento `Application` gli spazi dei nomi:

```xml
xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
xmlns:views="clr-namespace:MjmCleaner.App.Views"
```

In `App.axaml.cs`, sostituire il corpo di `OnFrameworkInitializationCompleted` con:

```csharp
public override async void OnFrameworkInitializationCompleted()
{
    if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
    {
        AppServices services = await AppServices.CreateAsync();
        MainWindowViewModel viewModel = new(services);

        desktop.MainWindow = new MainWindow { DataContext = viewModel };
        await viewModel.RefreshTotalAsync();
    }

    base.OnFrameworkInitializationCompleted();
}
```

Aggiungere gli `using` necessari: `Avalonia.Controls.ApplicationLifetimes`, `MjmCleaner.App.Services`, `MjmCleaner.App.ViewModels`, `MjmCleaner.App.Views`.

- [ ] **Step 6: Verificare**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet run --project src/MjmCleaner.App
```
Atteso: la finestra si apre con la barra strumenti, i due pulsanti disabilitati e la scritta **«0 B liberati finora»** a sinistra. Quel testo è la prova che il database è stato creato e interrogato: verificare che esista `~/Library/Application Support/mjm.cleaner/history.db`.

- [ ] **Step 7: Commit**

```bash
git add src/MjmCleaner.App
git commit -m "feat: add service composition and window shell with toolbar"
```

---

## Task 17: Passo 1 — Scegli

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/ChooseStepViewModel.cs`
- Create: `src/MjmCleaner.App/Views/ChooseStepView.axaml` (+ `.axaml.cs`)
- Modify: `src/MjmCleaner.App/App.axaml`, `src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`

**Interfaces:**
- Consumes: `AppServices` (Task 16), `CleanupCategory` (Task 7)
- Produces:
  - `CategoryChoice` con `bool IsSelected`, `CleanupCategory Category`, `string RiskLabel`, `Thickness Indent`
  - `ChooseStepViewModel(AppServices, MainWindowViewModel)` con `ObservableCollection<CategoryChoice> Choices` e comando `Analyze`

- [ ] **Step 1: Creare il ViewModel**

`src/MjmCleaner.App/ViewModels/ChooseStepViewModel.cs`:

```csharp
using System.Collections.ObjectModel;
using Avalonia;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.ViewModels;

public sealed partial class CategoryChoice(CleanupCategory category, bool isSelected) : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected = isSelected;

    public CleanupCategory Category { get; } = category;

    public string DisplayName => Category.DisplayName;
    public string Description => Category.Description;

    public string RiskLabel => Category.Risk switch
    {
        RiskLevel.Low => "rischio basso",
        RiskLevel.Medium => "rischio medio",
        RiskLevel.High => "rischio alto",
        _ => string.Empty,
    };

    /// <summary>I pacchetti NuGet compaiono rientrati sotto le cache di sviluppo.</summary>
    public Thickness Indent => Category.ParentId is null ? new Thickness(0) : new Thickness(28, 0, 0, 0);
}

public sealed partial class ChooseStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    public ChooseStepViewModel(AppServices services, MainWindowViewModel main)
    {
        _services = services;
        _main = main;

        CleanerSettings settings = services.Settings.Load();
        HashSet<string> remembered = new(settings.SelectedCategoryIds, StringComparer.Ordinal);

        Choices = [.. services.BuildCategories().Select(category =>
            new CategoryChoice(category, remembered.Contains(category.Id)))];
    }

    public ObservableCollection<CategoryChoice> Choices { get; }

    [RelayCommand]
    private void Analyze()
    {
        CleanupCategory[] selected = [.. Choices.Where(c => c.IsSelected).Select(c => c.Category)];

        if (selected.Length == 0)
        {
            return;
        }

        // La selezione viene ricordata: è ciò che rende sopportabili quattro passi ogni settimana.
        CleanerSettings settings = _services.Settings.Load() with
        {
            SelectedCategoryIds = [.. selected.Select(c => c.Id)],
        };
        _services.Settings.Save(settings);

        _main.GoTo(new ScanStepViewModel(_services, _main, selected));
    }
}
```

- [ ] **Step 2: Creare la vista**

`src/MjmCleaner.App/Views/ChooseStepView.axaml`:

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
             x:Class="MjmCleaner.App.Views.ChooseStepView"
             x:DataType="vm:ChooseStepViewModel">

    <DockPanel>
        <StackPanel DockPanel.Dock="Top" Spacing="4" Margin="0,0,0,16">
            <TextBlock Text="1 · Scegli › 2 Analizza › 3 Conferma › 4 Fatto" Opacity="0.6" FontSize="12" />
            <TextBlock Text="Cosa vuoi pulire?" FontSize="22" FontWeight="Bold" />
        </StackPanel>

        <Button DockPanel.Dock="Bottom"
                HorizontalAlignment="Right"
                Margin="0,16,0,0"
                Padding="18,8"
                Content="Analizza →"
                Command="{Binding AnalyzeCommand}" />

        <ScrollViewer>
            <ItemsControl ItemsSource="{Binding Choices}">
                <ItemsControl.ItemTemplate>
                    <DataTemplate DataType="vm:CategoryChoice">
                        <Border Margin="{Binding Indent}"
                                Padding="12,10"
                                CornerRadius="6"
                                BorderThickness="1"
                                BorderBrush="{DynamicResource SystemControlForegroundBaseLowBrush}">
                            <Grid ColumnDefinitions="Auto,*,Auto">
                                <CheckBox Grid.Column="0"
                                          IsChecked="{Binding IsSelected}"
                                          VerticalAlignment="Center"
                                          Margin="0,0,10,0" />
                                <StackPanel Grid.Column="1" Spacing="2">
                                    <TextBlock Text="{Binding DisplayName}" FontWeight="SemiBold" />
                                    <TextBlock Text="{Binding Description}"
                                               Opacity="0.65"
                                               FontSize="12"
                                               TextWrapping="Wrap" />
                                </StackPanel>
                                <TextBlock Grid.Column="2"
                                           Text="{Binding RiskLabel}"
                                           Opacity="0.6"
                                           FontSize="11"
                                           VerticalAlignment="Center" />
                            </Grid>
                        </Border>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
                <ItemsControl.ItemsPanel>
                    <ItemsPanelTemplate>
                        <StackPanel Spacing="8" />
                    </ItemsPanelTemplate>
                </ItemsControl.ItemsPanel>
            </ItemsControl>
        </ScrollViewer>
    </DockPanel>
</UserControl>
```

`src/MjmCleaner.App/Views/ChooseStepView.axaml.cs`:

```csharp
using Avalonia.Controls;
using Avalonia.Markup.Xaml;

namespace MjmCleaner.App.Views;

public partial class ChooseStepView : UserControl
{
    public ChooseStepView() => InitializeComponent();

    private void InitializeComponent() => AvaloniaXamlLoader.Load(this);
}
```

- [ ] **Step 3: Collegare il passo alla shell**

In `App.axaml`, dentro `<Application.DataTemplates>`:

```xml
<DataTemplate DataType="vm:ChooseStepViewModel"><views:ChooseStepView /></DataTemplate>
```

In `MainWindowViewModel`, aggiungere il metodo e chiamarlo dal costruttore:

```csharp
    public void StartOver() => CurrentPage = new ChooseStepViewModel(_services, this);
```

Il costruttore diventa:

```csharp
    public MainWindowViewModel(AppServices services)
    {
        _services = services;
        StartOver();
    }
```

- [ ] **Step 4: Verificare a mano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet run --project src/MjmCleaner.App
```
Atteso: sei righe di categoria; «Pacchetti NuGet inutilizzati» rientrata e non selezionata; «Cestino, Download e file grandi» non selezionata con etichetta «rischio alto»; le altre quattro selezionate. Deselezionare una categoria, premere *Analizza* (fallirà: il passo 2 non esiste ancora — è previsto), riavviare e verificare che la deselezione sia stata ricordata. Controllare che `~/Library/Application Support/mjm.cleaner/settings.json` esista e contenga `SelectedCategoryIds`.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.App
git commit -m "feat: add wizard step 1 with remembered category selection"
```

---

## Task 18: Passo 2 — Analizza

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/ScanStepViewModel.cs`
- Create: `src/MjmCleaner.App/Views/ScanStepView.axaml` (+ `.axaml.cs`)
- Modify: `src/MjmCleaner.App/App.axaml`

**Interfaces:**
- Consumes: `IScanEngine` (Task 10), `ChooseStepViewModel` (Task 17)
- Produces: `ScanStepViewModel(AppServices, MainWindowViewModel, IReadOnlyList<CleanupCategory>)` che al termine naviga a `ConfirmStepViewModel`

- [ ] **Step 1: Creare il ViewModel**

`src/MjmCleaner.App/ViewModels/ScanStepViewModel.cs`:

```csharp
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

public sealed partial class CategoryProgress(string displayName) : ObservableObject
{
    [ObservableProperty]
    private string _status = "in attesa";

    public string DisplayName { get; } = displayName;
}

public sealed partial class ScanStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;
    private readonly IReadOnlyList<CleanupCategory> _categories;
    private readonly CancellationTokenSource _cts = new();

    [ObservableProperty]
    private string _currentPath = string.Empty;

    [ObservableProperty]
    private bool _isRunning = true;

    public ScanStepViewModel(
        AppServices services,
        MainWindowViewModel main,
        IReadOnlyList<CleanupCategory> categories)
    {
        _services = services;
        _main = main;
        _categories = categories;

        Progress = [.. categories.Select(c => new CategoryProgress(c.DisplayName))];
        _ = RunAsync();
    }

    public ObservableCollection<CategoryProgress> Progress { get; }

    private async Task RunAsync()
    {
        Progress<ScanProgress> reporter = new(OnProgress);

        try
        {
            IReadOnlyList<CategoryScanResult> results =
                await _services.Scan.ScanAsync(_categories, reporter, _cts.Token);

            IsRunning = false;
            _main.GoTo(new ConfirmStepViewModel(_services, _main, _categories, results));
        }
        catch (OperationCanceledException)
        {
            IsRunning = false;
            _main.StartOver();
        }
    }

    private void OnProgress(ScanProgress progress)
    {
        CleanupCategory? category = _categories.FirstOrDefault(c => c.Id == progress.CategoryId);
        if (category is null)
        {
            return;
        }

        CategoryProgress row = Progress.First(p => p.DisplayName == category.DisplayName);
        row.Status = progress.CurrentPath.Length == 0
            ? $"{progress.ItemsFound} elementi · {FormatBytes(progress.BytesFound)}"
            : "in corso…";

        if (progress.CurrentPath.Length > 0)
        {
            CurrentPath = progress.CurrentPath;
        }
    }

    [RelayCommand]
    private void Cancel() => _cts.Cancel();
}
```

- [ ] **Step 2: Creare la vista**

`src/MjmCleaner.App/Views/ScanStepView.axaml`:

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
             x:Class="MjmCleaner.App.Views.ScanStepView"
             x:DataType="vm:ScanStepViewModel">

    <DockPanel>
        <StackPanel DockPanel.Dock="Top" Spacing="4" Margin="0,0,0,16">
            <TextBlock Text="1 Scegli › 2 · Analizza › 3 Conferma › 4 Fatto" Opacity="0.6" FontSize="12" />
            <TextBlock Text="Analisi in corso…" FontSize="22" FontWeight="Bold" />
            <ProgressBar IsIndeterminate="{Binding IsRunning}" Height="4" Margin="0,8,0,0" />
            <TextBlock Text="{Binding CurrentPath}" Opacity="0.55" FontSize="11" TextTrimming="CharacterEllipsis" />
        </StackPanel>

        <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,16,0,0" Spacing="12">
            <TextBlock Text="Nessun file è stato ancora toccato."
                       Opacity="0.65"
                       VerticalAlignment="Center" />
            <Button Content="Annulla" Command="{Binding CancelCommand}" />
        </StackPanel>

        <ItemsControl ItemsSource="{Binding Progress}">
            <ItemsControl.ItemTemplate>
                <DataTemplate DataType="vm:CategoryProgress">
                    <Grid ColumnDefinitions="*,Auto" Margin="0,5">
                        <TextBlock Grid.Column="0" Text="{Binding DisplayName}" />
                        <TextBlock Grid.Column="1" Text="{Binding Status}" Opacity="0.65" />
                    </Grid>
                </DataTemplate>
            </ItemsControl.ItemTemplate>
        </ItemsControl>
    </DockPanel>
</UserControl>
```

`src/MjmCleaner.App/Views/ScanStepView.axaml.cs`: identico a `ChooseStepView.axaml.cs` con nome di classe `ScanStepView`.

- [ ] **Step 3: Registrare il modello di dati**

In `App.axaml`, dentro `<Application.DataTemplates>`:

```xml
<DataTemplate DataType="vm:ScanStepViewModel"><views:ScanStepView /></DataTemplate>
```

- [ ] **Step 4: Verificare a mano**

Il passo 3 non esiste ancora: per provare questo task, commentare temporaneamente la riga `_main.GoTo(new ConfirmStepViewModel(...))` in `RunAsync`.

```bash
dotnet run --project src/MjmCleaner.App
```
Atteso: selezionare *Cache utente e di sistema*, premere *Analizza*. La barra si anima, i percorsi scorrono, al termine la riga della categoria mostra elementi e dimensione (verosimilmente qualche GB). Ripetere premendo *Annulla* a metà: si torna al passo 1 in tempi ragionevoli. Ripristinare la riga commentata prima del commit.

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.App
git commit -m "feat: add wizard step 2 with progress and cancellation"
```

---

## Task 19: Passo 3 — Conferma

Il passo che protegge l'utente: l'unica rete di sicurezza, dato che l'eliminazione è definitiva.

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/ConfirmStepViewModel.cs`
- Create: `src/MjmCleaner.App/Views/ConfirmStepView.axaml` (+ `.axaml.cs`)
- Modify: `src/MjmCleaner.App/App.axaml`

**Interfaces:**
- Consumes: `CategoryScanResult` (Task 8), `ICleanEngine` (Task 11), `IRunningAppsProbe` (Task 14)
- Produces:
  - `PathNode` con `bool IsSelected`, `string Path`, `string SizeText`, `IReadOnlyList<ScanItem> Items`
  - `CategoryNode` con `string DisplayName`, `ObservableCollection<PathNode> Paths`
  - `ConfirmStepViewModel` con `TotalText`, `ExclusionsText`, `RunningAppsWarning` e comando `Delete`

- [ ] **Step 1: Creare il ViewModel**

`src/MjmCleaner.App/ViewModels/ConfirmStepViewModel.cs`:

```csharp
using System.Collections.ObjectModel;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

public sealed partial class PathNode(string path, IReadOnlyList<ScanItem> items) : ObservableObject
{
    [ObservableProperty]
    private bool _isSelected = true;

    public string Path { get; } = path;
    public IReadOnlyList<ScanItem> Items { get; } = items;
    public long SizeBytes { get; } = items.Sum(i => i.SizeBytes);
    public string SizeText => ViewModelBase.FormatBytes(SizeBytes);
    public string CountText => $"{Items.Count} elementi";
}

public sealed class CategoryNode(string categoryId, string displayName, IEnumerable<PathNode> paths)
{
    public string CategoryId { get; } = categoryId;
    public string DisplayName { get; } = displayName;
    public ObservableCollection<PathNode> Paths { get; } = [.. paths];
}

public sealed partial class ConfirmStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    [ObservableProperty]
    private string _totalText = string.Empty;

    [ObservableProperty]
    private bool _isDeleting;

    public ConfirmStepViewModel(
        AppServices services,
        MainWindowViewModel main,
        IReadOnlyList<CleanupCategory> categories,
        IReadOnlyList<CategoryScanResult> results)
    {
        _services = services;
        _main = main;

        Nodes = [.. results
            .Where(r => r.Items.Count > 0)
            .Select(result => new CategoryNode(
                result.CategoryId,
                categories.First(c => c.Id == result.CategoryId).DisplayName,
                result.Items
                    .GroupBy(i => i.DeclaredRoot, StringComparer.Ordinal)
                    .Select(group => new PathNode(group.Key, [.. group]))))];

        foreach (PathNode node in Nodes.SelectMany(n => n.Paths))
        {
            node.PropertyChanged += OnNodeChanged;
        }

        // Elenco di ciò che le protezioni hanno tolto d'ufficio: se un totale non torna,
        // qui se ne trova il motivo.
        GuardExclusion[] exclusions = [.. results.SelectMany(r => r.Exclusions)];
        ExclusionsText = exclusions.Length == 0
            ? string.Empty
            : $"{exclusions.Length} elementi esclusi dalle protezioni:\n" +
              string.Join('\n', exclusions.Take(5).Select(e => $"· {e.Path} — {e.Reason}"));

        string[] affected = [.. services.RunningApps.AffectedApps(
            results.SelectMany(r => r.Items).Take(2000).Select(i => i.Path))];
        RunningAppsWarning = affected.Length == 0
            ? string.Empty
            : $"{string.Join(", ", affected)} in esecuzione: le loro cache potrebbero rigenerarsi subito.";

        Recalculate();
    }

    public ObservableCollection<CategoryNode> Nodes { get; }
    public string ExclusionsText { get; }
    public string RunningAppsWarning { get; }

    private void OnNodeChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(PathNode.IsSelected))
        {
            Recalculate();
        }
    }

    private void Recalculate()
    {
        PathNode[] selected = [.. Nodes.SelectMany(n => n.Paths).Where(p => p.IsSelected)];
        long bytes = selected.Sum(p => p.SizeBytes);
        int items = selected.Sum(p => p.Items.Count);

        TotalText = $"{FormatBytes(bytes)} · {items:N0} elementi";
        DeleteCommand.NotifyCanExecuteChanged();
    }

    private bool CanDelete() => !IsDeleting && Nodes.SelectMany(n => n.Paths).Any(p => p.IsSelected);

    [RelayCommand(CanExecute = nameof(CanDelete))]
    private async Task DeleteAsync()
    {
        IsDeleting = true;
        DeleteCommand.NotifyCanExecuteChanged();

        CategorySelection[] selections =
        [
            .. Nodes
                .Select(node => new CategorySelection(
                    node.CategoryId,
                    [.. node.Paths.Where(p => p.IsSelected).SelectMany(p => p.Items)]))
                .Where(s => s.Items.Count > 0),
        ];

        CleanReport report = await _services.Clean.CleanAsync(selections, null, CancellationToken.None);

        _main.GoTo(new DoneStepViewModel(_services, _main, report));
    }

    [RelayCommand]
    private void Back() => _main.StartOver();
}
```

- [ ] **Step 2: Creare la vista**

`src/MjmCleaner.App/Views/ConfirmStepView.axaml`:

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
             x:Class="MjmCleaner.App.Views.ConfirmStepView"
             x:DataType="vm:ConfirmStepViewModel">

    <DockPanel>
        <StackPanel DockPanel.Dock="Top" Spacing="4" Margin="0,0,0,12">
            <TextBlock Text="1 Scegli › 2 Analizza › 3 · Conferma › 4 Fatto" Opacity="0.6" FontSize="12" />
            <TextBlock Text="Verifica prima di eliminare" FontSize="22" FontWeight="Bold" />
            <TextBlock Text="{Binding TotalText}" Opacity="0.75" />
        </StackPanel>

        <StackPanel DockPanel.Dock="Bottom" Spacing="10" Margin="0,12,0,0">
            <Border Padding="10"
                    CornerRadius="6"
                    BorderThickness="1"
                    BorderBrush="{DynamicResource SystemControlForegroundBaseMediumBrush}">
                <TextBlock TextWrapping="Wrap"
                           FontWeight="SemiBold"
                           Text="Eliminazione definitiva: questi file non finiscono nel Cestino e non sono recuperabili." />
            </Border>

            <TextBlock Text="{Binding RunningAppsWarning}"
                       IsVisible="{Binding RunningAppsWarning, Converter={x:Static StringConverters.IsNotNullOrEmpty}}"
                       Opacity="0.7" FontSize="12" TextWrapping="Wrap" />

            <TextBlock Text="{Binding ExclusionsText}"
                       IsVisible="{Binding ExclusionsText, Converter={x:Static StringConverters.IsNotNullOrEmpty}}"
                       Opacity="0.7" FontSize="11" TextWrapping="Wrap" />

            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Spacing="10">
                <Button Content="← Indietro" Command="{Binding BackCommand}" />
                <Button Content="{Binding TotalText, StringFormat='Elimina {0}'}"
                        Command="{Binding DeleteCommand}"
                        Padding="18,8"
                        FontWeight="Bold" />
            </StackPanel>
        </StackPanel>

        <ScrollViewer>
            <ItemsControl ItemsSource="{Binding Nodes}">
                <ItemsControl.ItemTemplate>
                    <DataTemplate DataType="vm:CategoryNode">
                        <Expander Header="{Binding DisplayName}" IsExpanded="True" Margin="0,0,0,8">
                            <ItemsControl ItemsSource="{Binding Paths}">
                                <ItemsControl.ItemTemplate>
                                    <DataTemplate DataType="vm:PathNode">
                                        <Grid ColumnDefinitions="Auto,*,Auto,Auto" Margin="6,3">
                                            <CheckBox Grid.Column="0" IsChecked="{Binding IsSelected}" />
                                            <TextBlock Grid.Column="1"
                                                       Text="{Binding Path}"
                                                       VerticalAlignment="Center"
                                                       TextTrimming="CharacterEllipsis" />
                                            <TextBlock Grid.Column="2"
                                                       Text="{Binding CountText}"
                                                       Opacity="0.55"
                                                       Margin="10,0"
                                                       VerticalAlignment="Center" />
                                            <TextBlock Grid.Column="3"
                                                       Text="{Binding SizeText}"
                                                       FontWeight="SemiBold"
                                                       VerticalAlignment="Center" />
                                        </Grid>
                                    </DataTemplate>
                                </ItemsControl.ItemTemplate>
                            </ItemsControl>
                        </Expander>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>
    </DockPanel>
</UserControl>
```

`src/MjmCleaner.App/Views/ConfirmStepView.axaml.cs`: come le precedenti, classe `ConfirmStepView`.

L'albero si ferma ai percorsi: elencare centinaia di migliaia di file sarebbe illeggibile e lentissimo da disegnare.

- [ ] **Step 3: Registrare il modello di dati**

In `App.axaml`:

```xml
<DataTemplate DataType="vm:ConfirmStepViewModel"><views:ConfirmStepView /></DataTemplate>
```

Rimuovere il commento temporaneo introdotto al Task 18, Step 4, se ancora presente.

- [ ] **Step 4: Verificare a mano**

Il passo 4 non esiste ancora: commentare temporaneamente `_main.GoTo(new DoneStepViewModel(...))`.

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet run --project src/MjmCleaner.App
```
Atteso: dopo l'analisi compaiono le categorie espandibili con i percorsi e le dimensioni; deselezionando un percorso il totale in alto e l'etichetta del pulsante calano; deselezionando tutto il pulsante si disabilita. **Non premere ancora Elimina.**

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.App
git commit -m "feat: add wizard step 3 with preview, exclusions and warnings"
```

---

## Task 20: Passo 4 — Fatto, con salvataggio dello storico

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/DoneStepViewModel.cs`
- Create: `src/MjmCleaner.App/Views/DoneStepView.axaml` (+ `.axaml.cs`)
- Modify: `src/MjmCleaner.App/App.axaml`

**Interfaces:**
- Consumes: `CleanReport` (Task 11), `IHistoryStore` (Task 12), `ISessionLogWriter` (Task 13)
- Produces: `DoneStepViewModel(AppServices, MainWindowViewModel, CleanReport)` con `FreedText`, `SummaryText`, `ErrorsText`, `HistoryWarning` e comando `NewCleanup`

- [ ] **Step 1: Creare il ViewModel**

`src/MjmCleaner.App/ViewModels/DoneStepViewModel.cs`:

```csharp
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.App.ViewModels;

public sealed partial class DoneStepViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;
    private readonly CleanReport _report;

    [ObservableProperty]
    private string _historyWarning = string.Empty;

    public DoneStepViewModel(AppServices services, MainWindowViewModel main, CleanReport report)
    {
        _services = services;
        _main = main;
        _report = report;

        FreedText = $"{FormatBytes(report.BytesFreed)} liberati";
        SummaryText = $"in {report.Duration.TotalSeconds:0} secondi · {report.ItemsDeleted:N0} elementi eliminati";

        Rows = [.. report.Categories
            .Where(c => c.ItemsDeleted > 0)
            .Select(c => $"{c.CategoryId} — {FormatBytes(c.BytesFreed)}")];

        ErrorsText = report.ItemsFailed == 0
            ? string.Empty
            : $"{report.ItemsFailed} elementi non eliminati. {DescribeErrors(report.Errors)}";

        _ = PersistAsync();
    }

    public string FreedText { get; }
    public string SummaryText { get; }
    public string ErrorsText { get; }
    public ObservableCollection<string> Rows { get; }

    /// <summary>
    /// Se la scrittura dello storico fallisce la pulizia è comunque avvenuta:
    /// va detto, senza far credere che non abbia cancellato nulla.
    /// </summary>
    private async Task PersistAsync()
    {
        try
        {
            long sessionId = await _services.History.SaveAsync(_report, CancellationToken.None);
            await _services.SessionLog.WriteAsync(sessionId, _report, CancellationToken.None);
            await _main.RefreshTotalAsync();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or Microsoft.Data.Sqlite.SqliteException)
        {
            HistoryWarning = "Pulizia completata, storico non aggiornato: " + ex.Message;
        }
    }

    private static string DescribeErrors(IReadOnlyList<ScanError> errors)
    {
        if (errors.Any(e => e.Kind == ScanErrorKind.AccessDenied))
        {
            return "Alcuni richiedono l'Accesso completo al disco: " +
                   "Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco.";
        }

        return errors.Any(e => e.Kind == ScanErrorKind.InUse)
            ? "Alcuni erano in uso da applicazioni aperte."
            : "Dettagli nel log della sessione.";
    }

    [RelayCommand]
    private void NewCleanup() => _main.StartOver();
}
```

- [ ] **Step 2: Creare la vista**

`src/MjmCleaner.App/Views/DoneStepView.axaml`:

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
             x:Class="MjmCleaner.App.Views.DoneStepView"
             x:DataType="vm:DoneStepViewModel">

    <DockPanel>
        <TextBlock DockPanel.Dock="Top"
                   Text="1 Scegli › 2 Analizza › 3 Conferma › 4 · Fatto"
                   Opacity="0.6" FontSize="12" Margin="0,0,0,16" />

        <StackPanel DockPanel.Dock="Bottom" Spacing="10" Margin="0,16,0,0">
            <TextBlock Text="{Binding ErrorsText}"
                       IsVisible="{Binding ErrorsText, Converter={x:Static StringConverters.IsNotNullOrEmpty}}"
                       Opacity="0.7" FontSize="12" TextWrapping="Wrap" />
            <TextBlock Text="{Binding HistoryWarning}"
                       IsVisible="{Binding HistoryWarning, Converter={x:Static StringConverters.IsNotNullOrEmpty}}"
                       Opacity="0.7" FontSize="12" TextWrapping="Wrap" />
            <Button Content="Nuova pulizia"
                    Command="{Binding NewCleanupCommand}"
                    HorizontalAlignment="Right"
                    Padding="18,8" />
        </StackPanel>

        <StackPanel Spacing="14">
            <StackPanel HorizontalAlignment="Center" Spacing="2">
                <TextBlock Text="{Binding FreedText}" FontSize="32" FontWeight="Bold" HorizontalAlignment="Center" />
                <TextBlock Text="{Binding SummaryText}" Opacity="0.6" HorizontalAlignment="Center" />
            </StackPanel>

            <ItemsControl ItemsSource="{Binding Rows}">
                <ItemsControl.ItemTemplate>
                    <DataTemplate>
                        <TextBlock Text="{Binding}" Margin="0,3" />
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </StackPanel>
    </DockPanel>
</UserControl>
```

`src/MjmCleaner.App/Views/DoneStepView.axaml.cs`: come le precedenti, classe `DoneStepView`.

- [ ] **Step 3: Registrare il modello di dati**

In `App.axaml`:

```xml
<DataTemplate DataType="vm:DoneStepViewModel"><views:DoneStepView /></DataTemplate>
```

Rimuovere il commento temporaneo introdotto al Task 19, Step 4.

- [ ] **Step 4: Prima pulizia reale, su un bersaglio innocuo**

**Non provare con le cache di sistema.** Preparare un bersaglio finto e configurarlo come root di progetto:

```bash
mkdir -p /tmp/mjm-prova/app/bin /tmp/mjm-prova/app/obj
printf '<Project/>' > /tmp/mjm-prova/app/app.csproj
dd if=/dev/zero of=/tmp/mjm-prova/app/bin/grosso.bin bs=1m count=20
```

Aggiungere `/tmp/mjm-prova` a `ProjectRoots` in `~/Library/Application Support/mjm.cleaner/settings.json` (le impostazioni hanno interfaccia dal Task 21), riavviare l'applicazione, selezionare **solo** *Cartelle bin e obj nei progetti*, analizzare, confermare ed eliminare.

Atteso: il passo 4 mostra circa «20 MB liberati»; `/tmp/mjm-prova/app/bin` non esiste più; `/tmp/mjm-prova/app/app.csproj` è intatto; il totale in barra strumenti passa a 20 MB; esiste un file in `~/Library/Application Support/mjm.cleaner/logs/`.

Verificare il contenuto del log:

```bash
gunzip -c ~/Library/Application\ Support/mjm.cleaner/logs/session-000001.jsonl.gz | head
```

- [ ] **Step 5: Commit**

```bash
git add src/MjmCleaner.App
git commit -m "feat: add wizard step 4 with history persistence"
```

---

## Task 21: Storico e Impostazioni

**Files:**
- Create: `src/MjmCleaner.App/ViewModels/HistoryViewModel.cs`
- Create: `src/MjmCleaner.App/ViewModels/SettingsViewModel.cs`
- Create: `src/MjmCleaner.App/Views/HistoryView.axaml` (+ `.axaml.cs`)
- Create: `src/MjmCleaner.App/Views/SettingsView.axaml` (+ `.axaml.cs`)
- Modify: `src/MjmCleaner.App/ViewModels/MainWindowViewModel.cs`, `src/MjmCleaner.App/Views/MainWindow.axaml`, `src/MjmCleaner.App/App.axaml`

**Interfaces:**
- Consumes: `IHistoryStore` (Task 12), `ISettingsStore` (Task 5)
- Produces: `HistoryViewModel(AppServices, MainWindowViewModel)`, `SettingsViewModel(AppServices, MainWindowViewModel)`; comandi `ShowHistory` e `ShowSettings` su `MainWindowViewModel`

- [ ] **Step 1: Creare `HistoryViewModel`**

`src/MjmCleaner.App/ViewModels/HistoryViewModel.cs`:

```csharp
using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.History;

namespace MjmCleaner.App.ViewModels;

public sealed class HistoryRow(CleanSessionSummary session)
{
    /// <summary>I timestamp sono salvati in UTC e resi in ora locale: altrimenti il cambio d'ora riordina lo storico.</summary>
    public string When { get; } = session.StartedAtUtc.ToLocalTime().ToString("dd/MM/yyyy HH:mm");

    public string Freed { get; } = ViewModelBase.FormatBytes(session.BytesFreed);
    public string Items { get; } = $"{session.ItemsDeleted:N0} elementi";
    public string Categories { get; } = string.Join(", ", session.Categories.Select(c => c.CategoryId));
    public string Failed { get; } = session.ItemsFailed == 0 ? string.Empty : $"{session.ItemsFailed} falliti";
}

public sealed partial class HistoryViewModel : ViewModelBase
{
    private readonly MainWindowViewModel _main;

    public HistoryViewModel(AppServices services, MainWindowViewModel main)
    {
        _main = main;
        _ = LoadAsync(services);
    }

    public ObservableCollection<HistoryRow> Rows { get; } = [];

    private async Task LoadAsync(AppServices services)
    {
        IReadOnlyList<CleanSessionSummary> sessions =
            await services.History.GetSessionsAsync(50, CancellationToken.None);

        foreach (CleanSessionSummary session in sessions)
        {
            Rows.Add(new HistoryRow(session));
        }
    }

    [RelayCommand]
    private void Close() => _main.StartOver();
}
```

- [ ] **Step 2: Creare `SettingsViewModel`**

`src/MjmCleaner.App/ViewModels/SettingsViewModel.cs`:

```csharp
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using MjmCleaner.App.Services;
using MjmCleaner.Core.Settings;

namespace MjmCleaner.App.ViewModels;

public sealed partial class SettingsViewModel : ViewModelBase
{
    private readonly AppServices _services;
    private readonly MainWindowViewModel _main;

    [ObservableProperty] private string _projectRoots;
    [ObservableProperty] private string _largeFileRoots;
    [ObservableProperty] private int _largeFileThresholdMegabytes;
    [ObservableProperty] private int _downloadsMinAgeDays;
    [ObservableProperty] private int _logsMinAgeDays;
    [ObservableProperty] private int _nuGetMinAgeDays;

    public SettingsViewModel(AppServices services, MainWindowViewModel main)
    {
        _services = services;
        _main = main;

        CleanerSettings settings = services.Settings.Load();
        _projectRoots = string.Join(Environment.NewLine, settings.ProjectRoots);
        _largeFileRoots = string.Join(Environment.NewLine, settings.LargeFileRoots);
        _largeFileThresholdMegabytes = (int)(settings.LargeFileThresholdBytes / (1024 * 1024));
        _downloadsMinAgeDays = settings.DownloadsMinAgeDays;
        _logsMinAgeDays = settings.LogsMinAgeDays;
        _nuGetMinAgeDays = settings.NuGetMinAgeDays;
    }

    [RelayCommand]
    private void Save()
    {
        CleanerSettings settings = _services.Settings.Load() with
        {
            ProjectRoots = SplitLines(ProjectRoots),
            LargeFileRoots = SplitLines(LargeFileRoots),
            LargeFileThresholdBytes = Math.Max(1, LargeFileThresholdMegabytes) * 1024L * 1024L,
            DownloadsMinAgeDays = Math.Max(0, DownloadsMinAgeDays),
            LogsMinAgeDays = Math.Max(0, LogsMinAgeDays),
            NuGetMinAgeDays = Math.Max(0, NuGetMinAgeDays),
        };

        _services.Settings.Save(settings);
        _main.StartOver();
    }

    [RelayCommand]
    private void Cancel() => _main.StartOver();

    private static string[] SplitLines(string text)
        => [.. text
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)];
}
```

- [ ] **Step 3: Creare le viste**

`src/MjmCleaner.App/Views/HistoryView.axaml`:

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
             x:Class="MjmCleaner.App.Views.HistoryView"
             x:DataType="vm:HistoryViewModel">

    <DockPanel>
        <TextBlock DockPanel.Dock="Top" Text="Storico delle pulizie" FontSize="22" FontWeight="Bold" Margin="0,0,0,14" />
        <Button DockPanel.Dock="Bottom" Content="Chiudi" Command="{Binding CloseCommand}"
                HorizontalAlignment="Right" Margin="0,14,0,0" />

        <ScrollViewer>
            <ItemsControl ItemsSource="{Binding Rows}">
                <ItemsControl.ItemTemplate>
                    <DataTemplate DataType="vm:HistoryRow">
                        <Grid ColumnDefinitions="Auto,Auto,*,Auto" Margin="0,6">
                            <TextBlock Grid.Column="0" Text="{Binding When}" Width="130" />
                            <TextBlock Grid.Column="1" Text="{Binding Freed}" Width="90" FontWeight="SemiBold" />
                            <TextBlock Grid.Column="2" Text="{Binding Categories}" Opacity="0.6" TextTrimming="CharacterEllipsis" />
                            <TextBlock Grid.Column="3" Text="{Binding Items}" Opacity="0.6" />
                        </Grid>
                    </DataTemplate>
                </ItemsControl.ItemTemplate>
            </ItemsControl>
        </ScrollViewer>
    </DockPanel>
</UserControl>
```

`src/MjmCleaner.App/Views/SettingsView.axaml`:

```xml
<UserControl xmlns="https://github.com/avaloniaui"
             xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
             xmlns:vm="clr-namespace:MjmCleaner.App.ViewModels"
             x:Class="MjmCleaner.App.Views.SettingsView"
             x:DataType="vm:SettingsViewModel">

    <DockPanel>
        <TextBlock DockPanel.Dock="Top" Text="Impostazioni" FontSize="22" FontWeight="Bold" Margin="0,0,0,14" />

        <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" HorizontalAlignment="Right"
                    Spacing="10" Margin="0,14,0,0">
            <Button Content="Annulla" Command="{Binding CancelCommand}" />
            <Button Content="Salva" Command="{Binding SaveCommand}" Padding="18,8" FontWeight="SemiBold" />
        </StackPanel>

        <ScrollViewer>
            <StackPanel Spacing="14">
                <StackPanel Spacing="4">
                    <TextBlock Text="Cartelle di progetto per bin e obj (una per riga)" FontWeight="SemiBold" />
                    <TextBox Text="{Binding ProjectRoots}" AcceptsReturn="True" Height="80" />
                </StackPanel>

                <StackPanel Spacing="4">
                    <TextBlock Text="Cartelle in cui cercare file grandi (una per riga)" FontWeight="SemiBold" />
                    <TextBox Text="{Binding LargeFileRoots}" AcceptsReturn="True" Height="60" />
                </StackPanel>

                <Grid ColumnDefinitions="*,*" RowDefinitions="Auto,Auto" ColumnSpacing="14" RowSpacing="10">
                    <StackPanel Grid.Row="0" Grid.Column="0" Spacing="4">
                        <TextBlock Text="Soglia file grandi (MB)" />
                        <NumericUpDown Value="{Binding LargeFileThresholdMegabytes}" Minimum="1" Maximum="100000" />
                    </StackPanel>
                    <StackPanel Grid.Row="0" Grid.Column="1" Spacing="4">
                        <TextBlock Text="Età minima Download (giorni)" />
                        <NumericUpDown Value="{Binding DownloadsMinAgeDays}" Minimum="0" Maximum="3650" />
                    </StackPanel>
                    <StackPanel Grid.Row="1" Grid.Column="0" Spacing="4">
                        <TextBlock Text="Età minima log (giorni)" />
                        <NumericUpDown Value="{Binding LogsMinAgeDays}" Minimum="0" Maximum="3650" />
                    </StackPanel>
                    <StackPanel Grid.Row="1" Grid.Column="1" Spacing="4">
                        <TextBlock Text="Età minima pacchetti NuGet (giorni)" />
                        <NumericUpDown Value="{Binding NuGetMinAgeDays}" Minimum="0" Maximum="3650" />
                    </StackPanel>
                </Grid>

                <TextBlock Opacity="0.6" FontSize="11" TextWrapping="Wrap"
                           Text="L'età dei pacchetti NuGet si basa sull'ultimo accesso registrato dal filesystem: è un'euristica, non una certezza." />
            </StackPanel>
        </ScrollViewer>
    </DockPanel>
</UserControl>
```

I rispettivi `.axaml.cs` seguono il modello dei task precedenti, con classi `HistoryView` e `SettingsView`.

- [ ] **Step 4: Collegare la barra strumenti**

In `MainWindowViewModel`, aggiungere:

```csharp
    [RelayCommand]
    private void ShowHistory() => CurrentPage = new HistoryViewModel(_services, this);

    [RelayCommand]
    private void ShowSettings() => CurrentPage = new SettingsViewModel(_services, this);
```

In `MainWindow.axaml`, sostituire i due pulsanti disabilitati con:

```xml
                <StackPanel Grid.Column="2" Orientation="Horizontal" Spacing="8">
                    <Button Content="Storico" Command="{Binding ShowHistoryCommand}" />
                    <Button Content="Impostazioni" Command="{Binding ShowSettingsCommand}" />
                </StackPanel>
```

In `App.axaml`, aggiungere:

```xml
<DataTemplate DataType="vm:HistoryViewModel"><views:HistoryView /></DataTemplate>
<DataTemplate DataType="vm:SettingsViewModel"><views:SettingsView /></DataTemplate>
```

- [ ] **Step 5: Verificare a mano**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet run --project src/MjmCleaner.App
```
Atteso: *Storico* mostra la pulizia di prova del Task 20 con data in ora locale e «20 MB»; *Impostazioni* mostra `/tmp/mjm-prova` fra le cartelle di progetto; cambiare l'età minima dei log, salvare, riaprire le impostazioni e verificare che il valore sia rimasto.

- [ ] **Step 6: Commit**

```bash
git add src/MjmCleaner.App
git commit -m "feat: add history and settings pages"
```

---

## Task 22: Verifica complessiva, confezionamento e documentazione

**Files:**
- Create: `README.md` (sostituisce il segnaposto attuale)
- Modify: `docs/superpowers/spikes/2026-09-15-full-disk-access.md`

**Interfaces:**
- Consumes: tutto
- Produces: applicazione confezionata e verificata; documentazione d'uso

- [ ] **Step 1: Eseguire l'intera suite di test**

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test
```
Atteso: tutti i test passano. Riportare il numero effettivo di test eseguiti; non dichiarare il lavoro concluso senza aver visto questo esito.

- [ ] **Step 2: Confezionare e provare il bundle**

```bash
./build/bundle.sh
open artifacts/mjm.cleaner.app
```
Se compaiono errori di accesso negato, concedere l'Accesso completo al disco a `artifacts/mjm.cleaner.app` in *Impostazioni di Sistema → Privacy e sicurezza*, quindi riavviare l'applicazione.

- [ ] **Step 3: Percorso completo su bersaglio reale ma innocuo**

Selezionare **solo** *Log e crash report*, analizzare, esaminare l'anteprima, eliminare. Verificare al passo 4 che lo spazio liberato sia coerente e che il totale in barra strumenti sia cresciuto della stessa quantità.

Poi provare la protezione: in *Impostazioni*, inserire `/` fra le cartelle di progetto, salvare, selezionare *Cartelle bin e obj nei progetti* e analizzare.

Atteso: **nessun elemento proposto sotto percorsi protetti**; eventuali candidati compaiono nel riquadro delle esclusioni del passo 3. Se anche un solo elemento sotto `/System`, `/usr` o `/Applications` viene proposto per l'eliminazione, **fermarsi**: è un difetto del `PathGuard`, da riprodurre con un test prima di qualunque altra modifica. Rimuovere `/` dalle impostazioni al termine della prova.

- [ ] **Step 4: Aggiornare le conclusioni dello spike**

Integrare in `docs/superpowers/spikes/2026-09-15-full-disk-access.md` il comportamento osservato dal bundle: quali percorsi hanno richiesto il permesso e se questo è sopravvissuto a una ricompilazione seguita da un nuovo `bundle.sh`.

- [ ] **Step 5: Scrivere il README**

`README.md`:

````markdown
# mjm.cleaner

Applicazione macOS per eliminare file temporanei rigenerabili, con anteprima
obbligatoria, storico delle pulizie e contatore cumulativo dello spazio liberato.

## Requisiti

- macOS 13 o successivo
- .NET 10 SDK (su questa macchina: `/usr/local/share/dotnet`)

## Sviluppo

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test                              # suite completa
dotnet run --project src/MjmCleaner.App  # avvio in sviluppo
./build/bundle.sh                        # crea artifacts/mjm.cleaner.app
```

## Come funziona

Wizard a quattro passi: scegli le categorie, analizza, verifica l'anteprima,
elimina. Lo storico è in `~/Library/Application Support/mjm.cleaner/history.db`,
l'elenco completo dei percorsi eliminati nelle ultime 20 sessioni in `logs/`
nella stessa cartella.

## Avvertenze

- **L'eliminazione è definitiva:** i file non passano dal Cestino. L'anteprima del
  passo 3 elenca i percorsi esatti; il `PathGuard` blocca comunque i percorsi protetti.
- **Full Disk Access:** alcune categorie lo richiedono. Concederlo al bundle in
  *Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco*.
  Dopo una ricompilazione può essere necessario riconcederlo.
- **Nessuna elevazione di privilegi:** gli elementi di proprietà di `root`
  falliscono con accesso negato e compaiono nel riepilogo finale.
- **Docker non viene toccato:** lo spazio si recupera con `docker system prune`.

## Documentazione

- Specifica: `docs/superpowers/specs/2026-09-15-mjm-cleaner-design.md`
- Piano di implementazione: `docs/superpowers/plans/2026-09-15-mjm-cleaner.md`
````

- [ ] **Step 6: Commit finale**

```bash
git add README.md docs/
git commit -m "docs: add README and finalise full disk access findings"
```

---

## Copertura della specifica

| Sezione della specifica | Task |
|---|---|
| 3 — Stack tecnico | 1, 15 |
| 4 — Architettura e flusso | 1, 10, 11, 16 |
| 5 — Modello delle categorie | 7 |
| 6.1-6.5 — Le cinque categorie | 7 (definizione), 8-9 (esecuzione) |
| 7 — Motore di scansione | 8, 9, 10 |
| 8 — PathGuard | 3, 4 |
| 9 — Storico e contatore | 12, 13 |
| 10 — Interfaccia | 16, 17, 18, 19, 20, 21 |
| 11 — Gestione degli errori | 8 (classificazione), 11 (isolamento), 20 (resa) |
| 12 — Strategia di test | 3-14 (unità), 12 (integrazione), 17-22 (manuale) |
| 13 — Spike | 2 (accesso), 15 (bundle) |
| 14 — Fuori ambito | nessun task: deliberatamente escluso |
