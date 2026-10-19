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
}
