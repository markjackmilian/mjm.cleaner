# Download completi e risultati raggruppati per cartella

## Scopo e decisioni

Il passo di conferma oggi mostra una riga per ciascun percorso, raggruppata solo per categoria. Una cartella con 200 file produce 200 righe consecutive. La categoria Download, inoltre, non è preselezionata: anche quando viene scelta, la regola propone solo file più vecchi di `downloadsMinAgeDays` (90 giorni per impostazione predefinita). L'utente vuole poter svuotare Download senza quel filtro e capire il risultato per cartella.

Decisioni approvate il 22 ottobre 2026:

- Aggiungere al passo 1 l'opzione **«Svuota Download»**. In questa modalità si ignora soltanto l'età minima. Restano valide le cartelle escluse nelle Impostazioni, la deny-list, la validazione dei percorsi e le altre protezioni dello scanner e del motore.
- Quando la modalità è attiva, le voci proponibili di Download partono tutte spuntate nel passo 3. L'utente può deselezionarle prima di eliminare.
- Nel passo 3 raggruppare i risultati per cartella, senza perdere le singole caselle e senza trasformare una cartella di raggruppamento in una nuova voce da cancellare.

La modalità è una scelta della singola analisi: si ricorda la categoria Download secondo il meccanismo esistente, ma non l'opzione «Svuota Download». Al prossimo passaggio dal passo 1, l'opzione è spenta; l'utente la riattiva esplicitamente. Questo evita di riproporre automaticamente una pulizia completa di dati reali.

## Approccio scelto

Il passo 1 produce una variante della sola categoria Download per l'analisi corrente. La sua regola `matchingFiles` conserva root, glob, esclusioni e gli altri limiti, ma non ha `minAge`; la sua proprietà `itemsSelectedByDefault` diventa vera. Le altre categorie e le impostazioni salvate restano quelle del catalogo.

L'alternativa di scansionare sempre tutti i Download e applicare il filtro di età nel passo 3 costerebbe più tempo nelle analisi ordinarie e richiederebbe di tenere in memoria risultati che non saranno mostrati. L'alternativa di cambiare temporaneamente `CleanerSettings.downloadsMinAgeDays` confonderebbe la scelta per questa analisi con una preferenza persistente.

## Passo 1 e analisi

- La riga Download conserva la propria casella di categoria. Sotto la descrizione compare una seconda casella, «Svuota Download (ignora il limite di età)», inizialmente spenta. Attivarla seleziona anche Download; spegnere Download spegne l'opzione. Spegnere solo l'opzione lascia Download selezionato e ripristina la normale soglia di età.
- La seconda casella è chiaramente distinta dalla casella della categoria e accessibile da tastiera e VoiceOver. Il tocco sulla seconda casella non attiva anche il gestore del tocco dell'intera riga.
- `ChooseStepModel.analyze()` passa alla navigazione una categoria Download modificata solo se entrambe le caselle sono attive. Il salvataggio di `selectedCategoryIds` continua a memorizzare soltanto gli ID delle categorie.
- `ScanStepModel` riceve già le categorie scelte, le passa allo scanner e poi al passo 3. Il passo 3 legge dalla categoria ricevuta lo stato iniziale delle voci. Non serve un nuovo campo persistente nelle impostazioni o un'opzione globale dello scanner.
- La scansione standard di Download continua a usare `downloadsMinAgeDays`. La modalità completa usa lo stesso `RuleScanner`, con il filtro di età assente. Pacchetti macOS restano voci indivisibili; i collegamenti simbolici e le directory versionate seguono le protezioni correnti. File illeggibili o negati non vengono inseriti nei risultati.

## Passo 3: gruppi per cartella

Dentro ogni categoria, le righe deduplicate da `ConfirmationRows.build` sono raggruppate per **cartella padre immediata** del loro percorso visualizzato. Una cartella padre con 200 file produce una riga di gruppo richiudibile con il proprio percorso, «200 elementi» e la dimensione complessiva, seguita dai file solo quando viene aperta. I file direttamente in `~/Downloads` formano il gruppo `~/Downloads`; quelli in `~/Downloads/Archivio` formano il gruppo `~/Downloads/Archivio`. I gruppi sono ordinati per percorso; le righe interne mantengono l'ordine di scansione.

- Ogni gruppo ha una casella «Seleziona tutte le voci di ‹cartella›». È spuntata se tutte le voci appaiono spuntate; in uno stato misto resta non spuntata e il riepilogo mostra quante voci sono spuntate. Attivarla seleziona le voci libere del gruppo, disattivarla le deseleziona. Se tutte le voci sono coperte da una cartella proposta e spuntata altrove, la casella del gruppo è disabilitata.
- I gruppi sono **solo presentazione e selezione collettiva**. La loro casella agisce sulle `PathNode` esistenti. Non crea una `ScanItem` per la cartella padre, non modifica `ConfirmationRows.selections` e non fa eliminare la cartella padre in quanto tale.
- Una cartella che è già una `ScanItem` cancellabile rimane una riga individuale nel gruppo della propria cartella padre. Continua ad avere la propria casella e la semantica di contenimento esistente. Un pacchetto macOS resta una sola riga.
- La casella di categoria e il totale «Elimina» continuano a derivare dalle stesse `PathNode`. Le voci coperte da una cartella cancellabile spuntata restano visibili, spuntate e bloccate. Il totale non conta due volte voci coperte.
- La categoria e ciascun gruppo si possono aprire e chiudere senza cambiare le selezioni. Il contenitore delle righe resta lazy per non costruire subito centinaia di viste SwiftUI. Nella categoria Download con «Svuota Download» attivo, gruppi e voci partono spuntati; nessun file viene eliminato prima del pulsante finale «Elimina».

## Errori e confini

- L'opzione «Svuota Download» non supera cartelle escluse, deny-list, protezione delle root, contenimento, rifiuto di percorsi non validi, errori di accesso o rivalidazione immediata prima dell'eliminazione.
- Se la root Download manca o non è leggibile, il risultato segue l'attuale comportamento dello scanner; non si crea un gruppo vuoto. Gli errori e le esclusioni rimangono nel flusso esistente.
- Se una categoria non produce righe, non compare nel passo 3, come oggi. Se nessuna voce è selezionata, «Elimina» rimane disabilitato.
- Fuori ambito: cambiare le preferenze globali di età; includere cartelle escluse dall'utente; aggiungere una cancellazione in blocco di `~/Downloads` come cartella; modificare le pagine Docker e Xcode; modificare la logica di cancellazione.

## Verifica

Test Swift Testing, scritti prima dell'implementazione:

- La categoria Download standard mantiene la soglia configurata e parte deselezionata; la variante «Svuota Download» non ha `minAge`, preserva esclusioni e altre proprietà della regola e parte selezionata. Nessuna altra categoria cambia.
- Attivare la modalità seleziona Download; spegnere la categoria spegne la modalità; spegnere la modalità mantiene la categoria e la sua regola standard. La modalità non viene salvata nelle impostazioni.
- Con un filesystem di prova contenente un file recente, uno vecchio, un pacchetto e una cartella esclusa, la scansione standard e quella completa producono rispettivamente i risultati attesi, senza superare l'esclusione.
- Le righe di due cartelle producono due gruppi con conteggi e dimensioni corretti; 200 file nella stessa cartella producono un solo gruppo con 200 righe espandibili. Le righe restano selezionabili singolarmente.
- Selezione di gruppo e di categoria, deselezione puntuale e voci coperte mantengono coerenti caselle, totale e `ConfirmationRows.selections`. Una casella di gruppo non introduce la cartella padre nell'input del motore.
- `swift test -Xswiftc -warnings-as-errors` in `MjmCleanerKit`, build dell'app e controllo manuale della vista in tema chiaro e scuro, compresi tastiera e VoiceOver.
