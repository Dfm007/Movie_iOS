import Foundation

final class DDYSSource: MovieSourceProtocol {
    let sourceName = "低端影视"
    let baseURL = "https://ddys.io"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchHomeMovies() async throws -> [MovieItem] {
        guard let url = URL(string: baseURL + "/api/hot-movies") else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(HotMoviesResponse.self, from: data)
        return resp.data.map { item in
            MovieItem(id: String(item.id ?? 0), title: item.title, type: item.type ?? "", year: String(item.year ?? 0), rating: item.rating ?? "", detailURL: item.url ?? "")
        }
    }

    func searchMovies(keyword: String) async throws -> [MovieItem] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseURL + "/api/search-suggest?q=" + encoded) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
        return resp.data.map { item in
            MovieItem(id: item.slug ?? "", title: item.title, type: item.type ?? "", year: String(item.year ?? 0), rating: item.rating ?? "", detailURL: item.url ?? "")
        }
    }

    func fetchMovieDetail(path: String) async throws -> MovieDetail {
        let fullPath = path.hasPrefix("http") ? path : baseURL + path
        guard let url = URL(string: fullPath) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        let movieId = extractMovieId(from: html) ?? ""
        let title = extractTitle(from: html) ?? ""
        let sources = extractPlaySources(from: html)
        return MovieDetail(movieId: movieId, title: title, sources: sources)
    }

    private func extractMovieId(from html: String) -> String? {
        guard let range = html.range(of: "const movieId = ") else { return nil }
        var digits = ""
        var index = range.upperBound
        while index < html.endIndex, digits.count < 10 {
            let char = html[index]
            if char.isNumber { digits.append(char) }
            else if !digits.isEmpty { break }
            index = html.index(after: index)
        }
        return digits.isEmpty ? nil : digits
    }

    private func extractTitle(from html: String) -> String? {
        guard let range = html.range(of: "<title>") else { return nil }
        let start = range.upperBound
        guard let endRange = html.range(of: "</title>", range: start..<html.endIndex) else { return nil }
        return String(html[start..<endRange.lowerBound])
    }

    private func extractPlaySources(from html: String) -> [PlaySource] {
        var sources: [PlaySource] = []
        let pattern = #"switchSource(s*(d+)s*,s*'([^']+)'s*,s*'([^']+)'"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
            let matches = regex.matches(in: html, range: nsRange)
            for match in matches {
                guard let idRange = Range(match.range(at: 1), in: html),
                      let urlRange = Range(match.range(at: 2), in: html),
                      let formatRange = Range(match.range(at: 3), in: html) else { continue }
                let id = String(html[idRange])
                let rawURL = String(html[urlRange])
                let format = String(html[formatRange])
                let cleanURL = rawURL.replacingOccurrences(of: "\/", with: "/")
                sources.append(contentsOf: parseSource(id: id, rawURL: cleanURL, format: format))
            }
        }
        if sources.isEmpty {
            if let firstSourceURL = extractFirstSourceURL(from: html) {
                sources.append(contentsOf: parseSource(id: "1", rawURL: firstSourceURL, format: "m3u8"))
            }
        }
        return sources
    }

    private func parseSource(id: String, rawURL: String, format: String) -> [PlaySource] {
        if rawURL.contains("#") && rawURL.contains("$") {
            let parts = rawURL.components(separatedBy: "#")
            var episodes: [PlaySource] = []
            for (index, part) in parts.enumerated() {
                let segments = part.components(separatedBy: "$")
                if segments.count >= 2 {
                    let name = segments[0]
                    let url = segments[1]
                    episodes.append(PlaySource(id: "(id)-ep(index + 1)", name: name, url: url, format: format))
                }
            }
            let container = PlaySource(id: id, name: "源 (id)", url: "", format: format, episodes: episodes)
            return [container]
        } else {
            return [PlaySource(id: id, name: "源 (id)", url: rawURL, format: format)]
        }
    }

    private func extractFirstSourceURL(from html: String) -> String? {
        guard let range = html.range(of: "firstSource") else { return nil }
        let snippet = String(html[range.lowerBound...].prefix(1500))
        let pattern = #"urls*[:=]s*\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..<snippet.endIndex, in: snippet)),
              let urlRange = Range(match.range(at: 1), in: snippet) else { return nil }
        let rawURL = String(snippet[urlRange])
        return rawURL.replacingOccurrences(of: "\/", with: "/")
    }
}

private struct HotMoviesResponse: Codable { let data: [HotMovieItem] }
private struct HotMovieItem: Codable {
    let id: Int?
    let title: String
    let type: String?
    let year: Int?
    let rating: String?
    let url: String?
}
private struct SearchResponse: Codable { let data: [SearchItem] }
private struct SearchItem: Codable {
    let title: String
    let slug: String?
    let type: String?
    let year: Int?
    let rating: String?
    let url: String?
}
