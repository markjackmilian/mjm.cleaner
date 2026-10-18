import Testing
@testable import CleanerCore

struct PathExpanderTests {
    private func create() throws -> PathExpander {
        try PathExpander(homeDirectory: "/Users/tester", tempDirectory: "/var/folders/ab/xyz/T/")
    }

    @Test func expandsTildePrefix() throws {
        #expect(try create().expand("~/Library/Caches") == "/Users/tester/Library/Caches")
    }

    @Test func expandsBareTilde() throws {
        #expect(try create().expand("~") == "/Users/tester")
    }

    @Test func expandsTmpdirVariable() throws {
        #expect(try create().expand("$TMPDIR") == "/var/folders/ab/xyz/T")
    }

    @Test func leavesAbsolutePathUnchanged() throws {
        #expect(try create().expand("/Library/Caches") == "/Library/Caches")
    }

    @Test func trimsTrailingSlash() throws {
        #expect(try create().expand("~/Downloads/") == "/Users/tester/Downloads")
    }

    @Test func doesNotExpandTildeOfAnotherUser() throws {
        #expect(try create().expand("~altro/Documents") == "~altro/Documents")
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///"] as [String?])
    func constructorRejectsInvalidHomeDirectory(homeDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) {
            try PathExpander(homeDirectory: homeDirectory, tempDirectory: "/var/folders/ab/xyz/T")
        }
    }

    @Test(arguments: [nil, "", "   ", "relative/path", "/", "//", "///"] as [String?])
    func constructorRejectsInvalidTempDirectory(tempDirectory: String?) {
        #expect(throws: InvalidConfiguration.self) {
            try PathExpander(homeDirectory: "/Users/tester", tempDirectory: tempDirectory)
        }
    }
}
