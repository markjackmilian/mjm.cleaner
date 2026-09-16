using MjmCleaner.Core.Cleaning;
using MjmCleaner.Core.Scanning;

namespace MjmCleaner.Core.Tests.Cleaning;

public class ConfirmationRowsTests
{
    private static ScanItem Item(string path, long size = 10, string root = "/root")
        => new(path, size, false, root);

    private static CategoryScanResult Result(string categoryId, params ScanItem[] items)
        => new(categoryId, items, items.Sum(i => i.SizeBytes), [], []);

    // IMPORTANT della revisione finale: lo stesso percorso presente in due categorie produceva
    // due righe, raggiungibile configurando le cartelle dei file grandi in sovrapposizione a
    // una root del catalogo. Una riga sola in tutto il passo, non solo dentro ciascuna categoria.
    [Fact]
    public void SamePathInTwoCategoriesProducesOnlyOneRowInTotal()
    {
        CategoryScanResult a = Result("cat-a", Item("/Users/tester/Downloads/x.zip", 100));
        CategoryScanResult b = Result("cat-b", Item("/Users/tester/Downloads/x.zip", 100));

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([a, b]);

        Assert.Single(built.SelectMany(c => c.Items), i => i.Path == "/Users/tester/Downloads/x.zip");
    }

    // La prima categoria a proporlo se lo tiene; le successive non lo ripetono. Questo è ciò
    // che rende la deselezione della riga davvero esaustiva: non esiste una seconda copia dello
    // stesso percorso in un'altra categoria che il motore possa ancora ricevere.
    [Fact]
    public void DuplicateIsAttributedToTheFirstCategoryOnlyAndDeselectingItsRowRemovesItEntirely()
    {
        CategoryScanResult a = Result("cat-a", Item("/x/dup", 10));
        CategoryScanResult b = Result("cat-b", Item("/x/dup", 10), Item("/x/solo-b", 5));

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([a, b]);

        ConfirmationCategory catA = built.Single(c => c.CategoryId == "cat-a");
        ConfirmationCategory catB = built.Single(c => c.CategoryId == "cat-b");

        Assert.Contains(catA.Items, i => i.Path == "/x/dup");
        Assert.DoesNotContain(catB.Items, i => i.Path == "/x/dup");
        Assert.Contains(catB.Items, i => i.Path == "/x/solo-b");
    }

    [Fact]
    public void TotalBytesAreNotDoubledForADuplicatePath()
    {
        CategoryScanResult a = Result("cat-a", Item("/x/dup", 500));
        CategoryScanResult b = Result("cat-b", Item("/x/dup", 500), Item("/x/other", 50));

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([a, b]);

        long total = built.SelectMany(c => c.Items).Sum(i => i.SizeBytes);
        Assert.Equal(550, total);
    }

    // La deduplicazione dentro la stessa categoria (già presente prima della correzione) deve
    // continuare a funzionare: due regole della stessa categoria possono coprire lo stesso file.
    [Fact]
    public void DeduplicatesWithinTheSameCategoryToo()
    {
        CategoryScanResult a = Result("cat-a", Item("/x/dup", 10), Item("/x/dup", 10));

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([a]);

        Assert.Single(built.Single().Items);
    }

    // Una categoria i cui percorsi sono TUTTI già stati assorbiti da una categoria precedente
    // non deve comparire come categoria vuota nel passo di conferma.
    [Fact]
    public void CategoryWithAllItemsClaimedByAnEarlierCategoryIsOmitted()
    {
        CategoryScanResult a = Result("cat-a", Item("/x/dup", 10));
        CategoryScanResult b = Result("cat-b", Item("/x/dup", 10));

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([a, b]);

        Assert.DoesNotContain(built, c => c.CategoryId == "cat-b");
    }

    [Fact]
    public void CategoryWithNoItemsIsOmitted()
    {
        CategoryScanResult empty = Result("cat-empty");

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([empty]);

        Assert.Empty(built);
    }

    [Fact]
    public void DistinctPathsAcrossCategoriesAreAllKept()
    {
        CategoryScanResult a = Result("cat-a", Item("/x/a", 10));
        CategoryScanResult b = Result("cat-b", Item("/x/b", 20));

        IReadOnlyList<ConfirmationCategory> built = ConfirmationRows.Build([a, b]);

        Assert.Equal(2, built.SelectMany(c => c.Items).Count());
    }
}
