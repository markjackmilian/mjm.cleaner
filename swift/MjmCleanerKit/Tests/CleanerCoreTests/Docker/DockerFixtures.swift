import Foundation
@testable import CleanerCore

/// Il caso reale da cui è nata la funzione: due container fermi (exit code 137) di SQL Server e di
/// Azurite avviati da un AppHost Aspire, più le immagini e i volumi che si erano accumulati attorno.
/// Gli ID di mssql 2025, azurite, dcptun e azurelinux sono quelli misurati; gli altri sono fittizi ma
/// nella stessa forma (sha256 di 64 caratteri esadecimali).
///
/// Le fixture JSON stanno accanto a questo file, in `Fixtures/`, copiate byte per byte dal C#: si
/// leggono dal percorso del sorgente (`#filePath`), senza risorse nel bundle dei test.
enum DockerFixtures {
    static let mssql2025Id = "sha256:2b5b581621126574f3d1f75e78d3eebe8d05aedb59ad0cfdf9aa42cb0634d726"
    static let azuriteId = "sha256:647c63a91102a9d8e8000aab803436e1fc85fbb285e7ce830a82ee5d6661cf37"
    static let dcptunId = "sha256:c1a077005187d683004cabff17b02f174db19515ec56327f38d8e3d7e2e8c04a"
    static let azureLinuxId = "sha256:34a22db497ff34a0f35ca5fc54bd38711d04238a2c1b2f65d35dc9d45dd82584"
    static let mssql2022Id = fake("a1")
    static let keycloakId = fake("b2")
    static let mssqlToolsId = fake("c3")
    static let alpineId = fake("d4")
    static let ryukId = fake("e5")
    static let localBuildId = fake("f6")

    static let anonymousVolume = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    static func read(_ name: String) throws -> String {
        let directory = PathText.join(PathText.parent(#filePath) ?? ".", "Fixtures")
        return try String(contentsOfFile: PathText.join(directory, name), encoding: .utf8)
    }

    static func snapshot(existingComposeProjects: Set<String> = []) throws -> DockerSnapshot {
        let verbose = try DockerJson.parseDfVerbose(read("df-verbose.json"))

        return DockerSnapshot(
            containers: try DockerJson.parseContainers(read("containers.json")),
            images: try DockerJson.parseImages(read("images.json"), uniqueSizes: verbose.imageUniqueSizes),
            volumes: try DockerJson.parseVolumes(read("volumes.json"), sizes: verbose.volumeSizes),
            df: try DockerJson.parseDfSummary(read("df.jsonl")),
            existingComposeProjects: existingComposeProjects)
    }

    private static func fake(_ pair: String) -> String {
        "sha256:" + String(repeating: pair, count: 32)
    }
}
