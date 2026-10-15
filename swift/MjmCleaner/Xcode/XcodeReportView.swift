import CleanerFeatures
import SwiftUI

/// Il resoconto Xcode (`XcodeReportView`): l'esito di ogni voce, la stima conteggiata nello storico
/// e lo spazio libero rilevato prima e dopo, tenuti separati.
struct XcodeReportView: View {
    let model: XcodeReportModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.items) { row in
                    if row.id > 0 {
                        Divider().padding(.leading, 16)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.name)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(row.outcomeText)
                                .foregroundStyle(.secondary)
                            Text(row.sizeText)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                        Text(row.identity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .card(padding: 0)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.freedText)
                    .fontWeight(.semibold)
                Text(model.freeSpaceText)
                    .foregroundStyle(.secondary)
                OptionalText(text: model.warningsText)
                OptionalText(text: model.historyWarning, style: .danger)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(.background)
        }
        .actionBar {
            Spacer()
            Button("Nuova analisi Xcode", action: model.analyzeAgain)
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Report pulizia")
        .navigationSubtitle(model.summaryText)
    }
}
