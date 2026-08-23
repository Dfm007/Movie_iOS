import SwiftUI
import AVKit
import UIKit

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    var onClose: () -> Void
    @State private var currentSource: PlaySource

    private let episodeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

init(source: PlaySource, allSources: [PlaySource] = [], onClose: @escaping () -> Void) {
    self.source = source
    self.allSources = allSources
    self.onClose = onClose
    _currentSource = State(initialValue: source)
}

    var body: some View {
        VStack(spacing: 0) {
            ZFPlayerRepresentable(url: currentSource.url)
                .frame(height: UIScreen.main.bounds.width * 9 / 16)
                .background(Color.black)

            episodeListView
        }
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            Button(action: { onClose() }) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }

    private var episodeListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(allSources) { group in
                    if group.episodes.isEmpty {
                        Button(action: {
                            currentSource = group
                        }) {
                            Text(group.name)
                                .font(.subheadline)
                                .foregroundColor(currentSource.id == group.id ? .white : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(currentSource.id == group.id ? Color.blue : Color.gray.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else {
                        Text(group.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: episodeColumns, spacing: 8) {
                            ForEach(group.episodes) { episode in
                                Button(action: {
                                    currentSource = episode
                                }) {
                                    Text(episode.name)
                                        .font(.caption)
                                        .foregroundColor(currentSource.id == episode.id ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(currentSource.id == episode.id ? Color.blue : Color.gray.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .background(Color.white)
    }
}

struct ZFPlayerRepresentable: UIViewControllerRepresentable {
    let url: String

    func makeUIViewController(context: Context) -> ZFPlayerViewController {
        let vc = ZFPlayerViewController()
        vc.playURLString = url
        return vc
    }

    func updateUIViewController(_ uiViewController: ZFPlayerViewController, context: Context) {
        uiViewController.playURLString = url
        uiViewController.restartIfNeeded()
    }
}

final class ZFPlayerViewController: UIViewController {
    var playURLString: String = ""
    private var player: ZFPlayerController?
    private var lastURLString: String = ""

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupPlayer()
        setupCustomFullScreenButton()
    }

    private func setupPlayer() {
        lastURLString = playURLString

        let manager = ZFAVPlayerManager()
        let player = ZFPlayerController(playerManager: manager, containerView: view)
        let controlView = ZFPlayerControlView()
        player.controlView = controlView
        controlView.portraitControlView.fullScreenBtn.isHidden = true
        self.player = player

        if let url = URL(string: playURLString) {
            manager.assetURL = url
        }
        player.playTheIndex(0)
    }

    private func setupCustomFullScreenButton() {
        let button = UIButton(type: .system)
        button.setTitle("全屏", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(toggleFullScreen), for: .touchUpInside)
        view.addSubview(button)
        view.bringSubviewToFront(button)

        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 64),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

@objc private func toggleFullScreen() {
    // 第 1 步：确认按钮点击已触发
    let alert = UIAlertController(title: "debug 1", message: "按钮点击已触发", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "继续", style: .default) { _ in
        // 第 2 步：拿 windowScene
        guard let windowScene = self.view.window?.windowScene else {
            let err = UIAlertController(title: "debug 2", message: "失败：拿不到 windowScene", preferredStyle: .alert)
            err.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(err, animated: true)
            return
        }

        let isLandscape = windowScene.interfaceOrientation.isLandscape
        let target: UIInterfaceOrientationMask = isLandscape ? .portrait : .landscapeRight

        let info = UIAlertController(title: "debug 3", message: "当前：\(isLandscape ? "横屏" : "竖屏")，目标：\(target == .portrait ? "竖屏" : "横屏")", preferredStyle: .alert)
        info.addAction(UIAlertAction(title: "继续", style: .default) { _ in
            // 第 3 步：请求横屏
            if #available(iOS 16.0, *) {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { error in
                    DispatchQueue.main.async {
                        let fail = UIAlertController(title: "debug 4", message: "requestGeometryUpdate 失败：\(error.localizedDescription)", preferredStyle: .alert)
                        fail.addAction(UIAlertAction(title: "OK", style: .default))
                        self.present(fail, animated: true)
                    }
                }
            }
        })
        self.present(info, animated: true)
    })
    present(alert, animated: true)
}

    func restartIfNeeded() {
        guard playURLString != lastURLString else { return }
        player?.stop()
        setupPlayer()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player?.stop()
    }
}