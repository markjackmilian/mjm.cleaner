import Testing
@testable import CleanerCore

/// Solo Swift: il motore dietro la CLI si riconosce dall'`OperatingSystem` del daemon.
struct DockerEngineTests {
    @Test(arguments: [
        ("Docker Desktop", DockerEngineKind.dockerDesktop, "Docker Desktop"),
        ("docker desktop", .dockerDesktop, "Docker Desktop"),
        ("OrbStack", .orbStack, "OrbStack"),
        ("orbstack", .orbStack, "OrbStack"),
        ("Ubuntu 24.04.1 LTS", .other, "Docker"),
        ("OrbStack Linux", .other, "Docker"),
        ("", .other, "Docker"),
    ])
    func recognizesTheEngineFromTheWholeOperatingSystemName(operatingSystem: String, kind: DockerEngineKind, name: String) {
        let engine = DockerEngine(serverVersion: "29.8.2", operatingSystem: operatingSystem)

        #expect(engine.kind == kind)
        #expect(engine.displayName == name)
        #expect(engine.operatingSystem == operatingSystem)
        #expect(engine.serverVersion == "29.8.2")
    }

    /// Due daemon con lo stesso sistema e la stessa versione restano diversi se l'ID è diverso:
    /// l'esecutore confronta il motore intero.
    @Test func theIdTellsTwoDaemonsOfTheSameKindApart() {
        let colima = DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04", id: "a1")

        #expect(colima.id == "a1")
        #expect(colima == DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04", id: "a1"))
        #expect(colima != DockerEngine(serverVersion: "29.8.2", operatingSystem: "Ubuntu 24.04", id: "b2"))
        #expect(DockerEngine(serverVersion: "29.8.2", operatingSystem: "OrbStack").id == "")
    }
}
