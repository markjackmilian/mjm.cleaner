import Darwin
import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let timedOut: Bool

    public init(exitCode: Int32, standardOutput: String, standardError: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }
}

public struct ProcessLaunchError: Error, Equatable, Sendable {
    public let executable: String
    public let code: Int32

    public init(executable: String, code: Int32) {
        self.executable = executable
        self.code = code
    }
}

public protocol ProcessRunning: Sendable {
    func run(
        _ executable: String,
        _ arguments: [String],
        timeout: Duration,
        environment: [String: String]?
    ) async throws -> ProcessResult
}

extension ProcessRunning {
    public func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> ProcessResult {
        try await run(executable, arguments, timeout: timeout, environment: nil)
    }
}

/// Avvia un processo con gli argomenti in un array, senza una shell che li reinterpreti: un nome
/// di volume o un template `{{json .}}` non possono diventare un comando diverso da quello scritto.
/// Un nome senza "/" si cerca nel PATH, come `ProcessStartInfo` in .NET.
public final class ProcessRunner: ProcessRunning {
    public init() {}

    public func run(
        _ executable: String,
        _ arguments: [String],
        timeout: Duration,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        try Task.checkCancellation()
        let child = try SpawnedProcess.launch(executable, arguments, environment: environment)

        let outcome: WaitOutcome = await withTaskCancellationHandler {
            await withTaskGroup(of: WaitOutcome.self) { group in
                group.addTask { await child.waitForExit() }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return .timedOut
                }
                let first = await group.next() ?? .timedOut
                if case .timedOut = first {
                    child.killGroup()
                }
                group.cancelAll()
                return first
            }
        } onCancel: {
            child.killGroup()
        }

        // L'annullamento richiesto dal chiamante si propaga come tale; il timeout no.
        try Task.checkCancellation()

        switch outcome {
        case .timedOut:
            // Come in C#: al timeout non si attende l'output, che un nipote sopravvissuto potrebbe
            // tenere aperto indefinitamente.
            return ProcessResult(exitCode: -1, standardOutput: "", standardError: "", timedOut: true)
        case .exited(let status):
            let output = await child.collectOutput()
            return ProcessResult(exitCode: status, standardOutput: output.stdout, standardError: output.stderr, timedOut: false)
        }
    }
}

enum WaitOutcome: Sendable {
    case exited(Int32)
    case timedOut
}

/// Processo figlio avviato con `posix_spawnp` in un proprio process group: al timeout o
/// all'annullamento si termina l'intero gruppo, come `Kill(entireProcessTree: true)` in C#.
/// Foundation `Process` terminerebbe solo il figlio diretto, lasciando vivo `simctl` dietro `xcrun`.
final class SpawnedProcess: Sendable {
    let pid: pid_t
    private let stdoutTask: Task<Data, Never>
    private let stderrTask: Task<Data, Never>
    private let exitTask: Task<Int32, Never>

    private init(pid: pid_t, stdout: Int32, stderr: Int32) {
        self.pid = pid
        stdoutTask = Task.detached { await SpawnedProcess.readToEnd(stdout) }
        stderrTask = Task.detached { await SpawnedProcess.readToEnd(stderr) }
        exitTask = Task.detached { await SpawnedProcess.reap(pid) }
    }

    static func launch(_ executable: String, _ arguments: [String], environment: [String: String]?) throws -> SpawnedProcess {
        var outPipe: [Int32] = [0, 0]
        var errPipe: [Int32] = [0, 0]
        guard pipe(&outPipe) == 0 else { throw ProcessLaunchError(executable: executable, code: errno) }
        guard pipe(&errPipe) == 0 else {
            let code = errno
            close(outPipe[0])
            close(outPipe[1])
            throw ProcessLaunchError(executable: executable, code: code)
        }

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errPipe[1], 2)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // I thread del pool cooperativo di Swift hanno quasi tutti i segnali bloccati e il figlio
        // erediterebbe la maschera: come .NET (pal_process.c), il figlio parte con maschera vuota e
        // gestori predefiniti.
        var noSignals = sigset_t()
        sigemptyset(&noSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        var defaults = sigset_t()
        sigfillset(&defaults)
        sigdelset(&defaults, SIGKILL)
        sigdelset(&defaults, SIGSTOP)
        posix_spawnattr_setsigdefault(&attributes, &defaults)
        posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)
        )
        posix_spawnattr_setpgroup(&attributes, 0)

        var merged = ProcessInfo.processInfo.environment
        for (key, value) in environment ?? [:] { merged[key] = value }

        let argv = ([executable] + arguments).map { strdup($0) } + [nil]
        let envp = merged.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let status = posix_spawnp(&pid, executable, &actions, &attributes, argv, envp)
        close(outPipe[1])
        close(errPipe[1])

        guard status == 0 else {
            close(outPipe[0])
            close(errPipe[0])
            throw ProcessLaunchError(executable: executable, code: status)
        }

        return SpawnedProcess(pid: pid, stdout: outPipe[0], stderr: errPipe[0])
    }

    func waitForExit() async -> WaitOutcome {
        .exited(await exitTask.value)
    }

    func killGroup() {
        // Il gruppo può essere già terminato fra il timeout e il kill: non è un errore.
        _ = killpg(pid, SIGKILL)
    }

    func collectOutput() async -> (stdout: String, stderr: String) {
        _ = await exitTask.value
        let out = await stdoutTask.value
        let err = await stderrTask.value
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    private static func readToEnd(_ descriptor: Int32) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }

    private static func reap(_ pid: pid_t) async -> Int32 {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var status: Int32 = 0
                var result: pid_t = -1
                repeat {
                    result = waitpid(pid, &status, 0)
                } while result == -1 && errno == EINTR
                if result == -1 {
                    // Stato non recuperabile: non viene mai riportato come successo.
                    continuation.resume(returning: -1)
                    return
                }
                // WIFEXITED/WEXITSTATUS e WTERMSIG sono macro C, non importate in Swift.
                let exitCode: Int32 = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                continuation.resume(returning: exitCode)
            }
        }
    }
}
