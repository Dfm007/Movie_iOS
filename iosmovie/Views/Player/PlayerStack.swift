import DanmakuKit
import VideoPlayerContainer

@available(iOS 16.0, *)
enum PlayerStack {
    static func makeContext() -> Context {
        Context()
    }

    static func makeDanmakuCoordinator() -> DanmakuViewAdapter.Coordinator {
        DanmakuViewAdapter.Coordinator()
    }
}
