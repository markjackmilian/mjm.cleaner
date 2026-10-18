# Swift port 5 — verbale visivo

Date: 2026-10-16 (prima sessione) e 2026-10-18 (ripresa), Europe/Rome. Stato: **PASS — gate visivo superato**, con quattro rilievi Minor rinviati (vedi «Ripresa del 2026-10-18»).

Il 2026-10-16 il confronto offline era completo e il collaudo attivo parziale: restavano l’errore V-01 dell’anteprima Xcode nella demo e la viewport 900×600. Il 2026-10-18 V-01 è corretto, la finestra minima è catturata su tutte le pagine e il difetto D-2 emerso da quella cattura è corretto. Il requisito VoiceOver è stato rimosso dall’utente durante la prima sessione («ferma voice over, non mi interessa»), quindi non costituisce un blocco.

## Identità e finestra autorizzata

- Commit di codice verificato: `57ce1329f17407e8876c52ee50d5a74e0a9fc647`, branch `codex/swift-port-5`.
- Tree `swift/`: `616061fd9468e841bf6c03e49994d536d0a88d32`.
- macOS `27.0.1` (`26A434`); sessione attiva circa 15:45–15:56 CEST.
- L’utente ha risposto «procedi» dopo la richiesta di una finestra UI dedicata; il controller ha presentato bundle e prove prima della delega.
- App usata: `/private/var/folders/vv/bthtdqwx31q582gp464m7r0h0000gn/T/mjm-cleaner-screenshots/Build/Products/Debug/MjmCleaner.app`, ID letto dal plist `com.mjm.cleaner.debug`.
- Avvio per percorso assoluto, sempre con `-MJMDemo` e pagina nota. Nessun comando di pulizia o conferma distruttiva premuto. Demo chiusa al termine.

## Mappatura offline, chiaro e scuro

Esaminati prima di aprire l’app tutti i 26 PNG sotto `2026-10-15-swift-4b/` e tutti i 18 PNG sotto `2026-10-02-macos-redesign/`. Ogni riga indica entrambe le varianti `-light.png` e `-dark.png`. Il riferimento C# è 2240×1400 pixel, equivalente a 1120×700 punti; gli screenshot Swift sono 1120×700 pixel. Per Impostazioni il riferimento separato è 1400×1360 pixel.

| Swift 4b | Redesign | Esito offline e differenze osservate in entrambi i temi |
| --- | --- | --- |
| `choose` | `01-scegli` | Struttura, categorie, rischio e azione inferiore coerenti. Sidebar e selezioni native; demo Swift seleziona quattro categorie contro una nel riferimento. |
| `scan` | `02-analizza` | Titolo, avanzamento, categorie e annullamento presenti. Swift mostra percorso corrente e più categorie demo. |
| `confirm` | `03-conferma` | Gruppi, selezioni, avviso e comando inferiore presenti. Inventario demo diverso; scorrimento lungo da verificare attivamente. |
| `done` | `04-fatto` | Esito, spazio, riepilogo e nuova pulizia presenti. Swift mostra più categorie e un errore demo in basso; importi differenti non sono una regressione di layout. |
| `docker` | `05-docker` | Riferimento mostra motore indisponibile; Swift mostra inventario disponibile. Corrispondenza di pagina, non di stato. Gruppi inferiori oltre la piega: verifica attiva necessaria. |
| `docker-unavailable` | `05-docker` | Stesso stato indisponibile, testo e Riprova leggibili. Controlli toolbar nativi. |
| `docker-report` | `05-docker` | Stato report aggiuntivo senza equivalente diretto nel set C#. Titolo, recupero, avvertimento, voci e nuova analisi leggibili. |
| `xcode` | `06-xcode` | Quattro gruppi, selezione vuota e azioni inferiori coerenti; Swift ha dati demo popolati contro gruppi vuoti/parziali C#. |
| `xcode-preview` | `06-xcode` | Anteprima aggiuntiva senza equivalente diretto. Rischio runtime, accettazione e comandi presenti nello screenshot 4b; prova attiva necessaria. |
| `xcode-report` | `06-xcode` | Report aggiuntivo senza equivalente diretto. Esiti per voce, nota spazio e nuova analisi leggibili. |
| `history` | `07-storico` | Quattro colonne e righe alternate coerenti. Swift usa badge categoria, tre righe demo e diversa densità nativa. |
| `settings` | `08-impostazioni`, `09-impostazioni-eta` | Sheet Swift sopra la principale; C# ha finestra separata. Aspetto a radio nativi invece di miniature; liste e soglie in scorrimento. Campi inferiori assenti dalla cattura iniziale: prova attiva necessaria. |
| `startup-failure` | nessun equivalente; `01-scegli` solo come ingresso | Stato di errore aggiuntivo. Testo di errore e Esci leggibili; non è confrontabile come parità visiva della pagina Scegli. |

Differenze intenzionali del port osservate: sidebar e toolbar macOS native, indicatore dei passi a capsule, radio e checkbox nativi, sheet modale Impostazioni, tabella nativa Storico. Il confronto è qualitativo: non dimostra contrasto numerico, parità dei dati o navigazione parlata. Non sono emersi difetti visivi certi nelle sole immagini archiviate.

## Verifiche attive

`swift/Scripts/screenshots.sh /private/tmp/mjm-task3-current choose docker settings` ha completato con exit 0: sei catture attive chiaro/scuro, tutte esaminate. Nessun clipping osservato su queste tre pagine a 1120×700. Le immagini temporanee duplicano il riferimento e non sono aggiunte al repository.

`swift/Scripts/screenshots.sh /private/tmp/mjm-task3-unknown not-a-demo-page` ha restituito exit 2 con `pagina demo sconosciuta: not-a-demo-page`, prima della build/avvio. Il rifiuto dello script è verificato; non è stata eseguita una prova separata di avvio dell’app con pagina sconosciuta.

| Prova | Esito | Evidenza osservata e limiti |
| --- | --- | --- |
| Viewport 900×600 | BLOCKED | Trascinamento da 1120×700 verso 900×600 senza variazione osservata; azione nativa «ridimensiona finestra» porta a 1920×1170, non al formato richiesto. Secondo trascinamento senza variazione. Non si deduce il pass dal `minWidth/minHeight` nel codice. |
| Docker sotto la piega, 1120×700 | PASS limitato | Scorrimento reale: barra passa da 0 a circa 0,9997; compaiono Volumi non montati, `a1b2c3d4`, `shop_pgdata` e Da tenere. Avviso e pulsante inferiore restano visibili. |
| Sheet Impostazioni, 700×560 | PASS limitato | Apertura dal pulsante; scorrimento fino a soglia 500 MB e età 90/30/180 giorni. Annulla/Salva sempre visibili. Stepper soglia 500→501 osservato; inviato Decrement, poi Annulla. Nessun salvataggio. |
| Sidebar e disclosure Xcode | PASS funzionale limitato | Click Xcode cambia pagina; apertura Dispositivi simulati mostra iPhone 15 e iPad Air disabilitato con motivo «In esecuzione: chiudilo per eliminarlo». Non è una prova VoiceOver. |
| Selezione e anteprima cache Xcode | FAIL | `ShopApp-abcdefgh` selezionata: riepilogo 3 GB / 1 selezione e Anteprima abilitata. Premendo Anteprima compare errore interno; vedi difetto V-01. |
| Storico | PASS funzionale limitato | Tre righe, quattro colonne e totale 9,4 GB visibili. Click ordinamento Spazio cambia l’ordine delle righe. Non è una prova VoiceOver. |
| Contenuti arbitrariamente lunghi e Conferma a 900×600 | NON VERIFICATO | I dati demo osservati non coprono il caso di stress e la viewport minima non è stata ottenuta. |
| Passi, selezioni, campi e ritorno del fuoco con VoiceOver | RIMOSSO DALL’UTENTE | Nessun pass dichiarato; requisito ritirato durante il collaudo. |

## Difetto V-01 — anteprima cache Xcode nella demo

Riproduzione sulla build indicata:

1. Avviare `-MJMDemo docker -MJMAppearance light`.
2. Aprire Xcode dalla sidebar.
3. Selezionare `ShopApp-abcdefgh` sotto DerivedData.
4. Premere «Anteprima selezione» (azione non distruttiva).

Atteso: anteprima della selezione. Osservato: testo rosso `Selected file candidate has no complete guarded inventory entry: ShopApp-abcdefgh`; l’anteprima non compare. Riproduzione osservata una volta nella demo, senza inferire l’impatto sui dati reali. Difetto Important per l’accettazione del percorso demo; correzione delegata al controller, nessun codice modificato in questo task.

Evidenza: [xcode-preview-error-light.png](2026-10-16-swift-port-5/xcode-preview-error-light.png), cattura finestra 1920×1170. La finestra nella cattura salvata è inattiva; l’errore era stato osservato prima anche nello screenshot CUA e nello stato AX dopo l’azione.

## VoiceOver e ripristino

Prima della revoca: Cmd-F5 non ha prodotto uno stato osservabile; apertura diretta di `/System/Library/CoreServices/VoiceOver.app` tramite CUA terminata con timeout `-10005`. Nessuna navigazione parlata verificata. Dopo «ferma voice over, non mi interessa», interrotti tutti i tentativi. `pgrep -x VoiceOver`, eseguito con accesso necessario alla lista processi, ha restituito exit 1 senza PID: VoiceOver non risultava attivo. Le osservazioni AX del verbale sono prove funzionali, non sostituiscono il parlato.

## Condizioni residue al 2026-10-16

Correggere e riprovare V-01; ottenere una prova osservata a 900×600 con contenuti lunghi, azioni inferiori e sheet. Questo verbale parziale non autorizzava il gate di consegna né l’avvio del Task 4. Nessun test RED/GREEN applicabile in quella sessione, poiché non erano state apportate correzioni al codice.

## Ripresa del 2026-10-18

Dopo il limite d’uso della prima sessione il lavoro è proseguito in Claude Code, nello stesso worktree. Le prove attive usano solo `swift/Scripts/screenshots.sh`, che avvia la demo per percorso assoluto con `-MJMDemo` e cattura con `screencapture -l`: nessun input sintetico, nessun trascinamento della finestra. L’utente ha lasciato il Mac libero nelle due finestre concordate (circa 17:19–17:21 e 18:03 CEST).

### Correzioni

| Commit | Contenuto | Prova |
| --- | --- | --- |
| `7e80fdf` | V-01: `DemoData.xcodeSnapshot` riceve `fileInventory` per le tre cartelle selezionabili, costruito come in `XcodeFileScanner`; la pagina `xcode-preview` seleziona anche `ShopApp-abcdefgh`. Test `swift/Scripts/demo-xcode-preview.test.sh`, che compila il vero `DemoData.swift` contro `CleanerCore` | RED sul `DemoData.swift` di `da662db`: `Selected file candidate has no complete guarded inventory entry: ShopApp-abcdefgh`; GREEN: `PASS: demo Xcode preview`. Revisione Opus: flusso reale `XcodeModel` + `DemoServices` fino al resoconto senza errori, 12 mutazioni su 15 uccise, le 3 sopravvissute non lette dalla demo |
| `fb87d80`, `56377ec` | `-MJMWindowSize <L>x<A>` solo Debug in `DemoLaunch` e `screenshots.sh --size`; la finestra minima reale è 900×652 punti (i 900×600 della vista sotto la toolbar di 52 pt, come già provato nel piano 4b) | Validazione prima della build provata con shim; `--size 900x600` → 1800×1304 px a 2x su tutte le pagine |
| `66d51e5` | D-2: la presa d’atto «Ho capito…» del pannello di conferma Xcode esce dallo scorrimento interno alto 220 pt e sta sopra i pulsanti. Scelta dell’utente: scostamento voluto dal C#, che ha lo stesso scorrimento (`XcodeView.axaml`, `ScrollViewer MaxHeight="220"`) | Catture [1120 chiaro](2026-10-16-swift-port-5/xcode-preview-1120-light.png), [1120 scuro](2026-10-16-swift-port-5/xcode-preview-1120-dark.png), [900 chiaro](2026-10-16-swift-port-5/xcode-preview-900-light.png), [900 scuro](2026-10-16-swift-port-5/xcode-preview-900-dark.png): casella visibile, «Conferma ed elimina» disabilitato finché non è spuntata |
| `c4b5f77` | Lo script passa sempre `-MJMWindowSize` (1120x700 senza `--size`): macOS ricorda la misura in `NSWindow Frame main` dei defaults Debug e `-ApplePersistenceIgnoreState` non la scavalca, tanto che un giro senza `--size` dopo uno a 900×600 era uscito ancora 900×652 | Giro successivo senza `--size`: 2240×1400 px, cioè 1120×700 punti |

### Finestra minima, tutte le pagine

`swift/Scripts/screenshots.sh --size 900x600` su `56377ec`: 26 catture, exit 0, tutte 1800×1304 px (900×652 pt), tranne `startup-failure` 1800×1264 px (senza toolbar). Una revisione Opus ha esaminato ogni immagine in chiaro e scuro: nessuna sovrapposizione, nessun controllo fuori dalla finestra, azioni inferiori intere su tutte le pagine, sheet Impostazioni intero (circa 700×559 pt) con Annulla e Salva visibili. `c4b5f77` e `66d51e5` cambiano solo lo script e il pannello di conferma Xcode, ricatturato sopra.

| Prova aperta il 2026-10-16 | Esito |
| --- | --- |
| Viewport 900×600 | PASS: finestra minima ottenuta da codice su tutte le pagine |
| Selezione e anteprima cache Xcode (V-01) | PASS a 1120×700 e a 900×652 |
| Contenuti lunghi e Conferma a 900×600 | PASS per le azioni inferiori; con i dati demo nessun testo troncato. Contenuti arbitrariamente lunghi non dimostrati dai dati demo; i percorsi lunghi reali del collaudo di parità (finestre più grandi) non hanno mostrato troncamenti con perdita d’informazione |
| Docker sotto la piega | PASS limitato della prima sessione (scorrimento reale a 1120×700); a 900×652 i gruppi inferiori non si vedono senza scorrere, vedi D-3 |
| Sheet Impostazioni | PASS: intero nella finestra minima ([cattura](2026-10-16-swift-port-5/settings-900-light.png)); lo scorrimento fino a soglia ed età è quello verificato attivamente il 2026-10-16 |

### Rilievi rinviati (Minor)

| Rilievo | Cattura | Motivo del rinvio |
| --- | --- | --- |
| D-1: a 900×652 la pagina Conferma della demo mostra 6 righe su 7; il gruppo «Log e crash report» è sotto la piega e nulla indica lo scorrimento | [confirm-900](2026-10-16-swift-port-5/confirm-900-light.png) | Scelta dell’utente: barre di scorrimento a comparsa di macOS, contenuto raggiungibile scorrendo, conteggio corretto nel titolo e nel pulsante |
| D-3: a 900×652 i gruppi Docker dopo «Costruite in locale» sono sotto la piega senza indizio | [docker-900](2026-10-16-swift-port-5/docker-900-light.png) | Stesso comportamento di D-1; nessuna voce selezionata per impostazione |
| D-4: a 900×652 la colonna Categorie dello Storico mostra 2 badge su 4, l’ultimo ritagliato | [history-900](2026-10-16-swift-port-5/history-900-light.png) | Solo presentazione; il dato completo resta nella riga a finestre più larghe |
| Pannello di conferma Xcode: la riga UUID dell’ultimo dispositivo è tagliata dallo scorrimento interno | catture `xcode-preview-*` | Scorrimento interno identico al C#; dopo D-2 non nasconde più nulla di obbligatorio |

Costo se il rinvio è sbagliato: un utente su una finestra minima non si accorge di un gruppo finché non scorre; nessun rischio di eliminazione, perché ogni pulsante distruttivo riporta il totale.

Note già presenti nel 4b, fuori ambito: in scuro «Conferma ed elimina» disabilitato si distingue poco dall’abilitato; nei dati demo Fatto riporta «7 elementi eliminati» e «1 elemento non eliminato»; nelle intestazioni Xcode compare «1 voci».

### Esito

Gate visivo superato per le prove nel perimetro (VoiceOver escluso dall’utente). Nessun difetto Critical o Important aperto.
