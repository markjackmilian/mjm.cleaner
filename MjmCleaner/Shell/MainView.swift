import CleanerFeatures
import SwiftUI

/// `MainWindow`: la sidebar e la pagina corrente (spec §6.2, §6.3). Lo sheet delle Impostazioni
/// esiste finché `main.settings` non è `nil`.
struct MainView: View {
    let main: MainModel

    var body: some View {
        NavigationSplitView {
            SidebarView(main: main)
                .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 320)
        } detail: {
            PageView(page: main.page)
        }
        .sheet(item: settingsSheet) { settings in
            SettingsView(model: settings)
        }
    }

    /// Se lo sheet lo chiude il sistema (Esc), vale come Annulla: torna l'aspetto di prima
    /// (`ClosingTheWindowRestoresTheAppearance`). Salva e Annulla azzerano già `main.settings`.
    private var settingsSheet: Binding<SettingsModel?> {
        Binding(get: { main.settings }, set: { if $0 == nil { main.settings?.cancel() } })
    }
}

/// La pagina corrente. Ogni modello ha la propria identità: una pagina nuova dello stesso tipo
/// (Docker riselezionato, un nuovo ciclo del wizard) riparte con lo stato della vista azzerato.
struct PageView: View {
    let page: Page

    var body: some View {
        content
            .modifier(WizardChrome(step: page.kind.wizardStep))
    }

    @ViewBuilder private var content: some View {
        switch page {
        case .choose(let model): ChooseStepView(model: model).id(ObjectIdentifier(model))
        case .scan(let model): ScanStepView(model: model).id(ObjectIdentifier(model))
        case .confirm(let model): ConfirmStepView(model: model).id(ObjectIdentifier(model))
        case .done(let model): DoneStepView(model: model).id(ObjectIdentifier(model))
        case .docker(let model): DockerView(model: model).id(ObjectIdentifier(model))
        case .dockerReport(let model): DockerReportView(model: model).id(ObjectIdentifier(model))
        case .xcode(let model): XcodeView(model: model).id(ObjectIdentifier(model))
        case .xcodeReport(let model): XcodeReportView(model: model).id(ObjectIdentifier(model))
        case .history(let model): HistoryView(model: model).id(ObjectIdentifier(model))
        }
    }
}

/// La toolbar dei quattro passi del wizard: «Pulizia», «Passo N di 4» e l'indicatore.
struct WizardChrome: ViewModifier {
    let step: Int?

    func body(content: Content) -> some View {
        if let step {
            content
                .navigationTitle("Pulizia")
                .navigationSubtitle("Passo \(String(step)) di 4")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        StepIndicator(current: step)
                    }
                }
        } else {
            content
        }
    }
}
