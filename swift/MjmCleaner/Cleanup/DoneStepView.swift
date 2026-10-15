import CleanerFeatures
import SwiftUI

/// Passo 4 (`DoneStepView`): quanto si è liberato, per categoria, e gli eventuali avvisi.
struct DoneStepView: View {
    let model: DoneStepModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.green)
                        .frame(width: 48, height: 48)
                        .background(.green.opacity(0.15), in: Circle())
                    Text("Pulizia completata")
                        .font(.system(size: 22, weight: .bold))
                    Text(model.freedText)
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                    Text(model.summaryText)
                        .foregroundStyle(.secondary)
                }
                if !model.rows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                            Text(row)
                        }
                    }
                    .frame(maxWidth: 600, alignment: .leading)
                    .card(padding: 14)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                OptionalText(text: model.errorsText, style: .danger)
                OptionalText(text: model.historyWarning)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 12)
        }
        .actionBar {
            Spacer()
            Button("Nuova pulizia", action: model.newCleanup)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }
}
