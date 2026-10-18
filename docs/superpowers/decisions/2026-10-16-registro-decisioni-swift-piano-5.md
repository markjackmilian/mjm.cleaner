# SDD ledger — plan: docs/superpowers/plans/2026-10-16-swift-port-5-handoff.md

Branch: codex/swift-port-5. Worktree: /Users/mjm/.codex/worktrees/swift-port-5/mjm.cleaner. Base: 037b5bb. Plan approval: user “ok” on 2026-10-16. Preflight HEAD: 998c0f2.

## Preflight scan

| Tasks | Producer → consumer or self-check | Finding |
| --- | --- | --- |
| 1 | Debug.xcconfig and path test → Task 4 isolated Swift Debug data | Consistent; Task 4 can use separate bundle ID. |
| 2 | Release packaging script → Tasks 5, 6, 7 package gate, moved script, clean checkout | Consistent; relative script path is required after move. |
| 3 | Visual and VoiceOver report → Task 5 gate | Consistent; active UI needs a dedicated user window. |
| 4 | C#/Swift parity report → Task 5 gate | Consistent; C# remains available through Task 5. |
| 5 | GO/NO-GO report → Task 6 removal | Consistent; NO-GO prevents Task 6. |
| 6 | Root Swift layout and workflow → Task 7 clean checkout | Consistent; Task 7 checks active old references. |
| 7 | Clean checkout evidence → final branch review | Consistent. |
| 1 ↔ 2 | Debug ID vs Release package ID | Distinct configurations; no shared file edits. |
| 1 ↔ 3 | Debug identity vs demo screenshots | Debug bundle can run without sharing C# data. |
| 2 ↔ 3 | Candidate ZIP vs later visual defects | Task 5 requires rebuild if Task 3 changes code. |
| 2 ↔ 4 | Candidate ZIP vs parity defects | Task 5 requires rebuild if Task 4 changes code. |
| 3 ↔ 4 | UI focus and same machine | Sequential active UI; one agreed window can cover both. |
| 3 ↔ 5 | Visual evidence consumed by gate | Required, no substitute from code inspection. |
| 4 ↔ 5 | Parity evidence consumed by gate | Required, no destructive interaction. |
| 5 ↔ 7 | Gate before removal vs final test | Different checks; both required. |

No preflight conflict found. Package provenance is based on the committed `swift/` tree SHA, so documentation-only commits do not invalidate the binary. User was asked asynchronously for an active UI window; Tasks 1–2 proceed independently.

Task 1: started; base 998c0f2; implementer /root/implement_task1.
Task 1: complete (commit f3cf554; Sol spec compliant and quality approved; post-review suite 536 Core + 173 Features; Debug paths recorded).
Task 2: started; base f3cf554.
Task 2: review 8c00e27 found two Important transfer/collision findings and two Minor report/test findings; fix round 1/5 started, base 8c00e27.
Task 2: fix round 1/5 (3 addressed, 1 open: ZIP claim accepts pre-existing symlink/FIFO; commit b9f7bb4). Fix round 2/5 started; base b9f7bb4.
Task 2: fix round 2/5 (original symlink/FIFO issue addressed; 1 new Important: ln follows directory destination; commit 125c10f). Fix round 3/5 started; base 125c10f.
Task 2: fix round 3/5 (1 addressed, 0 open; commit 57ce132); complete, Sol task quality approved. Current Swift tree 616061fd9468e841bf6c03e49994d536d0a88d32; candidate ZIP SHA-256 7d4b09243563d012ad5a4d1f137262d4704aafbfbed09c9c036468b476f72eea. Fresh suite 536 Core + 173 Features passed; package script tests passed; lipo x86_64 arm64 and codesign verify passed.
Task 3: not started. User explicitly asked to stop before active UI collaudo; resume only when a dedicated Mac window is available. Tasks 4-7 not started.
Task 3: started by user “procedi”; base 57ce132. Active UI window assumed available from this instruction.
Ruling: User explicitly removed VoiceOver from scope on 2026-10-16 (“ferma voice over, non mi interessa”). Task 3 and Gate Task 5 will assess visual and functional UI only; no VoiceOver result can block GO. Cost if wrong: accessibility regressions may remain undetected by this phase. Stop any VO session and do not repeat it.
Task 3: partial report commit 5027502; V-01 demo Xcode preview and 900x600 remain open. User removed VoiceOver; spec/plan amendment commit da662db. Sol diagnosis: DemoData.xcodeSnapshot lacks guarded fileInventory while selectable cache rows require it; production scanner supplies inventory. Luna fix dispatched; base da662db.
Handoff: Codex session hit its usage limit on 2026-10-16 while the V-01 fix was uncommitted; execution continues in Claude Code (controller Opus; implementers Sonnet/Haiku; reviewers Opus), same worktree and branch.
Task 3: V-01 fix verified by controller (RED on HEAD DemoData reproduces V-01; GREEN exit 0; suite 536 Core + 173 Features; Debug build OK). Opus review: DA CORREGGERE — 1 Important (stale comment on previewedXcodeKeys), Minors on test script; 12/15 mutations killed, 3 survivors equivalent for the demo.
Ruling: user chose (2026-10-16) a Debug-only `-MJMWindowSize` flag + `screenshots.sh --size` to verify 900x600 without synthetic input, and `xcode-preview` demo page to include ShopApp so the screenshot shows the V-01 path. Task 4 parity: user drives both apps (no synthetic input), controller launches bundles and captures windows.
Task 3: fix round 1 started (V-01 polish + window size flag); brief task-3-fix-brief.md; implementer Sonnet; base da662db.
Task 3: fix round 1 done by Sonnet (commits 7e80fdf V-01 polish, fb87d80 -MJMWindowSize + screenshots.sh --size; suite 536 + 173; Debug build OK). Opus review of da662db..fb87d80 started.
Task 3: Opus review of da662db..fb87d80: DA CORREGGERE — Important I1 (comments promise a 900x600 capture; real minimum window is 900x652, view min under the 52 pt toolbar, as ruled in plan 4b); Minor M1 usage line, M2 test misses fallback to runtime-only, M3 unbounded digits / silent give-up. V-01 commit correct (flow traced with real XcodeModel, RED/GREEN confirmed).
Ruling: keep the window-size semantics (frame incl. toolbar); `--size 900x600` captures the minimum window 900x652, which is the spec's 900x600 view minimum. Fix comments + M1–M3 in fix round 2 (haiku, brief task-3-fix2-brief.txt). Cost if wrong: one comment and a flag semantics change.
Task 3: fix round 2 done (haiku, commit 56377ec; PASS, mutation runtime-only killed, suite 536 + 173, Debug build clean). Controller verified diff = brief.
Task 3: (2026-10-18) screenshots --size 900x600 on 56377ec: 26/26 at 1800x1304 px (900x652 pt; startup-failure 900x632). Opus visual review: V-01 PASS; D-1 (confirm 7th group below fold, no indicator), D-2 (Xcode acknowledgement hidden in 220 pt inner scroll — same as C#), D-3 docker below fold, D-4 history badges clipped; shots-default duplicated 900x652 because NSWindow Frame main persists despite -ApplePersistenceIgnoreState.
Ruling (user, 2026-10-18): fix D-2 in Swift (deliberate departure from C#); D-1 recorded and deferred (macOS overlay scrollers). D-3/D-4 deferred as Minor by controller (same nature).
Task 3: fix round 3 by haiku: 66d51e5 (D-2), c4b5f77 (script always passes size, default 1120x700). Opus review APPROVATO, 2 Minor comments -> fix round 4 (haiku, brief task-3-fix4-brief.txt). Final captures xcode-preview 2240x1400 and 1800x1304: V-01 and D-2 fixed. Visual record committed 0940ede (with parity ledger rows D-2 and sorted listing).
Task 4: parity collaudo 2026-10-18 17:25-18:15, user-driven, commit 56377ec; C##1 -> Swift#1 -> C##2 -> Swift#2. All 7 categories, Docker, Xcode identical; diffs = natural cache churn, C##1 selection lacked logs/nuget, sorted listing order (accepted). C# settings backed up and restored (sha ok). Record committed 4957285. PASS.
Task 5: gate GO committed (ZIP sha256 edf75280...; swift tree 30dea2b9 at 47d5a79). Task 6 next.
Task 6: started; base 70b703b; implementer Sonnet; brief task-6-brief.txt (workflow YAML and .gitignore given verbatim by controller).
Task 6: DONE by Sonnet, commit c7e3146 (418 files, C# removed, swift/* at root with history; workflow/README/.gitignore). Local GREEN per report: 536+173, Debug OK, package ZIP sha 82010b8a..., YAML ok. Leftover untracked src/ (118 MB bin/obj) and empty swift/: rm denied to implementer by permission classifier; controller did NOT run it, asking user. Xcode now 27.1 / Swift 6.4. Task 7: clean-archive verification (controller) and final Opus branch review started.
Task 7: clean archive of c7e3146 (git archive, no caches): suite 536+173 (0 warnings), script tests PASS, Debug OK, package exit 0, extracted ZIP x86_64 arm64, codesign ok, adhoc, no demo strings, ZIP sha256 5f94bea1..., YAML ok; obsolete refs outside docs/superpowers only legitimate (fixture provenance comment, Dockerfile test data, *.slnx marker). App source trees identical to 47d5a79 (MjmCleaner 6fd4490f, MjmCleanerKit 6747826c, Config c10d7ba4, xcodeproj 9d750874).
Task 7: final Opus review DA CORREGGERE: I-1 README FDA claim false (ad hoc signature changes every build: debug map embeds temp paths); minors M-1 gate Xcode 27.1, M-2 gate visual tree, M-3 Gatekeeper sentence, M-4 .idea/.vscode, M-6 fixture comment, M-7 workflow hardening, M-8 requirements line. M-5 (strip local paths from Release binary) deferred to a separate follow-up. Fix round 1 dispatched to haiku (task-7-fix1-brief.txt).
Task 7: fix round 1 by haiku: b9541a9 (README I-1/M-3/M-8, .gitignore M-4, fixture comment M-6, workflow M-7), 1157df5 (gate M-1/M-2). Clean archive of 1157df5: suite 536+173 (0 warnings), scripts PASS, Debug and Release 0 compiler warnings, ZIP x86_64 arm64, codesign ok, adhoc, DTXcodeBuild 27A9275, sha256 9e48c4e3..., YAML ok. Final record 2026-10-16-swift-port-5-final.md. M-5 (strip local paths from Release binary) deferred.
Plan 5 complete. Ledger copied to docs/superpowers/decisions/2026-10-16-registro-decisioni-swift-piano-5.md. Next: superpowers:finishing-a-development-branch (user choice: merge / PR / keep); leftover src/ and swift/ in worktree await the user.
