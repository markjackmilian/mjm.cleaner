# Redesign macOS della UI — design

Data: 2026-10-02 · Branch: `feat/macos-redesign`

Fonte: handoff «mjm.cleaner — UI handoff (redesign macOS)» e canvas
https://claude.ai/artifact/EDJZiBGXhMetgs7HjfyJCR (`project/Main`, `Docker`, `Storico`,
`Impostazioni.dc.html`). Questo documento fissa come l'handoff si applica all'app Avalonia
esistente e le decisioni prese dove l'handoff non basta.

## Obiettivo e vincoli

Portare l'app all'aspetto del canvas cambiando **solo** presentazione e navigazione.
Nessun flusso, passo o azione aggiunto o rimosso; nessuna modifica alla logica di Core
salvo la nuova preferenza `Appearance`. I testi funzionali restano invariati; i soli testi
nuovi sono quelli di presentazione previsti dal canvas (elencati sotto).

## Decisioni

| Tema | Decisione |
|---|---|
| Xcode | Non è nel canvas ma esiste: voce di sidebar «Xcode» fra Docker e Storico. |
| Dimensioni finestra | Iniziale 1120×700; minima 900×600 (non 1120×700, scomoda sui 13"). |
| Impostazioni | Finestra **modale** separata, 700 px, centrata sulla principale. Salva salva e torna al passo 1 (come oggi). Annulla o chiusura dalla titlebar non salvano e ripristinano l'aspetto precedente. |
| Liste cartelle | «+» apre il selettore cartelle nativo, «−» rimuove la selezionata (disabilitato senza selezione). I percorsi già salvati, anche con `~`, restano invariati. |
| Età minima | Restano i tre campi esistenti (Download, Log, Pacchetti NuGet) come righe del gruppo: il canvas ne mostra uno, ma ridurli cambierebbe la logica. |
| Docker non raggiungibile | Lo stato vuoto mostra il messaggio di Core così com'è (`DockerUnavailableException`), senza spezzarlo in titolo/corpo. |
| Navigazione «Pulizia» | Se la pagina corrente è un passo del wizard non fa nulla; altrimenti `StartOver()`. Docker/Xcode/Storico creano una pagina nuova, come i pulsanti di oggi. |
| Blocco navigazione | Invariato: la sidebar e ⌘, sono disabilitati solo mentre Xcode elimina (`IsXcodeBusy`). |
| Accento | Fisso `#0A66D8` in entrambi i temi, anche sui controlli Fluent. |
| Vibrancy sidebar | Non usata: colore pieno `side`, fedele al canvas e prevedibile in entrambi i temi. |
| `downloads-large` | Tile arancio `#E8833A` (categoria nata dopo il canvas); `trash` usa `#D2453A`. |

## Mappatura schermate

| Attuale | Redesign |
|---|---|
| `MainWindow`: toolbar con totale e pulsanti Docker/Xcode/Storico/Impostazioni | Titlebar unificata (traffic light sulla sidebar), sidebar 232: titolo app, Pulizia · Docker · Xcode · Storico, card «Spazio liberato», «Impostazioni… ⌘,». |
| `ChooseStepView` | Toolbar «Pulizia / Passo 1 di 4» + indicatore passi; titolo 22/700; lista raggruppata (checkbox · tile · titolo/descrizione · pill), riga intera cliccabile, NuGet figlia indentata; barra azioni con scudo, «L'analisi non elimina alcun file.», contatore, «Analizza ›» disabilitato a 0 selezioni. |
| `ScanStepView`, `ConfirmStepView`, `DoneStepView` | Stessa toolbar (passo 2/3/4), contenuto in card raggruppate, barra azioni 56 con i pulsanti esistenti. |
| `DockerView`, `DockerReportView` | Toolbar «Pulizia Docker» + sottotitolo; pill «Motore non raggiungibile» in errore; stato vuoto centrato (tile 72, messaggio, Riprova); barra azioni; niente «Chiudi». |
| `XcodeView`, `XcodeReportView` | Stesso schema di Docker; niente «Chiudi». |
| `HistoryView` | Toolbar «Storico delle pulizie» + totale «X in N pulizie»; tabella a righe alterne fino al fondo; colonne Data (indicatore discendente) · Spazio (bold, destra) · Categorie (chip con nome leggibile) · Elementi (destra, separatore migliaia); niente «Chiudi». |
| `SettingsView` (pagina) | `SettingsWindow` modale: Aspetto · Progetti .NET · File grandi · Età minima; Annulla/Salva in basso a destra. |

## Componenti

- **Token** in `Styles/MacTheme.axaml` come `ThemeDictionaries` Light/Dark con i valori del §2
  dell'handoff (`win`, `side`, `content`, `group`, `text`, `text2`, `sep`, `border`, `hover`,
  `sel`, `field`, `stripe`, `accent`, pill rischio). Colori di avviso/pericolo/successo in
  scuro derivati dalle pill (avviso `#FFB04D` su `rgba(255,159,10,.16)`, pericolo `#FF8A80`).
  Nessun colore letterale nelle view, salvo il bianco del testo su accento e i colori tile.
- **Stili condivisi**: `Border.Toolbar` (52, bordo inferiore `sep`), `Border.ActionBar`
  (56, bordo superiore), `Border.Group` (r10, contorno `border`), riga lista (padding 11×16,
  gap 12, separatori inset 72/116), `Border.RiskPill.Low|Medium|High`, `Border.CategoryTile`
  (28, r7), pulsanti alti 28 (primario, secondario, distruttivo), voce sidebar (30, r7).
- **`StepIndicator`**: controllo con `CurrentStep` (1–4), cerchio pieno sul passo corrente.
- **Tipografia**: font di sistema (SF Pro); titolo pagina 22/700, toolbar 15/700, riga 13/600,
  corpo 13, descrizione 11,5, didascalie 11.

## Aspetto

- Core: `enum AppearancePreference { Auto, Light, Dark }`, `CleanerSettings.Appearance`
  predefinito `Auto`, serializzato come stringa. File precedenti senza il campo → `Auto`.
- App: `Application.RequestedThemeVariant` = `Default` / `Light` / `Dark`, applicato
  all'avvio prima di mostrare la finestra (`App.axaml` non forza più `Light`). `Default`
  segue Impostazioni di Sistema in tempo reale.
- Finestra Impostazioni: tre riquadri-anteprima in radio group; la scelta si applica subito,
  Annulla/chiusura ripristinano il valore caricato, Salva lo rende persistente.

## Storico

- Nomi leggibili: catalogo corrente + `xcode-*` + `docker-*` + l'ID storico
  `trash-downloads-large` («Cestino, Download e file grandi»); ID sconosciuti mostrati così come sono.
- Data: `d MMM yyyy, HH:mm` in `it-IT` (coerente con `FormatBytes`), ora locale.
- Totale in toolbar: somma e conteggio delle sessioni caricate.

## Testi nuovi (solo presentazione)

«Passo N di 4», «N categorie selezionate» / «1 categoria selezionata» / «Nessuna categoria
selezionata», «Motore non raggiungibile», «X in N pulizie», «Nessuna cartella. Premi + per
aggiungerne una.», «Automatico segue l'aspetto scelto in Impostazioni di Sistema.», etichette
Aspetto (Automatico/Chiaro/Scuro), pill con iniziale maiuscola, colonna Elementi solo numerica.
La didascalia «una per riga» di Progetti .NET diventa «Cartelle di progetto in cui cercare bin e obj.»

## Accessibilità

Controlli reali; `AutomationProperties.Name` sui pulsanti solo-icona (+, −); focus visibile in
accento; contrasto ≥ 4.5:1; rischio comunicato anche dal testo della pill.

## Test e verifica

- Core (TDD): default e round-trip di `Appearance`, file legacy senza campo.
- App (headless): nessun pulsante «Chiudi»; sidebar seleziona la voce della pagina corrente;
  ⌘, / comando apre le Impostazioni; anteprima aspetto e ripristino su Annulla; Storico con
  nomi leggibili e data localizzata; Analizza disabilitato a 0 selezioni; layout: barra azioni
  sempre nel viewport con contenuti lunghi.
- Verifica finale: build, suite completa, screenshot di ogni schermata in chiaro e scuro
  confrontati con il canvas, checklist §7 dell'handoff voce per voce.

## Fuori scope

Nuove funzioni, ordinamento interattivo della tabella, vibrancy, modifiche ai flussi di
Docker/Xcode, refactoring non legati alla presentazione.
