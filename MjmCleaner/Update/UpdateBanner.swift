import CleanerCore
import CleanerFeatures
import SwiftUI

/// Il banner in cima alla finestra quando un aggiornamento è scaricato e verificato. «Installa e
/// riavvia» chiede conferma, perché l'app si chiude e il permesso di Accesso completo al disco va
/// concesso di nuovo; se il bundle non si può sostituire sul posto, «Mostra nel Finder».
struct UpdateBanner: View {
    let model: UpdateModel
    @State private var confirming = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.bannerTitle)
                    .fontWeight(.semibold)
                if let reason = model.installBlockedReason {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if case .manual(let reason) = model.installMode {
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Novità", action: model.openReleaseNotes)
                .buttonStyle(.link)
            Button("Più tardi", action: model.later)
            if case .manual = model.installMode {
                Button("Mostra nel Finder", action: model.revealUpdate)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Installa e riavvia…") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.installBlockedReason != nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .alert("Installare l'aggiornamento?", isPresented: $confirming) {
            Button("Annulla", role: .cancel) {}
            Button("Installa e riavvia", action: model.install)
        } message: {
            Text("mjm.cleaner si chiuderà e si riaprirà con la nuova versione. Dopo l'aggiornamento dovrai concedere di nuovo l'Accesso completo al disco, se lo usi (serve solo per il Cestino).")
        }
    }
}

/// La sezione «Aggiornamenti» delle Impostazioni: l'interruttore si salva con Salva, «Controlla
/// ora» agisce subito.
struct UpdateSettingsSection: View {
    @Bindable var settings: SettingsModel
    let model: UpdateModel

    var body: some View {
        Section {
            Toggle("Controlla automaticamente", isOn: $settings.automaticUpdateChecks)
            LabeledContent("Versione installata", value: model.currentVersionText)
            LabeledContent("Ultimo controllo") {
                if let last = model.lastCheckText {
                    Text(verbatim: last)
                } else {
                    Text("mai")
                }
            }
            HStack(spacing: 10) {
                OptionalText(text: model.statusText, style: model.hasFailed ? .danger : .secondary)
                Spacer()
                Button("Controlla ora") {
                    Task { await model.checkNow() }
                }
                .disabled(model.isBusy)
            }
        } header: {
            Text("Aggiornamenti")
        } footer: {
            Text("Cerca le nuove versioni fra le release di GitHub all'avvio e una volta al giorno.")
        }
    }
}
