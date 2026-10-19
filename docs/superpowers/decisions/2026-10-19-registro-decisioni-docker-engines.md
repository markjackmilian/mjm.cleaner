# SDD ledger — plan: docs/superpowers/plans/2026-10-19-docker-engines.md

Spec: docs/superpowers/specs/2026-10-19-docker-engines-design.md (letta, raggiungibile).
Worktree: /Users/mjm/projects/mjm.cleaner/.claude/worktrees/docker-engines, branch feat/docker-engines da main 52143a9.
Baseline: 536 test / 48 suite (Core) + 173 / 21 (Features), nessun warning.
Modelli (scelta dell'utente 2026-10-19): implementatori haiku (fix round al massimo sonnet), revisori sonnet,
opus per la revisione del Task 3 (con mutazioni) e per la revisione finale.
Istruzioni generiche: implementer-instructions.txt, reviewer-instructions.txt in questo workspace. Report in .txt.

## Scansione preliminare

| Coppia / task | Produce → consuma | Esito |
|---|---|---|
| T1–T2 | `DockerUnavailableError.reason`, `DockerEngine.kind(named:)` (interna), `FakeDockerCli.infoCommand/info` → `DockerContext`, test del servizio | coerente: T2 li usa con le firme di T1 |
| T1–T2 | `DockerCleanupService.swift`: T1 cambia due righe, T2 riscrive il file tenendo `engine.serverVersion` | coerente |
| T1–T2 | `DockerJson.swift`: entrambi inseriscono prima di «/// Un valore per riga» | coerente: l'ancora resta unica |
| T1–T3 | `DockerCli.swift`: T1 struttura dell'errore e due `throw`; T3 locator e commento di `environment` | regioni disgiunte |
| T1–T3 | `DockerCliTests.swift`: T1 test d'errore; T3 sostituisce i tre test del locator | regioni disgiunte |
| T2–T3 | `AppEnvironment.swift`: T2 riga `contexts:`; T3 commento e chiamata del locator | regioni disgiunte |
| T2–T4 | `DockerCleanupService.swift` riscritto in T4 con `contexts` e `measure(for:)`; `DockerCleanupServiceTests` (T2 file intero, T4 sostituisce un test e ne aggiunge uno con `service(fs, cli)` e `FakeDockerCli.info`) | coerente |
| T1–T4 | `DockerModelTests.swift`: T1 un testo, T4 altri punti | regioni disgiunte |
| T4–T5 | protocollo `DockerNavigating`, `DockerReportModel`, `MainModel`, `DockerNavigationSpy`, `SharedEventsNavigation`: i testi «vecchi» di T5 coincidono con i «nuovi» di T4 | coerente (verificato dalla riesecuzione) |
| T4–T5 | demo: T4 `DemoData.dockerAnalysis.engine`; T5 lo usa in `DemoLaunch` | coerente |
| T6 | prova dal vivo: `DockerBinaryLocator.find(homeDirectory:)` (T3), `DockerContextReader` (T2), `checkDaemon` (T1) | coerente |
| T1 | test ↔ codice, file creati ↔ toccati | coerente: rieseguito in stesura, RED e GREEN 539/49 + 173/21 |
| T2 | idem | coerente: 546/50 + 173/21 |
| T3 | idem | coerente: 549/50 + 173/21 |
| T4 | idem | coerente: 551/50 + 175/21, app compilata |
| T5 | idem; i `sed` danno 10 e 5 sostituzioni | coerente: 551/50 + 177/21, app compilata |
| T6 | README e prova dal vivo | coerente: prova riuscita in stesura |
| Rubrica | errori ingoiati: `DockerContextReader.activeContext()` restituisce `nil` per ogni errore, anche annullamento | deciso dal piano (sezione «Decisioni prese durante la stesura») |
| Rubrica | test che non verificano nulla / duplicazioni di logica imposte dal piano | nessuno trovato |

Ruling: `DockerContextReader.activeContext()` ingoia ogni errore, annullamento compreso — il piano lo decide e lo motiva (il messaggio d'errore non deve diventare a sua volta un errore; un contesto illeggibile lascia il testo generico); se un revisore lo segnala, lo si valuta nel loop contro questa decisione — se sbagliato, un'analisi annullata a daemon spento mostrerebbe il testo generico invece di propagare l'annullamento, effetto solo estetico.

## Avanzamento
Task 1: dispatched implementer (haiku), BASE 52143a9
Task 1: implementer DONE (commit feb4f33, 539/49 + 173/21, trailer ok); review dispatched (sonnet) on review-52143a9..feb4f33.diff
Task 1: review Approved (spec ✅). ⚠️ trailer verificato dal controller (git log: Claude Opus 5.5); ⚠️ suite: evidenza nel report, coincide con la riesecuzione in stesura.
Task 1: minor (deferred): plan-mandated — `reason` predefinito `.notRunning` permette `DockerUnavailableError(notInstalled)` con motivo sbagliato; irrigidire con costruttori statici o reason obbligatorio (DockerCli.swift:27)
Task 1: minor (deferred): `DockerText.trimmed(info.serverVersion)` non coperto da test; aggiungere caso "  " o togliere il trim (DockerInventoryCollector.swift:22)
Task 1: minor (deferred): RED mostrava solo DockerEngine/DockerEngineKind, non engineFormat (processo)
Task 1: minor (deferred): «non eseguito: …» di DockerCleanExecutor.swift:151 usa il testo generico notRunning, non asserito
Task 1: complete (commits 52143a9..feb4f33, review clean)
Task 2: dispatched implementer (haiku), BASE feb4f33
Task 2: implementer DONE (commit efbf162, 546/50 + 173/21, trailer ok); review dispatched (sonnet) on review-feb4f33..efbf162.diff
Task 2: review Approved (spec ✅). ⚠️ trailer verificato dal controller; ⚠️ app non compilata in questo task (il brief non lo chiede; lo fanno i Task 4–5).
Task 2: minor (deferred): manca un test di servizio col solo endpoint (Description vuota, host ~/.orbstack/run) che verifichi il passaggio di homeDirectory dal lettore (DockerCleanupServiceTests.swift:20, DockerContext.swift:69-71)
Task 2: minor (deferred): guard `unix://` non isolato dai test; caso `http:///Users/tester/.docker/run/docker.sock` → .other (DockerContext.swift:23)
Task 2: minor (deferred): catch di activeContext() provato solo con uscita ≠ 0, non con JSON malformato (DockerContext.swift:61-67)
Task 2: minor (deferred): plan-mandated — @concurrent sia su analyze sia su analyzeRunningDaemon, due salti invece di uno (DockerCleanupService.swift:40,60)
Task 2: complete (commits feb4f33..efbf162, review clean)
Task 3: dispatched implementer (haiku), BASE efbf162
Task 3: implementer DONE (commit 9d73c04, 549/50 + 173/21, trailer ok); review dispatched (opus, mutazioni G1–G4) on review-efbf162..9d73c04.diff
Task 3: review (opus) Needs fixes — spec ✅; 18 mutazioni, 2 sopravvissute: M10 (`== S_IFREG` → `!= S_IFDIR`), M18 (predefinito di find = FileManager.isExecutableFile, accetta cartelle). Entrambe plan-mandated.
Ruling: aggiungere i due test proposti dal revisore (caso FIFO in onlyAnExecutableFileReachedThroughItsLinksCounts; nuovo test locatorSkipsAFolderWhereTheBinaryShouldBe) oltre al testo del piano — la spec (§Ricerca del binario) chiede «un file eseguibile», e per preferenza dell'utente una mutazione sopravvissuta richiede un test — se sbagliato costa due test in più; effetto a valle: il Core sale di 1 test (550/50 dopo il Task 3), quindi i conteggi attesi dei Task 4–6 diventano 552/50 invece di 551/50.
Task 3: minor (deferred): plan-mandated — il test dell'orfano punta a /Applications/Docker.app/…/docker-uninstalled, fuori dalla cartella temporanea; usare home.path + "/missing/docker" (DockerCliTests.swift:163)
Task 3: fix round 1 implemented (commit 99ed612, 550/50 + 173/21, trailer ok); scoped re-review dispatched (sonnet, rerun M10/M18)
Task 3: fix round 1/5 (2 addressed, 0 open — M10 ucciso da onlyAnExecutableFileReachedThroughItsLinksCounts:160, M18 da locatorSkipsAFolderWhereTheBinaryShouldBe:184; commits 9d73c04..99ed612)
Task 3: complete (commits efbf162..99ed612, review clean)
Task 4: dispatched implementer (haiku), BASE 99ed612, atteso 552/50 + 175/21 (ruling del Task 3)
Task 4: implementer DONE (commit 837d02f, 552/50 + 175/21, app BUILD SUCCEEDED, trailer ok); review dispatched (sonnet, mutazioni G1 disco) on review-99ed612..837d02f.diff
Task 4: review (sonnet) Needs fixes — spec ✅; 14 mutazioni, sopravvissute M5/M6 (fileExists/fileLength prima del nil per un motore estraneo) e M12 (servizio: disk.measure() extra scartato) → G1 non vincolata su accesso al filesystem e du nel servizio (Important); M14 Minor.
Ruling: correggere rafforzando i test esistenti (onlyDockerDesktopHasADiskToMeasure, orbStackHasNoDiskToMeasureEvenWithADockerRawLeftBehind) con un AccessLogFileSystem condiviso in Tests/CleanerCoreTests/Support e un runner che registra le chiamate, invece di aggiungere una suite nuova — la spec promette «per OrbStack nessun accesso al filesystem e nessun du», e una mutazione sopravvissuta richiede un test — se sbagliato costa un file di supporto; i conteggi restano 552/50 + 175/21.
Task 4: minor (deferred): M14 sopravvive — `engine = engine ?? analysis.engine` in load(); test con due analisi di motori diversi, retry(), delete(), measuredEngines == [secondo] (DockerModel.swift:250)
Task 4: minor (deferred): plan-mandated — describeDisk non verifica che il motore sia Docker Desktop prima dei testi di Docker.raw (DockerModel.swift:281-287)
Task 4: minor (deferred): DiskUsageProbe.measure() senza motore resta public e aggira la guardia; potrebbe essere internal (DiskUsageProbe.swift:52)
Task 4: minor (deferred): plan-mandated — measure(for:) @concurrent chiama measure() @concurrent, due salti (DiskUsageProbe.swift:43-47)
Task 4: fix round 1 implemented (commit f6d2f3d, 552/50 + 175/21, trailer ok); scoped re-review dispatched (sonnet, rerun M5/M6/M12)
Task 4: fix round 1/5 (1 addressed, 0 open — M5/M6 uccise da DiskUsageProbeTests.swift:70 e DockerCleanupServiceTests.swift:73, M12 da :73-74; commits 837d02f..f6d2f3d)
Task 4: minor (deferred): AccessLogFileSystem registra solo fileExists/itemInfo; una lettura con directoryExists/readData/contentsOfDirectory sfuggirebbe (Support/AccessLogFileSystem.swift)
Task 4: minor (deferred): `NoProcess` ora registra le chiamate e simula du: nome fuorviante (DockerCleanupServiceTests.swift)
Task 4: complete (commits 99ed612..f6d2f3d, review clean)
Task 5: dispatched implementer (haiku), BASE f6d2f3d, atteso 552/50 + 177/21
Task 5: implementer DONE (commit 662621d, 552/50 + 177/21, app BUILD SUCCEEDED, trailer ok); review dispatched (sonnet, mutazioni G1 Purge) on review-f6d2f3d..662621d.diff
Task 5: review (sonnet) Needs fixes — spec ✅; 14 mutazioni, sopravvissute M8 (MainModel.showDockerReport passa un Docker Desktop fisso: OrbStack avrebbe il Purge; Important, plan-mandated) e M14 (Minor).
Ruling: aggiungere in MainModelTests il test theDockerReportKeepsTheEngineItIsGiven proposto e validato dal revisore — la spec vieta il Purge per motori diversi da Docker Desktop e il giunto MainModel non era coperto; una mutazione sopravvissuta richiede un test — se sbagliato costa un test; effetto a valle: Features 178/21 (non 177) nel Task 6.
Task 5: minor (deferred): M14 — il testo del disco dei motori non Desktop è provato solo con misure nil; aggiungere #expect(model.diskText.hasPrefix("Disco virtuale:")) in purgeIsSuggestedOnlyForDockerDesktop (DockerReportModelTests.swift ~131-146)
Task 5: minor (deferred): nome purgeIsSuggestedOnlyForDockerDesktop promette anche il caso positivo; rinominare purgeIsNeverSuggestedForOtherEngines
Task 5: minor (deferred): la regola «solo Docker Desktop ha il disco misurato» vive in tre punti (DiskUsageProbe, DockerModel.describeDisk, DockerReportModel) con testi diversi per pagina
Task 5: fix round 1 implemented (commit 3f25382, 552/50 + 178/21, trailer ok); scoped re-review dispatched (sonnet, rerun M8)
Task 5: fix round 1/5 (1 addressed, 0 open — M8 uccisa da MainModelTests.theDockerReportKeepsTheEngineItIsGiven:231-233; commits 662621d..3f25382)
Task 5: complete (commits f6d2f3d..3f25382, review clean)
Task 6: dispatched implementer (haiku), BASE 3f25382, atteso 552/50 + 178/21, scratch scratchpad/task6
Task 6: implementer DONE (commit df4d7db, 552/50 + 178/21, app BUILD SUCCEEDED, live probe ok: OrbStack riconosciuto, messaggio desktop-linux corretto, contesto orbstack prima/dopo; trailer ok); review dispatched (sonnet)
Task 6: review Approved (spec ✅; ogni affermazione del README verificata sul codice di HEAD).
Task 6: minor (deferred): plan-mandated — README «names the engine» vale per Docker Desktop/OrbStack; per Colima/Rancher la pagina mostra l'OperatingSystem del daemon o il nome del contesto (README.md:107-111)
Task 6: minor (deferred): plan-mandated — «No file under an engine's own folders is ever deleted» è garantito dalla deny-list solo per Docker Desktop/OrbStack; ~/.colima e ~/.rd fuori ambito per la spec (README.md:108-109)
Task 6: minor (deferred): la sezione Documentation del README non elenca spec e piano 2026-10-19-docker-engines
Task 6: complete (commits 3f25382..df4d7db, review clean)
Final review: dispatched (opus) on review-52143a9..df4d7db.diff, 9 commit
Final review (opus): With fixes — 0 Critical, 2 Important, 4 Minor; triage dei minor: tutti «può restare» tranne la frase del README «No file under an engine's own folders…».
Ruling: aggiungere "\(home)/OrbStack" alla deny-list con test e README — OrbStack vi monta in NFS volumi, immagini e container (verificato dal revisore con mount); la spec motiva la deny-list «come le voci di Docker» ed esclude solo motori diversi da OrbStack; una voce in più può solo ridurre ciò che l'app cancella — se sbagliato, l'app non pulisce più nulla sotto ~/OrbStack, che contiene solo dati del motore; Core sale a 553/50.
Ruling: riformulare nel README la frase sulla sicurezza dei file dei motori (falsa in assoluto: la categoria Cache svuota ~/Library/Caches anche dei motori) — garanzia di sicurezza dichiarata — se sbagliato, solo testo.
Ruling: DiskUsageProbe.measure() diventa internal (solo il Core e i test @testable la usano) — chiude il bypass della guardia di measure(for:) — se sbagliato, un chiamante esterno futuro non compila.
Ruling: Important 2 (il contesto attivo può cambiare fra l'analisi ed «Elimina»: rmi/volume rm/builder prune sul motore del momento) — parcheggiato come follow-up: esisteva già su main, è fuori dalla spec approvata e richiede testi nuovi — se sbagliato, un volume omonimo non in uso sull'altro motore può essere eliminato finché il follow-up non arriva.
Final review: minor (deferred, fuori branch): il piano app-updates su main dice +4 test Features se docker-engines arriva prima; sono +5 (178/21).
Final review: minor (deferred): «… e premi Riprova.» compare anche nell'errore di «Elimina» e nelle righe «non eseguito: …»; da rivedere con la localizzazione.
Final fix wave: dispatched (haiku), FIX_BASE df4d7db, atteso 553/50 + 178/21 + app
Final fix wave: DONE (commit e1ac5da, 553/50 + 178/21, app BUILD SUCCEEDED, trailer ok); scoped re-review dispatched (sonnet, mutazione ~/OrbStack)
Final fix wave: re-review — 3 addressed, 0 open (mutazione ~/OrbStack uccisa da DenyListTests.deniesTheOrbStackDataMount:158; measure() senza chiamanti esterni); commits df4d7db..e1ac5da
Final review: clean dopo il giro di correzioni. Follow-up aperto: Important 2 (verifica del motore/contesto prima di «Elimina»).
