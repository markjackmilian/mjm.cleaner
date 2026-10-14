import CleanerCore
import Foundation

/// Base dei doppi di guasto: inoltra ogni operazione al filesystem interno. Ogni doppio
/// ridefinisce solo il metodo in cui inietta il guasto (in C# lo faceva `DispatchProxy`).
class ForwardingFileSystem: FileSystem, @unchecked Sendable {
    let inner: any FileSystem

    init(_ inner: any FileSystem) {
        self.inner = inner
    }

    func directoryExists(_ path: String) -> Bool { inner.directoryExists(path) }
    func fileExists(_ path: String) -> Bool { inner.fileExists(path) }
    func contentsOfDirectory(_ path: String) throws -> [String] { try inner.contentsOfDirectory(path) }
    func itemInfo(_ path: String) throws -> FileItemInfo { try inner.itemInfo(path) }
    func deleteFile(_ path: String) throws { try inner.deleteFile(path) }
    func deleteDirectoryRecursively(_ path: String) throws { try inner.deleteDirectoryRecursively(path) }
    func readData(_ path: String) throws -> Data { try inner.readData(path) }
    func writeData(_ path: String, _ data: Data) throws { try inner.writeData(path, data) }
    func appendData(_ path: String, _ data: Data) throws { try inner.appendData(path, data) }
    func createDirectory(_ path: String) throws { try inner.createDirectory(path) }
    func availableFreeSpace(forVolumeContaining path: String) throws -> Int64 {
        try inner.availableFreeSpace(forVolumeContaining: path)
    }
}
