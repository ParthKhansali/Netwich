import Foundation

/// Weighted least-flows scheduler.
///
/// This is the piece worth keeping from NetMerge: pick the link with the lowest
/// `(busyFlows + 1) / weight`, per address family, skipping unhealthy links. It is
/// synchronous and lock-guarded because it runs in the flow-accept path, where an
/// `await` would let flows pile up.
public final class Scheduler: @unchecked Sendable {
    public struct Config: Sendable {
        public var floorWeightMbps: Double = 25
        public var degradedDivisor: Double = 2
        public var failureCooldown: TimeInterval = 10
        public var failuresToDown: Int = 3
        public var ewmaAlpha: Double = 0.3
        /// 0 means unlimited.
        public var maxFlowsPerLink: Int = 0

        public init() {}
    }

    private struct Entry {
        var candidate: LinkCandidate
        var busyV4: Int = 0
        var busyV6: Int = 0
        var measuredMbps: Double = 0
        var tier: HealthTier = .up
        var failures: Int = 0
        var cooldownUntil: Date = .distantPast
        var bytesIn: UInt64 = 0
        var bytesOut: UInt64 = 0
        var flows: Int = 0

        func busy(_ family: AddressFamily) -> Int {
            family == .v4 ? busyV4 : busyV6
        }

        mutating func addBusy(_ family: AddressFamily, _ delta: Int) {
            if family == .v4 {
                busyV4 = max(0, busyV4 + delta)
            } else {
                busyV6 = max(0, busyV6 + delta)
            }
        }

        func supports(_ family: AddressFamily) -> Bool {
            family == .v4 ? candidate.supportsV4 : candidate.supportsV6
        }
    }

    public let config: Config

    private let lock = NSLock()
    private var entries: [LinkID: Entry] = [:]
    private let now: () -> Date

    public init(config: Config = Config(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    // MARK: - Configuration

    /// Replaces the link set, preserving counters and health for links that persist.
    public func setCandidates(_ candidates: [LinkCandidate]) {
        lock.lock()
        defer { lock.unlock() }
        var next: [LinkID: Entry] = [:]
        next.reserveCapacity(candidates.count)
        for candidate in candidates {
            if var existing = entries[candidate.id] {
                existing.candidate = candidate
                next[candidate.id] = existing
            } else {
                next[candidate.id] = Entry(candidate: candidate)
            }
        }
        entries = next
    }

    public func setEnabled(_ id: LinkID, _ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        entries[id]?.candidate.isEnabled = enabled
    }

    public func setManualWeight(_ id: LinkID, _ mbps: Double?) {
        lock.lock()
        defer { lock.unlock() }
        entries[id]?.candidate.manualWeightMbps = mbps
    }

    // MARK: - Scheduling

    /// Returns a link and marks one flow busy on it, or nil when nothing is usable.
    public func acquire(_ family: AddressFamily) -> LinkID? {
        acquire(family, avoiding: [])
    }

    public func acquire(_ family: AddressFamily, avoiding excluded: Set<LinkID>) -> LinkID? {
        lock.lock()
        defer { lock.unlock() }

        let time = now()

        // Retry links whose failure cooldown has expired.
        let revived = entries.compactMap { id, entry -> LinkID? in
            entry.tier == .down && time >= entry.cooldownUntil ? id : nil
        }
        for id in revived {
            entries[id]?.tier = .degraded
        }

        let keys = entries.keys.sorted()
        guard !keys.isEmpty else { return nil }

        // Start from a randomized offset so equal-score ties do not starve any adapter
        let startOffset = Int.random(in: 0..<keys.count)
        var bestID: LinkID?
        var bestScore = Double.infinity

        for i in 0..<keys.count {
            let id = keys[(startOffset + i) % keys.count]
            guard let entry = entries[id] else { continue }
            guard entry.candidate.isEnabled, !excluded.contains(id) else { continue }
            guard entry.tier > .down, time >= entry.cooldownUntil else { continue }
            guard entry.supports(family) else { continue }
            let busy = entry.busy(family)
            if config.maxFlowsPerLink > 0, busy >= config.maxFlowsPerLink { continue }
            let weight = weightLocked(entry)
            guard weight > 0 else { continue }
            let score = Double(busy + 1) / weight
            if score < bestScore {
                bestScore = score
                bestID = id
            }
        }

        guard let chosen = bestID else { return nil }
        entries[chosen]?.addBusy(family, 1)
        entries[chosen]?.flows += 1
        return chosen
    }

    /// Releases a flow and feeds its observed bytes back into the link weight.
    public func release(
        _ id: LinkID,
        family: AddressFamily,
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0,
        elapsed: TimeInterval = 0,
        succeeded: Bool = true
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[id] else { return }
        entry.addBusy(family, -1)
        entry.flows = max(0, entry.flows - 1)
        entry.bytesIn &+= bytesIn
        entry.bytesOut &+= bytesOut

        if elapsed > 0.01 {
            let mbps = Double(bytesIn &+ bytesOut) * 8 / elapsed / 1_000_000
            entry.measuredMbps = entry.measuredMbps == 0
                ? mbps
                : (config.ewmaAlpha * mbps + (1 - config.ewmaAlpha) * entry.measuredMbps)
        }

        if succeeded {
            entry.failures = 0
            entry.tier = .up
            entry.cooldownUntil = .distantPast
        } else {
            recordFailureLocked(&entry, at: now())
        }
        entries[id] = entry
    }

    /// Records a health probe outcome for a link.
    public func probeResult(_ id: LinkID, ok: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[id] else { return }
        if ok {
            entry.failures = 0
            entry.tier = .up
            entry.cooldownUntil = .distantPast
        } else {
            recordFailureLocked(&entry, at: now())
        }
        entries[id] = entry
    }

    // MARK: - Inspection

    public func snapshot() -> [LinkSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return entries.keys.sorted().compactMap { id in
            guard let entry = entries[id] else { return nil }
            return LinkSnapshot(
                id: id,
                kind: entry.candidate.kind,
                tier: entry.tier,
                busyV4: entry.busyV4,
                busyV6: entry.busyV6,
                measuredMbps: entry.measuredMbps,
                weightMbps: weightLocked(entry),
                bytesIn: entry.bytesIn,
                bytesOut: entry.bytesOut,
                flows: entry.flows,
                supportsV4: entry.candidate.supportsV4,
                supportsV6: entry.candidate.supportsV6,
                isEnabled: entry.candidate.isEnabled
            )
        }
    }

    public func activeFlowCount() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.values.reduce(0) { $0 + $1.flows }
    }

    public func tier(_ id: LinkID) -> HealthTier? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.tier
    }

    // MARK: - Internals

    private func weightLocked(_ entry: Entry) -> Double {
        guard entry.candidate.isEnabled, entry.tier > .down else { return 0 }
        let base = entry.candidate.manualWeightMbps ?? max(config.floorWeightMbps, entry.measuredMbps)
        let adjusted = entry.tier == .degraded ? base / config.degradedDivisor : base
        return max(0, adjusted)
    }

    private func recordFailureLocked(_ entry: inout Entry, at time: Date) {
        entry.failures += 1
        if entry.failures >= config.failuresToDown {
            entry.tier = .down
            entry.cooldownUntil = time.addingTimeInterval(config.failureCooldown)
        } else {
            entry.tier = .degraded
        }
    }
}
