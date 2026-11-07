import AppKit
import Foundation
import MergeKit
import Observation
import ServiceManagement

/// Single source of truth for the app.
///
/// Two rules keep the UI responsive:
/// - `init` does no subprocess work and no file scanning. Anything that shells out
///   (`networksetup`, `route`) happens in `bootstrap()` or behind an explicit action.
/// - Every published value is written on the main actor from a snapshot, never by
///   reading a concurrently-mutated engine object field-by-field.
@MainActor
@Observable
public final class AppState {
    public enum Phase: Equatable {
        case idle
        case activating
        case on
        case failed(String)
    }

    // MARK: - Connection state

    public var phase: Phase = .idle
    public var candidates: [LinkCandidate] = []
    public var disabledLinks: Set<String> = []
    public var manualWeights: [String: Double] = [:]

    // MARK: - Downloads

    public var downloads: [DownloadItem] = []
    public var defaultConcurrency: Int = 8 {
        didSet {
            UserDefaults.standard.set(defaultConcurrency, forKey: "defaultConcurrency")
            downloadManager.defaultConcurrency = defaultConcurrency
        }
    }
    public var defaultDestinationFolder: URL {
        didSet {
            UserDefaults.standard.set(defaultDestinationFolder.path, forKey: "destinationFolder")
            downloadManager.defaultDestination = defaultDestinationFolder
        }
    }

    // MARK: - Settings

    public var launchAtLogin: Bool = LaunchAtLogin.isEnabled

    // MARK: - Live telemetry

    public var totalProxyBytesIn: UInt64 = 0
    public var totalProxyBytesOut: UInt64 = 0
    public var activeConnectionsCount: Int = 0
    public var currentDownloadSpeedBytesPerSec: Double = 0
    public var currentUploadSpeedBytesPerSec: Double = 0
    public var peakSpeedBytesPerSec: Double = 0
    public var totalBytesRoutedToday: UInt64 = 0
    public var adapterSpeeds: [String: Double] = [:]
    public var adapterTotalRx: [String: UInt64] = [:]
    public var adapterFlows: [String: Int] = [:]
    /// Rolling 60-sample history at 1 Hz, used by the live waveform.
    public var speedHistory: [Double] = Array(repeating: 0, count: 60)
    public var uploadHistory: [Double] = Array(repeating: 0, count: 60)

    // MARK: - Setup & health

    public var setup: PermissionCenter
    public var browserBridgePort: UInt16?
    public var localProxyPort: UInt16 = 1080
    public var proxyError: String?
    public var benchmarkPhase: BenchmarkPhase = .idle

    // MARK: - Engines

    public let scheduler = Scheduler()
    public let downloadManager = DownloadManager.shared
    private let inventory = LinkInventory()
    private let systemProxy = SystemProxyManager()
    private var localProxy: LocalProxyServer?
    private var browserBridge: BrowserBridgeServer?
    private let statusCache = BridgeStatusCache()

    private var poller: Timer?
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastRxByAdapter: [String: UInt64] = [:]
    private var didBootstrap = false

    public init() {
        let savedFolder = UserDefaults.standard.string(forKey: "destinationFolder")
            .map { URL(fileURLWithPath: $0) }
        let fallbackFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let folder = savedFolder ?? fallbackFolder

        let savedConcurrency = UserDefaults.standard.integer(forKey: "defaultConcurrency")
        self.defaultDestinationFolder = folder
        self.defaultConcurrency = savedConcurrency == 0 ? 8 : savedConcurrency
        self.setup = PermissionCenter()

        downloadManager.defaultDestination = folder
        downloadManager.defaultConcurrency = self.defaultConcurrency
        downloadManager.setScheduler(scheduler)

        inventory.onChange = { [weak self] fresh in
            Task { @MainActor in self?.ingest(fresh) }
        }
        inventory.start()

        downloadManager.onDownloadsChanged = { [weak self] fresh in
            Task { @MainActor in self?.downloads = fresh }
        }
        downloads = downloadManager.allDownloads
        restoreDailyTotal()
        refreshLinkRows()
    }

    /// Everything that touches the system, deferred until the window exists.
    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        startBrowserBridge()
        startLocalProxy()
        ingest(inventory.current)

        // Recover a proxy left behind by a previous crash, off the main thread.
        let proxy = systemProxy
        Task.detached(priority: .utility) { proxy.recoverStaleState() }

        // 1 Hz is plenty for a rate meter. The tolerance lets the system coalesce
        // wakeups with other timers instead of waking the CPU precisely every second,
        // and .common keeps the readout alive while a menu or scroll is tracking.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateTelemetry() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        poller = timer

        await setup.refresh()
    }

    // MARK: - Derived state

    public var isOn: Bool { phase == .on }

    public var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return proxyError
    }

    public var activeDownloadsCount: Int {
        downloads.filter { $0.status == .downloading || $0.status == .probing || $0.status == .queued }.count
    }

    public var pausedDownloadsCount: Int {
        downloads.filter { $0.status == .paused }.count
    }

    public var failedDownloadsCount: Int {
        downloads.filter { $0.status.isFailed }.count
    }

    public var completedDownloadsCount: Int {
        downloads.filter { $0.status == .completed }.count
    }

    public var enabledLinkCount: Int {
        linkRows.filter(\.enabled).count
    }

    /// Live rows merged with the scheduler's real health, not a hardcoded `.up`.
    /// Cached because views read it many times per frame.
    public private(set) var linkRows: [LinkRow] = []

    private func refreshLinkRows() {
        let snapshot = scheduler.snapshot()
        let byID = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })

        let rows = candidates.map { candidate in
            let name = candidate.id.name
            let live = byID[candidate.id]
            let enabled = !disabledLinks.contains(name)
            return LinkRow(
                id: candidate.id,
                kind: candidate.kind,
                tier: live?.tier ?? .up,
                enabled: enabled,
                downBytesPerSecond: adapterSpeeds[name] ?? 0,
                flows: adapterFlows[name] ?? live?.flows ?? 0,
                isLive: isOn && enabled,
                totalBytes: adapterTotalRx[name] ?? live?.bytesIn ?? 0,
                measuredMbps: live?.measuredMbps ?? 0,
                weightMbps: live?.weightMbps ?? 0
            )
        }

        // Only publish when something actually moved. Reassigning an identical
        // array every second invalidates every view that reads it.
        if rows != linkRows { linkRows = rows }
    }

    // MARK: - Actions

    public func setOn(_ on: Bool) async {
        guard on != isOn, phase != .activating else { return }

        guard on else {
            await turnOff()
            return
        }

        phase = .activating
        proxyError = nil
        startLocalProxy()

        guard let proxy = localProxy, proxy.isServerRunning else {
            phase = .failed("The local proxy could not start. Port \(localProxyPort) may already be in use.")
            return
        }

        let manager = systemProxy
        do {
            try await Task.detached(priority: .userInitiated) {
                try manager.enableProxy(host: "127.0.0.1", port: proxyPortValue())
            }.value

            phase = .on
            statusCache.update(isOn: true, speed: currentDownloadSpeedBytesPerSec, connections: activeConnectionsCount, linkCount: enabledLinkCount)
            ScopedRouteManager.shared.sync(interfaces: candidates.filter(\.isEnabled).map { $0.id.name })
            await setup.refresh()
        } catch {
            // Leave nothing half-applied: undo whatever did stick, stop the proxy.
            await Task.detached(priority: .utility) { _ = manager.disableProxy() }.value
            proxy.stop()
            phase = .failed(error.localizedDescription)
            proxyError = error.localizedDescription
            statusCache.update(isOn: false, speed: 0, connections: 0, linkCount: enabledLinkCount)
        }
    }

    private func turnOff() async {
        phase = .activating
        ScopedRouteManager.shared.stop()
        let manager = systemProxy
        _ = await Task.detached(priority: .userInitiated) { manager.disableProxy() }.value
        localProxy?.stop()
        phase = .idle
        statusCache.update(isOn: false, speed: 0, connections: 0, linkCount: enabledLinkCount)
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
        Task { await setup.refresh() }
    }

    public func chooseDestinationFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Netwich saves new downloads here."
        if panel.runModal() == .OK, let url = panel.url {
            defaultDestinationFolder = url
        }
    }

    // MARK: - Downloads

    public func addDownload(url: URL, customFilename: String? = nil, concurrency: Int? = nil) {
        downloadManager.addDownload(
            url: url,
            destinationFolder: defaultDestinationFolder,
            customFilename: customFilename,
            concurrency: concurrency ?? defaultConcurrency
        )
    }

    public func pauseDownload(_ id: UUID) { downloadManager.pauseDownload(id: id) }
    public func resumeDownload(_ id: UUID) { downloadManager.resumeDownload(id: id) }
    public func restartDownload(_ id: UUID) { downloadManager.restartDownload(id: id) }
    public func cancelDownload(_ id: UUID) { downloadManager.cancelDownload(id: id) }
    public func deleteDownload(_ id: UUID, removeFile: Bool = false) {
        downloadManager.deleteDownload(id: id, removeFile: removeFile)
    }
    public func clearCompletedDownloads() { downloadManager.clearCompleted() }

    public func pauseAllDownloads() {
        for item in downloads where item.status == .downloading || item.status == .probing {
            downloadManager.pauseDownload(id: item.id)
        }
    }

    public func resumeAllDownloads() {
        for item in downloads where item.status == .paused || item.status.isFailed {
            downloadManager.resumeDownload(id: item.id)
        }
    }

    public func deleteDownloads(_ ids: Set<UUID>, removeFiles: Bool = false) {
        for id in ids { downloadManager.deleteDownload(id: id, removeFile: removeFiles) }
    }

    public func pauseDownloads(_ ids: Set<UUID>) {
        for id in ids { downloadManager.pauseDownload(id: id) }
    }

    public func resumeDownloads(_ ids: Set<UUID>) {
        for id in ids { downloadManager.resumeDownload(id: id) }
    }

    public func restartDownloads(_ ids: Set<UUID>) {
        for id in ids { downloadManager.restartDownload(id: id) }
    }

    public func clearAllHistory(removeFiles: Bool = false) {
        for item in downloads where item.status == .completed {
            downloadManager.deleteDownload(id: item.id, removeFile: removeFiles)
        }
    }

    public func openDefaultDownloadFolder() {
        NSWorkspace.shared.open(defaultDestinationFolder)
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

    public func activateWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        for window in NSApplication.shared.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Lifecycle

    private var isCleaningUp = false

    public func cleanupOnQuit() {
        guard !isCleaningUp else { return }
        isCleaningUp = true
        poller?.invalidate()
        poller = nil
        ScopedRouteManager.shared.stop()
        browserBridge?.stop()
        localProxy?.stop()
        systemProxy.disableProxy()
    }

    // MARK: - Internals

    private func startBrowserBridge() {
        guard browserBridge == nil else { return }
        let bridge = BrowserBridgeServer(downloadManager: downloadManager)
        let cache = statusCache
        bridge.statusProvider = { cache.get() }
        bridge.openAppHandler = { [weak self] in
            DispatchQueue.main.async { self?.activateWindow() }
        }
        if bridge.start() {
            browserBridge = bridge
            browserBridgePort = bridge.activePort
        }
    }

    private func startLocalProxy() {
        guard localProxy == nil || localProxy?.isServerRunning == false else { return }
        let proxy = localProxy ?? LocalProxyServer(config: .init(port: localProxyPort), scheduler: scheduler)
        do {
            try proxy.start()
            localProxy = proxy
            proxyError = nil
        } catch {
            localProxy = proxy
            proxyError = error.localizedDescription
        }
    }

    private func ingest(_ fresh: [LinkCandidate]) {
        candidates = fresh.map { candidate in
            var copy = candidate
            copy.isEnabled = !disabledLinks.contains(candidate.id.name)
            copy.manualWeightMbps = manualWeights[candidate.id.name]
            return copy
        }
        scheduler.setCandidates(candidates)
        refreshLinkRows()

        if isOn {
            ScopedRouteManager.shared.sync(interfaces: candidates.filter(\.isEnabled).map { $0.id.name })
        }
    }

    private func updateTelemetry() {
        let metrics = localProxy?.metrics
        let currentRx = metrics?.totalBytesIn ?? 0
        let currentTx = metrics?.totalBytesOut ?? 0

        let deltaRx = Double(currentRx >= lastBytesIn ? currentRx - lastBytesIn : 0)
        let deltaTx = Double(currentTx >= lastBytesOut ? currentTx - lastBytesOut : 0)
        let engineDown = downloads.reduce(0.0) { $0 + $1.speedBytesPerSec }

        // Downloads are routed through the local SOCKS proxy while aggregation is on, so
        // their bytes are *already* inside deltaRx. Taking the larger of the two keeps the
        // meter responsive without ever adding the same byte twice.
        currentDownloadSpeedBytesPerSec = isOn ? max(deltaRx, engineDown) : engineDown
        currentUploadSpeedBytesPerSec = isOn ? deltaTx : 0

        if currentDownloadSpeedBytesPerSec > peakSpeedBytesPerSec {
            peakSpeedBytesPerSec = currentDownloadSpeedBytesPerSec
        }

        accumulateDailyUpload(deltaRx)

        push(&speedHistory, currentDownloadSpeedBytesPerSec)
        push(&uploadHistory, currentUploadSpeedBytesPerSec)

        lastBytesIn = currentRx
        lastBytesOut = currentTx
        totalProxyBytesIn = currentRx
        totalProxyBytesOut = currentTx
        activeConnectionsCount = metrics?.activeConnections ?? 0

        guard let proxy = localProxy else { return }
        let perLink = proxy.linkThroughput()
        var speeds: [String: Double] = [:]
        var flows: [String: Int] = [:]
        var totals: [String: UInt64] = [:]

        for (name, stats) in perLink {
            let previous = lastRxByAdapter[name] ?? stats.rx
            speeds[name] = stats.rx >= previous ? Double(stats.rx - previous) : 0
            flows[name] = stats.flows
            totals[name] = stats.rx
            lastRxByAdapter[name] = stats.rx
        }

        adapterSpeeds = speeds
        adapterFlows = flows
        adapterTotalRx = totals
        refreshLinkRows()

        statusCache.update(
            isOn: isOn,
            speed: currentDownloadSpeedBytesPerSec,
            connections: activeConnectionsCount,
            linkCount: enabledLinkCount
        )
    }

    private func push(_ history: inout [Double], _ value: Double) {
        guard !history.isEmpty else {
            history.append(value)
            return
        }
        // Mutate in place: copying a 60-element array twice a second is small,
        // but it also churns the Observation change that drives every redraw.
        history.removeFirst()
        history.append(value)
    }

    // MARK: - Daily counter

    private func accumulateDailyUpload(_ bytes: Double) {
        let today = Self.dayKey(Date())
        if UserDefaults.standard.string(forKey: "routedDay") != today {
            UserDefaults.standard.set(today, forKey: "routedDay")
            totalBytesRoutedToday = 0
        }
        totalBytesRoutedToday &+= UInt64(max(0, bytes))
        UserDefaults.standard.set(Int(totalBytesRoutedToday), forKey: "routedBytes")
    }

    private func restoreDailyTotal() {
        let today = Self.dayKey(Date())
        if UserDefaults.standard.string(forKey: "routedDay") == today {
            totalBytesRoutedToday = UInt64(max(0, UserDefaults.standard.integer(forKey: "routedBytes")))
        } else {
            UserDefaults.standard.set(today, forKey: "routedDay")
            totalBytesRoutedToday = 0
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // MARK: - Benchmark

    /// Measures stacked throughput against a single-link baseline.
    ///
    /// Deliberately does **not** flip the system proxy on behind the user's back, and it
    /// reports a failed measurement as a failure instead of clamping it to a flattering
    /// floor. Each run transfers a few megabytes, so it is opt-in only.
    public func runBenchmark() async {
        guard case .running = benchmarkPhase else {
            let links = linkRows.filter { $0.enabled }
            guard !links.isEmpty else {
                benchmarkPhase = .failed("No active adapters to test. Connect Wi-Fi or plug in your phone first.")
                return
            }

            benchmarkPhase = .running(stage: "Preparing", progress: 0.02, currentSpeed: 0)

            var results: [String: Double] = [:]
            for (index, link) in links.enumerated() {
                let stage = "Measuring \(link.displayName)"
                benchmarkPhase = .running(stage: stage, progress: 0.1 + 0.6 * Double(index) / Double(links.count), currentSpeed: 0)
                results[link.name] = await measure(interface: link.name)
            }

            benchmarkPhase = .running(stage: "Measuring stacked throughput", progress: 0.8, currentSpeed: 0)
            let combined = await measureStacked(links)

            let bestSingle = results.values.max() ?? 0
            let gain = bestSingle > 0 ? max(0, (combined - bestSingle) / bestSingle * 100) : 0

            benchmarkPhase = .completed(
                BenchmarkResult(adapterSpeeds: results, combinedSpeed: combined, speedGainPercent: gain)
            )
            return
        }
    }

    public func resetBenchmark() {
        benchmarkPhase = .idle
    }

    /// Downloads 8 MB through one specific interface and returns bytes/second.
    private func measure(interface: String) async -> Double {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let start = Date()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                process.arguments = [
                    "--interface", interface,
                    "--connect-timeout", "5",
                    "--max-time", "12",
                    "-o", "/dev/null",
                    "-s", "-w", "%{size_download}",
                    "https://speed.cloudflare.com/__down?bytes=8000000"
                ]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: 0)
                    return
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let bytes = Int64(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                let elapsed = max(0.25, Date().timeIntervalSince(start))
                continuation.resume(returning: bytes > 0 ? Double(bytes) / elapsed : 0)
            }
        }
    }

    private func measureStacked(_ links: [LinkRow]) async -> Double {
        await withTaskGroup(of: Double.self) { group in
            for link in links {
                group.addTask { [weak self] in
                    guard let self else { return 0 }
                    return await self.measure(interface: link.name)
                }
            }
            var total = 0.0
            for await value in group { total += value }
            return total
        }
    }
}

// MARK: - Bridge status

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

// MARK: - Value types

public enum BenchmarkPhase: Equatable {
    case idle
    case running(stage: String, progress: Double, currentSpeed: Double)
    case completed(BenchmarkResult)
    case failed(String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
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

    public var isAccelerated: Bool { speedGainPercent > 5 }
    public var bestSingleSpeed: Double { adapterSpeeds.values.max() ?? 0 }
}

public struct LinkRow: Identifiable, Equatable {
    public var id: LinkID
    public var kind: LinkKind
    public var tier: HealthTier
    public var enabled: Bool
    public var downBytesPerSecond: Double
    public var flows: Int
    public var isLive: Bool
    public var totalBytes: UInt64
    public var measuredMbps: Double
    public var weightMbps: Double

    public var name: String { id.name }

    public var displayName: String {
        if name.hasPrefix("feth") { return "Android USB Tether" }
        switch kind {
        case .wifi: return "Wi-Fi"
        case .wired: return "Ethernet"
        case .cellular: return "Cellular"
        case .other: return "Network"
        }
    }

    public var subtitle: String { name }

    public var healthLabel: String {
        if !enabled { return "Disabled" }
        switch tier {
        case .up: return isLive ? "Stacked" : "Ready"
        case .degraded: return "Unstable"
        case .down: return "Disconnected"
        }
    }

    public var isHealthy: Bool { enabled && tier > .down }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

func proxyPortValue() -> UInt16 { 1080 }
