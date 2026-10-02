using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Categories;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ChooseStepTests
{
    private static CleanupCategory Category(string id, string? parent = null, RiskLevel risk = RiskLevel.Low)
        => new(id, id, "descrizione", risk, false, parent, []);

    [Theory]
    [InlineData(0, "Nessuna categoria selezionata")]
    [InlineData(1, "1 categoria selezionata")]
    [InlineData(3, "3 categorie selezionate")]
    public void CountTextAgrees(int count, string expected)
        => Assert.Equal(expected, ChooseStepViewModel.CountText(count));

    [Fact]
    public void ChildRowsAreIndentedWithDeeperSeparator()
    {
        CategoryChoice child = new(Category("nuget-packages", parent: "dev-caches"), false) { ShowSeparator = true };
        CategoryChoice root = new(Category("logs"), false) { ShowSeparator = true };
        Assert.True(child.IsChild);
        Assert.Equal(116, child.SeparatorMargin.Left);
        Assert.Equal(60, child.RowPadding.Left);
        Assert.Equal(72, root.SeparatorMargin.Left);
        Assert.Equal(16, root.RowPadding.Left);
    }

    [Theory]
    [InlineData(RiskLevel.Low, "Rischio basso")]
    [InlineData(RiskLevel.Medium, "Rischio medio")]
    [InlineData(RiskLevel.High, "Rischio alto")]
    public void RiskPillTextNamesTheLevel(RiskLevel risk, string expected)
        => Assert.Equal(expected, new CategoryChoice(Category("logs", risk: risk), false).RiskLabel);

    [Theory]
    [InlineData("system-caches", "#66788F")]
    [InlineData("dev-caches", "#7457E8")]
    [InlineData("nuget-packages", "#3567D0")]
    [InlineData("project-build-output", "#1D8784")]
    [InlineData("logs", "#85858B")]
    [InlineData("trash", "#D2453A")]
    [InlineData("downloads-large", "#E8833A")]
    public void TilesUseTheDesignColors(string id, string color)
        => Assert.Equal(color, CategoryVisuals.For(id).TileColor);
}
