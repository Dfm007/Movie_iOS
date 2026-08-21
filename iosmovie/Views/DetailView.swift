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

    var body: some View {
        Group {
            if let player = player {
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
            if let url = URL(string: source.url) {
                let p = AVPlayer(url: url)
                player = p
                p.play()
            }
        }
        .onDisappear {
            player?.pause()
        }
    }
}
