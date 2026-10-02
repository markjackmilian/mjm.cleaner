using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using MjmCleaner.App.Services;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Settings;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class HistoryViewTests
{
    private static async Task<(Window Window, HistoryViewModel Vm)> CreateAsync()
    {
        string home = Path.Combine(Path.GetTempPath(), "mjm-cleaner-tests-" + Guid.NewGuid().ToString("N"));
        AppServices services = await AppServices.CreateAsync(new AppPaths(home));
        HistoryViewModel vm = new(services, new MainWindowViewModel(services));
        Window window = new() { Width = 888, Height = 700, Content = new HistoryView { DataContext = vm } };
        window.Show();

        // Il caricamento dello storico parte nel costruttore: si attende che abbia valorizzato il riepilogo.
        for (int i = 0; i < 200 && string.IsNullOrEmpty(vm.CountText); i++)
        {
            await Task.Delay(10);
            Avalonia.Threading.Dispatcher.UIThread.RunJobs();
        }

        window.UpdateLayout();
        return (window, vm);
    }

    [AvaloniaFact]
    public async Task HasToolbarAndNoCloseButton()
    {
        var (window, _) = await CreateAsync();

        Assert.Contains(window.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
        Assert.DoesNotContain(
            Avalonia.LogicalTree.LogicalExtensions.GetLogicalDescendants(window).OfType<Button>(),
            b => b.Content as string == "Chiudi");

        window.Close();
    }

    [AvaloniaFact]
    public async Task EmptyHistoryShowsOnlyNessunaPulizia()
    {
        var (window, vm) = await CreateAsync();

        Assert.False(vm.HasSessions);
        TextBlock total = Assert.Single(window.GetVisualDescendants().OfType<TextBlock>(), t => t.Text == vm.TotalText);
        TextBlock count = Assert.Single(window.GetVisualDescendants().OfType<TextBlock>(), t => t.Text == "nessuna pulizia");
        Assert.False(total.IsVisible);
        Assert.True(count.IsVisible);

        window.Close();
    }

    [AvaloniaFact]
    public async Task AmountIsVisibleWhenThereAreSessions()
    {
        var (window, vm) = await CreateAsync();

        vm.TotalText = "1,2 GB";
        vm.CountText = "in 3 pulizie";
        vm.HasSessions = true;
        window.UpdateLayout();

        TextBlock total = Assert.Single(window.GetVisualDescendants().OfType<TextBlock>(), t => t.Text == "1,2 GB");
        Assert.True(total.IsVisible);
        Assert.True(total.IsEffectivelyVisible);

        window.Close();
    }

    [AvaloniaFact]
    public async Task SortChevronIsNinePixelsWithAThinStroke()
    {
        var (window, _) = await CreateAsync();

        // Chevron di ordinamento accanto a «Data»: 9x9 (Viewbox su un'icona 24x24, tratto 3 in viewBox 24).
        TextBlock data = window.GetVisualDescendants().OfType<TextBlock>().First(t => t.Text == "Data");
        Viewbox box = Assert.Single(data.GetVisualParent()!.GetVisualChildren().OfType<Viewbox>());
        Assert.Equal(9, box.Bounds.Width, 1);
        Assert.Equal(9, box.Bounds.Height, 1);
        Avalonia.Controls.Shapes.Path path = Assert.IsType<Avalonia.Controls.Shapes.Path>(box.Child);
        Assert.Equal(24, path.Width);
        Assert.Equal(3, path.StrokeThickness);

        window.Close();
    }

    [AvaloniaFact]
    public async Task ColumnHeadersShareOneStyle()
    {
        var (window, _) = await CreateAsync();

        foreach (string title in new[] { "Data", "Spazio", "Categorie", "Elementi" })
        {
            TextBlock header = window.GetVisualDescendants().OfType<TextBlock>().First(t => t.Text == title);
            Assert.Contains("ColumnHeader", header.Classes);
            Assert.Equal(11, header.FontSize);
            Assert.Equal(Avalonia.Media.FontWeight.SemiBold, header.FontWeight);
        }

        window.Close();
    }
}
