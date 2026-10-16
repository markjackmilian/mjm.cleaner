# Spike — nome canonico di un percorso su APFS

**Data:** 2026-10-16 (prima misura, durante la stesura del piano APFS); riverificata il 2026-10-16 (Task 1 del piano, output in Appendice B).
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

Componente mancante: ENOENT. Sotto un file: ENOTDIR. Dentro una cartella senza permesso di attraversamento: EACCES (la cartella stessa si legge). Attraverso un collegamento interrotto: ENOENT (il collegamento stesso si legge). Ciclo di collegamenti: ELOOP. Risoluzione oltre MAXPATHLEN: ENAMETOOLONG. Per il percorso costruito di almeno 1000 byte, la sonda controlla che il risultato di `ATTR_CMN_FULLPATH` inizi con `<base>/lungo/a/a`; il controllo col prefisso riesce, ma non confronta l'intero percorso. Un percorso relativo si risolve rispetto alla cartella corrente.

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

## Appendice A — sorgente della sonda

```swift
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
```

## Appendice B — output del 2026-10-16

```text
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

== 8. Costo (variabile)
10 000 getattrlist FULLPATH: 0.013238458 seconds; 10 000 lstat: 0.010548083 seconds [ok]
```
