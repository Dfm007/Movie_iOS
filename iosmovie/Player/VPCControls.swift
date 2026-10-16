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
            VPCTitleView(title: model.currentSource.name)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 10)
    }
}

struct VPCHalfScreenBottomControls: View {
    @ObservedObject var model: VPCPlayerModel

    var body: some View {
        HStack(spacing: 8) {
            VPCTimeLabel()
            VPCSeekBar()
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
            VPCTitleView(title: model.currentSource.name)
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
            VPCTimeLabel()
            VPCSeekBar()
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
    @EnvironmentObject private var context: Context

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let current = context.render.player.currentTime().seconds
            let total = context.render.player.currentItem?.duration.seconds ?? 0
            Text("\(Self.format(current)) / \(Self.format(total))")
                .font(.caption.monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
        }
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

struct VPCSeekBar: View {
    @EnvironmentObject private var context: Context
    @State private var isEditing = false
    @State private var editingValue: Double = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let rawDuration = context.render.player.currentItem?.duration.seconds ?? 0
            let total = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 1
            let rawCurrent = context.render.player.currentTime().seconds
            let current = rawCurrent.isFinite ? min(max(rawCurrent, 0), total) : 0
            let value = isEditing ? editingValue : current

            Slider(
                value: Binding(
                    get: { value },
                    set: { newValue in
                        editingValue = newValue
                        isEditing = true
                    }
                ),
                in: 0...total,
                onEditingChanged: { editing in
                    if !editing {
                        context.render.player.seek(
                            to: CMTime(seconds: editingValue, preferredTimescale: 600),
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        )
                        isEditing = false
                    }
                }
            )
            .tint(VPCTheme.accent)
        }
        .frame(height: 24)
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

    var body: some View {
        NavigationView {
            List {
                ForEach(groups) { group in
                    Section(header: Text(group.name)) {
                        if group.episodes.isEmpty {
                            episodeButton(group)
                        } else {
                            ForEach(group.episodes) { episode in
                                episodeButton(episode)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func episodeButton(_ source: PlaySource) -> some View {
        Button {
            onSelect(source)
            dismiss()
        } label: {
            HStack {
                Text(source.name.isEmpty ? "正片" : source.name)
                    .foregroundColor(AppTheme.textPrimary)
                Spacer()
                if source.id == currentSourceID {
                    Image(systemName: "checkmark")
                        .foregroundColor(AppTheme.accent)
                }
            }
        }
    }
}
