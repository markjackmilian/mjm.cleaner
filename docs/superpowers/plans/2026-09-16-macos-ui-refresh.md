# macOS UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the existing Avalonia desktop application as a polished, light-first macOS utility and add a production-ready macOS app icon without changing its four-step workflow or behavior.

**Architecture:** Keep every ViewModel, command, binding, and page transition intact. Add one application-level AXAML design system, then rewrite only view markup to consume those resources; create the icon as a project asset and teach the existing bundle script to build/copy an `.icns` file.

**Tech Stack:** .NET 10, Avalonia 12.1.2, AXAML, macOS `sips`/`iconutil`, Bash.

**Spec:** `docs/superpowers/specs/2026-09-15-mjm-cleaner-design.md` plus the UI direction approved by the user on 2026-09-16: preserve the flow; light-first native macOS utility styling; restrained blue primary action; red destructive action; compact stepper; readable history/settings; dedicated cleaner icon.

## Global Constraints

- Preserve the current wizard order: `1 · Scegli`, `2 · Analizza`, `3 · Conferma`, `4 · Fatto`.
- Do not modify ViewModels, services, cleanup rules, safety behavior, command semantics, or persisted data.
- Keep all existing bindings and commands functional; UI work is limited to styles, layout, copy presentation, and app icon packaging.
- Target macOS 13+ and keep Avalonia 12.1.2 and .NET 10; add no new NuGet dependencies.
- Optimize for a polished light appearance; full dark-theme parity is not required.
- Use system-like typography, 8–12 px corner radii, quiet gray surfaces, subtle borders, blue only for primary actions, red only for destructive/warning treatment.
- Preserve accessibility basics: minimum 32 px button height, visible focus states supplied by Avalonia, sufficient text contrast, and text wrapping/trimming where content can grow.
- Do not create brittle tests that grep AXAML or assert exact presentation constants. Existing behavior is protected by the full test suite; AXAML correctness is verified by compilation and a live launch.

---

### Task 1: Introduce the macOS visual system and refresh every application view

**Files:**
- Create: `src/MjmCleaner.App/Styles/MacTheme.axaml`
- Modify: `src/MjmCleaner.App/App.axaml`
- Modify: `src/MjmCleaner.App/Views/MainWindow.axaml`
- Modify: `src/MjmCleaner.App/Views/ChooseStepView.axaml`
- Modify: `src/MjmCleaner.App/Views/ScanStepView.axaml`
- Modify: `src/MjmCleaner.App/Views/ConfirmStepView.axaml`
- Modify: `src/MjmCleaner.App/Views/DoneStepView.axaml`
- Modify: `src/MjmCleaner.App/Views/HistoryView.axaml`
- Modify: `src/MjmCleaner.App/Views/SettingsView.axaml`

**Interfaces:**
- Consumes: existing public bindings and commands exactly as named in the current AXAML files.
- Produces: reusable resources and style classes (`PageTitle`, `PageSubtitle`, `Eyebrow`, `SurfaceCard`, `Primary`, `Secondary`, `Destructive`, `ToolbarButton`, `FieldLabel`, `Muted`, `StatusPill`) used by all views.

- [ ] **Step 1: Capture a clean behavioral baseline**

Run:

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test
dotnet build src/MjmCleaner.App/MjmCleaner.App.csproj
```

Expected: all existing tests pass and the application project builds before presentation changes.

- [ ] **Step 2: Add the shared visual system**

Create `Styles/MacTheme.axaml` as an Avalonia `Styles` resource containing named brushes for canvas, sidebar/toolbar, card, border, primary/secondary text, accent, accent hover, danger, warning surface, and success. Add control styles for the classes listed under **Produces** plus coherent defaults for `Button`, `TextBox`, `NumericUpDown`, `CheckBox`, `ProgressBar`, `Expander`, `ListBox`, and `ScrollViewer`.

Use a light palette close to native macOS utility windows: canvas `#F5F5F7`, card `#FFFFFF`, subtle surface `#ECECF0`, border `#D9D9DE`, primary text `#1D1D1F`, secondary text `#6E6E73`, accent `#0A84FF`, danger `#D70015`. Keep shadows/borders restrained and do not simulate traffic-light window controls.

- [ ] **Step 3: Load the theme and keep native window chrome**

In `App.axaml`, set `RequestedThemeVariant="Light"`, keep `FluentTheme`, and add:

```xml
<StyleInclude Source="avares://MjmCleaner.App/Styles/MacTheme.axaml" />
```

In `MainWindow.axaml`, retain the real macOS title bar and use a compact 64 px toolbar under it. Present `TotalFreedText` as a small label/value group, and render `Storico` and `Impostazioni` as icon-plus-label toolbar buttons using inline Avalonia `Path` geometry. Give the page host a centered maximum width around 1120 px with 28–32 px outer padding; preserve the existing `CurrentPage`, `ShowHistoryCommand`, and `ShowSettingsCommand` bindings.

- [ ] **Step 4: Refresh the four wizard pages without changing flow**

Apply a consistent compact stepper header and page-title block to Choose, Scan, Confirm, and Done.

- `ChooseStepView`: render choices as a connected white settings list with separators/soft cards, stronger title/description hierarchy, compact risk pills, and a sticky-looking bottom action row. Preserve `Choices`, `IsSelected`, `Indent`, `RiskLabel`, and `AnalyzeCommand`.
- `ScanStepView`: center the active scan state in a calm progress card, keep category progress readable in a white list, and keep cancel/error recovery commands intact.
- `ConfirmStepView`: improve category expanders and virtualized path rows, place the permanent-deletion warning in a tinted warning surface, and make the delete button visually destructive while preserving all progress/error/exclusion content.
- `DoneStepView`: create a centered success summary with a subtle success glyph, keep error/history warnings visible, and retain `NewCleanupCommand`.

- [ ] **Step 5: Refresh utility pages**

- `HistoryView`: add a descriptive subtitle, a bordered table surface with a clear header row (`Data`, `Spazio`, `Categorie`, `Elementi`), row separators, empty-space restraint, and a quiet close action. Continue using `Rows` and `CloseCommand` only.
- `SettingsView`: group project paths, large-file paths, and age thresholds into separate white sections; place explanatory copy below the relevant field; use native-sized controls and a footer with secondary `Annulla` and primary `Salva`. Preserve every existing binding.

- [ ] **Step 6: Compile and inspect the UI**

Run:

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet build src/MjmCleaner.App/MjmCleaner.App.csproj
dotnet run --project src/MjmCleaner.App/MjmCleaner.App.csproj
```

Expected: AXAML compilation succeeds and the running app shows the redesigned Choose page. Navigate through all reachable pages with safe/no-op data, checking clipping at the minimum window size (720×520) and the normal size (900×640). Capture at least one screenshot for review, then close the app.

### Task 2: Create and package a native macOS application icon

**Files:**
- Create: `src/MjmCleaner.App/Assets/AppIcon-1024.png`
- Create: `build/make-icon.sh`
- Modify: `build/Info.plist`
- Modify: `build/bundle.sh`

**Interfaces:**
- Consumes: one 1024×1024 source PNG generated for this project.
- Produces: `artifacts/mjm.cleaner.app/Contents/Resources/AppIcon.icns` and `CFBundleIconFile=AppIcon` in the final bundle.

- [ ] **Step 1: Generate the icon source with the image-generation skill**

Use built-in image generation with this prompt:

```text
Use case: logo-brand
Asset type: macOS application icon source, 1024×1024
Primary request: a refined utility icon for a safe disk-cleaning app: a rounded-square macOS icon with a minimal white cleaning brush sweeping one small sparkle, communicating cleanup without depicting a trash can or hazardous deletion
Style/medium: polished dimensional vector-like 3D icon, simple large shapes, subtle depth and soft inner highlights
Composition/framing: centered symbol, generous optical padding, readable at 16 px, no elements touching the edge
Color palette: calm blue-to-teal background with white symbol and one restrained aqua highlight
Constraints: no text, no letters, no watermark, no photorealism, no dark background, no Apple logo, no Finder face
```

Inspect the result at full size and as a 32 px thumbnail. Copy the selected asset into `src/MjmCleaner.App/Assets/AppIcon-1024.png`; do not leave the project reference pointing to a generated-image cache path.

- [ ] **Step 2: Add deterministic `.icns` generation**

Create executable `build/make-icon.sh` that accepts the source PNG and destination `.icns`, creates a temporary `.iconset` with `mktemp -d`, installs a cleanup trap, uses `sips -z` to create 16, 32, 64, 128, 256, 512, and 1024 pixel representations with the conventional `icon_16x16.png`, `icon_16x16@2x.png`, … filenames, then runs `iconutil -c icns`. Quote every path and fail fast with `set -euo pipefail`.

- [ ] **Step 3: Connect the icon to the app bundle**

Add to `build/Info.plist`:

```xml
<key>CFBundleIconFile</key>
<string>AppIcon</string>
```

Update `build/bundle.sh` to invoke `build/make-icon.sh` after creating `Contents/Resources` and before signing. The generated path must be `$APP/Contents/Resources/AppIcon.icns`.

- [ ] **Step 4: Verify final behavior and packaging**

Run:

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet test
dotnet build
./build/bundle.sh
test -s artifacts/mjm.cleaner.app/Contents/Resources/AppIcon.icns
plutil -lint artifacts/mjm.cleaner.app/Contents/Info.plist
codesign --verify --deep --strict artifacts/mjm.cleaner.app
```

Expected: full test suite passes, solution builds, `.icns` exists and is non-empty, plist validation succeeds, and code-signature verification exits 0.

- [ ] **Step 5: Self-review the complete diff**

Confirm that only presentation/packaging files and this plan changed; no ViewModel or core logic changed. Confirm every original binding and command still appears in the corresponding view. Check the new screenshot against the approved direction: light-first, native-looking, modern, restrained, and readable rather than a generic web dashboard.
