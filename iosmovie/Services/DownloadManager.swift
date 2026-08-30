import Foundation

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloadedMovies: [DownloadedMovie] = []
    @Published var isDownloading = false
    @Published var progress: Double = 0

    private let metadataKey = "downloaded_movies_metadata"
    private let downloadsDir: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        downloadsDir = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        loadMetadata()
    }

    func startDownload(title: String, episodeName: String, sourceURL: String) {
        guard !isDownloading else { return }
        isDownloading = true
        progress = 0

        Task {
            do {
                let url = try await downloadM3U8(sourceURL: sourceURL, title: title, episodeName: episodeName)
                let attr = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = attr[.size] as? Int64 ?? 0

                let movie = DownloadedMovie(
                    id: UUID().uuidString,
                    title: title,
                    episodeName: episodeName,
                    fileURL: url.path,
                    fileSize: size,
                    downloadDate: Date()
                )

                downloadedMovies.insert(movie, at: 0)
                persistMetadata()
            } catch {
                // 下载失败，这里可以加错误提示
            }

            isDownloading = false
            progress = 0
        }
    }

    private func downloadM3U8(sourceURL: String, title: String, episodeName: String) async throws -> URL {
        guard let url = URL(string: sourceURL) else { throw URLError(.badURL) }

        let (data, _) = try await URLSession.shared.data(from: url)
        guard let m3u8Text = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        let tsURLs = try parseM3U8(m3u8Text, baseURL: sourceURL)

        var localFiles: [URL] = []
        for (index, tsURL) in tsURLs.enumerated() {
            guard let tsDataURL = URL(string: tsURL) else { continue }
            let (tsData, _) = try await URLSession.shared.data(from: tsDataURL)
            let localURL = downloadsDir.appendingPathComponent("\(UUID().uuidString)_\(index).ts")
            try tsData.write(to: localURL)
            localFiles.append(localURL)
            progress = Double(index + 1) / Double(tsURLs.count)
        }

        let mergedURL = downloadsDir.appendingPathComponent("\(safeFileName(title))_\(safeFileName(episodeName)).mp4")
        try mergeTSFiles(localFiles, to: mergedURL)

        for file in localFiles {
            try? FileManager.default.removeItem(at: file)
        }

        return mergedURL
    }

    private func parseM3U8(_ text: String, baseURL: String) throws -> [String] {
        let lines = text.components(separatedBy: .newlines)
        var tsURLs: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            if trimmed.hasPrefix("http") {
                tsURLs.append(trimmed)
            } else if let base = URL(string: baseURL) {
                let absolute = base.deletingLastPathComponent().appendingPathComponent(trimmed).absoluteString
                tsURLs.append(absolute)
            }
        }

        guard !tsURLs.isEmpty else { throw URLError(.cannotParseResponse) }
        return tsURLs
    }

    private func mergeTSFiles(_ files: [URL], to outputURL: URL) throws {
        try? FileManager.default.removeItem(at: outputURL)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)

        for file in files {
            let data = try Data(contentsOf: file)
            handle.write(data)
        }

        try handle.close()
    }

    private func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }

    func deleteMovie(_ movie: DownloadedMovie) {
        let url = URL(fileURLWithPath: movie.fileURL)
        try? FileManager.default.removeItem(at: url)
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