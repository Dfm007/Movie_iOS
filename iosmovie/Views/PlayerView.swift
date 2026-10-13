import SwiftUI
import AVKit
import UIKit

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    /// 起播位置（秒），0 = 从头播。只有首次加载生效，切集自动归零。
    var startAt: Double = 0
    /// 播放位置回报 (当前播放位置, 总时长)，供续播记录使用；可能被调用一次以上，写入要幂等
    var onProgress: (Double, Double) -> Void
    /// 用户点了关闭按钮
    var onClose: () -> Void
    @State private var currentSource: PlaySource

    private let episodeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(
        source: PlaySource,
        allSources: [PlaySource] = [],
        startAt: Double = 0,
        onProgress: @escaping (Double, Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.source = source
        self.allSources = allSources
        self.startAt = startAt
        self.onProgress = onProgress
        self.onClose = onClose
        _currentSource = State(initialValue: source)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZFPlayerRepresentable(
                url: currentSource.url,
                startAt: startAt,
                onProgress: onProgress,
                onClose: onClose,
                episodeGroups: allSources,
                currentSourceID: currentSource.id,
                onEpisodeSelected: { selected in
                    currentSource = selected
                }
            )
            .frame(height: UIScreen.main.bounds.width * 9 / 16)
            .background(Color.black)

            episodeListView
        }
        .background(AppTheme.background)
    }

    private var episodeListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(allSources) { group in
                    if group.episodes.isEmpty {
                        Button(action: { currentSource = group }) {
                            Text(group.name)
                                .font(.subheadline)
                                .foregroundColor(currentSource.id == group.id ? .white : AppTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(currentSource.id == group.id ? AppTheme.accent : AppTheme.mutedFill)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                        }
                    } else {
                        Text(group.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: episodeColumns, spacing: 8) {
                            ForEach(group.episodes) { episode in
                                Button(action: { currentSource = episode }) {
                                    Text(episode.name)
                                        .font(.caption)
                                        .foregroundColor(currentSource.id == episode.id ? .white : AppTheme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(currentSource.id == episode.id ? AppTheme.accent : AppTheme.mutedFill)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background)
    }
}

struct ZFPlayerRepresentable: UIViewControllerRepresentable {
    let url: String
    var startAt: Double = 0
    var onProgress: (Double, Double) -> Void
    var onClose: () -> Void
    var episodeGroups: [PlaySource] = []
    var currentSourceID: String = ""
    var onEpisodeSelected: ((PlaySource) -> Void)? = nil

    func makeUIViewController(context: Context) -> ZFPlayerViewController {
        let vc = ZFPlayerViewController()
        vc.playURLString = url
        vc.startAt = startAt
        vc.onProgress = onProgress
        vc.onClose = onClose
        vc.episodeGroups = episodeGroups
        vc.currentSourceID = currentSourceID
        vc.onEpisodeSelected = onEpisodeSelected
        return vc
    }

    func updateUIViewController(_ uiViewController: ZFPlayerViewController, context: Context) {
        uiViewController.playURLString = url
        uiViewController.onProgress = onProgress
        uiViewController.onClose = onClose
        uiViewController.episodeGroups = episodeGroups
        uiViewController.currentSourceID = currentSourceID
        uiViewController.onEpisodeSelected = onEpisodeSelected
        uiViewController.restartIfNeeded()
    }
}

final class ZFPlayerViewController: UIViewController {
    var playURLString: String = ""
    /// 起播位置（秒），0 = 从头播
    var startAt: Double = 0
    /// 回报 (播放位置, 总时长)，用于续播记录
    var onProgress: ((Double, Double) -> Void)?
    /// 用户主动关闭
    var onClose: (() -> Void)?
    var episodeGroups: [PlaySource] = []
    var currentSourceID: String = ""
    var onEpisodeSelected: ((PlaySource) -> Void)?
    private var playerManager: ZFAVPlayerManager?
    private var player: ZFPlayerController?
    private var lastURLString: String = ""
    private var closeButton: UIButton?
    private var fullScreenButton: UIButton?
    private var speedButton: UIButton?
    private var episodeDrawerButton: UIButton?
    private var normalRate: Float = 1.0
    private var speedHintLabel: UILabel?
    private var speedMenuView: UIView?
    private var isFullScreen = false
    private weak var fullScreenVC: FullScreenPlayerViewController?
    private var didBecomeReady = false
    private var loadWatchdog: DispatchWorkItem?
    /// 起播定位只做一次，避免用户手动拖动后被反复拽回
    private var didApplyStartPosition = false
    /// 持续记录播放位置，关闭时回报给上层做续播
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var didReportProgress = false
    private var lastSpeedMenuToken = 0

    override var shouldAutorotate: Bool { false }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
        setupFullScreenButton()
        setupEpisodeDrawerButton()
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

        // 加载成功：撤销看门狗，并按续播记录定位
        player.playerReadyToPlay = { [weak self] _, _ in
            guard let self else { return }
            self.didBecomeReady = true
            self.loadWatchdog?.cancel()
            self.loadWatchdog = nil
            self.applyStartPositionIfNeeded()
        }

        // 持续记录播放位置：关闭时回报给上层，用于续播
        player.playerPlayTimeChanged = { [weak self] _, currentTime, duration in
            guard let self else { return }
            self.currentTime = currentTime
            self.duration = duration
        }

        // 播放失败：弹出真实错误，而不是黑屏无反馈
        player.playerPlayFailed = { [weak self] _, error in
            guard let self else { return }
            self.loadWatchdog?.cancel()
            self.loadWatchdog = nil
            let message = (error as? NSError)?.localizedDescription ?? String(describing: error)
            self.showPlaybackFailure(message: message)
        }

        // 播放结束：自动连播同一剧集列表里的下一集（已是最后一集则停在结尾）
        player.playerDidToEnd = { [weak self] _ in
            self?.playNextEpisodeIfAvailable()
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

    /// 按续播记录跳到上次位置。只在首次 ready 时执行一次。
    private func applyStartPositionIfNeeded() {
        guard !didApplyStartPosition else { return }
        didApplyStartPosition = true
        guard startAt > 1 else { return }

        // 直接操作底层 AVPlayer 定位：ZFPlayerController 的 seekToTime: 只是转发给它，
        // 这样写可以避开 ObjC 方法导入 Swift 后的名字歧义（seek(toTime:) / seek(to:)）。
        guard let manager = player?.currentPlayerManager as? ZFAVPlayerManager else { return }
        let target = CMTime(seconds: startAt, preferredTimescale: 600)
        manager.player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// 回报播放位置，供上层写入续播记录。只回报一次。
    private func reportProgress() {
        guard !didReportProgress else { return }
        didReportProgress = true
        onProgress?(currentTime, duration)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 进/出全屏会把本 VC 的 view 迁移到另一个容器，那不是"关闭播放器"。
        // 这里只补记进度，绝不再触发关闭动作（避免误关）。
        guard !isFullScreen else { return }
        reportProgress()
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

    // MARK: - 自动连播

    /// 播完当前集后自动切到同一剧集列表里的下一集。
    /// 已是最后一集、或当前播放的是单集源（如「我的下载」里的单个文件）时不做任何处理，
    /// 保持停在结尾，由用户自己决定下一步。
    private func playNextEpisodeIfAvailable() {
        guard let next = nextEpisode() else { return }
        currentSourceID = next.id
        onEpisodeSelected?(next)
    }

    /// 在当前 sourceID 所属的剧集分组内取下一集。
    /// 只在本分组内连播，不跨源分组——不同源的剧集划分可能不一致，跨源容易跳错集。
    private func nextEpisode() -> PlaySource? {
        for group in episodeGroups {
            guard let index = group.episodes.firstIndex(where: { $0.id == currentSourceID }),
                  index + 1 < group.episodes.count else { continue }
            return group.episodes[index + 1]
        }
        return nil
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

    private func setupEpisodeDrawerButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "list.bullet"), for: .normal)
        button.setTitle("选集", for: .normal)
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        button.layer.cornerRadius = 18
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(showEpisodeDrawer), for: .touchUpInside)
        view.addSubview(button)
        episodeDrawerButton = button

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.widthAnchor.constraint(equalToConstant: 72),
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

    @objc private func showEpisodeDrawer() {
        guard !episodeGroups.isEmpty else { return }

        let picker = FullScreenEpisodePickerViewController()
        picker.groups = episodeGroups
        picker.currentSourceID = currentSourceID
        picker.onSelect = { [weak self] selected in
            self?.currentSourceID = selected.id
            self?.onEpisodeSelected?(selected)
        }
        picker.modalPresentationStyle = .pageSheet
        if let sheet = picker.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(picker, animated: true)
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
            self.episodeDrawerButton?.isHidden = false
            if let button = self.episodeDrawerButton {
                self.view.bringSubviewToFront(button)
            }
        }
    }

    @objc private func closeTapped() {
        if isFullScreen {
            exitFullScreen()
        } else {
            reportProgress()
            onClose?()
        }
    }

    func exitFullScreen() {
        guard isFullScreen, let fullVC = fullScreenVC else { return }
        isFullScreen = false

        episodeDrawerButton?.isHidden = true

        self.willMove(toParent: nil)
        self.view.removeFromSuperview()
        self.removeFromParent()

        fullVC.dismiss(animated: false) { [weak self] in
            guard let self = self else { return }
            self.view.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 9 / 16)
            self.view.autoresizingMask = []
        }
    }

    func updateSpeedMenuToken(_ token: Int) {
        guard token != lastSpeedMenuToken else { return }
        lastSpeedMenuToken = token
        toggleSpeedMenu()
    }

    func restartIfNeeded() {
        // 播放器还没建好时什么都不做：初始化流程自己会读 playURLString / startAt。
        // （若此时就改 lastURLString，会把续播的起播位置一并清掉。）
        guard player != nil else { return }
        guard playURLString != lastURLString else { return }
        lastURLString = playURLString

        // 切集/换源：从头播，不沿用上一集的续播位置
        startAt = 0
        didApplyStartPosition = false
        currentTime = 0
        duration = 0
        // 新的一集要重新上报进度，否则切集后关闭播放器不会再写续播记录
        didReportProgress = false

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
        if let episodes = episodeDrawerButton {
            view.bringSubviewToFront(episodes)
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

final class FullScreenEpisodePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var groups: [PlaySource] = []
    var currentSourceID: String = ""
    var onSelect: ((PlaySource) -> Void)?

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选集"
        view.backgroundColor = .systemGroupedBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        groups.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].name
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let group = groups[section]
        return group.episodes.isEmpty ? 1 : group.episodes.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        let group = groups[indexPath.section]
        let source = group.episodes.isEmpty ? group : group.episodes[indexPath.row]

        cell.textLabel?.text = source.name
        cell.textLabel?.textColor = .label
        cell.accessoryType = source.id == currentSourceID ? .checkmark : .none
        cell.tintColor = .systemBlue
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let group = groups[indexPath.section]
        let source = group.episodes.isEmpty ? group : group.episodes[indexPath.row]
        onSelect?(source)
        dismiss(animated: true)
    }
}
