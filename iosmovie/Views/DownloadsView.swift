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
                    DownloadTaskRow(task: task)
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
            format: "mp4",
            episodes: []
        )
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadTask

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

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(statusColor)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusText: String {
        switch task.status {
        case .downloading:
            return "下载中"
        case .paused:
            return "已暂停"
        case .completed:
            return "已完成"
        case .failed:
            return "失败"
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading:
            return .blue
        case .paused:
            return .orange
        case .completed:
            return .green
        case .failed:
            return .red
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