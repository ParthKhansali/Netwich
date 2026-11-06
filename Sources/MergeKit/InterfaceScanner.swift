import Darwin
import Foundation

public struct InterfaceAddresses: Sendable, Equatable {
    public var v4: [String] = []
    public var v6: [String] = []
    public var isUp: Bool = false

    public init(v4: [String] = [], v6: [String] = [], isUp: Bool = false) {
        self.v4 = v4
        self.v6 = v6
        self.isUp = isUp
    }
}

public enum InterfaceScanner {
    /// Every interface that is up and carries a routable address, keyed by name.
    public static func scan() -> [String: InterfaceAddresses] {
        var result: [String: InterfaceAddresses] = [:]
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return result }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            defer { cursor = pointer.pointee.ifa_next }
            let ifa = pointer.pointee
            let name = String(cString: ifa.ifa_name)
            var entry = result[name] ?? InterfaceAddresses()
            if (ifa.ifa_flags & UInt32(IFF_UP)) != 0 {
                entry.isUp = true
            }

            guard let address = ifa.ifa_addr else {
                result[name] = entry
                continue
            }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else {
                result[name] = entry
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
                result[name] = entry
                continue
            }

            var text = String(cString: host)
            if family == AF_INET {
                entry.v4.append(text)
            } else {
                if let percent = text.firstIndex(of: "%") {
                    text = String(text[text.startIndex..<percent])
                }
                let lowered = text.lowercased()
                // Link-local and loopback IPv6 addresses never route a flow.
                if !lowered.hasPrefix("fe80") && lowered != "::1" {
                    entry.v6.append(text)
                }
            }
            result[name] = entry
        }
        return result
    }

    /// Interfaces that exist but can never be a physical egress link.
    /// Mirrors NetMerge's rule (`^(en|feth)\d+$`) expressed as a blocklist so
    /// TetherKit's `feth0` and future hardware still qualify.
    public static func isVirtual(_ name: String) -> Bool {
        let blocked = ["lo", "utun", "awdl", "llw", "bridge", "anpi", "gif", "stf", "ap", "p2p", "vmenet", "ipsec"]
        return blocked.contains { name.hasPrefix($0) }
    }

    public static func hasRoutableAddress(_ entry: InterfaceAddresses) -> Bool {
        entry.isUp && !(entry.v4.isEmpty && entry.v6.isEmpty)
    }
}
