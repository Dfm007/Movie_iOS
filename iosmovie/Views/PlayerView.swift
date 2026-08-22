import SwiftUI
import AVKit
import UIKit

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(12)
                }
                Spacer()
                Text(source.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            .background(Color.black)

            ZFPlayerRepresentable(url: source.url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

struct ZFPlayerRepresentable: UIViewControllerRepresentable {
    let url: String

    func makeUIViewController(context: Context) -> ZFPlayerViewController {
        let vc = ZFPlayerViewController()
        vc.playURLString = url
        return vc
    }

    func updateUIViewController(_ uiViewController: ZFPlayerViewController, context: Context) {}
}

final class ZFPlayerViewController: UIViewController {
    var playURLString: String = ""
    private var player: ZFPlayerController?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let manager = ZFAVPlayerManager()
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        player.controlManager = ZFPlayerControlView()
        self.player = player

        if let url = URL(string: playURLString) {
            manager.assetURL = url
        }
        player.playTheIndex(0)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.stop()
    }
}
