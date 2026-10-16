import AVKit
import SwiftUI
import UIKit
import VideoPlayerContainer

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    var startAt: Double = 0
    var onProgress: (Double, Double) -> Void
    var onClose: () -> Void

    @StateObject private var model: VPCPlayerModel
    @State private var showEpisodePicker = false

    private let episodeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(
        source: PlaySource,
        allSources: [PlaySource] = [],
        startAt: Double = 0,
        onProgress: @escaping (Double, Double) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.source = source
        self.allSources = allSources
        self.startAt = startAt
        self.onProgress = onProgress
        self.onClose = onClose
        _model = StateObject(
            wrappedValue: VPCPlayerModel(
                source: source,
                allSources: allSources,
                startAt: startAt,
                onProgress: onProgress,
                onClose: onClose
            )
        )
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                playerWidget
                    .frame(maxWidth: .infinity)
                    .frame(height: model.isFullScreen ? nil : proxy.size.width * 9 / 16)
                    .frame(maxHeight: model.isFullScreen ? .infinity : nil)
                    .background(Color.black)
                    .ignoresSafeArea(edges: model.isFullScreen ? .all : [])

                if !model.isFullScreen {
                    episodeListView
                }
            }
        }
        .background(AppTheme.background)
        .onAppear { configurePlayer() }
        .onDisappear { model.stop() }
        .onChange(of: model.isFullScreen) { fullScreen in
            PlayerOrientation.setFullScreen(fullScreen)
        }
        .sheet(isPresented: $showEpisodePicker) {
            VPCEpisodePickerView(
                groups: model.allSources,
                currentSourceID: model.currentSource.id
            ) { selected in
                model.selectSource(selected)
            }
        }
        .alert(
            "播放失败",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var playerWidget: some View {
        PlayerWidget(model.context)
            .background(Color.black)
            .overlay {
                VPCDanmakuView()
                    .allowsHitTesting(false)
                    .opacity(model.isDanmakuVisible ? 1 : 0)
            }
    }

    private var episodeListView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.allSources) { group in
                    if group.episodes.isEmpty {
                        Button(action: { model.selectSource(group) }) {
                            Text(group.name)
                                .font(.subheadline)
                                .foregroundColor(model.currentSource.id == group.id ? .white : AppTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(model.currentSource.id == group.id ? AppTheme.accent : AppTheme.mutedFill)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                        }
                    } else {
                        Text(group.name)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(AppTheme.textSecondary)
                            .padding(.horizontal, 4)

                        LazyVGrid(columns: episodeColumns, spacing: 8) {
                            ForEach(group.episodes) { episode in
                                Button(action: { model.selectSource(episode) }) {
                                    Text(episode.name)
                                        .font(.caption)
                                        .foregroundColor(model.currentSource.id == episode.id ? .white : AppTheme.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(model.currentSource.id == episode.id ? AppTheme.accent : AppTheme.mutedFill)
                                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 16)
        }
        .background(AppTheme.background)
    }

    private func configurePlayer() {
        model.start()

        let context = model.context
        context.control.configure(displayStyle: .auto(firstAppear: true, animation: .easeInOut, duration: 3))
        context.control.configure(.halfScreen, insets: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        context.control.configure(.fullScreen, insets: EdgeInsets(top: 0, leading: 24, bottom: 18, trailing: 24))

        context.control.configure(.halfScreen(.top1)) {
            [
                AnyView(VPCCloseButton(action: onClose)),
                AnyView(VPCTitleView(title: model.currentSource.name)),
                AnyView(VPCSpacer())
            ]
        }
        context.control.configure(.halfScreen(.center)) {
            [AnyView(VPCPlaybackButton())]
        }
        context.control.configure(.halfScreen(.bottom1)) {
            [
                AnyView(VPCTimeLabel()),
                AnyView(VPCSeekBar()),
                AnyView(VPCFullScreenButton(isFullScreen: false) { model.enterFullScreen() })
            ]
        }

        context.control.configure(.fullScreen(.top1)) {
            [
                AnyView(VPCBackButton(action: model.exitFullScreen)),
                AnyView(VPCTitleView(title: model.currentSource.name)),
                AnyView(VPCSpacer()),
                AnyView(VPCEpisodeButton { showEpisodePicker = true })
            ]
        }
        context.control.configure(.fullScreen(.center)) {
            [AnyView(VPCPlaybackButton())]
        }
        context.control.configure(.fullScreen(.bottom1)) {
            [
                AnyView(VPCTimeLabel()),
                AnyView(VPCSeekBar()),
                AnyView(VPCDanmakuToggleButton(isOn: model.isDanmakuVisible) { model.toggleDanmaku() }),
                AnyView(VPCSpeedMenu()),
                AnyView(VPCFullScreenButton(isFullScreen: true) { model.exitFullScreen() })
            ]
        }
    }
}

enum PlayerOrientation {
    static func setFullScreen(_ fullScreen: Bool) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            return
        }

        let mask: UIInterfaceOrientationMask = fullScreen ? .landscapeRight : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
