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
    private var speedHintLabel: UILabel?
    private var speedMenuView: UIView?
    private var fullScreenTrailingConstraint: NSLayoutConstraint?

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
        setupSpeedHintLabel()
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
        full.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        full.tintColor = .white
        full.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        full.layer.cornerRadius = 6
        full.translatesAutoresizingMaskIntoConstraints = false
        full.addTarget(self, action: #selector(toggleFullScreen), for: .touchUpInside)
        view.addSubview(full)
        view.bringSubviewToFront(full)

        let trailing = full.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12)
        NSLayoutConstraint.activate([
            trailing,
            full.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            full.widthAnchor.constraint(equalToConstant: 36),
            full.heightAnchor.constraint(equalToConstant: 36)
        ])
        fullScreenTrailingConstraint = trailing
        fullScreenButton = full

        let speed = UIButton(type: .system)
        speed.setTitle("1.0x", for: .normal)
        speed.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        speed.setTitleColor(.white, for: .normal)
        speed.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        speed.layer.cornerRadius = 6
        speed.translatesAutoresizingMaskIntoConstraints = false
        speed.addTarget(self, action: #selector(toggleSpeedMenu), for: .touchUpInside)
        speed.isHidden = true
        view.addSubview(speed)
        view.bringSubviewToFront(speed)

        NSLayoutConstraint.activate([
            speed.trailingAnchor.constraint(equalTo: full.leadingAnchor, constant: -20),
            speed.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            speed.widthAnchor.constraint(equalToConstant: 48),
            speed.heightAnchor.constraint(equalToConstant: 36)
        ])
        speedButton = speed
    }

    private func setupSpeedHintLabel() {
        let label = UILabel()
        label.text = "2x快进中"
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        view.addSubview(label)
        view.bringSubviewToFront(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 80),
            label.widthAnchor.constraint(equalToConstant: 120),
            label.heightAnchor.constraint(equalToConstant: 40)
        ])
        speedHintLabel = label
    }

    @objc private func toggleFullScreen() {
        isFullScreen.toggle()
        speedButton?.isHidden = !isFullScreen
        fullScreenTrailingConstraint?.constant = isFullScreen ? -60 : -12
        NotificationCenter.default.post(name: NSNotification.Name("toggleEpisodeList"), object: nil)

        if isFullScreen {
            let screen = UIScreen.main.bounds
            UIView.animate(withDuration: 0.3) {
                self.view.transform = CGAffineTransform(rotationAngle: .pi / 2)
                self.view.frame = CGRect(x: 0, y: 0, width: screen.height, height: screen.width)
                self.view.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.3) {
                self.view.transform = .identity
                self.view.frame = self.originalFrame
                self.view.layoutIfNeeded()
            }
        }
    }

    @objc private func toggleSpeedMenu() {
        if speedMenuView != nil {
            dismissSpeedMenu()
        } else {
            showSpeedMenu()
        }
    }

    private func showSpeedMenu() {
        let menu = UIView()
        menu.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        menu.layer.cornerRadius = 12
        menu.layer.masksToBounds = true
        menu.translatesAutoresizingMaskIntoConstraints = false

        let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        var buttons: [UIButton] = []

        for rate in rates {
            let btn = UIButton(type: .system)
            btn.setTitle("\(rate)x", for: .normal)
            btn.setTitleColor(.white, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
            btn.tag = Int(rate * 100)
            btn.addTarget(self, action: #selector(speedSelected(_:)), for: .touchUpInside)
            buttons.append(btn)
        }

        let stack = UIStackView(arrangedSubviews: buttons)
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        menu.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: menu.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: menu.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: menu.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: menu.trailingAnchor, constant: -12)
        ])

        view.addSubview(menu)
        view.bringSubviewToFront(menu)

        NSLayoutConstraint.activate([
            menu.trailingAnchor.constraint(equalTo: speedButton!.leadingAnchor, constant: -12),
            menu.bottomAnchor.constraint(equalTo: speedButton!.topAnchor, constant: -8)
        ])

        speedMenuView = menu
    }

    private func dismissSpeedMenu() {
        speedMenuView?.removeFromSuperview()
        speedMenuView = nil
    }

    @objc private func speedSelected(_ sender: UIButton) {
        let rate = Float(sender.tag) / 100.0
        setRate(rate)
        dismissSpeedMenu()
    }

    private func setRate(_ rate: Float) {
        normalRate = rate
        speedButton?.setTitle("\(rate)x", for: .normal)
        player?.currentPlayerManager.rate = rate
    }

    private func addLongPressSpeedGesture() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        view.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            speedHintLabel?.isHidden = false
            player?.currentPlayerManager.rate = 2.0
        case .ended, .cancelled, .failed:
            speedHintLabel?.isHidden = true
            player?.currentPlayerManager.rate = normalRate
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