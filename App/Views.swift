import AppKit
import MergeKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Formatting

enum ByteFormat {
    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "0 KB/s" }
        if bytesPerSecond >= 1_000_000_000 { return String(format: "%.2f GB/s", bytesPerSecond / 1_000_000_000) }
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000) }
        if bytesPerSecond >= 1_000 { return String(format: "%.0f KB/s", bytesPerSecond / 1_000) }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    static func size(_ bytes: Int64) -> String {
        guard bytes >= 0 else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "--" }
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds) / 60)m \(Int(seconds) % 60)s" }
        return "\(Int(seconds) / 3600)h \((Int(seconds) % 3600) / 60)m"
    }

    static func mbps(_ value: Double) -> String {
        value >= 1 ? String(format: "%.0f Mbps", value) : "Auto"
    }
}

// MARK: - Root shell

struct RootView: View {
    @Bindable var state: AppState
    @State private var tab: Tab = .overview
    @State private var showNewDownload = false
    @State private var showSetup = false
    @State private var isDropTargeted = false
    @AppStorage("hasOnboarded.v2") private var hasOnboarded = false

    enum Tab: String, CaseIterable, Identifiable {
        case overview, downloads, history, extensionPack, tethering, settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .overview: return "Overview"
            case .downloads: return "Downloads"
            case .history: return "History"
            case .extensionPack: return "Browser"
            case .tethering: return "Tethering"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "gauge.with.needle.fill"
            case .downloads: return "arrow.down.circle.fill"
            case .history: return "clock.arrow.circlepath"
            case .extensionPack: return "puzzlepiece.extension.fill"
            case .tethering: return "cable.connector"
            case .settings: return "gearshape.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            AuroraBackdrop(isActive: state.isOn)

            HStack(spacing: 0) {
                Sidebar(state: state, tab: $tab, onSetup: { showSetup = true })
                    .frame(width: 226)

                VStack(spacing: 0) {
                    PageHeader(title: tab.title, subtitle: subtitle) { headerActions }
                    Divider()
                        .overlay(Color.white.opacity(0.06))
                        .padding(.horizontal, 20)

                    Group {
                        switch tab {
                        case .overview:
                            OverviewPage(
                                state: state,
                                onNewDownload: { showNewDownload = true },
                                onOpenDownloads: { withAnimation(Motion.morph) { tab = .downloads } }
                            )
                        case .downloads:
                            DownloadsPage(state: state, scope: .active, onNewDownload: { showNewDownload = true })
                        case .history:
                            DownloadsPage(state: state, scope: .completed, onNewDownload: { showNewDownload = true })
                        case .extensionPack:
                            ExtensionPage(state: state)
                        case .tethering:
                            TetheringPage(state: state)
                        case .settings:
                            SettingsView(state: state)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(tab)
                    .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassSurface(cornerRadius: 24, elevated: true, strokeOpacity: 0.09)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .padding(.trailing, 12)
            }

            if isDropTargeted {
                dropOverlay
            }
        }
        .padding(.top, 26)
        .background(WindowChrome())
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 660)
        .sheet(isPresented: $showNewDownload) {
            NewDownloadSheet(state: state, isPresented: $showNewDownload)
        }
        .sheet(isPresented: $showSetup) {
            OnboardingView(state: state) {
                hasOnboarded = true
                showSetup = false
            }
        }
        .task {
            await state.bootstrap()
            if !hasOnboarded { showSetup = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewDownloadSheet)) { _ in
            showNewDownload = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSetupSheet)) { _ in
            showSetup = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectTab)) { note in
            guard let raw = note.object as? String, let next = Tab(rawValue: raw) else { return }
            withAnimation(Motion.morph) { tab = next }
        }
        .onDrop(of: [.url, .plainText], isTargeted: $isDropTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
                    Task { @MainActor in
                        state.addDownload(url: url)
                        withAnimation(Motion.morph) { tab = .downloads }
                    }
                }
            }
            return true
        }
    }

    private var subtitle: String {
        switch tab {
        case .overview: return "Every connection, working as one."
        case .downloads: return "Parallel chunks spread across your adapters."
        case .history: return "Everything Netwich has finished for you."
        case .extensionPack: return "Send downloads from your browser to Netwich."
        case .tethering: return "Add a phone as a second connection in minutes."
        case .settings: return "Defaults, network ports and setup checks."
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: 8) {
            if let port = state.browserBridgePort {
                StatusPill(text: "Bridge \(port)", color: Palette.mint)
            }
            if state.isOn {
                StatusPill(text: "Aggregating", color: Palette.accent, pulsing: true)
            }
            Button {
                showNewDownload = true
            } label: {
                Label("New Download", systemImage: "plus")
            }
            .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
            .help("Add a download (⌘N)")
        }
    }

    private var dropOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Palette.accent)
                Text("Drop a link to download")
                    .font(.system(size: 15, weight: .semibold))
                Text("Netwich splits it across every adapter.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(30)
            .glassSurface(cornerRadius: 22, tint: Palette.accent, tintStrength: 0.08)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var state: AppState
    @Binding var tab: RootView.Tab
    var onSetup: () -> Void
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 22)

            VStack(spacing: 2) {
                ForEach(RootView.Tab.allCases) { item in
                    navItem(item)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            SetupSummaryCard(state: state, action: onSetup)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                Circle()
                    .fill(state.isOn ? Palette.mint : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(state.isOn ? "Aggregation running" : "Aggregation paused")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { state.isOn },
                    set: { newValue in Task { await state.setOn(newValue) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(state.phase == .activating)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            Text("Netwich \(version)")
                .microLabel(Color.secondary.opacity(0.55))
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
        }
    }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    private var brand: some View {
        HStack(spacing: 10) {
            NetwichBrand.appIcon(size: 30)
                .shadow(color: Palette.accent.opacity(0.4), radius: 10, y: 3)

            VStack(alignment: .leading, spacing: 0) {
                Text("Netwich")
                    .font(.system(size: 14, weight: .semibold))
                Text("Stack your connections")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func badgeCount(for item: RootView.Tab) -> Int {
        switch item {
        case .downloads: return state.activeDownloadsCount
        case .history: return state.completedDownloadsCount
        case .settings: return state.setup.blockingCount
        default: return 0
        }
    }

    private func navItem(_ item: RootView.Tab) -> some View {
        let selected = tab == item
        let badge = badgeCount(for: item)

        return Button {
            withAnimation(Motion.morph) { tab = item }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Palette.accent : Color.secondary)

                Text(item.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))

                Spacer(minLength: 4)

                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(selected ? Palette.accent.opacity(0.25) : Color.white.opacity(0.09)))
                        .foregroundStyle(selected ? Palette.accent : Color.secondary)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.66))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
                        }
                        .matchedGeometryEffect(id: "nav.pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SetupSummaryCard: View {
    @Bindable var state: AppState
    var action: () -> Void

    var body: some View {
        let needsAttention = state.setup.blockingCount
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill((needsAttention > 0 ? Palette.amber : Palette.mint).opacity(0.16))
                        .frame(width: 26, height: 26)
                    Image(systemName: needsAttention > 0 ? "wrench.and.screwdriver.fill" : "checkmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(needsAttention > 0 ? Palette.amber : Palette.mint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(needsAttention > 0 ? "Setup needs attention" : "Everything is ready")
                        .font(.system(size: 11, weight: .semibold))
                    Text(needsAttention > 0 ? "\(needsAttention) check\(needsAttention == 1 ? "" : "s") to review" : "Permissions and extension")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Page header

private struct PageHeader<Actions: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }
}

// MARK: - Overview page

private struct OverviewPage: View {
    @Bindable var state: AppState
    var onNewDownload: () -> Void
    var onOpenDownloads: () -> Void
    @State private var appeared = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                HeroPanel(state: state)
                    .appear(0, appeared)
                MetricStrip(state: state)
                    .appear(1, appeared)
                AdaptersCard(state: state)
                    .appear(2, appeared)
                BenchmarkCard(state: state)
                    .appear(3, appeared)
                if state.activeDownloadsCount > 0 {
                    ActiveDownloadsCard(state: state, onOpenDownloads: onOpenDownloads)
                        .appear(4, appeared)
                } else {
                    QuickStartCard(state: state, onNewDownload: onNewDownload)
                        .appear(4, appeared)
                }
            }
            .padding(20)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(Motion.gentle) { appeared = true }
        }
    }
}

private struct HeroPanel: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 15) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 7) {
                        StatusPill(
                            text: state.isOn ? "Aggregating" : "Idle",
                            color: state.isOn ? Palette.mint : .secondary,
                            pulsing: state.isOn
                        )
                        StatusPill(text: "\(state.enabledLinkCount) link\(state.enabledLinkCount == 1 ? "" : "s")", color: Palette.accent)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(ByteFormat.rate(state.currentDownloadSpeedBytesPerSec))
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }

                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                PowerControl(state: state)
            }

            Sparkline(
                values: state.speedHistory,
                secondary: state.uploadHistory,
                tint: Palette.accent,
                secondaryTint: Palette.mint
            )
            .frame(height: 72)
            .overlay {
                if state.speedHistory.allSatisfy({ $0 <= 1 }) {
                    Text("The graph fills in as traffic flows")
                        .microLabel(Color.secondary.opacity(0.5))
                }
            }

            HStack(spacing: 14) {
                legend(color: Palette.accent, text: "Download")
                legend(color: Palette.mint, text: "Upload")
                Spacer()
                Text("last 60 seconds")
                    .microLabel(Color.secondary.opacity(0.7))
            }
        }
        .padding(18)
        .glassSurface(cornerRadius: 22, tint: Palette.accent, tintStrength: state.isOn ? 0.05 : 0)
    }

    private var subtitle: String {
        if case .activating = state.phase { return "Applying your system network settings…" }
        if state.isOn {
            let count = state.enabledLinkCount
            return count > 1
                ? "Traffic is spread across \(count) connections in real time."
                : "One connection active. Add a phone tether to stack bandwidth."
        }
        return "Turn aggregation on to combine every available connection."
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(color).frame(width: 12, height: 2.5)
            Text(text).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private struct PowerControl: View {
    @Bindable var state: AppState
    @State private var spin = false

    var body: some View {
        Button {
            Task { await state.setOn(!state.isOn) }
        } label: {
            ZStack {
                Circle().fill(Color(red: 0.09, green: 0.11, blue: 0.18))

                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: state.isOn
                                ? [Palette.accent.opacity(0.95), Palette.mint.opacity(0.55)]
                                : [Color.white.opacity(0.20), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )

                if state.isOn {
                    Circle()
                        .trim(from: 0, to: 0.16)
                        .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 6).repeatForever(autoreverses: false), value: spin)
                        .padding(7)
                }

                if state.phase == .activating {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.isOn ? "pause.fill" : "power")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(state.isOn ? Palette.accent : Color.primary.opacity(0.82))
                }
            }
            .frame(width: 84, height: 84)
            .shadow(color: state.isOn ? Palette.accent.opacity(0.34) : .clear, radius: 8, y: 3)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(state.phase == .activating)
        .help(state.isOn ? "Pause aggregation" : "Start aggregation")
        .onAppear { spin = true }
    }
}

private struct MetricStrip: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            MetricBlock(
                label: "Download",
                value: ByteFormat.rate(state.currentDownloadSpeedBytesPerSec),
                caption: "live",
                icon: "arrow.down",
                tint: Palette.accent
            )
            divider
            MetricBlock(
                label: "Upload",
                value: ByteFormat.rate(state.currentUploadSpeedBytesPerSec),
                caption: "live",
                icon: "arrow.up",
                tint: Palette.mint
            )
            divider
            MetricBlock(
                label: "Sockets",
                value: "\(state.activeConnectionsCount)",
                caption: "open flows",
                icon: "point.3.filled.connected.trianglepath",
                tint: Palette.violet
            )
            divider
            MetricBlock(
                label: "Today",
                value: ByteFormat.size(Int64(state.totalBytesRoutedToday)),
                caption: "routed",
                icon: "calendar",
                tint: Palette.cyan
            )
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .glassSurface(cornerRadius: 18, elevated: false)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(width: 1, height: 34)
            .padding(.horizontal, 14)
    }
}

// MARK: - Adapters

private struct AdaptersCard: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(
                title: "Connections",
                subtitle: "Live throughput, weight and health per adapter",
                icon: "network"
            ) {
                if state.enabledLinkCount > 1 {
                    StatusPill(text: "\(state.enabledLinkCount) stacked", color: Palette.mint)
                } else {
                    StatusPill(text: "Single link", color: Palette.amber)
                }
            }

            if state.linkRows.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No connections found").font(.system(size: 12.5, weight: .semibold))
                        Text("Join Wi-Fi, plug in Ethernet, or enable USB tethering on your phone.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03)))
            } else {
                VStack(spacing: 7) {
                    ForEach(state.linkRows) { link in
                        AdapterRow(state: state, link: link)
                    }
                }
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }
}

private struct AdapterRow: View {
    @Bindable var state: AppState
    var link: LinkRow

    var body: some View {
        let tint = Palette.forKind(link.kind)
        let totalSpeed = max(1, state.linkRows.reduce(0.0) { $0 + $1.downBytesPerSecond })
        let share = link.downBytesPerSecond / totalSpeed

        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(link.enabled ? 0.16 : 0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: link.kind.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(link.enabled ? tint : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(link.displayName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(link.subtitle)
                        .microLabel(Color.secondary.opacity(0.8))
                    StatusPill(text: link.healthLabel, color: healthColor)
                }

                HStack(spacing: 8) {
                    MeterBar(fraction: share, tint: tint, height: 3.5)
                        .frame(width: 108)
                    Text(ByteFormat.rate(link.downBytesPerSecond))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(link.measuredMbps > 0 ? ByteFormat.mbps(link.measuredMbps) : ByteFormat.mbps(link.weightMbps))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\(link.flows) flow\(link.flows == 1 ? "" : "s")")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .frame(width: 76, alignment: .trailing)

            Menu {
                Button("Automatic (measured)") { state.setWeight(link.id, mbps: nil) }
                Divider()
                Button("Priority · 100 Mbps") { state.setWeight(link.id, mbps: 100) }
                Button("Balanced · 50 Mbps") { state.setWeight(link.id, mbps: 50) }
                Button("Data saver · 10 Mbps") { state.setWeight(link.id, mbps: 10) }
            } label: {
                Text(state.manualWeights[link.name] != nil ? "\(Int(state.manualWeights[link.name] ?? 0))M" : "Auto")
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.07)))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Scheduling weight for this adapter")

            Toggle("", isOn: Binding(
                get: { link.enabled },
                set: { state.setLink(link.id, enabled: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.028)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(link.enabled ? tint.opacity(0.18) : Color.white.opacity(0.05), lineWidth: 0.7)
        )
        .opacity(link.enabled ? 1 : 0.6)
    }

    private var healthColor: Color {
        if !link.enabled { return .secondary }
        switch link.tier {
        case .up: return link.isLive ? Palette.mint : Palette.accent
        case .degraded: return Palette.amber
        case .down: return Palette.rose
        }
    }
}

// MARK: - Benchmark

private struct BenchmarkCard: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            CardHeader(
                title: "Speed check",
                subtitle: "Compares your best single link with the stacked total",
                icon: "speedometer"
            ) {
                if case .completed(let result) = state.benchmarkPhase {
                    StatusPill(
                        text: result.isAccelerated ? "+\(Int(result.speedGainPercent))%" : "measured",
                        color: result.isAccelerated ? Palette.mint : .secondary
                    )
                }
            }

            switch state.benchmarkPhase {
            case .idle:
                HStack(spacing: 12) {
                    Text("Downloads about 8 MB per adapter. Best on Wi-Fi — it uses mobile data on a tethered phone.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Run test") {
                        Task { await state.runBenchmark() }
                    }
                    .buttonStyle(GlassButtonStyle(tint: Palette.accent))
                }

            case .running(let stage, let progress, let speed):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(stage).font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        if speed > 0 {
                            Text(ByteFormat.rate(speed))
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    ProgressView(value: max(0.02, progress))
                        .progressViewStyle(.linear)
                        .tint(Palette.accent)
                }

            case .completed(let result):
                VStack(alignment: .leading, spacing: 9) {
                    bar(label: "Best single link", value: result.bestSingleSpeed, peak: peak(result), tint: Palette.cyan, emphasized: false)
                    bar(label: "Stacked total", value: result.combinedSpeed, peak: peak(result), tint: Palette.mint, emphasized: true)

                    HStack {
                        Text(result.isAccelerated
                             ? "Stacking added \(Int(result.speedGainPercent))% over your fastest single connection."
                             : "Links are balanced. Extra gain depends on what each server allows per connection.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Test again") {
                            state.resetBenchmark()
                            Task { await state.runBenchmark() }
                        }
                        .buttonStyle(GlassButtonStyle(tint: Palette.accent))
                    }
                }

            case .failed(let message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.amber)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Dismiss") { state.resetBenchmark() }
                        .buttonStyle(GlassButtonStyle())
                }
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }

    private func peak(_ result: BenchmarkResult) -> Double {
        max(1, result.combinedSpeed, result.bestSingleSpeed)
    }

    private func bar(label: String, value: Double, peak: Double, tint: Color, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 10.5, weight: emphasized ? .semibold : .regular))
                    .foregroundStyle(emphasized ? Color.primary : Color.secondary)
                Spacer()
                Text(value > 0 ? ByteFormat.rate(value) : "not reached")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(value > 0 ? tint : Color.secondary)
            }
            MeterBar(fraction: value / peak, tint: tint, height: emphasized ? 6 : 4)
        }
    }
}

// MARK: - Overview bottom cards

private struct ActiveDownloadsCard: View {
    @Bindable var state: AppState
    var onOpenDownloads: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            CardHeader(title: "In progress", subtitle: nil, icon: "arrow.down.circle") {
                Button("See all", action: onOpenDownloads)
                    .buttonStyle(GlassButtonStyle())
            }

            ForEach(state.downloads.filter { $0.status != .completed }.prefix(3)) { item in
                DownloadCard(state: state, item: item)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }
}

private struct QuickStartCard: View {
    @Bindable var state: AppState
    var onNewDownload: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing downloading yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Paste a link, drop one anywhere in this window, or hand a download over from your browser.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                onNewDownload()
            } label: {
                Label("New Download", systemImage: "plus")
            }
            .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
        }
        .padding(16)
        .glassSurface(cornerRadius: 18, elevated: false)
    }
}
