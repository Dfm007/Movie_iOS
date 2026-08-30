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

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadsDir = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadMetadata()
    }

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
        }

        alertMessage = "已创建 \(items.count) 个下载任务"
        showAlert = true

        for item in items {
            processDownload(item)
        }
    }

    private func processDownload(_ item: (title: String, episodeName: String, sourceURL: String)) {
        guard let index = tasks.firstIndex(where: { $0.sourceURL == item.sourceURL && $0.episodeName == item.episodeName }) else { return }

        Task {
            do {
                let localM3U8URL = try await downloadM3U8(
                    sourceURL: item.sourceURL,
                    title: item.title,
                    episodeName: item.episodeName
                ) { progress in
                    self.tasks[index].progress = progress
                }

                let attr = try FileManager.default.attributesOfItem(atPath: localM3U8URL.path)
                let size = attr[.size] as? Int64 ?? 0

                let movie = DownloadedMovie(
                    id: UUID().uuidString,
                    title: item.title,
                    episodeName: item.episodeName,
                    fileURL: localM3U8URL.path,
                    fileSize: size,
                    downloadDate: Date()
                )

                downloadedMovies.insert(movie, at: 0)
                persistMetadata()
                tasks[index].status = .completed
                tasks[index].progress = 1
            } catch {
                tasks[index].status = .failed
            }
        }
    }

    private func downloadM3U8(
        sourceURL: String,
        title: String,
        episodeName: String,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        guard let url = URL(string: sourceURL) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let m3u8Text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let safeTitle = safeFileName(title)
        let safeEpisode = safeFileName(episodeName)
        let folderName = "\(safeTitle)_\(safeEpisode)"
        let folderURL = downloadsDir.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let tsURLs = try parseTSURLs(from: m3u8Text, baseURL: sourceURL)

        var localM3U8Lines: [String] = []
        let lines = m3u8Text.components(separatedBy: .newlines)

        var tsIndex = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                localM3U8Lines.append(line)
                continue
            }

            guard tsIndex < tsURLs.count else { continue }
            let remoteURL = tsURLs[tsIndex]
            let fileName = "segment_\(tsIndex).ts"
            let localURL = folderURL.appendingPathComponent(fileName)

            let tsDataURL = URL(string: remoteURL)!
            let (tsData, _) = try await URLSession.shared.data(from: tsDataURL)
            try tsData.write(to: localURL)

            localM3U8Lines.append(fileName)
            tsIndex += 1
            progressHandler(Double(tsIndex) / Double(tsURLs.count))
        }

        let localM3U8URL = folderURL.appendingPathComponent("index.m3u8")
        try localM3U8Lines.joined(separator: "\n").write(to: localM3U8URL, atomically: true, encoding: .utf8)

        return localM3U8URL
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