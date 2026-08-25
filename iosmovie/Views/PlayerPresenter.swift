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
    private var previousRoot: UIViewController?
    private var playerVC: PlayerHostingController?

    func present(source: PlaySource, allSources: [PlaySource], onClose: @escaping () -> Void) {
        guard playerVC == nil else { return }
        guard let window = Self.keyWindow() else { return }

        previousRoot = window.rootViewController

        let vc = PlayerHostingController(source: source, allSources: allSources) { [weak self] in
            self?.dismiss()
            onClose()
        }
        playerVC = vc
        window.rootViewController = vc
    }

    func dismiss() {
        guard let window = Self.keyWindow() else { return }
        if let previousRoot {
            window.rootViewController = previousRoot
        }
        playerVC = nil
        previousRoot = nil
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
