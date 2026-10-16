import AVFoundation
import Combine
import DanmakuKit
import Foundation
import SwiftUI
import UIKit
import VideoPlayerContainer

final class VPCPlayerModel: ObservableObject {
    let context = Context()
    let danmakuCoordinator = DanmakuViewAdapter.Coordinator()

    @Published var currentSource: PlaySource
    @Published var isFullScreen = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var errorMessage: String?

    var allSources: [PlaySource]
    var onProgress: (Double, Double) -> Void
    var onClose: () -> Void

    private var startAt: Double
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var didApplyStartPosition = false
    private var didConfigure = false
    private var failedSourceIDs: Set<String> = []

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
        context.container.configure(overlay: .render) { [weak self] in
            guard let self = self else { return AnyView(EmptyView()) }
            return AnyView(
                DanmakuViewAdapter(coordinator: self.danmakuCoordinator)
                    .allowsHitTesting(false)
            )
        }

        installPlayerObservers()
        load(source: currentSource, startAt: startAt)
    }

    func stop() {
        reportProgress()
        context.render.player.pause()

        if let timeObserver = timeObserver {
            context.render.player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        statusObservation = nil

        if let endObserver = endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        if let failObserver = failObserver {
            NotificationCenter.default.removeObserver(failObserver)
            self.failObserver = nil
        }
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
            errorMessage = "播放地址无效"
            return
        }

        let item = AVPlayerItem(url: url)
        context.render.player.replaceCurrentItem(with: item)
        context.render.player.play()
        observeStatus(for: item)
    }

    private func installPlayerObservers() {
        let player = context.render.player

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
        guard let next = nextEpisode() else { return }
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

        errorMessage = message
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
