using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class ImageNameTests
{
    [Theory]
    [InlineData("alpine:3.20", "docker.io/library/alpine", "3.20")]
    [InlineData("docker.io/library/alpine:3.20", "docker.io/library/alpine", "3.20")]
    [InlineData("testcontainers/ryuk:0.14.0", "docker.io/testcontainers/ryuk", "0.14.0")]
    [InlineData("mcr.microsoft.com/mssql/server:2025-latest", "mcr.microsoft.com/mssql/server", "2025-latest")]
    [InlineData("localhost:5000/app:1", "localhost:5000/app", "1")]
    [InlineData("localhost/app", "localhost/app", null)]
    [InlineData("quay.io/keycloak/keycloak", "quay.io/keycloak/keycloak", null)]
    [InlineData("redis@sha256:abc", "docker.io/library/redis", null)]
    [InlineData("redis:7@sha256:abc", "docker.io/library/redis", "7")]
    [InlineData("Dcptun_Developer_MS:0.25.13", "docker.io/library/dcptun_developer_ms", "0.25.13")]
    public void NormalizesRepositoryAndSeparatesTheTag(string reference, string repository, string? tag)
    {
        ImageName name = ImageName.Parse(reference);

        Assert.Equal(repository, name.Repository);
        Assert.Equal(tag, name.Tag);
    }

    [Fact]
    public void ShortNameIsTheLastRepositorySegment()
        => Assert.Equal("ryuk", ImageName.Parse("testcontainers/ryuk:0.14.0").ShortName);
}
