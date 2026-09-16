namespace MjmCleaner.Core.Safety;

/// <summary>Riconosce i collegamenti simbolici. Astratto per rendere deterministici i test del PathGuard.</summary>
public interface ILinkInspector
{
    bool IsSymbolicLink(string path);
}
