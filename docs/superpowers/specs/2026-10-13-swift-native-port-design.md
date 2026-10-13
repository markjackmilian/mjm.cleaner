# Porting nativo in Swift — Specifica di progettazione (fase 1)

**Data:** 2026-10-13
**Stato:** approvata in sessione, in attesa di revisione scritta
**Branch:** `feat/swift-port`

## 1. Obiettivo

Riscrivere `mjm.cleaner` in Swift nativo come primo passo verso un'app di pulizia per il Mac App Store.

Il lavoro è diviso in due sotto-progetti, ciascuno con spec, piano e implementazione propri:

1. **Fase 1 — porting nativo (questo documento).** L'app Swift replica 1:1 l'app C#/Avalonia attuale: stessi flussi, stesse regole di sicurezza, stessi testi, stesse funzioni (Pulizia, Docker, Xcode, Storico, Impostazioni). **Nessuna sandbox.**
2. **Fase 2 — adattamento al Mac App Store.** App Sandbox, accesso alle cartelle concesso dall'utente, firma e distribuzione. Avrà una sua spec, preceduta dagli spike elencati al §11.

Il porting replica il comportamento, non la sintassi. Dove Swift impone un adattamento per mantenere una garanzia esistente, l'adattamento è dichiarato esplicitamente (§8.2).

## 2. Decisioni fondanti

| Decisione | Scelta | Motivazione |
|---|---|---|
| Sandbox in fase 1 | No | Un porting fedele è incompatibile con la sandbox: cache di altre app, `$TMPDIR` reale, CLI `docker`, `xcrun simctl`. L'App Store arriva con la fase 2 |
| Convivenza col C# | Stesso repository, cartella `swift/`; il C# resta come riferimento eseguibile fino alla parità, poi viene rimosso (§10) | Il comportamento da replicare resta eseguibile e confrontabile; storia e documenti restano insieme |
| macOS minimo | 15 Sequoia | Observation, `Table`, `NavigationSplitView` e API SwiftUI recenti senza ripieghi di compatibilità |
| Dati esistenti | Partenza da zero | Nuova cartella dati, nessuna migrazione di storico e impostazioni dell'app C# |
| Stack | SwiftUI + logica in un Swift Package locale | Il confine del package impone per compilatore che la logica non dipenda dalla UI ed è la giuntura in cui la fase 2 inserirà la sandbox |
| Dipendenze esterne | Nessuna | SQLite e zlib sono librerie di sistema; il resto è codice proprio |
| Lingua | Italiano, tutti i testi in String Catalog | Nessuna traduzione ora; il costo è nullo adesso e alto se rimandato |

Alternative scartate: **AppKit puro** (doppio del codice UI per un vantaggio prestazionale che non serve: l'albero di conferma si ferma ai percorsi, non ai singoli file); **SwiftUI in un unico target Xcode** (la separazione logica/UI resterebbe una convenzione e i test richiederebbero `xcodebuild` con un host).

## 3. Strumenti

- Xcode 27, Swift 6.4 sulla macchina di sviluppo
- Swift 6 language mode (concorrenza stretta)
- `swift-tools-version` allineata alla versione disponibile sui runner GitHub, non solo a quella locale
- Swift Testing per tutti i test
- Nessuna identità di firma: build firmate "Sign to Run Locally" (ad hoc)

## 4. Architettura

```
swift/                                  ← accanto a src/ e tests/ del C#
├── MjmCleaner.xcodeproj                 solo il target app, cartelle sincronizzate
├── Config/*.xcconfig                    bundle id, versione, firma
├── MjmCleaner/                          target app: @main, viste SwiftUI, Assets, Localizable.xcstrings
└── MjmCleanerKit/                       Swift Package locale, macOS 15
    ├── Package.swift
    ├── Sources/CleanerCore/             porting di MjmCleaner.Core
    │   ├── Categories/  Scanning/  Cleaning/  Safety/
    │   ├── History/  Settings/  Diagnostics/
    │   ├── Docker/  Xcode/
    │   └── Platform/                    FileSystem, WallClock, ProcessRunner, gzip
    ├── Sources/CleanerFeatures/         porting dei ViewModel e di AppServices
    ├── Sources/CZlib/                   target systemLibrary: module map verso la zlib di sistema
    └── Tests/
        ├── CleanerCoreTests/            + Fixtures/ (JSON Docker e Xcode copiati)
        └── CleanerFeaturesTests/
```

### 4.1 Confini

- **`CleanerCore`** non importa SwiftUI né AppKit e non conosce `CleanerFeatures`.
- **`CleanerFeatures`** non importa SwiftUI. Contiene i modelli di presentazione (`@MainActor @Observable`), la navigazione, il blocco di navigazione e `AppEnvironment`. Quello che oggi un ViewModel chiede alla UI diventa un protocollo implementato dall'app: selettore cartelle (`FolderPicking`), applicazione dell'aspetto (`AppearanceApplying`), apertura delle Impostazioni. Per questo i test di comportamento di `MjmCleaner.App.Tests` si portano senza avviare l'app.
- **Target app**: solo viste SwiftUI e adattatori AppKit (`NSOpenPanel`, `NSApp.appearance`).

Due moduli Swift e non di più (oltre al solo module map `CZlib`): il C# ha un solo assembly Core, e separare Docker e Xcode in moduli propri aggiungerebbe solo dichiarazioni `public` senza un confine che serva.

### 4.2 Concorrenza

- Modelli di dominio: `struct` `Sendable` (equivalenti dei `record` C#).
- Servizi senza stato mutabile: `final class` `Sendable`. Servizi con stato (storico): `actor`.
- `CancellationToken` → cancellazione cooperativa dei `Task` (`Task.checkCancellation()` / `Task.isCancelled`).
- `IProgress<T>` → callback `@Sendable` o `AsyncStream`, consumati dal modello sul `MainActor`.
- La scansione parallela per categoria usa un `TaskGroup`; la pulizia resta sequenziale come in C#.

### 4.3 Composizione

`AppEnvironment` è il porting di `AppServices`: costruisce a mano il grafo degli oggetti, senza contenitore DI, con le stesse dipendenze. L'app lo crea all'avvio e lo passa alle viste tramite `@Environment`.

### 4.4 Dati dell'applicazione

- Cartella: `~/Library/Application Support/<bundle id>/`, ricavata con `FileManager` (`.applicationSupportDirectory`). È distinta da `~/Library/Application Support/mjm.cleaner/` del C#: le due app convivono senza toccarsi. In fase 2 la stessa chiamata punterà al container della sandbox senza modifiche.
- Contenuto: `history.db`, `settings.json`, `logs/`, come oggi.
- È sotto `~/Library/Application Support`, quindi coperta dalla deny-list: l'app non può eliminare il proprio storico.
- Bundle id provvisorio: `com.mjm.cleaner`, definito in xcconfig. Quello definitivo va fissato prima della fase 2, perché ne dipende il percorso del container.

## 5. Porting del Core

### 5.1 Principio

Ogni tipo C# ha una controparte Swift con lo stesso nome (senza il prefisso `I` per i protocolli) e la stessa responsabilità. I commenti che motivano le regole di sicurezza in `PathGuard`, `DenyList`, `CanonicalPath`, `RuleScanner` e `CleanEngine` si portano insieme al codice: documentano i casi limite che i test verificano.

### 5.2 Giunture della piattaforma (`Platform/`)

| C# | Swift |
|---|---|
| `System.IO.Abstractions` + `ILinkInspector` | protocollo `FileSystem` |
| `TimeProvider` | protocollo `WallClock` (`var now: Date`) |
| `IProcessRunner` / `ProcessRunner` | protocollo `ProcessRunning` / `ProcessRunner` |

**`FileSystem`** espone solo le operazioni che il Core usa:

- informazioni su un percorso senza seguire i collegamenti (`lstat`): tipo, è-collegamento, dimensione logica, `atime`, `mtime`
- elenco del contenuto di una cartella
- destinazione finale di un collegamento (catena completa)
- rimozione di un file; rimozione ricorsiva di una cartella senza seguire i collegamenti
- lettura e scrittura atomica di testo; aggiunta in coda a un file (§8.2)
- creazione di una cartella
- spazio libero del volume

Gli errori arrivano come `FileSystemError(code: errno, path:)`. L'implementazione reale usa POSIX (`lstat`, `opendir`/`readdir`, `realpath`, `removefile`) e non segue mai i collegamenti simbolici.

Per i test: un `InMemoryFileSystem`, più i decoratori di guasto esistenti in C# portati 1:1 (`VanishingFileSystem`, `VanishingChildFileSystem`, `UnreadableDirectoryFileSystem`, `ThrowingOnDeleteFileSystem`), più `FakeLinkInspector` dove serve ai test del `PathGuard`.

**`ProcessRunner`** usa `posix_spawn` con:

- argomenti passati come array, mai attraverso una shell: un nome di volume o un template `{{json .}}` non possono diventare un altro comando;
- stdout e stderr letti in parallelo;
- ambiente opzionale aggiuntivo;
- timeout e cancellazione che terminano **l'intero process group** (`POSIX_SPAWN_SETPGROUP` + `killpg`). È l'equivalente di `Kill(entireProcessTree: true)`. Foundation `Process` termina solo il figlio diretto e lascerebbe vivo `simctl` dietro `xcrun`;
- risultato `ProcessResult(exitCode, stdout, stderr, timedOut)`. La cancellazione richiesta dal chiamante si propaga come cancellazione, il timeout come `timedOut: true`, come in C#.

### 5.3 Equivalenze da rispettare alla lettera

| Comportamento | C# | Swift |
|---|---|---|
| Classificazione errori | `RuleScanner.Describe` sul tipo di eccezione che .NET ricava dall'errno | stessa mappatura, applicata direttamente all'errno: `EACCES`/`EPERM`/`EBADF` → accesso negato; `ENOENT` → non trovato; `ENOTEMPTY` → non vuota; **qualunque altro errno → in uso**, perché in C# ogni `IOException` residua cade lì. `ScanErrorKind.Other` resta riservato agli esiti prodotti dal Core stesso (rifiuti del `PathGuard`, root mancante) |
| Testo del messaggio d'errore | `Exception.Message` (inglese, generato da .NET) | testo di sistema dell'errno (`strerror`). Il testo esatto differisce da quello .NET: differenza accettata |
| Glob | `FileSystemName.MatchesSimpleExpression`, case-insensitive | matcher proprio per `*` e `?`, case-insensitive. Niente `fnmatch`, che interpreterebbe `[…]` |
| Confronti di percorso | `OrdinalIgnoreCase` | confronto ordinale case-insensitive, con una sola funzione condivisa |
| Età di un elemento | max(`LastAccessTimeUtc`, `LastWriteTimeUtc`) | max(`atime`, `mtime`) |
| Dimensione | `FileInfo.Length` (logica) | `st_size` (logica) |
| Dimensione e date di un collegamento simbolico | `FileInfo`/`DirectoryInfo` leggono il collegamento stesso (`lstat`), misurato su .NET 10 | identico (`lstat`) |
| `File.Exists` / `Directory.Exists` su collegamenti | collegamento a cartella: `File.Exists` falso, `Directory.Exists` vero; collegamento interrotto: `File.Exists` vero | identico, anche dove produce un difetto (registro di parità, candidati) |
| Misura reale di una cartella prima di cancellarla | `EnumerateFiles(…, AllDirectories)` scende nei collegamenti a cartelle | **differenza voluta**: non si scende nei collegamenti, come prescrive la spec originale §7; la cancellazione non li segue, quindi quei byte non venivano comunque liberati |
| Cartella che fallisce a metà | elemento fallito, 0 byte accreditati | identico |
| Dimensione accreditata | rimisurata subito prima della cancellazione, mai quella dell'interfaccia | identico |
| Percorso cancellato | quello restituito dal `PathGuard` dopo la riscrittura sulla root risolta | identico |

### 5.4 Sicurezza

`PathGuard`, `DenyList` e `CanonicalPath` si portano per primi, in TDD, con tutte le regole della spec originale (`2026-09-15-mjm-cleaner-design.md` §8): rifiuto dei percorsi non canonici, contenimento, deny-list con uguaglianza esatta e ricorsiva ed eccezioni, profondità minima, collegamenti simbolici con validazione separata della root che risolve e giudica la destinazione, coerenza della configurazione, confronto case-insensitive.

`validate` e `validateRoot` **non sono `throws` per firma**: la regola «nessuna validazione solleva eccezioni» diventa un vincolo del compilatore.

### 5.5 Persistenza

- **Storico:** modulo `SQLite3` di sistema con un wrapper minimo (apertura, statement preparati, transazione). Lo schema è identico a quello attuale (`CleanSession`, `SessionCategory`, `PRAGMA user_version = 1`) e restano le stesse regole: totale calcolato con `SUM`, solo byte effettivamente liberati, timestamp UTC ISO 8601, lo storico non fa mai fallire la pulizia. Scartato SwiftData: schema opaco e migrazioni implicite per due tabelle.
- **Impostazioni:** `settings.json` con `Codable` e decodifica tollerante: campo mancante → default, aspetto sconosciuto → Auto. Campi e default identici a `CleanerSettings`.
- **Log di sessione:** `session-NNNNNN.jsonl.gz`, un record JSON per elemento, retention delle ultime 20 sessioni. La compressione gzip usa la zlib di sistema tramite un target `systemLibrary`: Foundation non scrive gzip, e il file deve restare leggibile con `gzip -dc` (su macOS `zcat` legge solo il formato `.Z`).

### 5.6 Docker e Xcode

Classificatori, regole, parser JSON, gruppi di conferma, selezione ed esecutori sono logica pura e si portano 1:1. Le fixture JSON (`containers.json`, `df-verbose.json`, `df.jsonl`, `images.json`, `volumes.json`, `simctl-list.json`, `runtime-list*.json`, `malformed-devices.json`) si copiano nei test Swift. Le regex di `ProjectReferenceScanner` diventano Swift `Regex`, verificate dagli stessi casi di test. Le invocazioni esterne (`docker`, `xcrun simctl`, `du`, `ps`) restano le stesse, con gli stessi argomenti, tramite `ProcessRunner`.

## 6. Interfaccia

### 6.1 Principio

Flussi, passi, azioni e testi restano gli stessi dell'app attuale dopo il redesign (`2026-10-02-macos-redesign-design.md`). Il redesign imitava i componenti nativi macOS: in SwiftUI si usano direttamente quelli. Spariscono i token colore custom e gli stili disegnati a mano.

### 6.2 Mappatura

| Attuale (Avalonia) | SwiftUI |
|---|---|
| Finestra unica, iniziale 1120×700, minima 900×600 | Scena `Window` singola, stesse dimensioni |
| Sidebar custom 232 px | `NavigationSplitView` con `List(selection:)`: Pulizia · Docker · Xcode · Storico, con SF Symbols; card «Spazio liberato» e «Impostazioni… ⌘,» in `safeAreaInset(edge: .bottom)` |
| Toolbar custom 52 px | Toolbar nativa unificata: `navigationTitle`, `navigationSubtitle`, `StepIndicator` come elemento di toolbar |
| Barra azioni 56 px | `safeAreaInset(edge: .bottom)`; primario `.borderedProminent`; «Elimina…» con `role: .destructive` e tinta rossa |
| Liste raggruppate ed Expander | `List`/`Form` con stile raggruppato e `DisclosureGroup`; NuGet resta figlia indentata |
| Tabella Storico | `Table`: Data (decrescente) · Spazio · Categorie (chip con nome leggibile) · Elementi |
| `SettingsWindow` modale 700 px | Sheet sulla finestra principale, larghezza 700, Annulla/Salva in basso a destra. La voce di menu «Impostazioni… ⌘,» apre lo sheet al posto della scena `Settings` standard, che non è modale e non ha Annulla |
| `FatalErrorWindow` | Vista d'errore nella finestra principale, con lo stesso testo e il pulsante Esci, quando `AppEnvironment` non si inizializza |

### 6.3 Navigazione

È uno stato di `CleanerFeatures`: un enum `Page` con il modello di pagina associato. La sidebar ricava da lì la voce selezionata. Le regole sono quelle attuali:

- «Pulizia» su un passo del wizard non fa nulla; da un'altra sezione riparte dal passo 1.
- Docker, Xcode e Storico creano una pagina nuova a ogni selezione.
- Mentre Xcode elimina, sidebar e ⌘, sono disabilitati. Il blocco è imposto dal modello, che rifiuta il cambio di pagina, e non solo dalla vista con `.disabled`, così che sia verificabile dai test.
- Salva nelle Impostazioni salva e riporta al passo 1.

### 6.4 Aspetto e colori

- Preferenza Auto/Chiaro/Scuro applicata con `NSApp.appearance` (`nil` / `.aqua` / `.darkAqua`): vale per tutte le finestre e per gli sheet, viene applicata all'avvio prima di mostrare la finestra e in anteprima mentre si sceglie. Annulla ripristina il valore caricato.
- Accento `#0A66D8` come `AccentColor` nel catalogo asset. macOS lo usa quando l'accento di sistema è "multicolore", altrimenti rispetta la scelta dell'utente: è il comportamento nativo.
- Colori dedicati, con varianti chiaro/scuro nel catalogo asset, solo per le pill di rischio e le tile delle categorie (incluse `downloads-large` `#E8833A` e `trash` `#D2453A`). Tutto il resto usa i colori semantici di sistema.

### 6.5 Testi e formati

- Tutti i testi visibili, dell'interfaccia e dei messaggi del Core, passano da `String(localized:)` con String Catalog. La lingua di sviluppo è l'italiano; nessuna traduzione in fase 1.
- `FormatBytes` si porta identica: base 1024, unità B/KB/MB/GB/TB, un decimale al massimo, cultura `it-IT`. Non si usa `ByteCountFormatter`, che lavora in base 1000 e mostrerebbe numeri diversi.
- Date dello storico in `d MMM yyyy, HH:mm`, `it-IT`, ora locale.

### 6.6 Cartelle e accessibilità

- «+» apre `NSOpenPanel` (solo cartelle) tramite `FolderPicking`; «−» rimuove la selezionata ed è disabilitato senza selezione. I percorsi salvati, anche con `~`, restano testo invariato.
- I controlli nativi forniscono i nomi accessibili; i pulsanti solo icona (+, −) hanno `accessibilityLabel`. Il rischio resta comunicato anche dal testo della pill.

## 7. Flusso

Invariato rispetto alla spec originale:

```
[UI] categorie selezionate
   → ScanEngine        (parallelo per categoria, progresso, cancellabile)
   → ScanResult        (elenco immutabile: percorso + dimensione)
   → [UI] passo 3      (anteprima, deselezioni puntuali)
   → PathGuard         (validazione immediatamente prima di ogni eliminazione)
   → CleanEngine       (errori per singolo elemento, mai fatali)
   → CleanReport → HistoryStore + SessionLogWriter → contatore aggiornato
```

Scansione e pulizia restano fasi separate: ciò che appare nell'anteprima è esattamente ciò che viene eliminato.

## 8. Gestione degli errori

### 8.1 Invariato

- Le quattro famiglie (accesso negato, in uso, non trovato, non vuota) vengono raccolte per elemento e non interrompono mai l'operazione.
- L'accesso negato indica il Full Disk Access e dove concederlo.
- Docker non raggiungibile mostra il messaggio del Core e offre Riprova; l'app non avvia mai Docker Desktop.
- `xcrun` assente o rimozione dei runtime non supportata dalla CLI: gli stessi messaggi di oggi.
- L'app non chiede né tenta l'elevazione dei privilegi.

### 8.2 Adattamento imposto da Swift: diario della pulizia

In C#, `CleanEngine` intercetta qualunque eccezione per non perdere l'elenco di ciò che è già stato cancellato: con l'eliminazione definitiva è l'unica ricostruzione possibile. In Swift un errore di programmazione (indice fuori intervallo, unwrap di `nil`) termina il processo e non è intercettabile, quindi la garanzia andrebbe persa.

Per mantenerla:

- durante la pulizia, ogni percorso eliminato con successo viene aggiunto subito in coda a `logs/pending-<timestamp UTC>.jsonl`, in chiaro, con lo stesso formato di record del log di sessione;
- a fine sessione il diario diventa il normale `session-NNNNNN.jsonl.gz` e il file in chiaro viene rimosso;
- dopo un crash il diario resta in `logs/`, leggibile; la retention, che riconosce solo `session-NNNNNN.jsonl.gz`, non lo tocca;
- nessun recupero automatico nello storico.

Il Core inoltre non usa `!`, `try!` né indicizzazioni non verificate.

## 9. Test

### 9.1 Core

- **Porting 1:1 delle 349 prove di `MjmCleaner.Core.Tests`**, mantenendo i nomi. I 208 casi `InlineData` diventano `@Test(arguments:)`.
- Stesso ordine della prima implementazione: `PathGuard` (con `DenyList` e `CanonicalPath`) per primo, in TDD.
- Unit test su `InMemoryFileSystem` e decoratori di guasto; test di integrazione su cartelle temporanee reali per collegamenti simbolici, permessi, eliminazione ricorsiva e case-insensitivity di APFS.
- Test di `ProcessRunner` su processi reali innocui (`/bin/echo`, `/bin/sleep`) per argomenti, timeout e terminazione del gruppo.
- Test del diario della pulizia (§8.2).

### 9.2 Features

Delle 78 prove di `MjmCleaner.App.Tests`, quelle di comportamento si portano in `CleanerFeaturesTests`: blocco di navigazione, voce di sidebar selezionata, apertura delle Impostazioni, anteprima e ripristino dell'aspetto, salvataggio e ritorno al passo 1, storico (nomi leggibili, data localizzata, totale), Analizza disabilitato senza selezioni, ViewModel Xcode e dei resoconti.

Le prove di layout e tema specifiche di Avalonia (barra azioni nel viewport, dizionari di tema, struttura dell'albero visuale) non hanno equivalente: con `safeAreaInset` e i colori di sistema il difetto che verificavano non può verificarsi. Le sostituisce la verifica manuale del §9.4. Nessun XCUITest in fase 1.

### 9.3 Registro di parità

`docs/superpowers/porting/2026-10-13-parity.md`: una riga per ogni file di test C# con il file Swift corrispondente e il numero di prove portate, oppure la ragione per cui non è portato. Lo stesso documento raccoglie i candidati a miglioramenti notati durante il porting e **non** applicati (§12).

### 9.4 Verifica e collaudo

- **Screenshot** di ogni schermata in chiaro e in scuro (Scegli, Analizza, Conferma, Fatto, Docker, Xcode, Storico, Impostazioni), confrontati con quelli di `docs/superpowers/verification/2026-10-02-macos-redesign/`.
- **Collaudo fianco a fianco:** su questo Mac, app C# e app Swift eseguono uno dopo l'altro l'analisi in sola lettura (passi 1–3, senza confermare) con la stessa selezione e le stesse impostazioni. Si confrontano numero di elementi e totale per categoria, esclusioni del `PathGuard`, inventario Docker con gli esiti KEEP/DELETE/PROPOSE/ASK e inventario Xcode. Le differenze spiegabili con la variazione naturale delle cache fra le due esecuzioni vanno annotate; le altre sono difetti.

## 10. Build, distribuzione e passaggio di consegne

### 10.1 Build

- `swift test` dentro `swift/MjmCleanerKit` per tutta la logica, senza progetto Xcode.
- `xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner` per l'app.
- Firma "Sign to Run Locally". Come oggi, il Full Disk Access è legato all'impronta della firma ad hoc e va concesso di nuovo dopo ogni modifica al codice.
- Versione e numero di build in xcconfig, sovrascrivibili da riga di comando.

### 10.2 Workflow di release

Si porta `release-macos.yml`:

- job di test: `swift test` + `xcodebuild build`;
- job di pacchetto: una sola build Release universale arm64+x86_64 (oggi sono due), firma ad hoc, zip;
- job di release: pubblicazione della GitHub release sul tag, come oggi.

Il workflow C# resta attivo fino al passaggio di consegne.

### 10.3 Rimozione del C#

Condizioni: registro di parità completo, suite Swift verde, verifica screenshot e collaudo fianco a fianco superati.

Poi, in un passaggio esplicito:

- rimozione di `src/`, `tests/`, `build/`, `Directory.Build.props`, `mjm.cleaner.slnx`;
- spostamento del contenuto di `swift/` alla radice del repository;
- README e workflow riscritti per Swift;
- le spec, i piani e i documenti storici in `docs/superpowers/` restano.

## 11. Preparazione della fase 2

### 11.1 Giunture lasciate pronte

| Giuntura | In fase 2 diventa |
|---|---|
| protocollo `FileSystem` | implementazione che apre e chiude l'accesso security-scoped attorno alle operazioni sulle cartelle concesse |
| `FolderPicking` + percorsi salvati come testo | bookmark salvati accanto ai percorsi |
| cartella dati da `FileManager` | punta da sola al container della sandbox |
| bundle id in xcconfig | si fissa quello definitivo cambiando una riga |
| `ProcessRunner` isolato | se Docker o `simctl` non funzionano in sandbox, si rimuove qui senza toccare le pagine |
| String Catalog | si aggiunge l'inglese |

### 11.2 Domande aperte, da chiudere con spike all'inizio della fase 2

1. CLI `docker` e socket `~/.docker/run/docker.sock` da un processo in sandbox.
2. `xcrun simctl` e il servizio XPC di CoreSimulator da un processo in sandbox.
3. `~/Library/Caches`, `/Library/Caches`, `/Library/Logs`, `$TMPDIR` reale e `~/.Trash` con la home concessa dal pannello e/o con Full Disk Access.
4. Eliminazione di file nelle cache di altre app dalla sandbox, con la protezione "App Data" di macOS 14 e successivi.
5. Nome commerciale e bundle id definitivi; iscrizione all'Apple Developer Program.

L'esito può ridurre il perimetro della versione App Store, per esempio con Docker e Xcode disponibili solo nella build diretta. La decisione spetta alla fase 2, con i dati degli spike.

## 12. Fuori ambito per la fase 1

- Nuove funzioni di pulizia: duplicati, residui di app disinstallate, menu bar, schedulazione, notifiche.
- Traduzioni.
- Sandbox, entitlement, security-scoped bookmark, firma con Apple Developer Program, notarizzazione, App Store Connect.
- Migrazione dei dati dell'app C#.
- Modifiche a flussi, regole o testi. I miglioramenti notati durante il porting si annotano nel registro di parità come candidati e non si applicano.
- Recupero automatico nello storico di una pulizia interrotta da un crash (§8.2).
