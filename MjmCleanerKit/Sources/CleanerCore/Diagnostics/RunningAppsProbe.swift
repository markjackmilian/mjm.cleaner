import Foundation

public protocol RunningAppsProbing: Sendable {
    func affectedApps(_ paths: [String]) async -> [String]
}

/// Euristica: svuotare la cache di un'applicazione aperta può farla comportare in modo anomalo
/// fino al riavvio, quindi conviene avvisare prima di eliminare.
public struct RunningAppsProbe: RunningAppsProbing {
    private static let minimumWordLength = 4
    private static let bundleMarker = ".app/"
    private static let executableMarker = ".app/Contents/MacOS/"
    private static let psTimeout: Duration = .seconds(5)

    private let processNames: @Sendable () async -> [String]

    public init(processNames: @escaping @Sendable () async -> [String]) {
        self.processNames = processNames
    }

    public func affectedApps(_ paths: [String]) async -> [String] {
        var seenProcesses = Set<String>()
        var candidates: [(fullName: String, significantWords: [String])] = []
        for name in await processNames() where seenProcesses.insert(name.lowercased()).inserted {
            let words = Self.splitIntoWords(name).filter { $0.utf16.count >= Self.minimumWordLength }
            if !words.isEmpty { candidates.append((name, words)) }
        }

        guard !candidates.isEmpty else { return [] }

        var folderWords = Set<String>()
        for path in paths {
            for word in Self.splitIntoWords(PathText.fileName(path)) {
                folderWords.insert(word.lowercased())
            }
        }

        var affected: [String: String] = [:]
        for candidate in candidates where candidate.significantWords.contains(where: { folderWords.contains($0.lowercased()) }) {
            let key = candidate.fullName.lowercased()
            if affected[key] == nil { affected[key] = candidate.fullName }
        }

        return affected.values.sorted { $0.compare($1, options: [.caseInsensitive, .literal]) == .orderedAscending }
    }

    /// Scompone un nome nelle sue parole (separatori: punto, spazio, trattino, trattino basso),
    /// per confrontare parole intere: "Dock" non deve corrispondere a "com.docker.docker".
    private static func splitIntoWords(_ value: String) -> [String] {
        value.split(whereSeparator: { ".- _".contains($0) }).map(String.init)
    }

    // Raccolta dei nomi sulla macchina reale: non basta il nome breve del processo. Conta che sia
    // un'applicazione che l'utente può chiudere: si chiede a `ps` il percorso completo e si tengono
    // solo gli eseguibili dentro un bundle .app in /Applications, /System/Applications o sotto la
    // home — non sotto /System/Library, dove vivono agenti di sistema (ControlCenter, WiFiAgent)
    // che l'utente non percepisce come "un'app aperta".

    public static func forCurrentMachine(runner: any ProcessRunning = ProcessRunner(), home: String = NSHomeDirectory()) -> RunningAppsProbe {
        RunningAppsProbe {
            RunningAppsProbe.extractApplicationNames(await RunningAppsProbe.collectProcessPaths(runner), home: home)
        }
    }

    /// Dai percorsi completi dei processi (forma di `ps -axo comm=`) ai nomi delle applicazioni
    /// utente: per ciascuno, il nome del primo bundle .app nel percorso, cioè l'app visibile e non un
    /// suo Helper annidato (".../Claude.app/.../Claude Helper.app/..." → "Claude").
    public static func extractApplicationNames(_ processPaths: [String], home: String = NSHomeDirectory()) -> [String] {
        let allowedRoots = ["/Applications/", "/System/Applications/", PathText.trimmingTrailingSlashes(home) + "/"]
        var seen = Set<String>()
        var names: [String] = []

        for path in processPaths {
            guard !path.allSatisfy(\.isWhitespace),
                  path.contains(executableMarker),
                  allowedRoots.contains(where: { path.hasPrefix($0) }),
                  let bundleName = firstBundleName(path) else {
                continue
            }
            if seen.insert(bundleName.lowercased()).inserted {
                names.append(bundleName)
            }
        }

        return names
    }

    private static func firstBundleName(_ path: String) -> String? {
        guard let bundle = path.range(of: bundleMarker) else { return nil }
        let beforeBundle = path[..<bundle.lowerBound]
        let name = beforeBundle.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? String(beforeBundle)
        return name.isEmpty ? nil : name
    }

    /// L'unico punto che dipende da un comando esterno. Un avviso che non si può calcolare non deve
    /// mai impedire una pulizia: qualunque fallimento restituisce un elenco vuoto.
    static func collectProcessPaths(_ runner: any ProcessRunning) async -> [String] {
        do {
            let result = try await runner.run("ps", ["-axo", "comm="], timeout: psTimeout)
            guard !result.timedOut, result.exitCode == 0 else { return [] }
            return result.standardOutput
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
}
