import CleanerCore
import CleanerFeatures
import SwiftUI

/// Le Impostazioni (`SettingsWindow`): uno sheet largo 700 sulla finestra principale, con
/// Annulla e Salva in basso a destra (spec §6.2). L'aspetto scelto si vede subito; Annulla lo
/// ripristina.
struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Impostazioni")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Personalizza i percorsi e le soglie usate durante l'analisi.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 12)
            Divider()
            Form {
                Section {
                    Picker("Aspetto", selection: $model.appearance) {
                        Text("Automatico").tag(AppearancePreference.auto)
                        Text("Chiaro").tag(AppearancePreference.light)
                        Text("Scuro").tag(AppearancePreference.dark)
                    }
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .labelsHidden()
                } header: {
                    Text("Aspetto")
                } footer: {
                    Text("Automatico segue l'aspetto scelto in Impostazioni di Sistema.")
                }

                Section {
                    FolderList(
                        roots: model.projectRoots,
                        selection: $model.selectedProjectRoot,
                        canRemove: model.canRemoveProjectRoot,
                        add: model.addProjectRoot,
                        remove: model.removeProjectRoot)
                } header: {
                    Text("Progetti .NET")
                } footer: {
                    Text("Cartelle di progetto in cui cercare bin e obj.")
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Cartelle in cui cercare")
                        FolderList(
                            roots: model.largeFileRoots,
                            selection: $model.selectedLargeFileRoot,
                            canRemove: model.canRemoveLargeFileRoot,
                            add: model.addLargeFileRoot,
                            remove: model.removeLargeFileRoot)
                    }
                    NumberRow(
                        title: "Soglia file grandi", unit: "MB",
                        value: $model.largeFileThresholdMegabytes, range: SettingsModel.thresholdMegabytesRange)
                } header: {
                    Text("File grandi")
                } footer: {
                    Text("Vengono proposti solo i file più grandi della soglia.")
                }

                Section {
                    NumberRow(
                        title: "Download", accessibilityName: "Età minima dei download", unit: "giorni",
                        value: $model.downloadsMinAgeDays, range: SettingsModel.minAgeDaysRange)
                    NumberRow(
                        title: "Log", accessibilityName: "Età minima dei log", unit: "giorni",
                        value: $model.logsMinAgeDays, range: SettingsModel.minAgeDaysRange)
                    NumberRow(
                        title: "Pacchetti NuGet", accessibilityName: "Età minima dei pacchetti NuGet", unit: "giorni",
                        value: $model.nuGetMinAgeDays, range: SettingsModel.minAgeDaysRange)
                } header: {
                    Text("Età minima")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("I file più recenti restano esclusi dall'analisi.")
                        Text("L'età dei pacchetti NuGet si basa sull'ultimo accesso registrato dal filesystem: è un'euristica, non una certezza.")
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack(spacing: 10) {
                OptionalText(text: model.saveErrorText, style: .danger)
                Spacer()
                Button("Annulla", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Salva", action: model.save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 56)
        }
        // Larga 700 come la finestra C#; alta 560 così entra anche nella finestra minima (900×600).
        .frame(width: 700, height: 560)
    }
}

/// Una lista di cartelle con la barra «+ / −» (spec §6.6): «−» è disabilitato senza selezione.
private struct FolderList: View {
    let roots: [String]
    @Binding var selection: String?
    let canRemove: Bool
    let add: () async -> Void
    let remove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if roots.isEmpty {
                Text("Nessuna cartella. Premi + per aggiungerne una.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 84)
            } else {
                List(selection: $selection) {
                    ForEach(roots, id: \.self) { root in
                        Text(root)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .tag(root)
                    }
                }
                .frame(height: 84)
            }
            Divider()
            HStack(spacing: 0) {
                Button {
                    Task { await add() }
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 24, height: 22)
                }
                .accessibilityLabel("Aggiungi cartella")
                Divider()
                    .frame(height: 14)
                Button(action: remove) {
                    Image(systemName: "minus")
                        .frame(width: 24, height: 22)
                }
                .accessibilityLabel("Rimuovi cartella selezionata")
                .disabled(!canRemove)
                Spacer()
            }
            .buttonStyle(.borderless)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

/// Un campo numerico con unità e stepper. Il valore resta nei limiti della finestra C#
/// (`Minimum`/`Maximum` dei `NumericUpDown`), anche quando si scrive nel campo.
private struct NumberRow: View {
    let title: LocalizedStringKey
    /// Il nome di campo e stepper per VoiceOver, come `AutomationProperties.Name` del C#; senza, il titolo.
    var accessibilityName: LocalizedStringKey?
    let unit: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(accessibilityName ?? title, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(unit)
                    .foregroundStyle(.secondary)
                Stepper(accessibilityName ?? title, value: clamped, in: range)
                    .labelsHidden()
            }
        }
    }

    private var clamped: Binding<Int> {
        Binding(get: { value }, set: { value = min(max($0, range.lowerBound), range.upperBound) })
    }
}
