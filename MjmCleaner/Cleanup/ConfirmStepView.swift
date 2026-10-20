import CleanerFeatures
import SwiftUI

/// Passo 3 (`ConfirmStepView`): ogni percorso da eliminare, raggruppato per categoria, con le
/// deselezioni puntuali. «Elimina» parte da un `Task` non legato alla vista: un cambio di vista
/// non annulla la pulizia, la ferma solo «Interrompi» (`cancelDelete()`).
struct ConfirmStepView: View {
    let model: ConfirmStepModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Verifica prima di eliminare", subtitle: model.totalText)
                ForEach(model.nodes) { node in
                    CategoryNodeView(node: node)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            // Le caselle si fermano, lo scorrimento no.
            .disabled(model.isDeleting)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Banner(text: String(localized: "Eliminazione definitiva: questi file non finiscono nel Cestino e non sono recuperabili."))
                OptionalText(text: model.runningAppsWarning)
                OptionalText(text: model.exclusionsText)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.background)
        }
        .actionBar {
            if model.isDeleting {
                Text(model.deleteProgressText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .monospacedDigit()
            }
            Spacer()
            Button("Ricomincia", action: model.restart)
                .disabled(model.isDeleting)
            if model.canCancelDelete {
                Button("Interrompi", action: model.cancelDelete)
            }
            Button(role: .destructive) {
                Task { await model.delete() }
            } label: {
                Text("Elimina \(model.totalText)")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(!model.canDelete)
        }
    }
}

private struct CategoryNodeView: View {
    @Bindable var node: CategoryNode
    @State private var isExpanded = true

    var body: some View {
        CollapsibleCard(items: node.paths, isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                Text(node.displayName)
                    .fontWeight(.semibold)
                Text(node.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            if node.itemsStartDeselected {
                Text("Dati reali: le voci partono deselezionate. Spunta solo ciò che vuoi eliminare.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            OptionalText(text: node.coveredText)
            Toggle("Seleziona tutte le voci", isOn: $node.allSelected)
                .toggleStyle(.checkbox)
                .accessibilityLabel(node.selectAllAccessibilityLabel)
                .disabled(!node.canSelectAll)
        } row: { path in
            PathRow(path: path)
        }
    }
}

/// Una voce dentro una cartella spuntata altrove appare spuntata e bloccata, con la nota «Inclusa
/// in …»: si cancella con la cartella, e si sblocca togliendo la spunta a quella.
private struct PathRow: View {
    let path: PathNode

    var body: some View {
        // Letto nel corpo, non dentro il Binding: così Observation registra la casella della voce e
        // quelle della sua catena di cartelle, e la riga si ridisegna quando una di loro cambia.
        let isChecked = path.isChecked
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Toggle(path.path, isOn: Binding(get: { isChecked }, set: { path.isSelected = $0 }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(path.isCovered)
                .accessibilityHint(path.containmentText)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(path.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(path.sizeText)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                OptionalText(text: path.containmentText)
                OptionalText(text: path.containsText)
            }
        }
    }
}
