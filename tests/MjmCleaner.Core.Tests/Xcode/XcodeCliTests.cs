using MjmCleaner.Core.Docker;
using MjmCleaner.Core.Xcode;

namespace MjmCleaner.Core.Tests.Xcode;

public class XcodeCliTests
{
    private sealed class FakeRunner(Func<IReadOnlyList<string>, ProcessResult> respond) : IProcessRunner
    {
        public List<IReadOnlyList<string>> Calls { get; } = [];
        public List<TimeSpan> Timeouts { get; } = [];

        public Task<ProcessResult> RunAsync(string fileName, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken ct, IReadOnlyDictionary<string, string>? environment = null)
        {
            Calls.Add(args.ToArray());
            Timeouts.Add(timeout);
            return Task.FromResult(respond(args));
        }
    }

    [Fact]
    public async Task DeleteUsesOnlyValidatedUuid()
    {
        FakeRunner runner = new(_ => new ProcessResult(0, "ok", string.Empty, false));
        XcodeCli cli = new(runner, "/usr/bin/xcrun");
        const string uuid = "11111111-1111-4111-8111-111111111111";

        await cli.DeleteDeviceAsync(uuid, CancellationToken.None);
        await cli.DeleteRuntimeAsync("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", CancellationToken.None);

        Assert.Equal(new[] { "simctl", "delete", uuid }, runner.Calls[0]);
        Assert.Equal(new[] { "simctl", "runtime", "delete", "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE" }, runner.Calls[1]);
        Assert.All(runner.Timeouts, timeout => Assert.Equal(TimeSpan.FromMinutes(5), timeout));
    }

    [Theory]
    [InlineData("all")]
    [InlineData("unavailable")]
    [InlineData("not-a-uuid")]
    [InlineData("--unusable")]
    public async Task InvalidDeleteIdentifiersNeverLaunchAProcess(string id)
    {
        FakeRunner runner = new(_ => new ProcessResult(0, string.Empty, string.Empty, false));
        XcodeCli cli = new(runner, "/usr/bin/xcrun");

        await Assert.ThrowsAsync<ArgumentException>(() => cli.DeleteRuntimeAsync(id, CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(() => cli.DeleteDeviceAsync(id, CancellationToken.None));

        Assert.Empty(runner.Calls);
    }

    [Fact]
    public async Task RuntimeDeleteUnsupportedIsReported()
    {
        FakeRunner runner = new(args => args.SequenceEqual(new[] { "simctl", "runtime" })
            ? new ProcessResult(1, string.Empty, "unknown operation", false)
            : new ProcessResult(0, "{}", string.Empty, false));
        XcodeCli cli = new(runner, "/usr/bin/xcrun");

        XcodeSnapshot snapshot = await cli.ReadInventoryAsync(CancellationToken.None);

        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Runtime && warning.Message.Contains("Settings", StringComparison.OrdinalIgnoreCase));
        Assert.Empty(snapshot.Candidates);
    }

    [Fact]
    public async Task InventoryCommandsUseThirtySecondTimeoutAndSeparateArguments()
    {
        FakeRunner runner = new(_ => new ProcessResult(0, "{}", string.Empty, false));
        XcodeCli cli = new(runner, "/usr/bin/xcrun");

        await cli.ReadInventoryAsync(CancellationToken.None);

        Assert.Contains(runner.Calls, args => args.SequenceEqual(new[] { "simctl", "list", "--json" }));
        Assert.Contains(runner.Calls, args => args.SequenceEqual(new[] { "simctl", "runtime", "list", "--json" }));
        Assert.All(runner.Timeouts, timeout => Assert.Equal(TimeSpan.FromSeconds(30), timeout));
    }

    [Fact]
    public async Task RuntimeInventoryIsStillReadWhenSimulatorInventoryCommandFails()
    {
        FakeRunner runner = new(args => args.SequenceEqual(new[] { "simctl", "list", "--json" })
            ? new ProcessResult(1, string.Empty, "simulator service unavailable", false)
            : args.SequenceEqual(new[] { "simctl", "runtime" })
                ? new ProcessResult(0, "delete (<identifier>)", string.Empty, false)
                : new ProcessResult(0, "{}", string.Empty, false));
        XcodeSnapshot snapshot = await new XcodeCli(runner, "/usr/bin/xcrun").ReadInventoryAsync(CancellationToken.None);

        Assert.Contains(snapshot.Warnings, warning => warning.ResourceGroup == XcodeResourceKind.Device);
        Assert.Contains(runner.Calls, args => args.SequenceEqual(new[] { "simctl", "runtime", "list", "--json" }));
    }
}
