import Foundation
import MergeKit
import Network
import NetworkExtension

/// The aggregation engine.
///
/// The system terminates every matching TCP flow and hands it here as a byte stream.
/// This provider decides which link carries it, opens its own connection on that link
/// and copies bytes. There is no TUN device, no routing table change, no root, and no
/// TCP/IP stack: Network.framework does all of that.
///
/// Note: connections created *inside* a provider are never re-intercepted by it, so a
/// relay cannot loop back into this code.
final class ProxyProvider: NETransparentProxyProvider {
    private let scheduler = Scheduler()
    private let inventory = LinkInventory()
    private let state = ProviderState()
    private let queue = DispatchQueue(label: "dev.parth.merge.provider")
    private var ticker: DispatchSourceTimer?

    // MARK: - Lifecycle

    override func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        inventory.onChange = { [weak self] candidates in
            self?.scheduler.setCandidates(candidates)
        }
        inventory.start()
        scheduler.setCandidates(inventory.current)
        applyControl()

        let settings = NETransparentProxyNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.includedNetworkRules = Self.includedRules
        settings.excludedNetworkRules = Self.excludedRules

        setTunnelNetworkSettings(settings) { [weak self] error in
            guard error == nil else {
                completionHandler(error)
                return
            }
            self?.startTicker()
            completionHandler(nil)
        }
    }

    override func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        ticker?.cancel()
        ticker = nil
        inventory.stop()
        state.writeStatus(active: false, scheduler: scheduler, note: "stopped")
        completionHandler()
    }

    // MARK: - Flows

    override func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        // v1 carries TCP only. Declining a flow lets macOS route it directly, which is
        // both the UDP story and the fail-open path when no link is usable.
        guard let tcp = flow as? NEAppProxyTCPFlow else {
            state.noteDecline()
            return false
        }
        guard let endpoint = Self.endpoint(of: tcp) else {
            state.noteDecline()
            return false
        }

        let family = AddressFamily.infer(host: endpoint.host)
        guard let link = scheduler.acquire(family), let interface = inventory.interface(link) else {
            state.noteDecline()
            return false
        }

        let relay = FlowRelay(
            flow: tcp,
            host: endpoint.host,
            port: endpoint.port,
            link: link,
            family: family,
            interface: interface,
            scheduler: scheduler,
            state: state,
            queue: queue
        )
        state.retain(relay)
        relay.start()
        return true
    }

    // MARK: - Rules

    private static var includedRules: [NENetworkRule] {
        [
            NENetworkRule(
                remoteNetwork: nil,
                remotePrefix: 0,
                localNetwork: nil,
                localPrefix: 0,
                protocol: .TCP,
                direction: .outbound
            )
        ]
    }

    /// Traffic that must never be aggregated: local networks (printers, AirDrop, NAS,
    /// routers) and multicast. Loopback is excluded by the system already.
    private static var excludedRules: [NENetworkRule] {
        let networks: [(String, Int)] = [
            ("10.0.0.0", 8),
            ("172.16.0.0", 12),
            ("192.168.0.0", 16),
            ("169.254.0.0", 16),
            ("224.0.0.0", 4),
            ("255.255.255.255", 32),
        ]
        return networks.map { network, prefix in
            NENetworkRule(
                remoteNetwork: NWHostEndpoint(hostname: network, port: "0"),
                remotePrefix: prefix,
                localNetwork: nil,
                localPrefix: 0,
                protocol: .any,
                direction: .outbound
            )
        }
    }

    // MARK: - Housekeeping

    private func startTicker() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.applyControl()
            self.state.writeStatus(active: true, scheduler: self.scheduler)
        }
        timer.resume()
        ticker = timer
    }

    /// Picks up the user's per-link switches and weights written by the app.
    private func applyControl() {
        guard let url = AppGroup.controlURL,
              let control = JSONFile.read(ProxyControl.self, from: url)
        else { return }

        let disabled = Set(control.disabledLinks)
        var names = Set(inventory.current.map(\.id.name))
        names.formUnion(disabled)
        names.formUnion(control.manualWeightsMbps.keys)

        for name in names {
            let id = LinkID(name)
            scheduler.setEnabled(id, !disabled.contains(name))
            scheduler.setManualWeight(id, control.manualWeightsMbps[name])
        }
    }

    /// The flow's original destination.
    ///
    /// macOS 15 added `remoteFlowEndpoint` (a Network.framework endpoint). Before that,
    /// `remoteEndpoint` returns NetworkExtension's *own* `NWEndpoint` class, which is a
    /// different type with the same name — hence the two parsers.
    private static func endpoint(of flow: NEAppProxyTCPFlow) -> (host: String, port: UInt16)? {
        if #available(macOS 15.0, *) {
            return parseModern(flow.remoteFlowEndpoint)
        }
        if let legacy = flow.remoteEndpoint as? NWHostEndpoint,
           let port = UInt16(legacy.port),
           !legacy.hostname.isEmpty {
            return (legacy.hostname, port)
        }
        return nil
    }

    private static func parseModern(_ endpoint: Network.NWEndpoint) -> (host: String, port: UInt16)? {
        guard case let .hostPort(host, port) = endpoint else { return nil }
        var text: String
        switch host {
        case .ipv4(let address): text = "\(address)"
        case .ipv6(let address): text = "\(address)"
        case .name(let name, _): text = name
        @unknown default: return nil
        }
        if let scope = text.firstIndex(of: "%") {
            text = String(text[text.startIndex..<scope])
        }
        guard !text.isEmpty else { return nil }
        return (text, port.rawValue)
    }
}
