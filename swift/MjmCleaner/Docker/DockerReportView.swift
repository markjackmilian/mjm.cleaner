import CleanerFeatures
import SwiftUI

/// Il resoconto Docker (`DockerReportView`): quanto si è recuperato, le misure prima e dopo, le
/// voci eliminate e quelle no. Il salvataggio nello storico è partito con il modello.
struct DockerReportView: View {
    let model: DockerReportModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 6) {
                    Text("Pulizia Docker completata")
                        .font(.system(size: 22, weight: .bold))
                    Text(model.freedText)
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.dfText)
                    Text(model.diskText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
                if !model.daemonLostText.isEmpty {
                    Banner(text: model.daemonLostText)
                }
                if !model.purgeHint.isEmpty {
                    Banner(text: model.purgeHint, emphasized: false)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Eliminate")
                        .fontWeight(.semibold)
                    ForEach(Array(model.deleted.enumerated()), id: \.offset) { _, entry in
                        Text(entry)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 12)
                if model.hasFailures {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Non eliminate")
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        ForEach(Array(model.failed.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OptionalText(text: model.historyWarning)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)
        }
        .actionBar {
            Spacer()
            Button("Nuova analisi", action: model.analyzeAgain)
                .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Pulizia Docker")
        .navigationSubtitle(model.summaryText)
    }
}
