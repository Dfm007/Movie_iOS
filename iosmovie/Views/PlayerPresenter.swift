import Combine
import SwiftUI
import UIKit

struct PlayerPresenter: UIViewControllerRepresentable {
    let title: String
    let source: PlaySource
    let allSources: [PlaySource]
    @Binding var isPresented: Bool
    /// 起播位置（秒），0 = 从头播
    var startAt: Double = 0
    /// 关闭时回报 (播放位置, 总时长)，供续播记录使用
    var onProgress: (Double, Double) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        if isPresented {
            PlayerWindowPresenter.shared.present(
                title: title,
                source: source,
                allSources: allSources,
                startAt: startAt,
                onProgress: onProgress
            ) {
                isPresented = false
            }
        }
    }
}

final class PlayerWindowPresenter {
    static let shared = PlayerWindowPresenter()
    private var playerVC: PlayerHostingController?

    func present(
        title: String,
        source: PlaySource,
        allSources: [PlaySource],
        startAt: Double = 0,
        onProgress: @escaping (Double, Double) -> Void = { _, _ in },
        onClose: @escaping () -> Void
    ) {
        guard playerVC == nil else { return }
        guard let top = Self.topViewController() else { return }

        let vc = PlayerHostingController(
            title: title,
            source: source,
            allSources: allSources,
            startAt: startAt,
            onProgress: onProgress
        ) { [weak self] in
            self?.dismiss()
            onClose()
        }
        vc.modalPresentationStyle = .fullScreen
        playerVC = vc
        top.present(vc, animated: false)
    }

    func dismiss() {
        playerVC?.dismiss(animated: false)
        playerVC = nil
    }

    private static func topViewController() -> UIViewController? {
        guard let root = keyWindow()?.rootViewController else { return nil }
        return topMost(from: root)
    }

    private static func topMost(from controller: UIViewController) -> UIViewController {
        if let presented = controller.presentedViewController {
            return topMost(from: presented)
        }
        if let nav = controller as? UINavigationController,
           let visible = nav.visibleViewController {
            return topMost(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return topMost(from: selected)
        }
        return controller
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

final class PlayerHostingController: UIHostingController<PlayerView> {
    private let orientationState: PlayerOrientationState
    private var orientationCancellable: AnyCancellable?

    init(
        title: String,
        source: PlaySource,
        allSources: [PlaySource],
        startAt: Double = 0,
        onProgress: @escaping (Double, Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        let orientationState = PlayerOrientationState()
        self.orientationState = orientationState
        super.init(
            rootView: PlayerView(
                title: title,
                source: source,
                allSources: allSources,
                startAt: startAt,
                orientationState: orientationState,
                onProgress: onProgress,
                onClose: onClose
            )
        )
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        orientationCancellable = orientationState.$isFullScreen
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAppDidBecomeActive() {
        guard orientationState.isFullScreen else { return }
        // 等 App 重新激活后的窗口布局完成，再请求一次横屏，避免被系统恢复成竖屏。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.orientationState.isFullScreen else { return }
            PlayerOrientation.setFullScreen(true)
        }
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        orientationState.isFullScreen ? .landscapeRight : .portrait
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        orientationState.isFullScreen ? .landscapeRight : .portrait
    }
}
