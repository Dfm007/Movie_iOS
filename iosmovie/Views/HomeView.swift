import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var noticeManager = NoticeManager()
    @State private var showNotice = false

    private let pagePadding: CGFloat = 20
    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                homeBackground

                VStack(spacing: 0) {
                    homeHeader
                    searchEntry
                    categoryBar
                    content
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                // 配置页与首页数据并行拉取
                let configTask = Task.detached { await AppConfig.shared.refresh() }
                let homeTask = Task { await viewModel.loadInitial() }

                // 配置就绪后请求公告接口，公告接口会同时返回公告、版本号和更新地址
                await configTask.value
                noticeManager.fetch()

                await homeTask.value
            }
            .onReceive(NotificationCenter.default.publisher(for: .defaultSourceDidChange)) { _ in
                Task {
                    await viewModel.updateDefaultSource(to: CMSSite.selectedDefaultSite)
                }
            }
        }
        .navigationViewStyle(.stack)
        .onAppear {
            Task {
                await viewModel.refreshDefaultSourceIfNeeded()
            }
        }
        .overlay {
            if showNotice, let notice = noticeManager.notice {
                NoticePopupView(
                    notice: notice,
                    icon: noticeManager.isUpdateNotice ? "arrow.down.circle.fill" : "megaphone.fill",
                    primaryTitle: noticeManager.isUpdateNotice ? "去更新" : "知道了",
                    onPrimary: noticeManager.isUpdateNotice ? openUpdateURL : nil
                ) {
                    showNotice = false
                }
            }
        }
        .onChange(of: noticeManager.notice) { newValue in
            if newValue != nil {
                showNotice = true
            }
        }
    }

    // MARK: - 版本更新

    /// 更新公告的「去更新」按钮：打开公告接口下发的地址
    private func openUpdateURL() {
        if let url = AppConfig.shared.updateURL {
            UIApplication.shared.open(url)
        }
        showNotice = false
    }

    private var homeBackground: some View {
        ZStack {
            AppTheme.background

            RadialGradient(
                colors: [AppTheme.accent.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 300
            )

            LinearGradient(
                colors: [AppTheme.surface.opacity(0.24), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var homeHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(AppTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppTheme.background)
                            .offset(x: 1)
                    }
                    .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 6)

                Text("影视王")
                    .font(.system(size: 28, weight: .heavy))
                    .tracking(-0.8)
                    .foregroundColor(AppTheme.textPrimary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                toolbarLink(systemImage: "arrow.down.to.line", label: "下载") {
                    DownloadsView()
                }

                toolbarLink(systemImage: "gearshape", label: "设置") {
                    SettingsView()
                }
            }
        }
        .frame(height: 54)
        .padding(.horizontal, pagePadding)
        .padding(.top, 4)
    }

    private func toolbarLink<Destination: View>(
        systemImage: String,
        label: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.textPrimary)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(AppTheme.surface.opacity(0.78))
                )
                .overlay(
                    Circle()
                        .stroke(AppTheme.border.opacity(0.75), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .accessibilityLabel(label)
    }

    private var searchEntry: some View {
        NavigationLink(destination: SearchPage()) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)

                Text("搜索片名、演员或导演")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(AppTheme.textSecondary)

                Spacer(minLength: 8)

                Text("搜索")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 25)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(AppTheme.mutedFill.opacity(0.7))
                    )
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surface.opacity(0.92))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .padding(.horizontal, pagePadding)
        .padding(.top, 15)
        .accessibilityLabel("搜索片名、演员或导演")
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.categories) { category in
                    CategoryChip(
                        title: shortCategoryTitle(category.name),
                        isSelected: viewModel.selectedCategoryID == category.id
                    ) {
                        Task { await viewModel.selectCategory(category) }
                    }
                }
            }
            .padding(.horizontal, pagePadding)
            .padding(.vertical, 14)
        }
    }

    private func shortCategoryTitle(_ name: String) -> String {
        switch name {
        case "电影片": return "电影"
        case "综艺片": return "综艺"
        case "动漫片": return "动漫"
        case "动作片": return "动作"
        default: return name
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.movies.isEmpty {
            LoadingStateView(title: "正在准备片库")
        } else if let error = viewModel.errorMessage, viewModel.movies.isEmpty {
            EmptyStateView(
                icon: "wifi.exclamationmark",
                title: "加载失败",
                message: error,
                actionTitle: "重新加载"
            ) {
                Task { await viewModel.loadInitial() }
            }
            .frame(maxHeight: .infinity)
        } else if viewModel.movies.isEmpty {
            EmptyStateView(
                icon: "film.stack",
                title: "暂无更新",
                message: "当前栏目还没有内容，稍后再来看看。"
            )
            .frame(maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let featured = viewModel.movies.first {
                        HomeHeroCard(movie: featured) {
                            HomeDetailRouter(movie: featured)
                        }
                        .padding(.horizontal, pagePadding)
                    }

                    updatesHeader
                        .padding(.horizontal, pagePadding)
                        .padding(.top, 20)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(Array(viewModel.movies.dropFirst())) { movie in
                            HomeMediaCard(movie: movie) {
                                HomeDetailRouter(movie: movie)
                            }
                        }
                    }
                    .padding(.horizontal, pagePadding)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var updatesHeader: some View {
        HStack(spacing: 9) {
            Text("今日更新")
                .font(.title3.weight(.bold))
                .foregroundColor(AppTheme.textPrimary)

            Text(sourceLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(AppTheme.surface.opacity(0.78))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(AppTheme.border.opacity(0.7), lineWidth: 0.5)
                )

            Spacer(minLength: 8)

            NavigationLink(destination: SearchPage()) {
                HStack(spacing: 2) {
                    Text("查看全部")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.textSecondary)
            }
            .buttonStyle(PressableScaleButtonStyle())
        }
    }

    private var sourceLabel: String {
        if viewModel.currentSite.id == "lzm3u8" {
            return "量子精选"
        }
        return "\(viewModel.currentSite.name)精选"
    }

}

private struct HomeHeroCard<Destination: View>: View {
    let movie: MovieItem
    let destination: () -> Destination

    private var rating: String? {
        normalizedRating(movie.rating)
    }

    private var metadata: String {
        var parts = [movie.type, movie.year].filter { !$0.isEmpty }
        parts.append("今日更新")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            ZStack(alignment: .bottomLeading) {
                Color.black

                GeometryReader { proxy in
                    heroImage
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }

                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.02), location: 0.18),
                        .init(color: Color.black.opacity(0.20), location: 0.52),
                        .init(color: Color.black.opacity(0.92), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [Color.black.opacity(0.48), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(AppTheme.warning)

                            Text("本周热播")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 27)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.white.opacity(0.15))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                        )

                        Spacer(minLength: 12)

                        HStack(spacing: 4) {
                            if rating != nil {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(AppTheme.warning)
                            }

                            Text(rating ?? "新上线")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.35), radius: 3, x: 0, y: 1)
                    }

                    Spacer(minLength: 18)

                    Text(movie.title)
                        .font(.system(size: 25, weight: .heavy))
                        .tracking(-0.5)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)

                    Text(metadata)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.78))
                        .lineLimit(1)
                        .padding(.top, 7)

                    HStack(spacing: 9) {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))

                            Text("立即播放")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundColor(Color.black.opacity(0.86))
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                        )

                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
                            )
                    }
                    .padding(.top, 13)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(18)
            }
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 10)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .accessibilityLabel("本周热播，\(movie.title)")
    }

    @ViewBuilder
    private var heroImage: some View {
        if let posterURL = movie.posterURL, let url = URL(string: posterURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    heroPlaceholder.overlay {
                        ProgressView()
                            .tint(.white)
                    }
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    heroPlaceholder
                @unknown default:
                    heroPlaceholder
                }
            }
        } else {
            heroPlaceholder
        }
    }

    private var heroPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, AppTheme.surfaceElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "film.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundColor(Color.white.opacity(0.3))
        }
    }
}

private struct HomeMediaCard<Destination: View>: View {
    let movie: MovieItem
    let destination: () -> Destination

    private var rating: String? {
        normalizedRating(movie.rating)
    }

    private var metadata: String {
        let parts = [movie.type, movie.year].filter { !$0.isEmpty }
        return parts.isEmpty ? "影视" : parts.joined(separator: " · ")
    }

    var body: some View {
        NavigationLink(destination: destination()) {
            VStack(alignment: .leading, spacing: 0) {
                PosterArtwork(
                    posterURL: movie.posterURL,
                    fallbackTitle: movie.title,
                    cornerRadius: 17
                )
                .shadow(color: Color.black.opacity(0.10), radius: 12, x: 0, y: 7)

                Text(movie.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(minHeight: 40, alignment: .topLeading)
                    .padding(.top, 10)

                HStack(spacing: 6) {
                    Text(metadata)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppTheme.textSecondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let rating = rating {
                        Text("\(rating) 分")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppTheme.warning)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableScaleButtonStyle())
        .accessibilityLabel(movie.title)
    }
}

private func normalizedRating(_ rating: String) -> String? {
    let value = rating.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, value != "0", value != "0.0" else { return nil }
    return value
}
