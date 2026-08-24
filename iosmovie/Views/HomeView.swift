import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @StateObject private var noticeManager = NoticeManager()
    @State private var showSearchResult = false
    @State private var searchKeyword = ""
    @State private var showNotice = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
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
                        let currentSite = viewModel.currentSite
                        NavigationLink(
                            destination: DetailView(
                                detailURL: movie.detailURL,
                                initialTitle: movie.title,
                                availableSites: [currentSite],
                                detailMap: [currentSite.id: movie.detailURL]
                            )
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
                    Text(movie.title)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                }
            )
    }

    private func submitSearch() {
        let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        searchKeyword = keyword
        showSearchResult = true
    }
}