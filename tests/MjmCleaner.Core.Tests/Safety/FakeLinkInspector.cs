using MjmCleaner.Core.Safety;

namespace MjmCleaner.Core.Tests.Safety;

/// <summary>
/// Doppio di test per <see cref="ILinkInspector"/>. Il costruttore a elenco di percorsi marca
/// ciascuno come collegamento simbolico con destinazione non specificata (<see cref="ResolveLinkTarget"/>
/// restituisce null per essi): usato dai test che verificano solo <c>IsSymbolicLink</c>, dove la
/// destinazione non conta. Il costruttore a mappa marca ciascun percorso con la destinazione
/// finale indicata: usato dai test che verificano la risoluzione in <c>PathGuard.ValidateRoot</c>.
/// </summary>
internal sealed class FakeLinkInspector : ILinkInspector
{
    private readonly Dictionary<string, string?> _links;

    public FakeLinkInspector(params string[] links)
        : this(links.ToDictionary(path => path, _ => (string?)null))
    {
    }

    public FakeLinkInspector(IReadOnlyDictionary<string, string?> links)
    {
        _links = new Dictionary<string, string?>(links, StringComparer.OrdinalIgnoreCase);
    }

    public bool IsSymbolicLink(string path) => _links.ContainsKey(path.TrimEnd('/'));

    public string? ResolveLinkTarget(string path)
        => _links.TryGetValue(path.TrimEnd('/'), out string? target) ? target : null;
}
