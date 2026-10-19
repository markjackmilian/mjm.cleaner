/// `allocatedBytes`: spazio realmente occupato sul disco (blocchi allocati, come `du`).
/// `apparentBytes`: dimensione apparente; per un file sparse è solo il limite massimo del disco
/// virtuale.
public struct DockerDiskUsage: Sendable, Equatable {
    public let path: String
    public let allocatedBytes: Int64?
    public let apparentBytes: Int64?

    public init(path: String, allocatedBytes: Int64?, apparentBytes: Int64?) {
        self.path = path
        self.allocatedBytes = allocatedBytes
        self.apparentBytes = apparentBytes
    }

    public var exists: Bool { apparentBytes != nil }
}

/// Misura il disco virtuale di Docker Desktop. `Docker.raw` è un file sparse: la sua dimensione
/// apparente (misurata: 994 GB) è il limite configurato, non lo spazio occupato (8,3 GB nello stesso
/// momento). Solo i blocchi allocati dicono quanto disco si è recuperato. Il file si legge e basta:
/// la deny-list continua a proteggere l'intera cartella di Docker.
public struct DiskUsageProbe: Sendable {
    private static let duTimeout: Duration = .seconds(20)

    private let runner: any ProcessRunning
    private let fileSystem: any FileSystem
    private let diskImagePath: String

    public init(runner: any ProcessRunning, fileSystem: any FileSystem, diskImagePath: String) {
        self.runner = runner
        self.fileSystem = fileSystem
        self.diskImagePath = diskImagePath
    }

    public static func defaultPath(_ homeDirectory: String) -> String {
        "\(PathText.trimmingTrailingSlashes(homeDirectory))/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"
    }

    /// Il disco virtuale del motore che risponde. Si misura solo `Docker.raw` di Docker Desktop:
    /// OrbStack riduce da solo il suo `data.img.raw`, che sta in un group container protetto da
    /// macOS (leggerlo chiederebbe all'utente l'accesso ai dati di altre app), e degli altri motori
    /// non si sa dove sia il disco. `nil`: nessun accesso al filesystem, nessun `du`.
    @concurrent
    public func measure(for engine: DockerEngine) async throws -> DockerDiskUsage? {
        guard engine.kind == .dockerDesktop else { return nil }
        return try await measure()
    }

    /// Lancia solo `CancellationError`: una misura non disponibile non deve impedire né l'analisi né
    /// la pulizia.
    @concurrent
    public func measure() async throws -> DockerDiskUsage {
        // Altre piattaforme o un disco spostato altrove: il file può non esistere, e allora non c'è
        // nulla da misurare.
        guard fileSystem.fileExists(diskImagePath) else {
            return DockerDiskUsage(path: diskImagePath, allocatedBytes: nil, apparentBytes: nil)
        }

        let apparent: Int64
        do {
            apparent = try fileSystem.fileLength(diskImagePath)
        } catch is FileSystemError {
            return DockerDiskUsage(path: diskImagePath, allocatedBytes: nil, apparentBytes: nil)
        }

        var allocated: Int64?
        do {
            // `du` per nome, come in C#: sta in /usr/bin, che è nel PATH anche di un'app aperta dal Finder.
            let du = try await runner.run("du", ["-k", diskImagePath], timeout: Self.duTimeout)
            if du.exitCode == 0 && !du.timedOut {
                allocated = Self.parseDuKilobytes(du.standardOutput)
            }
        } catch let error as CancellationError {
            throw error
        } catch {
            // Una misura non disponibile non deve impedire né l'analisi né la pulizia.
        }

        return DockerDiskUsage(path: diskImagePath, allocatedBytes: allocated, apparentBytes: apparent)
    }

    /// Prima colonna dell'output di `du -k`: blocchi da 1 KiB.
    public static func parseDuKilobytes(_ output: String) -> Int64? {
        // `output.Split(['\t', ' ', '\n'], 2, RemoveEmptyEntries).FirstOrDefault()`.
        let separators: Set<UInt8> = [UInt8(ascii: "\t"), UInt8(ascii: " "), UInt8(ascii: "\n")]
        let first = output.utf8.drop { separators.contains($0) }.prefix { !separators.contains($0) }

        // `long.TryParse(…, NumberStyles.None, …)`: solo cifre ASCII, niente segno né spazi.
        guard !first.isEmpty,
              first.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
              let kilobytes = Int64(String(decoding: first, as: UTF8.self)) else {
            return nil
        }
        // Come l'aritmetica non verificata del C#: nessuna trappola su un valore assurdo.
        return kilobytes &* 1024
    }
}
