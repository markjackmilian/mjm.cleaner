import SwiftUI

/// La barra azioni in fondo alla pagina (spec §6.2): resta visibile qualunque sia l'altezza del
/// contenuto, perché sta nell'area sicura e non nello scorrimento.
struct ActionBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

extension View {
    func actionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            ActionBar(content: content)
        }
    }

    /// Una card: superficie dei controlli, angoli 10, contorno sottile.
    func card(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.separator, lineWidth: 0.5)
            }
    }
}

/// Titolo e sottotitolo in testa alla pagina.
struct PageHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// L'avviso in evidenza («Eliminazione definitiva…», Docker fermato, Purge).
struct Banner: View {
    let text: String
    var emphasized = true

    var body: some View {
        Label {
            Text(text)
                .fontWeight(emphasized ? .semibold : .regular)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Un testo che compare solo se non è vuoto.
struct OptionalText: View {
    let text: String
    var style: Style = .secondary

    enum Style {
        case secondary
        case danger
    }

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.callout)
                .foregroundStyle(style == .danger ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Un gruppo richiudibile in una card, con le righe in uno scorrimento proprio alto al più 360
/// punti: come il `ListBox` del C#, anche una categoria con migliaia di voci crea solo le righe
/// visibili.
struct CollapsibleCard<Title: View, Header: View, Row: View, Item: Identifiable>: View {
    let items: [Item]
    @Binding var isExpanded: Bool
    @ViewBuilder let label: () -> Title
    @ViewBuilder let header: () -> Header
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                header()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            row(item)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }
                    }
                }
                .frame(maxHeight: 360)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        } label: {
            label()
        }
        .card(padding: 12)
    }
}
