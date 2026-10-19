import Darwin
import Testing
@testable import CleanerCore

struct DockerCliTests {
    private struct Call: Sendable {
        let file: String
        let arguments: [String]
        let environment: [String: String]?
    }

    private struct FakeRunner: ProcessRunning {
        let calls = Recorder<Call>()
        let respond: @Sendable (String, [String]) throws -> ProcessResult

        func run(_ executable: String, _ arguments: [String], timeout: Duration, environment: [String: String]?) async throws -> ProcessResult {
            calls.append(Call(file: executable, arguments: arguments, environment: environment))
            return try respond(executable, arguments)
        }
    }

    @Test(arguments: [
        "Cannot connect to the Docker daemon at unix:///Users/tester/.docker/run/docker.sock. Is the docker daemon running?",
        "error during connect: Get \"http://%2FUsers%2Ftester%2F.docker%2Frun%2Fdocker.sock/v1.47/info\": EOF",
        "failed to connect to the docker API at unix:///Users/tester/.docker/run/docker.sock; check if the path is correct and if the daemon is running: dial unix /Users/tester/.docker/run/docker.sock: connect: no such file or directory",
        "dial unix /var/run/docker.sock: connect: connection refused",
    ])
    func recognizesAnUnreachableDaemon(standardError: String) {
        #expect(DockerCliErrors.isDaemonUnavailable(standardError))
    }

    @Test(arguments: [
        "Error response from daemon: conflict: unable to delete 2b5b58162112 (cannot be forced) - image is being used by running container e20bf2607c5b",
        "Error: No such image: testcontainers/ryuk:0.14.0",
        "",
    ])
    func ordinaryErrorsAreNotADaemonOutage(standardError: String) {
        #expect(!DockerCliErrors.isDaemonUnavailable(standardError))
    }

    @Test func argumentsArePassedVerbatimToTheLocatedBinary() async throws {
        let runner = FakeRunner { _, _ in ProcessResult(exitCode: 0, standardOutput: "ok", standardError: "", timedOut: false) }
        let cli = DockerCli(runner: runner, binaryPath: "/Users/tester/.docker/bin/docker")

        let result = try await cli.run(["images", "--format", "{{json .}}"])

        #expect(result.standardOutput == "ok")
        let call = try #require(runner.calls.values.first)
        #expect(runner.calls.values.count == 1)
        #expect(call.file == "/Users/tester/.docker/bin/docker")
        #expect(call.arguments == ["images", "--format", "{{json .}}"])
        // Un'app aperta dal Finder non eredita il PATH della shell: i plugin e gli helper della CLI
        // (buildx, credential helper) vanno resi raggiungibili esplicitamente.
        let path = try #require(call.environment?["PATH"])
        #expect(path.hasPrefix("/Users/tester/.docker/bin:"))
    }

    @Test func unreachableDaemonBecomesAReadableException() async {
        let runner = FakeRunner { _, _ in
            ProcessResult(exitCode: 1, standardOutput: "", standardError: "Cannot connect to the Docker daemon at unix:///x.sock. Is the docker daemon running?", timedOut: false)
        }
        let cli = DockerCli(runner: runner, binaryPath: "/usr/local/bin/docker")

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }

        #expect(error == DockerUnavailableError(DockerUnavailableError.notRunning, reason: .notRunning))
        #expect(error?.message.contains("Avvia il motore Docker") == true)
    }

    @Test func missingBinaryBecomesAReadableException() async {
        let cli = DockerCli(runner: FakeRunner { _, _ in throw ProcessLaunchError(executable: "docker", code: ENOENT) }, binaryPath: nil)

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }

        #expect(error?.message.contains("non è stato trovato") == true)
        #expect(error?.reason == .notInstalled)
    }

    @Test func binaryThatCannotStartBecomesAReadableException() async {
        let cli = DockerCli(runner: FakeRunner { _, _ in throw ProcessLaunchError(executable: "/usr/local/bin/docker", code: ENOENT) }, binaryPath: "/usr/local/bin/docker")

        let error = await #expect(throws: DockerUnavailableError.self) {
            try await cli.run(["info"])
        }

        #expect(error?.reason == .notInstalled)
    }

    @Test func checkedRunFailsWithTheDockerErrorText() async {
        let cli = FakeDockerCli().on("volume inspect x") { FakeDockerCli.fail("Error response from daemon: get x: no such volume") }

        let error = await #expect(throws: DockerCommandError.self) {
            try await cli.runChecked(["volume", "inspect", "x"])
        }

        #expect(error?.message.contains("no such volume") == true)
    }

    @Test func checkedRunReportsATimeout() async {
        let cli = FakeDockerCli().on("system df") { ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true) }

        let error = await #expect(throws: DockerCommandError.self) {
            try await cli.runChecked(["system", "df"])
        }

        #expect(error?.message.contains("tempo") == true)
    }

    @Test func candidatesKeepTheirOrder() {
        #expect(DockerBinaryLocator.candidates(homeDirectory: "/Users/tester") == [
            "/Users/tester/.docker/bin/docker",
            "/Users/tester/.orbstack/bin/docker",
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
            "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
        ])
    }

    @Test(arguments: [
        (["/usr/local/bin/docker", "/Users/tester/.orbstack/bin/docker", "/Users/tester/.docker/bin/docker"], "/Users/tester/.docker/bin/docker"),
        (["/usr/local/bin/docker", "/Users/tester/.orbstack/bin/docker"], "/Users/tester/.orbstack/bin/docker"),
        (["/Applications/OrbStack.app/Contents/MacOS/xbin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker"], "/Applications/Docker.app/Contents/Resources/bin/docker"),
        (["/Applications/OrbStack.app/Contents/MacOS/xbin/docker"], "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"),
    ])
    func locatorTakesTheFirstExecutableCandidate(executables: [String], expected: String) {
        #expect(DockerBinaryLocator.find(homeDirectory: "/Users/tester", isExecutable: Set(executables).contains) == expected)
    }

    @Test func locatorReturnsNilWhenDockerIsNotInstalled() {
        #expect(DockerBinaryLocator.find(homeDirectory: "/Users/tester", isExecutable: { _ in false }) == nil)
    }

    /// Solo Swift: conta un file regolare eseguibile, raggiunto seguendo i collegamenti; un
    /// collegamento orfano non è un binario.
    @Test func onlyAnExecutableFileReachedThroughItsLinksCounts() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let binary = try directory.file("bin/docker")
        #expect(chmod(binary, 0o755) == 0)
        let plain = try directory.file("bin/plain")
        let link = try directory.symlink("links/docker", to: binary)
        let orphan = try directory.symlink("links/orphan", to: directory.path + "/missing/docker")
        let folder = try directory.directory("folder")

        #expect(DockerBinaryLocator.isExecutableFile(binary))
        #expect(DockerBinaryLocator.isExecutableFile(link))
        #expect(!DockerBinaryLocator.isExecutableFile(orphan))
        #expect(!DockerBinaryLocator.isExecutableFile(plain))
        #expect(!DockerBinaryLocator.isExecutableFile(folder))
        #expect(!DockerBinaryLocator.isExecutableFile(directory.path + "/missing/docker"))

        let fifo = directory.path + "/bin/fifo"
        #expect(mkfifo(fifo, 0o755) == 0)
        #expect(chmod(fifo, 0o755) == 0)
        #expect(!DockerBinaryLocator.isExecutableFile(fifo))
    }

    /// Solo Swift: disinstallare Docker Desktop può lasciare `~/.docker/bin/docker` orfano; con il
    /// predicato predefinito il locator passa al binario di OrbStack.
    @Test func locatorSkipsAnOrphanedDockerDesktopLink() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try home.symlink(".docker/bin/docker", to: "/Applications/Docker.app/Contents/Resources/bin/docker-uninstalled")
        let orbStack = try home.file(".orbstack/bin/docker")
        #expect(chmod(orbStack, 0o755) == 0)

        #expect(DockerBinaryLocator.find(homeDirectory: home.path) == orbStack)
    }

    /// Solo Swift: una cartella dove dovrebbe stare il binario non è un binario; il locator passa a
    /// quello di OrbStack.
    @Test func locatorSkipsAFolderWhereTheBinaryShouldBe() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try home.directory(".docker/bin/docker")
        let orbStack = try home.file(".orbstack/bin/docker")
        #expect(chmod(orbStack, 0o755) == 0)

        #expect(DockerBinaryLocator.find(homeDirectory: home.path) == orbStack)
    }
}
