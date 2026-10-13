import SwiftUI

struct SearchResultView: View {
    let keyword: String
    @StateObject private var viewModel = SearchViewModel()
    @State private var layout: SearchResultLayout = .grid

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        Group {
            if viewModel.isLoading {
                LoadingStateView(title: "正在搜索")
            } else if let error = viewModel.errorMessage {
                EmptyStateView(
                    icon: "film.stack",
                    title: "没有找到结果",
                    message: error + "，换个关键词试试。"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("搜索结果")
                                    .font(.title3.weight(.bold))
                                    .foregroundColor(AppTheme.textPrimary)
                                Text("共 \(viewModel.results.count) 部影视")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                            }

                            Spacer(minLength: 8)

                            Picker("布局", selection: $layout) {
                                ForEach(SearchResultLayout.allCases) { item in
                                    Text(item.title).tag(item)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .tint(AppTheme.accent)
                            .frame(width: 118)
                        }
                        .padding(.horizontal, AppTheme.pagePadding)

                        resultsContent
                            .padding(.horizontal, AppTheme.pagePadding)
                            .padding(.bottom, 28)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("搜索：\(keyword)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.search(keyword: keyword)
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if layout == .grid {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(viewModel.results) { item in
                    MediaCard(
                        title: item.title,
                        subtitle: metadata(for: item),
                        rating: item.rating,
                        badgeText: "\(item.sourceDetails.count)源",
                        detailText: "\(item.sourceDetails.count) 个来源",
                        tagText: item.type,
                        compact: true,
                        posterURL: item.posterURL
                    ) {
                        SearchDetailView(item: item)
                    }
                }
            }
        } else {
            LazyVStack(spacing: 10) {
                ForEach(viewModel.results) { item in
                    MediaRow(
                        title: item.title,
                        subtitle: metadata(for: item),
                        rating: item.rating,
                        badgeText: "\(item.sourceDetails.count)源",
                        posterURL: item.posterURL
                    ) {
                        SearchDetailView(item: item)
                    }
                }
            }
        }
    }

    private func metadata(for item: SearchResultItem) -> String {
        let parts = [item.year, item.type].filter { !$0.isEmpty }
        return parts.isEmpty ? "影视" : parts.joined(separator: " · ")
    }
}

private enum SearchResultLayout: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "网格"
        case .list: return "列表"
        }
    }
}

struct SearchDetailView: View {
    let item: SearchResultItem

    var body: some View {
        DetailView(
            detailURL: item.sourceDetails.first?.detailURL ?? "",
            initialTitle: item.title,
            availableSites: item.sourceDetails.map { $0.site },
            detailMap: Dictionary(uniqueKeysWithValues: item.sourceDetails.map { ($0.site.id, $0.detailURL) })
        )
    }
}