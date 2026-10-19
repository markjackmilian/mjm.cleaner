# Download e File grandi separati, cartelle escluse, «Seleziona tutte» al passo 3

## Obiettivo e ambito approvato

L'utente ha segnalato tre problemi della pulizia guidata (2026-10-19):

1. Download e file grandi stanno in una sola categoria, `downloads-large`, e al passo 3
   finiscono in un unico gruppo dove le voci si confondono. È pericoloso: fra i file grandi
   comparivano i dischi delle macchine virtuali Parallels, che non vanno cancellati.
2. Non c'è modo di escludere delle cartelle dall'analisi.
3. Al passo 3 non c'è un comando per selezionare o deselezionare tutte le voci di un gruppo.

Cause trovate nel codice:

- `CategoryCatalog` mette `~/Downloads` e le cartelle di `largeFileRoots` nella stessa
  categoria.
- `PathNode.isSelected` parte da `true` per ogni voce, anche per questa categoria ad alto
  rischio. Eppure la sua descrizione dice «Ogni voce va selezionata manualmente», e la spec
  originale (`2026-09-15-mjm-cleaner-design.md` §6.5) dice che le voci «nascono deselezionate
  anche quando la categoria è attiva». Il C# faceva lo stesso, e il porting ha conservato
  l'errore. Per questo i dischi Parallels arrivavano al passo 3 già spuntati.
- In modalità `matchingFiles`, `RuleScanner` scende nei pacchetti macOS (`.pvm`, `.app`,
  `.photoslibrary`, `.logarchive`…) e propone singoli file al loro interno. Lì stanno i dischi
  delle macchine virtuali, e cancellarne uno rompe il pacchetto. `~/Downloads` scende nei
  pacchetti allo stesso modo.
- La casella di gruppo esiste solo nelle pagine Xcode e Docker.

Decisioni dell'utente (2026-10-19):

- **Due categorie**, «Download» e «File grandi», con caselle, descrizioni e gruppi separati.
  Non una pagina dedicata ai file grandi.
- **Al passo 3 le voci di Download e File grandi partono deselezionate.** Le altre categorie,
  Cestino compreso, restano preselezionate: chi sceglie il Cestino vuole svuotarlo.
- **Le cartelle escluse valgono per tutto il wizard**, cioè per ogni categoria della pulizia.
  Le pagine Xcode e Docker restano fuori, perché hanno elenchi e regole propri.
- **Un pacchetto macOS è un'unità**: lo scanner non ci entra mai e lo propone intero, se
  supera età e soglia. Una macchina virtuale diventa una riga deselezionata
  («Windows 11.pvm · 80 GB»); per non vederla più basta escluderne la cartella.
- **Approccio A**: le esclusioni viaggiano nelle regole e le interpreta `RuleScanner`. Il
  `PathGuard` resta la sola deny-list di sistema, che `DenyList` dichiara «non configurabile
  dall'interfaccia: è l'ultima linea di difesa, non una preferenza». Scartati:
  esclusioni nel `PathGuard`, perché mescolano preferenze e protezioni e il guard nasce una
  volta sola all'avvio; filtro a valle in `ScanEngine`, perché lo scanner attraverserebbe
  comunque le cartelle escluse e ne mostrerebbe gli errori di lettura.

Fuori ambito: pagine Xcode e Docker; «seleziona tutto» al passo 1, dove le categorie sono
righe singole; casella di gruppo a tre stati; avviso «nessuna cartella configurata» per File
grandi.

## Catalogo: due categorie al posto di `downloads-large`

`CategoryCatalog.build` sostituisce `downloads-large` con due categorie, in quest'ordine dopo
`trash`:

| | `downloads` | `large-files` |
|---|---|---|
| Nome | «Download» | «File grandi» |
| Descrizione | «File in Download non usati da tempo. Contiene dati reali: nella verifica ogni voce parte deselezionata.» | «File e pacchetti oltre la soglia, nelle cartelle scelte nelle Impostazioni. Contiene dati reali: nella verifica ogni voce parte deselezionata.» |
| Rischio | alto | alto |
| `selectedByDefault` | `false` | `false` |
| `itemsSelectedByDefault` | `false` | `false` |
| Regole | `~/Downloads`, `.matchingFiles`, `minAge` = `downloadsMinAgeDays` (come oggi) | una per ogni voce di `largeFileRoots`, `.matchingFiles`, `minSizeBytes` = `largeFileThresholdBytes` (come oggi) |

`CleanupCategory` riceve il campo `itemsSelectedByDefault: Bool`: lo stato iniziale delle voci
al passo 3. Vale `false` per le due categorie qui sopra e `true` per tutte le altre.

La deduplicazione globale di `ConfirmationRows` tiene la prima occorrenza nell'ordine del
catalogo: se una cartella dei file grandi copre `~/Downloads`, un file abbastanza vecchio
finisce nel gruppo Download.

**Tile** (`CategoryVisuals` e catalogo asset dell'app):

- `downloads`: arancio `#E8833A`, simbolo `arrow.down.to.line`. L'asset `TileDownloadsLarge`
  si rinomina `TileDownloads`, con le stesse varianti chiaro/scuro.
- `large-files`: magenta `#B5477F`, simbolo `scalemass`. Asset nuovo `TileLargeFiles`, con la
  variante scura costruita come quelle esistenti.

**Selezione ricordata.** Se `selectedCategoryIds` contiene `downloads-large`, l'ID viene
ignorato perché non è più nel catalogo, come qualunque ID sconosciuto. Non si trasforma nelle
due categorie nuove: sono ad alto rischio, e l'utente le ri-spunta.

**Storico.** `CategoryNames` aggiunge `downloads-large` → «Download e file grandi» fra gli ID
di versioni precedenti, accanto a `trash-downloads-large`. Le sessioni passate restano leggibili.

## Scanner: cartelle escluse

`CleanupRule` riceve `excludedPaths: [String]`, con valore predefinito `[]`.
`CategoryCatalog.build` lo riempie su **ogni** regola con `settings.excludedFolders`, espanse
con `PathExpander` come le root e senza «/» finale.

Confronto: senza distinzione di maiuscole, con `PathText.isSameOrUnder`, come la deny-list. Il
percorso di un candidato si confronta in due forme: quella testuale (sotto la root dichiarata)
e quella con la root risolta, cioè `canonicalPathValidated` del verdetto di `validateRoot`. Così
una cartella esclusa scritta `/private/var/…` vale anche per la root `$TMPDIR`, che è sotto
`/var`, e viceversa.

Comportamento di `RuleScanner.scan`:

- **Root esclusa.** Se la root della regola è una cartella esclusa o sta sotto una di esse, la
  regola non produce elementi né errori. Lascia una sola esclusione sulla root, con il motivo
  «cartella esclusa nelle Impostazioni». Il controllo avviene dopo `validateRoot`, che serve a
  ottenere la root risolta.
- **Ramo escluso.** In `matchingFiles` e `matchingDirs`, una cartella incontrata nella discesa
  che coincide con un'esclusione viene potata per intero, con una sola esclusione e lo stesso
  motivo. Non si rivelano i nomi dei file al suo interno. Il controllo segue quelli su
  `.git`/`.hg`/`.svn` e sulla deny-list, già presenti.
- **Candidato che contiene un'esclusione.** Una cartella candidata, cioè un figlio in
  `clearContents`, un `bin`/`obj` in `matchingDirs` o un pacchetto in `matchingFiles`, sotto la
  quale sta una cartella esclusa non viene proposta: eliminarla cancellerebbe anche la parte
  esclusa. Lascia un'esclusione con il motivo «contiene una cartella esclusa nelle
  Impostazioni». Il controllo è testuale sui percorsi, non serve attraversare la cartella.
- **Candidato dentro un'esclusione.** In `clearContents` un figlio che coincide con una
  cartella esclusa non viene proposto, con il motivo «cartella esclusa nelle Impostazioni».
  Negli altri modi il caso è già coperto dalla potatura del ramo.

Le esclusioni finiscono in `RuleScanOutcome.exclusions`, quindi nel riquadro già presente al
passo 3 («N elementi esclusi dalle protezioni:», prime cinque righe). L'intestazione non cambia.

## Scanner: pacchetti macOS come unità

`FileSystem` riceve `isPackage(_ path: String) -> Bool`:

- `LocalFileSystem` restituisce `true` se `URLResourceValues.isPackage` è vero, oppure se
  l'estensione, senza distinzione di maiuscole, è `pvm`, `vmwarevm` o `utm`. Il ripiego serve
  perché `.pvm` risulta un pacchetto solo se Parallels Desktop è installato e ne dichiara il
  tipo. Senza Parallels lo scanner tornerebbe a proporre i dischi interni di una macchina
  virtuale copiata o archiviata.
- Il filesystem finto dei test lo legge da un insieme di percorsi dichiarati pacchetti.

Solo in `.matchingFiles` (Download, File grandi, Log), una cartella incontrata nella discesa
che è un pacchetto:

1. passa prima i controlli su `.git`/`.hg`/`.svn`, deny-list ed esclusioni dell'utente, già
   esistenti o descritti sopra;
2. non viene attraversata;
3. diventa un candidato unico: i glob di inclusione ed esclusione si applicano al suo nome; il
   verdetto di `pathGuard.validate` precede ogni lettura di statistiche, come in
   `scanContents`; dimensione e timestamp più recente vengono da `directoryStats`, quindi
   dall'intero albero; si scarta se il timestamp non è determinabile, se non supera `minAge` o
   se il totale è sotto `minSizeBytes`;
4. se passa, è proposto come `ScanItem(isDirectory: true)`. Il motore di pulizia elimina già
   cartelle intere per le voci di `clearContents`.

Effetto voluto anche sui Log: un `.logarchive` in `~/Library/Logs` diventa una voce unica
invece dei file interni. `clearContents` tratta già ogni figlio come un'unità e `matchingDirs`
non scende oltre una cartella trovata, quindi non cambiano. Se la root stessa di una regola è un
pacchetto, la si attraversa come oggi: l'utente l'ha scelta esplicitamente.

## Impostazioni: «Cartelle escluse»

- `CleanerSettings` riceve `excludedFolders: [String] = []`, chiave JSON `ExcludedFolders`,
  letta con `decodeIfPresent`: un `settings.json` esistente senza la chiave si legge con la
  lista vuota.
- `SettingsModel` ricalca le due liste esistenti: `excludedFolders`, `selectedExcludedFolder`,
  `canRemoveExcludedFolder`, `addExcludedFolder() async`, `removeExcludedFolder()`. Il pannello
  di scelta si intitola «Scegli una cartella da escludere» e i duplicati si ignorano con
  `addFolder` (`FeatureText.same`). Salva scrive la lista, Annulla la scarta.
- `SettingsView` aggiunge la sezione «Cartelle escluse» fra «File grandi» ed «Età minima», con
  la stessa `FolderList` a «+/−» e la didascalia «Non vengono mai analizzate né proposte, in
  nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.». Il foglio resta
  700×560, e il `Form` scorre.
- «Salva» chiama già `startOver()`, che ricostruisce il catalogo con `environment.categories()`.
  Le esclusioni valgono dalla scansione successiva, e nessun passo 3 resta calcolato con le
  impostazioni precedenti.

## Passo 3: preselezione e «Seleziona tutte le voci»

- `PathNode` riceve lo stato iniziale nel costruttore. `ConfirmStepModel` lo ricava da
  `itemsSelectedByDefault` della categoria del gruppo, cercata fra `categories` come già fa per
  il nome. Se una categoria non risultasse nel catalogo, caso che oggi non si verifica, le sue
  voci partirebbero deselezionate.
- `CategoryNode` riceve una proprietà calcolata `allSelected: Bool`. In lettura vale vero se il
  gruppo ha voci e sono tutte selezionate; in scrittura imposta `isSelected` di ogni voce. È
  calcolata, quindi non c'è stato da sincronizzare quando cambia una singola casella.
  `CategoryNode` espone anche `itemsStartDeselected: Bool` per la vista.
- `ConfirmStepView`: l'intestazione del `CollapsibleCard`, oggi `EmptyView()`, mostra la
  casella «Seleziona tutte le voci» (`.checkbox`, a due stati come in Xcode e Docker). Per
  VoiceOver l'etichetta è «Seleziona tutte le voci di ‹gruppo›». Se `itemsStartDeselected` è
  vero, sopra la casella compare «Dati reali: le voci partono deselezionate. Spunta solo ciò
  che vuoi eliminare.».
- Invariati: il totale nel sottotitolo e in «Elimina …» conta solo le voci selezionate, e
  `canDelete` resta falso finché non c'è almeno una voce selezionata. Con solo Download scelto
  al passo 1, il passo 3 parte da «0 byte · 0 elementi» con «Elimina» disabilitato. Durante
  l'eliminazione la casella di gruppo si blocca come le altre, con il `.disabled` dello
  `ScrollView`.

## Test

Swift Testing, con il filesystem finto dove non è indicato altro.

- **Catalogo:** ID e ordine nuovi; le due regole e i loro parametri; `excludedPaths` uguale su
  ogni regola di ogni categoria; `itemsSelectedByDefault` falso solo per `downloads` e
  `large-files`.
- **`RuleScanner`, esclusioni:** root esclusa e root sotto un'esclusione; ramo potato in
  `matchingFiles` e `matchingDirs`, con una sola esclusione e nessun elemento dal suo interno;
  candidato di `clearContents` che coincide con un'esclusione o la contiene; `bin` che contiene
  un'esclusione; confronto senza distinzione di maiuscole; root testuale sotto un collegamento
  con l'esclusione scritta sul percorso risolto, e viceversa.
- **`RuleScanner`, pacchetti:** pacchetto non attraversato e proposto intero; dimensione come
  somma dell'albero; età dal timestamp più recente dell'albero; soglia sul totale; glob sul
  nome; un pacchetto negato dal guard non si attraversa per calcolarne le statistiche;
  precedenza di `.git` e della deny-list; pacchetto in un ramo escluso mai proposto.
- **`LocalFileSystem.isPackage`:** su una cartella temporanea reale, `x.app` è un pacchetto,
  `x.pvm` lo è grazie al ripiego, una cartella normale no.
- **Impostazioni:** `settings.json` senza `ExcludedFolders` letto con la lista vuota; andata e
  ritorno su disco; `SettingsModel` aggiunge, ignora i duplicati, rimuove, salva e scarta con
  Annulla.
- **Passo 3:** voci di `downloads` e `large-files` deselezionate e le altre selezionate;
  `allSelected` in lettura (vuoto, misto, tutto) e in scrittura; `canDelete` falso all'inizio
  con solo quelle categorie; `delete()` passa solo le voci spuntate.
- **Storico e tile:** `downloads-large` → «Download e file grandi»; tile delle due categorie.

Revisioni: chi revisiona lo scanner e il passo 3 verifica le garanzie con mutazioni in una copia
scratch. In particolare: un'esclusione ignorata, un candidato che contiene un'esclusione
proposto, un pacchetto attraversato, voci di Download o File grandi preselezionate. Una
mutazione che sopravvive richiede un test nuovo.

## Demo, documentazione e localizzazione

- `DemoData` si adegua: le due categorie al passo 1, un `.pvm` deselezionato fra i File grandi
  al passo 3 e una cartella esclusa nelle Impostazioni demo. Gli screenshot con `-MJMDemo` si
  catturano solo dopo averlo chiesto all'utente.
- README: la riga «Trash, Downloads, and large files» diventa tre righe (Cestino, Download, File
  grandi), e la descrizione delle Impostazioni nomina le cartelle escluse.
- Le frasi nuove sono in italiano con `String(localized:)`, come tutte le altre: il piano di
  localizzazione (`2026-10-19-localization-design.md`) dovrà includerle nella sua tabella. Le
  modifiche non committate ai tre `Localizable.xcstrings` presenti nella cartella di lavoro
  non fanno parte di questo lavoro e non vanno messe in stage.
- A fine piano, il registro decisioni in `docs/superpowers/decisions/`.
