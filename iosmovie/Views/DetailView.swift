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
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerView

                        infoSection

                        Picker("采集站", selection: $viewModel.selectedSite) {
                            ForEach(viewModel.sites) { site in
                                Text(site.name).tag(site)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .onChange(of: viewModel.selectedSite) { newSite in
                            Task { await viewModel.loadDetail(path: detailURL, site: newSite) }
                        }

                        episodeSection
                    }
                    .padding(.vertical)
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

    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            if let posterURL = viewModel.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(2/3, contentMode: .fill)
                    default:
                        posterPlaceholder
                    }
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                posterPlaceholder
                    .frame(width: 100, height: 150)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.movieTitle)
                    .font(.headline)
                    .lineLimit(3)
                Text("采集站：\(viewModel.selectedSite.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.18, blue: 0.28),
                        Color(red: 0.30, green: 0.24, blue: 0.42)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "film")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            )
    }


    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !viewModel.remarks.isEmpty {
                Text(viewModel.remarks)
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            if !viewModel.year.isEmpty || !viewModel.area.isEmpty || !viewModel.className.isEmpty {
                Text([viewModel.year, viewModel.area, viewModel.className].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !viewModel.director.isEmpty {
                Text("导演：\(viewModel.director)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !viewModel.actors.isEmpty {
                Text("主演：\(viewModel.actors)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !viewModel.intro.isEmpty {
                Text(viewModel.intro)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
            }
        }
        .padding(.horizontal)
    }
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.sources) { source in
                if source.episodes.isEmpty {
                    Button(action: {
                        playingSource = source
                    }) {
                        Text(source.name)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text(source.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(source.episodes) { episode in
                                Button(action: {
                                    playingSource = episode
                                }) {
                                    Text(episode.name)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.blue.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
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