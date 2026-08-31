import Foundation
import CryptoSwift

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloadedMovies: [DownloadedMovie] = []
    @Published var tasks: [DownloadTask] = []
    @Published var showAlert = false
    @Published var alertMessage = ""

    private let metadataKey = "downloaded_movies_metadata"
    private let downloadsDir: URL
    private var taskHandles: [String: Task<Void, Never>] = [:]

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadsDir = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    // MARK: - 创建任务

    func startDownloads(items: [(title: String, episodeName: String, sourceURL: String)]) {
        guard !items.isEmpty else { return }

        for item in items {
            let task = DownloadTask(
                id: UUID().uuidString,
                title: item.title,
                episodeName: item.episodeName,
                sourceURL: item.sourceURL,
                progress: 0,
                status: .downloading
            )
            tasks.insert(task, at: 0)
            startProcess(for: task.id)
        }

        alertMessage = "已创建 \(items.count) 个下载任务"
        showAlert = true
    }

    // MARK: - 暂停 / 继续 / 取消 / 重试

    func pauseTask(_ task: DownloadTask) {
        guard task.status == .downloading else { return }
        setStatus(.paused, for: task.id)
        taskHandles[task.id]?.cancel()
        taskHandles[task.id] = nil
    }

    func resumeTask(_ task: DownloadTask) {
        guard task.status == .paused else { return }
        setStatus(.downloading, for: task.id)
        startProcess(for: task.id)
    }

    func cancelTask(_ task: DownloadTask) {
        taskHandles[task.id]?.cancel()
        taskHandles[task.id] = nil

        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            let t = tasks[index]
            let folderURL = folderURL(title: t.title, episodeName: t.episodeName)
            try? FileManager.default.removeItem(at: folderURL)
            tasks.remove(at: index)
        }
    }

    func retryTask(_ task: DownloadTask) {
        guard task.status == .failed else { return }
        setStatus(.downloading, for: task.id)
        setProgress(0, for: task.id)
        setCompletedSegments(0, for: task.id)
        setTotalBytes(0, for: task.id)
        setDownloadedBytes(0, for: task.id)
        startProcess(for: task.id)
    }

    func deleteTask(_ task: DownloadTask) {
        cancelTask(task)
    }

    // MARK: - 下载流程

    private func startProcess(for taskID: String) {
        let handle = Task { [weak self] in
            guard let self else { return }
            await self.processDownload(taskID: taskID)
        }
        taskHandles[taskID] = handle
    }

    private func processDownload(taskID: String) async {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[index]

        do {
            let localM3U8URL = try await downloadM3U8(taskID: taskID) { [weak self] progress, downloadedBytes, totalBytes in
                self?.setProgress(progress, for: taskID)
                self?.setDownloadedBytes(downloadedBytes, for: taskID)
                self?.setTotalBytes(totalBytes, for: taskID)
            }

            try Task.checkCancellation()

            // 计算总大小：整个文件夹所有 TS 的总和
            let folderURL = localM3U8URL.deletingLastPathComponent()
            let totalSize = Self.folderSize(at: folderURL)

            let movie = DownloadedMovie(
                id: UUID().uuidString,
                title: task.title,
                episodeName: task.episodeName,
                fileURL: localM3U8URL.path,
                fileSize: totalSize,
                downloadDate: Date()
            )

            downloadedMovies.insert(movie, at: 0)
            persistMetadata()
            setStatus(.completed, for: taskID)
            setProgress(1, for: taskID)
            taskHandles[taskID] = nil
        } catch is CancellationError {
            taskHandles[taskID] = nil
        } catch {
            setStatus(.failed, for: taskID)
            taskHandles[taskID] = nil
        }
    }

    // MARK: - m3u8 + TS 下载（AES-128 解密 + 断点续传 + 嵌套 m3u8）

    private func downloadM3U8(
        taskID: String,
        progressHandler: @escaping (Double, Int64, Int64) -> Void
    ) async throws -> URL {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw URLError(.cancelled)
        }
        let task = tasks[index]

        guard let sourceURL = URL(string: task.sourceURL) else { throw URLError(.badURL) }

        let folderURL = folderURL(title: task.title, episodeName: task.episodeName)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // 1. 解析嵌套 m3u8
        let resolved = try await resolveEffectiveM3U8(from: sourceURL, taskID: taskID)
        let m3u8Text = resolved.text
        let effectiveBaseURL = resolved.baseURL

        // 2. 解析 AES-128 密钥（如果有）
        let encInfo = try await parseEncryptionInfo(from: m3u8Text, effectiveBaseURL: effectiveBaseURL)

        // 3. 解析 TS 分片
        let tsURLs = try parseTSURLs(from: m3u8Text, baseURL: effectiveBaseURL)

        // 4. 下载 TS 并生成本地 m3u8（明文 + 绝对路径 + 无 EXT-X-KEY）
        var localM3U8Lines: [String] = []
        let lines = m3u8Text.components(separatedBy: .newlines)

        let startSegment = task.completedSegments
        var tsIndex = 0
        var totalBytes: Int64 = 0

        for line in lines {
            try Task.checkCancellation()

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 跳过 #EXT-X-KEY 行（因为 TS 已经是明文）
            if trimmed.hasPrefix("#EXT-X-KEY") {
                continue
            }

            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                localM3U8Lines.append(line)
                continue
            }

            guard tsIndex < tsURLs.count else { continue }
            let fileName = "segment_\(tsIndex).ts"
            let localURL = folderURL.appendingPathComponent(fileName)

            if tsIndex < startSegment {
                if FileManager.default.fileExists(atPath: localURL.path) {
                    localM3U8Lines.append(localURL.absoluteString)
                    let size = (try? FileManager.default.attributesOfItem(atPath: localURL.path)[.size] as? Int64) ?? 0
                    totalBytes += size ?? 0
                } else {
                    let size = try await downloadAndDecryptTS(
                        urlString: tsURLs[tsIndex],
                        to: localURL,
                        encInfo: encInfo
                    )
                    localM3U8Lines.append(localURL.absoluteString)
                    totalBytes += size
                    setDownloadedBytes(totalBytes, for: taskID)
                }
            } else {
                let size = try await downloadAndDecryptTS(
                    urlString: tsURLs[tsIndex],
                    to: localURL,
                    encInfo: encInfo
                )
                localM3U8Lines.append(localURL.absoluteString)
                totalBytes += size
                setDownloadedBytes(totalBytes, for: taskID)
                setCompletedSegments(tsIndex + 1, for: taskID)
            }

            tsIndex += 1
            progressHandler(Double(tsIndex) / Double(tsURLs.count), totalBytes, task.totalBytes)
        }

        setTotalBytes(totalBytes, for: taskID)

        let localM3U8URL = folderURL.appendingPathComponent("index.m3u8")
        try localM3U8Lines.joined(separator: "\n").write(to: localM3U8URL, atomically: true, encoding: .utf8)

        return localM3U8URL
    }

    // MARK: - TS 下载 + AES-128 解密

    private struct EncryptionInfo {
        let key: [UInt8]
        let iv: [UInt8]
    }

    private func parseEncryptionInfo(
        from m3u8Text: String,
        effectiveBaseURL: String
    ) async throws -> EncryptionInfo? {
        for line in m3u8Text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXT-X-KEY"), trimmed.contains("AES-128") else { continue }

            // 提取 URI
            guard let uriRange = trimmed.range(of: "URI=\""),
                  let uriEnd = trimmed[uriRange.upperBound...].range(of: "\"")?.lowerBound else {
                return nil
            }
            let keyURI = String(trimmed[uriRange.upperBound..<uriEnd])

            // 拼密钥绝对 URL
            let keyURL: URL
            if keyURI.hasPrefix("http") {
                keyURL = URL(string: keyURI)!
            } else if keyURI.hasPrefix("/") {
                var comps = URLComponents(url: URL(string: effectiveBaseURL)!, resolvingAgainstBaseURL: false)!
                comps.path = keyURI
                keyURL = comps.url!
            } else {
                let base = URL(string: effectiveBaseURL)!
                keyURL = base.deletingLastPathComponent().appendingPathComponent(keyURI)
            }

            // 下载密钥
            let (keyData, _) = try await URLSession.shared.data(from: keyURL)
            let keyBytes = [UInt8](keyData)

            // 解析 IV
            var iv: [UInt8] = Array(repeating: 0, count: 16)
            if let ivRange = trimmed.range(of: "IV=0x") {
                let hexStart = ivRange.upperBound
                let hexEnd = trimmed.index(hexStart, offsetBy: 32, limitedBy: trimmed.endIndex) ?? trimmed.endIndex
                let hexString = String(trimmed[hexStart..<hexEnd])
                var hexIndex = 0
                for i in 0..<16 {
                    let start = hexString.index(hexString.startIndex, offsetBy: hexIndex)
                    let end = hexString.index(start, offsetBy: 2)
                    iv[i] = UInt8(hexString[start..<end], radix: 16) ?? 0
                    hexIndex += 2
                }
            }

            return EncryptionInfo(key: keyBytes, iv: iv)
        }
        return nil
    }

    private func downloadAndDecryptTS(
        urlString: String,
        to localURL: URL,
        encInfo: EncryptionInfo?
    ) async throws -> Int64 {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (tsData, _) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()

        var finalData = tsData

        if let encInfo {
            let encryptedBytes = [UInt8](tsData)
            let aes = try AES(key: encInfo.key, blockMode: CBC(iv: encInfo.iv), padding: .noPadding)
            let decryptedBytes = try aes.decrypt(encryptedBytes)
            finalData = Data(decryptedBytes)
        }

        try finalData.write(to: localURL)
        return Int64(finalData.count)
    }

    // MARK: - 嵌套 m3u8 解析

    private struct ResolvedPlaylist {
        let text: String
        let baseURL: String
    }

    private func resolveEffectiveM3U8(from sourceURL: URL, taskID: String) async throws -> ResolvedPlaylist {
        let (data, _) = try await URLSession.shared.data(from: sourceURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        if text.contains("#EXT-X-STREAM-INF") {
            let childPaths = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && $0.hasSuffix(".m3u8") }

            guard let childPath = childPaths.first else {
                throw URLError(.cannotParseResponse)
            }

            let childURL: URL
            if childPath.hasPrefix("http") {
                childURL = URL(string: childPath)!
            } else if childPath.hasPrefix("/") {
                var comps = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)!
                comps.path = childPath
                childURL = comps.url!
            } else {
                childURL = sourceURL.deletingLastPathComponent().appendingPathComponent(childPath)
            }

            let (childData, _) = try await URLSession.shared.data(from: childURL)
            guard let childText = String(data: childData, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            return ResolvedPlaylist(text: childText, baseURL: childURL.absoluteString)
        }

        return ResolvedPlaylist(text: text, baseURL: sourceURL.absoluteString)
    }

    // MARK: - 工具方法

    private func folderURL(title: String, episodeName: String) -> URL {
        let folderName = "\(safeFileName(title))_\(safeFileName(episodeName))"
        return downloadsDir.appendingPathComponent(folderName, isDirectory: true)
    }

    private func parseTSURLs(from text: String, baseURL: String) throws -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var urls: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if trimmed.hasPrefix("http") {
                urls.append(trimmed)
            } else if let base = URL(string: baseURL) {
                let absolute = base.deletingLastPathComponent().appendingPathComponent(trimmed).absoluteString
                urls.append(absolute)
            }
        }

        guard !urls.isEmpty else { throw URLError(.cannotParseResponse) }
        return urls
    }

    private func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }

    private static func folderSize(at folderURL: URL) -> Int64 {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for fileURL in contents {
            let size = (try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            total += size ?? 0
        }
        return total
    }

    // MARK: - 状态更新

    private func setStatus(_ status: DownloadStatus, for taskID: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].status = status
        }
    }

    private func setProgress(_ progress: Double, for taskID: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].progress = progress
        }
    }

    private func setCompletedSegments(_ count: Int, for taskID: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].completedSegments = count
        }
    }

    private func setTotalBytes(_ bytes: Int64, for taskID: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].totalBytes = bytes
        }
    }

    private func setDownloadedBytes(_ bytes: Int64, for taskID: String) {
        if let index = tasks.firstIndex(where: { $0.id == taskID }) {
            tasks[index].downloadedBytes = bytes
        }
    }

    // MARK: - 扫描与删除

    func scanDownloadsDirectory() {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: downloadsDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        var discovered: [DownloadedMovie] = []
        var existingPaths = Set(downloadedMovies.map { $0.fileURL })

        for folderURL in contents {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let m3u8URL = folderURL.appendingPathComponent("index.m3u8")
            guard fm.fileExists(atPath: m3u8URL.path) else { continue }
            guard !existingPaths.contains(m3u8URL.path) else { continue }

            let folderName = folderURL.lastPathComponent
            let parts = folderName.split(separator: "_", maxSplits: 1).map(String.init)
            let title = parts.first ?? folderName
            let episodeName = parts.count > 1 ? parts[1] : ""

            let totalSize = Self.folderSize(at: folderURL)
            let attr = try? fm.attributesOfItem(atPath: m3u8URL.path)
            let date = attr?[.modificationDate] as? Date ?? Date()

            let movie = DownloadedMovie(
                id: UUID().uuidString,
                title: title,
                episodeName: episodeName,
                fileURL: m3u8URL.path,
                fileSize: totalSize,
                downloadDate: date
            )
            discovered.append(movie)
            existingPaths.insert(m3u8URL.path)
        }

        if !discovered.isEmpty {
            downloadedMovies.insert(contentsOf: discovered, at: 0)
            persistMetadata()
        }
    }

    func deleteMovie(_ movie: DownloadedMovie) {
        let fileURL = URL(fileURLWithPath: movie.fileURL)
        let folderURL = fileURL.deletingLastPathComponent()

        try? FileManager.default.removeItem(at: folderURL)

        downloadedMovies.removeAll { $0.id == movie.id }
        persistMetadata()
    }

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
}