using System.IO.Abstractions.TestingHelpers;
using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class ProjectReferenceScannerTests
{
    private static ProjectReferences Scan(params (string Path, string Content)[] files)
    {
        MockFileSystem fs = new();
        fs.AddDirectory("/p");
        foreach ((string path, string content) in files)
        {
            fs.AddFile(path, new MockFileData(content));
        }

        return new ProjectReferenceScanner(fs).Scan(["/p"], CancellationToken.None);
    }

    private static (string Repository, string? Tag)[] Images(ProjectReferences references)
        => [.. references.Images.Select(i => (i.Repository, i.Tag)).Order()];

    [Fact]
    public void ComposeImagesAreReadWithFileAndLine()
    {
        ProjectReferences found = Scan(("/p/shop/compose.yaml", """
            services:
              db:
                image: postgres:16
              cache:
                image: "redis"
            """));

        Assert.Equal([("docker.io/library/postgres", "16"), ("docker.io/library/redis", null)], Images(found));
        ImageReference postgres = found.Images.Single(i => i.Tag == "16");
        Assert.Equal(("/p/shop/compose.yaml", 3), (postgres.File, postgres.Line));
    }

    [Fact]
    public void ComposeProjectNameComesFromTheFolderWhenNotDeclared()
    {
        ProjectReferences found = Scan(("/p/My Shop/docker-compose.override.yml", "services: {}\n"));

        Assert.Equal(["myshop"], found.ComposeProjects);
    }

    [Fact]
    public void ComposeProjectNameDeclaredInTheFileWins()
    {
        ProjectReferences found = Scan(("/p/shop/compose.yml", "name: Orbit-Stack\nservices: {}\n"));

        Assert.Equal(["orbit-stack"], found.ComposeProjects);
    }

    [Fact]
    public void DockerfileFromLinesSkipStageNamesAndScratch()
    {
        ProjectReferences found = Scan(("/p/api/Dockerfile", """
            FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0 AS build
            RUN dotnet publish
            FROM build AS publish
            FROM scratch AS empty
            from mcr.microsoft.com/dotnet/aspnet:9.0
            """));

        Assert.Equal(
            [("mcr.microsoft.com/dotnet/aspnet", "9.0"), ("mcr.microsoft.com/dotnet/sdk", "9.0")],
            Images(found));
    }

    [Fact]
    public void AspireAppHostResourcesMapToTheirImages()
    {
        ProjectReferences found = Scan(("/p/Orbit.AppHost/Program.cs", """
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
            """));

        Assert.Equal(
            [
                ("docker.io/axllent/mailpit", "v1.20"),
                ("mcr.microsoft.com/azure-storage/azurite", "3.35.0"),
                ("mcr.microsoft.com/mssql/server", "2025-latest"),
                ("quay.io/keycloak/keycloak", null),
                ("quay.io/opstree/redis", "7.2"),
            ],
            Images(found));
        Assert.Equal(3, found.Images.Single(i => i.Tag == "2025-latest").Line);
    }

    [Fact]
    public void WithImageRegistryPrefixesTheRepository()
    {
        ProjectReferences found = Scan(("/p/Orbit.AppHost/Program.cs", """
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddContainer("api", "acme/api").WithImageRegistry("ghcr.io").WithImageTag("2.0");
            """));

        Assert.Equal([("ghcr.io/acme/api", "2.0")], Images(found));
    }

    [Fact]
    public void TestcontainersBuildersAndExplicitImagesAreFound()
    {
        ProjectReferences found = Scan(("/p/Tests/Fixture.cs", """
            using Testcontainers.MsSql;

            var sql = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();
            var plain = new ContainerBuilder().WithImage("alpine:3.20").Build();
            var redis = new RedisBuilder().Build();
            """));

        Assert.Equal(
            [
                ("docker.io/library/alpine", "3.20"),
                ("docker.io/library/redis", null),
                ("mcr.microsoft.com/mssql/server", "2022-latest"),
            ],
            Images(found));
    }

    [Fact]
    public void OrdinaryCSharpFilesAreNotScanned()
    {
        ProjectReferences found = Scan(("/p/Api/Service.cs", """
            var name = "postgres:16";
            var x = something.WithImage("alpine:3.20");
            """));

        Assert.Empty(found.Images);
    }

    [Fact]
    public void KubernetesAndHelmManifestsAreRead()
    {
        ProjectReferences found = Scan(
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
                """));

        Assert.Equal([("docker.io/library/nginx", "1.27"), ("ghcr.io/acme/api", "1.4.2")], Images(found));
    }

    [Fact]
    public void TemplatedValuesAreIgnored()
    {
        ProjectReferences found = Scan(("/p/shop/compose.yaml", """
            services:
              api:
                image: ${REGISTRY}/api:${TAG}
              web:
                image: "{{ .Values.image }}"
            """));

        Assert.Empty(found.Images);
    }

    [Theory]
    [InlineData("node_modules")]
    [InlineData("bin")]
    [InlineData("obj")]
    [InlineData(".git")]
    public void ExcludedFoldersAreSkipped(string folder)
    {
        ProjectReferences found = Scan(($"/p/web/{folder}/pkg/docker-compose.yml", "services:\n  x:\n    image: postgres:16\n"));

        Assert.Empty(found.Images);
        Assert.Empty(found.ComposeProjects);
    }

    [Fact]
    public void FilesLargerThanOneMegabyteAreSkipped()
    {
        ProjectReferences found = Scan(("/p/deploy/huge.yaml", "image: nginx:1.27\n" + new string('#', 1_100_000)));

        Assert.Empty(found.Images);
    }

    [Fact]
    public void MissingRootProducesNoReferences()
    {
        ProjectReferences found = new ProjectReferenceScanner(new MockFileSystem()).Scan(["/nope"], CancellationToken.None);

        Assert.Empty(found.Images);
    }
}
