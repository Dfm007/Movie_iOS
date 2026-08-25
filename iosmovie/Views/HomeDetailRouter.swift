import SwiftUI

// 主页进详情前的中间视图：先并发搜索所有源，为每个源解析出各自的 detailURL，
// 再进入 DetailView，避免切源时用错 vod_id 导致串剧或 -1017。
struct HomeDetailRouter: View {
    let movie: MovieItem

    @State private var sourceDetails: [SourceDetail]?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let sourceDetails = sourceDetails {
                let defaultSite = CMSSite.selectedDefaultSite
                let defaultDetail = sourceDetails.first(where: { $0.site.id == defaultSite.id })
                    ?? sourceDetails.first
                let sites = sourceDetails.map { $0.site }
                let detailMap = Dictionary(uniqueKeysWithValues: sourceDetails.map { ($0.site.id, $0.detailURL) })

                DetailView(
                    detailURL: defaultDetail?.detailURL ?? movie.detailURL,
                    initialTitle: movie.title,
                    availableSites: sites,
                    detailMap: detailMap
                )
            } else if let errorMessage = errorMessage {
                VStack(spacing: 12) {
                    Text("无法进入详情")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                ProgressView("正在解析多源...")
            }
        }
        .navigationTitle(movie.title)
        .task {
            await resolveSources()
        }
    }

    private func resolveSources() async {
        let title = movie.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            errorMessage = "影片标题为空"
            return
        }

        var matches: [SourceDetail] = []

        await withTaskGroup(of: (CMSSite, MovieItem)?.self) { group in
            for site in CMSSite.all {
                group.addTask {
                    let source = AppleCMSSource(site: site)
                    guard let results = try? await source.searchMovies(keyword: title),
                          !results.isEmpty else {
                        return nil
                    }
                    // 用与 SearchViewModel 相同的归一化逻辑匹配
                    let target = Self.normalize(title)
                    if let exact = results.first(where: { Self.normalize($0.title) == target }) {
                        return (site, exact)
                    }
                    // 退而求其次：相似度匹配
                    var best: MovieItem?
                    var bestScore = 0.0
                    for item in results {
                        let score = Self.similarity(between: target, and: Self.normalize(item.title))
                        if score > bestScore {
                            bestScore = score
                            best = item
                        }
                    }
                    if let best = best, bestScore >= 0.6 {
                        return (site, best)
                    }
                    return nil
                }
            }

            for await case let (site, movie)? in group {
                if !matches.contains(where: { $0.site.id == site.id }) {
                    matches.append(SourceDetail(id: "\(site.id)_\(movie.id)", site: site, detailURL: movie.id))
                }
            }
        }

        if matches.isEmpty {
            errorMessage = "所有源都未找到该影片"
        } else {
            // 默认源置顶
            let defaultID = CMSSite.selectedDefaultSite.id
            matches.sort { a, b in
                if a.site.id == defaultID { return true }
                if b.site.id == defaultID { return false }
                return false
            }
            sourceDetails = matches
        }
    }

    // 与 SearchViewModel.normalize 保持一致
    static func normalize(_ text: String) -> String {
        var result = text.lowercased()
        result = result.replacingOccurrences(of: " ", with: "")
        result = result.replacingOccurrences(of: "　", with: "")
        result = result.replacingOccurrences(of: "·", with: "")
        result = result.replacingOccurrences(of: "・", with: "")
        result = result.replacingOccurrences(of: ".", with: "")
        result = result.replacingOccurrences(of: "-", with: "")
        result = result.replacingOccurrences(of: "—", with: "")
        result = result.replacingOccurrences(of: ":", with: "")
        result = result.replacingOccurrences(of: "：", with: "")
        return result
    }

    static func similarity(between a: String, and b: String) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        let aChars = Array(a)
        let bChars = Array(b)
        let maxLen = max(aChars.count, bChars.count)
        guard maxLen > 0 else { return 0 }
        var dp = Array(repeating: Array(repeating: 0, count: bChars.count + 1), count: aChars.count + 1)
        for i in 0...aChars.count { dp[i][0] = i }
        for j in 0...bChars.count { dp[0][j] = j }
        for i in 1...aChars.count {
            for j in 1...bChars.count {
                if aChars[i - 1] == bChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
                }
            }
        }
        let distance = Double(dp[aChars.count][bChars.count])
        return 1.0 - (distance / Double(maxLen))
    }
}