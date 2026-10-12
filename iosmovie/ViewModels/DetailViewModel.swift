import Foundation

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var movieTitle = ""
    @Published var posterURL: String?
    @Published var year = ""
    @Published var area = ""
    @Published var className = ""
    @Published var actors = ""
    @Published var director = ""
    @Published var remarks = ""
    @Published var intro = ""
    @Published var sources: [PlaySource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSite: CMSSite = .defaultSite

    var sites: [CMSSite] = CMSSite.all
    private(set) var hasConfigured = false

    private var siteDetailMap: [String: String] = [:]
    private var currentMovieTitle = ""
    private var lastFetchError: Error?

    func configure(availableSites: [CMSSite], detailMap: [String: String]) {
        let sourceSites = availableSites.isEmpty ? CMSSite.all : availableSites
        let defaultSite = CMSSite.selectedDefaultSite

        // 默认源置顶，其余源保持原顺序
        var ordered: [CMSSite] = []
        if let first = sourceSites.first(where: { $0.id == defaultSite.id }) {
            ordered.append(first)
        }
        ordered.append(contentsOf: sourceSites.filter { $0.id != defaultSite.id })
        sites = ordered.isEmpty ? sourceSites : ordered

        selectedSite = sites.first ?? .defaultSite
        siteDetailMap = detailMap
        hasConfigured = true
    }

    private func makeSource(for site: CMSSite) -> MovieSourceProtocol {
        AppleCMSSource(site: site)
    }

    func loadDetail(path: String, site: CMSSite? = nil) async {
        let targetSite = site ?? selectedSite
        selectedSite = targetSite
        isLoading = true
        errorMessage = nil
        lastFetchError = nil

        let source = makeSource(for: targetSite)

        // 候选详情 id（按优先级）：detailMap 里该站点的精确 vod_id → 传入的 path。
        // 逐个尝试，选第一个「带分集」的详情；若都无分集，保留第一个成功的详情兜底展示。
        // 这样无论初次进入还是切换源，行为完全一致，不再依赖顺序或时序。
        var candidates: [String] = []
        if let id = siteDetailMap[targetSite.id], !id.isEmpty, !candidates.contains(id) {
            candidates.append(id)
        }
        if !path.isEmpty, !candidates.contains(path) {
            candidates.append(path)
        }

        var fallback: MovieDetail?
        for id in candidates {
            if let detail = await fetchDetail(on: source, path: id) {
                if detail.sources.contains(where: { !$0.episodes.isEmpty }) {
                    apply(detail)
                    isLoading = false
                    return
                }
                if fallback == nil { fallback = detail }
            }
        }

        // 标题搜索兜底：精确 id 未拿到分集（或该站点不在 detailMap 中）时，用原始标题重搜一次。
        if !currentMovieTitle.isEmpty,
           let matched = await bestMatch(in: source, for: currentMovieTitle),
           let detail = await fetchDetail(on: source, path: matched.id) {
            if detail.sources.contains(where: { !$0.episodes.isEmpty }) || fallback == nil {
                apply(detail)
                isLoading = false
                return
            }
        }

        // 所有候选都无分集：至少展示已拿到的详情；若连一次详情都没拿到，则给出错误提示（而非空白）。
        if let fallback {
            apply(fallback)
        } else if let error = lastFetchError {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func setInitialTitle(_ title: String) {
        if !title.isEmpty {
            currentMovieTitle = title
        }
    }

    private func bestMatch(in source: MovieSourceProtocol, for title: String) async -> MovieItem? {
        guard let results = try? await source.searchMovies(keyword: title), !results.isEmpty else {
            return nil
        }

        let target = normalizedTitle(title)

        // 完全匹配优先
        if let exact = results.first(where: { normalizedTitle($0.title) == target }) {
            return exact
        }

        // 否则选相似度最高的一条，并设置最低阈值
        var best: MovieItem?
        var bestScore = 0.0

        for item in results {
            let candidate = normalizedTitle(item.title)
            let score = similarityScore(between: target, and: candidate)
            if score > bestScore {
                bestScore = score
                best = item
            }
        }

        // 阈值 0.6，低于这个相似度宁可放弃匹配
        return bestScore >= 0.6 ? best : nil
    }

    private func normalizedTitle(_ title: String) -> String {
        let folded = title.folding(options: [.caseInsensitive, .widthInsensitive], locale: .current)
        let allowed = CharacterSet.alphanumerics
        let filtered = folded.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(filtered)).lowercased()
    }

    private func similarityScore(between a: String, and b: String) -> Double {
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

    /// 拉取详情（带一次重试，抵御首次请求冷启动失败）。
    private func fetchDetail(on source: MovieSourceProtocol, path: String) async -> MovieDetail? {
        for attempt in 0..<2 {
            do {
                return try await source.fetchMovieDetail(path: path)
            } catch {
                lastFetchError = error
                if attempt == 0 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        return nil
    }

    private func apply(_ detail: MovieDetail) {
        movieTitle = detail.title
        posterURL = detail.posterURL
        year = detail.year
        area = detail.area
        className = detail.className
        actors = detail.actors
        director = detail.director
        remarks = detail.remarks
        intro = detail.intro
        sources = detail.sources
        errorMessage = nil
        // 注意：不覆盖 currentMovieTitle。它应始终保留「用户想找的原始标题」（来自
        // setInitialTitle），供 bestMatch 兜底搜索；若被详情返回的同名错误标题覆盖，
        // 兜底搜索就会用错标题，永远匹配不到正确分集。
    }
}