# Sezione Xcode: cache, Device Support e simulatori

## Obiettivo e ambito approvato

Recuperare spazio occupato dai dati di sviluppo Xcode con una pagina dedicata,
accessibile accanto a Docker. L'utente deve poter distinguere cache rigenerabili,
dati dei dispositivi simulati e runtime condivisi, selezionare le risorse e
confermare le conseguenze prima della cancellazione.

Gruppi inclusi: DerivedData, Device Support, dispositivi simulati, runtime
iOS/watchOS/tvOS/visionOS. Archives esclusi: contengono binari e simboli delle
release. Esclusi anche download/installazione di runtime, reset dei simulatori,
pulizia automatica, modifica di Xcode.app, credenziali e provisioning.

## Interfaccia e flusso

Il pulsante Xcode apre una pagina con analisi in sola lettura e quattro gruppi
espandibili. Ogni voce mostra nome, dimensione o «non disponibile», percorso o
identificativo, disponibilità, motivo di eventuale blocco e conseguenze della
rimozione. DerivedData viene mostrata per cartella di progetto; Device Support
per cartella di versione/build, indicando la piattaforma.

Tutte le voci partono deselezionate. Solo DerivedData e Device Support consentono
selezione di gruppo. Dispositivi e runtime richiedono selezione individuale.
Il totale distingue dimensioni note e voci non misurabili. Il pulsante di pulizia
apre un riepilogo finale con le risorse selezionate e le dipendenze coinvolte;
solo la conferma di questo riepilogo autorizza l'esecuzione.

Un dispositivo conserva app e dati di test: cancellarlo li elimina. Eliminare
un runtime può rendere indisponibili i dispositivi che lo usano, senza eliminare
automaticamente tali dispositivi. Il riepilogo elenca questi dispositivi e
richiede di riconoscere la conseguenza quando ne restano di non selezionati.
Non si deduce l'inutilizzo dall'età o dal numero di versione.

Dispositivi accesi e runtime usati da dispositivi accesi sono bloccati. L'utente
li arresta dagli strumenti Xcode e ripete l'analisi. Le cache e Device Support
non vengono cancellati con Xcode in esecuzione: la pagina chiede di chiuderlo
e ripetere l'analisi, senza chiudere applicazioni automaticamente.

## Architettura e inventario

Un modulo Core/Xcode separa inventario, classificazione, selezione, esecuzione
e misurazione. Un servizio coordina il flusso; pagina e report usano ViewModel
dedicati, seguendo le convenzioni della sezione Docker.

Il modello candidato contiene tipo, chiave stabile (percorso o UUID), nome,
dimensione nullable, stato, motivo del blocco e dipendenze. Gli inventari
incompleti producono avvisi per gruppo, mai un falso inventario vuoto riuscito.

DerivedData viene letta in ~/Library/Developer/Xcode/DerivedData. Device Support
viene letta nelle directory utente note di Xcode per iOS, watchOS, tvOS e
visionOS; percorsi assenti significano nessuna voce. Nessuna ricerca generica
in Library/Developer e nessuna cancellazione di SDK o cartelle di Xcode.app.
Le radici precise e il formato delle directory vengono verificati durante
l'implementazione con fixture e inventario locale, senza ampliare l'ambito.

La CLI usa l'Xcode selezionato dal sistema: xcrun simctl list --json per
dispositivi, runtime logici e associazioni; xcrun simctl runtime list --json
per gli identificativi delle immagini runtime rimovibili. Il collegamento usa
identificativi e build, mai solo il nome visualizzato. Associazioni ambigue
bloccano la rimozione del runtime. Runtime senza identificativo di rimozione
verificato sono visibili ma non selezionabili.

Il runner dei processi esistente può essere riutilizzato senza shell, con
argomenti separati, timeout e cancellazione. I nuovi servizi dipendono da
interfacce testabili; nessuna dipendenza dalle regole di classificazione Docker.

## Esecuzione e protezioni

Prima di ogni operazione si rivalidano identità, percorsi, stato di esecuzione
e dipendenze rispetto all'inventario confermato. Una risorsa cambiata viene
saltata e riportata: la nuova analisi non amplia mai la selezione approvata.

DerivedData e Device Support passano dal motore file esistente, con PathGuard,
controllo dei link e radici consentite specifiche del modulo. Simulatori e
runtime passano esclusivamente da comandi CLI per identificativo:

- xcrun simctl delete <device UUID>
- xcrun simctl runtime delete <runtime image UUID>

Nessun alias all/unavailable, nessuna rimozione ricorsiva diretta di CoreSimulator,
nessun sudo e nessun allargamento della deny-list per consentire i runtime.
Il blocco dei runtime in uso è necessario perché il comando runtime delete
può arrestare automaticamente i dispositivi avviati.

Se sono selezionati dispositivi e relativi runtime, vengono elaborati prima i
dispositivi. Dopo un errore su un dispositivo, un runtime dipendente selezionato
viene saltato per non applicare parzialmente il piano confermato. Le altre
risorse indipendenti possono proseguire. Annullare impedisce nuove operazioni;
quelle già completate rimangono nel report. Dopo timeout o annullamento di un
comando, una nuova lettura distingue risultato verificato ed esito incerto.

## Errori e compatibilità

Xcode assente, simctl mancante, servizio indisponibile, JSON incompatibile e
permessi insufficienti producono messaggi distinti e Riprova. Le cache restano
analizzabili se la CLI fallisce. Il supporto alla rimozione dei runtime viene
rilevato dalla CLI installata; quando manca, il gruppo spiega il limite e
rimanda a Xcode Settings per la gestione manuale.

## Spazio, report e cronologia

La scansione distingue spazio allocato e dimensione logica quando disponibili;
le immagini runtime sono misurate sul file di backing, non sui volumi montati.
Dimensioni sconosciute restano sconosciute e non valgono zero. I totali non
contano due volte percorsi o immagini condivise; i clone APFS rendono comunque
il totale una stima, esplicitamente etichettata.

Il report contiene risorse eliminate, saltate, fallite o con esito incerto,
motivi e stime relative solo a rimozioni verificate. La variazione dello spazio
libero del disco viene mostrata separatamente perché altri processi possono
influenzarla; non viene attribuita integralmente alla pulizia. Cronologia e
log riutilizzano i servizi esistenti. Il contatore cumulativo riceve solo una
stima conservativa dello spazio delle risorse eliminate e misurabili, secondo
le convenzioni della cronologia; valori incerti non incrementano il contatore.

## Integrazione e verifiche

DerivedData viene tolta dalle regole della pulizia generale e dalla relativa
descrizione. Archives rimane esclusa, preservando le modifiche locali già
presenti. La nuova pagina e il report vengono collegati a navigazione,
composizione dei servizi, template delle viste, cronologia e README.

Test mirati coprono parsing con campi mancanti, inventario parziale, mapping
runtime/immagini, selezione individuale, riconoscimento delle dipendenze,
blocchi delle risorse accese, rivalidazione, protezione dei percorsi e link,
argomenti CLI per UUID, errori parziali e contabilizzazione senza duplicati.
Le fixture includono inventari non vuoti: il Mac attuale non ne fornisce.
La verifica manuale controlla analisi e navigazione senza cancellare dati reali.
Si eseguono build e suite di test del progetto prima di dichiarare il lavoro
completo.

## Evidenze raccolte il 2026-10-02

Con accesso al sistema, xcode-select -p restituisce
/Applications/Xcode.app/Contents/Developer. Gli help locali confermano delete
per dispositivi, runtime list --json e runtime delete per identificativo.
Le due letture JSON sono riuscite ma hanno restituito dispositivi e runtime
vuoti: verificata la raggiungibilità della CLI, non la rimozione effettiva.

Riferimento Apple sulla distinzione tra runtime e dispositivi:
https://developer.apple.com/documentation/safari-developer-tools/adding-additional-simulators
