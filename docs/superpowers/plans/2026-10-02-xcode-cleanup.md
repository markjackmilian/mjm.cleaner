# Xcode Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Aggiungere una pagina Xcode per pulire DerivedData e Device Support e rimuovere dispositivi simulati e runtime scelti esplicitamente.

**Architecture:** Modulo Core/Xcode con inventario file e CLI, classificazione, piano confermato, esecuzione e misurazione separati. ViewModel e viste Avalonia seguono la pagina Docker; filesystem, process runner, protezioni e cronologia esistenti vengono riutilizzati.

**Tech Stack:** C#/.NET 10, Avalonia, CommunityToolkit.Mvvm, System.IO.Abstractions, xUnit, CLI Xcode simctl, SQLite esistente.

**Spec:** `docs/superpowers/specs/2026-10-02-xcode-cleanup-design.md`

## Global Constraints

- Gruppi inclusi: DerivedData, Device Support, dispositivi simulati, runtime iOS/watchOS/tvOS/visionOS.
- Archives esclusi: contengono binari e simboli delle release.
- Tutte le voci partono deselezionate.
- Solo DerivedData e Device Support consentono selezione di gruppo.
- Dispositivi e runtime richiedono selezione individuale.
- Nessun alias all/unavailable, nessuna rimozione ricorsiva diretta di CoreSimulator, nessun sudo e nessun allargamento della deny-list per consentire i runtime.
- Una risorsa cambiata viene saltata e riportata: la nuova analisi non amplia mai la selezione approvata.
- Dimensioni sconosciute restano sconosciute e non valgono zero.
- Non modificare né includere nei commit le modifiche locali preesistenti non prodotte da questo lavoro.
- Eseguire comandi dotnet con `/usr/local/share/dotnet/dotnet`; non cancellare dati reali durante la verifica.

## Review Focus

- Più immagini con uguale versione ma build diverse: nessuna associazione ambigua autorizza la rimozione (Task 1).
- Inventario dispositivo illeggibile dopo un comando riuscito: esito incerto, nessun incremento del contatore (Task 4).
- Xcode o un dispositivo avviato dopo la conferma: bloccare la risorsa prima della mutazione (Task 4).
- Dimensione parziale per accesso negato o immagine condivisa: non dichiarare un totale esatto o sommare duplicati (Task 2).
- Doppio clic, navigazione o annullamento durante la pulizia: nessuna seconda esecuzione e report parziale persistito (Task 5).

## File structure

Nuovi file sotto `src/MjmCleaner.Core/Xcode/`:
`XcodeModels.cs` (contratti), `XcodeCli.cs` (comandi), `XcodeJson.cs` (parsing),
`XcodeInventoryCollector.cs` (inventario CLI), `XcodeFileScanner.cs` (cache),
`XcodeSizeProbe.cs` (misure), `XcodeClassifier.cs` (blocchi),
`XcodeSelection.cs` (conferma), `XcodeCleanExecutor.cs` (mutazioni),
`XcodeCleanupService.cs` (coordinamento).

Nuovi ViewModel `XcodeViewModel.cs`, `XcodeReportViewModel.cs` e relative viste
`XcodeView.axaml[.cs]`, `XcodeReportView.axaml[.cs]`. Test Core in `Xcode/`, test
App in `Xcode/`. Modifiche di integrazione elencate nei task sotto.

### Task 1: Inventario CLI e contratti

**Files:** Create `src/MjmCleaner.Core/Xcode/{XcodeModels,XcodeCli,XcodeJson,XcodeInventoryCollector}.cs`; create `tests/MjmCleaner.Core.Tests/Xcode/{XcodeJsonTests,XcodeCliTests,XcodeInventoryCollectorTests}.cs` and `Xcode/Fixtures/*.json`; modify `tests/MjmCleaner.Core.Tests/MjmCleaner.Core.Tests.csproj` to copy fixtures.

**Interfaces:**
- `XcodeResourceKind`: DerivedData, DeviceSupport, Device, Runtime.
- `XcodeCandidate`: Key, Kind, Name, Path?, CliId?, RuntimeIdentifier?, Build?, State?, SizeBytes?, BlockReason?, Dependencies (device keys). Derived property `CanSelect` requires no BlockReason.
- `XcodeSnapshot`: Candidates and Warnings; warnings carry resource group and message.
- `IXcodeCli.ReadInventoryAsync(CancellationToken) -> Task<XcodeSnapshot>`.
- `IXcodeCli.DeleteDeviceAsync(string uuid, CancellationToken) -> Task<ProcessResult>`; `DeleteRuntimeAsync(string uuid, CancellationToken) -> Task<ProcessResult>`.
- `IXcodeInventoryCollector.CollectAsync(CancellationToken) -> Task<XcodeSnapshot>`.

- [ ] Write failing tests: `EmptyInventoryIsSuccessful`, `MalformedDevicesProducesWarningAndBlocksRuntimes`, `SameVersionDifferentBuildDoesNotGuess`, `MissingRemovalUuidBlocksRuntime`, `DeleteUsesOnlyValidatedUuid`, `RuntimeDeleteUnsupportedIsReported`. Assert blocked runtimes cannot be selected and aliases `all`, `unavailable` and non-UUID arguments never launch a process.
- [ ] Run `/usr/local/share/dotnet/dotnet test tests/MjmCleaner.Core.Tests --filter 'FullyQualifiedName~Xcode'`; expect failures for missing contracts/implementation.
- [ ] Implement models and CLI using existing `IProcessRunner`, argument lists, 30-second inventory timeout and 5-minute deletion timeout. Detect runtime-delete support from help, capture inventory sources independently, map runtime identifiers/builds to image UUIDs, and block ambiguous mappings. Keep known resources visible on partial failure, with unsafe simulator deletion disabled.
- [ ] Run the same filtered tests; expect all pass. Verify local help and read-only JSON parsing; keep nonempty synthetic fixtures because the local inventory is empty.
- [ ] Commit only Task 1 files: `feat(xcode): add read-only simulator inventory`.

### Task 2: File inventory and space estimates

**Files:** Create `src/MjmCleaner.Core/Xcode/{XcodeFileScanner,XcodeSizeProbe}.cs`; create `tests/MjmCleaner.Core.Tests/Xcode/{XcodeFileScannerTests,XcodeSizeProbeTests}.cs`.

**Interfaces:**
- `IXcodeFileScanner.ScanAsync(CancellationToken) -> Task<XcodeSnapshot>`.
- `IXcodeSizeProbe.MeasureAsync(string path, CancellationToken) -> Task<long?>` returns allocated bytes when measurable.
- `IXcodeSizeProbe.GetFreeBytesAsync(CancellationToken) -> Task<long?>` measures the volume holding the user home.
- File candidates retain guarded `ScanItem` values in a separate `XcodeFileInventory` keyed by candidate Key; extend the snapshot with this immutable mapping.

- [ ] Write failing tests: `DerivedDataIsGroupedByProjectFolder`, `ArchivesAndUserDataAreNeverCandidates`, `AbsentSupportFolderIsEmpty`, `LinkedRootIsRejected`, `AccessDeniedSizeIsUnknown`, `SharedBackingImageCountedOnce`. Assert protected paths never become file candidates and unknown size remains null.
- [ ] Run filtered Xcode tests; expect new tests fail.
- [ ] Implement scanning with `RuleScanner`, `PathGuard` and existing link inspection. Use exact roots `~/Library/Developer/Xcode/DerivedData`, `iOS DeviceSupport`, `watchOS DeviceSupport`, `tvOS DeviceSupport`, `visionOS DeviceSupport` under the same Xcode directory. Confirm directory conventions read-only; absent roots are empty, inaccessible roots warn. Enumerate direct child directories only; exclude unrecognized files. Use allocated-size probing without traversing symlinks; failed or partial measurement returns null. Runtime size uses backing image, never mounted runtime contents. Deduplicate by canonical backing path and device UUID; label all totals as estimates due to APFS clones.
- [ ] Run filtered tests; expect pass. Read-only inspect known roots on the Mac to validate supported locations.
- [ ] Commit only Task 2 files: `feat(xcode): scan guarded cache and support folders`.

### Task 3: Classification and immutable confirmation

**Files:** Create `src/MjmCleaner.Core/Xcode/{XcodeClassifier,XcodeSelection}.cs`; create `tests/MjmCleaner.Core.Tests/Xcode/{XcodeClassifierTests,XcodeSelectionTests}.cs`.

**Interfaces:**
- `XcodeClassifier.Classify(XcodeSnapshot snapshot, bool xcodeRunning) -> XcodeSnapshot`.
- `XcodeSelection.Preview(XcodeSnapshot snapshot, IReadOnlySet<string> selectedKeys) -> XcodeConfirmation`.
- `XcodeConfirmation`: selected candidates, retained dependent devices, estimated bytes, unknown-size count.
- `XcodeSelection.Confirm(XcodeConfirmation preview, bool acknowledgeDependencies) -> XcodeConfirmedPlan`; throws on invalid selection or unacknowledged retained dependencies. Plan includes copied candidates and guarded file inventory from the source snapshot.

- [ ] Write failing tests: `AllRowsStartDeselected`, `BootedDeviceAndItsRuntimeAreBlocked`, `XcodeRunningBlocksFileCleanup`, `UnknownKeyIsRejected`, `RetainedDependenciesRequireAcknowledgement`, `ConfirmDoesNotSelectDependentDevices`, `UnknownSizesRemainVisible`.
- [ ] Run filtered Xcode tests; expect new failures.
- [ ] Implement deterministic classification; only explicit keys may enter confirmation, duplicate keys collapse, blocked/unknown keys reject the plan. Show retained dependent devices by name, runtime and UUID; unavailable devices remain individually selectable if their identity is verified.
- [ ] Run filtered tests; expect pass.
- [ ] Commit only Task 3 files: `feat(xcode): add explicit selection and dependency confirmation`.

### Task 4: Execution, revalidation and report

**Files:** Create `src/MjmCleaner.Core/Xcode/{XcodeCleanExecutor,XcodeCleanupService}.cs`; create `tests/MjmCleaner.Core.Tests/Xcode/{XcodeCleanExecutorTests,XcodeCleanupServiceTests}.cs`; extend `XcodeModels.cs` with result contracts.

**Interfaces:**
- `XcodeItemOutcome`: Deleted, Skipped, Failed, Uncertain.
- `XcodeItemResult`: candidate, outcome, reason, verified estimated bytes nullable.
- `XcodeCleanResult`: `CleanReport HistoryReport`, item results, free bytes before/after nullable, warnings.
- `IXcodeCleanupService.AnalyzeAsync(CancellationToken) -> Task<XcodeSnapshot>` combines file/CLI inventories and current Xcode-running state.
- `IXcodeCleanupService.ExecuteAsync(XcodeConfirmedPlan plan, IProgress<CleanProgress>? progress, CancellationToken ct) -> Task<XcodeCleanResult>`.

- [ ] Write failing tests: `RevalidationNeverAddsItems`, `ChangedIdentityIsSkipped`, `DeviceBootedAfterConfirmationIsSkipped`, `XcodeStartedAfterConfirmationBlocksFiles`, `DevicesRunBeforeRuntimes`, `DeviceFailureSkipsDependentRuntime`, `TimeoutWithUnreadableInventoryIsUncertain`, `CancellationRetainsCompletedResults`, `FailedAndUnknownSizesDoNotIncreaseHistoryBytes`, `IndependentFailureDoesNotStopOtherItems`. Assert exact fake runner calls and no filesystem deletion for simulator paths.
- [ ] Run filtered tests; expect new failures.
- [ ] Implement per-operation fresh inventory/state checks, comparing UUID, build, runtime identity, dependencies and file identity metadata captured at analysis (creation/last-write timestamps and guarded path). Guarded files delegate to `ICleanEngine`; CLI resources require command success plus verified absence for Deleted. After timeout/cancel, read inventory with a separate bounded token and classify verified absence versus Uncertain. Never retry deletion automatically. Process selected devices before runtimes; skip runtime after dependent device failure or identity changes. Continue unrelated operations, preserve partial reports on exceptions/cancel, record unknown estimates as zero only in the legacy numeric history field, visibly flagged in the detailed report. Free-space delta is displayed separately and never credited to history.
- [ ] Run filtered tests; expect pass. Ensure a CLI runtime delete cannot auto-shutdown devices because fresh state checks block booted dependents.
- [ ] Commit only Task 4 files: `feat(xcode): execute confirmed cleanup with revalidation`.

### Task 5: Page, confirmation, report and integration

**Files:** Create `src/MjmCleaner.App/ViewModels/{XcodeViewModel,XcodeReportViewModel}.cs`, `src/MjmCleaner.App/Views/{XcodeView,XcodeReportView}.axaml` and code-behind; create `tests/MjmCleaner.App.Tests/Xcode/{XcodeViewModelTests,XcodeReportViewModelTests}.cs`; modify `src/MjmCleaner.App/Services/AppServices.cs`, `ViewModels/MainWindowViewModel.cs`, `Views/MainWindow.axaml`, `App.axaml`, `src/MjmCleaner.Core/Categories/CategoryCatalog.cs`, `tests/MjmCleaner.Core.Tests/Categories/CategoryCatalogTests.cs`, and `README.md`.

**Interfaces:**
- `XcodeViewModel` consumes `IXcodeCleanupService`, history/log services and navigation. Commands Analyze/Retry, Preview, BackToSelection, ConfirmDelete, CancelDelete, Close. Properties expose IsLoading, IsDeleting, groups, confirmation, acknowledgement and warnings.
- `XcodeReportViewModel` consumes `XcodeCleanResult`; persists report/log exactly once, refreshes cumulative total, and exposes per-resource results plus separately labeled free-space delta.
- `AppServices.Xcode` exposes `IXcodeCleanupService`; `MainWindowViewModel.ShowXcodeCommand` navigates to the page.

- [ ] Write failing tests: `GroupSelectionOnlyAffectsCaches`, `DeleteRequiresPreviewAndAcknowledgement`, `DoubleClickExecutesOnce`, `RetryClearsOldSelection`, `CannotNavigateDuringDelete`, `CancelledPartialReportIsSavedOnce`, `UnknownSizeUsesUnavailableLabel`, `PersistenceFailureShowsReportAndError`, `GeneralCategoryNoLongerContainsDerivedData`. Preserve the existing Archives exclusion tests.
- [ ] Run `/usr/local/share/dotnet/dotnet test tests/MjmCleaner.App.Tests --filter 'FullyQualifiedName~Xcode'` and Core category tests; expect new failures.
- [ ] Implement four expanding groups with inline warnings, explicit selection, final confirmation panel, dependency acknowledgement and disabled unsafe actions. Disable navigation and selection while executing; cancel requests stop new operations and await the report. Wire page templates, toolbar and service composition; move DerivedData out of the general catalog, preserve the user's existing Archives modifications and adjust development-cache description. Report persistence errors must keep results readable and prevent duplicate save retries. Update README with consequences, CLI compatibility and estimated-space limits.
- [ ] Run both focused suites; expect pass. Read diffs of locally modified catalog/test files against the pre-task snapshot so commits include only this task's additions; if hunks cannot be isolated, leave those files uncommitted and report them.
- [ ] Commit only owned changes: `feat(xcode): add cleanup page and report`.

### Task 6: Complete verification and delivery

**Files:** Modify plan checkboxes with actual completion evidence; fix only defects discovered within this feature.

- [ ] Run `/usr/local/share/dotnet/dotnet build`; require exit 0.
- [ ] Run `/usr/local/share/dotnet/dotnet test`; require all tests pass. Fix failures with a targeted regression test, then repeat affected checks.
- [ ] Run `./build/bundle.sh`; require a complete macOS bundle. Launch and inspect Xcode navigation, empty and error states, expansion, selection and confirmation; use fixtures in tests to cover nonempty inventories. Do not trigger a destructive real cleanup.
- [ ] Run `git diff --check` and inspect `git status --short`; require no whitespace errors and clearly identify preexisting user changes.
- [ ] Review the completed change against the spec, especially CLI-only deletion, booted dependencies, partial inventory and estimates. If independent review is selected, give the reviewer spec, plan and owned diff; resolve findings before delivery.
- [ ] Report implemented behavior, verification results and the limitation that deletion was validated with fake CLI/filesystem rather than real user data. Follow the finishing-branch workflow without merging or pushing unless authorized.
