import CleanerFeatures
import SwiftUI

/// La sidebar (spec §6.2): Pulizia · Docker · Xcode · Storico, poi in fondo il contatore «Spazio
/// liberato» e «Impostazioni… ⌘,». La voce selezionata si ricava dalla pagina; mentre Xcode
/// elimina la lista è disabilitata e il modello rifiuta comunque il cambio di pagina.
struct SidebarView: View {
    let main: MainModel

    var body: some View {
        List(selection: selection) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Label(section.title, systemImage: section.symbolName)
                    .tag(section)
            }
        }
        .disabled(!main.canNavigateGlobally)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                FreedSpaceCard(amount: main.totalFreedAmount)
                Button(action: main.showSettings) {
                    HStack {
                        Label("Impostazioni…", systemImage: "gearshape")
                        Spacer()
                        Text(verbatim: "⌘,")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                // Il nome del C#, senza la scorciatoia scritta accanto.
                .accessibilityLabel("Impostazioni…")
                .disabled(!main.canShowSettings)
            }
            .padding(12)
        }
    }

    private var selection: Binding<SidebarSection?> {
        Binding(get: { main.section }, set: { if let section = $0 { main.select(section) } })
    }
}

/// La card «Spazio liberato» in fondo alla sidebar.
private struct FreedSpaceCard: View {
    let amount: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Spazio liberato")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            Text("liberati finora")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
    }
}

extension SidebarSection {
    var title: LocalizedStringKey {
        switch self {
        case .cleanup: "Pulizia"
        case .docker: "Docker"
        case .xcode: "Xcode"
        case .history: "Storico"
        }
    }

    var symbolName: String {
        switch self {
        case .cleanup: "sparkles"
        case .docker: "cube"
        case .xcode: "hammer"
        case .history: "clock"
        }
    }
}
