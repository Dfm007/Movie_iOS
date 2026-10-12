import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var playingMovie: DownloadedMovie?
    @State private var playerPresented = false

    var body: some View {
        List {
            downloadSection
            downloadedSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("全部暂停") {
                        downloadManager.pauseAllTasks()
                    }
                    Button("全部继续") {
                        downloadManager.resumeAllTasks()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(downloadManager.tasks.isEmpty)
            }
        }
        .alert("提示", isPresented: $downloadManager.showAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(downloadManager.alertMessage)
        }
        .background(
            PlayerPresenter(
                source: playingMovie.map(localPlaySource) ?? PlaySource(
                    id: "",
                    name: "",
                    url: "",
                    format: "",
                    episodes: []
                ),
                allSources: [],
                isPresented: $playerPresented
            )
        )
        .onAppear {
            downloadManager.scanDownloadsDirectory()
        }
    }

    @ViewBuilder
    private var downloadSection: some View {
        if !downloadManager.tasks.isEmpty {
            Section("下载中") {
                ForEach(downloadManager.tasks) { task in
                    DownloadTaskRow(
                        task: task,
                        onPause: { downloadManager.pauseTask(task) },
                        onResume: { downloadManager.resumeTask(task) },
                        onCancel: { downloadManager.cancelTask(task) },
                        onRetry: { downloadManager.retryTask(task) }
                    )
                    .swipeActions {
                        Button(role: .destructive) {
                            downloadManager.cancelTask(task)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var downloadedSection: some View {
        Section("已下载") {
            ForEach(downloadManager.downloadedMovies) { movie in
                Button {
                    playingMovie = movie
                    playerPresented = true
                } label: {
                    DownloadedMovieRow(movie: movie)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        downloadManager.deleteMovie(movie)
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
    }

    private func localPlaySource(for movie: DownloadedMovie) -> PlaySource {
        // absoluteString 会做百分号编码，播放端用 URL(string:) 解析即可正确还原中文路径
        let fileURL = URL(fileURLWithPath: movie.fileURL).absoluteString
        return PlaySource(
            id: movie.id,
            name: movie.episodeName,
            url: fileURL,
            format: movie.format,
            episodes: []
        )
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(task.title) \(task.episodeName)")
                .font(.subheadline)
                .fontWeight(.medium)

            ProgressView(value: task.progress)
                .progressViewStyle(.linear)

            HStack {
                Text("\(Int(task.progress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if task.totalSegments > 0 {
                    Text("\(task.completedSegments)/\(task.totalSegments) 分片")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if task.totalBytes > 0 {
                    Text("\(Self.formatBytes(task.downloadedBytes)) / 约 \(Self.formatBytes(task.totalBytes))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(task.status.displayText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }

            if let error = task.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(3)
            }

            HStack(spacing: 12) {
                switch task.status {
                case .downloading:
                    Button(action: onPause) {
                        Label("暂停", systemImage: "pause.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive, action: onCancel) {
                        Label("取消", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                case .paused:
                    Button(action: onResume) {
                        Label("继续", systemImage: "play.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive, action: onCancel) {
                        Label("取消", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                case .failed:
                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive, action: onCancel) {
                        Label("删除", systemImage: "trash.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                case .completed:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .paused:      return .orange
        case .completed:   return .green
        case .failed:      return .red
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct DownloadedMovieRow: View {
    let movie: DownloadedMovie

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(movie.title)
                .font(.subheadline)
                .fontWeight(.medium)
            Text(movie.episodeName)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(Self.formatBytes(movie.fileSize)) · \(movie.format.uppercased())")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
