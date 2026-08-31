import Foundation

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

        // 清理临时文件夹
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
            let localM3U8URL = try await downloadM3U8(taskID: taskID) { [weak self] progress in
                self?.setProgress(progress, for: taskID)
            }

            // 检查是否被取消（暂停/取消都可能触发）
            try Task.checkCancellation()

            let attr = try FileManager.default.attributesOfItem(atPath: localM3U8URL.path)
            let size = attr[.size] as? Int64 ?? 0

            let movie = DownloadedMovie(
                id: UUID().uuidString,
                title: task.title,
                episodeName: task.episodeName,
                fileURL: localM3U8URL.path,
                fileSize: size,
                downloadDate: Date()
            )

            downloadedMovies.insert(movie, at: 0)
            persistMetadata()
            setStatus(.completed, for: taskID)
            setProgress(1, for: taskID)
            taskHandles[taskID] = nil
        } catch is CancellationError {
            // 正常取消，状态已由 pause/cancel 设置，不额外处理
            taskHandles[taskID] = nil
        } catch {
            setStatus(.failed, for: taskID)
            taskHandles[taskID] = nil
        }
    }

    // MARK: - m3u8 + TS 下载（断点续传 + 嵌套 m3u8 + AES-128 密钥）

    private func downloadM3U8(
        taskID: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw URLError(.cancelled)
        }
        let task = tasks[index]

        guard let sourceURL = URL(string: task.sourceURL) else { throw URLError(.badURL) }

        let folderURL = folderURL(title: task.title, episodeName: task.episodeName)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        // 1. 下载第一层 m3u8 并解析最终的有效分片列表
        let resolved = try await resolveEffectiveM3U8(from: sourceURL, taskID: taskID)

        let m3u8Text = resolved.text
        let effectiveBaseURL = resolved.baseURL

        // 2. 下载 AES-128 密钥（如果有）
        try await downloadEncKeyIfNeeded(from: m3u8Text, effectiveBaseURL: effectiveBaseURL, folderURL: folderURL)

        // 3. 解析 TS 分片
        let tsURLs = try parseTSURLs(from: m3u8Text, baseURL: effectiveBaseURL)

        // 4. 下载 TS 分片并改写本地 m3u8
        var localM3U8Lines: [String] = []
        let lines = m3u8Text.components(separatedBy: .newlines)

        let startSegment = task.completedSegments
        var tsIndex = 0

        for line in lines {
            try Task.checkCancellation()

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                localM3U8Lines.append(line)
                continue
            }

            guard tsIndex < tsURLs.count else { continue }
            let fileName = "segment_\(tsIndex).ts"
            let localURL = folderURL.appendingPathComponent(fileName)

            if tsIndex < startSegment {
                // 已下载过的分片，直接复用
                if FileManager.default.fileExists(atPath: localURL.path) {
                    localM3U8Lines.append(fileName)
                } else {
                    // 本地分片缺失，需要重下
                    try await downloadTS(tsURLs[tsIndex], to: localURL)
                    localM3U8Lines.append(fileName)
                }
            } else {
                try await downloadTS(tsURLs[tsIndex], to: localURL)
                localM3U8Lines.append(fileName)
                setCompletedSegments(tsIndex + 1, for: taskID)
            }

            tsIndex += 1
            progressHandler(Double(tsIndex) / Double(tsURLs.count))
        }

        let localM3U8URL = folderURL.appendingPathComponent("index.m3u8")
        try localM3U8Lines.joined(separator: "\n").write(to: localM3U8URL, atomically: true, encoding: .utf8)

        return localM3U8URL
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

        // 如果是 master playlist（含 #EXT-X-STREAM-INF），需要找子 m3u8
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

            // 递归抓子 m3u8（最多一层，这里直接下载）
            let (childData, _) = try await URLSession.shared.data(from: childURL)
            guard let childText = String(data: childData, encoding: .utf8) else {
                throw URLError(.cannotDecodeContentData)
            }

            // 子 m3u8 里的相对 URI（如 enc.key）要用 childURL 来解析
            return ResolvedPlaylist(text: childText, baseURL: childURL.absoluteString)
        }

        // 单级 m3u8，直接返回
        return ResolvedPlaylist(text: text, baseURL: sourceURL.absoluteString)
    }

    // MARK: - AES-128 密钥下载

    private func downloadEncKeyIfNeeded(
        from m3u8Text: String,
        effectiveBaseURL: String,
        folderURL: URL
    ) async throws {
        // 找 #EXT-X-KEY 行里的 URI
        for line in m3u8Text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXT-X-KEY") else { continue }

            // 提取 URI="xxx"
            guard let uriRange = trimmed.range(of: "URI=\"") else { continue }
            let uriStart = uriRange.upperBound
            guard let uriEnd = trimmed[uriStart...].range(of: "\"")?.lowerBound else { continue }
            let keyURI = String(trimmed[uriStart..<uriEnd])

            // 拼绝对 URL
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

            // 下载密钥到本地 enc.key
            let (keyData, _) = try await URLSession.shared.data(from: keyURL)
            let localKeyURL = folderURL.appendingPathComponent("enc.key")
            try keyData.write(to: localKeyURL)
            break
        }
    }

    // MARK: - TS 下载

    private func downloadTS(_ urlString: String, to localURL: URL) async throws {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        let (tsData, _) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        try tsData.write(to: localURL)
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

    // MARK: - 删除已下载

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