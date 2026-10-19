import Testing
@testable import CleanerCore

/// Solo Swift: il motore del contesto attivo, per l'errore di un daemon che non risponde.
struct DockerContextTests {
    private static let home = "/Users/tester"
    /// Non privata: la usano gli argomenti di `@Test`.
    static let generic = "Docker non è in esecuzione. Avvia il motore Docker (Docker Desktop, OrbStack…) e premi Riprova."

    @Test func parsesTheActiveContextAsPrintedByTheCli() throws {
        // Misurato con OrbStack il 2026-10-19: `docker context inspect --format '{{json .}}'`.
        let json = #"{"Name":"orbstack","Metadata":{"Description":"OrbStack"},"Endpoints":{"docker":{"Host":"unix:///Users/tester/.orbstack/run/docker.sock","SkipTLSVerify":false}},"TLSMaterial":{},"Storage":{"MetadataPath":"/Users/tester/.docker/contexts/meta/2d89","TLSPath":"/Users/tester/.docker/contexts/tls/2d89"}}"#

        #expect(try DockerJson.parseContext(json) == DockerContext(
            name: "orbstack", description: "OrbStack", host: "unix:///Users/tester/.orbstack/run/docker.sock"))
    }

    @Test func theDefaultContextHasNoDescription() throws {
        let json = #"{"Name":"default","Metadata":{},"Endpoints":{"docker":{"Host":"unix:///var/run/docker.sock","SkipTLSVerify":false}}}"#

        #expect(try DockerJson.parseContext(json) == DockerContext(name: "default", description: "", host: "unix:///var/run/docker.sock"))
    }

    @Test(arguments: [
        ("Docker Desktop", "unix:///Users/tester/.orbstack/run/docker.sock", DockerEngineKind.dockerDesktop),
        ("OrbStack", "unix:///Users/tester/.docker/run/docker.sock", .orbStack),
        ("", "unix:///Users/tester/.docker/run/docker.sock", .dockerDesktop),
        ("", "unix:///Users/tester/.orbstack/run/docker.sock", .orbStack),
        ("", "unix:///var/run/docker.sock", .other),
        ("", "tcp://127.0.0.1:2375", .other),
        ("", "unix:///Users/altro/.orbstack/run/docker.sock", .other),
        ("", "unix:///Users/tester/.orbstack/runtime/docker.sock", .other),
        ("Colima", "unix:///Users/tester/.colima/default/docker.sock", .other),
    ])
    func recognizesTheEngineFromDescriptionThenEndpoint(description: String, host: String, expected: DockerEngineKind) {
        let context = DockerContext(name: "ctx", description: description, host: host)

        #expect(context.engineKind(homeDirectory: Self.home + "/") == expected)
    }

    @Test(arguments: [
        (DockerContext(name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/tester/.docker/run/docker.sock") as DockerContext?,
         "Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi Riprova."),
        (DockerContext(name: "orbstack", description: "", host: "unix:///Users/tester/.orbstack/run/docker.sock"),
         "OrbStack non è in esecuzione (contesto «orbstack»). Avvialo e premi Riprova."),
        (DockerContext(name: "default", description: "", host: "unix:///var/run/docker.sock"),
         "Il motore Docker del contesto «default» non risponde. Avvialo e premi Riprova."),
        (DockerContext(name: " ", description: "OrbStack", host: ""), DockerContextTests.generic),
        (nil, DockerContextTests.generic),
    ])
    func notRunningMessageNamesTheEngineOfTheContext(context: DockerContext?, expected: String) {
        #expect(DockerUnavailableError.notRunningMessage(context, homeDirectory: Self.home) == expected)
    }

    /// All'avvio di «Elimina» l'analisi resta valida: avviato il motore, basta premere di nuovo
    /// «Elimina». Nello stato pronto della pagina «Riprova» non c'è.
    @Test(arguments: [
        (DockerContext(name: "desktop-linux", description: "Docker Desktop", host: "unix:///Users/tester/.docker/run/docker.sock"),
         "Docker Desktop non è in esecuzione (contesto «desktop-linux»). Avvialo e premi di nuovo «Elimina»."),
        (DockerContext(name: "orbstack", description: "", host: "unix:///Users/tester/.orbstack/run/docker.sock"),
         "OrbStack non è in esecuzione (contesto «orbstack»). Avvialo e premi di nuovo «Elimina»."),
        (DockerContext(name: "default", description: "", host: "unix:///var/run/docker.sock"),
         "Il motore Docker del contesto «default» non risponde. Avvialo e premi di nuovo «Elimina»."),
    ])
    func theDeletionMessageAsksToPressDeleteAgain(context: DockerContext, expected: String) {
        #expect(DockerUnavailableError.notRunningForDeletionMessage(context, homeDirectory: Self.home) == expected)
    }
}
