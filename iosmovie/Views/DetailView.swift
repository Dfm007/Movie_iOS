import SwiftUI
import KSPlayer

struct DetailView: View {
    let detailURL: String
    var availableSites: [CMSSite]? = nil
    var detailMap: [String: String] = [:]
    @StateObject private var viewModel = DetailViewModel()
    @State private var playingSource: PlaySource?

    private let episodeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(detailURL: String, availableSites: [CMSSite]? = nil, detailMap: [String: String] = [:]) {
        self.detailURL = detailURL
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
                                Text(site.name).tag(site)
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
            if let sites = availableSites {
                viewModel.configure(availableSites: sites, detailMap: detailMap)
            }
            await viewModel.loadDetail(path: detailURL)
        }
        .fullScreenCover(item: $playingSource) { source in
            PlayerView(source: source, allSources: viewModel.sources)
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
            ForEach(viewModel.sources) { source in
                if source.episodes.isEmpty {
                    Button(action: {
                        playingSource = source
                    }) {
                        Text(source.name)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                } else {
                    Text(source.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    LazyVGrid(columns: episodeColumns, spacing: 8) {
                        ForEach(source.episodes) { episode in
                            Button(action: {
                                playingSource = episode
                            }) {
                                Text(episode.name)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.blue.opacity(0.15))
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
}

struct PlayerView: View {
    let source: PlaySource
    let allSources: [PlaySource]
    @Environment(\.dismiss) private var dismiss
    @State private var currentSource: PlaySource
    @State private var isFullScreen = false

    init(source: PlaySource, allSources: [PlaySource]) {
        self.source = source
        self.allSources = allSources
        _currentSource = State(initialValue: source)
    }

    private let episodeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        Group {
            if isFullScreen {
                fullScreenPlayer
            } else {
                portraitLayout
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onDisappear {
            if isFullScreen {
                forceOrientation(.portrait)
            }
        }
    }

    private var fullScreenPlayer: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: currentSource.url) {
                KSVideoPlayerView(url: url, options: KSOptions(), title: currentSource.name)
                    .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button(action: {
                        isFullScreen = false
                        forceOrientation(.portrait)
                    }) {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
            }
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    Color.black
                    if let url = URL(string: currentSource.url) {
                        KSVideoPlayerView(url: url, options: KSOptions(), title: currentSource.name)
                    } else {
                        Text("播放地址无效")
                            .foregroundColor(.white)
                    }

                    HStack(spacing: 12) {
                        Button(action: {
                            isFullScreen = true
                            forceOrientation(.landscape)
                        }) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                        }

                        Button(action: { dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding(8)
                        }
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                }
            }
            .frame(height: UIScreen.main.bounds.width * 9 / 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(allSources) { group in
                        if group.episodes.isEmpty {
                            Button(action: {
                                currentSource = group
                            }) {
                                Text(group.name)
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(currentSource.id == group.id ? Color.blue.opacity(0.35) : Color.blue.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        } else {
                            Text(group.name)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: episodeColumns, spacing: 8) {
                                ForEach(group.episodes) { episode in
                                    Button(action: {
                                        currentSource = episode
                                    }) {
                                        Text(episode.name)
                                            .font(.caption)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(currentSource.id == episode.id ? Color.blue.opacity(0.35) : Color.blue.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical)
            }
        }
    }

    private func forceOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation))
        }
    }
}
