import CleanerCore
import CleanerFeatures

@MainActor
final class DockerNavigationSpy: NavigationSpy, DockerNavigating {
    private(set) var reportResult: DockerCleanResult?
    private(set) var reportDiskBefore: DockerDiskUsage?
    private(set) var reportDiskAfter: DockerDiskUsage?

    func showDocker() {
        record("docker")
    }

    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage?) {
        record("dockerReport")
        reportResult = result
        reportDiskBefore = diskBefore
        reportDiskAfter = diskAfter
    }
}

/// Candidati Docker per i test delle pagine: i campi che le pagine leggono, il resto fisso.
func dockerCandidate(
    _ kind: DockerResourceKind,
    _ id: String,
    verdict: DockerVerdict,
    rule: String = "rule",
    size: Int64? = 100 * 1024 * 1024,
    cost: String = ""
) -> DockerCandidate {
    DockerCandidate(kind: kind, id: id, displayName: "nome-\(id)", sizeBytes: size, verdict: verdict, ruleId: rule, reason: "motivo", cost: cost)
}

/// Il motore delle analisi di prova, se il test non ne sceglie un altro.
let dockerDesktop = DockerEngine(serverVersion: "27.3.1", operatingSystem: "Docker Desktop")

func dockerAnalysis(
    _ candidates: [DockerCandidate],
    engine: DockerEngine = dockerDesktop,
    disk: DockerDiskUsage? = DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824),
    df: DockerDfSummary = .empty
) -> DockerAnalysis {
    DockerAnalysis(
        engine: engine,
        snapshot: DockerSnapshot(containers: [], images: [], volumes: [], df: df, existingComposeProjects: []),
        candidates: candidates,
        disk: disk)
}
