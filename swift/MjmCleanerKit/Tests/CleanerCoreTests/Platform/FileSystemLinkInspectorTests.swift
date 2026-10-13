import Foundation
import Testing
@testable import CleanerCore

struct FileSystemLinkInspectorTests {
    private let links = FileSystemLinkInspector()

    @Test func recognisesLinksIncludingBrokenOnes() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let file = try tmp.file("f.txt")
        #expect(links.isSymbolicLink(try tmp.symlink("l", to: file)))
        #expect(links.isSymbolicLink(try tmp.symlink("rotto", to: tmp.path + "/manca")))
        #expect(!links.isSymbolicLink(file))
        #expect(!links.isSymbolicLink(tmp.path + "/assente"))
    }

    @Test func resolvesRelativeChainWithTextualNormalizationLikeDotNet() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        try tmp.directory("dir")
        let name = PathText.fileName(tmp.path)
        let first = try tmp.symlink("rel", to: "../\(name)/dir/../dir")
        let second = try tmp.symlink("catena", to: first)
        #expect(links.resolveLinkTarget(first) == tmp.path + "/dir")
        #expect(links.resolveLinkTarget(second) == tmp.path + "/dir")
    }

    @Test func brokenLinkResolvesToItsDestinationPath() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        let broken = try tmp.symlink("rotto", to: tmp.path + "/manca")
        #expect(links.resolveLinkTarget(broken) == tmp.path + "/manca")
    }

    @Test func nonLinkAndCycleResolveToNil() throws {
        let tmp = try TemporaryDirectory(); defer { tmp.remove() }
        #expect(links.resolveLinkTarget(try tmp.file("f.txt")) == nil)
        try tmp.symlink("a", to: tmp.path + "/b")
        try tmp.symlink("b", to: tmp.path + "/a")
        #expect(links.resolveLinkTarget(tmp.path + "/a") == nil)
    }
}
