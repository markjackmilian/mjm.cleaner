using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

public class DockerSizeTests
{
    [Theory]
    [InlineData("0B", 0L)]
    [InlineData("57.3kB", 57_300L)]
    [InlineData("1.131kB", 1_131L)]
    [InlineData("195MB", 195_000_000L)]
    [InlineData("2.42GB", 2_420_000_000L)]
    [InlineData("1.5TB", 1_500_000_000_000L)]
    [InlineData("76.74MB (2%)", 76_740_000L)]
    [InlineData(" 106.9MB ", 106_900_000L)]
    public void ParsesTheDecimalUnitsPrintedByDocker(string text, long expected)
        => Assert.Equal(expected, DockerSize.Parse(text));

    [Theory]
    [InlineData("N/A")]
    [InlineData("")]
    [InlineData(null)]
    [InlineData("molto")]
    public void ReturnsNullWhenTheSizeIsUnknown(string? text)
        => Assert.Null(DockerSize.Parse(text));
}
