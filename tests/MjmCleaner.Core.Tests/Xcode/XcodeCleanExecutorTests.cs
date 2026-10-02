using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Diagnostics;
using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Scanning;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public sealed class XcodeCleanExecutorTests
{
    private const string DeviceId = "11111111-1111-4111-8111-111111111111";
    private const string OtherDeviceId = "33333333-3333-4333-8333-333333333333";
    private const string RuntimeId = "22222222-2222-4222-8222-222222222222";

    [Fact]
    public async Task RevalidationNeverAddsItems()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(), Runtime([DeviceId])), DeviceId);
        FakeCli cli = new();
        FakeCleanEngine clean = new();
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(Snapshot(Device(), Device(OtherDeviceId)), Snapshot(Device(OtherDeviceId))), clean);

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Single(cli.DeletedDevices);
        Assert.Equal(DeviceId, cli.DeletedDevices[0]);
        Assert.Equal(0, clean.Calls);
        Assert.Single(result.Items);
        Assert.Equal(XcodeItemOutcome.Deleted, result.Items[0].Outcome);
    }

    [Fact]
    public async Task ChangedIdentityIsSkipped()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device()), DeviceId);
        FakeCli cli = new();
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(Snapshot(Device() with { Build = "new-build" })));

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Empty(cli.DeletedDevices);
        Assert.Equal(XcodeItemOutcome.Skipped, Assert.Single(result.Items).Outcome);
    }

    [Fact]
    public async Task DeviceBootedAfterConfirmationIsSkipped()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device()), DeviceId);
        FakeCli cli = new();
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(Snapshot(Device() with { State = "Booted" })));

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Empty(cli.DeletedDevices);
        Assert.Equal(XcodeItemOutcome.Skipped, Assert.Single(result.Items).Outcome);
    }

    [Fact]
    public async Task DevicesRunBeforeRuntimes()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(), Runtime([DeviceId])), DeviceId, "runtime:" + RuntimeId);
        FakeCli cli = new();
        FakeCleanEngine clean = new();
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(
            Snapshot(Device(), Runtime([DeviceId])),
            Snapshot(Runtime([])),
            Snapshot(Runtime([])),
            Snapshot([])), clean);

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(new[] { "device", "runtime" }, cli.OperationOrder);
        Assert.All(result.Items, item => Assert.Equal(XcodeItemOutcome.Deleted, item.Outcome));
        Assert.Equal(0, clean.Calls);
    }

    [Fact]
    public async Task DeviceFailureSkipsDependentRuntime()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(), Runtime([DeviceId])), DeviceId, "runtime:" + RuntimeId);
        FakeCli cli = new() { DeviceResult = new ProcessResult(1, "", "in use", false) };
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(Snapshot(Device(), Runtime([DeviceId]))));

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(new[] { "device" }, cli.OperationOrder);
        Assert.Equal(XcodeItemOutcome.Failed, result.Items[0].Outcome);
        Assert.Equal(XcodeItemOutcome.Skipped, result.Items[1].Outcome);
    }

    [Fact]
    public async Task NewRuntimeDependencyAfterConfirmationSkipsRuntime()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(), Runtime([DeviceId])), "runtime:" + RuntimeId);
        FakeCli cli = new();
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(Snapshot(Device(), Device(OtherDeviceId), Runtime([DeviceId, OtherDeviceId]))));

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Empty(cli.OperationOrder);
        Assert.Equal(XcodeItemOutcome.Skipped, Assert.Single(result.Items).Outcome);
    }

    [Fact]
    public async Task TimeoutWithUnreadableInventoryIsUncertain()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device()), DeviceId);
        FakeCli cli = new() { DeviceResult = new ProcessResult(-1, "", "", true) };
        QueueCollector collector = new(Snapshot(Device()), Snapshot([], new XcodeInventoryWarning(XcodeResourceKind.Device, "unavailable")));

        XcodeCleanResult result = await Create(cli, collector).ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(XcodeItemOutcome.Uncertain, Assert.Single(result.Items).Outcome);
        Assert.Single(cli.DeletedDevices);
    }

    [Fact]
    public async Task IncompletePostCommandInventoryCannotVerifyAbsence()
    {
        const string malformedSimctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"33333333-3333-4333-8333-333333333333","name":"iPhone 16","state":"Shutdown","dataPathSize":[]},
              {"name":"missing UUID","state":"Shutdown"}]}}
            """;
        XcodeSnapshot incomplete = XcodeJson.ParseInventory(malformedSimctl, "{}", runtimeDeleteSupported: true);
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(size: 500)), DeviceId);
        FakeCli cli = new();
        FakeCleanEngine clean = new();

        XcodeCleanResult result = await Create(cli, new QueueCollector(Snapshot(Device(size: 500)), incomplete), clean)
            .ExecuteAsync(plan, null, CancellationToken.None);

        Assert.DoesNotContain(incomplete.Candidates, candidate => candidate.Key == DeviceId);
        Assert.Equal(XcodeItemOutcome.Uncertain, Assert.Single(result.Items).Outcome);
        Assert.Equal(0, result.HistoryReport.BytesFreed);
        Assert.Single(cli.DeletedDevices);
        Assert.Equal(0, clean.Calls);
    }

    [Fact]
    public async Task FailedCommandAndAbsentResourceIsNotCredited()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(size: 500)), DeviceId);
        FakeCli cli = new() { DeviceResult = new ProcessResult(1, "", "failed", false) };
        FakeCleanEngine clean = new();
        XcodeCleanResult result = await Create(cli, new QueueCollector(Snapshot(Device(size: 500)), Snapshot([])), clean)
            .ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(XcodeItemOutcome.Failed, Assert.Single(result.Items).Outcome);
        Assert.Equal(0, result.HistoryReport.BytesFreed);
        Assert.Equal(0, clean.Calls);
    }

    [Fact]
    public async Task TimedOutCommandAndAbsentResourceIsUncertainWithoutCredit()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(size: 500)), DeviceId);
        FakeCli cli = new() { DeviceResult = new ProcessResult(0, "", "", true) };
        FakeCleanEngine clean = new();
        XcodeCleanResult result = await Create(cli, new QueueCollector(Snapshot(Device(size: 500)), Snapshot([])), clean)
            .ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(XcodeItemOutcome.Uncertain, Assert.Single(result.Items).Outcome);
        Assert.Equal(0, result.HistoryReport.BytesFreed);
        Assert.Equal(0, clean.Calls);
    }

    [Fact]
    public async Task CancelledCommandAndAbsentResourceIsUncertainWithoutCredit()
    {
        using CancellationTokenSource cts = new();
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(size: 500)), DeviceId);
        FakeCli cli = new() { OnDeviceDelete = _ => cts.Cancel() };
        XcodeCleanResult result = await Create(cli, new QueueCollector(Snapshot(Device(size: 500)), Snapshot([])))
            .ExecuteAsync(plan, null, cts.Token);

        Assert.Equal(XcodeItemOutcome.Uncertain, Assert.Single(result.Items).Outcome);
        Assert.Equal(0, result.HistoryReport.BytesFreed);
    }

    [Fact]
    public async Task CommandExceptionAndAbsentResourceIsNotCredited()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(size: 500)), DeviceId);
        FakeCli cli = new() { DeviceException = new InvalidOperationException("runner failed") };
        XcodeCleanResult result = await Create(cli, new QueueCollector(Snapshot(Device(size: 500)), Snapshot([])))
            .ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(XcodeItemOutcome.Failed, Assert.Single(result.Items).Outcome);
        Assert.Equal(0, result.HistoryReport.BytesFreed);
    }

    [Fact]
    public async Task AdvisoryRuntimeSizeWarningDoesNotBlockDeleteOrVerification()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Runtime([])), "runtime:" + RuntimeId);
        XcodeInventoryWarning advisory = new(XcodeResourceKind.Runtime, "runtime size unknown") { Kind = XcodeInventoryWarningKind.Advisory };
        FakeCli cli = new();
        FakeCleanEngine clean = new();
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(
            Snapshot([Runtime([])], advisory),
            Snapshot([], advisory)), clean);

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(new[] { "runtime" }, cli.OperationOrder);
        Assert.Equal(XcodeItemOutcome.Deleted, Assert.Single(result.Items).Outcome);
        Assert.Equal(200, result.HistoryReport.BytesFreed);
        Assert.Equal(0, clean.Calls);
    }

    [Fact]
    public async Task CompletenessWarningStillBlocksRuntimeDelete()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Runtime([])), "runtime:" + RuntimeId);
        FakeCli cli = new();
        FakeCleanEngine clean = new();
        XcodeInventoryWarning incomplete = new(XcodeResourceKind.Runtime, "runtime inventory incomplete");
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(Snapshot([Runtime([])], incomplete)), clean);

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Empty(cli.OperationOrder);
        Assert.Equal(XcodeItemOutcome.Skipped, Assert.Single(result.Items).Outcome);
        Assert.Equal(0, clean.Calls);
    }

    [Fact]
    public async Task CancellationRetainsCompletedResults()
    {
        using CancellationTokenSource cts = new();
        FakeCli cli = new();
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(), Device(OtherDeviceId)), DeviceId, OtherDeviceId);
        QueueCollector collector = new(Snapshot(Device(), Device(OtherDeviceId)), Snapshot(Device(OtherDeviceId)));

        IProgress<CleanProgress> progress = new SynchronousProgress(value =>
        {
            if (value.ItemsDone == 1) cts.Cancel();
        });
        XcodeCleanResult result = await Create(cli, collector).ExecuteAsync(plan, progress, cts.Token);

        Assert.Equal(2, result.Items.Count);
        Assert.Equal(XcodeItemOutcome.Deleted, result.Items[0].Outcome);
        Assert.Equal(XcodeItemOutcome.Skipped, result.Items[1].Outcome);
        Assert.Single(cli.DeletedDevices);
    }

    [Fact]
    public async Task FailedAndUnknownSizesDoNotIncreaseHistoryBytes()
    {
        XcodeCandidate unknown = Device(OtherDeviceId) with { SizeBytes = null };
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(size: 500), unknown), DeviceId, OtherDeviceId);
        FakeCli cli = new() { DeviceResult = new ProcessResult(1, "", "failure", false) };
        XcodeCleanResult result = await Create(cli, new QueueCollector(Snapshot(Device(size: 500), unknown), Snapshot(Device(size: 500), unknown), Snapshot(Device(size: 500), unknown), Snapshot(unknown)))
            .ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(0, result.HistoryReport.BytesFreed);
        Assert.Null(result.Items[0].VerifiedEstimatedBytes);
    }

    [Fact]
    public async Task IndependentFailureDoesNotStopOtherItems()
    {
        XcodeConfirmedPlan plan = Confirm(Snapshot(Device(), Device(OtherDeviceId)), DeviceId, OtherDeviceId);
        FakeCli cli = new() { DeviceResult = new ProcessResult(1, "", "failure", false), DeviceResultForSecond = new ProcessResult(0, "", "", false) };
        XcodeCleanExecutor executor = Create(cli, new QueueCollector(
            Snapshot(Device(), Device(OtherDeviceId)), Snapshot(Device(), Device(OtherDeviceId)),
            Snapshot(Device(), Device(OtherDeviceId)), Snapshot(Device())));

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(new[] { DeviceId, OtherDeviceId }, cli.DeletedDevices);
        Assert.Equal(new[] { XcodeItemOutcome.Failed, XcodeItemOutcome.Deleted }, result.Items.Select(item => item.Outcome));
    }

    [Fact]
    public async Task XcodeStartedAfterConfirmationBlocksFilesWithoutCallingCleanEngine()
    {
        string path = "/Users/test/Library/Developer/Xcode/DerivedData/App-abc";
        ScanItem scan = new(path, 50, true, "/Users/test/Library/Developer/Xcode/DerivedData");
        XcodeFileIdentity identity = new(path, true, DateTime.UnixEpoch.AddDays(1), DateTime.UnixEpoch.AddDays(2), 50);
        const string key = "derived-data:/Users/test/Library/Developer/Xcode/DerivedData/App-abc";
        XcodeSnapshot source = new([new XcodeCandidate(key, XcodeResourceKind.DerivedData, "App-abc", path, SizeBytes: 10)], [])
        {
            FileInventory = new XcodeFileInventory([new KeyValuePair<string, XcodeFileEntry>(key, new XcodeFileEntry(scan, identity))]),
        };
        XcodeConfirmedPlan plan = Confirm(source, key);
        FakeCli cli = new();
        FakeCleanEngine clean = new();
        XcodeCleanExecutor executor = new(cli, new QueueCollector(source), clean, new FakeSizeProbe(), new QueueRunningProbe(XcodeRunningState.Running), TimeProvider.System);

        XcodeCleanResult result = await executor.ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(0, clean.Calls);
        Assert.Equal(XcodeItemOutcome.Skipped, Assert.Single(result.Items).Outcome);
        Assert.Empty(cli.DeletedDevices);
    }

    [Fact]
    public async Task ParsedUnavailableDeviceCanBeDeletedThroughExecutor()
    {
        XcodeSnapshot unavailable = ParseUnavailableDevice();
        XcodeConfirmedPlan plan = Confirm(unavailable, DeviceId);
        FakeCli cli = new();
        XcodeSnapshot after = XcodeJson.ParseInventory("""{"runtimes":[],"devices":{}}""", "{}", runtimeDeleteSupported: true);

        XcodeCleanResult result = await Create(cli, new QueueCollector(unavailable, after)).ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(new[] { DeviceId }, cli.DeletedDevices);
        Assert.Equal(XcodeItemOutcome.Deleted, Assert.Single(result.Items).Outcome);
    }

    [Fact]
    public async Task ParsedUnavailableDependencyDoesNotBlockRuntimeDelete()
    {
        XcodeSnapshot unavailable = ParseUnavailableDevice(includeRuntime: true);
        XcodeConfirmedPlan plan = Confirm(unavailable, "runtime:" + RuntimeId);
        FakeCli cli = new();
        XcodeSnapshot after = XcodeJson.ParseInventory("""{"runtimes":[],"devices":{}}""", "{}", runtimeDeleteSupported: true);

        XcodeCleanResult result = await Create(cli, new QueueCollector(unavailable, after)).ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(new[] { "runtime" }, cli.OperationOrder);
        Assert.Equal(XcodeItemOutcome.Deleted, Assert.Single(result.Items).Outcome);
    }

    [Fact]
    public async Task ParsedUnknownDeviceStateRemainsBlockedAtExecutor()
    {
        const string simctl = """
            {"runtimes":[],"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"MysteryState"}]}}
            """;
        XcodeSnapshot unknown = XcodeJson.ParseInventory(simctl, "{}", runtimeDeleteSupported: true);
        FakeCli cli = new();

        Assert.Throws<ArgumentException>(() => Confirm(unknown, DeviceId));
        Assert.Empty(cli.DeletedDevices);
    }

    [Fact]
    public async Task FileHistoryUsesFreshAllocatedSizeInsteadOfLogicalBytesFreed()
    {
        const string path = "/Users/test/Library/Developer/Xcode/DerivedData/App-abc";
        const string key = "derived-data:/Users/test/Library/Developer/Xcode/DerivedData/App-abc";
        const long allocatedBytes = 1_048_576;
        const long logicalBytes = 10L * 1024 * 1024 * 1024;
        XcodeSnapshot preview = FileSnapshot(path, key, allocatedBytes: 4_194_304);
        XcodeSnapshot fresh = FileSnapshot(path, key, allocatedBytes);
        XcodeConfirmedPlan plan = Confirm(preview, key);
        FakeCleanEngine clean = new() { BytesFreed = logicalBytes, ItemsDeleted = 1 };

        XcodeCleanResult result = await Create(new FakeCli(), new QueueCollector(fresh), clean).ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Equal(allocatedBytes, Assert.Single(result.Items).VerifiedEstimatedBytes);
        Assert.Equal(allocatedBytes, result.HistoryReport.BytesFreed);
    }

    [Fact]
    public async Task FileHistoryLeavesSizeUnknownWhenFreshAllocatedMeasureIsUnavailable()
    {
        const string path = "/Users/test/Library/Developer/Xcode/DerivedData/App-abc";
        const string key = "derived-data:/Users/test/Library/Developer/Xcode/DerivedData/App-abc";
        XcodeSnapshot preview = FileSnapshot(path, key, allocatedBytes: 4_194_304);
        XcodeSnapshot fresh = FileSnapshot(path, key, allocatedBytes: null);
        XcodeConfirmedPlan plan = Confirm(preview, key);
        FakeCleanEngine clean = new() { BytesFreed = 10L * 1024 * 1024 * 1024, ItemsDeleted = 1 };

        XcodeCleanResult result = await Create(new FakeCli(), new QueueCollector(fresh), clean).ExecuteAsync(plan, null, CancellationToken.None);

        Assert.Null(Assert.Single(result.Items).VerifiedEstimatedBytes);
        Assert.Equal(0, result.HistoryReport.BytesFreed);
    }

    private static XcodeCleanExecutor Create(FakeCli cli, IXcodeInventoryCollector collector, FakeCleanEngine? clean = null)
        => new(cli, collector, clean ?? new FakeCleanEngine(), new FakeSizeProbe(), new QueueRunningProbe(XcodeRunningState.NotRunning), TimeProvider.System);

    private static XcodeSnapshot Snapshot(params XcodeCandidate[] candidates)
        => new(candidates, []);

    private static XcodeSnapshot Snapshot(XcodeCandidate[] candidates, params XcodeInventoryWarning[] warnings)
        => new(candidates, warnings);

    private static XcodeCandidate Device(string id = DeviceId, long? size = 100)
        => new(id, XcodeResourceKind.Device, "iPhone", CliId: id, Build: "build-1", State: "Shutdown", SizeBytes: size);

    private static XcodeCandidate Runtime(IReadOnlyList<string> dependencies)
        => new("runtime:" + RuntimeId, XcodeResourceKind.Runtime, "iOS 18", CliId: RuntimeId, RuntimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-0", Build: "runtime-build", SizeBytes: 200, Dependencies: dependencies);

    private static XcodeConfirmedPlan Confirm(XcodeSnapshot source, params string[] selected)
        => XcodeSelection.Confirm(XcodeSelection.Preview(source, selected.ToHashSet(StringComparer.Ordinal)), acknowledgeDependencies: true);

    private static XcodeSnapshot ParseUnavailableDevice(bool includeRuntime = false)
    {
        const string simctl = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-0":[
              {"udid":"11111111-1111-4111-8111-111111111111","name":"iPhone 16","state":"Unavailable"}]},
             "runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","name":"iOS 18","version":"18.0","buildversion":"22A3351","platform":"iOS"}]}
            """;
        const string images = """
            {"22222222-2222-4222-8222-222222222222":{"identifier":"22222222-2222-4222-8222-222222222222","runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-0","version":"18.0","build":"22A3351","deletable":true}}
            """;
        return XcodeJson.ParseInventory(simctl, includeRuntime ? images : "{}", runtimeDeleteSupported: true);
    }

    private static XcodeSnapshot FileSnapshot(string path, string key, long? allocatedBytes)
    {
        ScanItem scan = new(path, 10L * 1024 * 1024 * 1024, true, "/Users/test/Library/Developer/Xcode/DerivedData");
        XcodeFileIdentity identity = new(path, true, DateTime.UnixEpoch.AddDays(1), DateTime.UnixEpoch.AddDays(2), scan.SizeBytes);
        return new XcodeSnapshot([new XcodeCandidate(key, XcodeResourceKind.DerivedData, "App-abc", path, SizeBytes: allocatedBytes)], [])
        {
            FileInventory = new XcodeFileInventory([new KeyValuePair<string, XcodeFileEntry>(key, new XcodeFileEntry(scan, identity))]),
        };
    }

    private sealed class QueueCollector(params XcodeSnapshot[] snapshots) : IXcodeInventoryCollector
    {
        private int _index;
        public Task<XcodeSnapshot> CollectAsync(CancellationToken ct)
        {
            int index = Math.Min(_index++, snapshots.Length - 1);
            return Task.FromResult(snapshots[index]);
        }
    }

    private sealed class FakeCli : IXcodeCli
    {
        public List<string> DeletedDevices { get; } = [];
        public List<string> OperationOrder { get; } = [];
        public ProcessResult DeviceResult { get; set; } = new(0, "", "", false);
        public ProcessResult DeviceResultForSecond { get; set; } = new(0, "", "", false);
        public Action<string>? OnDeviceDelete { get; set; }
        public Exception? DeviceException { get; set; }
        public Task<XcodeSnapshot> ReadInventoryAsync(CancellationToken ct) => Task.FromResult(XcodeSnapshot.Empty);
        public Task<ProcessResult> DeleteDeviceAsync(string uuid, CancellationToken ct)
        {
            DeletedDevices.Add(uuid);
            OperationOrder.Add("device");
            OnDeviceDelete?.Invoke(uuid);
            if (DeviceException is not null) throw DeviceException;
            return Task.FromResult(DeletedDevices.Count == 1 ? DeviceResult : DeviceResultForSecond);
        }
        public Task<ProcessResult> DeleteRuntimeAsync(string uuid, CancellationToken ct)
        {
            OperationOrder.Add("runtime");
            return Task.FromResult(new ProcessResult(0, "", "", false));
        }
    }

    private sealed class FakeCleanEngine : ICleanEngine
    {
        public int Calls { get; private set; }
        public long BytesFreed { get; set; }
        public int ItemsDeleted { get; set; }
        public Task<CleanReport> CleanAsync(IReadOnlyList<CategorySelection> selections, IProgress<CleanProgress>? progress, CancellationToken ct)
        {
            Calls++;
            return Task.FromResult(new CleanReport(DateTimeOffset.UnixEpoch, TimeSpan.Zero, BytesFreed, ItemsDeleted, 0, [], [], []));
        }
    }

    private sealed class SynchronousProgress(Action<CleanProgress> report) : IProgress<CleanProgress>
    {
        public void Report(CleanProgress value) => report(value);
    }

    private sealed class FakeSizeProbe : IXcodeSizeProbe
    {
        public Task<long?> MeasureAsync(string path, CancellationToken ct) => Task.FromResult<long?>(null);
        public Task<long?> GetFreeBytesAsync(CancellationToken ct) => Task.FromResult<long?>(1000);
    }

    private sealed class QueueRunningProbe(params XcodeRunningState[] states) : IXcodeRunningProbe
    {
        private int _index;
        public Task<XcodeRunningState> GetStateAsync(CancellationToken ct)
            => Task.FromResult(states[Math.Min(_index++, states.Length - 1)]);
    }
}
