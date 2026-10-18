import SwiftUI

/// L'indicatore dei quattro passi del wizard: cerchio pieno sul passo corrente.
struct StepIndicator: View {
    let current: Int

    private static let labels: [LocalizedStringKey] = ["Scegli", "Analizza", "Conferma", "Fatto"]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(Self.labels.enumerated()), id: \.offset) { index, label in
                if index > 0 {
                    Rectangle()
                        .fill(.separator)
                        .frame(width: 18, height: 1)
                }
                step(index + 1, label)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Avanzamento")
    }

    private func step(_ number: Int, _ label: LocalizedStringKey) -> some View {
        let isCurrent = number == current
        return HStack(spacing: 6) {
            Text(verbatim: String(number))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 18, height: 18)
                .background {
                    if isCurrent {
                        Circle().fill(Color.accentColor)
                    } else {
                        Circle().strokeBorder(.separator)
                    }
                }
            Text(label)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)
        }
    }
}
