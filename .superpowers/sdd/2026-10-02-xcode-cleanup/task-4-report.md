# Task 4 report: execution, revalidation and report

## Result

Implemented the Xcode cleanup service and executor. The service collects the combined file/CLI inventory, adds current Xcode process state, and leaves selected-item execution to a separately injectable executor. The executor receives `IXcodeCli`, `IXcodeInventoryCollector`, `ICleanEngine`, `IXcodeSizeProbe`, `IXcodeRunningProbe`, and `TimeProvider`.

`IXcodeRunningProbe` returns `Running`, `NotRunning`, or `Unknown`. Its `ps -axo comm=` check recognizes both Xcode and Xcode beta bundle paths, and a failed or timed-out process listing stays `Unknown`. Analysis and execution block file cleanup when that state cannot be verified.

Before every approved operation the executor collects fresh inventory and state, then compares the approved identity. It processes devices before runtimes. A runtime may proceed after a selected dependent device only when that device was verified absent; a changed/new dependency skips the runtime. File entries must still match their captured guarded path, directory flag, creation time, last-write time, and complete logical-size identity, then deletion delegates to `ICleanEngine`. Simulator paths never go through the file engine.

CLI deletion is issued once per candidate. The executor always attempts a bounded fresh inventory read afterward, including after timeout or cancellation. Verified absence is reported as deleted; an unreadable inventory is `Uncertain`; a still-present resource after an interrupted command is also `Uncertain`. Other selected resources continue after independent failures, while cancellation preserves completed results and marks remaining items skipped.

`XcodeCleanResult` carries item outcomes and reasons, `CleanReport` history, nullable free-space readings, and warnings. Verified known estimates contribute to history bytes; unknown estimates remain null in each item and contribute zero to the legacy numeric total. Free-space readings remain separate. Task 5 can compose the service with `IXcodeRunningProbe` and the public `IXcodeCleanupService` interface.

## RED / GREEN evidence

- RED: the first filtered run failed at compile time because `XcodeCleanExecutor`, `IXcodeRunningProbe`, `XcodeRunningState`, `IXcodeCleanExecutor`, and `XcodeCleanResult` did not exist yet.
- First GREEN attempt: 6/10 executor tests passed. The remaining failures exposed fixture verification sequencing and the legitimate removal of a runtime dependency after its selected device was verified deleted.
- After correcting the execution rule and fixtures, the focused executor/service/probe set passed: 16/16.
- Full Xcode test group passed: 66/66 using `/usr/local/share/dotnet/dotnet test tests/MjmCleaner.Core.Tests/MjmCleaner.Core.Tests.csproj --filter FullyQualifiedName~Xcode --no-restore`.
- All executor fakes use injected collectors, CLI, clean engine, measures, and process-state probe. No real simulator or file data was deleted.

## Files and integration notes

Owned implementation and tests are in `src/MjmCleaner.Core/Xcode/{XcodeCleanExecutor,XcodeCleanupService,XcodeRunningProbe,XcodeModels}.cs` and `tests/MjmCleaner.Core.Tests/Xcode/{XcodeCleanExecutorTests,XcodeCleanupServiceTests}.cs`. The service API is `IXcodeCleanupService.AnalyzeAsync(CancellationToken)` and `ExecuteAsync(XcodeConfirmedPlan, IProgress<CleanProgress>?, CancellationToken)`.

The workspace already had unrelated changes in `src/MjmCleaner.Core/Categories/CategoryCatalog.cs` and `tests/MjmCleaner.Core.Tests/Categories/CategoryCatalogTests.cs`; those are excluded from this task’s commit.
