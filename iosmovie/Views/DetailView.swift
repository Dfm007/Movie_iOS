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
            if viewModel.isLoading && viewModel.sources.isEmpty {
                LoadingStateView(title: "正在加载详情")
            } else if let error = viewModel.errorMessage, viewModel.sources.isEmpty {
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "加载失败",
                    message: error,
                    actionTitle: "重新加载"
                ) {
                    Task { await viewModel.loadDetail(path: detailURL) }
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerView
                        infoSection
                        sourcePicker
                        episodeSection
                    }
                    .padding(.vertical, 16)
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle(viewModel.movieTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !viewModel.hasConfigured else { return }
            // setInitialTitle 必须无条件执行，确保 currentMovieTitle 始终有值，
            // 供 loadDetail 里的 bestMatch 兜底搜索使用（即使 availableSites 为 nil）。
            viewModel.setInitialTitle(initialTitle)
            if let sites = availableSites {
                viewModel.configure(availableSites: sites, detailMap: detailMap)
            }
            // 先加载详情（用户最关心的内容），站点测速放在其后执行。
            await viewModel.loadDetail(path: detailURL)

            // 立即在后台预取其他源的详情，不等站点测速（测速要 1~3 秒，会推迟预取窗口）
            Task { await viewModel.discoverMoreSources(title: initialTitle) }

            await latencyManager.measureAll(sites: viewModel.sites)
        }
        .onChange(of: availableSites) { newSites in
            // 首页后台解析出的其他源陆续送达时，动态补进播放源列表
            guard let newSites = newSites, !newSites.isEmpty else { return }
            viewModel.mergeAvailableSites(newSites, detailMap: detailMap)
        }
        .background(
            PlayerPresenter(
                title: viewModel.movieTitle,
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
        AppCard(padding: 14, radius: AppTheme.radiusLarge) {
            HStack(alignment: .top, spacing: 16) {
                PosterArtwork(
                    posterURL: viewModel.posterURL,
                    fallbackTitle: viewModel.movieTitle,
                    cornerRadius: AppTheme.radiusMedium
                )
                .frame(width: 112)

                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.movieTitle)
                        .font(.title3.weight(.bold))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(3)

                    HStack(spacing: 6) {
                        AppPill(text: viewModel.selectedSite.name, color: AppTheme.accentSecondary)
                        if !viewModel.remarks.isEmpty {
                            AppPill(text: viewModel.remarks, color: AppTheme.accent, filled: true)
                        }
                    }

                    if !metadataText.isEmpty {
                        Text(metadataText)
                            .font(.caption)
                            .foregroundColor(AppTheme.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private var metadataText: String {
        [viewModel.year, viewModel.area, viewModel.className]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var infoSection: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "剧情简介")

                if !viewModel.director.isEmpty {
                    infoRow(label: "导演", value: viewModel.director)
                }

                if !viewModel.actors.isEmpty {
                    infoRow(label: "主演", value: viewModel.actors)
                }

                if !viewModel.intro.isEmpty {
                    Text(viewModel.intro)
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                        .lineSpacing(4)
                        .lineLimit(6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 34, alignment: .leading)

            Text(value)
                .font(.caption)
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(2)
        }
    }

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "播放源", subtitle: "切换不同采集站")

            Picker("采集站", selection: $viewModel.selectedSite) {
                ForEach(viewModel.sites) { site in
                    SitePickerLabel(site: site, latencyManager: latencyManager)
                        .tag(site)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .tint(AppTheme.accent)
            .onChange(of: viewModel.selectedSite) { newSite in
                Task { await viewModel.loadDetail(path: detailURL, site: newSite) }
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.isLoading && !viewModel.sources.isEmpty {
                // 正在切换源：给个明确的加载反馈，而不是继续显示旧源的选集
                HStack(spacing: 8) {
                    ProgressView()
                    Text("正在切换播放源…")
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 28)
            } else if viewModel.sources.isEmpty {
                emptyEpisodesHint
            } else {
                SectionHeader(title: "选集", subtitle: "选择要播放或下载的剧集")

                ForEach(viewModel.sources) { source in
                    if source.episodes.isEmpty {
                        singleSourceCard(source)
                    } else {
                        episodeGroup(source)
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.pagePadding)
    }

    private func singleSourceCard(_ source: PlaySource) -> some View {
        AppCard(padding: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppTheme.textPrimary)
                    Text("单集资源")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSecondary)
                }

                Spacer()

                Button {
                    playingSource = source
                    playerPresented = true
                } label: {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.black.opacity(0.82))
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(AppTheme.accent))
                }
                .buttonStyle(PressableScaleButtonStyle())

                Button {
                    startSingleDownload(source)
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(AppTheme.accentSecondary)
                }
                .buttonStyle(PressableScaleButtonStyle())
            }
        }
    }

    private func episodeGroup(_ source: PlaySource) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(source.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppTheme.textPrimary)

                Spacer()

                Button("下载") {
                    showDownloadPicker(for: source.episodes)
                }
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.accent)
                .buttonStyle(PressableScaleButtonStyle())
            }

            LazyVGrid(columns: episodeColumns, spacing: 8) {
                ForEach(source.episodes) { episode in
                    Button {
                        playingSource = episode
                        playerPresented = true
                    } label: {
                        Text(episode.name)
                            .font(.caption.weight(.medium))
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous)
                                    .fill(AppTheme.mutedFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.radiusSmall, style: .continuous)
                                    .stroke(AppTheme.border, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(PressableScaleButtonStyle())
                }
            }
        }
    }

    private var emptyEpisodesHint: some View {
        EmptyStateView(
            icon: "film.stack",
            title: "暂无播放源",
            message: "可尝试切换上方采集站，或点击重试。",
            actionTitle: "重试"
        ) {
            Task { await viewModel.loadDetail(path: detailURL) }
        }
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
                .foregroundColor(AppTheme.textPrimary)
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
