/// Equivalente di `FileSystemName.MatchesSimpleExpression(pattern, name, ignoreCase: true)`:
/// `*` corrisponde a zero o più caratteri, `?` esattamente a uno, nessun altro carattere è
/// speciale. Niente `fnmatch`, che interpreterebbe anche `[…]` e `\` e accetterebbe nomi che il
/// C# rifiutava.
public enum SimpleGlob {
    public static func matches(_ pattern: String, _ name: String) -> Bool {
        let pattern = Array(pattern.lowercased())
        let name = Array(name.lowercased())
        var patternIndex = 0
        var nameIndex = 0
        var starIndex: Int?
        var starMatch = 0

        while nameIndex < name.count {
            if patternIndex < pattern.count,
               pattern[patternIndex] == "?" || pattern[patternIndex] == name[nameIndex] {
                patternIndex += 1
                nameIndex += 1
            } else if patternIndex < pattern.count, pattern[patternIndex] == "*" {
                starIndex = patternIndex
                starMatch = nameIndex
                patternIndex += 1
            } else if let star = starIndex {
                patternIndex = star + 1
                starMatch += 1
                nameIndex = starMatch
            } else {
                return false
            }
        }

        while patternIndex < pattern.count, pattern[patternIndex] == "*" {
            patternIndex += 1
        }
        return patternIndex == pattern.count
    }
}
