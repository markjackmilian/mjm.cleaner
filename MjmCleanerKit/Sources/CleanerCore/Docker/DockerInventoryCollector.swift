/// Raccoglie lo stato di Docker con soli comandi di lettura e in formato JSON. Ogni I/O che la
/// classificazione richiede (incluso controllare che la cartella di un progetto compose esista)
/// avviene qui, così che le regole restino funzioni pure dello snapshot.
public struct DockerInventoryCollector: Sendable {
    private static let json = "{{json .}}"
    private static let composeWorkingDirLabel = "com.docker.compose.project.working_dir"

    /// Versione del server e motore con una sola chiamata `docker info`.
    static let engineFormat = #"{"ServerVersion":{{json .ServerVersion}},"OperatingSystem":{{json .OperatingSystem}}}"#

    private let cli: any DockerCommandRunning
    private let fileSystem: any FileSystem

    public init(cli: any DockerCommandRunning, fileSystem: any FileSystem) {
        self.cli = cli
        self.fileSystem = fileSystem
    }

    /// Verifica che il daemon risponda e riconosce il motore che lo esegue.
    public func checkDaemon() async throws -> DockerEngine {
        let info = try DockerJson.parseEngineInfo(try await cli.runChecked(["info", "--format", Self.engineFormat]))
        let version = DockerText.trimmed(info.serverVersion)

        // Senza daemon "docker info" può stampare comunque la parte client e uscire con 0: una
        // versione del server vuota è l'unico segnale affidabile.
        if version.isEmpty {
            throw DockerUnavailableError(DockerUnavailableError.notRunning)
        }

        return DockerEngine(serverVersion: version, operatingSystem: info.operatingSystem)
    }

    @concurrent
    public func collect() async throws -> DockerSnapshot {
        _ = try await checkDaemon()

        // Container compresi quelli fermi (-a): un container fermo tiene in uso immagine e volumi.
        let containerIds = DockerJson.parseLines(try await cli.runChecked(["ps", "-aq", "--no-trunc"]))
        let containers: [DockerContainer] = if containerIds.isEmpty {
            []
        } else {
            try DockerJson.parseContainers(try await cli.runChecked(["container", "inspect"] + containerIds))
        }

        let imageIds = try DockerJson.parseJsonLinesProperty(
            try await cli.runChecked(["images", "--no-trunc", "--format", Self.json]), "ID")
        let volumeNames = try DockerJson.parseJsonLinesProperty(
            try await cli.runChecked(["volume", "ls", "--format", Self.json]), "Name")

        let verbose = try DockerJson.parseDfVerbose(try await cli.runChecked(["system", "df", "-v", "--format", Self.json]))

        let images: [DockerImage] = if imageIds.isEmpty {
            []
        } else {
            try DockerJson.parseImages(try await cli.runChecked(["image", "inspect"] + imageIds), uniqueSizes: verbose.imageUniqueSizes)
        }
        let volumes: [DockerVolume] = if volumeNames.isEmpty {
            []
        } else {
            try DockerJson.parseVolumes(try await cli.runChecked(["volume", "inspect"] + volumeNames), sizes: verbose.volumeSizes)
        }

        let df = try await Self.readDf(cli)

        return DockerSnapshot(
            containers: containers,
            images: images,
            volumes: volumes,
            df: df,
            existingComposeProjects: existingComposeProjects(containers))
    }

    /// Riepilogo di `docker system df`: condiviso con l'esecutore per la misura prima/dopo.
    public static func readDf(_ cli: any DockerCommandRunning) async throws -> DockerDfSummary {
        try DockerJson.parseDfSummary(try await cli.runChecked(["system", "df", "--format", json]))
    }

    /// I volumi compose portano solo il nome del progetto; la sua cartella si legge dalle etichette
    /// dei container dello stesso progetto. Le cartelle trovate nei progetti dell'utente si
    /// aggiungono in fase di classificazione (`ProjectReferences.composeProjects`).
    private func existingComposeProjects(_ containers: [DockerContainer]) -> Set<String> {
        var projects = Set<String>()

        for container in containers {
            if let project = container.labels[VolumeRuleContext.composeProjectLabel],
               let directory = container.labels[Self.composeWorkingDirLabel],
               fileSystem.directoryExists(directory) {
                projects.insert(project)
            }
        }

        return projects
    }
}
