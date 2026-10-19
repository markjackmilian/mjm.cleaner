import Foundation

/// Un bundle estratto da uno ZIP verificato, pronto da installare.
public struct VerifiedUpdate: Sendable, Equatable {
    public let release: AvailableRelease
    /// `<updates>/<tag>/expanded/<nome>.app`.
    public let bundlePath: String

    public init(release: AvailableRelease, bundlePath: String) {
        self.release = release
        self.bundlePath = bundlePath
    }
}

/// Estrae lo ZIP e accetta il bundle solo se è una build Release di mjm.cleaner per la versione
/// del tag, con firma valida e universale. Ogni controllo che fallisce cancella la cartella della
/// release (ZIP compreso): al giro successivo si riscarica da capo.
public struct UpdateVerifier: Sendable {
    static let expandedName = "expanded"

    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning) {
        self.runner = runner
    }

    public func verify(_ download: DownloadedUpdate) async throws -> VerifiedUpdate {
        do {
            return try await check(download)
        } catch {
            try? FileManager.default.removeItem(atPath: download.directory)
            throw error
        }
    }

    private func check(_ download: DownloadedUpdate) async throws -> VerifiedUpdate {
        let manager = FileManager.default
        let expanded = PathText.join(download.directory, Self.expandedName)
        try? manager.removeItem(atPath: expanded)
        try manager.createDirectory(atPath: expanded, withIntermediateDirectories: true)

        guard try await succeeds("/usr/bin/ditto", ["-x", "-k", download.zipPath, expanded], timeout: .seconds(120)) else {
            throw invalid(String(localized: "lo ZIP non si estrae", bundle: .module))
        }

        let entries = try manager.contentsOfDirectory(atPath: expanded)
        guard entries.count == 1, let name = entries.first, name.hasSuffix(".app"),
              (try? manager.attributesOfItem(atPath: PathText.join(expanded, name))[.type] as? FileAttributeType) == .typeDirectory
        else {
            throw invalid(String(localized: "lo ZIP non contiene un solo bundle .app", bundle: .module))
        }
        let bundle = PathText.join(expanded, name)

        guard let data = manager.contents(atPath: PathText.join(bundle, "Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            throw invalid(String(localized: "Info.plist illeggibile", bundle: .module))
        }
        guard (info["CFBundleIdentifier"] as? String) == UpdateContext.releaseBundleIdentifier else {
            throw invalid(String(localized: "bundle id diverso da \(UpdateContext.releaseBundleIdentifier)", bundle: .module))
        }
        guard (info["CFBundleShortVersionString"] as? String) == download.release.version.description else {
            throw invalid(String(localized: "versione del bundle diversa da \(download.release.version.description)", bundle: .module))
        }
        guard let executableName = info["CFBundleExecutable"] as? String, !executableName.isEmpty,
              !executableName.contains("/"),
              manager.isExecutableFile(atPath: PathText.join(bundle, "Contents/MacOS/" + executableName)),
              (try? manager.attributesOfItem(atPath: PathText.join(bundle, "Contents/MacOS/" + executableName))[.type] as? FileAttributeType) == .typeRegular
        else {
            throw invalid(String(localized: "eseguibile mancante", bundle: .module))
        }
        let executable = PathText.join(bundle, "Contents/MacOS/" + executableName)

        guard try await succeeds("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundle], timeout: .seconds(120)) else {
            throw invalid(String(localized: "firma del codice non valida", bundle: .module))
        }

        let archs = try await runner.run("/usr/bin/lipo", ["-archs", executable], timeout: .seconds(30))
        let found = Set(archs.standardOutput.split(whereSeparator: \.isWhitespace).map(String.init))
        guard archs.exitCode == 0, !archs.timedOut, found.isSuperset(of: ["arm64", "x86_64"]) else {
            throw invalid(String(localized: "il bundle non è universale (arm64 e x86_64)", bundle: .module))
        }

        return VerifiedUpdate(release: download.release, bundlePath: bundle)
    }

    private func succeeds(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> Bool {
        let result = try await runner.run(executable, arguments, timeout: timeout)
        return result.exitCode == 0 && !result.timedOut
    }

    private func invalid(_ reason: String) -> UpdateError {
        .invalidBundle(reason)
    }
}
