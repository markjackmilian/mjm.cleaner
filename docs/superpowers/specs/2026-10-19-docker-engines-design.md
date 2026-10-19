# Pagina Docker indipendente dal motore: Docker Desktop, OrbStack e compatibili

## Obiettivo e ambito approvato

La pagina Docker oggi presume Docker Desktop: misura `Docker.raw`, chiede di avviare
Docker Desktop, suggerisce «Troubleshoot → Clean / Purge data» e non conosce i percorsi
di OrbStack. La parte che pulisce passa già solo dalla CLI `docker`, che parla con il
motore del contesto attivo: con OrbStack funziona, ma testi, misura del disco e report
descrivono il motore sbagliato. Sul Mac dell'utente Docker Desktop è ancora installato
(con un `Docker.raw` da circa 10 GB non più in uso) mentre il motore in uso è OrbStack:
oggi l'app misurerebbe quel file e, se il contesto attivo resta `desktop-linux`, direbbe
di avviare Docker Desktop.

L'obiettivo è una pagina che riconosce il motore che risponde e si comporta di
conseguenza, con profili espliciti per Docker Desktop e OrbStack e un comportamento
generico per qualunque altro motore compatibile (Colima, Rancher Desktop, …).

Decisioni dell'utente (2026-10-19):

- **Si pulisce il motore del contesto attivo.** Nessun selettore di contesto e nessun
  ripiego automatico su un altro motore: la pagina usa ciò che userebbe `docker` nel
  terminale e dice quale motore è.
- **Con OrbStack il disco virtuale non si misura.** `data.img.raw` sta in
  `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/`, protetto da macOS (leggerlo
  farebbe comparire la richiesta «accedere ai dati di altre app»), e OrbStack lo riduce
  da solo quando si cancellano dati. Fanno fede le misure di `docker system df`.
- **Motore letto dal daemon, contesto come ripiego** (approccio A): il motore si
  riconosce da `docker info`; il contesto attivo serve solo a dare un nome al motore
  nell'errore quando il daemon non risponde.
- **Demo invariata:** la demo resta su Docker Desktop, nessuno screenshot nuovo.

Fuori ambito: selettore di contesto, avvio o arresto dei motori, misura di
`data.img.raw`, profili dedicati per Colima o Rancher Desktop, voci della deny-list per
motori diversi da OrbStack, rimozione dei dati di un Docker Desktop non più usato (l'app
non cancella mai file dei motori; per recuperare quei 10 GB si disinstalla Docker
Desktop o si usa il suo Purge).

## Riconoscimento del motore

Nuovo modello nel Core (`CleanerCore/Docker/DockerEngine.swift`):

```swift
public enum DockerEngineKind: Sendable, Equatable {
    case dockerDesktop, orbStack, other
}

public struct DockerEngine: Sendable, Equatable {
    public let kind: DockerEngineKind
    public let displayName: String      // "Docker Desktop", "OrbStack" oppure "Docker"
    public let operatingSystem: String  // `OperatingSystem` riportato dal daemon
    public let serverVersion: String
}
```

`DockerInventoryCollector.checkDaemon()` restituisce un `DockerEngine` invece della sola
versione, leggendo `ServerVersion` e `OperatingSystem` con **una sola** chiamata
`docker info --format` che produce un oggetto JSON. Regole:

- `OperatingSystem` uguale a «Docker Desktop», senza distinguere maiuscole e minuscole,
  → `.dockerDesktop`, nome «Docker Desktop».
- `OperatingSystem` uguale a «OrbStack», con lo stesso confronto, → `.orbStack`,
  nome «OrbStack».
- Qualunque altro valore → `.other`, nome «Docker»; `operatingSystem` conserva il valore
  (per esempio «Ubuntu 24.04» con Colima), che può essere vuoto.
- Versione del server vuota o `null` → `DockerUnavailableError` con motivo
  «non in esecuzione», come oggi: è l'unico segnale affidabile di daemon spento.

Il confronto è esatto sull'intero valore: un `OperatingSystem` che contiene «OrbStack»
dentro un testo più lungo non basta.

## Daemon spento: errore con il nome del motore

`DockerUnavailableError` porta un motivo esplicito, «non installato» o «non in
esecuzione», così che nessuno debba più distinguerli confrontando il messaggio. Il testo
generico di «non in esecuzione» perde il riferimento a Docker Desktop: «Docker non è in
esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova.» Lo usano
anche l'esecutore («non eseguito: …») e la demo.

Quando l'analisi fallisce con «non in esecuzione», `DockerCleanupService.analyze` legge
il contesto attivo con `docker context inspect`, che non contatta il daemon, tramite un
nuovo lettore del Core che restituisce nome, descrizione ed endpoint del contesto (o
niente, se il comando fallisce). Il messaggio viene riscritto così:

- descrizione «Docker Desktop», oppure endpoint sotto `~/.docker/run/` →
  «Docker Desktop non è in esecuzione (contesto «‹nome›»). Avvialo e premi Riprova.»
- descrizione «OrbStack», oppure endpoint sotto `~/.orbstack/run/` →
  «OrbStack non è in esecuzione (contesto «‹nome›»). Avvialo e premi Riprova.»
- qualunque altro contesto, compreso `default` su `/var/run/docker.sock` →
  «Il motore Docker del contesto «‹nome›» non risponde. Avvialo e premi Riprova.»
- `context inspect` non riuscito → testo generico invariato.

La descrizione, confrontata come `OperatingSystem`, ha la precedenza sull'endpoint.
L'endpoint si riconosce solo nella forma `unix://‹percorso›`, confrontando il percorso con
le cartelle sotto la home dell'utente; `/var/run/docker.sock` non si risolve (sul Mac
dell'utente punta a OrbStack, ma il collegamento può cambiare).

Il motivo «non installato» non viene mai riscritto. L'app continua a non avviare alcun
motore: è l'utente a deciderlo. Durante la pulizia, un daemon che si ferma resta gestito
come oggi (testo generico, `daemonLost` nel resoconto).

## Ricerca del binario `docker`

`DockerBinaryLocator` prova, in ordine:

1. `~/.docker/bin/docker` (Docker Desktop per l'utente)
2. `~/.orbstack/bin/docker` (OrbStack per l'utente)
3. `/usr/local/bin/docker`
4. `/opt/homebrew/bin/docker`
5. `/Applications/Docker.app/Contents/Resources/bin/docker`
6. `/Applications/OrbStack.app/Contents/MacOS/xbin/docker`

Un candidato vale solo se la sua destinazione, seguendo i collegamenti simbolici, esiste
ed è un file eseguibile. Oggi `LocalFileSystem.fileExists` risponde vero per un
collegamento orfano: dopo aver disinstallato Docker Desktop, `~/.docker/bin/docker`
resterebbe scelto, l'avvio fallirebbe e la pagina direbbe «Docker non è installato»
anche con OrbStack acceso. Il binario non decide quale motore si pulisce (lo decide il
contesto, letto dalla CLI); l'ambiente del processo continua a mettere in testa al PATH
la cartella del binario, dove ciascun motore tiene i propri helper.

## Deny-list

Si aggiunge `~/.orbstack` (socket, configurazione, chiavi SSH di OrbStack), con la stessa
motivazione delle voci di Docker. Il group container di OrbStack è già coperto dalla
voce generica `~/Library/Group Containers`. Le voci esistenti di Docker restano
invariate.

## Disco virtuale e interfaccia del servizio

Il profilo del disco è una funzione pura del motore:

| Motore | Disco misurato | Dopo la pulizia |
|---|---|---|
| Docker Desktop | `Docker.raw` nel percorso attuale | rilascio differito: suggerimento Purge se non cala |
| OrbStack | nessuno | rilascio automatico |
| Altro | nessuno | sconosciuto |

`DiskUsageProbe` riceve il percorso alla misura invece che nel costruttore; logica, `du`
e timeout restano identici.

Cambi di interfaccia:

- `DockerAnalysis.serverVersion` diventa `DockerAnalysis.engine: DockerEngine`.
- `DockerAnalysis.disk` diventa `DockerDiskUsage?`: `nil` significa «questo motore non ha
  un disco da misurare»; un valore con `exists == false` continua a significare «Docker
  Desktop, ma `Docker.raw` non trovato».
- `measureDisk()` diventa `measureDisk(for engine: DockerEngine) async throws ->
  DockerDiskUsage?`: per OrbStack e per gli altri motori restituisce `nil` senza toccare
  il filesystem e senza lanciare `du`.
- `DockerCleanupServing`, il doppio dei test e `DemoServices` seguono la nuova firma.
- `DockerModel` conserva il motore dell'analisi, lo passa a `measureDisk(for:)` dopo la
  pulizia e a `showDockerReport`, che riceve anche il motore; `diskAfter` diventa
  opzionale.

La garanzia di sicurezza non cambia: nessun file sotto le cartelle dei motori viene mai
cancellato; di `Docker.raw` si legge solo la dimensione, di OrbStack nulla.

## Testi

Le viste non cambiano: mostrano i testi del modello così come sono.

Pagina Docker:

| | Docker Desktop | OrbStack | Altro |
|---|---|---|---|
| Server | «Docker Desktop · Docker ‹versione› in esecuzione» | «OrbStack · Docker ‹versione› in esecuzione» | «Docker ‹versione› in esecuzione su «‹operatingSystem›»»; con `operatingSystem` vuoto «Docker ‹versione› in esecuzione» |
| Disco | i tre testi attuali di `Docker.raw` | «OrbStack restituisce da solo al Mac lo spazio liberato: il suo disco virtuale non viene misurato.» | «Disco virtuale di questo motore non misurato: fa fede docker system df.» |

Resoconto:

| | Docker Desktop | OrbStack | Altro |
|---|---|---|---|
| Disco | testi attuali («Docker.raw sul disco: …») | «Disco virtuale: OrbStack restituisce lo spazio al Mac automaticamente.» | «Disco virtuale: non misurato per questo motore.» |
| Purge | testo attuale, solo se `Docker.raw` non cala | mai | mai |
| Daemon perso | «Docker Desktop si è fermato durante la pulizia: …» | «OrbStack si è fermato durante la pulizia: …» | testo attuale («Docker si è fermato…») |

La storia non cambia: la categoria resta «Docker».

## Demo, README e stringhe

- `DemoData` dichiara il motore Docker Desktop: pagina, resoconto e screenshot restano
  come oggi.
- README: la sezione Docker parla di «Docker Desktop, OrbStack o qualunque motore
  compatibile» e spiega la regola del contesto attivo, la misura del disco solo per
  Docker Desktop, il rilascio automatico di OrbStack e `~/.orbstack` nella deny-list.
- I tre `Localizable.xcstrings` hanno modifiche locali di Xcode non committate: non si
  modificano e non si committano.

## Test e verifica

Core (Swift Testing, `FakeDockerCli` e fake del filesystem esistenti):

- riconoscimento: «Docker Desktop», «OrbStack», «orbstack», «Ubuntu 24.04», sistema
  vuoto, versione vuota o `null`; una sola chiamata `docker info`;
- contesto a daemon spento: descrizione Docker Desktop o OrbStack, riconoscimento per
  endpoint, `default` con il testo generico e il nome del contesto, `context inspect`
  fallito; «non installato» mai riscritto;
- servizio: con OrbStack e con un altro motore `disk == nil` e nessun `du` lanciato (lo
  verifica un runner spia); con Docker Desktop si misura il percorso di `Docker.raw`;
- binario: `~/.orbstack/bin/docker` trovato, collegamento orfano saltato, ordine dei
  candidati;
- deny-list: `~/.orbstack` e i percorsi sotto di esso negati, con la motivazione.

Features: testo del server e testi del disco per i tre motori; `measureDisk(for:)`
riceve il motore dell'analisi; nel resoconto testo del disco e daemon perso per motore,
suggerimento Purge solo per Docker Desktop e solo se `Docker.raw` non cala.

Mutazioni, in una copia scratch, che devono essere uccise da un test:

- togliere `~/.orbstack` dalla deny-list;
- far misurare il disco anche a OrbStack;
- mostrare il suggerimento Purge per un motore diverso da Docker Desktop;
- accettare un collegamento orfano nel locator.

Verifica finale: suite completa del package (base 536 + 173 test) e build dell'app con
`xcodebuild`, perché `DemoServices` implementa il protocollo; prova in sola lettura sul
OrbStack reale, da una copia scratch non committata (`checkDaemon()` → `.orbStack`;
lettura del contesto per `orbstack` e `desktop-linux`), con i soli comandi
`docker info` e `docker context inspect`. Nessuno screenshot.
