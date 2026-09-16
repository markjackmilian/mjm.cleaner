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

        // Dimensione dichiarata falsa: l'elemento esiste davvero, ma con un contenuto molto più
        // piccolo di quanto SizeBytes affermi. Il resoconto deve riportare i byte MISURATI subito
        // prima della cancellazione, non quelli dichiarati dall'interfaccia: un contatore che
        // somma le intenzioni diventa decorativo in un mese.
        MockFileSystem fsLied = new();
        fsLied.AddFile($"{CacheRoot}/piccola/dentro/x.bin", new MockFileData(new byte[10]));

        CleanReport liedReport = await Create(fsLied).CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/piccola", 5_000_000_000, true, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.False(fsLied.Directory.Exists($"{CacheRoot}/piccola"));
        Assert.Equal(10, liedReport.BytesFreed);
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

    // CRITICAL: l'elenco arriva dall'interfaccia dopo la conferma dell'utente, quindi è
    // manipolabile. Una DeclaredRoot fabbricata che è in realtà un collegamento verso una
    // cartella protetta deve fallire alla convalida della ROOT (ValidateRoot), non a quella
    // del singolo elemento: Validate da sola non vede che il genitore diretto dell'elemento è
    // un collegamento, perché il suo ciclo si ferma proprio alla root senza eseguire alcuna
    // iterazione quando la root È il genitore diretto — il caso di ogni elemento ClearContents.
    [Fact]
    public async Task FabricatedDeclaredRootResolvingToProtectedPathIsRejected()
    {
        string fakeRoot = $"{CacheRoot}/finto";
        MockFileSystem fs = new();
        fs.AddFile($"{fakeRoot}/contratto.pdf", new MockFileData(new byte[10]));

        CleanEngine engine = new(
            fs,
            new PathGuard(
                new DenyList(Home),
                new FakeLinkInspector(new Dictionary<string, string?> { [fakeRoot] = $"{Home}/Documents" }),
                Home),
            new TestTimeProvider(Now));

        CleanReport report = await engine.CleanAsync(
            [Selection("bug", new ScanItem($"{fakeRoot}/contratto.pdf", 10, false, fakeRoot))],
            progress: null,
            CancellationToken.None);

        Assert.True(fs.File.Exists($"{fakeRoot}/contratto.pdf"));
        Assert.Equal(0, report.BytesFreed);
        Assert.Equal(1, report.ItemsFailed);
        Assert.Empty(report.DeletedPaths);
    }

    // Stessa fuga, variante con directory: con IsDirectory=true l'eliminazione sarebbe
    // ricorsiva (Directory.Delete(..., recursive: true)), l'esito più costoso possibile se il
    // guard non fermasse tutto alla root.
    [Fact]
    public async Task FabricatedDeclaredRootResolvingToProtectedPathRejectsDirectoryRecursively()
    {
        string fakeRoot = $"{CacheRoot}/finto2";
        MockFileSystem fs = new();
        fs.AddFile($"{fakeRoot}/fatture2026/gennaio.pdf", new MockFileData(new byte[10]));

        CleanEngine engine = new(
            fs,
            new PathGuard(
                new DenyList(Home),
                new FakeLinkInspector(new Dictionary<string, string?> { [fakeRoot] = $"{Home}/Documents" }),
                Home),
            new TestTimeProvider(Now));

        CleanReport report = await engine.CleanAsync(
            [Selection("bug", new ScanItem($"{fakeRoot}/fatture2026", 10, true, fakeRoot))],
            progress: null,
            CancellationToken.None);

        Assert.True(fs.Directory.Exists($"{fakeRoot}/fatture2026"));
        Assert.Equal(0, report.BytesFreed);
        Assert.Equal(1, report.ItemsFailed);
        Assert.Empty(report.DeletedPaths);
    }

    // Nessuna manipolazione dell'elenco: la DeclaredRoot è quella vera prodotta dallo scanner.
    // Ma fra la scansione e la conferma dell'utente, ~/Library/Caches è stata sostituita con un
    // collegamento verso ~/Documents (es. un tool di sincronizzazione). Il guard viene invocato
    // di nuovo qui, immediatamente prima della cancellazione, apposta per questo scarto
    // temporale: senza richiamare ValidateRoot in CleanEngine, un elemento del tutto legittimo
    // al momento della scansione verrebbe cancellato attraverso il collegamento.
    [Fact]
    public async Task RootReplacedBySymlinkAfterScanRejectsOtherwiseLegitimateItem()
    {
        MockFileSystem fs = new();
        fs.AddFile($"{CacheRoot}/tesi.docx", new MockFileData(new byte[10]));

        CleanEngine engine = new(
            fs,
            new PathGuard(
                new DenyList(Home),
                new FakeLinkInspector(new Dictionary<string, string?> { [CacheRoot] = $"{Home}/Documents" }),
                Home),
            new TestTimeProvider(Now));

        CleanReport report = await engine.CleanAsync(
            [Selection("caches", new ScanItem($"{CacheRoot}/tesi.docx", 10, false, CacheRoot))],
            progress: null,
            CancellationToken.None);

        Assert.True(fs.File.Exists($"{CacheRoot}/tesi.docx"));
        Assert.Equal(0, report.BytesFreed);
        Assert.Equal(1, report.ItemsFailed);
        Assert.Empty(report.DeletedPaths);
    }
}
