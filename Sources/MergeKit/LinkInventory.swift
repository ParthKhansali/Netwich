import Foundation
import Network

/// Watches the system for usable physical links.
///
/// Network.framework already knows which interfaces are up and preferred; this only
/// filters out the virtual ones and adds address-family information, which `NWPath`
/// does not expose per interface.
public final class LinkInventory: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.parth.merge.links")
    private let lock = NSLock()

    private var interfacesByID: [LinkID: NWInterface] = [:]
    private var candidates: [LinkCandidate] = []
    private var running = false

    /// Called on an arbitrary queue whenever the link set changes.
    public var onChange: (([LinkCandidate]) -> Void)?

    public init() {}

    public func start() {
        lock.lock()
        if running {
            lock.unlock()
            return
        }
        running = true
        lock.unlock()

        monitor.pathUpdateHandler = { [weak self] path in
            self?.apply(path)
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        lock.lock()
        running = false
        lock.unlock()
        monitor.cancel()
    }

    public var current: [LinkCandidate] {
        lock.lock()
        defer { lock.unlock() }
        return candidates
    }

    public func interface(_ id: LinkID) -> NWInterface? {
        lock.lock()
        defer { lock.unlock() }
        return interfacesByID[id]
    }

    private func apply(_ path: NWPath) {
        let addresses = InterfaceScanner.scan()
        var nextInterfaces: [LinkID: NWInterface] = [:]
        var nextCandidates: [LinkCandidate] = []
        var seenIDs: Set<LinkID> = []

        for interface in path.availableInterfaces {
            let name = interface.name
            guard interface.type != .loopback, !InterfaceScanner.isVirtual(name) else { continue }
            guard let entry = addresses[name], InterfaceScanner.hasRoutableAddress(entry) else { continue }

            let id = LinkID(name)
            guard !seenIDs.contains(id) else { continue }
            seenIDs.insert(id)

            nextInterfaces[id] = interface
            nextCandidates.append(
                LinkCandidate(
                    id: id,
                    kind: Self.kind(interface.type, name: name),
                    supportsV4: !entry.v4.isEmpty,
                    supportsV6: !entry.v6.isEmpty
                )
            )
        }
        nextCandidates.sort { $0.id < $1.id }

        lock.lock()
        interfacesByID = nextInterfaces
        candidates = nextCandidates
        lock.unlock()

        onChange?(nextCandidates)
    }

    public static func kind(_ type: NWInterface.InterfaceType, name: String = "") -> LinkKind {
        if name.hasPrefix("feth") {
            return .cellular
        }
        switch type {
        case .wifi: return .wifi
        case .wiredEthernet: return .wired
        case .cellular: return .cellular
        default: return .other
        }
    }
}
