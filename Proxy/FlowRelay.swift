import Foundation
import MergeKit
import Network
import NetworkExtension

/// One proxied flow: a pumped byte copy between the app's flow and our own connection.
final class FlowRelay {
    private let flow: NEAppProxyTCPFlow
    private let connection: NWConnection
    private let link: LinkID
    private let family: AddressFamily
    private let scheduler: Scheduler
    private let state: ProviderState
    private let queue: DispatchQueue
    private let started = Date()

    private let lock = NSLock()
    private var finished = false
    private var bytesIn: UInt64 = 0
    private var bytesOut: UInt64 = 0

    init(
        flow: NEAppProxyTCPFlow,
        host: String,
        port: UInt16,
        link: LinkID,
        family: AddressFamily,
        interface: NWInterface,
        scheduler: Scheduler,
        state: ProviderState,
        queue: DispatchQueue
    ) {
        self.flow = flow
        self.link = link
        self.family = family
        self.scheduler = scheduler
        self.state = state
        self.queue = queue

        let parameters = NWParameters.tcp
        // The whole design rests on this one line: pin the egress to a physical link.
        parameters.requiredInterface = interface
        parameters.allowLocalEndpointReuse = true
        parameters.prohibitExpensivePaths = false

        self.connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any,
            using: parameters
        )
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.openFlow()
            case .failed(let error):
                self.finish(error)
            case .cancelled:
                self.finish(nil)
            default:
                // .waiting is transient (interface briefly unavailable): keep waiting.
                break
            }
        }
        connection.start(queue: queue)
    }

    private func openFlow() {
        flow.open(withLocalEndpoint: nil) { [weak self] error in
            guard let self else { return }
            if let error {
                self.finish(error)
                return
            }
            self.pumpOutbound()
            self.pumpInbound()
        }
    }

    /// App → server.
    private func pumpOutbound() {
        flow.readData { [weak self] data, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lock.lock()
                self.bytesOut &+= UInt64(data.count)
                self.lock.unlock()

                self.connection.send(content: data, completion: .contentProcessed { sendError in
                    if let sendError {
                        self.finish(sendError)
                    } else {
                        self.pumpOutbound()
                    }
                })
            } else {
                // EOF from the app: half-close towards the server, then finish.
                self.connection.send(
                    content: nil,
                    contentContext: .defaultMessage,
                    isComplete: true,
                    completion: .contentProcessed { _ in }
                )
                self.finish(error)
            }
        }
    }

    /// Server → app.
    private func pumpInbound() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.lock.lock()
                self.bytesIn &+= UInt64(data.count)
                self.lock.unlock()

                self.flow.write(data) { writeError in
                    if let writeError {
                        self.finish(writeError)
                    } else if isComplete {
                        self.finish(nil)
                    } else {
                        self.pumpInbound()
                    }
                }
            } else if isComplete {
                self.finish(nil)
            } else if let error {
                self.finish(error)
            } else {
                self.pumpInbound()
            }
        }
    }

    /// Idempotent teardown: closes both sides and returns the flow slot to the scheduler.
    private func finish(_ error: Error?) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        let inBytes = bytesIn
        let outBytes = bytesOut
        lock.unlock()

        flow.closeReadWithError(error)
        flow.closeWriteWithError(error)
        connection.cancel()

        scheduler.release(
            link,
            family: family,
            bytesIn: inBytes,
            bytesOut: outBytes,
            elapsed: Date().timeIntervalSince(started),
            succeeded: error == nil
        )
        state.release(self)
    }
}
