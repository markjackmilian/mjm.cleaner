# Swift port 5 — verifica finale da un checkout pulito

Data: 2026-10-18, Europe/Rome. Esito: **PASS** — repository Swift alla radice, senza il C#, verificato da una copia pulita.

## Identità

- Commit verificato: `1157df5b2994d919258b65beeb7701bdc3f6765f` (albero `1e2b0ff9bc6b75c42b97664db77848e3207a028b`), branch `codex/swift-port-5`, base `037b5bb`.
- Commit della rimozione e dello spostamento: `c7e3146` (`refactor(swift): make the native app the repository root`), seguito dalle correzioni della revisione finale `b9541a9` e `1157df5`.
- macOS 27.0.1 (26A434), Xcode 27.1 (27A9275), Swift 6.4.
- Alberi dei sorgenti dell'app identici a quelli del gate (`47d5a79`, sotto `swift/`): `MjmCleaner` `6fd4490f`, `Config` `c10d7ba4`, `MjmCleaner.xcodeproj` `9d750874`. `MjmCleanerKit` è cambiato solo per un commento di test (`XcodeFixtures.swift`, la provenienza delle fixture), `Scripts` solo per le righe d'uso.

## Copia pulita

`git archive 1157df5 | tar -x` in una cartella nuova: nessuna `.build`, `.swiftpm` o DerivedData (0 trovate). Ogni build usa una DerivedData nuova. Il worktree di sviluppo non è stato pulito con `git clean`.

## Prove

| Prova | Esito |
| --- | --- |
| `cd MjmCleanerKit && swift test -Xswiftc -warnings-as-errors` | exit 0; 536 test in 48 suite (Core) e 173 in 21 suite (Features); nessun avviso o errore |
| `bash Scripts/package-release.test.sh` | `PASS: input validation`, `PASS: collision refusal and failure cleanup` |
| `bash Scripts/demo-xcode-preview.test.sh` | `PASS: demo Xcode preview` |
| `zsh -n Scripts/screenshots.sh` | exit 0 |
| `xcodebuild … -configuration Debug … build` | exit 0, nessun avviso del compilatore |
| `bash Scripts/package-release.sh --tag v0.1.0 --build-number 1 --output-dir <scratch>` | exit 0, nessun avviso del compilatore (Release universale) |
| ZIP estratto con `ditto -x -k` | `lipo -archs` → `x86_64 arm64`; `CFBundleIdentifier=com.mjm.cleaner`, `CFBundleName=mjm.cleaner`, `CFBundleExecutable=MjmCleaner`, `CFBundleShortVersionString=0.1.0`, `CFBundleVersion=1`, `LSMinimumSystemVersion=15.0`, `DTXcodeBuild=27A9275`; `codesign --verify --deep --strict` exit 0, `Signature=adhoc`; nessuna stringa della demo nel binario |
| SHA-256 dello ZIP | `9e48c4e3be3eb8076786b7d798a9317d73e906b8f76ae26dd0bf74e2634ddd20` (3.373.625 byte) |
| `ruby -e 'require "yaml"; YAML.load_file(…)'` sul workflow | exit 0 |
| Riferimenti attivi al vecchio layout fuori da `docs/` | solo occorrenze legittime: il marcatore `*.slnx` dello scanner dei progetti, un Dockerfile di prova con `dotnet` e il commento di provenienza delle fixture |

Gli ZIP non sono riproducibili bit per bit: il binario Release porta la mappa di debug con i percorsi della cartella temporanea di ogni build. Per questo i quattro SHA-256 registrati nella fase 5 sono tutti diversi a parità di sorgenti. La firma ad hoc cambia di conseguenza a ogni build, e il README lo dice per l'Accesso completo al disco. (Stato al momento della verifica: dopo la correzione di M-5 la mappa di debug non c'è più e la causa è un'altra, vedi `2026-10-18-swift-port-5-m5.md`.)

## Revisione dell'intero branch

Revisione Opus di `037b5bb..c7e3146` contro piano, spec e verbali, verdetto **DA CORREGGERE**: un Important e otto Minor, tutti nei testi o nel workflow, nessuno nel codice dell'app.

| Rilievo | Esito |
| --- | --- |
| I-1: il README diceva che il permesso di Accesso completo al disco sopravvive a una ricompilazione dello stesso sorgente; falso, perché la firma ad hoc cambia a ogni build | corretto in `b9541a9` |
| M-1, M-2: nel gate Xcode 27.0 invece di 27.1, e prove visive attribuite all'albero del pacchetto invece che a `c4b5f77` | corretti in `1157df5` |
| M-3: «right-click → Open» non vale più da macOS 15 | corretto in `b9541a9` (solo «Open Anyway») |
| M-4: `.gitignore` senza `.idea/` e `.vscode/` | corretto in `b9541a9` |
| M-6: commento delle fixture verso un percorso rimosso | corretto in `b9541a9` |
| M-7: workflow con permessi ampi, checkout per nome ambiguo, Xcode predefinito non preferito | corretto in `b9541a9`: `contents: read` globale e `write` solo nel job `release`, `ref: refs/tags/…` con `persist-credentials: false`, `/Applications/Xcode.app` provato per primo, `sw_vers` anche nel job `package` |
| M-8: frase dei requisiti Swift | corretta in `b9541a9` |
| M-5: il binario Release contiene percorsi locali (mappa di debug) | **rinviato**: richiede di cambiare `package-release.sh` (strip) e ripetere le prove del pacchetto; da trattare a parte; corretto poi il 2026-10-18, vedi `2026-10-18-swift-port-5-m5.md` |

Note della revisione, senza azione: i commit della prima sessione Codex (`436f3de`…`da662db`) non hanno il trailer `Co-Authored-By`, quelli della ripresa sì. `git log --follow` sull'icona mostra la storia del file C# identico, effetto solo cosmetico del rilevamento dei rinomini.

## Limiti e stato

- Il workflow `.github/workflows/release-macos.yml` resta `disabled_manually` su GitHub e non è mai stato eseguito nella nuova forma. È verificato solo da revisione e parser YAML; il vecchio test `tests/build/release-workflow.test.rb` è stato rimosso con il C#, senza sostituto.
- Nessun tag, nessuna release, nessun push in questa fase. Merge su `main` e riattivazione del workflow sono decisioni distinte dell'utente.
- Nel worktree di sviluppo restano due residui locali non tracciati: `src/` (bin/obj del C#, 118 MB) e una cartella `swift/` vuota. Non entrano nei commit e si tolgono a mano.
- Prima di un merge nel checkout `main`: le tre modifiche locali non committate a `swift/**/Localizable.xcstrings` (voci aggiunte da Xcode) bloccano il merge, perché quei file vengono spostati. Vanno scartate o committate a parte.
