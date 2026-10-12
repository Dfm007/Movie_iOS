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
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无可选剧集")
                            .font(.headline)
                        Text("当前播放源没有可下载的剧集，请尝试切换采集站后重试")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(episodes) { episode in
                            Button {
                                if selectedIDs.contains(episode.id) {
                                    selectedIDs.remove(episode.id)
                                } else {
                                    selectedIDs.insert(episode.id)
                                }
                            } label: {
                                HStack {
                                    Text(episode.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedIDs.contains(episode.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
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
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }
}