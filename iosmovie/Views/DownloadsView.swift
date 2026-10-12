import SwiftUI
import UIKit

struct DownloadsView: View {
    /// 只持有折叠状态；本视图刻意不订阅 DownloadManager。
    ///
    /// 原因：@StateObject / @ObservedObject 订阅的是整个对象的 objectWillChange，
    /// 而 DownloadManager.tasks 每下完一个分片就发一次通知。只要本视图订阅了它，
    /// 下载过程中 body 就会被每秒重算多次，挂在本视图上的 confirmationDialog
    /// 会在呈现过程中被反复打断 —— 表现为"有任务在下载时点剧集没反应"。
    /// 所以所有依赖 DownloadManager 的区域都下沉到自带 @ObservedObject 的子视图。
    @StateObject private var viewModel = DownloadsViewModel()

    @State private var playingMovie: DownloadedMovie?
    @State private var playStartAt: Double = 0
    @State private var playerPresented = false
    /// 唯一的弹窗状态：取消下载 / 删除已下载 / 续播询问都走它，
    /// 同层只保留一个 presentation modifier，避免多个弹窗互相覆盖。
    @State private var prompt: DownloadsPrompt?

    var body: some View {
        List {
            DownloadingSectionView { task in
                prompt = .cancelTask(task)
            }

            DownloadedSectionView(
                viewModel: viewModel,
                onPlay: { requestPlayback($0) },
                onPlayFromStart: { movie in
                    PlaybackProgressStore.shared.clear(folderID: movie.folderID)
                    beginPlayback(movie, from: 0, delayed: false)
                },
                onDeleteRequested: { prompt = .deleteMovie($0) }
            )

            EmptyDownloadsSection()
        }
        .listStyle(.insetGrouped)
        .navigationTitle("我的下载")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                DownloadsToolbarMenu(viewModel: viewModel)
            }
        }
        .confirmationDialog(
            prompt?.title ?? "提示",
            isPresented: promptBinding,
            titleVisibility: .visible,
            presenting: prompt
        ) { item in
            promptActions(for: item)
        } message: { item in
            Text(item.message)
        }
        .background(
            PlayerPresenter(
                source: playingMovie.map(localPlaySource) ?? PlaySource(
                    id: "",
                    name: "",
                    url: "",
                    format: "",
                    episodes: []
                ),
                allSources: [],
                isPresented: $playerPresented,
                startAt: playStartAt,
                onProgress: { position, duration in
                    guard let movie = playingMovie else { return }
                    PlaybackProgressStore.shared.save(
                        folderID: movie.folderID,
                        position: position,
                        duration: duration
                    )
                }
            )
        )
        .onAppear {
            DownloadManager.shared.scanDownloadsDirectory()
        }
    }

    /// 可选状态 → isPresented 绑定：单一数据源，避免"双状态"导致弹窗空白
    private var promptBinding: Binding<Bool> {
        Binding(
            get: { prompt != nil },
            set: { if !$0 { prompt = nil } }
        )
    }

    // MARK: - 弹窗动作

    @ViewBuilder
    private func promptActions(for item: DownloadsPrompt) -> some View {
        switch item {
        case .cancelTask(let task):
            Button("删除任务并清除已下载分片", role: .destructive) {
                prompt = nil
                DownloadManager.shared.cancelTask(task)
            }
            Button("取消", role: .cancel) { prompt = nil }

        case .deleteMovie(let movie):
            Button("删除", role: .destructive) {
                prompt = nil
                DownloadManager.shared.deleteMovie(movie)
                viewModel.forget(movie.title)
            }
            Button("取消", role: .cancel) { prompt = nil }

        case .resume(let movie):
            Button("继续观看（从 \(resumePositionText(for: movie)) 开始）") {
                let position = PlaybackProgressStore.shared.record(for: movie.folderID)?.position ?? 0
                prompt = nil
                beginPlayback(movie, from: position, delayed: true)
            }
            Button("从头播放") {
                PlaybackProgressStore.shared.clear(folderID: movie.folderID)
                prompt = nil
                beginPlayback(movie, from: 0, delayed: true)
            }
            Button("取消", role: .cancel) { prompt = nil }
        }
    }

    // MARK: - 播放

    private func requestPlayback(_ movie: DownloadedMovie) {
        if let record = PlaybackProgressStore.shared.record(for: movie.folderID), record.position > 1 {
            prompt = .resume(movie)
        } else {
            beginPlayback(movie, from: 0, delayed: false)
        }
    }

    /// 从弹窗里点"继续观看/从头播放"时，confirmationDialog 还在收起动画中；
    /// 若立刻 present，PlayerWindowPresenter 会把播放器挂到还没消失的弹窗上，
    /// 导致播放器一闪而过，所以延后一拍再起播。
    private func beginPlayback(_ movie: DownloadedMovie, from position: Double, delayed: Bool) {
        let start = {
            playStartAt = position
            playingMovie = movie
            playerPresented = true
        }
        if delayed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: start)
        } else {
            start()
        }
    }

    private func resumePositionText(for movie: DownloadedMovie) -> String {
        let position = PlaybackProgressStore.shared.record(for: movie.folderID)?.position ?? 0
        return PlaybackProgressStore.displayTime(position)
    }

    private func localPlaySource(for movie: DownloadedMovie) -> PlaySource {
        // TS 内容以 movie.m3u8 入口、配合 seg_* 分片本地保存。
        // iOS 的 AVPlayer 不支持从本地文件系统直接播放 HLS(m3u8)（CoreMedia -12865），
        // 因此必须通过本地 HTTP 服务器以 http://127.0.0.1 提供。
        // fMP4 / 旧版 mp4 为单个文件，本地 file:// 可直接播放。
        let isHLS = movie.format == "ts"
        if isHLS, !movie.folderID.isEmpty {
            LocalMediaServer.shared.start()
            if let base = LocalMediaServer.shared.baseURL {
                let url = base
                    .appendingPathComponent(movie.folderID)
                    .appendingPathComponent("movie.m3u8")
                return PlaySource(
                    id: movie.id,
                    name: movie.episodeName,
                    url: url.absoluteString,
                    format: movie.format,
                    episodes: []
                )
            }
            // 兜底：服务器尚未就绪（极少发生），退回 file://（会触发 -12865，便于排查）
        }

        let fileURL = URL(fileURLWithPath: movie.fileURL).absoluteString
        return PlaySource(
            id: movie.id,
            name: movie.episodeName,
            url: fileURL,
            format: movie.format,
            episodes: []
        )
    }
}

// MARK: - 弹窗状态

/// 本页所有二次确认 / 询问共用一个弹窗，避免同层多个 presentation modifier 冲突
private enum DownloadsPrompt {
    case cancelTask(DownloadTask)
    case deleteMovie(DownloadedMovie)
    case resume(DownloadedMovie)

    var title: String {
        switch self {
        case .cancelTask:  return "取消下载"
        case .deleteMovie: return "删除已下载内容"
        case .resume:      return "继续观看"
        }
    }

    var message: String {
        switch self {
        case .cancelTask(let task):
            return "《\(task.title)》\(task.episodeName)"
        case .deleteMovie(let movie):
            return "《\(movie.title)》\(movie.episodeName) · 将释放 \(DownloadFormat.size(movie.fileSize)) 空间"
        case .resume(let movie):
            return "《\(movie.title)》\(movie.episodeName)"
        }
    }
}

// MARK: - 下载中区域
//
// 自带 @ObservedObject：下载进度每秒更新多次，刷新必须限制在这个子视图内，
// 不能污染挂着弹窗的父视图。

private struct DownloadingSectionView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    /// 请求二次确认取消，弹窗由父视图统一呈现
    let onCancelRequested: (DownloadTask) -> Void

    var body: some View {
        if !downloadManager.tasks.isEmpty {
            Section("下载中") {
                ForEach(downloadManager.tasks) { task in
                    DownloadTaskCard(
                        task: task,
                        onPause: { downloadManager.pauseTask(task) },
                        onResume: { downloadManager.resumeTask(task) },
                        onRetry: { downloadManager.retryTask(task) },
                        onCancel: { onCancelRequested(task) }
                    )
                    .cardRow()
                    .swipeActions {
                        Button(role: .destructive) {
                            onCancelRequested(task)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 已下载（按剧名分组）

private struct DownloadedSectionView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject var viewModel: DownloadsViewModel
    let onPlay: (DownloadedMovie) -> Void
    /// 直接从头播放，不走续播询问（右滑快捷入口，也是弹窗异常时的保底路径）
    let onPlayFromStart: (DownloadedMovie) -> Void
    let onDeleteRequested: (DownloadedMovie) -> Void

    private var groups: [DownloadGroup] {
        viewModel.groups(from: downloadManager.downloadedMovies)
    }

    var body: some View {
        if !groups.isEmpty {
            Section("已下载") {
                ForEach(groups) { group in
                    let isExpanded = viewModel.isExpanded(group, groupCount: groups.count)

                    DownloadGroupHeader(
                        group: group,
                        isExpanded: isExpanded,
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.toggle(group, groupCount: groups.count)
                            }
                        }
                    )
                    .cardRow(leading: 16, trailing: 16, top: 6, bottom: 6)

                    if isExpanded {
                        ForEach(group.episodes) { movie in
                            Button {
                                onPlay(movie)
                            } label: {
                                DownloadedEpisodeRow(movie: movie)
                            }
                            .buttonStyle(.plain)
                            .cardRow(leading: 32, trailing: 24, top: 3, bottom: 3)
                            .swipeActions(edge: .leading) {
                                Button {
                                    onPlayFromStart(movie)
                                } label: {
                                    Label("从头播放", systemImage: "play.circle")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    onDeleteRequested(movie)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 空状态

private struct EmptyDownloadsSection: View {
    @ObservedObject private var downloadManager = DownloadManager.shared

    var body: some View {
        if downloadManager.tasks.isEmpty && downloadManager.downloadedMovies.isEmpty {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("还没有下载内容")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("在影视详情页选择剧集即可离线缓存，下载完成后在这里播放")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .listRowBackground(Color.clear)
            }
        }
    }
}

// MARK: - 工具栏菜单

private struct DownloadsToolbarMenu: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject var viewModel: DownloadsViewModel

    private var groups: [DownloadGroup] {
        viewModel.groups(from: downloadManager.downloadedMovies)
    }

    var body: some View {
        Menu {
            if !downloadManager.tasks.isEmpty {
                Button("全部暂停") { downloadManager.pauseAllTasks() }
                Button("全部继续") { downloadManager.resumeAllTasks() }
            }
            if !groups.isEmpty {
                Button("展开全部") { viewModel.expandAll(groups) }
                Button("折叠全部") { viewModel.collapseAll(groups) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .disabled(downloadManager.tasks.isEmpty && groups.isEmpty)
    }
}

// MARK: - 下载中卡片

private struct DownloadTaskCard: View {
    let task: DownloadTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PosterThumb(localPath: task.posterPath, remoteURL: task.posterURL, width: 54, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(task.episodeName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                ProgressView(value: min(max(task.progress, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(statusColor)

                HStack(spacing: 6) {
                    Text("\(Int(task.progress * 100))%")
                        .foregroundColor(statusColor)

                    if task.status == .downloading, task.speed > 0 {
                        Text("·")
                        Text(DownloadFormat.speed(task.speed))
                        if task.remainingSeconds > 1 {
                            Text("·")
                            Text("剩 \(DownloadFormat.remaining(task.remainingSeconds))")
                        }
                    }

                    Spacer()

                    Text(task.status.displayText)
                        .foregroundColor(statusColor)
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

                Text(progressDetail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if let error = task.errorMessage, !error.isEmpty {
                    Text(error)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }

                HStack(spacing: 16) {
                    switch task.status {
                    case .downloading:
                        actionButton("暂停", systemImage: "pause.circle", action: onPause)
                        destructiveButton("取消", systemImage: "xmark.circle", action: onCancel)

                    case .paused:
                        actionButton("继续", systemImage: "play.circle", action: onResume)
                        destructiveButton("取消", systemImage: "xmark.circle", action: onCancel)

                    case .failed:
                        actionButton("重试", systemImage: "arrow.clockwise.circle", action: onRetry)
                        destructiveButton("删除", systemImage: "trash.circle", action: onCancel)

                    case .completed:
                        EmptyView()
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var progressDetail: String {
        var parts: [String] = []
        if task.totalSegments > 0 {
            parts.append("\(task.completedSegments)/\(task.totalSegments) 分片")
        }
        if task.totalBytes > 0 {
            parts.append("\(DownloadFormat.size(task.downloadedBytes)) / 约 \(DownloadFormat.size(task.totalBytes))")
        } else if task.downloadedBytes > 0 {
            parts.append(DownloadFormat.size(task.downloadedBytes))
        }
        return parts.isEmpty ? "准备中…" : parts.joined(separator: " · ")
    }

    private var statusColor: Color {
        switch task.status {
        case .downloading: return .blue
        case .paused:      return .orange
        case .completed:   return .green
        case .failed:      return .red
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // 不用 Label：它自带的图标/文字间距偏大，HStack 才能把两者贴紧
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
    }

    private func destructiveButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            // role: .destructive 只会把文字染红，图标仍吃 tint（蓝色），
            // 所以这里显式给整组上红色
            HStack(spacing: 3) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - 剧集分组头

private struct DownloadGroupHeader: View {
    let group: DownloadGroup
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                PosterThumb(localPath: group.posterPath, remoteURL: group.posterURL, width: 56, height: 84)

                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Text("\(group.episodeCount) 集 · 共 \(DownloadFormat.size(group.totalSize))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("最近下载 \(DownloadFormat.date(group.latestDate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 已下载单集

private struct DownloadedEpisodeRow: View {
    let movie: DownloadedMovie

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.title3)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(movie.episodeName.isEmpty ? "正片" : movie.episodeName)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(DownloadFormat.size(movie.fileSize)) · \(movie.format.uppercased())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - 海报缩略图

private struct PosterThumb: View {
    let localPath: String?
    let remoteURL: String?
    let width: CGFloat
    let height: CGFloat

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: cacheKey) { await load() }
    }

    private var cacheKey: String {
        if let localPath, !localPath.isEmpty { return "file:" + localPath }
        if let remoteURL, !remoteURL.isEmpty { return "url:" + remoteURL }
        return ""
    }

    private func load() async {
        guard !cacheKey.isEmpty else { return }
        if let cached = PosterImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }
        // 优先本地缓存的海报：断网也能显示
        if let localPath, !localPath.isEmpty, let loaded = UIImage(contentsOfFile: localPath) {
            PosterImageCache.shared.store(loaded, for: cacheKey)
            image = loaded
            return
        }
        // 旧条目没有本地海报，联网兜一次
        guard let remoteURL, !remoteURL.isEmpty, let url = URL(string: remoteURL) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let downloaded = UIImage(data: data) else { return }
        PosterImageCache.shared.store(downloaded, for: cacheKey)
        image = downloaded
    }
}

private final class PosterImageCache {
    static let shared = PosterImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 200
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

// MARK: - 展示格式化

private enum DownloadFormat {
    private static let bytesFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func size(_ bytes: Int64) -> String {
        bytesFormatter.string(fromByteCount: bytes)
    }

    static func speed(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else { return "—" }
        return bytesFormatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    static func remaining(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "未知" }
        if seconds >= 3600 { return String(format: "%.1f 小时", seconds / 3600) }
        if seconds >= 60 { return String(format: "%.0f 分钟", seconds / 60) }
        return String(format: "%.0f 秒", seconds)
    }

    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}

// MARK: - 卡片行样式

private extension View {
    /// 让 List 行变成独立卡片：去掉分隔线与默认内边距，背景交给内容自己画
    func cardRow(
        leading: CGFloat = 12,
        trailing: CGFloat = 12,
        top: CGFloat = 4,
        bottom: CGFloat = 4
    ) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}
