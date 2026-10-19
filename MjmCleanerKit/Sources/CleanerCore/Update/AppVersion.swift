/// La versione `MAJOR.MINOR.PATCH` dell'app e dei tag delle release (`vMAJOR.MINOR.PATCH`, lo
/// stesso formato che il workflow di release accetta). Si confronta campo per campo come numeri:
/// `0.10.0` è più recente di `0.9.0`. Un testo diverso non produce una versione.
public struct AppVersion: Sendable, Equatable, Hashable, Comparable, Codable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `1.2.3` o `v1.2.3`; niente prerelease, metadati, spazi o segni.
    public init?(_ text: String) {
        let digits = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, let major = Self.number(parts[0]), let minor = Self.number(parts[1]),
              let patch = Self.number(parts[2]) else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    /// Da una a nove cifre ASCII: il valore entra sempre in un `Int`.
    private static func number(_ part: Substring) -> Int? {
        guard (1...9).contains(part.utf8.count), part.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(part)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    /// Il tag della release: `v` + versione.
    public var tag: String { "v" + description }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
