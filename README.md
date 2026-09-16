# mjm.cleaner

Applicazione macOS per eliminare file temporanei rigenerabili, con anteprima
obbligatoria, storico delle pulizie e contatore cumulativo dello spazio liberato.

L'app non decide mai da sola: ogni elemento viene prima elencato, con percorso
esatto e dimensione, e solo dopo una conferma esplicita viene eliminato. Un
`PathGuard` non configurabile rifiuta comunque i percorsi protetti, anche se una
cartella di progetto mal configurata dovesse puntarci contro.

## Requisiti

- macOS 13 o successivo
- .NET 10 SDK — su questa macchina è installato in `/usr/local/share/dotnet` e
  **non è nel `PATH`**: ogni comando `dotnet` va preceduto da

  ```bash
  export PATH="/usr/local/share/dotnet:$PATH"
  ```

  (`build/bundle.sh` lo fa già al proprio interno.)

## Sviluppo

```bash
export PATH="/usr/local/share/dotnet:$PATH"

dotnet build                             # compila soluzione e test
dotnet test                              # suite completa (262 test)
dotnet run --project src/MjmCleaner.App  # avvio in sviluppo
./build/bundle.sh                        # crea artifacts/mjm.cleaner.app
open artifacts/mjm.cleaner.app           # avvia il bundle
```

Il bundle è **firmato ad hoc** (`codesign --sign -`): senza firma macOS si
rifiuterebbe di avviarlo. Non essendo notarizzato, `spctl` lo rifiuta: compilato
in locale parte comunque, ma se venisse copiato da un altro Mac andrebbe aperto
la prima volta con **clic destro → Apri**.

## Come funziona

Wizard a quattro passi, sempre nello stesso ordine:

| Passo | Cosa fa |
|---|---|
| **1 · Scegli** | Si selezionano le categorie da pulire. Ognuna dichiara il proprio livello di rischio; quelle ad alto rischio non sono mai preselezionate. |
| **2 · Analizza** | Scansione in sola lettura, categorie in parallelo. Non elimina nulla. |
| **3 · Conferma** | Anteprima obbligatoria: percorsi esatti, dimensioni, avviso sulle app aperte e riquadro delle esclusioni decise dal `PathGuard`. È l'ultimo punto in cui si può tornare indietro. |
| **4 · Fatto** | Riepilogo dello spazio liberato e degli elementi che non è stato possibile eliminare. |

Nella barra strumenti, **Storico** mostra le pulizie precedenti e il totale
cumulativo liberato; **Impostazioni** permette di configurare le cartelle di
progetto in cui cercare `bin` e `obj`, le cartelle in cui cercare i file grandi,
la soglia dei file grandi e le età minime di Download, log e pacchetti NuGet.

### Categorie

- **Cache utente e di sistema** — `~/Library/Caches`, `/Library/Caches`, `$TMPDIR`
- **Cache di sviluppo** — npm, Xcode (DerivedData, Archives), Gradle, `~/.cache`
  - **Pacchetti NuGet inutilizzati** (sottocategoria, non preselezionata)
- **Cartelle bin e obj nei progetti** — solo se accanto alla cartella c'è un file
  di progetto (`.csproj`, `.sln`, …)
- **Log e crash report** — `~/Library/Logs`, `/Library/Logs`
- **Cestino, Download e file grandi** — rischio alto, mai preselezionata

## Storico e log

Tutto vive sotto `~/Library/Application Support/mjm.cleaner/`:

| File | Contenuto |
|---|---|
| `history.db` | SQLite: una riga per sessione di pulizia, con durata, byte liberati, elementi eliminati e falliti. Alimenta lo storico e il contatore cumulativo. |
| `settings.json` | Le impostazioni modificabili dalla pagina *Impostazioni*. |
| `logs/session-NNNNNN.jsonl.gz` | Elenco completo dei percorsi eliminati, una riga JSON per elemento, compresso. Ne vengono conservate le ultime **20** sessioni; le più vecchie sono rimosse automaticamente. |

I percorsi eliminati non finiscono in SQLite di proposito: una pulizia delle
cache tocca centinaia di migliaia di file e il database crescerebbe più in fretta
dello spazio liberato.

Questa cartella è sotto `~/Library/Application Support`, che la deny-list
protegge: **l'applicazione non può eliminare il proprio storico**.

## Avvertenze

- **L'eliminazione è definitiva:** i file non passano dal Cestino e non sono
  recuperabili. L'anteprima del passo 3 elenca i percorsi esatti; il `PathGuard`
  blocca comunque i percorsi protetti (`/System`, `/usr`, `/bin`, `/sbin`,
  `/Applications`, `/Volumes`, `~/Documents`, `~/.ssh`, `~/Library/Keychains`, …)
  e non è configurabile dall'interfaccia: è l'ultima linea di difesa, non una
  preferenza. Una cartella di progetto impostata su `/` viene rifiutata in blocco
  e non produce alcun candidato.
- **Full Disk Access — serve solo per il Cestino:** l'unico percorso che, alla
  misurazione dello spike, lo richiede è `~/.Trash`; tutte le altre categorie
  funzionano senza. Un accesso negato viene comunque sempre gestito e riportato,
  per qualsiasi percorso, non solo per quelli noti. Se serve,
  concederlo al bundle in *Impostazioni di Sistema → Privacy e sicurezza →
  Accesso completo al disco* aggiungendo `artifacts/mjm.cleaner.app` con il
  pulsante **+** (<kbd>⌘⇧G</kbd> per incollare il percorso). Essendo la firma ad
  hoc, la concessione è legata all'impronta del bundle: **dopo una modifica al
  codice va riconcessa**, mentre una ricompilazione a sorgente invariato la
  conserva.
- **Nessuna elevazione di privilegi:** l'app non usa mai `sudo` e non chiede la
  password. Gli elementi di proprietà di `root` falliscono con accesso negato e
  compaiono nel riepilogo finale del passo 4.
- **Docker non viene toccato:** `~/Library/Containers/com.docker.docker` e
  `~/.docker` sono nella deny-list. Lo spazio delle immagini e dei volumi si
  recupera con `docker system prune`.

## Documentazione

- Specifica: `docs/superpowers/specs/2026-09-15-mjm-cleaner-design.md`
- Piano di implementazione: `docs/superpowers/plans/2026-09-15-mjm-cleaner.md`
- Spike sul Full Disk Access: `docs/superpowers/spikes/2026-09-15-full-disk-access.md`
