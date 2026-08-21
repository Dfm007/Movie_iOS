import SwiftUI
import AVKit

struct DetailView: View {
    let detailURL: String
    @StateObject private var viewModel = DetailViewModel()
    @State private var playingSource: PlaySource?

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("加载中...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("重试") {
                        Task { await viewModel.loadDetail(path: detailURL) }
                    }
                }
            } else {
                List {
                    ForEach(viewModel.sources) { source in
                        if source.episodes.isEmpty {
                            Button(action: {
                                playingSource = source
                            }) {
                                HStack {
                                    Text(source.name)
                                    Spacer()
                                    Text(source.format.uppercased())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Section(header: Text(source.name)) {
                                ForEach(source.episodes) { episode in
                                    Button(action: {
                                        playingSource = episode
                                    }) {
                                        HStack {
                                            Text(episode.name)
                                            Spacer()
                                            Text(episode.format.uppercased())
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.movieTitle)
        .task {
            await viewModel.loadDetail(path: detailURL)
        }
        .fullScreenCover(item: $playingSource) { source in
            PlayerView(source: source)
        }
    }
}

struct PlayerView: View {
    let source: PlaySource
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let error = errorMessage {
                VStack(spacing: 16) {
                    Text("播放失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Text("URL: \(source.url)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("关闭") {
                        dismiss()
                    }
                }
            } else if let player = player {
                VideoPlayer(player: player)
            } else {
                ProgressView("加载播放器...")
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding()
            }
        }
        .onAppear {
            loadPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func loadPlayer() {
        guard let url = URL(string: source.url) else {
            errorMessage = "无效的播放地址"
            return
        }
        let asset = AVURLAsset(url: url)
        let p = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player = p
        p.play()

        Task {
            do {
                let status = try await asset.load(.isPlayable)
                if !status {
                    errorMessage = "视频不可播放"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
