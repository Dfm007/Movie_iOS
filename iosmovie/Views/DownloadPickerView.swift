import SwiftUI

struct DownloadPickerView: View {
    let title: String
    let episodes: [PlaySource]
    let onConfirm: ([PlaySource]) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationView {
            Group {
                if episodes.isEmpty {
                    EmptyStateView(
                        icon: "tray",
                        title: "暂无可选剧集",
                        message: "当前播放源没有可下载的剧集，请尝试切换采集站后重试。"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(episodes) { episode in
                                Button {
                                    if selectedIDs.contains(episode.id) {
                                        selectedIDs.remove(episode.id)
                                    } else {
                                        selectedIDs.insert(episode.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Text(episode.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(AppTheme.textPrimary)

                                        Spacer()

                                        Image(systemName: selectedIDs.contains(episode.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedIDs.contains(episode.id) ? AppTheme.accent : AppTheme.textSecondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 13)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                                            .fill(selectedIDs.contains(episode.id) ? AppTheme.accentSoft : AppTheme.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                                            .stroke(selectedIDs.contains(episode.id) ? AppTheme.accent.opacity(0.45) : AppTheme.border, lineWidth: 0.5)
                                    )
                                }
                                .buttonStyle(PressableScaleButtonStyle())
                            }
                        }
                        .padding(.horizontal, AppTheme.pagePadding)
                        .padding(.vertical, 14)
                    }
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("选择下载剧集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("下载") {
                        let selected = episodes.filter { selectedIDs.contains($0.id) }
                        onConfirm(selected)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(selectedIDs.isEmpty ? AppTheme.textSecondary : AppTheme.accent)
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}
