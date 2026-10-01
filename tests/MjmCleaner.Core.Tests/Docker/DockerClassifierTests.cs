using MjmCleaner.Core.Docker;
using static MjmCleaner.Core.Tests.Docker.DockerFixtures;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerClassifierTests
{
    private static readonly IReadOnlyDictionary<string, string> NoLabels = new Dictionary<string, string>();

    private static IReadOnlyList<DockerCandidate> ClassifyRealCase(ProjectReferences? references = null)
        => DockerClassifier.Classify(Snapshot(), references ?? ProjectReferences.Empty);

    private static DockerCandidate Find(IReadOnlyList<DockerCandidate> candidates, string displayName)
        => candidates.Single(c => c.DisplayName == displayName);

    // --- Il caso reale: l'esito atteso dal brief, risorsa per risorsa -------------------------

    [Theory]
    [InlineData("mcr.microsoft.com/mssql/server:2025-latest", DockerVerdict.Keep, "in-use")]
    [InlineData("mcr.microsoft.com/azure-storage/azurite:3.35.0", DockerVerdict.Keep, "in-use")]
    [InlineData("testcontainers/ryuk:0.14.0", DockerVerdict.Delete, "tool-recreated")]
    [InlineData("dcptun_developer_ms:0.25.13", DockerVerdict.Delete, "tool-recreated")]
    [InlineData("mcr.microsoft.com/azurelinux/base/core:3.0", DockerVerdict.Delete, "tool-recreated")]
    [InlineData("mcr.microsoft.com/mssql/server:2022-latest", DockerVerdict.Propose, "superseded")]
    [InlineData("quay.io/keycloak/keycloak:26.6", DockerVerdict.Propose, "unused")]
    [InlineData("mcr.microsoft.com/mssql-tools:latest", DockerVerdict.Propose, "unused")]
    [InlineData("alpine:3.20", DockerVerdict.Propose, "unused")]
    [InlineData("orbit-api:dev", DockerVerdict.Ask, "locally-built")]
    [InlineData("mssql2025-data", DockerVerdict.Keep, "mounted")]
    [InlineData("orbit.apphost-48d90b1972-storage-data", DockerVerdict.Keep, "mounted")]
    [InlineData("orbit.apphost-48d90b1972-sql-data", DockerVerdict.Keep, "aspire-current")]
    [InlineData("orbit.apphost-48d90b1972-keycloak-data", DockerVerdict.Keep, "aspire-current")]
    [InlineData("orbit.apphost-751ef8e8e6-storage-data", DockerVerdict.Propose, "aspire-stale")]
    [InlineData(AnonymousVolume, DockerVerdict.Propose, "anonymous")]
    public void RealCaseMatchesTheExpectedOutcome(string displayName, DockerVerdict verdict, string ruleId)
    {
        DockerCandidate candidate = Find(ClassifyRealCase(), displayName);

        Assert.Equal((verdict, ruleId), (candidate.Verdict, candidate.RuleId));
    }

    [Fact]
    public void EveryResourceOfTheRealCaseIsClassifiedOnce()
    {
        IReadOnlyList<DockerCandidate> candidates = ClassifyRealCase();

        // 10 immagini + 6 volumi + la cache di build.
        Assert.Equal(17, candidates.Count);
        Assert.Equal(candidates.Count, candidates.Select(c => (c.Kind, c.Id)).Distinct().Count());
    }

    [Fact]
    public void SupersededVersionNamesTheTagInUse()
    {
        DockerCandidate mssql2022 = Find(ClassifyRealCase(), "mcr.microsoft.com/mssql/server:2022-latest");

        Assert.Contains("versione superata", mssql2022.Reason);
        Assert.Contains("2025-latest", mssql2022.Reason);
        Assert.Contains("riscaricare", mssql2022.Cost);
    }

    [Fact]
    public void StoppedContainerWithExitCode137StillKeepsItsImage()
    {
        DockerCandidate mssql2025 = Find(ClassifyRealCase(), "mcr.microsoft.com/mssql/server:2025-latest");

        Assert.Contains("sqlserver2025", mssql2025.Reason);
        Assert.Contains("fermo", mssql2025.Reason);
    }

    [Fact]
    public void StaleAspireHashMentionsTheHashInUse()
    {
        DockerCandidate stale = Find(ClassifyRealCase(), "orbit.apphost-751ef8e8e6-storage-data");

        Assert.Contains("hash AppHost vecchio", stale.Reason);
        Assert.Contains("48d90b1972", stale.Reason);
    }

    [Fact]
    public void ImageInUseIsMatchedByIdNotByTag()
    {
        // Lo stesso tag di un'immagine in uso, ma un ID diverso: un'immagine sostituita da un
        // pull successivo e rimasta senza container non è "in uso" solo perché ne condivide il nome.
        DockerSnapshot snapshot = Snapshot() with
        {
            Containers = [Container("web", imageId: "sha256:" + new string('9', 64))],
        };

        DockerCandidate mssql2025 = Find(DockerClassifier.Classify(snapshot, ProjectReferences.Empty), "mcr.microsoft.com/mssql/server:2025-latest");

        Assert.NotEqual(DockerVerdict.Keep, mssql2025.Verdict);
    }

    // --- Riferimenti nei progetti -------------------------------------------------------------

    [Fact]
    public void ImageCitedWithRepositoryAndTagIsKeptAndNamesTheFile()
    {
        ProjectReferences references = References(new ImageReference("quay.io/keycloak/keycloak", "26.6", "/p/Orbit.AppHost/Program.cs", 12));

        DockerCandidate keycloak = Find(ClassifyRealCase(references), "quay.io/keycloak/keycloak:26.6");

        Assert.Equal((DockerVerdict.Keep, "referenced"), (keycloak.Verdict, keycloak.RuleId));
        Assert.Contains("/p/Orbit.AppHost/Program.cs:12", keycloak.Reason);
    }

    [Fact]
    public void ReferenceWithoutTagIsOnlyAPossibleReference()
    {
        ProjectReferences references = References(new ImageReference("quay.io/keycloak/keycloak", null, "/p/Orbit.AppHost/Program.cs", 12));

        DockerCandidate keycloak = Find(ClassifyRealCase(references), "quay.io/keycloak/keycloak:26.6");

        Assert.Equal(DockerVerdict.Propose, keycloak.Verdict);
        Assert.False(keycloak.SelectedByDefault);
        Assert.Contains("possibile riferimento", keycloak.Reason);
        Assert.Contains("/p/Orbit.AppHost/Program.cs", keycloak.Reason);
    }

    [Fact]
    public void ReferenceWithAnotherTagDoesNotKeepTheImage()
    {
        ProjectReferences references = References(new ImageReference("mcr.microsoft.com/mssql/server", "2025-latest", "/p/compose.yaml", 3));

        DockerCandidate mssql2022 = Find(ClassifyRealCase(references), "mcr.microsoft.com/mssql/server:2022-latest");

        Assert.Equal(DockerVerdict.Propose, mssql2022.Verdict);
    }

    [Fact]
    public void LocallyBuiltWinsOverAProjectReference()
    {
        ProjectReferences references = References(new ImageReference("docker.io/library/orbit-api", "dev", "/p/compose.yaml", 3));

        DockerCandidate local = Find(ClassifyRealCase(references), "orbit-api:dev");

        Assert.Equal(DockerVerdict.Ask, local.Verdict);
    }

    // --- Immagini: casi fuori dal caso reale ------------------------------------------------

    [Fact]
    public void DanglingImageIsSafeToDelete()
    {
        DockerCandidate dangling = ClassifyImage(Image("sha256:" + new string('7', 64), tags: ["<none>:<none>"]));

        Assert.Equal((DockerVerdict.Delete, "dangling"), (dangling.Verdict, dangling.RuleId));
        Assert.True(dangling.SelectedByDefault);
    }

    [Fact]
    public void ImageLabelledByTestcontainersIsRecreatedByTheTool()
    {
        DockerCandidate built = ClassifyImage(Image(
            "sha256:" + new string('8', 64),
            tags: ["testcontainers/abcdef:latest"],
            labels: new Dictionary<string, string> { ["org.testcontainers"] = "true" },
            origin: ImageOrigin.Built));

        Assert.Equal((DockerVerdict.Delete, "tool-recreated"), (built.Verdict, built.RuleId));
    }

    [Fact]
    public void WithoutIdentityAnImageWithoutDigestsIsLocallyBuilt()
    {
        DockerCandidate classic = ClassifyImage(Image("sha256:" + new string('6', 64), tags: ["my/app:1"], digests: []));

        Assert.Equal((DockerVerdict.Ask, "locally-built"), (classic.Verdict, classic.RuleId));
    }

    [Fact]
    public void CreationDateIsNotACriterion()
    {
        // alpine:3.20 ha la data zero di Unix (build riproducibile): resta una normale
        // immagine non usata, non "vecchissima, quindi da cancellare".
        DockerCandidate alpine = Find(ClassifyRealCase(), "alpine:3.20");

        Assert.False(alpine.SelectedByDefault);
        Assert.DoesNotContain("1970", alpine.Reason);
    }

    // --- Volumi -------------------------------------------------------------------------------

    [Fact]
    public void ComposeVolumeOfAnExistingProjectIsKept()
    {
        DockerSnapshot snapshot = Snapshot(existingComposeProjects: new HashSet<string> { "shop" }) with
        {
            Volumes = [Volume("shop_pgdata", compose: "shop")],
        };

        DockerCandidate volume = DockerClassifier.Classify(snapshot, ProjectReferences.Empty).Single(c => c.Id == "shop_pgdata");

        Assert.Equal((DockerVerdict.Keep, "compose-project"), (volume.Verdict, volume.RuleId));
    }

    [Fact]
    public void ComposeProjectFoundInTheProjectFoldersAlsoKeepsTheVolume()
    {
        DockerSnapshot snapshot = Snapshot() with { Volumes = [Volume("shop_pgdata", compose: "shop")] };
        ProjectReferences references = new([], new HashSet<string> { "shop" });

        DockerCandidate volume = DockerClassifier.Classify(snapshot, references).Single(c => c.Id == "shop_pgdata");

        Assert.Equal(DockerVerdict.Keep, volume.Verdict);
    }

    [Fact]
    public void ComposeVolumeOfAVanishedProjectNeedsExplicitConfirmation()
    {
        DockerSnapshot snapshot = Snapshot() with { Volumes = [Volume("old_pgdata", compose: "old")] };

        DockerCandidate volume = DockerClassifier.Classify(snapshot, ProjectReferences.Empty).Single(c => c.Id == "old_pgdata");

        Assert.Equal((DockerVerdict.Propose, "named-unused"), (volume.Verdict, volume.RuleId));
        Assert.False(volume.SelectedByDefault);
    }

    [Fact]
    public void AspireVolumeOfAnAppWithNoHashInUseNeedsExplicitConfirmation()
    {
        DockerSnapshot snapshot = Snapshot() with { Volumes = [Volume("shop.apphost-1234567890-redis-data")] };

        DockerCandidate volume = DockerClassifier.Classify(snapshot, ProjectReferences.Empty)
            .Single(c => c.Id == "shop.apphost-1234567890-redis-data");

        Assert.Equal("named-unused", volume.RuleId);
    }

    [Fact]
    public void NoVolumeIsEverDeleteNorPreselected()
    {
        Assert.All(
            ClassifyRealCase().Where(c => c.Kind == DockerResourceKind.Volume),
            volume =>
            {
                Assert.NotEqual(DockerVerdict.Delete, volume.Verdict);
                Assert.False(volume.SelectedByDefault);
            });
    }

    [Fact]
    public void OnlyDeleteVerdictsArePreselected()
    {
        Assert.All(ClassifyRealCase(), c => Assert.Equal(c.Verdict == DockerVerdict.Delete, c.SelectedByDefault));
    }

    // --- Cache di build -----------------------------------------------------------------------

    [Fact]
    public void BuildCacheIsASingleSafeDeletion()
    {
        DockerCandidate cache = ClassifyRealCase().Single(c => c.Kind == DockerResourceKind.BuildCache);

        Assert.Equal(DockerVerdict.Delete, cache.Verdict);
        Assert.Equal(106_900_000, cache.SizeBytes);
    }

    [Fact]
    public void BuildCacheSharedWithImagesSaysItMayNotBeFreedYet()
    {
        // Misurato: 101,9 MB di cache, 0 B recuperabili — i layer sono condivisi con l'immagine
        // dcptun ancora presente. Presentarla come spazio sicuramente recuperabile sarebbe falso.
        DockerSnapshot snapshot = Snapshot() with
        {
            Df = new DockerDfSummary([new DockerDfEntry(DockerDfSummary.BuildCacheType, 101_900_000, 0)]),
        };

        DockerCandidate cache = DockerClassifier.Classify(snapshot, ProjectReferences.Empty).Single(c => c.Kind == DockerResourceKind.BuildCache);

        Assert.Contains("condivisa con immagini presenti", cache.Reason);
    }

    [Fact]
    public void FullyReclaimableBuildCacheHasNoSharingNote()
    {
        DockerCandidate cache = ClassifyRealCase().Single(c => c.Kind == DockerResourceKind.BuildCache);

        Assert.DoesNotContain("condivisa", cache.Reason);
    }

    [Fact]
    public void EmptyBuildCacheIsNotProposed()
    {
        DockerSnapshot snapshot = Snapshot() with { Df = DockerDfSummary.Empty };

        Assert.DoesNotContain(DockerClassifier.Classify(snapshot, ProjectReferences.Empty), c => c.Kind == DockerResourceKind.BuildCache);
    }

    // --- Regole -------------------------------------------------------------------------------

    [Fact]
    public void RulesAreDeclaredInPriorityOrder()
    {
        Assert.Equal(
            ["in-use", "dangling", "tool-recreated", "locally-built", "referenced", "superseded", "unused"],
            ImageRules.Default.Select(r => r.Id));
        Assert.Equal(
            ["mounted", "anonymous", "compose-project", "aspire-current", "aspire-stale", "named-unused"],
            VolumeRules.Default.Select(r => r.Id));
    }

    // --- Utilità ------------------------------------------------------------------------------

    private static DockerCandidate ClassifyImage(DockerImage image)
        => DockerClassifier.Classify(
                Snapshot() with { Containers = [], Images = [image], Volumes = [], Df = DockerDfSummary.Empty },
                ProjectReferences.Empty)
            .Single();

    private static ProjectReferences References(params ImageReference[] images) => new(images, new HashSet<string>());

    private static DockerContainer Container(string name, string imageId)
        => new(name, name, imageId, "running", 0, [], NoLabels);

    private static DockerImage Image(
        string id,
        IReadOnlyList<string> tags,
        IReadOnlyList<string>? digests = null,
        IReadOnlyDictionary<string, string>? labels = null,
        ImageOrigin origin = ImageOrigin.Unknown)
        => new(id, tags, digests ?? [], 1_000, null, labels ?? NoLabels, origin);

    private static DockerVolume Volume(string name, string? compose = null)
        => new(
            name,
            compose is null ? NoLabels : new Dictionary<string, string> { ["com.docker.compose.project"] = compose },
            1_000);
}
