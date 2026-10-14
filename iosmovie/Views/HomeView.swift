import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var noticeManager = NoticeManager()
    @State private var showNotice = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                categoryBar
                content
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("影视王")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        NavigationLink(destination: DownloadsView()) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 17, weight: .semibold))
                        }

                        NavigationLink(destination: SearchPage()) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 17, weight: .semibold))
                        }

                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 17, weight: .semibold))
                        }
                    }
                    .foregroundColor(AppTheme.textPrimary)
                }
            }
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

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(viewModel.categories) { category in
                    CategoryChip(
                        title: category.name,
                        isSelected: viewModel.selectedCategoryID == category.id
                    ) {
                        Task { await viewModel.selectCategory(category) }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.vertical, 10)
        }
        .background(AppTheme.background)
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
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    SectionHeader(
                        title: "热门推荐",
                        subtitle: "来自 \(viewModel.currentSite.name) 的精选内容"
                    )
                    .padding(.horizontal, AppTheme.pagePadding)

                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(viewModel.movies) { movie in
                            MediaCard(
                                title: movie.title,
                                subtitle: metadata(for: movie),
                                rating: movie.rating,
                                detailText: "来源 \(viewModel.currentSite.name)",
                                tagText: movie.type,
                                posterURL: movie.posterURL
                            ) {
                                HomeDetailRouter(movie: movie)
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 28)
                }
                .padding(.top, 6)
            }
        }
    }

    private func metadata(for movie: MovieItem) -> String {
        let parts = [movie.year, movie.type].filter { !$0.isEmpty }
        return parts.isEmpty ? "影视" : parts.joined(separator: " · ")
    }
}
