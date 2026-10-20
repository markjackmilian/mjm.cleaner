# Passo 3: voci contenute in una cartella proposta altrove

## Obiettivo e ambito approvato

La revisione finale di `feat/large-files-exclusions` ha registrato un difetto preesistente,
più visibile dopo la separazione di Download e File grandi
(`docs/superpowers/decisions/2026-10-19-registro-decisioni-large-files-exclusions.md`, Minor 1
della revisione finale).

Il passo 3 deduplica le voci solo per percorso identico: `ConfirmationRows.build` tiene la
prima occorrenza nell'ordine del catalogo. Una voce può però stare **sotto** una cartella
proposta da un'altra voce. Con «File grandi» su `~`, `~/.cache/huggingface` compare spuntata
in «Cache di sviluppo», mentre il modello da 4,8 GB che contiene compare deselezionato in «File
grandi». Eliminare la cartella cancella anche il modello, e l'avviso «Dati reali: le voci
partono deselezionate. Spunta solo ciò che vuoi eliminare.» fa credere il contrario. Se
l'utente spunta sia la cartella sia il file, il totale conta due volte gli stessi byte e il
motore registra un errore ENOENT sul file già sparito con la cartella.

Le cartelle che possono contenere voci di altri gruppi sono: i figli di `~/Library/Caches`,
`~/.cache`, `~/.gradle/caches`, `~/.npm/_cacache` e `~/.Trash`, i pacchetti NuGet, le
cartelle `bin` e `obj` e i pacchetti macOS. Di solito la cartella precede la voce nel catalogo,
ma non sempre: dipende da come l'utente configura le cartelle dei progetti e dei file grandi.

Decisioni dell'utente (2026-10-20):

- **Approccio B, «annotare e legare».** La voce contenuta resta nel suo gruppo con la nota
  «Inclusa in …». Finché la cartella che la contiene è spuntata, la sua casella appare spuntata
  e bloccata; se la cartella si deseleziona, la voce torna libera, con il suo stato. Il totale
  e la selezione inviata al motore contano solo le voci libere. Scartati:
  - **A, «assorbire»:** la voce contenuta sparisce dal passo 3. Il file grande non
    comparirebbe più in «File grandi» e, togliendo la cartella, non si potrebbe eliminare da
    solo;
  - **C, «cartella prudente»:** come B, ma una cartella che contiene voci di dati reali parte
    deselezionata. Cambierebbe la pulizia predefinita delle cache.
- **Il contenimento si riconosce sulle root risolte**, come le cancellerà il motore: una root
  che è un collegamento (`~/.cache` → `~/Dati/cache`, con «File grandi» su `~/Dati`) non deve
  sfuggire. Un collegamento verso `/Volumes` non conta: la deny-list nega quella root, e le sue
  voci non si cancellano. Scartati: il confronto solo testuale (il collegamento
  sfugge) e una seconda difesa nel motore (tocca `CleanEngine` senza coprire un caso in più
  quando il passo 3 è corretto).
- La nota sulla riga della cartella («Contiene anche 1 voce di File grandi.») e la riga di
  conteggio sotto l'avviso del gruppo, approvate con la sezione 2 del design.

Fuori ambito:

- una root che cambia destinazione fra l'apertura del passo 3 e «Elimina»: il contenimento
  calcolato può essere superato, ma il motore rivalida ogni percorso prima di cancellarlo;
- le pagine Xcode e Docker, che hanno conferme proprie;
- la canonicalizzazione delle esclusioni nelle Impostazioni, oggetto di un altro lavoro, che
  tocca `ExcludedFolders` e lo scanner, non il passo 3.

## Core: chi contiene chi

### Righe e posizioni

```swift
public struct ConfirmationPosition: Sendable, Equatable, Hashable {
    public let category: Int   // indice nel risultato di build
    public let row: Int        // indice nelle righe di quella categoria
}

public struct ConfirmationRow: Sendable, Equatable {
    public let item: ScanItem
    /// La riga-cartella più vicina che contiene questa voce, in qualunque gruppo; nil se nessuna.
    public let container: ConfirmationPosition?
}

public struct ConfirmationCategory: Sendable, Equatable {
    public let categoryId: String
    public let rows: [ConfirmationRow]
    public var items: [ScanItem] { rows.map(\.item) }
}
```

`items` resta come proprietà calcolata: i test esistenti di `ConfirmationRowsTests` continuano
a leggere `built.flatMap(\.items)`.

### `ConfirmationRows.build(_ results:, resolveRoot:)`

`resolveRoot: (String) -> String` non ha un valore predefinito: chi costruisce le righe deve
dire come si risolvono le root. `build` lo chiama una sola volta per ogni `declaredRoot`
distinta (stringa esatta) e ricorda il risultato.

1. **Chiave di confronto.** Per ogni voce:
   - il percorso si riporta sulla root risolta con `CleanEngine.rewriteToResolvedRoot(path,
     declaredRoot:, resolvedRoot:)`, la stessa funzione che il motore usa prima di validare;
   - si ripiega con il ripiegamento completo delle maiuscole di Foundation
     (`folding(options: [.caseInsensitive], locale: nil)`), come fa APFS: «Straße» e «STRASSE»,
     il segno Kelvin e «k». È più ampio di `PathText.folded`, che segue OrdinalIgnoreCase per il
     guard.

   Le chiavi si confrontano come `String`, cioè per equivalenza canonica: le grafie NFC e NFD
   coincidono senza scomporle a parte (una scomposizione esplicita sarebbe codice che nessun
   test può distinguere).
2. **Deduplicazione** sulla chiave, non più sulla `String` esatta del percorso: resta la prima
   occorrenza nell'ordine dei risultati. `~/Projects/a/bin` e `~/projects/a/bin` diventano una
   riga sola; così anche due grafie che arrivano allo stesso file attraverso un collegamento.
   Un gruppo senza righe non compare, come oggi.
3. **Contenimento.** Si costruisce un dizionario chiave → posizione con le sole righe la cui
   voce ha `isDirectory` vero: cartelle e pacchetti; un file non contiene mai nulla. Per ogni
   riga si risalgono gli antenati della sua chiave, tagliando all'ultima `/` (confine di
   segmento: `/x/cache` non contiene `/x/cacheExtra/f`), e il primo antenato presente nel
   dizionario è il `container`. Un percorso non contiene se stesso: si guardano solo gli
   antenati propri. Il risultato non dipende dall'ordine dei gruppi né da quello delle righe.
   Il costo è lineare nel numero di righe per la profondità dei percorsi.

**Direzione dell'errore.** Riconoscere un contenimento inesistente è sicuro: la voce appare
spuntata e bloccata, non parte, e se la cartella non la conteneva davvero sopravvive.
Riconoscerne uno di meno riproduce il difetto. Per questo il confronto ripiega maiuscole e
grafie anche su un volume che le distinguerebbe, e per lo stesso motivo la deduplicazione per
chiave unisce in quel caso due voci distinte: la seconda non si propone e non si cancella.

### `ConfirmationRows.selections(_ categories:, isSelected:)`

```swift
public static func selections(
    _ categories: [ConfirmationCategory],
    isSelected: (ConfirmationPosition) -> Bool
) -> [CategorySelection]
```

È l'unico punto che decide che cosa riceve `CleanEngine`. Una riga parte se e solo se
`isSelected` è vero per lei e falso per ogni riga della sua catena di `container` (la cartella,
la cartella che contiene la cartella, e così via). Ordine dei gruppi e delle righe invariato; un
gruppo senza righe da inviare non compare.

Invariante: la selezione inviata non contiene mai una voce sotto un'altra voce della stessa
selezione. Quindi niente byte contati due volte e nessun ENOENT su un file già cancellato con
la sua cartella.

### `RootResolving`

```swift
/// Dove si trova davvero la root dichiarata da una regola.
public protocol RootResolving: Sendable {
    func resolvedRoot(_ declaredRoot: String) -> String
}

extension PathGuard: RootResolving {
    /// La root canonica di `validateRoot` (collegamenti degli antenati risolti), anche quando la
    /// root è negata: le voci sotto una root negata non si cancellano comunque. Senza un percorso
    /// canonico, la root dichiarata.
    public func resolvedRoot(_ declaredRoot: String) -> String
}
```

`AppEnvironment` riceve `roots: any RootResolving`, senza valore predefinito. I punti di
costruzione sono tre: `live`, che passa lo stesso `PathGuard` di scanner e motore; la demo, con
un risolutore identità definito nell'app; i doppi dei test di Features, con un risolutore a
mappa. Nessun risolutore identità nel codice di produzione del Core.

`ConfirmStepModel` lo chiama all'apertura del passo 3, sul main actor: con una quindicina di
root sono poche `lstat` e `storedPath`.

## Features: stato delle caselle

### `PathNode`

- `isSelected` resta la scelta della voce stessa.
- Nuovi campi (impostati dal modello dopo aver creato tutti i nodi): `container: PathNode?`, il
  nodo della riga che la contiene, e il nome visualizzato del gruppo di quel nodo.
- `isCovered`: vero se un nodo della catena di `container` è selezionato. È la stessa regola di
  `selections`.
- `isChecked`, ciò che mostra la casella: `isSelected || isCovered`. Quando la voce è coperta la
  casella è bloccata; togliendo la spunta alla cartella la voce torna al suo `isSelected`, cioè
  deselezionata per i dati reali, o com'era prima di essere coperta.
- `containmentText`: vuoto senza `container`; altrimenti
  - coperta: «Inclusa in ‹percorso della cartella› (‹gruppo›): si elimina con la cartella.»;
  - libera: «Inclusa in ‹percorso della cartella› (‹gruppo›).»
- `containsText`, sulla riga della cartella: una frase per ogni gruppo delle voci di cui è il
  `container` diretto, nell'ordine dei gruppi, separate da uno spazio: «Contiene anche 1 voce di
  File grandi.», «Contiene anche 3 voci di Download.». Vuoto se non contiene nulla. Una riga
  intermedia di una catena ha entrambe le note.

### `CategoryNode`

- `allSelected` in lettura: il gruppo ha voci e ogni casella appare spuntata (`isChecked`). In
  scrittura cambia `isSelected` solo delle voci libere (non coperte): una voce coperta non si
  deseleziona dal gruppo, perché la decide la cartella.
- `canSelectAll`: falso se ogni voce del gruppo è coperta; la casella «Seleziona tutte le voci»
  si blocca.
- `coveredText`: vuoto se nessuna voce del gruppo è coperta; altrimenti «1 voce è dentro una
  cartella spuntata e si elimina con quella.» o «‹n› voci sono dentro cartelle spuntate e si
  eliminano con quelle.». Vale in ogni gruppo, non solo in quelli di dati reali.
- `summaryText` invariato: conteggio e dimensione di ciò che è stato trovato nel gruppo.

### `ConfirmStepModel`

- Costruisce le righe con `ConfirmationRows.build(results, resolveRoot:
  environment.roots.resolvedRoot)` e conserva il risultato del Core, allineato per indice ai
  nodi.
- `totalText`, «Elimina …» e `canDelete` contano solo le voci che partono: `isSelected` e non
  `isCovered`. Nell'esempio, con la cache spuntata e il modello coperto: «6,1 GB · 2 elementi».
- `delete()` ottiene la selezione da `ConfirmationRows.selections`, leggendo `isSelected` dai
  nodi. Nel resoconto i byte di una voce coperta finiscono sotto il gruppo della cartella.

## Vista (`ConfirmStepView`)

- `PathRow`: la casella mostra `isChecked`, scrivere imposta `isSelected`; `.disabled` quando
  `isCovered`; `accessibilityHint` uguale a `containmentText`. Sotto il percorso, in
  `.callout` secondario e allineate al testo del percorso, `containmentText` e `containsText`
  quando non sono vuote.
- Intestazione del gruppo: sotto «Dati reali: …» la riga `coveredText` quando non è vuota; la
  casella «Seleziona tutte le voci» `.disabled(!node.canSelectAll)`.
- Invariato il `.disabled(model.isDeleting)` dello `ScrollView`.

## Test

Swift Testing; `swift test -Xswiftc -warnings-as-errors` in `MjmCleanerKit`.

**Core, `ConfirmationRowsTests`** (risolutore finto a mappa):

- contenimento fra gruppi diversi, con la cartella prima e dopo la voce nell'ordine dei gruppi;
- cartella più vicina in una catena A ⊃ B ⊃ C;
- confine di segmento; un file non contiene; un percorso non contiene se stesso;
- maiuscole, «ß»/«SS» e NFC/NFD nella deduplicazione e nel contenimento;
- alias risolto (`~/.cache` → `~/Dati/cache`), due grafie che portano alla stessa cartella e
  risolutore chiamato una volta per root;
- `selections`: voce coperta non inviata anche se selezionata; catena con la cartella esterna
  deselezionata e l'intermedia selezionata; nessuna voce inviata sotto un'altra; gruppi senza
  voci da inviare omessi;
- una posizione di `container` che non esiste: la riga non si invia;
- la garanzia su ogni combinazione di sei righe (una catena di tre, una cartella sorella con un
  file dentro, un file libero; 64 combinazioni): nessuna voce inviata sta sotto un'altra inviata, e ogni voce selezionata è
  inviata o sta sotto una voce inviata;
- i sette test esistenti, invariati nelle asserzioni.

**Core, garanzia completa con `InMemoryFileSystem`:** un vero `PathGuard` con
`FakeLinkInspector(targets:)` (`~/.cache` → `~/Dati/cache`), poi `ConfirmationRows`,
poi `CleanEngine`. Con la cartella deselezionata il modello sopravvive; con la cartella spuntata
e il modello deselezionato il modello sparisce, il resoconto non ha errori e i byte liberati
sono contati una volta; con cartella e modello entrambi spuntati, una sola cancellazione e nessun
ENOENT. Un test di `PathGuard.resolvedRoot` con root consentita, con root sotto un collegamento,
con root negata e con root senza percorso canonico.

**Features, `ConfirmStepModelTests`** (`CleanPerforming` finto che registra la selezione):

- caselle, blocco e note nei due stati della cartella; ritorno allo stato proprio;
- `allSelected` e `canSelectAll` con voci coperte; `coveredText` al singolare e al plurale;
  `containsText`;
- totale senza doppi conteggi;
- un test esaustivo su una catena di tre livelli più una voce libera (16 combinazioni di
  `isSelected`): una voce con la casella vuota non sta mai sotto una voce inviata, e una voce con
  la casella spuntata è inviata o sta sotto una voce inviata.

**Features, `AppEnvironmentTests`:** in `live`, `roots.resolvedRoot` segue un collegamento reale
in una `TemporaryDirectory`.

Revisioni: i revisori del Core e di Features verificano le garanzie con mutazioni in una copia
scratch. Da uccidere almeno: `selections` che ignora la copertura; copertura solo di primo
livello; chiave senza ripiegamento, con `PathText.folded` o senza root risolta; confine di
segmento tolto;
`isDirectory` ignorato; `isCovered` sempre falso; `allSelected` che scrive anche le voci
coperte; risolutore identità in `live`. Una mutazione che sopravvive richiede un test nuovo.

## Demo, documentazione e localizzazione

- `DemoData`: `~/.cache/huggingface` in «Cache di sviluppo» e un modello sotto quella cartella
  in «File grandi»; nelle impostazioni demo «File grandi» guarda `~`, il caso segnalato. Gli screenshot con `-MJMDemo` si catturano solo dopo averlo chiesto
  all'utente.
- README: nella riga «3 · Confirm» della tabella dei passi, una frase in inglese come il resto del
  file: un elemento dentro una cartella spuntata in un altro gruppo è segnato «Included in …» e si
  elimina con quella cartella.
- Le frasi nuove sono in italiano con `String(localized:)`, nel bundle di Features: «Inclusa in
  … (…): si elimina con la cartella.», «Inclusa in … (…).», «Contiene anche … di ….», «voce»,
  «voci», «1 voce è dentro una cartella spuntata e si elimina con quella.», «… voci sono dentro
  cartelle spuntate e si eliminano con quelle.». Il piano di localizzazione dovrà includerle;
  nessun `Localizable.xcstrings` cambia in questo lavoro.
- A fine piano, il registro decisioni in
  `docs/superpowers/decisions/2026-10-20-registro-decisioni-confirmation-containment.md`, con le
  frasi nuove.
