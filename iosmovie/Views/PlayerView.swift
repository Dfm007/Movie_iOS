import SwiftUI
import WebKit
import UIKit

struct PlayerView: View {
    let source: PlaySource
    var allSources: [PlaySource] = []
    var onClose: () -> Void
    @State private var currentSource: PlaySource
    @State private var hideEpisodeList = false
    @State private var isFullScreen = false

    private let episodeColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    init(source: PlaySource, allSources: [PlaySource] = [], onClose: @escaping () -> Void) {
        self.source = source
        self.allSources = allSources
        self.onClose = onClose
        _currentSource = State(initialValue: source)
    }

    var body: some View {
        VStack(spacing: 0) {
            WebPlayerView(urlString: resolveURL(for: currentSource.url), isFullScreen: $isFullScreen)
                .frame(height: isFullScreen ? UIScreen.main.bounds.width : (hideEpisodeList ? UIScreen.main.bounds.height : UIScreen.main.bounds.width * 9 / 16))
                .background(Color.black)

            if !isFullScreen && !hideEpisodeList {
                episodeListView
            }
        }
        .background(Color.white)
        .overlay(alignment: .topTrailing) {
            if !isFullScreen {
                Button(action: { onClose() }) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .padding(.top, hideEpisodeList ? 60 : 8)
                .padding(.trailing, 8)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("toggleEpisodeList"))) { _ in
            hideEpisodeList.toggle()
        }
    }

    private func resolveURL(for videoURL: String) -> String {
        guard let encoded = videoURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            return "https://lziplayer.com/?url="
        }
        return "https://lziplayer.com/?url=\(encoded)"
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

struct WebPlayerView: UIViewRepresentable {
    let urlString: String
    @Binding var isFullScreen: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .black
        webView.isOpaque = false

        load(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url?.absoluteString != urlString {
            load(in: webView)
        }
    }

    private func load(in webView: WKWebView) {
        guard let url = URL(string: urlString) else { return }
        let request = URLRequest(url: url)
        webView.load(request)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebPlayerView

        init(_ parent: WebPlayerView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            injectFullScreenBlocker(webView)
        }

        private func injectFullScreenBlocker(_ webView: WKWebView) {
            let js = """
            (function() {
                function blockFullScreen(video) {
                    video.addEventListener('webkitbeginfullscreen', function(e) {
                        e.preventDefault();
                        window.webkit.messageHandlers.fullScreenHandler.postMessage('enterFullScreen');
                    });
                }
                document.querySelectorAll('video').forEach(blockFullScreen);
                new MutationObserver(function(mutations) {
                    mutations.forEach(function(m) {
                        m.addedNodes.forEach(function(node) {
                            if (node.tagName === 'VIDEO') blockFullScreen(node);
                        });
                    });
                }).observe(document.body, { childList: true, subtree: true });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // 加载失败可在此处理
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // 加载失败可在此处理
        }
    }
}