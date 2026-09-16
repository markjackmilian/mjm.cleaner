namespace MjmCleaner.Core.Safety;

/// <summary>Riconosce i collegamenti simbolici. Astratto per rendere deterministici i test del PathGuard.</summary>
public interface ILinkInspector
{
    bool IsSymbolicLink(string path);

    /// <summary>
    /// Restituisce la destinazione finale del collegamento (dopo aver seguito l'intera catena),
    /// oppure null se <paramref name="path"/> non è un collegamento simbolico. Usato da
    /// <see cref="IPathGuard.ValidateRoot"/> per risolvere una root il cui antenato sia un
    /// collegamento, invece di negarla alla cieca.
    /// </summary>
    string? ResolveLinkTarget(string path);
}
