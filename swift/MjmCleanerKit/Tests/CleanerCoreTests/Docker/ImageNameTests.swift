import Testing
@testable import CleanerCore

struct ImageNameTests {
    @Test(arguments: [
        ("alpine:3.20", "docker.io/library/alpine", "3.20" as String?),
        ("docker.io/library/alpine:3.20", "docker.io/library/alpine", "3.20"),
        ("testcontainers/ryuk:0.14.0", "docker.io/testcontainers/ryuk", "0.14.0"),
        ("mcr.microsoft.com/mssql/server:2025-latest", "mcr.microsoft.com/mssql/server", "2025-latest"),
        ("localhost:5000/app:1", "localhost:5000/app", "1"),
        ("localhost/app", "localhost/app", nil),
        ("quay.io/keycloak/keycloak", "quay.io/keycloak/keycloak", nil),
        ("redis@sha256:abc", "docker.io/library/redis", nil),
        ("redis:7@sha256:abc", "docker.io/library/redis", "7"),
        ("Dcptun_Developer_MS:0.25.13", "docker.io/library/dcptun_developer_ms", "0.25.13"),
    ])
    func normalizesRepositoryAndSeparatesTheTag(reference: String, repository: String, tag: String?) {
        let name = ImageName.parse(reference)

        #expect(name.repository == repository)
        #expect(name.tag == tag)
    }

    @Test func shortNameIsTheLastRepositorySegment() {
        #expect(ImageName.parse("testcontainers/ryuk:0.14.0").shortName == "ryuk")
    }
}
