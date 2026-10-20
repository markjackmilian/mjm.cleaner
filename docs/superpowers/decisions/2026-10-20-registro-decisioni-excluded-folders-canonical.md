# Registro delle decisioni — Cartelle escluse nella grafia del disco

Spec `docs/superpowers/specs/2026-10-20-excluded-folders-canonical-design.md`, piano `docs/superpowers/plans/2026-10-20-excluded-folders-canonical.md`, branch `feat/excluded-folders-canonical` da `feat/large-files-exclusions` 273ed4e (non ancora su `main`). Esecuzione subagent-driven del 2026-10-20.

## Sintesi

- **Chiude** due lavori successivi di `feat/large-files-exclusions` (registro `2026-10-19-registro-decisioni-large-files-exclusions.md`): la canonicalizzazione delle esclusioni (Minor 2 della revisione finale) e il test dell'analisi abbandonata nel ramo dell'annullamento («Final: parked»).
- **Cosa cambia:**
  - `FileSystem.storedForm`, la risalita all'antenato esistente, passa da `PathGuard` a una funzione condivisa del Core, senza cambiare il comportamento del guard;
  - `ExcludedFolders.resolve` confronta ogni esclusione nel testo, nella grafia del disco e, se è un collegamento, nella grafia del disco della destinazione (da `resolveLinkTarget` e come la segue il kernel). Confronta ogni elemento anche sotto la root risolta, sotto la sua grafia del disco e sotto la root seguita dal kernel;
  - un'esclusione non canonica o non verificabile, o una root non verificabile, fa sì che la regola non produca nulla, con un'unica esclusione sulla root;
  - test unitari con doppi, test d'integrazione su APFS reale, test dell'analisi abbandonata che termina con `CancellationError`.
- **Decisioni dell'utente** (brainstorming del 2026-10-20): approccio A, cioè grafia del disco una volta per regola nello scanner; un'esclusione-collegamento vale anche per la destinazione; un'esclusione non verificabile ferma la regola.
- **Scostamenti dal piano, decisi durante l'esecuzione** (dettaglio nelle righe «Ruling:» qui sotto):
  - quattro test in più nei Task 2 e 3, perché tre mutazioni sulle garanzie sopravvivevano: N9 (collegamento-esclusione risolto sul testo invece che sulla grafia del disco), N12 (grafia del disco della root dichiarata invece che risolta), N3 (destinazione aggiunta come testo). In più, il caso «contiene» per la root in NFD;
  - dopo la revisione finale, due forme in più calcolate dal kernel (`storedPath(x + "/")`), per un'esclusione-collegamento e per la root, con due test d'integrazione. Coprono le catene di collegamenti con un «..» relativo oltre una cartella collegata, dove la risoluzione testuale porta altrove. La spec è aggiornata (forme e limiti noti), insieme a README e commenti.
- **Verifica:** Core 710 test in 63 suite (erano 681 in 60), Features 232 in 23 (erano 231), nessun warning con `-warnings-as-errors`; build Debug dell'app riuscita; nessun `Localizable.xcstrings` cambiato. Fra stesura e revisioni sono state provate oltre 60 mutazioni.
  - Restano senza test quattro mutazioni equivalenti, che il revisore ha giudicato tali: deduplica delle root tolta; `hasPrefix` al posto di `isSameOrUnder` sulla root; suffisso calcolato sui byte; ordine root/esclusioni.
  - Resta senza test anche una mutazione nella direzione sicura: un fallimento di `storedPath(root + "/")` trasformato in rifiuto.
  - Le mutazioni sopravvissute del Task 4 (`isRunning` dopo il guard) non riguardano la sicurezza.
- **Mutazioni del piano più quelle aggiunte in esecuzione**, tutte uccise: M1–M14 (tabella del piano); N9, N12 (Task 2); N3 (Task 3); «senza la destinazione seguita dal kernel» e «senza la root seguita dal kernel» (correzioni finali).
- **Lavori successivi proposti:**
  - `PathGuard.validateRoot` risolve i collegamenti della root sul testo. Con un «..» relativo oltre una cartella collegata approva una root risolta inesistente, e la deny-list ricorsiva guarda il percorso sbagliato. La protezione degli elementi resta nel `validate`, che usa la grafia del disco. È preesistente;
  - al passo 3, raggruppare le esclusioni con lo stesso motivo, o un avviso dedicato, quando un'esclusione non valida ferma ogni regola: oggi ogni root ripete il motivo, e il passo 2 mostra «0 elementi» senza spiegazione;
  - calcolare le forme delle esclusioni una volta per analisi invece che per regola: conta con un volume di rete che non risponde;
  - piccole correzioni: README «a `.` or `..` component» invece di «`.` or `..`»; un test per il fallimento di `storedPath(root + "/")`; un caso a due livelli in `StoredFormTests`; `#expect(!abandoned.isRunning)` nel test del Task 4.
- **Frasi nuove per la tabella del piano di localizzazione** (Core): «cartella esclusa con un percorso non valido: «\(testo)»», «cartella esclusa non verificabile sul filesystem: \(errore)». La fabbrica riusa «root non verificabile sul filesystem: \(errore)», già in `PathGuard`. I test di `ExcludedFoldersDiskSpellingTests` confrontano il testo italiano.
- **Possibili conflitti con i branch fratelli** (note delle sessioni sorelle):
  - `feat/package-exclusions-folder-warning` tocca lo stesso paragrafo del README sulle cartelle escluse e `MainModelTests.swift`;
  - `feat/confirmation-containment` tocca solo righe vicine del README.

## Registro SDD (copia del ledger)


Spec: docs/superpowers/specs/2026-10-20-excluded-folders-canonical-design.md
Worktree: .claude/worktrees/mystifying-shaw-38cff4, branch feat/excluded-folders-canonical, creato da feat/large-files-exclusions (273ed4e); spec 8af2b37, piano 5feeb50.
Partenza: Core 681 test in 60 suite, Features 231 in 23.
Modelli: implementatori haiku (fix round al massimo sonnet); revisori opus per Task 1 e 2 e per la revisione finale, sonnet per Task 3 e 4; ri-revisioni sonnet.

## Verifica preliminare del piano

| Coppia / task | Produce → consuma | Esito |
|---|---|---|
| T1 → T2 | T1 produce `FileSystem.storedForm(_:) -> Result<String, FileSystemError>`; T2 la chiama da `ExcludedFolders` (esclusioni, destinazione, root risolta) | coerente: firma identica nei due brief |
| T1 ↔ T2 su `PathGuard.swift` | solo T1 lo modifica; T2 non lo tocca | nessun conflitto |
| T2 → T3 | T2 crea `ExcludedFolders.swift` con la riga `forms.append(PathText.trimmingTrailingSlashes(stored))`; T3 la elimina temporaneamente e la ripristina con `git checkout --` | coerente se T2 è committato prima di T3 (lo è per ordine) |
| T2 → T3 su comportamento | T3 attende 5 test verdi e 4 falliti con M1: dipende dalle forme del disco di T2 | coerente con la tabella delle mutazioni |
| T4 ↔ altri | T4 tocca solo `MainModelTests.swift` e muta temporaneamente `ScanStepModel.swift` (Features) | nessun file condiviso |
| README | solo T2 | nessun conflitto |
| T1 (interno) | test con `AliasingFileSystem(aliases:failures:)` (inner predefinito) e un doppio privato; codice `StoredForm.swift` + 6 modifiche a `PathGuard` | coerente; il controllo `grep` attende 5 righe, misurato |
| T2 (interno) | 15 test, RED misurato 14/15 falliti; `ExcludedFolders` riscritto; `RuleScanner` una sostituzione; README | coerente; `Recorder` viene da `CleanerCoreTests/Support/TestSupport.swift`, `Mutex` dall'`import Synchronization` del file |
| T3 (interno) | 5 test d'integrazione, passano subito; passo «mordono» con M1 | non è TDD classico: il comportamento arriva da T2 (vedi Ruling) |
| T4 (interno) | test + doppio `CancellableGatedScan`; passa subito; passo «morde» togliendo il guard | come T3 |
| Rubrica vs piano | test che non asseriscono nulla? no; duplicazione di logica? i doppi `StoredPathLogFileSystem`/`StoredPathFailingLaterFileSystem` sono nuovi e diversi da quelli esistenti | nessun difetto imposto |

Ruling: i Task 3 e 4 aggiungono test che passano appena scritti, con un passo di mutazione temporanea al posto del RED — il comportamento lo consegna il Task 2 (T3) o esiste già (T4), e la spec chiede proprio questi test — se sbagliato costa solo la forma del ciclo TDD, non la copertura (le mutazioni dimostrano che mordono).

## Avanzamento
Task 1: implementer haiku a061ef48d01fd2cc9, commit 93a46cf (685/231), DONE.
Task 1: review opus a01459818eb03a890: spec ✅, Approvato; 13 mutazioni (M9, M10 + 11 nuove) tutte uccise; ⚠️ commenti che citano ExcludedFolders prima del Task 2 — risolto dal Task 2 sullo stesso branch.
Task 1: minor (deferred): StoredFormTests non fissa l'ordine di più componenti mancanti (senza reversed() solo PathGuardTests fallisce); aggiungere un caso a due livelli.
Task 1: minor (deferred): ForeignErrorFileSystem duplica NonFileSystemErrorStoredPathFileSystem di PathGuardTests (imposto dal piano, PathGuardTests invariato); spostarlo in Support/ in una pulizia.
Task 1: complete (commits 5feeb50..93a46cf, review clean)
Task 2: implementer haiku af3cf71c33be12943, commit d0f9c1a (700/231), DONE; dubbio «step 3» nel README: infondato, il README chiama così il passo «3 · Confirm» della sua tabella del wizard.
Task 2: review opus a477e927b94094767: spec ✅ (identico al brief byte per byte), Da correggere: 2 Important imposti dal piano (mutazioni nuove sopravvissute): N9 collegamento-esclusione riconosciuto/risolto sul testo canonico invece che sulla grafia del disco; N12 storedForm della root dichiarata invece che della risolta. Mutazioni del piano M1–M8, M11–M13 uccise; N2, N3, N4, N8 sopravvissute ma equivalenti (giudizio del revisore).
Ruling: aggiungere i test A (anExclusionWrittenThroughALinkThatIsItselfALinkAlsoExcludesItsTarget) e B (anExclusionInTheDiskSpellingOfALinkedRootMatches) proposti dal revisore — la spec dice «se la forma del disco è un collegamento» e «storedForm della root risolta», e senza test una regressione renderebbe non valide esclusioni reali — se sbagliato costa due test in più: Core +2 (dopo T2 702/62, dopo T3 707/63; i «705» dei brief 3 e 4 diventano 707).
Ruling: nello stesso giro parametrizzare anExclusionInTheDiskSpellingMatchesARootDeclaredInAnotherNormalization con il caso «contiene» (Minor 2 del revisore) — la spec (§Test) chiede per ogni caso esclusione diretta e «contiene» — se sbagliato costa un argomento in più, nessun cambio di conteggio.
Task 2: minor (deferred): aRootThatStopsBeingVerifiableAfterValidationStopsTheRule dipende dal fatto che validateRoot chieda storedPath(root) una sola volta; se il guard lo chiedesse due volte il test passerebbe per il rifiuto del guard senza coprire resolve.
Task 2: fix round 1/5 (3 addressed, 0 open — test A uccide N9, test B uccide N12, «contiene» con root NFD uccide candidateReason senza forme alternative; re-review sonnet a75799cbbeb364339; commits d0f9c1a..f3c7ad9; Core 702/62, Features 231/23)
Task 2: complete (commits 93a46cf..f3c7ad9, review clean)
Task 3: implementer haiku a1e1247caddfb9253, commit f0a064f (707/231), DONE; passo «mordono» 4/5 come atteso, Sources ripristinato.
Task 3: review sonnet a9cd4ddbaa83f65bc: spec ✅ (identico al brief), Da correggere: 1 Important imposto dal piano — N3 (destinazione del collegamento-esclusione aggiunta come testo invece che con storedForm(target)) sopravvive a tutto il package. M1, M2, M3, M13 uccise; N1b, N5 equivalenti; N11 uccisa dai test unitari. Il revisore ha provato anche un volume APFS case-sensitive in un'immagine scratch (smontata ed eliminata): test 3 saltato, gli altri verdi.
Ruling: aggiungere il test d'integrazione anExclusionThatIsARealLinkExcludesItsTargetInTheDiskSpelling proposto dal revisore (root dichiarata /private/var, collegamento verso /var/…) — la spec chiede la grafia del disco della destinazione e senza test la regressione lascerebbe proporre la cartella puntata — se sbagliato costa un test: Core 708/63 (il «707» del brief 4 diventa 708); N3 va nella tabella delle mutazioni del registro.
Task 3: minor (deferred): #require su /var fa fallire invece di saltare se $TMPDIR non sta sotto /var (convenzione già in uso); #expect(mkdir…) non interrompe il test (come StoredPathTests); l'integrazione non copre candidateReason né la root sotto un'esclusione (coperti dai test unitari).
Task 3: fix round 1/5 (1 addressed, 0 open — test con root /private/var e collegamento verso /var uccide N3 da solo; re-review sonnet a11a9589831bd767d; commits f0a064f..bc3b0eb; Core 708/63, Features 231/23)
Task 3: complete (commits f3c7ad9..bc3b0eb, review clean)
Task 4: implementer haiku a4188ca79772fa115, commit 96f242f (708/232, app BUILD SUCCEEDED), DONE; mutazione del guard: fallisce solo il test nuovo.
Task 4: review sonnet afb7ffcc9a9f8e6c6: spec ✅, Approvato; M14 uccisa 25/25 sotto carico; M15–M19, M21–M24 uccise; M26/M22b (isRunning dopo il guard) sopravvissute, non di sicurezza.
Task 4: minor (deferred): manca #expect(!abandoned.isRunning) (M26 sopravvive; il test fratello del successo non lo asserisce); #expect(current.isRunning) non discrimina (later ignora l'annullamento); dump rumoroso dell'identità ===; runningAppsCheck di ConfirmStepModel non atteso a fine test.
Task 4: complete (commits bc3b0eb..96f242f, review clean)
Revisione finale: opus ac7f562e5c2001bec, «Con correzioni (leggere)»: 0 Critical, 0 Important, 4 Minor; tutti i minor rinviati dei task giudicati «resta». Verifica controller: Core 708/63, Features 232/23, app BUILD SUCCEEDED, worktree pulito.
Ruling: correggere il Minor 1 (catena di collegamenti con «..» relativo oltre una cartella collegata: resolveLinkTarget risolve sul testo e l'esclusione, o la root, finisce su un percorso diverso da quello del kernel) aggiungendo due forme: storedPath(forma del disco + "/") per un'esclusione-collegamento e storedPath(root + "/") fra le forme della root, con due test d'integrazione dalle sonde del revisore — è la direzione non sicura, la decisione dell'utente era «vale anche per la destinazione finale» e la destinazione vera è quella del kernel; aggiungere forme può solo escludere di più — se sbagliato costa due chiamate a storedPath in più per regola con esclusioni e due test; la spec si aggiorna (forme e limiti noti).
Ruling: nello stesso giro i Minor 2–4 (README «not a plain absolute path», commento neutro in StoredForm, commento di RuleScanner con la root non verificabile) — economici e nello stesso intervento — se sbagliato costa solo testo.
Ruling: restano fuori, come lavori successivi, il raggruppamento delle esclusioni con lo stesso motivo al passo 3, il calcolo delle forme una volta per analisi e la risoluzione testuale della root in PathGuard.validateRoot (preesistente) — fuori dall'ambito della spec — se sbagliato il rischio resta documentato nel registro.
Correzioni finali: fixer sonnet a5afecf231df6748f, commit 01d88bd (710/232), DONE; mutazioni senza (a) / senza (b) uccise ciascuna dal proprio test.
Correzioni finali: ri-revisione opus aab368c33a42ae7aa: 4/4 ADDRESSED; senza (a) e senza (b) uccise ciascuna dal proprio test; chiamata sulla root sopra il guard uccisa; errore della forma del kernel trasformato in rifiuto ucciso (3 test).
Final: parked — un fallimento di storedPath(root + "/") trasformato in rifiuto sopravvive a tutto il package — Ruling: il codice è corretto e la mutazione va nella direzione sicura (la regola non produce nulla); un test con un ForwardingFileSystem che lancia EIO su root + "/" è un lavoro successivo da una riga — se sbagliato costa un rifiuto superfluo dopo una regressione futura.
Final: parked — README «containing `//`, `.` or `..`» si può leggere come «qualunque punto» (~/.docker) — Ruling: impreciso ma non pericoloso; da riformulare in «a `.` or `..` component» in un lavoro successivo — se sbagliato costa un utente che evita di escludere una cartella nascosta.
Final: parked — riga di commento di 103 colonne in ExcludedFolders.swift:66; la spec non elenca i due test d'integrazione e le mutazioni (a)/(b) — Ruling: cosmetico, il registro li elenca — se sbagliato nessun costo.
