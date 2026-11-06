import Foundation
import MergeKit

/// Per-provider bookkeeping: keeps relays alive and publishes the status file.
final class ProviderState: @unchecked Sendable {
    private let lock = NSLock()
    private var relays: [ObjectIdentifier: FlowRelay] = [:]
    private var declined: UInt64 = 0

    func retain(_ relay: FlowRelay) {
        lock.lock()
        relays[ObjectIdentifier(relay)] = relay
        lock.unlock()
    }

    func release(_ relay: FlowRelay) {
        lock.lock()
        relays[ObjectIdentifier(relay)] = nil
        lock.unlock()
    }

    func noteDecline() {
        lock.lock()
        declined &+= 1
        lock.unlock()
    }

    var activeFlows: Int {
        lock.lock()
        defer { lock.unlock() }
        return relays.count
    }

    var declinedFlows: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return declined
    }

    func writeStatus(active: Bool, scheduler: Scheduler, note: String? = nil) {
        guard let url = AppGroup.statusURL else { return }
        let status = ProxyStatus(
            active: active,
            links: scheduler.snapshot(),
            activeFlows: activeFlows,
            declinedFlows: declinedFlows,
            note: note
        )
        try? JSONFile.write(status, to: url)
    }
}
