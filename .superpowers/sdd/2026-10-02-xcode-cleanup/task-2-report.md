# Task 2 report: Xcode file inventory and size estimates

## RED / GREEN

- Initial filtered run failed at compile time because the requested `XcodeFileScanner` and `IXcodeSizeProbe` APIs did not exist yet.
- After adding the runtime backing-path assertion, its focused run failed as expected: the parsed runtime candidate had `Path == null` instead of the reported payload path.
- After implementation, `/usr/local/share/dotnet/dotnet test tests/MjmCleaner.Core.Tests/MjmCleaner.Core.Tests.csproj --filter FullyQualifiedName~Xcode --no-restore` passed: 31 passed, 0 failed.
- Full Core verification with `/usr/local/share/dotnet/dotnet test tests/MjmCleaner.Core.Tests/MjmCleaner.Core.Tests.csproj --no-restore` passed: 448 passed, 0 failed.

## Implementation

- Added guarded direct-child scanning for `DerivedData`, `iOS DeviceSupport`, `watchOS DeviceSupport`, `tvOS DeviceSupport`, and `visionOS DeviceSupport` under `~/Library/Developer/Xcode`. Missing roots stay empty, files are ignored, and linked roots or partial scans produce group warnings.
- Added `XcodeFileInventory`, an immutable key-to-entry mapping holding the guarded `ScanItem` and portable identity metadata: canonical path, directory flag, creation and last-write timestamps, and logical size.
- Added allocated-size probing via `du -k -s -P`, returning unknown for inaccessible, linked, timed-out, failed, or partial measurements. Free bytes come from the volume containing the home directory.
- Retained runtime backing payload paths reported in `path` or `diskImagePath`. The mounted runtime path is ignored. Runtime allocation is measured from the backing payload, and shared canonical backing paths contribute a size once; duplicates retain unknown size and a warning.
- Added tests for DerivedData grouping, protected/out-of-scope folders, absent roots, linked roots, unknown allocation, partial measurement, free bytes, shared backing paths, and runtime backing-path parsing.

## Read-only local inspection

`xcrun simctl runtime list --json` reported a runtime `path` under `...asset/AssetData`, plus a distinct `mountPath` under `/private/var/run/...`. The reported payload folder contains `Restore/043-70362-657.dmg`; `du -k -s -P` read it without following links. DerivedData and all four Device Support roots are absent on this Mac, so live folder contents could not validate their naming conventions. No real data was changed or deleted.

## Scope

Owned files are the Xcode scanner, size probe, models, parser adjustment, their focused tests, and this report. The pre-existing dirty `CategoryCatalog.cs` and `CategoryCatalogTests.cs` were left untouched and excluded from the commit.

## Round-one review fixes

- Exposed runtime backing-image enrichment through `IXcodeFileScanner` and wired the collector to combine CLI and file inventories, then measure runtime backing paths when a scanner is supplied. The original one-argument collector construction remains valid for existing callers.
- Deduplicated device rows by UUID. Exact repeats collapse to one row; conflicting metadata collapses to one blocked row with unknown size, and every runtime named by the conflicting rows is blocked because its dependencies cannot be verified.
- Made logical size nullable in the captured identity. A candidate whose recursive scan has an error beneath its path is blocked and stores unknown logical size, so later revalidation cannot mistake a partial traversal for a complete fingerprint.
- When `Directory.Exists` returns false, the scanner now performs a narrow direct enumeration probe. Not-found stays empty; access-denied and other I/O errors produce warnings. Added a simulated filesystem test for the hidden access-denied case.
- RED evidence: the new collector integration test initially failed to compile because the injectable scanner constructor was absent; the conflict test then failed because neither associated runtime was blocked. Focused Xcode tests pass 35/35, and the full Core suite passes 452/452.
