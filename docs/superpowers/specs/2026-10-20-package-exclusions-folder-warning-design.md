# Pacchetti fra le cartelle escluse, avviso per le categorie senza cartelle

## Obiettivo e ambito approvato

Due rifiniture emerse dalla revisione finale del branch `feat/large-files-exclusions`
(registro `2026-10-19-registro-decisioni-large-files-exclusions.md`, «Lavori successivi
proposti»):

1. **Un pacchetto non si può escludere.** Il pannello di `AppKitFolderPicker` ha
   `canChooseDirectories = true`, `canChooseFiles = false` e `treatsFilePackagesAsDirectories`
   al valore predefinito, falso. AppKit mostra quindi i pacchetti come file, e con
   `canChooseFiles = false` restano grigi. Per non vedere più una macchina virtuale in
   `~/Downloads` bisognerebbe escludere l'intera cartella dei Download.
2. **«File grandi» senza cartelle tace.** Con `largeFileRoots` vuoto la categoria non ha regole.
   Si può spuntare al passo 1, il passo 2 mostra «0 elementi» e il passo 3 scarta le categorie
   vuote. Nessun passo dice perché.

Verifiche del 2026-10-20, senza avviare l'app:

- **Sonda non interattiva** (`NSWorkspace.isFilePackage`, `URLResourceValues.isPackage` e
  `contentType`) su cartelle create in una cartella temporanea del Mac dell'utente:
  - `Windows 11.pvm` è un pacchetto (`com.parallels.vm.vmpackage`, conforme a `.package`,
    perché Parallels Desktop è installato), come `Prova.app` e `Sistema.logarchive`. Nel
    pannello di oggi **non si possono scegliere**.
  - `Linux.utm` e `Ubuntu.vmwarevm` risultano `public.folder`, perché UTM e VMware Fusion non
    sono installati. Per il pannello sono cartelle comuni e si scelgono già.
- **Scanner.** Un pacchetto fra le esclusioni funziona senza modifiche al Core:
  - in `scanFiles`, `excludedReason` sulle cartelle viene prima di `isPackage`, quindi il
    pacchetto si pota con «cartella esclusa nelle Impostazioni»;
  - `proposeWholeDirectory` e `scanContents` usano `candidateReason`;
  - un **file normale**, invece, in `scanFiles` non si confronta con le esclusioni.
- **«Cartelle bin e obj nei progetti».** Senza `projectRoots` si comporta come «File grandi».
  La selezione predefinita (`CleanerSettings.selectedCategoryIds`) la contiene già, quindi al
  primo avvio è spuntata e non produce nulla.

Decisioni dell'utente (2026-10-20):

- **Nel pannello delle esclusioni si scelgono cartelle e pacchetti**, non file singoli.
- **Il pacchetto si sceglie come unità** (`canChooseFiles` con `allowedContentTypes = [.package]`).
  Si scarta `treatsFilePackagesAsDirectories = true`, che aprirebbe un `.pvm` come una cartella
  e permetterebbe di escludere un pezzo interno che lo scanner non guarda mai.
- **L'avviso vale per entrambe le categorie** che prendono le cartelle dalle Impostazioni.
- **Al passo 1** la riga di una categoria senza cartelle è disattivata e deselezionata, con un
  avviso e il pulsante «Apri Impostazioni…».

Fuori ambito:

- file singoli fra le esclusioni;
- un pacchetto come cartella di progetto o come cartella dei file grandi;
- un avviso al passo 2 o al passo 3;
- conservare nella selezione ricordata una categoria non disponibile;
- una variante della demo con l'avviso;
- la canonicalizzazione delle esclusioni, affidata a un'altra sessione.

## Pannello delle esclusioni

- `FolderPicking.pickFolder(title:)` diventa `pickFolder(title:allowsPackages:)`. Nessun valore
  predefinito: ogni chiamante dichiara che cosa chiede.
- `SettingsModel` passa `allowsPackages: true` solo da `addExcludedFolder()`.
  `addProjectRoot()` e `addLargeFileRoot()` passano `false`. Il parametro attraversa
  `addFolder(to:title:)`.
- `AppKitFolderPicker`, con `allowsPackages` vero:
  - `canChooseFiles = true`;
  - `allowedContentTypes = [.package]`;
  - `treatsFilePackagesAsDirectories = false`, scritto per esteso.

  Un `.pvm`, un `.app` o un `.logarchive` si sceglie con un clic e resta chiuso; i file normali
  restano grigi; le cartelle si attraversano e si scelgono come oggi. Con `allowsPackages` falso
  il pannello resta quello di oggi.
- Il percorso restituito resta `url.path(percentEncoded: false)`. Una barra finale non conta,
  perché `ExcludedFolders` la toglie già.
- Il Core non cambia. Un pacchetto escluso compare al passo 3, nel riquadro delle esclusioni,
  con il motivo di oggi, «cartella esclusa nelle Impostazioni»: un pacchetto è una cartella.
- Testi:
  - titolo del pannello: «Scegli una cartella o un pacchetto da escludere» (prima «Scegli una
    cartella da escludere»);
  - didascalia della sezione: «Cartelle e pacchetti, come una macchina virtuale, mai analizzati
    né proposti in nessuna categoria della pulizia. Le pagine Xcode e Docker non li usano.»
    (prima «Non vengono mai analizzate né proposte, in nessuna categoria della pulizia. Le pagine
    Xcode e Docker non le usano.»);
  - il titolo «Cartelle escluse» e i testi di `FolderList` («Nessuna cartella. Premi + per
    aggiungerne una.», «Aggiungi cartella») restano invariati.

## Passo 1: categorie senza cartelle

- **Disponibilità.** Una categoria è disponibile se ha almeno una regola. Oggi solo
  `project-build-output` e `large-files` possono restare senza regole, perché le prendono da
  `projectRoots` e `largeFileRoots`; un test del catalogo lo fissa.
- **`CategoryChoice`:**
  - riceve `isAvailable: Bool` (`!category.rules.isEmpty`);
  - riceve `unavailableText: String`, cioè «Nessuna cartella da analizzare.» se non disponibile,
    altrimenti la stringa vuota.
- **Una categoria non disponibile non risulta mai selezionata.**
  - Parte deselezionata, anche se è nella selezione ricordata o se il chiamante passa
    `isSelected: true`.
  - Un'assegnazione `isSelected = true` si ignora nel modello, non solo nella vista.
  - Di conseguenza non entra in `selectedCount`, in `canAnalyze`, nell'analisi né nella
    selezione salvata da `analyze()`.
- **`ChooseStepModel.openSettings()`** chiama `navigation?.showSettings()`. `CleanupNavigating`
  riceve `func showSettings()`. `MainModel` la ha già, con questa firma e con la guardia
  `canShowSettings`. I tre doppi dei test che adottano il protocollo (`CleanupNavigationSpy`,
  `SnapshotNavigation`, `ProgressSnapshotNavigation`) la implementano; la spia registra
  `"settings"`.
- **Dopo le Impostazioni.** Salva chiama già `startOver()`, che ricrea il passo 1 da
  `environment.categories()`: con una cartella aggiunta la riga torna disponibile. Annulla non
  cambia nulla. Le spunte del passo 1 non ancora analizzate si perdono con Salva, come oggi
  con ⌘,.
- **Selezione ricordata.** Si riscrive solo con «Analizza», come oggi. Una categoria non
  disponibile ne esce quando si analizzano altre categorie; dopo aver aggiunto una cartella
  l'utente la rispunta. È una semplificazione voluta.
- **Primo avvio.** Senza cartelle di progetto, la riga «Cartelle bin e obj nei progetti» compare
  disattivata con l'avviso, e il contatore dice «3 categorie selezionate» invece di 4.
- **`ChoiceRow`:**
  - la casella è `.disabled(!choice.isAvailable)` e il tocco sulla riga non commuta;
  - sotto la descrizione compare una riga con l'icona `exclamationmark.triangle.fill` arancione,
    come in `Banner`, il testo di `unavailableText` e un pulsante-link «Apri Impostazioni…»
    (`.buttonStyle(.link)`) che chiama `model.openSettings`;
  - casella e riquadro della categoria si attenuano.

  Nome, descrizione e livello di rischio restano leggibili. VoiceOver legge la casella
  disattivata, l'avviso e il pulsante.

## Test

Swift Testing, scritti prima del codice.

- **Catalogo (Core):**
  - con `CleanerSettings()` le categorie senza regole sono esattamente `project-build-output` e
    `large-files`;
  - con una cartella in `projectRoots` e una in `largeFileRoots` nessuna categoria è senza
    regole.
- **Impostazioni (Features):**
  - `FakePicker` registra anche `allowsPackages`;
  - il «+» delle esclusioni chiede `allowsPackages: true` con il titolo nuovo;
  - i «+» dei progetti e dei file grandi chiedono `false`;
  - i test che oggi confrontano «Scegli una cartella da escludere» passano al titolo nuovo.
- **Passo 1 (Features):**
  - una categoria senza regole che è nella selezione ricordata parte deselezionata e non
    disponibile, con `unavailableText` non vuoto. Una categoria con regole ha
    `unavailableText` vuoto;
  - `isSelected = true` su una categoria non disponibile la lascia deselezionata; contatore e
    `canAnalyze` non cambiano;
  - `analyze()` non la passa all'analisi né la salva nella selezione;
  - con le cartelle configurate la stessa categoria è disponibile e si seleziona;
  - `openSettings()` registra `"settings"` nella spia.
- **`MainModel`:** `openSettings()` del passo 1 corrente apre lo sheet (`settings != nil`).
- **Test esistenti:** chi conta righe o selezioni del passo 1 con le impostazioni predefinite
  si adegua, perché `project-build-output` non risulta più selezionata senza cartelle di
  progetto.

Revisioni con mutazioni in una copia scratch, in particolare:

- la guardia di `isAvailable` tolta dall'`init` o dall'assegnazione;
- `allowsPackages` vero anche per progetti o file grandi, oppure falso per le esclusioni;
- `openSettings()` che non chiama la navigazione.

Una mutazione che sopravvive richiede un test nuovo. L'adattatore AppKit non ha test automatici:
si verifica con la build Debug e la lettura del codice. L'utente può provare il clic su un
`.pvm` nell'app; nessun agente manda input sintetico.

## Demo, documentazione e localizzazione

- **Demo.** `DemoServices` ha cartelle di progetto e dei file grandi, quindi la demo e gli
  screenshot non cambiano. Gli screenshot con `-MJMDemo` si catturano solo dopo averlo chiesto
  all'utente, e qui non servono.
- **README:**
  - il paragrafo sulle cartelle escluse aggiunge che si può escludere anche un singolo
    pacchetto, come una macchina virtuale;
  - l'elenco delle categorie dice che «Project bin and obj directories» e «Large files» restano
    non disponibili al passo 1 finché non si sceglie una cartella nelle Impostazioni.
- **Localizzazione.** Le frasi sono in italiano con `String(localized:)`. Il registro decisioni
  le elenca per la tabella del piano di localizzazione:
  - Features: «Scegli una cartella o un pacchetto da escludere» (sostituisce «Scegli una
    cartella da escludere»), «Nessuna cartella da analizzare.»;
  - app: «Apri Impostazioni…», la didascalia nuova della sezione (sostituisce quella di oggi).

  Nessun `Localizable.xcstrings` cambia.
- **Branch.** `feat/package-exclusions-folder-warning`, da `feat/large-files-exclusions`
  (273ed4e), da unire dopo di esso. Nessun push. A fine piano, il registro decisioni in
  `docs/superpowers/decisions/`.
- **Sovrapposizioni.** La sessione «Cartelle escluse: confronto nella grafia del disco» può
  toccare `SettingsModel.addFolder`: un conflitto al merge si risolve tenendo il parametro
  `allowsPackages` e la canonicalizzazione.
