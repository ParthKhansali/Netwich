import XCTest
@testable import MergeKit

/// Regression tests for the hardening work: untrusted filenames, hostile web origins,
/// and truncated transfers that must never be reported as complete.
final class SecurityTests: XCTestCase {

    // MARK: - Filename sanitisation

    func testPathTraversalIsStrippedFromFilenames() {
        let cases: [(String, String)] = [
            ("../../../../Library/LaunchAgents/evil.plist", "evil.plist"),
            ("/etc/passwd", "passwd"),
            ("..", "fallback"),
            (".", "fallback"),
            ("", "fallback")
        ]

        for (input, expected) in cases {
            XCTAssertEqual(
                DownloadItem.sanitizeName(input, fallback: "fallback"),
                expected,
                "unexpected sanitisation for \(input)"
            )
        }
    }

    func testDownloadItemNeverEscapesDestinationFolder() {
        let folder = URL(fileURLWithPath: "/tmp/netwich-test")
        let item = DownloadItem(
            url: URL(string: "https://example.com/file.bin")!,
            filename: "../../../evil.dylib",
            destinationFolder: folder
        )
        XCTAssertEqual(item.filename, "evil.dylib")
        XCTAssertEqual(item.destinationFileURL.deletingLastPathComponent().path, folder.path)
    }

    // MARK: - Bridge origin policy

    func testWebOriginsAreRejectedButExtensionsAreNot() throws {
        let manager = DownloadManager(defaultDestination: FileManager.default.temporaryDirectory)
        let bridge = BrowserBridgeServer(downloadManager: manager)
        XCTAssertTrue(bridge.start())
        defer { bridge.stop() }

        guard let port = bridge.activePort else {
            XCTFail("bridge did not bind")
            return
        }

        XCTAssertEqual(status(for: port, origin: "https://evil.example"), 403,
                       "a web page must not be able to read the download list")
        XCTAssertEqual(status(for: port, origin: "http://127.0.0.1:8080"), 403,
                       "a page served from another local port is still a web origin")
        XCTAssertEqual(status(for: port, origin: "chrome-extension://abcdefghijklmnop"), 200,
                       "the Chrome extension must keep working")
        XCTAssertEqual(status(for: port, origin: nil), 200,
                       "native clients (and the netwich:// handoff) send no Origin")
    }

    func testRejectedOriginGetsNoCORSGrant() throws {
        let manager = DownloadManager(defaultDestination: FileManager.default.temporaryDirectory)
        let bridge = BrowserBridgeServer(downloadManager: manager)
        XCTAssertTrue(bridge.start())
        defer { bridge.stop() }

        guard let port = bridge.activePort else {
            XCTFail("bridge did not bind")
            return
        }

        let headers = responseHeaders(for: port, origin: "https://evil.example")
        XCTAssertNil(headers?["access-control-allow-origin"],
                     "a rejected origin must never receive a CORS grant")
    }

    func testProtocolRelativeUrlIsRejected() throws {
        let manager = DownloadManager(defaultDestination: FileManager.default.temporaryDirectory)
        let bridge = BrowserBridgeServer(downloadManager: manager)
        XCTAssertTrue(bridge.start())
        defer { bridge.stop() }

        guard let port = bridge.activePort else {
            XCTFail("bridge did not bind")
            return
        }

        let body = #"{"url":"file:///etc/passwd"}"#
        let (data, _) = post("/add", body: body, port: port)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("invalid_url"), "only http(s) targets may be added, got: \(text)")
    }

    // MARK: - Helpers

    private func status(for port: UInt16, origin: String?) -> Int? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        if let origin { request.setValue(origin, forHTTPHeaderField: "Origin") }
        return syncStatus(for: request)
    }

    private func responseHeaders(for port: UInt16, origin: String) -> [String: String]? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
        request.setValue(origin, forHTTPHeaderField: "Origin")

        var headers: [String: String]?
        let done = expectation(description: "headers")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            headers = (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String {
                    result[key.lowercased()] = String(describing: pair.value)
                }
            }
            done.fulfill()
        }.resume()
        _ = XCTWaiter.wait(for: [done], timeout: 5)
        return headers
    }

    private func post(_ path: String, body: String, port: UInt16) -> (Data, Int?) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("chrome-extension://abcdefghijklmnop", forHTTPHeaderField: "Origin")

        var payload = Data()
        var code: Int?
        let done = expectation(description: "post")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            payload = data ?? Data()
            code = (response as? HTTPURLResponse)?.statusCode
            done.fulfill()
        }.resume()
        _ = XCTWaiter.wait(for: [done], timeout: 5)
        return (payload, code)
    }

    private func syncStatus(for request: URLRequest) -> Int? {
        var code: Int?
        let done = expectation(description: "status")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            code = (response as? HTTPURLResponse)?.statusCode
            done.fulfill()
        }.resume()
        _ = XCTWaiter.wait(for: [done], timeout: 5)
        return code
    }
}
