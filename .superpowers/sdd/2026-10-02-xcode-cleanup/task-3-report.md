# Task 3 report: classification and immutable confirmation

## RED

Command:

```text
/usr/local/share/dotnet/dotnet test tests/MjmCleaner.Core.Tests --filter FullyQualifiedName~Xcode --no-restore
```

Before implementation, the focused test build failed with missing `XcodeClassifier`, `XcodeSelection`, `XcodeConfirmation`, and `XcodeConfirmedPlan` symbols. This was the expected RED state for the new API and tests.

## GREEN

Command:

```text
/usr/local/share/dotnet/dotnet test tests/MjmCleaner.Core.Tests --filter FullyQualifiedName~Xcode --no-restore
```

Result: Passed 45, Failed 0, Skipped 0. `git diff --check` passed.

## Review

- Classification keeps rows unselected, blocks booted devices and runtimes with booted dependencies, blocks file cleanup while Xcode is running, and requires verified UUID identity. An unavailable device remains selectable when its UUID matches the CLI identity.
- Preview admits only explicit keys, normalizes UUID key spelling, collapses equivalent selections, rejects unknown or blocked keys, and leaves dependent devices out of the selected candidates.
- Confirmation requires acknowledgement for retained dependent devices and copies candidates, dependencies, and guarded inventory into read-only collections. Null sizes stay null and are counted separately from known estimated bytes.
- The pre-existing local modifications to `CategoryCatalog.cs` and `CategoryCatalogTests.cs` were not touched or staged.
