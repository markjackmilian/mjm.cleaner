# Aggiornamenti dell'app dalle release GitHub

## Obiettivo e ambito approvato

Oggi una nuova versione di mjm.cleaner si installa a mano: si scarica lo ZIP dalla pagina
delle release, si estrae, si sostituisce il bundle e si fa «Apri comunque». L'obiettivo è che
l'app scopra da sola una release più recente, la scarichi e la verifichi in background, e
proponga «Installa e riavvia».

Le release esistono già e non cambiano: il workflow `.github/workflows/release-macos.yml`
pubblica, per ogni tag `vMAJOR.MINOR.PATCH`, un solo asset
`mjm.cleaner-vX.Y.Z-macos-universal.zip` (bundle universale firmato ad hoc, non notarizzato).
L'API GitHub espone per ogni asset un `digest` `sha256:…` (per `v0.1.0`:
`sha256:6c1dfc5c886b1cbc8a0849770fe66c4da07247f1e82094aeaa29cddf48154d07`) e
`/releases/latest` esclude bozze e prerelease.

Decisioni dell'utente (2026-10-19):

- **Proposta «Installa e riavvia» / «Più tardi».** L'app si chiude, il bundle viene sostituito
  sul posto e l'app si riapre; «Più tardi» ripropone l'aggiornamento al prossimo avvio.
- **Controllo all'avvio e ogni 24 ore**, disattivabile, con «Controlla ora» nelle Impostazioni
  e «Controlla aggiornamenti…» nel menu dell'app.
- **Verifica con il digest GitHub e controlli del bundle**, senza firma EdDSA né segreti in CI.
- **Updater nativo** (approccio A): codice del progetto in `CleanerCore` e `CleanerFeatures`
  più uno script di sostituzione; niente Sparkle, nessuna dipendenza esterna, nessuna modifica
  al workflow di release.

Fuori ambito: firma EdDSA, Sparkle, canale prerelease, aggiornamenti delta, «Salta questa
versione», rinnovo automatico dell'Accesso completo al disco (impossibile con la firma ad hoc:
il permesso è legato alla singola build, README «Full Disk Access»), aggiornamento delle build
Debug.

## Componenti

### CleanerCore/Update

Tutto puro e testabile con `swift test`; la rete passa da un protocollo iniettato.

- **`AppVersion`**: parsing di `MAJOR.MINOR.PATCH` con `v` iniziale facoltativa, confronto
  numerico campo per campo. Una stringa non valida non produce una versione e non si
  confronta mai come testo.
- **`HTTPClient`**: protocollo con due operazioni, lettura di dati (`GET` → `Data` + stato
  HTTP) e download in un file con avanzamento. Implementazione `URLSessionHTTPClient`; le
  richieste all'API mandano `Accept: application/vnd.github+json` e uno `User-Agent`
  `mjm.cleaner/<versione>`, senza autenticazione.
- **`ReleaseFeed`** / **`GitHubReleaseFeed`**: `GET
  https://api.github.com/repos/markjackmilian/mjm.cleaner/releases/latest`. Restituisce
  `AvailableRelease` (versione, tag, URL della pagina della release, URL dell'asset,
  dimensione, digest SHA-256 in esadecimale) solo se:
  - `tag_name` è una `AppVersion` valida e **maggiore** della versione corrente;
  - fra gli asset c'è **esattamente uno** chiamato `mjm.cleaner-<tag>-macos-universal.zip`;
  - quell'asset ha un `digest` nella forma `sha256:<64 cifre esadecimali>`.
  Release uguale o più vecchia → `nil` (aggiornato). Release più recente ma con asset o digest
  non conformi → errore `invalidRelease(motivo)`.
- **`UpdateDownloader`**: scarica l'asset in `<updates>/<tag>/download.partial`, calcola lo
  SHA-256 in streaming (CryptoKit) e solo se coincide col digest rinomina in `<asset>.zip` e
  scrive accanto `release.json` con l'`AvailableRelease` (serve a riproporre l'aggiornamento al
  riavvio senza rete).
  Se il digest non coincide o il download si interrompe, il file parziale si cancella. Se
  `<asset>.zip` esiste già e il suo digest coincide, non si riscarica. Le cartelle di tag
  diversi da quello corrente si cancellano.
- **`UpdateVerifier`**: estrae lo ZIP con `/usr/bin/ditto -x -k` in `<updates>/<tag>/expanded/`
  tramite il `ProcessRunning` esistente, poi richiede che:
  - la cartella estratta contenga un solo elemento, un bundle `.app`;
  - `CFBundleIdentifier` sia `com.mjm.cleaner`;
  - `CFBundleShortVersionString` coincida con la versione del tag;
  - `/usr/bin/codesign --verify --deep --strict` riesca;
  - `/usr/bin/lipo -archs` sull'eseguibile riporti sia `arm64` sia `x86_64`.
  Ogni controllo fallito produce un motivo distinto e cancella `expanded/` e lo ZIP.
- **`UpdateInstaller`**: verifica i prerequisiti di installazione e avvia lo script di
  sostituzione (sezione «Installazione»).
- **`AppPaths.updatesDirectory`**: `<supportDirectory>/updates`. La cache **non** sta in
  `~/Library/Caches`: la categoria «Cache di sistema» dell'app la cancellerebbe. Application
  Support è già protetta dalla deny-list.
- **`CleanerSettings`**: due campi nuovi, `AutomaticUpdateChecks` (`Bool`, predefinito `true`)
  e `LastUpdateCheck` (`Date?`, predefinito `nil`), decodificati con la stessa regola dei
  campi esistenti: se mancano valgono il predefinito.

### CleanerFeatures/Update

**`UpdateModel`** (`@MainActor @Observable`, senza SwiftUI), con stati:

| Stato | Significato |
|---|---|
| `idle` | nessuna operazione in corso, nessun risultato da mostrare |
| `checking` | lettura del feed |
| `upToDate` | ultimo controllo manuale riuscito senza novità |
| `downloading(progress)` | download in corso |
| `ready(AvailableRelease, bundle)` | ZIP verificato, bundle estratto pronto |
| `installing` | script avviato, l'app sta per chiudersi |
| `failed(motivo)` | errore da mostrare |

Pianificazione: all'avvio e a ogni tick di un timer orario, se `AutomaticUpdateChecks` è vero
e `LastUpdateCheck` è assente o più vecchio di 24 ore secondo il `WallClock` iniettato, parte
un controllo automatico. `checkNow()` ignora la soglia. `LastUpdateCheck` si salva solo dopo
un controllo riuscito (con o senza novità). Un controllo automatico che fallisce torna a `idle`
senza mostrare nulla; un controllo manuale fallito va in `failed`. Un solo controllo alla volta.

L'ambiente decide se l'updater esiste: `AppEnvironment.live` lo crea solo quando il bundle id è
`com.mjm.cleaner`. Le build Debug (`com.mjm.cleaner.debug`) e la demo non controllano mai.

### App (SwiftUI)

- **Banner** in cima alla finestra principale con stato `ready`: «mjm.cleaner X.Y.Z è pronto»,
  pulsanti «Installa e riavvia», «Più tardi» e il collegamento «Novità» alla pagina della
  release.
- Comando di menu **«Controlla aggiornamenti…»** accanto a quello delle Impostazioni.
- Sezione **«Aggiornamenti»** in `SettingsView`: interruttore del controllo automatico,
  «Controlla ora», versione corrente, data dell'ultimo controllo, ed esito dell'ultimo
  controllo manuale (`upToDate` o `failed`).

Tutti i testi nuovi vanno nei cataloghi `Localizable.xcstrings`.

## Flusso

1. **Controllo** (automatico o manuale) → `checking`.
2. Se c'è una release più recente → **download** subito, in background → `downloading`.
3. **Verifica** → `ready`, oppure `failed` con i file cancellati.
4. **Proposta**: il banner compare. «Più tardi» lo nasconde per la sessione. Al prossimo
   avvio, prima e indipendentemente da qualsiasi controllo in rete, `UpdateModel` cerca in
   `updates/` una cartella di tag con `release.json` e ZIP: se il tag è ancora più recente
   della versione corrente, ricalcola il digest, ripete la verifica del bundle e torna a
   `ready`; altrimenti cancella la cartella.
5. **Conferma**: «Installa e riavvia» apre un dialogo con l'avviso «Dopo l'aggiornamento dovrai
   concedere di nuovo l'Accesso completo al disco, se lo usi (serve solo per il Cestino).» Il
   pulsante è disabilitato, con il motivo, mentre è in corso una pulizia: wizard in esecuzione,
   cancellazione Docker o Xcode. `MainModel` espone per questo una proprietà che riunisce i tre
   casi (oggi `canNavigateGlobally` copre solo Xcode).
6. **Installazione** → `installing`: avvio dello script, poi `NSApp.terminate`.

## Installazione

**Prerequisiti**, controllati prima di offrire «Installa e riavvia»:

- la cartella che contiene `Bundle.main.bundleURL` è scrivibile;
- il percorso del bundle non contiene `/AppTranslocation/`.

Se uno dei due manca, il banner offre invece **«Mostra nel Finder»**: seleziona il nuovo bundle
verificato e spiega di sostituire a mano quello in uso.

**Script di sostituzione**: `/bin/sh`, scritto in una cartella temporanea propria
(`FileManager.url(for: .itemReplacementDirectory, …)`), avviato staccato dall'app. Riceve come
argomenti posizionali, mai interpolati nel testo dello script: PID dell'app, percorso del
bundle attuale, percorso del nuovo bundle, tag, cartella `updates`. Passi:

1. attende la fine del PID (`kill -0` ogni 0,2 s, al massimo 30 s; oltre, rinuncia senza
   toccare nulla);
2. copia con `/usr/bin/ditto` il nuovo bundle in `<cartella del bundle>/.mjm.cleaner-update-<tag>.app`,
   sullo stesso volume del bundle attuale;
3. rinomina il bundle attuale in `.mjm.cleaner-old-<tag>.app`, poi lo staging nel nome del
   bundle attuale; se la seconda rinomina fallisce, riporta `.old` al nome originale e cancella
   lo staging;
4. a sostituzione riuscita cancella `.old` e `<updates>/<tag>/`;
5. scrive `<updates>/install-result` (`ok <tag>` oppure `failed <passo>`) e accoda il proprio
   log a `<updates>/install.log`;
6. riapre il bundle al percorso originale con `/usr/bin/open`: la versione nuova, o la vecchia
   dopo un ripristino.

**Al prossimo avvio** `UpdateModel` legge `install-result`: `ok <tag>` con versione corrente
uguale al tag → successo, il file si cancella; `failed <passo>` → avviso con la versione rimasta
installata e il percorso di `install.log`, poi il file si cancella.

**Gatekeeper**: l'app non dichiara `LSFileQuarantineEnabled`, quindi lo ZIP scaricato con
`URLSession` non riceve l'attributo di quarantena. L'updater **non** rimuove attributi estesi:
se il bundle nuovo venisse bloccato all'avvio, vale la stessa procedura «Apri comunque» del
README. Il collaudo lo verifica.

## Errori

| Caso | Esito |
|---|---|
| Rete assente, timeout, HTTP diverso da 200, limite dell'API (60 richieste/ora senza autenticazione) | automatico: silenzioso, si riprova al tick successivo; manuale: `failed` |
| Release più recente con asset mancante, duplicato o con nome inatteso, digest assente o malformato | `failed(invalidRelease)` |
| Digest del file scaricato diverso | file cancellato, `failed` |
| Disco pieno o download interrotto | file parziale cancellato, `failed` |
| Bundle estratto non conforme (bundle id, versione, firma, architetture, contenuto dello ZIP) | file cancellati, `failed` con il motivo |
| Cartella del bundle non scrivibile o App Translocation | «Mostra nel Finder» al posto di «Installa e riavvia» |
| Lo script fallisce | ripristino del bundle vecchio, `install-result` = `failed`, avviso al riavvio |

## Test

**CleanerCoreTests**, senza rete (`HTTPClient` finto) e con fixture JSON lette dal sorgente come
quelle di Docker e Xcode:

- `AppVersion`: parsing con e senza `v`, ordinamento, stringhe non valide.
- `GitHubReleaseFeed`: release più recente, uguale, più vecchia; asset mancante, duplicato, con
  nome inatteso; digest assente o non `sha256:`; HTTP 403/404; JSON malformato.
- `UpdateDownloader`: digest giusto e sbagliato, file parziale cancellato, riuso della cache,
  pulizia dei tag vecchi.
- `UpdateVerifier`: bundle finti in una cartella temporanea e `ProcessRunning` finto per
  `ditto`, `codesign` e `lipo`; un test per ciascun controllo che fallisce.
- `CleanerSettings`: decodifica dei campi nuovi e di un `settings.json` senza.

**CleanerFeaturesTests**: `UpdateModel` con `WallClock` finto (soglia delle 24 ore, controllo
automatico silenzioso e manuale visibile, un controllo alla volta, «Più tardi», ripresa da
cache, blocco durante una pulizia, lettura di `install-result`), e `AppEnvironment` senza
updater per il bundle id Debug.

**Script**: `Scripts/update-install.test.sh`, nello stile di `package-release.test.sh`, con
bundle finti e un `sleep` come processo da attendere: sostituzione riuscita, ripristino quando
la seconda rinomina fallisce, timeout del PID, percorsi con spazi e apostrofi. Il job `test`
del workflow di release lo esegue insieme agli altri script.

**Revisione**: mutazioni sui controlli di sicurezza (confronto del digest, bundle id, versione,
firma, architetture, ripristino dello script); una mutazione che sopravvive richiede un test.

**Collaudo end-to-end**, senza pubblicare release: `Scripts/package-release.sh --tag v0.0.9`
costruisce in una cartella scratch una Release con l'updater e versione più bassa di `v0.1.0`.
Avviata, trova `v0.1.0` su GitHub, la scarica, la verifica e propone l'installazione. I clic li
fa l'utente (nessun input sintetico); si controllano bundle sostituito con versione `0.1.0`,
`install-result`, `install.log` ed eventuale blocco di Gatekeeper al riavvio. Poiché `v0.1.0`
non contiene l'updater, il collaudo esercita il ramo vecchia → nuova, l'unico che conta.
