import Darwin
import Testing
@testable import CleanerCore

private struct UnexpectedStoredPathError: Error {}

/// `storedPath` lancia un errore che non viene dal filesystem su un percorso esatto.
private final class ForeignErrorFileSystem: ForwardingFileSystem, @unchecked Sendable {
    private let path: String

    init(path: String) {
        self.path = path
        super.init(InMemoryFileSystem())
    }

    override func storedPath(_ path: String) throws -> String {
        if path == self.path { throw UnexpectedStoredPathError() }
        return try super.storedPath(path)
    }
}

/// `FileSystem.storedForm`, la risalita condivisa da `PathGuard` ed `ExcludedFolders`: si risale
/// all'antenato esistente più profondo e si ricompone il resto dal testo, solo con gli errori per
/// cui nemmeno il kernel raggiunge l'oggetto.
struct StoredFormTests {
    private static let alias = "/Users/tester/Des\u{212A}top"
    private static let stored = "/Users/tester/Desktop"

    @Test(arguments: [ENOENT, ENOTDIR, EACCES, EPERM])
    func climbsToTheDeepestAncestorTheDiskSpells(code: Int32) {
        let fs = AliasingFileSystem(aliases: [(Self.alias, Self.stored)], failures: [("\(Self.alias)/nuovo/x", code)])

        #expect(fs.storedForm("\(Self.alias)/nuovo/x") == .success("\(Self.stored)/nuovo/x"))
    }

    /// La risalita si ferma al primo errore che non è fra quelli previsti, anche dopo un ENOENT.
    @Test(arguments: [EIO, ELOOP, ENAMETOOLONG])
    func anyOtherErrorIsTheResult(code: Int32) {
        let fs = AliasingFileSystem(
            aliases: [(Self.alias, Self.stored)], failures: [("\(Self.alias)/nuovo/x", ENOENT), ("\(Self.alias)/nuovo", code)])

        #expect(fs.storedForm("\(Self.alias)/nuovo/x") == .failure(FileSystemError(code: code, path: "\(Self.alias)/nuovo")))
    }

    /// Nemmeno la radice si legge: non c'è un antenato da cui ricomporre il percorso.
    @Test func reachingTheRootWithoutSuccessIsTheResult() {
        let fs = AliasingFileSystem(failures: [("/", ENOENT)])

        #expect(fs.storedForm("/Users/tester/x") == .failure(FileSystemError(code: ENOENT, path: "/")))
    }

    @Test func anErrorThatIsNotFromTheFileSystemBecomesEIOOnItsPath() {
        let fs = ForeignErrorFileSystem(path: "/Users/tester")

        #expect(fs.storedForm("/Users/tester/x") == .failure(FileSystemError(code: EIO, path: "/Users/tester")))
    }
}
