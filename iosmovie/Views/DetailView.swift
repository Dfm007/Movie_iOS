import SwiftUI

struct DetailView: View {
    let detailURL: String
    let initialTitle: String
    var availableSites: [CMSSite]? = nil
    var detailMap: [String: String] = [:]
    @StateObject private var viewModel = DetailViewModel()
    @StateObject private var latencyManager = SiteLatencyManager.shared
    @StateObject private var downloadManager = DownloadManager.shared
    @State private var playingSource: PlaySource?
    @State private var playerPresented = false
    @State private var downloadPayload: DownloadPickerPayload?

    private let episodeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(detailURL: String, initialTitle: String = "", availableSites: [CMSSite]? = nil, detailMap: [String: String] = [:]) {
        self.detailURL = detailURL
        self.initialTitle = initialTitle
        self.availableSites = availableSites
        self.detailMap = detailMap
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("加载中...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text("加载失败")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("重试") {
                        Task { await viewModel.loadDetail(path: detailURL) }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headerView
                        infoSection

                        Picker("采集站", selection: $viewModel.selectedSite) {
                            ForEach(viewModel.sites) { site in
                                SitePickerLabel(site: site, latencyManager: latencyManager)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .onChange(of: viewModel.selectedSite) { newSite in
                            Task { await viewModel.loadDetail(path: detailURL, site: newSite) }
                        }

                        episodeSection
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(viewModel.movieTitle)
        .task {
            guard !viewModel.hasConfigured else { return }
            // setInitialTitle 必须无条件执行，确保 currentMovieTitle 始终有值，
            // 供 loadDetail 里的 bestMatch 兜底搜索使用（即使 availableSites 为 nil）。
            viewModel.setInitialTitle(initialTitle)
            if let sites = availableSites {
                viewModel.configure(availableSites: sites, detailMap: detailMap)
            }
            // 先加载详情（用户最关心的内容），站点测速放在其后执行。
            // 之前是「先 await measureAll（每站最多 3s）再 loadDetail」，其间
            // isLoading 仍为 false、sources 为空 → 页面出现一段空白，若测速卡住会一直空。
            await viewModel.loadDetail(path: detailURL)
            await latencyManager.measureAll(sites: viewModel.sites)
        }
        .background(
            PlayerPresenter(
                source: playingSource ?? viewModel.sources.first ?? PlaySource(id: "", name: "", url: "", format: "", episodes: []),
                allSources: viewModel.sources,
                isPresented: $playerPresented
            )
        )
        .sheet(item: $downloadPayload) { payload in
            DownloadPickerView(title: viewModel.movieTitle, episodes: payload.episodes) { selected in
                createDownloadTasks(for: selected)
            }
        }
        .alert(isPresented: $downloadManager.showAlert) {
            Alert(title: Text(downloadManager.alertMessage))
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 16) {
            if let posterURL = viewModel.posterURL, let url = URL(string: posterURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(2/3, contentMode: .fill)
                    default:
                        posterPlaceholder
                    }
                }
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                posterPlaceholder
                    .frame(width: 100, height: 150)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.movieTitle)
                    .font(.headline)
                    .lineLimit(3)
                Text("采集站：\(viewModel.selectedSite.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }

    private var posterPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.15, green: 0.18, blue: 0.28),
                        Color(red: 0.30, green: 0.24, blue: 0.42)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "film")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.7))
            )
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !viewModel.remarks.isEmpty {
                Text(viewModel.remarks)
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            if !viewModel.year.isEmpty || !viewModel.area.isEmpty || !viewModel.className.isEmpty {
                Text([viewModel.year, viewModel.area, viewModel.className].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !viewModel.director.isEmpty {
                Text("导演：\(viewModel.director)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !viewModel.actors.isEmpty {
                Text("主演：\(viewModel.actors)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if !viewModel.intro.isEmpty {
                Text(viewModel.intro)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(5)
            }
        }
        .padding(.horizontal)
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.sources.isEmpty {
                emptyEpisodesHint
            }
            ForEach(viewModel.sources) { source in
                if source.episodes.isEmpty {
                    HStack {
                        Button(action: {
                            playingSource = source
                            playerPresented = true
                        }) {
                            Text(source.name)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        Spacer()

                        Button(action: {
                            startSingleDownload(source)
                        }) {
                            Image(systemName: "arrow.down.circle")
                                .font(.title3)
                        }
                    }
                } else {
                    HStack {
                        Text(source.name)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("下载") {
                            showDownloadPicker(for: source.episodes)
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }

                    LazyVGrid(columns: episodeColumns, spacing: 8) {
                        ForEach(source.episodes) { episode in
                            Button(action: {
                                playingSource = episode
                                playerPresented = true
                            }) {
                                Text(episode.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var emptyEpisodesHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "film.stack")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("当前采集站暂无可用播放源")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("可尝试切换上方采集站，或点击重试")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("重试") {
                Task { await viewModel.loadDetail(path: detailURL) }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 24)
    }

    private func showDownloadPicker(for episodes: [PlaySource]) {
        downloadPayload = DownloadPickerPayload(episodes: episodes)
    }

    private func startSingleDownload(_ source: PlaySource) {
        DownloadManager.shared.startDownloads(requests: [
            DownloadRequest(
                title: viewModel.movieTitle,
                episodeName: source.name,
                sourceURL: source.url,
                posterURL: viewModel.posterURL
            )
        ])
    }

    private func createDownloadTasks(for episodes: [PlaySource]) {
        // 海报地址在下载期间保持一致，先取出来再进 map
        let posterURL = viewModel.posterURL
        DownloadManager.shared.startDownloads(requests: episodes.map {
            DownloadRequest(
                title: viewModel.movieTitle,
                episodeName: $0.name,
                sourceURL: $0.url,
                posterURL: posterURL
            )
        })
    }
}

private struct DownloadPickerPayload: Identifiable {
    let id = UUID()
    let episodes: [PlaySource]
}

private struct SitePickerLabel: View {
    let site: CMSSite
    @ObservedObject var latencyManager: SiteLatencyManager

    var body: some View {
        (
            Text(site.name)
                .foregroundColor(.primary)
            +
            Text(" \(latencyManager.latencyText(for: site))")
                .font(.caption2)
                .foregroundColor(latencyManager.color(for: site))
        )
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .tag(site)
    }
}