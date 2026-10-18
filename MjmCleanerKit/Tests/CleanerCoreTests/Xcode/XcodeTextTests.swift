import Darwin
import Testing
@testable import CleanerCore

/// Test solo Swift: le primitive su testo e UUID che sostituiscono `string`, `StringComparison` e
/// `Guid` del C#. I casi riproducono quanto misurato su .NET 10 (vedi «Fatti misurati» del piano 3).
struct XcodeTextTests {
    private static let uuid = "11111111-1111-4111-8111-111111111111"

    @Test(arguments: [
        ("11111111-1111-4111-8111-111111111111", "11111111-1111-4111-8111-111111111111" as String?),
        ("AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
        (" \t11111111-1111-4111-8111-111111111111\n", "11111111-1111-4111-8111-111111111111"),
        ("\u{00A0}11111111-1111-4111-8111-111111111111", "11111111-1111-4111-8111-111111111111"),
        ("11111111111141118111111111111111", nil),
        ("{11111111-1111-4111-8111-111111111111}", nil),
        ("11111111-1111-4111-8111-11111111111", nil),
        ("11111111-1111-4111-8111-11111111111g", nil),
        ("\u{FF11}1111111-1111-4111-8111-111111111111", nil),
        ("+1111111-1111-4111-8111-111111111111", nil),
        ("all", nil),
        ("", nil),
    ])
    func canonicalExactAcceptsOnlyTheDFormatLikeTryParseExact(text: String, expected: String?) {
        #expect(XcodeUuid.canonicalExact(text) == expected)
    }

    @Test(arguments: [
        ("11111111111141118111111111111111", "11111111-1111-4111-8111-111111111111" as String?),
        ("{11111111-1111-4111-8111-111111111111}", "11111111-1111-4111-8111-111111111111"),
        ("(AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE)", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
        (" 11111111-1111-4111-8111-111111111111 ", "11111111-1111-4111-8111-111111111111"),
        ("{11111111-1111-4111-8111-111111111111)", nil),
        ("{11111111111141118111111111111111}", nil),
        ("{0x11111111,0x1111,0x4111,{0x81,0x11,0x11,0x11,0x11,0x11,0x11,0x11}}", nil),
        ("runtime:11111111-1111-4111-8111-111111111111", nil),
    ])
    func canonicalAcceptsTheFormatsOfGuidTryParse(text: String, expected: String?) {
        #expect(XcodeUuid.canonical(text) == expected)
    }

    @Test func whiteSpaceMatchesDotNetIsWhiteSpace() {
        for scalar: Unicode.Scalar in ["\t", "\n", "\u{0B}", "\u{0C}", "\r", " ", "\u{85}", "\u{A0}", "\u{2028}", "\u{2029}", "\u{3000}"] {
            #expect(XcodeText.isWhiteSpace(scalar))
        }
        for scalar: Unicode.Scalar in ["a", "\u{200B}", "\u{FEFF}", "-"] {
            #expect(!XcodeText.isWhiteSpace(scalar))
        }
        #expect(XcodeText.trimmed(" \u{2028}x y\u{A0}\r") == "x y")
        #expect(XcodeText.isNullOrWhiteSpace(nil))
        #expect(XcodeText.isNullOrWhiteSpace(" \t"))
        #expect(!XcodeText.isNullOrWhiteSpace(" x "))
    }

    @Test func linesSplitOnlyOnLineFeedAndTrimLikeDotNet() {
        #expect(XcodeText.lines(" a \r\n\n b\t\n") == ["a", "b"])
        #expect(XcodeText.lines("x\ry") == ["x\ry"])
        #expect(XcodeText.lines("").isEmpty)
    }

    @Test func ordinalComparisonDistinguishesCanonicallyEquivalentForms() {
        #expect(!XcodeText.same("caf\u{E9}", "cafe\u{301}"))
        #expect(XcodeText.same(nil, nil))
        #expect(!XcodeText.same("a", nil))
        #expect(XcodeText.distinct(["b", "a", "b", "cafe\u{301}", "caf\u{E9}"]) == ["b", "a", "cafe\u{301}", "caf\u{E9}"])
        #expect(XcodeText.hasOrdinalPrefix("runtime:x", "runtime:"))
        #expect(!XcodeText.hasOrdinalPrefix("Runtime:x", "runtime:"))
    }

    @Test func containsIgnoringCaseIsOrdinalIgnoreCase() {
        #expect(XcodeText.containsIgnoringCase("Associazione runtime AMBIGUA: x", "ambigua"))
        #expect(XcodeText.containsIgnoringCase("/Applications/XCODE.app/contents/macos/Xcode", "/xcode.app/contents/macos/"))
        // Come la regex .NET con IgnoreCase: "ſ" (U+017F) non equivale a "s".
        #expect(!XcodeText.containsIgnoringCase("/Applications/Xcode.app/Contents/MacO\u{17F}/x", "/xcode.app/contents/macos/"))
        #expect(XcodeText.containsIgnoringCase("abc", ""))
        #expect(!XcodeText.containsIgnoringCase("", "a"))
    }

    @Test func messageMapsErrorsLikeExceptionMessage() {
        #expect(XcodeText.message(FileSystemError(code: EACCES, path: "/x")) == String(cString: strerror(EACCES)))
        #expect(XcodeText.message(CancellationError()) == "operazione annullata")
        #expect(XcodeText.message(XcodeUnavailableError("Xcode command line tools non trovati.")) == "Xcode command line tools non trovati.")
        #expect(XcodeText.message(ProcessLaunchError(executable: "/usr/bin/xcrun", code: ENOENT)) == String(cString: strerror(ENOENT)))
    }
}
