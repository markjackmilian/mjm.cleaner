import CleanerCore
import Foundation
import Testing
@testable import CleanerFeatures

struct HistoryTests {
    private static let names = CategoryNames.build([
        CleanupCategory(
            id: "system-caches", displayName: "Cache utente e di sistema", description: "", risk: .medium,
            selectedByDefault: true, parentId: nil, rules: []),
    ])

    /// Il 26 settembre 2026 alle 01:19 in ora locale, come `DateTimeKind.Local` nel test C#.
    private static func session(_ ids: String...) throws -> CleanSessionSummary {
        let local = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: .current, year: 2026, month: 9, day: 26, hour: 1, minute: 19)
        return CleanSessionSummary(
            id: 1,
            startedAt: try #require(local.date),
            duration: .seconds(3),
            bytesFreed: 10_200_547_328,
            itemsDeleted: 2117,
            itemsFailed: 0,
            categories: ids.map { CategoryCleanResult(categoryId: $0, bytesFreed: 1, itemsDeleted: 1) })
    }

    @Test func dateIsLocalisedItalian() throws {
        #expect(HistoryRow(session: try Self.session("system-caches"), names: Self.names).when == "26 set 2026, 01:19")
    }

    @Test func itemsUseThousandsSeparator() throws {
        #expect(HistoryRow(session: try Self.session("system-caches"), names: Self.names).items == "2.117")
    }

    @Test func categoriesShowReadableNames() throws {
        let row = HistoryRow(
            session: try Self.session(
                "system-caches", "docker-images", "xcode-derived-data", "trash-downloads-large", "downloads-large", "sconosciuta"),
            names: Self.names)
        #expect(row.categoryNames == [
            "Cache utente e di sistema", "Immagini Docker", "DerivedData", "Cestino, Download e file grandi", "Download e file grandi",
            "sconosciuta",
        ])
    }

    @Test(arguments: [(0, "nessuna pulizia"), (1, "in 1 pulizia"), (4, "in 4 pulizie")])
    @MainActor
    func summaryAgrees(count: Int, expected: String) {
        #expect(HistoryModel.summarize(count) == expected)
    }
}
