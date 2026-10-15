import CleanerFeatures
import SwiftUI

/// La pagina Docker (`DockerView`): anteprima a gruppi, nulla viene eliminato prima di «Elimina».
/// Docker non raggiungibile mostra il messaggio del Core e Riprova; l'app non avvia mai Docker
/// Desktop. «Elimina» parte da un `Task` non legato alla vista e lo ferma solo «Interrompi».
struct DockerView: View {
    let model: DockerModel

    var body: some View {
        content
            .navigationTitle("Pulizia Docker")
            .navigationSubtitle("Anteprima: nulla viene eliminato finché non premi «Elimina».")
            .toolbar {
                if model.hasError {
                    ToolbarItem(placement: .primaryAction) {
                        Label("Motore non raggiungibile", systemImage: "circle.fill")
                            .labelStyle(StatusPillLabelStyle())
                    }
                }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Analisi di Docker e delle cartelle progetto in corso…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.hasError {
            VStack(spacing: 14) {
                Image(systemName: "cube")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 72, height: 72)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityHidden(true)
                Text(model.errorText)
                    .font(.system(size: 17, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Riprova") { Task { await model.retry() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canRetry)
                    .padding(.top, 6)
            }
            .frame(width: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.isReady {
            ready
        }
    }

    private var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.serverText)
                        .fontWeight(.semibold)
                    Group {
                        Text(model.diskText)
                        Text(model.dfText)
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
                ForEach(model.groups) { group in
                    DockerGroupView(group: group)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            // Le caselle si fermano, lo scorrimento no.
            .disabled(model.isDeleting)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                Banner(text: String(localized: "Eliminazione definitiva: immagini e volumi eliminati non sono recuperabili. I volumi contengono dati."))
                OptionalText(text: model.deleteErrorText, style: .danger)
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
                    .truncationMode(.middle)
            }
            Spacer()
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

private struct DockerGroupView: View {
    @Bindable var group: DockerGroupNode
    @State private var isExpanded: Bool

    init(group: DockerGroupNode) {
        self.group = group
        _isExpanded = State(initialValue: group.isExpanded)
    }

    var body: some View {
        CollapsibleCard(items: group.rows, isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                Text(group.title)
                    .fontWeight(.semibold)
                Text(group.summaryText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text(group.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                if group.showGroupCheckBox {
                    Toggle(group.groupCheckBoxLabel, isOn: $group.isSelected)
                        .toggleStyle(.checkbox)
                }
            }
        } row: { row in
            DockerRowView(row: row)
        }
    }
}

private struct DockerRowView: View {
    @Bindable var row: DockerRow

    var body: some View {
        HStack(spacing: 8) {
            if row.showCheckBox {
                Toggle(row.name, isOn: $row.isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(row.kindLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Text(row.sizeText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

/// La pill di stato della toolbar («Motore non raggiungibile»): pallino grigio e testo.
struct StatusPillLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
                .foregroundStyle(.gray)
            configuration.title
                .font(.callout)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}
