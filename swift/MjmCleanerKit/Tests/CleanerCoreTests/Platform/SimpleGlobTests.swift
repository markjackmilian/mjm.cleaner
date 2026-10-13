import Testing
@testable import CleanerCore

struct SimpleGlobTests {
    @Test(arguments: [
        ("*", "qualunque.txt", true),
        ("*", "", true),
        ("bin", "BIN", true),
        ("bin", "binary", false),
        ("*.csproj", "App.CSPROJ", true),
        ("*.csproj", "App.csproj.user", false),
        ("?.txt", "a.txt", true),
        ("?.txt", "ab.txt", false),
        ("a*b*c", "aXXbYYc", true),
        ("a*b*c", "aXXbYY", false),
        ("[ab].txt", "a.txt", false),
        ("[ab].txt", "[ab].txt", true),
        ("", "", true),
        ("", "x", false),
    ])
    func matchesLikeDotNetSimpleExpression(pattern: String, name: String, expected: Bool) {
        #expect(SimpleGlob.matches(pattern, name) == expected)
    }
}
