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

    func present(source: PlaySource, allSources: [PlaySource], onClose: @escaping () -> Void) {
        guard playerWindow == nil else { return }
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        let vc = PlayerViewController(source: source, allSources: allSources) { [weak self] in
            self?.dismiss()
            onClose()
        }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = vc
        window.windowLevel = .normal + 1
        window.makeKeyAndVisible()
        playerWindow = window
    }

    func dismiss() {
        playerWindow?.isHidden = true
        playerWindow = nil
    }
}
