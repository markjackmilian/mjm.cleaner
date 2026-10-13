import Foundation

/// L'ora corrente, astratta per rendere deterministici i filtri di età nei test.
public protocol WallClock: Sendable {
    var now: Date { get }
}

public struct SystemWallClock: WallClock {
    public init() {}

    public var now: Date { Date() }
}
