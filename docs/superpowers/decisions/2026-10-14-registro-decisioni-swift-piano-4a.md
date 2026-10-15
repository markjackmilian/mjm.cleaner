# SDD ledger — plan: docs/superpowers/plans/2026-10-14-swift-port-4a-features.md

Spec: docs/superpowers/specs/2026-10-13-swift-native-port-design.md (raggiungibile, autorità vincolante).
Workspace: in place sul branch feat/swift-port-app (creato da main 3e0b6bf; commit del piano 4caa1a0), nessun worktree, come nei piani 1–3.
Baseline: 496 test verdi in CleanerCoreTests; CleanerFeatures non esiste ancora.
Report degli implementatori in `.txt` (haiku rifiuta i `.md`). Istruzioni generiche: implementer-instructions.txt e reviewer-instructions.txt in questo workspace.

## Pre-flight scan (2026-10-14)

Evidenza di partenza: durante la stesura ogni blocco di codice del piano è stato estratto in ordine, task per task, in una copia pulita di
swift/MjmCleanerKit presa da main (scratchpad/verify4a): per ogni task la build con i soli test fallisce (RED, messaggi allineati agli
Expected), poi passa con i conteggi cumulativi 10, 15, 26, 34, 42, 46, 54, 60, 78, 104, 118; suite finale 118 + 496, nessun warning;
15 esecuzioni consecutive della suite Features verdi; 9 mutazioni sulle garanzie di sicurezza tutte uccise (diario scartato prima del log
nel wizard e in Xcode, diario non passato al passo 4, volumi named-unused selezionati dal gruppo, blocco della navigazione tolto,
annullamenti ignorati in analisi, passo 3 e Xcode). I sorgenti e i test estratti sono identici byte per byte a quelli verificati.

### Coppie di task che condividono file o interfacce

| Task A → Task B | Prodotto da A | Consumato da B | Esito |
|---|---|---|---|
| 1 → tutti | Package.swift (target CleanerFeatures/CleanerFeaturesTests), Formatting, FeatureText, SafeSum, ProgressRelay | ogni modello | coerente (compila in sequenza) |
| 1 → 2..11 | sezione «Test solo Swift di CleanerFeaturesTests» nel registro | righe aggiunte in fondo | ancora verificata (riga «Altri test solo Swift…» esiste) |
| 2 → 3..11 | AppEnvironment, DockerCleanupServing, FolderPicking, AppearanceApplying, Navigating, StartupFailure; test: TestSupport, ServiceDoubles, TestHome | modelli e test | coerente |
| 3 → 11 | SettingsModel(store:appearance:folders:onSaved:onClose:), FakeAppearance, FakePicker | MainModel.showSettings, test 11 | coerente |
| 4 → 5,9,10 | NavigationSpy (classe base non final) | CleanupNavigationSpy, DockerNavigationSpy, FakeNavigation | coerente |
| 5 → 6,7,8,11 | CleanupNavigating, ChooseStepModel.navigation (weak, setter interno) | passi 2–4, MainModel.init | coerente |
| 9 → 11 | DockerNavigating, DockerModel, DockerReportModel | MainModel | coerente |
| 10 → 11 | XcodeNavigating, XcodeModel, XcodeReportModel; XcodeViewModelTests.FakeXcode/fixture | MainModel, NavigationLockTests, MainModelTests | coerente |
| 2..11 ↔ registro | righe App.Tests sostituite per nome file; Differenze/Candidati in fondo; riga Utilità sostituita (Task 2) | 12 chiude le 6 righe restanti e aggiunge la riga di completamento | ancore e nomi verificati; colonne controllate (6/3/4) |

### Coerenza interna di ciascun task

| Task | Test specificati vs codice | File creati vs toccati dopo | Esito |
|---|---|---|---|
| 1 | 10 test / 4 utilità + package | Package.swift solo qui | coerente |
| 2 | 5 test / 3 sorgenti + 3 file di supporto | supporto riusato, non modificato | coerente |
| 3 | 11 / SettingsModel + PlatformDoubles | — | coerente |
| 4 | 8 / CategoryNames + HistoryModel + NavigationSpy | — | coerente |
| 5 | 8 / CategoryVisuals + ChooseStepModel + spy | — | coerente |
| 6 | 4 / ScanStepModel | — | coerente |
| 7 | 8 / ConfirmStepModel | — | coerente |
| 8 | 6 / DoneStepModel | — | coerente |
| 9 | 18 / DockerModel + DockerReportModel + spy | — | coerente |
| 10 | 26 / XcodeReportModel + XcodeModel | fixture riusate dal Task 11 | coerente |
| 11 | 14 / Page + MainModel | — | coerente |
| 12 | verifica + registro | — | coerente |

### Punti che la rubrica di review potrebbe trattare come difetti

- `XcodeViewLayoutTests` mantiene i nomi C# («…KeepsDestructiveAndBackControlsInViewport», «…RendersFourGroups…») ma verifica il modello, non il viewport.
- `persist` di DoneStepModel e DockerReportModel ha la stessa forma (save → write → refresh), come in C#; Xcode ha la propria variante a tre messaggi.

### Rulings pre-flight

Ruling: si lavora in place su feat/swift-port-app senza worktree — è il branch indicato dall'utente e la prassi dei piani 1–3 — se sbagliato costa solo l'isolamento di una cartella.
Ruling: i test portati di XcodeViewLayoutTests mantengono i nomi C# anche se verificano il modello — il vincolo globale impone i nomi e il doc della suite lo dichiara; le verifiche di viewport passano al 4b — se sbagliato costa nomi che promettono più di quanto verificano (si rinominano in un passaggio).
Ruling: la forma comune di persist (wizard e Docker) resta duplicata — sono due flussi distinti con messaggi e diario diversi, come in C#; un helper condiviso aggiungerebbe un'astrazione per sei righe — se sbagliato costa un piccolo refactoring.

## Modelli

Implementatori: haiku (il piano contiene il codice completo). Revisori: sonnet per 1, 3, 4, 5, 6, 12; opus per 2 (composizione), 7 e 8 (pulizia e diario), 9 (selezione di ciò che Docker cancella), 10 (eliminazione Xcode e diario), 11 (composizione della finestra e blocco). Review finale: opus.

## Avanzamento
Task 1: dispatched (BASE 4caa1a0, implementer haiku)
Task 1: implemented 7cdbffb (506 tests: 496+10, trailer verified Opus 5.5); review dispatched (sonnet)
Task 1: review (sonnet) — spec ✅, quality Needs fixes: Important 1 plan-mandated: hasOrdinalPrefix non fissato contro hasPrefix (mutazione FeatureText.swift:21 → hasPrefix sopravvive; test solo ASCII). 25 altre mutazioni uccise.
Ruling: aggiungere a comparisonsAreOrdinalNotCanonical le due asserzioni non ASCII proposte dal revisore (hasOrdinalPrefix("cafe\u{301}", "cafe") vero; hasOrdinalPrefix("caf\u{E9}", "cafe\u{301}") falso) — il vincolo globale vieta hasPrefix e la funzione esiste per questo; il conteggio dei test non cambia — se sbagliato costa due righe di test.
Task 1: minor (deferred): ProgressRelay senza deinit { continuation.finish() } — se un chiamante salta finish() il consumatore resta vivo (oggi ogni percorso dei modelli chiama finish).
Task 1: minor (deferred): il test d'ordine di ProgressRelay non distingue un Task per valore (FIFO del runtime); informativo.
Task 1: minor (deferred): Formatting.seconds va in trap su durate estreme (Int64.max secondi), irraggiungibile.
Task 1: minor (deferred): SafeSum.total dipende dall'ordine dopo la saturazione.
Task 1: minor (deferred): FeatureText.message duplica XcodeText.message del Core (interno; plan-mandated).
Task 1: fix round 1 dispatched (resume implementer a8aa38cb4d2f46fdc)
Task 1: fix round 1 implemented cdba4a4 (+2 asserzioni, FeatureTextTests 3/3); scoped re-review (haiku): ADDRESSED, mutazione hasPrefix uccisa a :20/:21; trailer verificato dal controller.
Task 1: fix round 1/5 (1 addressed, 0 open; commits 7cdbffb..cdba4a4)
Task 1: complete (commits 4caa1a0..cdba4a4, review clean after fix round 1)
Note: i subagent vedono un promemoria di attribuzione "Haiku 5.5"; la regola del progetto (piano, Global Constraints) resta "Claude Opus 5.5". Non è un finding.
Task 2: dispatched (BASE cdba4a4, implementer haiku)
Task 2: implemented f019dcf (511 = 496+15, trailer verified; concerns: riga Utilità cita doppi del Task 3, commento FakeDocker 'executeFailure', PlatformServices senza import Foundation — tutti testo del piano); review dispatched (opus)
Task 2: review (opus) — spec ✅ (blocchi verbatim, parità con AppServices.cs punto per punto), quality Needs fixes: Important 1 plan-mandated: la home iniettata in live non è fissata (mutazioni DenyList/PathGuard del clean, CleanEngine principale e PathExpander su un'altra home sopravvivono; nessun task successivo può fissarle); Important 2 plan-mandated: categoriesAndProjectRoots… controlla solo gli id (categories() che ignora le impostazioni sopravvive). Mutanti (e) collettore nuovo = equivalente (struct senza stato); (e2) collettore senza file scanner e (f) guard diverso nel CleanEngine dell'esecutore: non fissabili per comportamento senza xcrun reale → garanzie affidate alla revisione.
Ruling: fix round con codice esatto preparato e verificato dal controller in scratch (task-2-fix1-snippet.swift): categoriesAndProjectRootsFollowTheCurrentSettings verifica le root delle regole di project-build-output e una seconda lettura dopo un save; nuovo test solo-Swift liveCompositionUsesTheGivenHomeForTheGuardAndTheExpander (home da realpath, ~/Documents protetto, cache eliminata, espansione) — le tre mutazioni g/h/i e j uccise in scratch — se sbagliato costa un test in più; i totali del piano salgono di 1 (Task 3: 27 … fine piano 119).
Ruling: (e2) e (f) restano affidati alla revisione (stesso collettore con file scanner e stesso PathGuard per l'esecutore Xcode): un test di comportamento richiede xcrun e Xcode reali — se sbagliato costa una regressione della composizione non vista dai test, mitigata dalla review finale opus.
Task 2: minor (deferred): con una home che contiene un collegamento (es. /var/folders senza realpath) la deny-list non protegge nulla (PathGuard risolve la root, DenyList no; uguale al C#); live accetta ora una home iniettabile: candidato a miglioramento da registrare (realpath in live o documentazione).
Task 2: minor (deferred): Gate.wait() senza limite: se un modello non chiama mai scan/clean, `await scan.started.wait()` sospende per sempre (Task 6, 7).
Task 2: minor (deferred): liveCompositionFailsWhenTheDataFolderIsUnusable accetta qualunque errore ((any Error).self).
Task 2: minor (deferred): commento di FakeDocker cita executeFailure inesistente; setDiskAfter vale per ogni measureDisk; FakeClean/FakeScan aprono started prima di diario/avanzamento (corsa possibile in un test che legge il diario dopo started).
Task 2: minor (deferred): con FixedWallClock due openJournal dello stesso FakeSessionLog danno lo stesso file.
Task 2: minor (deferred): PlatformServices.swift usa String(localized:bundle:) senza import Foundation (visibilità transitiva; si romperebbe con MemberImportVisibility).
Task 2: minor (deferred): la riga «Utilità» del registro cita FakeAppearance/FakePicker prima del Task 3 (da verificare al Task 3).
Task 2: fix round 1 dispatched (resume implementer ac069eb2c3f969d8d)
Task 2: fix round 1 implemented 3ce4285 (AppEnvironmentTests 6, Features 16; test identico allo snippet verificato dal controller); scoped re-review (sonnet): entrambi ADDRESSED, 9 mutazioni uccise.
Task 2: fix round 1/5 (2 addressed, 0 open; commits f019dcf..3ce4285)
Task 2: minor (deferred): home iniettata non fissata per DockerBinaryLocator, DiskUsageProbe, XcodeSizeProbe, XcodeFileScanner, RunningAppsProbe, guard del RuleScanner e del CleanEngine Xcode (se costruiti a parte), tempDirectory dell'espansore — affidati alla revisione (servirebbero sonde per servizio).
Task 2: minor (deferred): il commento del nuovo test cita «Candidati a miglioramento» per la ragione di realpath, ma la riga sulla home con collegamenti non esiste ancora: aggiungerla (vedi minor della home con collegamento) nella fix wave finale.
Task 2: complete (commits cdba4a4..3ce4285, review clean after fix round 1)
Ruling: i conteggi attesi del piano salgono di 1 da qui (Task 3: 27; 4: 35; 5: 43; 6: 47; 7: 55; 8: 61; 9: 79; 10: 105; 11: 119; Task 12 e riga del registro: 45 nuove → 75 nuove, totale 119) — il test aggiunto in review — costo nullo (solo conteggi).
Task 3: dispatched (BASE 3ce4285, implementer haiku)
Task 3: implemented 657274a (SettingsViewModelTests 11, Features 27, 496+27; trailer verified); review dispatched (sonnet)
Task 3: review (sonnet) — spec ✅ (blocchi identici al brief), quality Needs fixes: 4 Important plan-mandated (mutazioni sopravvissute): clamp di nuGetMinAgeDays non fissato; tetto Int32 dei megabyte non fissato (senza, save va in trap); dedupe/rimozione ordinali non fissate (== sopravvive); selezione mantenuta con pannello annullato non fissata. 20 altre mutazioni uccise.
Ruling: tre test solo-Swift preparati e verificati dal controller in scratch (task-3-fix1-snippet.swift; 6 mutazioni uccise): saveClampsNegativeNuGetAgeAndHugeThresholds, foldersAreComparedOrdinallyWhenAddingAndRemoving, cancelledPickerKeepsTheCurrentSelection — garanzie dichiarate dal piano senza test — se sbagliato costa tre test; totali +3 (SettingsViewModelTests 14, Features 30; fine piano 122).
Task 3: minor (deferred): lato file grandi senza copertura di rimozione/selezione (canRemoveLargeFileRoot, rimozione dalla lista giusta), titoli del pannello non verificati, hasSaveError su modello mai fallito non verificato, save che riapplica l'aspetto non verificato.
Task 3: minor (deferred): save() parte da store.load() per conservare selectedCategoryIds, ma nessun test lo fissa (CleanerSettings() sopravvive).
Task 3: minor (deferred): saveErrorText = "" dopo un salvataggio riuscito non osservabile (lo sheet si chiude).
Task 3: fix round 1 dispatched (resume implementer ae937d2919f46f2f9)
Task 3: fix round 1 implemented b39b41c (SettingsViewModelTests 14, Features 30; test identici allo snippet verificato); scoped re-review (haiku): 4/4 ADDRESSED, mutazioni a–e fallite (b per crash da overflow).
Task 3: fix round 1/5 (4 addressed, 0 open; commits 657274a..b39b41c)
Task 3: complete (commits 3ce4285..b39b41c, review clean after fix round 1)
Ruling: conteggi attesi ora +4 rispetto al piano (Task 4: 38; 5: 46; 6: 50; 7: 58; 8: 64; 9: 82; 10: 108; 11: 122) — test aggiunti in review — costo nullo.
Task 4: dispatched (BASE b39b41c, implementer haiku)
Task 4: implemented 9b0749c (History 8, Features 38; trailer verified); review dispatched (sonnet)
Task 4: review (sonnet) — spec ✅ (byte per byte), quality Approved; 27 mutazioni uccise. Important 1 plan-mandated: HistoryModel.load inghiotte l'errore di lettura con try? (pagina vuota senza motivo).
Ruling: HistoryModel.load resta con try? — è la parità con il C# (task non osservato, stessa pagina vuota) dichiarata nel brief e fissata da unreadableHistoryLeavesThePageEmpty; la lettura non cancella nulla — nella fix wave finale si aggiunge una riga «Candidati a miglioramento» (motivo visibile nello Storico illeggibile) — se sbagliato costa un errore di lettura dello storico che l'utente non vede spiegato.
Task 4: minor (deferred): data locale dipendente dal fuso della macchina nel test portato (su un runner UTC la conversione rimossa sopravvive); parametro timeZone di HistoryRow mai esercitato.
Task 4: minor (deferred): limite di 50 sessioni non fissato (FakeHistory fa solo prefix).
Task 4: minor (deferred): precedenza del catalogo sui nomi fissi non fissata; chiavi ordinali di CategoryNames non fissate (NFC/NFD); 5 nomi fissi su 8 non verificati.
Task 4: minor (deferred): HistoryRow.freed e startedAt mai verificati; weak della navigazione non fissato.
Task 4: minor (deferred): categories() legge settings sul main actor (come il C#).
Task 4: complete (commits b39b41c..9b0749c, review clean)
Task 5: dispatched (BASE 9b0749c, implementer haiku)
Task 5: implemented 470869a (ChooseStep 8, Features 46; trailer verified); review dispatched (sonnet)
Task 5: review (sonnet) — spec ✅, quality Needs fixes: 2 Important plan-mandated (mutazioni sopravvissute): guard di analyze() senza selezione non fissato (salverebbe [] e aprirebbe il passo 2 vuoto); conservazione delle altre impostazioni nel salvataggio non fissata (CleanerSettings() al posto di load() sopravvive).
Ruling: due test solo-Swift preparati e verificati dal controller in scratch (task-5-fix1-snippet.swift; 2 mutazioni uccise): analyzeWithNothingSelectedDoesNothing, analyzeKeepsTheOtherSettings — garanzie protettive della selezione e delle preferenze — se sbagliato costa due test; totali +2 (ChooseStepTests 10, Features 48; fine piano 124).
Task 5: minor (deferred): il nome rememberedSelectionIsRestoredAndAnalyzeSavesItBeforeScanning promette l'ordine save→scan che non verifica (ordine non osservabile oggi).
Task 5: minor (deferred): tileColorName e symbolName delle sei categorie non verificati (solo designHex, TileNeutral, Risk*).
Task 5: minor (deferred): CategoryVisuals usa Array(x.utf8) inline invece di FeatureText.ordinalKey (sette array per lettura).
Task 5: minor (deferred): CleanupNavigationSpy.showConfirm scarta le categorie (nessun test le chiede finora).
Task 5: fix round 1 dispatched (resume implementer a311bab5aaa2525ef)
Task 5: fix round 1 implemented 67382d3 (ChooseStepTests 10, Features 48; test identici allo snippet); scoped re-review (haiku): 2/2 ADDRESSED, mutazioni uccise.
Task 5: fix round 1/5 (2 addressed, 0 open; commits 470869a..67382d3)
Task 5: complete (commits 9b0749c..67382d3, review clean after fix round 1)
Ruling: conteggi attesi ora +6 rispetto al piano (Task 6: 52; 7: 60; 8: 66; 9: 84; 10: 110; 11: 124) — costo nullo.
Task 6: dispatched (BASE 67382d3, implementer haiku)
Task 6: implemented c21019a (ScanStep 4, Features 52; trailer verified; il dubbio sul registro è infondato: i solo-Swift dei file portati stanno nella colonna Note); review dispatched (sonnet)
Task 6: review (sonnet) — spec ✅, quality Needs fixes: Important 1 plan-mandated: lo svuotamento dell'avanzamento prima della navigazione non è fissato (S1/S2: finish() dopo showConfirm/startOver; S3/S4: finish() tolto dai rami annullamento/errore — tutti sopravvivono). 17 altre mutazioni uccise.
Ruling: tre test solo-Swift + un doppio privato SnapshotNavigation (fotografa il modello quando naviga), preparati e verificati dal controller in scratch (task-6-fix1-tests.swift, task-6-fix1-double.swift; S1–S4 uccise) — è la garanzia di concorrenza del task (spec §4.2) — se sbagliato costa tre test; totali +3 (ScanStepModelTests 7, Features 55; fine piano 127).
Task 6: minor (deferred): currentPath non fissato contro un aggiornamento a percorso vuoto che arriva per ultimo (S5).
Task 6: minor (deferred): confronto ordinale di id e nome delle righe non fissato (S6/S7, solo visualizzazione).
Task 6: minor (deferred): coda duplicata nei tre rami di perform (finish + isRunning) — plan-mandated; commento di errorText ereditato dal C# («task faulted»).
Task 6: fix round 1 dispatched (resume implementer a761f858a5b23407b)
Task 6: fix round 1 implemented 8702200 (ScanStepModelTests 7, Features 55; test identici a quelli verificati; l'implementatore ha fatto amend del proprio commit del round, non pubblicato); scoped re-review (haiku): ADDRESSED, S1–S4 uccise (3 esecuzioni ciascuna).
Task 6: fix round 1/5 (1 addressed, 0 open; commits c21019a..8702200)
Task 6: minor (deferred): i nuovi test di svuotamento dipendono dall'ordine di esecuzione sul main actor (il consumatore gira dopo la ripresa di perform), non da un handshake esplicito.
Task 6: complete (commits 67382d3..8702200, review clean after fix round 1)
Ruling: conteggi attesi ora +9 rispetto al piano (Task 7: 63; 8: 69; 9: 87; 10: 113; 11: 127) — costo nullo.
Task 7: dispatched (BASE 8702200, implementer haiku)
Task 7: implemented f42feaf (ConfirmStep 8, Features 63; trailer verified); review dispatched (opus)
Task 7: review (opus) — spec ✅ (identico al brief; diario §8.2 fissato bene: M9–M12 uccise), quality Needs fixes: Important plan-mandated: (1) deselezione per riga non fissata (M3 categoria intera, M4 attribuzione); (2) guardia di delete() non fissata (M6/M6b/M6c: doppio delete avvierebbe una seconda pulizia e un secondo diario); (3) svuotamento del relay prima di showDone non fissato (M16/M17); (4) SafeSum nei totali non fissata (M18/M19 trap); (5) varianti di testo (M20 cinque app, M22 singolare esclusioni, M24 byte dell'avanzamento).
Ruling: sei test solo-Swift + doppio privato ProgressSnapshotNavigation, preparati e verificati dal controller in scratch (task-7-fix1-tests.swift, task-7-fix1-double.swift; M3, M6, M6b, M6c, M16, M17, M18, M19, M20, M22 uccise) — garanzie di sicurezza del passo che elimina — se sbagliato costa sei test; totali +6 (ConfirmStepModelTests 14, Features 69; fine piano 133).
Ruling: M24 (byte nel testo d'avanzamento) resta minor rinviato — solo visualizzazione; per fissarlo serve cambiare FakeClean (doppio condiviso) e l'aspettativa di un test esistente — se sbagliato costa un testo d'avanzamento con i byte sbagliati non visto dai test.
Task 7: minor (deferred): M24 (bytesFreed nel testo d'avanzamento) non fissato: FakeClean segnala sempre 0.
Task 7: minor (deferred): cancelDeleteStillShowsThePartialReport attende clean.started senza limite (una regressione che non chiama clean blocca la suite: M29 600 s, M31 90 s).
Task 7: minor (deferred): canCancelDelete a riposo non fissato (M27); limite di 2000 percorsi della sonda non fissato (M23).
Task 7: minor (deferred): `?? row.categoryId` diverge dal C# First() (eccezione) e manca dalle Differenze del registro.
Task 7: minor (deferred): openJournal fa I/O sincrono sul main actor (trascurabile).
Task 7: fix round 1 dispatched (resume implementer a1d10bed6903a66c3)
Task 7: fix round 1 implemented 479b7aa (ConfirmStepModelTests 14, Features 69; test identici a quelli verificati); scoped re-review (sonnet): 5/5 ADDRESSED, 11 mutazioni uccise, 25 ripetizioni stabili.
Task 7: fix round 1/5 (5 addressed, 0 open; commits f42feaf..479b7aa)
Task 7: complete (commits 8702200..479b7aa, review clean after fix round 1)
Ruling: conteggi attesi ora +15 rispetto al piano (Task 8: 75; 9: 93; 10: 119; 11: 133) — costo nullo.
Task 8: dispatched (BASE 479b7aa, implementer haiku)
Task 8: implemented a0a3922 (DoneStep 6, Features 75; trailer verified; concern: refreshTotal nello stesso do/catch dà «storico non aggiornato» anche dopo storico e log scritti — uguale al C#); review dispatched (opus)
Task 8: review (opus) — spec ✅ (identico al brief; ordine save→write→discard→refresh conforme a §8.2), quality Needs fixes: Important (1) argomenti di write non fissati (S7 id+1, S7b2 id costante, S8/S8b report senza deletedPaths sopravvivono: il diario si scarterebbe dopo un log sbagliato); (2) discard non fissato rispetto a refreshTotal (S5: discard dopo refresh lascerebbe pending-*.jsonl a ogni errore del contatore). Dubbio dell'implementatore sul testo quando fallisce solo il contatore: parità con il C# (stesso try), non un difetto.
Ruling: due test solo-Swift + estensione del doppio condiviso FakeSessionLog (registra sessionId e report scritti: `written`; `writes` resta il conteggio), preparati e verificati dal controller in scratch (task-8-fix1-tests.swift, task-8-fix1-doubles.diff; S5, S7, S7b2, S8, S8b uccise) — garanzie del diario §8.2 — se sbagliato costa due test e tre righe di doppio; totali +2 (DoneStepModelTests 8, Features 77; fine piano 135).
Task 8: minor (deferred): posizione di refreshTotal non osservata (S10/S10b): i test di fallimento passano lo spy inline (riferimento weak → deallocato).
Task 8: minor (deferred): testi non fissati: singolari di «elemento eliminato»/«elemento non eliminato», filtro itemsDeleted > 0 contro bytesFreed > 0 (T3, T3b, T4).
Task 8: minor (deferred): conteggi non fissati (T3c, T6, T6b, T6c): integer vs grezzo, itemsFailed vs errors.count.
Task 8: minor (deferred): semantica «almeno uno» di describeErrors non fissata (T7b: casi con il tipo decisivo sempre ultimo).
Task 8: minor (deferred): candidato: avviso dedicato quando fallisce solo il contatore (oggi «storico non aggiornato», parità C#).
Task 8: fix round 1 dispatched (resume implementer a23efb5275f34db0c)
Task 8: fix round 1 implemented 8835e8f (DoneStepModelTests 8, Features 77; test e doppio identici a quelli verificati); scoped re-review (sonnet): 2/2 ADDRESSED, S5/S7/S7b2/S8/S8b uccise con asserzioni.
Task 8: fix round 1/5 (2 addressed, 0 open; commits a0a3922..8835e8f)
Task 8: minor (deferred): la costante 1 al posto di sessionId sopravvive (FakeHistory restituisce sempre 1 con un solo save).
Task 8: complete (commits 479b7aa..8835e8f, review clean after fix round 1)
Ruling: conteggi attesi ora +17 rispetto al piano (Task 9: 95; 10: 121; 11: 135) — costo nullo.
Task 9: dispatched (BASE 8835e8f, implementer haiku)
Task 9: implemented 5ff5783 (Docker 18, Features 95; trailer verified); review dispatched (opus)
Task 9: review (opus) — spec ✅ (byte per byte), quality Needs fixes: 5 Important (lacune dei test del brief): (1) tipo nella chiave di riga non fissato (M10: un volume named-unused chiamato «build-cache» erediterebbe la riga spuntata della cache → eliminato senza gesto); (2) guardia di delete() e annullamento non fissati (M15–M18, M29); (3) misura del disco dopo l'esecuzione non fissata (M21: suggerirebbe il Purge); (4) condizioni del Purge parziali (R01 senza eliminazioni, R03 senza prima misura); (5) persistenza: posizione di refreshTotal, sessionId, avviso su log fallito (R09, R10b, R11, R12).
Ruling: sette test solo-Swift + due doppi privati (SequencedDocker in DockerModelTests, SharedEventsNavigation in DockerReportModelTests), preparati e verificati dal controller in scratch (task-9-fix1-*.swift; 12 mutazioni uccise) — garanzie su ciò che Docker elimina e sul Purge suggerito — se sbagliato costa sette test; totali +7 (DockerModelTests 16, DockerReportModelTests 9, Features 102; fine piano 142).
Task 9: minor (deferred): M02 stato del gruppo derivato solo dalle righe raggruppabili non fissato; M11 chiavi ordinali NFC/NFD delle righe non fissate (irraggiungibile con nomi ASCII); M31/M32 svuotamento della pagina su un Riprova fallito dopo un successo non fissato; M33 isLoading = true mascherato dal valore iniziale.
Task 9: minor (deferred): M26/M27/M28 svuotamento del relay prima della navigazione non fissabile in modo deterministico con i doppi attuali (il main actor applica l'avanzamento prima che delete() riprenda).
Task 9: minor (deferred): measureDisk gira nel task di delete(), non in deleteTask: se quel task viene annullato dopo execute, la pagina mostra «Pulizia non riuscita: operazione annullata» senza resoconto né storico (il C# usava CancellationToken.None) — divergenza non registrata; da considerare nel 4b (chiamare delete() da un Task non legato alla vista) o nella fix wave.
Task 9: minor (deferred): describe toglie un byte UTF-8 (il C# un'unità UTF-16) su voci malformate non ASCII; R04/R07 sopravvivono (irraggiungibili).
Task 9: fix round 1 dispatched (resume implementer acf875349ee55276c)
Task 9: fix round 1 implemented 70c9a11 (Docker 16+9, Features 102; test identici a quelli verificati); scoped re-review (sonnet): 5/5 ADDRESSED, 12 mutazioni uccise con asserzioni, 8 ripetizioni stabili.
Task 9: fix round 1/5 (5 addressed, 0 open; commits 5ff5783..70c9a11)
Task 9: minor (deferred): il Purge con prima misura presente e seconda assente non è fissato (rawAfter ?? Int64.max sopravvive); la riga del registro dice «due misure».
Task 9: complete (commits 8835e8f..70c9a11, review clean after fix round 1)
Ruling: conteggi attesi ora +24 rispetto al piano (Task 10: 128; 11: 142) — costo nullo.
Task 10: dispatched (BASE 70c9a11, implementer haiku)
Task 10: implemented 2420a42 (Xcode 26 = 15+7+4, Features 128; trailer verified); review dispatched (opus)
Task 10: review (opus) — spec ✅ (5 file byte per byte), quality Needs fixes: 7 Important (lacune dei test del brief): (1) il piano consegnato a execute non è verificato (M19 piano allargato sopravvive); (2) righe bloccate e casella dei gruppi non cache (M2–M5); (3) load che non svuota conferma, gruppi e snapshot (M33, M34: conferma vecchia eseguibile dopo Riprova); (4) preview/backToSelection durante l'eliminazione e conferma vuota (M10, M30, M13); (5) diario del resoconto se fallisce il contatore o lo storico (R1, R3b); (6) relay non svuotato prima del resoconto (M23, M24); (7) conteggi del riepilogo (R9, R10).
Ruling: otto test solo-Swift scritti dal controller (il revisore non li aveva preparati) e verificati in scratch: in XcodeViewModelTests executeReceivesExactlyThePreviewedResources, blockedRowsAndIndividualGroupsAreNeverSelectedTogether, retryDropsTheOldConfirmationAndAFailedRetryEmptiesThePage, previewAndBackToSelectionAreIgnoredWhileDeleting, progressIsAppliedBeforeShowingTheReport (tre simulatori: con uno solo M23/M24 sopravvivevano) + doppio privato ProgressSnapshotNavigation; FakeXcode registra executedKeys e segnala un avanzamento per candidato; in XcodeReportViewModelTests aFailedTotalRefreshStillDiscardsTheJournal, historyFailureKeepsTheJournal, summaryCountsEachOutcomeSeparately. Tutte le 17 mutazioni uccise (M19/M23/M24 3 volte su 3), 12 esecuzioni stabili. File completi in task-10-fix1-XcodeViewModelTests.swift e task-10-fix1-XcodeReportViewModelTests.swift (solo aggiunte rispetto al commit) — se sbagliato costa otto test; totali +8 (Xcode 20+10+4, Features 136; fine piano 150).
Task 10: minor (deferred): M17 (guardia executionStarted di confirmDelete) uccisa solo da un blocco: doubleClickExecutesOnce attende second.value prima di aprire il gate.
Task 10: minor (deferred): M27 (executionStarted vero dopo un fallimento, direzione fail-closed) non verificato; M37 (diario aperto prima di confirm) non verificato; R4 (log sotto l'id dello storico) non verificato; R8 (spazio libero invariato) non verificato; M35/M36 canPreview/canRetry durante l'eliminazione non verificati.
Task 10: minor (deferred): executionStarted è @ObservationIgnored ma letto da canConfirmDelete osservabile (oggi ogni scrittura coincide con un cambio di isDeleting/isLoading).
Task 10: fix round 1 dispatched (resume implementer a556143bd70e64004)
Task 10: fix round 1 implemented 16de08c (Xcode 20+10+4, Features 136; file identici a quelli verificati); scoped re-review (sonnet): 7/7 ADDRESSED, 17 mutazioni uccise; drain 25/25 anche con le CPU sature.
Task 10: fix round 1/5 (7 addressed, 0 open; commits 2420a42..16de08c)
Task 10: minor (deferred): rowChanged del gruppo Xcode: X1 (righe bloccate contano per la spunta automatica), X3 (gruppo tutto bloccato mostrato selezionato), X2 innocuo; X4 load azzera executionStarted anche durante l'eliminazione se retry() viene chiamato (la UI lo guarda con canRetry).
Task 10: complete (commits 70c9a11..16de08c, review clean after fix round 1)
Ruling: conteggi attesi ora +32 rispetto al piano (Task 11: 150) — costo nullo.
Task 11: dispatched (BASE 16de08c, implementer haiku)
Task 11: implemented 63fd203 (Shell 14, Features 150 in 20 suite; trailer verified); review dispatched (opus)
Task 11: review (opus) — spec ✅ (verbatim), quality Needs fixes: Important 1 plan-mandated: il blocco §6.3 si aggira da una pagina non più corrente (startOver/showScan/showConfirm/showDone/showDockerReport senza guardia: un'analisi o un'eliminazione abbandonata sostituisce la pagina Xcode mentre elimina; sonda del revisore in scratchpad/rev-t11/probe/NavigationLockProbeTests.swift fallisce sul codice attuale; correzione verificata dal revisore: guard canNavigateGlobally in startOver/showScan/showConfirm, in showDone e showDockerReport costruire prima il modello e mettere la guardia solo prima di `page = …`, showXcodeReport senza guardia). Important 2: composizione storico/diario non fissata (C18 history stub, C19 sessionLog stub, C6, C11, C12, C16). Important 3: cablaggio di navigazione e dati delle pagine non fissato (C2–C5, C7–C9, C13–C15, C24). Minor: P7 kind di .docker; F3 errore di refreshTotal; C20 clock; settings `private(set)` richiederà un Binding nel 4b; pagine abbandonate riportano al wizard anche senza Xcode (parità C#).
Ruling (da applicare al fix round 1): Important 1 si corregge nel codice come verificato dal revisore — la spec §6.3 («il modello rifiuta il cambio di pagina») è vincolante e il brief la applicava solo a sidebar e menu — più il test solo-Swift della sonda e una riga «Differenze» (scostamento voluto dal C#); Important 2 e 3 con test solo-Swift in MainModelTests come proposto dal revisore — se sbagliato costa una guardia in più su cinque metodi di navigazione.
STATO: fix round 1 del Task 11 NON ancora inviato (limite d'uso raggiunto). Prossimi passi: preparare e verificare in scratch i test e la correzione del Task 11, riprendere l'implementatore aabdcc80be58c643c (o un nuovo haiku), ri-revisione; poi Task 12 (atteso 150 + i test del fix), review finale opus con i minor del ledger, copia del ledger in docs/superpowers/decisions/2026-10-14-registro-decisioni-swift-piano-4a.md, finishing-a-development-branch.
HANDOFF (2026-10-15): il lavoro prosegue con Codex nello stesso checkout. Creati: AGENTS.md (radice, non tracciato), CODEX-HANDOFF.md, CODEX-PROMPTS.md, task-12-brief.md, handoff/ (baseline: 150 + 496 test verdi, exit 0, nessun warning, HEAD 63fd203; sonda NavigationLockProbeTests.swift, log e harness delle 63 mutazioni del revisore, task11-fixcheck.py con la correzione esatta). Punto di ripresa invariato: fix round 1 del Task 11 non ancora fatto (vedi le due righe precedenti).
Ruling: i commit di Codex non portano il trailer di Claude (la regola «Co-Authored-By: Claude Opus 5.5» del piano valeva per i commit di Claude) — un trailer di Claude su commit scritti da Codex sarebbe un'attribuzione falsa — se l'utente preferisce un trailer, si aggiunge con un amend dei soli commit di Codex.
Ruling (2026-10-15, supera la riga HANDOFF e il ruling sul trailer di Codex qui sopra): l'utente rinuncia a Codex e prosegue con Claude in una nuova sessione opus — il materiale per Codex (AGENTS.md, CODEX-HANDOFF.md, CODEX-PROMPTS.md) è archiviato in handoff/archivio-codex/ e non è più in uso; i commit tornano al trailer «Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>». Per la ripartenza vale RIPARTENZA-4a.md in questo workspace — se sbagliato costa niente (solo file di lavoro).
SESSIONE 2026-10-15 (opus, ripresa con RIPARTENZA-4a.md): stato verificato con git — branch feat/swift-port-app, HEAD 63fd203, solo .zed/ e mjm-cleaner-ui-handoff.md non tracciati.
Task 11: fix round 1 preparato in scratch (scratchpad/t11): task-11-fix1-MainModel.swift (cinque guardie; showDone/showDockerReport costruiscono il modello prima della guardia; showXcodeReport non guardato) e task-11-fix1-MainModelTests.swift (+11 test solo-Swift: sonda, 5 blocchi, Xcode con i servizi dell'ambiente, cablaggio, dati ricevuti, picker delle Impostazioni, contatore illeggibile). RED: i 7 test del blocco falliscono sul codice attuale perché la pagina viene sostituita. GREEN: 161 + 496, nessun warning. Mutazioni in corso (70: le 63 del revisore adattate + G1–G7).
Ruling: i test di composizione (cablaggio, dati ricevuti, Xcode, picker, contatore) passano già sul codice attuale — fissano cablaggi oggi corretti contro i mutanti sopravvissuti C2–C24/F3/P7, non un difetto — se sbagliato costa nulla (sono test di regressione).
Ruling: i minor C20 (orologio), F3 (errore del contatore) e P7 (kind di .docker) si uccidono nel fix round perché costano un'asserzione o un test ciascuno — se sbagliato costa un test in più.
Task 11: fix round 1 verificato in scratch — 70 mutazioni (task-11-fix1-mutations.log, harness task-11-fix1-mutate.py): 68 uccise al primo giro; L5a (select(.cleanup) che salta showCleanup: un clic su «Pulizia» durante il passo 3 ricomincerebbe il wizard) sopravviveva dopo la correzione, uccisa da un'asserzione aggiunta a everyPageIsWiredToTheMainModel; G1–G7, L14, L5a 3 volte su 3 (task-11-fix1-mutations-rerun.log); suite 161 + 496 verde, nessun warning; CleanerFeaturesTests 10 esecuzioni su 10 verdi.
Ruling: L1 (guardia di showCleanup tolta) è ora un mutante equivalente — showCleanup passa da startOver, che è guardato — e la guardia resta: è il codice del piano, rende esplicito il blocco all'ingresso della sidebar e costa una riga — se sbagliato costa una riga ridondante.
Task 11: fix round 1 dispatched (BASE 63fd203, implementatore haiku nuovo; brief task-11-fix1-brief.md, report task-11-report.txt)
Task 11: fix round 1 implemented df51732 (MainModelTests 17, Features 161 + 496; file identici a quelli verificati; trailer verificato); scoped re-review dispatched (sonnet)
Task 11: scoped re-review (sonnet): 3 Important + 3 Minor (P7, F3, C20) ADDRESSED; mutazioni rieseguite dal revisore in una copia propria (5 guardie tolte, 2 guardie anticipate, showXcodeReport guardato, C18, C19, C20, C12, C16, C6, C11, P7, F3: 3/3; C2, C9, C13, C14: 1/1; 3 mutanti propri uccisi); 15 esecuzioni stabili; L1 confermato equivalente. Nuove rotture: nessuna Critical/Important.
Task 11: fix round 1/5 (6 addressed, 0 open — blocco per le pagine, composizione Xcode, cablaggio e dati, P7, F3, C20; commits 63fd203..df51732)
Task 11: minor (deferred): startXcodeDeletion e la sonda attendono executionStarted/scan.started senza limite (stesso schema di NavigationLockTests e XcodeViewModelTests): una regressione che non avvia l'eliminazione blocca la suite invece di farla fallire.
Task 11: minor (deferred): showDoneIsRefusedWhileXcodeDeletesButTheReportIsSaved termina con la persistenza del resoconto Xcode ancora in volo e la cartella temporanea già rimossa (innocuo: discard su un file mancante).
Task 11: minor (deferred): pagine abbandonate (fuori dal blocco Xcode) riportano al wizard come in C#; settings `private(set)` richiederà un Binding nel 4b (dalla review opus).
Task 11: complete (commits 16de08c..df51732, review clean after fix round 1)
Task 12: dispatched (BASE df51732, implementer haiku; task-12-brief.md con i numeri reali: 161 + 496, 117 solo Swift, 122/122, data 2026-10-15)
Task 12: implemented fd080b8 (161 + 496, 10/10 stabili, vincoli e confini puliti, 122/122; trailer verificato); review dispatched (sonnet)
Task 12: review (sonnet) — spec ✅, quality Approved: righe identiche al brief, 74 + 87 = 161 e 44 + 117 = 161, 78 prove C# tutte rendicontate, Core e C# intatti, 122/122, nessun confronto fra String.
Task 12: minor (deferred): ShowsTheFourSectionsAndTheEmptyFolderState (SettingsWindowTests.cs) non è nominato nella nota della riga né nelle «Prove della vista» del 4b.
Task 12: minor (deferred): la riga SettingsWindowTests dice «coperto da closingFromTheTitleBarBehavesLikeCancel», ma il collegamento vista → dismiss() (.sheet(onDismiss:)) va verificato nel 4b e non è fra le prove della vista elencate.
Task 12: minor (deferred): righe con Piano «4a» che lasciano parti al 4b (ChooseStep, HistoryView, SettingsOpening, XcodeViewLayout) non emergono filtrando la colonna Piano; la colonna «Portate» contiene il totale Swift del file (convenzione esistente).
Task 12: complete (commits df51732..fd080b8, review clean)
Final review: dispatched (opus, range 4caa1a0..fd080b8)
Final review (opus): With fixes. Important 1: DockerModel.delete() attende measureDisk nel task del chiamante (DockerModel.swift:182): un chiamante annullato durante execute fa fallire la misura con CancellationError → «Pulizia non riuscita: operazione annullata», nessun resoconto né storico di voci già rimosse (il C# usava CancellationToken.None); sonda dockerReportSurvivesACancelledCaller fallisce sul codice reale. Important 2: registro — due righe di differenze («Tile e icone delle categorie», «Navigazione delle pagine») finite nei Candidati (3 colonne); mancano i candidati home con collegamento/deny-list, Storico illeggibile senza motivo, avviso se fallisce solo il contatore, e la differenza `?? row.categoryId`. Minor: (1) Gate.wait() senza limite (M12 uccisa solo da un blocco); (2) M23 sopravvive (save da CleanerSettings() cancellerebbe selectedCategoryIds); (3) collisione dei nomi del diario al secondo (Core) da registrare; (4) commento executeFailure di FakeDocker e import Foundation in PlatformServices; (5) note per il 4b (refreshTotal all'avvio, binding di settings, executionStarted non osservato). Nessuna mutazione sopravvive su una garanzia di sicurezza (M1–M14, N8, N18 uccise; N8b equivalente).
Ruling: l'Important 1 si corregge nel codice (misura in un Task non strutturato, come CancellationToken.None del C#) con la sonda come test solo-Swift, invece della sola riga «Differenze» prevista da RIPARTENZA (d) — la perdita dello storico di una pulizia avvenuta è un difetto di dati, la correzione è una riga e rende vera la riga di registro esistente «Comandi lanciati con CancellationToken.None (… misura finale)» — se sbagliato costa una riga da riportare indietro.
Ruling: Gate.wait(within:) (Minor 1) non entra nella fix wave — richiede di riscrivere Gate e i doppi che attendono (FakeXcode.execution) e di ri-verificare le mutazioni di più task; le garanzie sono comunque uccise (con un blocco invece di un fallimento) — si propone come lavoro a parte prima del 4b — se sbagliato costa una CI che resta appesa su una regressione invece di fallire.
Ruling: nella fix wave entrano anche M23 (test solo-Swift), il commento di FakeDocker, l'import Foundation e le righe di registro del triage (candidati: pagine abbandonate che sostituiscono una pagina non del wizard, collisione dei nomi del diario; nota della riga SettingsWindowTests) — costano una riga ciascuno — se sbagliato costa righe di registro in più.
Ruling: l'import Foundation di PlatformServices.swift (minor T2/finale) resta com'è — 22 file su 36 che usano String(localized:), Core compreso, si affidano alla stessa visibilità transitiva e MemberImportVisibility non è attivo; correggerne uno sarebbe incoerente e correggerli tutti toccherebbe il Core — se sbagliato costa 22 import da aggiungere quando si attiverà MemberImportVisibility.
Final fix wave: preparata e verificata in scratch (scratchpad/fw): final-fix-DockerModel.swift (misura in un Task non strutturato), final-fix-DockerModelTests.swift (aCancelledCallerStillGetsTheReport; SequencedDocker con release e misura che fallisce in un task annullato, come DiskUsageProbe), final-fix-SettingsViewModelTests.swift (saveKeepsTheRememberedCategorySelection), final-fix-ServiceDoubles.swift (commento), final-fix-parity.py (conteggi 163/119, due righe spostate nelle Differenze, differenza `?? row.categoryId`, cinque candidati, nota SettingsWindowTests). RED: solo aCancelledCallerStillGetsTheReport fallisce (misura annullata). GREEN: 163 + 496, nessun warning; 10/10 esecuzioni stabili. Mutazioni (final-fix-mutations.log): D1 (misura nel task del chiamante) 3/3, D3 (resoconto saltato se la misura fallisce) 3/3, M23 3/3 uccise.
Final fix wave: minor (deferred): D2 (misura prima dell'esecuzione) uccisa da diskIsMeasuredAfterTheExecution solo 2 volte su 3 — corsa preesistente del test del Task 9 (execute può finire prima della misura concorrente), non introdotta dalla correzione; renderla deterministica richiede un doppio che trattenga execute finché la misura non è chiamata.
Final fix wave: dispatched (BASE fd080b8, implementatore haiku; brief final-fix-brief.md, report final-fix-report.txt)
Final fix wave: implemented ae59866 (163 + 496, file identici a quelli verificati, trailer verificato); scoped re-review dispatched (opus: tocca il componente che elimina)
Final fix wave: scoped re-review (opus): Important 1, Important 2, M23, collisione dei nomi del diario, commento di FakeDocker, candidato delle pagine abbandonate e riga SettingsWindowTests ADDRESSED; mutazioni del revisore R1–R4 e R6 uccise 3/3, R5 (= D2) 2/3 (corsa preesistente, già rinviata), R7 di controllo atteso; nessuna rottura Critical/Important (cancelDelete invariato; un'eliminazione abbandonata ora arriva a showDockerReport come il GoTo incondizionato del C#, e durante il blocco Xcode salva senza cambiare pagina).
Final fix wave: parked — candidato «Pagina abbandonata…» (parity.md:212) cita solo il wizard: anche un'eliminazione Docker abbandonata sostituisce la pagina corrente, e la proposta deve conservare la costruzione del resoconto (come il blocco Xcode) — Ruling: resta com'è nel 4a — è una riga di candidato, non codice; la precisazione va nel piano che la applicherà — se sbagliato costa una proposta letta alla lettera che farebbe perdere lo storico (chi la applica deve leggere questa riga).
Final fix wave: parked — parity.md:188 cita `row.CategoryId` dove il C# ha `category.CategoryId` — Ruling: cosmetico, resta — se sbagliato costa un nome di variabile impreciso nel registro.
Final fix wave: parked — il commento di SequencedDocker unisce le due attese (release non reagisce all'annullamento) — Ruling: cosmetico, resta — se sbagliato costa un commento impreciso in un doppio di test.
Note per il 4b (dalla revisione finale, non difetti del 4a): chiamare delete()/confirmDelete() da Task non legati alla vista e collegare «Annulla» a cancelDelete(); chiamare refreshTotal() all'avvio (in C# App.axaml.cs:51); settings è private(set): il binding di .sheet(item:) deve chiamare settings?.cancel(); canConfirmDelete legge executionStarted, che è @ObservationIgnored; Gate.wait(within:) prima dei test del 4b.
Final review: complete (commits 4caa1a0..ae59866; una fix wave, re-review pulita, 3 minor di testo parcheggiati)
Chiusura (2026-10-15): ledger copiato in docs/superpowers/decisions/2026-10-14-registro-decisioni-swift-piano-4a.md (commit del solo file); poi superpowers:finishing-a-development-branch senza merge, push né PR fino alla scelta dell'utente.
