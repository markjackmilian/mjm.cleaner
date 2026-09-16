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

    // IMPORTANT 2 della revisione del Task 8: ClearContents ignorava IncludeGlobs, ExcludeGlobs
    // e MinSizeBytes, proponendo elementi che la regola dichiara di conservare.
    [Fact]
    public void ClearContentsHonoursExcludeGlobs()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/normale.tmp", File(10));
        fs.AddFile($"{CacheRoot}/da_conservare.keep", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, ["*.keep"]),
            CancellationToken.None);

        Assert.Equal($"{CacheRoot}/normale.tmp", outcome.Items.Single().Path);
    }

    [Fact]
    public void ClearContentsHonoursMinSize()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/grande.tmp", File(2_000_000));
        fs.AddFile($"{CacheRoot}/piccolo.tmp", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, [], MinSizeBytes: 1_000_000),
            CancellationToken.None);

        Assert.Equal($"{CacheRoot}/grande.tmp", outcome.Items.Single().Path);
    }

    // IMPORTANT 3: in ClearContents il filtro di età guardava il timestamp del solo
    // contenitore, non del contenuto. Su disco vero l'mtime di una directory non cambia quando
    // un file al suo interno viene riscritto sul posto, quindi una directory "vecchia" può
    // contenere un file scritto oggi: l'età va calcolata sul timestamp più recente nell'albero.
    [Fact]
    public void ClearContentsDirectoryAgeReflectsNewestContainedFile()
    {
        MockFileSystem fs = new();
        string dir = $"{CacheRoot}/app";
        fs.AddFile($"{dir}/nuovo.bin", File(10, Now.UtcDateTime.AddDays(-1)));

        DateTime old = Now.UtcDateTime.AddDays(-200);
        fs.Directory.SetLastWriteTimeUtc(dir, old);
        fs.Directory.SetLastAccessTimeUtc(dir, old);

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, [], MinAge: TimeSpan.FromDays(30)),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
    }

    // IMPORTANT 4: MatchingFiles scendeva dentro i rami negati dalla deny-list, producendo
    // un'esclusione per ciascun file privato al loro interno (i cui nomi finiscono così
    // nell'elenco delle esclusioni mostrato all'utente) invece di potare il ramo intero.
    // Root = "~/Library", non la home stessa: contiene sia una sottocartella protetta
    // (Keychains) sia una non protetta (Caches), per isolare l'effetto della potatura.
    [Fact]
    public void MatchingFilesPrunesDeniedBranchWithoutDescendingIntoIt()
    {
        MockFileSystem fs = new();
        string library = $"{Home}/Library";
        fs.AddFile($"{library}/Keychains/login.keychain", File(10));
        fs.AddFile($"{library}/Caches/normale.tmp", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(library, ScanMode.MatchingFiles, All, []),
            CancellationToken.None);

        Assert.Contains(outcome.Exclusions, e => e.Path == $"{library}/Keychains");
        Assert.DoesNotContain(outcome.Exclusions, e => e.Path == $"{library}/Keychains/login.keychain");
        Assert.Equal($"{library}/Caches/normale.tmp", outcome.Items.Single().Path);
    }

    // Test opposto, a protezione dal rischio contrario: un ramo ordinario non va potato, e la
    // ricorsione deve continuare a funzionare normalmente.
    [Fact]
    public void MatchingFilesDoesNotPruneOrdinaryBranches()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/app/sub/file.log", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(CacheRoot, ScanMode.MatchingFiles, All, []),
            CancellationToken.None);

        Assert.Empty(outcome.Exclusions);
        Assert.Equal($"{CacheRoot}/app/sub/file.log", outcome.Items.Single().Path);
    }

    // Minor (caso E2 della revisione): un elemento scomparso fra l'enumerazione e la lettura
    // della dimensione veniva annotato come errore NotFound ma anche aggiunto agli elementi con
    // dimensione zero, comparendo così sia fra gli errori sia fra ciò che si propone di
    // eliminare. Richiede un IFileSystem che simuli davvero la corsa critica: un percorso mai
    // aggiunto al MockFileSystem non verrebbe nemmeno enumerato, e non eserciterebbe il ramo
    // "elencato ma poi introvabile" che questo test deve coprire.
    [Fact]
    public void MatchingFilesDoesNotListAFileThatVanishesBeforeSizeRead()
    {
        MockFileSystem mock = new();
        string logs = $"{Home}/Library/Logs";
        string vanished = $"{logs}/scomparso.log";
        mock.AddFile(vanished, File(10));

        VanishingFileSystem fs = new(mock, vanished);
        FakeLinkInspector links = new();
        RuleScanner scanner = new(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));

        RuleScanOutcome outcome = scanner.Scan(
            new CleanupRule(logs, ScanMode.MatchingFiles, All, []),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
        Assert.Contains(outcome.Errors, e => e.Path == vanished && e.Kind == ScanErrorKind.NotFound);
    }

    // IMPORTANT (re-revisione): root = home con soglia sui file grandi (LargeFileRoots = ["~"]
    // nel catalogo reale) deve continuare a trovare i file legittimi, non restituire zero
    // elementi. Misura anche l'effetto congiunto con la correzione a ValidateRoot: la home come
    // root è ora ammessa (voci a uguaglianza esatta non applicate alle root), e i rami protetti
    // al suo interno vengono comunque potati da ScanFiles (Important 4), non attraversati.
    [Fact]
    public void MatchingFilesFindsLegitimateLargeFilesInHomeWhilePruningProtectedBranches()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Home}/Downloads/installer.dmg", File(2_000_000));
        fs.AddFile($"{Home}/progetti/archivio.zip", File(3_000_000));
        fs.AddFile($"{Home}/Documents/riservato.pdf", File(5_000_000));
        fs.AddFile($"{Home}/.ssh/id_rsa", File(10));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(Home, ScanMode.MatchingFiles, All, [], MinSizeBytes: 1_000_000),
            CancellationToken.None);

        Assert.Equal(2, outcome.Items.Count);
        Assert.Contains(outcome.Items, i => i.Path == $"{Home}/Downloads/installer.dmg");
        Assert.Contains(outcome.Items, i => i.Path == $"{Home}/progetti/archivio.zip");
        Assert.Contains(outcome.Exclusions, e => e.Path == $"{Home}/Documents");
        Assert.Contains(outcome.Exclusions, e => e.Path == $"{Home}/.ssh");
    }

    // Minor (re-revisione): la potatura introdotta per l'Important 4 era stata aggiunta solo a
    // ScanFiles, e il calcolo delle statistiche era stato spostato prima del verdetto del guard
    // in ScanContents — una directory negata veniva quindi attraversata per intero (i percorsi
    // interni illeggibili finiscono fra gli errori mostrati all'utente) e solo dopo esclusa.
    // Verificato con un file che, se letto, produrrebbe un errore: con la correzione, il guard
    // esclude "Keychains" PRIMA di attraversarla, quindi quel file non viene mai toccato.
    [Fact]
    public void ClearContentsValidatesBeforeTraversingADeniedDirectory()
    {
        MockFileSystem mock = new();
        string library = $"{Home}/Library";
        string innerSecret = $"{library}/Keychains/login.keychain";
        mock.AddFile(innerSecret, File(10));
        mock.AddFile($"{library}/Caches/normale.tmp", File(10));

        VanishingFileSystem fs = new(mock, innerSecret);
        FakeLinkInspector links = new();
        RuleScanner scanner = new(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));

        RuleScanOutcome outcome = scanner.Scan(
            new CleanupRule(library, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.DoesNotContain(outcome.Errors, e => e.Path == innerSecret);
        Assert.Contains(outcome.Exclusions, e => e.Path == $"{library}/Keychains");
        Assert.Contains(outcome.Items, i => i.Path == $"{library}/Caches");
    }

    // Minor (re-revisione): DirectoryInfo.LastWriteTimeUtc/LastAccessTimeUtc su una directory
    // scomparsa non lanciano — restituiscono la sentinella "1601-01-01", la data più vecchia
    // possibile, non "indeterminato". Prima della correzione questo faceva apparire la
    // directory antichissima (quindi superava qualunque soglia di età) e, non essendo la
    // deduplicazione estesa alle directory, veniva comunque aggiunta agli elementi mentre lo
    // stesso percorso finiva anche fra gli errori.
    [Fact]
    public void ClearContentsDoesNotListADirectoryThatVanishesBeforeStatsRead()
    {
        MockFileSystem mock = new();
        string vanished = $"{CacheRoot}/scomparsa";
        mock.AddFile($"{vanished}/dentro.bin", File(10));

        VanishingChildFileSystem fs = new(mock, vanished);
        FakeLinkInspector links = new();
        RuleScanner scanner = new(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));

        RuleScanOutcome outcome = scanner.Scan(
            new CleanupRule(CacheRoot, ScanMode.ClearContents, All, []),
            CancellationToken.None);

        Assert.DoesNotContain(outcome.Items, i => i.Path == vanished);
    }

    // IMPORTANT della revisione finale: configurando le cartelle per la ricerca dei file grandi
    // su una directory che contiene repository, la ricorsione entrava in ".git" e proponeva i
    // pack file dell'intera storia del repository, indistinguibili per nome o estensione da un
    // file grande legittimo — una perdita non ricostruibile, perché la cartella ".git"
    // sopravvive alla cancellazione ma la storia no. Misura che il ramo viene saltato per
    // intero, mentre un file grande legittimo accanto al repository continua a comparire.
    [Fact]
    public void MatchingFilesNeverEntersAGitDirectory()
    {
        MockFileSystem fs = new();
        string projects = $"{Home}/projects";
        fs.AddFile($"{projects}/progetto/.git/objects/pack/grosso.pack", File(200_000_000));
        fs.AddFile($"{projects}/progetto/dati.bin", File(100_000_000));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(projects, ScanMode.MatchingFiles, All, [], MinSizeBytes: 50_000_000),
            CancellationToken.None);

        Assert.DoesNotContain(outcome.Items, i => i.Path.Contains(".git"));
        Assert.Contains(outcome.Items, i => i.Path == $"{projects}/progetto/dati.bin");
        Assert.Contains(outcome.Exclusions, e => e.Path == $"{projects}/progetto/.git");
    }

    // Per simmetria: la ricerca per directory (usata per "bin"/"obj" e i pacchetti NuGet) non
    // deve nemmeno considerare ".git" come candidato, né scendervi in cerca di altro.
    [Fact]
    public void MatchingDirsNeverEntersOrMatchesAGitDirectory()
    {
        MockFileSystem fs = new();
        string projects = $"{Home}/projects";
        fs.AddFile($"{projects}/progetto/app.csproj", new MockFileData("<Project/>"));
        fs.AddFile($"{projects}/progetto/bin/app.dll", File(10));
        fs.AddFile($"{projects}/progetto/.git/objects/pack/grosso.pack", File(200_000_000));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(projects, ScanMode.MatchingDirs, ["bin", "obj"], [], RequiresProjectMarker: true),
            CancellationToken.None);

        Assert.DoesNotContain(outcome.Items, i => i.Path.Contains(".git"));
        Assert.Contains(outcome.Items, i => i.Path == $"{projects}/progetto/bin");
        Assert.Contains(outcome.Exclusions, e => e.Path == $"{projects}/progetto/.git");
    }
}
