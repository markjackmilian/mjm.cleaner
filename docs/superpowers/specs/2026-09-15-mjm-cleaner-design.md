# mjm.cleaner — Specifica di progettazione

**Data:** 2026-09-15
**Stato:** approvata, pronta per il piano di implementazione

## 1. Obiettivo

Applicazione desktop per macOS che libera spazio eliminando file rigenerabili, con selezione delle categorie da pulire, storico delle pulizie e contatore cumulativo dei gigabyte liberati.

Uso personale su un singolo Mac. Nessuna distribuzione a terzi: niente sandbox, niente Apple Developer Program, niente notarizzazione.

## 2. Decisioni fondanti

| Decisione | Scelta | Motivazione |
|---|---|---|
| Distribuzione | Solo macchina personale | Elimina il vincolo sandbox, che renderebbe inaccessibili le cache di altre app |
| Stack UI | Avalonia 12 + .NET 10 | Linguaggio già padroneggiato; con questi requisiti la superficie di interop nativo è nulla |
| Modalità eliminazione | Definitiva, con conferma | Scelta esplicita dell'utente; recupera spazio immediatamente senza passare dal Cestino |
| Struttura UI | Wizard a 4 passi + toolbar | L'anteprima non è saltabile per costruzione: unica rete di sicurezza data l'eliminazione definitiva |
| Persistenza storico | SQLite via `Microsoft.Data.Sqlite` | Due tabelle: EF Core non ripagherebbe il proprio costo |
| Presenza di sistema | Nessuna | Solo finestra: niente menu bar, schedulazione o notifiche |

### 2.1 Perché Avalonia e non SwiftUI

I requisiti azzerano la necessità di interop con AppKit: nessun `NSStatusItem` (niente menu bar), nessun `LaunchAgent` (niente schedulazione), nessun `NSFileManager.trashItem` (eliminazione definitiva, basta `Directory.Delete`). Lo scan è I/O POSIX puro. In assenza di superficie nativa, l'argomento decisivo diventa la padronanza del linguaggio.

Alternative scartate: **SwiftUI** (richiede l'installazione di Xcode, assente sulla macchina — presenti solo i Command Line Tools — più l'apprendimento di un nuovo ecosistema); **Tauri** (backend privilegiato in Rust, terzo linguaggio); **Electron** (~150 MB, layer Node il più lento per scan ricorsivi); **.NET MAUI / Mac Catalyst** (modello sandbox-oriented con accesso al filesystem depotenziato — inadatto proprio nel punto che conta).

### 2.2 Limite accettato

L'eliminazione definitiva non ha annullamento. Le contromisure sono l'anteprima obbligatoria con i percorsi esatti (passo 3 del wizard), la deny-list del `PathGuard` e il log completo per sessione.

## 3. Stack tecnico

- .NET 10 (SDK 10.0.401, presente in `/usr/local/share/dotnet`)
- Avalonia 12.1.x (richiede .NET 10 su desktop), tema Fluent
- `CommunityToolkit.Mvvm` — MVVM
- `Microsoft.Data.Sqlite` — storico, SQL scritto a mano
- `System.IO.Abstractions` — astrazione filesystem per i test
- xUnit — test

## 4. Architettura

```
mjm.cleaner/
├── src/
│   ├── MjmCleaner.Core/            # net10.0 — nessun riferimento ad Avalonia
│   │   ├── Categories/             # definizioni categorie e regole
│   │   ├── Scanning/               # motore di scansione
│   │   ├── Cleaning/               # esecuzione eliminazione
│   │   ├── Safety/                 # PathGuard + deny-list
│   │   ├── History/                # persistenza SQLite e log di sessione
│   │   └── Settings/               # preferenze utente
│   ├── MjmCleaner.App/             # Avalonia + CommunityToolkit.Mvvm
│   └── MjmCleaner.Core.Tests/      # xUnit
├── build/bundle.sh                 # publish → .app → Info.plist → codesign ad-hoc
└── docs/superpowers/specs/
```

**Vincolo architetturale:** `MjmCleaner.Core` non referenzia Avalonia. Le regole di eliminazione devono essere testabili senza avviare un'interfaccia grafica.

### 4.1 Flusso

```
[UI] categorie selezionate
   → ScanEngine        (parallelo per categoria, progresso, cancellabile)
   → ScanResult        (elenco immutabile: percorso + dimensione)
   → [UI] passo 3      (anteprima, deselezioni puntuali)
   → PathGuard         (validazione immediatamente prima di ogni eliminazione)
   → CleanEngine       (errori per singolo elemento, mai fatali)
   → CleanReport → HistoryStore → contatore aggiornato
```

**Scan e clean sono fasi separate.** La pulizia consuma l'elenco prodotto dallo scan senza ri-scansionare: ciò che appare nell'anteprima è esattamente ciò che viene eliminato.

## 5. Modello delle categorie

Le regole sono dati, non codice: una sola implementazione di scanner le interpreta.

```csharp
enum ScanMode { ClearContents, MatchingDirs, MatchingFiles }
enum RiskLevel { Low, Medium, High }

record CleanupRule(
    string    Root,                       // supporta ~ e $TMPDIR
    ScanMode  Mode,
    string[]  IncludeGlobs,
    string[]  ExcludeGlobs,
    TimeSpan? MinAge,
    int       MaxDepth,
    bool      RequiresProjectMarker = false);

record CleanupCategory(
    string Id,
    string DisplayName,
    string Description,
    RiskLevel Risk,
    bool SelectedByDefault,
    IReadOnlyList<CleanupRule> Rules);
```

**Modalità di scansione:**

- `ClearContents` — svuota il contenuto della root mantenendo la root (cache)
- `MatchingDirs` — individua ricorsivamente directory il cui nome corrisponde ai pattern (`bin`, `obj`)
- `MatchingFiles` — file per pattern ed età (log, Download)

**Root inesistente ⇒ categoria vuota, non errore.** Xcode DerivedData e le cache Gradle non esistono sulla macchina attuale: le relative regole restano definite e diventano attive se un giorno quei percorsi compariranno.

## 6. Le cinque categorie

Dimensioni rilevate il 2026-09-15 sulla macchina di riferimento.

### 6.1 Cache utente e di sistema — rischio medio

| Percorso | Modalità | Note |
|---|---|---|
| `~/Library/Caches` | `ClearContents` | 5.4 GB rilevati |
| `/Library/Caches` | `ClearContents` | Alcuni elementi appartengono a root |
| `$TMPDIR` (`/var/folders/…/T/`) | `ClearContents`, età min. 1 giorno | |

Selezionata di default. Il passo 3 avvisa quali applicazioni fra quelle interessate risultano in esecuzione: svuotare la cache di un'app aperta può causarne un comportamento anomalo fino al riavvio.

**L'applicazione non richiede né tenta l'elevazione dei privilegi.** Gli elementi di `/Library/Caches` appartenenti a `root` falliranno con accesso negato e compariranno nel riepilogo degli errori del passo 4: è il comportamento previsto, non un difetto. Eseguire con privilegi di root un processo che cancella file in via definitiva è un rischio sproporzionato rispetto allo spazio recuperabile.

### 6.2 Cache di sviluppo — rischio basso

| Percorso | Modalità | Note |
|---|---|---|
| `~/.npm/_cacache` | `ClearContents` | 124 MB |
| `~/.cache` | `ClearContents` | 1.6 GB |
| `~/Library/Developer/Xcode/DerivedData` | `ClearContents` | Assente oggi |
| `~/Library/Developer/Xcode/Archives` | `ClearContents` | Assente oggi |
| `~/.gradle/caches` | `ClearContents` | Assente oggi |

Selezionata di default.

**`~/.nuget/packages` (4.6 GB) è una voce annidata e deselezionata di default**, con filtro per età (predefinito: 6 mesi). Svuotare la cache NuGet costa il ri-download di ogni pacchetto alla build successiva e rende impossibile compilare offline: non deve accadere per inerzia insieme alle altre cache dev.

*Limite noto:* "pacchetto non usato da N mesi" si basa su `LastAccessTimeUtc`, con ricaduta su `LastWriteTimeUtc` quando l'ultimo accesso non è attendibile. È un'euristica, e va presentata come tale nell'interfaccia.

**Docker è escluso via deny-list.** Eliminare file dentro `~/Library/Containers/com.docker.docker` corrompe la macchina virtuale. Lo spazio occupato da Docker si recupera con `docker system prune`, non con la cancellazione di file.

### 6.3 Progetti .NET: `bin` / `obj` ricorsivi — rischio basso

Root configurabili dall'utente (nessuna preimpostata). Modalità `MatchingDirs` sui nomi `bin` e `obj`.

**`RequiresProjectMarker = true`: una directory viene proposta solo se la sua directory padre contiene un file `*.csproj`, `*.fsproj`, `*.vbproj`, `*.sln` o `*.slnx`.** Senza questo vincolo, una root configurata male porterebbe a proporre l'eliminazione di `/usr/bin`.

La ricorsione non prosegue all'interno di una directory già individuata. Selezionata di default.

### 6.4 Log e crash report — rischio basso

`~/Library/Logs`, `/Library/Logs`, `~/Library/Logs/DiagnosticReports`, `/Library/Logs/DiagnosticReports`. Modalità `MatchingFiles`, età minima 30 giorni (configurabile). Selezionata di default.

### 6.5 Cestino, Download e file grandi — rischio alto

| Voce | Comportamento |
|---|---|
| `~/.Trash` | `ClearContents` |
| `~/Downloads` | `MatchingFiles`, età minima 90 giorni (configurabile) |
| File grandi | Ricerca su root configurabili, soglia predefinita 500 MB |

**Mai selezionata di default.** Le singole voci nascono deselezionate anche quando la categoria è attiva: la selezione è sempre esplicita, elemento per elemento. La ricerca file grandi si limita a elencare.

## 7. Motore di scansione ed eliminazione

- **Parallelo per categoria**, avanzamento via `IProgress<ScanProgress>`, `CancellationToken` propagato a ogni livello. Attraversare `~/Library/Caches` significa centinaia di migliaia di file: l'interfaccia resta reattiva e l'operazione è annullabile.
- **I symlink non vengono mai seguiti.** Sono trattati come foglie: si elimina il collegamento, mai il bersaglio. Un link dentro una cache che punti a `~/Documents` trasformerebbe una pulizia di routine in una perdita di dati.
- **Dimensioni:** `FileInfo.Length` (dimensione logica). Discrepanza nota sui file sparsi, dove sovrastima l'occupazione reale; il caso pratico rilevante (immagini disco Docker) è già escluso.
- **Errori per elemento, mai fatali:** si annota e si prosegue.

## 8. Sicurezza — `PathGuard`

Invocato immediatamente prima di ogni eliminazione, non solo in fase di definizione delle regole. Cinque controlli in ordine:

1. **Canonicalizzazione** del percorso (risoluzione di `.` e `..`) prima di ogni confronto.
2. **Contenimento:** l'elemento deve trovarsi sotto la root dichiarata dalla regola che lo ha prodotto.
3. **Deny-list** (non modificabile dall'interfaccia, deliberatamente), con due semantiche distinte:

   **Uguaglianza esatta** — negati come blocco singolo, perché negarli in modo ricorsivo renderebbe non pulibile tutto ciò che sta sotto: `/`, `/Users`, `~`.

   **Ricorsivi** — negati con tutto il loro contenuto:
   - sistema: `/System`, `/usr`, `/bin`, `/sbin`, `/etc`, `/private/etc`, `/private/var/db`, `/private/var/root`, `/Applications`, `/Library` (con eccezione di `/Library/Caches` e `/Library/Logs`), `/Volumes`, `/Network`, `/opt`, `/cores`
   - utente: `~/Documents`, `~/Desktop`, `~/Pictures`, `~/Movies`, `~/Music`, `~/Public`, `~/Sites`, `~/Applications`, `~/Library/Application Support`, `~/Library/Mobile Documents`, `~/Library/Keychains`, `~/Library/Mail`, `~/Library/Messages`, `~/Library/Safari`, `~/Library/Preferences`, `~/Library/Containers`, `~/Library/Group Containers`, `~/Library/Application Scripts`, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.kube`, `~/.docker`, `~/.config`, `~/.local`, `~/.password-store`

   Due voci meritano una nota. **`/Volumes`** copre i dischi esterni e i backup di Time Machine: è il percorso il cui danno potenziale è più grande di tutti gli altri messi insieme. **`/private/etc`** è il gemello di `/etc`, che la canonicalizzazione non raggiunge perché `Path.GetFullPath` non risolve i collegamenti simbolici.

   `/private/var/db` e `/private/var/root` sono negati, ma **`/private/var/folders` no**: è `$TMPDIR`, ed è legittimamente pulibile. Per la stessa ragione restano fuori dalla deny-list `~/Library/Caches`, `/Library/Caches`, `~/Library/Logs`, `/Library/Logs`, `~/Library/Developer`, `~/.Trash`, `~/Downloads`, `~/.nuget`, `~/.npm`, `~/.cache` e `/tmp`: sono le categorie stesse dell'applicazione.

   **Il controllo è fail-closed.** Un percorso vuoto, non assoluto, o che contenga `//`, `/./` o `/../` viene negato con motivazione esplicita, senza essere confrontato con gli elenchi. Non è pedanteria: le eccezioni sono ricorsive e valutate per prime, quindi un percorso non canonico che cominci per `/Library/Caches/` verrebbe altrimenti *attivamente permesso* in cortocircuito su tutte le negazioni — `/Library/Caches/../../etc/passwd` passava.
4. **Profondità minima:** mai la home stessa; mai un figlio diretto della home che non compaia esplicitamente in una regola. Questa regola copre **esattamente** la profondità 1: tutto ciò che sta più in basso è affare della deny-list, che va tenuta completa di conseguenza. `~/Downloads/vecchio.dmg`, a profondità 2, è legittimamente eliminabile — ed è il motivo per cui la regola non può essere estesa in profondità senza rendere inutile l'applicazione.
5. **Symlink:** si elimina il collegamento, mai il bersaglio.

**Il confronto è case-insensitive.** APFS è case-insensitive nella configurazione predefinita: un percorso che arriva come `~/documents` deve essere bloccato dalla voce `~/Documents`, perché il filesystem lo risolverebbe comunque sulla cartella reale.

Gli elementi scartati dal `PathGuard` sono mostrati al passo 3 in un riquadro dedicato, con la motivazione: se un totale non torna, se ne trova lì la ragione.

**Il `PathGuard` è il primo componente da implementare, in TDD.** È il punto in cui un difetto non genera un errore visibile, ma una perdita di dati.

## 9. Storico e contatore

Posizione: `~/Library/Application Support/mjm.cleaner/` (già coperta dalla deny-list: l'applicazione non può eliminare il proprio storico).

```sql
CREATE TABLE CleanSession (
  Id           INTEGER PRIMARY KEY AUTOINCREMENT,
  StartedAtUtc TEXT    NOT NULL,   -- ISO 8601 UTC
  DurationMs   INTEGER NOT NULL,
  BytesFreed   INTEGER NOT NULL,
  ItemsDeleted INTEGER NOT NULL,
  ItemsFailed  INTEGER NOT NULL
);

CREATE TABLE SessionCategory (
  SessionId    INTEGER NOT NULL REFERENCES CleanSession(Id) ON DELETE CASCADE,
  CategoryId   TEXT    NOT NULL,
  BytesFreed   INTEGER NOT NULL,
  ItemsDeleted INTEGER NOT NULL,
  PRIMARY KEY (SessionId, CategoryId)
);
```

Versionamento dello schema tramite `PRAGMA user_version` (versione iniziale: 1).

**Regole:**

- **Il totale è calcolato, non memorizzato:** `SELECT SUM(BytesFreed) FROM CleanSession`. Una colonna aggiornata a ogni pulizia prima o poi diverge dalle righe e mostra un numero falso; la somma è vera per costruzione e su qualche migliaio di righe è istantanea.
- **Si contano solo i byte effettivamente liberati**, non quelli pianificati. Se 400 MB falliscono per permessi, non entrano nel totale.
- **Timestamp in UTC**, resi in ora locale dall'interfaccia.
- **Il dettaglio per elemento non va in SQLite.** L'elenco completo dei percorsi eliminati finisce in un log per sessione (JSON Lines compresso) in `~/Library/Application Support/mjm.cleaner/logs/`, con conservazione delle ultime 20 sessioni. Con l'eliminazione definitiva è l'unica ricostruzione possibile di cosa sia accaduto.
- **Lo storico non può far fallire la pulizia.** Se la scrittura fallisce, l'esito è "pulizia completata, storico non aggiornato".

## 10. Interfaccia

Finestra unica. **Toolbar fissa** in alto con *Storico*, *Impostazioni* e il contatore cumulativo («159,7 GB liberati»), visibile da ogni passo. Sotto, il wizard.

### Passo 1 — Scegli
Le cinque categorie con casella di selezione, badge di rischio e dimensione dell'ultima rilevazione. NuGet compare come voce annidata e deselezionata. **La selezione viene ricordata fra gli avvii**: è ciò che riduce il costo dei quattro passaggi nella pulizia di routine.

### Passo 2 — Analizza
Barra di avanzamento, percorso corrente, risultati per categoria man mano che arrivano, *Annulla* sempre attivo. Dicitura esplicita: nessun file è stato ancora toccato.

### Passo 3 — Conferma
Albero espandibile **fino ai percorsi**, non ai singoli file: elencare 284.000 voci sarebbe illeggibile e lentissimo da disegnare. Ogni nodo è deselezionabile. Presenti: avviso di irreversibilità, riquadro degli elementi esclusi dal `PathGuard` con motivazione, avviso sulle applicazioni in esecuzione. Il pulsante di conferma riporta il totale: «Elimina 11,3 GB».

### Passo 4 — Fatto
Spazio effettivamente liberato, dettaglio per categoria, elenco espandibile dei file non eliminati con motivo, nuovo totale cumulativo. Pulsanti: *Vedi storico*, *Nuova pulizia*.

### Impostazioni
Root di progetto per `bin`/`obj`; root e soglia per la ricerca file grandi (500 MB); soglie di età per Download (90 giorni), log (30 giorni), NuGet (6 mesi). Persistite in `settings.json` accanto al database.

Interfaccia in italiano, nessuna localizzazione.

## 11. Gestione degli errori

Quattro famiglie, tutte raccolte, nessuna interrompe l'operazione: **accesso negato**, **file in uso**, **file non più esistente**, **directory non vuota**.

L'accesso negato ha un trattamento dedicato: invece di un messaggio generico, l'applicazione indica che manca il Full Disk Access e dove concederlo (*Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco*).

## 12. Strategia di test

- **Unit test del Core su filesystem simulato** (`System.IO.Abstractions`): regole, `PathGuard`, calcolo dimensioni, aggregazioni dello storico. Il caso "la deny-list blocca `~/Documents`" si verifica senza toccare dati reali.
- **Test di integrazione su directory temporanee reali:** symlink, permessi, eliminazione ricorsiva, file bloccati, confronto case-insensitive. Il filesystem simulato non riproduce il comportamento di APFS.
- **Interfaccia:** verifica manuale. Per un'applicazione a uso personale i test automatici su Avalonia costano più di quanto rendano.

Il `PathGuard` si sviluppa in TDD prima di ogni altro componente.

## 13. Spike preliminari

Da eseguire prima del codice di produzione; l'esito può modificare le sezioni 6 e 11.

1. **Full Disk Access:** stabilire quali percorsi lo richiedono realmente e cosa accade al permesso dopo una ricompilazione, dato che macOS lega l'autorizzazione all'identità firmata dell'applicazione. Indizio da chiarire: `~/.Trash` esiste ma non ha risposto al calcolo delle dimensioni da riga di comando.
2. **Bundle `.app`:** `dotnet publish` → `Info.plist` → `codesign` ad-hoc → avvio con doppio clic e riconoscimento da parte di TCC.

## 14. Fuori ambito per la versione 1

Icona nel menu bar, pulizia schedulata, notifiche di sistema, ricerca duplicati, rimozione residui di applicazioni disinstallate, localizzazione, ripristino da Cestino, distribuzione a terzi.
