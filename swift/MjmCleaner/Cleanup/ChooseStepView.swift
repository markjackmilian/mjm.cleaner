import CleanerFeatures
import SwiftUI

/// Passo 1 (`ChooseStepView`): le categorie da analizzare. Tutta la riga commuta la casella;
/// «Pacchetti NuGet inutilizzati» è una riga figlia indentata.
struct ChooseStepView: View {
    let model: ChooseStepModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    title: "Cosa vuoi pulire?",
                    subtitle: String(localized: "Seleziona solo ciò che vuoi analizzare. Vedrai ogni elemento prima della rimozione."))
                VStack(spacing: 0) {
                    ForEach(model.choices) { choice in
                        if choice.showSeparator {
                            Divider()
                                .padding(.leading, choice.isChild ? 116 : 72)
                        }
                        ChoiceRow(choice: choice)
                    }
                }
                .card(padding: 0)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .actionBar {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.secondary)
            Text("L'analisi non elimina alcun file.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(model.selectedCountText)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button(action: model.analyze) {
                Label("Analizza", systemImage: "chevron.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canAnalyze)
        }
    }
}

private struct ChoiceRow: View {
    @Bindable var choice: CategoryChoice

    var body: some View {
        HStack(spacing: 12) {
            Toggle(choice.displayName, isOn: $choice.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
            CategoryTile(visual: choice.visual)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.displayName)
                    .fontWeight(.semibold)
                Text(choice.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            RiskPill(risk: choice.risk)
        }
        .padding(.vertical, 11)
        .padding(.leading, choice.isChild ? 60 : 16)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .onTapGesture { choice.isSelected.toggle() }
    }
}

/// «Analizza ›»: il testo prima, la freccia dopo.
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
                .imageScale(.small)
        }
    }
}
