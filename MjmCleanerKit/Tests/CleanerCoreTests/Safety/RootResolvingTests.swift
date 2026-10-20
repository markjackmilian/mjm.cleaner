import Testing
@testable import CleanerCore

/// `PathGuard` come `RootResolving`: la root come la vede il motore, cioè quella di `validateRoot`.
struct RootResolvingTests {
    private static let home = "/Users/tester"

    private func resolver(_ targets: [String: String?] = [:]) throws -> any RootResolving {
        try PathGuard(
            denyList: DenyList(homeDirectory: Self.home), fileSystem: InMemoryFileSystem(), links: FakeLinkInspector(targets: targets),
            homeDirectory: Self.home)
    }

    @Test func anOrdinaryRootStaysAsDeclared() throws {
        #expect(try resolver().resolvedRoot("/Users/tester/Library/Caches") == "/Users/tester/Library/Caches")
    }

    @Test func aLinkedRootLeadsToItsTarget() throws {
        let roots = try resolver(["/Users/tester/.cache": "/Users/tester/Dati/cache", "/var": "/private/var"])

        #expect(roots.resolvedRoot("/Users/tester/.cache") == "/Users/tester/Dati/cache")
        #expect(roots.resolvedRoot("/var/folders/xyz/T") == "/private/var/folders/xyz/T")
    }

    /// Una root negata dopo la risoluzione vale comunque dove porta: le sue voci non si cancellano, e
    /// il percorso risolto riconosce più contenimenti.
    @Test func aDeniedRootStillLeadsToItsTarget() throws {
        let roots = try resolver(["/Users/tester/Library/Caches": "/Volumes/SSD/Caches"])

        #expect(roots.resolvedRoot("/Users/tester/Library/Caches") == "/Volumes/SSD/Caches")
    }

    /// Senza un percorso canonico (root relativa o con segmenti «..»), resta la root dichiarata.
    @Test func withoutACanonicalPathTheDeclaredRootStays() throws {
        let roots = try resolver()

        #expect(roots.resolvedRoot("relativa/cache") == "relativa/cache")
        #expect(roots.resolvedRoot("/Users/tester/../altro") == "/Users/tester/../altro")
    }
}
