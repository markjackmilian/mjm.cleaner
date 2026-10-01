using MjmCleaner.Core.Docker;
using static MjmCleaner.Core.Tests.Docker.DockerFixtures;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerJsonTests
{
    [Fact]
    public void ContainersKeepFullImageIdStateAndOnlyNamedVolumeMounts()
    {
        IReadOnlyList<DockerContainer> containers = DockerJson.ParseContainers(Read("containers.json"));

        DockerContainer storage = containers.Single(c => c.Name == "storage-bedaxjvn");
        Assert.Equal(AzuriteId, storage.ImageId);
        Assert.Equal("exited", storage.State);
        Assert.Equal(137, storage.ExitCode);
        Assert.Equal(["orbit.apphost-48d90b1972-storage-data"], storage.VolumeNames);
        Assert.Equal("storage-bedaxjvn", storage.Labels["com.microsoft.developer.usvc-dev.name"]);
    }

    [Fact]
    public void ImagesReadTagsDigestsSizeLabelsAndOrigin()
    {
        IReadOnlyList<DockerImage> images = DockerJson.ParseImages(
            Read("images.json"),
            new Dictionary<string, long> { [DcptunId] = 76_740_000 });

        DockerImage dcptun = images.Single(i => i.Id == DcptunId);
        Assert.Equal(["dcptun_developer_ms:0.25.13"], dcptun.RepoTags);
        Assert.Single(dcptun.RepoDigests);
        Assert.Equal(195_234_351, dcptun.SizeBytes);
        Assert.Equal(76_740_000, dcptun.UniqueSizeBytes);
        Assert.Equal(ImageOrigin.Built, dcptun.Origin);
        Assert.Equal(AzureLinuxId, dcptun.Labels["com.microsoft.developer.usvc-dev.base-image-digest"]);

        DockerImage mssql = images.Single(i => i.Id == Mssql2025Id);
        Assert.Equal(ImageOrigin.Pulled, mssql.Origin);
        Assert.Null(mssql.UniqueSizeBytes);
    }

    [Fact]
    public void MissingLabelsAndIdentityAreTolerated()
    {
        const string json = """
            [{"Id":"sha256:1","RepoTags":null,"RepoDigests":[],"Size":10,"Config":null},
             {"Id":"sha256:2","RepoTags":["a:1"],"RepoDigests":null,"Size":20,"Config":{"Labels":null}}]
            """;

        IReadOnlyList<DockerImage> images = DockerJson.ParseImages(json);

        Assert.All(images, image => Assert.Empty(image.Labels));
        Assert.All(images, image => Assert.Equal(ImageOrigin.Unknown, image.Origin));
        Assert.Empty(images[0].RepoTags);
        Assert.True(images[0].IsDangling);
        Assert.Empty(images[1].RepoDigests);
    }

    [Fact]
    public void IdentityWithBothBuildAndPullCountsAsPulled()
    {
        const string json = """
            [{"Id":"sha256:1","RepoTags":["a:1"],"Size":1,"Identity":{"Build":[{"Ref":"x"}],"Pull":[{"Repository":"a"}]}}]
            """;

        Assert.Equal(ImageOrigin.Pulled, DockerJson.ParseImages(json)[0].Origin);
    }

    [Fact]
    public void VolumesTakeLabelsFromInspectAndSizeFromSystemDf()
    {
        DockerDfVerbose verbose = DockerJson.ParseDfVerbose(Read("df-verbose.json"));
        IReadOnlyList<DockerVolume> volumes = DockerJson.ParseVolumes(Read("volumes.json"), verbose.VolumeSizes);

        DockerVolume sql = volumes.Single(v => v.Name == "orbit.apphost-48d90b1972-sql-data");
        Assert.Equal(158_300_000, sql.SizeBytes);
        Assert.Empty(sql.Labels);
        Assert.Null(volumes.Single(v => v.Name == AnonymousVolume).SizeBytes);
    }

    [Fact]
    public void DfVerboseReadsUniqueImageSizes()
    {
        DockerDfVerbose verbose = DockerJson.ParseDfVerbose(Read("df-verbose.json"));

        Assert.Equal(1_131, verbose.ImageUniqueSizes[AzureLinuxId]);
    }

    [Fact]
    public void DfSummaryReadsOneEntryPerType()
    {
        DockerDfSummary df = DockerJson.ParseDfSummary(Read("df.jsonl"));

        Assert.Equal(5_840_000_000, df.Images);
        Assert.Equal(558_500_000, df.Volumes);
        Assert.Equal(106_900_000, df.BuildCache);
        Assert.Equal(106_900_000, df.Entries.Single(e => e.Type == DockerDfSummary.BuildCacheType).ReclaimableBytes);
    }

    [Fact]
    public void JsonLinesPropertyIgnoresBlankLines()
    {
        const string lines = """
            {"ID":"sha256:1","Repository":"a"}

            {"ID":"sha256:2","Repository":"b"}
            """;

        Assert.Equal(["sha256:1", "sha256:2"], DockerJson.ParseJsonLinesProperty(lines, "ID"));
    }

    [Fact]
    public void InvalidJsonBecomesAReadableError()
    {
        DockerOutputException error = Assert.Throws<DockerOutputException>(
            () => DockerJson.ParseContainers("Error response from daemon"));

        Assert.Contains("container", error.Message, StringComparison.OrdinalIgnoreCase);
    }
}
