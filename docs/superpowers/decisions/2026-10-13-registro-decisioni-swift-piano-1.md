# SDD ledger — plan: docs/superpowers/plans/2026-10-13-swift-port-1-core.md

Spec: docs/superpowers/specs/2026-10-13-swift-native-port-design.md (raggiungibile, autorità vincolante).
Workspace: in place su feat/swift-port (scelta dell'utente, nessun worktree). Branch base: 291a080.
Baseline: nessun codice Swift ancora; il C# non viene toccato da questo piano.

## Pre-flight scan

Evidenza di partenza: durante la stesura ogni blocco di codice del piano è stato estratto in un package
usa e getta (scratchpad/plancheck) e compilato con `-warnings-as-errors`: 230 test verdi, conteggi per
task tutti uguali agli "Expected" del piano (verificato filtro per filtro).

### Coppie di task che condividono file o interfacce

| Task A → Task B | Prodotto da A | Consumato da B | Esito |
|---|---|---|---|
| 1 → tutti | Package.swift, PathText, SimpleGlob, CZlib, Localizable.xcstrings | import CleanerCore, PathText.*, SimpleGlob.matches | coerente (compila) |
| 1 → tutti | registro di parità docs/superpowers/porting/2026-10-13-parity.md | ogni task aggiorna le proprie righe | coerente; righe pre-create in Task 1 |
| 2 → 3 | FileSystem, FileSystemError, FileItemInfo, LinkInspecting, WallClock | InMemoryFileSystem, ForwardingFileSystem, FakeLinkInspector, FixedWallClock | coerente |
| 2 → 10,11,12,14 | TemporaryDirectory (Tests/Support) | test di integrazione | coerente |
| 3 → 8 | TestSupport.swift creato | Task 8 vi aggiunge Recorder + `import Synchronization` | coerente (estrazione con append verificata) |
| 4 → 7,8,9,14 | PathGuarding, PathGuard(denyList:links:homeDirectory:), DenyList(homeDirectory:) | RuleScanner, CleanEngine, test | coerente |
| 5 → 6 | CleanerSettings (campi var) | CategoryCatalog.build | coerente |
| 6 → 7,8 | CleanupRule(_:_:include:exclude:minAge:minSizeBytes:maxDepth:requiresProjectMarker:), CleanupCategory | scanner e test | ordine dei parametri verificato in ogni chiamata |
| 7 → 8,9 | RuleScanner, ScanItem, ScanError, RuleScanner.describe (internal) | ScanEngine, CleanEngine | coerente |
| 8 → 9 | Recorder | CleanEngineTests | coerente (8 precede 9) |
| 9 → 10,11 | CleanReport, CategoryCleanResult, DeletionRecording | HistoryStore, SessionLogWriter, PendingJournal | coerente |
| 12 → 13 | ProcessRunning + estensione run(_:_:timeout:), ProcessResult, ProcessLaunchError | RunningAppsProbe e FakeProcessRunner | coerente |
| 1–13 → 14 | intero modulo | RealFileSystemCleanupTests | coerente |

### Coerenza interna di ciascun task

| Task | Test specificati vs codice specificato | File creati vs toccati dopo | Esito |
|---|---|---|---|
| 1 | 8 test / PathText+SimpleGlob | crea package e registro | coerente |
| 2 | 19 test / FileSystem+LocalFileSystem+LinkInspector | crea TemporaryDirectory poi riusato | coerente |
| 3 | 6 test / doppi | TestSupport poi esteso da 8 | coerente |
| 4 | 56 test / Safety | — | coerente |
| 5 | 10 test / Settings | — | coerente |
| 6 | 17 test / Categories | — | coerente |
| 7 | 38 test / RuleScanner | — | coerente |
| 8 | 6 test / ScanEngine | modifica TestSupport | coerente |
| 9 | 26 test / CleanEngine+ConfirmationRows | — | coerente |
| 10 | 6 test / SQLite+HistoryStore | — | coerente |
| 11 | 14 test / Gzip+SessionLogWriter+PendingJournal | — | coerente |
| 12 | 6 test / ProcessRunner | — | coerente |
| 13 | 14 test / RunningAppsProbe | nota di ripiego su Result non-Sendable | ripiego non necessario (compila) |
| 14 | 4 test + suite completa + grep vincoli | aggiorna registro | coerente |

### Punti che la rubrica di review potrebbe trattare come difetti

- Helper `create(...)` ripetuti nei file di test (RuleScannerTests, MatchingDirsTests, CleanEngineTests, ScanEngineTests): duplicazione di 5–8 righe di fixture, presente anche nel C#.
- `LocalFileSystem`/`ProcessRunner` indicizzano array di pipe a 2 elementi (`outPipe[1]`).

### Rulings pre-flight

Ruling: la nota di ripiego del Task 13 (enum PsFailure se Result non è Sendable) non si applica — `any Error` è Sendable in Swift 6 e il test compila così com'è (verificato) — se sbagliato costa un test parametrico da riscrivere.
Ruling: gli indici fissi `outPipe[0]/[1]` su array creati con 2 elementi contano come "verificati per costruzione" rispetto al vincolo globale sugli accessi per indice — l'alternativa (tuple o pipe wrapper) aggiunge codice senza ridurre rischi — se sbagliato costa una piccola riscrittura in ProcessRunner.
Ruling: le fixture `create(...)` duplicate fra file di test restano locali a ciascun file, come nei test C# portati 1:1 — un helper condiviso cambierebbe la forma dei test rispetto al registro di parità — se sbagliato costa un refactoring dei test.

## Modelli

Implementatori: haiku (il piano contiene il codice completo: trascrizione + test). Revisori: sonnet; opus per i task in cui un difetto è perdita di dati (4 Safety, 7 RuleScanner, 9 CleanEngine). Review finale: opus.

## Avanzamento
Task 1: dispatched (base 291a080, implementer haiku ae3584dfab42c1f9a)
Task 1: implementer DONE_WITH_CONCERNS (a85099b). Ruling: la RED attesa del Task 1 ("cannot find 'PathText'") non si ottiene senza un sorgente nel target, perché SwiftPM fallisce prima al caricamento del package; l'implementatore l'ha verificata con un segnaposto temporaneo — accettato, nessun effetto sui task successivi che trovano sorgenti già presenti — se sbagliato costa solo una nota nel piano. Ruling: il trailer resta "Claude Opus 5.5" come da attribuzione della sessione e del piano — se sbagliato costa un amend locale.
Task 1: review (sonnet) — spec ❌ su 2 Important plan-mandated: SimpleGlob con `*` letterale nel nome; PathText.parent con barre ripetute. Minor: normalize scarta il "/" finale che GetFullPath conserva (doc impreciso); SimpleGlob su Character invece che unità UTF-16; lacune di test.
Ruling: correggere SimpleGlob (ramo `*` valutato per primo) e PathText.parent (algoritmo di GetDirectoryNameOffset: taglio all'ultimo separatore, rimozione dei separatori consecutivi che lo precedono, compressione dei separatori ripetuti) — la spec §5.3 impone l'equivalenza con .NET e il costo è locale a due funzioni pure — se sbagliato costa un ripristino di due funzioni.
Ruling: nello stesso giro, poiché tocca le stesse funzioni, SimpleGlob lavora su unità UTF-16 (come .NET: `?` = un'unità, confronto ordinale) e il commento di `normalize` dichiara che il "/" finale di GetFullPath non viene conservato (l'unico consumatore, PathGuard, lo rimuove comunque) — allinea il codice alla spec senza cambiare firme — se sbagliato costa una riga di doc e la scelta Character/UTF-16.
Ruling: il testo del Task 1 nel piano resta com'è (task completato); la correzione vive nel codice e in questo ledger.
Task 1: fix round 1/5 dispatched (resume implementer) — commit 1b3f648; re-review in corso (sonnet).
Nota operativa: l'implementatore haiku rifiuta di scrivere file .md di report per le proprie regole interne; il controller salva il report dalla consegna. Nei prossimi dispatch: chiedere il report completo nella consegna.
Task 1: minor (deferred): lacune di test su caratteri non ASCII nel case folding ("È"/"è"); doc di isSameOrUnder sul requisito di ancestor senza "/" finale.
Task 1: fix round 1/5 (2 addressed, 0 open; commits a85099b..1b3f648)
Task 1: minor (deferred): SimpleGlob fa lowercased() sull'intera stringa prima delle unità UTF-16; per pochi caratteri (es. "İ") la lunghezza cambia e il conteggio di `?` può differire da .NET.
Task 1: minor (deferred): fileName/join/trimmingTrailingSlashes lavorano su Character, parent su unità UTF-16: un "/" seguito da un segno combinante può farle divergere.
Task 1: complete (commits 291a080..1b3f648, review clean after fix round 1)
Task 2: dispatched (base 1b3f648)
Task 2: implementer haiku a17246ec6299d8e90 (report task-2-report.txt)
Task 2: implementer DONE_WITH_CONCERNS (7024d55) — note: tmp file residuo se writeAll fallisce; readData su cartella → EIO; deleteDirectoryRecursively su file → ENOTDIR
Task 2: review (sonnet) — spec ❌: 1 Important plan-mandated (deleteDirectoryRecursively("<link>/") segue il collegamento e svuota la destinazione: riprodotto dal revisore). ⚠️ itemInfo lancia ENOENT dove .NET dà la sentinella: risolto dal design dei Task 7 (accept/readDirectoryStamp trattano ENOENT come sentinella) — verificato nel testo del piano.
Ruling: deleteDirectoryRecursively rimuove i "/" finali prima di lstat (la radice "/" resta "/") e un test copre il collegamento passato con "/" finale — è il primitivo di cancellazione e la garanzia "mai la destinazione" non può dipendere dai chiamanti — se sbagliato costa una riga.
Ruling: promosso da Minor a Important l'errno in contentsOfDirectory: azzerarlo immediatamente prima di ogni readdir — un errno sporco dopo una chiamata di libreria nel ciclo farebbe saltare in silenzio un'intera cartella (scansione e cancellazione) — se sbagliato costa una riga.
Task 2: minor (deferred): writeData lascia il .tmp-UUID se writeAll fallisce; l'errore riporta il percorso temporaneo; nessun fsync.
Task 2: minor (deferred): writeData su un collegamento sostituisce il collegamento invece di scrivere attraverso (.NET scrive attraverso) — da annotare nel registro.
Task 2: minor (deferred): readData sostituisce l'errno reale con EIO (directory → EIO invece di EISDIR).
Task 2: minor (deferred): readText conserva il BOM UTF-8 (.NET ReadAllText lo toglie).
Task 2: minor (deferred): resolveLinkTarget: catena di esattamente 32 collegamenti → nil (off-by-one); percorso relativo risolto contro "/".
Task 2: minor (deferred): doc "ordine ordinale" impreciso (String.sorted non è ordinale UTF-16).
Task 2: minor (deferred): race lstat/opendir in deleteDirectoryRecursively (stessa finestra di .NET).
Task 2: minor (deferred): TemporaryDirectory.remove usa chmod che segue i collegamenti; test EACCES fallisce da root.
Task 2: minor (deferred): lacune di copertura (newestStamp, lastAccess, readData/appendData errori, deleteDirectoryRecursively su percorso mancante o file, filtro di "."/"..", SystemWallClock, FileSystemError.description).
Ruling: accettata la deviazione dell'implementatore dal mio ruling del fix round 1 — "" NON diventa "/" (solo un input di sole "/" diventa "/"), perché "" → "/" avrebbe cancellato la radice; "" continua a fallire con ENOENT — il mio ruling era difettoso — se sbagliato costa nulla (comportamento più restrittivo).
Nota: "/." e "/.." finali risolvono ancora attraverso un collegamento in LocalFileSystem; li respinge CanonicalPath nel PathGuard prima di ogni cancellazione (Task 4/9).
Task 2: fix round 1/5 (2 addressed, 0 open; commits 7024d55..6718287)
Task 2: minor (deferred): nessun test fissa che deleteDirectoryRecursively("") fallisca con ENOENT invece di diventare "/".
Task 2: complete (commits 1b3f648..6718287, review clean after fix round 1)
Task 3: dispatched (base 6718287)
Task 3: implementer haiku ab67f4fa71387eefa (report task-3-report.txt)
Task 3: implementer DONE_WITH_CONCERNS (7ae27f2) — note: setTimes su percorso mancante è no-op silenzioso; commento VanishingFileSystem anticipa RuleScanner
Task 3: review (sonnet) — spec ✅, quality Approved. ⚠️ commento di VanishingFileSystem sull'ENOENT come sentinella: da verificare alla review del Task 7 (RuleScanner), dove il piano tratta ENOENT come sentinella in accept/readDirectoryStamp.
Task 3: minor (deferred): VanishingFileSystem più severo del C# (lancia su ogni stat, C# solo su Length): con una regola MinAge l'errore cadrebbe al controllo di età; i test C# che lo usano hanno regole "*" senza età.
Task 3: minor (deferred): nessun test diretto per decoratori, FakeLinkInspector (String??), utc, days, cancelCurrentTask.
Task 3: minor (deferred): no-op silenziosi nei builder (setTimes su percorso mancante, addDirectory su file, ensureParents non verifica che l'antenato sia cartella, addFile su cartella orfana i figli).
Task 3: minor (deferred): FakeLinkInspector normalizza le chiavi alla costruzione (C# solo in lettura) e usa lowercased invece di OrdinalIgnoreCase.
Task 3: minor (deferred): utc() ripiega su .distantPast con componenti non valide; @unchecked Sendable non commentato su ForwardingFileSystem e ridondante nelle sottoclassi; contentsOfDirectory O(n).
Task 3: complete (commits 6718287..7ae27f2, review clean)
Task 4: dispatched (base 7ae27f2)
Task 4: implementer haiku a8d6e302ade521e61 (report task-4-report.txt)
Task 4: implementer DONE_WITH_CONCERNS (7f5337a) — commenti C# completi al posto di due versioni condensate (solo commenti)
Task 4: review (opus) — spec ❌. Critical 1 (plan-mandated): CanonicalPath confronta grafemi Swift; uno scalare Prepend (U+0600) o un segno combinante fuso con "/" nasconde "/../": 5 input permessi da Swift e negati dal C# (verificato con sonde Swift e C#). Critical 2 (plan-mandated): .caseInsensitive di Foundation ripiega ß→ss e legature, cambiando la lunghezza; il limite del passo 5 per lunghezza UTF-16 salta un antenato collegato (sonda reale: elemento sotto collegamento permesso). Important 1 (plan-mandated): suffisso in resolveSymlinkedAncestors tagliato per Character, perde il "/" dopo uno scalare Prepend (validateRoot risolve in ".../LibraryPreferences" e permette). Minor: isHomeOrDirectChild su Character; commenti di sicurezza accorciati; catalogo stringhe vuoto; nessun test Unicode specifico.
Ruling: tutte le operazioni testuali sui percorsi lavorano su byte UTF-8 (separatore e punti sono ASCII, quindi l'esito coincide col confronto per unità UTF-16 del C#) e il confronto senza maiuscole usa un ripiegamento per scalare con la sola maiuscola a scalare singolo (semantica OrdinalIgnoreCase, lunghezza invariata: ß resta ß, le legature restano tali), con percorso rapido ASCII. Si riscrivono PathText (fileName, join, trimmingTrailingSlashes, normalize, equalsIgnoringCase, hasPrefixIgnoringCase; parent è già per unità UTF-16), CanonicalPath (controlli sui byte), SimpleGlob (stesso ripiegamento, poi unità UTF-16), e in PathGuard: limite del passo 5 per prefisso semantico (hasPrefixIgnoringCase(current, root + "/")) invece che per lunghezza, suffisso per byte UTF-8, isHomeOrDirectChild per scalari; DenyList.init controlla "/" iniziale sul byte. Test solo-Swift per ogni sonda del revisore — la spec §5.3/§5.4 impone l'equivalenza con OrdinalIgnoreCase e con il rifiuto dei non canonici, e un difetto qui è perdita di dati — se sbagliato costa la riscrittura di due file di utilità.
Ruling: i commenti di sicurezza accorciati dal piano (DenyList Xcode/UserData, PathGuard passo 6, limite delle sostituzioni, doc di recursiveDeniedReason) tornano al testo C# completo — spec §5.1 lo impone — costo nullo.
Ruling: da portare nei dispatch successivi: Task 6 PathExpander controlla "~/" e "/" sui byte UTF-8 e taglia per byte; Task 9 CleanEngine.rewriteToResolvedRoot taglia il prefisso per byte UTF-8 (dropFirst(declaredRoot.utf8.count)), non per Character.
Task 4: minor (deferred): Localizable.xcstrings vuoto (i motivi ricadono sulla chiave italiana, comportamento voluto dalla spec in fase 1).
Task 4: fix round 1 consegnato (494892c): 16 issue RED sui nuovi test solo-Swift col codice vecchio; suite completa 96/96.
Task 4: minor (deferred): LinkInspecting.swift:35 e LocalFileSystem.swift:81 usano ancora hasPrefix("/") sui Character — innocui oggi (join byte-level restituisce comunque la destinazione assoluta; il ramo "/" di deleteDirectoryRecursively scatta solo con byte tutti "/"), da allineare per coerenza.
Task 4: minor (deferred): altri commenti Swift ancora condensati rispetto al C# oltre ai quattro ripristinati.
Task 4: fix round 1/5 (4 addressed, 1 new open — Critical: fold rende ı (U+0131) uguale a I: fuga dal contenimento via ~/Lıbrary/Caches e aggiramento della regola "/Users altro utente"; confronto esaustivo con .NET OIC: 27 equivalenze solo-Swift (ı, ſ, U+16EBB–16ED3) e 27 solo-.NET (coppie greche con ypogegrammeni); commits 7f5337a..494892c)
Ruling: fold = ASCII rapido; ı (U+0131), ſ (U+017F) e il blocco U+16EA0–U+16EDF restano invariati; altrimenti maiuscola a scalare singolo, altrimenti titlecase a scalare singolo (recupera le coppie greche, come la mappatura semplice di .NET), altrimenti invariato — principio: il ripiegamento non deve mai equiparare due scalari che .NET OIC distingue (sarebbe più permissivo sul contenimento); perdere un'equivalenza di .NET è il lato sicuro (nega di più) — se sbagliato costa un altro giro su una funzione di 15 righe.
Ruling: nello stesso giro FakeLinkInspector usa PathText.folded per le chiavi (come il dizionario OrdinalIgnoreCase del C#); LinkInspecting.swift e LocalFileSystem.swift controllano "/" iniziale sul byte (chiude la classe di difetti); commento a riga lunga del passo 5 andato a capo e `root + "/"` calcolato una volta — costo minimo.
Ruling: la re-review rilancia il confronto esaustivo con .NET OIC già pronto nella scratchpad (foldprobe/netprobe2) sul nuovo ripiegamento.
Task 4: minor (deferred): SimpleGlob con lo stesso ripiegamento diverge da ToUpperInvariant di .NET su ſ ("S*" vs "ſx": .NET true, Swift false) — lato sicuro per i marcatori di progetto.
Task 4: fix round 2 consegnato (2b9959f): 6 issue RED sul codice del giro 1; suite completa 98/98.
Task 4: fix round 2/5 (1 addressed + nit + ruled-in, 0 open; commits 494892c..2b9959f). Confronto esaustivo con .NET 10.0.12 OIC su 1.112.064 scalari: 0 equivalenze solo-Swift, 0 solo-.NET (1453 classi identiche); controllo col ripiegamento del giro 1 ritrova le 29+27 differenze note.
Task 4: minor (deferred): il test pruneReason("/Users/marco.mılanı/Documents") passava già col codice del giro 1; meglio "/Users/marco.mılanı/Library/Caches"; nessun test fissa l'esclusione U+16EA0–U+16EDF.
Task 4: minor (deferred): il ripiegamento dipende dalle tabelle Unicode del sistema; un macOS futuro con nuove coppie potrebbe creare equivalenze solo-Swift — irrobustimento possibile con properties.age invece dell'intervallo fisso; la riga "equivalente" del registro vale sul runtime attuale.
Task 4: minor (deferred): FakeLinkInspector usa chiavi String (equivalenza canonica NFC/NFD), più permissivo del C# (solo test, lato "più dinieghi").
Task 4: complete (commits 7ae27f2..2b9959f, review clean after fix round 2)
Task 5: dispatched (base 2b9959f)
Task 5: implementer haiku a06a4f51cc79217d7 (report task-5-report.txt)
Task 5: implementer DONE_WITH_CONCERNS (2ec7872) — load() intercetta ogni errore (C# solo Json/IO/UnauthorizedAccess); ordine chiavi e spaziatura JSON diversi dal C#
Task 5: review (sonnet) — spec ✅, quality Approved.
Task 5: minor (deferred): decodifica più tollerante del C# non annotata nel registro: campo intero null → default del solo campo (C# scarta tutto il file), 12.0 accettato, 3000000000 accettato (Int 64 bit vs int 32), "ProjectRoots": null → [] (C# null), [null] → file intero ai default (C# conserva l'elemento null).
Task 5: minor (deferred): test sulle chiavi letterali solo per 3 di 8 chiavi; default per campo da file parziale non verificati; nessun test sul campo di tipo errato.
Task 5: minor (deferred): appPathsLiveUnderApplicationSupport verifica solo suffissi; forBundleIdentifier("") non protetto.
Task 5: minor (deferred): load() intercetta ogni errore; riga del registro con "<bundle id>" che alcuni renderer Markdown inghiottono.
Task 5: complete (commits 2b9959f..2ec7872, review clean)
Task 6: dispatched (base 2ec7872) — porta il ruling del Task 4 su PathExpander (controlli "~/" e "/" sui byte UTF-8).
Task 6: implementer haiku ae1179a96004e9acd (report task-6-report.txt)
Task 6: implementer DONE (5a9be6b)
Task 6: review (sonnet) — spec ✅, quality Approved (catalogo identico al C# stringa per stringa).
Task 6: minor (deferred): nessun test solo-Swift fissa i controlli su byte di PathExpander (es. expand("~/\u{301}Library")); nota del registro con attribuzione "ruling del Task 4" poco autoesplicativa; forCurrentUser non testato (NSTemporaryDirectory vs $TMPDIR override).
Task 6: complete (commits 2ec7872..5a9be6b, review clean)
Task 7: dispatched (base 5a9be6b)
Task 7: implementer haiku ac3a9c96e1b6d3218 (report task-7-report.txt)
Task 7: implementer DONE_WITH_CONCERNS (66f4b1c) — isExpected senza chiamanti; catch-all in accept/readDirectoryStamp/fileSizeAndStamp/tryFileSize (C# filtra con IsExpected); date implicite di InMemoryFileSystem dall'orologio reale
Task 7: review (opus) — spec ✅, quality Approved. Verifica del Task 3 su VanishingFileSystem chiusa: i due test che lo usano hanno minAge nil, esito identico al C#.
Task 7: minor (deferred): ENOTDIR (genitore diventato file, solo in race) classificato "in uso" e non come sentinella/NotFound come in .NET (misurato); lato sicuro (Swift propone meno), da annotare in §5.3/registro.
Task 7: minor (deferred): equivalenze §5.3 non fissate da test (ramo accept ENOENT→true, readDirectoryStamp senza errore, mappatura describe per EPERM/EBADF/ENOTEMPTY/altro/.other); commento di FaultInjectingFileSystems descrive .NET reale più che il doppio C#.
Task 7: minor (deferred): RuleScanner.isExpected è codice morto (il CleanEngine del piano usa `catch let error as FileSystemError`), plan-mandated.
Task 7: minor (deferred): helper che intercettano ogni errore (C# filtrava con IsExpected); un CancellationError lanciato da un FileSystem sarebbe inghiottito (oggi impossibile, protocollo sincrono).
Task 7: minor (deferred): InMemoryFileSystem data le cartelle implicite con Date() reale (trappola latente per futuri test con minAge).
Task 7: complete (commits 5a9be6b..66f4b1c, review clean)
Task 8: dispatched (base 66f4b1c)
Task 8: implementer haiku a5a0535521fbdd76e (report task-8-report.txt)
Task 8: implementer DONE_WITH_CONCERNS (25a44f0) — annullamento a metà scansione non testato
Task 8: review (sonnet) — spec ✅, quality Approved.
Task 8: minor (deferred): annullamento a metà scansione non testato; test d'ordine non rileverebbe un ordinamento mancante; asserzioni più deboli del C# (categoryWithoutRules usa .first, progress non verifica il resoconto finale); contratto di threading del callback non documentato; lavoro bloccante sul pool cooperativo; categoria senza regole restituita anche se annullata prima di partire; @concurrent oggi solo dichiarativo.
Task 8: complete (commits 66f4b1c..25a44f0, review clean)
Ruling: (affina il ruling del Task 4 per il Task 9) in CleanEngine.rewriteToResolvedRoot il resto del percorso si taglia per SCALARI (dropFirst(declaredRoot.unicodeScalars.count)), non per byte: il prefisso è riconosciuto senza maiuscole e due forme di una lettera possono avere lunghezze UTF-8 diverse (ȿ/Ȿ), mentre il ripiegamento è uno-a-uno sugli scalari — se sbagliato costa una riga.
Task 9: dispatched (base 25a44f0)
Task 9: implementer haiku a4768b298c0f2f0d7 (report task-9-report.txt)
Task 9: implementer DONE_WITH_CONCERNS (4e0c7ce) — rootVerdicts con chiave lowercased() (equivalenza canonica: KELVIN SIGN = K); dedup di ConfirmationRows su Set<String> unisce NFC/NFD; measureRealSize intercetta ogni errore; ruling a scalari senza test non-ASCII
Task 9: review (opus) — spec ❌: Important 1 plan-mandated: rootVerdicts con chiave lowercased() (String: equivalenza canonica) unisce root che OIC distingue (U+212A/K, ẞ/ß, NFC/NFD, U+2126/Ω, U+212B/Å); sonda su APFS reale: [(Des\u{212A}top/decoy, R1), (Desktop/secret.txt, R2)] → R2 mai validata, secret.txt cancellato; il C# rifiuta. Minor: dedup ConfirmationRows su Set<String>; measureRealSize intercetta ogni errore; nessun test del taglio a scalari; test del diario non prova l'immediatezza; elemento-cartella che è un collegamento al momento della pulizia misurato attraverso il collegamento (byte accreditati non liberati).
Ruling: chiave dei verdetti = byte UTF-8 del percorso ripiegato ([[UInt8]: GuardVerdict], Array(PathText.folded(root).utf8)) + test di regressione Kelvin — ogni root distinta per OIC viene validata — se sbagliato costa una riga.
Ruling: nello stesso giro: measureRealSize intercetta solo FileSystemError (gli altri errori risalgono al catch esterno, come §8.2) e restituisce 0 per un elemento-cartella che è un collegamento (non si accreditano byte che la cancellazione non libera; estende la differenza voluta già registrata); test del taglio a scalari (U+03B9 vs U+1FBE); test del diario che verifica il conteggio a ogni avanzamento — costo minimo, stesse funzioni.
Ruling: ConfirmationRows resta su Set<String> (equivalenza canonica): unire le grafie NFC/NFD dello stesso file evita il doppio conteggio che l'Ordinal del C# produrrebbe con root configurate in grafie diverse; si corregge il commento ("confronto esatto" era falso) e si registra la differenza — se sbagliato costa una chiave [UInt8].
Task 9: improvement candidate (fuori ambito, uguale al C#): APFS ripiega oltre OIC (U+212A→k, ſ→s): un elemento manipolato "~/Des\u{212A}top/x" con root uguale supera la deny-list testuale e APFS lo risolve in ~/Desktop — da registrare fra i candidati a miglioramento con priorità alta.
Task 9: fix round 1 consegnato (3f0c7b8): 197/197; test Kelvin adattato (secret.txt registrato anche nella grafia Kelvin) e asserzione U+0600 aggiunta al test del taglio
Task 9: fix round 1/5 (6 addressed, 0 open; commits 4e0c7ce..3f0c7b8). Sonda APFS: R2 ora negata, secret.txt intatto.
Ruling: la falla del ripiegamento APFS oltre OIC (elemento e root manipolati "~/Des\u{212A}top/…" cancellano ~/Desktop/…, identica nel C#) resta un candidato a miglioramento ad alta priorità e non si corregge nel porting — la spec §12 vieta di cambiare regole in fase 1 e il comportamento è identico all'app attuale — se sbagliato costa la cancellazione di un file protetto solo con un elenco manipolato; da segnalare in evidenza all'utente a fine piano.
Task 9: minor (deferred): nessun test per la propagazione degli errori fuori contratto da measureRealSize né per l'elemento-cartella collegamento (verificati su APFS dal revisore); a capo irregolare nel doc di ConfirmationRows.
Task 9: complete (commits 25a44f0..3f0c7b8, review clean after fix round 1)
Task 10: dispatched (base 3f0c7b8)
Task 10: implementer haiku a4e1220cdb445455b (report task-10-report.txt)
Task 10: implementer DONE_WITH_CONCERNS (5c07318) — sessions(limit:) con due SELECT senza transazione
Task 10: review (sonnet) — spec ✅, quality Approved.
Task 10: minor (deferred): timestamp troncato al millisecondo (accettato nel registro); nessun sqlite3_busy_timeout (C# attendeva 30 s); sessions(limit:) con due SELECT senza transazione; nessun ORDER BY sulle categorie; SQLiteError non LocalizedError e messaggio di apertura non localizzato; sqlite3_close invece di close_v2; stringhe non nel catalogo; test assenti per user_version, ROLLBACK, malformedRow e conservazione dei dati al secondo initialize; query usata anche per INSERT.
Task 10: complete (commits 3f0c7b8..5c07318, review clean)
Task 11: dispatched (base 5c07318)
Task 11: implementer haiku a8fec68be1cf37c77 (report task-11-report.txt)
Task 11: implementer DONE (ea5bdb2) — note: retention negativa fa trappola in prune (dropFirst); %d per Int in journalStamp; nome di un test promette più di quanto verifica
Task 11: review (sonnet) — spec ✅, quality Approved.
Nota per il piano 3: chi orchestra la pulizia deve chiamare discard(journal) SOLO dopo che write(sessionId:report:) è riuscito; se write lancia, il diario resta (nulla in questo task lo impone).
Task 11: minor (deferred): largeInputSpansManyChunks non attraversa più blocchi in compressione (precedenza di >> sopra &*: sequenza periodica, ~4 KB compressi) — plan-mandated; copertura scarsa di dati corrotti (header, CRC) e dei rami di escape \r, \u00xx e non-BMP; U+0085/U+2028/U+2029 non escapati (JSON valido, ma alcuni lettori spezzano la riga) e non-ASCII grezzo invece di \uXXXX, da registrare; nome di test che promette troppo; failure path del diario non testati; retention negativa fa trappola, 0 cancella il log appena scritto; pruning che cancella il log nuovo se gli id ripartono (uguale al C#); collisione del nome del diario entro lo stesso secondo; memoria: l'intero log tenuto tre volte (C# in streaming); uInt(inputCount) per input >4 GiB.
Task 11: complete (commits 5c07318..ea5bdb2, review clean)
Task 12: dispatched (base ea5bdb2)
Task 12: implementer haiku adf28c0607505d717 (report task-12-report.txt)
Task 12: implementer DONE_WITH_CONCERNS (31c3c42) — drenaggio di stdout/stderr dopo l'uscita del figlio senza timeout né annullamento (sonda: timeout 1 s → ritorno dopo 3 s; uguale al C#); pipe senza FD_CLOEXEC; indici 0/1 sulle pipe (ruling pre-flight)
Task 12: review (opus) — spec ✅ ma quality Needs fixes: Important plan-mandated: il figlio eredita la maschera dei segnali dei thread del pool cooperativo (~20 segnali bloccati: TERM, INT, HUP, ALRM, CHLD…); sonda: `sh -c "kill -TERM $$; echo survived"` → exit 0 "survived" (shell normale: 143); .NET ripristina maschera e gestori (pal_process.c). Correzione verificata dal revisore in scratchpad/rv12.
Ruling: posix_spawnattr_setsigmask con insieme vuoto + setsigdefault con tutti i segnali tranne SIGKILL/SIGSTOP + flag SETSIGMASK|SETSIGDEF, test exitCode 143 sul self-SIGTERM — parità con .NET e prerequisito per Diagnostics/Xcode — se sbagliato costa due attributi di spawn.
Ruling: nello stesso giro: SpawnedProcess da @unchecked Sendable a Sendable (tutti let Sendable); waitpid fallito (es. ECHILD) restituisce -1 invece di 0; il test di annullamento ha un limite di tempo — stesse righe, costo minimo.
Task 12: minor (deferred): drenaggio dell'output dopo l'uscita del figlio senza timeout/annullamento (parità C#, non raggiungibile con ps/du/docker/simctl secondo le sonde); ritorno di timeout/annullamento che attende il reap del figlio diretto (D-state); pipe senza FD_CLOEXEC (finestra di microsecondi); valori di ritorno di posix_spawn_*_ e strdup ignorati; tre thread GCD bloccati per esecuzione; lacune di test (codici di segnale, output >64 KB, ambiente ereditato, ProcessLaunchError.code).
Nota per il piano 2: posix_spawnp cerca nel PATH dell'app (da Finder: /usr/bin:/bin:/usr/sbin:/sbin): docker va passato con percorso assoluto (DockerBinaryLocator).
Task 12: fix round 1 consegnato (558178c): RED del nuovo test sul codice vecchio (exit 0, 'survived'); 224/224
Task 12: fix round 1/5 (4 addressed, 0 open; commits 31c3c42..558178c)
Task 12: minor (deferred): SETSIGDEF sull'intero insieme azzera anche i SIG_IGN ereditati (es. nohup), .NET li conserva; commento "quasi tutti i segnali" (sono ~20); i chiamanti futuri devono distinguere il timeout con timedOut (exitCode -1 ha due origini).
Task 12: complete (commits ea5bdb2..558178c, review clean after fix round 1)
Task 13: dispatched (base 558178c)
Task 13: implementer haiku a780a3aa273e98a43 (report task-13-report.txt)
Task 13: implementer DONE (e2dea32)
Task 13: review (sonnet) — spec ✅, quality Approved; probe reale di forCurrentMachine con ps e ProcessRunner riuscito.
Task 13: minor (deferred): ordinamento con .caseInsensitive (minuscole) invece di OrdinalIgnoreCase (maiuscole): diverge su [ \ ] ^ _ ` rispetto alle lettere (solo ordine della lista di avvisi); gestione a Character (avviso, non guardia: impatto trascurabile; .whitespacesAndNewlines per CRLF); test che non fissano la guardia timedOut né il timeout di 5 s; test dipendenti da NSHomeDirectory; deduplicazione ridondante; riga del registro senza conteggio InlineData.
Task 13: complete (commits 558178c..e2dea32, review clean)
Ruling: il Task 14 attende ora 242 test totali (230 del piano + 12 aggiunti nei giri di correzione: Task 1 +0 funzioni, Task 2 +1, Task 4 +6, Task 9 +2, Task 12 +1, …) — il conteggio del piano era quello prima delle correzioni — e la riga di chiusura del registro dice "176 prove C# portate (+ 66 nuove)"; l'esecutore riporta il numero reale osservato se diverso.
Task 14: dispatched (base e2dea32)
Task 14: implementer haiku a2fe46a9603d04aa6 (report task-14-report.txt)
Task 14: implementer DONE_WITH_CONCERNS (b4b3c3f) — 242/242; file di integrazione senza riga nel registro (nessun C# corrispondente)
Task 14: review (sonnet) — spec ✅, quality Approved.
Task 14: minor (deferred): asserzioni sottili nei test 2 e 3 (sopravvivenza dei file, percorso dell'errore, itemsDeleted/bytesFreed); dipendenza da utente non root e da TMPDIR sotto /var senza precondizione esplicita; contenuto del log verificato per sottostringa; i 4 test di integrazione non annotati nel registro.
Task 14: complete (commits e2dea32..b4b3c3f, review clean)
Final review: dispatched (opus)
Final review (opus): Ready to merge "With fixes". Nessun Critical. Important 1: registro di parità incompleto (differenze da annotare dei Task 2, 4, 5, 7, 11, 12 + nuove: rmdir EACCES/EPERM → accessDenied e LooksLikePermissionError del C#; deviazione da §5.2 su realpath/removefile; race di removeTree; sezione dei test solo-Swift). Suite rieseguita dal revisore su copia pulita: 242/242.
Final review: chiusi da correzioni successive (da cancellare): Task 1 lowercased in SimpleGlob; Task 1 fileName/join/trimming su Character; Task 4 hasPrefix("/") in LinkInspecting/LocalFileSystem.
Final review: prima del piano 3 (restano rinviati per questo merge): cancellazione ereditata in SessionLogWriter.write; SessionLogWriting restituisce PendingJournal con init interno (non simulabile); FileSystemError/SQLiteError non LocalizedError; lavoro bloccante sul pool cooperativo e callback di avanzamento concorrenti; target di supporto ai test condiviso; unica fonte della home in AppEnvironment; test reali con home risolta e con elemento-cartella diventato collegamento.
Final review: prima del rilascio (piano 4): ripiegamento dipendente dalle tabelle Unicode del sistema; smoke test di Bundle.module nell'app impacchettata; ricorsione di removeTree/sumOfFiles (SIGBUS in debug oltre ~200 livelli) da rendere iterativa se si passa a openat.
Final review: stringhe InvalidConfiguration e "sqlite3_open_v2 fallita" non localizzate; FileSystemLinkInspector e HistoryStore.initialize aggirano il protocollo FileSystem (seam per la fase 2).
Final review: nessun ruling giudicato errato. Il ruling sulla falla del ripiegamento APFS (Kelvin/ſ) richiede una decisione dell'utente.
Final fix wave: dispatched (haiku) — solo registro di parità.
Final fix wave: bd3179c (registro: 9 differenze, 1 candidato, sezione test solo-Swift 8 file / 51 @Test)
Final fix wave: re-review (sonnet) — Important ADDRESSED; nessuna nuova rottura Critical/Important.
Final: parked — riga settings del registro: "array null" non rende illeggibile il file in .NET (lo accetta come null; [null] è accettato con elemento null, mentre Swift va ai default) — Ruling: imprecisione documentale minore, ereditata dalla formulazione del finding; si corregge con una riga all'inizio del piano 2/3 — se lasciata costa un'indicazione sbagliata a chi porta il caricamento delle impostazioni.
Final: parked — riga SimpleGlob del registro: in .NET ToUpperInvariant lascia ı invariata; diverge solo ſ→S — Ruling: stessa correzione di una riga — costo trascurabile.
Final: parked — Contenuto di SimpleGlobTests attribuisce i test su ı/ſ (stanno in PathTextTests); conteggi senza casi parametrici; riga jsonLine incompleta (`<>&'` grezzi; il lettore del diario deve dividere solo su \n) — Ruling: minor documentali, insieme alla correzione sopra.
Final review: clean (fix wave bd3179c addressed). Plan 1 complete.
