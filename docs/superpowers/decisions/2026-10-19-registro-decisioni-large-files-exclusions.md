# Registro delle decisioni — Download e File grandi separati, cartelle escluse, «Seleziona tutte»

Spec `docs/superpowers/specs/2026-10-19-large-files-exclusions-design.md`, piano `docs/superpowers/plans/2026-10-19-large-files-exclusions.md`, branch `feat/large-files-exclusions` da `main` 41f824e. Esecuzione subagent-driven del 2026-10-20.

## Sintesi

- **Chiude** la segnalazione dell'utente del 2026-10-19: i dischi Parallels (`.pvm`) comparivano già spuntati al passo 3 fra «Download e file grandi». Le cause erano due. `PathNode.isSelected` partiva vero per ogni voce, contro la spec originale §6.5, un difetto ereditato dal C#. E `matchingFiles` scendeva nei pacchetti macOS.
- **Cosa cambia:**
  - due categorie, `downloads` e `large-files`, con le voci deselezionate al passo 3;
  - le cartelle escluse nelle Impostazioni, valide per tutto il wizard;
  - i pacchetti macOS come unità in Download, File grandi e Log;
  - la casella «Seleziona tutte le voci» per ogni gruppo del passo 3.
- **Scostamenti dal piano, decisi durante l'esecuzione** (dettaglio nelle righe «Ruling:» qui sotto):
  - test in più nei Task 1–3, perché le mutazioni sulle garanzie sopravvivevano: collegamento `.utm`, cartella `.pvm` e lista delle estensioni fissata; caso «contiene» con root risolta e senza maiuscole; `bin` mai misurato; pacchetto con timestamp non determinabile. Il Core passa così da 679 a 681 test;
  - `considerPackage` e il ramo «matches» di `scanDirectories` sono unificati in `proposeWholeDirectory`, unico punto dell'ordine guard → esclusioni → statistiche;
  - `Scripts/make-assets.py` aggiornato, perché altrimenti avrebbe ricreato `TileDownloadsLarge`;
  - il paragrafo del README sulle esclusioni è riformulato: una cartella che contiene un'esclusione si attraversa, e si scarta solo un candidato da eliminare per intero;
  - dopo la revisione finale `startOver()` abbandona l'ultima analisi: Salva nelle Impostazioni durante un'analisi non porta più a un passo 3 calcolato con le impostazioni vecchie. La spec è allineata (8ca59f2).
- **Verifica:** 681 test in 60 suite (Core) e 231 in 23 (Features), nessun warning; build Debug dell'app riuscita; nessun `Localizable.xcstrings` cambiato. Fra stesura e revisioni sono state provate oltre 90 mutazioni. Ne sopravvivono quattro, nessuna su una garanzia raggiungibile: `parentId` di `downloads` (T4), `allSelected` su un gruppo vuoto (T6, caso irraggiungibile), `abandon` dopo il guard di navigazione (finale, caso irraggiungibile), il guard `!abandoned` nel ramo dell'annullamento (finale, senza test perché `GatedScan` ignora l'annullamento).
- **Lavori successivi proposti:**
  - deduplicazione del passo 3 consapevole del contenimento: oggi una voce deselezionata dei File grandi si cancella se una cartella che la contiene è spuntata in un'altra categoria;
  - canonicalizzazione delle esclusioni: collegamenti sotto la root, `/var` contro `/private/var` dichiarato, NFC/NFD, ripiegamento di APFS;
  - scelta di un singolo pacchetto nel pannello delle esclusioni (`treatsFilePackagesAsDirectories`);
  - un test per l'analisi abbandonata che passa dal ramo dell'annullamento;
  - un avviso per «File grandi» senza cartelle configurate.
- **Frasi nuove per la tabella del piano di localizzazione:**
  - Core: «cartella esclusa nelle Impostazioni», «contiene una cartella esclusa nelle Impostazioni», «Download», «File in Download non usati da tempo. Contiene dati reali: nella verifica ogni voce parte deselezionata.», «File grandi», «File e pacchetti oltre la soglia, nelle cartelle scelte nelle Impostazioni. Contiene dati reali: nella verifica ogni voce parte deselezionata.». Escono dal Core «Download e file grandi» e la sua descrizione.
  - Features: «Download e file grandi» (nome storico), «Scegli una cartella da escludere», «Seleziona tutte le voci di \(nome)».
  - App: «Cartelle escluse», «Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.», «Dati reali: le voci partono deselezionate. Spunta solo ciò che vuoi eliminare.», «Seleziona tutte le voci».
  - I test di `SettingsViewModelTests` confrontano il testo italiano del titolo del pannello.

## Registro SDD (copia del ledger)


Spec: docs/superpowers/specs/2026-10-19-large-files-exclusions-design.md
Worktree: .claude/worktrees/large-files-exclusions, branch feat/large-files-exclusions, base 41f824e (main).
Baseline nel worktree: Core 648 test / 58 suite, Features 219 / 23.

Modelli (preferenze utente): implementatori haiku (codice completo nel brief), fix round al massimo sonnet; revisori sonnet; opus per le revisioni dei Task 2, 3 e 6 e per la revisione finale. Mutazioni nelle revisioni dei Task 1, 2, 3, 4 e 6.

## Controllo preliminare

Il piano è già stato applicato meccanicamente, blocco per blocco, a una copia pulita di main (script apply_plan.py nello scratchpad della sessione di stesura): 69 blocchi applicati, risultato identico alla copia collaudata; per ogni task gli errori RED attesi e i conteggi GREEN tornano (Core 650/662/672/679/679/679/679, Features 219/219/219/221/224/229/229), build app riuscita, xcstrings invariati.

| Coppia o task | Cosa produce / consuma | Esito |
|---|---|---|
| T1 → T2 | ForwardingFileSystem.isPackage (T1) serve ad AccessLogFileSystem nei test di T2 | coerente |
| T1 → T3 | FileSystem.isPackage, InMemoryFileSystem.addPackage (T1) usati da RuleScanner e PackageScanTests (T3) | coerente |
| T2 → T3 | RuleScanner.swift: T3 sostituisce il blocco di potatura che T2 introduce in scanFiles; considerPackage usa ExcludedFolders di T2 | il testo «old» di T3 coincide con il «new» di T2 (verificato dallo script) |
| T2 → T4 | CleanupRule.swift: T2 aggiunge excludedPaths, T4 aggiunge excluding dopo l'init | coerente |
| T4 → T5 | CleanerSettings.excludedFolders (T4) usato da SettingsModel (T5) | coerente |
| T4 → T6 | CleanupCategory.itemsSelectedByDefault (T4) usato da ConfirmStepModel e makeCategory (T6) | coerente |
| T4 → T7 | ID large-files ed excludedFolders (T4) usati dalla demo (T7) | coerente |
| T5 / T6 | viste distinte (SettingsView, ConfirmStepView), test distinti | nessuna sovrapposizione |
| T1 | test LocalFileSystem/InMemory contro isPackage e addPackage | coerente |
| T2 | 12 test contro ExcludedFolders e i tre modi dello scanner | coerente |
| T3 | 10 test; RED atteso: 6 falliscono, 4 passano già (dichiarato nel brief) | coerente |
| T4 | test catalogo/impostazioni/features contro catalogo, visuals, nomi storici, asset | coerente; rinomina asset con git mv |
| T5 | 3 test contro SettingsModel; Fixture con picker | coerente |
| T6 | 5 test contro CategoryNode/ConfirmStepModel; makeCategory con parametro predefinito | coerente |
| T7 | solo demo e README, nessun test nuovo | coerente |
| Rubrica | test che non asseriscono nulla: nessuno. Duplicazione verbatim di logica: considerPackage ripete lo schema guard→statistiche→età→soglia di scanContents/scanDirectories, che nel file esistente è già ripetuto per modo; non è un blocco verbatim | nessun conflitto da decidere |

Esito: nessun conflitto da decidere prima del Task 1.

## Avanzamento
Task 1: implementer haiku abc9fd979846dc757, commit 1fd550e (650/219). Review sonnet a32f1ebac81f049fb: spec ✅, 2 Important imposti dal piano.
Ruling: aggiungere al test isPackageRecognisesBundlesAndVirtualMachines un collegamento «collegamento.utm» (deve valere falso), una cartella «Windows 11.pvm» (deve valere vero) e l'uguaglianza della lista delle estensioni a {pvm, vmwarevm, utm} — la spec (§Test) chiede «x.pvm lo è grazie al ripiego» e il contratto «un collegamento non è mai un pacchetto»; il piano non li traduceva in asserzioni (mutazioni stat al posto di lstat e lista senza pvm sopravvivevano) — se sbagliato costa tre asserzioni in più, nessun cambiamento di comportamento.
Task 1: minor (deferred): InMemoryFileSystem.deleteDirectoryRecursively non toglie il percorso da packages: una cartella ricreata con addDirectory risulta ancora pacchetto (nessun test successivo lo fa); il report dell'implementatore afferma il contrario.
Task 1: minor (deferred): commenti di produzione con misure datate (2026-10-19, 20 µs) in LocalFileSystem.swift — imposti dal piano.
Task 1: minor (deferred): le asserzioni su utm/vmware discriminano il ripiego solo dove UTM e VMware Fusion non sono installati; manca un commento che lo dica.
Task 1: minor (deferred): ForwardingFileSystem.isPackage non è esercitato direttamente da test del Task 1 (lo usano i Task 2–3 via AccessLogFileSystem).
Task 1: fix round 1/5 (2 addressed, 0 open — lstat e pvm ora protetti; mutazioni stat e lista senza pvm uccise; commits 1fd550e..4b3154e)
Task 1: complete (commits 41f824e..4b3154e, review clean)
Task 2: implementer haiku ad0577a7cb548b845, commit db20bf7 (662/219), DONE_WITH_CONCERNS (trailer, xcstrings: osservazioni).
Task 2: review opus aaa03eeaab2174ea1: spec ✅ salvo scostamenti imposti dal piano; 1 Important (imposto dal piano): caso «contiene» non protetto con root risolta né senza maiuscole (mutazioni A e B sopravvissute).
Ruling: aggiungere un test «contiene» con esclusione scritta sul percorso risolto sotto $TMPDIR e parametrizzare matchingDirsDoesNotProposeABinThatContainsAnExclusion con una grafia a maiuscole diverse, aggiungendovi AccessLogFileSystem per provare che il bin non si misura — la spec chiede che un candidato che contiene un'esclusione non si proponga e che il controllo sia testuale senza attraversare; il piano non lo copriva — se sbagliato costa un test in più: da qui i conteggi del Core del piano sono +1 (Task 2: 663, Task 3: 673, Task 4–7: 680).
Ruling: il Minor 2 della revisione (mutazione F, bin misurato prima di candidateReason, sopravvissuta) entra nello stesso fix invece di essere rinviato — tocca lo stesso test del rilievo Important ed è una garanzia di sicurezza — se sbagliato costa una riga di asserzione.
Task 2: minor (deferred): in scanDirectories l'esclusione dell'utente precede la deny-list (la spec dice che la segue): cambia solo il motivo mostrato per una cartella negata ed esclusa; imposto dal piano, deciso in stesura.
Task 2: minor (deferred): ExcludedFolders eredita il ripiegamento OrdinalIgnoreCase, meno ampio di APFS (NFC/NFD, ß, U+212A): un'equivalenza persa fa riconoscere di meno un'esclusione; rischio basso perché pannello e enumerazione danno percorsi del filesystem.
Task 2: minor (deferred): forms() ricalcola equalsIgnoringCase(root, resolvedRoot) per ogni percorso anche senza esclusioni; in scanDirectories candidateReason ripete excludedReason già fatto.
Task 2: fix round 1/5 (3 addressed, 0 open — caso «contiene» con root risolta e senza maiuscole, bin non misurato; mutazioni A, B, F uccise; commits db20bf7..9dd5376)
Task 2: minor (deferred): aChildContainingAnExclusionWrittenOnTheResolvedRootIsNotProposed non usa AccessLogFileSystem (il caso testuale è già coperto da clearContentsSkipsAChildThatContainsAnExclusionWithoutMeasuringIt).
Task 2: complete (commits 4b3154e..9dd5376, review clean)
Task 3: implementer haiku add41c574b9d2cefd, commit 08b1827 (673/219), DONE.
Task 3: review opus a53b2ec992bc19d77: spec ✅; 2 Important imposti dal piano: (A) timestamp non determinabile di un pacchetto senza test (mutazione sopravvissuta); (B) considerPackage duplica quasi verbatim il ramo «matches» di scanDirectories.
Ruling: aggiungere aPackageWithoutADeterminableStampIsNotProposed (pacchetto con data della cartella 1980, minAge 90 giorni, nessun elemento) — la spec dice «si scarta se il timestamp non è determinabile» — se sbagliato costa un test; i conteggi del Core salgono di un altro +1 (Task 3: 674, Task 4–7: 681).
Ruling: unificare considerPackage e il ramo «matches» di scanDirectories in proposeWholeDirectory (stesso ordine: guard, esclusioni, statistiche, determinabilità/età, soglia), con i glob dei pacchetti controllati dal chiamante in scanFiles — l'ordine guard→esclusioni→statistiche è la garanzia di sicurezza e due copie rischiano di divergere; scanDirectories cambia solo per estrazione — se sbagliato costa un refactor non previsto dal piano, coperto da MatchingDirsTests, ExcludedFoldersScanTests e PackageScanTests.
Task 3: minor (deferred): un pacchetto alla profondità maxDepth si propone e directoryStats ne attraversa l'albero senza limite; oggi nessuna regola matchingFiles ha maxDepth finito.
Task 3: minor (deferred): aPackageTheGuardRejectsIsNeverMeasured prova che nessun file interno viene letto, non che il pacchetto non venga elencato (AccessLogFileSystem registra solo fileExists e itemInfo).
Task 3: minor (deferred): nessun test per una root che è essa stessa un pacchetto (corretta per costruzione: enter(rule.root)).
Task 3: fix round 1/5 (2 addressed, 0 open — test del timestamp non determinabile; helper unico proposeWholeDirectory; mutazioni su determinabilità, guard prima delle statistiche, candidateReason, glob tutte uccise; commits 08b1827..da467b8)
Task 3: minor (deferred): il test del timestamp non determinabile non controlla errors né exclusions (coerente con il caso clearContents).
Task 3: complete (commits 9dd5376..da467b8, review clean)
Task 4: implementer haiku a3452b217221956ba, commit fe5289e (681/221, app BUILD SUCCEEDED), DONE_WITH_CONCERNS: Scripts/make-assets.py elenca ancora TileDownloadsLarge e non genera TileDownloads né TileLargeFiles.
Ruling: aggiornare Scripts/make-assets.py nel Task 4 (TileDownloadsLarge → TileDownloads #E8833A, nuova TileLargeFiles #B5477F) e verificare che lo script, eseguito in una cartella temporanea, rigeneri esattamente le colorset committate — lo script è la fonte del catalogo asset (spec §6.4 del redesign) e rieseguirlo ricreerebbe l'asset vecchio; il piano non lo nominava — se sbagliato costa due righe in uno script fuori dall'elenco dei file del piano.
Task 4: review sonnet a9c797d146da6678c: spec ✅, Approvato, 17/18 mutazioni uccise, nessun Critical/Important.
Task 4: minor (deferred): parentId nil di downloads e large-files non asserito (mutazione «downloads figlia di dev-caches» sopravvive; nessun rischio per i dati).
Task 4: minor (deferred): CleanupRule.excluding e CleanupCategory.excluding sostituiscono excludedPaths invece di aggiungerli (nessuna regola del catalogo ne ha di proprie oggi).
Task 4: minor (deferred): excludedFoldersReachEveryRuleAlreadyExpanded fissa rules.count == 13 (guardia contro la vacuità, imposta dal piano).
Task 4: complete (commits da467b8..442b180, review clean)
Task 5: implementer haiku af5d13950f8fe935a, commit 09d879c (681/224, app BUILD SUCCEEDED), DONE.
Task 5: review sonnet a71b73f1520edc90b: spec ✅, Approvato, 6/6 mutazioni uccise. ⚠️ Salva → startOver(): verificato dal controller in MainModel.swift:104 (onSaved: startOver), codice esistente.
Task 5: minor (deferred): excludedFoldersAreLoadedAddedRemovedAndSaved concentra più comportamenti in un test (imposto dal piano).
Task 5: minor (deferred): asserzioni sul testo italiano «Scegli una cartella da escludere»: il piano l10n dovrà tenerne conto.
Task 5: complete (commits 442b180..09d879c, review clean)
Task 6: implementer haiku a484d5215dbb59888, commit b02d842 (681/229, app BUILD SUCCEEDED), DONE.
Task 6: review opus a75a8afc5327e71e9: spec ✅, Approvato, 6/7 mutazioni uccise (sopravvive solo «gruppo vuoto letto come tutto selezionato», caso non raggiungibile).
Task 6: minor (deferred): manca il test di allSelected su gruppo vuoto (la spec elenca «vuoto, misto, tutto»; ConfirmationRows scarta le categorie vuote, nessun effetto sulla cancellazione).
Task 6: minor (deferred): avviso e casella di gruppo spariscono a gruppo chiuso (dentro il DisclosureGroup), coerente con le voci; il gruppo parte espanso.
Task 6: complete (commits 09d879c..b02d842, review clean)
Task 7: implementer haiku a1a69917ce65dd83f, commit a48664f (681/229, app BUILD SUCCEEDED), DONE; Step 5 (screenshot) riservato al controller.
Task 7: review sonnet acde2b01be04f48f8: spec ✅; 1 Important imposto dal piano: README dice che anche una cartella che contiene un'esclusione non viene «scanned», ma lo scanner la attraversa e scarta solo i candidati da eliminare interi.
Ruling: riformulare il paragrafo del README sui pacchetti e sulle esclusioni (pacchetti unità solo in Downloads/large files/logs; cartella esclusa mai analizzata né proposta; un candidato eliminato per intero — sottocartella di cache, bin/obj, pacchetto — non si propone se contiene un'esclusione; Xcode e Docker non le usano) — la documentazione deve descrivere il comportamento della spec e del codice; il Minor 1 (pacchetti «never entered» troppo generale) entra nello stesso fix perché è la stessa frase — se sbagliato costa una riformulazione.
Task 7: minor (deferred): DemoData.item imposta isDirectory: true anche per Xcode_26.xip (nessuna vista lo legge).
Task 7: minor (deferred): la demo del passo 3 non mostra il motivo «cartella esclusa nelle Impostazioni» nel riquadro delle esclusioni (exclusions sempre vuote).
Task 7: fix round 1/5 (2 addressed, 0 open — paragrafo del README su pacchetti ed esclusioni riformulato; commits a48664f..68a4705)
Task 7: complete (commits b02d842..68a4705, review clean)
Revisione finale: opus a9312e14aaa3fa91a, «Con correzioni»: 0 Critical, 1 Important (Salva durante l'analisi → passo 3 con impostazioni vecchie, cartella appena esclusa spuntata; gara preesistente, ora via per aggirare le esclusioni), 5 Minor; tutti i minor rinviati dei task giudicati «può restare».
Ruling: correggere l'Important con MainModel.lastScan + ScanStepModel.abandon(): startOver() abbandona l'ultima analisi anche se il cambio di pagina è rifiutato, e un'analisi abbandonata non chiama più showConfirm né startOver — la spec (§Impostazioni) garantisce che nessun passo 3 resti calcolato con le impostazioni precedenti; il riferimento all'ultima analisi copre anche il caso «passato a un'altra pagina prima di salvare» — se sbagliato costa un cambio di comportamento: «Pulizia» da un'altra pagina (che chiama startOver) ora abbandona anche un'analisi rimasta in background invece di lasciarla arrivare al passo 3.
Ruling: nello stesso intervento la fixture neutra in ConfirmStepModelTests (Minor 4) e l'allineamento di due frasi della spec (Minor 5) — economici e nello stesso giro — se sbagliato costa due commit di sola documentazione/test.
Ruling: Minor 1 (voce deselezionata cancellata attraverso la cartella di un'altra categoria), Minor 2 (canonicalizzazione delle esclusioni) e Minor 3 (escludere un singolo pacchetto dal pannello) restano fuori da questo branch e vanno proposti come lavori successivi — richiedono un design proprio — se sbagliato il rischio residuo resta documentato e le voci partono comunque deselezionate.
Correzioni finali: implementer sonnet a956b99aae03ab27f, commits 68a4705..8ca59f2 (1bfb38b, c154946, 8ca59f2), Core 681/60, Features 231/23, app BUILD SUCCEEDED. Ri-revisione opus adbab965c62ea2381: 3/3 risolti, nessun nuovo Critical/Important; mutazioni «senza abandon in startOver» e «senza guard dopo lo scan riuscito» uccise.
Final: parked — il guard !abandoned nel ramo CancellationError di ScanStepModel.perform non è coperto da test (GatedScan ignora l'annullamento) — Ruling: il codice è corretto e senza il guard l'effetto sarebbe ricreare il passo 1 o abbandonare una nuova analisi, mai mostrare un passo 3 vecchio; resta un test da aggiungere in un lavoro successivo — se sbagliato costa un'analisi nuova annullata per errore.
Final: parked — la mutazione «abandon dopo il guard canNavigateGlobally» sopravvive — Ruling: descrive Salva mentre Xcode elimina, irraggiungibile dall'interfaccia (Impostazioni disabilitate); la scelta resta difensiva — se sbagliato nessun costo.
Final: minor (deferred): commento in ConfirmStepModelTests.swift:17 parla ancora di «file grandi»; la spec per matchingDirs dice «segue .git» ma il controllo copre .git/.hg/.svn.
Final: minor (deferred): il nuovo comportamento «Pulizia» o «Chiudi» da un'altra sezione abbandona un'analisi in background (coerente con la spec del porting §6.3) non è testato.
