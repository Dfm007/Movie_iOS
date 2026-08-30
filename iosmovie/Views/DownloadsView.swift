import SwiftUI

struct DownloadsView: View {
    @StateObject private var downloadManager = DownloadManager.shared

    var body: some View {
        Group {
            if downloadManager.isDownloading {
                VStack(spacing: 12) {
                    ProgressView(value: downloadManager.progress)
                        .progressViewStyle(.linear)
                    Text("下载中 \(Int(downloadManager.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }

            List {
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
            .listStyle(.plain)
        }
        .navigationTitle("我的下载")
        .navigationBarTitleDisplayMode(.inline)
    }
}