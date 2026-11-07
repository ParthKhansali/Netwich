import Foundation

/// Manages macOS scoped default routes (`-ifscope <interface>`) for multi-adapter internet aggregation.
///
/// On macOS Darwin, socket binding via `IP_BOUND_IF` looks up routing destinations strictly within
/// that interface's scoped routing table. macOS only creates a scoped default route for non-primary
/// interfaces, and frequently strips it when a tether or secondary interface is connected.
///
/// `ScopedRouteManager` monitors active interfaces, ensures every active adapter has an operative
/// scoped default route, and cleans up after itself on disable or crash recovery.
public final class ScopedRouteManager: @unchecked Sendable {
    public static let shared = ScopedRouteManager()

    private let lock = NSLock()
    private var addedRoutes: [String: String] = [:] // [interface: gateway]
    private let routeQueue = DispatchQueue(label: "dev.parth.merge.routes", qos: .utility)
    private let stateFileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let netwichDir = appSupport.appendingPathComponent("Netwich", isDirectory: true)
        let legacyMergeDir = appSupport.appendingPathComponent("Merge", isDirectory: true)
        let legacyFile = legacyMergeDir.appendingPathComponent("scoped_routes.json")
        let netwichFile = netwichDir.appendingPathComponent("scoped_routes.json")

        try? FileManager.default.createDirectory(at: netwichDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: legacyFile.path) && !FileManager.default.fileExists(atPath: netwichFile.path) {
            try? FileManager.default.copyItem(at: legacyFile, to: netwichFile)
        }
        self.stateFileURL = netwichFile

        // Cleanup any leftover routes from previous crashes
        cleanupStale()
    }

    /// Discovers the router gateway for a network interface.
    public func discoverGateway(for interface: String) -> String? {
        // 1. Try ipconfig getoption
        if let out = runCommand("/usr/sbin/ipconfig", arguments: ["getoption", interface, "router"]) {
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidIPv4(trimmed) {
                return trimmed
            }
        }

        // 2. Try netstat routing table inspection
        if let netstatOut = runCommand("/usr/sbin/netstat", arguments: ["-rn", "-f", "inet"]) {
            for line in netstatOut.components(separatedBy: .newlines) {
                let parts = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
                guard parts.count >= 4 else { continue }
                if parts[0] == "default" && parts[3] == interface {
                    let gw = parts[1]
                    if isValidIPv4(gw) {
                        return gw
                    }
                }
            }
        }

        // 3. Fallback: ipconfig getpacket
        if let pktOut = runCommand("/usr/sbin/ipconfig", arguments: ["getpacket", interface]) {
            for line in pktOut.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("router (ip_mult) :") {
                    let gw = trimmed.replacingOccurrences(of: "router (ip_mult) :", with: "")
                        .replacingOccurrences(of: "{", with: "")
                        .replacingOccurrences(of: "}", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidIPv4(gw) {
                        return gw
                    }
                }
            }
        }

        return nil
    }

    /// Checks if a valid scoped default route already exists for the given interface.
    public func hasScopedRoute(for interface: String) -> Bool {
        guard let output = runCommand("/sbin/route", arguments: ["-n", "get", "-ifscope", interface, "1.1.1.1"]) else {
            return false
        }
        let lower = output.lowercased()
        if lower.contains("not in table") || lower.contains("no route") {
            return false
        }
        // Darwin kernel socket binding (IP_BOUND_IF) requires the IFSCOPE flag
        let hasIfScopeFlag = output.contains("IFSCOPE")
        return hasIfScopeFlag && output.contains("interface: \(interface)") && output.contains("gateway:")
    }

    /// Synchronizes scoped routes for the specified active interfaces asynchronously.
    public func sync(interfaces: [String]) {
        routeQueue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            defer { self.lock.unlock() }

            let activeSet = Set(interfaces)

            for iface in activeSet {
                if self.hasScopedRoute(for: iface) {
                    continue
                }

                guard let gateway = self.discoverGateway(for: iface) else {
                    continue
                }

                let added = self.addScopedRoute(interface: iface, gateway: gateway)
                if added {
                    self.addedRoutes[iface] = gateway
                }
            }

            var removed: [String] = []
            for (iface, gw) in self.addedRoutes {
                if !activeSet.contains(iface) {
                    self.removeScopedRoute(interface: iface, gateway: gw)
                    removed.append(iface)
                }
            }
            for iface in removed {
                self.addedRoutes.removeValue(forKey: iface)
            }

            self.saveState()
        }
    }

    /// Starts synchronization for active interfaces.
    public func start(interfacesProvider: @escaping @Sendable () -> [String]) {
        sync(interfaces: interfacesProvider())
    }

    /// Stops route management and removes all managed routes.
    public func stop() {
        routeQueue.async { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            for (iface, gw) in self.addedRoutes {
                self.removeScopedRoute(interface: iface, gateway: gw)
            }
            self.addedRoutes.removeAll()
            self.saveState()
            self.lock.unlock()
        }
    }

    /// Adds a scoped default route for the interface.
    @discardableResult
    private func addScopedRoute(interface: String, gateway: String) -> Bool {
        let args = ["-n", "/sbin/route", "-q", "-n", "add", "-inet", "default", gateway, "-ifscope", interface]
        if let out = runCommand("/usr/bin/sudo", arguments: args) {
            return !out.contains("failed")
        }
        let directArgs = ["-q", "-n", "add", "-inet", "default", gateway, "-ifscope", interface]
        _ = runCommand("/sbin/route", arguments: directArgs)
        return hasScopedRoute(for: interface)
    }

    /// Removes a scoped default route.
    @discardableResult
    private func removeScopedRoute(interface: String, gateway: String) -> Bool {
        let args = ["-n", "/sbin/route", "-q", "-n", "delete", "-inet", "default", gateway, "-ifscope", interface]
        if let _ = runCommand("/usr/bin/sudo", arguments: args) {
            return true
        }
        let directArgs = ["-q", "-n", "delete", "-inet", "default", gateway, "-ifscope", interface]
        return runCommand("/sbin/route", arguments: directArgs) != nil
    }

    // MARK: - State Persistence

    private func saveState() {
        let data = try? JSONEncoder().encode(addedRoutes)
        try? data?.write(to: stateFileURL, options: .atomic)
    }

    private func cleanupStale() {
        guard let data = try? Data(contentsOf: stateFileURL),
              let stale = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        for (iface, gw) in stale {
            removeScopedRoute(interface: iface, gateway: gw)
        }
        try? FileManager.default.removeItem(at: stateFileURL)
    }

    // MARK: - Helpers

    private func isValidIPv4(_ str: String) -> Bool {
        var sin = sockaddr_in()
        return str.withCString { inet_pton(AF_INET, $0, &sin.sin_addr) } == 1
    }

    private func runCommand(_ executable: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
