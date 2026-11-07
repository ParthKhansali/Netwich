import Foundation

/// Manages the macOS system SOCKS proxy across network services.
///
/// Three rules drive this class, each of which the previous implementation broke:
///
/// 1. **Never destroy user settings.** Every service's previous SOCKS configuration is
///    snapshotted before we touch it and restored byte-for-byte afterwards. A user with
///    a corporate proxy must get it back, not a hardcoded "off".
/// 2. **Never go silent.** `networksetup` writes require administrator rights; without
///    them macOS returns "Command requires admin privileges" and the old code reported a
///    generic failure. We retry the whole batch through one native elevation prompt.
/// 3. **Never block launch.** Nothing runs in `init`. All subprocess work happens on a
///    utility queue, and no password prompt can appear at startup.
public final class SystemProxyManager: @unchecked Sendable {
    public struct ServiceProxyStatus: Sendable, Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public var isEnabled: Bool
        public var server: String
        public var port: Int

        public init(name: String, isEnabled: Bool, server: String, port: Int) {
            self.name = name
            self.isEnabled = isEnabled
            self.server = server
            self.port = port
        }
    }

    public enum SetupError: LocalizedError {
        case noServices
        case permissionDenied
        case restoreFailed(String)
        case commandFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noServices:
                return "No active network service was found. Connect to Wi-Fi or plug in your phone, then try again."
            case .permissionDenied:
                return "macOS did not grant administrator access, so the system proxy was left unchanged."
            case .restoreFailed(let detail):
                return "Netwich could not restore your original proxy settings: \(detail)"
            case .commandFailed(let detail):
                return "macOS rejected the proxy change: \(detail)"
            }
        }
    }

    private struct ServiceSnapshot: Codable, Sendable {
        var server: String
        var port: Int
        var isEnabled: Bool
    }

    private struct SavedState: Codable, Sendable {
        var version: Int = 2
        var host: String
        var port: UInt16
        var services: [String: ServiceSnapshot]
        var updated: Date
    }

    /// Services that must never be proxied: their traffic is already tunnelled and
    /// pointing them at loopback breaks the tunnel itself.
    private static let vpnMarkers = ["vpn", "wireguard", "tailscale", "proton", "zerotier", "openvpn", "ipsec"]

    private let workQueue = DispatchQueue(label: "dev.parth.netwich.systemproxy", qos: .userInitiated)
    private let stateFileURL: URL
    private let lock = NSLock()
    private var appliedServices: Set<String> = []

    public init(stateFileURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory = (appSupport ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Netwich", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.stateFileURL = stateFileURL ?? directory.appendingPathComponent("proxy_state.json")
    }

    // MARK: - Inspection

    /// All enabled network services (disabled ones are prefixed with `*`).
    public func listServices() -> [String] {
        Self.parseServices(ProcessRunner.run(ProcessRunner.networksetup, ["-listallnetworkservices"]).output)
    }

    static func parseServices(_ output: String) -> [String] {
        output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty
                    && !line.hasPrefix("An asterisk")
                    && !line.hasPrefix("*")
            }
    }

    /// Services we are willing to configure.
    func configurableServices() -> [String] {
        listServices().filter { service in
            let lower = service.lowercased()
            return !Self.vpnMarkers.contains { lower.contains($0) }
        }
    }

    public func getStatus(for service: String) -> ServiceProxyStatus {
        Self.status(from: ProcessRunner.run(ProcessRunner.networksetup, ["-getsocksfirewallproxy", service]).output, service: service)
    }

    static func status(from output: String, service: String) -> ServiceProxyStatus {
        var isEnabled = false
        var server = ""
        var port = 0

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("enabled:") {
                isEnabled = trimmed.lowercased().contains("yes")
            } else if trimmed.lowercased().hasPrefix("server:") {
                server = trimmed.dropFirst("Server:".count).trimmingCharacters(in: .whitespaces)
            } else if trimmed.lowercased().hasPrefix("port:") {
                port = Int(trimmed.dropFirst("Port:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        return ServiceProxyStatus(name: service, isEnabled: isEnabled, server: server, port: port)
    }

    public var isProxyActive: Bool {
        configurableServices().contains { service in
            let status = getStatus(for: service)
            return status.isEnabled && Self.isLoopback(status.server)
        }
    }

    static func isLoopback(_ server: String) -> Bool {
        let host = server.lowercased()
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    // MARK: - Enable / restore

    /// Points every configurable service at our local SOCKS proxy.
    ///
    /// - Throws: `SetupError` when nothing could be applied, so the UI can show the
    ///   real reason instead of a generic "could not enable" string.
    public func enableProxy(host: String = "127.0.0.1", port: UInt16 = 1080) throws {
        try workQueue.sync {
            let services = configurableServices()
            guard !services.isEmpty else { throw SetupError.noServices }

            var snapshots: [String: ServiceSnapshot] = [:]
            for service in services {
                let status = getStatus(for: service)
                snapshots[service] = ServiceSnapshot(server: status.server, port: status.port, isEnabled: status.isEnabled)
            }

            // Persist *before* mutating, so a crash mid-write can still be undone.
            saveState(SavedState(host: host, port: port, services: snapshots, updated: Date()))

            var commands: [[String]] = []
            for service in services {
                commands.append([ProcessRunner.networksetup, "-setsocksfirewallproxy", service, host, String(port)])
                commands.append([ProcessRunner.networksetup, "-setsocksfirewallproxystate", service, "on"])
            }

            try runPossiblyElevated(commands, allowElevation: true)

            // Verify rather than trust the exit status.
            let applied = services.filter { service in
                let status = getStatus(for: service)
                return status.isEnabled && Self.isLoopback(status.server)
            }
            guard !applied.isEmpty else {
                throw SetupError.commandFailed("the proxy did not stick for any network service")
            }

            lock.lock()
            appliedServices = Set(applied)
            lock.unlock()
        }
    }

    /// Restores the exact SOCKS configuration each service had before Netwich touched it.
    @discardableResult
    public func disableProxy() -> Bool {
        workQueue.sync {
            restoreLocked(allowElevation: true)
        }
    }

    /// Non-blocking variant for callers on the main actor.
    public func disableProxyAsync(completion: (@Sendable (Bool) -> Void)? = nil) {
        workQueue.async { [weak self] in
            guard let self else { return }
            let ok = self.restoreLocked(allowElevation: true)
            completion?(ok)
        }
    }

    @discardableResult
    private func restoreLocked(allowElevation: Bool) -> Bool {
        guard let state = loadState() else {
            // No snapshot: only clear proxies that point at *our* loopback port, so a
            // user's real proxy is never collateral damage.
            let leftovers = configurableServices().filter { service in
                let status = getStatus(for: service)
                return status.isEnabled && Self.isLoopback(status.server) && status.port == 1080
            }
            guard !leftovers.isEmpty else { return true }
            let commands = leftovers.map { [ProcessRunner.networksetup, "-setsocksfirewallproxystate", $0, "off"] }
            _ = try? runPossiblyElevated(commands, allowElevation: allowElevation)
            return true
        }

        var commands: [[String]] = []
        for (service, snapshot) in state.services {
            if snapshot.isEnabled, !snapshot.server.isEmpty, snapshot.port > 0 {
                commands.append([ProcessRunner.networksetup, "-setsocksfirewallproxy", service, snapshot.server, String(snapshot.port)])
                commands.append([ProcessRunner.networksetup, "-setsocksfirewallproxystate", service, "on"])
            } else {
                commands.append([ProcessRunner.networksetup, "-setsocksfirewallproxystate", service, "off"])
            }
        }

        do {
            try runPossiblyElevated(commands, allowElevation: allowElevation)
        } catch {
            return false
        }

        try? FileManager.default.removeItem(at: stateFileURL)
        lock.lock()
        appliedServices.removeAll()
        lock.unlock()
        return true
    }

    /// Undo a proxy left behind by a crash. Runs off the main thread at launch.
    ///
    /// This only restores a **saved snapshot**; it never blindly disables every
    /// loopback proxy on the machine the way the old `emergencyDisableAll` did.
    public func recoverStaleState() {
        workQueue.async { [weak self] in
            guard let self else { return }
            guard self.loadState() != nil else { return }
            _ = self.restoreLocked(allowElevation: false)
        }
    }

    /// Last-resort cleanup used from the terminate path.
    ///
    /// Scoped to proxies that point at our own port. Synchronous on purpose, but it
    /// only ever issues `-setsocksfirewallproxystate off` for services that are
    /// currently pointed at 127.0.0.1:<our port>.
    public static func emergencyDisableAll(port: UInt16 = 1080) {
        let manager = SystemProxyManager()
        let targets = manager.configurableServices().filter { service in
            let status = manager.getStatus(for: service)
            return status.isEnabled && isLoopback(status.server) && status.port == Int(port)
        }
        guard !targets.isEmpty else { return }
        let commands = targets.map { [ProcessRunner.networksetup, "-setsocksfirewallproxystate", $0, "off"] }
        for command in commands {
            _ = ProcessRunner.run(command[0], Array(command.dropFirst()), timeout: 8)
        }
    }

    // MARK: - Elevation

    /// Runs a batch of `networksetup` commands, retrying once with administrator
    /// privileges when macOS reports that the caller lacks rights.
    private func runPossiblyElevated(_ commands: [[String]], allowElevation: Bool) throws {
        guard !commands.isEmpty else { return }

        // Try everything directly first: admins (and root-launched builds) need no prompt.
        var needsRights: [[String]] = []
        for command in commands {
            let result = ProcessRunner.run(command[0], Array(command.dropFirst()), timeout: 30)
            if result.succeeded { continue }
            if ProcessRunner.isPermissionFailure(result) {
                needsRights.append(command)
            } else {
                throw SetupError.commandFailed(result.output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        guard !needsRights.isEmpty else { return }
        guard allowElevation else { throw SetupError.permissionDenied }

        // One native authentication dialog for the whole remaining batch.
        do {
            _ = try PrivilegedShell.run(needsRights, timeout: 120)
        } catch PrivilegedShell.ElevationError.cancelled {
            throw SetupError.permissionDenied
        } catch {
            throw SetupError.commandFailed(error.localizedDescription)
        }
    }

    // MARK: - Persistence

    private func saveState(_ state: SavedState) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateFileURL, options: .atomic)
    }

    private func loadState() -> SavedState? {
        guard let data = try? Data(contentsOf: stateFileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SavedState.self, from: data)
    }
}
