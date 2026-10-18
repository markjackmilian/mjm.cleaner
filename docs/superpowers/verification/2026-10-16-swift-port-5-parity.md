# Swift port 5 — collaudo C# / Swift in sola lettura

Data del collaudo: 2026-10-18, Europe/Rome, circa 17:25–18:15 CEST. Stato: **PASS — gate di parità superato**.

Le due app hanno analizzato gli stessi dati veri del Mac dell'utente, con le stesse impostazioni. Tutte le categorie di pulizia, la pagina Docker e la pagina Xcode coincidono per numero di elementi, byte, esclusioni con motivo, verdetti Docker e disponibilità Xcode. Restano due differenze: la variazione naturale delle cache tra un giro e l'altro (chiusa con la sequenza C# → Swift → C# → Swift) e l'ordine in cui la Swift elenca i nomi, che è solo di presentazione (vedi «Giudizi»). Non è stato premuto alcun comando di eliminazione.

## Identità

- Commit collaudato: `56377ece385bb98c9e4b9a14b270865472109385`, branch `codex/swift-port-5`.
- Albero `swift/`: `d4e0084ba1a5e6826108c3c8faf595173e7981ca`; sorgenti dell'app `swift/MjmCleaner` `e536d140a16bdd6e537dc8b1ae05023707a0d437`, `swift/MjmCleanerKit` `6747826cc2bc14faf7692892ceb03d23e49e26b6`.
- macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), .NET SDK 10.0.401. Docker Desktop in esecuzione (server 29.8.2 per `docker info`; entrambe le app mostrano «Docker 29.8.0»).
- C#: `./build/bundle.sh --output-dir <scratch>` dallo stesso commit → `mjm.cleaner.app`, ID `com.mjm.cleaner`, dati in `~/Library/Application Support/mjm.cleaner`.
- Swift: build Debug dallo stesso commit in una DerivedData di scratch → `MjmCleaner.app`, ID `com.mjm.cleaner.debug` (Task 1), avviata **senza** `-MJMDemo`, quindi sui dati veri.
- Avvio di entrambi i bundle per percorso assoluto con `open -n`. Accesso completo al disco non concesso a nessuno dei due (bundle ad hoc appena costruiti): stesse restrizioni per entrambi.

## Metodo

- Nessun input sintetico: l'utente ha guidato le due app (selezioni, Analizza, apertura dei gruppi, ridimensionamento), il controller ha avviato i bundle e catturato le finestre con `screencapture -l<id>` (id letto con `CGWindowListCopyWindowInfo`). Le catture contengono percorsi e nomi di progetti dell'utente: restano fuori dal repository.
- Impostazioni allineate: `settings.json` del C# copiato nel dominio Debug `com.mjm.cleaner.debug` (vuoto fino ad allora), scelta dell'utente. Prima del collaudo il file del C# è stato salvato (SHA-256 `d5bf0cce…a42a78f5`); il C# lo riscrive a ogni analisi (categorie scelte), quindi al termine è stato ripristinato dalla copia e l'hash ricontrollato. Il C# non ha subito altre modifiche: nessuna pulizia, nessuna voce nello storico.
- Soglie in uso: Download 15 giorni, Log 30, NuGet 180, file grandi ≥ 500 MB in `~/Downloads/` e `~/`, progetti in `~/projects/`.
- Sequenza: C# #1 → Swift #1 (Conferma, Docker, Xcode) → C# #2 → Swift #2 (solo Conferma).

## Pulizia — pagina Conferma

| Categoria | C# #1 | Swift #1 | C# #2 | Swift #2 |
| --- | --- | --- | --- | --- |
| Cache utente e di sistema | 9.723 · 789,9 MB | 9.631 · 585,1 MB | 9.631 · 585,1 MB | 9.631 · 585,1 MB |
| Cache di sviluppo | 7 · 2,2 GB | 7 · 2,2 GB | 7 · 2,2 GB | 7 · 2,2 GB |
| Pacchetti NuGet inutilizzati | non scelta | non scelta | nessun gruppo | nessun gruppo |
| Cartelle bin e obj nei progetti | 118 · 4,2 GB | 118 · 4,2 GB | 118 · 4,2 GB | 118 · 4,2 GB |
| Log e crash report | non scelta | 12 · 293,7 KB | 12 · 293,7 KB | 12 · 293,7 KB |
| Cestino | nessun gruppo | nessun gruppo | nessun gruppo | nessun gruppo |
| Download e file grandi | 89 · 47,4 GB | 89 · 47,4 GB | 89 · 47,4 GB | 89 · 47,4 GB |
| **Totale** | 54,6 GB · 9.937 | 54,4 GB · 9.857 | 54,4 GB · 9.857 | 54,4 GB · 9.857 |
| Esclusi dalle protezioni | 67 | 67 | 67 | 67 |
| App in esecuzione segnalate | claude, Outlook, Teams, OneDrive | claude, Docker, Outlook, Teams, OneDrive | claude, Docker, Outlook, Teams, OneDrive | claude, Docker, Outlook, Teams, OneDrive |

Le categorie scelte si leggono da `SelectedCategoryIds` che ogni app salva all'avvio dell'analisi. Nel giro #1 il C# ha analizzato 5 categorie (senza Log e NuGet) e la Swift 6 (senza NuGet), benché l'intenzione fosse «tutte e 7»: la colonna «non scelta» lo riporta. Nel giro #2 entrambe hanno salvato tutte e 7.

Esclusioni: in tutti i giri 67 elementi, con lo stesso motivo «repository di controllo versione: ramo saltato per non cancellare la storia del progetto» per i rami `.git` mostrati. Le cinque righe d'esempio mostrate differiscono perché le due app elencano in ordine diverso (vedi «Giudizi»).

Contenuto del gruppo Log (Swift #1, 12 file): `~/Library/Logs/Claude/{main-window,mcp,unknown-window}.log`, `JetBrains/Daemon/std{err,out}.log`, tre file in `OneDrive/ListSync/`, quattro `CloudTelemetry_messageLog_2026-09-14-*.txt`. Date di creazione, modifica e accesso tutte tra il 14 e il 16 settembre, cioè oltre i 30 giorni della soglia: idonei. Il C# #2 riporta lo stesso conteggio e la stessa dimensione.

## Docker

C# #1 e Swift #1 coincidono riga per riga.

| Voce | C# #1 | Swift #1 |
| --- | --- | --- |
| Motore | Docker 29.8.0 in esecuzione; Docker.raw 5 GB su disco (apparente 926,3 GB) | uguale |
| Riepilogo `df` | Immagini 3 GB (recuperabili 0 B) · Volumi 519,8 MB (151,6 MB) · Cache di build 857,2 MB (19,4 MB) | uguale |
| Eliminabili in sicurezza (DELETE, in blocco) | 3 voci · 1,1 GB: `dcptun_developer_ms:0.25.13` 186,2 MB (tunnel di .NET Aspire), `mcr.microsoft.com/azurelinux/base/core:3.0` 113 MB (immagine base del tunnel), Cache di build 857,2 MB | uguale, stessi motivi e costi |
| Immagini non usate (PROPOSE) | 4 voci · 290,3 MB: due `…/api-devfactory-dev:azd-deploy-…` da 92,3 MB, `devfactory-web:latest` 96,4 MB, `ghcr.io/orbstack/dmigrate-agent:1` 9,2 MB | uguale |
| Da tenere (KEEP) | 6 voci · 3,2 GB: `mssql/server:2025-latest` (usata da sqlserver2025, in esecuzione), `azurite:3.35.0` (usata da storage-bedaxjvn, fermo), volume `mssql2025-data` (montato da sqlserver2025), volumi `orbit.apphost-48d90b1972-{keycloak,sql}-data` (AppHost «orbit» in uso con lo stesso hash), `orbit.apphost-48d90b1972-storage-data` (montato da storage-bedaxjvn) | uguale; dimensioni Swift 2,3 GB, 406,8 MB, 368,2 MB, 651,9 KB, 151 MB, 11,3 KB |
| Pulsante | Elimina 1,1 GB · 3 voci | uguale |

Nessuna voce ASK in questo stato del motore. Il «29.8.0» delle due app contro il «29.8.2» di `docker info` è lo stesso in entrambe: non è una divergenza fra i porting.

## Xcode

| Gruppo | C# #1 | Swift #1 |
| --- | --- | --- |
| DerivedData | 8 voci · 267,4 MB stimati noti | uguale; stesse cartelle e dimensioni (`CompilationCache.noindex` 28 KB, cinque `MjmCleaner-*` da 12 KB a 152,2 MB, `SDKExplicitPrecompiledModules` 96,3 MB, `SymbolCache.noindex` 18,2 MB) |
| Device Support | 0 voci | 0 voci |
| Dispositivi simulati | 11 voci · 2,5 GB stimati noti, tutti Shutdown | uguale, stessi UUID e dimensioni visibili |
| Runtime | 1 voce, iOS 27.0, dimensione «non disponibile», stato Ready, avviso «il percorso dell'immagine non supera i controlli di sicurezza» | uguale, stesso percorso e stesso avviso |
| Riepilogo | 0 B stimati · 0 selezionate | uguale |

Nessuna voce bloccata: nessun simulatore in esecuzione.

## Giudizi

| Differenza | Esito | Motivo |
| --- | --- | --- |
| Cache utente e di sistema: 9.723 · 789,9 MB (C# #1) contro 9.631 · 585,1 MB | Variazione naturale | Ripetuta C# → Swift → C# → Swift: C# #2 e Swift #2 danno esattamente 9.631 · 585,1 MB come Swift #1. Le cache delle app in esecuzione cambiano tra un giro e l'altro. |
| Docker assente dall'avviso «in esecuzione» del C# #1 | Variazione naturale | Presente in C# #2 come nella Swift. |
| Log: gruppo assente nel C# #1 | Selezione, non difetto | Il C# #1 ha salvato `SelectedCategoryIds` senza `logs`; con `logs` scelto (C# #2) riporta 12 · 293,7 KB come la Swift. |
| Ordine dei nomi (DerivedData, esempi di esclusione) | Differenza di presentazione accettata | La Swift ordina per nome le voci di ogni cartella (`LocalFileSystem.contentsOfDirectory` → `entries.sorted()`, dal piano 1, commit `7024d55`); il C# usa l'ordine grezzo di `readdir`, cioè l'ordine di hash di APFS, che non ha significato. Insiemi, conteggi, byte e motivi coincidono. Non rientra nelle due eccezioni della spec §9.4 in senso stretto: è registrato qui come giudizio del controller, con costo se sbagliato pari a un ordinamento da togliere. |

Nessuna differenza è un alias APFS della spec §12, e nessuna richiede una correzione.

## Esito

**Gate di parità superato.** Tutte e 7 le categorie di pulizia, Docker e Xcode coincidono sullo stesso stato del disco. Nessun difetto aperto da questo collaudo.

Limiti:

- Le categorie NuGet e Cestino non avevano voci idonee su questo Mac, quindi la loro parità è dimostrata solo sul caso vuoto. Restano coperte dai test portati.
- Senza Accesso completo al disco nessuna delle due app legge le cartelle protette da TCC: il confronto vale a parità di permessi.
- Le catture non sono nel repository; il registro operativo con le letture è nello scratchpad della sessione.
- Il commit `56377ec` è precedente alla correzione D-2 del verbale visivo, che sposta la presa d'atto nel pannello di conferma Xcode. Quella modifica riguarda solo la disposizione del pannello, che compare dopo «Anteprima selezione», e non tocca l'analisi confrontata qui.
