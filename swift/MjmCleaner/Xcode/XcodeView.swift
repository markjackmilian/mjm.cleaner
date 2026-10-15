import CleanerCore
import CleanerFeatures
import SwiftUI

/// La pagina Xcode (`XcodeView`): voci tutte deselezionate, anteprima obbligatoria, conferma
/// finale e, se servono, presa d'atto dei dispositivi che restano. Mentre elimina, la finestra
/// blocca la navigazione; «Conferma ed elimina» parte da un `Task` non legato alla vista.
struct XcodeView: View {
    let model: XcodeModel

    var body: some View {
        content
            .navigationTitle("Pulizia cache e simulatori")
            .navigationSubtitle("Tutte le voci partono deselezionate. L’anteprima non elimina nulla.")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    OptionalText(text: model.warningText)
                    if let confirmation = model.confirmation {
                        XcodeConfirmationPanel(model: model, confirmation: confirmation)
                    }
                    OptionalText(text: model.errorText, style: .danger)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(.background)
            }
            .actionBar {
                if model.isDeleting {
                    Text(model.progressText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if model.canCancelDelete {
                    Button("Interrompi", action: model.cancelDelete)
                }
                Button("Riprova analisi") { Task { await model.retry() } }
                    .disabled(!model.canRetry)
                if !model.hasConfirmation {
                    Button("Anteprima selezione", action: model.preview)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canPreview)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if model.isLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.linear)
                Text("Analisi delle cartelle Xcode e dei simulatori…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.totalText)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(padding: 12)
                    ForEach(model.groups) { group in
                        XcodeGroupView(group: group)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
            .disabled(model.isDeleting)
        }
    }
}

/// La conferma finale: cosa verrà eliminato, le avvertenze e, se un runtime è usato da dispositivi
/// che restano, la presa d'atto senza la quale «Conferma ed elimina» resta disabilitato.
private struct XcodeConfirmationPanel: View {
    @Bindable var model: XcodeModel
    let confirmation: XcodeConfirmation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Conferma finale")
                        .fontWeight(.bold)
                    Text(model.previewSummaryText)
                    Text(model.previewEstimateText)
                        .foregroundStyle(.secondary)
                    ForEach(Array(confirmation.selectedCandidates.enumerated()), id: \.offset) { _, candidate in
                        CandidateLines(candidate: candidate, showsPath: true)
                    }
                    if model.hasSelectedDevices {
                        Text("Eliminare un dispositivo rimuove anche le sue app e i dati di test.")
                    }
                    if model.hasSelectedRuntimes {
                        Text("Rimuovere un runtime può rendere indisponibili i dispositivi che lo usano.")
                    }
                    if model.hasRetainedDependencies {
                        Text("I dispositivi elencati resteranno sul disco, ma potrebbero non avviarsi se rimuovi il runtime.")
                        ForEach(Array(confirmation.retainedDependentDevices.enumerated()), id: \.offset) { _, candidate in
                            CandidateLines(candidate: candidate, showsPath: false)
                        }
                        Toggle(
                            "Ho capito che i dispositivi elencati potrebbero non essere più disponibili finché non reinstallo il runtime.",
                            isOn: $model.acknowledgeDependencies)
                            .toggleStyle(.checkbox)
                            .disabled(model.isDeleting)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
            HStack {
                Spacer()
                Button("Torna alla selezione", action: model.backToSelection)
                    .disabled(model.isDeleting)
                Button("Conferma ed elimina", role: .destructive) {
                    Task { await model.confirmDelete() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!model.canConfirmDelete)
            }
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CandidateLines: View {
    let candidate: XcodeCandidate
    let showsPath: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(candidate.name)
                .fontWeight(.semibold)
            if showsPath, let path = candidate.path {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let cliId = candidate.cliId {
                Text(cliId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct XcodeGroupView: View {
    @Bindable var group: XcodeGroupNode
    @State private var isExpanded: Bool

    init(group: XcodeGroupNode) {
        self.group = group
        _isExpanded = State(initialValue: group.isExpanded)
    }

    var body: some View {
        CollapsibleCard(items: group.rows, isExpanded: $isExpanded) {
            HStack(spacing: 10) {
                Text(group.title)
                    .fontWeight(.semibold)
                Text(group.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            ForEach(Array(group.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if group.showGroupCheckBox {
                Toggle("Seleziona tutte le voci di cache", isOn: $group.isSelected)
                    .toggleStyle(.checkbox)
            }
        } row: { row in
            XcodeRowView(row: row)
        }
    }
}

private struct XcodeRowView: View {
    @Bindable var row: XcodeRow

    var body: some View {
        HStack(spacing: 8) {
            Toggle(row.name, isOn: $row.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!row.canSelect)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(row.identityText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if row.hasState {
                    Text(row.stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Text(row.sizeText)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
