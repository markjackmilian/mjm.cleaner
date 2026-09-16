# Spike — accessibilità dei percorsi e Full Disk Access

**Data:** 2026-09-16
**Stato:** parziale — misurazione "senza permesso" completata e **riverificata** il 2026-09-16 durante il Task 22 (istruzioni e sorgente della sonda eseguiti alla lettera: vedi §7); misurazione "con permesso" ancora da eseguire manualmente (vedi sezione 4).

## 1. Obiettivo

Prima di scrivere il `PathGuard` e il catalogo delle categorie (Task 7), verificare quali percorsi che `mjm.cleaner` dovrà scandire sono soggetti alla protezione **Full Disk Access (FDA)** di macOS, così da poter mostrare messaggi d'errore e note corrette all'utente quando il permesso manca.

Metodo: una piccola console app usa e getta (`spikes/fda-probe`) che tenta `Directory.EnumerateFileSystemEntries` su ciascun percorso candidato e classifica l'esito (accesso riuscito con/senza elementi, accesso negato, percorso assente, altro errore).

## 2. Come è stata eseguita la sonda

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet new console -n fda-probe -o spikes/fda-probe -f net10.0
# Program.cs sostituito con la versione estesa riportata per intero
# in Appendice A (sezione 4) — non quella minima del brief — perché
# riporta tipo/messaggio dell'eccezione e distingue esplicitamente
# "0 elementi" da "eccezione durante l'enumerazione"
dotnet run --project spikes/fda-probe
```

Il progetto sonda è stato creato, eseguito e poi rimosso (`rm -rf spikes/fda-probe`); non è presente nel repository. Solo questo documento è permanente, come da brief. Il sorgente esatto usato è incorporato per intero in Appendice A (sezione 4), così da poter riprodurre la misurazione senza dover recuperare nulla da altrove.

**Importante — processo host della sonda:** il comando è stato eseguito dalla shell (`/bin/zsh`) lanciata da Claude Code (`claude.app`), **non** da `Terminal.app` o `iTerm2`. Questo è rilevante perché su macOS l'enforcement TCC per le categorie "leggere" (Scrivania, Documenti, Cartella Download — categorie distinte da Full Disk Access, anche se spesso raggruppate colloquialmente sotto lo stesso ombrello) si applica tipicamente alle app con bundle e Info.plist che richiedono l'autorizzazione, mentre gli eseguibili CLI non firmati (come `dotnet run`) spesso non attivano quel prompt. Le poche risorse elencate esplicitamente da Apple sotto la categoria **Full Disk Access** vera e propria (Mail, Messages, Safari, Time Machine, `~/.Trash`, il database TCC stesso, ecc.) restano invece protette indipendentemente dal tipo di processo. Questo spiega perché, di seguito, solo `~/.Trash` risulta negato: **il risultato su `~/.Trash` è affidabile e riproducibile in qualsiasi host**; i risultati "OK" su Download e sugli altri percorsi vanno riverificati quando l'app sarà pacchettizzata come `.app` (vedi nota nella sezione 5).

## 3. Risultati — SENZA Full Disk Access concesso

Eseguito il 2026-09-16, senza aver mai concesso Full Disk Access a `Terminal.app`, `iTerm2` o `claude.app` in *Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco*.

| Percorso | Esito senza permesso | Esito con permesso |
|---|---|---|
| `~/Library/Caches` | OK | *da completare — vedi §4* |
| `/Library/Caches` | OK | *da completare — vedi §4* |
| `~/Library/Logs` | OK | *da completare — vedi §4* |
| `/Library/Logs` | OK | *da completare — vedi §4* |
| `~/Library/Logs/DiagnosticReports` | OK | *da completare — vedi §4* |
| `/Library/Logs/DiagnosticReports` | OK | *da completare — vedi §4* |
| `~/.Trash` | **ACCESSO NEGATO** (`UnauthorizedAccessException`: *"Access to the path '/Users/mjm/.Trash' is denied."*) | *da completare — vedi §4* |
| `~/Downloads` | OK | *da completare — vedi §4* |
| `~/.nuget/packages` | OK | *da completare — vedi §4* |
| `~/.npm` | OK | *da completare — vedi §4* |
| `~/.cache` | OK | *da completare — vedi §4* |
| `$TMPDIR` (`/var/folders/.../T/`) | OK | *da completare — vedi §4* |

**Elenco dei percorsi che risultano richiedere Full Disk Access (misurazione senza permesso):**

- `~/.Trash`

Nessun altro percorso della lista è risultato negato in questa misurazione. Vedi comunque la riserva sulla riproducibilità nella sezione 2 e 5: per i percorsi di sistema (`/Library/Caches`, `/Library/Logs`, `/Library/Logs/DiagnosticReports`) l'accesso osservato è spiegabile con i permessi POSIX standard (vedi tabella sotto), non con una TCC grant — quindi il risultato "OK" è atteso restare stabile anche da un'app pacchettizzata.

### 3.1 Perché `~/.Trash` è negato mentre cartelle simili no

Permessi POSIX osservati (`ls -ld`):

```
drwx------+   3 mjm   staff     ~/.Trash            (proprietario mjm, stesso utente del processo)
drwx------+ 104 mjm   staff     ~/Library/Caches    (proprietario mjm, OK)
drwxrwx---   40 root  _analyticsusers  /Library/Logs/DiagnosticReports  (mjm è nel gruppo _analyticsusers → OK via permessi gruppo)
drwxrwxrwt   11 root  admin     /Library/Caches     (world-writable/sticky → OK per chiunque)
drwxr-xr-x   10 root  wheel     /Library/Logs       (world-readable → OK per chiunque)
```

Il processo gira come `uid=501(mjm)`, lo stesso proprietario di `~/.Trash`, che ha permessi `rwx` per il proprietario: **a livello POSIX l'accesso sarebbe consentito**. Il fatto che l'enumerazione fallisca comunque con `UnauthorizedAccessException` (il comando equivalente `ls -la ~/.Trash` restituisce `Operation not permitted`, cioè `EPERM`, non un errore di permessi file) conferma che il blocco è imposto da **TCC**, non dal filesystem: `~/.Trash` è una delle poche risorse che Apple protegge esplicitamente sotto Full Disk Access indipendentemente dai permessi Unix del proprietario. Questo esclude l'ipotesi "cartella vuota" (vedi sezione 4 del brief e sezione 6 sotto).

## 4. Misurazione CON Full Disk Access — DA COMPLETARE (richiede l'utente)

Questa parte **non è stata eseguita**: concedere Full Disk Access richiede di aprire Impostazioni di Sistema e autenticarsi con la password dell'utente, un'azione che l'agente non può e non deve compiere al posto dell'utente (nessun `sudo`, nessuna modifica diretta del database TCC).

**Istruzioni per l'utente:**

1. Aprire **Impostazioni di Sistema → Privacy e sicurezza → Accesso completo al disco**.
2. Individuare nell'elenco l'applicazione che ha effettivamente eseguito il comando `dotnet run` (verificare quale, perché non è detto sia `Terminal.app`: in questa sessione era `claude.app`/Claude Code — vedi §2). Se l'app non è nell'elenco, aggiungerla con il pulsante **+** puntando al suo `.app` in `/Applications`.

   *Variante con il bundle (preferibile, dal Task 15 in poi):* per misurare il comportamento dell'applicazione reale invece che quello dell'host CLI, aggiungere con **+** il bundle `artifacts/mjm.cleaner.app` prodotto da `./build/bundle.sh`. Non si trova in `/Applications`: nel pannello di scelta file premere <kbd>⌘⇧G</kbd> e incollare il percorso completo della cartella `artifacts` del repository. Vedi §7 per che cosa aspettarsi dopo una ricompilazione.
3. Attivare l'interruttore accanto all'applicazione.
4. **Riavviare completamente l'applicazione** (chiuderla del tutto, non solo la finestra) perché la concessione TCC ha effetto solo sui processi lanciati dopo la modifica.
5. Dalla radice del repository, ricreare la sonda **esattamente** come segue (il progetto non è nel repository per scelta — va sempre creato al bisogno e rimosso dopo l'uso):

   ```bash
   export PATH="/usr/local/share/dotnet:$PATH"
   dotnet new console -n fda-probe -o spikes/fda-probe -f net10.0
   ```

6. Sostituire integralmente il contenuto di `spikes/fda-probe/Program.cs` generato al passo precedente con il seguente (identico a quello usato per la misurazione "senza permesso" in sezione 3 — usare la stessa versione è essenziale perché le due colonne della tabella siano confrontabili):

   ```csharp
   string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
   string tmp = Path.GetTempPath();

   string[] targets =
   [
       Path.Combine(home, "Library/Caches"),
       "/Library/Caches",
       Path.Combine(home, "Library/Logs"),
       "/Library/Logs",
       Path.Combine(home, "Library/Logs/DiagnosticReports"),
       "/Library/Logs/DiagnosticReports",
       Path.Combine(home, ".Trash"),
       Path.Combine(home, "Downloads"),
       Path.Combine(home, ".nuget/packages"),
       Path.Combine(home, ".npm"),
       Path.Combine(home, ".cache"),
       tmp,
   ];

   foreach (string target in targets)
   {
       string status;
       int count = 0;
       try
       {
           foreach (string _ in Directory.EnumerateFileSystemEntries(target))
           {
               count++;
               if (count >= 5) break;
           }
           // Enumeration succeeded without throwing. Distinguish explicitly
           // between "has entries" and "succeeded but zero entries" so that a
           // silently-empty result is never confused with a denied/failed read
           // (relevant for ~/.Trash, see brief note #4).
           status = count > 0 ? "OK" : "OK (enumerazione riuscita, 0 elementi)";
       }
       catch (UnauthorizedAccessException ex)
       {
           status = $"ACCESSO NEGATO ({ex.GetType().Name}: {ex.Message})";
       }
       catch (DirectoryNotFoundException)
       {
           status = "ASSENTE";
       }
       catch (Exception ex)
       {
           // Any other exception (e.g. IOException for EPERM on some macOS
           // paths) is reported with its concrete type and message rather than
           // being folded into a generic bucket, so we can tell a permission
           // failure apart from any other cause.
           status = $"ERRORE: {ex.GetType().Name}: {ex.Message}";
       }

       Console.WriteLine($"{status,-70} {target}");
   }
   ```

7. Riaprire un terminale nella stessa app (dopo il riavvio del passo 4) ed eseguire, dalla radice del repository:

   ```bash
   export PATH="/usr/local/share/dotnet:$PATH"
   dotnet run --project spikes/fda-probe
   ```

8. Riportare qui l'output ottenuto per ciascun percorso, aggiornando la colonna "con permesso" della tabella in sezione 3.
9. Rimuovere di nuovo il progetto sonda prima di qualunque nuovo commit (deve restare fuori dal repository, come da brief):

   ```bash
   rm -rf spikes/fda-probe
   ```

**Aspettativa da verificare:** con FDA concesso, `~/.Trash` dovrebbe passare a `OK`; gli altri percorsi, già `OK` senza il permesso, dovrebbero restare `OK`. Se un qualunque percorso oggi `OK` dovesse risultare diverso con FDA concesso, è un segnale che il risultato "senza permesso" era in realtà già coperto da una grant preesistente per l'app host e va indagato.

## 5. Conseguenze per il Task 7 (catalogo categorie)

- **`trash-downloads-large`** (categoria che include `~/.Trash` e `~/Downloads`): la regola su `~/.Trash` deve gestire esplicitamente `UnauthorizedAccessException` come "richiede Full Disk Access", con un messaggio utente dedicato (non un generico errore di scansione) e un link/nota su come concedere il permesso. Il `ScanErrorKind.AccessDenied` già previsto nel modello di scansione (Task 8/9) è il posto naturale dove intercettarlo.
- **`system-caches`, `logs`**: sulla base di questa misurazione, i relativi percorsi (`Library/Caches`, `Library/Logs`, `DiagnosticReports`, sia utente che di sistema) **non** hanno richiesto FDA in questo ambiente CLI. Va però trattato come risultato **provvisorio**: quando `mjm.cleaner` verrà eseguita come `.app` pacchettizzata (non come `dotnet run` da CLI), l'enforcement TCC potrebbe essere più ampio (le cartelle "leggere" come Download/Desktop/Documenti sono normalmente protette per le app bundle, mentre qui sono risultate accessibili proprio perché il processo host era un binario CLI non firmato). **Raccomandazione:** non eliminare comunque il gestore di `UnauthorizedAccessException` generico da nessuna regola di scansione — trattarlo sempre come possibile, anche per percorsi oggi "OK", e riverificare con questo stesso probe una volta disponibile un build `.app` firmato dell'app reale.
- Il messaggio d'errore/nota utente per FDA deve quindi essere agganciato al `ScanErrorKind.AccessDenied` generico (non a una lista fissa di percorsi), con `~/.Trash` come caso noto e documentato, e menzione che altri percorsi potrebbero richiederlo a seconda di come l'app viene eseguita/pacchettizzata.

## 6. Nota su `du -sh ~/.Trash` (indizio che ha originato lo spike)

Durante la progettazione, `du -sh ~/.Trash` non aveva prodotto output nonostante la cartella esista. Verificato qui:

```
$ du -sh ~/.Trash
du: /Users/mjm/.Trash: Operation not permitted
$ echo $?
1
```

`du` termina con **codice di uscita 1** e stampa l'errore su **stderr** (`Operation not permitted`); se lo stderr non viene osservato (es. redirezione, cattura solo di stdout, o messaggio scorso rapidamente), sembra che il comando "non produca output" — in realtà produce un errore, non un risultato vuoto.

Confrontato con `stat ~/.Trash`, che **riesce** (restituisce i metadati dell'inode della cartella stessa, incluso un "size" di 0 che è la dimensione della entry di directory, non la somma ricorsiva del contenuto) — la cartella esiste ed è raggiungibile a livello di metadata, ma **l'enumerazione del contenuto è bloccata da TCC**.

Nella sonda, per `~/.Trash` l'esito riportato è esplicitamente **`ACCESSO NEGATO (UnauthorizedAccessException: ...)`**, cioè un'eccezione sollevata durante l'enumerazione — non `OK (enumerazione riuscita, 0 elementi)`. Questo distingue in modo inequivocabile le due ipotesi poste dal brief:

- ❌ **non** è una cartella vuota che l'enumerazione legge correttamente restituendo zero elementi;
- ✅ **è** un accesso negato da TCC/Full Disk Access che impedisce del tutto l'enumerazione, coerente con `du`/`ls` che falliscono con `Operation not permitted` (`EPERM`) invece di riportare "0 byte" o una lista vuota.

**Conclusione:** il comportamento di `du -sh ~/.Trash` osservato in fase di progettazione è dovuto ai permessi (Full Disk Access mancante), non a una cartella vuota o inesistente. Il `PathGuard`/scanner di `mjm.cleaner` dovrà trattare questo percorso allo stesso modo: interpretare l'eccezione di accesso negato come "serve Full Disk Access", non come "0 byte da liberare".

## 7. Riverifica del 2026-09-16 (Task 22) — riproducibilità e identità del bundle

### 7.1 Le istruzioni e il sorgente della sonda sono ancora eseguibili alla lettera

Rieseguito l'intero §2/§4 senza modificarne una riga, con .NET SDK **10.0.401**:

```bash
export PATH="/usr/local/share/dotnet:$PATH"
dotnet new console -n fda-probe -o spikes/fda-probe -f net10.0   # OK
# Program.cs sostituito con il sorgente dell'Appendice (§4 passo 6), invariato
dotnet run --project spikes/fda-probe                            # OK, 0 warning
rm -rf spikes/fda-probe
```

Esito: il template `console -f net10.0` esiste ancora, il sorgente compila **senza
alcun warning** anche sotto il `Directory.Build.props` del repository (che imposta
`TreatWarningsAsErrors=true`, quindi un solo warning basterebbe a bloccare la
compilazione), e l'output riproduce **identicamente** la tabella della sezione 3:
unico percorso negato `~/.Trash` con `UnauthorizedAccessException`, tutti gli altri
`OK`. La colonna "senza permesso" è quindi confermata e le istruzioni di §4 non
richiedono correzioni.

### 7.2 Identità di codice del bundle e sopravvivenza della concessione

Il bundle prodotto da `./build/bundle.sh` è firmato **ad hoc** (`codesign --sign -`):

```
Identifier      = com.mjm.cleaner
Signature       = adhoc
TeamIdentifier  = not set
designated      => cdhash H"80b10cd8e158682c812fd582ec41bec695406a1e"
```

Il requisito designato di una firma ad hoc è il **cdhash**, cioè l'impronta del
contenuto sigillato: non un Team ID stabile. TCC àncora la concessione di Accesso
completo al disco a quel requisito, quindi la concessione vale esattamente finché il
cdhash resta lo stesso. Misurato:

| Scenario | cdhash | Conseguenza sulla concessione |
|---|---|---|
| `bundle.sh` eseguito due volte **senza modifiche al sorgente** | `80b10cd8…` → `80b10cd8…` (**identico**) | **sopravvive**: la ricompilazione da sola non la invalida |
| Contenuto del bundle alterato di un solo byte, poi rifirmato ad hoc | `80b10cd8…` → `f5134fa8…` (**diverso**) | **decade**: va riconcessa |

La build è quindi riproducibile bit per bit a sorgente invariato. In pratica: dopo
**qualunque** modifica al codice il cdhash cambia e l'Accesso completo al disco va
riconcesso; una ricompilazione a vuoto non costa nulla. La nota stampata da
`bundle.sh` ("dopo ogni ricompilazione **può** essere necessario riconcedere
l'Accesso completo al disco") è corretta proprio per quel *può*: è necessario solo
quando il sorgente è cambiato.

### 7.3 Gatekeeper

`codesign --verify --deep` dà esito positivo (firma ad hoc valida, 232 file
sigillati), ma `spctl --assess --type execute` risponde `rejected`: è il
comportamento atteso per un bundle non notarizzato e non firmato con un certificato
Developer ID. Compilando in locale il bundle non riceve l'attributo di quarantena,
quindi si avvia normalmente; se venisse copiato da un altro Mac o scaricato,
richiederebbe il primo avvio con **clic destro → Apri**.

### 7.4 Che cosa resta da misurare

Solo la colonna "con permesso" della tabella in §3, che richiede l'azione manuale
descritta in §4 — preferibilmente nella variante col bundle (§4 passo 2), così da
misurare l'applicazione reale e non l'host CLI.
