/// Equivalente di `FileSystemName.MatchesSimpleExpression(pattern, name, ignoreCase: true)`:
/// `*` corrisponde a zero o più caratteri, `?` esattamente a uno, nessun altro carattere è
/// speciale. Come in .NET, `?` corrisponde a una singola unità UTF-16 (un carattere fuori dal
/// BMP, come un'emoji, ne occupa due). Niente `fnmatch`, che interpreterebbe anche `[…]` e `\` e
/// accetterebbe nomi che il C# rifiutava.
public enum SimpleGlob {
    public static func matches(_ pattern: String, _ name: String) -> Bool {
        let asterisk = UInt16(UInt8(ascii: "*"))
        let questionMark = UInt16(UInt8(ascii: "?"))
        let pattern = Array(pattern.lowercased().utf16)
        let name = Array(name.lowercased().utf16)
        var patternIndex = 0
        var nameIndex = 0
        var starIndex: Int?
        var starMatch = 0

        while nameIndex < name.count {
            if patternIndex < pattern.count, pattern[patternIndex] == asterisk {
                starIndex = patternIndex
                starMatch = nameIndex
                patternIndex += 1
            } else if patternIndex < pattern.count,
                      pattern[patternIndex] == questionMark || pattern[patternIndex] == name[nameIndex] {
                patternIndex += 1
                nameIndex += 1
            } else if let star = starIndex {
                patternIndex = star + 1
                starMatch += 1
                nameIndex = starMatch
            } else {
                return false
            }
        }

        while patternIndex < pattern.count, pattern[patternIndex] == asterisk {
            patternIndex += 1
        }
        return patternIndex == pattern.count
    }
}
