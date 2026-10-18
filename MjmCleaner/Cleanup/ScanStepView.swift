import CleanerFeatures
import SwiftUI

/// Passo 2 (`ScanStepView`): l'analisi in corso, categoria per categoria. Nessun file viene toccato.
struct ScanStepView: View {
    let model: ScanStepModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Analisi in corso…")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stiamo controllando le categorie selezionate.")
                        .fontWeight(.semibold)
                    if model.isRunning {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text(model.currentPath)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    OptionalText(text: model.errorText, style: .danger)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text("CATEGORIE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    ForEach(Array(model.progress.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().padding(.leading, 16)
                        }
                        HStack {
                            Text(row.displayName)
                            Spacer()
                            Text(row.status)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                    }
                }
                .card(padding: 0)
                Text("Nessun file è stato ancora toccato.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .actionBar {
            Spacer()
            if model.hasError {
                Button("Torna al passo 1", action: model.backToStart)
            } else {
                Button("Annulla", action: model.cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
    }
}
