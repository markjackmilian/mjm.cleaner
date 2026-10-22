# Download completi e gruppi per cartella — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permettere di svuotare Download senza filtro di età e rendere leggibile il passo 3 raggruppando le voci per cartella.

**Architecture:** La scelta temporanea del passo 1 produce una variante della categoria Download per la sola analisi corrente. Il modello di conferma crea gruppi di presentazione dalle `PathNode` già deduplicate; la selezione consegnata al motore continua a passare per `ConfirmationRows.selections`.

**Tech Stack:** Swift 6.2, SwiftUI, Observation, Swift Testing, macOS 15+.

**Spec:** `docs/superpowers/specs/2026-10-22-downloads-and-result-folders-design.md`

## Global Constraints

- «Svuota Download» ignora soltanto `minAge`; conserva root, glob, esclusioni e tutte le protezioni del motore.
- La modalità non è salvata nelle impostazioni; `selectedCategoryIds` continua a contenere solo ID.
- Con la modalità attiva, le voci Download partono selezionate; in modalità ordinaria partono deselezionate.
- Un gruppo visuale non diventa mai una `ScanItem` e non modifica `ConfirmationRows.selections`.
- Le cartelle cancellabili e i pacchetti restano righe singole con il contenimento esistente.
- Non modificare le tre `Localizable.xcstrings` già cambiate dall'utente; lasciare anche `.zed/` e `mjm-cleaner-ui-handoff.md` intatti. Le nuove stringhe SwiftUI/localized vengono estratte nel passaggio di localizzazione successivo.

## Review Focus

- Download disattivato dopo l'opzione: la modalità deve spegnersi e la categoria restare fuori dall'analisi (Task 2).
- Download riattivato in una nuova schermata: l'opzione deve tornare spenta anche quando l'ID della categoria è ricordato (Task 2).
- Cartelle escluse e pacchetti: la variante senza età non deve superare le esclusioni o disaggregare un pacchetto (Task 1).
- Voci coperte da una cartella cancellabile di un'altra categoria: la casella di gruppo non deve sbloccarle o contarle due volte (Task 3).
- Percorsi con nomi simili (`/A` e `/AB`) o righe cartella: ogni voce deve appartenere solo al gruppo della propria cartella padre (Task 3).

---

### Task 1: variante temporanea della categoria Download

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupRule.swift`
- Modify: `MjmCleanerKit/Sources/CleanerCore/Categories/CleanupCategory.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Categories/CategoryCatalogTests.swift`
- Test: `MjmCleanerKit/Tests/CleanerCoreTests/Scanning/PackageScanTests.swift`

**Interfaces:**
- Consumes: `CleanupCategory` e `CleanupRule` correnti.
- Produces: `CleanupCategory.forCompleteDownloads() -> CleanupCategory` (per ID diversi da `downloads` restituisce `self`); `CleanupRule.withoutMinimumAge() -> CleanupRule` (copia ogni campo tranne `minAge`, che diventa `nil`).

- [ ] **Step 1: Write failing tests.** In `CategoryCatalogTests`, verificare che la categoria standard con età configurata resti identica, mentre `forCompleteDownloads()` ha `minAge == nil`, `itemsSelectedByDefault == true`, stesso ID, rischio, root, glob, esclusioni, `maxDepth` e `minSizeBytes`; una categoria diversa resta invariata. In `PackageScanTests`, scansionare la variante con file recente, file vecchio, pacchetto recente e pacchetto escluso: i primi tre compaiono e l'escluso no.
- [ ] **Step 2: Verify red.** Run `swift test --filter CategoryCatalogTests --filter PackageScanTests -Xswiftc -warnings-as-errors` in `MjmCleanerKit`; expected failure: missing new methods or assertions.
- [ ] **Step 3: Implement the two copy methods.** Preserve all existing fields explicitly; do not edit persistent `CleanerSettings`.
- [ ] **Step 4: Verify green.** Run the same filtered tests; expected 0 failures.
- [ ] **Step 5: Commit.** Commit only Task 1 files with message `feat: add one-run full Downloads category`.

### Task 2: scelta «Svuota Download» al passo 1

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ChooseStepModel.swift`
- Modify: `MjmCleaner/Cleanup/ChooseStepView.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/ChooseStepTests.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`

**Interfaces:**
- Consumes: `CleanupCategory.forCompleteDownloads()` from Task 1; existing `CleanupNavigating.showScan(_:)` and `showConfirm(_:results:)`.
- Produces: `CategoryChoice.emptiesDownloads: Bool` (set true selects Download; deselecting Download resets it); `ChooseStepModel.analyze()` passes the variant only when that property is true.

- [ ] **Step 1: Write failing tests.** In `ChooseStepTests`, assert activation selects Download and passes a rule with `minAge == nil`, turning the mode off retains a selected Download with its configured age, turning Download off resets the mode, `selectedCategoryIds` contains only `downloads`, and a fresh `ChooseStepModel` starts with the mode off even when Download was remembered. In `ConfirmStepModelTests`, pass a full-mode category and verify Download paths start selected; standard category paths remain deselected.
- [ ] **Step 2: Verify red.** Run `swift test --filter ChooseStepTests --filter ConfirmStepModelTests -Xswiftc -warnings-as-errors` in `MjmCleanerKit`; expected failure from the absent behavior.
- [ ] **Step 3: Implement model and view.** Add the secondary checkbox below Download's description. Give it its own button hit area so the row's `.onTapGesture` does not toggle the category again. Use a localized label and make the choice legible to VoiceOver.
- [ ] **Step 4: Verify green and build UI.** Run the filtered tests, then `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug build`; expected 0 failures and build exit 0.
- [ ] **Step 5: Commit.** Commit only Task 2 files with message `feat: expose full Downloads choice`.

### Task 3: gruppi visuali selezionabili al passo 3

**Files:**
- Modify: `MjmCleanerKit/Sources/CleanerFeatures/Cleanup/ConfirmStepModel.swift`
- Modify: `MjmCleaner/Cleanup/ConfirmStepView.swift`
- Test: `MjmCleanerKit/Tests/CleanerFeaturesTests/ConfirmStepModelTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes: existing `CategoryNode.paths`, `PathNode.isChecked/isCovered/isSelected`, and `ConfirmationRows.selections`.
- Produces: `FolderGroupNode: Identifiable` with `folderPath: String`, `paths: [PathNode]`, `summaryText: String`, `selectedCountText: String`, `allSelected: Bool` get/set, `canSelectAll: Bool`; `CategoryNode.folderGroups: [FolderGroupNode]` grouped by the immediate parent path.

- [ ] **Step 1: Write failing tests.** In `ConfirmStepModelTests`, assert two parent paths make two ordered groups, 200 items in one parent make one group with 200 `PathNode` references, a directory item belongs to its parent's group, group select/deselect changes only its member rows, and mixed selections show a selected count. Cover a row under `/A` but not `/AB`, plus a covered row from another category: its checkbox stays locked, `totalText` does not double count, and the deletion spy receives only selected `ScanItem`s, never the visual folder.
- [ ] **Step 2: Verify red.** Run `swift test --filter ConfirmStepModelTests -Xswiftc -warnings-as-errors` in `MjmCleanerKit`; expected failure from missing group API or assertions.
- [ ] **Step 3: Implement groups and view.** Construct groups once from the deduplicated paths; use their `PathNode` references. Render nested disclosure sections under each category with count, bytes, selected count and checkbox; keep a lazy list and individual `PathRow`. A covered row obeys existing containment behavior. Update README steps 1 and 3 plus Download description.
- [ ] **Step 4: Verify green and full suite.** Run `swift test --filter ConfirmStepModelTests -Xswiftc -warnings-as-errors`, `swift test -Xswiftc -warnings-as-errors`, and the Debug app build; expected 0 failures. Inspect a populated Download group in light/dark UI and keyboard/VoiceOver if the macOS UI is available.
- [ ] **Step 5: Commit.** Commit only Task 3 files with message `feat: group confirmation items by folder`.

## Final review

- Review the aggregate diff against the spec, especially folder group selection and `ConfirmationRows.selections`.
- Re-run the full Swift package tests and Debug app build after any review fix.
- Report any manual UI checks that could not be performed instead of claiming them complete.
