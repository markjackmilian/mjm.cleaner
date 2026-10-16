# Swift port 5 — verbale visivo parziale

Data: 2026-10-16, Europe/Rome. Stato: **BLOCKED — NO-GO per il gate visivo**.

Il confronto offline è completo; il collaudo attivo è parziale. Restano un errore riproducibile dell’anteprima Xcode nella demo e la verifica della viewport 900×600. Il requisito VoiceOver è stato rimosso dall’utente durante la sessione («ferma voice over, non mi interessa»), quindi non costituisce un blocco.

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

## Condizioni residue

Correggere e riprovare V-01; ottenere una prova osservata a 900×600 con contenuti lunghi, azioni inferiori e sheet. Questo verbale parziale non autorizza il gate di consegna né l’avvio del Task 4. Nessun test RED/GREEN applicabile in questa sessione, poiché non sono state apportate correzioni al codice.
