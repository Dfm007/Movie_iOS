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

    @Published var currentSource: PlaySource
    @Published var isFullScreen = false
    @Published var errorMessage: String?
    @Published var isDanmakuVisible = true
    @Published var state: VPCPlaybackState = .idle
    @Published var gestureHint: String?

    var allSources: [PlaySource]
    var onProgress: (Double, Double) -> Void
    var onClose: () -> Void

    private var startAt: Double
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var didApplyStartPosition = false
    private var didConfigure = false
    private var failedSourceIDs: Set<String> = []
    private var gestureCancellables = Set<AnyCancellable>()
    private var dragStartTime: Double?
    private var dragStartBrightness: CGFloat?
    private var dragStartVolume: Float?
    private var previousRate: Float = 1

    init(
        source: PlaySource,
        allSources: [PlaySource],
        startAt: Double,
        onProgress: @escaping (Double, Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.currentSource = source
        self.allSources = allSources
        self.startAt = startAt
        self.onProgress = onProgress
        self.onClose = onClose
    }

    func start() {
        guard !didConfigure else { return }
        didConfigure = true

        context.status.toHalfScreen()
        context.render.player.actionAtItemEnd = .none
        state = .loading

        installPlayerObservers()
        installGestureObservers()
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
        gestureCancellables.removeAll()

        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver = failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }

        state = .idle
    }

    func selectSource(_ source: PlaySource) {
        failedSourceIDs.removeAll()
        selectSourceForPlayback(source)
    }

    private func selectSourceForPlayback(_ source: PlaySource) {
        currentSource = source
        startAt = 0
        didApplyStartPosition = false
        errorMessage = nil
        load(source: source, startAt: 0)
    }

    func togglePlayPause() {
        if context.render.player.rate == 0 {
            context.render.player.play()
        } else {
            context.render.player.pause()
        }
    }

    func seek(to seconds: Double) {
        guard seconds.isFinite, seconds >= 0 else { return }
        context.render.player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func setRate(_ rate: Float) {
        context.render.player.rate = rate
    }

    func toggleDanmaku() {
        isDanmakuVisible.toggle()
    }

    func enterFullScreen() {
        guard !isFullScreen else { return }
        isFullScreen = true
        context.status.toFullScreen()
    }

    func exitFullScreen() {
        guard isFullScreen else { return }
        isFullScreen = false
        context.status.toHalfScreen()
    }

    func reportProgress() {
        onProgress(currentTime, duration)
    }

    private func load(source: PlaySource, startAt: Double) {
        guard let url = Self.assetURL(from: source.url) else {
            state = .failed
            errorMessage = "播放地址无效"
            return
        }

        state = .loading
        let item = AVPlayerItem(url: url)
        context.render.player.replaceCurrentItem(with: item)
        context.render.player.play()
        observeStatus(for: item)
    }

    private func installPlayerObservers() {
        let player = context.render.player

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.updatePlaybackState(for: player)
            }
        }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self = self, let item = self.context.render.player.currentItem else { return }
            let seconds = max(0, time.seconds)
            let total = item.duration.seconds
            self.currentTime = seconds
            self.duration = total.isFinite && total > 0 ? total : 0
            self.onProgress(self.currentTime, self.duration)
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
            self.handleFailure(message: message)
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
                    self.handleFailure(message: observedItem.error?.localizedDescription ?? "播放失败")
                default:
                    break
                }
            }
        }
    }

    private func applyStartPositionIfNeeded() {
        guard !didApplyStartPosition else { return }
        didApplyStartPosition = true
        guard startAt > 1 else { return }
        seek(to: startAt)
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

    private func handleFailure(message: String) {
        failedSourceIDs.insert(currentSource.id)

        if let next = nextSourceForSameEpisode() {
            selectSourceForPlayback(next)
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
        context.gesture.observe(.doubleTap(.left)) { [weak self] _ in
            self?.seek(by: -10)
        }.store(in: &gestureCancellables)

        context.gesture.observe(.doubleTap(.right)) { [weak self] _ in
            self?.seek(by: 10)
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

    private func seek(by delta: Double) {
        guard duration.isFinite, duration > 0 else { return }
        let target = min(max(currentTime + delta, 0), duration)
        seek(to: target)
        gestureHint = delta > 0 ? "快进 10 秒" : "后退 10 秒"
        clearGestureHintLater()
    }

    private func handleHorizontalDrag(_ event: GestureService.GestureEvent) {
        guard case let .drag(value) = event.value else { return }
        guard duration.isFinite, duration > 0 else { return }

        if dragStartTime == nil {
            dragStartTime = currentTime
        }

        let width = max(CGFloat(context.viewSize.width), 1)
        let delta = Double(value.translation.width / width) * duration
        let target = min(max((dragStartTime ?? currentTime) + delta, 0), duration)

        switch event.action {
        case .start:
            gestureHint = "\(Self.formatTime(target)) / \(Self.formatTime(duration))"
        case .end:
            seek(to: target)
            dragStartTime = nil
            clearGestureHintLater()
        }
    }

    private func handleBrightnessDrag(_ event: GestureService.GestureEvent) {
        guard case let .drag(value) = event.value else { return }
        if dragStartBrightness == nil {
            dragStartBrightness = UIScreen.main.brightness
        }

        let height = max(CGFloat(context.viewSize.height), 1)
        let delta = -Double(value.translation.height / height)
        let target = min(max(Double(dragStartBrightness ?? UIScreen.main.brightness) + delta, 0), 1)
        UIScreen.main.brightness = CGFloat(target)
        gestureHint = "亮度 \(Int(target * 100))%"

        if event.action == .end {
            dragStartBrightness = nil
            clearGestureHintLater()
        }
    }

    private func handleVolumeDrag(_ event: GestureService.GestureEvent) {
        guard case let .drag(value) = event.value else { return }
        if dragStartVolume == nil {
            dragStartVolume = AVAudioSession.sharedInstance().outputVolume
        }

        let height = max(CGFloat(context.viewSize.height), 1)
        let delta = Float(-value.translation.height / height)
        let target = min(max((dragStartVolume ?? AVAudioSession.sharedInstance().outputVolume) + delta, 0), 1)
        Self.setSystemVolume(target)
        gestureHint = "音量 \(Int(target * 100))%"

        if event.action == .end {
            dragStartVolume = nil
            clearGestureHintLater()
        }
    }

    func setLongPressActive(_ active: Bool) {
        if active {
            previousRate = context.render.player.rate > 0 ? context.render.player.rate : 1
            context.render.player.rate = 2
            gestureHint = "2x 快进中"
        } else {
            context.render.player.rate = previousRate
            clearGestureHintLater()
        }
    }

    private func clearGestureHintLater() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.gestureHint = nil
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
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
