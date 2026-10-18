public enum XcodeRunningState: Sendable, Equatable {
    case unknown
    case notRunning
    case running
}

/// `IXcodeRunningProbe`.
public protocol XcodeRunningProbing: Sendable {
    /// Lancia solo `CancellationError`.
    func state() async throws -> XcodeRunningState
}

/// Legge direttamente i percorsi dei processi: un elenco non disponibile non deve mai essere
/// scambiato per «Xcode chiuso».
public struct XcodeRunningProbe: XcodeRunningProbing {
    private static let timeout: Duration = .seconds(5)
    private static let bundleMarkers = ["/Xcode.app/Contents/MacOS/", "/Xcode-beta.app/Contents/MacOS/"]

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func state() async throws -> XcodeRunningState {
        do {
            let result = try await runner.run("ps", ["-axo", "comm="], timeout: Self.timeout)
            guard !result.timedOut, result.exitCode == 0, XcodeText.isNullOrWhiteSpace(result.standardError) else {
                return .unknown
            }

            // Equivalente della regex `/(?:Xcode|Xcode-beta)\.app/Contents/MacOS/` con IgnoreCase.
            let running = XcodeText.lines(result.standardOutput).contains { path in
                Self.bundleMarkers.contains { XcodeText.containsIgnoringCase(path, $0) }
            }
            return running ? .running : .notRunning
        } catch is CancellationError where Task.isCancelled {
            throw CancellationError()
        } catch {
            return .unknown
        }
    }
}
