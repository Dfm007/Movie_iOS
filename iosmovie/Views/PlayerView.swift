import SwiftUI
import UIKit
import AVFoundation

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
            CLPlayerRepresentable(urlString: currentSource.url)
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

struct CLPlayerRepresentable: UIViewRepresentable {
    let urlString: String

    func makeUIView(context: Context) -> CLPlayer {
        let player = CLPlayer(frame: .zero) { config in
config.rotateStyle = .all
config.topBarHiddenStyle = .onlySmall
        }

        if let url = URL(string: urlString) {
            player.url = url
            player.play()
        }

        return player
    }

    func updateUIView(_ player: CLPlayer, context: Context) {
        if player.url?.absoluteString != urlString {
            if let url = URL(string: urlString) {
                player.url = url
                player.play()
            }
        }
    }
}