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
                EmptyStateView(
                    icon: "exclamationmark.triangle",
                    title: "无法进入详情",
                    message: errorMessage
                )
            } else {
                LoadingStateView(title: "正在解析多源")
            }
        }
        .appScreenBackground()
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

        let defaultSite = CMSSite.selectedDefaultSite
        var matches: [SourceDetail] = []
        var enteredDetail = false

        // 所有源并发解析：默认源用首页带来的 vod_id，其余源按标题搜索
        await withTaskGroup(of: (CMSSite, String)?.self) { group in
            // ① 默认源：直接用 vod_id 取详情（采集站搜索索引常与列表不一致，只靠搜索会误报"未找到"）
            if !movie.detailURL.isEmpty {
                let vodID = movie.detailURL
                group.addTask {
                    let source = AppleCMSSource(site: defaultSite)
                    guard (try? await source.fetchMovieDetail(path: vodID)) != nil else { return nil }
                    return (defaultSite, vodID)
                }
            }

            // ② 其他源：按标题搜索
            for site in CMSSite.all where site.id != defaultSite.id {
                group.addTask {
                    let source = AppleCMSSource(site: site)
                    guard let results = try? await source.searchMovies(keyword: title),
                          !results.isEmpty else {
                        return nil
                    }

                    let target = Self.normalize(title)

                    // 1. 完全匹配优先
                    if let exact = results.first(where: { Self.normalize($0.title) == target }) {
                        return (site, exact.id)
                    }

                    // 2. 候选标题包含目标标题，且是正片（非解说/预告等），选第一个
                    if let contained = results.first(where: { item in
                        let cand = Self.normalize(item.title)
                        return cand.contains(target) && !Self.isNonMainTitle(item.title)
                    }) {
                        return (site, contained.id)
                    }

                    // 3. 短标题（≤3字）不再做模糊匹配，避免"遮天"配成"一手遮天"
                    if target.count <= 3 {
                        return nil
                    }

                    // 4. 长标题才允许相似度匹配
                    var best: String?
                    var bestScore = 0.0
                    for item in results {
                        let score = Self.similarity(between: target, and: Self.normalize(item.title))
                        if score > bestScore {
                            bestScore = score
                            best = item.id
                        }
                    }
                    if let best = best, bestScore >= 0.6 {
                        return (site, best)
                    }
                    return nil
                }
            }

            // 任一源成功就先进详情；其余源后台继续，成功后陆续补进播放源列表
            for await case let (site, vodID)? in group {
                guard !matches.contains(where: { $0.site.id == site.id }) else { continue }
                matches.append(SourceDetail(id: "\(site.id)_\(vodID)", site: site, detailURL: vodID))
                sourceDetails = matches
                enteredDetail = true
            }
        }

        if !enteredDetail {
            errorMessage = "所有源都未找到该影片"
        }
    }

    // 判断是否是解说、预告等非正片标题
    private static func isNonMainTitle(_ title: String) -> Bool {
        let keywords = ["解说", "预告", "花絮", "合集", "cut", "CUT", "Cut", "片段", "精彩"]
        return keywords.contains(where: { title.contains($0) })
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
