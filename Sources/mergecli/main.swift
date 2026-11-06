import Foundation
import MergeKit

/// Headless harness: inspect links, test scheduler, proxy, and downloads.
let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "links"

switch command {
case "links":
    let addresses = InterfaceScanner.scan().sorted { $0.key < $1.key }
    print("INTERFACE  UP   IPv4                     IPv6")
    for (name, entry) in addresses {
        guard InterfaceScanner.hasRoutableAddress(entry) else { continue }
        let virtual = InterfaceScanner.isVirtual(name) ? " (virtual, ignored)" : ""
        let v4 = entry.v4.joined(separator: ",")
        let v6 = entry.v6.joined(separator: ",")
        print("\(name.padding(toLength: 10, withPad: " ", startingAt: 0)) \(entry.isUp ? "up " : "dn ")  \(v4.padding(toLength: 24, withPad: " ", startingAt: 0)) \(v6)\(virtual)")
    }

case "sched":
    // Demonstrates the weighting without any network: two links, 300 vs 40 Mbit.
    let scheduler = Scheduler()
    scheduler.setCandidates([
        LinkCandidate(id: LinkID("en0"), kind: .wifi, supportsV4: true, supportsV6: true, manualWeightMbps: 300),
        LinkCandidate(id: LinkID("feth0"), kind: .other, supportsV4: true, supportsV6: false, manualWeightMbps: 40),
    ])
    var counts: [String: Int] = [:]
    for _ in 0..<100 {
        if let id = scheduler.acquire(.v4) {
            counts[id.name, default: 0] += 1
        }
    }
    for (name, count) in counts.sorted(by: { $0.key < $1.key }) {
        print("\(name): \(count) of 100 flows")
    }
    print("v6 flows always land on en0:", scheduler.acquire(.v6)?.name ?? "none")

case "systemproxy":
    let manager = SystemProxyManager()
    let services = manager.listServices()
    print("Detected Network Services:")
    for service in services {
        let status = manager.getStatus(for: service)
        print("  - \(service): SOCKS Enabled=\(status.isEnabled), Server=\(status.server), Port=\(status.port)")
    }

case "proxy":
    let scheduler = Scheduler()
    let server = LocalProxyServer(config: .init(port: 1080), scheduler: scheduler)
    do {
        try server.start()
        print("Local SOCKS5 proxy server listening on 127.0.0.1:1080")
        print("Press Ctrl+C to stop.")
        RunLoop.current.run()
    } catch {
        print("Failed to start proxy: \(error)")
    }

case "test":
    // 1. Ensure scoped routes are active for all physical interfaces
    let addresses = InterfaceScanner.scan()
    let physicalNames = addresses.filter { name, entry in
        !InterfaceScanner.isVirtual(name) && InterfaceScanner.hasRoutableAddress(entry)
    }.map { $0.key }.sorted()
    print("Detected physical interfaces: \(physicalNames)")

    ScopedRouteManager.shared.sync(interfaces: physicalNames)
    for name in physicalNames {
        let hasRoute = ScopedRouteManager.shared.hasScopedRoute(for: name)
        let gw = ScopedRouteManager.shared.discoverGateway(for: name) ?? "none"
        print("  - \(name): Gateway=\(gw), ScopedRoutePresent=\(hasRoute)")
    }

    // 2. Start scheduler and proxy server
    let scheduler = Scheduler()
    var candidates: [LinkCandidate] = []
    for name in physicalNames {
        let entry = addresses[name]!
        candidates.append(LinkCandidate(
            id: LinkID(name),
            kind: LinkInventory.kind(.other, name: name),
            supportsV4: !entry.v4.isEmpty,
            supportsV6: !entry.v6.isEmpty
        ))
    }
    scheduler.setCandidates(candidates)

    let server = LocalProxyServer(config: .init(port: 11080), scheduler: scheduler)
    do {
        try server.start()
        print("Test SOCKS5 proxy running on 127.0.0.1:11080")

        // 3. Make 6 parallel requests through the proxy
        print("Executing 6 requests through proxy to verify multi-interface aggregation...")
        for i in 1...6 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            p.arguments = ["-s", "-x", "socks5h://127.0.0.1:11080", "https://api.ipify.org"]
            let pipe = Pipe()
            p.standardOutput = pipe
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let ip = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "err"
            print("  Request \(i) -> Egress Public IP: \(ip)")
        }

        let tp = server.linkThroughput()
        print("\nLink throughput observed by proxy:")
        for (link, stats) in tp {
            print("  - \(link): rx=\(stats.rx) B, tx=\(stats.tx) B, activeFlows=\(stats.flows)")
        }

        server.stop()
        print("Test complete.")
    } catch {
        print("Test failed: \(error)")
    }

case "download":
    guard arguments.count > 1, let url = URL(string: arguments[1]) else {
        print("usage: mergecli download <url>")
        exit(1)
    }
    let manager = DownloadManager()
    let item = manager.addDownload(url: url)
    print("Started download: \(url.absoluteString)")
    while item.status == .probing || item.status == .downloading || item.status == .queued {
        Thread.sleep(forTimeInterval: 0.5)
        let percent = String(format: "%.1f%%", item.progress * 100)
        print("\rProgress: \(percent) (\(item.downloadedBytes)/\(item.totalBytes) bytes) - \(item.status.title)", terminator: "")
        fflush(stdout)
    }
    print("\nDownload finished with status: \(item.status.title)")
    if item.status == .completed {
        print("Saved to: \(item.destinationFileURL.path)")
    }

default:
    print("usage: mergecli [links|sched|systemproxy|proxy|download <url>]")
}
