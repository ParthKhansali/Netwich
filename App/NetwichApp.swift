import AppKit
import MergeKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Restores the user's original proxy configuration on the way out.
        appState?.cleanupOnQuit()
    }
}

@main
struct NetwichApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .onAppear { appDelegate.appState = state }
                .onOpenURL(perform: handleURL)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1140, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download…") {
                    NotificationCenter.default.post(name: .openNewDownloadSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Resume All Downloads") { state.resumeAllDownloads() }
                    .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Pause All Downloads") { state.pauseAllDownloads() }
                    .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                Button("Open Downloads Folder") { state.openDefaultDownloadFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }

            CommandMenu("Aggregation") {
                Button(state.isOn ? "Pause Aggregation" : "Start Aggregation") {
                    Task { await state.setOn(!state.isOn) }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(state.phase == .activating)
            }
        }

        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            HStack(spacing: 4) {
                NetwichBrand.menuBarIcon(active: state.isOn)
                if state.isOn, state.currentDownloadSpeedBytesPerSec > 50_000 {
                    Text(ByteFormat.rate(state.currentDownloadSpeedBytesPerSec))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            ZStack {
                AuroraBackdrop(isActive: state.isOn)
                SettingsView(state: state)
            }
            .frame(width: 660, height: 680)
        }
    }

    /// `netwich://download?url=…` and the legacy `merge://` scheme.
    private func handleURL(_ url: URL) {
        state.activateWindow()

        guard url.scheme == "netwich" || url.scheme == "merge" else { return }

        // netwich://tab/<overview|downloads|history|browser|tethering|settings>
        if url.host == "tab" {
            let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            NotificationCenter.default.post(name: .selectTab, object: name.isEmpty ? "overview" : name)
            return
        }

        // netwich://setup opens the onboarding/permissions setup sheet.
        if url.host == "setup" {
            NotificationCenter.default.post(name: .openSetupSheet, object: nil)
            return
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
           let target = URL(string: raw),
           let scheme = target.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            state.addDownload(url: target)
            return
        }

        // `netwich://open` just brings the window forward.
        if url.host == "open" || url.path.isEmpty {
            state.activateWindow()
        }
    }
}

extension Notification.Name {
    static let openNewDownloadSheet = Notification.Name("dev.parth.netwich.openNewDownload")
    static let openSetupSheet = Notification.Name("dev.parth.netwich.openSetup")
    static let selectTab = Notification.Name("dev.parth.netwich.selectTab")
}
