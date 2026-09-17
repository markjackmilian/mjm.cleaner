using Avalonia;
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Layout;
using Avalonia.VisualTree;
using MjmCleaner.App.Views;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class MainWindowLayoutTests
{
    [AvaloniaFact]
    public void LongPathsDoNotResizeThePageOrPushItsFooterBelowTheViewport()
    {
        MainWindow window = new()
        {
            Width = 900,
            Height = 640,
        };
        window.Show();

        ContentControl pageHost = window.GetVisualDescendants()
            .OfType<ContentControl>()
            .Single(control => control.MaxWidth == 1120);
        Border footer = new()
        {
            Height = 44,
            HorizontalAlignment = HorizontalAlignment.Stretch,
        };
        TextBlock path = new()
        {
            Text = "/Users/example/" + new string('x', 4_000),
            TextTrimming = Avalonia.Media.TextTrimming.CharacterEllipsis,
        };
        pageHost.Content = new DockPanel
        {
            Children =
            {
                new TextBlock { Text = "Titolo", [DockPanel.DockProperty] = Dock.Top },
                footer.WithDock(Dock.Bottom),
                new ScrollViewer
                {
                    Content = new StackPanel
                    {
                        Children =
                        {
                            path,
                            new Border { Height = 1_200 },
                        },
                    },
                },
            },
        };

        window.UpdateLayout();

        Assert.InRange(pageHost.Bounds.Width, 1, window.ClientSize.Width - 60);
        Assert.True(
            footer.TranslatePoint(new Point(0, footer.Bounds.Height), window)?.Y <= window.ClientSize.Height,
            "Il footer deve restare visibile nel viewport della finestra.");
    }
}

file static class LayoutTestExtensions
{
    public static T WithDock<T>(this T control, Dock dock) where T : Control
    {
        DockPanel.SetDock(control, dock);
        return control;
    }
}
