import Darwin
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Loopback HTTP bridge used by the Netwich browser extensions.
///
/// Runs on 127.0.0.1:19288 (falling back to 19289/19290) and speaks a small JSON
/// protocol: `GET /ping`, `/status`, `POST /add`, `/confirm`, `/open`, and download
/// controls.
///
/// ## Security model
///
/// A loopback HTTP server is reachable by *every* web page the user visits, so the
/// protocol has to assume the caller is hostile until proven otherwise:
///
/// - **Origin allowlist.** Extension-origin requests (`chrome-extension://`,
///   `moz-extension://`, `safari-web-extension://`) are accepted. A page-initiated
///   request always carries an `http(s)://` origin, which is rejected with 403.
///   The old code reflected *any* origin in `Access-Control-Allow-Origin`, which let a
///   random site read the user's download history — including absolute file paths.
/// - **No wildcard CORS.** The response only ever echoes a validated extension origin.
/// - **Bounded parsing.** The request is read until the header terminator and then
///   exactly `Content-Length` bytes, so large cookie payloads are not truncated.
/// - **Bounded state.** Pending offers are capped so a hostile caller cannot grow the
///   queue without limit.
public final class BrowserBridgeServer: @unchecked Sendable {
    public static let standardPorts: [UInt16] = [19288, 19289, 19290]

    enum Limits {
        static let maxHeaderBytes = 32 * 1024
        static let maxBodyBytes = 512 * 1024
        static let maxPendingOffers = 32
        static let offerTTL: TimeInterval = 30
    }

    public struct BridgePing: Codable, Sendable {
        public let app: String
        public let version: String
        public let api: Int
    }

    public struct BridgeAddRequest: Codable, Sendable {
        public let url: String
        public let pageUrl: String?
        public let fileName: String?
        public let minBytes: Int64?
        public let browser: BridgeBrowserContext?
    }

    public struct BridgeBrowserContext: Codable, Sendable {
        public let cookies: [BridgeCookie]?
        public let referer: String?
        public let userAgent: String?
    }

    public struct BridgeCookie: Codable, Sendable {
        public let name: String
        public let value: String
        public let domain: String?
        public let path: String?
    }

    public struct BridgeAddResponse: Codable, Sendable {
        public let token: String
    }

    public struct BridgeConfirmRequest: Codable, Sendable {
        public let token: String
    }

    private let downloadManager: DownloadManager
    private var serverSocket: Int32 = -1
    private var listeningPort: UInt16?
    private var isRunning = false
    private let lock = NSLock()
    private var pendingOffers: [String: BridgeAddRequest] = [:]

    public var statusProvider: (@Sendable () -> [String: Any])?
    public var openAppHandler: (@Sendable () -> Void)?

    public init(downloadManager: DownloadManager = .shared) {
        self.downloadManager = downloadManager
    }

    public var activePort: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return listeningPort
    }

    public func start() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return true }

        for port in Self.standardPorts {
            let sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
            guard sock >= 0 else { continue }

            var opt: Int32 = 1
            setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
            #if canImport(Darwin)
            setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &opt, socklen_t(MemoryLayout<Int32>.size))
            #endif

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindRes = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }

            guard bindRes == 0, listen(sock, 64) == 0 else {
                close(sock)
                continue
            }

            serverSocket = sock
            listeningPort = port
            isRunning = true

            let thread = Thread { [weak self] in
                self?.acceptLoop()
            }
            thread.name = "dev.parth.netwich.browserbridge"
            thread.start()
            return true
        }

        return false
    }

    public func stop() {
        lock.lock()
        guard isRunning else {
            lock.unlock()
            return
        }
        isRunning = false
        listeningPort = nil
        let sock = serverSocket
        serverSocket = -1
        lock.unlock()

        if sock >= 0 {
            shutdown(sock, SHUT_RDWR)
            close(sock)
        }
    }

    // MARK: - Accept Loop

    private func acceptLoop() {
        while true {
            lock.lock()
            let sock = serverSocket
            let running = isRunning
            lock.unlock()

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

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.handleConnection(clientSock: clientSock)
            }
        }
    }

    // MARK: - HTTP

    private struct HTTPRequest {
        var method: String
        var path: String
        var headers: [String: String]
        var body: Data

        var origin: String? { headers["origin"] }
    }

    private enum OriginVerdict {
        case allowed(String?)
        case rejected
    }

    /// Extension origins are trusted; web origins are not.
    ///
    /// Browsers attach `Origin` to every cross-origin fetch and form POST, so a page
    /// cannot hide. Requests with no `Origin` at all come from native clients such as
    /// the tests and `netwich://` handoffs.
    private static func verifyOrigin(_ origin: String?) -> OriginVerdict {
        guard let origin, !origin.isEmpty else { return .allowed(nil) }
        let lower = origin.lowercased()
        let extensionSchemes = ["chrome-extension://", "moz-extension://", "safari-web-extension://"]
        if extensionSchemes.contains(where: { lower.hasPrefix($0) }) {
            return .allowed(origin)
        }
        return .rejected
    }

    private func handleConnection(clientSock: Int32) {
        defer { close(clientSock) }

        // Bound how long a single request may take so a stalled client cannot pin a thread.
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(clientSock, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientSock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let request = readRequest(from: clientSock) else {
            send(socket: clientSock, status: "400 Bad Request", headers: "", body: Data())
            return
        }

        let verdict = Self.verifyOrigin(request.origin)
        guard case .allowed(let echoOrigin) = verdict else {
            // No CORS headers: the browser will also refuse to hand the body to the page.
            send(socket: clientSock, status: "403 Forbidden", headers: "", body: Data("{\"error\":\"origin_not_allowed\"}".utf8))
            return
        }

        var cors = "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            + "Access-Control-Allow-Headers: Content-Type\r\n"
            + "Access-Control-Max-Age: 600\r\n"
            + "Access-Control-Allow-Private-Network: true\r\n"
            + "Cache-Control: no-store\r\n"
        if let echoOrigin {
            cors += "Access-Control-Allow-Origin: \(echoOrigin)\r\nVary: Origin\r\n"
        }

        if request.method == "OPTIONS" {
            send(socket: clientSock, status: "204 No Content", headers: cors, body: Data())
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/ping"):
            let ping = BridgePing(app: "netwich", version: Self.appVersion, api: 1)
            sendJSON(socket: clientSock, cors: cors, value: ping)

        case ("GET", "/status"), ("GET", "/downloads"):
            sendJSONString(socket: clientSock, cors: cors, json: statusJSON())

        case ("GET", "/open"), ("POST", "/open"):
            DispatchQueue.main.async { [weak self] in self?.openAppHandler?() }
            sendJSONString(socket: clientSock, cors: cors, json: "{\"ok\":true}")

        case ("POST", "/add"):
            handleAdd(socket: clientSock, cors: cors, body: request.body)

        case ("POST", "/confirm"):
            handleConfirm(socket: clientSock, cors: cors, body: request.body)

        case ("POST", "/downloads/open"), ("POST", "/downloads/reveal"),
             ("POST", "/downloads/pause"), ("POST", "/downloads/resume"),
             ("POST", "/downloads/cancel"):
            handleDownloadAction(socket: clientSock, cors: cors, path: request.path, body: request.body)

        case ("POST", "/downloads/clear"):
            downloadManager.clearCompleted()
            sendJSONString(socket: clientSock, cors: cors, json: "{\"ok\":true}")

        default:
            send(socket: clientSock, status: "404 Not Found", headers: cors, body: Data())
        }
    }

    // MARK: - Endpoint handlers

    private func handleAdd(socket clientSock: Int32, cors: String, body: Data) {
        guard let req = try? JSONDecoder().decode(BridgeAddRequest.self, from: body),
              let url = URL(string: req.url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            sendJSONString(socket: clientSock, cors: cors, json: "{\"error\":\"invalid_url\"}")
            return
        }

        let token = UUID().uuidString
        lock.lock()
        if pendingOffers.count >= Limits.maxPendingOffers {
            // Drop the oldest offer rather than growing without bound.
            if let oldest = pendingOffers.keys.first {
                pendingOffers.removeValue(forKey: oldest)
            }
        }
        pendingOffers[token] = req
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + Limits.offerTTL) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.pendingOffers.removeValue(forKey: token)
            self.lock.unlock()
        }

        sendJSON(socket: clientSock, cors: cors, value: BridgeAddResponse(token: token))
    }

    private func handleConfirm(socket clientSock: Int32, cors: String, body: Data) {
        guard let req = try? JSONDecoder().decode(BridgeConfirmRequest.self, from: body) else {
            sendJSONString(socket: clientSock, cors: cors, json: "{\"error\":\"invalid_request\"}")
            return
        }

        lock.lock()
        let offer = pendingOffers.removeValue(forKey: req.token)
        lock.unlock()

        guard let offer, let url = URL(string: offer.url) else {
            sendJSONString(socket: clientSock, cors: cors, json: "{\"error\":\"offer_expired\"}")
            return
        }

        var cookieHeader: String?
        if let cookies = offer.browser?.cookies, !cookies.isEmpty {
            cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }

        downloadManager.addDownload(
            url: url,
            customFilename: offer.fileName,
            userAgent: offer.browser?.userAgent,
            referer: offer.browser?.referer ?? offer.pageUrl,
            cookies: cookieHeader
        )
        sendJSONString(socket: clientSock, cors: cors, json: "{\"ok\":true}")
    }

    private func handleDownloadAction(socket clientSock: Int32, cors: String, path: String, body: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let idString = json["id"] as? String,
              let id = UUID(uuidString: idString) else {
            sendJSONString(socket: clientSock, cors: cors, json: "{\"error\":\"invalid_request\"}")
            return
        }

        switch path {
        case "/downloads/open":
            if let item = downloadManager.allDownloads.first(where: { $0.id == id }) {
                #if canImport(AppKit)
                DispatchQueue.main.async {
                    let destination = item.destinationFileURL
                    if FileManager.default.fileExists(atPath: destination.path) {
                        NSWorkspace.shared.open(destination)
                    }
                }
                #endif
            }
        case "/downloads/reveal":
            if let item = downloadManager.allDownloads.first(where: { $0.id == id }) {
                #if canImport(AppKit)
                DispatchQueue.main.async {
                    let destination = item.destinationFileURL
                    if FileManager.default.fileExists(atPath: destination.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([destination])
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([item.destinationFolder])
                    }
                }
                #endif
            }
        case "/downloads/pause":
            downloadManager.pauseDownload(id: id)
        case "/downloads/resume":
            downloadManager.resumeDownload(id: id)
        case "/downloads/cancel":
            downloadManager.cancelDownload(id: id)
        default:
            break
        }

        sendJSONString(socket: clientSock, cors: cors, json: "{\"ok\":true}")
    }

    private func statusJSON() -> String {
        var data = statusProvider?() ?? [
            "app": "netwich",
            "version": Self.appVersion,
            "connected": true,
            "speedBytesPerSec": 0.0,
            "activeConnections": 0
        ]

        let items = downloadManager.allDownloads.map { item -> [String: Any] in
            var dict: [String: Any] = [
                "id": item.id.uuidString,
                "filename": item.filename,
                "url": item.url.absoluteString,
                "status": Self.statusSlug(item.status),
                "statusTitle": item.status.title,
                "isCompleted": item.status == .completed,
                "progress": item.progress,
                "downloadedBytes": item.downloadedBytes,
                "totalBytes": item.totalBytes,
                "speedBytesPerSec": item.speedBytesPerSec,
                "destinationPath": item.destinationFileURL.path,
                "addedDate": item.addedDate.timeIntervalSince1970
            ]
            if let eta = item.etaSeconds { dict["etaSeconds"] = eta }
            return dict
        }
        data["downloads"] = items

        guard let json = try? JSONSerialization.data(withJSONObject: data) else {
            return "{\"connected\":true,\"downloads\":[]}"
        }
        return String(decoding: json, as: UTF8.self)
    }

    static func statusSlug(_ status: DownloadStatus) -> String {
        switch status {
        case .queued: return "queued"
        case .probing: return "probing"
        case .downloading: return "downloading"
        case .paused: return "paused"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }

    static var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0.0"
    }

    // MARK: - Wire format

    private func readRequest(from socket: Int32) -> HTTPRequest? {
        var buffer = Data()
        var headerEnd: Range<Data.Index>?

        while buffer.count < Limits.maxHeaderBytes {
            guard let chunk = receive(socket: socket, max: 8 * 1024), !chunk.isEmpty else { break }
            buffer.append(chunk)
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                headerEnd = range
                break
            }
        }

        guard let headerEnd,
              let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else {
            return nil
        }

        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().components(separatedBy: " ")
        guard requestLine.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        var body = Data(buffer[headerEnd.upperBound...])
        let expected = Int(headers["content-length"] ?? "0") ?? 0
        if expected > Limits.maxBodyBytes { return nil }

        while body.count < expected {
            guard let chunk = receive(socket: socket, max: min(16 * 1024, expected - body.count)), !chunk.isEmpty else { break }
            body.append(chunk)
        }

        let rawPath = requestLine[1]
        let path = rawPath.components(separatedBy: "?").first ?? rawPath

        return HTTPRequest(
            method: requestLine[0].uppercased(),
            path: path,
            headers: headers,
            body: body
        )
    }

    private func receive(socket: Int32, max: Int) -> Data? {
        var buffer = [UInt8](repeating: 0, count: max)
        let count = recv(socket, &buffer, max, 0)
        guard count > 0 else { return nil }
        return Data(buffer[0..<count])
    }

    private func sendJSON<T: Encodable>(socket: Int32, cors: String, value: T) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            sendJSONString(socket: socket, cors: cors, json: "{}")
            return
        }
        sendJSONString(socket: socket, cors: cors, json: json)
    }

    private func sendJSONString(socket: Int32, cors: String, json: String) {
        send(
            socket: socket,
            status: "200 OK",
            headers: cors + "Content-Type: application/json; charset=utf-8\r\n",
            body: Data(json.utf8)
        )
    }

    private func send(socket: Int32, status: String, headers: String, body: Data) {
        var response = "HTTP/1.1 \(status)\r\n"
        response += headers
        response += "Content-Length: \(body.count)\r\n"
        response += "Connection: close\r\n\r\n"

        var payload = Data(response.utf8)
        payload.append(body)

        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < payload.count {
                let written = Darwin.send(socket, base.advanced(by: sent), payload.count - sent, 0)
                if written <= 0 { return }
                sent += written
            }
        }
    }
}
