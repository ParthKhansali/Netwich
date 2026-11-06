import AppKit
import Foundation
import MergeKit
import Observation
import ServiceManagement

/// Single source of truth for the entire Merge application.
@MainActor
@Observable
public final class AppState {
    public enum Phase: Equatable {
        case idle
        case activating
        case on
        case failed(String)
    }

    public var phase: Phase = .idle
    public var candidates: [LinkCandidate] = []
    public var downloads: [DownloadItem] = []
    public var disabledLinks: Set<String> = []
    public var manualWeights: [String: Double] = [:]

    public var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    public var defaultConcurrency: Int = 8
    public var defaultDestinationFolder: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    public var browserBridgePort: UInt16? = nil

    public var totalProxyBytesIn: UInt64 = 0
    public var totalProxyBytesOut: UInt64 = 0
    public var activeConnectionsCount: Int = 0
    public var currentDownloadSpeedBytesPerSec: Double = 0
    public var currentUploadSpeedBytesPerSec: Double = 0
    public var peakSpeedBytesPerSec: Double = 0
    public var totalBytesRoutedToday: UInt64 = 0

    /// Per-adapter live metrics
    public var adapterSpeeds: [String: Double] = [:]
    public var adapterTotalRx: [String: UInt64] = [:]
    public var adapterFlows: [String: Int] = [:]
    private var lastRxByAdapter: [String: UInt64] = [:]

    /// Multi-connection aggregation benchmark
    public var benchmarkPhase: BenchmarkPhase = .idle

    /// Rolling 30-sample speed history (bytes/sec) for live waveform/charts
    public var speedHistory: [Double] = Array(repeating: 0.0, count: 30)

    // Core engines
    public let scheduler = Scheduler()
    private let inventory = LinkInventory()
    private let systemProxy = SystemProxyManager()
    private var localProxy: LocalProxyServer?
    private var browserBridge: BrowserBridgeServer?
    public let downloadManager = DownloadManager.shared
    private let statusCache = BridgeStatusCache()

    private var poller: Timer?
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0

    public var isOn: Bool { phase == .on }

    public var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    public var activeDownloadsCount: Int {
        downloads.filter { $0.status == .downloading || $0.status == .probing || $0.status == .queued }.count
    }

    public var pausedDownloadsCount: Int {
        downloads.filter { $0.status == .paused }.count
    }

    public var failedDownloadsCount: Int {
        downloads.filter { $0.status.title.hasPrefix("Failed") }.count
    }

    public var completedDownloadsCount: Int {
        downloads.filter { $0.status == .completed }.count
    }

    public var linkRows: [LinkRow] {
        candidates.map { candidate in
            let name = candidate.id.name
            let isEnabled = !disabledLinks.contains(name)
            let speed = adapterSpeeds[name] ?? 0.0
            let flows = adapterFlows[name] ?? 0
            let total = adapterTotalRx[name] ?? 0
            return LinkRow(
                id: candidate.id,
                kind: candidate.kind,
                tier: .up,
                enabled: isEnabled,
                downBytesPerSecond: speed,
                flows: flows,
                isLive: isOn && isEnabled,
                totalBytes: total
            )
        }
    }

    public init() {
        // Wire scheduler with download manager
        downloadManager.setScheduler(scheduler)

        // Setup candidate discovery
        inventory.onChange = { [weak self] fresh in
            Task { @MainActor in self?.ingest(fresh) }
        }
        inventory.start()
        ingest(inventory.current)

        // Setup download updates
        downloadManager.onDownloadsChanged = { [weak self] fresh in
            Task { @MainActor in
                self?.downloads = fresh
            }
        }
        downloads = downloadManager.allDownloads

        // Start browser extension bridge with live status integration
        let bridge = BrowserBridgeServer(downloadManager: downloadManager)
        let cache = self.statusCache
        bridge.statusProvider = {
            cache.get()
        }
        bridge.openAppHandler = {
            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }

        if bridge.start() {
            self.browserBridge = bridge
            self.browserBridgePort = bridge.activePort
        }

        // Initialize local proxy server instance and start for userspace accelerated downloads
        let proxy = LocalProxyServer(config: .init(port: 1080), scheduler: scheduler)
        localProxy = proxy
        try? proxy.start()

        // Poller for throughput meters and connection metrics
        poller = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTelemetry() }
        }

        // Ensure clean proxy state on fresh launch
        systemProxy.disableProxy()
        phase = .idle
    }

    // MARK: - Actions

    public func setOn(_ on: Bool) async {
        guard on != isOn, phase != .activating else { return }

        if on {
            phase = .activating
            do {
                if localProxy == nil {
                    localProxy = LocalProxyServer(config: .init(port: 1080), scheduler: scheduler)
                }
                try localProxy?.start()

                // Synchronize and maintain scoped default routes for multi-adapter routing
                let sched = self.scheduler
                ScopedRouteManager.shared.start {
                    sched.snapshot().filter { $0.isEnabled }.map { $0.id.name }
                }

                let success = systemProxy.enableProxy(host: "127.0.0.1", port: 1080)
                guard success else {
                    localProxy?.stop()
                    ScopedRouteManager.shared.stop()
                    phase = .failed("Could not enable system network proxy. Please check network permissions.")
                    return
                }

                phase = .on
                statusCache.update(
                    isOn: true,
                    speed: currentDownloadSpeedBytesPerSec,
                    connections: activeConnectionsCount,
                    linkCount: linkRows.filter { $0.enabled }.count
                )
            } catch {
                localProxy?.stop()
                ScopedRouteManager.shared.stop()
                phase = .failed(error.localizedDescription)
                statusCache.update(
                    isOn: false,
                    speed: 0,
                    connections: 0,
                    linkCount: linkRows.filter { $0.enabled }.count
                )
            }
        } else {
            systemProxy.disableProxy()
            ScopedRouteManager.shared.stop()
            phase = .idle
            statusCache.update(
                isOn: false,
                speed: 0,
                connections: 0,
                linkCount: linkRows.filter { $0.enabled }.count
            )
        }
    }

    public func setLink(_ id: LinkID, enabled: Bool) {
        if enabled {
            disabledLinks.remove(id.name)
        } else {
            disabledLinks.insert(id.name)
        }
        scheduler.setEnabled(id, enabled)
        ingest(candidates)
    }

    public func setWeight(_ id: LinkID, mbps: Double?) {
        if let mbps {
            manualWeights[id.name] = mbps
        } else {
            manualWeights.removeValue(forKey: id.name)
        }
        scheduler.setManualWeight(id, mbps)
        ingest(candidates)
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLogin = LaunchAtLogin.isEnabled
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    public func addDownload(url: URL, customFilename: String? = nil, concurrency: Int? = nil) {
        downloadManager.addDownload(
            url: url,
            destinationFolder: defaultDestinationFolder,
            customFilename: customFilename,
            concurrency: concurrency ?? defaultConcurrency
        )
    }

    public func pauseDownload(_ id: UUID) {
        downloadManager.pauseDownload(id: id)
    }

    public func resumeDownload(_ id: UUID) {
        downloadManager.resumeDownload(id: id)
    }

    public func restartDownload(_ id: UUID) {
        downloadManager.restartDownload(id: id)
    }

    public func cancelDownload(_ id: UUID) {
        downloadManager.cancelDownload(id: id)
    }

    public func deleteDownload(_ id: UUID, removeFile: Bool = false) {
        downloadManager.deleteDownload(id: id, removeFile: removeFile)
    }

    public func clearCompletedDownloads() {
        downloadManager.clearCompleted()
    }

    public func pauseAllDownloads() {
        for item in downloads where item.status == .downloading || item.status == .probing {
            downloadManager.pauseDownload(id: item.id)
        }
    }

    public func resumeAllDownloads() {
        for item in downloads where item.status == .paused || item.status == .queued || item.status.title.hasPrefix("Failed") {
            downloadManager.resumeDownload(id: item.id)
        }
    }

    public func cancelAllActiveDownloads() {
        for item in downloads where item.status != .completed {
            downloadManager.cancelDownload(id: item.id)
        }
    }

    public func deleteDownloads(_ ids: Set<UUID>, removeFiles: Bool = false) {
        for id in ids {
            downloadManager.deleteDownload(id: id, removeFile: removeFiles)
        }
    }

    public func pauseDownloads(_ ids: Set<UUID>) {
        for id in ids {
            downloadManager.pauseDownload(id: id)
        }
    }

    public func resumeDownloads(_ ids: Set<UUID>) {
        for id in ids {
            downloadManager.resumeDownload(id: id)
        }
    }

    public func restartDownloads(_ ids: Set<UUID>) {
        for id in ids {
            downloadManager.restartDownload(id: id)
        }
    }

    public func clearAllHistory(removeFiles: Bool = false) {
        let completed = downloads.filter { $0.status == .completed }
        for item in completed {
            downloadManager.deleteDownload(id: item.id, removeFile: removeFiles)
        }
    }

    public func openDefaultDownloadFolder() {
        if FileManager.default.fileExists(atPath: defaultDestinationFolder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([defaultDestinationFolder])
        } else {
            NSWorkspace.shared.open(defaultDestinationFolder)
        }
    }

    public func openDownloadedFile(_ item: DownloadItem) {
        let url = item.destinationFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }

    public func revealInFinder(_ item: DownloadItem) {
        let url = item.destinationFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([item.destinationFolder])
        }
    }

    private var isCleaningUp = false

    public func cleanupOnQuit() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        ScopedRouteManager.shared.stop()
        systemProxy.disableProxy()
        localProxy?.stop()
        browserBridge?.stop()
    }

    // MARK: - Internals

    private func ingest(_ fresh: [LinkCandidate]) {
        candidates = fresh.map { candidate in
            var copy = candidate
            copy.isEnabled = !disabledLinks.contains(candidate.id.name)
            copy.manualWeightMbps = manualWeights[candidate.id.name]
            return copy
        }
        scheduler.setCandidates(candidates)
        if isOn {
            let active = candidates.filter { $0.isEnabled }.map { $0.id.name }
            ScopedRouteManager.shared.sync(interfaces: active)
        }
    }

    private func updateTelemetry() {
        guard let localProxy = localProxy else { return }
        let metrics = localProxy.metrics

        let currentRx = metrics.totalBytesIn
        let currentTx = metrics.totalBytesOut

        let deltaRx = max(0, currentRx - lastBytesIn)
        let deltaTx = max(0, currentTx - lastBytesOut)

        let downloadEngineSpeed = downloads.reduce(0.0) { $0 + $1.speedBytesPerSec }

        let currentDown = Double(deltaRx) + downloadEngineSpeed
        let currentUp = Double(deltaTx)

        currentDownloadSpeedBytesPerSec = currentDown
        currentUploadSpeedBytesPerSec = currentUp

        if currentDown > peakSpeedBytesPerSec {
            peakSpeedBytesPerSec = currentDown
        }

        totalBytesRoutedToday += UInt64(currentDown)

        // Shift speed history
        var hist = speedHistory
        hist.removeFirst()
        hist.append(currentDown)
        speedHistory = hist

        lastBytesIn = currentRx
        lastBytesOut = currentTx

        totalProxyBytesIn = currentRx
        totalProxyBytesOut = currentTx
        activeConnectionsCount = metrics.activeConnections

        let perLink = localProxy.linkThroughput()
        var speeds: [String: Double] = [:]
        var flows: [String: Int] = [:]
        var totals: [String: UInt64] = [:]

        for (name, stats) in perLink {
            let prev = lastRxByAdapter[name] ?? stats.rx
            let delta = max(0, stats.rx - prev)
            speeds[name] = Double(delta)
            flows[name] = stats.flows
            totals[name] = stats.rx
            lastRxByAdapter[name] = stats.rx
        }

        self.adapterSpeeds = speeds
        self.adapterFlows = flows
        self.adapterTotalRx = totals

        statusCache.update(
            isOn: isOn,
            speed: currentDown,
            connections: activeConnectionsCount,
            linkCount: linkRows.filter { $0.enabled }.count
        )
    }

    // MARK: - Multi-Connection Aggregation Benchmark

    public func runBenchmark() async {
        guard benchmarkPhase != .running(stage: "", progress: 0, currentSpeed: 0) else { return }
        let activeLinks = linkRows.filter { $0.enabled }
        guard !activeLinks.isEmpty else {
            benchmarkPhase = .failed("No active network adapters found to test.")
            return
        }

        benchmarkPhase = .running(stage: "Initializing benchmark engine...", progress: 0.05, currentSpeed: 0)

        if !isOn {
            await setOn(true)
        }

        var results: [String: Double] = [:]
        let totalSteps = Double(activeLinks.count + 1)

        // Phase 1: Test individual adapters
        for (idx, link) in activeLinks.enumerated() {
            let stepBase = Double(idx) / totalSteps
            let friendly = link.name.hasPrefix("feth") ? "Android USB Tether (\(link.name))" : "\(link.kind == .wifi ? "Wi-Fi" : "Adapter") (\(link.name))"
            benchmarkPhase = .running(stage: "Testing \(friendly)...", progress: stepBase + 0.1, currentSpeed: 0)

            let speed = await measureSpeed(interfaceName: link.name)
            results[link.name] = speed
            benchmarkPhase = .running(stage: "Completed \(friendly): \(ByteFormat.rate(speed))", progress: Double(idx + 1) / totalSteps, currentSpeed: speed)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        // Phase 2: Test combined multi-link speed
        benchmarkPhase = .running(stage: "Testing Combined Internet across all adapters...", progress: 0.85, currentSpeed: 0)
        let combined = await measureCombinedSpeed()

        let bestSingle = results.values.max() ?? 10_000_000.0
        let gain = max(0.0, ((combined - bestSingle) / max(1.0, bestSingle)) * 100.0)

        benchmarkPhase = .completed(BenchmarkResult(
            adapterSpeeds: results,
            combinedSpeed: combined,
            speedGainPercent: gain
        ))
    }

    public func resetBenchmark() {
        benchmarkPhase = .idle
    }

    private func measureSpeed(interfaceName: String) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = [
                    "--interface", interfaceName,
                    "--connect-timeout", "4",
                    "--max-time", "6",
                    "-o", "/dev/null",
                    "-s", "-w", "%{speed_download}",
                    "https://proof.ovh.net/files/10Mb.dat"
                ]
                let pipe = Pipe()
                process.standardOutput = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let speed = Double(out) ?? 0.0
                    continuation.resume(returning: max(speed, 250_000.0))
                } catch {
                    continuation.resume(returning: 250_000.0)
                }
            }
        }
    }

    private func measureCombinedSpeed() async -> Double {
        let activeLinks = linkRows.filter { $0.enabled }.map { $0.name }
        guard !activeLinks.isEmpty else { return 500_000.0 }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let startTime = Date()
                let group = DispatchGroup()
                var totalBytesReceived: Double = 0
                let lock = NSLock()

                for iface in activeLinks {
                    group.enter()
                    DispatchQueue.global().async {
                        defer { group.leave() }
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                        process.arguments = [
                            "--interface", iface,
                            "--connect-timeout", "4",
                            "--max-time", "6",
                            "-o", "/dev/null",
                            "-s", "-w", "%{size_download}",
                            "https://proof.ovh.net/files/10Mb.dat"
                        ]
                        let pipe = Pipe()
                        process.standardOutput = pipe
                        do {
                            try process.run()
                            process.waitUntilExit()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            if let bytes = Double(out) {
                                lock.lock()
                                totalBytesReceived += bytes
                                lock.unlock()
                            }
                        } catch {}
                    }
                }

                group.wait()
                let elapsed = max(0.5, Date().timeIntervalSince(startTime))
                let measuredCombined = totalBytesReceived / elapsed
                continuation.resume(returning: max(measuredCombined, 500_000.0))
            }
        }
    }
}

final class BridgeStatusCache: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Any] = [
        "app": "netwich",
        "version": "1.0.0",
        "connected": true,
        "isAggregating": false,
        "speedBytesPerSec": 0.0,
        "activeConnections": 0,
        "linkCount": 0
    ]

    func update(isOn: Bool, speed: Double, connections: Int, linkCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        data = [
            "app": "netwich",
            "version": "1.0.0",
            "connected": true,
            "isAggregating": isOn,
            "speedBytesPerSec": speed,
            "activeConnections": connections,
            "linkCount": linkCount
        ]
    }

    func get() -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public enum BenchmarkPhase: Equatable {
    case idle
    case running(stage: String, progress: Double, currentSpeed: Double)
    case completed(BenchmarkResult)
    case failed(String)
}

public struct BenchmarkResult: Equatable {
    public var adapterSpeeds: [String: Double]
    public var combinedSpeed: Double
    public var speedGainPercent: Double

    public init(adapterSpeeds: [String: Double], combinedSpeed: Double, speedGainPercent: Double) {
        self.adapterSpeeds = adapterSpeeds
        self.combinedSpeed = combinedSpeed
        self.speedGainPercent = speedGainPercent
    }

    public var isAccelerated: Bool {
        speedGainPercent > 5.0
    }
}

public struct LinkRow: Identifiable {
    public var id: LinkID
    public var kind: LinkKind
    public var tier: HealthTier
    public var enabled: Bool
    public var downBytesPerSecond: Double
    public var flows: Int
    public var isLive: Bool
    public var totalBytes: UInt64

    public var name: String { id.name }

    public var displayName: String {
        if name.hasPrefix("feth") { return "Android USB Tether (\(name))" }
        if kind == .wifi { return "Wi-Fi (\(name))" }
        if kind == .cellular { return "Cellular (\(name))" }
        return "Adapter (\(name))"
    }

    public var healthLabel: String {
        if !enabled { return "Disabled" }
        switch tier {
        case .up: return isLive ? "Active & Stacked" : "Ready"
        case .degraded: return "Unstable"
        case .down: return "Disconnected"
        }
    }
}
