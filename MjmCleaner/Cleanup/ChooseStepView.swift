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
                        ChoiceRow(choice: choice, openSettings: model.openSettings)
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
                .accessibilityHidden(true)
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

/// Una categoria senza cartelle nelle Impostazioni ha la casella disattivata e, sotto la
/// descrizione, l'avviso con «Apri Impostazioni…».
private struct ChoiceRow: View {
    @Bindable var choice: CategoryChoice
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(choice.displayName, isOn: $choice.isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!choice.isAvailable)
            CategoryTile(visual: choice.visual)
                .opacity(choice.isAvailable ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                // Il nome lo legge già la casella: VoiceOver non lo ripete.
                Text(choice.displayName)
                    .fontWeight(.semibold)
                    .accessibilityHidden(true)
                Text(choice.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !choice.isAvailable {
                    MissingFoldersNote(text: choice.unavailableText, openSettings: openSettings)
                }
            }
            Spacer(minLength: 12)
            RiskPill(risk: choice.risk)
        }
        .padding(.vertical, 11)
        .padding(.leading, choice.isChild ? 60 : 16)
        .padding(.trailing, 16)
        .contentShape(Rectangle())
        .onTapGesture {
            // Come la casella: una categoria senza cartelle non si spunta.
            if choice.isAvailable {
                choice.isSelected.toggle()
            }
        }
    }
}

/// L'avviso di una categoria senza cartelle, con il triangolo di `Banner` e la scorciatoia per le
/// Impostazioni.
private struct MissingFoldersNote: View {
    let text: String
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
            Button("Apri Impostazioni…", action: openSettings)
                .buttonStyle(.link)
        }
        .font(.callout)
        .padding(.top, 2)
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
