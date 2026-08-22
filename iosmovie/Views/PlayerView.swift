import SwiftUI
import AVKit
import UIKit

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    @Environment(\.dismiss) private var dismiss
    @State private var currentSource: PlaySource
    @State private var isFullScreen = false

    init(source: PlaySource, allSources: [PlaySource] = []) {
        self.source = source
        self.allSources = allSources
        _currentSource = State(initialValue: source)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZFPlayerRepresentable(url: currentSource.url)
                .frame(height: isFullScreen ? UIScreen.main.bounds.height : UIScreen.main.bounds.width * 9 / 16)
                .background(Color.black)

            if !isFullScreen {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(allSources) { group in
                            if group.episodes.isEmpty {
                                Button(action: {
                                    currentSource = group
                                }) {
                                    Text(group.name)
                                        .font(.subheadline)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(currentSource.id == group.id ? Color.blue.opacity(0.35) : Color.blue.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            } else {
                                Text(group.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                                    ForEach(group.episodes) { episode in
                                        Button(action: {
                                            currentSource = episode
                                        }) {
                                            Text(episode.name)
                                                .font(.caption)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 8)
                                                .background(currentSource.id == episode.id ? Color.blue.opacity(0.35) : Color.blue.opacity(0.15))
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical)
                }
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding()
        }
    }
}

struct ZFPlayerRepresentable: UIViewControllerRepresentable {
    let url: String

    func makeUIViewController(context: Context) -> ZFPlayerViewController {
        let vc = ZFPlayerViewController()
        vc.playURLString = url
        return vc
    }

    func updateUIViewController(_ uiViewController: ZFPlayerViewController, context: Context) {
        uiViewController.playURLString = url
        uiViewController.restartIfNeeded()
    }
}

final class ZFPlayerViewController: UIViewController {
    var playURLString: String = ""
    private var player: ZFPlayerController?

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let manager = ZFAVPlayerManager()
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        player.controlView = ZFPlayerControlView()
        self.player = player

        if let url = URL(string: playURLString) {
            manager.assetURL = url
        }
        player.playTheIndex(0)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.stop()
    }
}
}
