import Darwin
import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Lightweight local HTTP server implementing Plexo's browser extension bridge protocol.
///
/// Runs on 127.0.0.1:19288 (falling back to 19289, 19290) to seamlessly intercept and
/// accelerate downloads directly from Chrome, Edge, Brave, and Firefox extensions.
public final class BrowserBridgeServer: @unchecked Sendable {
    public static let standardPorts: [UInt16] = [19288, 19289, 19290]

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
            thread.name = "dev.parth.merge.browserbridge"
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
                self?.handleHttpRequest(clientSock: clientSock)
            }
        }
    }

    // MARK: - HTTP Handler

    private func handleHttpRequest(clientSock: Int32) {
        defer { close(clientSock) }

        var buffer = [UInt8](repeating: 0, count: 16_384)
        let bytesRead = recv(clientSock, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }

        guard let requestString = String(bytes: buffer.prefix(bytesRead), encoding: .utf8) else {
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else { return }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return }

        let method = parts[0].uppercased()
        let path = parts[1]
        let cleanPath = path.components(separatedBy: "?").first ?? path

        // Find Origin for CORS
        var origin = "*"
        for line in lines {
            if line.lowercased().hasPrefix("origin:") {
                origin = line.replacingOccurrences(of: "Origin:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
            }
        }

        let corsHeaders = """
        Access-Control-Allow-Origin: \(origin)\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type\r
        Access-Control-Max-Age: 86400\r\n
        """

        if method == "OPTIONS" {
            let response = "HTTP/1.1 204 No Content\r\n\(corsHeaders)Content-Length: 0\r\n\r\n"
            sendResponse(socket: clientSock, text: response)
            return
        }

        if method == "GET" && cleanPath == "/ping" {
            let ping = BridgePing(app: "netwich", version: "1.0.0", api: 1)
            if let json = try? JSONEncoder().encode(ping), let jsonStr = String(data: json, encoding: .utf8) {
                sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: jsonStr)
            }
            return
        }

        if method == "GET" && (cleanPath == "/status" || cleanPath == "/downloads") {
            var data = statusProvider?() ?? [
                "app": "netwich",
                "version": "1.0.0",
                "connected": true,
                "speed": 0.0,
                "activeFlows": 0
            ]

            let allItems = downloadManager.allDownloads
            let downloadsData: [[String: Any]] = allItems.map { item in
                var dict: [String: Any] = [
                    "id": item.id.uuidString,
                    "filename": item.filename,
                    "url": item.url.absoluteString,
                    "status": String(describing: item.status).components(separatedBy: "(").first?.lowercased() ?? "unknown",
                    "statusTitle": item.status.title,
                    "isCompleted": item.status == .completed,
                    "progress": item.progress,
                    "downloadedBytes": item.downloadedBytes,
                    "totalBytes": item.totalBytes,
                    "speedBytesPerSec": item.speedBytesPerSec,
                    "destinationPath": item.destinationFileURL.path,
                    "addedDate": item.addedDate.timeIntervalSince1970
                ]
                if let eta = item.etaSeconds {
                    dict["etaSeconds"] = eta
                }
                return dict
            }
            data["downloads"] = downloadsData

            if let json = try? JSONSerialization.data(withJSONObject: data),
               let jsonStr = String(data: json, encoding: .utf8) {
                sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: jsonStr)
            } else {
                sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"connected\":true,\"downloads\":[]}")
            }
            return
        }

        if (method == "GET" || method == "POST") && cleanPath == "/open" {
            DispatchQueue.main.async { [weak self] in
                self?.openAppHandler?()
            }
            sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
            return
        }

        // Extract body for POST requests
        if method == "POST" {
            var body = ""
            if let bodyIndex = requestString.range(of: "\r\n\r\n") {
                body = String(requestString[bodyIndex.upperBound...])
            }

            if cleanPath == "/add" {
                if let bodyData = body.data(using: .utf8),
                   let req = try? JSONDecoder().decode(BridgeAddRequest.self, from: bodyData),
                   let _ = URL(string: req.url) {

                    let token = UUID().uuidString
                    lock.lock()
                    pendingOffers[token] = req
                    lock.unlock()

                    // Auto expire after 30s
                    DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                        self?.lock.lock()
                        self?.pendingOffers.removeValue(forKey: token)
                        self?.lock.unlock()
                    }

                    let addResp = BridgeAddResponse(token: token)
                    if let json = try? JSONEncoder().encode(addResp), let jsonStr = String(data: json, encoding: .utf8) {
                        sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: jsonStr)
                    }
                    return
                }
            } else if cleanPath == "/confirm" {
                if let bodyData = body.data(using: .utf8),
                   let req = try? JSONDecoder().decode(BridgeConfirmRequest.self, from: bodyData) {

                    lock.lock()
                    let offer = pendingOffers.removeValue(forKey: req.token)
                    lock.unlock()

                    if let offer = offer, let url = URL(string: offer.url) {
                        var cookieHeader: String? = nil
                        if let cookies = offer.browser?.cookies, !cookies.isEmpty {
                            cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
                        }
                        let referer = offer.browser?.referer ?? offer.pageUrl
                        let userAgent = offer.browser?.userAgent

                        downloadManager.addDownload(
                            url: url,
                            customFilename: offer.fileName,
                            userAgent: userAgent,
                            referer: referer,
                            cookies: cookieHeader
                        )
                        sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{}")
                        return
                    }
                }
            } else if cleanPath == "/downloads/open" {
                if let bodyData = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let idStr = json["id"] as? String,
                   let uuid = UUID(uuidString: idStr),
                   let item = downloadManager.allDownloads.first(where: { $0.id == uuid }) {
                    #if canImport(AppKit)
                    DispatchQueue.main.async {
                        let dest = item.destinationFileURL
                        if FileManager.default.fileExists(atPath: dest.path) {
                            NSWorkspace.shared.open(dest)
                        }
                    }
                    #endif
                    sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
                    return
                }
            } else if cleanPath == "/downloads/reveal" {
                if let bodyData = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let idStr = json["id"] as? String,
                   let uuid = UUID(uuidString: idStr),
                   let item = downloadManager.allDownloads.first(where: { $0.id == uuid }) {
                    #if canImport(AppKit)
                    DispatchQueue.main.async {
                        let dest = item.destinationFileURL
                        if FileManager.default.fileExists(atPath: dest.path) {
                            NSWorkspace.shared.activateFileViewerSelecting([dest])
                        } else {
                            NSWorkspace.shared.activateFileViewerSelecting([item.destinationFolder])
                        }
                    }
                    #endif
                    sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
                    return
                }
            } else if cleanPath == "/downloads/pause" {
                if let bodyData = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let idStr = json["id"] as? String,
                   let uuid = UUID(uuidString: idStr) {
                    downloadManager.pauseDownload(id: uuid)
                    sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
                    return
                }
            } else if cleanPath == "/downloads/resume" {
                if let bodyData = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let idStr = json["id"] as? String,
                   let uuid = UUID(uuidString: idStr) {
                    downloadManager.resumeDownload(id: uuid)
                    sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
                    return
                }
            } else if cleanPath == "/downloads/cancel" {
                if let bodyData = body.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                   let idStr = json["id"] as? String,
                   let uuid = UUID(uuidString: idStr) {
                    downloadManager.cancelDownload(id: uuid)
                    sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
                    return
                }
            } else if cleanPath == "/downloads/clear" {
                downloadManager.clearCompleted()
                sendJsonResponse(socket: clientSock, corsHeaders: corsHeaders, json: "{\"ok\":true}")
                return
            }
        }

        // Not Found
        let notFound = "HTTP/1.1 404 Not Found\r\n\(corsHeaders)Content-Length: 0\r\n\r\n"
        sendResponse(socket: clientSock, text: notFound)
    }

    private func sendJsonResponse(socket: Int32, corsHeaders: String, json: String) {
        let jsonBytes = json.utf8.count
        let response = """
        HTTP/1.1 200 OK\r
        \(corsHeaders)Content-Type: application/json\r
        Content-Length: \(jsonBytes)\r\n\r
        \(json)
        """
        sendResponse(socket: socket, text: response)
    }

    private func sendResponse(socket: Int32, text: String) {
        text.withCString { ptr in
            _ = write(socket, ptr, strlen(ptr))
        }
    }
}
