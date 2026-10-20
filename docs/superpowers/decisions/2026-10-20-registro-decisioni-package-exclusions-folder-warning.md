# Registro delle decisioni — pacchetti fra le cartelle escluse, avviso per le categorie senza cartelle

Spec `docs/superpowers/specs/2026-10-20-package-exclusions-folder-warning-design.md`, piano `docs/superpowers/plans/2026-10-20-package-exclusions-folder-warning.md`, branch `feat/package-exclusions-folder-warning` da `feat/large-files-exclusions` (273ed4e, non ancora su `main`). Esecuzione subagent-driven del 2026-10-20.

## Sintesi

- **Chiude** due lavori successivi proposti dal registro `2026-10-19-registro-decisioni-large-files-exclusions.md`: la scelta di un singolo pacchetto nel pannello delle esclusioni e l'avviso per «File grandi» senza cartelle configurate.
- **Cosa cambia:**
  - nel pannello delle cartelle escluse si sceglie anche un pacchetto macOS intero (`.pvm`, `.app`, `.logarchive`…). `FolderPicking.pickFolder(title:allowsPackages:)` lo chiede solo da `SettingsModel.addExcludedFolder()`. `AppKitFolderPicker` usa `canChooseFiles = true`, `allowedContentTypes = [.package]` e `treatsFilePackagesAsDirectories = false`; i file normali restano grigi. Lo scanner non cambia: un pacchetto escluso si pota già in tutte e tre le modalità;
  - al passo 1, «Cartelle bin e obj nei progetti» e «File grandi» senza cartelle nelle Impostazioni sono disattivate e deselezionate, con «Nessuna cartella da analizzare.» e il pulsante-link «Apri Impostazioni…». La garanzia sta nel modello: `CategoryChoice.isSelected` vale `selected && isAvailable`, quindi una categoria senza regole non entra né nel contatore né nell'analisi né nella selezione salvata. Salva nelle Impostazioni ricrea il passo 1 con le categorie nuove;
  - effetto in più, voluto: al primo avvio la selezione predefinita contiene `project-build-output` senza cartelle di progetto. Ora la riga compare disattivata e il contatore dice «3 categorie selezionate».
- **Verifica del comportamento di partenza**, senza avviare l'app. Una sonda non interattiva sui tipi ha dato:
  - `Windows 11.pvm` (Parallels installato), `Prova.app` e `Sistema.logarchive` sono pacchetti, quindi nel pannello di prima non si potevano scegliere;
  - `Linux.utm` e `Ubuntu.vmwarevm` risultano `public.folder`, perché le loro app non sono installate, e si sceglievano già.
- **Scostamenti dal piano, decisi durante l'esecuzione** (dettaglio nelle righe «Ruling:» qui sotto). Dopo la revisione finale:
  - un test del giro completo «Apri Impostazioni…» → Salva → passo 1 ricreato. Senza, la mutazione `if case .choose = page { return }` in `startOver()` sopravviveva a tutta la suite;
  - un test del Core per un pacchetto escluso in sé, con la barra finale del pannello. Il Core passa così da 682 a 683 test;
  - hint VoiceOver sulla casella disattivata, `fixedSize` sul testo dell'avviso e quattro commenti corretti.
- **Verifica:**
  - test: 683 in 60 suite (Core) e 239 in 23 (Features), con `-warnings-as-errors`;
  - build Debug dell'app riuscita, nessun `Localizable.xcstrings` cambiato, nessun sorgente del Core cambiato;
  - mutazioni: 9 in stesura e 9 + 18 nelle revisioni dei Task 1 e 2, tutte uccise sulle garanzie. Una era sopravvissuta alla revisione finale, ed è stata uccisa dal test aggiunto;
  - l'adattatore AppKit non ha test automatici: va provato a mano scegliendo un `.pvm`, un `.app` e una cartella normale, e controllando che un file normale resti grigio.
- **Lavori successivi proposti:**
  - se la prova manuale trova un pacchetto che il pannello non abilita, un delegate `panel(_:shouldEnable:)` basato su `isPackageKey`. Il pannello riconosce i pacchetti per conformità UTType a `.package`; lo scanner usa `isPackageKey` più le estensioni delle macchine virtuali;
  - un hint sul pulsante «Apri Impostazioni…»: oggi due righe non disponibili danno due pulsanti uguali nel rotore di VoiceOver.
- **Frasi nuove per la tabella del piano di localizzazione:**
  - Features: «Scegli una cartella o un pacchetto da escludere» (sostituisce «Scegli una cartella da escludere»), «Nessuna cartella da analizzare.»;
  - App: «Apri Impostazioni…»; «Cartelle e pacchetti, come una macchina virtuale, mai analizzati né proposti in nessuna categoria della pulizia. Le pagine Xcode e Docker non li usano.» (sostituisce «Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine Xcode e Docker non le usano.»);
  - i test di `SettingsViewModelTests` e `SettingsOpeningTests`/`ChooseStepTests` confrontano il testo italiano del titolo del pannello, dell'avviso e dei contatori.

## Registro SDD (copia del ledger)


Spec: docs/superpowers/specs/2026-10-20-package-exclusions-folder-warning-design.md
Worktree: .claude/worktrees/charming-cerf-98b828, branch feat/package-exclusions-folder-warning, da feat/large-files-exclusions 273ed4e + spec 0ae6761 + piano 8388eba.
Baseline nel worktree: Core 681 test / 60 suite, Features 231 / 23.

Modelli (preferenze utente): implementatori haiku (codice completo nel brief), fix round al massimo sonnet; revisori sonnet con mutazioni nei Task 1 e 2; opus per la revisione finale.

## Controllo preliminare

Il piano è già stato applicato meccanicamente, blocco per blocco, a due copie pulite di 0ae6761 (script apply_plan.py nello scratchpad della sessione): 26 sostituzioni, ognuna trovata una sola volta; RED e GREEN come negli Expected (Core 681/682, Features 232/238, suite SettingsViewModelTests 21 e ChooseStepTests 17), build app riuscita, xcstrings invariati; 9/9 mutazioni della tabella uccise.

| Coppia o task | Cosa produce / consuma | Esito |
|---|---|---|
| T1 → T2 | T1 cambia FakePicker (requests); T2 usa FakePicker() solo come argomento in SettingsOpeningTests | coerente |
| T1 → T3 | entrambi toccano README.md, in punti diversi (Impostazioni ed esclusioni; riga del passo 1) | nessuna sovrapposizione dei testi «old» |
| T2 → T3 | T2 produce CategoryChoice.isAvailable, unavailableText e ChooseStepModel.openSettings(); T3 li usa in ChooseStepView | coerente |
| T1 | test (requests, titolo nuovo) contro SettingsModel e FakePicker; MainModelTests.titles → requests | coerente |
| T2 | 5 test del passo 1 + 1 di SettingsOpeningTests + 1 del catalogo (passa già, caratterizzazione dichiarata) contro ChooseStepModel; tre doppi aggiornati | coerente |
| T3 | solo vista e README, nessun test: comportamento coperto dai test del T2 | coerente |
| Rubrica | test che non asseriscono nulla: nessuno; duplicazione verbatim di logica: nessuna | nessun conflitto da decidere |

Esito: nessun conflitto da decidere prima del Task 1.

## Avanzamento
Task 1: implementer haiku a3345034ff3fca70c, commit 46e6d12 (681/232, app BUILD SUCCEEDED), DONE; nota: il brief non porta le Global Constraints, ora in global-constraints.txt nel workspace.
Task 1: review sonnet af32a363f8c64bec4: spec ✅, Approvato, 9/9 mutazioni uccise (M2, M3, M4, M8, M9 solo dal test nuovo).
Task 1: ⚠️ risolti dal controller: (a) comportamento reale del pannello non verificabile dal diff — la spec lo affida a build + lettura e a una prova manuale facoltativa dell'utente; (b) build dell'app affermata dal report — gli stessi blocchi compilano nella copia di stesura (BUILD SUCCEEDED).
Task 1: minor (deferred): AppKitServices.swift:21-22 «si scelgono comunque (verificato il 2026-10-20)» sovrastima: la sonda ha verificato i tipi (public.folder), non il pannello nuovo con allowedContentTypes = [.package].
Task 1: minor (deferred): SettingsViewModelTests.swift:204 riga di 144 caratteri (copiata dal piano).
Task 1: minor (deferred): README, paragrafo delle esclusioni: ritorno a capo irregolare dopo l'inserimento (il testo reso non cambia).
Task 1: complete (commits 8388eba..46e6d12, review clean)
Task 2: implementer haiku a35aabadccfa61586, commit d06a12b (682/238, app BUILD SUCCEEDED), DONE.
Task 2: review sonnet a0d4851d80381dc7b: spec ✅, Approvato, 18 mutazioni (14 Features, 4 Core) tutte uccise sulle garanzie del task; build app rifatta dal revisore nella copia: BUILD SUCCEEDED.
Task 2: ⚠️ nota per il Task 3: casella e tocco della riga restano attivi finché la vista non cambia (effetto mascherato dal getter) — coperto dal brief del Task 3 (.disabled e guardia nel tap).
Task 2: minor (deferred): nessun test fissa canAnalyze falso e «Nessuna categoria selezionata» quando le sole categorie ricordate sono non disponibili (M11 uccisa solo per caso da analyzeIsDisabledWithoutSelectionAndFollowsTheToggles); la spec nomina canAnalyze.
Task 2: minor (deferred): mutazione C3 (large-files che usa projectRoots) non uccisa dal test nuovo, uccisa dall'esistente downloadsHaveTheAgeRuleAndLargeFilesOneThresholdRulePerRoot.
Task 2: complete (commits 46e6d12..d06a12b, review clean)
Task 3: implementer haiku a7a5bc239a7c0d799, commit ca3b04d (682/238, app BUILD SUCCEEDED), DONE.
Task 3: review sonnet a95f8d810eca573a9: spec ✅, Approvato; controlli mirati: il Button «Apri Impostazioni…» vince sul gesto della riga (e il gesto è comunque un no-op su una riga non disponibile); l'icona nascosta lascia l'avviso comprensibile a VoiceOver.
Task 3: ⚠️ rendering e clic reale non verificabili senza avviare l'app — come da spec, prova manuale facoltativa dell'utente; screenshot non previsti (la demo non ha righe non disponibili).
Task 3: minor (deferred): ChooseStepView.swift:3-4 il commento «Tutta la riga commuta la casella» non dice l'eccezione delle righe non disponibili.
Task 3: minor (deferred): MissingFoldersNote senza fixedSize: con traduzioni lunghe o Dynamic Type grande il testo potrebbe troncarsi invece di andare a capo.
Task 3: complete (commits d06a12b..ca3b04d, review clean)
Revisione finale: opus a5c9b5ded11f68d21, «Con correzioni»: 0 Critical, 1 Important (nessun test del giro «Apri Impostazioni…» → Salva → passo 1 ricreato: la mutazione `if case .choose = page { return }` in startOver() sopravvive a tutti i 238 test), 7 Minor; triage dei minor rinviati: correggere i due commenti (AppKitServices, ChooseStepView), gli altri possono restare.
Ruling: aggiungere in SettingsOpeningTests il test del giro completo, dalla sonda del revisore (savingAProjectFolderFromStepOneMakesTheCategoryAvailable) — la spec («Dopo le Impostazioni», «Primo avvio») poggia la funzione 2 su questo percorso e una mutazione plausibile sopravvive — se sbagliato costa un test in più (Features 239).
Ruling: nella stessa ondata i Minor economici: commento di AppKitFolderPicker riscritto (un pezzo interno escluso protegge il pacchetto; la sonda ha verificato i tipi, non il pannello), commento di ChooseStepView con l'eccezione, hint VoiceOver sulla casella disattivata con unavailableText (nessuna frase nuova), fixedSize verticale sul testo dell'avviso (al limite a 900 pt con la sidebar larga), commento di excludedFolders in SettingsModel con «e pacchetti», commento su makeCategory senza regole, test del Core per un pacchetto escluso in sé con la barra finale del pannello (Core 683) — costano poche righe e fissano promesse visibili all'utente; il test del Core esce dall'elenco dei file del piano — se sbagliato costa un commit di rifinitura da togliere.
Ruling: restano fuori, come da triage: definizione di «pacchetto» diversa fra pannello (UTType .package) e scanner (isPackageKey + estensioni VM) — da toccare solo se la prova manuale trova un caso; test di canAnalyze con sole categorie non disponibili; mutazione C3; riga di 144 caratteri; a capo nel README; hint sul pulsante «Apri Impostazioni…» (richiederebbe una frase nuova) — se sbagliato resta un pacchetto esotico non sceglibile o un pulsante duplicato nel rotore di VoiceOver.
Correzioni finali: implementer sonnet a1621c0172ce0d22b, commit 773a480 (Core 683/60, Features 239/23, app BUILD SUCCEEDED); mutazione startOver uccisa dal test nuovo (4 issue).
Ri-revisione finale: sonnet a28d81b5f722bf6c6: 8/8 rilievi ADDRESSED, nessun nuovo Critical/Important.
Final: parked — AppKitServices.swift:20 dice che al passo 3 il pacchetto escluso compare «con il suo nome», ma ConfirmStepModel mostra il percorso intero (prime 5 esclusioni) — Ruling: testo imposto dal brief del controller, impreciso di una parola; nessun effetto sul comportamento; da correggere in «con il suo percorso» al prossimo tocco del file — se sbagliato costa un commento impreciso.
Final: minor (deferred): il commento di savingAProjectFolderFromStepOneMakesTheCategoryAvailable dice «disponibile e spuntata»: spuntata vale perché la selezione ricordata predefinita contiene project-build-output.
