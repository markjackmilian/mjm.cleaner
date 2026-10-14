# SDD ledger — plan: docs/superpowers/plans/2026-10-13-swift-port-2-docker.md

Spec: docs/superpowers/specs/2026-10-13-swift-native-port-design.md (reachable).
Branch: feat/swift-port-docker-xcode (from main 05fb0d7; plan docs commit 05020d2).
Reports are `.txt` (haiku refuses to write `.md` reports — plan 1 experience).

## Pre-flight scan (2026-10-14)

Evidence base: on 2026-10-13/14 the controller extracted every code block of this plan
(file blocks + edits) into a scratch copy of the package, in task order, then applied plan 3 on top:
`swift build --build-tests -Xswiftc -warnings-as-errors` clean, 356 tests green after plan 2,
463 after plan 3. Automated check: no `@Test` in Tests/CleanerCoreTests/Docker without
`#expect`/`#require`/`Issue.record` (114 tests checked).

### Shared files / interfaces between tasks

| Tasks | Produces → consumes | Found |
|---|---|---|
| 1 → 2..10 | models, `DockerText`, `DockerSize`, `ImageName` | signatures used by later tasks compile in sequence — OK |
| 2 → 3,4,5,9 | `DockerJson`, `DockerOutputError`, `DockerFixtures` (test) | compiles — OK |
| 2 (Package.swift) ↔ plan 3 Task 4 | `exclude: ["Docker/Fixtures"]` block; plan 3 replaces it verbatim | text matched exactly in sequential apply — OK |
| 3 → 4,6,9,10 | `DockerClassifier`, `VolumeRuleContext.composeProjectLabel`, `buildCacheId` | compiles — OK |
| 5 → 6,9,10 | `DockerCommandRunning`, `DockerCliErrors`, `FakeDockerCli`, `Shared` | compiles — OK |
| 6,7,8,9 → 10 | collector, probe, scanner, executor | compiles — OK |
| 1..10 ↔ 11 | parity register: each task adds rows to distinct tables/rows; 11 closes and fixes parked rows (a),(b) | doc-only, no overlapping row edits — OK |

### Per-task self-consistency

| Task | Tests vs code / files created vs touched | Found |
|---|---|---|
| 1 | 3 test files vs 4 sources | green in sequence — OK |
| 2 | Package.swift full replace + fixtures copy + DockerJson | green — OK |
| 3 | rules + classifier vs DockerClassifierTests (27) | green — OK |
| 4 | groups vs 7 tests | green — OK |
| 5 | CLI + FakeDockerCli vs 11 tests | green — OK |
| 6 | collector vs 7 tests | green — OK |
| 7 | probe vs 6 tests | green — OK |
| 8 | scanner vs 17 tests | green — OK |
| 9 | executor vs 16 tests | green — OK |
| 10 | service vs 2 tests | green — OK |
| 11 | verification + register only | n/a |

Scan clean: no rulings needed before Task 1.

## Tasks
Task 1: dispatched (BASE 05020d2, implementer haiku, agent add29ff569d72970a)
Task 1: implemented 9164fba (253 tests); review dispatched (sonnet, agent af9e43ca959edf73f)
Task 1: ⚠️ resolved — commit trailer verified (Co-Authored-By: Claude Opus 5.5); RED tail-only is a process note, compile errors predicted by missing types.
Task 1: minor (deferred): DockerText UTF-32 BE branch, trimmedLeading/trimmedTrailing, isBlank have no direct test (later tasks may exercise them).
Task 1: minor (deferred): DockerSize Int64 overflow → nil (parity "Differenze" row) not pinned by a test ("9224PB", "99999999999PB").
Task 1: minor (deferred): parity register lacks a note on the 35-code-point `\b` residual in DockerSize.swift (plan text documents it).
Task 1: minor (deferred): DockerText.lineStarts hand-advanced index; `unicodeScalars.indices` would be simpler.
Task 1: complete (commits 05020d2..9164fba, review clean)
Task 2: dispatched (BASE 9164fba, implementer haiku, agent a9a33af40b7073d27)
Task 2: implemented b248b26 (263 tests); review dispatched (sonnet, agent a4342e7b2628b2368)
Task 2: ⚠️ resolved — commit trailer verified.
Task 2: minor (deferred): DockerJsonValue accepts integral floats (`1.0`, `1e2`) as Int64 where .NET TryGetInt64 rejects them; doc comment "come TryGetInt64" and register row "numero non intero → 0" slightly imprecise (harmless: Docker emits plain integers).
Task 2: minor (deferred): no test pins ExitCode 0/1 decoded as numbers (Bool probed before Int64).
Task 2: minor (deferred): per-scalar failing try? probes allocate DecodingError (negligible; plan-mandated).
Task 2: minor (deferred): duplicate label keys → first value claimed in register, no test.
Task 2: complete (commits 9164fba..b248b26, review clean)
Task 3: dispatched (BASE b248b26, implementer haiku, agent a6021bbb87fb95b03)
Task 3: implemented d301ab4 (290 tests, trailer verified); review dispatched (sonnet, agent accd178eb23a7b56a)
Task 3: minor (deferred): VolumeRules.isAnonymous `\n?$` workaround untested (add `<64hex>\n` → PROPOSE, 63/65 hex → named-unused); test name says "regexes" but covers only AspireVolumeName.
Task 3: minor (deferred): customRulesWithoutAFallbackAreAProgrammingError covers only empty imageRules (not volumeRules, not the message).
Task 3: minor (deferred): testcontainers/dcptun predicates duplicated in isCreatedByTool and tool-recreated rule (faithful to C#, brief-mandated) — drift risk if a tool is added.
Task 3: minor (deferred): DockerClassifierTests local `let volume` shadows helper `volume(_:compose:)` (readability).
Task 3: minor (deferred): private DockerClassifier.firstMatch name collides visually with Regex.firstMatch(of:).
Task 3: complete (commits b248b26..d301ab4, review clean)
Task 4: dispatched (BASE d301ab4, implementer haiku, agent a2c39c363658731e6)
Task 4: implemented e76d3a4 (297 tests, trailer verified); review dispatched (sonnet, agent ae8b8802abaa86091)
Task 4: minor (deferred, safety-relevant): the final `.filter { $0.verdict != .keep }` in DockerConfirmationGroups.selection (defence in depth) is untested — build() puts KEEP only in readOnly groups; a Swift-only test with a hand-built block/selectable group holding a KEEP item would pin it (C# suite has the same gap).
Task 4: minor (deferred): DockerConfirmationGroups.swift (and ImageRules/VolumeRules) use String(localized:) without `import Foundation` (transitive import).
Task 4: minor (deferred): requiresIndividualConfirmation's `kind == .volume` half not exercised (image with ruleId named-unused); matches C# tests.
Task 4: complete (commits d301ab4..e76d3a4, review clean)
Task 5: dispatched (BASE e76d3a4, implementer haiku, agent ac7ad523cb2a75ecc)
Task 5: implemented bcf5397 (308 tests, trailer verified); review dispatched (sonnet, agent a53389900f210fbb8)
Task 5: minor (deferred): 60 s default timeout of DockerCli not asserted (FakeRunner.Call lacks timeout); faithful to C#/brief.
Task 5: minor (deferred): FakeDockerCli discards timeout, so Task 9 cannot assert the 10-minute delete timeout.
Task 5: minor (deferred): missingBinaryBecomesAReadableException has dead FakeRunner setup and does not assert the runner was never called.
Task 5: minor (deferred): no test that CancellationError/non-launch errors pass through DockerCli.run untranslated (narrow catch at DockerCli.swift:157).
Task 5: minor (deferred): FakeDockerCli.withRealCase reads each fixture twice; untested until Task 6+.
Task 5: note: Localizable.xcstrings empty — pre-existing plan-1 state, keys fall back to Italian source text (not a Task 5 defect).
Task 5: complete (commits e76d3a4..bcf5397, review clean)
Task 6: dispatched (BASE bcf5397, implementer haiku, agent ae897ab8a7a255ed3)
Task 6: implemented 402d413 (315 tests, trailer verified); review dispatched (sonnet, agent ad5b9d1367c2bfbe0)
Task 6: minor (deferred): onlyReadOnlyCommandsAreUsed passes vacuously on empty commandLines and uses loose string prefixes ("ps" accepts "psx"); verbatim from C#.
Task 6: minor (deferred): DockerInventoryCollector.swift:92/97/102 lines ~120-125 columns.
Task 6: complete (commits bcf5397..402d413, review clean)
Task 7: dispatched (BASE 402d413, implementer haiku, agent a57e4d980697b3497)
Task 7: implemented 19f17ed (321 tests, trailer verified); review dispatched (sonnet, agent a5692f8375650f62c)
Task 7: minor (deferred): DiskUsageProbe.measure() untested branches — timedOut with exit 0, runner throwing non-cancellation error swallowed, CancellationError rethrown (most valuable), fileLength throwing FileSystemError; C# test set has the same gaps.
Task 7: minor (deferred): doc "Lancia solo CancellationError" relies on FileSystem's FileSystemError-only contract (could say so); line-58 comment ~120 cols.
Task 7: complete (commits 402d413..19f17ed, review clean)
Task 8: dispatched (BASE 19f17ed, implementer haiku, agent a881a4e08b2ba054f)
Task 8: implemented 9f44e78 (338 tests, trailer verified); review dispatched (sonnet, agent a9f673dc5363fe44c)
Task 8: review → Needs fixes: 1 Important (plan-mandated): classify() builds the composeFileName/dockerfileName regexes for every file walked (~193 µs/file vs ~4.5 µs hoisted, measured).
Task 8: Ruling: hoist the two file-name regexes to once per `scan` call and pass them to `classify` — the plan constraint allows "una volta per chiamata", behaviour unchanged, the C# scanner is meant to stay fast; the brief's per-file construction was an unforced choice — cost if wrong: a private signature differs from the plan text (no API change, no test change).
Task 8: minor (deferred): doc comment ProjectReferenceScanner.swift:78-79 claims .NET IgnoreCase equates "i" and U+0130 — contradicts test comment :647 and the plan's measured facts (brief-mandated text).
Task 8: minor (deferred): traversal rules untested — depth 12, links not followed (InMemoryFileSystem has no symlinks), case-insensitive excluded folders (all test args lowercase), 1 MiB boundary, cancellation, unreadable dirs; mirrors C# suite.
Task 8: minor (deferred): directoryExists called twice per entry (:190-191); statement loop allocates filtered scalar arrays up to 3× per statement (:616-623).
Task 8: fix round 1 implemented ae92db7 (17/17 focused, 338 full); scoped re-review dispatched (haiku, agent a356e53c1534a9814)
Task 8: fix round 1/5 (1 addressed, 0 open; commits 9f44e78..ae92db7)
Task 8: minor (deferred): struct doc ProjectReferenceScanner.swift:11 still says regexes are built "una volta per file" — now false for the two file-name regexes.
Task 8: complete (commits 19f17ed..ae92db7, review clean after 1 fix round)
Task 9: dispatched (BASE ae92db7, implementer haiku, agent a736025dad3ba2699)
Task 9: implemented 5d060ee (354 tests ×2, cancel tests 10× green; DONE_WITH_CONCERNS: deletion-path shielding untested, `
`-suffixed sha256 refusal untested); review dispatched (opus, agent a7db6d00ba353662e)
Task 9: review → Needs fixes: 1 Important (plan-mandated): no test covers the deletion-path cancellation shield (DockerCleanExecutor.swift:180-183); both cancel tests cancel from the progress callback after rmi returned; removing `shielded` keeps the suite green (implementer mutation + reviewer reasoning). Brief and parity.md:29 claim the isolation is verified.
Task 9: Ruling: add ONE Swift-only test in DockerCleanExecutorTests.swift that cancels the outer task while the `rmi` handler runs, via a file-private wrapper double that delegates to FakeDockerCli and calls `Task.checkCancellation()` after the inner response (as ProcessRunner does after the child exits); FakeDockerCli.swift unchanged; outer Task handle passed through `Shared`, gated (AsyncStream) so it is stored before execute starts; mutation-check (unshield → test fails) reported, not committed; parity row for DockerCleanExecutorTests updated (+1 Swift-only) — why: the global constraint on CancellationToken.None semantics is otherwise unverified while the plan claims it is — cost if wrong: one extra test; plan text totals (Task 10: 356, Task 11, plan 3: 463) become +1 (357 / 464).
Task 9: minor (deferred): strict `$` in executor guards not pinned by a test (add "sha256:<64hex>\n" and "old-data\n" refusal cases); a mechanical "fix" to `\n?$` would go unnoticed.
Task 9: minor (deferred): no test refuses a build-cache entry with KEEP verdict (C# same gap).
Task 9: minor (deferred): bytes-freed test uses `.first{}` instead of filter+count==1+#require (plan-mandated; total check catches duplicates indirectly).
Task 9: minor (deferred): parity.md:121 lists DockerCleanExecutor among table-translated regexes, contradicting the new row :124 (deliberate strict `$`).
Task 9: fix round 1 implemented f1a34c1 (17 focused ×2, 355 full ×2, new test 10×, mutation → FAIL CancellationError); scoped re-review dispatched (sonnet, agent a03389239bf824d7d)
Task 9: fix round 1/5 (1 addressed, 0 open; commits 5d060ee..f1a34c1)
Task 9: complete (commits ae92db7..f1a34c1, review clean after 1 fix round)
Task 10: dispatched (BASE f1a34c1, implementer haiku, agent a611183657ca040d7; told expected total 357 per Task 9 ruling)
Task 10: implemented 6d16b3f (357 tests, trailer verified); review dispatched (sonnet, agent a99b1ceac6050becf)
Task 10: minor (deferred): DockerCleanupServiceTests.swift:136 uses `first{}` where C# used Single (plan-mandated; table says filter+count==1+#require).
Task 10: minor (deferred): serverVersion not asserted; NoProcess fake name misleading (returns a du line); analyze error/cancel propagation and execute/measureDisk forwarders untested (C# same).
Task 10: complete (commits f1a34c1..6d16b3f, review clean)
Task 11: dispatched (BASE 6d16b3f, implementer haiku, agent a74bb4ecc66e70ac9; told 357 total, +16 Swift-only, date 2026-10-14, stage parity doc only)
Task 11: implemented c1484bb (357 tests, 7 greps clean, only expected "-f"); review dispatched (haiku, agent a2dfff16b502b33d4)
Task 11: review → Needs fixes: 1 Important: parity.md:114 still says «il piano 3» for the App port (DoneStepViewModel) — should be piano 4 under the five-plan numbering.
Task 11: minor (deferred): settings.json Swift behaviours in the Differenze row (null fields, 12.0, [null], 64-bit) not pinned by Swift tests.
Task 11: fix round 1 dispatched (resume implementer a74bb4ecc66e70ac9; also grep all plan-number references)
Task 11: fix round 1 implemented da0d931 (line 114 piano 3→4; grep of all plan refs clean); scoped re-review dispatched (haiku, agent a020b1d1d6c4b16fd)
Task 11: fix round 1/5 (1 addressed, 0 open; commits c1484bb..da0d931)
Task 11: complete (commits 6d16b3f..da0d931, review clean after 1 fix round)
Note: subagents' harness suggested a "Haiku 5.5" trailer; all commits keep "Claude Opus 5.5" per the plan's Global Constraints (user's project rule). Not a finding.
Final review: dispatched on 05020d2..da0d931 (opus)
Final review (opus): With fixes — no Critical; Important 1: unpinned safety guards (executor strict `$` vs "sha256:…\n"/"old-data\n"; KEEP build-cache never pruned; selection() KEEP filter over hand-built groups). Minors to fix before merge: ProjectReferenceScanner.swift:9-11 doc (U+0130 claim false; "una volta per file" stale); parity.md:123 lists DockerCleanExecutor among table-translated regexes; parity.md:120 "JSON patologico" imprecise (.NET JsonDocument keeps LAST duplicate field; TryGetInt64 rejects 1.0, Swift reads 1.0/1e2). Minor 5 (scanner read follows symlinks/FIFO past the 1 MiB lstat cap; same in C#) → register «Candidati a miglioramento» row.
Final review: Ruling: Minor 4 (timeouts 600 s / 60 s / 20 s not pinned; FakeDockerCli discards timeout) stays a follow-up, not fixed now — it needs a change to the shared fake and is not a regression risk today — cost if wrong: a timeout regression would go unnoticed until a long rmi/prune is killed client-side.
Final review: Rulings L98 (Task 8) and L110 (Task 9) judged sound by the final reviewer.
Final review: fix wave dispatched (sonnet) — 3 Swift-only tests (+3 → 360 total, 19 Swift-only) + doc/register edits
Final fix wave: implemented 25923ce, 7f4705b (360 ×2; 3 mutation checks fail as expected; C2 fact corrected by fixer: C# DockerJson uses GetInt32/GetInt64 → FormatException on 1.0/1e2, not "absent"); scoped re-review dispatched (sonnet)
Final fix wave: re-review — all findings addressed (A1–A3, B, C1–C4), no new breakage; commits da0d931..7f4705b.
Final review: clean. Plan 2 complete on 2026-10-14: 99 C# Docker tests ported + 19 Swift-only, suite 360 green.
Follow-ups carried to later plans: timeouts not pinned (FakeDockerCli discards timeout); register candidate: scanner symlink/FIFO read; plan 4 UI must exclude named-unused volumes from group selection (selection() does not enforce requiresIndividualConfirmation, as in C#) — deserves a CleanerFeatures test; plan 5: LocalFileSystem traversal tests for the scanner (links, depth, case-insensitive exclusions).
