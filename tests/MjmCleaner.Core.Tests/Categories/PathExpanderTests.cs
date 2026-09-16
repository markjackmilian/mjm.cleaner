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

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("relative/path")]
    [InlineData("/")]
    [InlineData("//")]
    [InlineData("///")]
    public void ConstructorRejectsInvalidHomeDirectory(string? homeDirectory)
    {
        Assert.Throws<ArgumentException>(() => new PathExpander(homeDirectory, "/var/folders/ab/xyz/T"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("relative/path")]
    [InlineData("/")]
    [InlineData("//")]
    [InlineData("///")]
    public void ConstructorRejectsInvalidTempDirectory(string? tempDirectory)
    {
        Assert.Throws<ArgumentException>(() => new PathExpander("/Users/tester", tempDirectory));
    }
}
