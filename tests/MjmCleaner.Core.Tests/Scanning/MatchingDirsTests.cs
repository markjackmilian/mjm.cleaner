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

    // IMPORTANT 1 della revisione del Task 9: un nome che corrisponde a ExcludeGlobs veniva
    // trattato come un semplice mancato match ("continua a cercare più in basso") invece che
    // come un rifiuto esplicito, e la ricorsione scendeva dentro il ramo escluso — proponendo la
    // singola versione di un pacchetto NuGet esplicitamente escluso invece del pacchetto intero,
    // l'esito che questo task esiste per impedire.
    [Fact]
    public void ExcludedDirectoryIsSkippedEntirelyInsteadOfBeingTraversed()
    {
        MockFileSystem fs = new();
        string nuget = $"{Home}/.nuget/packages";
        fs.AddFile($"{nuget}/escluso.pacchetto/1.0.0/lib/a.dll", new MockFileData(new byte[10]));
        fs.AddFile($"{nuget}/normale/1.0.0/lib/b.dll", new MockFileData(new byte[20]));

        CleanupRule rule = new(nuget, ScanMode.MatchingDirs, ["*"], ["escluso.*"], MaxDepth: 1);
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Equal($"{nuget}/normale", outcome.Items.Single().Path);
        Assert.DoesNotContain(outcome.Items, i => i.Path.Contains("escluso"));
    }

    // IMPORTANT 2 della revisione del Task 9: nessun test copriva la potatura della deny-list in
    // questa modalità — un refactor capace di rimuovere la chiamata a ShouldPrune sarebbe passato
    // comunque. Root = "~/Library", con una sottocartella protetta (Keychains, contenente a sua
    // volta un "bin" che altrimenti verrebbe trovato e nominato per intero in un'esclusione per
    // elemento) e una ordinaria (Caches), per isolare l'effetto della potatura. I nomi dei globi
    // ("bin") non corrispondono a "Keychains"/"Caches" stessi, quindi il match avviene solo più
    // in profondità: questo esercita il ramo "non corrisponde, quindi pota o ricorri", non il
    // ramo "corrisponde ma il guard nega" (coperto a parte).
    [Fact]
    public void PrunesDeniedBranchWithoutDescendingIntoIt()
    {
        MockFileSystem fs = new();
        string library = $"{Home}/Library";
        fs.AddFile($"{library}/Keychains/bin/segreto.pfx", new MockFileData(new byte[10]));
        fs.AddFile($"{library}/Caches/proj/bin/output.dll", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(library, ScanMode.MatchingDirs, ["bin"], []),
            CancellationToken.None);

        Assert.Equal($"{library}/Keychains", outcome.Exclusions.Single().Path);
        Assert.DoesNotContain(outcome.Exclusions, e => e.Path.Contains("bin") || e.Path.Contains("segreto"));
        Assert.DoesNotContain(outcome.Errors, e => e.Path.Contains("segreto"));
        Assert.DoesNotContain(outcome.Items, i => i.Path.Contains("Keychains"));
        Assert.Contains(outcome.Items, i => i.Path == $"{library}/Caches/proj/bin");
    }

    // Complemento del test precedente: una directory che CORRISPONDE ma che il guard respinge
    // (qui perché il nome incluso coincide con un percorso della deny-list) deve diventare
    // un'esclusione, non un elemento — e la ricorsione, come per ogni corrispondenza, non deve
    // proseguire al suo interno.
    [Fact]
    public void MatchedDirectoryRejectedByGuardBecomesAnExclusionNotAnItem()
    {
        MockFileSystem fs = new();
        string library = $"{Home}/Library";
        fs.AddFile($"{library}/Keychains/login.keychain", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(
            new CleanupRule(library, ScanMode.MatchingDirs, ["Keychains"], []),
            CancellationToken.None);

        Assert.Empty(outcome.Items);
        Assert.Contains(outcome.Exclusions, e => e.Path == $"{library}/Keychains");
    }

    // Il filtro di età, per una directory, non è mai ancorato al timestamp del solo contenitore
    // (si veda DirectoryStats): un pacchetto NuGet con la cartella "vecchia" ma un file al suo
    // interno toccato ieri non va proposto, mentre uno con contenitore e contenuto entrambi
    // vecchi sì. È il meccanismo con cui i pacchetti "non usati da N mesi" vengono selezionati.
    [Fact]
    public void HonoursMinAgeUsingTheNewestTimestampInTheTree()
    {
        MockFileSystem fs = new();
        string nuget = $"{Home}/.nuget/packages";
        DateTime oldStamp = Now.UtcDateTime.AddDays(-200);
        DateTime recentStamp = Now.UtcDateTime.AddDays(-1);

        string oldPackage = $"{nuget}/vecchio";
        fs.AddFile($"{oldPackage}/lib.dll", new MockFileData(new byte[10]) { LastWriteTime = oldStamp, LastAccessTime = oldStamp });
        fs.Directory.SetLastWriteTimeUtc(oldPackage, oldStamp);
        fs.Directory.SetLastAccessTimeUtc(oldPackage, oldStamp);

        string recentlyUsedPackage = $"{nuget}/usato_di_recente";
        fs.AddFile($"{recentlyUsedPackage}/lib.dll", new MockFileData(new byte[10]) { LastWriteTime = recentStamp, LastAccessTime = recentStamp });
        fs.Directory.SetLastWriteTimeUtc(recentlyUsedPackage, oldStamp);
        fs.Directory.SetLastAccessTimeUtc(recentlyUsedPackage, oldStamp);

        CleanupRule rule = new(nuget, ScanMode.MatchingDirs, ["*"], [], MinAge: TimeSpan.FromDays(30), MaxDepth: 1);
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Equal(oldPackage, outcome.Items.Single().Path);
    }

    // La dimensione di una directory trovata è la somma ricorsiva su più livelli, non la
    // dimensione di un solo file al suo interno.
    [Fact]
    public void SumsSizeRecursivelyAcrossMultipleLevels()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/app.csproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/app/bin/a.dll", new MockFileData(new byte[100]));
        fs.AddFile($"{Projects}/app/bin/livello1/b.dll", new MockFileData(new byte[50]));
        fs.AddFile($"{Projects}/app/bin/livello1/livello2/c.dll", new MockFileData(new byte[25]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        ScanItem item = outcome.Items.Single();
        Assert.Equal($"{Projects}/app/bin", item.Path);
        Assert.Equal(175, item.SizeBytes);
    }

    // Un sottoalbero illeggibile (permessi negati) durante la somma ricorsiva non azzera il
    // totale della directory trovata e non interrompe la scansione: contribuisce 0 (i suoi
    // contenuti non sono elencabili) e viene registrato come errore sulla propria directory,
    // mentre i rami leggibili continuano a contare normalmente.
    [Fact]
    public void UnreadableSubtreeDoesNotZeroTheTotalNorStopTheScan()
    {
        MockFileSystem mock = new();
        mock.AddFile($"{Projects}/app/app.csproj", new MockFileData("x"));
        mock.AddFile($"{Projects}/app/bin/livello1/a.dll", new MockFileData(new byte[100]));
        mock.AddFile($"{Projects}/app/bin/livello1/livello2/b.dll", new MockFileData(new byte[50]));
        string unreadable = $"{Projects}/app/bin/protetta";
        mock.AddFile($"{unreadable}/c.dll", new MockFileData(new byte[9999]));

        UnreadableDirectoryFileSystem fs = new(mock, unreadable);
        FakeLinkInspector links = new();
        RuleScanner scanner = new(fs, new PathGuard(new DenyList(Home), links, Home), links, new TestTimeProvider(Now));

        RuleScanOutcome outcome = scanner.Scan(BinObjRule(), CancellationToken.None);

        ScanItem item = Assert.Single(outcome.Items);
        Assert.Equal($"{Projects}/app/bin", item.Path);
        Assert.Equal(150, item.SizeBytes);
        Assert.Contains(outcome.Errors, e => e.Path == unreadable && e.Kind == ScanErrorKind.AccessDenied);
    }

    // Minor della revisione del Task 9: MinSizeBytes è applicato nelle altre due modalità ma era
    // ignorato in questa.
    [Fact]
    public void HonoursMinSizeBytes()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/app.csproj", new MockFileData("x"));
        fs.AddFile($"{Projects}/app/bin/grande.dll", new MockFileData(new byte[2000]));
        fs.AddFile($"{Projects}/app/obj/piccolo.bin", new MockFileData(new byte[10]));

        CleanupRule rule = BinObjRule() with { MinSizeBytes = 1000 };
        RuleScanOutcome outcome = Create(fs).Scan(rule, CancellationToken.None);

        Assert.Equal($"{Projects}/app/bin", outcome.Items.Single().Path);
    }

    // Minor della revisione del Task 9: una *directory* chiamata "x.sln" soddisfaceva il vincolo
    // del marcatore di progetto perché il controllo non verificava che il fratello fosse un
    // file — un modo in più di soddisfare il vincolo che esiste per non proporre "/usr/bin".
    [Fact]
    public void ProjectMarkerMustBeAFileNotADirectory()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{Projects}/app/x.sln/nota.txt", new MockFileData("x"));
        fs.AddFile($"{Projects}/app/bin/output.dll", new MockFileData(new byte[10]));

        RuleScanOutcome outcome = Create(fs).Scan(BinObjRule(), CancellationToken.None);

        Assert.Empty(outcome.Items);
    }
}
