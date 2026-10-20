# Registro delle decisioni — passo 3: voci contenute in una cartella proposta altrove

Spec `docs/superpowers/specs/2026-10-20-confirmation-containment-design.md`, piano `docs/superpowers/plans/2026-10-20-confirmation-containment.md`, branch `feat/confirmation-containment` da `feat/large-files-exclusions` 273ed4e (non ancora unito a `main`). Esecuzione subagent-driven del 2026-10-20, nessun push.

## Sintesi

- **Chiude** il Minor 1 della revisione finale di `feat/large-files-exclusions`: una voce deselezionata in «File grandi» veniva cancellata se una cartella che la contiene era spuntata in un'altra categoria (con «File grandi» su `~`, il modello sotto `~/.cache/huggingface` proposta da «Cache di sviluppo»). L'avviso «Dati reali: le voci partono deselezionate» faceva credere il contrario. Spuntando sia la cartella sia il file, il totale contava due volte gli stessi byte e il motore registrava un ENOENT.
- **Decisioni dell'utente (brainstorming):**
  - approccio B, «annotare e legare»: la voce contenuta resta nel suo gruppo, segnata «Inclusa in …», spuntata e bloccata finché la cartella è spuntata. Scartati: A, assorbirla e toglierla dal passo 3; C, la cartella che parte deselezionata;
  - contenimento riconosciuto sulle root risolte come le cancellerà il motore. Scartati: il confronto solo testuale e una seconda difesa in `CleanEngine`;
  - nota sulla riga della cartella e riga di conteggio sotto l'avviso del gruppo.
- **Cosa cambia:**
  - `RootResolving`, a cui si conforma `PathGuard`; `AppEnvironment.roots` obbligatorio;
  - `ConfirmationRows.build(_:resolveRoot:)` deduplica su una chiave ripiegata come APFS (`folding(.caseInsensitive)`) sulla root risolta, e lega ogni riga alla riga-cartella più vicina (`ConfirmationRow.container`), in qualunque gruppo e ordine;
  - `ConfirmationRows.selections` è l'unico punto che decide che cosa riceve `CleanEngine`: una riga parte solo se è selezionata e nessuna cartella della sua catena lo è;
  - al passo 3: la casella di una voce coperta appare spuntata e bloccata, con la nota «Inclusa in …»; la cartella mostra «Contiene anche …»; «Seleziona tutte» cambia solo le voci libere; il totale di «Elimina» conta solo ciò che parte;
  - demo (`File grandi` su `~`, `~/.cache/huggingface` e un modello lì dentro) e README.
- **Scostamenti dal piano, decisi durante l'esecuzione** (dettaglio nelle righe «Ruling:» qui sotto):
  - fix del Task 2: quattro test in più (ogni voce inviata è selezionata, più voci sotto una root collegata, segmento che comincia con un segno combinante, posizione inesistente con la guardia di riga) e l'ordine delle righe; il Core passa da 707 a 710;
  - correzioni finali: il totale di «Elimina» asserito nel test esaustivo, un test delle note su catena e più gruppi, un test contro il ripiegamento di accenti e larghezze, i numeri della demo allineati, README e un commento; il Core passa a 711, Features a 241.
- **Verifica:** 711 test in 62 suite (Core) e 241 in 23 (Features), nessun warning con `-warnings-as-errors`; build Debug dell'app riuscita; nessun `Localizable.xcstrings` cambiato. Mutazioni: le 25 della stesura (24 uccise, M18 equivalente) più quelle dei revisori; le sopravvissute non equivalenti (O1, O2, O3, O4, O5, O6, O10, O12, OD, OW) hanno ora un test che le uccide. Restano equivalenti M18 (`canDelete`), O7 (gruppo vuoto) e O8 (`delete()` che legge `isChecked`).
- **Fuori ambito, rimasto aperto:**
  - una root che cambia destinazione fra l'apertura del passo 3 e «Elimina» (il motore rivalida comunque ogni percorso);
  - `selections` su una catena di `container` ciclica costruita a mano (`build` non la produce);
  - lo screenshot del passo 3 demo con la riga «Inclusa in …», da catturare solo con il consenso dell'utente.
- **Frasi nuove per la tabella del piano di localizzazione** (tutte in Features, `String(localized:, bundle: .module)`):
  - «Inclusa in \(percorso) (\(gruppo)): si elimina con la cartella.»
  - «Inclusa in \(percorso) (\(gruppo)).»
  - «Contiene anche \(numero) \(voce|voci) di \(gruppo).», con «voce» e «voci»
  - «1 voce è dentro una cartella spuntata e si elimina con quella.»
  - «\(numero) voci sono dentro cartelle spuntate e si eliminano con quelle.»
  - nessuna frase nuova nel Core né nell'app; il README guadagna una frase in inglese.
- **Ordine di merge:** il branch parte da `feat/large-files-exclusions`, che va unito a `main` prima di questo (o la PR va aperta verso quel branch). Chi aggiunge chiamate a `AppEnvironment(...)` in altri branch deve passare `roots:`.

## Registro SDD (copia del ledger)


Spec: docs/superpowers/specs/2026-10-20-confirmation-containment-design.md
Worktree: .claude/worktrees/vigorous-bouman-a475d2, branch feat/confirmation-containment, creato da feat/large-files-exclusions 273ed4e; spec db19a9b, piano b12292e.
Baseline: Core 681 test / 60 suite, Features 231 / 23.

Modelli (preferenze utente): implementatori haiku (codice completo nel brief), fix round al massimo sonnet; revisori sonnet per i Task 1 e 4, opus per i Task 2 e 3 e per la revisione finale. Mutazioni nelle revisioni dei Task 1, 2 e 3.

## Controllo preliminare

Il piano è già stato applicato meccanicamente, blocco per blocco, a una copia pulita del branch (scratchpad della sessione, tools/apply_plan.py): 23 blocchi applicati; RED attesi per T1–T3; GREEN Core/Features 685/232, 707/232, 707/240, 707/240; app BUILD SUCCEEDED dopo T1 e T4; risultato identico alla copia collaudata; xcstrings invariati. 25 mutazioni provate, 24 uccise, M18 equivalente.

| Coppia o task | Cosa produce / consuma | Esito |
|---|---|---|
| T1 → T2 | RootResolving e AppEnvironment.roots (T1) usati da ConfirmStepModel nella riga del T2; PathGuard.resolvedRoot usato da ConfirmationCleanupTests (T2) | coerente |
| T1 → T3 | FakeRootResolver e makeEnvironment(roots:) (T1) usati da containmentUsesTheRootsOfTheEnvironment (T3) | coerente |
| T1 → T4 | DemoServices.swift: T1 aggiunge DemoRoots e roots:, T4 cambia largeFileRoots (righe diverse) | il testo «old» di T4 non tocca le righe di T1 (verificato dallo script) |
| T2 → T3 | ConfirmStepModel.swift: T2 cambia la riga di build, T3 sostituisce l'intero file includendo quella riga; ConfirmationPosition/selections/rows (T2) usati da T3 | coerente |
| T3 → T4 | isChecked, isCovered, containmentText, containsText, coveredText, canSelectAll (T3) usati da ConfirmStepView (T4) | coerente |
| T1 | 4 test RootResolvingTests + 1 AppEnvironmentTests contro RootResolving.swift e AppEnvironment | coerente; RED: solo l'errore del Core (il build si ferma prima di Features), dichiarato nel brief |
| T2 | 24 test ConfirmationRowsTests (7 invariati nelle asserzioni) + 5 ConfirmationCleanupTests contro ConfirmationRows.swift | coerente |
| T3 | 8 test ConfirmStepModelTests + makeItem(directory:) contro ConfirmStepModel.swift | coerente |
| T4 | solo vista, demo, README; nessun test | coerente |
| Rubrica | test che non asseriscono nulla: nessuno. Duplicazione verbatim: la regola di copertura è scritta due volte (ConfirmationRows.selections nel Core, PathNode.isCovered in Features) — 6 righe ciascuna, su strutture diverse (posizioni contro nodi); il test esaustivo theTicksOnScreenMatchWhatIsDeleted lega le due | da segnalare se un revisore la solleva; vedi Ruling |

Ruling: la doppia formulazione della regola di copertura (Core su posizioni, Features su nodi osservabili) resta — la spec la chiede esplicitamente («È la stessa regola di selections») perché la vista deve osservare i nodi e il motore deve ricevere la selezione dal Core; il test esaustivo di Features confronta caselle e selezione inviata su 16 combinazioni — se sbagliato costa un refactor che faccia leggere a PathNode la regola del Core.

## Avanzamento
Task 1: implementer haiku a78cecf2e0d12f0ce, BASE b12292e
Task 1: commit 64f7f59 (685/232, app BUILD SUCCEEDED), DONE; file identici alla copia collaudata. Review sonnet abd3a0df55cc5ae46.
Task 1: review sonnet abd3a0df55cc5ae46: spec ✅, Approvato, M23/M24 + N1–N4 uccise; N5/N6 (doppi di test) sopravvivono senza consumatori nel Task 1. ⚠️ build app: confermata dal report dell'implementatore (BUILD SUCCEEDED) e dall'applicazione del piano in stesura.
Task 1: minor (deferred): aDeniedRootStillLeadsToItsTarget non asserisce che la root sia negata (precondizione su validateRoot); oggi N3 prova che il test distingue il ramo.
Task 1: minor (deferred): N5 (makeEnvironment scarta roots) e N6 (FakeRootResolver ignora targets) da verificare uccise nella revisione del Task 3 (containmentUsesTheRootsOfTheEnvironment).
Task 1: complete (commits b12292e..64f7f59, review clean)
Task 2: implementer haiku a00eb0b6c7ea5a0e9, BASE 64f7f59
Task 2: commit 35f7a8a (707/232), DONE; file identici alla copia collaudata; app non compilata dall'implementatore (non richiesta dal brief, verificata in stesura). Review opus acbb3fbea9164bd05.
Task 2: review opus acbb3fbea9164bd05: spec ✅ (trascrizione byte per byte), Da correggere: 4 Important sui test (O10 file non spuntato inviato, O1 memoria delle root, O2 risalita per Character, O12 guardia di riga), 2 Minor; M1–M10 uccise; O7 (=M20) atteso ucciso al Task 3.
Ruling: Important 1 e 4, marcati plan-mandated, si correggono nei test (asserzione «ogni voce inviata è selezionata» nel test esaustivo; predicato `$0.category == 0 && $0.row < 2`) — la spec dice «se e solo se» e chiede il test della posizione inesistente; il piano non lo traduceva in asserzioni — se sbagliato costa due righe di test.
Ruling: Important 2 e 3 entrano con due test nuovi (più voci sotto una root collegata con la cartella in seconda posizione; segmento che comincia con U+0301) — entrambi proteggono la direzione non sicura del contenimento — se sbagliato costa due test; Core da 707 a 710 con il Minor 1.
Ruling: il Minor 1 (ordine dei gruppi e delle righe in selections) entra nello stesso fix — la spec lo afferma, costa un test nello stesso file — se sbagliato costa un test.
Ruling: il Minor 2 (catena di container ciclica fabbricata a mano blocca selections) resta fuori dal fix e va alla revisione finale — build non produce cicli (il contenitore ha sempre meno «/»), servirebbe codice di produzione nuovo — se sbagliato resta un blocco possibile solo con righe costruite a mano.
Task 2: ⚠️ (revisore) il test esaustivo di Features asserisce anche «casella vuota → mai inviata»: verificato dal controller sul piano (theTicksOnScreenMatchWhatIsDeleted confronta deleted == isChecked per ogni riga).
Task 2: correzioni del fix round 1 verificate dal controller in una copia scratch (6 sostituzioni, 710/232) prima del dispatch.
Task 2: fix round 1 implementer haiku a00eb0b6c7ea5a0e9 (ripreso), commit 83df169 (710/232). Re-review sonnet a942923e976bc6b0c.
Task 2: fix round 1/5 (5 addressed, 0 open — O10, O1, O2, O12, O3 ora uccise; commits 35f7a8a..83df169)
Task 2: minor (deferred): selections non termina su una catena di container ciclica fabbricata a mano (build non la produce); isSelected chiamata prima di validare la posizione (la closure del Task 3 usa node(at:in:), che controlla gli indici).
Task 2: minor (deferred): il commento di comparisonKey cita il segno Kelvin, che nessun test copre (lo copre il caso «ß», stessa funzione).
Task 2: complete (commits 64f7f59..83df169, review clean)
Ruling: da qui i conteggi del Core del piano sono +3 (Task 3 e 4: 710 test in 62 suite, Features 240 in 23) — tre test nuovi del fix round 1 — se sbagliato costa un conteggio da correggere nel brief.
Task 3: implementer haiku a76dd610c541d64a9, BASE 83df169 (conteggio Core corretto a 710 nel dispatch)
Task 3: commit 9a564ae (710/240, app BUILD SUCCEEDED), DONE_WITH_CONCERNS (osservazioni: trailer, frasi l10n, conteggio 710); file identici alla copia collaudata. Review opus a43393f147b9d28eb.
Task 3: review opus a43393f147b9d28eb: spec ✅ (byte per byte), Approvato, nessun Critical/Important; M11–M17, M19–M22, M25, N5, N6 uccise; M18, O7, O8 equivalenti. ⚠️ vista non ancora aggiornata a 9a564ae (ConfirmStepView lega $path.isSelected): coperta dal Task 4, da verificare nella sua revisione; RED e build app solo dal report (build app confermata in stesura).
Task 3: minor (deferred): totalText con catene di più livelli non testato (O2: isSentOnItsOwn che guarda solo la cartella diretta sopravvive); proposta: asserire nel test esaustivo il totale contro i byte e il conteggio inviati — da triare nella revisione finale.
Task 3: minor (deferred): note testuali non coperte su catene e su più gruppi (O4 ordine inverso dei gruppi in containsText, O5 cartella più esterna in containmentText, O6 «voci» al singolare sopravvivono) — da triare nella revisione finale.
Task 3: minor (deferred): regola di copertura scritta due volte (Core e nodi); diverge solo su una posizione inesistente, irraggiungibile, nella direzione sicura — coperta dal Ruling del controllo preliminare.
Task 3: minor (deferred): «Seleziona tutte» dipende dall'ordine voce/cartella nello stesso gruppo per lo stato proprio di una voce che poi resta coperta; coerente con spec e garanzia, solo da annotare.
Task 3: complete (commits 83df169..9a564ae, review clean)
Task 4: implementer haiku ac8b4375657d9a4ae, BASE 9a564ae (conteggio Core 710 nel dispatch; screenshot riservati al controller)
Task 4: commit 5e1c368 (710/240, app BUILD SUCCEEDED), DONE; file identici alla copia collaudata. Review sonnet a34cd00f2926940df.
Task 4: review sonnet a34cd00f2926940df: spec ✅ (byte per byte), Approvato; tracciamento Observation di PathRow provato con 6 casi in copia scratch; build app con SWIFT_TREAT_WARNINGS_AS_ERRORS riuscita. ⚠️ layout della riga da vedere nello screenshot (controller, solo con consenso).
Task 4: minor (deferred): DemoData.cleanReport e sessions[0] non quadrano più con il passo 3 demo (10 654 MB / 8 elementi contro 4 754 MB / 7) dopo l'aggiunta di huggingface; solo in DEBUG.
Task 4: minor (deferred): commento di PathRow «Letto qui e non solo nel Binding» impreciso (il Binding cattura il valore, non lo legge).
Task 4: complete (commits 9a564ae..5e1c368, review clean)
Revisione finale: opus abe220ca69615b14d su b12292e..5e1c368 (pacchetto review-b12292e..5e1c368.diff), con la lista dei minor rinviati.
Revisione finale: opus abe220ca69615b14d, «With fixes»: 0 Critical, 1 Important (totale sulle catene non testato, O2 sopravvive), 6 Minor; triage dei rinviati: correggere O2, O4–O6 e i numeri della demo; il resto può restare.
Ruling: un unico giro di correzioni (final-fix.md) con l'Important 1 (totale nel test esaustivo), i Minor 1 (test delle note su catena e più gruppi), 2 (accenti e larghezze non si ripiegano), 3 (numeri della demo), 5 (README «same group or another») e il commento di PathRow — tutti senza codice di produzione nel Core né in Features; verificati dal controller in copia scratch (10 sostituzioni, 711/241, O2/O4/O5/O6/OD/OW uccise) — se sbagliato costa test e testi da ritoccare.
Ruling: il Minor 4 (guardia ridondante nodes.indices.contains in link) resta — senza, l'accesso nodes[position.category] non sarebbe più verificato sintatticamente, contro le Global Constraints — se sbagliato costa una riga ridondante.
Ruling: la precondizione facoltativa in aDeniedRootStillLeadsToItsTarget (Task 1) resta fuori — il revisore finale l'ha giudicata facoltativa e la sua mutazione sul ramo negato è uccisa — se sbagliato il test potrebbe smettere di coprire il ramo negato se la deny-list cambiasse.
Final: parked — catena di container ciclica fabbricata a mano blocca selections — Ruling: build produce solo antenati propri, sempre più corti; l'unico chiamante passa l'output di build — se sbagliato resta un blocco possibile solo con righe costruite a mano.
Final: parked — «Seleziona tutte» dipende dall'ordine voce/cartella per lo stato proprio di una voce coperta — Ruling: ciò che si vede coincide sempre con ciò che si cancella, cambia solo lo stato che riappare togliendo la cartella — se sbagliato costa una sorpresa di interfaccia, mai una cancellazione.
Correzioni finali: implementer haiku a84a4a640a66f34a2, FIX_BASE 5e1c368 (final-fix.md).
Correzioni finali: commit 675a88a (711/241, app BUILD SUCCEEDED), file identici alle correzioni verificate. Re-review sonnet a8991aab1df2433b0.
Correzioni finali: re-review sonnet a8991aab1df2433b0: 5/5 affrontati; O2, O4, O5, O6, OD, OW uccise; nessun nuovo problema.
Final: minor (deferred): il doc-comment di theTicksOnScreenMatchWhatIsDeleted non nomina il totale ora asserito; nella spec «Da uccidere almeno» non elenca le mutazioni aggiunte in esecuzione (la sezione dei test le copre).
Final: minor (deferred): il piano storico 2026-10-15-swift-port-4b-app.md riporta i vecchi numeri della demo (documento storico, non si tocca).
Verifica finale del controller nel worktree a 675a88a: Core 711/62, Features 241/23, app BUILD SUCCEEDED, status pulito.
