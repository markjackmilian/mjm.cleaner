using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using MjmCleaner.App.Tests.Xcode;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using Xunit;

namespace MjmCleaner.App.Tests;

public sealed class ToolPagesLayoutTests
{
    [AvaloniaFact]
    public async Task XcodePageHasToolbarAndNoCloseButton()
    {
        XcodeViewModel vm = new(new XcodeViewModelTests.FakeXcode(XcodeViewModelTests.Snapshot(
                XcodeViewModelTests.Candidate("derived", Core.Xcode.XcodeResourceKind.DerivedData))),
            new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), new XcodeViewModelTests.FakeNavigation());
        await vm.InitialLoad;
        Window window = new() { Width = 888, Height = 700, Content = new XcodeView { DataContext = vm } };
        window.Show();
        window.UpdateLayout();

        Assert.Contains(window.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
        Assert.DoesNotContain(window.GetVisualDescendants().OfType<Button>(), b => b.Content as string == "Chiudi");
    }

    [AvaloniaFact]
    public void DockerViewsHaveNoCloseButton()
    {
        foreach (UserControl view in new UserControl[] { new DockerView(), new DockerReportView(), new XcodeReportView() })
        {
            Window window = new() { Width = 888, Height = 700, Content = view };
            window.Show();
            window.UpdateLayout();
            Assert.Contains(view.GetVisualDescendants().OfType<Border>(), b => b.Classes.Contains("Toolbar"));
            Assert.DoesNotContain(view.GetLogicalDescendantsOfType<Button>(), b => b.Content as string == "Chiudi");
            window.Close();
        }
    }
}

file static class LogicalExtensions
{
    public static IEnumerable<T> GetLogicalDescendantsOfType<T>(this Avalonia.LogicalTree.ILogical root)
        => Avalonia.LogicalTree.LogicalExtensions.GetLogicalDescendants(root).OfType<T>();
}
