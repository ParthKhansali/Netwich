import Darwin
import Foundation
import Network

public enum LocalProxyError: Error, LocalizedError {
    case posix(Int32, String)
    case unsupportedVersion
    case unsupportedCommand
    case connectionFailed(String)
    case hostResolutionFailed

    public var errorDescription: String? {
        switch self {
        case .posix(let code, let msg): return "\(msg) (errno \(code))"
        case .unsupportedVersion: return "Only SOCKS5 is supported"
        case .unsupportedCommand: return "Command not supported"
        case .connectionFailed(let host): return "Connection to \(host) failed"
        case .hostResolutionFailed: return "Failed to resolve host"
        }
    }
}

/// High-performance local SOCKS5 proxy server that distributes outbound
/// TCP connections across multiple physical network interfaces.
///
/// Runs unprivileged in userspace on 127.0.0.1:1080 without requiring root,
/// kernel extensions, or paid Apple developer entitlements.
public final class LocalProxyServer: @unchecked Sendable {
    public struct Config: Sendable {
        public var port: UInt16 = 1080
        public var host: String = "127.0.0.1"
        public var bufferSize: Int = 32_768
        public var connectionTimeoutSeconds: Int = 10

        public init(port: UInt16 = 1080, host: String = "127.0.0.1") {
            self.port = port
            self.host = host
        }
    }

    public struct Metrics: Sendable {
        public var totalConnections: UInt64 = 0
        public var activeConnections: Int = 0
        public var totalBytesIn: UInt64 = 0
        public var totalBytesOut: UInt64 = 0
        public var lastError: String?

        public init() {}
    }

    private let config: Config
    private let scheduler: Scheduler
    private var serverSocket: Int32 = -1
    private var isRunning = false
    private let stateLock = NSLock()
    private var acceptThread: Thread?

    private var activeCount: Int = 0
    private var totalCount: UInt64 = 0
    private var bytesRx: UInt64 = 0
    private var bytesTx: UInt64 = 0
    private var lastErr: String?

    private var bytesRxByLink: [String: UInt64] = [:]
    private var bytesTxByLink: [String: UInt64] = [:]
    private var activeFlowsByLink: [String: Int] = [:]

    public init(config: Config = Config(), scheduler: Scheduler) {
        self.config = config
        self.scheduler = scheduler
    }

    public var isServerRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isRunning
    }

    public var metrics: Metrics {
        stateLock.lock()
        defer { stateLock.unlock() }
        var m = Metrics()
        m.totalConnections = totalCount
        m.activeConnections = activeCount
        m.totalBytesIn = bytesRx
        m.totalBytesOut = bytesTx
        m.lastError = lastErr
        return m
    }

    public func linkThroughput() -> [String: (rx: UInt64, tx: UInt64, flows: Int)] {
        stateLock.lock()
        defer { stateLock.unlock() }
        var result: [String: (rx: UInt64, tx: UInt64, flows: Int)] = [:]
        let keys = Set(bytesRxByLink.keys).union(activeFlowsByLink.keys).union(bytesTxByLink.keys)
        for key in keys {
            result[key] = (
                rx: bytesRxByLink[key] ?? 0,
                tx: bytesTxByLink[key] ?? 0,
                flows: activeFlowsByLink[key] ?? 0
            )
        }
        return result
    }

    public func start() throws {
        stateLock.lock()
        guard !isRunning else {
            stateLock.unlock()
            return
        }

        let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard sock >= 0 else {
            let err = errno
            stateLock.unlock()
            throw LocalProxyError.posix(err, "socket creation failed")
        }

        var opt: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        #if canImport(Darwin)
        setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))
        #endif

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = config.port.bigEndian
        addr.sin_addr.s_addr = inet_addr(config.host)

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindRes == 0 else {
            let err = errno
            close(sock)
            stateLock.unlock()
            throw LocalProxyError.posix(err, "bind to \(config.host):\(config.port) failed")
        }

        guard listen(sock, 512) == 0 else {
            let err = errno
            close(sock)
            stateLock.unlock()
            throw LocalProxyError.posix(err, "listen failed")
        }

        serverSocket = sock
        isRunning = true
        stateLock.unlock()

        let thread = Thread { [weak self] in
            self?.acceptLoop()
        }
        thread.name = "dev.parth.merge.proxy.accept"
        thread.start()
        acceptThread = thread
    }

    public func stop() {
        stateLock.lock()
        guard isRunning else {
            stateLock.unlock()
            return
        }
        isRunning = false
        let sock = serverSocket
        serverSocket = -1
        stateLock.unlock()

        if sock >= 0 {
            shutdown(sock, SHUT_RDWR)
            close(sock)
        }
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while true {
            stateLock.lock()
            let sock = serverSocket
            let running = isRunning
            stateLock.unlock()

            guard running, sock >= 0 else { break }

            var clientAddr = sockaddr_in()
            var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)

            let clientSock = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(sock, $0, &clientLen)
                }
            }

            guard clientSock >= 0 else {
                if !isRunning { break }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            #if canImport(Darwin)
            var opt: Int32 = 1
            setsockopt(clientSock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))
            #endif

            stateLock.lock()
            activeCount += 1
            totalCount += 1
            stateLock.unlock()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(clientSock: clientSock)
            }
        }
    }

    // MARK: - Client Handler (SOCKS5 Protocol)

    private func handleClient(clientSock: Int32) {
        defer {
            close(clientSock)
            stateLock.lock()
            activeCount = max(0, activeCount - 1)
            stateLock.unlock()
        }

        let startTime = Date()

        do {
            // SOCKS5 Handshake
            let verMethod = try readExact(socket: clientSock, count: 2)
            guard verMethod[0] == 0x05 else { return } // Only SOCKS5

            let nMethods = Int(verMethod[1])
            let methods = try readExact(socket: clientSock, count: nMethods)

            var requestedInterface: String? = nil

            // Check if client offers RFC 1929 username auth to request a specific interface
            if methods.contains(0x02) {
                try writeExact(socket: clientSock, data: [0x05, 0x02])

                // Read RFC 1929 subnegotiation: [VER, ULEN, UNAME..., PLEN, PASSWD...]
                let authHeader = try readExact(socket: clientSock, count: 2)
                let ulen = Int(authHeader[1])
                if ulen > 0 {
                    let uBytes = try readExact(socket: clientSock, count: ulen)
                    if let user = String(bytes: uBytes, encoding: .utf8), !user.isEmpty {
                        requestedInterface = user
                    }
                }
                let plenByte = try readExact(socket: clientSock, count: 1)
                let plen = Int(plenByte[0])
                if plen > 0 {
                    _ = try readExact(socket: clientSock, count: plen)
                }

                // Auth success [0x01, 0x00]
                try writeExact(socket: clientSock, data: [0x01, 0x00])
            } else {
                // Respond with No-Auth required [0x05, 0x00]
                let authResponse: [UInt8] = [0x05, 0x00]
                try writeExact(socket: clientSock, data: authResponse)
            }

            // Read SOCKS5 request: [VER, CMD, RSV, ATYP, DST.ADDR, DST.PORT]
            let reqHeader = try readExact(socket: clientSock, count: 4)
            guard reqHeader[0] == 0x05 else { return }
            let cmd = reqHeader[1]
            let atyp = reqHeader[3]

            // We handle CONNECT (0x01)
            guard cmd == 0x01 else {
                let errResp: [UInt8] = [0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
                _ = try? writeExact(socket: clientSock, data: errResp)
                return
            }

            var targetHost = ""
            var targetFamily: AddressFamily = .v4

            switch atyp {
            case 0x01: // IPv4 (4 bytes)
                let ipBytes = try readExact(socket: clientSock, count: 4)
                targetHost = "\(ipBytes[0]).\(ipBytes[1]).\(ipBytes[2]).\(ipBytes[3])"
                targetFamily = .v4

            case 0x03: // Domain name (1-byte length + bytes)
                let lenByte = try readExact(socket: clientSock, count: 1)
                let domainLen = Int(lenByte[0])
                let domainBytes = try readExact(socket: clientSock, count: domainLen)
                guard let domainStr = String(bytes: domainBytes, encoding: .utf8) else { return }
                targetHost = domainStr
                targetFamily = AddressFamily.infer(host: domainStr)

            case 0x04: // IPv6 (16 bytes)
                let ip6Bytes = try readExact(socket: clientSock, count: 16)
                var addr6 = in6_addr()
                withUnsafeMutableBytes(of: &addr6) { ptr in
                    ptr.copyBytes(from: ip6Bytes)
                }
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                inet_ntop(AF_INET6, &addr6, &buffer, socklen_t(INET6_ADDRSTRLEN))
                targetHost = String(cString: buffer)
                targetFamily = .v6

            default:
                let errResp: [UInt8] = [0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
                _ = try? writeExact(socket: clientSock, data: errResp)
                return
            }

            let portBytes = try readExact(socket: clientSock, count: 2)
            let targetPort = UInt16(portBytes[0]) << 8 | UInt16(portBytes[1])

            // Try requested interface if client explicitly requested one (e.g. parallel chunk streams)
            var outboundSock: Int32 = -1
            var activeLinkID: LinkID? = nil
            var attemptedLinks = Set<LinkID>()

            if let iface = requestedInterface {
                let linkID = LinkID(iface)
                attemptedLinks.insert(linkID)
                do {
                    outboundSock = try connectBound(host: targetHost, port: targetPort, interfaceName: iface, family: targetFamily)
                    activeLinkID = linkID
                } catch {
                    // Fall back to scheduler if preferred interface fails
                }
            }

            // If not requested or preferred interface failed, balance across active links
            if outboundSock < 0 {
                for _ in 0..<3 {
                    if let link = scheduler.acquire(targetFamily, avoiding: attemptedLinks) {
                        attemptedLinks.insert(link)
                        do {
                            outboundSock = try connectBound(host: targetHost, port: targetPort, interfaceName: link.name, family: targetFamily)
                            activeLinkID = link
                            break
                        } catch {
                            scheduler.release(link, family: targetFamily, bytesIn: 0, bytesOut: 0, elapsed: 0.1, succeeded: false)
                        }
                    } else {
                        break
                    }
                }
            }

            // Fallback to direct connection if bound connections failed or no links available
            if outboundSock < 0 {
                do {
                    outboundSock = try connectUnbound(host: targetHost, port: targetPort, family: targetFamily)
                } catch {
                    let errResp: [UInt8] = [0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
                    _ = try? writeExact(socket: clientSock, data: errResp)
                    stateLock.lock()
                    lastErr = error.localizedDescription
                    stateLock.unlock()
                    return
                }
            }

            defer { close(outboundSock) }

            let linkName = activeLinkID?.name
            if let name = linkName {
                stateLock.lock()
                activeFlowsByLink[name, default: 0] += 1
                stateLock.unlock()
            }

            var succeeded = false
            var rxBytes: UInt64 = 0
            var txBytes: UInt64 = 0

            defer {
                if let linkID = activeLinkID {
                    let name = linkID.name
                    stateLock.lock()
                    activeFlowsByLink[name] = max(0, (activeFlowsByLink[name] ?? 1) - 1)
                    stateLock.unlock()

                    let elapsed = Date().timeIntervalSince(startTime)
                    scheduler.release(
                        linkID,
                        family: targetFamily,
                        bytesIn: rxBytes,
                        bytesOut: txBytes,
                        elapsed: elapsed,
                        succeeded: succeeded
                    )
                }
            }

            // Inform client of success
            let successResp: [UInt8] = [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
            try writeExact(socket: clientSock, data: successResp)

            // Pump bytes bidirectionally
            let (rx, tx) = try pump(socketA: clientSock, socketB: outboundSock, linkName: linkName)
            rxBytes = rx
            txBytes = tx
            succeeded = true

            stateLock.lock()
            bytesRx += rx
            bytesTx += tx
            stateLock.unlock()

        } catch {
            stateLock.lock()
            lastErr = error.localizedDescription
            stateLock.unlock()
        }
    }

    // MARK: - Direct (Unbound) Fallback

    private func routeDirect(clientSock: Int32, host: String, port: UInt16, family: AddressFamily) throws {
        let outboundSock = try connectUnbound(host: host, port: port, family: family)
        defer { close(outboundSock) }

        let successResp: [UInt8] = [0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
        try writeExact(socket: clientSock, data: successResp)

        let (rx, tx) = try pump(socketA: clientSock, socketB: outboundSock)
        stateLock.lock()
        bytesRx += rx
        bytesTx += tx
        stateLock.unlock()
    }

    // MARK: - Outbound Socket Binding (IP_BOUND_IF)

    private func nonBlockingConnect(sock: Int32, addr: UnsafePointer<sockaddr>, addrlen: socklen_t, timeoutSeconds: Double) -> Bool {
        let flags = fcntl(sock, F_GETFL, 0)
        guard flags >= 0 else { return false }
        guard fcntl(sock, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }

        let res = connect(sock, addr, addrlen)
        if res == 0 {
            _ = fcntl(sock, F_SETFL, flags)
            return true
        }

        if errno != EINPROGRESS {
            return false
        }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let timeoutMs = Int32(max(100, timeoutSeconds * 1000))
        let pollRes = poll(&pfd, 1, timeoutMs)
        guard pollRes > 0 else { return false }

        var err: Int32 = 0
        var errLen = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(sock, SOL_SOCKET, SO_ERROR, &err, &errLen) == 0, err == 0 else {
            return false
        }

        _ = fcntl(sock, F_SETFL, flags)
        return true
    }

    private func connectBound(host: String, port: UInt16, interfaceName: String, family: AddressFamily) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var res: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let getaddrRes = getaddrinfo(host, portStr, &hints, &res)
        guard getaddrRes == 0, let head = res else {
            throw LocalProxyError.hostResolutionFailed
        }
        defer { freeaddrinfo(head) }

        var list: [UnsafeMutablePointer<addrinfo>] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = head
        while let current = ptr {
            list.append(current)
            ptr = current.pointee.ai_next
        }

        // Prioritize address family matching the target connection
        // Dual-stack cellular/hotspot setups often drop IPv6; default to IPv4 first for reliability
        list.sort { a, b in
            let aFam = a.pointee.ai_family
            let bFam = b.pointee.ai_family
            if family == .v6 {
                if aFam == AF_INET6 && bFam != AF_INET6 { return true }
                if aFam != AF_INET6 && bFam == AF_INET6 { return false }
            } else {
                if aFam == AF_INET && bFam != AF_INET { return true }
                if aFam != AF_INET && bFam == AF_INET { return false }
            }
            return false
        }

        var lastError: Int32 = ECONNREFUSED
        let ifIndex = if_nametoindex(interfaceName)

        for candidate in list {
            let info = candidate.pointee
            let sock = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            guard sock >= 0 else {
                lastError = errno
                continue
            }

            #if canImport(Darwin)
            var nosigpipe: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

            // Bind socket to physical interface via IP_BOUND_IF / IPV6_BOUND_IF
            if ifIndex > 0 {
                var indexVar = ifIndex
                let isV6 = info.ai_family == AF_INET6
                let optName = isV6 ? IPV6_BOUND_IF : IP_BOUND_IF
                let optLevel = isV6 ? IPPROTO_IPV6 : IPPROTO_IP
                _ = setsockopt(sock, Int32(optLevel), Int32(optName), &indexVar, socklen_t(MemoryLayout<UInt32>.size))
            }
            #endif

            // Responsive non-blocking connect (2.0s timeout per candidate)
            let connected = nonBlockingConnect(sock: sock, addr: info.ai_addr, addrlen: info.ai_addrlen, timeoutSeconds: 2.0)
            if connected {
                #if canImport(Darwin)
                var normalTv = timeval(tv_sec: 15, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &normalTv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &normalTv, socklen_t(MemoryLayout<timeval>.size))
                #endif
                return sock
            } else {
                lastError = errno
                close(sock)
            }
        }

        throw LocalProxyError.posix(lastError, "connect to \(host):\(port) via \(interfaceName) failed")
    }

    private func connectUnbound(host: String, port: UInt16, family: AddressFamily) throws -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var res: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let getaddrRes = getaddrinfo(host, portStr, &hints, &res)
        guard getaddrRes == 0, let head = res else {
            throw LocalProxyError.hostResolutionFailed
        }
        defer { freeaddrinfo(head) }

        var list: [UnsafeMutablePointer<addrinfo>] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = head
        while let current = ptr {
            list.append(current)
            ptr = current.pointee.ai_next
        }

        list.sort { a, b in
            let aFam = a.pointee.ai_family
            let bFam = b.pointee.ai_family
            if family == .v6 {
                if aFam == AF_INET6 && bFam != AF_INET6 { return true }
                if aFam != AF_INET6 && bFam == AF_INET6 { return false }
            } else {
                if aFam == AF_INET && bFam != AF_INET { return true }
                if aFam != AF_INET && bFam == AF_INET { return false }
            }
            return false
        }

        var lastError: Int32 = ECONNREFUSED

        for candidate in list {
            let info = candidate.pointee
            let sock = socket(info.ai_family, info.ai_socktype, info.ai_protocol)
            guard sock >= 0 else {
                lastError = errno
                continue
            }

            #if canImport(Darwin)
            var nosigpipe: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
            #endif

            let connected = nonBlockingConnect(sock: sock, addr: info.ai_addr, addrlen: info.ai_addrlen, timeoutSeconds: 3.0)
            if connected {
                #if canImport(Darwin)
                var normalTv = timeval(tv_sec: 15, tv_usec: 0)
                setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &normalTv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &normalTv, socklen_t(MemoryLayout<timeval>.size))
                #endif
                return sock
            } else {
                lastError = errno
                close(sock)
            }
        }

        throw LocalProxyError.posix(lastError, "connect to \(host):\(port) failed")
    }

    // MARK: - Bidirectional Data Pump

    private func pump(socketA: Int32, socketB: Int32, linkName: String? = nil) throws -> (bytesAtoB: UInt64, bytesBtoA: UInt64) {
        var totalAtoB: UInt64 = 0
        var totalBtoA: UInt64 = 0
        let bufSize = config.bufferSize
        var buffer = [UInt8](repeating: 0, count: bufSize)

        var fds = [
            pollfd(fd: socketA, events: Int16(POLLIN), revents: 0),
            pollfd(fd: socketB, events: Int16(POLLIN), revents: 0)
        ]

        var openA = true
        var openB = true

        while openA || openB {
            fds[0].events = openA ? Int16(POLLIN) : 0
            fds[1].events = openB ? Int16(POLLIN) : 0
            fds[0].revents = 0
            fds[1].revents = 0

            let pollRes = poll(&fds, 2, 15_000)
            guard pollRes > 0 else {
                if pollRes == 0 { break } // Idle timeout (15s)
                if errno == EINTR { continue }
                break
            }

            // Socket A -> Socket B
            if openA && (fds[0].revents & Int16(POLLIN)) != 0 {
                let n = recv(socketA, &buffer, bufSize, 0)
                if n > 0 {
                    let written = writeExactSocket(socketB, buffer: buffer, count: n)
                    if written > 0 {
                        totalAtoB += UInt64(written)
                        if let name = linkName {
                            stateLock.lock()
                            bytesTxByLink[name, default: 0] += UInt64(written)
                            stateLock.unlock()
                        }
                    } else {
                        openA = false
                        openB = false
                        break
                    }
                } else {
                    openA = false
                    shutdown(socketB, SHUT_WR)
                }
            }

            // Socket B -> Socket A
            if openB && (fds[1].revents & Int16(POLLIN)) != 0 {
                let n = recv(socketB, &buffer, bufSize, 0)
                if n > 0 {
                    let written = writeExactSocket(socketA, buffer: buffer, count: n)
                    if written > 0 {
                        totalBtoA += UInt64(written)
                        if let name = linkName {
                            stateLock.lock()
                            bytesRxByLink[name, default: 0] += UInt64(written)
                            stateLock.unlock()
                        }
                    } else {
                        openA = false
                        openB = false
                        break
                    }
                } else {
                    openB = false
                    shutdown(socketA, SHUT_WR)
                }
            }

            if (fds[0].revents & (Int16(POLLHUP) | Int16(POLLERR))) != 0 {
                openA = false
                shutdown(socketB, SHUT_WR)
            }
            if (fds[1].revents & (Int16(POLLHUP) | Int16(POLLERR))) != 0 {
                openB = false
                shutdown(socketA, SHUT_WR)
            }
        }

        return (totalAtoB, totalBtoA)
    }

    // MARK: - Socket Helpers

    private func readExact(socket: Int32, count: Int) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: count)
        var readSoFar = 0
        while readSoFar < count {
            let n = recv(socket, &buffer[readSoFar], count - readSoFar, 0)
            guard n > 0 else {
                throw LocalProxyError.posix(ECONNRESET, "connection reset")
            }
            readSoFar += n
        }
        return buffer
    }

    private func writeExact(socket: Int32, data: [UInt8]) throws {
        _ = writeExactSocket(socket, buffer: data, count: data.count)
    }

    private func writeExactSocket(_ sock: Int32, buffer: [UInt8], count: Int) -> Int {
        var written = 0
        while written < count {
            let n = buffer.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return 0 }
                return write(sock, base.advanced(by: written), count - written)
            }
            if n <= 0 { return written }
            written += n
        }
        return written
    }
}
