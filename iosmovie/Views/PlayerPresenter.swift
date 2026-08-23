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
        if isPresented, host.presentedViewController == nil {
            let vc = PlayerHostingController(source: source, allSources: allSources) { [weak host] in
                host?.dismiss(animated: true) {
                    isPresented = false
                }
            }
            vc.modalPresentationStyle = .fullScreen
            host.present(vc, animated: true)
        } else if !isPresented, host.presentedViewController != nil {
            host.dismiss(animated: true)
        }
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