import SwiftUI
import AVKit

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

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(view.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    let playerLayer = AVPlayerLayer()

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}

struct PlayerView: View {
    let source: PlaySource
    let allSources: [PlaySource]
    @Environment(\.dismiss) private var dismiss
    @State private var currentSource: PlaySource
    @State private var player: AVPlayer?
    @State private var errorMessage: String?
    @State private var isFullscreen = false
    @State private var isLocked = false
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var playbackRate: Float = 1.0
    @State private var showControls = true
    @State private var timeObserver: Any?
    @State private var dragStartTime: Double = 0

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
            if isLocked {
                isLocked.toggle()
                showControls = true
            } else {
                withAnimation {
                    showControls.toggle()
                }
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
            if let error = errorMessage {
                errorView(error)
            } else if let player = player {
                PlayerLayerView(player: player)
            } else {
                ProgressView("加载中...")
                    .foregroundColor(.white)
            }

            if showControls && !isLocked {
                controlsOverlay
            }
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onChanged { value in
                    if dragStartTime == 0 {
                        dragStartTime = currentTime
                    }
                    let delta = Double(value.translation.width) * 0.5
                    let newTime = min(max(dragStartTime + delta, 0), safeDuration)
                    currentTime = newTime
                }
                .onEnded { value in
                    let targetTime = currentTime
                    seek(to: targetTime)
                    dragStartTime = 0
                }
        )
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
                in: 0...max(safeDuration, 1)
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
            showControls = true
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
            toggleFullscreen()
        }) {
            Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    private func toggleFullscreen() {
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
                isFullscreen.toggle()
                showControls = true
                return
            }
            let orientation: UIInterfaceOrientationMask = isFullscreen ? .portrait : .landscape
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientation)) { error in
                isFullscreen.toggle()
                showControls = true
            }
        } else {
            if isFullscreen {
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            } else {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
            UINavigationController.attemptRotationToDeviceOrientation()
            isFullscreen.toggle()
            showControls = true
        }
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Text("播放失败")
                .font(.headline)
                .foregroundColor(.white)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
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
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func setRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        currentTime = time
    }

    private func switchTo(_ newSource: PlaySource) {
        cleanup()
        currentSource = newSource
        errorMessage = nil
        setupPlayer()
    }

    private func setupPlayer() {
        let rawURL = currentSource.url
        guard !rawURL.isEmpty,
              let encodedURL = rawURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: encodedURL) else {
            errorMessage = "播放地址无效"
            return
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.rate = playbackRate
        player = newPlayer
        newPlayer.play()
        isPlaying = true

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = time.seconds
            duration = newPlayer.currentItem?.duration.seconds ?? 0
            if newPlayer.rate == 0 {
                isPlaying = false
            } else {
                isPlaying = true
            }
        }
    }

    private func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private var safeDuration: Double {
        duration.isFinite && duration > 0 ? duration : 1
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