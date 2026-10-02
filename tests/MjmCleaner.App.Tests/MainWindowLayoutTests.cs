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
            Width = 1120,
            Height = 700,
        };
        window.Show();

        ContentControl pageHost = window.FindControl<ContentControl>("PageHost")!;
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

        Assert.InRange(pageHost.Bounds.Width, 1, window.ClientSize.Width - 232);
        Assert.True(
            footer.TranslatePoint(new Point(0, footer.Bounds.Height), window)?.Y <= window.ClientSize.Height,
            "Il footer deve restare visibile nel viewport della finestra.");
    }

    [AvaloniaFact]
    public void ShellHasSidebarAndNoCloseButtons()
    {
        MainWindow window = new() { Width = 1120, Height = 700 };
        window.Show();
        window.UpdateLayout();

        string[] texts = [.. window.GetVisualDescendants().OfType<TextBlock>().Select(t => t.Text ?? "")];
        Assert.Contains("Pulizia", texts);
        Assert.Contains("Docker", texts);
        Assert.Contains("Xcode", texts);
        Assert.Contains("Storico", texts);
        Assert.Contains("Impostazioni…", texts);
        Assert.DoesNotContain(window.GetVisualDescendants().OfType<Button>(), b => b.Content as string == "Chiudi");
    }
    [AvaloniaFact]
    public void WizardViewsHaveToolbarAndActionBar()
    {
        UserControl[] views = [new ChooseStepView(), new ScanStepView(), new ConfirmStepView(), new DoneStepView()];
        for (int i = 0; i < views.Length; i++)
        {
            UserControl view = views[i];
            Window window = new() { Width = 888, Height = 700, Content = view };
            window.Show();
            window.UpdateLayout();
            Assert.Contains(view.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
            Assert.Contains(view.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("ActionBar"));
            // Ogni vista indica il proprio passo: 1, 2, 3, 4 nell'ordine del wizard.
            StepIndicator indicator = Assert.Single(view.GetVisualDescendants().OfType<StepIndicator>());
            Assert.Equal(i + 1, indicator.CurrentStep);
            window.Close();
        }
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
