import XCTest
@testable import MergeKit

final class EngineTests: XCTestCase {
    /// These tests touch the host's real adapters, system proxy or the internet.
    /// Hosted CI runners do not expose the same network surface, so they are opt-in.
    private func requireIntegration() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["NETWICH_INTEGRATION"] == "1",
            "Set NETWICH_INTEGRATION=1 to run tests that need real adapters or internet access."
        )
    }

    func testSystemProxyManagerListing() throws {
        try requireIntegration()
        let manager = SystemProxyManager()
        let services = manager.listServices()
        // Every macOS machine has at least Wi-Fi or Ethernet or Thunderbolt
        XCTAssertFalse(services.isEmpty, "Should list network services on macOS")
    }

    func testLocalProxyServerLifecycle() throws {
        let scheduler = Scheduler()
        let server = LocalProxyServer(config: .init(port: 11080), scheduler: scheduler)
        XCTAssertFalse(server.isServerRunning)

        try server.start()
        XCTAssertTrue(server.isServerRunning)

        let metrics = server.metrics
        XCTAssertEqual(metrics.totalConnections, 0)
        XCTAssertEqual(metrics.activeConnections, 0)

        server.stop()
        XCTAssertFalse(server.isServerRunning)
    }

    func testBrowserBridgeLifecycle() throws {
        let downloadManager = DownloadManager()
        let bridge = BrowserBridgeServer(downloadManager: downloadManager)

        let started = bridge.start()
        XCTAssertTrue(started, "Bridge should bind to one of the standard ports")
        XCTAssertNotNil(bridge.activePort)

        bridge.stop()
        XCTAssertNil(bridge.activePort)
    }

    func testDownloadManagerItemLifecycle() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = DownloadManager(defaultDestination: tempDir)
        let testUrl = URL(string: "https://example.com/testfile.zip")!

        let item = manager.addDownload(url: testUrl, customFilename: "test.zip", startImmediately: false)
        XCTAssertEqual(item.filename, "test.zip")
        XCTAssertEqual(item.status, .queued)

        let all = manager.allDownloads
        XCTAssertTrue(all.contains(where: { $0.id == item.id }))

        manager.cancelDownload(id: item.id)
        manager.deleteDownload(id: item.id, removeFile: true)

        let afterDelete = manager.allDownloads
        XCTAssertFalse(afterDelete.contains(where: { $0.id == item.id }))
    }

    func testLinkInventoryDeduplication() throws {
        try requireIntegration()
        let inventory = LinkInventory()
        inventory.start()
        defer { inventory.stop() }

        let exp = expectation(description: "interfaces received")
        inventory.onChange = { _ in
            exp.fulfill()
        }
        _ = XCTWaiter.wait(for: [exp], timeout: 0.5)

        let candidates = inventory.current
        let uniqueNames = Set(candidates.map { $0.id.name })
        XCTAssertEqual(candidates.count, uniqueNames.count, "Each physical network adapter must only be listed once")
    }

    func testBrowserBridgeStatusWithDownloads() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let downloadManager = DownloadManager(defaultDestination: tempDir)
        let item = downloadManager.addDownload(
            url: URL(string: "https://example.com/archive.dmg")!,
            customFilename: "archive.dmg",
            startImmediately: false
        )

        let bridge = BrowserBridgeServer(downloadManager: downloadManager)
        XCTAssertTrue(bridge.start())
        defer { bridge.stop() }

        guard let port = bridge.activePort else {
            XCTFail("Bridge port not found")
            return
        }

        let url = URL(string: "http://127.0.0.1:\(port)/status")!
        let exp = expectation(description: "fetch status")
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            XCTAssertNil(error)
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let downloads = json["downloads"] as? [[String: Any]] else {
                XCTFail("Failed to parse status response")
                exp.fulfill()
                return
            }

            let found = downloads.first(where: { ($0["id"] as? String) == item.id.uuidString })
            XCTAssertNotNil(found)
            XCTAssertEqual(found?["filename"] as? String, "archive.dmg")
            exp.fulfill()
        }
        task.resume()
        _ = XCTWaiter.wait(for: [exp], timeout: 2.0)
    }

    func testDownloadManagerBrowserContext() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = DownloadManager(defaultDestination: tempDir)
        let item = manager.addDownload(
            url: URL(string: "https://example.com/video.webm")!,
            customFilename: "video.webm",
            userAgent: "CustomUA/1.0",
            referer: "https://example.com/",
            cookies: "session=xyz",
            startImmediately: false
        )

        XCTAssertEqual(item.userAgent, "CustomUA/1.0")
        XCTAssertEqual(item.referer, "https://example.com/")
        XCTAssertEqual(item.cookies, "session=xyz")
    }

    func testScopedRouteManagerDiscovery() throws {
        try requireIntegration()
        let manager = ScopedRouteManager.shared
        // On macOS with active tethering or wifi, discoverGateway discovers a valid IPv4
        let addresses = InterfaceScanner.scan()
        for (name, entry) in addresses {
            guard !InterfaceScanner.isVirtual(name), InterfaceScanner.hasRoutableAddress(entry) else { continue }
            if let gw = manager.discoverGateway(for: name) {
                XCTAssertFalse(gw.isEmpty)
                print("Discovered gateway for \(name): \(gw)")
            }
        }
    }

    func testRealParallelDownloadExecution() throws {
        try requireIntegration()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let manager = DownloadManager(defaultDestination: tempDir)
        // 2 MB test file from Cloudflare Speed test service with Range support
        let testUrl = URL(string: "https://speed.cloudflare.com/__down?bytes=2097152")!

        let exp = expectation(description: "download complete")
        let item = manager.addDownload(
            url: testUrl,
            destinationFolder: tempDir,
            customFilename: "test_2mb.bin",
            concurrency: 4,
            startImmediately: true
        )

        manager.onDownloadsChanged = { items in
            if let updated = items.first(where: { $0.id == item.id }) {
                if updated.status == .completed {
                    exp.fulfill()
                } else if case .failed(let err) = updated.status {
                    XCTFail("Download failed unexpectedly: \(err)")
                    exp.fulfill()
                }
            }
        }

        let result = XCTWaiter.wait(for: [exp], timeout: 25.0)
        XCTAssertEqual(result, .completed, "Download should complete within timeout")

        let filePath = tempDir.appendingPathComponent("test_2mb.bin").path
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath), "Downloaded file must exist on disk")

        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        let size = attrs?[.size] as? Int64 ?? 0
        XCTAssertEqual(size, 2_097_152, "Downloaded file size must match expected 2MB")
    }

    func testLocalProxySOCKS5DomainResolutionAndFallback() throws {
        try requireIntegration()
        let scheduler = Scheduler()
        let server = LocalProxyServer(config: .init(port: 11082), scheduler: scheduler)
        try server.start()
        defer { server.stop() }

        let clientSock = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertTrue(clientSock >= 0)
        defer { close(clientSock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(11082).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(clientSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connRes, 0, "Client should connect to proxy on 127.0.0.1:11082")

        // SOCKS5 Handshake [0x05, 0x01, 0x00]
        var handshake: [UInt8] = [0x05, 0x01, 0x00]
        send(clientSock, &handshake, 3, 0)

        var resp = [UInt8](repeating: 0, count: 2)
        let nRead = recv(clientSock, &resp, 2, 0)
        XCTAssertEqual(nRead, 2)
        XCTAssertEqual(resp[0], 0x05)
        XCTAssertEqual(resp[1], 0x00, "Proxy must accept No-Auth")

        // SOCKS5 Connect to domain 1.1.1.1:80
        // [VER, CMD, RSV, ATYP, DOMAIN_LEN, DOMAIN..., PORT_HI, PORT_LO]
        let domain = "1.1.1.1"
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(domain.utf8.count)]
        req.append(contentsOf: domain.utf8)
        req.append(0x00)
        req.append(0x50) // port 80

        send(clientSock, &req, req.count, 0)

        var connResp = [UInt8](repeating: 0, count: 10)
        let nResp = recv(clientSock, &connResp, 10, 0)
        XCTAssertEqual(nResp, 10)
        XCTAssertEqual(connResp[0], 0x05)
        XCTAssertEqual(connResp[1], 0x00, "Proxy CONNECT to 1.1.1.1:80 should succeed (0x00)")
    }

    func testLocalProxySOCKS5DomainNameResolution() throws {
        try requireIntegration()
        let scheduler = Scheduler()
        let server = LocalProxyServer(config: .init(port: 11083), scheduler: scheduler)
        try server.start()
        defer { server.stop() }

        let clientSock = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertTrue(clientSock >= 0)
        defer { close(clientSock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(11083).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let connRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(clientSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(connRes, 0)

        // SOCKS5 Handshake
        var handshake: [UInt8] = [0x05, 0x01, 0x00]
        send(clientSock, &handshake, 3, 0)
        var resp = [UInt8](repeating: 0, count: 2)
        _ = recv(clientSock, &resp, 2, 0)

        // SOCKS5 Connect to domain "www.speedtest.net:443"
        let domain = "www.speedtest.net"
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03, UInt8(domain.utf8.count)]
        req.append(contentsOf: domain.utf8)
        req.append(0x01)
        req.append(0xBB) // port 443 (0x01BB)

        send(clientSock, &req, req.count, 0)

        var connResp = [UInt8](repeating: 0, count: 10)
        let nResp = recv(clientSock, &connResp, 10, 0)
        XCTAssertEqual(nResp, 10)
        XCTAssertEqual(connResp[0], 0x05)
        XCTAssertEqual(connResp[1], 0x00, "Proxy CONNECT to www.speedtest.net:443 must succeed (0x00) without ERR_ADDRESS_UNREACHABLE")
    }
}

