import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

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
                    List(viewModel.movies) { movie in
                        NavigationLink(destination: DetailView(detailURL: movie.detailURL)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(movie.title)
                                    .font(.body)
                                HStack {
                                    Text(movie.type)
                                    Text(movie.year)
                                    Text(movie.rating)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
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
}
