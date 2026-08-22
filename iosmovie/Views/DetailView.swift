import SwiftUI
import IJKMediaFramework

struct DetailView: View {
    let detailURL: String
    @StateObject private var viewModel = DetailViewModel()
    @State private var playingSource: PlaySource?

    private let episodeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

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
    @State private var isFullscreen = false
    @State private var isLocked = false
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var showControls = true

    private let episodeColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(source: PlaySource, allSources: [PlaySource]) {
        self.source = source
        self.allSources = allSources
        _currentSource = State(initialValue: source)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isFullscreen {
                fullscreenPlayer
            } else {
                portraitLayout
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
        .onTapGesture {
            withAnimation {
                showControls.toggle()
            }
        }
    }

    private var portraitLayout: some View {
        VStack(spacing: 0) {
            playerContainer
                .frame(height: 220)
            episodePanel
        }
    }

    private var fullscreenPlayer: some View {
        playerContainer
            .ignoresSafeArea()
    }

    private var playerContainer: some View {
        ZStack {
            IJKPlayerContainerView(url: currentSource.url, isPlaying: $isPlaying, currentTime: $currentTime, duration: $duration, playbackRate: $playbackRate)

            if showControls && !isLocked {
                controlsOverlay
            }
        }
    }

    private var controlsOverlay: some View {
        VStack {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            HStack(spacing: 16) {
                playPauseButton
                rateButton
                lockButton
                Spacer()
                fullscreenButton
            }
            .padding(.horizontal, 12)

            progressSlider
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        }
        .background(Color.black.opacity(0.4))
    }

    private var progressSlider: some View {
        HStack(spacing: 8) {
            Text(timeString(currentTime))
                .font(.system(size: 11))
                .foregroundColor(.white)

            Slider(
                value: Binding(
                    get: { currentTime },
                    set: { newValue in
                        seek(to: newValue)
                    }
                ),
                in: 0...max(duration, 1)
            )
            .accentColor(.white)

            Text(timeString(duration))
                .font(.system(size: 11))
                .foregroundColor(.white)
        }
    }

    private var playPauseButton: some View {
        Button(action: {
            togglePlayPause()
        }) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private var rateButton: some View {
        Menu {
            ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                Button("\(rate)x") {
                    setRate(Float(rate))
                }
            }
        } label: {
            Text("\(playbackRate)x")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.5))
                .clipShape(Capsule())
        }
    }

    private var lockButton: some View {
        Button(action: {
            isLocked.toggle()
            if isLocked {
                showControls = false
            }
        }) {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private var backButton: some View {
        Button(action: {
            dismiss()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .padding(.leading, 10)
        .padding(.top, 10)
    }

    private var fullscreenButton: some View {
        Button(action: {
            isFullscreen.toggle()
            showControls = true
        }) {
            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private var episodePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if availableEpisodes.isEmpty {
                    Text("暂无剧集")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: episodeColumns, spacing: 8) {
                        ForEach(availableEpisodes) { episode in
                            Button(action: {
                                switchTo(episode)
                            }) {
                                Text(episode.name)
                                    .font(.caption)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(currentSource.id == episode.id ? Color.blue : Color.white.opacity(0.12))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGray6).opacity(0.08))
    }

    private var availableEpisodes: [PlaySource] {
        allSources.flatMap { source in
            source.episodes.isEmpty ? [source] : source.episodes
        }
    }

    private func togglePlayPause() {
        isPlaying.toggle()
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
    }

    private func seek(to time: Double) {
        currentTime = time
    }

    private func switchTo(_ newSource: PlaySource) {
        currentSource = newSource
        isPlaying = false
        currentTime = 0
        duration = 0
        setupPlayer()
    }

    private func setupPlayer() {
        isPlaying = true
    }

    private func cleanup() {
        isPlaying = false
    }

    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct IJKPlayerContainerView: UIViewRepresentable {
    let url: String
    @Binding var isPlaying: Bool
    @Binding var currentTime: Double
    @Binding var duration: Double
    @Binding var playbackRate: Float

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let player = IJKFFMoviePlayerController(contentURLString: url, with: nil)
        player?.view.frame = view.bounds
        player?.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        player?.scalingMode = .aspectFit
        player?.shouldAutoplay = true
        if let player = player {
            view.addSubview(player.view)
            player.prepareToPlay()
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
    }
}