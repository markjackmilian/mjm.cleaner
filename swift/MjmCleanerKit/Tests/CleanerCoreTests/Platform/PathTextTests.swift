import Testing
@testable import CleanerCore

struct PathTextTests {
    @Test(arguments: [
        ("/a/b", "b"), ("/a/b/", ""), ("/", ""), ("nome", "nome"), ("/Users/tester/.ssh", ".ssh"),
    ])
    func fileNameMatchesDotNetGetFileName(path: String, expected: String) {
        #expect(PathText.fileName(path) == expected)
    }

    @Test(arguments: [
        ("/a/b", "/a" as String?), ("/a", "/"), ("/", nil), ("", nil), ("/a/b/", "/a/b"), ("relativo", ""),
    ])
    func parentMatchesDotNetGetDirectoryNameOnUnix(path: String, expected: String?) {
        #expect(PathText.parent(path) == expected)
    }

    @Test(arguments: [
        ("/a", "b", "/a/b"), ("/a/", "b", "/a/b"), ("/a", "/b", "/b"), ("", "b", "b"), ("/a", "", "/a"), ("/", "b", "/b"),
    ])
    func joinMatchesDotNetCombine(base: String, component: String, expected: String) {
        #expect(PathText.join(base, component) == expected)
    }

    @Test(arguments: [("/a/b///", "/a/b"), ("///", ""), ("/a", "/a"), ("", "")])
    func trimmingTrailingSlashesMatchesTrimEnd(path: String, expected: String) {
        #expect(PathText.trimmingTrailingSlashes(path) == expected)
    }

    @Test(arguments: [
        ("/a/./b", "/a/b"), ("/a/b/../c", "/a/c"), ("//a//b//", "/a/b"), ("/../a", "/a"), ("/a/dir/../dir", "/a/dir"), ("/", "/"),
    ])
    func normalizeResolvesDotSegmentsTextually(path: String, expected: String) {
        #expect(PathText.normalize(path) == expected)
    }

    @Test func comparisonsIgnoreCase() {
        #expect(PathText.equalsIgnoringCase("/Users/TESTER", "/users/tester"))
        #expect(!PathText.equalsIgnoringCase("/a", "/ab"))
        #expect(PathText.hasPrefixIgnoringCase("/Users/Tester/Documents", "/users/tester/"))
        #expect(PathText.hasPrefixIgnoringCase("/qualunque", ""))
        #expect(!PathText.hasPrefixIgnoringCase("/a", "/ab"))
    }

    @Test func isSameOrUnderRespectsSegmentBoundaries() {
        #expect(PathText.isSameOrUnder("/Library/Caches", "/library/caches"))
        #expect(PathText.isSameOrUnder("/Library/Caches/x", "/Library/Caches"))
        #expect(!PathText.isSameOrUnder("/Library/CachesExtra", "/Library/Caches"))
    }
}
