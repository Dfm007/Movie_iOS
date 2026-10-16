import Combine
import Foundation

/// 手势提示单独成模型，亮度/音量/快进提示变化时不会刷新进度条。
final class VPCGestureHintModel: ObservableObject {
    @Published private(set) var text: String?

    private var hintWorkItem: DispatchWorkItem?

    func show(_ text: String) {
        hintWorkItem?.cancel()
        hintWorkItem = nil
        self.text = text
    }

    func clear(after delay: TimeInterval = 0.6) {
        hintWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.text = nil
        }
        hintWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func clearImmediately() {
        hintWorkItem?.cancel()
        hintWorkItem = nil
        text = nil
    }
}
