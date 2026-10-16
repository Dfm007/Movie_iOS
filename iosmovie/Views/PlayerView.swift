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
                playerWidget(width: proxy.size.width)
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

    private func playerWidget(width: CGFloat) -> some View {
        PlayerWidget(model.context)
            .background(Color.black)
            .overlay {
                VPCDanmakuView()
                    .allowsHitTesting(false)
                    .opacity(model.isDanmakuVisible ? 1 : 0)
            }
            .overlay {
                if model.state == .loading {
                    VPCBufferingView(text: "加载中")
                } else if model.state == .buffering {
                    VPCBufferingView(text: "缓冲中")
                }
            }
            .overlay(alignment: .top) {
                if let hint = model.gestureHint {
                    VPCGestureHintView(text: hint)
                        .padding(.top, 82)
                }
            }
            .overlay(alignment: .top) {
                if model.controlsVisible && !model.isLocked {
                    Group {
                        if model.isFullScreen {
                            VPCFullScreenTopControls(model: model) {
                                showEpisodePicker = true
                            }
                        } else {
                            VPCHalfScreenTopControls(model: model, onClose: onClose)
                        }
                    }
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if model.controlsVisible && !model.isLocked {
                    Group {
                        if model.isFullScreen {
                            VPCFullScreenBottomControls(model: model)
                        } else {
                            VPCHalfScreenBottomControls(model: model)
                        }
                    }
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .center) {
                if model.controlsVisible && !model.isLocked {
                    VPCPlaybackButton()
                        .environmentObject(model.context)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .leading) {
                if model.isFullScreen && (model.isLocked || model.controlsVisible) {
                    VPCLockButton(isLocked: model.isLocked) { model.toggleLock() }
                        .padding(.leading, 12)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
            .animation(.easeInOut(duration: 0.2), value: model.isLocked)
            .simultaneousGesture(
                SpatialTapGesture(count: 2)
                    .onEnded { value in
                        model.handleDoubleTap(at: value.location.x, width: width)
                    }
            )
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5, maximumDistance: 12)
                    .onChanged { model.setLongPressActive($0) }
                    .onEnded { _ in model.setLongPressActive(false) }
            )
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
