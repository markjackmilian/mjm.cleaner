import Foundation

/// Le fixture JSON dei test C# (`tests/MjmCleaner.Core.Tests/Xcode/Fixtures`), copiate byte per
/// byte in `Fixtures/` accanto a questo file e lette dal disco: nessuna risorsa nel bundle.
enum XcodeFixtures {
    private static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func text(_ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }
}
