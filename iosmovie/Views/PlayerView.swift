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
            ZFPlayerRepresentable(url: currentSource.url, onClose: onClose)
                .frame(height: hideEpisodeList ? UIScreen.main.bounds.height : UIScreen.main.bounds.width * 9 / 16)
                .background(Color.black)

            if !hideEpisodeList {
                episodeListView
            }
        }
        .background(Color.white)
    }

    private var episodeListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(allSources) { group in
                    if group.episodes.isEmpty {
                        Button(action: { currentSource = group }) {
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
                                Button(action: { currentSource = episode }) {
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
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> ZFPlayerViewController {
        let vc = ZFPlayerViewController()
        vc.playURLString = url
        vc.onClose = onClose
        return vc
    }

    func updateUIViewController(_ uiViewController: ZFPlayerViewController, context: Context) {
        uiViewController.playURLString = url
        uiViewController.onClose = onClose
        uiViewController.restartIfNeeded()
    }
}

final class ZFPlayerViewController: UIViewController {
    var playURLString: String = ""
    var onClose: (() -> Void)?
    private var playerManager: ZFAVPlayerManager?
    private var player: ZFPlayerController?
    private var lastURLString: String = ""
    private var closeButton: UIButton?
    private var fullScreenButton: UIButton?
    private var speedButton: UIButton?
    private var normalRate: Float = 1.0
    private var speedHintLabel: UILabel?
    private var speedMenuView: UIView?
    private var isFullScreen = false
    private weak var fullScreenVC: FullScreenPlayerViewController?
    private var didBecomeReady = false
    private var loadWatchdog: DispatchWorkItem?

    override var shouldAutorotate: Bool { false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
        setupFullScreenButton()
        setupCloseButton()
        setupSpeedButton()
        setupSpeedHintLabel()
    }

    deinit {
        loadWatchdog?.cancel()
    }

    // MARK: - URL 构造

    /// 本地缓存文件走 file://，网络地址走 http(s)://
    /// 关键：不能把 absoluteString 去掉 scheme 再用 fileURLWithPath 还原，
    /// 中文/空格会被百分号编码两次导致文件找不到（黑屏元凶之一）。
    static func assetURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }
        if let url = URL(string: trimmed) { return url }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) { return url }
        return URL(fileURLWithPath: trimmed)
    }

    // MARK: - 播放器

    private func setupPlayer() {
        lastURLString = playURLString
        let manager = ZFAVPlayerManager()
        self.playerManager = manager
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        let controlView = ZFPlayerControlView()
        player.controlView = controlView
        controlView.portraitControlView.fullScreenBtn.isHidden = true
        self.player = player

        // 加载成功：撤销看门狗
        player.playerReadyToPlay = { [weak self] _, _ in
            guard let self else { return }
            self.didBecomeReady = true
            self.loadWatchdog?.cancel()
            self.loadWatchdog = nil
        }

        // 播放失败：弹出真实错误，而不是黑屏无反馈
        player.playerPlayFailed = { [weak self] _, error in
            guard let self else { return }
            self.loadWatchdog?.cancel()
            self.loadWatchdog = nil
            let message = (error as? NSError)?.localizedDescription ?? String(describing: error)
            self.showPlaybackFailure(message: message)
        }

        guard let assetURL = Self.assetURL(from: playURLString) else {
            showPlaybackFailure(message: "播放地址无效：\(playURLString)")
            return
        }

        // 设置 assetURL 会触发 prepareToPlay → initializePlayer → 自动播放
        manager.assetURL = assetURL
        scheduleLoadWatchdog()

        addLongPressSpeedGesture()
    }

    /// 20 秒仍未 ready 且没有失败回调时给出明确提示（旧实现这里只有黑屏）
    private func scheduleLoadWatchdog() {
        loadWatchdog?.cancel()
        didBecomeReady = false
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.didBecomeReady else { return }
            guard self.presentedViewController == nil else { return }
            self.showPlaybackFailure(
                message: "视频长时间未能加载。缓存文件可能不完整，建议删除后重新下载。"
            )
        }
        loadWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func showPlaybackFailure(message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(
            title: "播放失败",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    private func setupFullScreenButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(fullScreenTapped), for: .touchUpInside)
        view.addSubview(button)
        view.bringSubviewToFront(button)
        self.fullScreenButton = button

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func setupCloseButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(button)
        view.bringSubviewToFront(button)
        self.closeButton = button

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func setupSpeedButton() {
        let speed = UIButton(type: .system)
        speed.setTitle("1.0x", for: .normal)
        speed.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        speed.setTitleColor(.white, for: .normal)
        speed.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        speed.layer.cornerRadius = 6
        speed.translatesAutoresizingMaskIntoConstraints = false
        speed.addTarget(self, action: #selector(toggleSpeedMenu), for: .touchUpInside)
        view.addSubview(speed)
        view.bringSubviewToFront(speed)
        speedButton = speed

        NSLayoutConstraint.activate([
            speed.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60),
            speed.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            speed.widthAnchor.constraint(equalToConstant: 48),
            speed.heightAnchor.constraint(equalToConstant: 36)
        ])
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
        speedHintLabel = label

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.topAnchor, constant: 80),
            label.widthAnchor.constraint(equalToConstant: 120),
            label.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    @objc private func fullScreenTapped() {
        if isFullScreen {
            exitFullScreen()
        } else {
            presentFullScreen()
        }
    }

    private func presentFullScreen() {
        guard !isFullScreen else { return }
        isFullScreen = true

        let fullVC = FullScreenPlayerViewController()
        fullVC.modalPresentationStyle = .fullScreen
        fullVC.onClose = { [weak self] in
            self?.isFullScreen = false
        }
        fullScreenVC = fullVC

        present(fullVC, animated: false) { [weak self] in
            guard let self = self else { return }

            fullVC.addChild(self)
            self.view.frame = fullVC.view.bounds
            self.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            fullVC.view.addSubview(self.view)
            self.didMove(toParent: fullVC)
        }
    }

    @objc private func closeTapped() {
        if isFullScreen {
            exitFullScreen()
        } else {
            onClose?()
        }
    }

    func exitFullScreen() {
        guard isFullScreen, let fullVC = fullScreenVC else { return }
        isFullScreen = false

        self.willMove(toParent: nil)
        self.view.removeFromSuperview()
        self.removeFromParent()

        fullVC.dismiss(animated: false) { [weak self] in
            guard let self = self else { return }
            self.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 9 / 16)
            self.view.autoresizingMask = []
        }
    }

    func restartIfNeeded() {
        guard playURLString != lastURLString else { return }
        lastURLString = playURLString

        guard let assetURL = Self.assetURL(from: playURLString) else {
            showPlaybackFailure(message: "播放地址无效：\(playURLString)")
            return
        }

        playerManager?.assetURL = assetURL
        scheduleLoadWatchdog()

        // 重新把控件提到最前
        if let close = closeButton {
            view.bringSubviewToFront(close)
        }
        if let fullScreen = fullScreenButton {
            view.bringSubviewToFront(fullScreen)
        }
        if let speed = speedButton {
            view.bringSubviewToFront(speed)
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

        if let speed = speedButton {
            NSLayoutConstraint.activate([
                menu.trailingAnchor.constraint(equalTo: speed.leadingAnchor, constant: -12),
                menu.bottomAnchor.constraint(equalTo: speed.topAnchor, constant: -8)
            ])
        }

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
}

final class FullScreenPlayerViewController: UIViewController {
    var onClose: (() -> Void)?

    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }
}
