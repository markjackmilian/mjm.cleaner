using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia;
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

    [AvaloniaFact]
    public async Task LargeConfirmationKeepsDestructiveAndBackControlsInViewport()
    {
        XcodeCandidate[] candidates = Enumerable.Range(0, 100)
            .Select(i => XcodeViewModelTests.Candidate($"device-{i:D3}", XcodeResourceKind.Device))
            .ToArray();
        XcodeViewModel vm = new(new XcodeViewModelTests.FakeXcode(XcodeViewModelTests.Snapshot(candidates)),
            new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), new XcodeViewModelTests.FakeNavigation());
        await vm.InitialLoad;
        foreach (XcodeRow row in vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows) row.IsSelected = true;
        vm.PreviewCommand.Execute(null);
        Assert.Equal(100, vm.Confirmation!.SelectedCandidates.Count);

        Window window = new() { Width = 1100, Height = 700, Content = new XcodeView { DataContext = vm } };
        window.Show();
        window.UpdateLayout();

        Button confirm = window.GetVisualDescendants().OfType<Button>().Single(button => button.Content?.ToString() == "Conferma ed elimina");
        Button back = window.GetVisualDescendants().OfType<Button>().Single(button => button.Content?.ToString() == "Torna alla selezione");
        double confirmBottom = confirm.TranslatePoint(new Point(0, confirm.Bounds.Height), window)!.Value.Y;
        double backBottom = back.TranslatePoint(new Point(0, back.Bounds.Height), window)!.Value.Y;
        Assert.True(confirm.IsEffectivelyVisible);
        Assert.True(back.IsEffectivelyVisible);
        Assert.InRange(confirmBottom, 1, window.ClientSize.Height);
        Assert.InRange(backBottom, 1, window.ClientSize.Height);
    }

    [AvaloniaFact]
    public async Task LargeRetainedDependencyListKeepsFinalControlsInViewport()
    {
        string[] deviceNames = Enumerable.Range(0, 100).Select(i => $"dependent-{i:D3}").ToArray();
        XcodeCandidate[] candidates =
        [
            XcodeViewModelTests.Candidate("runtime", XcodeResourceKind.Runtime, deviceNames),
            .. deviceNames.Select(name => XcodeViewModelTests.Candidate(name, XcodeResourceKind.Device)),
        ];
        XcodeViewModel vm = new(new XcodeViewModelTests.FakeXcode(XcodeViewModelTests.Snapshot(candidates)),
            new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), new XcodeViewModelTests.FakeNavigation());
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Runtime).Rows.Single().IsSelected = true;
        vm.PreviewCommand.Execute(null);
        Assert.Equal(100, vm.Confirmation!.RetainedDependentDevices.Count);

        Window window = new() { Width = 1100, Height = 700, Content = new XcodeView { DataContext = vm } };
        window.Show();
        window.UpdateLayout();

        Button confirm = window.GetVisualDescendants().OfType<Button>().Single(button => button.Content?.ToString() == "Conferma ed elimina");
        Button back = window.GetVisualDescendants().OfType<Button>().Single(button => button.Content?.ToString() == "Torna alla selezione");
        double confirmBottom = confirm.TranslatePoint(new Point(0, confirm.Bounds.Height), window)!.Value.Y;
        double backBottom = back.TranslatePoint(new Point(0, back.Bounds.Height), window)!.Value.Y;
        Assert.True(confirm.IsEffectivelyVisible);
        Assert.True(back.IsEffectivelyVisible);
        Assert.InRange(confirmBottom, 1, window.ClientSize.Height);
        Assert.InRange(backBottom, 1, window.ClientSize.Height);
    }

    [AvaloniaFact]
    public async Task ReportRowsRenderResourceIdentity()
    {
        const string uuid = "11111111-1111-4111-8111-111111111111";
        XcodeCandidate candidate = new("device:" + uuid, XcodeResourceKind.Device, "iPhone 16", CliId: uuid);
        XcodeCleanResult result = new(XcodeViewModelTests.EmptyReport(),
            [new XcodeItemResult(candidate, XcodeItemOutcome.Deleted, "verified", 100)], 100, 120, []);
        XcodeReportViewModel vm = new(new XcodeViewModelTests.FakeXcode(XcodeViewModelTests.Snapshot()),
            new XcodeViewModelTests.FakeHistory(), new XcodeViewModelTests.FakeLog(), new XcodeViewModelTests.FakeNavigation(), result);
        await vm.PersistenceTask;

        Window window = new() { Width = 900, Height = 640, Content = new XcodeReportView { DataContext = vm } };
        window.Show();
        window.UpdateLayout();

        string[] visible = window.GetVisualDescendants().OfType<TextBlock>().Select(text => text.Text ?? string.Empty).ToArray();
        Assert.Contains(uuid, visible);
    }
}
