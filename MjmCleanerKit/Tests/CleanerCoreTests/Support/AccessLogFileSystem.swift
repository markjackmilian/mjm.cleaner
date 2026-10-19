import CleanerCore

/// Registra i percorsi letti con `fileExists` e `itemInfo` (da cui passa anche `fileLength`):
/// prova che un'operazione non ha nemmeno guardato il disco.
final class AccessLogFileSystem: ForwardingFileSystem, @unchecked Sendable {
    let paths = Recorder<String>()

    override func fileExists(_ path: String) -> Bool {
        paths.append(path)
        return super.fileExists(path)
    }

    override func itemInfo(_ path: String) throws -> FileItemInfo {
        paths.append(path)
        return try super.itemInfo(path)
    }
}
