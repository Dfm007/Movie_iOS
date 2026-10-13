import SwiftUI

struct SearchPage: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var history: [String] = SearchHistoryStore.all()
    @State private var showResult = false
    @State private var resultKeyword = ""

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            if history.isEmpty {
                emptyHistoryView
            } else {
                historyListView
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.large)
        .background(AppTheme.background.ignoresSafeArea())
        .background(
            NavigationLink(
                destination: SearchResultView(keyword: resultKeyword),
                isActive: $showResult
            ) {
                EmptyView()
            }
        )
        .onAppear {
            history = SearchHistoryStore.all()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            AppSearchField(placeholder: "搜索影视、演员或类型", text: $searchText) {
                submitSearch()
            }

            Button("搜索") {
                submitSearch()
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.black.opacity(0.86))
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .background(Capsule().fill(AppTheme.accent))
            .buttonStyle(PressableScaleButtonStyle())
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.vertical, 12)
    }

    private var historyListView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: "搜索历史",
                    actionTitle: "清空"
                ) {
                    SearchHistoryStore.removeAll()
                    history = []
                }
                .padding(.horizontal, AppTheme.pagePadding)

                ForEach(history, id: \.self) { keyword in
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(AppTheme.textSecondary)

                        Button(keyword) {
                            submitSearch(keyword)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppTheme.textPrimary)
                        .buttonStyle(PlainButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            SearchHistoryStore.remove(keyword)
                            history = SearchHistoryStore.all()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        .buttonStyle(PressableScaleButtonStyle())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                            .fill(AppTheme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.radiusMedium, style: .continuous)
                            .stroke(AppTheme.border, lineWidth: 0.5)
                    )
                    .padding(.horizontal, AppTheme.pagePadding)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var emptyHistoryView: some View {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "还没有搜索记录",
            message: "输入片名、演员或类型，找到你想看的影视。"
        )
        .frame(maxHeight: .infinity)
    }

    private func submitSearch(_ keyword: String? = nil) {
        let text = (keyword ?? searchText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        searchText = text
        SearchHistoryStore.add(text)
        history = SearchHistoryStore.all()
        resultKeyword = text
        showResult = true
    }
}
