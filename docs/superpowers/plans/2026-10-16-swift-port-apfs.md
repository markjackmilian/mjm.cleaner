# Porting Swift — Piano APFS: la deny-list sulla grafia del disco

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chiudere il buco del ripiegamento di APFS nel `PathGuard`: un elemento scritto con un nome che APFS equipara a quello di una cartella protetta (`~/Des\u{212A}top/x`, `~/Library/Me\u{00DF}ages`) non deve più superare la deny-list. Il piano comprende lo spike sul nome canonico, l'emendamento della spec §12 e la correzione in `PathGuard` e nella giuntura `FileSystem`.

**Architecture:** Nuovo requisito `FileSystem.storedPath(_:)`: restituisce il percorso come lo registra il filesystem. `LocalFileSystem` lo legge con `getattrlist` (`ATTR_CMN_FULLPATH` e `FSOPT_NOFOLLOW`), `InMemoryFileSystem` restituisce l'identità. `PathGuard` riceve il filesystem e, dopo ogni controllo testuale, ripete la deny-list (in `validate`, `validateRoot` e `pruneReason`) e la profondità minima (in `validate`) sul percorso registrato. Il confronto usa una deny-list costruita sulla home come la registra il disco. Per un percorso che non esiste del tutto vale l'antenato più profondo che esiste, seguito dai componenti mancanti; ogni errore diverso da «non esiste» o «non si attraversa» nega.

**Tech Stack:** Swift 6 language mode, macOS 15, `Darwin` (`getattrlist`), Swift Testing. Nessuna dipendenza esterna.

**Spec:** `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` (§5.2, §5.4, §12 emendati nel Task 2), spike `docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md` (Task 1).

È il piano dedicato al buco APFS, **fra il piano 4 e il piano 5**. Lo ha deciso l'utente il 2026-10-14 (piano 1, Task 9: il buco è uguale nel C# e annotato fra i candidati del registro di parità).

Stato di partenza: `main` a `e83a67e` più il commit di questo piano (nessun push). `(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors)` dà **514** test in 47 suite (`CleanerCoreTests`) e **172** in 21 (`CleanerFeaturesTests`). Il controller crea il branch `feat/swift-port-apfs` da `main` prima del Task 1.

Decisioni dell'utente:

- **Perimetro (2026-10-14).** Spike su come macOS restituisce il nome canonico (realpath, F_GETPATH, getattrlist o altro), misurato su un volume APFS case-insensitive; emendamento della spec §12; correzione in `PathGuard` e nella giuntura `FileSystem`. Fuori: ogni altro candidato del registro, il piano 5.
- **Design (2026-10-16).** Approvato prima della stesura:
  - `FileSystem.storedPath` con `getattrlist`;
  - deny-list e profondità ripetute sul percorso registrato dopo i controlli esistenti, così cambiano solo verdetti che oggi permettono;
  - risalita all'antenato su ENOENT, ENOTDIR, EACCES ed EPERM;
  - ogni altro errore nega con un testo nuovo, «percorso non verificabile sul filesystem: …»;
  - deny-list registrata costruita sulla home come la scrive il disco. Chiude anche il candidato «Home che contiene un collegamento simbolico».

Decisioni prese durante la stesura, verificate in una copia scratch (`git archive` di `e83a67e`):

- **API.** `ATTR_CMN_FULLPATH` con `FSOPT_NOFOLLOW` è l'unica chiamata misurata che dà insieme gli antenati risolti, l'ultimo componente non seguito, i nomi del disco e i firmlink nella forma `/Users/…`, senza `open()`. Il perché delle alternative scartate è nel Task 1.
- **Due task per `PathGuard`.** Il Task 4 cambia solo la firma (`fileSystem:`) e i punti di costruzione, senza effetti. Il Task 5 aggiunge i controlli. Così la revisione della sicurezza (opus, con mutazioni) guarda un diff che contiene solo la logica.
- **Percorso da eliminare.** `canonicalPathValidated` resta il percorso testuale: il kernel lo risolve nello stesso oggetto appena verificato. Diario, log e resoconti non cambiano forma.
- **Testi.** I motivi dei rifiuti sul percorso registrato riusano quelli esistenti («percorso protetto: …», «profondità insufficiente: …», «root risolta degenere: …»). Sono nuovi solo «percorso non verificabile sul filesystem: …», «root non verificabile sul filesystem: …» e due messaggi di `InvalidConfiguration`, che come gli altri non sono localizzati. I `Localizable.xcstrings` non si toccano: `String(localized:)` ricade sulla chiave e i cataloghi committati sono quasi vuoti (in `main` sono modificati da Xcode e non vanno in stage).
- **Doppi di test.** Il filesystem in memoria distingue le maiuscole e non ha collegamenti, quindi restituisce il percorso così com'è. Il nuovo `AliasingFileSystem` simula le grafie di APFS e gli errno per i test del `PathGuard`, con confronti per byte UTF-8: `String` unirebbe U+212A e «K».
- **Mutazioni.** In stesura ne sono state provate 27 su `PathGuard` e `LocalFileSystem` (tabella in fondo). Due sopravvivevano, M3 e M19; i test del Task 5 sono stati rafforzati finché sono morte tutte.

## Global Constraints

- Il codice Swift vive in `swift/`. Il C# (`src/`, `tests/`) **non si modifica**: è il riferimento eseguibile, e qui il comportamento Swift se ne allontana di proposito (spec §12 emendata).
- Il Core cambia solo nei file di questo piano: `Platform/FileSystem.swift`, `Platform/LocalFileSystem.swift`, `Safety/PathGuard.swift`. In `CleanerFeatures` cambiano una riga di `Environment/AppEnvironment.swift` e un commento di `AppEnvironmentTests.swift`. `DenyList`, `PathText`, `CanonicalPath`, `LinkInspecting`, `CleanEngine` e gli scanner restano invariati.
- macOS 15, Swift 6 language mode (concorrenza stretta), nessuna dipendenza esterna.
- In tutto il codice Swift del piano: vietati `!` di forced unwrap, `try!`, `as!` e accessi per indice non verificati (spec §8.2).
- `validate`, `validateRoot` e `pruneReason` non lanciano (spec §5.4): ogni errore del filesystem diventa un rifiuto motivato.
- Testi: solo i due nuovi della sezione precedente. Nessun file `Localizable.xcstrings` cambia.
- Comandi di verifica standard, dalla radice del repository:
  - package: `(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')`;
  - una suite: `(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter <Suite> 2>&1 | grep -E '✘|Test run with|(^|: )(warning|error): ')`.
- Commit frequenti. Ogni messaggio termina con la riga `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, anche se l'ambiente di chi esegue ne suggerisce un'altra.
- Branch `feat/swift-port-apfs`, nessun push. Si mettono in stage solo percorsi espliciti, mai `git add -A`, `git add .` o una cartella intera. Non vanno mai in stage: `.zed/`, `mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` (`swift/MjmCleaner/`, `CleanerCore/Resources/`, `CleanerFeatures/Resources/`) riscritti da Xcode.

---

## Fatti misurati (2026-10-16, macOS 27.0.1, Swift 6.4, volume Data APFS case-insensitive)

- APFS case-insensitive considera lo stesso nome U+212A e «k», «ſ» e «s», «ß» e «ẞ» con «ss», «ﬁ» e «fi», NFC e NFD, U+2126 e «ω», U+212B e «å», «ς» e «σ», le maiuscole e minuscole cherokee. È il ripiegamento completo: la lunghezza cambia.
- Restano nomi diversi «ı» e «İ» da «i», le forme a larghezza piena, U+200B e U+00AD.
- Fra quelle coppie `OrdinalIgnoreCase`, e il `PathText.fold` che lo replica, equipara solo le maiuscole ASCII, «ς» e «σ» e il cherokee. Così `~/Des\u{212A}top`, `~/De\u{017F}ktop`, `~/Library/Me\u{00DF}ages` e `~/.\u{017F}sh` superano la deny-list testuale.
- `getattrlist(path, ATTR_CMN_FULLPATH, FSOPT_NOFOLLOW)` restituisce per `<dir>/Des\u{212A}top/x` il percorso `<dir>/Desktop/x`, con la cache dei nomi fredda o calda. Le altre proprietà misurate:
  - segue i collegamenti fra gli antenati (`/var/tmp` → `/private/var/tmp`), mentre per un collegamento come ultimo componente restituisce il percorso del collegamento;
  - per un collegamento fisico restituisce il nome cercato, anche dopo aver cercato l'altro;
  - conserva la normalizzazione memorizzata, NFC o NFD;
  - mostra la home come `/Users/<nome>`, non `/System/Volumes/Data/Users/<nome>`;
  - `/` dà `/`.
- Errori di `getattrlist`: componente mancante ENOENT, sotto un file ENOTDIR, dentro una cartella senza permesso di attraversamento EACCES (la cartella stessa si legge), ciclo di collegamenti ELOOP, risoluzione oltre MAXPATHLEN ENAMETOOLONG. Un percorso relativo si risolve rispetto alla cartella corrente: il `PathGuard` passa solo percorsi canonici.
- `realpath` segue anche l'ultimo collegamento. `F_GETPATH` richiede un descrittore (`open()` fallisce sui file illeggibili e si blocca su una FIFO), quindi per i collegamenti serve `O_SYMLINK`. `F_GETPATH_NOFIRMLINK` restituisce `/System/Volumes/Data/…`. `ATTR_CMN_NAME` dà solo l'ultimo componente.
- Costo: circa 1–2 µs a chiamata, come `lstat`.
- `FileManager.createDirectory` e `Data.write(to:)` registrano i nomi in NFD (`fileSystemRepresentation`). Un test che deve creare un nome NFC usa `mkdir`.
- `swift build --build-tests -Xswiftc -warnings-as-errors` non segnala una proprietà `private let` mai letta: il Task 4 compila senza avvisi.

---

## Mappa dei file

```
docs/superpowers/
├── spikes/2026-10-16-apfs-nome-canonico.md                     Task 1 (nuovo)
├── specs/2026-10-13-swift-native-port-design.md                Task 2 (§5.2, §5.4, §12)
└── porting/2026-10-13-parity.md                                Task 6
swift/MjmCleanerKit/
├── Sources/CleanerCore/Platform/FileSystem.swift               Task 3 (requisito storedPath)
├── Sources/CleanerCore/Platform/LocalFileSystem.swift          Task 3 (getattrlist)
├── Sources/CleanerCore/Safety/PathGuard.swift                  Task 4 (firma), Task 5 (controlli)
├── Sources/CleanerFeatures/Environment/AppEnvironment.swift    Task 4 (una riga)
├── Tests/CleanerCoreTests/Platform/StoredPathTests.swift       Task 3 (nuovo, 7 test)
├── Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift     Task 3
├── Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift   Task 3
├── Tests/CleanerCoreTests/Support/AliasingFileSystem.swift     Task 5 (nuovo doppio)
├── Tests/CleanerCoreTests/Safety/PathGuardTests.swift          Task 4 (costruzioni), Task 5 (13 test)
├── Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift
│                                                               Task 4 (fixture), Task 5 (2 test)
├── Tests/CleanerCoreTests/{Cleaning/CleanEngineTests, Scanning/RuleScannerTests,
│   Scanning/MatchingDirsTests, Scanning/ScanEngineTests, Xcode/XcodeFileScannerTests,
│   Xcode/XcodeCleanExecutorTests, Integration/XcodeRealFileSystemTests}.swift
│                                                               Task 4 (costruzioni)
└── Tests/CleanerFeaturesTests/AppEnvironmentTests.swift        Task 5 (un commento)
```

---

### Task 1: spike sul nome canonico

Misura di nuovo, sul volume APFS case-insensitive di questo Mac, ciò che il piano dà per misurato. Il documento resta nel repository, la sonda no. Se una riga dell'output (esclusa la sezione 8, il costo) differisce da quella attesa, il design non è più fondato: il task si ferma con `BLOCKED` e riporta la differenza.

**Files:**
- Create: `docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md`

**Interfaces:**
- Consumes: nulla.
- Produces: il documento citato dai commenti dei Task 3 e 5 (`spike del 2026-10-16`, `docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md`).

- [ ] **Step 1: Scrivere la sonda fuori dal repository**

```bash
work="$(mktemp -d -t mjm-apfs-spike)"
echo "$work"
cat > "$work/probe.swift" <<'SWIFT'
// Sonda usa e getta dello spike APFS (piano APFS, Task 1). Misura come APFS case-insensitive
// equipara i nomi e che cosa restituiscono realpath, F_GETPATH e getattrlist per un nome
// scritto in un'altra grafia. Uso: probe <cartella di lavoro nuova>.
import Darwin
import Foundation

func esc(_ text: String) -> String {
    text.unicodeScalars.map { $0.isASCII && $0.value >= 0x20 && $0.value < 0x7f ? String($0) : String(format: "\\u{%04X}", $0.value) }.joined()
}

func errorText(_ code: Int32) -> String { "errno \(code) (\(String(cString: strerror(code))))" }

func exists(_ path: String) -> Bool { var status = stat(); return lstat(path, &status) == 0 }

func touch(_ path: String) { close(open(path, O_CREAT | O_WRONLY, 0o644)) }

func realpathOf(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return errorText(errno) }
    defer { free(resolved) }
    return String(cString: resolved)
}

func fcntlPath(_ path: String, flags: Int32 = O_RDONLY, command: Int32 = F_GETPATH) -> String {
    let descriptor = open(path, flags | O_CLOEXEC)
    guard descriptor >= 0 else { return "open: " + errorText(errno) }
    defer { close(descriptor) }
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(descriptor, command, &buffer) == 0 else { return "fcntl: " + errorText(errno) }
    return String(cString: buffer)
}

func attribute(_ path: String, _ attr: Int32, nofollow: Bool = true) -> String {
    var request = attrlist()
    request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
    request.commonattr = attrgroup_t(attr)
    var buffer = [UInt8](repeating: 0, count: 12 + Int(MAXPATHLEN))
    let result = getattrlist(path, &request, &buffer, buffer.count, nofollow ? UInt32(FSOPT_NOFOLLOW) : 0)
    guard result == 0 else { return errorText(errno) }
    return buffer.withUnsafeBytes { raw in
        let offset = Int(raw.loadUnaligned(fromByteOffset: 4, as: Int32.self))
        let length = Int(raw.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
        return String(decoding: raw[(4 + offset)..<(4 + offset + length - 1)], as: UTF8.self)
    }
}

func fullPath(_ path: String, nofollow: Bool = true) -> String { attribute(path, ATTR_CMN_FULLPATH, nofollow: nofollow) }

guard CommandLine.arguments.count == 2 else { print("uso: probe <cartella>"); exit(2) }
let base = CommandLine.arguments[1]
guard mkdir(base, 0o755) == 0 else { print("la cartella deve essere nuova: \(base)"); exit(2) }
let storedBase = fullPath(base)
func show(_ text: String) -> String {
    esc(text.replacingOccurrences(of: storedBase, with: "<base>").replacingOccurrences(of: base, with: "<base>"))
}
func fresh(_ name: String) -> String { let path = base + "/" + name; mkdir(path, 0o755); return path }

var volume = statfs()
statfs(base, &volume)
let fsType = withUnsafeBytes(of: volume.f_fstypename) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
print("== Volume")
print("tipo: \(fsType); case-sensitive: \(pathconf(base, _PC_CASE_SENSITIVE) == 1 ? "sì" : "no"); conserva le maiuscole: \(pathconf(base, _PC_CASE_PRESERVING) == 1 ? "sì" : "no")")
print("cartella di lavoro registrata come /private/var/…: \(storedBase.hasPrefix("/private/var/") ? "sì" : "no")")

print("\n== 1. Equivalenze di APFS (nome memorizzato ~ nome cercato)")
let pairs: [(String, String, String)] = [
    ("Desktop", "Des\u{212A}top", "U+212A KELVIN SIGN e k"),
    ("Desktop", "De\u{017F}ktop", "U+017F s lunga e s"),
    ("Desktop", "DESKTOP", "maiuscole ASCII"),
    ("Library", "L\u{0131}brary", "U+0131 i senza punto"),
    ("Library", "L\u{0130}brary", "U+0130 I con punto"),
    ("Strasse", "Stra\u{00DF}e", "U+00DF e ss"),
    ("Stra\u{00DF}e", "STRASSE", "ss e U+00DF"),
    ("Stra\u{00DF}e", "Stra\u{1E9E}e", "U+1E9E e U+00DF"),
    ("fine", "\u{FB01}ne", "legatura U+FB01 e fi"),
    ("caf\u{00E9}", "cafe\u{0301}", "NFC e NFD"),
    ("\u{03C3}igma", "\u{03C2}igma", "sigma finale"),
    ("\u{03C9}hm", "\u{2126}hm", "U+2126 OHM SIGN"),
    ("\u{00E5}ngstrom", "\u{212B}ngstrom", "U+212B ANGSTROM SIGN"),
    ("\u{13A0}x", "\u{AB70}x", "cherokee"),
    ("Desktop", "\u{FF24}esktop", "larghezza piena"),
    ("Desktop", "Desk\u{200B}top", "U+200B"),
    ("Desktop", "Des\u{00AD}ktop", "U+00AD"),
]
for (index, pair) in pairs.enumerated() {
    let directory = fresh("eq\(index)")
    mkdir(directory + "/" + pair.0, 0o755)
    print("\(exists(directory + "/" + pair.1) ? "STESSO " : "diverso") \(esc(pair.0)) ~ \(esc(pair.1))  [\(pair.2)]")
}

print("\n== 2. Nome restituito per <dir>/Des\\u{212A}top/x (memorizzato: Desktop/x)")
for order in ["cache fredda", "cache calda"] {
    let directory = fresh(order == "cache fredda" ? "fredda" : "calda")
    mkdir(directory + "/Desktop", 0o755)
    touch(directory + "/Desktop/x")
    if order == "cache calda" { _ = exists(directory + "/Desktop/x") }
    let alias = directory + "/Des\u{212A}top/x"
    print("[\(order)] realpath                        : \(show(realpathOf(alias)))")
    print("[\(order)] F_GETPATH                       : \(show(fcntlPath(alias)))")
    print("[\(order)] F_GETPATH_NOFIRMLINK            : \(show(fcntlPath(alias, command: F_GETPATH_NOFIRMLINK)))")
    print("[\(order)] ATTR_CMN_NAME                   : \(show(attribute(alias, ATTR_CMN_NAME)))")
    print("[\(order)] ATTR_CMN_NAME della cartella    : \(show(attribute(directory + "/Des\u{212A}top", ATTR_CMN_NAME)))")
    print("[\(order)] ATTR_CMN_FULLPATH, FSOPT_NOFOLLOW: \(show(fullPath(alias)))")
}

print("\n== 3. Collegamenti simbolici")
do {
    let directory = fresh("link")
    mkdir(directory + "/Desktop", 0o755)
    symlink(directory + "/Desktop", directory + "/link")
    print("FULLPATH con NOFOLLOW sul collegamento   : \(show(fullPath(directory + "/LINK")))")
    print("FULLPATH senza NOFOLLOW sul collegamento : \(show(fullPath(directory + "/LINK", nofollow: false)))")
    print("FULLPATH attraverso il collegamento      : \(show(fullPath(directory + "/LINK/manca")))")
    mkdir(directory + "/Desktop/sub", 0o755)
    print("FULLPATH di un figlio via collegamento   : \(show(fullPath(directory + "/LINK/sub")))")
    print("realpath sul collegamento                : \(show(realpathOf(directory + "/LINK")))")
    print("F_GETPATH con O_SYMLINK                  : \(show(fcntlPath(directory + "/LINK", flags: O_RDONLY | O_SYMLINK)))")
}

print("\n== 4. Collegamenti fisici (Desktop/x e Caches/y sono lo stesso file)")
do {
    let directory = fresh("fisici")
    mkdir(directory + "/Desktop", 0o755)
    mkdir(directory + "/Caches", 0o755)
    touch(directory + "/Desktop/x")
    link(directory + "/Desktop/x", directory + "/Caches/y")
    print("FULLPATH Caches/y              : \(show(fullPath(directory + "/Caches/y")))")
    print("FULLPATH Des\\u{212A}top/x dopo y : \(show(fullPath(directory + "/Des\u{212A}top/x")))")
    print("FULLPATH Caches/y dopo x       : \(show(fullPath(directory + "/Caches/y")))")
}

print("\n== 5. Normalizzazione e ripiegamento completo")
do {
    let directory = fresh("norm")
    mkdir(directory + "/caf\u{00E9}", 0o755)
    mkdir(directory + "/jose\u{0301}", 0o755)
    mkdir(directory + "/Stra\u{00DF}e", 0o755)
    print("NFC memorizzato, cercato NFD        : \(show(fullPath(directory + "/cafe\u{0301}")))")
    print("NFD memorizzato, cercato NFC        : \(show(fullPath(directory + "/jos\u{00E9}")))")
    print("Stra\\u{00DF}e memorizzato, cercato STRASSE: \(show(fullPath(directory + "/STRASSE")))")
    let viaFoundation = directory + "/cr\u{00E8}me"
    try? FileManager.default.createDirectory(atPath: viaFoundation, withIntermediateDirectories: false)
    print("creato con FileManager come cr\\u{00E8}me: \(show(fullPath(viaFoundation)))")
}

print("\n== 6. Errori")
do {
    let directory = fresh("errori")
    touch(directory + "/file")
    mkdir(directory + "/chiusa", 0o755)
    mkdir(directory + "/chiusa/dentro", 0o755)
    chmod(directory + "/chiusa", 0o600)
    symlink(directory + "/ciclo2", directory + "/ciclo1")
    symlink(directory + "/ciclo1", directory + "/ciclo2")
    symlink(directory + "/nulla", directory + "/rotto")
    var long = fresh("lungo")
    while long.utf8.count < 1000 { long += "/a"; mkdir(long, 0o755) }
    symlink(long, directory + "/corto")
    print("componente mancante       : \(show(fullPath(directory + "/manca/x")))")
    print("sotto un file             : \(show(fullPath(directory + "/file/x")))")
    print("dentro una cartella 0600  : \(show(fullPath(directory + "/chiusa/dentro")))")
    print("la cartella 0600 stessa   : \(show(fullPath(directory + "/chiusa")))")
    print("collegamento interrotto   : \(show(fullPath(directory + "/rotto")))")
    print("attraverso l'interrotto   : \(show(fullPath(directory + "/rotto/x")))")
    print("attraverso un ciclo       : \(show(fullPath(directory + "/ciclo1/x")))")
    print("risolto oltre MAXPATHLEN  : \(show(fullPath(directory + "/corto" + String(repeating: "/b", count: 40))))")
    print("percorso di 1000 byte e più: \(fullPath(long).hasPrefix(storedBase + "/lungo/a/a") ? "registrato per intero" : show(fullPath(long)))")
    print("percorso relativo         : \(show(fullPath("relativo-che-non-esiste")))")
    chmod(directory + "/chiusa", 0o755)
}

print("\n== 7. Firmlink e collegamenti di sistema")
let home = NSHomeDirectory()
print("FULLPATH /var/tmp             : \(fullPath("/var/tmp"))")
print("FULLPATH /tmp (NOFOLLOW)      : \(fullPath("/tmp"))")
print("FULLPATH /                    : \(fullPath("/"))")
print("FULLPATH della home           : \(fullPath(home) == home ? "uguale alla home" : esc(fullPath(home)))")
print("F_GETPATH della home          : \(fcntlPath(home) == home ? "uguale alla home" : esc(fcntlPath(home)))")
print("F_GETPATH_NOFIRMLINK della home: \(fcntlPath(home, command: F_GETPATH_NOFIRMLINK) == "/System/Volumes/Data" + home ? "/System/Volumes/Data + home" : esc(fcntlPath(home, command: F_GETPATH_NOFIRMLINK)))")

print("\n== 8. Costo (variabile)")
do {
    let directory = fresh("costo")
    for index in 0..<2000 { touch(directory + "/f\(index)") }
    var total = 0
    let start = ContinuousClock.now
    for _ in 0..<5 { for index in 0..<2000 { total += fullPath(directory + "/f\(index)").utf8.count } }
    let attributes = ContinuousClock.now - start
    var status = stat()
    let second = ContinuousClock.now
    for _ in 0..<5 { for index in 0..<2000 { total += Int(lstat(directory + "/f\(index)", &status)) } }
    let lstats = ContinuousClock.now - second
    print("10 000 getattrlist FULLPATH: \(attributes); 10 000 lstat: \(lstats) [\(total > 0 ? "ok" : "?")]")
}
SWIFT
```

Expected: stampa un percorso sotto `/var/folders/…/T/`.

- [ ] **Step 2: Compilare ed eseguire**

```bash
swiftc -O "$work/probe.swift" -o "$work/probe" && "$work/probe" "$work/run" > "$work/output.txt"; echo "uscita $?"
```

Expected: `uscita 0`, nessun avviso del compilatore.

- [ ] **Step 3: Confrontare con le misure del piano**

```bash
cat > "$work/expected.txt" <<'TEXT'
== Volume
tipo: apfs; case-sensitive: no; conserva le maiuscole: sì
cartella di lavoro registrata come /private/var/…: sì

== 1. Equivalenze di APFS (nome memorizzato ~ nome cercato)
STESSO  Desktop ~ Des\u{212A}top  [U+212A KELVIN SIGN e k]
STESSO  Desktop ~ De\u{017F}ktop  [U+017F s lunga e s]
STESSO  Desktop ~ DESKTOP  [maiuscole ASCII]
diverso Library ~ L\u{0131}brary  [U+0131 i senza punto]
diverso Library ~ L\u{0130}brary  [U+0130 I con punto]
STESSO  Strasse ~ Stra\u{00DF}e  [U+00DF e ss]
STESSO  Stra\u{00DF}e ~ STRASSE  [ss e U+00DF]
STESSO  Stra\u{00DF}e ~ Stra\u{1E9E}e  [U+1E9E e U+00DF]
STESSO  fine ~ \u{FB01}ne  [legatura U+FB01 e fi]
STESSO  caf\u{00E9} ~ cafe\u{0301}  [NFC e NFD]
STESSO  \u{03C3}igma ~ \u{03C2}igma  [sigma finale]
STESSO  \u{03C9}hm ~ \u{2126}hm  [U+2126 OHM SIGN]
STESSO  \u{00E5}ngstrom ~ \u{212B}ngstrom  [U+212B ANGSTROM SIGN]
STESSO  \u{13A0}x ~ \u{AB70}x  [cherokee]
diverso Desktop ~ \u{FF24}esktop  [larghezza piena]
diverso Desktop ~ Desk\u{200B}top  [U+200B]
diverso Desktop ~ Des\u{00AD}ktop  [U+00AD]

== 2. Nome restituito per <dir>/Des\u{212A}top/x (memorizzato: Desktop/x)
[cache fredda] realpath                        : <base>/fredda/Desktop/x
[cache fredda] F_GETPATH                       : <base>/fredda/Desktop/x
[cache fredda] F_GETPATH_NOFIRMLINK            : /System/Volumes/Data<base>/fredda/Desktop/x
[cache fredda] ATTR_CMN_NAME                   : x
[cache fredda] ATTR_CMN_NAME della cartella    : Desktop
[cache fredda] ATTR_CMN_FULLPATH, FSOPT_NOFOLLOW: <base>/fredda/Desktop/x
[cache calda] realpath                        : <base>/calda/Desktop/x
[cache calda] F_GETPATH                       : <base>/calda/Desktop/x
[cache calda] F_GETPATH_NOFIRMLINK            : /System/Volumes/Data<base>/calda/Desktop/x
[cache calda] ATTR_CMN_NAME                   : x
[cache calda] ATTR_CMN_NAME della cartella    : Desktop
[cache calda] ATTR_CMN_FULLPATH, FSOPT_NOFOLLOW: <base>/calda/Desktop/x

== 3. Collegamenti simbolici
FULLPATH con NOFOLLOW sul collegamento   : <base>/link/link
FULLPATH senza NOFOLLOW sul collegamento : <base>/link/Desktop
FULLPATH attraverso il collegamento      : errno 2 (No such file or directory)
FULLPATH di un figlio via collegamento   : <base>/link/Desktop/sub
realpath sul collegamento                : <base>/link/Desktop
F_GETPATH con O_SYMLINK                  : <base>/link/link

== 4. Collegamenti fisici (Desktop/x e Caches/y sono lo stesso file)
FULLPATH Caches/y              : <base>/fisici/Caches/y
FULLPATH Des\u{212A}top/x dopo y : <base>/fisici/Desktop/x
FULLPATH Caches/y dopo x       : <base>/fisici/Caches/y

== 5. Normalizzazione e ripiegamento completo
NFC memorizzato, cercato NFD        : <base>/norm/caf\u{00E9}
NFD memorizzato, cercato NFC        : <base>/norm/jose\u{0301}
Stra\u{00DF}e memorizzato, cercato STRASSE: <base>/norm/Stra\u{00DF}e
creato con FileManager come cr\u{00E8}me: <base>/norm/cre\u{0300}me

== 6. Errori
componente mancante       : errno 2 (No such file or directory)
sotto un file             : errno 20 (Not a directory)
dentro una cartella 0600  : errno 13 (Permission denied)
la cartella 0600 stessa   : <base>/errori/chiusa
collegamento interrotto   : <base>/errori/rotto
attraverso l'interrotto   : errno 2 (No such file or directory)
attraverso un ciclo       : errno 62 (Too many levels of symbolic links)
risolto oltre MAXPATHLEN  : errno 63 (File name too long)
percorso di 1000 byte e più: registrato per intero
percorso relativo         : errno 2 (No such file or directory)

== 7. Firmlink e collegamenti di sistema
FULLPATH /var/tmp             : /private/var/tmp
FULLPATH /tmp (NOFOLLOW)      : /tmp
FULLPATH /                    : /
FULLPATH della home           : uguale alla home
F_GETPATH della home          : uguale alla home
F_GETPATH_NOFIRMLINK della home: /System/Volumes/Data + home
TEXT
diff -B "$work/expected.txt" <(sed '/^== 8\./,$d' "$work/output.txt") && echo "come nel piano"
sed -n '/^== 8\./,$p' "$work/output.txt"
```

Expected: `come nel piano`, poi la sezione 8 con due durate dell'ordine di 0,01–0,03 secondi ciascuna e `[ok]`. Se `diff` stampa qualcosa, fermarsi: `BLOCKED` con l'output di `diff` (e `"$work/output.txt"` per intero). Le misure sono la premessa del design.

- [ ] **Step 4: Scrivere il documento dello spike**

````bash
cat > "$work/head.md" <<'DOC'
# Spike — nome canonico di un percorso su APFS

**Data:** 2026-10-16 (prima misura, durante la stesura del piano APFS); riverificata il AAAA-MM-GG (Task 1 del piano, output in Appendice B).
**Stato:** completato.
**Piano:** `docs/superpowers/plans/2026-10-16-swift-port-apfs.md`

## 1. Obiettivo

La deny-list del `PathGuard` confronta i percorsi come testo, con il ripiegamento di `OrdinalIgnoreCase`. APFS case-insensitive ripiega di più, quindi un elemento manipolato come `~/Des\u{212A}top/x`, con la stessa root, supera la deny-list e il kernel lo risolve in `~/Desktop/x`. Il C# si comporta allo stesso modo. Lo spike risponde a due domande:

1. Quali nomi equipara APFS, oltre a quelli che equipara `OrdinalIgnoreCase`?
2. Quale chiamata di macOS restituisce il percorso come lo registra il filesystem? Candidati: `realpath`, `fcntl(F_GETPATH)`, `fcntl(F_GETPATH_NOFIRMLINK)`, `getattrlist` con `ATTR_CMN_NAME` o `ATTR_CMN_FULLPATH`.

## 2. Metodo

Una sonda usa e getta in Swift (Appendice A), compilata con `swiftc -O` fuori dal repository ed eseguita su una cartella nuova creata da `mktemp -d -t mjm-apfs-spike` in `$TMPDIR`. Quella cartella sta sul volume Data, APFS case-insensitive, come in ogni Mac con la configurazione predefinita. I nomi si creano con `mkdir` e `open`, non con `FileManager`, che li registrerebbe in NFD (§3.3). Nell'output `<base>` è la cartella di lavoro come la registra il filesystem (`/private/var/folders/…`). La sonda e la cartella sono state rimosse dopo l'esecuzione.

## 3. Risultati

### 3.1 Equivalenze di APFS

| Coppia | APFS | `OrdinalIgnoreCase` |
|---|---|---|
| U+212A KELVIN SIGN e «k» | stesso nome | diversi |
| U+017F «ſ» e «s» | stesso nome | diversi |
| «ß», U+1E9E «ẞ» e «ss» | stesso nome (ripiegamento completo: cambia la lunghezza) | diversi |
| legatura U+FB01 e «fi» | stesso nome | diversi |
| NFC e NFD (`café`) | stesso nome | diversi |
| U+2126 OHM SIGN e «ω», U+212B ANGSTROM SIGN e «å» | stesso nome | diversi |
| «ς» e «σ», cherokee | stesso nome | uguali |
| maiuscole ASCII | stesso nome | uguali |
| U+0131 «ı» e U+0130 «İ» con «i» | diversi | diversi |
| larghezza piena, U+200B, U+00AD | diversi | diversi |

Ne seguono, tra gli altri, `~/Des\u{212A}top`, `~/De\u{017F}ktop`, `~/Documentſ`, `~/.\u{017F}sh`, `~/Library/\u{212A}eychains`, `~/Library/Me\u{00DF}ages` e `~/.pa\u{00DF}word-store`: ognuno raggiunge la cartella protetta senza che la deny-list testuale lo riconosca.

### 3.2 Quale chiamata restituisce il nome del disco

Per `<dir>/Des\u{212A}top/x`, con `Desktop/x` memorizzato, con la cache dei nomi fredda (alias cercato per primo) e calda:

| Chiamata | Risultato | Problema |
|---|---|---|
| `realpath` | `<dir>/Desktop/x` | segue anche l'ultimo collegamento: per un collegamento da rimuovere giudicherebbe la destinazione |
| `F_GETPATH` | `<dir>/Desktop/x` | serve `open()`: fallisce sui file illeggibili, si blocca su una FIFO, e per un collegamento serve `O_SYMLINK` |
| `F_GETPATH_NOFIRMLINK` | `/System/Volumes/Data<dir>/Desktop/x` | la grafia dei firmlink non corrisponde alle voci della deny-list (`/Users/…`) |
| `ATTR_CMN_NAME` | `x` (e `Desktop` per la cartella) | solo l'ultimo componente |
| `ATTR_CMN_FULLPATH` con `FSOPT_NOFOLLOW` | `<dir>/Desktop/x` | nessuno |

### 3.3 Collegamenti, collegamenti fisici, normalizzazione

- Con `FSOPT_NOFOLLOW`, `ATTR_CMN_FULLPATH` di un collegamento è il percorso del collegamento. Senza, o con `realpath`, è la destinazione. Un figlio raggiunto attraverso il collegamento ha il percorso della destinazione: gli antenati si seguono sempre.
- Con un collegamento fisico (`Desktop/x` e `Caches/y` sono lo stesso file) si ottiene il nome cercato, anche dopo aver cercato l'altro.
- La normalizzazione resta quella memorizzata: un nome NFC cercato in NFD dà NFC, e il contrario dà NFD. `Straße` cercato come `STRASSE` dà `Straße`.
- `FileManager.createDirectory` registra `crème` in NFD (`cre\u{0300}me`).

### 3.4 Errori

Componente mancante: ENOENT. Sotto un file: ENOTDIR. Dentro una cartella senza permesso di attraversamento: EACCES (la cartella stessa si legge). Attraverso un collegamento interrotto: ENOENT (il collegamento stesso si legge). Ciclo di collegamenti: ELOOP. Risoluzione oltre MAXPATHLEN: ENAMETOOLONG. Un percorso di mille byte si legge per intero. Un percorso relativo si risolve rispetto alla cartella corrente.

### 3.5 Firmlink e collegamenti di sistema

`/var/tmp` dà `/private/var/tmp`. `/tmp` con `FSOPT_NOFOLLOW` dà `/tmp`, perché è un collegamento. `/` dà `/`. La home dà sé stessa (`/Users/<nome>`), mentre `F_GETPATH_NOFIRMLINK` la scrive `/System/Volumes/Data/Users/<nome>`.

### 3.6 Costo

Diecimila chiamate a `getattrlist` con `ATTR_CMN_FULLPATH` costano quanto diecimila `lstat`, circa 1–2 µs ciascuna (Appendice B, sezione 8).

## 4. Scelta

`getattrlist` con `ATTR_CMN_FULLPATH` e `FSOPT_NOFOLLOW`, esposto come `FileSystem.storedPath(_:)`. È l'unica chiamata misurata che dà insieme:

- i nomi nella grafia del disco;
- gli antenati risolti;
- l'ultimo componente non seguito: il `PathGuard` permette di rimuovere un collegamento e ne giudica il percorso, non la destinazione;
- i firmlink nella forma delle voci della deny-list;
- nessun `open()`.

## 5. Conseguenze per la correzione

- **Due confronti.** Il `PathGuard` ripete la deny-list e la profondità minima sul percorso registrato, dopo i controlli testuali. Il testo resta il primo controllo, e i motivi dei rifiuti che dava restano invariati.
- **Risalita.** Per un percorso che non esiste del tutto si risale all'antenato più profondo che esiste e si aggiungono i componenti mancanti presi dal testo. Si risale con ENOENT ed ENOTDIR (non c'è nulla da eliminare lì) e con EACCES ed EPERM: nemmeno l'eliminazione attraversa quella cartella, perché la ricerca del kernel è la stessa.
- **Fail-closed.** ELOOP, ENAMETOOLONG e ogni altro errore rendono il percorso non verificabile, e il percorso si nega.
- **Home registrata.** I percorsi registrati di una home sotto un collegamento cominciano con `/private/var/…`, quindi il confronto usa la home come la registra il disco.
- **Volume case-sensitive.** Non misurato, perché lo spike riguarda il volume predefinito. Lì un nome con altre maiuscole è un altro nome, e la ricerca dà ENOENT: si risale, si confronta il testo e nessuna cartella protetta viene raggiunta.
DOC
sed "s/AAAA-MM-GG/$(date +%F)/" "$work/head.md" > "$work/head-dated.md"
{
    cat "$work/head-dated.md"
    printf '\n## Appendice A — sorgente della sonda\n\n```swift\n'
    cat "$work/probe.swift"
    printf '```\n\n## Appendice B — output del %s\n\n```text\n' "$(date +%F)"
    cat "$work/output.txt"
    printf '```\n'
} > docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md
grep -c '^## ' docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md
grep -n 'AAAA-MM-GG' docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md || echo "data inserita"
````

Expected: `7` (cinque sezioni e due appendici), poi `data inserita`. Aprire il file e controllare che l'Appendice A sia la sonda dello Step 1 e l'Appendice B l'output dello Step 2, compresa la sezione 8.

- [ ] **Step 5: Rimuovere la sonda e committare**

```bash
rm -rf "$work"
git add docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md
git commit -F - <<'MSG'
docs(swift): measure how APFS spells a path on disk

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
git status --short
```

Expected: il commit con il trailer. `git status --short` mostra solo le voci che c'erano prima del task: `?? .zed/`, `?? mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings` modificati, se ci sono.

---

### Task 2: emendamento della spec

La spec §12 vieta di cambiare le regole durante il porting. Il piano APFS ne è un'eccezione decisa dall'utente: va scritta lì, insieme alla regola nuova. Le §5.2 e §5.4, che descrivono la giuntura `FileSystem` e le regole di sicurezza, la richiamano.

**Files:**
- Modify: `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` (§5.2, §5.4, §12)

**Interfaces:**
- Consumes: lo spike del Task 1.
- Produces: la regola che i Task 3–5 implementano.

- [ ] **Step 1: §5.2, le operazioni di `FileSystem`**

**In `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`, sostituire:**

```markdown
- creazione di una cartella
- spazio libero del volume
```

**con:**

```markdown
- creazione di una cartella
- spazio libero del volume
- percorso come lo registra il filesystem (`storedPath`: `getattrlist` con `ATTR_CMN_FULLPATH` e `FSOPT_NOFOLLOW`), usato dal `PathGuard` (§12)
```

- [ ] **Step 2: §5.4, la sicurezza**

**In `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`, sostituire:**

```markdown
`validate` e `validateRoot` **non sono `throws` per firma**: la regola «nessuna validazione solleva eccezioni» diventa un vincolo del compilatore.
```

**con:**

```markdown
`validate` e `validateRoot` **non sono `throws` per firma**: la regola «nessuna validazione solleva eccezioni» diventa un vincolo del compilatore.

Unica regola che si allontana dal C#, per decisione dell'utente (§12): la deny-list e la profondità minima si applicano anche al percorso come lo registra il filesystem.
```

- [ ] **Step 3: §12, l'eccezione**

**In `docs/superpowers/specs/2026-10-13-swift-native-port-design.md`, sostituire:**

```markdown
- Modifiche a flussi, regole o testi. I miglioramenti notati durante il porting si annotano nel registro di parità come candidati e non si applicano.
```

**con:**

```markdown
- Modifiche a flussi, regole o testi. I miglioramenti notati durante il porting si annotano nel registro di parità come candidati e non si applicano.

  **Eccezione: il ripiegamento di APFS** (decisa dall'utente il 2026-10-14; piano `docs/superpowers/plans/2026-10-16-swift-port-apfs.md`, spike `docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md`). APFS case-insensitive equipara più nomi di `OrdinalIgnoreCase`: U+212A KELVIN SIGN e «k», «ſ» e «s», «ß» e «ss», NFC e NFD. Così un elemento manipolato `~/Des\u{212A}top/x`, con la stessa root, supera la deny-list testuale e il kernel lo risolve in `~/Desktop/x`. Il C# ha lo stesso buco, che in fase 1 si corregge così:

  - `FileSystem.storedPath` restituisce il percorso come lo registra il filesystem (`getattrlist`, `ATTR_CMN_FULLPATH`, `FSOPT_NOFOLLOW`): antenati risolti, ultimo componente non seguito, nomi nella grafia del disco;
  - `PathGuard` ripete la deny-list su quel percorso in `validate`, `validateRoot` e `pruneReason`, e la profondità minima in `validate`, dopo tutti i controlli testuali. Cambiano solo verdetti che prima permettevano; gli altri rifiuti conservano il motivo del C#;
  - per un percorso che non esiste del tutto vale l'antenato più profondo che esiste, seguito dai componenti mancanti presi dal testo. Si risale solo con `ENOENT`, `ENOTDIR`, `EACCES` ed `EPERM`. Ogni altro errore nega con «percorso non verificabile sul filesystem: …» o «root non verificabile sul filesystem: …», gli unici testi nuovi;
  - il confronto usa una deny-list costruita sulla home come la registra il filesystem. Così vale anche per una home sotto un collegamento (chiude il candidato «Home che contiene un collegamento simbolico» del registro di parità);
  - si elimina sempre il percorso testuale validato, come prima.
```

- [ ] **Step 4: Verificare e committare**

```bash
grep -n 'storedPath\|Eccezione: il ripiegamento di APFS\|Unica regola che si allontana' docs/superpowers/specs/2026-10-13-swift-native-port-design.md
git add docs/superpowers/specs/2026-10-13-swift-native-port-design.md
git commit -F - <<'MSG'
docs(swift): amend the spec to close the APFS folding gap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

Expected: quattro righe del `grep`, una in §5.2, una in §5.4 e due in §12; poi il commit con il trailer.

---

### Task 3: `FileSystem.storedPath`

La giuntura del filesystem impara a dire come il disco registra un percorso. Nessun consumatore ancora: il `PathGuard` la usa nei Task 4 e 5.

**Files:**
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/StoredPathTests.swift`
- Modify: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift` (protocollo `FileSystem`)
- Modify: `swift/MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift` (dopo `availableFreeSpace`)
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`

**Interfaces:**
- Consumes: `FileSystemError(code:path:)`, `TemporaryDirectory` (con `volumeIsCaseInsensitive`, `file`, `directory`, `symlink`, `deepTree`), `PathText.trimmingTrailingSlashes`.
- Produces: requisito `func storedPath(_ path: String) throws -> String` del protocollo `FileSystem` (lancia `FileSystemError` con l'errno; `ENOENT` se il percorso non esiste), implementato da `LocalFileSystem`, `InMemoryFileSystem` (la chiave del nodo) e `ForwardingFileSystem` (inoltra a `inner`, ridefinibile con `override`).

- [ ] **Step 1: Scrivere i test**

**Creare `swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/StoredPathTests.swift`:**

```swift
import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// `FileSystem.storedPath` (piano APFS, spec §12): le misure dello spike del 2026-10-16
/// (`docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md`) fissate sul disco reale. I
/// percorsi si confrontano per byte UTF-8: l'uguaglianza di `String` unirebbe NFC e NFD.
struct StoredPathTests {
    private let fs = LocalFileSystem()

    private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive), arguments: [
        ("Desktop", "Des\u{212A}top"),
        ("Desktop", "De\u{017F}ktop"),
        ("Desktop", "DESKTOP"),
        ("Messages", "Me\u{00DF}ages"),
        ("caf\u{00E9}", "cafe\u{0301}"),
    ])
    func storedPathSpellsNamesAsTheDiskStoresThem(stored: String, alias: String) throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        // `mkdir` e non FileManager, che scriverebbe il nome in NFD (`fileSystemRepresentation`).
        #expect(mkdir(tmp.path + "/" + stored, 0o755) == 0)
        try tmp.file(stored + "/x")
        let base = try fs.storedPath(tmp.path)

        #expect(bytes(try fs.storedPath(tmp.path + "/" + alias + "/x")) == bytes(base + "/" + stored + "/x"))
        #expect(bytes(try fs.storedPath(tmp.path + "/" + alias)) == bytes(base + "/" + stored))
    }

    @Test func storedPathResolvesLinkedAncestorsButNotTheLastComponent() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.file("dir/f")
        try tmp.symlink("link", to: tmp.path + "/dir")
        let base = try fs.storedPath(tmp.path)

        // La cartella temporanea sta sotto /var/folders: /var è un collegamento a /private/var.
        #expect(base.hasPrefix("/private/var/"))
        #expect(try fs.storedPath(tmp.path + "/link") == base + "/link")
        #expect(try fs.storedPath(tmp.path + "/link/f") == base + "/dir/f")
    }

    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func storedPathOfAHardLinkIsTheNameThatWasLookedUp() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let original = try tmp.file("Desktop/x", contents: "dati")
        try tmp.directory("Caches")
        #expect(link(original, tmp.path + "/Caches/y") == 0)
        let base = try fs.storedPath(tmp.path)

        #expect(try fs.storedPath(tmp.path + "/Caches/y") == base + "/Caches/y")
        #expect(try fs.storedPath(tmp.path + "/Des\u{212A}top/x") == base + "/Desktop/x")
        #expect(try fs.storedPath(tmp.path + "/Caches/y") == base + "/Caches/y")
    }

    @Test func storedPathOfTheRootAndOfTheHomeKeepsTheUserVisibleSpelling() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        let trimmed = PathText.trimmingTrailingSlashes(home)

        #expect(try fs.storedPath("/") == "/")
        // /Users è un firmlink verso /System/Volumes/Data/Users: resta nella forma che vede l'utente.
        #expect(try fs.storedPath(trimmed) == trimmed)
    }

    @Test func storedPathReportsTheErrnoOfTheLookup() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = try tmp.file("file")
        let locked = try tmp.directory("chiusa/dentro")
        try tmp.symlink("ciclo1", to: tmp.path + "/ciclo2")
        try tmp.symlink("ciclo2", to: tmp.path + "/ciclo1")
        let deep = try tmp.deepTree("profondo")
        let bottom = deep.root + String(repeating: "/a", count: deep.depth)
        try tmp.symlink("corto", to: bottom)
        let chiusa = tmp.path + "/chiusa"
        chmod(chiusa, 0o600)
        defer { chmod(chiusa, 0o755) }

        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/manca/x")) { try fs.storedPath(tmp.path + "/manca/x") }
        #expect(throws: FileSystemError(code: ENOTDIR, path: file + "/x")) { try fs.storedPath(file + "/x") }
        #expect(throws: FileSystemError(code: EACCES, path: locked)) { try fs.storedPath(locked) }
        #expect(throws: FileSystemError(code: ELOOP, path: tmp.path + "/ciclo1/x")) { try fs.storedPath(tmp.path + "/ciclo1/x") }
        // Un collegamento corto verso un percorso lungo: la risoluzione supera MAXPATHLEN.
        let tooLong = tmp.path + "/corto" + String(repeating: "/b", count: 40)
        #expect(throws: FileSystemError(code: ENAMETOOLONG, path: tooLong)) { try fs.storedPath(tooLong) }
        // La cartella chiusa resta leggibile come oggetto: manca solo il permesso di attraversarla.
        #expect(try fs.storedPath(chiusa) == (try fs.storedPath(tmp.path)) + "/chiusa")
    }

    @Test func inMemoryStoredPathIsTheNodeKeyAndMissingPathsThrow() throws {
        let fs = InMemoryFileSystem()
        fs.addFile("/Users/tester/Library/Caches/a.bin", size: 1)

        #expect(try fs.storedPath("/Users/tester/Library/Caches/a.bin") == "/Users/tester/Library/Caches/a.bin")
        #expect(try fs.storedPath("/") == "/")
        #expect(throws: FileSystemError(code: ENOENT, path: "/Users/tester/library")) { try fs.storedPath("/Users/tester/library") }
    }

    @Test func forwardingFileSystemForwardsTheStoredPath() throws {
        let inner = InMemoryFileSystem()
        inner.addDirectory("/Users/tester/Library")

        #expect(try ForwardingFileSystem(inner).storedPath("/Users/tester/Library") == "/Users/tester/Library")
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) { try ForwardingFileSystem(inner).storedPath("/manca") }
    }
}
```

- [ ] **Step 2: Verificare che non compilino**

```bash
(cd swift/MjmCleanerKit && swift build --build-tests -Xswiftc -warnings-as-errors 2>&1 | grep -oE "value of type '[A-Za-z]+' has no member 'storedPath'" | sort -u)
```

Expected: tre righe, `value of type 'ForwardingFileSystem' has no member 'storedPath'`, `value of type 'InMemoryFileSystem' has no member 'storedPath'` e `value of type 'LocalFileSystem' has no member 'storedPath'`. La build fallisce.

- [ ] **Step 3: Il requisito del protocollo**

**In `swift/MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift`, sostituire:**

```swift
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64
}
```

**con:**

```swift
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64
    /// Il percorso assoluto con cui il filesystem registra l'oggetto, senza equivalente .NET
    /// (spec §12): i collegamenti fra gli antenati sono risolti, l'ultimo componente non viene
    /// seguito e ogni nome è scritto come sta sul disco. Su APFS case-insensitive
    /// "Des\u{212A}top", "De\u{017F}ktop" e "DESKTOP" danno "Desktop". Un percorso inesistente
    /// lancia `ENOENT`; ogni altro errore lancia il suo errno.
    func storedPath(_ path: String) throws -> String
}
```

- [ ] **Step 4: L'implementazione reale**

**In `swift/MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift`, sostituire:**

```swift
        guard !overflow else { throw FileSystemError(code: EOVERFLOW, path: path) }
        return bytes
    }
```

**con:**

```swift
        guard !overflow else { throw FileSystemError(code: EOVERFLOW, path: path) }
        return bytes
    }

    /// `getattrlist` con `ATTR_CMN_FULLPATH` e `FSOPT_NOFOLLOW` (spike del 2026-10-16): senza
    /// `open()`, quindi vale anche per i file illeggibili, per i collegamenti e per le FIFO;
    /// `realpath` seguirebbe l'ultimo collegamento, `F_GETPATH` richiede un descrittore e
    /// `F_GETPATH_NOFIRMLINK` scrive "/System/Volumes/Data/…" invece di "/Users/…". Il percorso
    /// registrato non supera MAXPATHLEN: oltre, il kernel risponde `ENAMETOOLONG`.
    public func storedPath(_ path: String) throws -> String {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_FULLPATH)

        // La risposta: la lunghezza totale (u_int32_t), un attrreference_t (posizione del testo
        // rispetto all'attrreference stesso e lunghezza con il terminatore), poi il testo.
        let headerSize = MemoryLayout<UInt32>.size
        let referenceSize = MemoryLayout<attrreference_t>.size
        var buffer = [UInt8](repeating: 0, count: headerSize + referenceSize + Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBytes { bytes in
            getattrlist(path, &request, bytes.baseAddress, bytes.count, UInt32(FSOPT_NOFOLLOW))
        }
        guard result == 0 else { throw FileSystemError(code: errno, path: path) }

        let reference = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: headerSize, as: attrreference_t.self) }
        let start = headerSize + Int(reference.attr_dataoffset)
        let length = Int(reference.attr_length)
        // Un riferimento fuori dal buffer o senza terminatore è una risposta inattesa, non un percorso.
        guard length > 1, start >= headerSize + referenceSize, start + length <= buffer.count, buffer[start + length - 1] == 0 else {
            throw FileSystemError(code: EIO, path: path)
        }
        return String(decoding: buffer[start..<(start + length - 1)], as: UTF8.self)
    }
```

- [ ] **Step 5: I doppi di test**

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift`, sostituire:**

```swift
        return freeSpace.withLock { $0 }
    }
```

**con:**

```swift
        return freeSpace.withLock { $0 }
    }

    /// Senza collegamenti e con le maiuscole distinte, il percorso registrato è la chiave del nodo.
    func storedPath(_ path: String) throws -> String {
        let key = Self.key(path)
        guard nodes.withLock({ $0[key] != nil }) else { throw FileSystemError(code: ENOENT, path: path) }
        return key
    }
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift`, sostituire:**

```swift
        try inner.availableFreeSpace(forVolumeContaining: path)
    }
}
```

**con:**

```swift
        try inner.availableFreeSpace(forVolumeContaining: path)
    }
    func storedPath(_ path: String) throws -> String { try inner.storedPath(path) }
}
```

- [ ] **Step 6: Verificare**

```bash
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter StoredPathTests 2>&1 | grep -E '✘|Test run with|(^|: )(warning|error): ')
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')
```

Expected: `Test run with 7 tests in 1 suite passed`; poi `Test run with 172 tests in 21 suites passed` e `Test run with 521 tests in 48 suites passed`, nessun avviso. Su un volume case-sensitive i due test con `.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive)` vengono saltati: va segnalato, non è il caso di questo Mac.

- [ ] **Step 7: Commit**

```bash
git add swift/MjmCleanerKit/Sources/CleanerCore/Platform/FileSystem.swift \
    swift/MjmCleanerKit/Sources/CleanerCore/Platform/LocalFileSystem.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Platform/StoredPathTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/InMemoryFileSystem.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/ForwardingFileSystem.swift
git commit -F - <<'MSG'
feat(swift): read the path as the file system stores it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

Expected: il commit con il trailer.

---

### Task 4: il `PathGuard` riceve il filesystem

Solo la firma: `PathGuard.init` riceve `fileSystem:` e ogni costruzione lo passa. Nessun comportamento cambia: la suite resta identica. La logica arriva nel Task 5.

**Files:**
- Modify: `swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift` (proprietà e `init`)
- Modify: `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift:73`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift` (6 costruzioni)
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/CleanEngineTests.swift` (2)
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/RuleScannerTests.swift`, `MatchingDirsTests.swift`, `ScanEngineTests.swift` (1 ciascuno)
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeFileScannerTests.swift` (2), `XcodeCleanExecutorTests.swift` (1)
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift` (fixture), `XcodeRealFileSystemTests.swift` (1)

**Interfaces:**
- Consumes: `FileSystem` con `storedPath` (Task 3).
- Produces: `PathGuard.init(denyList: DenyList, fileSystem: any FileSystem, links: any LinkInspecting, homeDirectory: String?) throws`. Ogni costruzione passa il filesystem che usano già scanner e motore: `InMemoryFileSystem()` nei test del solo `PathGuard`, `fs` dove c'è, `LocalFileSystem` nell'app e nei test di integrazione.

- [ ] **Step 1: La firma**

**In `swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift`, sostituire:**

```swift
    private let denyList: DenyList
    private let links: any LinkInspecting
    private let home: String

    public init(denyList: DenyList, links: any LinkInspecting, homeDirectory: String?) throws {
```

**con:**

```swift
    private let denyList: DenyList
    private let fileSystem: any FileSystem
    private let links: any LinkInspecting
    private let home: String

    public init(denyList: DenyList, fileSystem: any FileSystem, links: any LinkInspecting, homeDirectory: String?) throws {
```

**In `swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift`, sostituire:**

```swift
        self.denyList = denyList
        self.links = links
        self.home = home
```

**con:**

```swift
        self.denyList = denyList
        self.fileSystem = fileSystem
        self.links = links
        self.home = home
```

- [ ] **Step 2: L'app**

**In `swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift`, sostituire:**

```swift
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
```

**con:**

```swift
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fileSystem, links: links, homeDirectory: home)
```

- [ ] **Step 3: I test del `PathGuard`**

Sei costruzioni: le due funzioni `create`, i due test del costruttore e i due test con una home propria. Il filesystem è uno `InMemoryFileSystem` vuoto.

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
        try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(symlinks), homeDirectory: Self.home)
```

**con:**

```swift
        try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(symlinks), homeDirectory: Self.home)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
        try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(targets: targets), homeDirectory: Self.home)
```

**con:**

```swift
        try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(targets: targets),
            homeDirectory: Self.home)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
            try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(), homeDirectory: homeDirectory)
```

**con:**

```swift
            try PathGuard(
                denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(),
                homeDirectory: homeDirectory)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
            try PathGuard(denyList: DenyList(homeDirectory: "/Users/altro"), links: FakeLinkInspector(), homeDirectory: Self.home)
```

**con:**

```swift
            try PathGuard(
                denyList: DenyList(homeDirectory: "/Users/altro"), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(),
                homeDirectory: Self.home)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
            denyList: DenyList(homeDirectory: home),
            links: FakeLinkInspector("/Users/aleßandro.roßi/Library/Caches/l"),
```

**con:**

```swift
            denyList: DenyList(homeDirectory: home),
            fileSystem: InMemoryFileSystem(),
            links: FakeLinkInspector("/Users/aleßandro.roßi/Library/Caches/l"),
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
        let guardrail = try PathGuard(denyList: DenyList(homeDirectory: home), links: FakeLinkInspector(), homeDirectory: home)
```

**con:**

```swift
        let guardrail = try PathGuard(
            denyList: DenyList(homeDirectory: home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(), homeDirectory: home)
```

- [ ] **Step 4: Gli altri test**

In `CleanEngineTests` le due funzioni `create` ricevono già il filesystem come `fs`.

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/CleanEngineTests.swift`, sostituire:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
```

**con:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/CleanEngineTests.swift`, sostituire:**

```swift
                denyList: DenyList(homeDirectory: Self.home), links: FakeLinkInspector(targets: targets), homeDirectory: Self.home),
```

**con:**

```swift
                denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: FakeLinkInspector(targets: targets),
                homeDirectory: Self.home),
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/RuleScannerTests.swift`, sostituire:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
```

**con:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/MatchingDirsTests.swift`, sostituire:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
```

**con:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ScanEngineTests.swift`, sostituire:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home),
```

**con:**

```swift
            pathGuard: try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home),
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeFileScannerTests.swift`, sostituire:**

```swift
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home)
```

**con:**

```swift
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeFileScannerTests.swift`, sostituire:**

```swift
        let real = try PathGuard(denyList: DenyList(homeDirectory: Self.home), links: links, homeDirectory: Self.home)
```

**con:**

```swift
        let real = try PathGuard(denyList: DenyList(homeDirectory: Self.home), fileSystem: fs, links: links, homeDirectory: Self.home)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeCleanExecutorTests.swift`, sostituire:**

```swift
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
```

**con:**

```swift
        let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fs, links: links, homeDirectory: home)
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/XcodeRealFileSystemTests.swift`, sostituire:**

```swift
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
```

**con:**

```swift
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fs, links: links, homeDirectory: home)
```

Nella fixture di `RealFileSystemCleanupTests` lo stesso `LocalFileSystem` va al guard, allo scanner e al motore.

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift`, sostituire:**

```swift
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), links: links, homeDirectory: home)
            scanner = RuleScanner(fileSystem: LocalFileSystem(), pathGuard: pathGuard, links: links, clock: SystemWallClock())
            engine = CleanEngine(fileSystem: LocalFileSystem(), pathGuard: pathGuard, clock: SystemWallClock())
```

**con:**

```swift
            let fs = LocalFileSystem()
            let links = FileSystemLinkInspector()
            let pathGuard = try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fs, links: links, homeDirectory: home)
            scanner = RuleScanner(fileSystem: fs, pathGuard: pathGuard, links: links, clock: SystemWallClock())
            engine = CleanEngine(fileSystem: fs, pathGuard: pathGuard, clock: SystemWallClock())
```

- [ ] **Step 5: Verificare**

```bash
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')
```

Expected: `Test run with 172 tests in 21 suites passed` e `Test run with 521 tests in 48 suites passed`, gli stessi numeri del Task 3, nessun avviso. Che ogni costruzione passi il filesystem lo verifica il compilatore: `fileSystem:` non ha un valore predefinito. Le 17 costruzioni sono: 6 in `PathGuardTests`, 2 in `CleanEngineTests`, 2 in `XcodeFileScannerTests`, una ciascuno negli altri sei file e in `AppEnvironment`.

- [ ] **Step 6: Commit**

```bash
git add swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift \
    swift/MjmCleanerKit/Sources/CleanerFeatures/Environment/AppEnvironment.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Cleaning/CleanEngineTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/RuleScannerTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/MatchingDirsTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Scanning/ScanEngineTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeFileScannerTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Xcode/XcodeCleanExecutorTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/XcodeRealFileSystemTests.swift
git commit -F - <<'MSG'
refactor(swift): give the path guard the file system

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

Expected: il commit con il trailer.

---

### Task 5: deny-list e profondità sul percorso registrato

La correzione. Componente che decide le cancellazioni: revisione opus, con le mutazioni della tabella in fondo al piano riprovate in una copia scratch.

**Files:**
- Create: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/AliasingFileSystem.swift`
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift` (import, 13 test in fondo)
- Modify: `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift` (2 test in fondo)
- Modify: `swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift` (contenuto intero)
- Modify: `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift` (un commento)

**Interfaces:**
- Consumes: `FileSystem.storedPath` (Task 3), `PathGuard.init(denyList:fileSystem:links:homeDirectory:)` (Task 4), `DenyList.deniedReason`/`recursiveDeniedReason`, `CanonicalPath.canonical`, `PathText.parent`/`fileName`/`join`, `FakeLinkInspector`, `InMemoryFileSystem`, `ForwardingFileSystem`.
- Produces: `PathGuard` che nega anche quando il percorso registrato è protetto. `AliasingFileSystem(_ inner: any FileSystem = InMemoryFileSystem(), aliases: [(String, String)] = [], failures: [(String, Int32)] = [])`, doppio dei test.

- [ ] **Step 1: Il doppio**

**Creare `swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/AliasingFileSystem.swift`:**

```swift
import CleanerCore
import Darwin

/// Solo Swift (piano APFS): simula, per i test del `PathGuard`, come APFS case-insensitive
/// registra i nomi. Ogni voce di `aliases` riscrive un prefisso (fino a un confine di segmento)
/// nella grafia del disco, per esempio "/Users/tester/Des\u{212A}top" → "/Users/tester/Desktop";
/// ogni voce di `failures` fa lanciare il proprio errno a `storedPath` su quel percorso esatto.
/// I confronti sono per byte UTF-8: `String` unirebbe U+212A e "K" (equivalenza canonica). Il
/// resto va al filesystem interno, vuoto per default: lì `storedPath` lancia ENOENT fino alla
/// radice e il `PathGuard` ricompone il testo.
final class AliasingFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let aliases: [(alias: [UInt8], stored: String)]
    private let failures: [(path: [UInt8], code: Int32)]

    init(_ inner: any FileSystem = InMemoryFileSystem(), aliases: [(String, String)] = [], failures: [(String, Int32)] = []) {
        self.aliases = aliases.map { (Array($0.0.utf8), $0.1) }
        self.failures = failures.map { (Array($0.0.utf8), $0.1) }
        super.init(inner)
    }

    override func storedPath(_ path: String) throws -> String {
        let bytes = Array(path.utf8)
        if let failure = failures.first(where: { $0.path == bytes }) {
            throw FileSystemError(code: failure.code, path: path)
        }
        for entry in aliases where bytes.starts(with: entry.alias) {
            let rest = bytes.dropFirst(entry.alias.count)
            if rest.isEmpty { return entry.stored }
            if rest.first == UInt8(ascii: "/") { return entry.stored + String(decoding: rest, as: UTF8.self) }
        }
        return try super.storedPath(path)
    }
}
```

- [ ] **Step 2: I test del `PathGuard`**

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
import Testing
@testable import CleanerCore
```

**con:**

```swift
import Darwin
import Testing
@testable import CleanerCore
```

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift`, sostituire:**

```swift
        #expect(!guardrail.validate("/Users/marco.mılanı/Library/Caches/x", declaredRoot: "\(home)/Library/Caches").isAllowed)
        #expect(guardrail.pruneReason("/Users/marco.mılanı/Documents") != nil)
    }
}
```

**con:**

```swift
        #expect(!guardrail.validate("/Users/marco.mılanı/Library/Caches/x", declaredRoot: "\(home)/Library/Caches").isAllowed)
        #expect(guardrail.pruneReason("/Users/marco.mılanı/Documents") != nil)
    }

    // MARK: - Percorso registrato dal filesystem (solo Swift, piano APFS, spec §12)

    private func create(storing fileSystem: AliasingFileSystem, home: String = Self.home, targets: [String: String?] = [:]) throws -> PathGuard {
        try PathGuard(denyList: DenyList(homeDirectory: home), fileSystem: fileSystem, links: FakeLinkInspector(targets: targets), homeDirectory: home)
    }

    // Il buco: root ed elemento scritti con un nome che APFS equipara a quello di una cartella
    // protetta superano i confronti OrdinalIgnoreCase, e il kernel li risolve nella cartella
    // protetta. Equivalenze misurate nello spike del 2026-10-16.
    @Test(arguments: [
        ("Des\u{212A}top", "Desktop"),
        ("De\u{017F}ktop", "Desktop"),
        ("Library/Me\u{00DF}ages", "Library/Messages"),
        (".\u{017F}sh", ".ssh"),
    ])
    func deniesAnItemWhoseStoredPathIsProtected(alias: String, stored: String) throws {
        let root = "\(Self.home)/\(alias)"
        let protected = "\(Self.home)/\(stored)"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(root, protected)]))

        let rootVerdict = guardrail.validateRoot(root)
        let verdict = guardrail.validate("\(root)/x", declaredRoot: root)

        #expect(!rootVerdict.isAllowed)
        #expect(rootVerdict.reason.contains(protected))
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains(protected))
        #expect(verdict.canonicalPathValidated == "\(root)/x")
    }

    // La profondità minima si ripete sulla grafia del disco: "/U\u{017F}ers" sfugge sia alla regola
    // "/Users" sia alla home testuale.
    @Test func deniesADirectChildOfTheHomeReachedThroughAnAlias() throws {
        let alias = "/U\u{017F}ers/tester"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(alias, Self.home)]))

        let verdict = guardrail.validate("\(alias)/Downloads", declaredRoot: alias)

        #expect(guardrail.validateRoot(alias).isAllowed)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("profondità"))
        #expect(guardrail.validate("\(alias)/Downloads/vecchio.dmg", declaredRoot: alias).isAllowed)
    }

    // Anche le voci a uguaglianza esatta valgono sulla grafia del disco.
    @Test func deniesAnItemWhoseStoredPathIsTheHome() throws {
        let guardrail = try create(storing: AliasingFileSystem(aliases: [("/U\u{017F}ers/tester", Self.home)]))

        let verdict = guardrail.validate("/U\u{017F}ers/tester", declaredRoot: "/U\u{017F}ers")

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("percorso protetto: \(Self.home)"))
    }

    // La destinazione di un collegamento si legge come testo (readlink): una cache spostata su
    // "~/Des\u{212A}top" con un collegamento passava la deny-list testuale.
    @Test func validateRootDeniesALinkTargetSpelledWithAnAlias() throws {
        let alias = "\(Self.home)/Des\u{212A}top"
        let guardrail = try create(
            storing: AliasingFileSystem(aliases: [(alias, "\(Self.home)/Desktop")]), targets: [Self.cacheRoot: alias])

        let verdict = guardrail.validateRoot(Self.cacheRoot)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("\(Self.home)/Desktop"))
        #expect(verdict.canonicalPathValidated == alias)
    }

    @Test func validateRootDeniesARootStoredAsTheFilesystemRoot() throws {
        let root = "\(Self.home)/radice"
        let verdict = try create(storing: AliasingFileSystem(aliases: [(root, "/")])).validateRoot(root)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("degenere"))
    }

    @Test func pruneReasonPrunesABranchWhoseStoredPathIsProtected() throws {
        let alias = "\(Self.home)/progetti/Des\u{212A}top"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(alias, "\(Self.home)/Desktop")]))

        let reason = try #require(guardrail.pruneReason(alias))

        #expect(reason.contains("\(Self.home)/Desktop"))
        #expect(guardrail.pruneReason("\(Self.home)/progetti/app") == nil)
    }

    // Fail-closed: un errore che non dice «non esiste» né «non si attraversa» lascia il percorso
    // non verificabile, e la cancellazione non si tenta.
    @Test(arguments: [EIO, ELOOP, ENAMETOOLONG])
    func anUnverifiableStoredPathIsDenied(code: Int32) throws {
        let item = "\(Self.cacheRoot)/x"
        let branch = "\(Self.cacheRoot)/sub"
        let root = "\(Self.home)/Library/Logs"
        let guardrail = try create(storing: AliasingFileSystem(failures: [(item, code), (branch, code), (root, code)]))

        let verdict = guardrail.validate(item, declaredRoot: Self.cacheRoot)
        let rootVerdict = guardrail.validateRoot(root)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("non verificabile"))
        #expect(!rootVerdict.isAllowed)
        #expect(rootVerdict.reason.contains("non verificabile"))
        #expect(try #require(guardrail.pruneReason(branch)).contains("non verificabile"))
    }

    // Un elemento sparito o dietro una cartella che non si attraversa resta verificabile: si
    // risale all'antenato, e la cancellazione che segue riporta il proprio errore come prima.
    @Test(arguments: [ENOENT, ENOTDIR, EACCES, EPERM])
    func missingOrHiddenComponentsClimbToTheirAncestor(code: Int32) throws {
        let item = "\(Self.cacheRoot)/x"
        let guardrail = try create(storing: AliasingFileSystem(failures: [(item, code), (Self.cacheRoot, code)]))

        #expect(guardrail.validateRoot(Self.cacheRoot).isAllowed)
        #expect(guardrail.validate(item, declaredRoot: Self.cacheRoot).isAllowed)
        #expect(guardrail.pruneReason(item) == nil)
    }

    // I componenti che mancano si giudicano dopo l'antenato nella sua grafia del disco, nel loro
    // ordine: qui mancano sia "Xcode" sia "UserData".
    @Test func missingComponentsAreJudgedAfterTheStoredSpellingOfTheirAncestor() throws {
        let alias = "/U\u{017F}ers/tester/Library/Developer"
        let root = "\(alias)/Xcode"
        let item = "\(root)/UserData"
        let guardrail = try create(storing: AliasingFileSystem(
            aliases: [(alias, "\(Self.home)/Library/Developer")], failures: [(item, ENOENT), (root, ENOENT)]))

        let verdict = guardrail.validate(item, declaredRoot: root)

        #expect(guardrail.validateRoot(root).isAllowed)
        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("\(Self.home)/Library/Developer/Xcode/UserData"))
    }

    // La deny-list registrata si costruisce sulla home come la scrive il disco: con una home
    // sotto un collegamento (/var → /private/var) i percorsi già risolti da validateRoot non
    // somigliano più alla home testuale.
    @Test func theStoredHomeProtectsAHomeUnderALink() throws {
        let home = "/var/h/tester"
        let stored = "/private/var/h/tester"
        let guardrail = try create(storing: AliasingFileSystem(aliases: [(home, stored)]), home: home)

        let rootVerdict = guardrail.validateRoot("\(stored)/Documents")
        let item = guardrail.validate("\(stored)/Documents/x", declaredRoot: stored)
        let child = guardrail.validate("\(stored)/Downloads", declaredRoot: stored)

        #expect(!rootVerdict.isAllowed)
        #expect(rootVerdict.reason.contains("\(stored)/Documents"))
        #expect(!item.isAllowed)
        #expect(item.reason.contains("\(stored)/Documents"))
        #expect(!child.isAllowed)
        #expect(child.reason.contains("profondità"))
        #expect(guardrail.validate("\(stored)/Library/Caches/x", declaredRoot: "\(stored)/Library/Caches").isAllowed)
    }

    @Test func constructorRejectsAHomeThatTheFilesystemCannotVerify() {
        #expect(throws: InvalidConfiguration.self) {
            try create(storing: AliasingFileSystem(failures: [(Self.home, EIO)]))
        }
    }

    @Test(arguments: ["/", "/Users", "Users/tester", "", "/Users/tester/../altro"])
    func constructorRejectsADegenerateStoredHome(stored: String) {
        #expect(throws: InvalidConfiguration.self) {
            try create(storing: AliasingFileSystem(aliases: [(Self.home, stored)]))
        }
    }

    // I controlli sulla grafia del disco vengono dopo quelli testuali: un rifiuto che il C#
    // emetteva conserva il proprio motivo.
    @Test func textualRefusalsKeepTheirReason() throws {
        let link = "\(Self.cacheRoot)/collegamento"
        let guardrail = try PathGuard(
            denyList: DenyList(homeDirectory: Self.home),
            fileSystem: AliasingFileSystem(aliases: [(link, "\(Self.home)/Documents")]),
            links: FakeLinkInspector(link),
            homeDirectory: Self.home)

        let verdict = guardrail.validate("\(link)/x", declaredRoot: Self.cacheRoot)

        #expect(!verdict.isAllowed)
        #expect(verdict.reason.contains("antenato è un collegamento simbolico"))
    }
}
```

- [ ] **Step 3: I test di integrazione**

**In `swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift`, sostituire:**

```swift
        let outcome = try await fixture.scanOnTheCooperativePool(CleanupRule(fixture.caches, .matchingDirs, include: ["bin"], exclude: []))

        #expect(outcome == RuleScanOutcome(
            items: [ScanItem(path: tree.bottom + "/bin", sizeBytes: 1, isDirectory: true, declaredRoot: fixture.caches)], errors: [], exclusions: []))
    }
}
```

**con:**

```swift
        let outcome = try await fixture.scanOnTheCooperativePool(CleanupRule(fixture.caches, .matchingDirs, include: ["bin"], exclude: []))

        #expect(outcome == RuleScanOutcome(
            items: [ScanItem(path: tree.bottom + "/bin", sizeBytes: 1, isDirectory: true, declaredRoot: fixture.caches)], errors: [], exclusions: []))
    }

    // Solo Swift (piano APFS, spec §12): un elenco manipolato con root ed elemento scritti
    // "Des\u{212A}top" superava la deny-list testuale, e APFS li risolveva nella Scrivania.
    @Test(.enabled(if: TemporaryDirectory.volumeIsCaseInsensitive))
    func anItemSpelledWithAnApfsAliasOfAProtectedFolderIsNeverDeleted() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let thesis = try fixture.tmp.file("home/Desktop/tesi.docx", contents: "dati preziosi")
        let root = fixture.home + "/Des\u{212A}top"
        let item = ScanItem(path: root + "/tesi.docx", sizeBytes: 0, isDirectory: false, declaredRoot: root)

        let report = await fixture.engine.clean([CategorySelection(categoryId: "caches", items: [item])], progress: nil, journal: nil)

        #expect(report.itemsDeleted == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.errors.first?.message.contains("/Desktop") == true)
        #expect(FileManager.default.fileExists(atPath: thesis))
    }

    // Solo Swift (piano APFS): la home di prova sta sotto /var, collegamento a /private/var.
    // validateRoot risolve la root in /private/var e la deny-list testuale, costruita sulla home
    // in /var, non la riconosceva: ~/Documents non era protetta (candidato «Home che contiene un
    // collegamento simbolico»). La deny-list sulla grafia del disco la riconosce.
    @Test func aHomeUnderALinkStillProtectsItsDocuments() async throws {
        let fixture = try Fixture(); defer { fixture.tmp.remove() }
        let thesis = try fixture.tmp.file("home/Documents/tesi.docx", contents: "dati preziosi")
        let item = ScanItem(path: thesis, sizeBytes: 0, isDirectory: false, declaredRoot: fixture.home + "/Documents")

        let report = await fixture.engine.clean([CategorySelection(categoryId: "caches", items: [item])], progress: nil, journal: nil)

        #expect(report.itemsDeleted == 0)
        #expect(report.itemsFailed == 1)
        #expect(report.errors.first?.message.contains("/Documents") == true)
        #expect(FileManager.default.fileExists(atPath: thesis))
    }
}
```

- [ ] **Step 4: Verificare che falliscano**

```bash
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E '^✘ Test [A-Za-z]+\(\)|^✘ Test [A-Za-z]+\([a-z:]+\) with|Test run with|(^|: )(warning|error): ' | grep -v 'recorded an issue' | sort -u)
```

Expected: falliscono 13 test e la suite non passa (`Test run with 536 tests in 48 suites failed`):

- 11 in `PathGuardTests`: `deniesAnItemWhoseStoredPathIsProtected(alias:stored:)`, `deniesADirectChildOfTheHomeReachedThroughAnAlias()`, `deniesAnItemWhoseStoredPathIsTheHome()`, `validateRootDeniesALinkTargetSpelledWithAnAlias()`, `validateRootDeniesARootStoredAsTheFilesystemRoot()`, `pruneReasonPrunesABranchWhoseStoredPathIsProtected()`, `anUnverifiableStoredPathIsDenied(code:)`, `missingComponentsAreJudgedAfterTheStoredSpellingOfTheirAncestor()`, `theStoredHomeProtectsAHomeUnderALink()`, `constructorRejectsAHomeThatTheFilesystemCannotVerify()`, `constructorRejectsADegenerateStoredHome(stored:)`;
- 2 in `RealFileSystemCleanupTests`: `anItemSpelledWithAnApfsAliasOfAProtectedFolderIsNeverDeleted()` e `aHomeUnderALinkStillProtectsItsDocuments()`. Nel primo il file di prova sotto la Scrivania della home finta viene davvero cancellato: è il buco, in una cartella temporanea.

Passano già `missingOrHiddenComponentsClimbToTheirAncestor(code:)` e `textualRefusalsKeepTheirReason()`, che fissano ciò che non deve cambiare. `CleanerFeaturesTests` resta a 172 verdi.

- [ ] **Step 5: La correzione**

**Sostituire l'intero contenuto di `swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift` con:**

```swift
import Foundation

/// Esito di una validazione. `canonicalPathValidated` è il percorso su cui il verdetto è stato
/// effettivamente emesso: quando permesso, è quello che va eliminato, non l'argomento originale —
/// validare una stringa e cancellarne un'altra vanificherebbe ogni controllo precedente. È vuoto
/// quando il rifiuto è emesso prima che un percorso canonico fosse disponibile.
public struct GuardVerdict: Sendable, Equatable {
    public let isAllowed: Bool
    public let reason: String
    public let canonicalPathValidated: String

    public init(isAllowed: Bool, reason: String, canonicalPathValidated: String) {
        self.isAllowed = isAllowed
        self.reason = reason
        self.canonicalPathValidated = canonicalPathValidated
    }

    public static func allow(_ canonicalPath: String) -> GuardVerdict {
        GuardVerdict(isAllowed: true, reason: "", canonicalPathValidated: canonicalPath)
    }

    public static func deny(_ reason: String, _ canonicalPath: String = "") -> GuardVerdict {
        GuardVerdict(isAllowed: false, reason: reason, canonicalPathValidated: canonicalPath)
    }
}

public protocol PathGuarding: Sendable {
    /// Valida la root dichiarata da una regola, risalendo i suoi antenati fino alla radice: se la
    /// root o un antenato è un collegamento simbolico lo risolve alla destinazione finale invece di
    /// negarlo alla cieca (su macOS "/var", "/etc" e "/tmp" sono collegamenti, e negarli renderebbe
    /// "$TMPDIR" non pulibile), e al percorso risolto applica la canonicità e solo le voci
    /// RICORSIVE della deny-list. Va invocata una volta per regola, prima degli elementi.
    func validateRoot(_ declaredRoot: String) -> GuardVerdict

    /// Valida un singolo elemento contro la root dichiarata. Presuppone che `validateRoot` sia già
    /// stata invocata con successo sulla stessa root: il controllo sui collegamenti qui risale solo
    /// fino alla root.
    func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict

    /// Il motivo per cui una cartella va esclusa dalla discesa ricorsiva perché la deny-list la
    /// protegge, oppure `nil`. Così uno scanner pota l'intero ramo invece di produrre
    /// un'esclusione per ogni elemento al suo interno, che per "~/Documents" o "~/.ssh" ne
    /// rivelerebbe i nomi dei file. Applica solo la deny-list, non contenimento né profondità.
    func pruneReason(_ candidatePath: String) -> String?
}

/// Ultima linea di difesa: invocato immediatamente prima di ogni eliminazione, non solo quando si
/// definiscono le regole. Non lancia mai: un input malformato produce un rifiuto motivato, mai un
/// errore che un `catch` a monte potrebbe trasformare in un salto silenzioso. In Swift la regola
/// è imposta dalla firma: `validate` e `validateRoot` non sono `throws`.
///
/// Solo Swift (piano APFS, spec §12): la deny-list e la profondità minima si applicano anche al
/// percorso come lo registra il filesystem (`FileSystem.storedPath`), dopo ogni controllo
/// testuale. APFS case-insensitive ripiega più di OrdinalIgnoreCase (U+212A per "k", "ſ" per
/// "s", "ß" per "ss", NFC e NFD): un elemento scritto "~/Des\u{212A}top/x" supera i confronti
/// testuali e il kernel lo risolve in "~/Desktop/x".
public struct PathGuard: PathGuarding {
    /// Limite di sostituzioni successive durante la risoluzione dei collegamenti di una root:
    /// una catena più lunga è quasi certamente un ciclo nel doppio di test, non uno scenario
    /// reale — nega invece di girare all'infinito.
    private static let maxSymlinkResolutions = 32

    /// Gli errori di `storedPath` per cui si risale all'antenato: il componente non esiste
    /// (ENOENT, ENOTDIR) o il suo genitore non si attraversa (EACCES, EPERM). In entrambi i casi
    /// nemmeno l'eliminazione raggiunge l'oggetto, perché la ricerca del kernel è la stessa. Ogni
    /// altro errore rende il percorso non verificabile, e il percorso viene negato.
    private static let climbableErrors: Set<Int32> = [ENOENT, ENOTDIR, EACCES, EPERM]

    private let denyList: DenyList
    private let fileSystem: any FileSystem
    private let links: any LinkInspecting
    private let home: String
    /// Home e deny-list nella grafia del disco: il percorso registrato di un elemento si confronta
    /// con queste, non con quelle testuali. Una home sotto un collegamento (/var → /private/var)
    /// o scritta in un'altra normalizzazione ha sul disco un'altra grafia.
    private let storedHome: String
    private let storedDenyList: DenyList

    public init(denyList: DenyList, fileSystem: any FileSystem, links: any LinkInspecting, homeDirectory: String?) throws {
        guard let home = CanonicalPath.canonical(homeDirectory), home != "/" else {
            throw InvalidConfiguration("La home directory deve essere un percorso assoluto canonico diverso dalla radice.")
        }

        // Imposta, non solo documenta: con due home diverse fra guard e deny-list, la regola di
        // profondità (punto 4 di validate) proteggerebbe la home sbagliata.
        guard PathText.equalsIgnoringCase(home, denyList.homeDirectory) else {
            throw InvalidConfiguration("La home del PathGuard deve coincidere con quella della DenyList.")
        }

        let stored: String
        switch Self.storedForm(home, in: fileSystem) {
        case .success(let path): stored = path
        case .failure(let error):
            throw InvalidConfiguration("La home directory non è verificabile sul filesystem: \(error.description)")
        }
        guard let storedHome = CanonicalPath.canonical(stored), storedHome != "/" else {
            throw InvalidConfiguration("La home directory registrata dal filesystem deve essere un percorso assoluto canonico diverso dalla radice.")
        }

        self.denyList = denyList
        self.fileSystem = fileSystem
        self.links = links
        self.home = home
        self.storedHome = storedHome
        storedDenyList = try DenyList(homeDirectory: storedHome)
    }

    public func validateRoot(_ declaredRoot: String) -> GuardVerdict {
        let root: String
        switch Self.canonicalRoot(declaredRoot) {
        case .success(let canonical): root = canonical
        case .failure(let verdict): return verdict
        }

        let resolved: String
        switch resolveSymlinkedAncestors(root) {
        case .success(let path): resolved = path
        case .failure(let verdict): return verdict
        }

        // Due cause distinte, due messaggi distinti: un percorso risolto non canonico non
        // "coincide con la radice del filesystem" — lo fa solo il caso verificato a parte.
        guard let canonicalResolved = CanonicalPath.canonical(resolved) else {
            return .deny(String(localized: "root risolta non canonica", bundle: .module))
        }

        if canonicalResolved == "/" {
            return .deny(String(localized: "root risolta degenere: coincide con la radice del filesystem", bundle: .module))
        }

        // Solo le voci ricorsive: quelle a uguaglianza esatta ("/", "/Users", la home) proteggono
        // solo se stesse, non il permesso di guardarci dentro.
        if let reason = denyList.recursiveDeniedReason(canonicalResolved) {
            return .deny(reason, canonicalResolved)
        }

        // Come il punto 7 di validate: la root risolta si confronta anche nella grafia del disco,
        // con le sole voci ricorsive.
        switch storedForm(canonicalResolved) {
        case .failure(let error):
            return .deny(String(localized: "root non verificabile sul filesystem: \(error.description)", bundle: .module), canonicalResolved)
        case .success(let stored):
            if stored == "/" {
                return .deny(String(localized: "root risolta degenere: coincide con la radice del filesystem", bundle: .module), canonicalResolved)
            }
            if let reason = storedDenyList.recursiveDeniedReason(stored) {
                return .deny(reason, canonicalResolved)
            }
        }

        return .allow(canonicalResolved)
    }

    public func validate(_ candidatePath: String, declaredRoot: String) -> GuardVerdict {
        // 1. Rifiuto dei percorsi non canonici, prima di qualsiasi confronto. Nessuna risoluzione
        //    testuale di "." o "..": il kernel risolve ".." DOPO aver attraversato un collegamento,
        //    una risoluzione testuale lo farebbe PRIMA, facendo sparire il collegamento dalla
        //    stringa prima che la regola 5 possa vederlo. Gli elementi da eliminare arrivano
        //    sempre dall'enumerazione del filesystem, che non produce mai "..".
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return .deny(String(localized: "percorso non canonico", bundle: .module))
        }

        let root: String
        switch Self.canonicalRoot(declaredRoot) {
        case .success(let canonical): root = canonical
        case .failure(let verdict): return verdict
        }

        // 2. Contenimento nella root dichiarata dalla regola che ha prodotto l'elemento.
        guard PathText.hasPrefixIgnoringCase(path, root + "/") || PathText.equalsIgnoringCase(path, root) else {
            return .deny(String(localized: "violazione del contenimento: fuori da \(root)", bundle: .module), path)
        }

        // 3. Deny-list.
        if let reason = denyList.deniedReason(path) {
            return .deny(reason, path)
        }

        // 4. Profondità minima: mai la home, mai un suo figlio diretto.
        if Self.isHomeOrDirectChild(path, of: home) {
            return .deny(String(localized: "profondità insufficiente: figlio diretto della home", bundle: .module), path)
        }

        // 5. Collegamenti simbolici fra l'elemento e la root: la root e ciò che sta sopra sono già
        //    stati verificati da validateRoot, quindi qui si risale fino a lì, non oltre.
        // Il limite è semantico (strettamente sotto la root), non una lunghezza: un ripiegamento
        // delle maiuscole non può accorciarlo.
        let rootPrefix = root + "/"
        var ancestor = PathText.parent(path)
        while let current = ancestor, PathText.hasPrefixIgnoringCase(current, rootPrefix) {
            if links.isSymbolicLink(current) {
                return .deny(String(localized: "antenato è un collegamento simbolico: \(current)", bundle: .module), path)
            }
            ancestor = PathText.parent(current)
        }

        // 6. Un elemento che coincide esattamente con la root dichiarata cancellerebbe la
        //    root per intero invece di svuotarla — il contratto di ogni regola (in
        //    particolare quelle a svuotamento) è che la root sopravvive. Lo scanner non
        //    produce mai un elemento così (ClearContents elenca solo i figli diretti della
        //    root, mai la root stessa), ma il modello di minaccia dichiara esplicitamente
        //    l'elenco manipolabile fra la scansione e la conferma. Deliberatamente l'ultimo
        //    controllo, dopo quello di profondità (punto 4): quando root e home coincidono
        //    (o la root è un figlio diretto della home), quella regola già nega con un
        //    motivo più specifico ("profondità insufficiente"), e non va scavalcata da un
        //    motivo più generico qui.
        if PathText.equalsIgnoringCase(path, root) {
            return .deny(String(localized: "l'elemento coincide con la root della regola: \(root)", bundle: .module), path)
        }

        // 7. Il percorso come lo registra il filesystem (spec §12): deny-list e profondità minima
        //    si ripetono sulla grafia del disco. Sono gli ultimi controlli, così i motivi dei
        //    rifiuti testuali restano quelli di prima. Si elimina comunque il percorso testuale:
        //    il kernel lo risolve nello stesso oggetto appena verificato.
        switch storedForm(path) {
        case .failure(let error):
            return .deny(String(localized: "percorso non verificabile sul filesystem: \(error.description)", bundle: .module), path)
        case .success(let stored):
            if let reason = storedDenyList.deniedReason(stored) {
                return .deny(reason, path)
            }
            if Self.isHomeOrDirectChild(stored, of: storedHome) {
                return .deny(String(localized: "profondità insufficiente: figlio diretto della home", bundle: .module), path)
            }
        }

        return .allow(path)
    }

    public func pruneReason(_ candidatePath: String) -> String? {
        guard let path = CanonicalPath.canonical(candidatePath) else {
            return String(localized: "percorso non canonico", bundle: .module)
        }
        if let reason = denyList.deniedReason(path) {
            return reason
        }
        // Come il punto 7 di validate.
        switch storedForm(path) {
        case .failure(let error):
            return String(localized: "percorso non verificabile sul filesystem: \(error.description)", bundle: .module)
        case .success(let stored):
            return storedDenyList.deniedReason(stored)
        }
    }

    // MARK: - Privati

    private enum Step<Value> {
        case success(Value)
        case failure(GuardVerdict)
    }

    /// Canonicalizza la root e ne rifiuta le forme degeneri: una root che coincide con la radice
    /// rende il contenimento vero per qualunque percorso assoluto, quindi privo di significato.
    private static func canonicalRoot(_ declaredRoot: String) -> Step<String> {
        guard let canonical = CanonicalPath.canonical(declaredRoot), canonical != "/" else {
            return .failure(.deny(String(localized: "root non canonica o degenere: coincide con la radice del filesystem", bundle: .module)))
        }
        return .success(canonical)
    }

    /// Risolve iterativamente i collegamenti fra gli antenati di `root` (se stessa inclusa),
    /// sostituendo ciascuno con la sua destinazione finale, finché non ne restano. Se la
    /// destinazione di un antenato non è determinabile nega, invece di proseguire alla cieca.
    private func resolveSymlinkedAncestors(_ root: String) -> Step<String> {
        var current = root

        for _ in 0..<Self.maxSymlinkResolutions {
            var substituted: String?
            var ancestor: String? = current

            while let candidate = ancestor {
                if links.isSymbolicLink(candidate) {
                    guard let target = links.resolveLinkTarget(candidate) else {
                        return .failure(.deny(
                            String(localized: "la root o un suo antenato è un collegamento simbolico la cui destinazione non è determinabile: \(candidate)", bundle: .module),
                            current))
                    }
                    // `candidate` è un prefisso in byte di `current` (lo produce PathText.parent): il taglio
                    // avviene in byte UTF-8, così un separatore che segue uno scalare "Prepend" non va perso.
                    let suffix = current.utf8.count > candidate.utf8.count ? String(decoding: current.utf8.dropFirst(candidate.utf8.count), as: UTF8.self) : ""
                    substituted = PathText.trimmingTrailingSlashes(target) + suffix
                    break
                }
                ancestor = PathText.parent(candidate)
            }

            guard let next = substituted else { return .success(current) }
            current = next
        }

        return .failure(.deny(String(localized: "troppi collegamenti simbolici annidati mentre si risolveva la root: \(root)", bundle: .module)))
    }

    private func storedForm(_ path: String) -> Result<String, FileSystemError> {
        Self.storedForm(path, in: fileSystem)
    }

    /// Il percorso come lo registra il filesystem: quello dell'antenato più profondo che esiste,
    /// `path` compreso, seguito dai componenti che mancano, presi dal testo. Un elemento sparito
    /// dopo la scansione resta verificabile, e la cancellazione che segue lo segnala «non
    /// trovato» come prima. Si risale solo con `climbableErrors`. `path` è canonico.
    private static func storedForm(_ path: String, in fileSystem: any FileSystem) -> Result<String, FileSystemError> {
        var existing = path
        var missing: [String] = []
        while true {
            do {
                let stored = try fileSystem.storedPath(existing)
                return .success(missing.reversed().reduce(stored) { PathText.join($0, $1) })
            } catch let error as FileSystemError {
                guard climbableErrors.contains(error.code), let parent = PathText.parent(existing), !parent.isEmpty else {
                    return .failure(error)
                }
                missing.append(PathText.fileName(existing))
                existing = parent
            } catch {
                return .failure(FileSystemError(code: EIO, path: existing))
            }
        }
    }

    private static func isHomeOrDirectChild(_ path: String, of home: String) -> Bool {
        if PathText.equalsIgnoringCase(path, home) { return true }
        guard PathText.hasPrefixIgnoringCase(path, home + "/") else { return false }
        // hasPrefixIgnoringCase garantisce che il prefisso riconosciuto abbia lo stesso numero di scalari di home + "/".
        return !path.unicodeScalars.dropFirst(home.unicodeScalars.count + 1).contains("/")
    }
}
```

Rispetto al Task 4 cambiano:

- la documentazione del tipo e `climbableErrors`;
- `storedHome` e `storedDenyList`, calcolati nell'`init`, che lancia `InvalidConfiguration` se la home non è verificabile o se quella registrata è degenere;
- il blocco dopo la deny-list in `validateRoot`;
- il punto 7 di `validate`;
- il secondo confronto di `pruneReason`;
- `storedForm`;
- `isHomeOrDirectChild`, che diventa `static` con la home come parametro.

Tutto il resto è identico, commenti compresi: controllarlo con `git diff`.

- [ ] **Step 6: Il commento reso falso dalla correzione**

**In `swift/MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift`, sostituire:**

```swift
    // Solo Swift (review del Task 2): la home passata a `live` arriva alla deny-list del `clean` e
    // all'espansore. La home passa da `realpath`: sotto /var, collegamento a /private/var, la
    // deny-list non riconoscerebbe la home (registro, «Candidati a miglioramento»).
```

**con:**

```swift
    // Solo Swift (review del Task 2): la home passata a `live` arriva alla deny-list del `clean` e
    // all'espansore. La home passa da `realpath` perché il test riguarda il passaggio della home,
    // non la sua grafia: dal piano APFS la deny-list riconosce anche una home sotto un collegamento
    // (/var → /private/var), confrontandola nella grafia del disco (spec §12).
```

- [ ] **Step 7: Verificare**

```bash
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors --filter PathGuardTests 2>&1 | grep -E '✘|Test run with|(^|: )(warning|error): ')
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')
git diff --stat
```

Expected: `Test run with 58 tests in 1 suite passed`; poi `Test run with 172 tests in 21 suites passed` e `Test run with 536 tests in 48 suites passed`, nessun avviso. `git diff --stat` elenca solo i quattro file modificati del task (il doppio è nuovo e non tracciato).

- [ ] **Step 8: Commit**

```bash
git add swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Support/AliasingFileSystem.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Safety/PathGuardTests.swift \
    swift/MjmCleanerKit/Tests/CleanerCoreTests/Integration/RealFileSystemCleanupTests.swift \
    swift/MjmCleanerKit/Tests/CleanerFeaturesTests/AppEnvironmentTests.swift
git commit -F - <<'MSG'
fix(swift): check the deny-list against the path as APFS stores it

A name that APFS folds onto a protected folder (U+212A for "k", "ſ" for
"s", "ß" for "ss", NFD for NFC) passed the textual deny-list and the
kernel resolved it to the protected folder. The guard now repeats the
deny-list and the depth rule on the stored path, after every textual
check, against a deny-list built on the stored home.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -1
```

Expected: il commit con il trailer.

---

### Task 6: verifica finale e registro di parità

Nessun codice nuovo. Si verificano la suite, la build dell'app, i vincoli e i confini; poi il registro di parità registra le prove nuove, la differenza voluta e i due candidati chiusi.

**Files:**
- Modify: `docs/superpowers/porting/2026-10-13-parity.md`

**Interfaces:**
- Consumes: i Task 1–5.
- Produces: nessuna API.

- [ ] **Step 1: Suite e app**

```bash
(cd swift/MjmCleanerKit && swift test -Xswiftc -warnings-as-errors 2>&1 | grep -E 'Test run with|(^|: )(warning|error): ')
xcodebuild -project swift/MjmCleaner.xcodeproj -scheme MjmCleaner -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "${TMPDIR:-/tmp}/mjm-cleaner-build" build \
    > "${TMPDIR:-/tmp}/mjm-cleaner-build.log" 2>&1
grep -E '\*\* BUILD (SUCCEEDED|FAILED) \*\*' "${TMPDIR:-/tmp}/mjm-cleaner-build.log"
grep -E '(^|: )(warning|error): ' "${TMPDIR:-/tmp}/mjm-cleaner-build.log" || echo "nessuna diagnostica"
```

Expected: `Test run with 172 tests in 21 suites passed` e `Test run with 536 tests in 48 suites passed`, nessun avviso; `** BUILD SUCCEEDED **` e `nessuna diagnostica`. L'app non si avvia: la correzione è nel package, e l'app vera senza `-MJMDemo` non va mai lanciata.

- [ ] **Step 2: Vincoli e confini**

```bash
git diff --name-only main...HEAD
git diff main...HEAD -- swift/MjmCleanerKit/Sources swift/MjmCleanerKit/Tests | grep -E '^\+' | grep -E 'try!|as!' || echo "nessuna violazione"
git diff main...HEAD -- swift/MjmCleanerKit/Sources swift/MjmCleanerKit/Tests | grep -E '^\+' | grep -E '[A-Za-z0-9_\)\]]!([^=]|$)' || echo "nessun forced unwrap"
git diff --name-only main...HEAD -- src tests '*.xcstrings'
grep -c 'non verificabile sul filesystem' swift/MjmCleanerKit/Sources/CleanerCore/Safety/PathGuard.swift
```

Expected:

- il primo comando elenca esattamente 20 file:
  - lo spike e la spec;
  - i 3 file del Core (`FileSystem`, `LocalFileSystem`, `PathGuard`) e `AppEnvironment.swift`;
  - 11 file di test del Core già esistenti: i 9 con costruzioni del `PathGuard`, `InMemoryFileSystem` e `ForwardingFileSystem`;
  - i due nuovi (`StoredPathTests.swift`, `AliasingFileSystem.swift`) e `AppEnvironmentTests.swift`.

  Il registro di parità arriva nello Step 4;
- «nessuna violazione» e «nessun forced unwrap». Il secondo controllo può segnalare un `!` dentro un commento o una stringa: controllare ogni riga;
- il quarto comando non stampa nulla;
- l'ultimo stampa `3`: i messaggi di `validate`, `pruneReason` e `validateRoot` (quello dell'`init` dice «non è verificabile»).

- [ ] **Step 3: Rileggere la correzione contro la spec**

Aprire `PathGuard.swift` accanto alla spec §12 emendata e controllare punto per punto:

- il punto 7 di `validate` viene dopo il punto 6;
- `validateRoot` confronta il registrato solo dopo `recursiveDeniedReason` testuale;
- `pruneReason` confronta il testo prima del registrato;
- `storedForm` risale solo con i quattro errno;
- `canonicalPathValidated` resta il testo in ogni ramo.

- [ ] **Step 4: Registro di parità**

Sostituire `AAAA-MM-GG` con la data di oggi (`date +%F`).

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
Spec: `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` §9.3.
```

**con:**

```markdown
Piano APFS completato il AAAA-MM-GG: la deny-list e la profondità minima si applicano anche al percorso come lo registra il filesystem (`FileSystem.storedPath`, spec §12 emendata, spike `docs/superpowers/spikes/2026-10-16-apfs-nome-canonico.md`); 22 test solo Swift in più, 27 mutazioni di `PathGuard` e `LocalFileSystem` tutte uccise, suite Swift verde (536 + 172 test).

Spec: `docs/superpowers/specs/2026-10-13-swift-native-port-design.md` §9.3.
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Safety/PathGuardTests.cs | 39 (13) | Safety/PathGuardTests.swift | 45 (18) | 1 | «`ShouldPrune(path, out reason)` → `pruneReason(_:) -> String?`»; 39 portati + 6 solo-Swift sulla semantica Unicode (5 casi in più nei due test parametrici) |
```

**con:**

```markdown
| Safety/PathGuardTests.cs | 39 (13) | Safety/PathGuardTests.swift | 58 (34) | 1, APFS | «`ShouldPrune(path, out reason)` → `pruneReason(_:) -> String?`»; 39 portati + 6 solo-Swift sulla semantica Unicode (5 casi in più nei due test parametrici) + 13 solo-Swift del piano APFS (16 casi parametrici) sul percorso registrato, con il doppio `AliasingFileSystem`. Coprono: elemento e root con un nome che APFS equipara a una cartella protetta (U+212A, ſ, ß); profondità e voci esatte sulla grafia del disco; destinazione di un collegamento scritta in un'altra grafia; root registrata come `/`; potatura; errori non verificabili negati e risalita con ENOENT, ENOTDIR, EACCES ed EPERM; componenti mancanti giudicati nel loro ordine; home sotto un collegamento; home non verificabile o degenere; motivi dei rifiuti testuali invariati. Le costruzioni passano `fileSystem: InMemoryFileSystem()` |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Platform/FileSystemVolumeTests.swift | 6 | spazio libero del volume (`statfs`, come `DriveInfo.AvailableFreeSpace`) e data di creazione (`st_birthtimespec`) su disco reale, nel filesystem in memoria e nell'inoltro |
```

**con:**

```markdown
| Platform/FileSystemVolumeTests.swift | 6 | spazio libero del volume (`statfs`, come `DriveInfo.AvailableFreeSpace`) e data di creazione (`st_birthtimespec`) su disco reale, nel filesystem in memoria e nell'inoltro |
| Platform/StoredPathTests.swift | 7 | piano APFS: `storedPath` (`getattrlist`, `ATTR_CMN_FULLPATH`, `FSOPT_NOFOLLOW`) su disco reale con le misure dello spike. Coprono: nomi nella grafia del disco (U+212A, ſ, maiuscole, ß, NFC cercato in NFD; confronto per byte); antenati collegati risolti e ultimo collegamento non seguito; collegamento fisico; radice e home con i firmlink; errno ENOENT, ENOTDIR, EACCES, ELOOP, ENAMETOOLONG; filesystem in memoria e inoltro |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Integration/RealFileSystemCleanupTests.swift | 11 | integrazione scansione → pulizia → diario e log su filesystem reale; dal 2026-10-15 misura e cancellazione di una cartella più profonda dello stack e un collegamento a cartella non accreditato; dal 2026-10-16 le tre visite dello scanner su un albero più profondo dello stack (thread da 64 KB; matchingDirs anche sul pool cooperativo, tramite `ScanEngine`) |
```

**con:**

```markdown
| Integration/RealFileSystemCleanupTests.swift | 13 | integrazione scansione → pulizia → diario e log su filesystem reale; dal 2026-10-15 misura e cancellazione di una cartella più profonda dello stack e un collegamento a cartella non accreditato; dal 2026-10-16 le tre visite dello scanner su un albero più profondo dello stack (thread da 64 KB; matchingDirs anche sul pool cooperativo, tramite `ScanEngine`); dal piano APFS un elemento scritto `Des\u{212A}top` che non viene cancellato e `Documents` protetta con una home sotto /var |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, sostituire:**

```markdown
| Semantica delle stringhe di percorso | unità UTF-16, `OrdinalIgnoreCase` | byte UTF-8 per separatori e punti; ripiegamento per scalare a lunghezza invariata; test solo-Swift in PathGuardTests/PathTextTests/SimpleGlobTests | equivalente a OrdinalIgnoreCase di .NET 10 (confronto esaustivo sugli scalari nella review del Task 4; ı, ſ e U+16EA0–U+16EDF esclusi) |
```

**con:**

```markdown
| Semantica delle stringhe di percorso | unità UTF-16, `OrdinalIgnoreCase` | byte UTF-8 per separatori e punti; ripiegamento per scalare a lunghezza invariata; test solo-Swift in PathGuardTests/PathTextTests/SimpleGlobTests | equivalente a OrdinalIgnoreCase di .NET 10 (confronto esaustivo sugli scalari nella review del Task 4; ı, ſ e U+16EA0–U+16EDF esclusi) |
| Deny-list e profondità minima del `PathGuard` | solo sul testo, con `OrdinalIgnoreCase`. Un nome che APFS equipara a una cartella protetta (U+212A, ſ, ß, NFD: `~/Des\u{212A}top/x`) la supera e il kernel lo risolve nella cartella protetta. Con una home sotto un collegamento (/var → /private/var) la deny-list non riconosce i percorsi che `validateRoot` ha già risolto | ripetute sul percorso registrato dal filesystem (`FileSystem.storedPath`), dopo ogni controllo testuale, con una deny-list costruita sulla home registrata. Per i componenti che non esistono vale l'antenato più profondo, risalendo solo con ENOENT, ENOTDIR, EACCES ed EPERM; ogni altro errore nega con «percorso non verificabile sul filesystem: …» o «root non verificabile sul filesystem: …». `PathGuard.init` riceve `fileSystem:` e lancia se la home non è verificabile | voluta (spec §12 emendata, piano APFS): cambiano solo verdetti che il C# permetteva |
```

**In `docs/superpowers/porting/2026-10-13-parity.md`, cancellare la riga:**

```markdown
| APFS ripiega più di OrdinalIgnoreCase (U+212A→k, ſ→s) | un elemento manipolato "~/Des\u{212A}top/x" con la stessa root supera la deny-list testuale e APFS lo risolve in ~/Desktop (uguale nel C#) | confrontare la deny-list sul percorso risolto dal filesystem (realpath/F_GETPATH) oltre che sul testo |
```

La riga sparisce del tutto, a capo compreso: è chiusa dal piano APFS e ora sta nelle differenze.

**In `docs/superpowers/porting/2026-10-13-parity.md`, cancellare la riga:**

```markdown
| Home che contiene un collegamento simbolico | `PathGuard` risolve la root, la deny-list no: con una home sotto un collegamento (es. /var → /private/var) la deny-list non riconosce i percorsi della home (uguale al C#); `AppEnvironment.live` riceve la home così com'è | passare la home da `realpath` in `live`, o confrontare la deny-list sul percorso risolto |
```

Anche questa sparisce del tutto: la chiude la deny-list sulla home registrata.

Dopo le due cancellazioni la tabella dei candidati non deve avere righe vuote al suo interno: controllare con `sed -n '/^## Candidati/,$p' docs/superpowers/porting/2026-10-13-parity.md`.

- [ ] **Step 5: Commit**

```bash
grep -c 'Des\\u{212A}top' docs/superpowers/porting/2026-10-13-parity.md
git add docs/superpowers/porting/2026-10-13-parity.md
git commit -F - <<'MSG'
docs(swift): record the APFS fix in the parity ledger and close plan APFS

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
git log --format='%h %s | %(trailers:key=Co-Authored-By,valueonly)' -6
git status --short
```

Expected: `2` (le righe di `RealFileSystemCleanupTests` e della differenza nuova). Poi il commit, e i sei commit del piano, ciascuno con il trailer. `git status --short` mostra solo ciò che c'era prima del piano: `?? .zed/`, `?? mjm-cleaner-ui-handoff.md` e i tre `Localizable.xcstrings`, se ci sono.

---

## Mutazioni verificate in stesura

Copia scratch con il codice finale, filtro `PathGuardTests|StoredPathTests|RealFileSystemCleanupTests`. Ogni riga è una sostituzione testuale nel file indicato. I revisori del Task 3 (righe M21–M24) e del Task 5 (M1–M20) le riprovano e ne aggiungono altre loro.

| # | File | Mutazione | Uccisa da |
|---|---|---|---|
| M1 | PathGuard | `validate` senza la deny-list registrata | `deniesAnItemWhoseStoredPathIsProtected`, `deniesAnItemWhoseStoredPathIsTheHome`, `missingComponentsAreJudged…` |
| M2 | PathGuard | `validate` senza la profondità registrata | `deniesADirectChildOfTheHomeReachedThroughAnAlias`, `theStoredHomeProtectsAHomeUnderALink` |
| M3 | PathGuard | `validate` con `denyList` al posto di `storedDenyList` | `theStoredHomeProtectsAHomeUnderALink` (sopravviveva prima del controllo su `Documents/x`) |
| M4 | PathGuard | profondità registrata sulla home testuale | `theStoredHomeProtectsAHomeUnderALink` |
| M5 | PathGuard | `validate` con `recursiveDeniedReason` sul registrato | `deniesAnItemWhoseStoredPathIsTheHome` |
| M6 | PathGuard | `validateRoot` senza il confronto registrato | `deniesAnItemWhoseStoredPathIsProtected`, `validateRootDeniesALinkTargetSpelledWithAnAlias`, `theStoredHomeProtectsAHomeUnderALink` |
| M7 | PathGuard | `validateRoot` senza il controllo di `/` | `validateRootDeniesARootStoredAsTheFilesystemRoot` |
| M8 | PathGuard | `pruneReason` senza il confronto registrato | `pruneReasonPrunesABranchWhoseStoredPathIsProtected` |
| M9a–d | PathGuard | non risale con ENOENT / ENOTDIR / EACCES / EPERM | quasi tutta la suite (ENOENT); `missingOrHiddenComponentsClimbToTheirAncestor` (gli altri tre) |
| M10 | PathGuard | risale con ogni errore | `anUnverifiableStoredPathIsDenied`, `constructorRejectsAHomeThatTheFilesystemCannotVerify` |
| M11–M13 | PathGuard | errore non verificabile permesso in `validate` / `validateRoot` / `pruneReason` | `anUnverifiableStoredPathIsDenied` |
| M14 | PathGuard | `storedForm` perde i componenti mancanti | quasi tutta la suite |
| M15 | PathGuard | componenti mancanti in ordine inverso | `missingComponentsAreJudged…` e altri sei |
| M16 | PathGuard | su un errore da cui si risale restituisce il testo intero | `missingComponentsAreJudged…` |
| M17 | PathGuard | `init` con la home testuale e la deny-list testuale | i due test di integrazione, `theStoredHomeProtectsAHomeUnderALink`, `constructorRejectsADegenerateStoredHome` |
| M18 | PathGuard | `init` che accetta una home non verificabile | `constructorRejectsAHomeThatTheFilesystemCannotVerify` |
| M19 | PathGuard | `init` senza il controllo di canonicità della home registrata | `constructorRejectsADegenerateStoredHome` (sopravviveva prima del caso `/Users/tester/../altro`) |
| M20 | PathGuard | confronto registrato prima del punto 5 | `textualRefusalsKeepTheirReason` |
| M21 | LocalFileSystem | senza `FSOPT_NOFOLLOW` | `storedPathResolvesLinkedAncestorsButNotTheLastComponent` e due test di integrazione sui collegamenti |
| M22 | LocalFileSystem | percorso con il terminatore | quasi tutti i test di integrazione |
| M23 | LocalFileSystem | `ATTR_CMN_NAME` al posto di `ATTR_CMN_FULLPATH` | quasi tutti i test di integrazione |
| M24 | LocalFileSystem | errno fisso `ENOENT` | `storedPathReportsTheErrnoOfTheLookup` |

---

## Dopo il piano APFS

- A fine esecuzione il ledger SDD si copia in `docs/superpowers/decisions/<data>-registro-decisioni-swift-piano-apfs.md` (commit a parte, come per i piani 4a e 4b); poi `superpowers:finishing-a-development-branch`.
- **Piano 5**: collaudo fianco a fianco con l'app C# (§9.4), workflow di release (§10.2), rimozione del C# (§10.3). Restano da decidere lì il bundle id distinto per il Debug, il nome del bundle, `ONLY_ACTIVE_ARCH`, la prova con VoiceOver e i gruppi Docker sotto la piega. Il workflow C# «Build macOS release» è disattivato su GitHub dal 2026-10-16. Nel collaudo l'app C# e l'app Swift possono dare esclusioni diverse solo per i nomi che APFS ripiega più del C#: in un'analisi normale lo scanner elenca i nomi del disco e non ne produce.
- I candidati a miglioramento rimasti nel registro di parità restano non applicati (spec §12).
