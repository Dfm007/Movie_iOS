import AVFoundation
import DanmakuKit
import SwiftUI
import UIKit
import VideoPlayerContainer

enum VPCTheme {
    static let accent = Color(red: 0.98, green: 0.45, blue: 0.60)
    static let controlBackground = Color.black.opacity(0.55)
}

struct VPCDanmakuView: UIViewRepresentable {
    func makeUIView(context: UIViewRepresentableContext<VPCDanmakuView>) -> DanmakuView {
        let view = DanmakuView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: DanmakuView, context: UIViewRepresentableContext<VPCDanmakuView>) {}
}

struct VPCLongPressGestureView: UIViewRepresentable {
    let onBegan: () -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onEnded: onEnded)
    }

    func makeUIView(context: UIViewRepresentableContext<VPCLongPressGestureView>) -> LongPressHostView {
        let view = LongPressHostView()
        view.isUserInteractionEnabled = false
        view.onBegan = context.coordinator.onBegan
        view.onEnded = context.coordinator.onEnded
        return view
    }

    func updateUIView(_ uiView: LongPressHostView, context: UIViewRepresentableContext<VPCLongPressGestureView>) {
        uiView.onBegan = context.coordinator.onBegan
        uiView.onEnded = context.coordinator.onEnded
    }

    final class Coordinator {
        let onBegan: () -> Void
        let onEnded: () -> Void

        init(onBegan: @escaping () -> Void, onEnded: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onEnded = onEnded
        }
    }
}

final class LongPressHostView: UIView, UIGestureRecognizerDelegate {
    var onBegan: (() -> Void)?
    var onEnded: (() -> Void)?

    private weak var installedRecognizer: UILongPressGestureRecognizer?

    deinit {
        if let recognizer = installedRecognizer {
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard installedRecognizer == nil, let window = window else { return }

        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        recognizer.minimumPressDuration = 0.5
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window.addGestureRecognizer(recognizer)
        installedRecognizer = recognizer
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onBegan?()
        case .ended, .cancelled, .failed:
            onEnded?()
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

struct VPCBufferingView: View {
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.white)
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(VPCTheme.controlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct VPCGestureHintView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(VPCTheme.controlBackground)
            .clipShape(Capsule())
    }
}

struct VPCCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct VPCBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(VPCTheme.controlBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct VPCLockButton: View {
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(VPCTheme.controlBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct VPCHalfScreenTopControls: View {
    @ObservedObject var model: VPCPlayerModel
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VPCCloseButton(action: onClose)
            VPCTitleView(title: model.displayTitle)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
    }
}

struct VPCHalfScreenBottomControls: View {
    @ObservedObject var model: VPCPlayerModel

    var body: some View {
        HStack(spacing: 8) {
            VPCTimeLabel(metrics: model.metrics)
            VPCSeekBar(metrics: model.metrics) { seconds in
                model.seek(to: seconds)
            }
            VPCFullScreenButton(isFullScreen: false) { model.enterFullScreen() }
        }
        .padding(.horizontal, 10)
        .environmentObject(model.context)
    }
}

struct VPCFullScreenTopControls: View {
    @ObservedObject var model: VPCPlayerModel
    let onShowEpisodes: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VPCBackButton { model.exitFullScreen() }
            VPCTitleView(title: model.displayTitle)
            Spacer(minLength: 8)
            VPCEpisodeButton(action: onShowEpisodes)
        }
        .padding(.horizontal, 12)
    }
}

struct VPCFullScreenBottomControls: View {
    @ObservedObject var model: VPCPlayerModel

    var body: some View {
        HStack(spacing: 8) {
            VPCTimeLabel(metrics: model.metrics)
            VPCSeekBar(metrics: model.metrics) { seconds in
                model.seek(to: seconds)
            }
            VPCDanmakuToggleButton(isOn: model.isDanmakuVisible) { model.toggleDanmaku() }
            VPCSpeedMenu()
            VPCFullScreenButton(isFullScreen: true) { model.exitFullScreen() }
        }
        .padding(.horizontal, 14)
        .environmentObject(model.context)
    }
}

struct VPCPlaybackButton: View {
    @EnvironmentObject private var context: Context

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Button {
                if context.render.player.rate == 0 {
                    context.render.player.play()
                } else {
                    context.render.player.pause()
                }
            } label: {
                Image(systemName: context.render.player.rate == 0 ? "play.fill" : "pause.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

struct VPCTimeLabel: View {
    @ObservedObject var metrics: VPCPlaybackMetrics

    var body: some View {
        Text("\(VPCPlaybackMetrics.formatTime(metrics.displayTime)) / \(VPCPlaybackMetrics.formatTime(metrics.duration))")
            .font(.caption.monospacedDigit())
            .foregroundColor(.white)
            .lineLimit(1)
    }
}

struct VPCSeekBar: View {
    @ObservedObject var metrics: VPCPlaybackMetrics
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))

                Capsule()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: width * metrics.bufferedProgress)

                Capsule()
                    .fill(VPCTheme.accent)
                    .frame(width: width * metrics.playbackProgress)

                Circle()
                    .fill(Color.white)
                    .frame(
                        width: metrics.isDragging ? 14 : 10,
                        height: metrics.isDragging ? 14 : 10
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: width * metrics.playbackProgress - (metrics.isDragging ? 7 : 5))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard metrics.duration > 0 else { return }
                        metrics.beginDragging(to: target(for: value.location.x, width: width))
                    }
                    .onEnded { value in
                        guard metrics.duration > 0 else { return }
                        let target = target(for: value.location.x, width: width)
                        metrics.endDragging()
                        onSeek(target)
                    }
            )
            .overlay(alignment: .top) {
                if metrics.isDragging {
                    VPCSeekTargetBubble(
                        text: "\(VPCPlaybackMetrics.formatTime(metrics.dragTargetTime)) / \(VPCPlaybackMetrics.formatTime(metrics.duration))"
                    )
                    .fixedSize()
                    .offset(x: bubbleOffset(width: width), y: -30)
                }
            }
        }
        .frame(height: 32)
    }

    private func target(for x: CGFloat, width: CGFloat) -> Double {
        guard metrics.duration > 0 else { return 0 }
        let ratio = min(max(x / width, 0), 1)
        return ratio * metrics.duration
    }

    private func bubbleOffset(width: CGFloat) -> CGFloat {
        let knobX = width * metrics.playbackProgress
        let clampedX = min(max(knobX, 52), max(width - 52, 52))
        return clampedX - width / 2
    }
}

private struct VPCSeekTargetBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.75))
            .clipShape(Capsule())
    }
}

/// 只订阅高频播放状态，手势提示变化不会刷新整个播放页。
struct VPCGestureHintOverlay: View {
    @ObservedObject var hint: VPCGestureHintModel

    var body: some View {
        if let text = hint.text {
            VPCGestureHintView(text: text)
                .padding(.top, 82)
                .transition(.opacity)
        }
    }
}

/// 长视频拖动进度时，在画面中央显示大号目标时间和相对偏移。
struct VPCSeekPreviewOverlay: View {
    @ObservedObject var metrics: VPCPlaybackMetrics

    var body: some View {
        if metrics.isDragging, metrics.isLongVideo {
            VStack(spacing: 3) {
                Text(VPCPlaybackMetrics.formatTime(metrics.dragTargetTime))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(offsetText)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity)
        }
    }

    private var offsetText: String {
        let offset = Int(metrics.dragOffset.rounded())
        if offset == 0 { return "当前进度" }
        return offset > 0 ? "快进 \(offset) 秒" : "后退 \(abs(offset)) 秒"
    }
}

struct VPCSpeedMenu: View {
    @EnvironmentObject private var context: Context
    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        Menu {
            ForEach(rates, id: \.self) { rate in
                Button {
                    context.render.player.rate = rate
                } label: {
                    Text(rate == 1.0 ? "正常" : "\(rate)x")
                }
            }
        } label: {
            Text("倍速")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(VPCTheme.controlBackground)
                .clipShape(Capsule())
        }
    }
}

struct VPCDanmakuToggleButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "text.bubble.fill" : "text.bubble")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isOn ? VPCTheme.accent : .white)
                .frame(width: 36, height: 36)
                .background(VPCTheme.controlBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct VPCFullScreenButton: View {
    let isFullScreen: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(VPCTheme.controlBackground)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct VPCEpisodeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet")
                Text("选集")
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(VPCTheme.controlBackground)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct VPCTitleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .lineLimit(1)
    }
}

struct VPCSpacer: View {
    var body: some View {
        Spacer(minLength: 8)
    }
}

struct VPCEpisodePickerView: View {
    let groups: [PlaySource]
    let currentSourceID: String
    let onSelect: (PlaySource) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroupID: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(
        groups: [PlaySource],
        currentSourceID: String,
        onSelect: @escaping (PlaySource) -> Void
    ) {
        self.groups = groups
        self.currentSourceID = currentSourceID
        self.onSelect = onSelect
        let initialGroup = groups.first(where: { group in
            group.episodes.contains(where: { $0.id == currentSourceID })
        })?.id ?? groups.first?.id ?? ""
        _selectedGroupID = State(initialValue: initialGroup)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups) { group in
                            Button {
                                selectedGroupID = group.id
                            } label: {
                                Text(group.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(selectedGroupID == group.id ? .white : AppTheme.textPrimary)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(selectedGroupID == group.id ? VPCTheme.accent : AppTheme.mutedFill)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Text("要切换播放源请返回影视详情页")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                Divider()

                ScrollView {
                    if let selectedGroup {
                        if selectedGroup.episodes.isEmpty {
                            episodeGrid([selectedGroup])
                        } else {
                            episodeGrid(selectedGroup.episodes)
                        }
                    }
                }
            }
            .background(AppTheme.background)
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private var selectedGroup: PlaySource? {
        groups.first(where: { $0.id == selectedGroupID }) ?? groups.first
    }

    private func episodeGrid(_ episodes: [PlaySource]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(episodes) { source in
                Button {
                    onSelect(source)
                    dismiss()
                } label: {
                    Text(source.name.isEmpty ? "正片" : source.name)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(source.id == currentSourceID ? .white : AppTheme.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(source.id == currentSourceID ? VPCTheme.accent : AppTheme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
