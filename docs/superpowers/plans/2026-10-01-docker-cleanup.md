# Pulizia Docker sicura — piano di implementazione

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** pagina "Docker" che classifica immagini, volumi e cache di build per rischio e cancella solo ciò che l'utente conferma.

**Architecture:** tutto il dominio vive in `MjmCleaner.Core/Docker/`: raccolta (CLI, I/O) separata da classificazione (funzioni pure su uno snapshot immutabile). L'App aggiunge una pagina con il proprio ViewModel e riusa storico e log di sessione tramite `CleanReport`.

**Tech Stack:** .NET 10, C# latest, xUnit 2.9, System.IO.Abstractions (+ TestingHelpers), Avalonia 12, CommunityToolkit.Mvvm.

**Spec:** `docs/superpowers/specs/2026-10-01-docker-cleanup-design.md`

## Global Constraints

- `TreatWarningsAsErrors=true`, nullable abilitato: nessun warning.
- Testi dell'interfaccia e commenti in italiano; commenti che spiegano il *perché*.
- `dotnet` non è nel `PATH`: `export PATH="/usr/local/share/dotnet:$PATH"`.
- Mai `rmi -f`/`--force`, mai `docker system prune`; immagini cancellate solo per `sha256:<64 hex>`.
- Mai DELETE su un volume; le voci KEEP non arrivano mai a un comando distruttivo.
- Nessun file sotto `~/Library/Containers/com.docker.docker` viene cancellato; la deny-list non cambia.
- Classificazione pura: nessuna chiamata a `docker` né al filesystem dentro `DockerClassifier`/regole.

## File Structure

```
src/MjmCleaner.Core/Docker/
  DockerModels.cs            record dello snapshot e dei candidati, enum
  DockerSize.cs              "195MB" → byte
  ImageName.cs               normalizzazione repository/tag
  DockerJson.cs              parsing puro dell'output della CLI
  ProcessRunner.cs           processo con ArgumentList + timeout
  DockerCli.cs               IDockerCli, DockerCli, DockerBinaryLocator, DockerUnavailableException
  DockerInventoryCollector.cs  letture → DockerSnapshot
  ProjectReferenceScanner.cs riferimenti alle immagini nei progetti
  ImageRules.cs              lista ordinata delle regole sulle immagini
  VolumeRules.cs             lista ordinata delle regole sui volumi
  DockerClassifier.cs        snapshot + riferimenti → candidati
  DiskUsageProbe.cs          du -k / dimensione apparente di Docker.raw
  DockerCleanExecutor.cs     cancellazione delle voci confermate → DockerCleanResult
tests/MjmCleaner.Core.Tests/Docker/
  Fixtures/*.json            caso reale del brief
  DockerFixtures.cs          caricamento delle fixture
  *Tests.cs                  uno per unità
src/MjmCleaner.App/ViewModels/DockerViewModel.cs, DockerReportViewModel.cs
src/MjmCleaner.App/Views/DockerView.axaml(.cs), DockerReportView.axaml(.cs)
```

## Task 1: modelli, dimensioni, nomi

**Produces:**
- `enum DockerVerdict { Keep, Delete, Propose, Ask }`, `enum DockerResourceKind { Image, Volume, BuildCache }`, `enum ImageOrigin { Unknown, Pulled, Built }`
- `record DockerContainer(string Id, string Name, string ImageId, string State, int ExitCode, IReadOnlyList<string> VolumeNames, IReadOnlyDictionary<string,string> Labels)`
- `record DockerImage(string Id, IReadOnlyList<string> RepoTags, IReadOnlyList<string> RepoDigests, long SizeBytes, long? UniqueSizeBytes, IReadOnlyDictionary<string,string> Labels, ImageOrigin Origin)`
- `record DockerVolume(string Name, IReadOnlyDictionary<string,string> Labels, long? SizeBytes)`
- `record DockerDfEntry(string Type, long SizeBytes, long ReclaimableBytes)`; `record DockerDfSummary(IReadOnlyList<DockerDfEntry> Entries)` con `Images`, `Volumes`, `BuildCache`, `Total`
- `record DockerSnapshot(containers, images, volumes, DockerDfSummary Df, IReadOnlySet<string> ExistingComposeProjects)`
- `record DockerCandidate(DockerResourceKind Kind, string Id, string DisplayName, long? SizeBytes, DockerVerdict Verdict, string RuleId, string Reason, string Cost)` con `SelectedByDefault => Verdict == Delete`
- `DockerSize.Parse(string) → long?` (unità decimali B, kB, MB, GB, TB; "N/A"/vuoto → null; ignora " (2%)")
- `ImageName.Parse(string) → ImageName(string Repository, string? Tag)`: aggiunge `docker.io/` e `docker.io/library/`, toglie `@digest`, il tag è dopo l'ultimo `:` successivo all'ultimo `/`

Test: `DockerSizeTests` (`"195MB"`→195_000_000, `"1.131kB"`→1131, `"0B"`→0, `"76.74MB (2%)"`→76_740_000, `"N/A"`→null); `ImageNameTests` (`alpine:3.20`, `localhost:5000/x:1`, `mcr.microsoft.com/mssql/server:2025-latest`, `repo@sha256:…`, senza tag).

## Task 2: parsing JSON (`DockerJson`)

**Produces:** `ParseContainers(string inspectJson)`, `ParseImages(string inspectJson, IReadOnlyDictionary<string,long> uniqueSizes)`, `ParseVolumes(string inspectJson, IReadOnlyDictionary<string,long> sizes)`, `ParseDfVerbose(string json) → (IReadOnlyDictionary<string,long> ImageUniqueSizes, IReadOnlyDictionary<string,long> VolumeSizes)`, `ParseDfSummary(string jsonLines) → DockerDfSummary`, `ParseIdLines(string)`, `ParseJsonLines(string, string property)`.
Tolleranze: `Config` o `Labels` null/assenti, `Mounts` solo `Type == "volume"`, nome container senza `/`, `Identity.Build`/`Identity.Pull` → `ImageOrigin`.
Errori: JSON non valido → `DockerOutputException` con messaggio leggibile.

Test: fixture reali (`containers.json`, `images.json`, `volumes.json`, `df-verbose.json`, `df.jsonl`) parse con i valori attesi.

## Task 3: regole e classificatore

**Produces:** `ImageRule(string Id, Func<DockerImage, ImageRuleContext, RuleMatch?> Evaluate)`, `ImageRules.Default`; `VolumeRule`, `VolumeRules.Default`; `RuleMatch(DockerVerdict, string Reason, string Cost)`; `ImageReference(string Repository, string? Tag, string File, int Line)`; `ProjectReferences(IReadOnlyList<ImageReference> Images, IReadOnlySet<string> ComposeProjects)`; `DockerClassifier.Classify(DockerSnapshot, ProjectReferences) → IReadOnlyList<DockerCandidate>`.
Ordine delle regole come spec §5 (con `tool-recreated` prima di `locally-built`). Nota "possibile riferimento" aggiunta dal classificatore, non da una regola.

Test (`DockerClassifierTests`, fixture del caso reale): una `Theory` (risorsa → esito, RuleId) per ogni voce dell'atteso in spec §10; più: keycloak con `quay.io/keycloak/keycloak:26.6` citato → KEEP con file; `AddKeycloak` senza tag → PROPOSE con "possibile riferimento"; immagine dangling → DELETE; volume compose con progetto esistente → KEEP, assente → PROPOSE `named-unused`; un'immagine `Identity` assente e `RepoDigests` vuoto → ASK; cache di build → DELETE; nessun volume è mai DELETE (proprietà su tutti i candidati).

## Task 4: scanner dei riferimenti nei progetti

**Produces:** `ProjectReferenceScanner(IFileSystem fs)` con `Scan(IEnumerable<string> roots, CancellationToken ct) → ProjectReferences`.

Test su `MockFileSystem`: compose con `image:` e `name:`; compose senza `name:` → nome cartella normalizzato; `Dockerfile` con multi-stage e `scratch`; AppHost `.AddSqlServer("sql").WithImageTag("2025-latest")` → `mcr.microsoft.com/mssql/server:2025-latest`; `.AddKeycloak("kc")` → tag null; `.WithImage("quay.io/keycloak/keycloak", "26.6")`; Testcontainers `new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest")`; values Helm `repository:`+`tag:`; file in `node_modules`/`bin`/`obj`/`.git` ignorati; template `${TAG}` ignorato.

## Task 5: CLI, processi, raccolta, du

**Produces:** `ProcessRunner.RunAsync(string file, IReadOnlyList<string> args, TimeSpan timeout, CancellationToken) → ProcessResult(int ExitCode, string StdOut, string StdErr, bool TimedOut)`; `IDockerCli.RunAsync(IReadOnlyList<string> args, TimeSpan? timeout, CancellationToken) → ProcessResult`; `DockerCli`; `DockerBinaryLocator.Find(IFileSystem, string home) → string?`; `DockerUnavailableException`; `DockerCliErrors.IsDaemonUnavailable(string stderr)`; `DockerInventoryCollector(IDockerCli, IFileSystem).CollectAsync(ct) → DockerSnapshot`; `DiskUsageProbe` con `MeasureAsync(ct) → DockerDiskUsage(string Path, long? AllocatedBytes, long? ApparentBytes)` e `ParseDuKilobytes(string)`.

Test: `IsDaemonUnavailable` su messaggi reali ("Cannot connect to the Docker daemon at unix:///…", "error during connect", "connect: no such file or directory"); `DockerCli` su runner finto che lancia → `DockerUnavailableException`; collector con `FakeDockerCli` che risponde con le fixture (nessuna immagine/volume/container → nessun `inspect` invocato); `ParseDuKilobytes("8677192\t/path")`; locator su `MockFileSystem`.

## Task 6: esecutore

**Produces:** `DockerCleanExecutor(IDockerCli cli, TimeProvider clock).ExecuteAsync(IReadOnlyList<DockerCandidate> selected, IProgress<CleanProgress>?, CancellationToken) → DockerCleanResult(CleanReport Report, DockerDfSummary Before, DockerDfSummary? After, IReadOnlyList<string> Deleted, IReadOnlyList<ScanError> Failed)`.

Test con `FakeDockerCli` che registra i comandi: `rmi` riceve l'ID; nessun argomento `-f`/`--force` dopo `rmi`; mai `system prune`; KEEP rifiutata senza comando; ID non `sha256:` rifiutato; volume → `volume rm <nome>`; cache → `builder prune -f`; ritentativo di un'immagine con "dependent child images"; daemon spento a metà → resoconto parziale con le voci restanti fallite; byte liberati = delta del df per tipo.

## Task 7: App

**Produces:** `AppServices.Docker` (collector, scanner, classifier, executor, disk probe); pulsante "Docker" nella toolbar (`ShowDockerCommand`); `DockerViewModel` (stati: verifica → non disponibile con "Riprova" | anteprima → esecuzione); `DockerReportViewModel` (resoconto, salvataggio storico come `DoneStepViewModel`); viste XAML con gli stili esistenti.

Verifica: build, test esistenti verdi, avvio dell'app con il daemon acceso (sola analisi, nessuna cancellazione).

## Task 8: documentazione

README: sezione "Docker" e correzione dell'avviso "Docker is not touched"; spec principale §6.2: rimando alla nuova spec.
