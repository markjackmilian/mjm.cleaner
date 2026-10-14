# SDD ledger — plan: docs/superpowers/plans/2026-10-13-swift-port-3-xcode.md

Spec: docs/superpowers/specs/2026-10-13-swift-native-port-design.md (reachable).
Branch: feat/swift-port-docker-xcode — plan 3 runs after plan 2 on the same branch (plan 2 ledger: .superpowers/sdd/2026-10-13-swift-port-2-docker/progress.md).
Reports are `.txt`.

## Pre-flight scan (2026-10-14)

Evidence base: before execution the controller applied every code block of plan 2 then plan 3 (file blocks,
the 10 "sostituire" edits of Task 1, the Package.swift replacement of Task 4, the "In fondo a" append of Task 10)
to a scratch copy of the package: `swift build --build-tests -Xswiftc -warnings-as-errors` clean, 463 tests green.
Plan 2 as executed diverged from its plan text only by added tests (+4 Swift-only → 360) and comment/doc edits;
it did not touch Platform/, Tests/Support/ or anything plan 3 edits except Package.swift (exactly the block plan 3
replaces) and the parity register. Automated check: no `@Test` without `#expect`/`#require` in
Tests/CleanerCoreTests/{Xcode,Integration/XcodeRealFileSystemTests,Platform/FileSystemVolumeTests}.

### Shared files / interfaces between tasks

| Tasks | Produces → consumes | Found |
|---|---|---|
| 1 → 6,7,9,11 | `FileSystem.availableFreeSpace(forVolumeContaining:)`, `FileItemInfo.creation`; edits to LocalFileSystem/InMemoryFileSystem/ForwardingFileSystem | snippets match current files (unchanged since plan 1) — OK |
| 2 → 3..11 | Xcode models, `XcodeText`, `XcodeUuid` | compiles in sequence — OK |
| 3 → 9,10,11 | `XcodeClassifier`, `XcodeSelection` (confirm/preview) | compiles — OK |
| 4 (Package.swift) ↔ plan 2 Task 2 | replaces `exclude: ["Docker/Fixtures"]` block with Docker+Xcode | block on disk identical to plan 2 text — OK |
| 4 → 5,8 | `XcodeJson` + order-preserving reader | compiles — OK |
| 5 → 8,9,10 | `XcodeCli`, `XcodeCliInvoking` | compiles — OK |
| 6 → 7,9,11 | `XcodeSizeProbe`, `XcodeRunningProbe` | compiles — OK |
| 7,8 → 9,10,11 | file scanner, inventory collector | compiles — OK |
| 9 ↔ 10 | Task 10 appends to XcodeCleanupServiceTests.swift ("In fondo a") — created by Task 9? (applied cleanly in sequence) | OK |
| 1..11 ↔ register | each task replaces its own `Xcode/…` row; Task 11 adds the closing line | Ruling below (placement + count) |
| all ↔ plan 2 boundary | no file under Docker/ touched (Task 11 Step 4 grep) | OK |

### Per-task self-consistency

| Task | Found |
|---|---|
| 1–11 | each task's tests vs code green in the sequential apply (per-task counts 6+9+15+20+9+9+8+2+25+2+2 = 107) — OK |

### Rulings before Task 1

- Ruling: expected suite totals are plan 2's real total (360) + this plan's per-task counts, i.e. 467 at the end (plan text says 463 via "242 + plan 2 + 107") — why: plan 2 gained 4 Swift-only tests in review — cost if wrong: none (counts only).
- Ruling: Task 11's closing line «Piano 3 completato …» goes under the plan-2 line (the plan text says "sotto la riga del piano 1", written before plan 2's line existed) and states the suite total («suite Swift verde (467 test)») like the plan-2 line — why: keep the register's header chronological and uniform — cost if wrong: one doc line placement.
- Ruling: Task 11 commit stages explicit paths only (not `git add swift/MjmCleanerKit`) — why: untracked user files must never be staged — cost if wrong: none.
- Note for Task 9 review (from plan 2 final review): Xcode executor guards, if regex-based, should keep a strict `$` and be pinned by tests.

## Tasks
Task 1: dispatched (BASE 34ba6c8, implementer haiku, agent a9685337da14759ea; expected total 366)
Task 1: implemented 56f88fc (366 tests, trailer verified; concern: InMemoryFileSystem.writeData keeps creation date, LocalFileSystem rename gives new birth time); review dispatched (sonnet, agent a1bb3ff20a3bc9c3e)
Task 1: ⚠️ resolved — trailer verified (Opus 5.5).
Task 1: minor (deferred): FileSystem.swift:35-37 doc says creation survives rewrites, but LocalFileSystem.writeData (temp+rename) gives a new birth time; InMemoryFileSystem.write preserves it (untested branch). Irrelevant to plan 3 (creation read only for directories) — qualify the doc.
Task 1: minor (deferred): free-space test can't distinguish the queried path from "/" (1 GiB tolerance); ENOENT test pins the argument.
Task 1: note: creation default = lastWrite fails safe for future FileSystem implementations (identity check sees a change).
Task 1: complete (commits 34ba6c8..56f88fc, review clean)
Task 2: dispatched (BASE 56f88fc, implementer haiku, agent af5019fef455c66c3; expected total 375)
Task 2: implemented fcf4105 (375 tests, trailer verified); review dispatched (sonnet, agent adf31cd0aa7dc08b2)
Task 2: review → Approved with 1 Important (plan-mandated): XcodeFileIdentity's synthesized Equatable compares canonicalPath by canonical equivalence (NFC == NFD), while C# record equality is ordinal; it is the identity type of the pre-delete revalidation guard.
Task 2: Ruling: hand-write `==` on XcodeFileIdentity with `XcodeText.same` for canonicalPath (other fields unchanged) + one Swift-only test (NFC vs NFD canonicalPath → unequal); register row XcodeModelsTests +1 Swift-only; plan totals +1 (end 468) — why: the plan's own constraint forbids String `==` for Ordinal comparisons and this public type is the guard's identity; plan 3 Task 9's sameFileIdentity already compares field-wise with XcodeText.same, so this removes a latent trap (e.g. plan 4 code using `==`) rather than a live bug — cost if wrong: one small function and one test differ from the plan text.
Task 2: minor (deferred): XcodeFileInventory.init silently drops duplicate keys (first wins) where C# ToDictionary/Dictionary.Add throws — divergence not in the register's «Differenze» table.
Task 2: minor (deferred): XcodeText.swift imports only Darwin but uses String(localized:) (transitive Foundation import).
Task 2: minor (deferred): XcodeText.message default branch uses String(describing:) (debug text for non-Xcode errors; consistent with RuleScanner/CleanEngine); untested.
Task 2: minor (deferred): no negative N-form UUID cases (non-hex, uppercase) nor mismatched brackets in XcodeTextTests; unused `private static let uuid` in XcodeTextTests.swift:8.
Task 2: fix round 1 dispatched (resume implementer af5019fef455c66c3)
Task 2: fix round 1 implemented a2004c7 (XcodeModelsTests 3, full 376; mutation → fails at :49)
Task 2: scoped re-review dispatched (haiku, agent a3bff53afa3ef2f88)
Task 2: fix round 1/5 (1 addressed, 0 open; commits fcf4105..a2004c7)
Task 2: minor (deferred): XcodeCandidate and XcodeFileEntry.item (ScanItem.path) keep synthesized Equatable over Strings (canonical equivalence); lookups already use ordinalKey — check later tasks don't compare candidates/entries with `==` for decisions.
Task 2: complete (commits 56f88fc..a2004c7, review clean after 1 fix round)
Task 3: dispatched (BASE a2004c7, implementer haiku, agent a8c448e2b31001ee4; expected total 391)
Task 3: implemented 0696c98 (391 tests, trailer verified); review dispatched (sonnet, agent a1cc9aac556178483)
Task 3: review → Needs fixes: 1 Important: the file guard (XcodeSelection.completeFileGuard, :332-345) that gates directories into the deletion plan is mostly untested — reviewer mutated XcodeText.same→`==` and dropped the lastWriteTime conjunct: all 15 shipped tests stayed green.
Task 3: ⚠️ for later: unavailableStateWarning relaxation (XcodeClassifier.swift:124-127) depends on Task 4's parser emitting the identical localized string — check at Task 4 review.
Task 3: minor (deferred): confirmationCopiesCandidatesAndGuardedInventory second half vacuous under value semantics (plan-mandated).
Task 3: minor (deferred): selectedKeys: Set<String> collapses canonically-equivalent keys (under-selects; safe direction) — comment at app layer (plan 4).
Task 3: minor (deferred): `ordinalKey(normalizeSelectionKey(x))` repeated 7×; unreachable duplicate-key guard XcodeSelection.swift:256-258 (mirrors C#).
Task 3: minor (deferred): XcodeSelection.swift:297 Int64 reduce traps on overflow (C# Sum throws OverflowException); unrealistic.
Task 3: fix round 1 dispatched (resume implementer a8c448e2b31001ee4): Swift-only tests — one-defect-at-a-time guard cases (parameterized), NFC/NFD canonicalPath/item.path rejection, NFD selected key unknown; mutation checks; register; expected 394 (plan end 471).
Task 3: fix round 1 implemented 75200c3 (XcodeSelectionTests 12, full 394; mutations a/b/c all caught)
Task 3: scoped re-review dispatched (sonnet, agent adffb5121e696fc7b)
Task 3: fix round 1/5 (1 addressed, 0 open; commits 0696c98..75200c3)
Task 3: minor (deferred, safety-relevant): confirm() re-runs completeFileGuard (XcodeSelection.swift:111-113, XcodeOperationError "lost its guarded inventory entry") — no test reaches it; removing it keeps the suite green (C# same gap). Also new guard tests use only .derivedData (no .deviceSupport).
Task 3: complete (commits a2004c7..75200c3, review clean after 1 fix round)
Task 3: ⚠️ resolved — Task 4 brief emits the identical "Stato del dispositivo non verificato: \(state); ripeti l'analisi." string used by XcodeClassifier.swift:43.
Task 4: dispatched (BASE 75200c3, implementer haiku, agent aa318934fa73d58e0; expected total 414)
Task 4: implemented 12883ff (414 tests, trailer verified, fixtures cmp-identical); review dispatched (sonnet, agent a77f76e0a3e944b52)
Task 4: review → Needs fixes (tests only): Important 1: ordinal discipline unpinned (mutants using String ==/!= in XcodeJsonReader.property, conflict checks on name/runtimeIdentifier, exactMatches, dependentDevices all pass — test data is ASCII). Important 2: hostile-input guards unpinned — removing the low-surrogate guard (XcodeJsonReader.swift:202) passes all tests and crashes (SIGTRAP) on ["\ud800A"]; object-depth guard (:106) untested (depth test uses arrays only); truncated inputs not enumerated. Reviewer differential: 28k inputs vs .NET JsonDocument, 140k inventories vs C# ParseInventory — identical except documented lone-surrogate rejection.
Task 4: minor (deferred): parity.md:140 understates the surrogate difference (Swift rejects surrogates in unread fields/names; high+non-low \u escape; C# keeps images read before the failing one, Swift returns none + warning) — all fail-safe.
Task 4: minor (deferred): syntax-error warning text ("JSON non valido al byte N") asserted nowhere; XcodeJsonReader.swift:210 needless allocation.
Task 4: fix round 1 dispatched (resume implementer aa318934fa73d58e0)
Task 4: fix round 1 implemented d3510e3 (+5 @Test, invalid-document list 17→25 cases, object depth 64/65; full 419; mutants a–e all caught, d crashes the test process with SIGTRAP)
Task 4: scoped re-review dispatched (sonnet, agent a2e3d13723b77e1bc). Running plan-end total now 476 (467 +1 T2 +3 T3 +5 T4).
Task 4: fix round 1/5 (2 addressed, 0 open; commits 12883ff..d3510e3) — reviewer re-verified each mutant and the C# outcomes with a .NET 10 probe.
Task 4: minor (deferred): still unpinned for NFC/NFD: `other.state` conflict check (XcodeJson.swift:143), build/version terms (:217, :236-237); test name invalidDocumentsAreRejectedLikeJsonDocument overstates parity for surrogates (documented in register).
Task 4: complete (commits 75200c3..d3510e3, review clean after 1 fix round)
Task 5: dispatched (BASE d3510e3, implementer haiku, agent a5613fcdd3d7c91b4; expected total 428)
Task 5: implemented e8e4cc4 (428 tests, trailer verified); review dispatched (sonnet, agent ae7492c6b44fcd5d2)
Task 5: minor (deferred, safety-relevant): validateUuid checks the trimmed text but the raw (whitespace-padded) uuid is forwarded to simctl delete — same as C#, cannot become an option/alias; not in «Candidati a miglioramento».
Task 5: minor (deferred, safety-relevant): invalidDeleteIdentifiersNeverLaunchAProcess has only the 4 C# inputs — a weakened guard (`count == 36`, or XcodeUuid.canonical accepting N/B/P forms) would pass; missing `booted`, "", whitespace-only, 36-char leading "-", 35/37 chars, N-form, braced.
Task 5: minor (deferred): timedOut path untested (no case passes timedOut: true).
Task 5: minor (deferred): parity row says 9 (4), convention gives 9 (14) (plan-mandated); «Xcode command line tools non trovati.» localized twice.
Task 5: complete (commits d3510e3..e8e4cc4, review clean)
Task 6: dispatched (BASE e8e4cc4, implementer haiku, agent ad346795ed4e7e267; expected total 437)
Task 6: implemented 8690f1c (437 tests, trailer verified); review dispatched (sonnet, agent a2a30d64fcc000414)
Task 6: minor (deferred): embedded NUL in XcodeSizeProbe.measure path passes fileExists/argv (C-string truncation) → du measures the truncated prefix (read-only, over-reported estimate); C# returns null. Controller verified deletion is NOT exposed: CanonicalPath.swift:19 rejects NUL and PathGuard.validate denies non-canonical paths. Fix candidate: `!path.utf8.contains(0)` in the measure guard.
Task 6: minor (deferred): ps args/5 s timeout and du 30 s timeout unpinned (runners drop timeout); free-space test can't tell home from "/"; Int64.max/1024 accept side untested; no cancellation tests for measure/freeBytes/state; freeBytes catch-all vs narrow list; no @concurrent on state() (no effect without NonisolatedNonsendingByDefault).
Task 6: complete (commits e8e4cc4..8690f1c, review clean)
Task 7: dispatched (BASE 8690f1c, implementer haiku, agent ad0d99ce46182e36a; expected total 445)
Task 7: implemented 7a263d9 (445 tests, trailer verified); review dispatched (sonnet, agent a77c890d6725660fb)
Task 7: review → Approved with 2 Important (plan-mandated test gaps): (1) scanner guard/identity properties unpinned — mutants pass 8/8: pathGuard.validate→.allow(item.path) (:93), canonical→item.path (:99), per-item link/dir recheck removed (:94), itemInfo(root) (:105), identity dates/isDirectory altered (:115-117), ScanItem(path: item.path) (:119), runtime branch guards removed (:158-175); (2) XcodeFileScannerTests.swift:70-71 `creationTime != nil`/`lastWriteTime != nil` can never fail (non-optional Dates).
Task 7: Ruling: fix round with Swift-only tests (PathGuarding double returning a different canonical path / denying; stateful LinkInspecting for the per-item recheck; identity equality against fs.itemInfo; runtime-branch symlink/deny/relative/empty cases) and replace the two vacuous assertions in the ported test with equality against the file system's itemInfo values (test name kept) — why: same standard as Tasks 3/4 and plan 2 (safety properties must have a failing test); the executor (Task 9) relies on this inventory — cost if wrong: extra tests; a ported test's assertions differ from the C# wording (stronger).
Task 7: ⚠️ note for Task 9: canonicalPathValidated is not a realpath (symlinked ancestors above the root are followed by plan-1 design, as in C#) — the executor must lstat and re-validate, not trust the scanner string to be link-free.
Task 7: minor (deferred): info.kind not checked (isDirectory hard-coded true) at :105-118; `first{}?.sizeBytes == nil` vacuous if missing (:144-145); itemInfo-throws "metadati non leggibili" branch, default errno/EPERM/EBADF/ENOTDIR and watchOS/tvOS/visionOS roots untested; unchecked subscript write candidates[index] (:155-184, safe by construction, plan-mandated); tests use String ==/< on ASCII.
Task 7: fix round 1 dispatched (resume implementer ad0d99ce46182e36a)
Task 7: fix round 1 implemented 9e92b2e (+10 @Test, XcodeFileScannerTests 18, full 455; 16/16 mutants caught). Running plan-end total now 486 (476 +10).
Task 7: scoped re-review dispatched (sonnet, agent a19424d5597960585)
Task 7: fix round 1/5 (2 addressed, 0 open; commits 7a263d9..9e92b2e) — re-reviewer reproduced the mutants in a scratch copy.
Task 7: minor (deferred): surviving mutant `itemInfo(canonical)`→`itemInfo(item.path)` at :105 (only distinguishable with the substituting guard double); derivedDataIsGroupedByProjectFolder's itemInfo(root) catch is timing-dependent (identity-dates test is the deterministic pin).
Task 7: complete (commits 8690f1c..9e92b2e, review clean after 1 fix round)
Task 8: dispatched (BASE 9e92b2e, implementer haiku, agent add3d7d4270efdfdd; expected total 457)
Task 8: implemented 0c53099 (457 tests, trailer verified); review dispatched (sonnet, agent a963868ec95a4bbe8)
Task 8: minor (deferred): merge contract (CLI-before-file order, warnings from both, fileInventory from the scan, combined snapshot to measureRuntimeBackingImages) not asserted — C# same gap; `first{}?.sizeBytes == 4096` weaker than Single.
Task 8: complete (commits 9e92b2e..0c53099, review clean)
Task 9: dispatched (BASE 0c53099, implementer haiku, agent acb68434903874f9e; expected total 482)
Task 9: implemented b98dee2 (482 tests ×2, trailer verified); review dispatched (opus, agent a66b447c42d98a085)
Task 9: review (opus) → Needs fixes: Important 1: folder safety decisions untested — mutants survive: M01 drop `.unknown` Xcode-state check (:76), M02 `sameFileIdentity || true`, M03 identity never re-read, M04 path compare dropped, M24 XcodeText.same→== on canonicalPath. Reviewer validated probe tests in scratch (scratchpad/rev-t9/).
Task 9: Ruling: reclassify review Minors 1–3 as Important and fix them in the same round — journal precision (M08 record before verification, M09 record when uncertain), runtime deletion argument (M07: FakeCli.deleteRuntime discards uuid), folder not deleted by CleanEngine → not credited (M13, M20) — why: they are safety properties the brief states, with no failing test; same standard the plan-2 final review applied ("safety guarantees with no test that fails when removed" = Important) — cost if wrong: a few extra tests in this round instead of the final fix wave.
Task 9: minor (deferred): raw cliId forwarded to XcodeCli (:178) — canonical in production via XcodeJson; passing canonicalExact(cliId)/oldId would be defense in depth (C# parity, production change).
Task 9: minor (deferred, plan 4): journal text (CleanEngine's guard-resolved target) can differ from history deletedPaths (candidate.path) when an ancestor of ~/Library/Developer is symlinked — plan 4 must not reconcile journal and history by text.
Task 9: minor (deferred): sameFileIdentity duplicates XcodeFileIdentity.== field by field (:300-304) — could use `==` now that it is ordinal (production change; plan-mandated duplication).
Task 9: minor (deferred): parsedUnknownDeviceStateRemainsBlockedAtExecutor's cli.deletedDevices assertion vacuous (no executor built; C# same); runtimeIdentifier compare (M11), free-space-after isolation (M14), CancellationError→.skipped (M15), verification isolation (M18, no outcome change) unpinned.
Task 9: fix round 1 dispatched (resume implementer acb68434903874f9e)
Task 9: fix round 1 implemented 6c3b4c5 (+8 @Test, XcodeCleanExecutorTests 33, full 490 ×2; 10/10 mutants killed). Running plan-end total now 494 (486 +8).
Task 9: scoped re-review dispatched (sonnet, agent a684598e3d889ebcb)
Task 9: fix round 1/5 (4 addressed, 0 open; commits b98dee2..6c3b4c5) — re-reviewer reproduced all 10 mutants in a fresh scratch copy; skip reasons probed and match the intended guards.
Task 9: complete (commits 0c53099..6c3b4c5, review clean after 1 fix round)
Task 10: dispatched (BASE 6c3b4c5, implementer haiku, agent a360bbe180574e824; expected total 492)
Task 10: implemented ffd0d22 (492 tests, trailer verified); review dispatched (sonnet, agent a68774c28924a3e28)
Task 10: minor (deferred): executeForwardsThePlanAndTheJournalToTheExecutor checks only journal != nil (progress nil, plan/result unchecked); unknown-state test covers one .derivedData item only (no .deviceSupport, existing blockReason, warnings/fileInventory); `xcodeRunning: state == .running` untested at service level (executor re-probes); double renamed FixedRunningProbe (brief-mandated).
Task 10: complete (commits 6c3b4c5..ffd0d22, review clean)
Task 11: dispatched (BASE ffd0d22, implementer haiku, agent a460a28d03ec33275; expected 494; header «Piano 3 completato il 2026-10-14: 74 prove C# Xcode portate (+ 60 nuove), suite Swift verde (494 test).» under the plan-2 line)
Task 11: implemented 745997b (494 tests, greps clean, trailer verified); review dispatched (sonnet, agent abf21c5cecb3b27f1)
Task 11: ⚠️ resolved — controller confirmed G5: no file under Docker/ changed between 56f88fc~1 and HEAD.
Task 11: minor (deferred): XcodeRealFileSystemTests asserts the journal path starts with "/private/var/" (fails spuriously if TMPDIR is under /tmp — loud, documented); Fixture.init can leak the temp dir if setup throws before `defer`; doc comment overstates (scan-time size and birth date not asserted); register's PathGuardTests row (plan 1) shows 39 while +6 Swift-only exist (register Swift-column sum 488 vs 494 suite) — pre-existing.
Task 11: complete (commits ffd0d22..745997b, review clean)
Final review: dispatched (opus)
Final review (opus): With fixes — no Critical. Important 1: executor's inventory-completeness check (XcodeCleanExecutor.swift:70) pinned only for runtimes — mutant `approved.kind == .device || isInventoryReadable(...)` passes all tests and lets simctl delete run on an Unavailable device with an incomplete fresh inventory (only barrier for that case); `isFile(kind) || …` also survives. Important 2 (promotes L97): XcodeCli UUID guard unpinned against weakening — `canonical(uuid) != nil || count == 36` passes; a 36-byte "--…" option would reach simctl; `booted` not tested.
Final review: fix-before-merge doc/register batch: L58 «Differenze» row (XcodeFileInventory keeps first duplicate, C# throws); L86 surrogate row precision; PathGuardTests Swift cell 39→45 (plan-1 leftover, reconcile with suite); FileSystem.swift:35-37 creation doc qualifier (writeData temp+rename). «Candidati a miglioramento» rows: (a) padded/uppercase UUID forwarded raw; (b) Xcode running state read before the full fresh collect; (c) 15 s post-command verification bounds the full collect incl. du on DerivedData (simulator/runtime outcomes may be "uncertain"); (d) Int64 sums trap (XcodeSelection.swift:90, XcodeCleanExecutor.swift:335/343) where C# throws.
Final review: all controller rulings judged sound (L41, L42, L43, L57, L109, L125).
Final review: fix wave dispatched (sonnet): 2 executor tests (+2 → 496), CLI invalid-input cases (no count change), doc/register batch; header «+ 62 nuove … (496 test)».
Final fix wave: implemented b9f2fe4, 720e5e4 (496 ×2; mutants A device/file and B count==36/canonical all fail; Sources diff = 5 comment lines); scoped re-review dispatched (sonnet)
Final fix wave: re-review — all findings addressed (A, B, C, D), no new breakage; commits 745997b..720e5e4. Minor wording: «Somme Int64» row calls :343 a reduce (it is `existing.bytesFreed + freed`).
Final review: clean. Plan 3 complete on 2026-10-14: 74 C# Xcode tests ported + 62 Swift-only, suite 496 green.
Follow-ups for plans 4–5 (from the final review): compose like AppServices.cs:83-89 (same collector and PathGuard for the executor); open the PendingJournal before execute, hand it to the report model, discard only after the session log is written; the executor never throws — a cancelled run still returns a result to save; progress arrives off the main actor from two sources (CleanEngine reports itemsTotal 1 per folder); overflow-safe size sums in the VM; never decide with XcodeCandidate ==; with unknown Xcode state analyze returns an unclassified snapshot — always go through preview; selection error texts are English (register candidate); CleanerFeatures test for the navigation lock while Xcode deletes; journal vs history paths differ under symlinked ancestors (/private/var vs /var) — never reconcile by text; plan 5: watch "uncertain" simulator/runtime outcomes and per-item re-collect cost; two integration tests assume TMPDIR under /var; audit @concurrent if NonisolatedNonsendingByDefault or MemberImportVisibility is enabled.
