using MjmCleaner.Core.Docker;

namespace MjmCleaner.Core.Tests.Docker;

/// <summary>
/// CLI finta: risponde con le fixture per comando (argomenti uniti da spazi) e registra ogni
/// invocazione, così i test possono verificare COSA verrebbe eseguito su un Docker vero.
/// </summary>
internal sealed class FakeDockerCli : IDockerCli
{
    private readonly Dictionary<string, Func<ProcessResult>> _responses = new(StringComparer.Ordinal);
    private readonly List<(string Prefix, Func<IReadOnlyList<string>, ProcessResult> Respond)> _prefixResponses = [];

    public List<IReadOnlyList<string>> Calls { get; } = [];

    public IEnumerable<string> CommandLines => Calls.Select(c => string.Join(' ', c));

    public FakeDockerCli On(string commandLine, string stdout)
        => On(commandLine, () => Ok(stdout));

    public FakeDockerCli On(string commandLine, Func<ProcessResult> respond)
    {
        _responses[commandLine] = respond;
        return this;
    }

    public FakeDockerCli OnPrefix(string prefix, Func<IReadOnlyList<string>, ProcessResult> respond)
    {
        _prefixResponses.Add((prefix, respond));
        return this;
    }

    public Task<ProcessResult> RunAsync(IReadOnlyList<string> args, CancellationToken ct, TimeSpan? timeout = null)
    {
        Calls.Add([.. args]);
        string line = string.Join(' ', args);

        if (_responses.TryGetValue(line, out Func<ProcessResult>? respond))
        {
            return Task.FromResult(respond());
        }

        foreach ((string prefix, Func<IReadOnlyList<string>, ProcessResult> byPrefix) in _prefixResponses)
        {
            if (line.StartsWith(prefix, StringComparison.Ordinal))
            {
                return Task.FromResult(byPrefix(args));
            }
        }

        return Task.FromResult(new ProcessResult(1, string.Empty, $"comando non previsto dal test: {line}", false));
    }

    public static ProcessResult Ok(string stdout = "") => new(0, stdout, string.Empty, false);

    public static ProcessResult Fail(string stderr) => new(1, string.Empty, stderr, false);

    /// <summary>Una CLI che risponde con l'intero caso reale delle fixture.</summary>
    public static FakeDockerCli WithRealCase()
    {
        const string Json = "{{json .}}";
        string images = string.Join('\n', DockerJson.ParseImages(DockerFixtures.Read("images.json"))
            .Select(i => $$"""{"ID":"{{i.Id}}","Repository":"x","Tag":"y"}"""));
        string volumes = string.Join('\n', DockerJson.ParseVolumes(DockerFixtures.Read("volumes.json"))
            .Select(v => $$"""{"Name":"{{v.Name}}","Driver":"local"}"""));
        string[] containerIds = [.. DockerJson.ParseContainers(DockerFixtures.Read("containers.json")).Select(c => c.Id)];

        return new FakeDockerCli()
            .On("info --format {{json .ServerVersion}}", "\"29.8.0\"\n")
            .On("ps -aq --no-trunc", string.Join('\n', containerIds) + "\n")
            .OnPrefix("container inspect ", _ => Ok(DockerFixtures.Read("containers.json")))
            .On($"images --no-trunc --format {Json}", images)
            .OnPrefix("image inspect ", _ => Ok(DockerFixtures.Read("images.json")))
            .On($"volume ls --format {Json}", volumes)
            .OnPrefix("volume inspect ", _ => Ok(DockerFixtures.Read("volumes.json")))
            .On($"system df -v --format {Json}", DockerFixtures.Read("df-verbose.json"))
            .On($"system df --format {Json}", DockerFixtures.Read("df.jsonl"));
    }
}
