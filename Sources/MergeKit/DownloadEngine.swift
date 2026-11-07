import Foundation
import Network
#if canImport(AppKit)
import AppKit
#endif

public enum DownloadStatus: Codable, Sendable, Equatable {
    case queued
    case probing
    case downloading
    case paused
    case completed
    case failed(String)

    public var title: String {
        switch self {
        case .queued: return "Queued"
        case .probing: return "Probing"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed(let msg): return "Failed: \(msg)"
        }
    }

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}

public enum DownloadError: LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case cancelled
    case serverRejectedRanges

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code, let msg):
            return "HTTP \(code): \(msg)"
        case .cancelled:
            return "Download cancelled"
        case .serverRejectedRanges:
            return "Server rejected byte range requests"
        }
    }
}

public struct ChunkState: Codable, Sendable, Identifiable {
    public var id: Int
    public var startByte: Int64
    public var endByte: Int64
    public var downloadedBytes: Int64
    public var assignedInterface: String?
    public var isCompleted: Bool

    public var totalBytes: Int64 {
        endByte - startByte + 1
    }

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }
}

public struct DownloadRecord: Codable, Sendable {
    public var id: UUID
    public var url: URL
    public var filename: String
    public var destinationFolder: String
    public var totalBytes: Int64
    public var downloadedBytes: Int64
    public var statusTitle: String
    public var isCompleted: Bool
    public var addedDate: Date
    public var completionDate: Date?
    public var chunks: [ChunkState]

    public init(
        id: UUID,
        url: URL,
        filename: String,
        destinationFolder: String,
        totalBytes: Int64,
        downloadedBytes: Int64,
        statusTitle: String,
        isCompleted: Bool,
        addedDate: Date,
        completionDate: Date?,
        chunks: [ChunkState]
    ) {
        self.id = id
        self.url = url
        self.filename = filename
        self.destinationFolder = destinationFolder
        self.totalBytes = totalBytes
        self.downloadedBytes = downloadedBytes
        self.statusTitle = statusTitle
        self.isCompleted = isCompleted
        self.addedDate = addedDate
        self.completionDate = completionDate
        self.chunks = chunks
    }
}

public struct DownloadMeta: Codable, Sendable {
    public var id: UUID
    public var url: URL
    public var filename: String
    public var destinationPath: String
    public var totalBytes: Int64
    public var etag: String?
    public var chunks: [ChunkState]
    public var supportsRanges: Bool
}

public final class DownloadItem: @unchecked Sendable, Identifiable {
    public let id: UUID
    public let url: URL
    public var filename: String
    public var destinationFolder: URL
    public var totalBytes: Int64 = -1
    public var downloadedBytes: Int64 = 0
    public var speedBytesPerSec: Double = 0
    public var status: DownloadStatus = .queued
    public var chunks: [ChunkState] = []
    public var supportsRanges: Bool = false
    public var etag: String?
    public var addedDate: Date = Date()
    public var completionDate: Date?
    public var userAgent: String?
    public var referer: String?
    public var cookies: String?

    private var activeTasks: [Task<Void, Never>] = []
    private let itemLock = NSLock()

    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(downloadedBytes) / Double(totalBytes)
    }

    public var destinationFileURL: URL {
        destinationFolder.appendingPathComponent(filename)
    }

    public var partFileURL: URL {
        let netwichPart = destinationFolder.appendingPathComponent("\(filename).netwich-part")
        let legacyMergePart = destinationFolder.appendingPathComponent("\(filename).merge-part")
        if FileManager.default.fileExists(atPath: legacyMergePart.path) && !FileManager.default.fileExists(atPath: netwichPart.path) {
            return legacyMergePart
        }
        return netwichPart
    }

    public var metaFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Netwich/metadata", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(id.uuidString).netwich-meta.json")
    }

    public var etaSeconds: TimeInterval? {
        guard speedBytesPerSec > 1024, totalBytes > downloadedBytes else { return nil }
        let remaining = totalBytes - downloadedBytes
        return Double(remaining) / speedBytesPerSec
    }

    public init(
        id: UUID = UUID(),
        url: URL,
        filename: String? = nil,
        destinationFolder: URL,
        userAgent: String? = nil,
        referer: String? = nil,
        cookies: String? = nil
    ) {
        self.id = id
        self.url = url
        self.destinationFolder = destinationFolder
        self.filename = filename ?? url.lastPathComponent
        if self.filename.isEmpty || self.filename == "/" {
            self.filename = "download_\(id.uuidString.prefix(8))"
        }
        self.userAgent = userAgent
        self.referer = referer
        self.cookies = cookies
    }

    func cancelTasks() {
        itemLock.lock()
        for task in activeTasks {
            task.cancel()
        }
        activeTasks.removeAll()
        itemLock.unlock()
    }

    func addTask(_ task: Task<Void, Never>) {
        itemLock.lock()
        activeTasks.append(task)
        itemLock.unlock()
    }

    public func updateChunkProgress(chunkId: Int, chunkDownloaded: Int64, deltaBytes: Int64) {
        itemLock.lock()
        downloadedBytes += deltaBytes
        if let idx = chunks.firstIndex(where: { $0.id == chunkId }) {
            chunks[idx].downloadedBytes = chunkDownloaded
        }
        itemLock.unlock()
    }

    public func markChunkCompleted(chunkId: Int) {
        itemLock.lock()
        if let idx = chunks.firstIndex(where: { $0.id == chunkId }) {
            chunks[idx].isCompleted = true
        }
        itemLock.unlock()
    }

    public func addDownloadedBytes(_ delta: Int64) {
        itemLock.lock()
        downloadedBytes += delta
        itemLock.unlock()
    }
}

final class ChunkFileWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func write(offset: UInt64, data: Data) throws {
        lock.lock()
        defer { lock.unlock() }
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }
}

final class ChunkDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let writer: ChunkFileWriter
    private var writeOffset: UInt64
    private let endOffset: UInt64
    private let progressCallback: (Int64) -> Void
    private let continuation: CheckedContinuation<Int64, Error>
    private var downloadedBytes: Int64 = 0
    private var isCompleted = false
    private let lock = NSLock()

    init(
        startOffset: UInt64,
        endOffset: UInt64,
        writer: ChunkFileWriter,
        progressCallback: @escaping (Int64) -> Void,
        continuation: CheckedContinuation<Int64, Error>
    ) {
        self.writeOffset = startOffset
        self.endOffset = endOffset
        self.writer = writer
        self.progressCallback = progressCallback
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(with: .failure(DownloadError.invalidResponse), session: session)
            completionHandler(.cancel)
            return
        }

        // If chunk starts > 0 and server returned 200, the server ignored the Range header
        if writeOffset > 0 && http.statusCode == 200 {
            finish(with: .failure(DownloadError.serverRejectedRanges), session: session)
            completionHandler(.cancel)
            return
        }

        guard http.statusCode == 206 || http.statusCode == 200 else {
            let msg = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            if http.statusCode == 403 || http.statusCode == 410 {
                finish(with: .failure(DownloadError.httpError(statusCode: http.statusCode, message: "Download link expired or access denied (\(msg)). Please copy a fresh link.")), session: session)
            } else {
                finish(with: .failure(DownloadError.httpError(statusCode: http.statusCode, message: msg)), session: session)
            }
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }

        let offset = writeOffset
        writeOffset += UInt64(data.count)
        downloadedBytes += Int64(data.count)

        do {
            try writer.write(offset: offset, data: data)
            progressCallback(Int64(data.count))
        } catch {
            finish(with: .failure(error), session: session)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            finish(with: .failure(error), session: session)
        } else {
            finish(with: .success(downloadedBytes), session: session)
        }
    }

    private func finish(with result: Result<Int64, Error>, session: URLSession) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        lock.unlock()

        DispatchQueue.global().async {
            session.finishTasksAndInvalidate()
        }

        switch result {
        case .success(let count):
            continuation.resume(returning: count)
        case .failure(let err):
            continuation.resume(throwing: err)
        }
    }
}

final class SingleStreamDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let handle: FileHandle
    private let isResuming: Bool
    private var writeOffset: UInt64
    private let progressCallback: (Int64, Int64) -> Void
    private let continuation: CheckedContinuation<Int64, Error>
    private var downloadedBytes: Int64 = 0
    private var totalBytes: Int64 = -1
    private var isCompleted = false
    private let lock = NSLock()

    init(
        handle: FileHandle,
        isResuming: Bool,
        initialOffset: UInt64,
        progressCallback: @escaping (Int64, Int64) -> Void,
        continuation: CheckedContinuation<Int64, Error>
    ) {
        self.handle = handle
        self.isResuming = isResuming
        self.writeOffset = initialOffset
        self.progressCallback = progressCallback
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(with: .failure(DownloadError.invalidResponse), session: session)
            completionHandler(.cancel)
            return
        }

        guard (200...299).contains(http.statusCode) else {
            let msg = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            if http.statusCode == 403 || http.statusCode == 410 {
                finish(with: .failure(DownloadError.httpError(statusCode: http.statusCode, message: "Download link expired or access denied (\(msg)). Please copy a fresh link.")), session: session)
            } else {
                finish(with: .failure(DownloadError.httpError(statusCode: http.statusCode, message: msg)), session: session)
            }
            completionHandler(.cancel)
            return
        }

        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let totalStr = cr.components(separatedBy: "/").last,
           let total = Int64(totalStr) {
            totalBytes = total
        } else if http.expectedContentLength > 0 {
            totalBytes = http.expectedContentLength + (isResuming ? Int64(writeOffset) : 0)
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCompleted else { return }

        do {
            try handle.seek(toOffset: writeOffset)
            try handle.write(contentsOf: data)
            writeOffset += UInt64(data.count)
            downloadedBytes += Int64(data.count)
            progressCallback(Int64(data.count), totalBytes)
        } catch {
            finish(with: .failure(error), session: session)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            finish(with: .failure(error), session: session)
        } else {
            finish(with: .success(downloadedBytes), session: session)
        }
    }

    private func finish(with result: Result<Int64, Error>, session: URLSession) {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCompleted = true
        lock.unlock()

        DispatchQueue.global().async {
            session.finishTasksAndInvalidate()
        }

        switch result {
        case .success(let count):
            continuation.resume(returning: count)
        case .failure(let err):
            continuation.resume(throwing: err)
        }
    }
}

/// Core engine for parallel chunk downloading across multiple network interfaces.
public final class DownloadManager: @unchecked Sendable {
    public static let shared = DownloadManager()

    public var defaultDestination: URL
    public var defaultConcurrency: Int = 8
    private let managerLock = NSLock()
    private var downloads: [UUID: DownloadItem] = [:]
    private var scheduler: Scheduler?
    private var speedTimer: Timer?
    private var lastRecordedBytes: [UUID: Int64] = [:]
    private var notifyPending = false
    private var lastNotifyTime: Date = .distantPast
    private let persistenceQueue = DispatchQueue(label: "dev.parth.merge.persistence", qos: .utility)

    public var onDownloadsChanged: (([DownloadItem]) -> Void)?

    public init(defaultDestination: URL? = nil, scheduler: Scheduler? = nil) {
        if let dest = defaultDestination {
            self.defaultDestination = dest
        } else {
            let downloadsFolder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            self.defaultDestination = downloadsFolder
        }
        self.scheduler = scheduler

        // Restore any paused / unfinished downloads from disk metadata
        restoreSavedDownloads()

        // Background speed calculation timer (runs on main runloop)
        DispatchQueue.main.async { [weak self] in
            self?.speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateSpeeds()
            }
        }
    }

    public func setScheduler(_ sched: Scheduler) {
        managerLock.lock()
        self.scheduler = sched
        managerLock.unlock()
    }

    public var allDownloads: [DownloadItem] {
        managerLock.lock()
        defer { managerLock.unlock() }
        return Array(downloads.values).sorted { $0.addedDate > $1.addedDate }
    }

    // MARK: - Download Management API

    @discardableResult
    public func addDownload(
        url: URL,
        destinationFolder: URL? = nil,
        customFilename: String? = nil,
        userAgent: String? = nil,
        referer: String? = nil,
        cookies: String? = nil,
        concurrency: Int? = nil,
        startImmediately: Bool = true
    ) -> DownloadItem {
        let dest = destinationFolder ?? defaultDestination
        let item = DownloadItem(
            url: url,
            filename: customFilename,
            destinationFolder: dest,
            userAgent: userAgent,
            referer: referer,
            cookies: cookies
        )

        managerLock.lock()
        downloads[item.id] = item
        managerLock.unlock()

        notifyChange()

        if startImmediately {
            startDownload(item, concurrency: concurrency ?? defaultConcurrency)
        }

        return item
    }

    public func pauseDownload(id: UUID) {
        managerLock.lock()
        guard let item = downloads[id] else {
            managerLock.unlock()
            return
        }
        item.status = .paused
        item.speedBytesPerSec = 0
        item.cancelTasks()
        saveMetadata(for: item)
        managerLock.unlock()

        notifyChange()
    }

    public func resumeDownload(id: UUID) {
        managerLock.lock()
        guard let item = downloads[id], item.status == .paused || item.status.title.hasPrefix("Failed") else {
            managerLock.unlock()
            return
        }
        item.status = .queued
        managerLock.unlock()

        startDownload(item, concurrency: defaultConcurrency)
    }

    public func cancelDownload(id: UUID) {
        pauseDownload(id: id)
        managerLock.lock()
        if let item = downloads[id] {
            item.status = .failed("Cancelled by user")
            try? FileManager.default.removeItem(at: item.partFileURL)
            try? FileManager.default.removeItem(at: item.metaFileURL)
        }
        managerLock.unlock()
        notifyChange()
    }

    public func deleteDownload(id: UUID, removeFile: Bool = false) {
        cancelDownload(id: id)
        managerLock.lock()
        if let item = downloads.removeValue(forKey: id) {
            if removeFile {
                try? FileManager.default.removeItem(at: item.destinationFileURL)
                try? FileManager.default.removeItem(at: item.partFileURL)
                try? FileManager.default.removeItem(at: item.metaFileURL)
            }
        }
        managerLock.unlock()
        saveHistory()
        notifyChange()
    }

    public func clearCompleted() {
        managerLock.lock()
        downloads = downloads.filter { $0.value.status != .completed }
        managerLock.unlock()
        saveHistory()
        notifyChange()
    }

    public func restartDownload(id: UUID) {
        managerLock.lock()
        guard let item = downloads[id] else {
            managerLock.unlock()
            return
        }
        item.cancelTasks()
        item.status = .queued
        item.downloadedBytes = 0
        item.chunks.removeAll()
        item.speedBytesPerSec = 0
        try? FileManager.default.removeItem(at: item.partFileURL)
        try? FileManager.default.removeItem(at: item.metaFileURL)
        managerLock.unlock()

        saveHistory()
        notifyChange()
        startDownload(item, concurrency: defaultConcurrency)
    }

    // MARK: - Download Execution

    private func startDownload(_ item: DownloadItem, concurrency: Int) {
        let task = Task { [weak self] in
            guard let self = self else { return }

            item.status = .probing
            self.notifyChange()

            do {
                // Step 1: Probe URL
                let probe = try await self.probe(item: item)
                item.totalBytes = probe.contentLength
                item.supportsRanges = probe.supportsRanges
                item.etag = probe.etag
                if let name = probe.suggestedFilename, !name.isEmpty, item.filename.hasPrefix("download_") {
                    item.filename = name
                }

                // If file is already completed
                if FileManager.default.fileExists(atPath: item.destinationFileURL.path) &&
                    item.totalBytes > 0 &&
                    (try? FileManager.default.attributesOfItem(atPath: item.destinationFileURL.path)[.size] as? Int64) == item.totalBytes {
                    item.status = .completed
                    item.downloadedBytes = item.totalBytes
                    self.notifyChange()
                    #if canImport(AppKit)
                    DispatchQueue.main.async {
                        NSSound(named: "Glass")?.play()
                    }
                    #endif
                    return
                }

                // Step 2: Plan Chunks if ranges supported and file > 1MB
                let isMultiChunk = item.supportsRanges && item.totalBytes > 1_048_576 && concurrency > 1

                if isMultiChunk {
                    do {
                        try await self.downloadParallel(item: item, concurrency: concurrency)
                    } catch {
                        if Task.isCancelled { return }
                        // If parallel downloading fails (e.g. rate-limiting, range failure, 503),
                        // seamlessly fall back to single-stream download!
                        item.chunks.removeAll()
                        item.downloadedBytes = 0
                        try await self.downloadSingle(item: item)
                    }
                } else {
                    try await self.downloadSingle(item: item)
                }

                // Step 3: Complete Download
                try self.finalizeDownload(item: item)
                item.status = .completed
                item.completionDate = Date()
                item.speedBytesPerSec = 0
                self.saveHistory()
                self.notifyChange()

                #if canImport(AppKit)
                DispatchQueue.main.async {
                    NSSound(named: "Glass")?.play()
                    NSApp?.requestUserAttention(.informationalRequest)
                }
                #endif

            } catch {
                if Task.isCancelled { return }
                item.status = .failed(error.localizedDescription)
                item.speedBytesPerSec = 0
                self.saveHistory()
                self.notifyChange()
            }
        }

        item.addTask(task)
    }

    // MARK: - Parallel Chunk Downloader

    private func downloadParallel(item: DownloadItem, concurrency: Int) async throws {
        // Prepare part file
        let partPath = item.partFileURL.path
        if !FileManager.default.fileExists(atPath: partPath) {
            FileManager.default.createFile(atPath: partPath, contents: nil)
            let handle = try FileHandle(forWritingTo: item.partFileURL)
            try handle.truncate(atOffset: UInt64(item.totalBytes))
            try handle.close()
        }

        // Initialize chunks if not already present
        if item.chunks.isEmpty {
            let total = item.totalBytes
            let chunkSize = total / Int64(concurrency)
            var newChunks: [ChunkState] = []

            for i in 0..<concurrency {
                let start = Int64(i) * chunkSize
                let end = (i == concurrency - 1) ? total - 1 : (start + chunkSize - 1)
                newChunks.append(ChunkState(
                    id: i,
                    startByte: start,
                    endByte: end,
                    downloadedBytes: 0,
                    assignedInterface: nil,
                    isCompleted: false
                ))
            }
            item.chunks = newChunks
            saveMetadata(for: item)
        }

        item.status = .downloading
        notifyChange()

        let chunkFileHandle = try FileHandle(forWritingTo: item.partFileURL)
        let chunkWriter = ChunkFileWriter(handle: chunkFileHandle)

        defer {
            try? chunkFileHandle.close()
        }

        // Available interfaces for load-balancing chunks
        let interfaces = getCandidateInterfaces()

        try await withThrowingTaskGroup(of: (Int, Int64).self) { group in
            for index in 0..<item.chunks.count {
                var chunk = item.chunks[index]
                if chunk.isCompleted { continue }

                // Assign interface round-robin across candidate physical adapters
                let iface = interfaces.isEmpty ? nil : interfaces[index % interfaces.count]
                chunk.assignedInterface = iface
                item.chunks[index] = chunk

                group.addTask {
                    let downloaded = try await self.downloadChunk(
                        item: item,
                        chunk: chunk,
                        writer: chunkWriter,
                        interfaceName: iface,
                        progressCallback: { _ in }
                    )
                    return (chunk.id, downloaded)
                }
            }

            for try await (chunkId, _) in group {
                item.markChunkCompleted(chunkId: chunkId)
                saveMetadata(for: item)
                notifyChange()
            }
        }
    }

    private func downloadChunk(
        item: DownloadItem,
        chunk: ChunkState,
        writer: ChunkFileWriter,
        interfaceName: String?,
        progressCallback: @escaping (Int64) -> Void
    ) async throws -> Int64 {
        var localChunk = chunk
        var attempts = 0
        let maxAttempts = 4
        var useProxy = true

        while localChunk.downloadedBytes < localChunk.totalBytes && attempts < maxAttempts {
            attempts += 1
            try Task.checkCancellation()

            let currentOffset = localChunk.startByte + localChunk.downloadedBytes
            guard currentOffset <= localChunk.endByte else { break }

            var request = URLRequest(url: item.url)
            request.setValue("bytes=\(currentOffset)-\(localChunk.endByte)", forHTTPHeaderField: "Range")
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let ua = item.userAgent ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
            request.setValue(ua, forHTTPHeaderField: "User-Agent")

            if let ref = item.referer, !ref.isEmpty {
                request.setValue(ref, forHTTPHeaderField: "Referer")
            }
            if let cookies = item.cookies, !cookies.isEmpty {
                request.setValue(cookies, forHTTPHeaderField: "Cookie")
            }

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 30
            config.timeoutIntervalForResource = 3600
            config.waitsForConnectivity = true

            if useProxy {
                var proxyDict: [String: Any] = [
                    kCFNetworkProxiesSOCKSEnable as String: 1,
                    kCFNetworkProxiesSOCKSProxy as String: "127.0.0.1",
                    kCFNetworkProxiesSOCKSPort as String: 1080
                ]
                if let iface = interfaceName, !iface.isEmpty {
                    proxyDict[kCFProxyUsernameKey as String] = iface
                    proxyDict[kCFProxyPasswordKey as String] = "merge"
                }
                config.connectionProxyDictionary = proxyDict
            } else {
                config.connectionProxyDictionary = [:]
            }

            do {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64, Error>) in
                    let delegate = ChunkDownloadDelegate(
                        startOffset: UInt64(currentOffset),
                        endOffset: UInt64(localChunk.endByte),
                        writer: writer,
                        progressCallback: { bytesCount in
                            localChunk.downloadedBytes += bytesCount
                            item.updateChunkProgress(
                                chunkId: localChunk.id,
                                chunkDownloaded: localChunk.downloadedBytes,
                                deltaBytes: bytesCount
                            )
                            progressCallback(bytesCount)
                        },
                        continuation: continuation
                    )

                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    let task = session.dataTask(with: request)
                    task.resume()
                }

                if localChunk.downloadedBytes >= localChunk.totalBytes {
                    break
                }
            } catch {
                if Task.isCancelled { throw error }
                if let dlErr = error as? DownloadError, case .serverRejectedRanges = dlErr {
                    throw dlErr
                }

                // If proxy failed, immediately switch to direct connection for subsequent attempts
                if useProxy {
                    useProxy = false
                }

                if attempts >= maxAttempts {
                    throw error
                }

                let backoffNanos = UInt64(attempts) * 400_000_000
                try? await Task.sleep(nanoseconds: backoffNanos)
            }
        }

        return localChunk.downloadedBytes
    }

    // MARK: - Single Stream Downloader (Fallback)

    private func downloadSingle(item: DownloadItem) async throws {
        item.status = .downloading
        notifyChange(force: true)

        var attempts = 0
        let maxAttempts = 4

        while (item.totalBytes <= 0 || item.downloadedBytes < item.totalBytes) && attempts < maxAttempts {
            attempts += 1
            try Task.checkCancellation()

            var request = URLRequest(url: item.url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            let ua = item.userAgent ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
            request.setValue(ua, forHTTPHeaderField: "User-Agent")

            if let ref = item.referer, !ref.isEmpty {
                request.setValue(ref, forHTTPHeaderField: "Referer")
            }
            if let cookies = item.cookies, !cookies.isEmpty {
                request.setValue(cookies, forHTTPHeaderField: "Cookie")
            }

            let isResuming = item.downloadedBytes > 0 && item.supportsRanges
            if isResuming {
                request.setValue("bytes=\(item.downloadedBytes)-", forHTTPHeaderField: "Range")
            }

            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 45
            config.timeoutIntervalForResource = 86400
            config.connectionProxyDictionary = [:]

            let partPath = item.partFileURL.path
            if !FileManager.default.fileExists(atPath: partPath) {
                FileManager.default.createFile(atPath: partPath, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: item.partFileURL)
            if !isResuming && attempts == 1 && item.downloadedBytes == 0 {
                try handle.truncate(atOffset: 0)
            }

            do {
                _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int64, Error>) in
                    let delegate = SingleStreamDownloadDelegate(
                        handle: handle,
                        isResuming: isResuming,
                        initialOffset: UInt64(item.downloadedBytes),
                        progressCallback: { bytesRead, totalBytes in
                            item.addDownloadedBytes(bytesRead)
                            if totalBytes > 0 && item.totalBytes <= 0 {
                                item.totalBytes = totalBytes
                            }
                        },
                        continuation: continuation
                    )

                    let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
                    let task = session.dataTask(with: request)
                    task.resume()
                }

                try? handle.close()

                if item.totalBytes > 0 && item.downloadedBytes >= item.totalBytes {
                    break
                }
                if item.totalBytes <= 0 {
                    break
                }
            } catch {
                try? handle.close()
                if Task.isCancelled { throw error }
                if attempts >= maxAttempts {
                    throw error
                }
                let backoff = UInt64(attempts) * 600_000_000
                try? await Task.sleep(nanoseconds: backoff)
            }
        }
    }

    private func finalizeDownload(item: DownloadItem) throws {
        let dest = item.destinationFileURL
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: item.partFileURL, to: dest)

        persistenceQueue.sync {
            try? FileManager.default.removeItem(at: item.metaFileURL)
            // Clean up any legacy .merge-meta.json file in the destination folder
            let legacyMeta = item.destinationFolder.appendingPathComponent("\(item.filename).merge-meta.json")
            try? FileManager.default.removeItem(at: legacyMeta)
        }
    }

    // MARK: - URL Probe

    public struct ProbeInfo {
        public var contentLength: Int64
        public var supportsRanges: Bool
        public var etag: String?
        public var suggestedFilename: String?
    }

    private func probe(item: DownloadItem) async throws -> ProbeInfo {
        let ua = item.userAgent ?? "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.connectionProxyDictionary = [:]
        let session = URLSession(configuration: config)

        var response: HTTPURLResponse?

        // Attempt 1: Standard HEAD request (clean, no Range header)
        var headReq = URLRequest(url: item.url)
        headReq.httpMethod = "HEAD"
        headReq.setValue(ua, forHTTPHeaderField: "User-Agent")
        headReq.setValue("*/*", forHTTPHeaderField: "Accept")
        headReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        if let ref = item.referer, !ref.isEmpty {
            headReq.setValue(ref, forHTTPHeaderField: "Referer")
        }
        if let cookies = item.cookies, !cookies.isEmpty {
            headReq.setValue(cookies, forHTTPHeaderField: "Cookie")
        }

        do {
            let (_, res) = try await session.data(for: headReq)
            if let httpRes = res as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                response = httpRes
            }
        } catch {
            // HEAD failed or rejected, fall through to GET probe
        }

        // Attempt 2: GET with bytes=0-0 to inspect headers without buffering body
        if response == nil {
            var getReq = URLRequest(url: item.url)
            getReq.httpMethod = "GET"
            getReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            getReq.setValue(ua, forHTTPHeaderField: "User-Agent")
            getReq.setValue("*/*", forHTTPHeaderField: "Accept")
            getReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            if let ref = item.referer, !ref.isEmpty {
                getReq.setValue(ref, forHTTPHeaderField: "Referer")
            }
            if let cookies = item.cookies, !cookies.isEmpty {
                getReq.setValue(cookies, forHTTPHeaderField: "Cookie")
            }

            do {
                let (_, res) = try await session.data(for: getReq)
                if let httpRes = res as? HTTPURLResponse {
                    response = httpRes
                }
            } catch {
                // If bytes probe failed, retry once more with plain request
                if let (_, res) = try? await session.data(for: headReq), let httpRes = res as? HTTPURLResponse {
                    response = httpRes
                }
            }
        }

        guard let http = response else {
            return ProbeInfo(contentLength: -1, supportsRanges: false)
        }

        if http.statusCode == 403 || http.statusCode == 410 {
            let msg = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw DownloadError.httpError(statusCode: http.statusCode, message: "Download link expired or unauthorized (\(msg)). Please copy a fresh link.")
        }

        var len: Int64 = -1
        if let cl = http.value(forHTTPHeaderField: "Content-Length"), let parsed = Int64(cl) {
            len = parsed
        }
        if let cr = http.value(forHTTPHeaderField: "Content-Range") {
            if let totalStr = cr.components(separatedBy: "/").last, let total = Int64(totalStr) {
                len = total
            }
        }

        // Range support detection:
        // Must verify that server actually serves HTTP 206 Partial Content when requested,
        // because some servers advertise Accept-Ranges: bytes but ignore Range headers.
        var supportsRanges = (http.statusCode == 206)
        if !supportsRanges && (http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") ?? false) {
            var rangeCheck = URLRequest(url: item.url)
            rangeCheck.httpMethod = "GET"
            rangeCheck.setValue("bytes=0-0", forHTTPHeaderField: "Range")
            rangeCheck.setValue(ua, forHTTPHeaderField: "User-Agent")
            rangeCheck.setValue("*/*", forHTTPHeaderField: "Accept")
            rangeCheck.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            if let ref = item.referer, !ref.isEmpty { rangeCheck.setValue(ref, forHTTPHeaderField: "Referer") }
            if let cookies = item.cookies, !cookies.isEmpty { rangeCheck.setValue(cookies, forHTTPHeaderField: "Cookie") }

            if let (_, rangeRes) = try? await session.data(for: rangeCheck),
               let rangeHttp = rangeRes as? HTTPURLResponse, rangeHttp.statusCode == 206 {
                supportsRanges = true
            }
        }

        let etag = http.value(forHTTPHeaderField: "ETag")

        var filename: String? = nil
        if let cd = http.value(forHTTPHeaderField: "Content-Disposition") {
            if let match = cd.range(of: "filename=\"([^\"]+)\"", options: .regularExpression) {
                let sub = cd[match]
                filename = sub.replacingOccurrences(of: "filename=", with: "").replacingOccurrences(of: "\"", with: "")
            } else if let match = cd.range(of: "filename=([^;]+)", options: .regularExpression) {
                let sub = cd[match]
                filename = sub.replacingOccurrences(of: "filename=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ProbeInfo(
            contentLength: len,
            supportsRanges: supportsRanges,
            etag: etag,
            suggestedFilename: filename
        )
    }

    private func probe(url: URL) async throws -> ProbeInfo {
        let tempItem = DownloadItem(url: url, destinationFolder: defaultDestination)
        return try await probe(item: tempItem)
    }

    // MARK: - State Persistence & Speed Calculation

    private func saveMetadata(for item: DownloadItem) {
        guard item.status != .completed else { return }
        let meta = DownloadMeta(
            id: item.id,
            url: item.url,
            filename: item.filename,
            destinationPath: item.destinationFolder.path,
            totalBytes: item.totalBytes,
            etag: item.etag,
            chunks: item.chunks,
            supportsRanges: item.supportsRanges
        )
        persistenceQueue.async {
            guard item.status != .completed else { return }
            if let data = try? JSONEncoder().encode(meta) {
                try? data.write(to: item.metaFileURL, options: .atomic)
            }
        }
    }

    private var historyFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let netwichDir = appSupport.appendingPathComponent("Netwich", isDirectory: true)
        let legacyMergeDir = appSupport.appendingPathComponent("Merge", isDirectory: true)
        let legacyHistory = legacyMergeDir.appendingPathComponent("downloads_history.json")
        let netwichHistory = netwichDir.appendingPathComponent("downloads_history.json")

        try? FileManager.default.createDirectory(at: netwichDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: legacyHistory.path) && !FileManager.default.fileExists(atPath: netwichHistory.path) {
            try? FileManager.default.copyItem(at: legacyHistory, to: netwichHistory)
        }
        return netwichHistory
    }

    public func saveHistory() {
        managerLock.lock()
        let records = downloads.values.map { item -> DownloadRecord in
            DownloadRecord(
                id: item.id,
                url: item.url,
                filename: item.filename,
                destinationFolder: item.destinationFolder.path,
                totalBytes: item.totalBytes,
                downloadedBytes: item.downloadedBytes,
                statusTitle: item.status.title,
                isCompleted: item.status == .completed,
                addedDate: item.addedDate,
                completionDate: item.completionDate,
                chunks: item.chunks
            )
        }
        managerLock.unlock()

        let fileURL = historyFileURL
        persistenceQueue.async {
            if let data = try? JSONEncoder().encode(records) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func restoreSavedDownloads() {
        // Load from centralized history file first
        if let data = try? Data(contentsOf: historyFileURL),
           let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
            managerLock.lock()
            for record in records {
                let folder = URL(fileURLWithPath: record.destinationFolder)
                let item = DownloadItem(id: record.id, url: record.url, filename: record.filename, destinationFolder: folder)
                item.totalBytes = record.totalBytes
                item.downloadedBytes = record.downloadedBytes
                item.addedDate = record.addedDate
                item.completionDate = record.completionDate
                item.chunks = record.chunks
                if record.isCompleted {
                    item.status = .completed
                } else {
                    item.status = .paused
                }
                downloads[item.id] = item
            }
            managerLock.unlock()
            return
        }

        // Fallback: check destination directory for .merge-meta.json
        guard let files = try? FileManager.default.contentsOfDirectory(at: defaultDestination, includingPropertiesForKeys: nil) else {
            return
        }

        for file in files where file.pathExtension == "json" && file.lastPathComponent.contains(".merge-meta") {
            if let data = try? Data(contentsOf: file),
               let meta = try? JSONDecoder().decode(DownloadMeta.self, from: data) {
                let folder = URL(fileURLWithPath: meta.destinationPath)
                let item = DownloadItem(id: meta.id, url: meta.url, filename: meta.filename, destinationFolder: folder)
                item.totalBytes = meta.totalBytes
                item.etag = meta.etag
                item.supportsRanges = meta.supportsRanges
                item.chunks = meta.chunks

                // If final destination file exists and no part file remains, clean up the stale meta file
                if FileManager.default.fileExists(atPath: item.destinationFileURL.path) &&
                   !FileManager.default.fileExists(atPath: item.partFileURL.path) {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }

                item.status = .paused
                item.downloadedBytes = meta.chunks.reduce(0) { $0 + $1.downloadedBytes }

                managerLock.lock()
                downloads[item.id] = item
                managerLock.unlock()
            }
        }
    }

    private func updateSpeeds() {
        managerLock.lock()
        for item in downloads.values {
            if item.status == .downloading {
                let previous = lastRecordedBytes[item.id] ?? 0
                let current = item.downloadedBytes
                let delta = max(0, current - previous)
                item.speedBytesPerSec = Double(delta)
                lastRecordedBytes[item.id] = current
            } else {
                item.speedBytesPerSec = 0
            }
        }
        managerLock.unlock()
        notifyChange()
    }

    private func getCandidateInterfaces() -> [String] {
        if let sched = scheduler {
            let active = sched.snapshot()
                .filter { $0.tier > .down && $0.isEnabled }
                .map { $0.id.name }
            if !active.isEmpty {
                return active
            }
        }

        let addresses = InterfaceScanner.scan()
        return addresses
            .filter { name, entry in
                !InterfaceScanner.isVirtual(name) && InterfaceScanner.hasRoutableAddress(entry)
            }
            .map { $0.key }
            .sorted()
    }

    private func notifyChange(force: Bool = false) {
        managerLock.lock()
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNotifyTime)

        if force || elapsed >= 0.25 {
            lastNotifyTime = now
            notifyPending = false
            let items = Array(downloads.values).sorted { $0.addedDate > $1.addedDate }
            managerLock.unlock()

            DispatchQueue.main.async { [weak self] in
                self?.onDownloadsChanged?(items)
            }
        } else {
            if !notifyPending {
                notifyPending = true
                managerLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.notifyChange(force: true)
                }
            } else {
                managerLock.unlock()
            }
        }
    }
}
