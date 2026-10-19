# Aggiornamenti in-app — collaudo end-to-end

Data: 2026-10-19, Europe/Rome. Esito: **PASS** — una Release 0.0.9 con l'updater trova la v0.1.0 pubblicata su GitHub, la scarica, la verifica, la propone e si sostituisce sul posto.

## Identità

- Commit verificato: `362fa7f3b5276fb53fd9af394fe374f2fd4c3190`, branch `feat/app-updates`, worktree `.claude/worktrees/app-updates`.
- macOS 27.0.1 (26A434), Xcode 27.1 (27A9275).
- Build di collaudo: `bash Scripts/package-release.sh --tag v0.0.9 --build-number 1 --output-dir "$TMPDIR/mjm-app-updates-e2e/out"`, copiata con `ditto` in `$TMPDIR/mjm-app-updates-e2e/Applications/mjm.cleaner.app` (`CFBundleShortVersionString` `0.0.9`, `CFBundleIdentifier` `com.mjm.cleaner`).
- Release di destinazione: `v0.1.0` pubblicata il 2026-10-18 (nessuna release nuova è stata pubblicata per il collaudo).
- Prima del collaudo `~/Library/Application Support/com.mjm.cleaner/updates` non esisteva e `settings.json` non aveva le chiavi degli aggiornamenti (controllo automatico attivo per valore predefinito).
- I clic li ha fatti l'utente; il controller ha avviato i bundle e letto i file. Nessun input sintetico.

## Passi

| Passo (piano, Task 10 Step 4) | Esito | Prova |
| --- | --- | --- |
| 1. Avvio della 0.0.9 | PASS | `open …/mjm.cleaner.app`, PID 67245 |
| 2. Controllo, download e verifica all'avvio | PASS | Entro 6 s: `updates/v0.1.0/` con lo ZIP (3.188.840 byte), `release.json` ed `expanded/mjm.cleaner.app`. `shasum -a 256` dello ZIP = `6c1dfc5c886b1cbc8a0849770fe66c4da07247f1e82094aeaa29cddf48154d07`, uguale al digest dell'API. `release.json` con gli URL di `github.com/markjackmilian/mjm.cleaner` del tag. `settings.json`: `AutomaticUpdateChecks` `true`, `LastUpdateCheck` salvato |
| 3. Banner e Impostazioni | PASS (utente) | Banner «mjm.cleaner 0.1.0 è pronto da installare.»; Impostazioni → Aggiornamenti: versione installata 0.0.9, «La versione 0.1.0 è pronta da installare.» |
| 4. «Più tardi» e riavvio | PASS | Il banner sparisce; dopo ⌘Q e una nuova apertura (PID 68102) il banner torna. ZIP e `release.json` hanno lo stesso orario di modifica di prima (12:28:11): nessun nuovo download |
| 5. «Installa e riavvia…» | PASS (utente) | L'avviso sull'Accesso completo al disco compare; dopo la conferma l'app si chiude e si riapre |
| 6. Esito | PASS | `CFBundleShortVersionString` `0.1.0`; `install-result` `ok v0.1.0`; `install.log`: «aggiornamento a v0.1.0: attesa della fine del processo 68102» alle 10:31:03Z, «ok v0.1.0» alle 10:31:04Z; in `Applications` solo `mjm.cleaner.app` (nessun `.mjm.cleaner-update-*` o `.mjm.cleaner-old-*`); `updates/` contiene solo `install-result` e `install.log` (cartella `v0.1.0` cancellata); `codesign --verify --deep --strict` OK; nessuno script residuo; app riaperta dallo script (PID 68196, avviato alle 12:31:04) |

## Osservazioni

- **Gatekeeper**: nessun blocco alla riapertura. Il bundle installato ha solo l'attributo `com.apple.provenance`, nessuna quarantena; l'updater non ha rimosso attributi. `spctl -a -vv` lo rifiuta, come ogni bundle ad hoc non notarizzato (README), ma l'avvio non è stato impedito.
- **`open` con ambiente ridotto** (solo `PATH`): funziona, l'app è stata riaperta.
- **`install-result` resta su disco** con `ok v0.1.0`: la v0.1.0 riaperta non contiene l'updater e non lo legge, come previsto dal piano.
- **Prima riapertura del passo 4**: un `open` lanciato mentre la 0.0.9 stava ancora chiudendosi ha riattivato l'istanza in uscita invece di avviarne una nuova; ripetuto a chiusura completata. Non riguarda l'updater (lo script attende la fine del PID prima di `open`).

## Non coperto

- **App Management di macOS su `/Applications`**: la copia di collaudo stava in `$TMPDIR`, quindi la protezione che macOS applica alla modifica delle app in `/Applications` non è stata messa alla prova. Va verificata alla prima installazione reale da `/Applications`; se il `mv` venisse negato, lo script registra `failed move-old` (o `failed rollback`) e l'app lo segnala al riavvio.
- **Rinnovo dell'Accesso completo al disco** dopo l'aggiornamento: non provato (dipende dalla firma ad hoc, documentato nel README).
- **Percorsi di errore reali** (digest diverso, bundle non valido, rollback): coperti solo dai test automatici e dalle mutazioni delle revisioni.
