import Foundation
import Testing
@testable import CleanerCore

struct ProjectReferenceScannerTests {
    /// `(Repository, Tag)` del C#: le tuple Swift non sono `Equatable` dentro un array.
    private struct Found: Equatable, CustomStringConvertible {
        let repository: String
        let tag: String?

        init(_ repository: String, _ tag: String?) {
            self.repository = repository
            self.tag = tag
        }

        var description: String { "(\(repository), \(tag ?? "nil"))" }
    }

    private func scan(_ files: (path: String, content: String)...) throws -> ProjectReferences {
        let fs = InMemoryFileSystem()
        fs.addDirectory("/p")
        for (path, content) in files {
            fs.addFile(path, text: content)
        }

        return try ProjectReferenceScanner(fileSystem: fs).scan(["/p"])
    }

    /// `.Order()` del C# sulle tuple: repository, poi tag con `nil` per primo.
    private func images(_ references: ProjectReferences) -> [Found] {
        references.images.map { Found($0.repository, $0.tag) }.sorted { lhs, rhs in
            if lhs.repository != rhs.repository { return lhs.repository < rhs.repository }
            switch (lhs.tag, rhs.tag) {
            case let (left?, right?): return left < right
            case (nil, _?): return true
            default: return false
            }
        }
    }

    @Test func composeImagesAreReadWithFileAndLine() throws {
        let found = try scan(("/p/shop/compose.yaml", """
            services:
              db:
                image: postgres:16
              cache:
                image: "redis"
            """))

        #expect(images(found) == [Found("docker.io/library/postgres", "16"), Found("docker.io/library/redis", nil)])
        let postgres = try #require(found.images.first { $0.tag == "16" })
        #expect(postgres.file == "/p/shop/compose.yaml")
        #expect(postgres.line == 3)
    }

    @Test func composeProjectNameComesFromTheFolderWhenNotDeclared() throws {
        let found = try scan(("/p/My Shop/docker-compose.override.yml", "services: {}\n"))

        #expect(found.composeProjects == ["myshop"])
    }

    @Test func composeProjectNameDeclaredInTheFileWins() throws {
        let found = try scan(("/p/shop/compose.yml", "name: Orbit-Stack\nservices: {}\n"))

        #expect(found.composeProjects == ["orbit-stack"])
    }

    @Test func dockerfileFromLinesSkipStageNamesAndScratch() throws {
        let found = try scan(("/p/api/Dockerfile", """
            FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:9.0 AS build
            RUN dotnet publish
            FROM build AS publish
            FROM scratch AS empty
            from mcr.microsoft.com/dotnet/aspnet:9.0
            """))

        #expect(images(found) == [Found("mcr.microsoft.com/dotnet/aspnet", "9.0"), Found("mcr.microsoft.com/dotnet/sdk", "9.0")])
    }

    @Test func aspireAppHostResourcesMapToTheirImages() throws {
        let found = try scan(("/p/Orbit.AppHost/Program.cs", """
            var builder = DistributedApplication.CreateBuilder(args);

            var sql = builder.AddSqlServer("sql")
                .WithImageTag("2025-latest")
                .WithDataVolume();

            var keycloak = builder.AddKeycloak("keycloak", 8080);

            var storage = builder.AddAzureStorage("storage")
                .RunAsEmulator(emulator => emulator.WithImageTag("3.35.0"));

            var mail = builder.AddContainer("mail", "axllent/mailpit", "v1.20");

            var custom = builder.AddRedis("cache").WithImage("quay.io/opstree/redis", "7.2");

            builder.Build().Run();
            """))

        #expect(images(found) == [
            Found("docker.io/axllent/mailpit", "v1.20"),
            Found("mcr.microsoft.com/azure-storage/azurite", "3.35.0"),
            Found("mcr.microsoft.com/mssql/server", "2025-latest"),
            Found("quay.io/keycloak/keycloak", nil),
            Found("quay.io/opstree/redis", "7.2"),
        ])
        #expect(found.images.first { $0.tag == "2025-latest" }?.line == 3)
    }

    @Test func withImageRegistryPrefixesTheRepository() throws {
        let found = try scan(("/p/Orbit.AppHost/Program.cs", """
            var builder = DistributedApplication.CreateBuilder(args);
            builder.AddContainer("api", "acme/api").WithImageRegistry("ghcr.io").WithImageTag("2.0");
            """))

        #expect(images(found) == [Found("ghcr.io/acme/api", "2.0")])
    }

    @Test func testcontainersBuildersAndExplicitImagesAreFound() throws {
        let found = try scan(("/p/Tests/Fixture.cs", """
            using Testcontainers.MsSql;

            var sql = new MsSqlBuilder("mcr.microsoft.com/mssql/server:2022-latest").Build();
            var plain = new ContainerBuilder().WithImage("alpine:3.20").Build();
            var redis = new RedisBuilder().Build();
            """))

        #expect(images(found) == [
            Found("docker.io/library/alpine", "3.20"),
            Found("docker.io/library/redis", nil),
            Found("mcr.microsoft.com/mssql/server", "2022-latest"),
        ])
    }

    @Test func ordinaryCSharpFilesAreNotScanned() throws {
        let found = try scan(("/p/Api/Service.cs", """
            var name = "postgres:16";
            var x = something.WithImage("alpine:3.20");
            """))

        #expect(found.images.isEmpty)
    }

    @Test func kubernetesAndHelmManifestsAreRead() throws {
        let found = try scan(
            ("/p/deploy/deployment.yaml", """
                spec:
                  containers:
                    - name: web
                      image: nginx:1.27
                """),
            ("/p/deploy/chart/values.yaml", """
                image:
                  repository: ghcr.io/acme/api
                  pullPolicy: IfNotPresent
                  tag: "1.4.2"
                """))

        #expect(images(found) == [Found("docker.io/library/nginx", "1.27"), Found("ghcr.io/acme/api", "1.4.2")])
    }

    @Test func templatedValuesAreIgnored() throws {
        let found = try scan(("/p/shop/compose.yaml", """
            services:
              api:
                image: ${REGISTRY}/api:${TAG}
              web:
                image: "{{ .Values.image }}"
            """))

        #expect(found.images.isEmpty)
    }

    @Test(arguments: ["node_modules", "bin", "obj", ".git"])
    func excludedFoldersAreSkipped(folder: String) throws {
        let found = try scan(("/p/web/\(folder)/pkg/docker-compose.yml", "services:\n  x:\n    image: postgres:16\n"))

        #expect(found.images.isEmpty)
        #expect(found.composeProjects.isEmpty)
    }

    @Test func filesLargerThanOneMegabyteAreSkipped() throws {
        let found = try scan(("/p/deploy/huge.yaml", "image: nginx:1.27\n" + String(repeating: "#", count: 1_100_000)))

        #expect(found.images.isEmpty)
    }

    // MARK: - Solo Swift: esiti del C# reale (harness .NET 10 durante la stesura del piano 2)

    @Test func fileNamesAreClassifiedLikeTheGeneratedDotNetRegexes() throws {
        // Un carattere fuori dal piano base non è `\w` per .NET: il file resta un YAML qualunque.
        let supplementary = try scan(("/p/a/compose\u{1D400}.yml", "image: nginx:1\n"))
        #expect(images(supplementary) == [Found("docker.io/library/nginx", "1")])
        #expect(supplementary.composeProjects.isEmpty)

        // Il segno Kelvin equivale a "k" anche per l'IgnoreCase di .NET.
        #expect(try scan(("/p/a/doc\u{212A}er-compose.yml", "image: nginx:1\n")).composeProjects == ["a"])

        // U+0130 non equivale a "i" nella cultura invariante delle regex generate.
        #expect(try scan(("/p/a/Dockerf\u{130}le", "FROM alpine:3.20\n")).images.isEmpty)
    }

    @Test func composeNameFollowsTheDotNetMultilineAnchor() throws {
        // "^" vale solo dopo "\n", e `\s*` prosegue sulla riga seguente.
        #expect(try scan(("/p/b/compose.yml", "x: 1\rname: bad\nname:\n  good\n")).composeProjects == ["good"])
        #expect(try scan(("/p/b/compose.yml", "x: 1\u{2028}name: bad\n")).composeProjects == ["b"])
    }

    @Test func projectFilesAreDecodedLikeReadAllText() throws {
        let fs = InMemoryFileSystem()
        fs.addDirectory("/p/c")
        fs.addDirectory("/p/w")
        try fs.writeData("/p/c/compose.yml", Data([0xEF, 0xBB, 0xBF]) + Data("name: Bom\nservices:\n  x:\n    image: redis:7\n".utf8))
        try fs.writeData("/p/w/compose.yml", Data([0xFF, 0xFE]) + Data("name: Wide\n".utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }))

        let found = try ProjectReferenceScanner(fileSystem: fs).scan(["/p"])

        #expect(found.composeProjects == ["bom", "wide"])
        #expect(found.images.map(\.line) == [4])
    }

    @Test func cSharpStatementsAreSplitOnScalars() throws {
        // Un segno combinante dopo ";" non nasconde la fine dell'istruzione; U+2028 è uno spazio
        // per `TrimStart` ma non conta come riga.
        let combining = try scan(("/p/d/AppHost.cs", "var b = DistributedApplication.CreateBuilder(args);\u{301}builder.AddRedis(\"r\");"))
        #expect(combining.images.map(\.line) == [1])

        let separator = try scan(("/p/d/AppHost.cs", "DistributedApplication;\n\u{2028}\n  builder.AddRedis(\"x\");"))
        #expect(separator.images.map(\.line) == [3])
    }

    @Test func missingRootProducesNoReferences() throws {
        let found = try ProjectReferenceScanner(fileSystem: InMemoryFileSystem()).scan(["/nope"])

        #expect(found.images.isEmpty)
    }
}
