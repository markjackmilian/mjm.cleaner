# Swift Port Phase 5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collaudare la versione Swift contro il C#, confezionare una Release universale verificata e, solo dopo il gate di parità, consegnare un repository Swift senza il C#.

**Architecture:** Il C# rimane nel branch finché il confronto reale, le schermate e VoiceOver non sono registrati. Un pacchetto Release Swift viene costruito e verificato prima del passaggio; uno script che risolve i percorsi rispetto alla propria posizione si sposta con `swift/` alla radice. La rimozione e lo spostamento sono un commit dedicato, seguito da prove su un checkout pulito.

**Tech Stack:** macOS 15+, Swift 6 language mode, Xcode 27, Swift Testing, `xcodebuild`, `lipo`, `codesign`, `ditto`, GitHub Actions; .NET 10 solo per il confronto prima della rimozione.

**Spec:** `docs/superpowers/specs/2026-10-16-swift-port-5-handoff-design.md` integra `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` §§9.4, 10.1–10.3.

## Global Constraints

- Operare nel worktree isolato `codex/swift-port-5`; il checkout `main` contiene tre `Localizable.xcstrings` modificati e `.zed/`, `mjm-cleaner-ui-handoff.md` non tracciati. Non includerli nei commit e non usare `git add -A`, stash, reset o clean nel checkout principale.
- Il C# resta eseguibile fino a parità, screenshot e VoiceOver registrati. Nel collaudo non premere azioni di cancellazione; le prove reali si fermano all'anteprima.
- Nessuna app, cattura o input UI si avvia mentre l'utente usa il Mac. Concordare una finestra dedicata prima dei Task 3–4; se indisponibile, completare i Task 1–2 e fermarsi al gate, senza fingere che test automatici equivalgano al collaudo.
- Debug Swift usa `com.mjm.cleaner.debug`; Release conserva `com.mjm.cleaner`. Nome esterno di distribuzione `mjm.cleaner.app`; eseguibile e scheme `MjmCleaner`.
- Release: una build `arm64` + `x86_64`, firma ad hoc, un solo ZIP. Nessuna identità Developer Program, notarizzazione o pubblicazione senza decisione separata.
- Il workflow `.github/workflows/release-macos.yml` è `disabled_manually` su GitHub al 2026-10-16. Modificare YAML non lo riattiva; non abilitarlo, creare tag o pubblicare release nell'esecuzione del piano.
- Il commit di rimozione segue il gate documentato. Usare solo percorsi espliciti in staging; preservare i documenti storici sotto `docs/superpowers/`.

## Review Focus

1. Debug scrive nei defaults o in Application Support del C#: il Task 1 verifica ID nel plist costruito e origine di `AppStartup.paths`.
2. `ONLY_ACTIVE_ARCH = NO` ma il binario ha una sola slice: il Task 2 verifica con `lipo -archs` sia prima sia dopo lo ZIP.
3. La copia o compressione rompe la firma: il Task 2 estrae lo ZIP e ripete `codesign --verify --deep --strict`.
4. Una differenza di cache variabile sembra una divergenza di prodotto, o un alias APFS giustifica troppo: il Task 4 registra C# → Swift → C# e applica solo le due eccezioni della spec §9.4.
5. Dopo lo spostamento resta un riferimento al layout C# o una dipendenza nascosta nella cache: il Task 6 usa un checkout pulito e cerca riferimenti attivi ai vecchi percorsi.

---

### Task 1: Isolare l'identità Debug

**Files:**
- Modify: `swift/Config/Debug.xcconfig`
- Test: comandi di build settings e plist, nessun nuovo test unitario.

**Interfaces:**
- Consumes: `AppStartup.paths` passa `Bundle.main.bundleIdentifier` a `AppEnvironment.defaultPaths`, che usa `AppPaths.forBundleIdentifier`.
- Produces: Debug con ID `com.mjm.cleaner.debug`; Release resta `com.mjm.cleaner`.

- [ ] **Step 1: Verificare il RED.** Da `swift/`, eseguire `xcodebuild -project MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug -showBuildSettings | grep 'PRODUCT_BUNDLE_IDENTIFIER ='`. Atteso prima della modifica: `com.mjm.cleaner`, quindi diverso dal valore richiesto.
- [ ] **Step 2: Implementare.** In `swift/Config/Debug.xcconfig`, dopo l'include di Base, aggiungere `PRODUCT_BUNDLE_IDENTIFIER = com.mjm.cleaner.debug`. Non cambiare Base o Release.
- [ ] **Step 3: Verificare GREEN.** Ripetere build settings Debug e Release; costruire Debug in una nuova DerivedData sotto `/private/tmp`; leggere `CFBundleIdentifier` dal plist con `PlistBuddy`. Attesi Debug `com.mjm.cleaner.debug`, Release `com.mjm.cleaner`; `rg -n 'Bundle.main.bundleIdentifier' swift/MjmCleaner/App/AppStartup.swift` trova la sorgente della cartella dati. Eseguire `swift test -Xswiftc -warnings-as-errors` nel package: 536 Core + 172 Features verdi.
- [ ] **Step 4: Commit.** Stage solo `swift/Config/Debug.xcconfig` e committare `fix(swift): isolate the debug app identity`.

### Task 2: Creare e provare il pacchetto Release

**Files:**
- Create: `swift/Scripts/package-release.sh`
- Create: `swift/Scripts/package-release.test.sh`

**Interfaces:**
- Consumes: Xcode project/scheme `MjmCleaner`, `Config/Release.xcconfig`, directory dello script `Scripts/`.
- Produces: `package-release.sh --tag vX.Y.Z --build-number N --output-dir DIR` e `--validate-only` per validare tag e build number senza compilare né richiedere output directory. ZIP `mjm.cleaner-vX.Y.Z-macos-universal.zip` contenente `mjm.cleaner.app` con eseguibile `MjmCleaner`. Il percorso del progetto si deriva da `dirname "$0"/..`, valido anche dopo lo spostamento di `swift/` alla radice.

- [ ] **Step 1: Test RED degli input.** In `package-release.test.sh` invocare `--validate-only` con `v0.1.0`, build `1` (successo, stampa `0.1.0`), e con tag `v1`, `v1.2.3-rc1`, build `0` e build non numerica (exit non zero, nessuna build avviata). Prima dell'implementazione lo script manca: il test fallisce.
- [ ] **Step 2: Implementare validazione e prova GREEN.** Lo script usa `set -euo pipefail`, accetta solo il formato `v[0-9]+.[0-9]+.[0-9]+` e build number `[1-9][0-9]*`; rifiuta opzioni sconosciute e valori mancanti; la directory di output è obbligatoria per il packaging e non serve a `--validate-only`. `--validate-only` termina prima di creare file. Eseguire `bash swift/Scripts/package-release.test.sh`, atteso exit 0.
- [ ] **Step 3: Implementare il packaging.** Con una directory temporanea esclusiva: `xcodebuild` Release, destinazione `generic/platform=macOS`, `ARCHS='arm64 x86_64'`, `ONLY_ACTIVE_ARCH=NO`, versione/build da input e firma ad hoc già configurata. Verificare `lipo -archs` = `arm64 x86_64` senza dipendere dall'ordine; `PlistBuddy` per ID, nome, versione, build e macOS minimo 15; `codesign --verify --deep --strict` e `codesign -dv` per `Signature=adhoc`; nessun `MJMDemo` o «Pagina demo» nei binari Release. Copiare il bundle come `mjm.cleaner.app`, riverificare, comprimere con `ditto -c -k --sequesterRsrc --keepParent`, estrarre con `ditto -x -k` in un'altra directory e ripetere i controlli. Se bundle o ZIP di destinazione esistono già, rifiutare senza sovrascriverli. Un errore rimuove solo gli output parziali di questa invocazione, mai una directory preesistente dell'utente.
- [ ] **Step 4: Prova reale.** Eseguire `bash swift/Scripts/package-release.sh --tag v0.1.0 --build-number 1 --output-dir /private/tmp/mjm-swift-port5-candidate` e ispezionare ZIP estratto: due architetture, plist e firma validi. Non avviare l'app e non pubblicare il pacchetto.
- [ ] **Step 5: Commit.** Stage solo i due script e committare `feat(swift): package a verified universal macOS release`.

### Task 3: Confrontare schermate e VoiceOver

**Files:**
- Create: `docs/superpowers/verification/2026-10-16-swift-port-5-visual.md`
- Create only when needed: screenshot nuovi sotto `docs/superpowers/verification/2026-10-16-swift-port-5/` con percorsi espliciti.

**Interfaces:**
- Consumes: le 26 immagini `docs/superpowers/verification/2026-10-15-swift-4b/` e le schermate di `docs/superpowers/verification/2026-10-02-macos-redesign/`.
- Produces: verbale con mappatura chiaro/scuro, esito di layout e VoiceOver, difetti e prove.

- [ ] **Step 1: Confronto offline.** Mappare le 13 pagine × 2 temi del 4b alle schermate del redesign; annotare differenze intenzionali SwiftUI e difetti da verificare sul Mac. Non aprire app.
- [ ] **Step 2: Concordare finestra UI.** Presentare all'utente i bundle e la lista di prove; aspettare una finestra in cui possa lasciare il Mac libero. La conferma della spec non equivale alla disponibilità del Mac.
- [ ] **Step 3: Schermate attive.** Solo durante quella finestra, usare la demo Debug nota (`swift/Scripts/screenshots.sh`) o controllo UI diretto per verificare viewport 900×600, contenuti lunghi, gruppi Docker sotto la piega, azioni inferiori e sheet. Script e app non devono passare alla modalità dati veri in caso di pagina sconosciuta. Salvare solo le nuove immagini necessarie a mostrare un difetto o una correzione.
- [ ] **Step 4: VoiceOver.** Con l'utente disponibile, registrare la navigazione effettiva di sidebar, passi, selezioni, campi/stepper, disclosure Docker/Xcode, tabella Storico, sheet Impostazioni e ritorno del fuoco. Ogni voce ha esito pass/fail e osservazione. Non usare l'ispezione del codice come sostituto della prova parlata.
- [ ] **Step 5: Correggere eventuali difetti.** Per ogni difetto reale, aggiungere la prova più mirata disponibile, mostrare RED/GREEN quando automatizzabile, rifare lo screenshot o il percorso VoiceOver interessato, review Sol e commit dedicato. Se la prova non è eseguibile, registrare il blocco e non dichiarare superato il gate.
- [ ] **Step 6: Commit del verbale.** Stage solo il verbale e le nuove immagini nominate; committare `docs(swift): record visual and VoiceOver acceptance`.

### Task 4: Collaudo C# / Swift in sola lettura

**Files:**
- Create: `docs/superpowers/verification/2026-10-16-swift-port-5-parity.md`
- Modify only for confirmed defects: file della funzione interessata e test relativo.

**Interfaces:**
- Consumes: C# e Swift allo stesso commit di base; bundle C# creato con `./build/bundle.sh --output-dir <temp>`, Swift Debug con ID distinto dal Task 1.
- Produces: tabella per categoria, Docker e Xcode, con esito giustificato e riproducibile.

- [ ] **Step 1: Preparare senza avvio.** Registrare SHA, versione .NET/Xcode, percorsi assoluti dei bundle, selezioni, impostazioni e presenza di Full Disk Access. Non modificare i dati dell'app C# o copiare alla cieca la sua configurazione nel dominio Swift.
- [ ] **Step 2: Concordare finestra UI.** Come Task 3: l'utente lascia il Mac libero; confermare che il confronto si ferma prima di ogni cancellazione.
- [ ] **Step 3: Analisi C# → Swift.** Avviare ciascun bundle tramite percorso assoluto. Per Scegli/Analizza/Conferma, annotare per categoria numero, byte ed esclusioni con motivo. Per Docker: ID, KEEP/DELETE/PROPOSE/ASK e ragione. Per Xcode: identificatore, byte, disponibilità e blocchi. Non premere «Pulisci», «Elimina» o equivalenti.
- [ ] **Step 4: Isolare le divergenze.** Ripetere solo le categorie discordanti con C# → Swift → C#. Accettare soltanto la variazione naturale osservata o gli alias APFS della spec §12; ogni altra differenza è un difetto da correggere con test e re-review prima del gate.
- [ ] **Step 5: Commit del verbale.** Stage solo `docs/superpowers/verification/2026-10-16-swift-port-5-parity.md` e gli eventuali test/correzioni già verificati; preferire commit distinti per codice e verbale. Il verbale specifica esplicitamente se il gate è superato.

### Task 5: Gate di consegna

**Files:**
- Modify: `docs/superpowers/porting/2026-10-13-parity.md` solo per esiti definitivi del collaudo.
- Create: `docs/superpowers/verification/2026-10-16-swift-port-5-gate.md`.

**Interfaces:**
- Consumes: report dei Task 2–4 e suite corrente.
- Produces: decisione GO/NO-GO verificabile prima di rimuovere C#.

- [ ] **Step 1: Rileggere prove.** Controllare registro di parità completo, 536 + 172 test o nuovi conteggi giustificati, build Debug/Release senza avvisi, ZIP estratto con due slice e firma, screenshot e VoiceOver, confronto reale e differenze giudicate. Un test non eseguito o un difetto Critical/Important aperto produce NO-GO.
- [ ] **Step 2: Registrare esito.** Scrivere la tabella dei gate con link ai report, SHA e output essenziali, più eventuali minor rinviati e costo. Se NO-GO, continuare a correggere o fermarsi sul dato esterno mancante; non iniziare Task 6.
- [ ] **Step 3: Commit.** Stage solo il gate e l'eventuale riga aggiornata del registro di parità; committare `docs(swift): record phase-five handoff gate`.

### Task 6: Rimuovere C# e ricollocare Swift

**Files:**
- Delete: `src/`, `tests/`, `build/`, `Directory.Build.props`, `mjm.cleaner.slnx`.
- Move: `swift/Config/`, `swift/MjmCleaner/`, `swift/MjmCleaner.xcodeproj/`, `swift/MjmCleanerKit/`, `swift/Scripts/` alla radice con `git mv` espliciti.
- Modify: `.gitignore`, `README.md`, `.github/workflows/release-macos.yml`.
- Modify only where active path references require it: script Swift, progetto Xcode, test.

**Interfaces:**
- Consumes: GO registrato nel Task 5; `Scripts/package-release.sh` risolve il progetto dalla propria directory.
- Produces: repository Swift alla radice, workflow di un solo ZIP universale e README Swift/macOS 15.

- [ ] **Step 1: Inventario RED.** Cercare in workflow, README, `.gitignore`, script/progetto/test attivi i vecchi `swift/`, `src/`, `tests/`, `build/`, `.NET` e i riferimenti necessari all'icona. Registrare le collisioni di nomi alla radice; nessuna delle cinque directory Swift deve collidere. Il C# ancora presente e i comandi README .NET sono il RED atteso.
- [ ] **Step 2: Rimozione e spostamento.** Usare `git rm -r` solo per i percorsi C# della spec e `git mv` per ciascuna delle cinque voci Swift; non usare `git clean`. Preservare i documenti storici. Aggiornare `.gitignore` per `.build/`, `.swiftpm/`, `xcuserdata/` e DerivedData nel nuovo layout.
- [ ] **Step 3: Workflow.** Sostituire i job C# con test (`swift test -Xswiftc -warnings-as-errors` nel nuovo `MjmCleanerKit`, build Debug) e package (script del Task 2, una build Release universale), runner `xcode-27` verificato con `xcodebuild -version`; release usa il tag esistente, scarica un solo ZIP e lo pubblica dopo job verdi, senza `--clobber` su un asset omonimo. Conservare trigger `v*` e `workflow_dispatch`, ma validare `vMAJOR.MINOR.PATCH` prima di eseguire la build. Non abilitare il workflow remoto né creare tag.
- [ ] **Step 4: README.** Sostituire requisiti .NET/macOS 13 e comandi C# con macOS 15, Xcode/Swift, `swift test`, `xcodebuild` e `Scripts/package-release.sh`; spiegare bundle ad hoc, Full Disk Access e nome del singolo ZIP. Le descrizioni funzionali rimangono accurate.
- [ ] **Step 5: GREEN locale.** Suite dal nuovo `MjmCleanerKit`, build Debug e Release, prova del package script, parse del workflow YAML con `ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' .github/workflows/release-macos.yml` e ricerca dei riferimenti attivi obsoleti. Le occorrenze storiche in `docs/superpowers/` sono ammesse, quelle in workflow/README/script/progetto non lo sono. Il workflow remoto rimane disabilitato.
- [ ] **Step 6: Commit.** Stage solo i percorsi espliciti rimossi/spostati/modificati; commit `refactor(swift): make the native app the repository root`.

### Task 7: Verificare il repository finale da un checkout pulito

**Files:**
- Create: `docs/superpowers/verification/2026-10-16-swift-port-5-final.md`.

**Interfaces:**
- Consumes: commit Task 6.
- Produces: evidenza finale per review e decisione di merge/attivazione CI.

- [ ] **Step 1: Checkout pulito.** Creare una copia temporanea del commit corrente con `git archive` o un worktree separato; non usare `git clean` sul worktree di sviluppo. Assicurarsi che `.build` e DerivedData non vengano copiati.
- [ ] **Step 2: Verifiche complete.** Nel checkout pulito: `swift test -Xswiftc -warnings-as-errors` (conteggio corrente); build Debug e Release con `xcodebuild`; package/estrazione v0.1.0, `lipo -archs`, plist, `codesign --verify --deep --strict`; nessun warning/error. Controllare che il parser YAML accetti il workflow e che non ci siano path attivi del vecchio layout.
- [ ] **Step 3: Review Sol dell'intero branch.** Confrontare il diff dalla base `037b5bb` con spec e gate, triagiare Important/Minor e correggere i primi con nuovo test e re-review. Rilanciare le prove interessate dopo ogni correzione.
- [ ] **Step 4: Verbale e commit.** Salvare comandi, output e limiti (in particolare workflow GitHub ancora disabilitato e nessuna release pubblicata), stage solo il verbale, commit `docs(swift): verify native handoff from a clean checkout`. Conservare branch e worktree fino alla scelta dell'utente su merge e attivazione del workflow.
