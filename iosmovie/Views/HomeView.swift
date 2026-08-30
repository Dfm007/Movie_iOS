import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var noticeManager = NoticeManager()
    @State private var showSearchResult = false
    @State private var searchKeyword = ""
    @State private var showNotice = false
    @State private var searchHistory: [String] = SearchHistoryStore.all()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar

                if !searchHistory.isEmpty && viewModel.searchText.isEmpty {
                    searchHistoryView
                }

                categoryBar
                content
            }
            .navigationTitle("影视王")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gear")
                    }
                }
            }
            .background(
                NavigationLink(
                    destination: SearchResultView(keyword: searchKeyword),
                    isActive: $showSearchResult
                ) {
                    EmptyView()
                }
            )
            .task {
                await viewModel.loadInitial()
            }
            .onReceive(NotificationCenter.default.publisher(for: .defaultSourceDidChange)) { _ in
                Task {
                    await viewModel.updateDefaultSource(to: CMSSite.selectedDefaultSite)
                }
            }
        }
        .onAppear {
            noticeManager.fetch()
            Task {
                await viewModel.refreshDefaultSourceIfNeeded()
            }
        }
        .overlay {
            if showNotice, let notice = noticeManager.notice {
                NoticePopupView(notice: notice) {
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

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("搜索影视", text: $viewModel.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        submitSearch()
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Button("搜索") {
                submitSearch()
            }
            .buttonStyle(PlainButtonStyle())
            .foregroundColor(.blue)
            .disabled(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var searchHistoryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("搜索历史")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                Spacer()

                Button("清空") {
                    SearchHistoryStore.removeAll()
                    searchHistory = []
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            FlowLayout(spacing: 8) {
                ForEach(searchHistory, id: \.self) { keyword in
                    HStack(spacing: 4) {
                        Button(keyword) {
                            submitSearch(keyword)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button {
                            SearchHistoryStore.remove(keyword)
                            searchHistory = SearchHistoryStore.all()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(viewModel.categories) { category in
                    Button {
                        Task { await viewModel.selectCategory(category) }
                    } label: {
                        Text(category.name)
                            .font(.subheadline)
                            .fontWeight(viewModel.selectedCategoryID == category.id ? .semibold : .regular)
                            .foregroundColor(viewModel.selectedCategoryID == category.id ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    viewModel.selectedCategoryID == category.id
                                    ? Color.blue
                                    : Color(.systemGray5)
                                )
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            Spacer()
            ProgressView("加载中...")
            Spacer()
        } else if let error = viewModel.errorMessage {
            Spacer()
            VStack(spacing: 12) {
                Text("加载失败")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("重试") {
                    Task { await viewModel.loadInitial() }
                }
            }
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.movies) { movie in
                        NavigationLink(
                            destination: HomeDetailRouter(movie: movie)
                        ) {
                            VStack(alignment: .leading, spacing: 6) {
                                posterView(for: movie)
                                Text(movie.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 4) {
                                    if !movie.rating.isEmpty && movie.rating != "0.0" {
                                        Text(movie.rating)
                                            .font(.system(size: 11))
                                            .foregroundColor(.orange)
                                            .fontWeight(.semibold)
                                    }
                                    Text(movie.type)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder
    private func posterView(for movie: MovieItem) -> some View {
        if let posterURL = movie.posterURL, let url = URL(string: posterURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    posterPlaceholder(for: movie)
                        .overlay(ProgressView())
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    posterPlaceholder(for: movie)
                @unknown default:
                    posterPlaceholder(for: movie)
                }
            }
            .aspectRatio(2/3, contentMode: .fit)
        } else {
            posterPlaceholder(for: movie)
        }
    }

    private func posterPlaceholder(for movie: MovieItem) -> some View {
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
            .aspectRatio(2/3, contentMode: .fit)
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "film")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.7))
                    Text(movie.type)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
            )
    }

    private func submitSearch(_ keyword: String? = nil) {
        let text = (keyword ?? viewModel.searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        viewModel.searchText = text
        SearchHistoryStore.add(text)
        searchHistory = SearchHistoryStore.all()
        searchKeyword = text
        showSearchResult = true
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        y += rowHeight
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}