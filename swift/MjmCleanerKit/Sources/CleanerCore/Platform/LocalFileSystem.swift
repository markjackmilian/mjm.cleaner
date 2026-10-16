import Darwin
import Foundation

/// Implementazione reale su chiamate POSIX. Non segue mai i collegamenti simbolici, salvo dove
/// la semantica .NET replicata lo richiede (`directoryExists`, `fileExists`).
public struct LocalFileSystem: FileSystem {
    public init() {}

    public func directoryExists(_ path: String) -> Bool {
        var status = stat()
        return Self.statFollowingLinks(path, &status) && (status.st_mode & S_IFMT) == S_IFDIR
    }

    public func fileExists(_ path: String) -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else { return false }
        guard (status.st_mode & S_IFMT) == S_IFLNK else {
            return (status.st_mode & S_IFMT) != S_IFDIR
        }
        // Collegamento: conta la destinazione; se è irraggiungibile .NET risponde comunque vero.
        var target = stat()
        guard Self.statFollowingLinks(path, &target) else { return true }
        return (target.st_mode & S_IFMT) != S_IFDIR
    }

    public func contentsOfDirectory(_ path: String) throws -> [String] {
        guard let directory = opendir(path) else { throw FileSystemError(code: errno, path: path) }
        defer { closedir(directory) }

        var entries: [String] = []
        while true {
            // `errno` si azzera a ogni chiamata: una libreria può lasciarlo non nullo anche con una
            // lettura riuscita, e senza questo azzeramento ne seguirebbe un errore spurio.
            errno = 0
            guard let entry = readdir(directory) else { break }
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafeBytes(of: entry.pointee.d_name) { bytes in
                String(decoding: bytes.prefix(length), as: UTF8.self)
            }
            if name != "." && name != ".." {
                entries.append(PathText.join(path, name))
            }
        }
        // Lettura subito dopo l'ultimo `readdir`: `errno` è valido solo qui, prima di altre chiamate.
        let failure = errno
        if failure != 0 { throw FileSystemError(code: failure, path: path) }
        return entries.sorted()
    }

    public func itemInfo(_ path: String) throws -> FileItemInfo {
        var status = stat()
        guard lstat(path, &status) == 0 else { throw FileSystemError(code: errno, path: path) }

        let kind: FileItemKind
        switch status.st_mode & S_IFMT {
        case S_IFREG: kind = .file
        case S_IFDIR: kind = .directory
        case S_IFLNK: kind = .symbolicLink
        default: kind = .other
        }

        return FileItemInfo(
            kind: kind,
            size: Int64(status.st_size),
            lastWrite: Self.date(status.st_mtimespec),
            lastAccess: Self.date(status.st_atimespec),
            creation: Self.date(status.st_birthtimespec))
    }

    public func deleteFile(_ path: String) throws {
        guard unlink(path) != 0 else { return }
        let code = errno
        if code != ENOENT { throw FileSystemError(code: code, path: path) }
    }

    public func deleteDirectoryRecursively(_ path: String) throws {
        // Senza normalizzazione, "collegamento/" farebbe risolvere `lstat` al bersaglio (come
        // "collegamento/."): il controllo sotto vedrebbe una cartella e cancellerebbe il suo
        // contenuto. Il "/" finale si toglie prima; la radice "/" resta "/", una stringa vuota
        // resta vuota e fallisce con ENOENT come prima.
        let trimmed = PathText.trimmingTrailingSlashes(path)
        let target = trimmed.isEmpty && path.utf8.first == UInt8(ascii: "/") ? "/" : trimmed

        var status = stat()
        guard lstat(target, &status) == 0 else { throw FileSystemError(code: errno, path: target) }
        if (status.st_mode & S_IFMT) == S_IFLNK {
            // Come .NET: su un collegamento a cartella si rimuove il collegamento, mai il contenuto
            // della destinazione.
            if unlink(target) != 0 { throw FileSystemError(code: errno, path: target) }
            return
        }

        var firstError: FileSystemError?
        removeTree(target, firstError: &firstError)
        if let firstError { throw firstError }
    }

    public func readData(_ path: String) throws -> Data {
        let descriptor = open(path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { throw FileSystemError(code: errno, path: path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            return try handle.readToEnd() ?? Data()
        } catch {
            throw FileSystemError(code: EIO, path: path)
        }
    }

    public func writeData(_ path: String, _ data: Data) throws {
        let temporary = path + ".tmp-" + UUID().uuidString
        try writeAll(temporary, data, flags: O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC)
        if rename(temporary, path) != 0 {
            let code = errno
            unlink(temporary)
            throw FileSystemError(code: code, path: path)
        }
    }

    public func appendData(_ path: String, _ data: Data) throws {
        try writeAll(path, data, flags: O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC)
    }

    public func createDirectory(_ path: String) throws {
        if directoryExists(path) { return }
        if let parent = PathText.parent(path), !parent.isEmpty, parent != path {
            try createDirectory(parent)
        }
        if mkdir(path, 0o755) != 0 {
            let code = errno
            if code == EEXIST && directoryExists(path) { return }
            throw FileSystemError(code: code, path: path)
        }
    }

    public func availableFreeSpace(forVolumeContaining path: String) throws -> Int64 {
        var volume = statfs()
        guard statfs(path, &volume) == 0 else { throw FileSystemError(code: errno, path: path) }
        // Come DriveInfo.AvailableFreeSpace su Unix: blocchi disponibili ai processi senza
        // privilegi per la dimensione del blocco. `volumeAvailableCapacityForImportantUsage`
        // aggiungerebbe lo spazio eliminabile e darebbe un numero diverso dall'app C#.
        let (bytes, overflow) = Int64(volume.f_bsize).multipliedReportingOverflow(by: Int64(clamping: volume.f_bavail))
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

        return try Self.parseStoredPathResponse(buffer, path: path)
    }

    static func parseStoredPathResponse(_ buffer: [UInt8], path: String) throws -> String {
        let headerSize = MemoryLayout<UInt32>.size
        let referenceSize = MemoryLayout<attrreference_t>.size
        guard buffer.count >= headerSize + referenceSize else { throw FileSystemError(code: EIO, path: path) }

        let reference = buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: headerSize, as: attrreference_t.self) }
        let offset = Int(reference.attr_dataoffset)
        let length = Int(reference.attr_length)
        let (start, startOverflow) = headerSize.addingReportingOverflow(offset)
        let (end, endOverflow) = start.addingReportingOverflow(length)
        // Un riferimento fuori dal buffer o senza terminatore è una risposta inattesa, non un percorso.
        guard !startOverflow, !endOverflow, length > 1, start >= headerSize + referenceSize,
              end <= buffer.count, buffer[end - 1] == 0 else {
            throw FileSystemError(code: EIO, path: path)
        }
        return String(decoding: buffer[start..<(end - 1)], as: UTF8.self)
    }

    // MARK: - Privati

    /// Elimina tutto ciò che può sotto `root`, poi `root` stesso; ricorda solo il primo errore,
    /// che è quello che .NET avrebbe lanciato.
    ///
    /// Iterativa, con una pila esplicita: la versione ricorsiva scendeva di una chiamata per livello
    /// e una cartella di qualche centinaio di livelli esauriva lo stack del thread (512 KB nei thread
    /// di Swift Concurrency: crash del 2026-10-15). L'ordine delle operazioni, e quindi il primo
    /// errore, resta quello della ricorsione: in profondità, i figli nell'ordine di
    /// `contentsOfDirectory`, ogni cartella rimossa dopo il suo contenuto; una cartella che non si
    /// legge registra l'errore e resta al suo posto.
    private func removeTree(_ root: String, firstError: inout FileSystemError?) {
        // Le cartelle aperte, dalla più esterna: il percorso da rimuovere alla fine e i figli ancora
        // da visitare.
        var open: [(path: String, children: IndexingIterator<[String]>)] = []
        var entering: String? = root

        while true {
            if let directory = entering {
                entering = nil
                do {
                    open.append((directory, try contentsOfDirectory(directory).makeIterator()))
                } catch let error as FileSystemError {
                    if firstError == nil { firstError = error }
                } catch {}
            }

            guard var current = open.popLast() else { return }
            guard let child = current.children.next() else {
                if rmdir(current.path) != 0, firstError == nil {
                    firstError = FileSystemError(code: errno, path: current.path)
                }
                continue
            }
            open.append(current)

            var status = stat()
            guard lstat(child, &status) == 0 else {
                if firstError == nil { firstError = FileSystemError(code: errno, path: child) }
                continue
            }
            if (status.st_mode & S_IFMT) == S_IFDIR {
                entering = child
            } else if unlink(child) != 0, firstError == nil {
                firstError = FileSystemError(code: errno, path: child)
            }
        }
    }

    private func writeAll(_ path: String, _ data: Data, flags: Int32) throws {
        let descriptor = open(path, flags, 0o644)
        guard descriptor >= 0 else { throw FileSystemError(code: errno, path: path) }
        defer { close(descriptor) }

        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                let written = write(descriptor, base + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw FileSystemError(code: errno, path: path)
                }
                offset += written
            }
        }
    }

    /// `stat(2)`, che segue i collegamenti. In Swift il nome `stat` indica anche la struct, e
    /// `Darwin.stat(path, &buffer)` si risolve sul suo inizializzatore: `fstatat` con flag 0 è la
    /// stessa chiamata senza ambiguità.
    private static func statFollowingLinks(_ path: String, _ status: inout stat) -> Bool {
        fstatat(AT_FDCWD, path, &status, 0) == 0
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
