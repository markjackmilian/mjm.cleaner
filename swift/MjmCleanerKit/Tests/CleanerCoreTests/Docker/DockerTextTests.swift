import Foundation
import Testing
@testable import CleanerCore

/// Solo Swift: le equivalenze con i metodi .NET su cui si appoggia il porting di Docker, misurate
/// su .NET 10 durante la stesura del piano 2.
struct DockerTextTests {
    @Test func linesSplitOnlyOnNewlineAndTrimUnicodeWhitespace() {
        // `Split('\n', RemoveEmptyEntries | TrimEntries)`: "\r" e U+2028 non dividono, `Trim` li toglie.
        #expect(DockerText.lines("a\r\nb\n\n c \u{2028}x\n \u{A0}\n") == ["a", "b", "c \u{2028}x"])
        #expect(DockerText.rawLines("a\n\nb\n").map(String.init) == ["a", "", "b", ""])
        // U+FEFF e U+200B non sono spazi per `char.IsWhiteSpace`.
        #expect(DockerText.trimmed("\u{FEFF}x\u{200B}") == "\u{FEFF}x\u{200B}")
        #expect(DockerText.trimmed("\"\"29.8.0\"", "\"") == "29.8.0")
    }

    @Test func ordinalComparisonsWorkOnBytesNotGraphemes() {
        // Uno scalare «prepend» (U+0600) si fonde con il "/" in un solo grafema: per `String` di
        // Swift il suffisso non c'è, per `EndsWith(Ordinal)` di .NET sì.
        #expect(DockerText.hasSuffix("x\u{600}/testcontainers/ryuk", "/testcontainers/ryuk"))
        #expect(DockerText.hasPrefix("dcptun_\u{301}x", "dcptun_"))
        #expect(DockerText.contains("abc;\u{301}def", ";"))
        #expect(!DockerText.contains("ab", "abc"))
        #expect(DockerText.containsIgnoringCase("Error: CANNOT CONNECT to the Docker daemon", "cannot connect"))
        #expect(!DockerText.containsIgnoringCase("\u{131}", "I"))
        #expect(DockerText.hasSuffixIgnoringCase("Program.CS", ".cs"))
    }

    @Test func distinctAndOrderAreOrdinal() {
        // NFC e NFD dello stesso testo sono distinti per `StringComparer.Ordinal`.
        #expect(DockerText.distinct(["e\u{301}", "\u{E9}", "e\u{301}"]) == ["e\u{301}", "\u{E9}"])
        // Ordine per unità UTF-16: U+10000 (D800 DC00) precede U+FF61.
        #expect(DockerText.ordinalSorted(["\u{FF61}", "\u{10000}", "B", "a"]) == ["B", "a", "\u{10000}", "\u{FF61}"])
    }

    @Test func lowercasedInvariantUsesTheSimpleMapping() {
        // U+0130 resta (la sua minuscola completa è di due scalari); il segno Kelvin diventa "k".
        #expect(DockerText.lowercasedInvariant("\u{C0}B\u{130}\u{212A}\u{10400}") == "\u{E0}b\u{130}k\u{10428}")
    }

    // Gli esiti di `File.ReadAllText` misurati su .NET 10 con gli stessi byte.
    @Test(arguments: [
        ([0xEF, 0xBB, 0xBF, 0x6E, 0x61] as [UInt8], "na"),
        ([0xFF, 0xFE, 0x6E, 0x00, 0x61, 0x00], "na"),
        ([0xFE, 0xFF, 0x00, 0x6E, 0x00, 0x61], "na"),
        ([0xFF, 0xFE, 0x00, 0x00, 0x6E, 0x00, 0x00, 0x00], "n"),
        ([0xFF, 0xFE, 0x6E, 0x00, 0x61], "n\u{FFFD}"),
        ([0xFF, 0xFE, 0x00, 0x00, 0x6E, 0x00, 0x00, 0x00, 0x61], "n\u{FFFD}"),
        ([0x6E, 0xFF], "n\u{FFFD}"),
        ([0x6E, 0xE2, 0x82], "n\u{FFFD}"),
    ])
    func fileContentsAreDecodedLikeReadAllText(bytes: [UInt8], expected: String) {
        #expect(DockerText.decodeLikeReadAllText(Data(bytes)) == expected)
    }

    @Test func lineStartsFollowTheDotNetMultilineAnchor() {
        let text = "a\rb\u{2028}c\nd\n"
        let starts = DockerText.lineStarts(text).map { String(text[$0...]) }
        #expect(starts == ["a\rb\u{2028}c\nd\n", "d\n", ""])
    }
}
