namespace MjmCleaner.Core.Tests.Scanning;

internal sealed class TestTimeProvider(DateTimeOffset now) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => now;
}
