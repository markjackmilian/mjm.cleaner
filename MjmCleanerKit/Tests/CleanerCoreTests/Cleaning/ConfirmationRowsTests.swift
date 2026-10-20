import Testing
@testable import CleanerCore

struct ConfirmationRowsTests {
    private func item(_ path: String, _ size: Int64 = 10, directory: Bool = false, root: String = "/root") -> ScanItem {
        ScanItem(path: path, sizeBytes: size, isDirectory: directory, declaredRoot: root)
    }

    private func result(_ categoryId: String, _ items: ScanItem...) -> CategoryScanResult {
        CategoryScanResult(categoryId: categoryId, items: items, totalBytes: items.reduce(0) { $0 + $1.sizeBytes }, errors: [], exclusions: [])
    }

    /// Le root si risolvono con la mappa; una root assente resta com'è dichiarata.
    private func build(_ results: [CategoryScanResult], roots: [String: String] = [:]) -> [ConfirmationCategory] {
        ConfirmationRows.build(results) { roots[$0] ?? $0 }
    }

    private func position(_ category: Int, _ row: Int) -> ConfirmationPosition {
        ConfirmationPosition(category: category, row: row)
    }

    // IMPORTANT della revisione finale: lo stesso percorso presente in due categorie produceva due
    // righe, raggiungibile configurando le cartelle dei file grandi in sovrapposizione a una root
    // del catalogo. Una riga sola in tutto il passo, non solo dentro ciascuna categoria.
    @Test func samePathInTwoCategoriesProducesOnlyOneRowInTotal() {
        let built = build([
            result("cat-a", item("/Users/tester/Downloads/x.zip", 100)),
            result("cat-b", item("/Users/tester/Downloads/x.zip", 100)),
        ])

        #expect(built.flatMap(\.items).filter { $0.path == "/Users/tester/Downloads/x.zip" }.count == 1)
    }

    // La prima categoria a proporlo se lo tiene; le successive non lo ripetono. Questo è ciò che
    // rende la deselezione della riga davvero esaustiva: non esiste una seconda copia dello stesso
    // percorso in un'altra categoria che il motore possa ancora ricevere.
    @Test func duplicateIsAttributedToTheFirstCategoryOnlyAndDeselectingItsRowRemovesItEntirely() throws {
        let built = build([
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
        let built = build([
            result("cat-a", item("/x/dup", 500)),
            result("cat-b", item("/x/dup", 500), item("/x/other", 50)),
        ])

        #expect(built.flatMap(\.items).reduce(0) { $0 + $1.sizeBytes } == 550)
    }

    // La deduplicazione dentro la stessa categoria deve continuare a funzionare: due regole della
    // stessa categoria possono coprire lo stesso file.
    @Test func deduplicatesWithinTheSameCategoryToo() {
        let built = build([result("cat-a", item("/x/dup", 10), item("/x/dup", 10))])
        #expect(built.map(\.items.count) == [1])
    }

    // Una categoria i cui percorsi sono TUTTI già stati assorbiti da una categoria precedente non
    // deve comparire come categoria vuota nel passo di conferma.
    @Test func categoryWithAllItemsClaimedByAnEarlierCategoryIsOmitted() {
        let built = build([result("cat-a", item("/x/dup", 10)), result("cat-b", item("/x/dup", 10))])
        #expect(!built.contains { $0.categoryId == "cat-b" })
    }

    @Test func categoryWithNoItemsIsOmitted() {
        #expect(build([result("cat-empty")]).isEmpty)
    }

    @Test func distinctPathsAcrossCategoriesAreAllKept() {
        let built = build([result("cat-a", item("/x/a", 10)), result("cat-b", item("/x/b", 20))])
        #expect(built.flatMap(\.items).count == 2)
    }

    // Contenimento (spec `2026-10-20-confirmation-containment-design.md`).

    /// Il caso segnalato: con «File grandi» su `~`, il modello sotto `~/.cache/huggingface` sta nella
    /// cartella che «Cache di sviluppo» propone.
    @Test func aFileInsideAFolderOfAnotherCategoryPointsToThatFolder() {
        let built = build([
            result("dev-caches", item("/Users/tester/.cache/huggingface", 5_900, directory: true, root: "/Users/tester/.cache")),
            result("large-files", item("/Users/tester/.cache/huggingface/hub/model.bin", 4_800, root: "/Users/tester")),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[nil], [position(0, 0)]])
    }

    @Test func containmentDoesNotDependOnTheOrderOfTheGroups() {
        let built = build([
            result("downloads", item("/Users/tester/Downloads/progetto/bin/Debug/app.dll")),
            result("project-build-output", item("/Users/tester/Downloads/progetto/bin", directory: true)),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[position(1, 0)], [nil]])
    }

    @Test func theNearestFolderOfAChainIsTheContainer() {
        let built = build([
            result("cat-c", item("/x/a/b/c.bin")),
            result("cat-a", item("/x/a", directory: true)),
            result("cat-b", item("/x/a/b", directory: true)),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[position(2, 0)], [nil], [position(1, 0)]])
    }

    /// Confine di segmento: `/x/cache` non contiene `/x/cacheExtra/f`.
    @Test func aFolderDoesNotContainASiblingWithACommonPrefix() {
        let built = build([
            result("cat-a", item("/x/cache", directory: true)),
            result("cat-b", item("/x/cacheExtra/f"), item("/x/cache.old")),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[nil], [nil, nil]])
    }

    /// Solo cartelle e pacchetti contengono. Il caso non si presenta sul disco, ma fissa che la
    /// regola guarda `isDirectory` e non solo il testo.
    @Test func aFileContainsNothing() {
        let built = build([result("cat-a", item("/x/a")), result("cat-b", item("/x/a/b"))])

        #expect(built.map { $0.rows.map(\.container) } == [[nil], [nil]])
    }

    @Test func aSameCategoryFolderAlsoContains() {
        let built = build([result("large-files", item("/x/vm.pvm", directory: true), item("/x/vm.pvm/disk.hdd"))])

        #expect(built.map { $0.rows.map(\.container) } == [[nil, position(0, 0)]])
    }

    /// APFS non distingue maiuscole e grafie: `~/Progetti/App/bin` e `~/progetti/APP/BIN` sono la
    /// stessa cartella, e «Straße» è «STRASSE».
    @Test func samePathWithDifferentCaseOrSpellingIsOneRow() {
        let built = build([
            result("cat-a", item("/Users/tester/Progetti/App/bin", directory: true), item("/Users/tester/Lavoro/Café.mov")),
            result("cat-b", item("/Users/tester/progetti/APP/BIN", directory: true), item("/Users/tester/LAVORO/Cafe\u{301}.mov")),
            result("cat-c", item("/Users/tester/Archivio/Straße.zip"), item("/Users/tester/Archivio/STRASSE.zip")),
        ])

        #expect(built.map { $0.items.map(\.path) } == [
            ["/Users/tester/Progetti/App/bin", "/Users/tester/Lavoro/Café.mov"],
            ["/Users/tester/Archivio/Straße.zip"],
        ])
    }

    @Test func containmentIgnoresCaseAndSpelling() {
        let built = build([
            result("cat-a", item("/Users/tester/Lavoro/Straße", directory: true), item("/Users/tester/Lavoro/Caf\u{E9}", directory: true)),
            result("cat-b", item("/Users/tester/lavoro/STRASSE/video.mov"), item("/Users/tester/Lavoro/CAFE\u{301}/foto.raw")),
        ])

        #expect(built.map { $0.rows.map(\.container) } == [[nil, nil], [position(0, 0), position(0, 1)]])
    }

    /// `~/.cache` è un collegamento a `~/Dati/cache` e «File grandi» guarda `~/Dati`: il modello sta
    /// nella cartella che il motore cancellerà, anche se il testo dei due percorsi non lo dice.
    @Test func aLinkedRootIsComparedWhereItLeads() {
        let results = [
            result("dev-caches", item("/Users/tester/.cache/huggingface", directory: true, root: "/Users/tester/.cache")),
            result("large-files", item("/Users/tester/Dati/cache/huggingface/model.bin", root: "/Users/tester/Dati")),
        ]

        #expect(build(results, roots: ["/Users/tester/.cache": "/Users/tester/Dati/cache"]).map { $0.rows.map(\.container) }
            == [[nil], [position(0, 0)]])
        #expect(build(results).map { $0.rows.map(\.container) } == [[nil], [nil]])
    }

    @Test func twoSpellingsThatLeadToTheSameFolderAreOneRow() {
        let built = build(
            [
                result("dev-caches", item("/Users/tester/.cache/pip", directory: true, root: "/Users/tester/.cache")),
                result("large-files", item("/Users/tester/Dati/cache/pip", directory: true, root: "/Users/tester/Dati")),
            ],
            roots: ["/Users/tester/.cache": "/Users/tester/Dati/cache"])

        #expect(built.map { $0.items.map(\.path) } == [["/Users/tester/.cache/pip"]])
    }

    @Test func eachDeclaredRootIsResolvedOnce() {
        var asked: [String] = []
        _ = ConfirmationRows.build([
            result("cat-a", item("/a/1", root: "/a"), item("/a/2", root: "/a")),
            result("cat-b", item("/a/3", root: "/a"), item("/b/1", root: "/b")),
        ]) { root in
            asked.append(root)
            return root
        }

        #expect(asked == ["/a", "/b"])
    }

    // `selections`: che cosa riceve il motore.

    private func selections(_ categories: [ConfirmationCategory], selected: Set<ConfirmationPosition>) -> [[String]] {
        ConfirmationRows.selections(categories) { selected.contains($0) }.map { $0.items.map(\.path) }
    }

    private var cacheAndModel: [ConfirmationCategory] {
        build([
            result("dev-caches", item("/u/.cache/huggingface", directory: true)),
            result("large-files", item("/u/.cache/huggingface/model.bin"), item("/u/Movies/raw.mov")),
        ])
    }

    @Test func aRowCoveredByASelectedFolderIsNotSent() {
        let sent = ConfirmationRows.selections(cacheAndModel) { _ in true }

        #expect(sent.map(\.categoryId) == ["dev-caches", "large-files"])
        #expect(sent.map { $0.items.map(\.path) } == [["/u/.cache/huggingface"], ["/u/Movies/raw.mov"]])
    }

    @Test func aRowWhoseFolderIsNotSelectedIsSentOnItsOwn() {
        #expect(selections(cacheAndModel, selected: [position(1, 0)]) == [["/u/.cache/huggingface/model.bin"]])
    }

    @Test func aGroupWithNothingToSendIsOmitted() {
        let sent = ConfirmationRows.selections(cacheAndModel) { $0 != position(1, 1) }

        #expect(sent.map(\.categoryId) == ["dev-caches"])
    }

    /// La copertura risale tutta la catena: il file sotto B è coperto da A anche se B è deselezionata.
    @Test func coverageFollowsTheWholeChain() {
        let chain = build([
            result("cat-a", item("/x/a", directory: true)),
            result("cat-b", item("/x/a/b", directory: true)),
            result("cat-c", item("/x/a/b/c.bin")),
        ])

        #expect(selections(chain, selected: [position(0, 0), position(2, 0)]) == [["/x/a"]])
        #expect(selections(chain, selected: [position(1, 0), position(2, 0)]) == [["/x/a/b"]])
    }

    /// Una posizione che `build` non produrrebbe mai: la riga resta indietro, è la direzione sicura.
    @Test func aRowWhoseContainerDoesNotExistIsNotSent() {
        let forged = [ConfirmationCategory(categoryId: "cat-a", rows: [
            ConfirmationRow(item: item("/x/a"), container: position(4, 0)),
            ConfirmationRow(item: item("/x/b"), container: position(0, 7)),
        ])]

        #expect(ConfirmationRows.selections(forged) { _ in false }.isEmpty)
        #expect(ConfirmationRows.selections(forged) { $0.category == 0 }.isEmpty)
    }

    /// La garanzia, su ogni combinazione di una catena, di una cartella sorella e di un file libero:
    /// nessuna voce inviata sta sotto un'altra voce inviata, e ogni voce selezionata è inviata o sta
    /// sotto una voce inviata.
    @Test func everySelectionSendsNoNestedRowsAndLosesNoSelectedRow() {
        let categories = build([
            result("cat-a", item("/x/a/b/c.bin"), item("/x/libero.iso")),
            result("cat-b", item("/x/a", directory: true), item("/x/sorella", directory: true)),
            result("cat-c", item("/x/a/b", directory: true), item("/x/sorella/f.bin")),
        ])
        let positions = categories.enumerated().flatMap { categoryIndex, category in
            category.rows.indices.map { position(categoryIndex, $0) }
        }
        func path(_ position: ConfirmationPosition) -> String {
            categories[position.category].rows[position.row].item.path
        }
        func isUnder(_ path: String, _ folder: String) -> Bool { path.hasPrefix(folder + "/") }

        for mask in 0..<(1 << positions.count) {
            let selected = Set(positions.indices.filter { mask & (1 << $0) != 0 }.map { positions[$0] })
            let sent = ConfirmationRows.selections(categories) { selected.contains($0) }.flatMap { $0.items.map(\.path) }

            for one in sent {
                #expect(!sent.contains { isUnder(one, $0) }, "maschera \(mask): \(one) inviata sotto un'altra voce inviata")
            }
            for chosen in selected.map(path) {
                #expect(sent.contains(chosen) || sent.contains { isUnder(chosen, $0) }, "maschera \(mask): \(chosen) persa")
            }
        }
    }
}
