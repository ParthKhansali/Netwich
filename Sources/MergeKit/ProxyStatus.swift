import Foundation

/// Files shared between the app and the system extension.
///
/// A shared container plus two JSON files replaces any IPC framework: the extension
/// writes `status.json` twice a second, the app writes `control.json` when the user
/// changes something. Both are trivially inspectable with `cat` when something is
/// wrong, and a stale timestamp is unambiguous evidence that a process died.
public enum AppGroup {
    public static let identifier = "group.dev.parth.merge"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    public static var statusURL: URL? {
        containerURL?.appendingPathComponent("status.json")
    }

    public static var controlURL: URL? {
        containerURL?.appendingPathComponent("control.json")
    }
}

public struct ProxyStatus: Codable, Sendable, Equatable {
    public var updated: Date
    public var active: Bool
    public var links: [LinkSnapshot]
    public var activeFlows: Int
    public var declinedFlows: UInt64
    public var note: String?

    public init(
        updated: Date = Date(),
        active: Bool,
        links: [LinkSnapshot] = [],
        activeFlows: Int = 0,
        declinedFlows: UInt64 = 0,
        note: String? = nil
    ) {
        self.updated = updated
        self.active = active
        self.links = links
        self.activeFlows = activeFlows
        self.declinedFlows = declinedFlows
        self.note = note
    }

    /// A status older than this means the extension is gone or wedged.
    public var isStale: Bool {
        Date().timeIntervalSince(updated) > 3
    }
}

public struct ProxyControl: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var disabledLinks: [String]
    public var manualWeightsMbps: [String: Double]
    public var updated: Date

    public init(
        enabled: Bool = true,
        disabledLinks: [String] = [],
        manualWeightsMbps: [String: Double] = [:],
        updated: Date = Date()
    ) {
        self.enabled = enabled
        self.disabledLinks = disabledLinks
        self.manualWeightsMbps = manualWeightsMbps
        self.updated = updated
    }
}

public enum JSONFile {
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
}
