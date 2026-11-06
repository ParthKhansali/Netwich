import Foundation

/// Manages macOS system SOCKS proxy configuration across active network interfaces
/// using the built-in `/usr/sbin/networksetup` command.
///
/// Features automated rollback, state tracking, and crash-recovery so the user's
/// internet is never left interrupted if Merge stops or quits unexpectedly.
public final class SystemProxyManager: @unchecked Sendable {
    public struct ServiceProxyStatus: Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public var isEnabled: Bool
        public var server: String
        public var port: Int
    }

    private let lock = NSLock()
    private var modifiedServices: Set<String> = []
    private let stateFileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let mergeDir = appSupport.appendingPathComponent("Merge", isDirectory: true)
        try? FileManager.default.createDirectory(at: mergeDir, withIntermediateDirectories: true)
        self.stateFileURL = mergeDir.appendingPathComponent("proxy_state.json")

        // Run recovery check on startup in case previous run crashed
        cleanupIfStale()
        registerProcessExitHandlers()
    }

    private func registerProcessExitHandlers() {
        atexit {
            SystemProxyManager.emergencyDisableAll()
        }
        signal(SIGINT) { _ in
            SystemProxyManager.emergencyDisableAll()
            exit(0)
        }
        signal(SIGTERM) { _ in
            SystemProxyManager.emergencyDisableAll()
            exit(0)
        }
        signal(SIGHUP) { _ in
            SystemProxyManager.emergencyDisableAll()
            exit(0)
        }
    }

    /// Emergency synchronous cleanup that directly disables 127.0.0.1 SOCKS proxies on physical services.
    public static func emergencyDisableAll() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()

        guard let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else { return }
        let services = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("An asterisk") &&
                !line.hasPrefix("*") &&
                !line.lowercased().contains("vpn") &&
                !line.lowercased().contains("wireguard") &&
                !line.lowercased().contains("proton")
            }

        for service in services {
            let checkProc = Process()
            checkProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            checkProc.arguments = ["-getsocksfirewallproxy", service]
            let checkPipe = Pipe()
            checkProc.standardOutput = checkPipe
            try? checkProc.run()
            checkProc.waitUntilExit()
            if let checkOut = String(data: checkPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8),
               checkOut.contains("Enabled: Yes") && (checkOut.contains("127.0.0.1") || checkOut.contains("localhost")) {
                let offProc = Process()
                offProc.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                offProc.arguments = ["-setsocksfirewallproxystate", service, "off"]
                try? offProc.run()
                offProc.waitUntilExit()
            }
        }
    }

    /// Returns all available network services configured on the Mac.
    public func listServices() -> [String] {
        guard let output = runNetworkSetup(["-listallnetworkservices"]) else { return [] }
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("An asterisk") &&
                !line.hasPrefix("*") // Disabled services have leading asterisk
            }
    }

    /// Gets SOCKS proxy status for a specific network service.
    public func getStatus(for service: String) -> ServiceProxyStatus {
        guard let output = runNetworkSetup(["-getsocksfirewallproxy", service]) else {
            return ServiceProxyStatus(name: service, isEnabled: false, server: "", port: 0)
        }

        var isEnabled = false
        var server = ""
        var port = 0

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Enabled:") {
                isEnabled = trimmed.lowercased().contains("yes")
            } else if trimmed.hasPrefix("Server:") {
                server = trimmed.replacingOccurrences(of: "Server:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Port:") {
                let portStr = trimmed.replacingOccurrences(of: "Port:", with: "").trimmingCharacters(in: .whitespaces)
                port = Int(portStr) ?? 0
            }
        }

        return ServiceProxyStatus(name: service, isEnabled: isEnabled, server: server, port: port)
    }

    /// Enables system-wide SOCKS proxy for all active network services.
    @discardableResult
    public func enableProxy(host: String = "127.0.0.1", port: UInt16 = 1080) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let services = listServices()
        var newlyModified: Set<String> = []

        for service in services {
            // Configure SOCKS proxy
            let setSuccess = runNetworkSetup(["-setsocksfirewallproxy", service, host, String(port)]) != nil
            let stateSuccess = runNetworkSetup(["-setsocksfirewallproxystate", service, "on"]) != nil

            if setSuccess && stateSuccess {
                newlyModified.insert(service)
            }
        }

        modifiedServices.formUnion(newlyModified)
        saveState()
        return !newlyModified.isEmpty
    }

    /// Disables system-wide SOCKS proxy on all services modified by Merge.
    public func disableProxy() {
        lock.lock()
        defer { lock.unlock() }

        var targets = modifiedServices
        if targets.isEmpty {
            // Only inspect real physical services, filter out VPNs/tunnels
            let physical = listServices().filter { s in
                let lower = s.lowercased()
                return !lower.contains("vpn") && !lower.contains("wireguard") && !lower.contains("tailscale") && !lower.contains("proton")
            }
            targets = Set(physical)
        }

        for service in targets {
            let status = getStatus(for: service)
            // Only disable if pointing to 127.0.0.1
            if status.isEnabled && (status.server == "127.0.0.1" || status.server == "localhost") {
                _ = runNetworkSetup(["-setsocksfirewallproxystate", service, "off"])
            }
        }

        modifiedServices.removeAll()
        saveState()
    }

    /// Verifies if proxy is currently enabled on any service pointing to 127.0.0.1.
    public var isProxyActive: Bool {
        let services = listServices()
        for service in services {
            let status = getStatus(for: service)
            if status.isEnabled && (status.server == "127.0.0.1" || status.server == "localhost") {
                return true
            }
        }
        return false
    }

    // MARK: - State Persistence & Recovery

    private func saveState() {
        let data = try? JSONEncoder().encode(Array(modifiedServices))
        try? data?.write(to: stateFileURL, options: .atomic)
    }

    private func cleanupIfStale() {
        if let data = try? Data(contentsOf: stateFileURL),
           let saved = try? JSONDecoder().decode([String].self, from: data) {
            modifiedServices = Set(saved)
            if !modifiedServices.isEmpty {
                disableProxy()
            }
        }
        // Always run emergency sweep on physical services to ensure no orphaned 127.0.0.1 proxies exist
        SystemProxyManager.emergencyDisableAll()
        try? FileManager.default.removeItem(at: stateFileURL)
    }

    // MARK: - Process Execution

    private func runNetworkSetup(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
