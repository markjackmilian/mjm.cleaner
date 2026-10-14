import Darwin
import Foundation
import Testing
@testable import CleanerCore

/// Spazio libero del volume e data di creazione: le due letture che il piano 3 aggiunge a
/// `FileSystem` per `XcodeSizeProbe` (`DriveInfo.AvailableFreeSpace`) e per l'identità delle
/// cartelle Xcode (`DirectoryInfo.CreationTimeUtc`).
struct FileSystemVolumeTests {
    @Test func localFreeSpaceIsStatfsAvailableBlocksOfTheContainingVolume() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let nested = try tmp.directory("a/b")

        let free = try LocalFileSystem().availableFreeSpace(forVolumeContaining: nested)

        var volume = statfs()
        #expect(statfs(tmp.path, &volume) == 0)
        let expected = Int64(volume.f_bsize) * Int64(volume.f_bavail)
        // Lo spazio libero cambia mentre il test gira: basta che le due letture siano vicine.
        #expect(free > 0)
        #expect(abs(free - expected) < 1_073_741_824)
    }

    @Test func localFreeSpaceOfAMissingPathThrowsNotFound() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(throws: FileSystemError(code: ENOENT, path: tmp.path + "/assente")) {
            try LocalFileSystem().availableFreeSpace(forVolumeContaining: tmp.path + "/assente")
        }
    }

    @Test func localCreationIsTheBirthTimeAndDoesNotFollowLaterWrites() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let dir = try tmp.directory("DerivedData/App-abc")
        let before = try LocalFileSystem().itemInfo(dir)
        // Una data futura: impostarne una anteriore alla creazione sposterebbe indietro anche
        // la data di nascita (semantica BSD di utimes).
        let later = Date().addingTimeInterval(86_400)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: dir)

        let after = try LocalFileSystem().itemInfo(dir)
        let birth = try #require(FileManager.default.attributesOfItem(atPath: dir)[.creationDate] as? Date)

        #expect(after.creation == before.creation)
        #expect(abs(after.creation.timeIntervalSince(birth)) < 0.001)
        #expect(abs(after.lastWrite.timeIntervalSince(later)) < 0.001)
    }

    @Test func inMemoryFreeSpaceIsSettableAndMissingPathsThrow() throws {
        let fs = InMemoryFileSystem()
        fs.addDirectory("/Users/tester")
        fs.setAvailableFreeSpace(1234)

        #expect(try fs.availableFreeSpace(forVolumeContaining: "/Users/tester") == 1234)
        #expect(throws: FileSystemError(code: ENOENT, path: "/manca")) {
            try fs.availableFreeSpace(forVolumeContaining: "/manca")
        }
    }

    @Test func inMemoryCreationIsTheFirstStampAndSurvivesSetTimes() throws {
        let fs = InMemoryFileSystem()
        let created = utc(2026, 1, 2)
        fs.addFile("/a/f.bin", size: 1, stamp: created)
        fs.setTimes("/a/f.bin", lastWrite: utc(2026, 3, 4), lastAccess: utc(2026, 3, 4))

        let info = try fs.itemInfo("/a/f.bin")

        #expect(info.creation == created)
        #expect(info.lastWrite == utc(2026, 3, 4))
    }

    @Test func forwardingFileSystemForwardsFreeSpace() throws {
        let inner = InMemoryFileSystem()
        inner.addDirectory("/Users/tester")
        inner.setAvailableFreeSpace(4096)

        #expect(try ForwardingFileSystem(inner).availableFreeSpace(forVolumeContaining: "/Users/tester") == 4096)
    }
}
