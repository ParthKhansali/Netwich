import Foundation

/// Result of a short-lived helper process.
public struct CommandResult: Sendable {
    public var status: Int32
    public var output: String
    public var timedOut: Bool

    public var succeeded: Bool { status == 0 && !timedOut }

    public init(status: Int32, output: String, timedOut: Bool = false) {
        self.status = status
        self.output = output
        self.timedOut = timedOut
    }
}

/// Runs macOS helper tools without the classic deadlock.
///
/// The previous implementation called `waitUntilExit()` and only then drained the
/// pipe. That works for tiny outputs and hangs forever for large ones, because the
/// child blocks on a full pipe while we block waiting for it to exit. Here the pipe
/// is drained on a second thread while the parent waits, and a watchdog terminates
/// anything that tries to sit on a TTY prompt.
public enum ProcessRunner {
    public static let networksetup = "/usr/sbin/networksetup"

    /// Runs `executable` with `arguments` and returns its combined output.
    public static func run(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 20,
        stdin: String? = nil
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        if let stdin {
            let input = Pipe()
            process.standardInput = input
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try? input.fileHandleForWriting.close()
        }

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }

        // Drain both pipes concurrently, then wait. Reading to EOF returns when the
        // child closes its descriptors (i.e. exits), so this cannot deadlock.
        let collected = LockedString()
        let drained = DispatchGroup()
        for pipe in [stdout, stderr] {
            drained.enter()
            DispatchQueue.global(qos: .utility).async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collected.append(String(decoding: data, as: UTF8.self))
                drained.leave()
            }
        }

        let finished = drained.wait(timeout: .now() + timeout)
        if finished == .timedOut {
            process.terminate()
            process.waitUntilExit()
            return CommandResult(status: process.terminationStatus, output: collected.value, timedOut: true)
        }

        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: collected.value)
    }

    /// Returns true when `networksetup` refuses a write because we lack rights.
    public static func isPermissionFailure(_ result: CommandResult) -> Bool {
        let text = result.output.lowercased()
        return text.contains("requires admin")
            || text.contains("administrator")
            || text.contains("must be root")
            || text.contains("not authorized")
            || result.timedOut
    }
}

/// Minimal thread-safe string box used while draining pipes.
final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ text: String) {
        lock.lock()
        storage += text
        lock.unlock()
    }
}

/// Elevates a batch of shell commands through AppleScript.
///
/// `networksetup` write commands require administrator rights. macOS shows a single
/// native authentication dialog for the whole batch, which is exactly the "one
/// password, explained, then never again" moment we want in onboarding.
public enum PrivilegedShell {
    public enum ElevationError: LocalizedError {
        case cancelled
        case failed(String)

        public var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Administrator access was not granted. Netwich needs it once to switch your network proxy on and off."
            case .failed(let message):
                return "Could not apply network settings: \(message)"
            }
        }
    }

    /// Runs `commands` (each an argv array) in one elevated shell.
    public static func run(_ commands: [[String]], timeout: TimeInterval = 120) throws -> CommandResult {
        guard !commands.isEmpty else { return CommandResult(status: 0, output: "") }

        let shellLine = commands
            .map { $0.map(shellQuote).joined(separator: " ") }
            .joined(separator: " && ")

        // AppleScript string literal: escape backslashes, then double quotes.
        let appleScriptLiteral = shellLine
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = "do shell script \"\(appleScriptLiteral)\" with administrator privileges"
        let result = ProcessRunner.run("/usr/bin/osascript", ["-e", script], timeout: timeout)

        if result.timedOut {
            throw ElevationError.cancelled
        }
        let output = result.output
        if output.contains("-128") || output.lowercased().contains("user canceled") {
            throw ElevationError.cancelled
        }
        guard result.status == 0 else {
            throw ElevationError.failed(output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    /// POSIX single-quote quoting: safe for any argument contents.
    static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/:@")
        if value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
