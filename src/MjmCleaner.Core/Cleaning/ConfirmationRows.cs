using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Cleaning;

/// <summary>
/// Gli elementi di una categoria dopo la deduplicazione applicata da <see cref="ConfirmationRows.Build"/>.
/// Una categoria il cui contenuto è stato interamente riassorbito da una categoria precedente
/// (stessi percorsi, proposti anche da un'altra regola) non compare nel risultato: non avrebbe
/// alcuna riga da mostrare.
/// </summary>
public sealed record ConfirmationCategory(string CategoryId, IReadOnlyList<ScanItem> Items);

/// <summary>
/// Costruisce le righe del passo di conferma a partire dagli esiti della scansione: un percorso,
/// una riga, in tutto il passo — non solo dentro la categoria che lo ha prodotto. Pura logica
/// C#, senza dipendenze dall'interfaccia: il ViewModel si limita a chiamarla ed esporne il
/// risultato, così che questa parte torni ad essere coperta dai test del Core invece che solo
/// esercitabile a mano nell'app.
/// </summary>
public static class ConfirmationRows
{
    /// <summary>
    /// Deduplica GLOBALMENTE per percorso, non solo dentro ciascuna categoria: lo stesso
    /// percorso proposto da due categorie (raggiungibile configurando le cartelle dei file
    /// grandi in sovrapposizione a una root del catalogo, per esempio la home o
    /// "~/Library/Logs") produceva prima due righe — il totale ne contava la dimensione due
    /// volte, e deselezionarlo in una categoria non lo escludeva dall'altra: il motore lo
    /// riceveva comunque. Si tiene un solo <see cref="ScanItem"/> per percorso: il primo
    /// incontrato, nell'ordine in cui i risultati sono passati (che rispecchia l'ordine delle
    /// categorie nel catalogo). È lo stesso file sul disco, quindi la stessa dimensione reale
    /// qualunque categoria l'abbia prodotto; attribuirlo alla prima è una scelta arbitraria ma
    /// stabile, e garantisce che il totale non lo conti due volte e che deselezionare la sua
    /// unica riga lo escluda davvero da tutte le selezioni consegnate al motore di pulizia.
    /// </summary>
    public static IReadOnlyList<ConfirmationCategory> Build(IReadOnlyList<CategoryScanResult> results)
    {
        HashSet<string> seenPaths = new(StringComparer.Ordinal);
        List<ConfirmationCategory> categories = [];

        foreach (CategoryScanResult result in results)
        {
            List<ScanItem> items = [];

            foreach (ScanItem item in result.Items)
            {
                if (seenPaths.Add(item.Path))
                {
                    items.Add(item);
                }
            }

            if (items.Count > 0)
            {
                categories.Add(new ConfirmationCategory(result.CategoryId, items));
            }
        }

        return categories;
    }
}
