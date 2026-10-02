using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.VisualTree;
using MjmCleaner.App.Tests.Xcode;
using MjmCleaner.App.ViewModels;
using MjmCleaner.App.Views;
using MjmCleaner.Core.Xcode;
using Xunit;

namespace MjmCleaner.App.Tests.Xcode;

public sealed class XcodeViewLayoutTests
{
    [AvaloniaFact]
    public async Task NonEmptyPageRendersFourGroupsAndFinalConfirmationLabels()
    {
        XcodeViewModelTests.FakeXcode service = new(
            XcodeViewModelTests.Snapshot(
                XcodeViewModelTests.Candidate("derived", XcodeResourceKind.DerivedData),
                XcodeViewModelTests.Candidate("support", XcodeResourceKind.DeviceSupport),
                XcodeViewModelTests.Candidate("device", XcodeResourceKind.Device),
                XcodeViewModelTests.Candidate("runtime", XcodeResourceKind.Runtime)));
        XcodeViewModel vm = new(service, new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), new XcodeViewModelTests.FakeNavigation());
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;

        Window window = new() { Width = 900, Height = 640, Content = new XcodeView { DataContext = vm } };
        window.Show();
        window.UpdateLayout();
        string[] visible = window.GetVisualDescendants().OfType<TextBlock>().Select(text => text.Text ?? string.Empty).ToArray();
        Assert.Contains("DerivedData", visible);
        Assert.Contains("Device Support", visible);
        Assert.Contains("Dispositivi simulati", visible);
        Assert.Contains("Runtime iOS, watchOS, tvOS e visionOS", visible);

        vm.PreviewCommand.Execute(null);
        Assert.Equal("Risorse selezionate: 1", vm.PreviewSummaryText);
        window.UpdateLayout();
        visible = window.GetVisualDescendants().OfType<TextBlock>().Select(text => text.Text ?? string.Empty).ToArray();
        Assert.Contains("Conferma finale", visible);
        Assert.True(visible.Any(value => value.Contains("Risorse selezionate", StringComparison.Ordinal)), string.Join(" | ", visible));
    }
}
