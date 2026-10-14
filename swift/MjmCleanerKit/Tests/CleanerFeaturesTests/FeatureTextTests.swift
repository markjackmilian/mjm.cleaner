import CleanerCore
import Darwin
import Foundation
import Testing
@testable import CleanerFeatures

/// Confronti ordinali, testo degli errori e somme senza trap: le utilità che i modelli usano al
/// posto di `==`, `ex.Message` e `Sum()` del C#.
struct FeatureTextTests {
    @Test func comparisonsAreOrdinalNotCanonical() {
        let composed = "caf\u{E9}"
        let decomposed = "cafe\u{301}"

        // `==` fra String li considera uguali; StringComparison.Ordinal no.
        #expect(composed == decomposed)
        #expect(!FeatureText.same(composed, decomposed))
        #expect(FeatureText.ordinalKey(composed) != FeatureText.ordinalKey(decomposed))
        #expect(FeatureText.hasOrdinalPrefix("docker:image:sha", "docker:image:"))
        #expect(!FeatureText.hasOrdinalPrefix("docker:imag", "docker:image:"))
        #expect(FeatureText.hasOrdinalPrefix("cafe\u{301}", "cafe"))
        #expect(!FeatureText.hasOrdinalPrefix("caf\u{E9}", "cafe\u{301}"))
        #expect(FeatureText.distinct(["b", composed, "b", decomposed, composed]) == ["b", composed, decomposed])
    }

    @Test func messagesFollowTheCoreConventions() {
        #expect(FeatureText.message(FileSystemError(code: EACCES, path: "/x")) == String(cString: strerror(EACCES)))
        #expect(FeatureText.message(ProcessLaunchError(executable: "/usr/bin/xcrun", code: ENOENT)) == String(cString: strerror(ENOENT)))
        #expect(FeatureText.message(CancellationError()) == "operazione annullata")
        #expect(FeatureText.message(DockerUnavailableError("Docker non risponde.")) == "Docker non risponde.")
        #expect(FeatureText.message(XcodeArgumentError("Unknown Xcode candidate key: x")) == "Unknown Xcode candidate key: x")
    }

    @Test func sumsSaturateInsteadOfTrapping() {
        #expect(SafeSum.total([Int64]()) == 0)
        #expect(SafeSum.total([1, 2, 3]) == 6)
        #expect(SafeSum.total([Int64.max, 1]) == Int64.max)
        #expect(SafeSum.total([Int64.min, -1]) == Int64.min)
        #expect(SafeSum.difference(10, 4) == 6)
        #expect(SafeSum.difference(Int64.max, -1) == Int64.max)
        #expect(SafeSum.difference(Int64.min, 1) == Int64.min)
    }
}
