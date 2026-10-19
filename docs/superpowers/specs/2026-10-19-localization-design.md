# Localizzazione — inglese, italiano, tedesco, spagnolo

Data: 2026-10-19. Emenda la spec `2026-10-13-swift-native-port-design.md` nella riga «Lingua» della tabella delle decisioni (§2) e in §6.5 «Testi e formati». Il comportamento dell'app non cambia: cambiano la lingua dei testi e il formato di numeri e date.

## Decisioni

| Decisione | Scelta | Motivazione |
|---|---|---|
| Lingue | Inglese, italiano, tedesco, spagnolo | Richiesta dell'utente |
| Scelta della lingua | Segue macOS: lingue preferite del sistema o lingua della sola app (Impostazioni di Sistema → Generali → Lingua e Zona → Applicazioni) | Comportamento standard del Mac, nessun codice di selezione |
| Lingua di ripiego | Inglese | Release pubblica: chi non ha nessuna delle quattro lingue fra le preferite vede l'inglese |
| Lingua sorgente dei cataloghi | Inglese (approccio B) | Vedi «Approcci» |
| Numeri, dimensioni, date | Formato di zona di macOS (`Locale.autoupdatingCurrent`), come il Finder | Coerente con la scelta della lingua; i test iniettano un locale fisso |
| Revisione delle traduzioni | Solo i controlli automatici di §4, nessuna revisione madrelingua | Scelta dell'utente |
| Perimetro aggiuntivo | Dati della demo, screenshot per lingua, README, testo della release | Scelta dell'utente |

## Approcci

1. **Sorgente inglese (scelta).** Le chiavi del codice passano in inglese; italiano, tedesco e spagnolo sono traduzioni. È la configurazione standard: il ripiego inglese è naturale e Xcode resta allineato senza voci artificiali.
2. Chiavi italiane con ripiego inglese. Scartata: il compilatore dei cataloghi non genera il `.lproj` della lingua sorgente, quindi servirebbe una copia `it` di ogni chiave mantenuta a mano. In più i test andrebbero riscritti comunque in inglese (vedi «Fatti misurati», punto 4): la configurazione sarebbe anomala senza risparmiare lavoro.
3. Chiavi semantiche (`"cleanup.confirm.banner"` con `defaultValue:`). Scartata: la più pesante, e poco idiomatica con i letterali SwiftUI.

## Fatti misurati

Sonda usa e getta del 2026-10-19 (Xcode 27.1, Swift 6.4, macOS 27), nello scratchpad della sessione, con un package minimo e una copia del repository:

1. Con `sourceLanguage: "it"` né `swift build` né `xcodebuild` dell'app producono `it.lproj`: nascono solo i `.lproj` delle traduzioni. Con `sourceLanguage: "en"` e `defaultLocalization: "en"` SwiftPM produce anche `en.lproj`.
2. I bundle di risorse del package seguono la localizzazione scelta dal bundle principale dell'app, non le lingue preferite dell'utente prese da sole.
3. Con `CFBundleDevelopmentRegion = en`, sorgente inglese e traduzioni `it` e `de`, la lingua scelta è: `en-US, it-IT` → en; `it` → it; `fr` → en; `fr, it` → it; `fr, de` → de. Non serve `CFBundleLocalizations`.
4. Il runner di `swift test` (`…/usr/libexec/swift/pm`, nessuna localizzazione) vede sempre la lingua di sviluppo, con qualunque `AppleLanguages` e anche con `defaultLocalization: "it"`.
5. Il parametro `locale:` di `String(localized:bundle:locale:)` non cambia la lingua di ricerca. `LocalizedStringResource` con `locale` impostato sì: nel runner, `de` restituisce «Papierkorb».
6. Il Mac di sviluppo ha `AppleLanguages = (en-US, it-IT)`.

## 1. Lingue e configurazione

- Progetto Xcode: `developmentRegion = en`; `knownRegions = (en, it, de, es, Base)`.
- `Config/Info.plist`: `CFBundleDevelopmentRegion = en`.
- `MjmCleanerKit/Package.swift`: `defaultLocalization: "en"`.
- I tre `Localizable.xcstrings` (app, `CleanerCore`, `CleanerFeatures`) hanno `sourceLanguage: "en"`. Ogni chiave ha `it`, `de` ed `es` in stato `translated`.
- `Config/Base.xcconfig`: il commento «testi in italiano» diventa «testi in quattro lingue».
- Il nome dell'app («mjm.cleaner») non cambia. I menu standard di AppKit si traducono da soli nelle lingue dichiarate.

## 2. Migrazione dei testi

Perimetro: 177 chiamate `String(localized:)` in `CleanerCore`, 112 in `CleanerFeatures`, 3 nell'app, circa 67 letterali SwiftUI (`Text`, `Button`, `Toggle`, `Section`…) e 7 `LocalizedStringKey`. I conteggi sono di oggi: il piano li rifà sul codice.

- **Tabella unica.** `docs/superpowers/porting/2026-10-19-l10n-mapping.tsv`, con le colonne modulo, italiano attuale, chiave inglese, tedesco, spagnolo. Uno script una tantum, scritto nel piano e non committato, applica la tabella al codice sostituendo il letterale esatto e genera i tre cataloghi: chiave = inglese, `it` = italiano attuale, `de` ed `es` dalla tabella. Dopo la migrazione la fonte di verità sono i cataloghi; la tabella resta come prova della parità dell'italiano.
- **Segnaposto.** Le chiavi usano i segnaposto prodotti dall'interpolazione Swift (`%@`, `%lld`). Le traduzioni con più di un argomento usano i segnaposto posizionali (`%1$@`, `%2$@`…).
- **Frasi intere.** Le frasi composte da frammenti diventano frasi complete. Per esempio `"\(n) \(noun) dalle protezioni:"` con `noun` scelto da `Formatting.plural`. Singolare e plurale sono due chiavi, scelte in codice con `count == 1`: le quattro lingue hanno le stesse due forme. Niente variazioni plurali del catalogo; se un giorno si aggiunge una lingua con regole diverse, si passa a quelle. `Formatting.plural` sparisce.
- **Entrano nel catalogo** tutti i testi visibili, compresi i messaggi `InvalidConfiguration` di `PathGuard`, `DenyList` e `PathExpander`, oggi letterali fuori dal catalogo. Entrano anche gli errori del Core già scritti in inglese (`XcodeSelection` e simili): la chiave resta, la traduzione italiana è testo nuovo e non parità con il C#.
- **Restano fuori** le stringhe di confronto con l'output della CLI di Docker (`"Cannot connect to the Docker daemon"`, `"No such"`, `"Error response from daemon: "`), `NSLog` e il log di sessione.
- **Stile dell'inglese.** Convenzioni Apple (HIG): Title Case per pulsanti, voci di menu e titoli; frase normale per descrizioni, etichette e messaggi. Tedesco e spagnolo seguono le convenzioni macOS di ciascuna lingua.
- **Glossario.** I termini di sistema usano i nomi ufficiali di macOS in ogni lingua, perché l'utente deve ritrovarli nel sistema:

| Italiano | Inglese | Tedesco | Spagnolo |
|---|---|---|---|
| Impostazioni di Sistema | System Settings | Systemeinstellungen | Ajustes del Sistema |
| Privacy e sicurezza | Privacy & Security | Datenschutz & Sicherheit | Privacidad y seguridad |
| Accesso completo al disco | Full Disk Access | Festplattenvollzugriff | Acceso total al disco |
| Cestino | Trash | Papierkorb | Papelera |
| Download (cartella) | Downloads | Downloads | Descargas |

I nomi tecnici restano invariati in tutte le lingue: DerivedData, Device Support, Docker, Docker Desktop, Docker.raw, `docker system df`, NuGet, `bin`/`obj`, Xcode, Simulator.

- **Storico.** I nomi delle categorie si risolvono al momento della visualizzazione dall'id salvato (`CategoryNames`), quindi seguono la lingua corrente. Nessuna migrazione dei dati.

## 3. Numeri, dimensioni e date

- `AppEnvironment` riceve il campo `locale: Locale`: `Locale.autoupdatingCurrent` nell'app vera, un locale fisso nei test. I modelli di `CleanerFeatures` che formattano lo ricevono dall'ambiente o dal modello genitore.
- Ogni funzione di `Formatting` prende `locale:` senza valore predefinito, così nessun punto di chiamata ricade per sbaglio sul locale della macchina. Scartati `@TaskLocal` e una variabile globale: sono dipendenze nascoste e poco sicure con la concorrenza di Swift 6.
- `bytes`: base 1024, unità B/KB/MB/GB/TB uguali in tutte le lingue, al massimo un decimale, arrotondamento lontano dallo zero, nessun raggruppamento. Cambia solo il separatore decimale del locale: «1,3 KB» in it/de/es, «1.3 KB» in en_US.
- `integer`: `formatted(.number.locale(locale))` con le regole CLDR. Per esempio en_US «1,234», it_IT e de_DE «1.234», es_ES «1234»: CLDR non raggruppa le cifre sotto 10.000 in spagnolo.
- `historyDate`: `Date.FormatStyle(date: .abbreviated, time: .shortened)` con locale e fuso espliciti; rispetta anche le preferenze 12/24 ore dell'utente. Il formato fisso `d MMM yyyy, HH:mm` e la tabella dei mesi italiani spariscono. Resta la regola di oggi: timestamp salvati in UTC e mostrati in ora locale.
- `seconds`: invariata.
- Scostamento da §6.5 della spec del porting: lì si chiedeva «lo stesso testo su ogni macchina». Ora il testo segue la zona dell'utente, e il determinismo resta nei test grazie al locale iniettato.

## 4. Test e verifica

- **Suite esistenti.** Le attese testuali passano dall'italiano all'inglese, perché il runner vede sempre la lingua sorgente (fatto 4): il risultato è identico sulla CI e su qualunque Mac. I test dei modelli usano un `AppEnvironment` con locale `en_US`. Dei test esistenti (536 Core + 173 Features alla data), ognuno resta o viene sostituito da uno equivalente. Spariscono solo i test di `Formatting.plural`, insieme alla funzione, e la sostituzione va annotata nel registro delle decisioni.
- **`LocalizationCatalogTests`.** Legge i tre cataloghi dal repository via `#filePath`, come le fixture JSON. Per ogni catalogo controlla:
  1. `sourceLanguage` = `en`;
  2. ogni chiave ha `it`, `de` ed `es` in stato `translated`, con valore non vuoto;
  3. ogni traduzione ha gli stessi segnaposto della chiave, a meno della numerazione posizionale;
  4. nessuna chiave in stato di estrazione `stale`;
  5. il glossario di §2: se la chiave contiene un termine del glossario, la traduzione contiene il termine corrispondente.
- **Controlli puntuali per lingua.** In `CleanerCoreTests` e `CleanerFeaturesTests`, alcune chiavi (fra cui una con tre argomenti) si risolvono con `LocalizedStringResource` e `locale` it, de ed es (fatto 5). Si verifica così che il bundle compilato contenga le tre lingue e che l'ordine degli argomenti sia giusto.
- **Codice e cataloghi allineati.** `Scripts/check-strings.sh` gira dopo un `xcodebuild` e confronta le chiavi estratte dal compilatore (file `.stringsdata`) con quelle di ogni catalogo. Fallisce per una chiave nel codice assente dal catalogo, che apparirebbe in inglese in ogni lingua, e per una chiave del catalogo assente dal codice. Ha il suo `Scripts/check-strings.test.sh`, come gli altri script, ed entra nel job di test del workflow dopo «Build Debug». Il piano verifica per prima cosa che `xcodebuild` estragga anche le stringhe dei moduli del package; altrimenti usa `swift build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path <dir>`.
- **Parità dell'italiano.** Passo di verifica del piano, non test permanente: per ogni riga della tabella, la traduzione `it` della chiave inglese coincide con l'italiano attuale.
- **Mutazioni.** I revisori, in una copia scratch, tolgono una traduzione `de`, scambiano un segnaposto e lasciano un letterale fuori dal catalogo: ciascuna mutazione deve far fallire un controllo.
- **Screenshot per lingua.** `Scripts/screenshots.sh --lang <en|it|de|es>` passa alla demo `-AppleLanguages (xx)` e `-AppleLocale` con la zona corrispondente (`en_US`, `it_IT`, `de_DE`, `es_ES`). Si fa un giro di tutte le pagine a `--size 900x600` (finestra minima reale 900×652) per ciascuna lingua, catturato solo quando l'utente lo concorda. Si cercano troncamenti e sovrapposizioni, soprattutto in tedesco; le correzioni di layout entrano nel registro delle decisioni.
- **Controllo manuale dell'utente.** Una volta, a fine lavoro: in Impostazioni di Sistema → Generali → Lingua e Zona → Applicazioni, l'app offre le quattro lingue e il cambio ha effetto al riavvio. Niente input sintetico.

## 5. Demo, README, release

- **Demo.** I testi finti di `MjmCleaner/Demo/DemoData.swift`, come i motivi Docker e le etichette, passano dal catalogo dell'app, così ogni giro di screenshot è tutto in una lingua. I percorsi finti restano fissi e neutri (`~/Projects/shop`) e non si traducono. Il codice della demo resta solo Debug.
- **README.** È già in inglese. Si aggiunge una sezione *Languages*: le quattro lingue, il ripiego inglese e come scegliere la lingua per la sola app.
- **Release.** Il passo di pubblicazione del workflow aggiunge `--notes-file .github/release-notes-header.md`, un'intestazione breve in inglese (cos'è l'app, le lingue, macOS 15 o successivo). `gh` la antepone alle note di `--generate-notes`.

## 6. Esecuzione

- Branch `feat/l10n` da `main`; il piano si scrive con `writing-plans` e si esegue come i precedenti (preferenze nella memoria del progetto).
- All'inizio del lavoro, le modifiche locali di Xcode ai tre `Localizable.xcstrings` si salvano come patch nello scratchpad e si scartano: i cataloghi vengono rigenerati da zero. `.zed/` e `mjm-cleaner-ui-handoff.md` restano intatti e fuori dallo stage.
- Ordine dei task:
  1. configurazione e `LocalizationCatalogTests`;
  2. `Formatting` con locale;
  3. migrazione del Core;
  4. migrazione delle Features;
  5. migrazione dell'app e della demo;
  6. traduzioni `de` ed `es` con il glossario;
  7. `check-strings.sh` e workflow;
  8. README e testo della release;
  9. screenshot per lingua ed emendamenti alla spec del porting.
- **Rischi:**
  - testi tedeschi più lunghi alla finestra minima;
  - output ICU diverso fra versioni di macOS, che i test delle date evitano usando `FormatStyle` come oracolo;
  - Xcode che riscrive i cataloghi all'apertura del progetto: con cataloghi allineati deve toccare al più gli stati di estrazione, e `check-strings.sh` lo rileva.

## Fuori perimetro

Selettore della lingua nell'app; lingue oltre le quattro; variazioni plurali del catalogo; traduzione dei documenti in `docs/`; localizzazione di `CFBundleDisplayName`.

## Emendamenti alla spec del porting

Nel task 9 si aggiornano due punti di `2026-10-13-swift-native-port-design.md`, con un rimando a questa spec:

- §2, riga «Lingua»: «Inglese (sorgente), italiano, tedesco, spagnolo, in String Catalog; vedi `2026-10-19-localization-design.md`».
- §6.5: «La lingua di sviluppo è l'italiano; nessuna traduzione in fase 1», «cultura `it-IT`» e il formato fisso delle date sono superati dalle §§1–3 di questa spec.
