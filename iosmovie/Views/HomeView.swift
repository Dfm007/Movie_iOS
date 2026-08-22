import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showSearchResult = false
    @State private var searchKeyword = ""

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                categoryBar
                content
            }
            .navigationTitle("影视王")
            .searchable(text: $viewModel.searchText, prompt: "搜索影视")
            .onSubmit(of: .search) {
                let keyword = viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !keyword.isEmpty {
                    searchKeyword = keyword
                    showSearchResult = true
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
        }
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
                        NavigationLink(destination: DetailView(detailURL: movie.detailURL)) {
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
}
