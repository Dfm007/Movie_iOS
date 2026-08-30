import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        List {
            if !downloadManager.tasks.isEmpty {
                Section("下载中") {
                    ForEach(downloadManager.tasks) { task in
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

                                statusText(for: task.status)
                                    .font(.caption)
                                    .foregroundColor(statusColor(for: task.status))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("已下载") {
                ForEach(downloadManager.downloadedMovies) { movie in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(movie.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text(movie.episodeName)
                            .font(.caption)
                            .foregroundColor(.secondary)
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
        .listStyle(.insetGrouped)
        .navigationTitle("我的下载")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statusText(for status: DownloadStatus) -> String {
        switch status {
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

    private func statusColor(for status: DownloadStatus) -> Color {
        switch status {
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