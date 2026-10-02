using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Xcode;
using Xunit;
using static MjmCleaner.App.Tests.Xcode.XcodeViewModelTests;

namespace MjmCleaner.App.Tests.Xcode;

public sealed class XcodeReportViewModelTests
{
    [Fact]
    public async Task CancelledPartialReportIsSavedOnce()
    {
        FakeHistory history = new(); FakeLog log = new();
        XcodeReportViewModel vm = new(new FakeXcode(Snapshot()), history, log, new FakeNavigation(), PartialResult());
        await vm.PersistenceTask;
        await vm.PersistCommand.ExecuteAsync(null);
        Assert.Equal(1, history.Saves); Assert.Equal(1, log.Writes); Assert.Single(vm.Items);
    }
    [Fact]
    public async Task UnknownSizeUsesUnavailableLabel()
    {
        XcodeItemResult item = new(Candidate("runtime", XcodeResourceKind.Runtime) with { SizeBytes = null }, XcodeItemOutcome.Deleted, "verified", null);
        XcodeReportViewModel vm = new(new FakeXcode(Snapshot()), new FakeHistory(), new FakeLog(), new FakeNavigation(), new(EmptyReport(), [item], null, null, []));
        await vm.PersistenceTask;
        Assert.Equal("non disponibile", Assert.Single(vm.Items).SizeText);
    }
    [Fact]
    public async Task PersistenceFailureShowsReportAndError()
    {
        FakeHistory history = new() { FailSave = true };
        XcodeReportViewModel vm = new(new FakeXcode(Snapshot()), history, new FakeLog(), new FakeNavigation(), PartialResult());
        await vm.PersistenceTask; await vm.PersistCommand.ExecuteAsync(null);
        Assert.Contains("storico", vm.HistoryWarning, StringComparison.OrdinalIgnoreCase); Assert.Single(vm.Items); Assert.Equal(1, history.Saves);
    }
    private static XcodeCleanResult PartialResult() => new(EmptyReport(), [new(Candidate("device", XcodeResourceKind.Device), XcodeItemOutcome.Skipped, "annullata", null)], 100, 110, []);
}
