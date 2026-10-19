# Pagina Docker: l'eliminazione agisce solo sul motore analizzato

## Obiettivo e ambito approvato

La pagina Docker pulisce il motore del contesto attivo della CLI `docker`
(spec `2026-10-19-docker-engines-design.md`). Il contesto però è letto di nuovo a ogni
comando: se cambia fra l'analisi e il clic su «Elimina», `DockerCleanExecutor` lancia
`rmi <id>`, `volume rm <nome>` e `builder prune -f` su un altro motore. Non è un caso
teorico: il 2026-10-19 OrbStack, avviandosi, ha portato da solo il contesto attivo da
`desktop-linux` a `orbstack`. Un volume con lo stesso nome, non in uso sull'altro
motore, verrebbe eliminato lì, e il resoconto nominerebbe il motore dell'analisi, che
in quel caso è sbagliato. La revisione finale di docker-engines l'ha segnalato come
Important e l'ha rinviato a questo lavoro (registro
`2026-10-19-registro-decisioni-docker-engines.md`, Important 2).

L'obiettivo: l'eliminazione agisce solo sul motore che è stato analizzato.

Fatti misurati sul Mac dell'utente il 2026-10-19, con soli comandi di lettura:

- contesti `default` (`unix:///var/run/docker.sock`), `desktop-linux`
  (`~/.docker/run/docker.sock`, Docker Desktop spento) e `orbstack` (attivo);
- `/var/run/docker.sock` è un collegamento a `~/.orbstack/run/docker.sock`, riscritto il
  2026-10-18: lo riscrive il motore avviato per ultimo;
- `docker info` riporta un `ID` stabile del daemon (OrbStack:
  `b2756783-e527-49e3-a6c6-cd7f4e49c9ff`), identico da `orbstack` e da `default`;
- `docker --context desktop-linux info` a Docker Desktop spento esce con «failed to
  connect to the docker API at unix:///Users/…/.docker/run/docker.sock», che
  `DockerCliErrors` riconosce già come daemon non raggiungibile.

Decisioni dell'utente (2026-10-19):

- **Contesto fisso più identità del daemon.** Il contesto si legge all'inizio
  dell'analisi e ogni comando, di analisi e di esecuzione, porta `--context <nome>`.
  All'avvio dell'esecuzione il daemon di quel contesto deve essere lo stesso
  dell'analisi (ID, sistema, versione), altrimenti non si elimina nulla. Le due strade
  da sole non bastano: il solo contesto fisso non copre `default`, il cui collegamento
  cambia motore; il solo ricontrollo prima di `execute` lascia scoperta l'esecuzione,
  che può durare minuti (fino a 600 s per comando) e continua a seguire il contesto
  attivo.
- **Rifiuto mostrato sotto «Elimina».** Se il daemon è cambiato, l'elenco resta com'è e
  il messaggio compare nell'area degli errori di eliminazione; il modello non cambia
  stato, e un nuovo clic viene rifiutato di nuovo.
- **Contesto illeggibile: l'analisi fallisce.** Senza un nome valido non si può fissare
  il contesto, e non si analizza.

Conseguenza voluta: se il contesto attivo cambia ma il motore analizzato è ancora
acceso, «Elimina» pulisce il motore analizzato, cioè ciò che l'utente ha visto e
confermato, e il resoconto lo nomina correttamente. L'app non cambia mai il contesto
dell'utente: `--context` vale per il singolo comando e non scrive
`~/.docker/config.json`.

Fuori ambito: selettore di contesto, avvio o arresto dei motori, controllo dell'identità
prima di ogni singolo comando (vedi «Rischio residuo»), invalidare l'analisi dopo un
rifiuto, nuove schermate o screenshot.

## Identità del daemon

`DockerEngine` (`CleanerCore/Docker/DockerEngine.swift`) aggiunge l'`ID` del daemon:

```swift
public struct DockerEngine: Sendable, Equatable {
    public let kind: DockerEngineKind
    public let displayName: String
    public let operatingSystem: String
    public let serverVersion: String
    /// L'`ID` del daemon riportato da `docker info`; vuoto se il daemon non lo dà.
    public let id: String

    public init(serverVersion: String, operatingSystem: String, id: String = "")
}
```

- `DockerInventoryCollector.engineFormat` legge anche `{{json .ID}}` nella stessa e unica
  chiamata `docker info --format`; `DockerJson.parseEngineInfo` restituisce anche `id`
  (campo assente o `null` → stringa vuota).
- La lettura del motore diventa una funzione statica,
  `DockerInventoryCollector.readEngine(_ cli:)`, come `readDf`: `checkDaemon()` la
  chiama, e l'esecutore la usa senza bisogno di un collettore. La regola della versione
  vuota («daemon non in esecuzione») resta dentro `readEngine`.
- Lo stesso daemon significa `DockerEngine` uguale, con l'uguaglianza sintetizzata: ID,
  sistema, nome e versione. Un aggiornamento del motore fra analisi ed «Elimina» viene
  quindi rifiutato anch'esso, e basta rianalizzare. Con ID vuoti restano a confronto
  sistema e versione.
- Il valore predefinito `id: ""` lascia validi i motori costruiti nei test e nella demo.

## Contesto fisso

Nuovo decoratore interno al Core, in `CleanerCore/Docker/DockerContext.swift`:

```swift
/// Ogni comando va al daemon del contesto `name`, qualunque sia il contesto attivo.
struct DockerContextCli: DockerCommandRunning {
    init(_ base: any DockerCommandRunning, context name: String) throws
    func run(_ arguments: [String], timeout: Duration?) async throws -> ProcessResult
    // base.run(["--context", name] + arguments, timeout: timeout)
}
```

- L'`init` lancia `DockerOutputError("Nome del contesto Docker non valido: «‹nome›».")`
  se il nome non rispetta `^[A-Za-z0-9][A-Za-z0-9_.+-]*$`. Restano fuori, quindi, un
  nome vuoto e un nome che comincia con «-», che non può essere scambiato per
  un'opzione. È l'unico punto di validazione, usato dall'analisi e dall'esecuzione.
- `--context` precede il sottocomando (`docker --context orbstack info …`), come
  richiede la CLI.

Il bersaglio dell'analisi:

```swift
public struct DockerTarget: Sendable, Equatable {
    public let context: DockerContext
    public let engine: DockerEngine
    public init(context: DockerContext, engine: DockerEngine)
}
```

`DockerAnalysis` aggiunge `context: DockerContext`, nel costruttore subito dopo `engine`,
e la proprietà calcolata `target`. `engine` resta: la pagina e il resoconto lo usano già.

## Analisi

`DockerContextReader` aggiunge una lettura che lancia:

```swift
/// Il contesto attivo; «non installato» risale così com'è, ogni altro errore della CLI o
/// dell'output pure.
func readActiveContext() async throws -> DockerContext
/// Il testo per un daemon che non risponde, per un contesto già letto.
func notRunningMessage(for context: DockerContext) -> String
```

`activeContext()` resta e continua a non lanciare (`try?` sulla nuova lettura).

`DockerCleanupService.analyze(_:)`:

1. legge il contesto con `readActiveContext()`. «Docker non installato» risale com'è;
   un `context inspect` fallito o illeggibile fa fallire l'analisi, e la pagina mostra
   «Analisi di Docker non riuscita: docker context inspect: …»;
2. costruisce il collettore fissato, `collector.pinned(to: context.name)`, che lancia
   per un nome non valido. Tutti i comandi dell'analisi (`info`, `ps`,
   `container inspect`, `images`, `image inspect`, `volume ls`, `volume inspect`,
   `system df -v`, `system df`) passano da `--context <nome>`: un cambio di contesto a
   metà analisi non può più mescolare due motori;
3. un daemon che non risponde diventa l'errore che nomina il motore **del contesto letto
   al passo 1** (`notRunningMessage(for:)`), senza rileggerlo;
4. restituisce `DockerAnalysis` con `engine` (dal `checkDaemon()` fissato) e `context`.

Il disco virtuale e la ricerca nei progetti non parlano con Docker e non cambiano.

## Esecuzione

`DockerCleanExecutor.execute(_ selected:, on target: DockerTarget, progress:)` è il punto
in cui vale la garanzia, come le altre regole sul singolo elemento:

1. crea `DockerContextCli(cli, context: target.context.name)`; un nome non valido
   lancia prima di qualunque comando;
2. legge il motore con `readEngine` sulla CLI fissata. Se è diverso da `target.engine`
   lancia `DockerEngineChangedError`, e nessun altro comando parte: né la misura né le
   cancellazioni. Un daemon spento lancia `DockerUnavailableError` come oggi;
3. ogni comando successivo usa la CLI fissata: `system df` prima e dopo, `rmi`,
   `volume rm`, `builder prune -f`;
4. il resto non cambia: il daemon perso a metà dà `daemonLost`, l'annullamento ferma la
   pulizia fra un elemento e l'altro, le voci KEEP e gli identificativi non validi
   vengono rifiutati.

Nuovo errore nel Core:

```swift
/// Il daemon del contesto analizzato non è più quello dell'analisi: non si è eliminato nulla.
public struct DockerEngineChangedError: Error, Equatable, Sendable, LocalizedError {
    public let message: String
    public init(context: String)
    public var errorDescription: String? { message }
}
```

Testo: «Il motore Docker del contesto «‹nome›» non è più quello analizzato: non è stato
eliminato nulla. Premi Riprova per analizzarlo di nuovo.»

`DockerCleanupService.execute(_:on:progress:)` inoltra il bersaglio. Un
`DockerUnavailableError` con motivo `.notRunning` lanciato dall'esecutore arriva prima di
ogni cancellazione, perché il daemon perso a metà finisce nel resoconto: il servizio lo
riscrive con `notRunningMessage(for: target.context)`, per esempio «Docker Desktop non è
in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova.», anche se il contesto
attivo ora è un altro.

## Rischio residuo

Con il contesto `default`, se un altro motore riscrive `/var/run/docker.sock` durante
l'esecuzione, i comandi successivi vanno al nuovo daemon: il controllo dell'identità
copre solo l'avvio. Un controllo prima di ogni comando restringerebbe la finestra senza
chiuderla (Docker non offre un «cancella se il daemon è X») e raddoppierebbe le
chiamate. Resta fuori ambito e va scritto nel registro. I contesti con nome (Docker
Desktop, OrbStack, Colima, Rancher Desktop) hanno un socket proprio e non hanno questa
finestra.

Un motore che riportasse un `ID` diverso a ogni chiamata verrebbe rifiutato sempre. Non
riguarda i motori basati su `dockerd`, il cui ID è persistente; per altri motori
compatibili non è stato verificato.

## Features e demo

- `DockerCleanupServing.execute(_ selected:, on target: DockerTarget, progress:)`.
- `DockerModel` conserva `target` al posto del `engine` privato: il resoconto e
  `measureDisk(for:)` usano `target.engine`. `delete()` passa a `execute` esattamente il
  bersaglio dell'analisi riuscita.
- `DockerModel.delete()` cattura `DockerEngineChangedError` e mette `error.message` in
  `deleteErrorText` così com'è, senza «Pulizia non riuscita:»; non apre il resoconto,
  `isDeleting` torna `false`, elenco e selezione restano.
- Doppi dei test (`FakeDocker`, `SequencedDocker`, `SlowFirstAnalysisDocker`, l'analisi
  di `DockerNavigationSpy`) e demo (`DemoDocker`, `DemoData.dockerAnalysis` con il
  contesto `desktop-linux` di Docker Desktop) si adeguano alle firme. La demo resta su
  Docker Desktop, e nessuno screenshot cambia.

## Testi, README e stringhe

Testi nuovi nel Core, in italiano come gli altri:

- «Il motore Docker del contesto «‹nome›» non è più quello analizzato: non è stato
  eliminato nulla. Premi Riprova per analizzarlo di nuovo.»
- «Nome del contesto Docker non valido: «‹nome›».»

README, sezione Docker: una frase dice che analisi ed eliminazione restano sul contesto
letto all'inizio dell'analisi (`docker --context`) e che, se il daemon di quel contesto
non è più quello analizzato, la pagina non elimina nulla e chiede di analizzare di nuovo.

I tre `Localizable.xcstrings` hanno modifiche locali di Xcode non committate: non si
modificano e non si committano. Le due frasi nuove entreranno nella tabella del piano di
localizzazione.

## Test e verifica

Core (Swift Testing):

- **doppio con due motori**: Docker Desktop (`desktop-linux`) e OrbStack (`orbstack`),
  ciascuno un `FakeDockerCli` con il proprio `info` e un ID diverso, più un contesto
  attivo che il test può cambiare. Ogni comando va al motore del `--context` iniziale,
  tolto il prefisso, oppure al contesto attivo se il prefisso manca; `context inspect`
  risponde con il contesto attivo;
- **test richiesto**: analisi con `desktop-linux` attivo, poi il contesto passa a
  `orbstack`, poi esecuzione di un'immagine, un volume e la cache di build sul
  `target` dell'analisi. OrbStack non riceve alcun comando dopo il cambio; Docker
  Desktop riceve `rmi`, `volume rm` e `builder prune -f`;
- variante: dopo il cambio Docker Desktop è spento → «Docker Desktop non è in
  esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova.», e OrbStack resta
  intatto;
- analisi: il contesto cambia subito dopo `context inspect`, ma ogni comando successivo
  porta `--context desktop-linux` e il motore resta Docker Desktop; un `context inspect`
  fallito fa fallire l'analisi; «non installato» non viene riscritto;
- esecutore: ogni comando comincia con `--context <nome>`; stesso contesto ma daemon con
  un altro ID, a parità di sistema e versione (il caso di `default` riscritto) →
  `DockerEngineChangedError`, e dopo `info` nessun comando; nome non valido (vuoto,
  `-H`, `a b`) → errore senza alcun comando;
- `readEngine`/`checkDaemon`: l'ID si legge; ID assente o `null` → stringa vuota;
- i test esistenti dell'esecutore passano da un doppio che pretende il prefisso
  `--context` e lo toglie, così le attese sulle righe di comando restano quelle di oggi.

Features: `execute` riceve il bersaglio dell'analisi; `DockerEngineChangedError` finisce
in `deleteErrorText` senza prefisso, senza resoconto, con elenco e selezione intatti.

Mutazioni, in una copia scratch, che devono essere uccise da un test:

- l'esecutore usa la CLI non fissata per i comandi distruttivi;
- l'esecutore salta il controllo dell'identità;
- l'identità ignora l'ID (confronta solo sistema e versione);
- l'analisi usa il collettore non fissato;
- `DockerContextCli` non valida il nome;
- il servizio riscrive «non in esecuzione» rileggendo il contesto attivo;
- `DockerModel` passa a `execute` un bersaglio diverso da quello dell'analisi.

Verifica finale:

- suite completa del package, `(cd MjmCleanerKit && swift test -Xswiftc
  -warnings-as-errors)`, a partire da 553 + 178 test;
- build dell'app con `xcodebuild`, perché `DemoServices` implementa il protocollo;
- prova dal vivo in sola lettura: `docker --context <attivo> info --format
  <engineFormat>` restituisce un `ID` non vuoto che il parser legge. Nessun comando
  distruttivo, nessun cambio di contesto, l'app non si avvia.

L'esecuzione avviene nel worktree `.claude/worktrees/docker-delete-guard`, sul branch
`feat/docker-delete-guard` da `main` (a20f74e). Nessun push.
