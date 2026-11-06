import AppKit
import SwiftUI
import MergeKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
        appState?.cleanupOnQuit()
        SystemProxyManager.emergencyDisableAll()
    }
}

@main
struct MergeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
                .frame(minWidth: 880, minHeight: 600)
                .onAppear {
                    appDelegate.appState = state
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1020, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Download...") {
                    NotificationCenter.default.post(name: .openNewDownloadSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Resume All Downloads") {
                    state.resumeAllDownloads()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])

                Button("Pause All Downloads") {
                    state.pauseAllDownloads()
                }
                .keyboardShortcut("p", modifiers: [.command, .option])

                Divider()

                Button("Open Downloads Folder") {
                    state.openDefaultDownloadFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("Clear Completed Downloads") {
                    state.clearCompletedDownloads()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra {
            MenuBarView(state: state)
        } label: {
            HStack(spacing: 4) {
                menuBarIconView
                if state.isOn && state.currentDownloadSpeedBytesPerSec > 50_000 {
                    Text(ByteFormat.rate(state.currentDownloadSpeedBytesPerSec))
                        .font(.caption2.monospacedDigit())
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
                .frame(width: 580, height: 500)
        }
    }

    @ViewBuilder
    private var menuBarIconView: some View {
        if let template = loadMenuBarIcon() {
            Image(nsImage: template)
        } else {
            Image(systemName: state.isOn ? "square.stack.3d.up.fill" : "network")
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        let candidate: NSImage? = {
            if let path = Bundle.main.path(forResource: "netwichTemplate", ofType: "png") {
                return NSImage(contentsOfFile: path)
            }
            if let named = NSImage(named: "netwichTemplate") ?? Bundle.main.image(forResource: "netwichTemplate") {
                return named
            }
            if let res = Bundle.main.resourcePath {
                return NSImage(contentsOfFile: res + "/netwichTemplate.png")
            }
            return nil
        }()

        guard let img = candidate else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }
}

extension Notification.Name {
    static let openNewDownloadSheet = Notification.Name("dev.parth.merge.openNewDownload")
}
