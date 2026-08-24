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

    private var siteDetailMap: [String: String] = [:]
    private var currentMovieTitle = ""

    func configure(availableSites: [CMSSite], detailMap: [String: String]) {
        sites = availableSites.isEmpty ? CMSSite.all : availableSites
        selectedSite = sites.first ?? .defaultSite
        siteDetailMap = detailMap
    }

    private func makeSource(for site: CMSSite) -> MovieSourceProtocol {
        AppleCMSSource(site: site)
    }

    func loadDetail(path: String, site: CMSSite? = nil) async {
        let targetSite = site ?? selectedSite
        let isSiteSwitch = site != nil && site?.id != selectedSite.id
        selectedSite = targetSite
        isLoading = true
        errorMessage = nil

        let source = makeSource(for: targetSite)

        if isSiteSwitch && !currentMovieTitle.isEmpty {
            if let matched = await bestMatch(in: source, for: currentMovieTitle) {
                await loadDetailDirect(on: source, path: matched.id)
                isLoading = false
                return
            }
        }

        let actualPath: String
        if !path.isEmpty && (path.hasPrefix("http") || !siteDetailMap.isEmpty) {
            actualPath = siteDetailMap[targetSite.id] ?? path
        } else {
            actualPath = path
        }

        await loadDetailDirect(on: source, path: actualPath)
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
        for j in 0...bChars.count { dp[j][0] = j }

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

    private func loadDetailDirect(on source: MovieSourceProtocol, path: String) async {
        do {
            let detail = try await source.fetchMovieDetail(path: path)
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
            currentMovieTitle = detail.title
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}