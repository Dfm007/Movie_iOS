import SwiftUI
import UIKit

@main
struct iosmovieApp: App {
    var body: some Scene {
        WindowGroup {
            RotationContainer {
                HomeView()
            }
            .ignoresSafeArea()
        }
    }
}

struct RotationContainer<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> RotationHostingController<Content> {
        RotationHostingController(rootView: content)
    }

    func updateUIViewController(_ uiViewController: RotationHostingController<Content>, context: Context) {
        uiViewController.rootView = content
    }
}

final class RotationHostingController<Content: View>: UIHostingController<Content> {
    override var shouldAutorotate: Bool {
        true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .allButUpsideDown
    }
}
