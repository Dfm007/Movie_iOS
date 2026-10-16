import Combine
import Foundation

/// 播放器高频变化状态。
///
/// 播放时间、缓冲进度和拖动状态每秒会变化多次。集中放在这里，
/// 让进度条、时间标签和提示层各自订阅，避免整个播放页跟着重算。
final class VPCPlaybackMetrics: ObservableObject {
    /// 达到该时长视为长视频，拖动时额外显示大号预览。
    static let longVideoThreshold: Double = 20 * 60

    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var bufferedTime: Double = 0
    @Published private(set) var isDragging = false
    @Published private(set) var dragTargetTime: Double = 0

    private var dragStartPlaybackTime: Double = 0

    var isLongVideo: Bool {
        duration >= Self.longVideoThreshold
    }

    /// 拖动时优先显示手指目标位置，松手后回到真实播放位置。
    var displayTime: Double {
        isDragging ? dragTargetTime : currentTime
    }

    var playbackProgress: Double {
        progress(for: displayTime)
    }

    var bufferedProgress: Double {
        progress(for: bufferedTime)
    }

    /// 相对拖动开始时播放位置的偏移，用于长视频预览。
    var dragOffset: Double {
        dragTargetTime - dragStartPlaybackTime
    }

    func update(currentTime: Double, duration: Double) {
        self.currentTime = currentTime.isFinite ? max(0, currentTime) : 0
        self.duration = duration.isFinite && duration > 0 ? duration : 0
        if bufferedTime > self.duration {
            bufferedTime = self.duration
        }
    }

    func updateBufferedTime(_ seconds: Double) {
        guard seconds.isFinite else { return }
        let clamped = duration > 0 ? min(max(seconds, 0), duration) : max(seconds, 0)
        guard abs(clamped - bufferedTime) > 0.05 else { return }
        bufferedTime = clamped
    }

    func prepareForNewItem(startAt: Double) {
        currentTime = max(0, startAt)
        bufferedTime = 0
        isDragging = false
        dragTargetTime = currentTime
        dragStartPlaybackTime = currentTime
    }

    func beginDragging(to target: Double) {
        if !isDragging {
            dragStartPlaybackTime = currentTime
            isDragging = true
        }
        dragTargetTime = clamped(target)
    }

    func endDragging() {
        isDragging = false
        dragTargetTime = currentTime
    }

    func applySeek(to seconds: Double) {
        let target = clamped(seconds)
        currentTime = target
        dragTargetTime = target
        dragStartPlaybackTime = target
        isDragging = false
    }

    func reset() {
        currentTime = 0
        duration = 0
        bufferedTime = 0
        isDragging = false
        dragTargetTime = 0
        dragStartPlaybackTime = 0
    }

    // MARK: - 工具

    static func formatTime(_ seconds: Double) -> String {
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

    private func clamped(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        let nonNegative = max(seconds, 0)
        return duration > 0 ? min(nonNegative, duration) : nonNegative
    }

    private func progress(for seconds: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1)
    }
}

