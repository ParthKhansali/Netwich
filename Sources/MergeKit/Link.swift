import Foundation

/// The address family a flow is being carried in.
public enum AddressFamily: String, Codable, Sendable, CaseIterable {
    case v4
    case v6

    /// Infers the family from a textual host. Literal IPv6 addresses contain ':'.
    public static func infer(host: String) -> AddressFamily {
        host.contains(":") ? .v6 : .v4
    }
}

/// A physical network interface, identified the way the system names it ("en0", "feth0").
public struct LinkID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var description: String { name }

    public static func < (a: LinkID, b: LinkID) -> Bool { a.name < b.name }
}

public enum LinkKind: String, Codable, Sendable {
    case wifi
    case wired
    case cellular
    case other

    public var symbolName: String {
        switch self {
        case .wifi: return "wifi"
        case .wired: return "cable.connector"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .other: return "network"
        }
    }
}

/// Health of a link, ordered so `> .down` means "usable".
public enum HealthTier: Int, Codable, Sendable, Comparable, CaseIterable {
    case down = 0
    case degraded = 1
    case up = 2

    public static func < (a: HealthTier, b: HealthTier) -> Bool { a.rawValue < b.rawValue }
}

/// What the inventory observed about a link this tick.
public struct LinkCandidate: Codable, Sendable, Equatable {
    public var id: LinkID
    public var kind: LinkKind
    public var supportsV4: Bool
    public var supportsV6: Bool
    public var isEnabled: Bool
    /// When set, overrides the measured throughput as the scheduling weight.
    public var manualWeightMbps: Double?

    public init(
        id: LinkID,
        kind: LinkKind,
        supportsV4: Bool,
        supportsV6: Bool,
        isEnabled: Bool = true,
        manualWeightMbps: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.supportsV4 = supportsV4
        self.supportsV6 = supportsV6
        self.isEnabled = isEnabled
        self.manualWeightMbps = manualWeightMbps
    }
}

/// A read-only view of a link for the UI and the status file.
public struct LinkSnapshot: Codable, Sendable, Equatable, Identifiable {
    public var id: LinkID
    public var kind: LinkKind
    public var tier: HealthTier
    public var busyV4: Int
    public var busyV6: Int
    public var measuredMbps: Double
    public var weightMbps: Double
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var flows: Int
    public var supportsV4: Bool
    public var supportsV6: Bool
    public var isEnabled: Bool

    public init(
        id: LinkID,
        kind: LinkKind,
        tier: HealthTier,
        busyV4: Int,
        busyV6: Int,
        measuredMbps: Double,
        weightMbps: Double,
        bytesIn: UInt64,
        bytesOut: UInt64,
        flows: Int,
        supportsV4: Bool,
        supportsV6: Bool,
        isEnabled: Bool
    ) {
        self.id = id
        self.kind = kind
        self.tier = tier
        self.busyV4 = busyV4
        self.busyV6 = busyV6
        self.measuredMbps = measuredMbps
        self.weightMbps = weightMbps
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.flows = flows
        self.supportsV4 = supportsV4
        self.supportsV6 = supportsV6
        self.isEnabled = isEnabled
    }
}
