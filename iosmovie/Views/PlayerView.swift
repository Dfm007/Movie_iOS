import SwiftUI
import AVKit
import UIKit

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    var onClose: () -> Void
    @State private var currentSource: PlaySource
    @State private var hideEpisodeList = false

    private let episodeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    init(source: PlaySource, allSources: [PlaySource] = [], onClose: @escaping () -> Void) {
        self.source = source
        self.allSources = allSources
        self.onClose = onClose
        _currentSource = State(initialValue: source)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZFPlayerRepresentable(url: currentSource.url)
                .frame(height: hideEpisodeList ? UIScreen.main.bounds.height : UIScreen.main.bounds.width * 9 / 16)
                .background(Color.black)

            if !hideEpisodeList {
                episodeListView
            }
        }
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            Button(action: { onClose() }) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.top, hideEpisodeList ? 60 : 8)
            .padding(.trailing, 8)
        }
    }

    private var episodeListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(allSources) { group in
                    if group.episodes.isEmpty {
                        Button(action: {
                            currentSource = group
                        }) {
                            Text(group.name)
                                .font(.subheadline)
                                .foregroundColor(currentSource.id == group.id ? .white : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(currentSource.id == group.id ? Color.blue : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text(group.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: episodeColumns, spacing: 8) {
                            ForEach(group.episodes) { episode in
                                Button(action: {
                                    currentSource = episode
                                }) {
                                    Text(episode.name)
                                        .font(.caption)
                                        .foregroundColor(currentSource.id == episode.id ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(currentSource.id == episode.id ? Color.blue : Color.gray.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .background(Color.white)
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
    private var lastURLString: String = ""
    private var landscapeVC: LandscapePlayerViewController?

    override var shouldAutorotate: Bool { false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
    }

    private func setupPlayer() {
        lastURLString = playURLString
        let manager = ZFAVPlayerManager()
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        let controlView = ZFPlayerControlView()
        player.controlView = controlView
        // 隐藏 ZFPlayer 原生全屏按钮，用我们的全屏逻辑
        controlView.portraitControlView.fullScreenBtn.isHidden = true
        self.player = player

        if let url = URL(string: playURLString) {
            manager.assetURL = url
        }
        player.playTheIndex(0)
    }

    func restartIfNeeded() {
        guard playURLString != lastURLString else { return }
        lastURLString = playURLString
        if let url = URL(string: playURLString) {
            playerManager?.assetURL = url
            player?.playTheIndex(0)
        }
    }

    func enterFullScreen() {
        guard landscapeVC == nil else { return }
        let landscape = LandscapePlayerViewController(urlString: playURLString)
        landscape.modalPresentationStyle = .fullScreen
        landscape.onDismiss = { [weak self] in
            self?.landscapeVC = nil
        }
        landscapeVC = landscape

        // 关键：present 完成后把竖屏控制器 view 插回 window 层级，避免闪屏和方向回退
        present(landscape, animated: true) { [weak self] in
            guard let self = self,
                  let window = self.view.window,
                  let landscapeView = landscape.view.superview else { return }
            window.insertSubview(self.view, belowSubview: landscapeView)
        }
    }
}

final class LandscapePlayerViewController: UIViewController {
    let urlString: String
    var onDismiss: (() -> Void)?
    private var player: ZFPlayerController?

    init(urlString: String) {
        self.urlString = urlString
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var shouldAutorotate: Bool { false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscapeRight }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
        setupBackButton()
    }

    private func setupPlayer() {
        let manager = ZFAVPlayerManager()
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        let controlView = ZFPlayerControlView()
        player.controlView = controlView
        self.player = player
        if let url = URL(string: urlString) {
            manager.assetURL = url
        }
        player.playTheIndex(0)
    }

    private func setupBackButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    @objc private func backTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onDismiss?()
        }
    }
}
