import SwiftUI
import UIKit

struct PlayerPresenter: UIViewControllerRepresentable {
    let source: PlaySource
    let allSources: [PlaySource]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .clear
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        if isPresented {
            PlayerWindowPresenter.shared.present(source: source, allSources: allSources) {
                isPresented = false
            }
        }
    }
}

final class PlayerWindowPresenter {
    static let shared = PlayerWindowPresenter()
    private var playerWindow: UIWindow?
    private var playerVC: PlayerHostingController?

    func present(source: PlaySource, allSources: [PlaySource], onClose: @escaping () -> Void) {
        guard playerWindow == nil else { return }
        guard let windowScene = Self.activeWindowScene() else { return }

        let vc = PlayerHostingController(source: source, allSources: allSources) { [weak self] in
            self?.dismiss()
            onClose()
        }
        playerVC = vc

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = vc
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        playerWindow = window
    }

    func dismiss() {
        playerWindow?.isHidden = true
        playerWindow = nil
        playerVC = nil
        // 让原 SwiftUI 主 window 重新成为 key window
        Self.keyWindow()?.makeKey()
    }

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

final class PlayerHostingController: UIHostingController<PlayerView> {
    init(source: PlaySource, allSources: [PlaySource], onClose: @escaping () -> Void) {
        super.init(rootView: PlayerView(source: source, allSources: allSources, onClose: onClose))
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    override var shouldAutorotate: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        .portrait
    }
}