import SwiftUI
import AVKit

struct DetailView: View {
    let detailURL: String
    @StateObject private var viewModel = DetailViewModel()

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
                    ForEach(viewModel.detail?.sources ?? []) { source in
                        Button(action: {
                            if let url = URL(string: source.url) {
                                let player = AVPlayer(url: url)
                                let playerVC = AVPlayerViewController()
                                playerVC.player = player
                                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                   let rootVC = scene.windows.first?.rootViewController {
                                    rootVC.present(playerVC, animated: true) {
                                        player.play()
                                    }
                                }
                            }
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
        .navigationTitle(viewModel.detail?.title ?? "")
        .task {
            await viewModel.loadDetail(path: detailURL)
        }
    }
}