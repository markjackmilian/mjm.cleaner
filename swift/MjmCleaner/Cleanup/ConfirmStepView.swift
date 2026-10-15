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
    let node: CategoryNode
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
            EmptyView()
        } row: { path in
            PathRow(path: path)
        }
    }
}

private struct PathRow: View {
    @Bindable var path: PathNode

    var body: some View {
        HStack(spacing: 8) {
            Toggle(path.path, isOn: $path.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(path.path)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text(path.sizeText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
