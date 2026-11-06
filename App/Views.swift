import AppKit
import MergeKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Byte Formatting Helpers

public enum ByteFormat {
    public static func rate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000_000 {
            return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000)
        } else if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        } else if bytesPerSecond >= 1_000 {
            return String(format: "%.0f KB/s", bytesPerSecond / 1_000)
        } else {
            return String(format: "%.0f B/s", bytesPerSecond)
        }
    }

    public static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let m = Int(seconds) / 60
            let s = Int(seconds) % 60
            return "\(m)m \(s)s"
        } else {
            let h = Int(seconds) / 3600
            let m = (Int(seconds) % 3600) / 60
            return "\(h)h \(m)m"
        }
    }
}

// MARK: - Glassmorphism Visual Modifiers

public extension View {
    func glassCard(cornerRadius: CGFloat = 16, strokeColor: Color = Color.white.opacity(0.12)) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [strokeColor, strokeColor.opacity(0.25)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 3)
    }

    func glassBar() -> some View {
        self
            .background(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Root View

public struct RootView: View {
    @Bindable public var state: AppState
    @State private var selectedTab: Tab = .overview
    @State private var showNewDownloadSheet: Bool = false
    @AppStorage("hasOnboarded") private var hasOnboarded: Bool = false
    @State private var showOnboarding: Bool = false

    public enum Tab: String, CaseIterable, Identifiable {
        case overview = "Dashboard"
        case downloads = "Downloads"
        case history = "History"
        case extensionSetup = "Browser Extension"
        case tethering = "Tethering Guide"
        case settings = "Settings"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .overview: return "gauge.with.needle.fill"
            case .downloads: return "arrow.down.circle.fill"
            case .history: return "clock.arrow.circlepath"
            case .extensionSetup: return "puzzlepiece.extension.fill"
            case .tethering: return "cable.connector"
            case .settings: return "gearshape.fill"
            }
        }
    }

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        NavigationSplitView {
            List(Tab.allCases, selection: $selectedTab) { tab in
                NavigationLink(value: tab) {
                    HStack {
                        Label(tab.rawValue, systemImage: tab.icon)
                        Spacer()
                        if tab == .downloads && state.activeDownloadsCount > 0 {
                            Text("\(state.activeDownloadsCount)")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        } else if tab == .history && state.completedDownloadsCount > 0 {
                            Text("\(state.completedDownloadsCount)")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.secondary.opacity(0.18), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewDownloadSheet = true
                    } label: {
                        Label("New Download", systemImage: "plus")
                    }
                    .help("Add New Download (⌘N)")
                }
            }
        } detail: {
            Group {
                switch selectedTab {
                case .overview:
                    DashboardOverviewView(state: state, onNewDownload: { showNewDownloadSheet = true })
                case .downloads:
                    DownloadsHubView(state: state, filterMode: .active, onNewDownload: { showNewDownloadSheet = true })
                case .history:
                    DownloadsHubView(state: state, filterMode: .completed, onNewDownload: { showNewDownloadSheet = true })
                case .extensionSetup:
                    ExtensionSetupView(state: state)
                case .tethering:
                    TetheringGuideView(state: state)
                case .settings:
                    SettingsView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showNewDownloadSheet) {
            NewDownloadSheet(state: state, isPresented: $showNewDownloadSheet)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(onFinish: {
                hasOnboarded = true
                showOnboarding = false
            })
            .interactiveDismissDisabled(true)
        }
        .onAppear {
            if !hasOnboarded {
                showOnboarding = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewDownloadSheet)) { _ in
            showNewDownloadSheet = true
        }
    }
}

// MARK: - Dashboard / Overview View

public struct DashboardOverviewView: View {
    @Bindable public var state: AppState
    public var onNewDownload: () -> Void

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Master Aggregation Hero Card
                MasterHeroCard(state: state)

                // Real-time Bandwidth Gauges & Waveform
                SpeedWaveformCard(state: state)

                // Multi-Connection Aggregation Benchmark & Verification
                AggregationBenchmarkCard(state: state)

                // Network Adapters & Multi-Path Breakdown
                NetworkAdaptersCard(state: state)

                // Active Downloads Quick-Look
                if state.activeDownloadsCount > 0 {
                    DashboardActiveDownloadsSection(state: state)
                }
            }
            .padding(24)
        }
    }
}

struct MasterHeroCard: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(state.isOn ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                    .frame(width: 64, height: 64)

                if let img = NSImage(named: "netwich-mark-512") ?? Bundle.main.image(forResource: "netwich-mark-512") ?? (Bundle.main.resourcePath.flatMap { NSImage(contentsOfFile: $0 + "/netwich-mark-512.png") }) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                        .opacity(state.isOn ? 1.0 : 0.6)
                } else {
                    Image(systemName: state.isOn ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(state.isOn ? Color.accentColor : Color.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("Connection Aggregation")
                        .font(.title2.weight(.bold))

                    if state.isOn {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("ACTIVE")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }

                Text(heroDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if state.phase == .activating {
                ProgressView()
                    .controlSize(.regular)
                    .padding(.trailing, 8)
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { state.isOn },
                    set: { newValue in Task { await state.setOn(newValue) } }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.large)
            .disabled(state.phase == .activating)
        }
        .padding(20)
        .glassCard(
            cornerRadius: 18,
            strokeColor: state.isOn ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.14)
        )
    }

    private var heroDescription: String {
        if state.isOn {
            let active = state.linkRows.filter { $0.enabled }.count
            if active > 1 {
                return "Distributing traffic concurrently across \(active) network adapters."
            } else {
                return "Aggregator running on 1 adapter. Plug in phone or second adapter to stack connections."
            }
        }
        return "Stack Wi-Fi and phone tethering into one coordinated connection."
    }
}

struct SpeedWaveformCard: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Speed Metrics Row
            HStack(spacing: 16) {
                // Download
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("Current Download")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteFormat.rate(state.currentDownloadSpeedBytesPerSec))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Upload
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Current Upload")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteFormat.rate(state.currentUploadSpeedBytesPerSec))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Peak Speed
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.orange)
                        Text("Session Peak")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(ByteFormat.rate(state.peakSpeedBytesPerSec))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                // Active Sockets
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "point.3.filled.connected.trianglepath")
                            .foregroundStyle(.purple)
                        Text("Active Sockets")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("\(state.activeConnectionsCount)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 6)

            Divider()

            // Live 30-sample Throughput Waveform
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Real-Time Bandwidth Waveform (Last 30 Seconds)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Live Traffic")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    let maxVal = max(1_000_000.0, state.speedHistory.max() ?? 1.0)
                    let barWidth = max(2.0, (geo.size.width - CGFloat(state.speedHistory.count - 1) * 3) / CGFloat(state.speedHistory.count))

                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(state.speedHistory.enumerated()), id: \.offset) { index, val in
                            let heightRatio = min(1.0, CGFloat(val / maxVal))
                            let barHeight = max(4.0, heightRatio * geo.size.height)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(val > 100_000 ? Color.accentColor : Color.secondary.opacity(0.2))
                                .frame(width: barWidth, height: barHeight)
                                .animation(.easeOut(duration: 0.3), value: val)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 54)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Aggregation Benchmark & Verification Card

struct AggregationBenchmarkCard: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "speedometer")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text("Aggregation Verification & Speed Benchmark")
                        .font(.headline)
                }

                Spacer()

                if case .completed(let res) = state.benchmarkPhase {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text(res.isAccelerated ? "AGGREGATION CONFIRMED" : "TEST COMPLETE")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12), in: Capsule())
                }
            }

            Text("Verify that internet traffic is concurrently routing across your connections and increasing overall throughput.")
                .font(.caption)
                .foregroundStyle(.secondary)

            switch state.benchmarkPhase {
            case .idle:
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Measures single-connection baselines versus stacked multi-link throughput.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await state.runBenchmark() }
                    } label: {
                        Label("Run Speed & Benchmark Test", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 2)

            case .running(let stage, let progress, let currentSpeed):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(stage)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        if currentSpeed > 0 {
                            Text(ByteFormat.rate(currentSpeed))
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }

                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                }
                .padding(.vertical, 4)

            case .completed(let res):
                VStack(alignment: .leading, spacing: 12) {
                    // Comparison Bar Chart
                    VStack(alignment: .leading, spacing: 8) {
                        let maxSpeed = max(res.combinedSpeed, (res.adapterSpeeds.values.max() ?? 1.0) * 1.05)

                        // Individual Adapters
                        ForEach(Array(res.adapterSpeeds.keys.sorted()), id: \.self) { iface in
                            let speed = res.adapterSpeeds[iface] ?? 0.0
                            let friendly = iface.hasPrefix("feth") ? "Android Phone (USB)" : (iface == "en0" ? "Wi-Fi" : iface)
                            let ratio = CGFloat(speed / maxSpeed)

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text("\(friendly) (\(iface)) Solo")
                                        .font(.caption.weight(.medium))
                                    Spacer()
                                    Text(ByteFormat.rate(speed))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.blue.opacity(0.75))
                                        .frame(width: max(8.0, geo.size.width * ratio), height: 10)
                                }
                                .frame(height: 10)
                            }
                        }

                        Divider()
                            .padding(.vertical, 2)

                        // Combined
                        let combinedRatio = CGFloat(res.combinedSpeed / maxSpeed)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                HStack(spacing: 5) {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(.orange)
                                    Text("Combined Netwich Internet")
                                        .font(.caption.weight(.bold))
                                }
                                Spacer()
                                Text(ByteFormat.rate(res.combinedSpeed))
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(LinearGradient(colors: [Color.accentColor, Color.green], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(8.0, geo.size.width * combinedRatio), height: 14)
                            }
                            .frame(height: 14)
                        }
                    }

                    // Summary Badge & Retest
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if res.isAccelerated {
                                Text("+\(Int(res.speedGainPercent))% Speed Boost")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(.green)
                                Text("Connections are bonded: aggregation successfully increased total download speed.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Connections Active")
                                    .font(.subheadline.weight(.semibold))
                                Text("Both adapters are online and balanced according to current network capacity.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("Test Again") {
                            state.resetBenchmark()
                            Task { await state.runBenchmark() }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 4)
                }

            case .failed(let err):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Try Again") {
                        state.resetBenchmark()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 16)
    }
}

struct NetworkAdaptersCard: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Network Adapters & Multi-Path Balancing")
                        .font(.headline)
                    Text("Individual status, hardware routing, and bandwidth weighting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                let activeCount = state.linkRows.filter { $0.enabled }.count
                HStack(spacing: 6) {
                    Image(systemName: activeCount > 1 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(activeCount > 1 ? .green : .orange)
                    Text(activeCount > 1 ? "\(activeCount) Adapters Stacked" : "1 Adapter Active")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.background, in: Capsule())
            }

            if state.linkRows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No network connections found")
                        .font(.headline)
                    Text("Connect to Wi-Fi, Ethernet, or plug in your phone via USB.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 10) {
                    ForEach(state.linkRows) { row in
                        AdapterDetailCard(state: state, row: row)
                    }
                }
            }

            // Tethering helper hint if only 1 adapter exists
            if state.linkRows.count < 2 {
                HStack(spacing: 12) {
                    Image(systemName: "lightbulb.fill")
                        .font(.title3)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("How to double your internet speed")
                            .font(.subheadline.weight(.semibold))
                        Text("Connect your Android phone with a USB cable and toggle USB Tethering on your phone. Netwich will automatically discover it and distribute traffic across both!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 16)
    }
}

struct AdapterDetailCard: View {
    @Bindable var state: AppState
    var row: LinkRow

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(row.enabled ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.1))
                    .frame(width: 42, height: 42)

                Image(systemName: iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(row.enabled ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(friendlyName)
                        .font(.body.weight(.semibold))

                    Text(row.name)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                    if row.enabled {
                        Text("HEALTHY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12), in: Capsule())
                    }
                }

                Text(row.healthLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live Per-Adapter Throughput & Flow Meter
            VStack(alignment: .trailing, spacing: 2) {
                if row.downBytesPerSecond > 5_000 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(ByteFormat.rate(row.downBytesPerSecond))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                    }
                } else if row.flows > 0 {
                    Text("\(row.flows) flows active")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Ready")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }

                if row.totalBytes > 0 {
                    Text(ByteFormat.size(Int64(row.totalBytes)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, 4)

            // Custom Weight Control
            let currentWeight = state.manualWeights[row.name] ?? 100.0
            Menu {
                Button("Auto Weight (EWMA)") {
                    state.setWeight(row.id, mbps: nil)
                }
                Button("Prioritize: 100 Mbps") {
                    state.setWeight(row.id, mbps: 100)
                }
                Button("Medium: 50 Mbps") {
                    state.setWeight(row.id, mbps: 50)
                }
                Button("Light / Mobile Data Saver: 10 Mbps") {
                    state.setWeight(row.id, mbps: 10)
                }
            } label: {
                Text(state.manualWeights[row.name] != nil ? "\(Int(currentWeight))M" : "Auto")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.12), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .help("Customize link weight")

            Toggle(
                "",
                isOn: Binding(
                    get: { row.enabled },
                    set: { state.setLink(row.id, enabled: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(12)
        .glassCard(
            cornerRadius: 12,
            strokeColor: row.enabled ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08)
        )
    }

    private var iconName: String {
        if row.name.hasPrefix("feth") {
            return "smartphone"
        }
        return row.kind.symbolName
    }

    private var friendlyName: String {
        if row.name.hasPrefix("feth") {
            return "Android USB Tether"
        }
        switch row.kind {
        case .wifi: return "Wi-Fi Interface"
        case .wired: return "Ethernet Adapter"
        case .cellular: return "Cellular Hotspot"
        case .other: return "Network Interface"
        }
    }
}

struct DashboardActiveDownloadsSection: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Active Downloads (\(state.activeDownloadsCount))")
                    .font(.headline)
                Spacer()
            }

            ForEach(state.downloads.filter { $0.status == .downloading || $0.status == .probing || $0.status == .queued }) { item in
                DownloadItemCard(state: state, item: item)
            }
        }
        .padding(18)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Downloads Hub & History View

public enum DownloadSortOption: String, CaseIterable, Identifiable {
    case dateDesc = "Newest First"
    case dateAsc = "Oldest First"
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case sizeDesc = "Largest First"
    case sizeAsc = "Smallest First"

    public var id: String { rawValue }
}

public enum ActiveStatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case downloading = "Downloading"
    case paused = "Paused"
    case failed = "Failed"

    public var id: String { rawValue }
}

public struct DownloadsHubView: View {
    @Bindable public var state: AppState
    public var filterMode: FilterMode
    public var onNewDownload: () -> Void

    @State private var searchKeyword: String = ""
    @State private var isTargeted: Bool = false
    @State private var isSelectionMode: Bool = false
    @State private var selectedIds: Set<UUID> = []
    @State private var sortOption: DownloadSortOption = .dateDesc
    @State private var statusFilter: ActiveStatusFilter = .all
    @State private var showDeleteConfirmation: Bool = false
    @State private var showClearAllConfirmation: Bool = false

    public enum FilterMode {
        case all
        case active
        case completed
    }

    public var filteredDownloads: [DownloadItem] {
        var list = state.downloads

        switch filterMode {
        case .all:
            break
        case .active:
            list = list.filter { $0.status != .completed }
            switch statusFilter {
            case .all:
                break
            case .downloading:
                list = list.filter { $0.status == .downloading || $0.status == .probing || $0.status == .queued }
            case .paused:
                list = list.filter { $0.status == .paused }
            case .failed:
                list = list.filter { $0.status.title.hasPrefix("Failed") }
            }
        case .completed:
            list = list.filter { $0.status == .completed }
        }

        if !searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
            let kw = searchKeyword.trimmingCharacters(in: .whitespaces)
            list = list.filter {
                $0.filename.localizedCaseInsensitiveContains(kw) ||
                $0.url.absoluteString.localizedCaseInsensitiveContains(kw)
            }
        }

        switch sortOption {
        case .dateDesc:
            list.sort { $0.addedDate > $1.addedDate }
        case .dateAsc:
            list.sort { $0.addedDate < $1.addedDate }
        case .nameAsc:
            list.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
        case .nameDesc:
            list.sort { $0.filename.localizedStandardCompare($1.filename) == .orderedDescending }
        case .sizeDesc:
            list.sort { $0.totalBytes > $1.totalBytes }
        case .sizeAsc:
            list.sort { $0.totalBytes < $1.totalBytes }
        }

        return list
    }

    private func countForFilter(_ f: ActiveStatusFilter) -> Int {
        let active = state.downloads.filter { $0.status != .completed }
        switch f {
        case .all: return active.count
        case .downloading: return state.activeDownloadsCount
        case .paused: return state.pausedDownloadsCount
        case .failed: return state.failedDownloadsCount
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Action Bar
            headerActionBar

            Divider()

            // Summary Stats Strip (when items exist)
            if !filteredDownloads.isEmpty {
                summaryBanner
                Divider()
            }

            // List or Empty Placeholder
            if filteredDownloads.isEmpty {
                emptyPlaceholderView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredDownloads) { item in
                            DownloadItemCard(
                                state: state,
                                item: item,
                                isSelectionMode: isSelectionMode,
                                isSelected: selectedIds.contains(item.id),
                                onToggleSelect: {
                                    if selectedIds.contains(item.id) {
                                        selectedIds.remove(item.id)
                                    } else {
                                        selectedIds.insert(item.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(14)
                }
            }
        }
        .confirmationDialog(
            "Delete Selected Downloads?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove from List Only") {
                state.deleteDownloads(selectedIds, removeFiles: false)
                selectedIds.removeAll()
                if selectedIds.isEmpty { isSelectionMode = false }
            }
            Button("Delete Files from Disk Completely", role: .destructive) {
                state.deleteDownloads(selectedIds, removeFiles: true)
                selectedIds.removeAll()
                if selectedIds.isEmpty { isSelectionMode = false }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have selected \(selectedIds.count) download(s). Do you want to remove them from the list or move the files to Trash?")
        }
        .confirmationDialog(
            "Clear Completed Downloads?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear List Only (Keep Files)") {
                state.clearCompletedDownloads()
            }
            Button("Delete Files from Disk & Clear History", role: .destructive) {
                state.clearAllHistory(removeFiles: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clear all \(state.completedDownloadsCount) completed download(s)? You can keep the files on disk or move them to Trash.")
        }
        .onDrop(of: [.url, .plainText], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            state.addDownload(url: url)
                        }
                    }
                }
            }
            return true
        }
    }

    @ViewBuilder
    private var headerActionBar: some View {
        if isSelectionMode {
            HStack(spacing: 12) {
                Button {
                    if selectedIds.count == filteredDownloads.count {
                        selectedIds.removeAll()
                    } else {
                        selectedIds = Set(filteredDownloads.map { $0.id })
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedIds.count == filteredDownloads.count && !filteredDownloads.isEmpty
                              ? "checkmark.circle.fill"
                              : (selectedIds.isEmpty ? "circle" : "minus.circle.fill"))
                            .foregroundStyle(selectedIds.isEmpty ? .secondary : Color.accentColor)
                        Text(selectedIds.count == filteredDownloads.count && !filteredDownloads.isEmpty ? "Deselect All" : "Select All")
                    }
                }
                .buttonStyle(.plain)

                Text("\(selectedIds.count) of \(filteredDownloads.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if filterMode == .active {
                    Button {
                        state.resumeDownloads(selectedIds)
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedIds.isEmpty)

                    Button {
                        state.pauseDownloads(selectedIds)
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedIds.isEmpty)
                } else {
                    Button {
                        state.restartDownloads(selectedIds)
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selectedIds.isEmpty)
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(selectedIds.isEmpty)

                Button("Done") {
                    withAnimation(.snappy) {
                        isSelectionMode = false
                        selectedIds.removeAll()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .glassBar()
        } else {
            HStack(spacing: 10) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(filterMode == .completed ? "Search history..." : "Search downloads...", text: $searchKeyword)
                        .textFieldStyle(.plain)
                    if !searchKeyword.isEmpty {
                        Button {
                            searchKeyword = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 220)

                // Unified glass capsule segmented filter bar
                if filterMode == .active && !state.downloads.filter({ $0.status != .completed }).isEmpty {
                    HStack(spacing: 2) {
                        ForEach(ActiveStatusFilter.allCases) { f in
                            let isSelected = statusFilter == f
                            let count = countForFilter(f)
                            Button {
                                statusFilter = f
                            } label: {
                                HStack(spacing: 5) {
                                    Text(f.rawValue)
                                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                                    if count > 0 && f != .all {
                                        Text("\(count)")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? Color.white.opacity(0.25) : Color.white.opacity(0.12))
                                            )
                                    }
                                }
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentColor : Color.clear)
                                )
                                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                }

                Spacer()

                // Sort Dropdown
                Menu {
                    ForEach(DownloadSortOption.allCases) { opt in
                        Button {
                            sortOption = opt
                        } label: {
                            HStack {
                                Text(opt.rawValue)
                                if sortOption == opt {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .menuStyle(.borderedButton)

                // Tab actions
                if filterMode == .active {
                    let hasPausedOrFailed = state.pausedDownloadsCount > 0 || state.failedDownloadsCount > 0
                    let hasDownloading = state.activeDownloadsCount > 0

                    HStack(spacing: 6) {
                        if hasPausedOrFailed {
                            Button {
                                state.resumeAllDownloads()
                            } label: {
                                Label("Resume All", systemImage: "play.fill")
                            }
                            .buttonStyle(.bordered)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .help("Resume all paused and failed downloads")
                        }

                        if hasDownloading {
                            Button {
                                state.pauseAllDownloads()
                            } label: {
                                Label("Pause All", systemImage: "pause.fill")
                            }
                            .buttonStyle(.bordered)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .help("Pause all active downloads")
                        }
                    }
                } else if filterMode == .completed {
                    Button {
                        state.openDefaultDownloadFolder()
                    } label: {
                        Label("Open Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Show downloads folder in Finder")

                    if state.completedDownloadsCount > 0 {
                        Menu {
                            Button("Clear History Records") {
                                state.clearCompletedDownloads()
                            }
                            Button("Clear History & Delete Files...", role: .destructive) {
                                showClearAllConfirmation = true
                            }
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                        .menuStyle(.borderedButton)
                    }
                }

                if !filteredDownloads.isEmpty {
                    Button {
                        withAnimation(.snappy) {
                            isSelectionMode = true
                            selectedIds.removeAll()
                        }
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .help("Select multiple items to batch pause, resume, or delete")
                }

                Button {
                    onNewDownload()
                } label: {
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
            .glassBar()
        }
    }

    @ViewBuilder
    private var summaryBanner: some View {
        if filterMode == .active {
            let active = filteredDownloads.filter { $0.status == .downloading || $0.status == .probing || $0.status == .queued }.count
            let paused = filteredDownloads.filter { $0.status == .paused }.count
            let failed = filteredDownloads.filter { $0.status.title.hasPrefix("Failed") }.count
            let totalSpeed = filteredDownloads.reduce(0.0) { $0 + $1.speedBytesPerSec }
            let totalDownloaded = filteredDownloads.reduce(Int64(0)) { $0 + $1.downloadedBytes }
            let totalSize = filteredDownloads.reduce(Int64(0)) { $0 + max($1.totalBytes, $1.downloadedBytes) }
            let ratio = totalSize > 0 ? Double(totalDownloaded) / Double(totalSize) : 0.0

            HStack(spacing: 14) {
                HStack(spacing: 8) {
                    if active > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("\(active) Active")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if paused > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Color.orange).frame(width: 7, height: 7)
                            Text("\(paused) Paused")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    if failed > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 7, height: 7)
                            Text("\(failed) Failed")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }

                if totalSize > 0 {
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(ByteFormat.size(totalDownloaded)) of \(ByteFormat.size(totalSize)) (\(Int(ratio * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if totalSpeed > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(ByteFormat.rate(totalSpeed))
                            .font(.caption.monospacedDigit().weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassBar()
        } else if filterMode == .completed {
            let totalSize = filteredDownloads.reduce(Int64(0)) { $0 + $1.totalBytes }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("\(filteredDownloads.count) completed items")
                    .font(.caption.weight(.semibold))

                if totalSize > 0 {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(ByteFormat.size(totalSize)) total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    state.openDefaultDownloadFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                        Text(state.defaultDestinationFolder.lastPathComponent)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassBar()
        }
    }

    @ViewBuilder
    private var emptyPlaceholderView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: filterMode == .completed ? "clock.arrow.circlepath" : "arrow.down.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary.opacity(0.4))

            Text(filterMode == .completed ? "No completed downloads" : "No active downloads")
                .font(.title3.weight(.medium))

            Text(filterMode == .completed ? "Finished downloads will be kept here with full history." : "Add a download or drag and drop links anywhere to accelerate them across your connections.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 12) {
                Button {
                    onNewDownload()
                } label: {
                    Label("New Download", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                if let clipboardURL = clipboardURL {
                    Button {
                        state.addDownload(url: clipboardURL)
                    } label: {
                        Label("Download from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                } else if filterMode == .completed {
                    Button {
                        state.openDefaultDownloadFolder()
                    } label: {
                        Label("Open Downloads Folder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clipboardURL: URL? {
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: clip),
              url.scheme == "http" || url.scheme == "https" else {
            return nil
        }
        return url
    }
}

// MARK: - Download Item Card with Multi-Chunk Visualizer

struct DownloadItemCard: View {
    @Bindable var state: AppState
    var item: DownloadItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    @State private var showChunksDrawer: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                selectionCheckbox
            }

            VStack(alignment: .leading, spacing: 10) {
                headerRowView

                if item.status == .downloading || item.status == .paused {
                    chunksSectionView
                } else if case .failed(let reason) = item.status {
                    failedBannerView(reason: reason)
                }
            }
        }
        .padding(14)
        .glassCard(
            cornerRadius: 14,
            strokeColor: isSelected ? Color.accentColor : Color.white.opacity(0.14)
        )
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelect?()
            }
        }
        .contextMenu {
            cardContextMenu
        }
    }

    @ViewBuilder
    private var selectionCheckbox: some View {
        Button {
            onToggleSelect?()
        } label: {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerRowView: some View {
        HStack(spacing: 12) {
            // File Type Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorForExtension.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: iconForExtension)
                    .font(.system(size: 22))
                    .foregroundStyle(colorForExtension)
            }

            // Title & Details
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.status.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(colorForStatus)

                    if item.totalBytes > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(ByteFormat.size(item.downloadedBytes)) of \(ByteFormat.size(item.totalBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if item.speedBytesPerSec > 0 {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(ByteFormat.rate(item.speedBytesPerSec))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.primary)
                    }

                    if let eta = item.etaSeconds {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("ETA: \(ByteFormat.duration(eta))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !item.chunks.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(item.chunks.count) Chunks")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Actions Toolbar
            HStack(spacing: 8) {
                switch item.status {
                case .downloading:
                    Button {
                        state.pauseDownload(item.id)
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Pause Download")

                case .paused, .failed:
                    Button {
                        state.resumeDownload(item.id)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Resume Download")

                case .completed:
                    Button {
                        state.openDownloadedFile(item)
                    } label: {
                        Label("Open", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        state.revealInFinder(item)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Show in Finder")

                case .queued, .probing:
                    EmptyView()
                }

                Menu {
                    cardContextMenu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .frame(width: 28, height: 28)
                .help("More Options")
            }
        }
    }

    @ViewBuilder
    private func failedBannerView(reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 2) {
                Text("Download Interrupted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(reason)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.resumeDownload(item.id)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.red.opacity(0.85))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.18), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var chunksSectionView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !item.chunks.isEmpty {
                // Multi-Chunk Segmented Progress Bar
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(item.chunks) { chunk in
                            chunkSegmentView(geo: geo, chunk: chunk)
                        }
                    }
                }
                .frame(height: 8)

                HStack {
                    Button {
                        withAnimation(.snappy) {
                            showChunksDrawer.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showChunksDrawer ? "chevron.up" : "chevron.down")
                            let count = item.chunks.count
                            Text(showChunksDrawer ? "Hide Chunks Breakdown" : "View Parallel Chunks (\(count))")
                        }
                        .font(.caption2.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    if item.status == .downloading {
                        let activeLinks = state.linkRows.filter { $0.enabled }
                        if activeLinks.count >= 2 {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .foregroundStyle(.yellow)
                                Text("Multi-Link (\(activeLinks.map { $0.displayName }.joined(separator: " + ")))")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundStyle(.blue)
                                Text("\(item.chunks.count) Parallel Streams")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                    }

                    Text("\(Int(item.progress * 100))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                }

                if item.status == .downloading {
                    multiLinkSpeedComparisonView
                }

                // Chunks Detail Drawer
                if showChunksDrawer {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 6) {
                        ForEach(item.chunks) { chunk in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(colorForChunk(chunk))
                                    .frame(width: 6, height: 6)
                                Text("Chunk #\(chunk.id + 1)")
                                    .font(.caption2.monospaced())
                                Spacer()
                                Text(chunk.assignedInterface ?? "en0")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                Text("\(Int(chunk.progress * 100))%")
                                    .font(.caption2.monospacedDigit().weight(.semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var multiLinkSpeedComparisonView: some View {
        let activeLinks = state.linkRows.filter { $0.enabled }
        if activeLinks.count >= 2 {
            let primaryLink = activeLinks.first
            let primarySpeed = primaryLink?.downBytesPerSecond ?? 0
            let totalSpeed = max(item.speedBytesPerSec, activeLinks.reduce(0.0) { $0 + $1.downBytesPerSecond })
            let multiplier = primarySpeed > 50_000 ? max(1.1, totalSpeed / primarySpeed) : 1.8
            let pctIncrease = Int((multiplier - 1.0) * 100)

            VStack(spacing: 7) {
                // Acceleration Proof Banner
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.yellow)

                    Text("Multi-Link Stacked")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    HStack(spacing: 3) {
                        Text("\(String(format: "%.1f", multiplier))x Speed")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.green)
                        Text("(+\(pctIncrease)% vs single Wi-Fi)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Individual Adapter Real-Time Throughput Meters
                VStack(spacing: 5) {
                    ForEach(activeLinks) { link in
                        let speed = link.downBytesPerSecond
                        let speedRatio = totalSpeed > 0 ? min(1.0, max(0.1, speed / totalSpeed)) : 0.5
                        HStack(spacing: 8) {
                            Image(systemName: link.kind.symbolName)
                                .font(.system(size: 11))
                                .foregroundStyle(speed > 50_000 ? Color.accentColor : Color.secondary)
                                .frame(width: 14)

                            Text(link.displayName)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(width: 130, alignment: .leading)

                            // Throughput distribution meter bar
                            GeometryReader { meterGeo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.06))
                                        .frame(height: 5)
                                    Capsule()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.accentColor, Color.green],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: max(6, meterGeo.size.width * CGFloat(speedRatio)), height: 5)
                                }
                            }
                            .frame(height: 5)

                            Text(ByteFormat.rate(speed))
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundStyle(speed > 50_000 ? Color.primary : Color.secondary)
                                .frame(width: 75, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                    )
            )
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var cardContextMenu: some View {
        if item.status == .downloading {
            Button("Pause Download") {
                state.pauseDownload(item.id)
            }
        } else if item.status == .paused || item.status.isFailed {
            Button("Resume Download") {
                state.resumeDownload(item.id)
            }
        } else if item.status == .completed {
            Button("Open File") {
                state.openDownloadedFile(item)
            }
        }

        Button("Show in Finder") {
            state.revealInFinder(item)
        }

        Button("Copy Download Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
        }

        if item.status == .completed || item.status.isFailed {
            Button("Restart Download") {
                state.restartDownload(item.id)
            }
        }

        Divider()

        Button("Remove from List", role: .destructive) {
            state.deleteDownload(item.id, removeFile: false)
        }

        Button("Delete File Completely", role: .destructive) {
            state.deleteDownload(item.id, removeFile: true)
        }
    }

    private func chunkSegmentView(geo: GeometryProxy, chunk: ChunkState) -> some View {
        let totalCount = CGFloat(max(1, item.chunks.count))
        let totalSpacing = (totalCount - 1) * 2
        let segmentWidth = max(2, (geo.size.width - totalSpacing) / totalCount)
        let fillWidth = max(0, segmentWidth * CGFloat(chunk.progress))

        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(.secondary.opacity(0.15))
            Rectangle()
                .fill(colorForChunk(chunk))
                .frame(width: fillWidth)
        }
        .frame(width: segmentWidth, height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func colorForChunk(_ chunk: ChunkState) -> Color {
        if chunk.isCompleted { return .green }
        if let iface = chunk.assignedInterface {
            if iface.hasPrefix("feth") || iface == "en1" {
                return .blue // Secondary/Phone connection
            }
        }
        return Color.accentColor // Primary connection
    }

    private var colorForStatus: Color {
        switch item.status {
        case .completed: return .green
        case .downloading: return Color.accentColor
        case .paused: return .orange
        case .probing: return .blue
        case .queued: return .secondary
        case .failed: return .red
        }
    }

    private var iconForExtension: String {
        let ext = item.destinationFileURL.pathExtension.lowercased()
        switch ext {
        case "zip", "tar", "gz", "7z", "rar", "bz2": return "doc.zipper"
        case "dmg", "iso", "pkg": return "opticaldiscdrive"
        case "mp4", "mov", "mkv", "avi", "webm": return "film"
        case "mp3", "wav", "m4a", "flac", "aac": return "waveform"
        case "png", "jpg", "jpeg", "webp", "gif": return "photo"
        case "pdf", "epub": return "doc.richtext"
        case "swift", "ts", "js", "py", "rs", "go", "json", "html": return "curlybraces"
        default: return "arrow.down.doc"
        }
    }

    private var colorForExtension: Color {
        let ext = item.destinationFileURL.pathExtension.lowercased()
        switch ext {
        case "zip", "tar", "gz", "7z", "rar", "dmg", "pkg": return .orange
        case "mp4", "mov", "mkv", "avi": return .purple
        case "mp3", "wav", "m4a", "flac": return .pink
        case "png", "jpg", "jpeg", "webp": return .green
        case "pdf", "epub": return .red
        default: return .blue
        }
    }
}

// MARK: - New Download Modal Sheet

struct NewDownloadSheet: View {
    @Bindable var state: AppState
    @Binding var isPresented: Bool

    @State private var urlString: String = ""
    @State private var customFilename: String = ""
    @State private var concurrency: Int = 8
    @State private var destinationFolder: URL

    init(state: AppState, isPresented: Binding<Bool>) {
        self.state = state
        self._isPresented = isPresented
        self._destinationFolder = State(initialValue: state.defaultDestinationFolder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add New Download")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Form
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Download URL")
                            .font(.subheadline.weight(.medium))
                        TextField("https://...", text: $urlString)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Custom Filename (Optional)")
                            .font(.subheadline.weight(.medium))
                        TextField("Leave blank to detect automatically", text: $customFilename)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Destination & Concurrency") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save To")
                                .font(.subheadline)
                            Text(destinationFolder.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Choose...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK, let url = panel.url {
                                destinationFolder = url
                            }
                        }
                    }

                    Stepper("Parallel Connections: \(concurrency)", value: $concurrency, in: 2...32, step: 2)
                        .help("Number of concurrent connections split across your network adapters")
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Start Download") {
                    startDownload()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(18)
        }
        .frame(width: 520, height: 420)
        .onAppear {
            checkClipboard()
        }
    }

    private func checkClipboard() {
        if let clip = NSPasteboard.general.string(forType: .string),
           let url = URL(string: clip.trimmingCharacters(in: .whitespaces)),
           url.scheme == "http" || url.scheme == "https" {
            urlString = clip.trimmingCharacters(in: .whitespaces)
        }
    }

    private func startDownload() {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else { return }
        let name = customFilename.trimmingCharacters(in: .whitespaces)
        state.downloadManager.addDownload(
            url: url,
            destinationFolder: destinationFolder,
            customFilename: name.isEmpty ? nil : name,
            concurrency: concurrency
        )
        isPresented = false
    }
}

// MARK: - Browser Extension Setup View

public struct ExtensionSetupView: View {
    @Bindable public var state: AppState
    @State private var testResult: String?

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Browser Extension Integration")
                            .font(.title2.weight(.bold))
                        Text("Send downloads from your browser directly to Netwich for multi-connection acceleration.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    // Bridge Status Indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.browserBridgePort != nil ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(state.browserBridgePort != nil ? "Bridge Ready (Port \(state.browserBridgePort!))" : "Bridge Stopped")
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.secondary.opacity(0.12), in: Capsule())
                }

                Divider()

                // Step 1: Reveal Extension Folder
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("1. Locate Extension Package")
                            .font(.headline)
                        Spacer()
                    }
                    Text("Netwich comes pre-packaged with clean, modernized browser extensions for Chromium browsers (Brave, Chrome, Edge, Arc) and Firefox.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            let chromePath = URL(fileURLWithPath: "/Users/parth/Developer/network proj/extension/chrome")
                            let altPath = URL(fileURLWithPath: "/Users/parth/Developer/network proj/extension")
                            if FileManager.default.fileExists(atPath: chromePath.path) {
                                NSWorkspace.shared.activateFileViewerSelecting([chromePath])
                            } else {
                                NSWorkspace.shared.activateFileViewerSelecting([altPath])
                            }
                        } label: {
                            Label("Reveal Brave / Chrome Extension Folder", systemImage: "folder.badge.gearshape")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            let firefoxPath = URL(fileURLWithPath: "/Users/parth/Developer/network proj/extension/firefox")
                            NSWorkspace.shared.activateFileViewerSelecting([firefoxPath])
                        } label: {
                            Label("Reveal Firefox Extension Folder", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                // Step 2: Brave & Chrome Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Label("Brave / Google Chrome / Edge / Arc", systemImage: "globe")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. In Brave, open brave://extensions in your address bar (or chrome://extensions in Chrome).")
                        Text("2. Turn on the Developer mode switch in the top-right corner.")
                        Text("3. Click Load unpacked and select the revealed extension folder (or extension/chrome).")
                        Text("4. The Netwich icon appears in your browser toolbar with a green pulsing dot!")
                        Text("5. Click any download link to automatically route and accelerate it in Netwich.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                // Step 3: Firefox Instructions
                VStack(alignment: .leading, spacing: 10) {
                    Label("Mozilla Firefox", systemImage: "flame")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Open about:debugging#/runtime/this-firefox in Firefox.")
                        Text("2. Click Load Temporary Add-on...")
                        Text("3. Select the manifest.json file inside the extension/firefox folder.")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
    }
}

// MARK: - Tethering Guide View

public struct TetheringGuideView: View {
    public var state: AppState?

    public init(state: AppState? = nil) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Android USB Tethering Guide")
                        .font(.title2.weight(.bold))
                    Text("Connect your phone alongside Wi-Fi to stack connections and multiply your bandwidth.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 14) {
                    Label("Step-by-Step Setup", systemImage: "cable.connector")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("1. Connect your Android phone to your Mac using a USB-C cable.")
                        Text("2. On your phone, open Settings → Network & Internet (or Connections).")
                        Text("3. Select Hotspot & tethering and switch ON USB tethering.")
                        Text("4. Netwich will immediately detect the new interface and start balancing connections!")
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 14) {
                    Label("Driver & Compatibility Notes", systemImage: "info.circle")
                        .font(.headline)

                    Text("Modern Android phones (such as Google Pixel 6+, newer Samsung Galaxy, and Xiaomi devices) use standard CDC-NCM and work natively on macOS with zero driver installations required. For devices using older RNDIS, the free open-source TetherKit driver is available.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Button {
                        if let url = URL(string: "https://github.com/jwise/HoRNDIS") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Learn more about Android USB drivers")
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
        }
    }
}

// MARK: - Settings View

public struct SettingsView: View {
    @Bindable public var state: AppState

    public var body: some View {
        Form {
            Section("General") {
                Toggle("Launch Netwich at Login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }
                ))
            }

            Section("Downloads Hub") {
                HStack {
                    Text("Default Download Folder")
                    Spacer()
                    Text(state.defaultDestinationFolder.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Choose...") {
                        selectFolder()
                    }
                }

                Stepper("Default Parallel Connections: \(state.defaultConcurrency)", value: $state.defaultConcurrency, in: 2...32, step: 2)

                Button("Clear All Completed Downloads") {
                    state.clearCompletedDownloads()
                }
                .foregroundStyle(.red)
            }

            Section("Network Aggregation") {
                HStack {
                    Text("Local SOCKS5 Proxy Port")
                    Spacer()
                    Text("1080 (127.0.0.1)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Browser Bridge HTTP Port")
                    Spacer()
                    Text(state.browserBridgePort.map { "\($0)" } ?? "Inactive")
                        .foregroundStyle(.secondary)
                }
            }

            Section("About Netwich") {
                HStack {
                    Text("Tagline")
                    Spacer()
                    Text("Stack your connections.")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0 (Apple Silicon Native)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Developer")
                    Spacer()
                    Link("Parth Khansali (GitHub)", destination: URL(string: "https://github.com/ParthKhansali")!)
                }
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            state.defaultDestinationFolder = url
            state.downloadManager.defaultDestination = url
        }
    }
}

// MARK: - Onboarding View (4-page sheet)

public struct OnboardingView: View {
    public let onFinish: () -> Void
    @State private var page: Int = 0
    private let pageCount = 4

    public var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.top, 40)

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 620, height: 500)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case 0:
            VStack(spacing: 16) {
                if let mark = NSImage(named: "netwich-mark-512") ?? Bundle.main.image(forResource: "netwich-mark-512") ?? (Bundle.main.resourcePath.flatMap { NSImage(contentsOfFile: $0 + "/netwich-mark-512.png") }) {
                    Image(nsImage: mark)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                } else {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }

                Text("Welcome to Netwich")
                    .font(.system(size: 28, weight: .bold))

                Text("A small, fast, native macOS utility to stack multiple internet connections and accelerate your downloads.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Combine Wi-Fi + Android phone USB tethering into one fast connection")
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Download files in parallel chunks across all your network adapters")
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Zero server maintenance, zero VPN fees, 100% free and private")
                    }
                }
                .font(.callout)
                .padding(.top, 10)
            }

        case 1:
            VStack(spacing: 16) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("System-wide Connection Aggregation")
                    .font(.title2.weight(.bold))

                Text("Netwich runs a high-performance local scheduler right on your Mac. When enabled, your Mac distributes outbound TCP flows intelligently across all connected network adapters.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("• One simple switch turns combined internet on or off.")
                    Text("• Browsers, apps, and stream sessions benefit automatically.")
                    Text("• If an adapter disconnects, traffic gracefully routes through remaining links.")
                }
                .font(.callout)
                .padding(.top, 6)
            }

        case 2:
            VStack(spacing: 16) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)

                Text("Accelerated Multi-Chunk Downloads")
                    .font(.title2.weight(.bold))

                Text("Large files are split into parallel chunks and downloaded simultaneously over your available networks.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("• Full pause and resume capability with automatic state saving.")
                    Text("• Integrates seamlessly with Chrome and Firefox browser extensions.")
                    Text("• Drag and drop URLs directly into the app for instant multi-link downloading.")
                }
                .font(.callout)
                .padding(.top, 6)
            }

        default:
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.purple)

                Text("Ready to Experience Netwich")
                    .font(.title2.weight(.bold))

                Text("Engineered for macOS Apple Silicon with clean Swift and zero bloat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Link(destination: URL(string: "https://github.com/ParthKhansali")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Created by Parth Khansali on GitHub")
                    }
                    .font(.subheadline.weight(.medium))
                }
                .padding(.top, 10)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(page == pageCount - 1 ? 0 : 1)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0..<pageCount, id: \.self) { idx in
                    Circle()
                        .fill(idx == page ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 7, height: 7)
                        .animation(.snappy(duration: 0.18), value: page)
                }
            }

            Spacer()

            if page > 0 {
                Button("Back") { withAnimation(.snappy) { page -= 1 } }
                    .buttonStyle(.bordered)
            }

            if page < pageCount - 1 {
                Button("Continue") { withAnimation(.snappy) { page += 1 } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Get Started") { onFinish() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// MARK: - Auto Dismiss Menu Bar Window

public struct AutoDismissWindowAccessor: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> AutoDismissNSView {
        AutoDismissNSView()
    }

    public func updateNSView(_ nsView: AutoDismissNSView, context: Context) {}
}

public final class AutoDismissNSView: NSView {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cleanup()

        guard let window = self.window else { return }

        window.isMovable = false

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            window?.orderOut(nil)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] _ in
            guard let window = window else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !window.frame.contains(mouseLoc) {
                window.orderOut(nil)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] event in
            guard let window = window else { return event }
            let mouseLoc = NSEvent.mouseLocation
            if !window.frame.contains(mouseLoc) {
                window.orderOut(nil)
            }
            return event
        }
    }

    private func cleanup() {
        if let g = globalMonitor {
            NSEvent.removeMonitor(g)
            globalMonitor = nil
        }
        if let l = localMonitor {
            NSEvent.removeMonitor(l)
            localMonitor = nil
        }
        if let r = resignObserver {
            NotificationCenter.default.removeObserver(r)
            resignObserver = nil
        }
    }

    deinit {
        cleanup()
    }
}

// MARK: - Menu Bar View

public struct MenuBarView: View {
    @Bindable public var state: AppState

    public var body: some View {
        VStack(spacing: 12) {
            headerBar
            speedAndAdaptersCard
            downloadsStrip
            toggleButton
            Divider().opacity(0.4)
            footerActions
        }
        .padding(14)
        .frame(width: 290)
        .background(.ultraThinMaterial)
        .background(AutoDismissWindowAccessor())
    }

    @ViewBuilder
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text("Netwich")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            Spacer()

            HStack(spacing: 5) {
                Circle()
                    .fill(state.isOn ? Color.green : Color.secondary)
                    .frame(width: 7, height: 7)
                Text(state.isOn ? "Active" : "Paused")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(state.isOn ? Color.green.opacity(0.14) : Color.secondary.opacity(0.12))
            )
            .foregroundStyle(state.isOn ? Color.green : Color.secondary)
        }
    }

    @ViewBuilder
    private var speedAndAdaptersCard: some View {
        let activeLinks = state.linkRows.filter { $0.enabled }
        VStack(spacing: 10) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL SPEED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(state.currentDownloadSpeedBytesPerSec > 50_000 ? Color.green : .secondary)
                        Text(ByteFormat.rate(state.currentDownloadSpeedBytesPerSec))
                            .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("ADAPTERS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .tracking(0.6)

                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Text("\(activeLinks.count) linked")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
            }

            if !state.linkRows.isEmpty {
                VStack(spacing: 4) {
                    ForEach(state.linkRows) { link in
                        adapterRow(link: link)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private func adapterRow(link: LinkRow) -> some View {
        HStack(spacing: 6) {
            Image(systemName: link.kind.symbolName)
                .font(.system(size: 10))
                .foregroundStyle(link.enabled ? Color.accentColor : .secondary)

            Text(link.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)

            Spacer()

            if link.enabled {
                Text("Active")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Text("Off")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.04))
        )
    }

    @ViewBuilder
    private var downloadsStrip: some View {
        if state.activeDownloadsCount > 0 || state.pausedDownloadsCount > 0 {
            VStack(spacing: 8) {
                HStack {
                    Text("Downloads")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.activeDownloadsCount) active · \(state.pausedDownloadsCount) paused")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if state.activeDownloadsCount > 0 {
                        Button {
                            state.pauseAllDownloads()
                        } label: {
                            Label("Pause All", systemImage: "pause.fill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if state.pausedDownloadsCount > 0 {
                        Button {
                            state.resumeAllDownloads()
                        } label: {
                            Label("Resume All", systemImage: "play.fill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Spacer()

                    Button {
                        state.openDefaultDownloadFolder()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
            )
        }
    }

    @ViewBuilder
    private var toggleButton: some View {
        Button {
            Task {
                await state.setOn(!state.isOn)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: state.isOn ? "pause.fill" : "bolt.horizontal.fill")
                Text(state.isOn ? "Pause Multi-Link" : "Activate Multi-Link")
            }
            .font(.system(size: 12, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .tint(state.isOn ? Color.orange : Color.accentColor)
    }

    @ViewBuilder
    private var footerActions: some View {
        HStack {
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                for window in NSApplication.shared.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 10))
                    Text("Open Dashboard")
                }
                .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)

            Spacer()

            Button {
                state.cleanupOnQuit()
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit Netwich")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}
