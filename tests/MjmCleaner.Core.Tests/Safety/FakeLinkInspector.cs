using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

internal sealed class FakeLinkInspector(params string[] links) : ILinkInspector
{
    private readonly HashSet<string> _links = new(links, StringComparer.OrdinalIgnoreCase);

    public bool IsSymbolicLink(string path) => _links.Contains(path.TrimEnd('/'));
}
