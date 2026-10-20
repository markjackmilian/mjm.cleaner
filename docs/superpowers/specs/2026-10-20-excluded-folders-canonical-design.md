# Cartelle escluse confrontate anche nella grafia del disco

## Obiettivo e ambito approvato

Il branch `feat/large-files-exclusions` (head 273ed4e, non ancora su `main`) ha introdotto le
cartelle escluse nelle Impostazioni, interpretate da `RuleScanner` tramite `ExcludedFolders`
(spec `2026-10-19-large-files-exclusions-design.md`, §«Scanner: cartelle escluse»). Oggi
`ExcludedFolders` confronta un'esclusione solo con il testo del percorso di un elemento: quello
sotto la root dichiarata e quello sotto la root risolta da `validateRoot`, con il ripiegamento
OrdinalIgnoreCase. La revisione finale di quel branch (registro
`2026-10-19-registro-decisioni-large-files-exclusions.md`, Task 2 e Minor 2 finale) ha trovato
tre casi in cui l'esclusione non vale, che è la direzione non sicura:

1. un'esclusione scritta attraverso un collegamento che sta sotto la root, per esempio
   `~/src/collegamento/vecchio` con `~/src/collegamento` → `~/src/archivio`: lo scanner non
   segue i collegamenti e trova la cartella come `~/src/archivio/vecchio`;
2. un'esclusione `/var/…` con una root dichiarata `/private/var/…`: la root non ha
   collegamenti da risolvere, e il testo `/var/…` non coincide con nulla;
3. un'esclusione scritta in un'altra normalizzazione Unicode (NFC/NFD) o con un'equivalenza di
   APFS case-insensitive che OrdinalIgnoreCase non conosce (U+212A per «K», «ß» per «ss»).

Il pannello di scelta restituisce già la grafia del disco, quindi i casi comuni funzionano. I
tre casi nascono da un `settings.json` scritto a mano, da un collegamento creato dopo la scelta
o da una root dichiarata in una grafia diversa da quella delle esclusioni.

Decisioni dell'utente (2026-10-20):

- **Approccio A**: la forma del disco di ogni esclusione si ricava una volta per regola, nello
  scanner, con `FileSystem.storedPath` dell'antenato esistente più profondo, come fa già
  `PathGuard`. Anche la root riceve la sua forma del disco, e gli elementi si confrontano anche
  sotto di essa. Scartati: canonicalizzare al salvataggio nelle Impostazioni, perché non copre
  un collegamento creato dopo, un JSON scritto a mano né una root dichiarata `/private/var`;
  chiedere `storedPath` per ogni elemento, perché costa una `getattrlist` per ogni voce visitata.
- **Un'esclusione che è essa stessa un collegamento vale anche per la sua destinazione
  finale.** `storedPath` non segue l'ultimo componente, quindi senza questa regola resterebbe
  escluso solo il collegamento e la cartella di destinazione verrebbe analizzata.
- **Un'esclusione non verificabile fa sì che la regola non produca nulla**, come «non
  verificabile» vuol dire negare in `PathGuard`. La stessa logica vale per un'esclusione che non
  è un percorso assoluto canonico.

Nello stesso branch entra un test rimasto in sospeso nello stesso registro: l'analisi
abbandonata che termina con `CancellationError` (§«Analisi abbandonata»).

Fuori ambito: le pagine Xcode e Docker, che non usano le esclusioni; il ricontrollo delle
esclusioni al momento della cancellazione (§«Limiti noti»); il pannello delle Impostazioni, che
continua a salvare il percorso che restituisce.

## Forma del disco condivisa: `FileSystem.storedForm`

La risalita che oggi sta in `PathGuard.storedForm` (privata, statica) diventa un'estensione
interna del Core, in un file nuovo `Platform/StoredForm.swift`:

```swift
extension FileSystem {
    func storedForm(_ path: String) -> Result<String, FileSystemError>
}
```

Il comportamento non cambia: `storedPath` dell'antenato esistente più profondo, `path`
compreso, seguito dai componenti che mancano, presi dal testo. Si risale solo con gli errori di
`climbableErrors` (ENOENT, ENOTDIR, EACCES, EPERM), che si spostano con la funzione; ogni altro
errore, o la radice raggiunta senza successo, restituisce il `FileSystemError`; un errore che
non è un `FileSystemError` diventa `EIO` sul percorso dove è avvenuto. `PathGuard` chiama
`fileSystem.storedForm` nei suoi quattro punti (inizializzatore, `validateRoot`, `validate`,
`pruneReason`) con gli stessi motivi di rifiuto di oggi.

## `ExcludedFolders`: forme delle esclusioni e della root

L'inizializzatore `init(_:root:resolvedRoot:)` lascia il posto a una fabbrica:

```swift
static func resolve(
    _ excluded: [String], root: String, resolvedRoot: String,
    fileSystem: any FileSystem, links: any LinkInspecting
) -> Result<ExcludedFolders, ExcludedFolders.Rejection>
```

`Rejection` porta il motivo, già localizzato, per cui la regola non produce nulla. Con
`excluded` vuoto la fabbrica restituisce subito delle esclusioni vuote, senza chiamare
`storedPath`: le regole senza esclusioni non fanno nessuna chiamata in più.

**Forme di un'esclusione**, nell'ordine in cui si calcolano, tutte senza «/» finali:

1. il testo, come oggi: «/» si riduce alla stringa vuota, che sta sopra ogni percorso assoluto,
   quindi escludere la radice esclude tutto;
2. se `CanonicalPath.canonical` del testo è `nil` (percorso relativo, vuoto, con «//», «.» o
   «..», con NUL) la fabbrica rifiuta: §«Errori e frasi»;
3. `storedForm` del percorso canonico; se fallisce, la fabbrica rifiuta;
4. se la forma del disco è un collegamento (`links.isSymbolicLink`), la sua destinazione finale
   (`links.resolveLinkTarget`) e poi la `storedForm` di quella. Una destinazione non
   determinabile vale come `FileSystemError(code: ELOOP, path:)` sulla forma del disco, e porta
   allo stesso rifiuto di un `storedForm` fallito.

**Forme della root**: la root dichiarata, la root risolta (come oggi) e `storedForm` della root
risolta. Se quest'ultima fallisce la fabbrica rifiuta. Una forma alternativa entra solo se non
coincide, senza distinzione di maiuscole, con una forma già presente.

**Forme di un elemento**: il percorso com'è e, per ogni forma alternativa della root, la stessa
forma seguita dal suffisso dell'elemento rispetto alla root dichiarata. È esatto perché lo
scanner raggiunge ogni elemento senza seguire collegamenti e `readdir` restituisce i nomi come
stanno sul disco: sotto la root, la grafia del disco di un elemento è la grafia del disco della
root più il suffisso enumerato.

`excludedReason` e `candidateReason` mantengono firme, motivi e semantica, applicati a tutte le
coppie (forma dell'elemento, forma dell'esclusione): un elemento è escluso se una sua forma
coincide con una forma di un'esclusione o vi sta sotto (`PathText.isSameOrUnder`); un candidato
contiene un'esclusione se una forma di un'esclusione sta sotto una sua forma
(`PathText.hasPrefixIgnoringCase` con «/»). Il ripiegamento resta OrdinalIgnoreCase: sulle forme
del disco le grafie coincidono già byte per byte, e aggiungere forme può solo escludere di più.

## `RuleScanner`

`scan` chiama la fabbrica subito dopo `validateRoot`, con `rootVerdict.canonicalPathValidated`
come root risolta, e prima del controllo sulla root esclusa. Con un rifiuto aggiunge una sola
`GuardExclusion(path: rule.root, reason:)` con il motivo del rifiuto e restituisce l'esito, senza
elementi né errori, come oggi quando la root è esclusa. Il resto non cambia: stessi punti di
controllo in `scanContents`, `scanFiles`, `scanDirectories` e `proposeWholeDirectory`, nello
stesso ordine rispetto al guard e alle statistiche.

## Errori e frasi

| Caso | Motivo sulla root della regola |
|---|---|
| Esclusione non canonica | «cartella esclusa con un percorso non valido: «‹testo›»» (nuova) |
| `storedForm` di un'esclusione o della destinazione fallisce, destinazione non determinabile | «cartella esclusa non verificabile sul filesystem: ‹errore›» (nuova; l'errore contiene il percorso) |
| `storedForm` della root risolta fallisce | «root non verificabile sul filesystem: ‹errore›» (la frase che `PathGuard` ha già) |

Un'esclusione sbagliata svuota ogni regola di ogni categoria, e ogni root mostra il motivo nel
riquadro delle esclusioni al passo 3: è la direzione sicura scelta dall'utente. Il fallimento
della root è in pratica una gara, perché `validateRoot` ha appena calcolato la stessa forma.

## Limiti noti

- Le forme si calcolano all'inizio di ogni regola: un collegamento creato o spostato durante
  l'analisi non si vede.
- Alla cancellazione le esclusioni non si ricontrollano, come oggi: lì decide solo `PathGuard`.
  La finestra fra analisi e conferma è quella che il modello di minaccia già dichiara.
- La destinazione di un'esclusione-collegamento si segue fino alla fine della catena, come fa
  `resolveLinkTarget`; una destinazione fuori dalla root non tocca la regola.

## Test

Swift Testing. Per ogni caso si controllano gli elementi e le esclusioni con i motivi esatti, e
sia l'esclusione diretta sia il caso «contiene».

**Unità**, con `InMemoryFileSystem`. `AliasingFileSystem` simula per `storedPath` i collegamenti
e le equivalenze di APFS; `FakeLinkInspector` simula i collegamenti per scanner e guard.

1. Un'esclusione scritta attraverso un collegamento sotto la root.
2. Una root dichiarata `/private/var/…` con un'esclusione `/var/…`.
3. Le equivalenze, come argomenti: U+212A, NFC sul disco e NFD scritta, NFD sul disco e NFC
   scritta, «ß» per «ss».
4. Una root dichiarata in NFD con il disco e l'esclusione in NFC: serve la forma del disco
   della root.
5. Un'esclusione che è un collegamento verso una cartella sotto la root, e una verso una
   cartella dentro un `bin`.
6. I rifiuti: esclusione relativa, con «//», con «..»; `storedPath` di un'esclusione con EIO;
   collegamento con destinazione non determinabile; `storedForm` della root risolta che fallisce
   solo dopo `validateRoot` (un doppio che fallisce dalla seconda chiamata su quel percorso).
7. Un'esclusione su cui `storedPath` lancia EACCES risale e vale ancora, senza rifiuto.
8. Una regola senza esclusioni non chiede a `storedPath` più di quanto chieda `validateRoot`.

`PathGuardTests` resta invariato e verde: prova che lo spostamento di `storedForm` non cambia il
comportamento del guard.

**Integrazione**, in `Integration/`, con `LocalFileSystem`, `FileSystemLinkInspector` e un
`PathGuard` vero su una cartella temporanea sotto `$TMPDIR` (quindi sotto il collegamento
`/var`): un collegamento reale sotto la root; una root dichiarata nella forma `/private/var/…`
con l'esclusione scritta `/var/…`; un nome NFD creato con `mkdir` ed escluso in NFC; U+212A e
«ß», solo se il volume è case-insensitive; un'esclusione che è un collegamento reale.

**Mutazioni**, provate dai revisori in una copia scratch; ognuna deve far fallire almeno un
test: senza la forma del disco delle esclusioni; senza la forma del disco della root; senza la
destinazione del collegamento; ciascuno dei rifiuti sostituito dal ripiego sul solo testo;
`climbableErrors` alterato; la fabbrica chiamata dopo il controllo sulla root esclusa. Una
mutazione che sopravvive richiede un test nuovo.

## Analisi abbandonata: il ramo dell'annullamento

`ScanStepModel.perform` ha un `guard !abandoned` anche nel ramo `catch is CancellationError`.
Senza, un'analisi abbandonata (Salva nelle Impostazioni) che termina con l'annullamento
chiamerebbe `navigation?.startOver()`: `MainModel.startOver()` abbandonerebbe l'analisi più
recente, che può essere una nuova analisi avviata nel frattempo, e tornerebbe al passo 1. Il
doppio `GatedScan` dei test ignora l'annullamento e restituisce sempre un risultato, quindi il
ramo non è coperto.

Test in `MainModelTests`, con un doppio nuovo: la prima chiamata apre `started`, aspetta il
proprio cancello ignorando l'annullamento, poi lancia `CancellationError` se il task è annullato
e lo registra; le chiamate successive aspettano un secondo cancello. Il test avvia l'analisi A,
salva le Impostazioni (che abbandona A), avvia l'analisi B e solo dopo libera A. Si aspetta che
A abbia lanciato `CancellationError` e che la pagina sia ancora l'analisi B, in corso. Infine
libera B per non lasciare task appesi. La mutazione «senza `guard !abandoned` nel ramo
dell'annullamento» deve far fallire il test.

## Documentazione e localizzazione

- README, paragrafo sulle cartelle escluse: un'esclusione vale anche per la stessa cartella
  raggiunta attraverso un collegamento o scritta in un'altra grafia che il disco considera
  uguale, e un'esclusione non valida o non verificabile ferma ogni regola della pulizia.
- I commenti di `ExcludedFolders` e di `PathGuard` descrivono il nuovo confronto e la funzione
  condivisa.
- Le due frasi nuove sono in italiano con `String(localized:)` nel Core: il piano di
  localizzazione (`2026-10-19-localization-design.md`) dovrà includerle nella sua tabella. I
  `Localizable.xcstrings` non si modificano a mano.
- A fine piano, il registro decisioni in
  `docs/superpowers/decisions/2026-10-20-registro-decisioni-excluded-folders-canonical.md`.
