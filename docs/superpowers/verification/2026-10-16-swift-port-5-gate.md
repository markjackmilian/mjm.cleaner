# Swift port 5 — gate di consegna

Data: 2026-10-18, Europe/Rome. Esito: **GO** — il Task 6 (rimozione del C# e Swift alla radice) può partire.

## Identità

- Commit verificato: `47d5a796016a3150baacd1c4889f58c1f6757af4`, branch `codex/swift-port-5`, worktree pulito prima e dopo le prove.
- Albero `swift/` del pacchetto: `30dea2b96051ef74a013eb0ef0243b8b1f050f32` (`swift/MjmCleaner` `6fd4490f7f8898e1475abf24e76cfcfebe2e937d`, `swift/MjmCleanerKit` `6747826cc2bc14faf7692892ceb03d23e49e26b6`).
- macOS 27.0.1 (26A434), Xcode 27.1 (27A9275): aggiornato dall'App Store alle 17:19 del 2026-10-18, prima delle prove del gate (lo ZIP riporta `DTXcodeBuild=27A9275`).

## Gate

| Condizione (piano, Task 5 Step 1) | Esito | Prova |
| --- | --- | --- |
| Registro di parità completo | PASS | `docs/superpowers/porting/2026-10-13-parity.md`, con le righe nuove del piano 5 (presa d'atto Xcode fuori dallo scorrimento, ordine delle voci) |
| Suite | PASS | `swift test -Xswiftc -warnings-as-errors` in `swift/MjmCleanerKit`: 536 test in 48 suite (Core) e 173 in 21 suite (Features), exit 0. Rispetto ai 536 + 172 del piano, il test in più è quello dei percorsi Debug del Task 1 (`f3cf554`) |
| Test degli script | PASS | `package-release.test.sh`: `PASS: input validation`, `PASS: collision refusal and failure cleanup`; `demo-xcode-preview.test.sh`: `PASS: demo Xcode preview` |
| Build Debug e Release senza avvisi | PASS | `xcodebuild` Debug exit 0; Release universale dentro `package-release.sh` exit 0. Nessun avviso del compilatore; l'unica riga «warning» di entrambi i log è di `appintentsmetadataprocessor` («Metadata extraction skipped, no AppIntents.framework dependency found»), estranea al codice |
| Pacchetto dallo stesso albero | PASS | `bash swift/Scripts/package-release.sh --tag v0.1.0 --build-number 1 --output-dir <scratch>` su `47d5a79`, albero `swift/` pulito |
| ZIP estratto: due slice e firma | PASS | Dopo `ditto -x -k`: `lipo -archs` → `x86_64 arm64`; `CFBundleIdentifier=com.mjm.cleaner`, `CFBundleName=mjm.cleaner`, `CFBundleExecutable=MjmCleaner`, `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=1`, `LSMinimumSystemVersion=15.0`; `codesign --verify --deep --strict` exit 0, `Signature=adhoc`, flags `0x2(adhoc)`; nessuna stringa della demo (`MJMDemo`, `/Users/demo`) nel binario Release |
| SHA-256 dello ZIP | registrato | `mjm.cleaner-v0.1.0-macos-universal.zip`: `edf75280f8f21704f84b8eb32b613ef958549267ca579aa927f03bf9d5ee5ebd` (3.373.409 byte) |
| Schermate e prove UI | PASS | [Verbale visivo](2026-10-16-swift-port-5-visual.md): V-01 e D-2 corretti, finestra minima su tutte le pagine; VoiceOver escluso dall'utente |
| Confronto reale | PASS | [Verbale di parità](2026-10-16-swift-port-5-parity.md): 7 categorie, Docker e Xcode coincidenti sullo stesso disco |
| Difetti Critical/Important aperti | nessuno | — |

## Albero collaudato e albero del pacchetto

Il confronto reale è stato fatto su `56377ec`. Fra quel commit e `47d5a79` sotto `swift/` cambiano tre file:

- `swift/MjmCleaner/Xcode/XcodeView.swift`: correzione D-2, la presa d'atto passa fuori dallo scorrimento del pannello di conferma. Solo disposizione: stesso stato, stessa condizione di conferma, nessun effetto sull'analisi confrontata. Ricatturata a 1120×700 e a 900×652 su `c4b5f77` (verbale visivo).
- `swift/MjmCleaner/Demo/DemoLaunch.swift`: commenti; il file è compilato solo in Debug.
- `swift/Scripts/screenshots.sh`: strumento di sviluppo, non entra nel pacchetto.

Il pacchetto è costruito dall'albero finale `30dea2b9…`, lo stesso che ha passato suite e build; le prove visive finali sono su `c4b5f77` (albero `2e558fe1`), che ne differisce solo per due commenti (`DemoLaunch.swift`, `screenshots.sh`).

## Minor rinviati

| Rilievo | Costo se il rinvio è sbagliato |
| --- | --- |
| D-1, D-3: a 900×652 l'ultimo gruppo di Conferma e i gruppi Docker inferiori sono sotto la piega, senza barra visibile finché non si scorre (barre a comparsa di macOS) | un gruppo notato solo scorrendo; i pulsanti distruttivi riportano sempre il totale |
| D-4: a 900×652 la colonna Categorie dello Storico mostra 2 badge su 4 | informazione visibile solo allargando la finestra |
| UUID dell'ultimo dispositivo tagliato dallo scorrimento del pannello Xcode | nessuno: dopo D-2 lo scorrimento non nasconde nulla di obbligatorio |
| Note del 4b: «Conferma ed elimina» disabilitato poco distinguibile in scuro; «1 voci»; dati demo di Fatto | estetica |
| Ordine alfabetico delle voci rispetto all'ordine grezzo del C# | un ordinamento da togliere, se lo si volesse identico |

## Limiti

- Il workflow GitHub `.github/workflows/release-macos.yml` resta `disabled_manually`. Nessun tag creato e nessuna release pubblicata. Il pacchetto è nello scratchpad della sessione.
- Nessuna identità Developer Program e nessuna notarizzazione: il bundle è firmato ad hoc, come previsto dal piano.
