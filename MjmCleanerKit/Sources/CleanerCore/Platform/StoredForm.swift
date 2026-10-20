import Darwin

/// Gli errori di `storedPath` per cui `storedForm` risale all'antenato: il componente non esiste
/// (ENOENT, ENOTDIR) o il suo genitore non si attraversa (EACCES, EPERM). In entrambi i casi
/// nemmeno l'eliminazione raggiunge l'oggetto, perché la ricerca del kernel è la stessa. Ogni
/// altro errore rende il percorso non verificabile.
private let climbableStoredPathErrors: Set<Int32> = [ENOENT, ENOTDIR, EACCES, EPERM]

extension FileSystem {
    /// Il percorso come lo registra il filesystem: quello dell'antenato più profondo che esiste,
    /// `path` compreso, seguito dai componenti che mancano, presi dal testo. Un elemento sparito
    /// dopo la scansione resta verificabile, e la cancellazione che segue lo segnala «non
    /// trovato» come prima. Si risale solo con `climbableStoredPathErrors`: ogni altro errore, o la
    /// radice raggiunta senza successo, è il risultato. Un errore che non viene dal filesystem vale
    /// `EIO` sul percorso dove è avvenuto. Condivisa da `PathGuard` ed `ExcludedFolders`; `path` è
    /// canonico.
    func storedForm(_ path: String) -> Result<String, FileSystemError> {
        var existing = path
        var missing: [String] = []
        while true {
            do {
                let stored = try storedPath(existing)
                return .success(missing.reversed().reduce(stored) { PathText.join($0, $1) })
            } catch let error as FileSystemError {
                guard climbableStoredPathErrors.contains(error.code), let parent = PathText.parent(existing), !parent.isEmpty else {
                    return .failure(error)
                }
                missing.append(PathText.fileName(existing))
                existing = parent
            } catch {
                return .failure(FileSystemError(code: EIO, path: existing))
            }
        }
    }
}
