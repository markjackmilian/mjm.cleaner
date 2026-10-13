import Testing
@testable import CleanerCore

struct ConfirmationRowsTests {
    private func item(_ path: String, _ size: Int64 = 10) -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: false, declaredRoot: "/root")
    }

    private func result(_ categoryId: String, _ items: ScanItem...) -> CategoryScanResult {
        CategoryScanResult(categoryId: categoryId, items: items, totalBytes: items.reduce(0) { $0 + $1.sizeBytes }, errors: [], exclusions: [])
    }

    // IMPORTANT della revisione finale: lo stesso percorso presente in due categorie produceva due
    // righe, raggiungibile configurando le cartelle dei file grandi in sovrapposizione a una root
    // del catalogo. Una riga sola in tutto il passo, non solo dentro ciascuna categoria.
    @Test func samePathInTwoCategoriesProducesOnlyOneRowInTotal() {
        let built = ConfirmationRows.build([
            result("cat-a", item("/Users/tester/Downloads/x.zip", 100)),
            result("cat-b", item("/Users/tester/Downloads/x.zip", 100)),
        ])

        #expect(built.flatMap(\.items).filter { $0.path == "/Users/tester/Downloads/x.zip" }.count == 1)
    }

    // La prima categoria a proporlo se lo tiene; le successive non lo ripetono. Questo è ciò che
    // rende la deselezione della riga davvero esaustiva: non esiste una seconda copia dello stesso
    // percorso in un'altra categoria che il motore possa ancora ricevere.
    @Test func duplicateIsAttributedToTheFirstCategoryOnlyAndDeselectingItsRowRemovesItEntirely() throws {
        let built = ConfirmationRows.build([
            result("cat-a", item("/x/dup", 10)),
            result("cat-b", item("/x/dup", 10), item("/x/solo-b", 5)),
        ])

        let catA = try #require(built.first { $0.categoryId == "cat-a" })
        let catB = try #require(built.first { $0.categoryId == "cat-b" })
        #expect(catA.items.contains { $0.path == "/x/dup" })
        #expect(!catB.items.contains { $0.path == "/x/dup" })
        #expect(catB.items.contains { $0.path == "/x/solo-b" })
    }

    @Test func totalBytesAreNotDoubledForADuplicatePath() {
        let built = ConfirmationRows.build([
            result("cat-a", item("/x/dup", 500)),
            result("cat-b", item("/x/dup", 500), item("/x/other", 50)),
        ])

        #expect(built.flatMap(\.items).reduce(0) { $0 + $1.sizeBytes } == 550)
    }

    // La deduplicazione dentro la stessa categoria deve continuare a funzionare: due regole della
    // stessa categoria possono coprire lo stesso file.
    @Test func deduplicatesWithinTheSameCategoryToo() {
        let built = ConfirmationRows.build([result("cat-a", item("/x/dup", 10), item("/x/dup", 10))])
        #expect(built.map(\.items.count) == [1])
    }

    // Una categoria i cui percorsi sono TUTTI già stati assorbiti da una categoria precedente non
    // deve comparire come categoria vuota nel passo di conferma.
    @Test func categoryWithAllItemsClaimedByAnEarlierCategoryIsOmitted() {
        let built = ConfirmationRows.build([result("cat-a", item("/x/dup", 10)), result("cat-b", item("/x/dup", 10))])
        #expect(!built.contains { $0.categoryId == "cat-b" })
    }

    @Test func categoryWithNoItemsIsOmitted() {
        #expect(ConfirmationRows.build([result("cat-empty")]).isEmpty)
    }

    @Test func distinctPathsAcrossCategoriesAreAllKept() {
        let built = ConfirmationRows.build([result("cat-a", item("/x/a", 10)), result("cat-b", item("/x/b", 20))])
        #expect(built.flatMap(\.items).count == 2)
    }
}
