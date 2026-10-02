using MjmCleaner.App.ViewModels;
using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.History;
using MjmCleaner.Core.Xcode;
using System.Security.Cryptography;
using System.Text;
using Xunit;

namespace MjmCleaner.App.Tests.Xcode;

public sealed class XcodeViewModelTests
{
    [Fact]
    public async Task GroupSelectionOnlyAffectsCaches()
    {
        FakeXcode service = new(Snapshot(Candidate("dd", XcodeResourceKind.DerivedData), Candidate("support", XcodeResourceKind.DeviceSupport), Candidate("device", XcodeResourceKind.Device), Candidate("runtime", XcodeResourceKind.Runtime)));
        XcodeViewModel vm = Create(service);
        await vm.InitialLoad;
        Assert.All(vm.Groups.SelectMany(g => g.Rows), row => Assert.False(row.IsSelected));
        XcodeGroupNode cache = vm.Groups.Single(g => g.Kind == XcodeResourceKind.DerivedData);
        cache.IsSelected = true;
        Assert.All(cache.Rows, row => Assert.True(row.IsSelected));
        XcodeGroupNode support = vm.Groups.Single(g => g.Kind == XcodeResourceKind.DeviceSupport);
        support.IsSelected = true;
        Assert.All(support.Rows, row => Assert.True(row.IsSelected));
        Assert.All(vm.Groups.Where(g => g.Kind is XcodeResourceKind.Device or XcodeResourceKind.Runtime).SelectMany(g => g.Rows), row => Assert.False(row.IsSelected));
        Assert.All(vm.Groups.Where(g => g.Kind is XcodeResourceKind.Device or XcodeResourceKind.Runtime), g => Assert.False(g.ShowGroupCheckBox));
    }

    [Fact]
    public async Task DeleteRequiresPreviewAndAcknowledgement()
    {
        FakeXcode service = new(Snapshot(Candidate("runtime", XcodeResourceKind.Runtime, ["device"]), Candidate("device", XcodeResourceKind.Device)));
        XcodeViewModel vm = Create(service);
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Runtime).Rows.Single().IsSelected = true;
        Assert.False(vm.ConfirmDeleteCommand.CanExecute(null));
        vm.PreviewCommand.Execute(null);
        Assert.Single(vm.Confirmation!.RetainedDependentDevices);
        Assert.False(vm.ConfirmDeleteCommand.CanExecute(null));
        vm.AcknowledgeDependencies = true;
        Assert.True(vm.ConfirmDeleteCommand.CanExecute(null));
    }

    [Fact]
    public async Task DoubleClickExecutesOnce()
    {
        FakeXcode service = new(Snapshot(Candidate("device", XcodeResourceKind.Device))) { Execution = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        XcodeViewModel vm = Create(service);
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        vm.PreviewCommand.Execute(null);
        Task first = vm.ConfirmDeleteCommand.ExecuteAsync(null);
        Task second = vm.ConfirmDeleteCommand.ExecuteAsync(null);
        Assert.Equal(1, service.ExecuteCount);
        service.Execution.SetResult(Result());
        await Task.WhenAll(first, second);
        Assert.Equal(1, service.ExecuteCount);
        Assert.False(vm.ConfirmDeleteCommand.CanExecute(null));
    }

    [Fact]
    public async Task RetryClearsOldSelection()
    {
        FakeXcode service = new(Snapshot(Candidate("one", XcodeResourceKind.Device)), Snapshot(Candidate("two", XcodeResourceKind.Device)));
        XcodeViewModel vm = Create(service);
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        await vm.RetryCommand.ExecuteAsync(null);
        Assert.Equal("two", Assert.Single(vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows).Candidate.Name);
        Assert.False(vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected);
    }

    [Fact]
    public void UnknownOnlyGroupSummaryDoesNotDisplayZeroBytes()
    {
        XcodeGroupNode group = new(XcodeResourceKind.DeviceSupport,
            [Candidate("unknown", XcodeResourceKind.DeviceSupport) with { SizeBytes = null }], []);

        Assert.Contains("dimensioni non disponibili", group.Summary, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("0 B", group.Summary, StringComparison.Ordinal);
    }

    [Fact]
    public void EmptyGroupSummaryShowsZeroEntriesWithoutSizeWarning()
    {
        XcodeGroupNode group = new(XcodeResourceKind.DeviceSupport, [], []);

        Assert.Contains("0 voci", group.Summary, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("dimensioni non disponibili", group.Summary, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void MixedGroupSummaryLabelsKnownEstimateAndUnknownCount()
    {
        XcodeGroupNode group = new(XcodeResourceKind.DerivedData,
            [Candidate("known", XcodeResourceKind.DerivedData) with { SizeBytes = 2048 }, Candidate("unknown", XcodeResourceKind.DerivedData) with { SizeBytes = null }], []);

        Assert.Contains("noti", group.Summary, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("1 dimensione non disponibile", group.Summary, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task CannotNavigateDuringDelete()
    {
        FakeXcode service = new(Snapshot(Candidate("device", XcodeResourceKind.Device))) { Execution = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        FakeNavigation navigation = new();
        XcodeViewModel vm = Create(service, navigation);
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        vm.PreviewCommand.Execute(null);
        Task deleting = vm.ConfirmDeleteCommand.ExecuteAsync(null);
        vm.CloseCommand.Execute(null);
        vm.BackToSelectionCommand.Execute(null);
        Assert.Equal(0, navigation.NavigationCount);
        Assert.False(vm.CloseCommand.CanExecute(null));
        service.Execution.SetResult(Result());
        await deleting;
    }

    [Fact]
    public async Task CancelDeleteReturnsAndPersistsPartialReportOnce()
    {
        FakeHistory history = new();
        FakeLog log = new();
        FakeXcode service = new(Snapshot(Candidate("device", XcodeResourceKind.Device)))
        {
            ExecutionHandler = (_, ct) =>
            {
                TaskCompletionSource<XcodeCleanResult> partial = new(TaskCreationOptions.RunContinuationsAsynchronously);
                ct.Register(() => partial.TrySetResult(new XcodeCleanResult(EmptyReport(),
                    [new XcodeItemResult(Candidate("device", XcodeResourceKind.Device), XcodeItemOutcome.Skipped, "annullata", null)], 10, 10, [])));
                return partial.Task;
            },
        };
        XcodeViewModel vm = new(service, history, log, new FakeNavigation());
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        vm.PreviewCommand.Execute(null);
        Task deleting = vm.ConfirmDeleteCommand.ExecuteAsync(null);
        vm.CancelDeleteCommand.Execute(null);
        await deleting;
        await vm.CurrentReport!.PersistenceTask;
        await vm.CurrentReport.PersistCommand.ExecuteAsync(null);
        Assert.Single(vm.CurrentReport.Items);
        Assert.Equal("Saltata", vm.CurrentReport.Items[0].OutcomeText);
        Assert.Equal(1, history.Saves);
        Assert.Equal(1, log.Writes);
    }

    [Fact]
    public async Task RetryAfterExecutionFailureCanConfirmAgain()
    {
        int attempts = 0;
        FakeXcode service = new(Snapshot(Candidate("device", XcodeResourceKind.Device)))
        {
            ExecutionHandler = (_, _) => ++attempts == 1
                ? Task.FromException<XcodeCleanResult>(new IOException("temporary executor failure"))
                : Task.FromResult(Result()),
        };
        FakeNavigation navigation = new();
        XcodeViewModel vm = new(service, new FakeHistory(), new FakeLog(), navigation);
        await vm.InitialLoad;
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        vm.PreviewCommand.Execute(null);
        await vm.ConfirmDeleteCommand.ExecuteAsync(null);
        Assert.Contains("temporary executor failure", vm.ErrorText, StringComparison.Ordinal);

        await vm.RetryCommand.ExecuteAsync(null);
        vm.Groups.Single(g => g.Kind == XcodeResourceKind.Device).Rows.Single().IsSelected = true;
        vm.PreviewCommand.Execute(null);
        Assert.True(vm.ConfirmDeleteCommand.CanExecute(null));
        await vm.ConfirmDeleteCommand.ExecuteAsync(null);

        Assert.Equal(2, service.ExecuteCount);
        Assert.Equal(1, navigation.NavigationCount);
        Assert.NotNull(vm.CurrentReport);
    }

    internal static XcodeSnapshot Snapshot(params XcodeCandidate[] candidates) => new(candidates, []);
    internal static XcodeCandidate Candidate(string key, XcodeResourceKind kind, IReadOnlyList<string>? dependencies = null)
    {
        string uuid = new Guid(MD5.HashData(Encoding.UTF8.GetBytes(key))).ToString("D");
        string identity = kind == XcodeResourceKind.Runtime ? "runtime:" + uuid : kind == XcodeResourceKind.Device ? uuid : key;
        return new(identity, kind, key, CliId: kind is XcodeResourceKind.Device or XcodeResourceKind.Runtime ? uuid : null,
            State: kind == XcodeResourceKind.Device ? "Shutdown" : null, SizeBytes: 100,
            Dependencies: dependencies?.Select(dep => new Guid(MD5.HashData(Encoding.UTF8.GetBytes(dep))).ToString("D")).ToArray());
    }
    internal static XcodeCleanResult Result() => new(EmptyReport(), [], 100, 120, []);
    internal static CleanReport EmptyReport() => new(DateTimeOffset.UtcNow, TimeSpan.Zero, 0, 0, 0, [], [], []);
    private static XcodeViewModel Create(FakeXcode service, FakeNavigation? nav = null) => new(service, new FakeHistory(), new FakeLog(), nav ?? new FakeNavigation());

    internal sealed class FakeXcode(params XcodeSnapshot[] snapshots) : IXcodeCleanupService
    {
        private readonly Queue<XcodeSnapshot> _snapshots = new(snapshots);
        public TaskCompletionSource<XcodeCleanResult> Execution { get; set; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Func<XcodeConfirmedPlan, CancellationToken, Task<XcodeCleanResult>>? ExecutionHandler { get; set; }
        public int ExecuteCount { get; private set; }
        public Task<XcodeSnapshot> AnalyzeAsync(CancellationToken ct) => Task.FromResult(_snapshots.Count > 1 ? _snapshots.Dequeue() : _snapshots.Peek());
        public Task<XcodeCleanResult> ExecuteAsync(XcodeConfirmedPlan plan, IProgress<CleanProgress>? progress, CancellationToken ct) { ExecuteCount++; return ExecutionHandler?.Invoke(plan, ct) ?? (Execution.Task.IsCompleted ? Task.FromResult(Result()) : Execution.Task); }
    }
    internal sealed class FakeNavigation : IXcodeNavigation
    {
        public int NavigationCount { get; private set; }
        public void GoTo(object page) => NavigationCount++;
        public void StartOver() => NavigationCount++;
        public Task RefreshTotalAsync() => Task.CompletedTask;
    }
    internal sealed class FakeHistory : IHistoryStore
    {
        public int Saves { get; private set; }
        public bool FailSave { get; set; }
        public Task InitializeAsync(CancellationToken ct) => Task.CompletedTask;
        public Task<long> SaveAsync(CleanReport report, CancellationToken ct) { Saves++; return FailSave ? Task.FromException<long>(new IOException("database unavailable")) : Task.FromResult(1L); }
        public Task<IReadOnlyList<CleanSessionSummary>> GetSessionsAsync(int limit, CancellationToken ct) => Task.FromResult<IReadOnlyList<CleanSessionSummary>>([]);
        public Task<long> GetTotalBytesFreedAsync(CancellationToken ct) => Task.FromResult(0L);
    }
    internal sealed class FakeLog : ISessionLogWriter
    {
        public int Writes { get; private set; }
        public Task WriteAsync(long sessionId, CleanReport report, CancellationToken ct) { Writes++; return Task.CompletedTask; }
    }
}
