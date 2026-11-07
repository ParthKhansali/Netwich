import AppKit
import MergeKit
import SwiftUI

// MARK: - Permission row (shared by onboarding and settings)

struct PermissionRow: View {
    var item: PermissionCenter.Item
    var action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .semibold))
                Text(item.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            if let title = item.actionTitle {
                Button(title, action: action)
                    .buttonStyle(GlassButtonStyle(tint: item.status == .needsAction ? Palette.amber : Palette.accent))
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(color.opacity(item.status == .needsAction ? 0.28 : 0.10), lineWidth: 0.7)
        )
    }

    private var icon: String {
        switch item.status {
        case .ready: return "checkmark"
        case .needsAction: return "exclamationmark"
        case .optional: return "circle.dashed"
        case .unknown: return "questionmark"
        }
    }

    private var color: Color {
        switch item.status {
        case .ready: return Palette.mint
        case .needsAction: return Palette.amber
        case .optional: return Palette.accent
        case .unknown: return .secondary
        }
    }
}

// MARK: - Browser extension page

struct ExtensionPage: View {
    @Bindable var state: AppState
    @State private var copied = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                bridgeCard

                HStack(alignment: .top, spacing: 14) {
                    browserCard(
                        title: "Chrome, Brave, Edge, Arc",
                        icon: "globe",
                        tint: Palette.accent,
                        steps: [
                            "Open chrome://extensions (brave://extensions in Brave).",
                            "Turn on Developer mode, top right.",
                            "Click Load unpacked.",
                            "Select the folder Netwich reveals."
                        ],
                        folder: "chromium"
                    )

                    browserCard(
                        title: "Firefox",
                        icon: "flame",
                        tint: Palette.amber,
                        steps: [
                            "Open about:debugging#/runtime/this-firefox.",
                            "Click Load Temporary Add-on…",
                            "Pick manifest.json inside the Firefox folder.",
                            "Firefox reloads it each launch — install the packed ZIP for a permanent copy."
                        ],
                        folder: "firefox"
                    )
                }

                notesCard
            }
            .padding(20)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity)
        }
    }

    private var bridgeCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill((state.browserBridgePort != nil ? Palette.mint : Palette.rose).opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.browserBridgePort != nil ? Palette.mint : Palette.rose)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.browserBridgePort != nil ? "Extension bridge is listening" : "Extension bridge is offline")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(state.browserBridgePort.map { "Only extension origins may talk to 127.0.0.1:\($0). Web pages are refused." }
                     ?? "Restart Netwich to bring the local bridge back up.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                state.setup.revealExtensions()
            } label: {
                Label("Reveal extension", systemImage: "folder")
            }
            .buttonStyle(GlassButtonStyle())

            if let port = state.browserBridgePort, let url = URL(string: "http://127.0.0.1:\(port)/ping") {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Test", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.accent))
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 18)
    }

    private func browserCard(title: String, icon: String, tint: Color, steps: [String], folder: String) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(tint)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(tint.opacity(0.14)))
                        Text(step)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 7) {
                Button {
                    state.setup.revealExtensions()
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
                .buttonStyle(GlassButtonStyle())

                Button {
                    copyPath(folder)
                } label: {
                    Label(copied ? "Copied" : "Copy path", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 18)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader(title: "Good to know", icon: "info.circle")
            Text("Unpacked extensions are the unsigned development format every browser allows but does not persist for store installs. Netwich ships both a loadable folder and a ZIP per browser so you can keep the browser's own copy. Extensions only ever talk to this Mac on a loopback port, and requests that claim to come from a website are rejected with 403.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassSurface(cornerRadius: 18, elevated: false)
    }

    private func copyPath(_ folder: String) {
        let base = Bundle.main.resourceURL?.appendingPathComponent("extensions")
            ?? Bundle.main.resourceURL?.appendingPathComponent("extension")
        let path = base?.appendingPathComponent(folder).path ?? "extension/\(folder)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
        withAnimation(Motion.snappy) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(Motion.fade) { copied = false }
        }
    }
}

// MARK: - Tethering page

struct TetheringPage: View {
    @Bindable var state: AppState

    private let steps: [(String, String, String)] = [
        ("cable.connector", "Connect the phone", "Use a data-capable USB-C or Lightning cable. Charge-only cables will not appear as a network adapter."),
        ("iphone.gen3", "Turn on USB tethering", "Android: Settings → Network & internet → Hotspot & tethering → USB tethering. iPhone: Personal Hotspot and trust the computer."),
        ("checkmark.shield", "Approve on the Mac", "macOS may ask you to trust the device. Accept once; the adapter appears as en5, en6 or feth0."),
        ("square.stack.3d.up.fill", "Switch aggregation on", "Netwich picks the new link up automatically and starts sharing flows between both connections.")
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(
                        title: "Add a second connection",
                        subtitle: "A tethered phone is the easiest way to double your bandwidth",
                        icon: "cable.connector"
                    ) {
                        StatusPill(
                            text: state.enabledLinkCount > 1 ? "\(state.enabledLinkCount) links ready" : "1 link",
                            color: state.enabledLinkCount > 1 ? Palette.mint : Palette.amber
                        )
                    }

                    VStack(spacing: 7) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 11) {
                                ZStack {
                                    Circle().fill(Palette.accent.opacity(0.13)).frame(width: 26, height: 26)
                                    Image(systemName: step.0)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Palette.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(step.1).font(.system(size: 12, weight: .semibold))
                                    Text(step.2)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
                        }
                    }
                }
                .padding(16)
                .glassSurface(cornerRadius: 18)

                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(title: "Detected adapters", icon: "network")
                    if state.linkRows.isEmpty {
                        Text("Nothing detected right now.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(state.linkRows) { link in
                            HStack(spacing: 9) {
                                Circle()
                                    .fill(Palette.forKind(link.kind))
                                    .frame(width: 6, height: 6)
                                Text(link.displayName).font(.system(size: 11, weight: .medium))
                                Text(link.subtitle).microLabel(Color.secondary.opacity(0.8))
                                Spacer()
                                Text(link.healthLabel)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
                .padding(16)
                .glassSurface(cornerRadius: 18, elevated: false)

                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.cyan)
                    Text("Older Android devices using RNDIS need the open-source HoRNDIS driver. Modern phones use CDC-NCM and work with no driver at all.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Driver notes") {
                        if let url = URL(string: "https://github.com/jwise/HoRNDIS") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                .padding(14)
                .glassSurface(cornerRadius: 16, elevated: false)
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var state: AppState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 14) {
                section(title: "General", icon: "gearshape") {
                    row(title: "Start at login", subtitle: "Restore your last state after a restart") {
                        Toggle("", isOn: Binding(
                            get: { state.launchAtLogin },
                            set: { state.setLaunchAtLogin($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Palette.accent)
                    }
                }

                section(title: "Downloads", icon: "arrow.down.circle") {
                    row(title: "Save to", subtitle: state.defaultDestinationFolder.path) {
                        Button("Choose…") { state.chooseDestinationFolder() }
                            .buttonStyle(GlassButtonStyle())
                    }
                    divider
                    row(title: "Parallel streams", subtitle: "Connections per download, spread over your links") {
                        Stepper(value: $state.defaultConcurrency, in: 2...32, step: 2) {
                            Text("\(state.defaultConcurrency)")
                                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                                .frame(width: 22, alignment: .trailing)
                        }
                        .fixedSize()
                    }
                }

                section(title: "Network", icon: "network") {
                    row(title: "Local SOCKS proxy", subtitle: "127.0.0.1:\(state.localProxyPort)") {
                        StatusPill(text: state.proxyError == nil ? "ready" : "error", color: state.proxyError == nil ? Palette.mint : Palette.rose)
                    }
                    divider
                    row(title: "Extension bridge", subtitle: state.browserBridgePort.map { "127.0.0.1:\($0)" } ?? "not running") {
                        StatusPill(text: state.browserBridgePort != nil ? "listening" : "offline", color: state.browserBridgePort != nil ? Palette.mint : Palette.secondaryColor)
                    }
                    if let error = state.proxyError {
                        divider
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.amber)
                            Text(error)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                section(title: "Setup checks", icon: "checkmark.shield") {
                    if state.setup.items.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Scanning…").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    } else {
                        ForEach(state.setup.items) { item in
                            PermissionRow(item: item) {
                                state.setup.performAction(for: item)
                            }
                        }
                    }
                    divider
                    HStack {
                        Text("Netwich needs no Accessibility, Screen Recording, Full Disk Access or kernel extension.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Re-scan") {
                            Task { await state.setup.refresh() }
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }

                section(title: "About", icon: "info.circle") {
                    row(title: "Netwich", subtitle: "Stack your connections · MIT licensed") {
                        Text(version).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    divider
                    HStack {
                        Text("Designed and built by Parth Khansali")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("GitHub") {
                            if let url = URL(string: "https://github.com/ParthKhansali") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
    }

    private var version: String {
        let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "1"
        return "\(short) (\(build))"
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private func section<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text(title).font(.system(size: 12.5, weight: .semibold))
            }
            VStack(spacing: 8) {
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 18)
    }

    private func row<Trailing: View>(title: String, subtitle: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @Bindable var state: AppState
    var onFinish: () -> Void

    @State private var step = 0
    private let lastStep = 4

    var body: some View {
        ZStack {
            AuroraBackdrop(isActive: true)

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(26)
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 18)),
                        removal: .opacity.combined(with: .offset(x: -18))
                    ))

                footer
            }
            .glassSurface(cornerRadius: 24)
            .padding(18)
            .frame(width: 780, height: 600)
        }
        .task { await state.setup.refresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: howItWorks
        case 2: permissions
        case 3: extensionStep
        default: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Palette.accent.opacity(0.30), Palette.violet.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Palette.accent.opacity(0.5), radius: 26, y: 8)

            Text("Netwich")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("Stack your connections")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 9) {
                feature("square.stack.3d.up.fill", "Wi-Fi and a tethered phone become one faster link.")
                feature("arrow.down.circle.fill", "Downloads split into chunks across every adapter.")
                feature("lock.shield.fill", "Nothing leaves this Mac. No account, no relay, no VPN.")
            }
            .frame(width: 404, alignment: .leading)
            .padding(.top, 6)

            Spacer()
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How it works")
                .font(.system(size: 20, weight: .semibold))
            Text("Netwich runs a small local scheduler on your Mac. When aggregation is on, your outbound connections are balanced across the adapters you enable — one download can use both links at once.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 9) {
                explainer("1", "Turn aggregation on", "macOS asks for your administrator password once, because the system proxy belongs to the whole Mac.")
                explainer("2", "Connect a second link", "Wi-Fi plus a USB-tethered phone is the classic pair. Ethernet works too.")
                explainer("3", "Download anything", "Files are fetched in parallel range requests, each chunk scheduled onto a link.")
                explainer("4", "Turn it off anytime", "Your original proxy settings are stored first and restored exactly.")
            }

            Spacer()
        }
    }

    private func explainer(_ index: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(index)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.accent)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.028)))
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Set up permissions")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Each row opens the exact place in System Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await state.setup.refresh() }
                } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(GlassButtonStyle())
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(state.setup.items) { item in
                        PermissionRow(item: item) {
                            state.setup.performAction(for: item)
                        }
                    }
                }
            }

            Text("Netwich never asks for Accessibility, Screen Recording or Full Disk Access. Administrator access is used only to set and restore your system proxy.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.85))
        }
    }

    private var extensionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add the browser extension")
                .font(.system(size: 20, weight: .semibold))
            Text("Optional, but it is how a download link in your browser becomes a multi-connection transfer in Netwich.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    state.setup.revealExtensions()
                } label: {
                    Label("Reveal extension folder", systemImage: "folder")
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))

                Text("Chrome, Brave, Edge and Arc load the chromium folder. Firefox loads the firefox manifest.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                explainer("1", "Open your browser's extensions page", "chrome://extensions or about:debugging for Firefox.")
                explainer("2", "Turn on Developer mode", "Required for loading an unpacked extension — that is a browser rule, not a Netwich one.")
                explainer("3", "Load unpacked", "Choose the folder Netwich just revealed.")
            }

            Spacer()
        }
    }

    private var ready: some View {
        VStack(spacing: 14) {
            Spacer()
            ZStack {
                Circle().fill(Palette.mint.opacity(0.18)).frame(width: 70, height: 70)
                Image(systemName: "checkmark")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Palette.mint)
            }
            Text("You're set")
                .font(.system(size: 22, weight: .semibold))
            Text("Turn on aggregation in the sidebar whenever you want more bandwidth. Netwich remembers your adapters and restores your proxy settings when you quit.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Skip") { onFinish() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .opacity(step == lastStep ? 0 : 1)

            Spacer()

            HStack(spacing: 5) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(index == step ? Palette.accent : Color.white.opacity(0.16))
                        .frame(width: index == step ? 16 : 5, height: 5)
                        .animation(Motion.morph, value: step)
                }
            }

            Spacer()

            if step > 0 {
                Button("Back") {
                    withAnimation(Motion.morph) { step -= 1 }
                }
                .buttonStyle(GlassButtonStyle())
            }

            if step < lastStep {
                Button("Continue") {
                    withAnimation(Motion.morph) { step += 1 }
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.accent, isProminent: true))
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Open Netwich") {
                    onFinish()
                }
                .buttonStyle(GlassButtonStyle(tint: Palette.mint, isProminent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.accent)
                Text("Netwich")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                StatusPill(
                    text: state.isOn ? "on" : "off",
                    color: state.isOn ? Palette.mint : .secondary,
                    pulsing: state.isOn
                )
            }

            VStack(spacing: 8) {
                HStack(alignment: .lastTextBaseline) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(ByteFormat.rate(state.currentDownloadSpeedBytesPerSec))
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    Text("\(state.enabledLinkCount) links")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Sparkline(values: state.speedHistory, secondary: state.uploadHistory, tint: Palette.accent, secondaryTint: Palette.mint, lineWidth: 1.4)
                    .frame(height: 36)

                VStack(spacing: 4) {
                    ForEach(state.linkRows.prefix(3)) { link in
                        HStack(spacing: 6) {
                            Image(systemName: link.kind.symbolName)
                                .font(.system(size: 9))
                                .foregroundStyle(link.enabled ? Palette.forKind(link.kind) : Color.secondary)
                                .frame(width: 12)
                            Text(link.displayName)
                                .font(.system(size: 10, weight: .medium))
                            Spacer()
                            Text(link.enabled ? ByteFormat.rate(link.downBytesPerSecond) : "off")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(0.07), lineWidth: 0.7))

            Button {
                Task { await state.setOn(!state.isOn) }
            } label: {
                Label(
                    state.isOn ? "Pause aggregation" : "Start aggregation",
                    systemImage: state.isOn ? "pause.fill" : "bolt.horizontal.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassButtonStyle(tint: state.isOn ? Palette.amber : Palette.accent, isProminent: true))
            .disabled(state.phase == .activating)

            HStack {
                Button {
                    state.activateWindow()
                } label: {
                    Label("Dashboard", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(Palette.accent)

                Spacer()

                Button {
                    state.cleanupOnQuit()
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 292)
        .background(.ultraThinMaterial)
        .background(AutoDismissWindowAccessor())
    }
}

// MARK: - Menu bar window behaviour

struct AutoDismissWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> AutoDismissNSView { AutoDismissNSView() }
    func updateNSView(_ nsView: AutoDismissNSView, context: Context) {}
}

final class AutoDismissNSView: NSView {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var observer: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cleanup()
        guard let window else { return }
        window.isMovable = false

        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak window] _ in
            window?.orderOut(nil)
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] _ in
            guard let window else { return }
            if !window.frame.contains(NSEvent.mouseLocation) {
                window.orderOut(nil)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak window] event in
            guard let window else { return event }
            if !window.frame.contains(NSEvent.mouseLocation) {
                window.orderOut(nil)
            }
            return event
        }
    }

    private func cleanup() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        globalMonitor = nil
        localMonitor = nil
        observer = nil
    }

    deinit { cleanup() }
}

// MARK: - Colour helper

private extension Palette {
    static var secondaryColor: Color { Color.secondary }
}
