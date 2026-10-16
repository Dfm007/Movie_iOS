import AVFoundation
import SwiftUI
import VideoPlayerContainer

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
            let total = max(context.render.player.currentItem?.duration.seconds ?? 0, 1)
            let current = min(max(context.render.player.currentTime().seconds, 0), total)
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
            .tint(.white)
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
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
        }
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
                .background(Color.black.opacity(0.5))
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
            .background(Color.black.opacity(0.5))
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
