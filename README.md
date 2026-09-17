# mjm.cleaner

A macOS application for deleting regenerable temporary files, with a mandatory
preview, cleanup history, and a cumulative counter of the disk space recovered.

The application never makes deletion decisions on its own: every item is listed
with its exact path and size before it can be removed, and deletion only starts
after explicit confirmation. A non-configurable `PathGuard` always rejects
protected paths, even if a misconfigured project directory points to one of
them.

## Requirements

- macOS 13 or later
- .NET 10 SDK — on this machine it is installed in `/usr/local/share/dotnet`
  and is **not in `PATH`**. Prefix each `dotnet` command with:

  ```bash
  export PATH="/usr/local/share/dotnet:$PATH"
  ```

  (`build/bundle.sh` already does this internally.)

## Development

```bash
export PATH="/usr/local/share/dotnet:$PATH"

dotnet build                             # build the solution and tests
dotnet test                              # run the complete test suite
dotnet run --project src/MjmCleaner.App  # run the development build
./build/bundle.sh                        # create the complete macOS bundle
open artifacts/mjm.cleaner.app           # launch the bundle
```

> [!IMPORTANT]
> Run **`./build/bundle.sh`** to create the distributable application.
> A plain `dotnet publish` only produces the Avalonia binaries, not a complete
> macOS bundle. The script publishes the application, creates
> `artifacts/mjm.cleaner.app`, adds `Info.plist` and the `.icns` icon, and then
> applies the ad hoc signature required to launch it on macOS.

The bundle is **ad hoc signed** (`codesign --sign -`): macOS would refuse to
launch it without a signature. Because it is not notarized, `spctl` rejects it.
A locally built copy still launches normally, but a copy transferred from
another Mac must be opened for the first time with **right-click → Open**.

## How it works

The application uses a four-step wizard, always in the same order:

| Step | What it does |
|---|---|
| **1 · Choose** | Select the categories to clean. Each category declares its risk level; high-risk categories are never preselected. |
| **2 · Analyze** | Performs a read-only scan, processing categories in parallel. Nothing is deleted. |
| **3 · Confirm** | Shows the mandatory preview: exact paths, sizes, a warning about running applications, and the exclusions made by `PathGuard`. This is the final point at which the operation can be abandoned. |
| **4 · Done** | Summarizes the disk space recovered and any items that could not be deleted. |

In the toolbar, **History** shows previous cleanup sessions and the cumulative
space recovered. **Settings** configures the project directories searched for
`bin` and `obj`, the directories searched for large files, the large-file size
threshold, and the minimum ages for Downloads, logs, and NuGet packages.

### Categories

- **User and system caches** — `~/Library/Caches`, `/Library/Caches`, `$TMPDIR`
- **Development caches** — npm, Xcode (DerivedData and Archives), Gradle,
  `~/.cache`
  - **Unused NuGet packages** (sub-category, not preselected)
- **Project bin and obj directories** — only when a project file (`.csproj`,
  `.sln`, …) exists next to the directory
- **Logs and crash reports** — `~/Library/Logs`, `/Library/Logs`
- **Trash, Downloads, and large files** — high risk, never preselected

## History and logs

All application data is stored under
`~/Library/Application Support/mjm.cleaner/`:

| File | Contents |
|---|---|
| `history.db` | SQLite database with one row per cleanup session, including duration, bytes recovered, deleted items, and failed items. It powers the history view and cumulative counter. |
| `settings.json` | Settings editable from the **Settings** page. |
| `logs/session-NNNNNN.jsonl.gz` | Complete list of deleted paths, with one JSON record per item, compressed. Only the latest **20** sessions are retained; older files are removed automatically. |

Deleted paths are deliberately not stored in SQLite: cleaning caches may touch
hundreds of thousands of files, which would make the database grow faster than
the disk space being recovered.

This directory is under `~/Library/Application Support`, which is protected by
the deny list: **the application cannot delete its own history**.

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
  adding `artifacts/mjm.cleaner.app` with the **+** button (<kbd>⌘⇧G</kbd> lets
  you paste the path). Because the bundle uses an ad hoc signature, the grant is
  tied to its fingerprint: **it must be granted again after a code change**,
  while rebuilding unchanged source preserves it.
- **No privilege elevation:** the application never uses `sudo` or asks for a
  password. Items owned by `root` fail with an access-denied error and appear in
  the final summary in step 4.
- **Docker is not touched:** `~/Library/Containers/com.docker.docker` and
  `~/.docker` are on the deny list. Reclaim image and volume space with
  `docker system prune`.

## Documentation

- Specification: `docs/superpowers/specs/2026-09-15-mjm-cleaner-design.md`
- Implementation plan: `docs/superpowers/plans/2026-09-15-mjm-cleaner.md`
- Full Disk Access spike: `docs/superpowers/spikes/2026-09-15-full-disk-access.md`
