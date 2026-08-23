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
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleEpisodeList"))) { _ in
            hideEpisodeList.toggle()
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
    private var fullScreenButton: UIButton?
    private var speedButton: UIButton?
    private var isFullScreen = false
    private var normalRate: Float = 1.0
    private var originalFrame: CGRect = .zero

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
        setupOverlayButtons()
    }

    private func setupPlayer() {
        lastURLString = playURLString

        let manager = ZFAVPlayerManager()
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        let controlView = ZFPlayerControlView()
        player.controlView = controlView
        controlView.portraitControlView.fullScreenBtn.isHidden = true
        self.player = player

        if let url = URL(string: playURLString) {
            manager.assetURL = url
        }
        player.playTheIndex(0)

        addLongPressSpeedGesture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isFullScreen {
            originalFrame = view.frame
        }
    }

    private func setupOverlayButtons() {
        let full = UIButton(type: .system)
        full.setTitle("全屏", for: .normal)
        full.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        full.setTitleColor(.white, for: .normal)
        full.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        full.layer.cornerRadius = 8
        full.translatesAutoresizingMaskIntoConstraints = false
        full.addTarget(self, action: #selector(toggleFullScreen), for: .touchUpInside)
        view.addSubview(full)
        view.bringSubviewToFront(full)

        NSLayoutConstraint.activate([
            full.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            full.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            full.widthAnchor.constraint(equalToConstant: 60),
            full.heightAnchor.constraint(equalToConstant: 40)
        ])
        fullScreenButton = full

        let speed = UIButton(type: .system)
        speed.setTitle("1.0x", for: .normal)
        speed.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        speed.setTitleColor(.white, for: .normal)
        speed.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        speed.layer.cornerRadius = 8
        speed.translatesAutoresizingMaskIntoConstraints = false
        speed.addTarget(self, action: #selector(showSpeedMenu), for: .touchUpInside)
        speed.isHidden = true
        view.addSubview(speed)
        view.bringSubviewToFront(speed)

        NSLayoutConstraint.activate([
            speed.trailingAnchor.constraint(equalTo: full.leadingAnchor, constant: -12),
            speed.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            speed.widthAnchor.constraint(equalToConstant: 60),
            speed.heightAnchor.constraint(equalToConstant: 40)
        ])
        speedButton = speed
    }

    @objc private func toggleFullScreen() {
        isFullScreen.toggle()
        speedButton?.isHidden = !isFullScreen
        NotificationCenter.default.post(name: NSNotification.Name("toggleEpisodeList"), object: nil)

        if isFullScreen {
            let screen = UIScreen.main.bounds
            UIView.animate(withDuration: 0.3) {
                self.view.transform = CGAffineTransform(rotationAngle: .pi / 2)
                self.view.frame = CGRect(x: 0, y: 0, width: screen.height, height: screen.width)
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                self.view.transform = .identity
                self.view.frame = self.originalFrame
            }
        }
    }

    @objc private func showSpeedMenu() {
        let sheet = UIAlertController(title: "播放速度", message: nil, preferredStyle: .actionSheet)
        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        for rate in rates {
            sheet.addAction(UIAlertAction(title: "\(rate)x", style: .default) { [weak self] _ in
                self?.setRate(rate)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(sheet, animated: true)
    }

    private func setRate(_ rate: Float) {
        normalRate = rate
        speedButton?.setTitle("\(rate)x", for: .normal)
        player?.currentPlayerManager.setRate(rate)
    }

    private func addLongPressSpeedGesture() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        view.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            player?.currentPlayerManager.setRate(2.0)
        case .ended, .cancelled, .failed:
            player?.currentPlayerManager.setRate(normalRate)
        default:
            break
        }
    }

    func restartIfNeeded() {
        guard playURLString != lastURLString else { return }
        player?.stop()
        setupPlayer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.stop()
    }
}