import CleanerCore
import Foundation

// Prova dell'anteprima Xcode dell'avvio dimostrativo: usa i dati fissi di `DemoData.swift` con
// `XcodeSelection`, come fanno i servizi finti della demo, e fallisce se una cartella selezionabile
// non ha la sua voce nell'inventario protetto (difetto V-01).
// Non si compila da solo: lo fa `Scripts/demo-xcode-preview.test.sh`.
// Uso: Scripts/demo-xcode-preview.test.sh

@main
struct DemoXcodePreviewTest {
    static func main() throws {
        let selectableFileCandidates = DemoData.xcodeSnapshot.candidates.filter {
            ($0.kind == .derivedData || $0.kind == .deviceSupport) && $0.canSelect
        }
        let preview = try XcodeSelection.preview(
            DemoData.xcodeSnapshot,
            selectedKeys: Set(selectableFileCandidates.map(\.key)))

        precondition(preview.selectedCandidates.count == 3, "attese tutte e tre le cartelle di cache Xcode selezionabili")
        precondition(
            preview.estimatedBytes == 3 * 1_073_741_824 + 900 * 1_048_576 + 4 * 1_073_741_824,
            "la stima dell'anteprima deve combaciare con le cartelle ShopApp, Widgets e Device Support della demo")

        // La conferma ricontrolla l'inventario: senza le tre voci il piano non si costruisce.
        let plan = try XcodeSelection.confirm(preview, acknowledgeDependencies: false)
        precondition(plan.fileInventory.count == 3, "il piano confermato deve portare le tre voci d'inventario dei file")

        // Quello che apre `-MJMDemo xcode-preview` (`DemoLaunch`, caso `.xcodePreview`): la cartella di
        // ShopApp e il runtime scelti insieme.
        let previewedKeys = Set(DemoData.previewedXcodeKeys)
        let demoPreview = try XcodeSelection.preview(DemoData.xcodeSnapshot, selectedKeys: previewedKeys)
        precondition(
            Set(demoPreview.selectedCandidates.map(\.key)) == previewedKeys,
            "l'anteprima della pagina xcode-preview deve contenere tutte le chiavi scelte dalla demo")
        precondition(
            demoPreview.selectedCandidates.contains { $0.kind == .derivedData },
            "la pagina xcode-preview deve mostrare anche una cartella DerivedData, il caso del difetto V-01")
    }
}
