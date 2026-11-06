import Foundation
import NetworkExtension
import ServiceManagement
import SystemExtensions

enum ProxyIdentity {
    static let bundleID = "dev.parth.merge.proxy"
    static let description = "Netwich"
}

enum ProxyError: LocalizedError {
    case activationIncomplete

    var errorDescription: String? {
        "Netwich's network extension needs approval. Open System Settings → Privacy & Security, allow Netwich, then switch it on again."
    }
}

/// Owns the system-extension lifecycle and the transparent proxy configuration.
@MainActor
final class ProxyController {
    private var manager: NETransparentProxyManager?
    private var activation: ActivationDelegate?

    /// Activates the system extension if macOS has not already done so.
    func activateIfNeeded() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let delegate = ActivationDelegate { result in
                continuation.resume(with: result)
            }
            activation = delegate

            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: ProxyIdentity.bundleID,
                queue: .main
            )
            request.delegate = delegate
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    func setEnabled(_ enabled: Bool) async throws {
        let manager = try await managerOrCreate()
        guard manager.isEnabled != enabled else { return }
        manager.isEnabled = enabled
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            manager.saveToPreferences { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Internals

    private func loadManager() async throws -> NETransparentProxyManager? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NETransparentProxyManager?, any Error>) in
            NETransparentProxyManager.loadAllFromPreferences { managers, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: managers?.first)
                }
            }
        }
    }

    private func managerOrCreate() async throws -> NETransparentProxyManager {
        if let manager { return manager }
        if let existing = try await loadManager() {
            manager = existing
            return existing
        }

        let fresh = NETransparentProxyManager()
        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = ProxyIdentity.bundleID
        proto.serverAddress = "merge.local"
        proto.providerConfiguration = ["mode": "transparent"]
        fresh.protocolConfiguration = proto
        fresh.localizedDescription = ProxyIdentity.description
        fresh.isEnabled = true
        manager = fresh
        return fresh
    }
}

final class ActivationDelegate: NSObject, OSSystemExtensionRequestDelegate {
    private let completion: (Result<Void, any Error>) -> Void
    private let lock = NSLock()
    private var finished = false

    init(completion: @escaping (Result<Void, any Error>) -> Void) {
        self.completion = completion
    }

    func request(
        _ request: OSSystemExtensionRequest,
        actionForReplacingExtension existing: OSSystemExtensionProperties,
        withExtension replacement: OSSystemExtensionProperties
    ) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // macOS is showing its own approval prompt; nothing to do but wait.
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            finish(.success(()))
        default:
            finish(.failure(ProxyError.activationIncomplete))
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: any Error) {
        finish(.failure(error))
    }

    private func finish(_ result: Result<Void, any Error>) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        completion(result)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
