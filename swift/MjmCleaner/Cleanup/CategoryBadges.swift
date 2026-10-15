import CleanerCore
import CleanerFeatures
import SwiftUI

/// La tile 28×28 di una categoria: colore dal catalogo asset, simbolo bianco (spec §6.4).
struct CategoryTile: View {
    let visual: CategoryVisual

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color(visual.tileColorName))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: visual.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// La pill del rischio: il livello resta scritto, non solo colorato (spec §6.6).
struct RiskPill: View {
    let risk: RiskLevel

    var body: some View {
        Text(risk.label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(risk.colorName))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color(risk.colorName + "Background"), in: Capsule())
    }
}
