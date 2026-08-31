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
        let fileURL = URL(fileURLWithPath: movie.fileURL).absoluteString
        return PlaySource(
            id: movie.id,
            name: movie.episodeName,
            url: fileURL,
            format: "m3u8",
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

                Text(task.status.displayText)
                    .font(.caption)
                    .foregroundColor(statusColor)
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
        }
    }
}