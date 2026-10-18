/// `IXcodeSizeProbe`: stime in sola lettura, `nil` quando la misura non è affidabile.
public protocol XcodeSizeProbing: Sendable {
    /// Byte allocati sotto `path`, o `nil`. Lancia solo `CancellationError` e gli errori fuori
    /// contratto del runner (in C# le eccezioni non elencate nel filtro).
    func measure(_ path: String) async throws -> Int64?
    /// Spazio libero del volume della home, o `nil`. Lancia solo `CancellationError`.
    func freeBytes() async throws -> Int64?
}

/// Dimensione allocata (via `du`) e spazio libero del volume che contiene la home.
public struct XcodeSizeProbe: XcodeSizeProbing {
    private static let measureTimeout: Duration = .seconds(30)

    private let fileSystem: any FileSystem
    private let runner: any ProcessRunning
    private let links: any LinkInspecting
    private let homeDirectory: String

    public init(fileSystem: any FileSystem, runner: any ProcessRunning, links: any LinkInspecting, homeDirectory: String) {
        self.fileSystem = fileSystem
        self.runner = runner
        self.links = links
        self.homeDirectory = homeDirectory
    }

    @concurrent
    public func measure(_ path: String) async throws -> Int64? {
        guard path.utf8.first == UInt8(ascii: "/"), !links.isSymbolicLink(path),
              fileSystem.fileExists(path) || fileSystem.directoryExists(path) else {
            return nil
        }

        let result: ProcessResult
        do {
            // Il du di BSD non segue i collegamenti simbolici per default; -P lo rende esplicito.
            // Un'uscita non nulla, un timeout o un output parziale non sono una stima utilizzabile.
            result = try await runner.run("du", ["-k", "-s", "-P", path], timeout: Self.measureTimeout)
        } catch is FileSystemError, is ProcessLaunchError, is XcodeArgumentError, is XcodeOperationError {
            // Gli errori che il C# filtrava (IOException, UnauthorizedAccessException,
            // Win32Exception, ArgumentException, InvalidOperationException): misura sconosciuta.
            return nil
        }

        guard result.exitCode == 0, !result.timedOut, XcodeText.isNullOrWhiteSpace(result.standardError) else { return nil }

        let rows = XcodeText.lines(result.standardOutput)
        guard rows.count == 1, let row = rows.first else { return nil }

        // Il primo campo, fino al primo tab o spazio; solo cifre ASCII (NumberStyles.None).
        let first = String(String.UnicodeScalarView(row.unicodeScalars.prefix { $0 != "\t" && $0 != " " }))
        guard !first.isEmpty, first.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
              let kilobytes = Int64(first), kilobytes <= Int64.max / 1024 else {
            return nil
        }
        return kilobytes * 1024
    }

    @concurrent
    public func freeBytes() async throws -> Int64? {
        try Task.checkCancellation()
        do {
            return try fileSystem.availableFreeSpace(forVolumeContaining: homeDirectory)
        } catch {
            return nil
        }
    }
}
