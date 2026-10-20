# mjm.cleaner

A macOS application for deleting regenerable temporary files, with a mandatory
preview, cleanup history, and a cumulative counter of the disk space recovered.

The application never makes deletion decisions on its own: every item is listed
with its exact path and size before it can be removed, and deletion only starts
after explicit confirmation. A non-configurable `PathGuard` always rejects
protected paths, even if a misconfigured project directory points to one of
them.

## Requirements

- macOS 15 or later
- For development: Xcode 27 (Swift 6 language mode; the package needs Swift
  tools 6.2 or later)

## Development

```bash
(cd MjmCleanerKit && swift test)    # run the Core and Features test suites
open MjmCleaner.xcodeproj            # develop and run from Xcode
xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug build
Scripts/package-release.sh --tag v0.1.0 --build-number 1 --output-dir artifacts
open artifacts/mjm.cleaner.app
```

> [!IMPORTANT]
> Run **`Scripts/package-release.sh`** to create the distributable application.
> The script builds a universal Release (arm64 + x86_64), creates
> `artifacts/mjm.cleaner.app` and a single ZIP,
> `artifacts/mjm.cleaner-vX.Y.Z-macos-universal.zip`, applies the ad hoc
> signature, and verifies architectures, signature and the absence of local build
> paths in the bundle, including on the copy extracted from the ZIP. It refuses
> to overwrite an existing bundle or ZIP.

Debug builds use the bundle id `com.mjm.cleaner.debug`, so their data is kept
apart from the release app's. A Debug build can also start with fake demo data,
without touching the disk: `-MJMDemo <page>`.
`Scripts/screenshots.sh [--size WxH] <out-dir> [page…]` captures the demo pages
(Debug only; do not use the Mac while it runs).

The bundle is **ad hoc signed** (identity `-`, see `Config/Base.xcconfig`):
macOS would refuse to launch it without a signature. Because it is not
notarized, `spctl` rejects it. A locally built copy launches normally; a
downloaded copy (for example, unpacked from the release ZIP) is blocked the
first time it is opened: then choose **System Settings → Privacy & Security →
Open Anyway**.

## How it works

The application uses a four-step wizard, always in the same order:

| Step | What it does |
|---|---|
| **1 · Choose** | Select the categories to clean. Each category declares its risk level; high-risk categories are never preselected. Project bin and obj directories and Large files stay unavailable, with a shortcut to Settings, until a directory is chosen there. |
| **2 · Analyze** | Performs a read-only scan, processing categories in parallel. Nothing is deleted. |
| **3 · Confirm** | Shows the mandatory preview: exact paths, sizes, a warning about running applications, and the exclusions made by `PathGuard` and by the excluded folders. Each group has a «Select all» checkbox; Downloads and large-file items start deselected. This is the final point at which the operation can be abandoned. |
| **4 · Done** | Summarizes the disk space recovered and any items that could not be deleted. |

In the sidebar, **Docker** opens the Docker cleanup page, **Xcode** opens the
Xcode cache and simulator page (see below), and **History** shows previous
cleanup sessions and the cumulative space recovered. **Settings**, at the bottom
of the sidebar and in the app menu (<kbd>⌘,</kbd>), configures the project
directories searched for `bin` and `obj`, the directories searched for large
files, the large-file size threshold, the folders and packages excluded from
every cleanup category, and the minimum ages for Downloads, logs, and NuGet
packages.

### Categories

- **User and system caches** — `~/Library/Caches`, `/Library/Caches`, `$TMPDIR`
- **Development caches** — npm, Gradle,
  `~/.cache`
  - **Unused NuGet packages** (sub-category, not preselected)
- **Project bin and obj directories** — only when a project file (`.csproj`,
  `.sln`, …) exists next to the directory
- **Logs and crash reports** — `~/Library/Logs`, `/Library/Logs`
- **Trash** — high risk, never preselected
- **Downloads** — files in `~/Downloads` older than the minimum age; high risk,
  never preselected, and every item starts deselected in the preview
- **Large files** — files and packages above the threshold in the directories
  chosen in Settings; high risk, never preselected, and every item starts
  deselected in the preview

In Downloads, large files, and logs, macOS packages, such as apps, Photos
libraries, and Parallels, VMware Fusion, or UTM virtual machines, are listed as
a single item and never entered: deleting a file inside one would break it.
Folders excluded in Settings are never scanned or proposed. A single macOS
package, such as a virtual machine, can be excluded on its own instead of the
folder that contains it. A folder that would be deleted as a whole, such as a
cache subfolder, a `bin` or `obj` directory, or a macOS package, is not proposed
if it contains an excluded folder. An exclusion also matches the same folder
reached through a symbolic link, written under `/var` instead of
`/private/var`, or spelled differently but naming the same folder on disk
(another Unicode normalization, an APFS case equivalence). An excluded folder
that is a symbolic link also excludes its target. An excluded folder that is
not a plain absolute path (relative, or containing `//`, `.` or `..`), or that
cannot be checked on disk, stops every cleanup rule, and step 3 shows why. The
Xcode and Docker pages do not use excluded folders.

### Xcode

The **Xcode** page analyzes DerivedData by project folder, iOS/watchOS/tvOS/visionOS
Device Support, simulated devices, and installed simulator runtimes. Every item
starts deselected. Only the two cache groups support group selection; devices
and runtimes require individual selection. Archives are excluded because they
contain shipped app binaries and debug symbols.

The page shows a final preview before deletion. Removing a simulated device also
removes its apps and test data. Removing a runtime can make dependent devices
unavailable; those devices are listed and require acknowledgement, and the app
never removes them automatically. Running devices and Xcode block affected
operations. File caches use the app's guarded cleanup engine; simulator and
runtime removal uses UUID-targeted `xcrun simctl` commands only. If the installed
Xcode does not support runtime removal through the CLI, the page reports that
limit and points to Xcode Settings.

Sizes are estimates. Unknown sizes remain unavailable, APFS clones can make
allocated-space estimates differ from space ultimately reclaimed, and the
before/after free-space measurement is shown separately because other processes
can change it during cleanup. Only verified, measurable removals are credited
to the cumulative history total.

### Docker

The **Docker** page cleans images, volumes, and build cache through the `docker`
CLI only, on the engine of the active Docker context: Docker Desktop, OrbStack,
or any other Docker-compatible engine (Colima, Rancher Desktop, …). The page
names the engine that answered `docker info`. The page never deletes files
directly, and no engine is ever started: if the daemon is not
running, the page names the engine of the active context (read with
`docker context inspect`) and offers **Retry**. The `docker` binary is looked up
in `~/.docker/bin`, `~/.orbstack/bin`, `/usr/local/bin`, `/opt/homebrew/bin`, and
inside `Docker.app` and `OrbStack.app`; a dangling link left by an uninstalled
engine is skipped.

The context is read once, when the analysis starts, and every command of the
analysis and of the cleanup runs with `docker --context <name>` on that context.
If the active context changes in the meantime (OrbStack, for example, makes its
own context active when it starts), the cleanup still deletes only on the
analyzed engine. Before deleting anything, the page checks that the daemon behind
that context is still the analyzed one (same ID, operating system, and version).
If it is not, nothing is deleted and the page asks you to analyze again. The
active context is never changed.

The analysis is read-only and is the dry run. Every resource gets an outcome
(KEEP / DELETE / PROPOSE / ASK), a reason, and the cost of recreating it:

- **Kept:** images used by any container, even stopped ones (matched by image ID,
  not tag); images cited with repository and tag in the project directories
  (compose files, Dockerfiles, Aspire AppHosts, Testcontainers, Kubernetes/Helm);
  mounted volumes, volumes of compose projects that still exist, and Aspire
  volumes whose AppHost hash is still in use.
- **Safe, confirmed as a block:** dangling images, images that Testcontainers and
  .NET Aspire recreate on their own (`testcontainers/ryuk`, `dcptun_*` and their
  base image), and the build cache.
- **To confirm one by one or by group:** locally built images (they cannot be
  pulled again), unused or superseded images, anonymous volumes, and Aspire
  volumes left behind by an old AppHost hash. Other named volumes can only be
  selected individually.

Images are removed by full ID (`docker rmi sha256:…`), never by tag and never
with `-f`; `docker system prune` is never used. The report shows what was
deleted, what failed and why, and the space recovered according to
`docker system df`. With Docker Desktop it also shows the real allocated size of
`Docker.raw` (a sparse file: its apparent size is only the disk limit); if
`Docker.raw` does not shrink, the report suggests **Docker Desktop →
Troubleshoot → Clean / Purge data**, which deletes all Docker data and is never
run automatically. OrbStack shrinks its disk image on its own, and macOS
protects the folder that holds it, so the app does not measure it; the disk
image of any other engine is not measured either.

## History and logs

All application data is stored under
`~/Library/Application Support/com.mjm.cleaner/` (Debug builds use
`com.mjm.cleaner.debug`):

| File | Contents |
|---|---|
| `history.db` | SQLite database with one row per cleanup session, including duration, bytes recovered, deleted items, and failed items. It powers the history view and cumulative counter. |
| `settings.json` | Settings editable from **Settings**. |
| `logs/session-NNNNNN.jsonl.gz` | Complete list of deleted paths, with one JSON record per item, compressed. Only the latest **20** sessions are retained; older files are removed automatically. |

Deleted paths are deliberately not stored in SQLite: cleaning caches may touch
hundreds of thousands of files, which would make the database grow faster than
the disk space being recovered.

This directory is under `~/Library/Application Support`, which is protected by
the deny list: **the application cannot delete its own history**.

The data of the previous C# application, in
`~/Library/Application Support/mjm.cleaner/`, is neither read nor migrated: the
Swift application starts from zero.

## Warnings

- **Deletion is permanent:** files do not go through the Trash and cannot be
  recovered. The step 3 preview lists the exact paths. `PathGuard` also blocks
  protected locations (`/System`, `/usr`, `/bin`, `/sbin`, `/Applications`,
  `/Volumes`, `~/Documents`, `~/.ssh`, `~/Library/Keychains`, …) and cannot be
  configured through the UI. It is the final line of defense, not a preference.
  A project directory set to `/` is rejected in full and produces no candidates.
- **Full Disk Access is only required for the Trash:** during the exploratory
  measurement, the only path requiring it was `~/.Trash`; all other categories
  work without it. Access-denied errors are always handled and reported for any
  path, not only known protected locations. When needed, grant access to the
  bundle under **System Settings → Privacy & Security → Full Disk Access** by
  adding `artifacts/mjm.cleaner.app` (or wherever you install it) with the
  **+** button (<kbd>⌘⇧G</kbd> lets you paste the path). Because the bundle
  uses an ad hoc signature, the grant is tied to that exact build: **grant it
  again after every new build**, even from unchanged source: a rebuild is not
  guaranteed to reproduce the same signature, because Apple's asset compiler
  can emit different bytes from the same asset catalog and the signature covers
  them.
- **No privilege elevation:** the application never uses `sudo` or asks for a
  password. Items owned by `root` fail with an access-denied error and appear in
  the final summary in step 4.
- **Docker engine data is never deleted:**
  `~/Library/Containers/com.docker.docker`, `~/.docker`, `~/.orbstack`, and
  `~/OrbStack` (where OrbStack mounts its volumes, images, and containers) stay on
  the deny list, and OrbStack's group container is covered by
  `~/Library/Group Containers`. Docker space is reclaimed only from the
  **Docker** page, through the `docker` CLI. The Caches category can still empty
  an engine's caches under `~/Library/Caches`, like any other application's.

## Updates

The release app checks the GitHub releases at launch and then once a day
(**Settings → Updates** turns this off; **Check for Updates…** in the app menu
checks right away). When a newer release exists, it downloads
`mjm.cleaner-vX.Y.Z-macos-universal.zip` into
`~/Library/Application Support/com.mjm.cleaner/updates/`, accepts it only if its
SHA-256 matches the digest GitHub publishes for the asset, extracts it and checks
the bundle id, the version, the signature and both architectures. A banner then
offers **Install and Relaunch**: the app quits, a small script swaps the bundle
in place (restoring the old one if the swap fails) and reopens it; the outcome
is written to `updates/install-result`, which the next launch reads and removes,
and `updates/install.log` keeps the detail. A failed install is reported at the
next launch; if the script cannot even start, the app stays open and says so.
If the app cannot be replaced in place (its folder is not writable, or macOS
runs it from a temporary location), the banner offers **Show in Finder**
instead.

Because the bundle is ad hoc signed, **Full Disk Access must be granted again
after every update** (see Warnings). Debug builds never check for updates.

## Documentation

- Swift port specification: `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`
- Phase 5 specification: `docs/superpowers/specs/2026-10-16-swift-port-5-handoff-design.md`
- Parity ledger: `docs/superpowers/porting/2026-10-13-parity.md`
- Phase 5 verification reports: `docs/superpowers/verification/2026-10-16-swift-port-5-visual.md`,
  `docs/superpowers/verification/2026-10-16-swift-port-5-parity.md` and
  `docs/superpowers/verification/2026-10-16-swift-port-5-gate.md`
- In-app updates design: `docs/superpowers/specs/2026-10-19-app-updates-design.md`

The entries below predate the Swift port and describe the original C#
application; they are kept as history.

- Specification: `docs/superpowers/specs/2026-09-15-mjm-cleaner-design.md`
- Implementation plan: `docs/superpowers/plans/2026-09-15-mjm-cleaner.md`
- Full Disk Access spike: `docs/superpowers/spikes/2026-09-15-full-disk-access.md`
- Docker cleanup design: `docs/superpowers/specs/2026-10-01-docker-cleanup-design.md`
- Docker cleanup plan: `docs/superpowers/plans/2026-10-01-docker-cleanup.md`
