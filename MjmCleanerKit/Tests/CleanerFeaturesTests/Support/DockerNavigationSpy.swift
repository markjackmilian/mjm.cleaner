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

    func showDockerReport(_ result: DockerCleanResult, diskBefore: DockerDiskUsage?, diskAfter: DockerDiskUsage) {
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

func dockerAnalysis(_ candidates: [DockerCandidate], version: String = "27.3.1", disk: DockerDiskUsage? = nil, df: DockerDfSummary = .empty) -> DockerAnalysis {
    DockerAnalysis(
        serverVersion: version,
        snapshot: DockerSnapshot(containers: [], images: [], volumes: [], df: df, existingComposeProjects: []),
        candidates: candidates,
        disk: disk ?? DockerDiskUsage(path: "/Docker.raw", allocatedBytes: 4 * 1_073_741_824, apparentBytes: 64 * 1_073_741_824))
}
