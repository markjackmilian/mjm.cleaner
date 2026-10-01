# Pulizia Docker sicura — design

Data: 2026-10-01 · Stato: approvato in chat

## 1. Obiettivo

Recuperare lo spazio occupato da Docker (immagini, volumi, cache di build) **senza mai
cancellare dati o immagini che servono ancora**. Ogni risorsa viene classificata con un
esito (KEEP / DELETE / PROPOSE / ASK), un motivo e un costo per ricrearla; nulla viene
cancellato senza conferma esplicita.

La spec principale (§6.2) resta valida: **nessun file sotto
`~/Library/Containers/com.docker.docker` viene mai cancellato** e la deny-list non cambia.
Questa funzione passa esclusivamente dalla CLI `docker`; di `Docker.raw` si legge solo
la dimensione.

## 2. Collocazione

Pagina dedicata **Docker**, aperta da un pulsante della toolbar accanto a Storico e
Impostazioni — non una categoria del wizard. Il wizard è costruito attorno a `ScanItem`
(un percorso), `PathGuard` e `CleanEngine` (cancellazione da filesystem): generalizzarlo
a risorse che non sono percorsi indebolirebbe proprio le garanzie che lo rendono sicuro.

La pagina riproduce lo stesso contratto del wizard: analisi in sola lettura → anteprima
obbligatoria con selezione → esecuzione → resoconto. **L'anteprima è il dry-run**: finché
l'utente non preme "Elimina" non viene invocato alcun comando distruttivo.

## 3. Architettura (`MjmCleaner.Core/Docker/`)

| Unità | Responsabilità | Dipende da |
|---|---|---|
| `ProcessRunner` | Avvia un processo con `ArgumentList` (mai una stringa da interpretare), timeout, stdout/stderr | — |
| `DockerBinaryLocator` | Trova `docker` fra percorsi noti: un'app aperta dal Finder non eredita il `PATH` della shell | `IFileSystem` |
| `IDockerCli` / `DockerCli` | Unico punto che esegue `docker`. Riconosce gli errori di connessione al socket e li traduce in `DockerUnavailableException` con un messaggio leggibile | `ProcessRunner` |
| `DockerJson` | Parsing puro dell'output JSON di `inspect`, `ls`, `system df` | — |
| `DockerSize` | Converte le dimensioni testuali di Docker (`195MB`, `1.131kB`, unità decimali) | — |
| `ImageName` | Normalizza i riferimenti (`alpine` ≡ `docker.io/library/alpine`), separa repository e tag | — |
| `DockerInventoryCollector` | Esegue le letture e produce un `DockerSnapshot` immutabile; fa anche le verifiche su disco (cartella di un progetto compose ancora presente) così che la classificazione resti pura | `IDockerCli`, `IFileSystem` |
| `ProjectReferenceScanner` | Cerca riferimenti alle immagini nei file dei progetti (§6) | `IFileSystem` |
| `ImageRules` / `VolumeRules` / `DockerClassifier` | Funzioni pure: snapshot + riferimenti → elenco di `DockerCandidate` | — |
| `DiskUsageProbe` | Spazio reale (`du -k`) e apparente di `Docker.raw` | `ProcessRunner`, `IFileSystem` |
| `DockerCleanExecutor` | Esegue la cancellazione delle sole voci confermate e produce un `CleanReport` | `IDockerCli` |

## 4. Raccolta dati (solo JSON)

1. `docker info --format '{{json .}}'` — verifica del daemon. Se non risponde: errore
   chiaro con "Riprova". Docker Desktop **non** viene avviato.
2. `docker ps -aq --no-trunc` + `docker container inspect` → nome, `.Image` (ID completo),
   `.Mounts[].Name` (tipo `volume`), `.Config.Labels`, stato ed exit code. **Anche i
   container fermi**: exit code 137 è normale (stop/kill) e non rende orfane immagini e volumi.
3. `docker images --no-trunc --format '{{json .}}'` + `docker image inspect` → `Id`,
   `RepoTags`, `RepoDigests`, `Size`, `Config.Labels` (può mancare), `Identity`.
4. `docker volume ls --format '{{json .}}'` + `docker volume inspect` → `Labels` (può essere `null`).
5. `docker system df -v --format '{{json .}}'` → dimensione dei volumi, dimensione
   esclusiva delle immagini; `docker system df --format '{{json .}}'` → riepilogo per tipo,
   cache di build inclusa.

La data di creazione **non** è usata come criterio: le build riproducibili riportano la
data zero di Unix (es. `alpine:3.20` "56 anni fa").

### 4.1 Immagine costruita in locale

Misurato su Docker 29.8 con il containerd image store (predefinito in Docker Desktop):
`RepoDigests` è valorizzato **anche per le immagini costruite in locale**
(`dcptun_developer_ms@sha256:<id>`), quindi "RepoDigests vuoto" da solo non funziona più.
`docker image inspect` espone invece `.Identity`:

- `{"Pull":[{"Repository":…}]}` → scaricata, si può riscaricare;
- `{"Build":[…]}` senza `Pull` → costruita in locale.

Regola: costruita in locale se `Identity` ha `Build` e non `Pull`; se `Identity` manca
(store classico) si ricade su `RepoDigests` vuoto.

## 5. Classificazione

Le regole sono **liste ordinate** di `(Id, predicato → esito, motivo, costo)`: vince la
prima che si applica. Estendere significa aggiungere una riga, non un `if`.

### 5.1 Immagini

| # | Id | Condizione | Esito |
|---|---|---|---|
| 1 | `in-use` | ID usato da almeno un container, anche fermo (confronto per **ID**, non per tag) | KEEP |
| 2 | `dangling` | Nessun tag (`<none>:<none>`) | DELETE |
| 3 | `tool-recreated` | Etichetta `org.testcontainers=true`, repository `testcontainers/ryuk*`, `dcptun_*`, oppure immagine base dichiarata da una di queste (etichetta `com.microsoft.developer.usvc-dev.base-image-digest`) | DELETE (si ricrea) |
| 4 | `locally-built` | Costruita in locale (§4.1) | ASK: non si può riscaricare, va ricostruita |
| 5 | `referenced` | Repository **e tag** citati in un file di progetto | KEEP, con file e riga |
| 6 | `superseded` | Un altro tag dello stesso repository è in uso | PROPOSE, "versione superata" |
| 7 | `unused` | Tutto il resto | PROPOSE, "costo: riscaricare" |

**Scostamento dal brief, approvato:** `tool-recreated` precede `locally-built`. `dcptun_*`
è costruita in locale da Aspire, e con l'ordine originale finirebbe in ASK invece che in
DELETE; un'immagine che lo strumento ricostruisce da solo non ha il problema "non si può
riscaricare".

**Riferimento senza tag** (es. `AddKeycloak()` senza `WithImageTag`): non produce KEEP.
Il motivo dell'esito finale riceve la nota "possibile riferimento in `<file>`" e la voce
resta non selezionata. Altrimenti un `AddSqlServer()` senza tag terrebbe anche
`mssql/server:2022-latest`.

### 5.2 Volumi (contengono dati: di default si tengono)

| # | Id | Condizione | Esito |
|---|---|---|---|
| 1 | `mounted` | Montato da almeno un container (anche fermo) | KEEP |
| 2 | `anonymous` | Nome di 64 caratteri esadecimali, non montato | PROPOSE |
| 3 | `compose-project` | Etichetta `com.docker.compose.project` e il progetto esiste ancora (cartella `working_dir` di un container, o file compose trovato nelle cartelle progetto) | KEEP |
| 4 | `aspire-current` | Nome `<app>.apphost-<hash>-<risorsa>-data` e `<hash>` in uso per quella `<app>` (volumi montati) | KEEP: Aspire lo ricollega al prossimo avvio |
| 5 | `aspire-stale` | Nome in stile Aspire con un hash diverso da quello in uso per la stessa app | PROPOSE, "hash AppHost vecchio" |
| 6 | `named-unused` | Tutto il resto | PROPOSE, solo con conferma esplicita |

Nessun volume è mai DELETE.

### 5.3 Cache di build

Un'unica voce DELETE con la dimensione di "Build Cache" da `docker system df`. Costo: solo
tempo alla build successiva.

### 5.4 Selezione predefinita

- DELETE: un blocco unico, preselezionato, confermato in blocco.
- PROPOSE e ASK: selezionabili singolarmente o per gruppo, **mai** preselezionati.
- KEEP: elencati in sola lettura.

## 6. Riferimenti nei progetti

Cartelle: `CleanerSettings.ProjectRoots` (le stesse di bin/obj); se vuoto, la ricerca è
saltata. Cartelle escluse: `node_modules`, `bin`, `obj`, `.git`, `.vs`, `.idea`,
`packages`, `.venv`, `venv`, `dist`, `target`, `.gradle`, `Pods`, `DerivedData`. I
collegamenti simbolici non vengono seguiti; i file oltre 1 MB sono ignorati.

| File | Cosa si estrae |
|---|---|
| `docker-compose*.y*ml`, `compose*.y*ml` | righe `image:`; nome del progetto (`name:` oppure nome della cartella) |
| `Dockerfile*` | righe `FROM` (esclusi `scratch` e i nomi di stage) |
| `*.cs` | per istruzione: `Add<Risorsa>(` di Aspire (tabella metodo → repository), `.WithImage("…"[, "tag"])`, `.WithImageTag("…")`, `.WithImageRegistry("…")`; builder di Testcontainers (`new MsSqlBuilder("img")`, tabella builder → repository) |
| altri `*.y*ml` (Kubernetes/Helm) | righe `image:`; coppie `repository:` + `tag:` |

Valori con template (`{{`, `${`) sono ignorati. Il confronto avviene su repository
normalizzato e, se presente, sul tag.

## 7. Esecuzione

- Immagini: `docker rmi <sha256:id>` — **sempre per ID, mai per tag** (con il containerd
  store `rmi nome:tag` può rispondere "No such image"). L'esecutore rifiuta qualunque
  identificativo che non sia un `sha256:` di 64 caratteri esadecimali.
- **Mai** `rmi -f`, **mai** `docker system prune`. Un'immagine rifiutata (per esempio
  "referenced in multiple repositories") viene riportata come fallita con il motivo.
- Un'immagine fallita perché ha immagini figlie viene ritentata una volta al termine del
  passaggio sulle immagini (le basi possono precedere le derivate).
- Volumi: `docker volume rm <nome>` (senza `-f`).
- Cache di build: `docker builder prune -f` (qui `-f` salta solo la domanda interattiva).
- Le voci KEEP vengono rifiutate anche se arrivano selezionate: ultima linea di difesa.
- Se il daemon si spegne a metà, l'esecuzione si ferma, le voci restanti risultano non
  eseguite e il resoconto parziale viene comunque mostrato e salvato.

## 8. Resoconto e storico

- Cancellato, fallito (con motivo), spazio recuperato secondo `docker system df` (prima →
  dopo) e secondo `du` su `Docker.raw` (prima → dopo), accanto alla dimensione apparente.
- Se `Docker.raw` non si riduce: suggerimento "Docker Desktop → Troubleshoot →
  Clean / Purge data". Mai eseguito in automatico.
- Il `CleanReport` usa le categorie `docker-images`, `docker-volumes`,
  `docker-build-cache`; i byte sono il **delta di `docker system df`** per tipo (la sola
  misura che non dipende da quando Docker restituisce i blocchi all'host). Va nello storico
  e nel log di sessione come le altre pulizie; i "percorsi" del log sono
  `docker:image:<id> (<tag>)`, `docker:volume:<nome>`, `docker:build-cache`.

## 9. Errori

- `docker` non trovato → "Docker non è installato o non è stato trovato".
- Daemon spento o socket irraggiungibile → "Docker non è in esecuzione. Avvia Docker
  Desktop e premi Riprova." Nessuno stack trace.
- Timeout di un comando → errore per quella voce, non fatale.
- JSON inatteso → errore leggibile dell'analisi, nessuna cancellazione possibile.

## 10. Test

Classificazione e parsing testati con fixture JSON derivate dal caso reale, senza Docker:

- Container `sqlserver2025` → `mssql/server:2025-latest` + `mssql2025-data`;
  `storage-bedaxjvn` → `azurite:3.35.0` + `orbit.apphost-48d90b1972-storage-data`, entrambi
  fermi con exit code 137.
- Immagini non usate: `mssql/server:2022-latest`, `keycloak:26.6`, `mssql-tools:latest`,
  `alpine:3.20` (data zero), `testcontainers/ryuk:0.14.0`, `dcptun_developer_ms:0.25.13`
  (`Identity.Build`), `azurelinux/base/core:3.0`, un'immagine costruita in locale.
- Volumi non montati: `orbit.apphost-48d90b1972-sql-data`,
  `orbit.apphost-48d90b1972-keycloak-data`, `orbit.apphost-751ef8e8e6-storage-data`, un
  volume anonimo.

Atteso — KEEP: mssql 2025, azurite, i volumi `48d90b1972`, `mssql2025-data`; DELETE: ryuk,
dcptun, azurelinux base; PROPOSE: mssql 2022 (versione superata), keycloak, mssql-tools,
alpine, volume `751ef8e8e6`, volume anonimo; ASK: l'immagine costruita in locale.

Più: scanner dei progetti su `MockFileSystem`; esecutore con una CLI finta (rmi per ID,
nessun `-f`, nessun `prune` di sistema, KEEP rifiutate, daemon spento a metà); traduzione
degli errori della CLI; parsing di `du` e delle dimensioni.
