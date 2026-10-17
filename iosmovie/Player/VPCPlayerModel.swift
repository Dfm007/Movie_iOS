import AVFoundation
import Combine
import Foundation
import MediaPlayer
import SwiftUI
import UIKit
import VideoPlayerContainer

enum VPCPlaybackState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case ended
    case failed
}

final class VPCPlayerModel: ObservableObject {
    let context = Context()
    /// 高频播放状态：只由进度条、时间标签和提示层订阅。
    let metrics = VPCPlaybackMetrics()
    let hint = VPCGestureHintModel()
    let movieTitle: String

    @Published var currentSource: PlaySource
    @Published var isFullScreen = false
    @Published var errorMessage: String?
    @Published var isDanmakuVisible = true
    @Published var state: VPCPlaybackState = .idle
    @Published var controlsVisible = true
    @Published var isLocked = false

    var allSources: [PlaySource]
    var onProgress: (Double, Double) -> Void
    var onClose: () -> Void

    private var startAt: Double
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var loadedRangeObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var keepUpObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var didApplyStartPosition = false
    private var didConfigure = false
    private var failedSourceIDs: Set<String> = []
    private var gestureCancellables = Set<AnyCancellable>()
    private var metricsCancellables = Set<AnyCancellable>()
    private var lastReportedProgressTime: Double = -1
    private var handledFailureItemID: ObjectIdentifier?
    private var dragStartTime: Double?
    private var horizontalDragLastTime: Date?
    private var horizontalDragLastTranslation: CGFloat = 0
    private var horizontalDragTargetTime: Double = 0
    private var dragStartBrightness: CGFloat?
    private var dragStartVolume: Float?
    private var previousRate: Float = 1
    private var controlsHideWorkItem: DispatchWorkItem?
    private var longPressActive = false

    /// 手势防误触：位移超过阈值且方向明显占优后才开始处理。
    private static let horizontalDragActivationDistance: CGFloat = 20
    private static let verticalDragActivationDistance: CGFloat = 14
    private static let dragDirectionDominance: CGFloat = 1.15

    init(
        movieTitle: String,
        source: PlaySource,
        allSources: [PlaySource],
        startAt: Double,
        onProgress: @escaping (Double, Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.movieTitle = movieTitle
        self.currentSource = source
        self.allSources = allSources
        self.startAt = startAt
        self.onProgress = onProgress
        self.onClose = onClose
    }

    var displayTitle: String {
        let episode = currentSource.name.isEmpty ? "正片" : currentSource.name
        if movieTitle.isEmpty { return episode }
        return "\(movieTitle) · \(episode)"
    }

    func start() {
        guard !didConfigure else { return }
        didConfigure = true

        context.status.toHalfScreen()
        context.render.player.actionAtItemEnd = .none
        context.container.enable(overlays: [.render])
        state = .loading

        installPlayerObservers()
        installGestureObservers()
        installMetricsObservers()
        showControls()
        load(source: currentSource, startAt: startAt)
    }

    func stop() {
        reportProgress()
        context.render.player.pause()

        if let timeObserver = timeObserver {
            context.render.player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        timeControlObservation = nil
        statusObservation = nil
        loadedRangeObservation = nil
        bufferEmptyObservation = nil
        keepUpObservation = nil
        gestureCancellables.removeAll()
        metricsCancellables.removeAll()
        controlsHideWorkItem?.cancel()
        controlsHideWorkItem = nil

        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver = failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }

        state = .idle
        metrics.reset()
        hint.clearImmediately()
    }

    func selectSource(_ source: PlaySource) {
        failedSourceIDs.removeAll()
        selectSourceForPlayback(source)
    }

    /// 播放失败后从当前进度重试当前播放源。
    func retry() {
        failedSourceIDs.remove(currentSource.id)
        errorMessage = nil
        let resumeAt = metrics.currentTime
        startAt = resumeAt
        didApplyStartPosition = false
        metrics.prepareForNewItem(startAt: resumeAt)
        load(source: currentSource, startAt: resumeAt)
    }

    private func selectSourceForPlayback(_ source: PlaySource, startAt: Double = 0) {
        currentSource = source
        self.startAt = max(startAt, 0)
        didApplyStartPosition = false
        errorMessage = nil
        metrics.prepareForNewItem(startAt: self.startAt)
        load(source: source, startAt: self.startAt)
    }

    func togglePlayPause() {
        guard !isLocked else { return }
        if context.render.player.rate == 0 {
            context.render.player.play()
        } else {
            context.render.player.pause()
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        let target = metrics.duration > 0 ? min(seconds, metrics.duration) : seconds
        metrics.applySeek(to: target)
        context.render.player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func setRate(_ rate: Float) {
        guard !isLocked else { return }
        context.render.player.rate = rate
    }

    func toggleDanmaku() {
        isDanmakuVisible.toggle()
    }

    func enterFullScreen() {
        guard !isFullScreen, !isLocked else { return }
        isFullScreen = true
        context.status.toFullScreen()
        showControls()
    }

    func exitFullScreen() {
        guard isFullScreen, !isLocked else { return }
        isFullScreen = false
        context.status.toHalfScreen()
        showControls()
    }

    func toggleLock() {
        isLocked.toggle()
        if isLocked {
            controlsVisible = false
            controlsHideWorkItem?.cancel()
            controlsHideWorkItem = nil
        } else {
            showControls()
        }
    }

    func toggleControls() {
        guard !isLocked else { return }
        controlsVisible.toggle()
        if controlsVisible {
            scheduleControlsHide()
        } else {
            controlsHideWorkItem?.cancel()
            controlsHideWorkItem = nil
        }
    }

    func showControls() {
        guard !isLocked else { return }
        controlsVisible = true
        scheduleControlsHide()
    }

    private func scheduleControlsHide() {
        controlsHideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.controlsVisible = false
        }
        controlsHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    func reportProgress() {
        onProgress(metrics.currentTime, metrics.duration)
    }

    private func load(source: PlaySource, startAt: Double) {
        guard let url = Self.assetURL(from: source.url) else {
            state = .failed
            errorMessage = "播放地址无效"
            return
        }

        state = .loading
        let item = AVPlayerItem(url: url)
        handledFailureItemID = nil
        lastReportedProgressTime = -1
        hint.clearImmediately()
        context.render.player.replaceCurrentItem(with: item)
        context.render.player.play()
        observeStatus(for: item)
        observeBuffering(for: item)
    }

    private func installPlayerObservers() {
        let player = context.render.player

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.updatePlaybackState(for: player)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self, let item = self.context.render.player.currentItem else { return }
            let seconds = max(0, time.seconds)
            let total = item.duration.seconds
            let safeDuration = total.isFinite && total > 0 ? total : 0
            // 失败后保留最后一次有效进度，避免 AVPlayer 回零覆盖续播位置。
            if self.state != .failed, item.status != .failed {
                self.metrics.update(currentTime: seconds, duration: safeDuration)
                if self.lastReportedProgressTime < 0 || abs(seconds - self.lastReportedProgressTime) >= 1 {
                    self.lastReportedProgressTime = seconds
                    self.onProgress(seconds, safeDuration)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let item = notification.object as? AVPlayerItem,
                  item === self.context.render.player.currentItem else { return }
            self.playNextEpisodeIfAvailable()
        }

        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let item = notification.object as? AVPlayerItem,
                  item === self.context.render.player.currentItem else { return }
            let message = item.error?.localizedDescription ?? "播放失败"
            self.handleFailure(message: message, for: item)
        }
    }

    private func observeStatus(for item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch observedItem.status {
                case .readyToPlay:
                    self.applyStartPositionIfNeeded()
                case .failed:
                    guard observedItem === self.context.render.player.currentItem else { return }
                    self.handleFailure(message: observedItem.error?.localizedDescription ?? "播放失败", for: observedItem)
                default:
                    break
                }
            }
        }
    }

    private func observeBuffering(for item: AVPlayerItem) {
        loadedRangeObservation = item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                self?.syncBufferedTime(for: item)
            }
        }

        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item === self.context.render.player.currentItem else { return }
                if item.isPlaybackBufferEmpty, self.context.render.player.rate > 0 {
                    self.state = .buffering
                }
            }
        }

        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self, item === self.context.render.player.currentItem else { return }
                self.updatePlaybackState(for: self.context.render.player)
            }
        }
    }

    /// 取包含当前播放位置的已缓冲区间末端；不连续区间不会把中间空洞算作已缓冲。
    private func syncBufferedTime(for item: AVPlayerItem) {
        guard item === context.render.player.currentItem else { return }
        let ranges = item.loadedTimeRanges
            .compactMap { $0.timeRangeValue }
            .filter {
                $0.start.seconds.isFinite &&
                CMTimeGetSeconds(CMTimeRangeGetEnd($0)).isFinite
            }
        guard !ranges.isEmpty else {
            metrics.updateBufferedTime(0)
            return
        }

        let current = max(metrics.currentTime, 0)
        let containingEnd = ranges
            .filter { range in
                let start = range.start.seconds
                let end = CMTimeGetSeconds(CMTimeRangeGetEnd(range))
                return start <= current + 0.5 && end >= current - 0.5
            }
            .map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) }
            .max()

        // 当前时间尚未落在任何缓冲段时，只回退到它之前最后一个缓冲段末端，
        // 不把中间存在空洞的远端缓冲算进来。
        let previousEnd = ranges
            .filter { $0.start.seconds <= current + 0.5 }
            .map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) }
            .max()
        metrics.updateBufferedTime(containingEnd ?? previousEnd ?? 0)
    }

    private func applyStartPositionIfNeeded() {
        guard !didApplyStartPosition else { return }
        didApplyStartPosition = true
        guard startAt > 1 else { return }
        let itemDuration = context.render.player.currentItem?.duration.seconds ?? 0
        let target = itemDuration.isFinite && itemDuration > 0
            ? min(startAt, max(itemDuration - 0.5, 0))
            : startAt
        seek(to: target)
    }

    private func playNextEpisodeIfAvailable() {
        guard let next = nextEpisode() else {
            state = .ended
            return
        }
        selectSource(next)
    }

    private func nextEpisode() -> PlaySource? {
        for group in allSources {
            guard let index = group.episodes.firstIndex(where: { $0.id == currentSource.id }),
                  index + 1 < group.episodes.count else { continue }
            return group.episodes[index + 1]
        }
        return nil
    }

    private func handleFailure(message: String, for item: AVPlayerItem) {
        guard item === context.render.player.currentItem else { return }
        let itemID = ObjectIdentifier(item)
        guard handledFailureItemID != itemID else { return }
        handledFailureItemID = itemID

        failedSourceIDs.insert(currentSource.id)
        let resumeAt = max(metrics.currentTime, 0)
        reportProgress()

        if let next = nextSourceForSameEpisode() {
            selectSourceForPlayback(next, startAt: resumeAt)
            return
        }

        state = .failed
        errorMessage = message
    }

    private func updatePlaybackState(for player: AVPlayer) {
        if player.currentItem?.status == .failed {
            state = .failed
            return
        }

        switch player.timeControlStatus {
        case .playing:
            state = .playing
        case .paused:
            state = player.currentItem?.status == .readyToPlay ? .paused : .loading
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
        @unknown default:
            state = .loading
        }
    }

    private func installGestureObservers() {
        context.gesture.observe(.tap(.all)) { [weak self] _ in
            self?.toggleControls()
        }.store(in: &gestureCancellables)

        context.gesture.observe(.drag(.horizontal)) { [weak self] event in
            self?.handleHorizontalDrag(event)
        }.store(in: &gestureCancellables)

        context.gesture.observe(.drag(.vertical(.left))) { [weak self] event in
            self?.handleBrightnessDrag(event)
        }.store(in: &gestureCancellables)

        context.gesture.observe(.drag(.vertical(.right))) { [weak self] event in
            self?.handleVolumeDrag(event)
        }.store(in: &gestureCancellables)
    }

    private func installMetricsObservers() {
        metrics.$isDragging
            .removeDuplicates()
            .sink { [weak self] dragging in
                guard let self else { return }
                if dragging {
                    self.controlsHideWorkItem?.cancel()
                    self.controlsHideWorkItem = nil
                } else if self.controlsVisible {
                    self.showControls()
                }
            }
            .store(in: &metricsCancellables)
    }

    private func seek(by delta: Double) {
        guard !isLocked else { return }
        guard metrics.duration.isFinite, metrics.duration > 0 else { return }
        let target = min(max(metrics.currentTime + delta, 0), metrics.duration)
        seek(to: target)
        hint.show(delta > 0 ? "快进 10 秒" : "后退 10 秒")
        hint.clear(after: 0.6)
    }

    private func handleHorizontalDrag(_ event: GestureService.GestureEvent) {
        guard !isLocked, !metrics.isDragging else { return }
        guard case let .drag(value) = event.value else { return }
        guard metrics.duration.isFinite, metrics.duration > 0 else { return }

        // 底部是进度条区域，避免和进度条自身的拖动手势重复处理。
        let height = CGFloat(context.viewSize.height)
        if height > 0, value.startLocation.y >= height - 64 {
            return
        }

        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if dragStartTime == nil {
            guard horizontalDistance >= Self.horizontalDragActivationDistance,
                  horizontalDistance > verticalDistance * Self.dragDirectionDominance else {
                return
            }
            dragStartTime = metrics.currentTime
            horizontalDragTargetTime = metrics.currentTime
            horizontalDragLastTime = value.time
            horizontalDragLastTranslation = value.translation.width
        } else {
            updateHorizontalDragTarget(with: value)
        }

        let target = horizontalDragTargetTime

        switch event.action {
        case .start:
            hint.show("\(VPCPlaybackMetrics.formatTime(target)) / \(VPCPlaybackMetrics.formatTime(metrics.duration))")
        case .end:
            guard dragStartTime != nil else { return }
            // 进度条自身正在拖动时，忽略播放器容器的水平拖动结束事件。
            if metrics.isDragging {
                resetHorizontalDragState()
                return
            }
            seek(to: horizontalDragTargetTime)
            resetHorizontalDragState()
            hint.clear(after: 0.6)
        }
    }

    /// 对齐 ZFPlayer 的水平手势：按拖动速度累计目标时间。
    private func updateHorizontalDragTarget(with value: DragGesture.Value) {
        guard let lastTime = horizontalDragLastTime else { return }
        let dt = max(value.time.timeIntervalSince(lastTime), 1.0 / 120.0)
        let dx = value.translation.width - horizontalDragLastTranslation
        let velocityX = Double(dx) / dt
        let next = horizontalDragTargetTime + velocityX / 200
        horizontalDragTargetTime = min(max(next, 0), metrics.duration)
        horizontalDragLastTime = value.time
        horizontalDragLastTranslation = value.translation.width
    }

    private func resetHorizontalDragState() {
        dragStartTime = nil
        horizontalDragLastTime = nil
        horizontalDragLastTranslation = 0
        horizontalDragTargetTime = 0
    }

    private func handleBrightnessDrag(_ event: GestureService.GestureEvent) {
        guard !isLocked else { return }
        guard case let .drag(value) = event.value else { return }

        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if dragStartBrightness == nil {
            guard verticalDistance >= Self.verticalDragActivationDistance,
                  verticalDistance > horizontalDistance * Self.dragDirectionDominance else {
                return
            }
            dragStartBrightness = UIScreen.main.brightness
        }

        let height = max(CGFloat(context.viewSize.height), 1)
        let delta = -Double(value.translation.height / height)
        let target = min(max(Double(dragStartBrightness ?? UIScreen.main.brightness) + delta, 0), 1)
        UIScreen.main.brightness = CGFloat(target)
        hint.show("亮度 \(Int(target * 100))%")

        if event.action == .end {
            dragStartBrightness = nil
            hint.clear(after: 0.6)
        }
    }

    private func handleVolumeDrag(_ event: GestureService.GestureEvent) {
        guard !isLocked else { return }
        guard case let .drag(value) = event.value else { return }

        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)

        if dragStartVolume == nil {
            guard verticalDistance >= Self.verticalDragActivationDistance,
                  verticalDistance > horizontalDistance * Self.dragDirectionDominance else {
                return
            }
            dragStartVolume = AVAudioSession.sharedInstance().outputVolume
        }

        let height = max(CGFloat(context.viewSize.height), 1)
        let delta = Float(-value.translation.height / height)
        let target = min(max((dragStartVolume ?? AVAudioSession.sharedInstance().outputVolume) + delta, 0), 1)
        Self.setSystemVolume(target)
        hint.show("音量 \(Int(target * 100))%")

        if event.action == .end {
            dragStartVolume = nil
            hint.clear(after: 0.6)
        }
    }

    func setLongPressActive(_ active: Bool) {
        guard !isLocked else { return }
        if active {
            guard !longPressActive, context.render.player.rate > 0 else { return }
            longPressActive = true
            previousRate = context.render.player.rate > 0 ? context.render.player.rate : 1
            context.render.player.rate = 2
            hint.show("2x 快进中")
        } else {
            guard longPressActive else { return }
            longPressActive = false
            context.render.player.rate = previousRate
            hint.clear(after: 0.6)
        }
    }

    func handleDoubleTap(at x: CGFloat) {
        let width = CGFloat(context.viewSize.width)
        guard !isLocked, width > 0 else { return }
        let ratio = x / width
        if ratio < 0.2 {
            seek(by: -10)
        } else if ratio < 0.8 {
            togglePlayPause()
        } else {
            seek(by: 10)
        }
    }

    private static let volumeView = MPVolumeView(frame: .zero)

    private static func setSystemVolume(_ value: Float) {
        if volumeView.superview == nil,
           let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow }) {
            volumeView.frame = CGRect(x: -1000, y: -1000, width: 10, height: 10)
            window.addSubview(volumeView)
        }
        let slider = volumeView.subviews.compactMap { $0 as? UISlider }.first
        slider?.value = min(max(value, 0), 1)
    }

    private func nextSourceForSameEpisode() -> PlaySource? {
        guard let currentGroup = allSources.first(where: { group in
                  group.episodes.contains(where: { $0.id == currentSource.id })
              }),
              let currentIndex = currentGroup.episodes.firstIndex(where: { $0.id == currentSource.id }) else {
            return nil
        }
        let currentEpisode = currentGroup.episodes[currentIndex]

        for group in allSources where group.id != currentGroup.id {
            if let sameName = group.episodes.first(where: {
                $0.name == currentEpisode.name && !failedSourceIDs.contains($0.id)
            }) {
                return sameName
            }
            if currentIndex < group.episodes.count {
                let candidate = group.episodes[currentIndex]
                if !failedSourceIDs.contains(candidate.id) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func assetURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("file://") { return URL(string: trimmed) }
        if let url = URL(string: trimmed) { return url }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encoded) { return url }
        return URL(fileURLWithPath: trimmed)
    }
}
