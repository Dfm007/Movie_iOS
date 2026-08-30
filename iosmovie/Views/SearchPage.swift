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
        .navigationBarTitleDisplayMode(.inline)
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
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("搜索影视", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onSubmit {
                        submitSearch()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
            .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var historyListView: some View {
        List {
            Section {
                ForEach(history, id: \.self) { keyword in
                    HStack {
                        Button(keyword) {
                            submitSearch(keyword)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            SearchHistoryStore.remove(keyword)
                            history = SearchHistoryStore.all()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .onDelete { indexSet in
                    let keywords = indexSet.map { history[$0] }
                    keywords.forEach { SearchHistoryStore.remove($0) }
                    history = SearchHistoryStore.all()
                }
            } header: {
                HStack {
                    Text("搜索历史")
                    Spacer()
                    Button("清空") {
                        SearchHistoryStore.removeAll()
                        history = []
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyHistoryView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("暂无搜索历史")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
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