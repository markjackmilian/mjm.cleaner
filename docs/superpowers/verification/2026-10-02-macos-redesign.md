# Verifica finale — redesign macOS di mjm.cleaner

Data: 2026-10-02 · Branch `feat/macos-redesign` · HEAD di partenza `2fd1917`
Riferimenti: [spec](../specs/2026-10-02-macos-redesign-design.md), handoff UI (§7 criteri di accettazione), canvas «mjm.cleaner — macOS» (board `Main`, `Docker`, `Storico`, `Impostazioni`).

## Ambito

Verifica dei criteri di accettazione del §7 dell'handoff dopo le modifiche di T1–T7: sidebar al posto delle schede, toolbar e barre azioni, token colore chiaro/scuro, finestra Impostazioni modale con scelta dell'Aspetto, Storico con nomi leggibili e date localizzate, restyling delle pagine Docker e Xcode. Nessun codice applicativo è modificato da questo task: contiene solo evidenza.

## Come è stata prodotta l'evidenza

- **Build e test**: comandi eseguiti alla radice del repository (sezione seguente).
- **Screenshot dell'app reale** (non headless): catturati dal controller con `screencapture -x -o -l <windowid>`, quindi **solo la finestra di mjm.cleaner** (nessun desktop, nessuna altra app). PNG Retina 2x: finestra principale 1120×700 pt (2240×1400 px), finestra Impostazioni 700×820 pt (1400×1640 px). Ogni immagine è stata riesaminata prima di essere copiata: tutte mostrano esclusivamente la finestra dell'app.
- **Screenshot headless (Step 3 del brief)**: non necessari, perché la cattura delle finestre reali è stata possibile; nessun progetto di cattura headless è stato usato.
- **Isolamento dei dati**: l'app è stata avviata con `HOME` puntato a una home finta in scratch (due copie, con `Appearance` = `Light` e `Dark` in `settings.json`), così le impostazioni reali dell'utente non sono mai state toccate; confronto con il backup dopo ogni esecuzione sulla home reale: identico. Il database dello Storico è una copia di quello reale (1 sessione reale).
- **Flusso reale su dati fittizi**: nella home finta un progetto demo (`demo-projects/Demo.Api/Demo.Api.csproj` con `bin`/`obj` fittizi); selezionata solo «Cartelle bin e obj nei progetti». Eseguito Scegli → Analizza → Conferma → Elimina → Fatto: la cancellazione è rimasta confinata alla scratch (verificato che le cartelle siano sparite). Per questo lo Storico mostra anche la nuova sessione «2 ott 2026, 16:30 · 4,3 MB · Cartelle bin e obj nei progetti · 2» sopra quella reale «26 set 2026, 01:19 · 9,5 GB · Cache utente e di sistema · 2.117» (intestazione «9,5 GB in 2 pulizie»).
- **Interazione**: navigazione con veri clic del mouse (CGEvent) sulla sidebar; Impostazioni aperte con il vero ⌘, (keystroke via System Events) e chiuse con Esc (Annulla); menu applicazione letto via System Events: «Impostazioni…, Services, Hide mjm.cleaner, Hide Others, Show All, Quit».
- **Docker** non era in esecuzione: lo screenshot mostra lo stato «Motore non raggiungibile». **Xcode** mostra l'inventario reale dei simulatori (analisi in sola lettura, nessuna pulizia eseguita).
- Un'esecuzione precedente sulla home reale in modalità Automatico con macOS in Scuro ha reso l'app scura (l'Automatico segue il sistema all'avvio).

## Build e test

| Comando | Esito |
|---|---|
| `export PATH="/usr/local/share/dotnet:$PATH"; dotnet build` e `dotnet build --no-incremental` (radice del repo) | exit 0 — `Build succeeded. 0 Warning(s), 0 Error(s).` — 0 avvisi nuovi |
| `dotnet test` (radice del repo) | exit 0 — `MjmCleaner.Core.Tests`: 502 superati, 0 falliti, 0 saltati · `MjmCleaner.App.Tests`: 93 superati, 0 falliti, 0 saltati · **totale 595 superati** |

(L'ultimo riferimento registrato, `2026-10-02-xcode-cleanup.md`, era 499 Core + 19 App; i totali odierni includono anche i test del redesign e delle modifiche al catalogo successive.)

## Screenshot

Tutti in `2026-10-02-macos-redesign/`. Nota: le sessioni dello Storico nei due temi provengono da due esecuzioni distinte (orario 16:30 in chiaro, 16:31 in scuro); in `06-xcode-light` la finestra non era in primo piano (semafori grigi), il contenuto è invariato.

| Schermata | Chiaro | Scuro |
|---|---|---|
| 1. Scegli (Pulizia, passo 1) | [01-scegli-light](2026-10-02-macos-redesign/01-scegli-light.png) | [01-scegli-dark](2026-10-02-macos-redesign/01-scegli-dark.png) |
| 2. Analizza (passo 2) | [02-analizza-light](2026-10-02-macos-redesign/02-analizza-light.png) | [02-analizza-dark](2026-10-02-macos-redesign/02-analizza-dark.png) |
| 3. Conferma (passo 3) | [03-conferma-light](2026-10-02-macos-redesign/03-conferma-light.png) | [03-conferma-dark](2026-10-02-macos-redesign/03-conferma-dark.png) |
| 4. Fatto (passo 4) | [04-fatto-light](2026-10-02-macos-redesign/04-fatto-light.png) | [04-fatto-dark](2026-10-02-macos-redesign/04-fatto-dark.png) |
| 5. Docker (motore non raggiungibile) | [05-docker-light](2026-10-02-macos-redesign/05-docker-light.png) | [05-docker-dark](2026-10-02-macos-redesign/05-docker-dark.png) |
| 6. Xcode | [06-xcode-light](2026-10-02-macos-redesign/06-xcode-light.png) | [06-xcode-dark](2026-10-02-macos-redesign/06-xcode-dark.png) |
| 7. Storico | [07-storico-light](2026-10-02-macos-redesign/07-storico-light.png) | [07-storico-dark](2026-10-02-macos-redesign/07-storico-dark.png) |
| 8. Impostazioni (Aspetto, Progetti .NET, File grandi) | [08-impostazioni-light](2026-10-02-macos-redesign/08-impostazioni-light.png) | [08-impostazioni-dark](2026-10-02-macos-redesign/08-impostazioni-dark.png) |
| 9. Impostazioni (Età minima, scorsa fino in fondo) | [09-impostazioni-eta-light](2026-10-02-macos-redesign/09-impostazioni-eta-light.png) | [09-impostazioni-eta-dark](2026-10-02-macos-redesign/09-impostazioni-eta-dark.png) |

Il percorso visibile in Progetti .NET in 08/09 è il progetto demo della HOME finta, in una cartella scratch (non un percorso reale dell'utente).

In `08-impostazioni-light` è selezionato «Chiaro» e in `08-impostazioni-dark` «Scuro» (sono le home finte con quella preferenza); l'anello d'accento è visibile sul riquadro scelto, non tagliato.

## Confronto con il canvas

Misure e colori sono stati confrontati dal controller sulle schermate reali contro i board; le differenze non di scelta sono state corrette nei task precedenti (commit `fix(ui)` fino a `2fd1917`). Nessuna differenza di misura o colore residua.

### Main / Scegli

Corrispondono: sidebar 232 pt con sezione «mjm.cleaner», voce selezionata, riquadro «Spazio liberato», «Impostazioni…» con ⌘, in fondo; toolbar 52 pt con titolo «Pulizia» e «Passo 1 di 4» a sinistra e indicatore dei passi a destra (cerchio pieno sul passo corrente); titolo di pagina e sottotitolo; lista raggruppata con tile colorati 28×28, pill di rischio (basso/medio/alto), riga NuGet indentata con separatore più profondo; barra azioni 56 pt con «L'analisi non elimina alcun file.», conteggio «1 categoria selezionata» e pulsante primario «Analizza». Le schermate Analizza/Conferma/Fatto seguono la stessa cornice (card di avanzamento, gruppo espandibile con percorsi e dimensioni, banner di avviso «Eliminazione definitiva…», pulsante distruttivo «Elimina 4,3 MB · 2 elementi», conferma con tick verde e «Nuova pulizia»); il canvas `Main` copre il passo Scegli, gli altri passi sono verificati rispetto ai token e alle stesse misure.

Differenze documentate (decisioni della spec):
- La sidebar ha anche la voce **Xcode** (non nel canvas, che mostra Pulizia · Docker · Storico): la pagina Xcode esisteva già come scheda e, senza «Chiudi», va raggiunta dalla sidebar.
- Niente vibrancy: sidebar a colore pieno (`side`), non traslucida.

### Docker

Corrispondono: toolbar «Pulizia Docker» con sottotitolo «Anteprima: nulla viene eliminato finché non premi «Elimina».», pill «Motore non raggiungibile» a destra, stato vuoto centrato (tile 72, messaggio, pulsante «Riprova»), assenza di «Chiudi».

Differenza documentata: il messaggio dello stato vuoto («Docker non è in esecuzione. Avvia Docker Desktop e premi Riprova.») è l'unica frase prodotta da Core, invece del titolo + descrizione su due livelli del canvas (decisione della spec). Lo stato con dati (gruppi immagini/volumi da eliminare) **non è coperto né da uno screenshot né da un test di layout con dati**: Docker Desktop non era in esecuzione e `ToolPagesLayoutTests.DockerViewsHaveNoCloseButton` costruisce le view senza `DataContext`, verificando solo toolbar e assenza di «Chiudi», senza renderizzare dati.

### Storico

Corrispondono: toolbar «Storico delle pulizie» con sottotitolo e totale «9,5 GB in 2 pulizie»; tabella con intestazione (Data con indicatore discendente · Spazio a destra in grassetto · Categorie come chip · Elementi a destra con separatore delle migliaia), righe alterne che proseguono fino al fondo della finestra, date «26 set 2026, 01:19», nome leggibile «Cache utente e di sistema».

Differenza: il canvas mostra una sola sessione («in 1 pulizia»); l'app ne mostra due perché il flusso reale su dati fittizi ne ha aggiunta una. Nessuna differenza di stile.

### Impostazioni

Corrispondono: finestra modale propria 700×820 con titolo «Impostazioni»; sezioni **Aspetto** (tre riquadri-anteprima Automatico/Chiaro/Scuro con anello sul selezionato e didascalia sotto la card) · **Progetti .NET** · **File grandi** · **Età minima**; didascalie sotto le card; liste cartelle con barra + / − e stato vuoto «Nessuna cartella. Premi + per aggiungerne una.»; stepper compatti con unità («MB», «giorni»); «Annulla» e «Salva» in basso a destra.

Differenza documentata: **Età minima ha tre righe** (Download · Log · Pacchetti NuGet), non quelle del board (decisione della spec: l'età dei pacchetti NuGet è un'impostazione esistente, con nota sull'euristica).

## Criteri di accettazione (§7 dell'handoff)

### 1. Nessun flusso, passo o azione aggiunto o rimosso — soddisfatto (con le eccezioni volute)

Confronto dei `Command` delle view tra `46870cd` (prima del redesign) e `HEAD`, ottenuto con `git show 46870cd:<view>` e `grep 'Command="{'`:

| View | Prima | Dopo |
|---|---|---|
| `ChooseStepView` | Analyze | Analyze |
| `ScanStepView` | BackToStart, Cancel | BackToStart, Cancel |
| `ConfirmStepView` | CancelDelete, Delete, Restart | CancelDelete, Delete, Restart |
| `DoneStepView` | NewCleanup | NewCleanup |
| `DockerView` | CancelDelete, **Close**, Delete, Retry | CancelDelete, Delete, Retry |
| `DockerReportView` | AnalyzeAgain, **Close** | AnalyzeAgain |
| `XcodeView` | BackToSelection, CancelDelete, **Close**, ConfirmDelete, Preview, Retry | BackToSelection, CancelDelete, ConfirmDelete, Preview, Retry |
| `XcodeReportView` | AnalyzeAgain, **Close** | AnalyzeAgain |
| `HistoryView` | **Close** | — |
| `MainWindow` (barra strumenti → sidebar) | ShowDocker, ShowXcode, ShowHistory, ShowSettings | ShowCleanup, ShowDocker, ShowXcode, ShowHistory, ShowSettings (anche come ⌘,) |
| `SettingsView` (pagina) → `SettingsWindow` | Cancel, Save (due `TextBox` multilinea per le cartelle) | Cancel, Save, AddProjectRoot, RemoveProjectRoot, AddLargeFileRoot, RemoveLargeFileRoot |

Differenze, tutte volute dalla spec:
- **Rimossi** i soli pulsanti «Chiudi» (5 view). I `CloseCommand` restano nei ViewModel (`DockerViewModel`, `DockerReportViewModel`, `XcodeViewModel`, `XcodeReportViewModel`, `HistoryViewModel`), ancora chiamabili e testabili; il ritorno al passo 1 è ora la voce **Pulizia** della sidebar (`ShowCleanupCommand` → `StartOver`, che prima era il «Chiudi»).
- **Impostazioni** passa da pagina a finestra modale (stessi Annulla/Salva, aperta da sidebar, menu e ⌘,).
- **Aggiunti** i comandi +/− per le liste cartelle di Impostazioni (selettore cartelle nativo al posto dei campi di testo a una riga per percorso): stessa impostazione, interfaccia diversa; salvataggio identico.
- Passi del flusso (Scegli → Analizza → Conferma → Fatto), azioni distruttive e blocco della navigazione durante l'eliminazione Xcode (`CanNavigateGlobally`/`IsXcodeBusy`) invariati; il flusso completo è stato anche eseguito per intero sull'app reale (screenshot 01–04).

### 2. La sidebar sostituisce le schede; nessun «Chiudi» — soddisfatto

- Test: `MainWindowLayoutTests.ShellHasSidebarAndNoCloseButtons`, `ToolPagesLayoutTests.XcodePageHasToolbarAndNoCloseButton`, `ToolPagesLayoutTests.DockerViewsHaveNoCloseButton`, `HistoryViewTests.HasToolbarAndNoCloseButton`, `MainWindowLayoutTests.WizardViewsHaveToolbarAndActionBar`, `SidebarSectionTests` (`WizardPagesBelongToCleanup`, `ReportsBelongToTheirTool`, `IsWizardPageOnlyForTheFourSteps`).
- Screenshot: sidebar con Pulizia · Docker · Xcode · Storico in tutte le schermate 01–07.

### 3. Impostazioni in finestra propria, ⌘, funzionante — soddisfatto

- Test: `SettingsOpeningTests` (`ShowSettingsCommandOpensTheModalSettingsWindow`, `WhileTheWindowIsOpenTheCommandIsDisabled`, `ClickingTheSidebarSettingsButtonOpensTheWindow`, `CommandCommaOpensTheWindow`, `TheApplicationMenuHasTheSettingsItemFromStartup`); `SettingsWindowTests.ShowsTheFourSectionsAndTheEmptyFolderState`.
- Prova manuale sull'app reale: ⌘, (keystroke reale) apre la finestra, Esc la chiude come Annulla; il menu applicazione contiene «Impostazioni…». Screenshot 08/09.

### 4. Token §2 applicati, chiaro e scuro — soddisfatto

- `src/MjmCleaner.App/Styles/MacTheme.axaml` verificato riga per riga contro la tabella §2: `win`, `side`, `content`, `group`, `text`, `text2`, `sep` (alpha 0x17 = .09), `border` (0x14 = .08), `hover` (0x07/0x09), `sel` (0x13/0x1A), `field`, `stripe` e le tre pill di rischio coincidono nei due temi; `accent` è #0A66D8 in entrambi. Unico scarto formale: `stripe` scuro, rgba(255,255,255,.03), è reso come tinta opaca equivalente (#313134) sul fondo `group`, per evitare sovrapposizioni di trasparenze nelle righe alternate.
- Test: `ThemeTests.ContentTokenFollowsVariant` (valori `ContentBrush` Light #F7F7F9 / Dark #1E1E20), `ThemeTests.IconGeometriesAreRegistered`, `ThemeTests.StepIndicatorMarksOnlyTheCurrentStep`, `ChooseStepTests.RiskPillTextNamesTheLevel`, `ChooseStepTests.TilesUseTheDesignColors`, `ExpanderThemeTests.ExpanderHeaderUsesGroupColour`, `ExpanderThemeTests.ExpanderStateBrushesAreOpaqueTokens` (file `ToolPagesLayoutTests.cs`). I test automatici non coprono ogni token: la copertura completa è la lettura del file sopra più gli screenshot 01–09 nei due temi.

### 5. Aspetto Automatico/Chiaro/Scuro funzionante e persistente — soddisfatto in parte: verificato all'avvio e per comportamento del framework; cambio dal vivo da provare a mano

- Funzionante e persistente — test: `ThemeTests.PreferenceMapsToThemeVariant`, `ThemeTests.ApplySetsApplicationVariant`; `SettingsViewModelTests` (`PickingAnAppearancePreviewsItImmediately`, `CancelRestoresTheLoadedAppearanceAndCloses`, `ClosingFromTheTitleBarBehavesLikeCancel`, `SavePersistsAppearanceAndFoldersThenReturnsToStart`); `SettingsWindowTests.ClosingTheWindowRestoresTheAppearance`; Core: `SettingsStoreTests` (`AppearanceDefaultsToAuto`, `LegacyFileWithoutAppearanceLoadsAsAuto`, `AppearanceRoundTripsAsReadableString`). L'app reale avviata con `Appearance` = `Light`/`Dark` nel `settings.json` ha reso il tema corretto all'avvio (screenshot 01–09: ogni coppia chiaro/scuro).
- **Automatico segue il sistema**: verificato **all'avvio** (esecuzione sulla home reale in Automatico con macOS in Scuro: app scura) e per **comportamento del framework** (`Auto` imposta `RequestedThemeVariant = Default`, che in Avalonia segue l'impostazione di piattaforma). **Il cambio dal vivo dell'Aspetto di sistema con l'app aperta non è stato eseguito**, perché avrebbe richiesto di modificare l'impostazione di sistema dell'utente: resta da provare a mano (`osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to not dark mode'`, poi ripristino).
- Verifica manuale per l'utente (cambio dal vivo): con l'app aperta in Automatico, aprire Impostazioni di Sistema → Aspetto e passare da Chiaro a Scuro e viceversa; la finestra dell'app deve cambiare tema senza riavvio.

### 6. Storico con nomi leggibili e date localizzate — soddisfatto

- Test: `HistoryTests.CategoriesShowReadableNames`, `HistoryTests.DateIsLocalisedItalian`, `HistoryTests.ItemsUseThousandsSeparator`, `HistoryViewTests` (`EmptyHistoryShowsOnlyNessunaPulizia`, `AmountIsVisibleWhenThereAreSessions`, `SortChevronIsNinePixelsWithAThinStroke`).
- Screenshot 07: «Cache utente e di sistema» e «Cartelle bin e obj nei progetti» al posto degli ID; date «2 ott 2026, 16:30» / «26 set 2026, 01:19»; «2.117» con separatore delle migliaia.

### 7. Screenshot di ogni schermata in chiaro e scuro confrontati col canvas — soddisfatto, con i limiti indicati sotto (Docker con dati)

- 18 screenshot dell'app reale (9 schermate × 2 temi) nella tabella sopra; confronto con i board nella sezione precedente; differenze solo per decisioni della spec.
- Limiti: lo stato **Docker con dati** (gruppi immagini/volumi) non è coperto né da screenshot né da un test di layout con dati (Docker Desktop non era in esecuzione; `DockerViewsHaveNoCloseButton` non renderizza dati). Le sezioni **Xcode** con voci selezionate/anteprima/conferma non sono state fotografate (la pulizia Xcode reale non va eseguita) ma sono coperte da `XcodeViewLayoutTests` (stati popolati e di conferma, anche con 100 dispositivi), `XcodeReportViewModelTests` e `XcodeViewModelTests`.

## Esito

Tutte le voci del §7 sono soddisfatte tranne il cambio dal vivo della voce 5 (da provare a mano). Altre riserve esplicite: Docker con dati non è coperto né da screenshot né da un test di layout con dati; gli stati Xcode in anteprima/conferma non sono fotografati ma sono coperti da `XcodeViewLayoutTests`.
