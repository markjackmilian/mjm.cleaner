using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

/// <summary>
/// Il caso reale da cui è nata la funzione: due container fermi (exit code 137) di SQL Server e
/// di Azurite avviati da un AppHost Aspire, più le immagini e i volumi che si erano accumulati
/// attorno. Gli ID di mssql 2025, azurite, dcptun e azurelinux sono quelli misurati; gli altri
/// sono fittizi ma nella stessa forma (sha256 di 64 caratteri esadecimali).
/// </summary>
internal static class DockerFixtures
{
    public const string Mssql2025Id = "sha256:2b5b581621126574f3d1f75e78d3eebe8d05aedb59ad0cfdf9aa42cb0634d726";
    public const string AzuriteId = "sha256:647c63a91102a9d8e8000aab803436e1fc85fbb285e7ce830a82ee5d6661cf37";
    public const string DcptunId = "sha256:c1a077005187d683004cabff17b02f174db19515ec56327f38d8e3d7e2e8c04a";
    public const string AzureLinuxId = "sha256:34a22db497ff34a0f35ca5fc54bd38711d04238a2c1b2f65d35dc9d45dd82584";
    public static readonly string Mssql2022Id = Fake("a1");
    public static readonly string KeycloakId = Fake("b2");
    public static readonly string MssqlToolsId = Fake("c3");
    public static readonly string AlpineId = Fake("d4");
    public static readonly string RyukId = Fake("e5");
    public static readonly string LocalBuildId = Fake("f6");

    public const string AnonymousVolume = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    public static string Read(string name)
        => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Docker", "Fixtures", name));

    public static DockerSnapshot Snapshot(IReadOnlySet<string>? existingComposeProjects = null)
    {
        DockerDfVerbose verbose = DockerJson.ParseDfVerbose(Read("df-verbose.json"));

        return new DockerSnapshot(
            DockerJson.ParseContainers(Read("containers.json")),
            DockerJson.ParseImages(Read("images.json"), verbose.ImageUniqueSizes),
            DockerJson.ParseVolumes(Read("volumes.json"), verbose.VolumeSizes),
            DockerJson.ParseDfSummary(Read("df.jsonl")),
            existingComposeProjects ?? new HashSet<string>());
    }

    private static string Fake(string pair) => "sha256:" + string.Concat(Enumerable.Repeat(pair, 32));
}
