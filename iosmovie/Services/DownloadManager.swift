import Foundation
import CryptoSwift

// MARK: - 持久化记录

struct DownloadTaskRecord: Codable {
    var id: String
    var title: String
    var episodeName: String
    var sourceURL: String
    var folderID: String
    var status: DownloadStatus
    var progress: Double
    var completedSegments: Int
    var totalSegments: Int
    var totalBytes: Int64
    var downloadedBytes: Int64
    var errorMessage: String?
}

/// 每个下载目录内的信息文件，用于重启后还原标题/剧集
struct DownloadedInfo: Codable {
    let title: String
    let episodeName: String
    let format: String
    let completedAt: Date
}

// MARK: - 引擎回调

struct DownloadProgress: Sendable {
    var completedSegments: Int
    var totalSegments: Int
    var downloadedBytes: Int64
    var estimatedTotalBytes: Int64
}

struct DownloadOutput: Sendable {
    let fileURL: URL
    let fileSize: Int64
    /// "ts" 或 "mp4"，由播放列表内容决定
    let format: String
}

enum DownloadFailure: Error, Sendable {
    case cancelled
    case message(String)

    var message: String {
        switch self {
        case .cancelled: return "已取消"
        case .message(let text): return text
        }
    }
}

// MARK: - 任务状态持久化

final class DownloadStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.iosmovie.download-store")

    init(directory: URL) {
        fileURL = directory.appendingPathComponent("download_state.json")
    }

    func load() -> [DownloadTaskRecord] {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let records = try? JSONDecoder().decode([DownloadTaskRecord].self, from: data) else {
                return []
            }
            return records
        }
    }

    func save(_ records: [DownloadTaskRecord]) {
        queue.async { [fileURL] in
            guard let data = try? JSONEncoder().encode(records) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - 全局并发闸门（轮询实现，取消时不会挂起）

actor DownloadThrottle {
    private var active = 0
    private let limit: Int

    init(limit: Int) {
        self.limit = max(limit, 1)
    }

    func acquire() async throws {
        while active >= limit {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        active += 1
    }

    func release() {
        active = max(active - 1, 0)
    }
}

// MARK: - 下载引擎

actor DownloadEngine {
    private let session: URLSession
    private let throttle = DownloadThrottle(limit: 4)
    private var keyCache: [String: [UInt8]] = [:]

    /// 单个任务内的分片并发数
    private let batchSize = 3
    /// 单个分片重试次数
    private let maxAttempts = 3

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.httpMaximumConnectionsPerHost = 4
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
    }

    // MARK: - 入口

    func run(
        folder: URL,
        sourceURL: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async -> Result<DownloadOutput, DownloadFailure> {
        do {
            let output = try await perform(folder: folder, sourceURL: sourceURL, progress: progress)
            return .success(output)
        } catch {
            return .failure(Self.wrap(error))
        }
    }

    private static func wrap(_ error: Error) -> DownloadFailure {
        if error is CancellationError { return .cancelled }
        if let failure = error as? DownloadFailure { return failure }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        return .message(error.localizedDescription)
    }

    // MARK: - 主流程

    private func perform(
        folder: URL,
        sourceURL: URL,
        progress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> DownloadOutput {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        Self.removePartFiles(in: folder)

        let playlist = try await M3U8Parser.resolve(
            from: sourceURL,
            fetcher: M3U8HTTPFetcher(session: session)
        )

        let items = Self.items(for: playlist)
        guard !items.isEmpty else { throw DownloadFailure.message("播放列表中没有视频分片") }

        let existing = Self.existingItems(in: folder, items: items)
        var completed = existing.count
        var downloadedBytes = Self.totalSize(of: existing, in: folder)

        progress(DownloadProgress(
            completedSegments: completed,
            totalSegments: items.count,
            downloadedBytes: downloadedBytes,
            estimatedTotalBytes: downloadedBytes
        ))

        try Task.checkCancellation()

        let pending = items.filter { !existing.contains($0.fileName) }
        var cursor = 0

        while cursor < pending.count {
            try Task.checkCancellation()
            let end = min(cursor + batchSize, pending.count)
            let batch = Array(pending[cursor..<end])

            try await withThrowingTaskGroup(
                of: Result<(String, Int64), Error>?.self
            ) { group in
                for item in batch {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        do {
                            try await self.throttle.acquire()
                        } catch {
                            return .failure(error)
                        }
                        do {
                            let bytes = try await self.downloadItem(item, folder: folder)
                            await self.throttle.release()
                            return .success((item.fileName, bytes))
                        } catch {
                            await self.throttle.release()
                            return .failure(error)
                        }
                    }
                }

                for try await result in group {
                    guard let result else { continue }
                    switch result {
                    case .success(let (_, bytes)):
                        completed += 1
                        downloadedBytes += bytes
                        let average = downloadedBytes / Int64(max(completed, 1))
                        let remaining = Int64(items.count - completed)
                        progress(DownloadProgress(
                            completedSegments: completed,
                            totalSegments: items.count,
                            downloadedBytes: downloadedBytes,
                            estimatedTotalBytes: downloadedBytes + remaining * average
                        ))
                    case .failure(let error):
                        group.cancelAll()
                        throw Self.wrap(error)
                    }
                }
            }

            cursor = end
        }

        let merged = try merge(folder: folder, playlist: playlist)
        return DownloadOutput(fileURL: merged.url, fileSize: merged.size, format: merged.format)
    }

    // MARK: - 单个分片下载（含重试）

    private func downloadItem(_ item: DownloadItem, folder: URL) async throws -> Int64 {
        let destination = folder.appendingPathComponent(item.fileName)
        let temporary = folder.appendingPathComponent(item.fileName + ".part")

        var attempt = 0
        while true {
            try Task.checkCancellation()
            do {
                let bytes = try await fetchAndStore(item, to: temporary)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                return bytes
            } catch {
                let failure = Self.wrap(error)
                if case .cancelled = failure { throw failure }
                attempt += 1
                if attempt >= maxAttempts { throw failure }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
            }
        }
    }

    private func fetchAndStore(_ item: DownloadItem, to temporary: URL) async throws -> Int64 {
        var request = URLRequest(url: item.url)
        request.timeoutInterval = 30
        for (field, value) in MovieRequestHeaders.headers(for: item.url) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (tempURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DownloadFailure.message("分片下载失败（HTTP \(code)）")
        }

        guard let raw = try? Data(contentsOf: tempURL), !raw.isEmpty else {
            throw DownloadFailure.message("分片内容为空")
        }

        var payload = raw

        // 1. 字节范围切片（加密在切片之后进行）
        if let length = item.byteRangeLength {
            let offset = item.byteRangeOffset ?? 0
            let start = Int(min(max(offset, 0), Int64(raw.count)))
            let end = Int(min(offset + length, Int64(raw.count)))
            guard end > start else { throw DownloadFailure.message("分片字节范围无效") }
            payload = raw.subdata(in: start..<end)
        }

        // 2. AES-128 解密（HLS 使用 PKCS#7 填充）
        if let keyURL = item.keyURL {
            guard payload.count % 16 == 0 else {
                throw DownloadFailure.message("加密分片长度异常")
            }
            let key = try await cachedKey(for: keyURL)
            let iv = item.iv ?? M3U8Parser.defaultIV(for: item.sequenceNumber)
            do {
                let aes = try AES(key: key, blockMode: CBC(iv: iv), padding: .pkcs7)
                let decrypted = try aes.decrypt([UInt8](payload))
                payload = Data(decrypted)
            } catch {
                throw DownloadFailure.message("分片解密失败（密钥或 IV 不匹配）")
            }
        }

        guard !payload.isEmpty else { throw DownloadFailure.message("分片内容为空") }

        try? FileManager.default.removeItem(at: temporary)
        try payload.write(to: temporary)
        return Int64(payload.count)
    }

    private func cachedKey(for urlString: String) async throws -> [UInt8] {
        if let cached = keyCache[urlString] { return cached }
        guard let url = URL(string: urlString) else {
            throw DownloadFailure.message("密钥地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (field, value) in MovieRequestHeaders.headers(for: url) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw DownloadFailure.message("密钥下载失败（HTTP \(code)）")
        }
        guard data.count == 16 else {
            throw DownloadFailure.message("密钥长度不是 16 字节")
        }
        let bytes = [UInt8](data)
        keyCache[urlString] = bytes
        return bytes
    }

    // MARK: - 合并

    private func merge(folder: URL, playlist: M3U8Playlist) throws -> (url: URL, size: Int64, format: String) {
        let isFragmentedMP4 = playlist.isFragmentedMP4
        let fileName = isFragmentedMP4 ? "movie.mp4" : "movie.ts"
        let outputURL = folder.appendingPathComponent(fileName)
        let partURL = folder.appendingPathComponent(fileName + ".part")

        try? FileManager.default.removeItem(at: partURL)
        guard FileManager.default.createFile(atPath: partURL.path, contents: nil) else {
            throw DownloadFailure.message("无法创建输出文件")
        }

        let handle = try FileHandle(forWritingTo: partURL)
        var total: Int64 = 0
        let chunkSize = 1024 * 1024

        func append(_ url: URL) throws {
            guard let input = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? input.close() }
            while true {
                guard let data = try? input.read(upToCount: chunkSize) else { break }
                if data.isEmpty { break }
                try handle.write(contentsOf: data)
                total += Int64(data.count)
            }
        }

        do {
            // items(for:) 已保证 seg_init 在最前，随后按序追加各分片
            for item in Self.items(for: playlist) {
                try Task.checkCancellation()
                try append(folder.appendingPathComponent(item.fileName))
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: partURL)
            throw error
        }

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: partURL, to: outputURL)

        // 合并成功后清理分片，释放空间
        for item in Self.items(for: playlist) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(item.fileName))
        }

        return (outputURL, total, isFragmentedMP4 ? "mp4" : "ts")
    }

    // MARK: - 播放列表 → 下载项

    private struct DownloadItem {
        let fileName: String
        let url: URL
        let keyURL: String?
        let iv: [UInt8]?
        let byteRangeLength: Int64?
        let byteRangeOffset: Int64?
        let sequenceNumber: Int
    }

    private static func items(for playlist: M3U8Playlist) -> [DownloadItem] {
        var result: [DownloadItem] = []
        if let initSegment = playlist.initSegment {
            result.append(DownloadItem(
                fileName: "seg_init",
                url: initSegment.url,
                keyURL: initSegment.keyURL,
                iv: initSegment.iv,
                byteRangeLength: initSegment.byteRangeLength,
                byteRangeOffset: initSegment.byteRangeOffset,
                sequenceNumber: 0
            ))
        }
        for segment in playlist.segments {
            result.append(DownloadItem(
                fileName: String(format: "seg_%06d", segment.index),
                url: segment.url,
                keyURL: segment.keyURL,
                iv: segment.iv,
                byteRangeLength: segment.byteRangeLength,
                byteRangeOffset: segment.byteRangeOffset,
                sequenceNumber: segment.sequenceNumber
            ))
        }
        return result
    }

    private static func existingItems(in folder: URL, items: [DownloadItem]) -> Set<String> {
        var result: Set<String> = []
        for item in items {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(item.fileName).path) {
                result.insert(item.fileName)
            }
        }
        return result
    }

    private static func totalSize(of fileNames: Set<String>, in folder: URL) -> Int64 {
        var total: Int64 = 0
        for name in fileNames {
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: folder.appendingPathComponent(name).path
            )
            total += (attributes?[.size] as? Int64) ?? 0
        }
        return total
    }

    private static func removePartFiles(in folder: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.pathExtension == "part" {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// MARK: - 对外门面（UI 只与这一层交互）

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloadedMovies: [DownloadedMovie] = []
    @Published var tasks: [DownloadTask] = []
    @Published var showAlert = false
    @Published var alertMessage = ""

    private let metadataKey = "downloaded_movies_metadata"
    private let downloadsDir: URL
    private let store: DownloadStore
    private let engine: DownloadEngine
    private var taskHandles: [String: Task<Void, Never>] = [:]

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadsDir = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        store = DownloadStore(directory: downloadsDir)
        engine = DownloadEngine()
        loadTasks()
        loadMetadata()
    }

    // MARK: - 创建任务

    func startDownloads(items: [(title: String, episodeName: String, sourceURL: String)]) {
        guard !items.isEmpty else { return }

        var created = 0
        var skipped = 0

        for item in items {
            let folderID = Self.folderID(title: item.title, episodeName: item.episodeName)

            // 同一集不重复下载
            if tasks.contains(where: { $0.folderID == folderID }) {
                skipped += 1
                continue
            }
            if downloadedMovies.contains(where: { $0.folderID == folderID }) {
                skipped += 1
                continue
            }

            let task = DownloadTask(
                id: UUID().uuidString,
                title: item.title,
                episodeName: item.episodeName,
                sourceURL: item.sourceURL,
                folderID: folderID,
                progress: 0,
                status: .downloading
            )
            tasks.insert(task, at: 0)
            created += 1
            launch(task)
        }

        persistTasks()

        if created > 0 {
            alertMessage = skipped > 0
                ? "已创建 \(created) 个下载任务，\(skipped) 个已在列表中"
                : "已创建 \(created) 个下载任务"
            showAlert = true
        } else if skipped > 0 {
            alertMessage = "所选剧集已在下载列表或已完成"
            showAlert = true
        }
    }

    // MARK: - 暂停 / 继续 / 取消 / 重试

    func pauseTask(_ task: DownloadTask) {
        guard task.status == .downloading else { return }
        taskHandles[task.id]?.cancel()
        taskHandles[task.id] = nil
        update(task.id) { $0.status = .paused }
        persistTasks()
    }

    func resumeTask(_ task: DownloadTask) {
        guard task.status == .paused || task.status == .failed else { return }
        update(task.id) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        persistTasks()
        guard let refreshed = tasks.first(where: { $0.id == task.id }) else { return }
        launch(refreshed)
    }

    func cancelTask(_ task: DownloadTask) {
        taskHandles[task.id]?.cancel()
        taskHandles[task.id] = nil
        let folder = downloadsDir.appendingPathComponent(task.folderID, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        tasks.removeAll { $0.id == task.id }
        persistTasks()
    }

    /// 重试会保留已下载完成的分片，只补缺失部分
    func retryTask(_ task: DownloadTask) {
        resumeTask(task)
    }

    func deleteTask(_ task: DownloadTask) {
        cancelTask(task)
    }

    func pauseAllTasks() {
        for task in tasks where task.status == .downloading {
            pauseTask(task)
        }
    }

    func resumeAllTasks() {
        for task in tasks where task.status == .paused {
            resumeTask(task)
        }
    }

    // MARK: - 任务执行

    private func launch(_ task: DownloadTask) {
        taskHandles[task.id]?.cancel()
        let handle = Task { [weak self] in
            guard let self else { return }
            await self.execute(taskID: task.id)
        }
        taskHandles[task.id] = handle
    }

    private func execute(taskID: String) async {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return }

        guard let sourceURL = URL(string: task.sourceURL) else {
            fail(taskID, message: "播放地址无效")
            return
        }

        let folder = downloadsDir.appendingPathComponent(task.folderID, isDirectory: true)

        let result = await engine.run(folder: folder, sourceURL: sourceURL) { progress in
            // DownloadManager 是 @MainActor 单例，本身即可跨线程传递
            Task { @MainActor in
                self.applyProgress(progress, taskID: taskID)
            }
        }

        switch result {
        case .success(let output):
            complete(taskID: taskID, folder: folder, output: output)
        case .failure(let failure):
            if case .cancelled = failure {
                update(taskID) { $0.status = .paused }
            } else {
                fail(taskID, message: failure.message)
            }
            taskHandles[taskID] = nil
            persistTasks()
        }
    }

    private func applyProgress(_ progress: DownloadProgress, taskID: String) {
        update(taskID) {
            $0.completedSegments = progress.completedSegments
            $0.totalSegments = progress.totalSegments
            $0.downloadedBytes = progress.downloadedBytes
            $0.totalBytes = progress.estimatedTotalBytes
            $0.progress = progress.totalSegments > 0
                ? Double(progress.completedSegments) / Double(progress.totalSegments)
                : 0
        }
    }

    private func complete(taskID: String, folder: URL, output: DownloadOutput) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[index]

        let info = DownloadedInfo(
            title: task.title,
            episodeName: task.episodeName,
            format: output.format,
            completedAt: Date()
        )
        if let data = try? JSONEncoder().encode(info) {
            try? data.write(to: folder.appendingPathComponent("info.json"))
        }

        let movie = DownloadedMovie(
            id: UUID().uuidString,
            title: task.title,
            episodeName: task.episodeName,
            fileURL: output.fileURL.path,
            fileSize: output.fileSize,
            downloadDate: Date(),
            folderID: task.folderID,
            format: output.format
        )
        downloadedMovies.insert(movie, at: 0)
        tasks.remove(at: index)
        taskHandles[taskID] = nil
        persistMetadata()
        persistTasks()
    }

    private func fail(_ taskID: String, message: String) {
        update(taskID) {
            $0.status = .failed
            $0.errorMessage = message
        }
        taskHandles[taskID] = nil
        persistTasks()
    }

    private func update(_ taskID: String, _ mutate: (inout DownloadTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        mutate(&tasks[index])
    }

    // MARK: - 已下载列表

    func scanDownloadsDirectory() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: downloadsDir,
            includingPropertiesForKeys: nil
        ) else { return }

        var discovered: [DownloadedMovie] = []
        var knownFolders = Set(downloadedMovies.map { $0.folderID })

        for folder in contents {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let folderID = folder.lastPathComponent
            guard !knownFolders.contains(folderID) else { continue }

            var title = ""
            var episodeName = ""
            var format = ""
            var date = Date()

            if let data = try? Data(contentsOf: folder.appendingPathComponent("info.json")),
               let info = try? JSONDecoder().decode(DownloadedInfo.self, from: data) {
                title = info.title
                episodeName = info.episodeName
                format = info.format
                date = info.completedAt
            } else {
                // 兼容旧目录命名：标题_剧集
                let parts = folderID.split(separator: "_", maxSplits: 1).map(String.init)
                title = parts.first ?? folderID
                episodeName = parts.count > 1 ? parts[1] : ""
            }

            let candidates = ["movie.ts", "movie.mp4", "output.mp4"]
            let foundURL: URL? = candidates
                .map { folder.appendingPathComponent($0) }
                .first { fileManager.fileExists(atPath: $0.path) }
            guard let movieURL = foundURL else { continue }

            if format.isEmpty {
                format = movieURL.pathExtension
            }

            let attributes: [FileAttributeKey: Any]? = try? fileManager.attributesOfItem(atPath: movieURL.path)
            let size = (attributes?[.size] as? Int64) ?? 0
            if let modificationDate = attributes?[.modificationDate] as? Date {
                date = modificationDate
            }

            let movie = DownloadedMovie(
                id: UUID().uuidString,
                title: title,
                episodeName: episodeName,
                fileURL: movieURL.path,
                fileSize: size,
                downloadDate: date,
                folderID: folderID,
                format: format
            )
            discovered.append(movie)
            knownFolders.insert(folderID)
        }

        if !discovered.isEmpty {
            downloadedMovies.insert(contentsOf: discovered, at: 0)
            persistMetadata()
        }
    }

    func deleteMovie(_ movie: DownloadedMovie) {
        let folder: URL
        if !movie.folderID.isEmpty {
            folder = downloadsDir.appendingPathComponent(movie.folderID, isDirectory: true)
        } else {
            folder = URL(fileURLWithPath: movie.fileURL).deletingLastPathComponent()
        }
        try? FileManager.default.removeItem(at: folder)

        downloadedMovies.removeAll { $0.id == movie.id }
        persistMetadata()
    }

    // MARK: - 持久化

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(downloadedMovies) {
            UserDefaults.standard.set(data, forKey: metadataKey)
        }
    }

    private func loadMetadata() {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let movies = try? JSONDecoder().decode([DownloadedMovie].self, from: data) else { return }
        downloadedMovies = movies.filter { FileManager.default.fileExists(atPath: $0.fileURL) }
    }

    private func persistTasks() {
        let records = tasks.map { task in
            DownloadTaskRecord(
                id: task.id,
                title: task.title,
                episodeName: task.episodeName,
                sourceURL: task.sourceURL,
                folderID: task.folderID,
                status: task.status,
                progress: task.progress,
                completedSegments: task.completedSegments,
                totalSegments: task.totalSegments,
                totalBytes: task.totalBytes,
                downloadedBytes: task.downloadedBytes,
                errorMessage: task.errorMessage
            )
        }
        store.save(records)
    }

    private func loadTasks() {
        let records = store.load()
        tasks = records.map { record in
            DownloadTask(
                id: record.id,
                title: record.title,
                episodeName: record.episodeName,
                sourceURL: record.sourceURL,
                folderID: record.folderID,
                progress: record.progress,
                // 被杀掉的"下载中"任务恢复为暂停，用户可手动继续
                status: record.status == .downloading ? .paused : record.status,
                completedSegments: record.completedSegments,
                totalSegments: record.totalSegments,
                totalBytes: record.totalBytes,
                downloadedBytes: record.downloadedBytes,
                errorMessage: record.errorMessage
            )
        }
        // 目录已被删掉的任务直接丢弃
        tasks.removeAll { task in
            !FileManager.default.fileExists(
                atPath: downloadsDir.appendingPathComponent(task.folderID, isDirectory: true).path
            )
        }
    }

    // MARK: - 目录名

    /// 可读前缀 + 稳定哈希，避免标题中的下划线/特殊字符导致同名或超长
    static func folderID(title: String, episodeName: String) -> String {
        let raw = "\(title)|\(episodeName)"
        let prefix = safeFileName("\(title)-\(episodeName)")
        let trimmed = prefix.count > 40 ? String(prefix.prefix(40)) : prefix
        return "\(trimmed)_\(stableHash(raw))"
    }

    private static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
            .union(.whitespacesAndNewlines)
            .union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// FNV-1a，跨进程稳定（String.hashValue 每次启动都不同）
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return String(hash, radix: 36)
    }
}
