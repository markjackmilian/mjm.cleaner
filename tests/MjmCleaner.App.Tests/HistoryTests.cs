using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Categories;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class HistoryTests
{
    private static readonly IReadOnlyDictionary<string, string> Names = CategoryNames.Build(
        [new CleanupCategory("system-caches", "Cache utente e di sistema", "", RiskLevel.Medium, true, null, [])]);

    private static CleanSessionSummary Session(params string[] ids) => new(
        1,
        new DateTimeOffset(new DateTime(2026, 9, 26, 1, 19, 0, DateTimeKind.Local)),
        TimeSpan.FromSeconds(3),
        10_200_547_328,
        2117,
        0,
        [.. ids.Select(id => new CategoryCleanResult(id, 1, 1))]);

    [Fact]
    public void DateIsLocalisedItalian() => Assert.Equal("26 set 2026, 01:19", new HistoryRow(Session("system-caches"), Names).When);

    [Fact]
    public void ItemsUseThousandsSeparator() => Assert.Equal("2.117", new HistoryRow(Session("system-caches"), Names).Items);

    [Fact]
    public void CategoriesShowReadableNames()
    {
        HistoryRow row = new(Session("system-caches", "docker-images", "xcode-derived-data", "trash-downloads-large", "sconosciuta"), Names);
        Assert.Equal(["Cache utente e di sistema", "Immagini Docker", "DerivedData", "Cestino, Download e file grandi", "sconosciuta"], row.CategoryNames);
    }

    [Theory]
    [InlineData(0, "nessuna pulizia")]
    [InlineData(1, "in 1 pulizia")]
    [InlineData(4, "in 4 pulizie")]
    public void SummaryAgrees(int count, string expected) => Assert.Equal(expected, HistoryViewModel.Summarize(count));
}
