# Porting Swift — collaudo, release e passaggio di consegne

Data: 2026-10-16. Integra la spec `2026-10-13-swift-native-port-design.md` §§9.4 e 10.1–10.3. Il C# resta il riferimento eseguibile fino al gate di collaudo; i documenti storici sotto `docs/superpowers/` restano nel repository.

## Scelta di sequenza

Tre sequenze considerate:

1. **Collaudo, poi consegna atomica (scelta).** Preparare un candidato Swift, confrontarlo con il C# ancora disponibile, quindi rimuovere il C# e spostare Swift alla radice in un commit dedicato. Il difetto nel confronto non resta nascosto da un albero già riorganizzato.
2. Workflow Swift temporaneo in parallelo a quello C#. Darebbe una prova CI anticipata, ma duplicherebbe i trigger e richiederebbe una regola transitoria per i tag.
3. Spostare Swift e rimuovere C# prima del confronto. Semplificherebbe l'albero finale, ma renderebbe più difficile riprodurre il riferimento e invertirebbe la condizione di §10.3.

La scelta 1 ha due gate. Preparazione, build e confronto non autorizzano una pubblicazione GitHub. Il passaggio di consegne si fa solo quando le prove del gate sono registrate. Il workflow corrente `.github/workflows/release-macos.yml` usa ancora .NET ed è `disabled_manually` su GitHub (API Actions, verificato il 2026-10-16); la frase «resta attivo» in §10.2 descriveva l'intenzione originale ed è superata da questo stato osservato. Aggiornare il YAML non riattiva da solo il workflow remoto.

## Identità e build candidata

- Debug Swift: bundle ID `com.mjm.cleaner.debug`, così defaults, Application Support e autorizzazioni TCC sono distinti dal C# (`com.mjm.cleaner`). `AppStartup` passa `Bundle.main.bundleIdentifier` a `AppEnvironment.defaultPaths`; il collaudo verifica l'effettiva directory. Nessuna migrazione dei dati dell'utente. Release Swift conserva `com.mjm.cleaner` nella fase 1.
- `Debug.xcconfig` mantiene `ONLY_ACTIVE_ARCH = YES`; `Release.xcconfig` mantiene `NO`. La presenza del valore non basta: il candidato Release deve contenere entrambe le slice `arm64` e `x86_64`, verificate con `lipo -archs`.
- Target, schema ed eseguibile restano `MjmCleaner`; la copia da distribuire si chiama `mjm.cleaner.app` come il bundle C#. Dopo aver rinominato il contenitore esterno si riverificano firma e risorse. `CFBundleName` e `CFBundleDisplayName` restano `mjm.cleaner`.
- Versione/tag: solo `vMAJOR.MINOR.PATCH`; `MARKETING_VERSION` riceve la versione senza `v`; `CURRENT_PROJECT_VERSION` è un intero positivo. Input invalidi fermano il job prima della build.
- Una sola build Release universale, firma ad hoc, un solo ZIP `mjm.cleaner-<tag>-macos-universal.zip`. Lo ZIP viene estratto in una directory nuova e verificato di nuovo: architetture, plist, firma e assenza degli ingressi/testi della demo Debug. Nessuna notarizzazione o identità Developer Program in fase 1.
- Per CI si usa un runner con Xcode 27, il major usato dal progetto locale. L'immagine e `xcodebuild -version` sono registrati dal job; se l'immagine non offre quel major, il job fallisce in modo esplicito. Il job test esegue `swift test -Xswiftc -warnings-as-errors` e una build Debug; il package job produce e verifica lo ZIP; il release job pubblica solo un tag esistente dopo package verde. Un asset omonimo già presente fa fallire il job: non si usa `--clobber` per sostituire in silenzio una release precedente. Lo stato remoto disabilitato resta tale fino a una decisione distinta.

## Collaudo prima della rimozione

- Due build in directory temporanee distinte, avviate per percorso assoluto, mai tramite bundle ID. Nessun input verso i pulsanti di conferma della cancellazione. La prova reale copre solo Scegli → Analizza → Conferma, Docker e Xcode fino all'anteprima.
- Stessa selezione e stesse impostazioni per C# e Swift. Per ogni categoria: numero di elementi, byte ed esclusioni con motivo. Per Docker: ID, esito KEEP/DELETE/PROPOSE/ASK, ragione e dimensione. Per Xcode: identificatore, dimensione, disponibilità e blocchi. Una differenza stabile si ripete C# → Swift → C#; si accettano solo variazione naturale documentata e la divergenza APFS della §12.
- Gli screenshot Swift del piano 4b si confrontano con quelli del redesign, in chiaro e in scuro. La verifica manuale copre viewport, contenuto lungo, gruppi Docker sotto la piega e accessibilità delle azioni. VoiceOver copre sidebar, passi, selezioni, campi, disclosure, tabelle, fogli e ritorno del fuoco. I risultati osservati, compresi difetti e differenze accettate, entrano in un verbale con commit, configurazioni e orari.
- L'interazione con le app sul Mac avviene in una finestra concordata con l'utente: catture e controllo UI possono spostare il fuoco e interferire con tastiera e mouse. L'analisi del codice, le build e il packaging proseguono indipendentemente da tale finestra.

## Gate di consegna

Prima del commit di rimozione: registro di parità completo; 536 test Core + 172 Features verdi o conteggi aggiornati per test aggiunti; build Debug e Release senza diagnostica; ZIP verificato e ricostruito dopo ogni correzione, con SHA dell'albero `swift/` uguale al codice collaudato e SHA-256 registrato; screenshot e VoiceOver registrati; confronto reale superato o differenze giudicate e corrette. Un difetto Critical/Important aperto ferma la consegna.

Superato il gate, in un commit esplicito sul branch di lavoro:

1. Rimuovere `src/`, `tests/`, `build/`, `Directory.Build.props` e `mjm.cleaner.slnx` come prescrive §10.3, dopo inventario dei riferimenti .NET residui. Non rimuovere risorse necessarie a Swift. Non toccare le modifiche locali dell'utente nel checkout `main`.
2. Spostare il contenuto di `swift/` alla radice preservando storia e riferimenti relativi; aggiornare `.gitignore`, README e workflow ai percorsi finali. I documenti storici mantengono i loro percorsi storici.
3. Da un checkout pulito, rieseguire suite, build Debug/Release, confezionamento/estrazione e controlli di firma. La prova pulita deve evitare che `.build` o DerivedData precedenti nascondano dipendenze dal vecchio layout.

Il merge su `main`, la riattivazione del workflow GitHub, la creazione di un tag e la pubblicazione della release sono azioni distinte. Si presentano con gli artefatti e gli esiti del gate, senza eseguirle implicitamente.
