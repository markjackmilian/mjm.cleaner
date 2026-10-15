import CleanerFeatures
import SwiftUI

/// Lo Storico (`HistoryView`, spec §6.2): una `Table` a righe alterne, dalla pulizia più recente;
/// le categorie con il nome leggibile, non con l'identificativo.
struct HistoryView: View {
    let model: HistoryModel
    @State private var sortOrder = [KeyPathComparator(\HistoryRow.startedAt, order: .reverse)]

    var body: some View {
        Table(model.rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Data", value: \.startedAt) { row in
                Text(row.when)
                    .monospacedDigit()
            }
            .width(min: 150, ideal: 190)
            TableColumn("Spazio", value: \.bytesFreed) { row in
                Text(row.freed)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)
            TableColumn("Categorie") { row in
                CategoryChips(names: row.categoryNames)
            }
            TableColumn("Elementi") { row in
                Text(row.items)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .navigationTitle("Storico delle pulizie")
        .navigationSubtitle("Le pulizie completate e lo spazio effettivamente recuperato.")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 6) {
                    if model.hasSessions {
                        Text(model.totalText)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    Text(model.countText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

private struct CategoryChips: View {
    let names: [String]

    // Le chip restano intere e quelle che non entrano si tagliano al bordo della colonna
    // (`ClipToBounds` del C#): lo scorrimento orizzontale prende la larghezza della colonna.
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}
