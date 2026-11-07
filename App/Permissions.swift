import AppKit
import Foundation
import Observation

/// Every macOS surface Netwich needs, checked live and explained in plain language.
///
/// The point of this file is to remove the "why does nothing happen?" moment. Each item
/// knows three things: whether it is satisfied, what the user would see if it is not, and
/// the exact button that takes them to the right place — a System Settings pane, Finder,
/// or a one-time administrator prompt.
@MainActor
@Observable
public final class PermissionCenter {

    public enum Status: Equatable {
        case ready
        case needsAction
        case optional
        case unknown

        public var isSatisfied: Bool { self == .ready || self == .optional }
    }

    public enum Kind: String, Identifiable, CaseIterable {
        case installation
        case security
        case administrator
        case loginItem
        case browserExtension

        public var id: String { rawValue }
    }

    public struct Item: Identifiable, Equatable {
        public var kind: Kind
        public var title: String
        public var detail: String
        public var status: Status
        public var actionTitle: String?

        public var id: String { kind.rawValue }
    }

    public private(set) var items: [Item] = []
    public private(set) var hasFinishedFirstScan = false

    public init() {}

    public var requiredItems: [Item] {
        items.filter { $0.status != .optional }
    }

    public var blockingCount: Int {
        items.filter { $0.status == .needsAction }.count
    }

    public var isReady: Bool {
        blockingCount == 0
    }

    // MARK: - Scan

    public func refresh() async {
        let installed = Self.isInstalledInApplications()
        let quarantined = Self.hasQuarantineAttribute(Bundle.main.bundlePath)
        let admin = Self.isAdminUser()
        let loginStatus = LaunchAtLogin.isEnabled
        let loginNeedsApproval = LaunchAtLogin.requiresApproval
        let extensionBundled = Self.bundledExtensionsExist()

        var next: [Item] = []

        next.append(
            Item(
                kind: .installation,
                title: installed ? "Installed in Applications" : "Move Netwich to Applications",
                detail: installed
                    ? "Netwich is running from your Applications folder, so login items and updates behave correctly."
                    : "Netwich is running from \(Bundle.main.bundlePath). Drag it into Applications in the installer window, then launch it from there.",
                status: installed ? .ready : .needsAction,
                actionTitle: installed ? nil : "Reveal in Finder"
            )
        )

        next.append(
            Item(
                kind: .security,
                title: quarantined ? "Allow Netwich in Privacy & Security" : "Gatekeeper check passed",
                detail: quarantined
                    ? "macOS marked this download as quarantined. If opening Netwich was blocked, click Open Anyway in Privacy & Security → Security. That is macOS asking once, not Netwich."
                    : "No quarantine flag on the app bundle. Nothing is blocked.",
                status: quarantined ? .needsAction : .ready,
                actionTitle: quarantined ? "Open Privacy & Security" : nil
            )
        )

        next.append(
            Item(
                kind: .administrator,
                title: admin ? "Administrator access available" : "Administrator password needed",
                detail: admin
                    ? "Turning aggregation on or off changes your Mac's proxy settings, so macOS asks for your password the first time. Netwich never stores it."
                    : "This account is not an administrator. macOS will ask for an administrator's name and password once when you switch aggregation on.",
                status: concurrencySafeAdminStatus(admin: admin),
                actionTitle: "Open Network Settings"
            )
        )

        next.append(
            Item(
                kind: .loginItem,
                title: loginStatus ? "Starts at login" : (loginNeedsApproval ? "Approve the login item" : "Optionally start at login"),
                detail: loginStatus
                    ? "Netwich is registered as a login item and will restore your last state when you sign in."
                    : loginNeedsApproval
                        ? "macOS is waiting for you to allow the login item in System Settings → General → Login Items."
                        : "Optional. Enable it to bring your stack back automatically after a restart.",
                status: loginStatus ? .ready : (loginNeedsApproval ? .needsAction : .optional),
                actionTitle: loginNeedsApproval ? "Open Login Items" : nil
            )
        )

        next.append(
            Item(
                kind: .browserExtension,
                title: extensionBundled ? "Browser extension is bundled" : "Browser extension missing",
                detail: extensionBundled
                    ? "A signed-ready ZIP for Chrome and Firefox is inside the app. Turn on Developer mode in your browser's extensions page, then Load unpacked from the folder Netwich reveals."
                    : "The app bundle has no extension payload. Rebuild with Scripts/package.sh.",
                status: extensionBundled ? .ready : .needsAction,
                actionTitle: extensionBundled ? "Reveal Extension Folder" : nil
            )
        )

        items = next
        hasFinishedFirstScan = true
    }

    /// Admin is never "required" — macOS can prompt for any administrator's credentials.
    private func concurrencySafeAdminStatus(admin: Bool) -> Status {
        admin ? .ready : .optional
    }

    // MARK: - Actions

    public func performAction(for item: Item) {
        switch item.kind {
        case .installation:
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        case .security:
            SystemSettingsPane.privacy.open()
        case .administrator:
            SystemSettingsPane.network.open()
        case .loginItem:
            SystemSettingsPane.loginItems.open()
        case .browserExtension:
            revealExtensions()
        }
    }

    /// Opens the folder holding the ready-to-load extension bundles.
    public func revealExtensions() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("extensions/chrome"),
            Bundle.main.resourceURL?.appendingPathComponent("extension/chrome"),
            Bundle.main.resourceURL?.appendingPathComponent("extensions")
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            NSWorkspace.shared.activateFileViewerSelecting([candidate])
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: - Probes

    static func isInstalledInApplications() -> Bool {
        let path = Bundle.main.bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    /// `com.apple.quarantine` is set by browsers on downloaded bundles.
    static func hasQuarantineAttribute(_ path: String) -> Bool {
        let name = "com.apple.quarantine"
        return path.withCString { pathPtr in
            name.withCString { namePtr in
                getxattr(pathPtr, namePtr, nil, 0, 0, 0) >= 0
            }
        }
    }

    static func isAdminUser() -> Bool {
        let adminGID: Int32 = 80
        guard let username = NSUserName().cString(using: .utf8) else { return false }
        var groups = [Int32](repeating: 0, count: 64)
        var count = Int32(groups.count)
        let result = groups.withUnsafeMutableBufferPointer { buffer in
            getgrouplist(username, Int32(getgid()), buffer.baseAddress, &count)
        }
        guard result >= 0 else { return false }
        return groups.prefix(Int(count)).contains(adminGID)
    }

    static func bundledExtensionsExist() -> Bool {
        let roots = [
            Bundle.main.resourceURL?.appendingPathComponent("extensions"),
            Bundle.main.resourceURL?.appendingPathComponent("extension")
        ].compactMap { $0 }

        return roots.contains { root in
            FileManager.default.fileExists(atPath: root.path)
        }
    }
}

/// System Settings destinations, using the identifiers Apple's own Settings app exposes.
public enum SystemSettingsPane {
    case privacy
    case loginItems
    case network
    case extensions

    public var url: URL? {
        let identifier: String
        switch self {
        case .privacy: identifier = "com.apple.settings.PrivacySecurity.extension"
        case .loginItems: identifier = "com.apple.LoginItems-Settings.extension"
        case .network: identifier = "com.apple.Network-Settings.extension"
        case .extensions: identifier = "com.apple.ExtensionsPreferences"
        }
        return URL(string: "x-apple.systempreferences:\(identifier)")
    }

    public func open() {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }
}
