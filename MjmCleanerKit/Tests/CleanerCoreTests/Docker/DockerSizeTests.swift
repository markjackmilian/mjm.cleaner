import Testing
@testable import CleanerCore

struct DockerSizeTests {
    @Test(arguments: [
        ("0B", Int64(0)),
        ("57.3kB", 57_300),
        ("1.131kB", 1_131),
        ("195MB", 195_000_000),
        ("2.42GB", 2_420_000_000),
        ("1.5TB", 1_500_000_000_000),
        ("76.74MB (2%)", 76_740_000),
        (" 106.9MB ", 106_900_000),
    ])
    func parsesTheDecimalUnitsPrintedByDocker(text: String, expected: Int64) {
        #expect(DockerSize.parse(text) == expected)
    }

    @Test(arguments: ["N/A", "", nil, "molto"] as [String?])
    func returnsNullWhenTheSizeIsUnknown(text: String?) {
        #expect(DockerSize.parse(text) == nil)
    }

    // Solo Swift: il confine di parola dopo l'unità e l'arrotondamento seguono .NET 10, misurato
    // durante la stesura del piano 2 ("5MB.x" e "5MBⅫ" valgono 5 MB; "5MBx", "5MB" + U+0301 e
    // "5MB" + U+200D non sono dimensioni; 2.5 B si arrotonda al pari).
    @Test(arguments: [
        ("5MB.x", Int64(5_000_000) as Int64?),
        ("5MB\u{216B}", 5_000_000),
        ("5MB\u{1D400}", 5_000_000),
        ("5MBx", nil),
        ("5MB_", nil),
        ("5MB\u{301}", nil),
        ("5MB\u{200D}", nil),
        ("2.5B", 2),
        ("3.5B", 4),
        ("\u{663}MB", nil),
    ])
    func wordBoundaryAndRoundingFollowDotNet(text: String, expected: Int64?) {
        #expect(DockerSize.parse(text) == expected)
    }
}
