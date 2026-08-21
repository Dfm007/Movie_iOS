import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationView {
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
                            Task { await viewModel.loadHome() }
                        }
                    }
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
                    }
                }
            }
            .navigationTitle("影视王")
            .searchable(text: $viewModel.searchText, prompt: "搜索影视")
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
            .task {
                await viewModel.loadHome()
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
