import Foundation

/// Esegue solo i comandi d'inventario di `simctl` in lettura e le rimozioni mirate per UUID.
public struct XcodeCli: XcodeCliInvoking {
    private static let inventoryTimeout: Duration = .seconds(30)
    private static let deleteTimeout: Duration = .seconds(5 * 60)

    /// Il percorso che l'app C# usava se esiste. Va passato assoluto: `posix_spawnp` cercherebbe
    /// un nome semplice nel PATH dell'app, che lanciata dal Finder è solo /usr/bin:/bin:/usr/sbin:/sbin.
    public static let defaultBinaryPath = "/usr/bin/xcrun"

    private let runner: any ProcessRunning
    private let binaryPath: String?

    public init(runner: any ProcessRunning, binaryPath: String?) {
        self.runner = runner
        self.binaryPath = binaryPath
    }

    /// Come la composizione C#: `xcrun` solo se `/usr/bin/xcrun` esiste, altrimenti nessuno.
    public static func locateBinary(_ fileSystem: any FileSystem) -> String? {
        fileSystem.fileExists(defaultBinaryPath) ? defaultBinaryPath : nil
    }

    @concurrent
    public func readInventory() async throws -> XcodeSnapshot {
        var simctlJson: String?
        var runtimeJson: String?
        var runtimeDeleteSupported = false
        var warnings: [XcodeInventoryWarning] = []

        do {
            let simctl = try await run(["simctl", "list", "--json"], timeout: Self.inventoryTimeout)
            if simctl.timedOut || simctl.exitCode != 0 {
                warnings.append(.completenessFailure(.device, String(localized: "Inventario simulatori non disponibile: \(Self.describe(simctl))", bundle: .module)))
            } else {
                simctlJson = simctl.standardOutput
            }
        } catch let error as XcodeUnavailableError {
            warnings.append(.completenessFailure(.device, error.description))
        }

        do {
            let help = try await run(["simctl", "runtime"], timeout: Self.inventoryTimeout)
            runtimeDeleteSupported = !help.timedOut && Self.listsRuntimeDelete("\(help.standardOutput)\n\(help.standardError)")
        } catch let error as XcodeUnavailableError {
            warnings.append(.completenessFailure(.runtime, error.description))
        }

        do {
            let runtime = try await run(["simctl", "runtime", "list", "--json"], timeout: Self.inventoryTimeout)
            if runtime.timedOut || runtime.exitCode != 0 {
                warnings.append(.completenessFailure(.runtime, String(localized: "Inventario immagini runtime non disponibile: \(Self.describe(runtime))", bundle: .module)))
            } else {
                runtimeJson = runtime.standardOutput
            }

            if !runtimeDeleteSupported {
                warnings.append(.advisory(.runtime, String(localized: "Questa versione di Xcode non supporta la rimozione dei runtime dalla CLI; gestiscili in Xcode Settings.", bundle: .module)))
            }
        } catch let error as XcodeUnavailableError {
            warnings.append(.completenessFailure(.runtime, error.description))
        }

        let parsed = XcodeJson.parseInventory(simctlJson, runtimeJson, runtimeDeleteSupported: runtimeDeleteSupported)
        return XcodeSnapshot(candidates: parsed.candidates, warnings: warnings + parsed.warnings)
    }

    public func deleteDevice(_ uuid: String) async throws -> ProcessResult {
        try Self.validateUuid(uuid)
        return try await run(["simctl", "delete", uuid], timeout: Self.deleteTimeout)
    }

    public func deleteRuntime(_ uuid: String) async throws -> ProcessResult {
        try Self.validateUuid(uuid)
        return try await run(["simctl", "runtime", "delete", uuid], timeout: Self.deleteTimeout)
    }

    private func run(_ arguments: [String], timeout: Duration) async throws -> ProcessResult {
        guard let binaryPath else {
            throw XcodeUnavailableError(String(localized: "Xcode command line tools non trovati.", bundle: .module))
        }

        do {
            return try await runner.run(binaryPath, arguments, timeout: timeout, environment: Self.environment(binaryPath))
        } catch is ProcessLaunchError {
            throw XcodeUnavailableError(String(localized: "Xcode command line tools non trovati.", bundle: .module))
        }
    }

    /// La cartella di `xcrun` e i percorsi abituali davanti al PATH ereditato, come in C#.
    private static func environment(_ binary: String) -> [String: String] {
        let directory = PathText.parent(binary) ?? "/usr/bin"
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var path = Array("\(directory):/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:\(inherited)".utf8)
        while path.last == UInt8(ascii: ":") { path.removeLast() }
        return ["PATH": String(decoding: path, as: UTF8.self)]
    }

    /// `Guid.TryParseExact(uuid, "D")`: un alias di simctl ("all", "booted", "unavailable") o
    /// un'opzione ("--unusable") non arrivano mai alla riga di comando.
    private static func validateUuid(_ uuid: String) throws {
        guard XcodeUuid.canonicalExact(uuid) != nil else {
            throw XcodeArgumentError(String(localized: "È richiesto un UUID esplicito; gli alias simctl non sono consentiti.", bundle: .module))
        }
    }

    private static func describe(_ result: ProcessResult) -> String {
        if result.timedOut {
            return String(localized: "timeout dopo 30 secondi", bundle: .module)
        }
        return XcodeText.lines(result.standardError).first
            ?? String(localized: "codice di uscita \(result.exitCode)", bundle: .module)
    }

    /// Equivalente della regex `(?m)^\s*delete\s+\(<identifier>` del C#: da un inizio di riga
    /// (inizio del testo o dopo "\n", mai dopo "\r"), spazi facoltativi — anche a capo, come `\s` —
    /// poi "delete", almeno uno spazio e "(<identifier>".
    static func listsRuntimeDelete(_ helpText: String) -> Bool {
        let scalars = Array(helpText.unicodeScalars)
        let keyword = Array("delete".unicodeScalars)
        let argument = Array("(<identifier>".unicodeScalars)

        func matches(_ expected: [Unicode.Scalar], at offset: Int) -> Bool {
            offset + expected.count <= scalars.count && scalars[offset..<(offset + expected.count)].elementsEqual(expected)
        }

        func skipWhiteSpace(from offset: Int) -> Int {
            var position = offset
            while position < scalars.count, XcodeText.isWhiteSpace(scalars[position]) { position += 1 }
            return position
        }

        var lineStart = 0
        while lineStart <= scalars.count {
            let keywordStart = skipWhiteSpace(from: lineStart)
            if matches(keyword, at: keywordStart) {
                let afterKeyword = keywordStart + keyword.count
                let argumentStart = skipWhiteSpace(from: afterKeyword)
                if argumentStart > afterKeyword && matches(argument, at: argumentStart) { return true }
            }
            guard let newline = scalars[lineStart...].firstIndex(of: "\n") else { return false }
            lineStart = newline + 1
        }
        return false
    }
}
