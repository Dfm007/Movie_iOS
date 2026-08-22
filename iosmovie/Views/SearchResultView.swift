import SwiftUI

struct SearchResultView: View {
    let keyword: String
    @StateObject private var viewModel = SearchViewModel()

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("搜索中...")
            } else if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.headline)
                    Text("换个关键词试试")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(viewModel.results) { item in
                            NavigationLink(destination: SearchDetailView(item: item)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    posterView(for: item)
                                    Text(item.title)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    HStack(spacing: 4) {
                                        if !item.rating.isEmpty && item.rating != "0.0" {
                                            Text(item.rating)
                                                .font(.system(size: 11))
                                                .foregroundColor(.orange)
                                                .fontWeight(.semibold)
                                        }
                                        Text(item.type)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(item.sourceDetails.count)源")
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
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
        .navigationTitle("搜索：\(keyword)")
        .task {
            await viewModel.search(keyword: keyword)
        }
    }

    @ViewBuilder
    private func posterView(for item: SearchResultItem) -> some View {
        if let posterURL = item.posterURL, let url = URL(string: posterURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    posterPlaceholder(for: item)
                        .overlay(ProgressView())
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                case .failure:
                    posterPlaceholder(for: item)
                @unknown default:
                    posterPlaceholder(for: item)
                }
            }
            .aspectRatio(2/3, contentMode: .fit)
        } else {
            posterPlaceholder(for: item)
        }
    }

    private func posterPlaceholder(for item: SearchResultItem) -> some View {
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
                    Text(item.type)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
            )
    }
}

struct SearchDetailView: View {
    let item: SearchResultItem

    var body: some View {
        DetailView(
            detailURL: item.sourceDetails.first?.detailURL ?? "",
            availableSites: item.sourceDetails.map { $0.site },
            detailMap: Dictionary(uniqueKeysWithValues: item.sourceDetails.map { ($0.site.id, $0.detailURL) })
        )
    }
}
    let item: SearchResultItem

    var body: some View {
        DetailView(
            detailURL: item.sourceDetails.first?.detailURL ?? "",
            availableSites: item.sourceDetails.map { $0.site }
        )
    }
}
