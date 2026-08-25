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
    private var playerVC: PlayerHostingController?

    func present(source: PlaySource, allSources: [PlaySource], onClose: @escaping () -> Void) {
        guard playerVC == nil else { return }
        guard let top = Self.topViewController() else { return }

        let vc = PlayerHostingController(source: source, allSources: allSources) { [weak self] in
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
        .all
    }
}