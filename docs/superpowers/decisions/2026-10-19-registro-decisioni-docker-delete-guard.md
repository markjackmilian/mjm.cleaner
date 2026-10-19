# Registro delle decisioni — «Elimina» Docker solo sul motore analizzato

Spec `docs/superpowers/specs/2026-10-19-docker-delete-guard-design.md`, piano `docs/superpowers/plans/2026-10-19-docker-delete-guard.md`, branch `feat/docker-delete-guard` da `main` 0e564d8. Esecuzione subagent-driven del 2026-10-19.

## Sintesi

- **Chiude** il follow-up «Important 2» del registro di docker-engines (`2026-10-19-registro-decisioni-docker-engines.md`): il contesto attivo può cambiare fra l'analisi ed «Elimina». Ora ogni comando di analisi ed esecuzione porta `docker --context <nome>`, con il contesto letto all'inizio dell'analisi. Prima di misurare o cancellare, il daemon di quel contesto deve essere lo stesso dell'analisi: stesso `DockerEngine`, cioè ID, sistema e versione.
- **Supera** la decisione del registro di docker-engines «`DockerContextReader.activeContext()` ingoia ogni errore». Ora `activeContext()` lancia, un contesto illeggibile ferma l'analisi, e `notRunningMessage()` senza argomenti non esiste più: si nomina sempre il contesto letto, con `notRunningMessage(for:)`.
- **Scelta dell'utente rivista dopo la revisione finale.** Al rifiuto per motore cambiato la pagina torna allo stato d'errore, con il messaggio e «Riprova». La prima scelta, «errore sotto Elimina» con l'elenco intatto, rimandava a un «Riprova» che nello stato pronto non c'è. La spec è emendata (d3b0202).
- **Rischio residuo accettato**, solo con il contesto `default`, che segue il collegamento `/var/run/docker.sock` riscritto dal motore avviato per ultimo:
  - *durante l'esecuzione*: se un altro motore riscrive il collegamento dopo il controllo dell'identità, i comandi successivi vanno al nuovo daemon. Un controllo prima di ogni comando restringerebbe la finestra senza chiuderla e raddoppierebbe le chiamate;
  - *durante l'analisi*: se il collegamento passa da A a B e torna ad A prima di «Elimina», il controllo all'avvio passa e su A si cancellano identificativi letti da B. Servono due riavvii di motore in pochi secondi, e `docker rmi`/`volume rm` senza `-f` rifiutano comunque le risorse in uso.

  I contesti con nome (Docker Desktop, OrbStack, Colima, Rancher Desktop) hanno un socket proprio e non hanno queste finestre.
- Un motore che riportasse un `ID` diverso a ogni chiamata verrebbe sempre rifiutato. Non riguarda `dockerd`, il cui ID è persistente; per altri motori compatibili non è stato verificato.
- Verifica: suite 572 test in 51 suite (Core) + 180 in 21 (Features), nessun warning; `xcodebuild` Debug riuscito; prova dal vivo in sola lettura su OrbStack, con il contesto `orbstack` prima e dopo, l'ID letto e un ID diverso rifiutato. Oltre 40 mutazioni provate fra stesura e revisioni, tutte uccise tranne due che non toccano la sicurezza: la M14 del Task 4 (solo testo) e la M5 del Task 2 (`fileSystem` del collettore fissato).
- Le due frasi nuove («Il motore Docker del contesto «‹nome›» non è più quello analizzato: non è stato eliminato nulla. Premi Riprova per analizzarlo di nuovo.» e «Nome del contesto Docker non valido: «‹nome›».») vanno nella tabella del piano di localizzazione.

## Registro SDD (copia del ledger)

Spec: docs/superpowers/specs/2026-10-19-docker-delete-guard-design.md (letta).
Worktree: /Users/mjm/projects/mjm.cleaner/.claude/worktrees/docker-delete-guard, branch feat/docker-delete-guard da main 0e564d8.
Modelli: implementatori haiku (fix round al massimo sonnet); revisori sonnet, opus per Task 3, Task 4 e revisione finale.

## Scansione preliminare

| Coppia / task | Prodotto → consumato | Esito |
|---|---|---|
| T1–T2 | `FakeDockerCli.info(_:_:id:)` (T1) usato nei test di T2; `DockerInventoryCollector.swift`: T1 cambia `engineFormat`/`checkDaemon`/`readEngine`, T2 inserisce `pinned(to:)` prima di `checkDaemon` (ancora identica dopo T1) | coerente |
| T1–T3 | `DockerEngine.swift`: T1 aggiunge `id`, T3 cambia il commento di testa (regioni disgiunte); `info(id:)` nei test di T3 | coerente |
| T1–T4 | `readEngine` (T1) usata dall'esecutore; `info(id:)` nei test dell'esecutore | coerente |
| T2–T3 | `DockerContext.swift`: T2 aggiunge `DockerContextCli` in fondo, T3 sostituisce `DockerContextReader` (disgiunte); `pinned(to:)` e `FakeDockerContexts` consumati da T3 | coerente |
| T2–T4 | `DockerContextCli` e `FakeDockerContexts` consumati dall'esecutore e dai suoi test | coerente |
| T3–T4 | `DockerCleanupService.swift`: T3 riscrive `DockerAnalysis`/`analyze`, T4 sostituisce `execute` (disgiunte); `DockerCleanupServiceTests`: T3 sostituisce il file, T4 aggiunge in coda con ancora sulla fine di `aStoppedEngineIsNamedFromTheContextReadAtTheStart` (unica); `DockerAnalysis.target`, `notRunningMessage(for:)`, `dockerAnalysis(_:engine:context:…)` consumati da T4 | coerente |
| T4–T5 | `DockerModel.swift`: T4 `target`, T5 `catch` (disgiunte); `DockerModelTests`: T5 inserisce prima del commento introdotto da T4 e aggiunge un argomento al test parametrico | coerente |
| T5–T6, T4–T6 | T6 tocca solo `README.md` e una copia scratch | nessuna sovrapposizione |
| T1 | test ↔ codice: `readEngine`, `id`, formato esatto | coerente (replay) |
| T2 | test ↔ codice; file creati e non ritoccati in T2 | coerente (replay) |
| T3 | test ↔ codice; RED senza gli errori di Features (documentato nel piano) | coerente (replay) |
| T4 | test ↔ codice; 2 occorrenze dichiarate due volte (executor cancellation, DockerModelTests execute) | coerente (replay) |
| T5 | RED a runtime; `aChangedEngineKeepsTheListAndTheSelection` passa già prima (documentato) | coerente |
| T6 | README + prova in sola lettura in scratch, nessun file scratch committato | coerente |

Ruling: `aChangedEngineKeepsTheListAndTheSelection` passa già prima del Task 5 — si tiene: è il presidio della scelta dell'utente «errore sotto Elimina» (asserisce stato reale, non è vuoto) — se sbagliato, un test in più senza passo rosso proprio.
Ruling: `DockerEngineTests.theIdTellsTwoDaemonsOfTheSameKindApart` verifica l'uguaglianza sintetizzata — si tiene: protegge da un `==` personalizzato che ignori l'ID (mutazione M4 a livello di tipo) — se sbagliato, un test ridondante.
Ruling: `DockerContextReader.activeContext()` lancia e `notRunningMessage()` sparisce, a differenza del testo della spec — deciso in stesura (nessun chiamante dopo il Task 3) e annotato nel piano — se sbagliato, va ripristinato un metodo che nessuno usa.

## Avanzamento
Task 1: implementer haiku DONE (25892bb, 556/50 + 178/21); review sonnet: spec ✅, Approved. ⚠️ formato `docker info` con ID e commento su `default`/`dockerd`: verificati dal controller dal vivo il 2026-10-19 (ID b2756783-… identico da `orbstack` e `default`, collegamento /var/run/docker.sock → OrbStack).
Task 1: minor (deferred): commento di `FakeDockerCli.infoCommand` cita ancora `checkDaemon` invece di `readEngine` (FakeDockerCli.swift:~70)
Task 1: minor (deferred): `readEngine` rifila solo `serverVersion`, non `operatingSystem`/`id` (innocuo: confronto fra due letture dello stesso formato)
Task 1: complete (commits 0e564d8..25892bb, review clean)
Task 2: implementer haiku DONE (91850da, 561/51 + 178/21); review sonnet con mutazioni: spec ✅, Needs fixes — Important ×2 plan-mandated (lacune di test): M17 `pinned(to:)` che ripiega sul collettore non fissato sopravvive; M8 `run` che perde il timeout del chiamante sopravvive.
Ruling: si aggiungono i due test proposti dal revisore (`pinnedRefusesAnInvalidNameInsteadOfFallingBackToTheActiveContext`, `decoratorForwardsTheCallersTimeout`) — la spec chiede che un nome non valido fermi analisi ed esecuzione e l'esecutore cancella con timeout di 600 s; nessun codice di produzione cambia — costo se sbagliato: due test in più; tutti gli Expected successivi del Core salgono di 2 (T3 567, T4 572, T5 572, T6 572).
Task 2: minor (deferred): `pinned(to:)` che sostituisce `fileSystem` non è coperto (M5), innocuo per la sicurezza
Task 2: minor (deferred): `.matchingSemantics(.unicodeScalar)` ininfluente sulla regex del nome (M11 equivalente); `wholeMatch` sarebbe più diretto
Task 2: minor (deferred): commento dell'`init` di `DockerContextCli` dice solo «vuoto o con «-» iniziale», la regex rifiuta di più (DockerContext.swift:80-81)
Task 2: minor (deferred): il caso `--host=tcp://…` non isola la regola del «-» iniziale; solo `-H` uccide M2
Task 2: fix round 1/5 (2 addressed, 0 open; commits 91850da..9407d68; 563/51 + 178/21; re-review haiku; trailer verificato dal controller)
Task 2: minor (deferred): i test che si aspettano il testo italiano dei rifiuti vanno aggiornati insieme alla chiave quando arriverà la localizzazione
Task 2: minor (deferred): `pinnedRefusesAnInvalidNameInsteadOfFallingBackToTheActiveContext` non verifica che nessun comando sia partito
Task 2: complete (commits 25892bb..9407d68, review clean after 1 fix round)
Task 3: implementer haiku DONE (a0d041a, 567/51 + 178/21, app BUILD SUCCEEDED, xcstrings intatti); review opus con 10 mutazioni, tutte uccise: spec ✅, Approved. ⚠️ build dell'app: dal report dell'implementatore (stesso esito del replay in stesura).
Task 3: minor (deferred): commento di `DockerUnavailableError.notRunningMessage(_:homeDirectory:)` parla ancora del «contesto attivo» (DockerContext.swift:34-35); valutare un parametro non opzionale
Task 3: minor (deferred): i test dell'analisi partono tutti da `desktop-linux`; un test speculare con `orbstack` attivo renderebbe diretta la copertura di «fissato al nome letto» (mutazione `pinned(to: "desktop-linux")` uccisa solo indirettamente)
Task 3: complete (commits 9407d68..a0d041a, review clean)
Task 4: implementer haiku DONE (850ccb0, 572/51 + 179/21, app BUILD SUCCEEDED, xcstrings intatti); review opus con 17 mutazioni (9 richieste + 8 extra): spec ✅, Approved; uccise tutte tranne M14 (non di sicurezza). ⚠️ rischio residuo di `default`: è nella spec e andrà nel registro delle decisioni.
Task 4: minor (deferred): `DockerCleanupService.execute` — il filtro `where error.reason == .notRunning` non ha test (M14: riscrivere ogni `DockerUnavailableError` sopravvive); conseguenza solo sul testo («non in esecuzione» invece di «non installato»), nulla viene cancellato in entrambi i casi
Task 4: complete (commits a0d041a..850ccb0, review clean)
Task 5: implementer haiku DONE (91bbe4b, 572/51 + 180/21); review sonnet con 2 mutazioni (tolto il catch; `isReady = false` nel catch), entrambe uccise: spec ✅, Approved.
Task 5: minor (deferred): il commento di `aChangedEngineKeepsTheListAndTheSelection` promette un secondo clic rifiutato che il test non esegue; il test non asserisce `hasDeleteError` (DockerModelTests.swift:77-92)
Task 5: minor (deferred): due rami `catch` identici in `DockerModel.delete()` (DockerUnavailableError e DockerEngineChangedError), voluti dal piano
Task 5: complete (commits 850ccb0..91bbe4b, review clean)
Ruling: lo Step 3 del Task 6 (prova dal vivo in sola lettura contro il Docker vero) lo esegue il controller, non l'implementatore — i comandi verso il motore reale restano fuori dai subagent, come le istruzioni generali già dicono — costo se sbagliato: nessuno, la prova è identica.
Task 6: implementer haiku DONE (57a7cd0, solo README; 572/51 + 180/21; app BUILD SUCCEEDED; xcstrings intatti). Step 3 eseguito dal controller su 57a7cd0: LIVE context orbstack, engine OrbStack 29.8.2 id b2756783-e527-49e3-a6c6-cd7f4e49c9ff, empty run 0 true, rifiuto DockerEngineChangedError per un id diverso, contesto dopo orbstack; `docker context show` = orbstack prima e dopo; copia scratch cancellata.
Task 6: review sonnet: spec ✅, Approved (ogni frase del README verificata contro il codice).
Task 6: minor (deferred): README «same ID» presuppone che il daemon riporti un ID; con ID vuoto il controllo si riduce a sistema e versione (README.md:121, plan-mandated)
Task 6: minor (deferred): README preesistente «the page names the engine of the active context» vale per l'analisi; in esecuzione si nomina il contesto analizzato (README.md:110-111)
Task 6: complete (commits 91bbe4b..57a7cd0, review clean)
Final review (opus, 0e564d8..57a7cd0): Critical 0; Important 1 — il rifiuto dice «Premi Riprova» ma nello stato pronto «Riprova» non c'è (DockerView mostra Riprova solo nel ramo hasError); Minor: commenti sul «contesto attivo» (DockerCli.swift:5-7/13-14, DockerContext.swift:34-35/81-82, DockerCleanExecutor.swift:68-71), rischio residuo di `default` anche durante l'analisi (secondo `checkDaemon` di `collect()` scartato), commento del test di Task 5. Triage dei minori rinviati: tutti «leave» tranne il registro delle decisioni (fix before merge, lo scrive il controller copiando il registro).
Decisione dell'utente (AskUserQuestion, 2026-10-19): «Stato d'errore» — al rifiuto il modello invalida l'analisi e la pagina mostra la vista d'errore con il messaggio e «Riprova»; sostituisce la scelta «errore sotto Elimina», presa sulla premessa sbagliata che Riprova fosse visibile.
Final fix: un solo dispatch (brief final-fix-brief.md): DockerModel catch → errorText/isReady/groups, test `aChangedEngineSendsThePageBackToRetry` al posto di `aChangedEngineKeepsTheListAndTheSelection`, argomento tolto da `deleteFailuresAreShownOnThePage`, commenti riallineati, spec emendata.
Ruling: la toolbar dello stato d'errore mostra «Motore non raggiungibile» anche per il rifiuto «motore cambiato» — si lascia: la pillola è già usata per ogni errore d'analisi (anche JSON non valido) e cambiarla tocca una vista, fuori dai vincoli — costo se sbagliato: un'etichetta imprecisa in un caso raro.
Ruling: il rischio residuo di `default` durante l'analisi (A→B→A fra analisi ed «Elimina») si registra e non si corregge — servono due riavvii di motore in pochi secondi e `docker rmi`/`volume rm` senza `-f` rifiutano comunque le risorse in uso — costo se sbagliato: in quel caso si cancellerebbero su A identificativi letti da B.
Final fix wave: sonnet DONE (94e76e8 fix + d3b0202 spec; 572/51 + 180/21; RED 6 issue su `aChangedEngineSendsThePageBackToRetry`); re-review sonnet: 4/4 ADDRESSED, nessuna rottura nuova, mutazioni (a) senza `isReady = false`, (b) senza `groups = []`, (c) `deleteErrorText` al posto di `errorText` tutte uccise.
Final fix: minor (deferred): dopo l'invalidazione restano `target`, `diskBefore`, `serverText`, `diskText`, `dfText` dell'analisi vecchia (non mostrati; `canDelete` richiede `isReady`; un `load()` riuscito li riassegna)
