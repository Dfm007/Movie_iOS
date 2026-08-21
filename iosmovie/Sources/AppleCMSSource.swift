import Foundation

final class AppleCMSSource: MovieSourceProtocol {
    let sourceName: String
    let baseURL: String

    private let session: URLSession

    init(site: CMSSite = .defaultSite) {
        sourceName = site.name
        baseURL = site.baseURL
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchHomeMovies() async throws -> [MovieItem] {
        try await fetchMovies(path: "\(baseURL)?ac=list")
    }

    func searchMovies(keyword: String) async throws -> [MovieItem] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw URLError(.badURL)
        }
        return try await fetchMovies(path: "\(baseURL)?ac=list&wd=\(encoded)")
    }

    func fetchMovieDetail(path: String) async throws -> MovieDetail {
        let detailPath = path.hasPrefix("http") ? path : "\(baseURL)?ac=detail&ids=\(path)"
        guard let url = URL(string: detailPath) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSearchResponse.self, from: data)

        guard let item = resp.list.first else { throw URLError(.cannotParseResponse) }

        let movieId = item.vod_id
        let title = item.vod_name
        let sources = parsePlaySources(from: item.vod_play_url, playFrom: item.vod_play_from)

        return MovieDetail(movieId: movieId, title: title, sources: sources)
    }

    func fetchCategories() async throws -> [MovieCategory] {
        let url = URL(string: "\(baseURL)?ac=list")!
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSCategoryResponse.self, from: data)
        return resp.class
    }

    func fetchMoviesByCategory(id: Int) async throws -> [MovieItem] {
        try await fetchMovies(path: "\(baseURL)?ac=list&t=\(id)")
    }

    private func fetchMovies(path: String) async throws -> [MovieItem] {
        guard let url = URL(string: path) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSearchResponse.self, from: data)
        let movies = resp.list.map { item in
            MovieItem(
                id: item.vod_id,
                title: item.vod_name,
                type: item.type_name ?? "",
                year: item.vod_year ?? "",
                rating: item.vod_score ?? "",
                detailURL: item.vod_id,
                posterURL: item.vod_pic
            )
        }
        return await fillPosters(for: movies)
    }

    private func fillPosters(for movies: [MovieItem]) async -> [MovieItem] {
        var result = movies
        let needPoster = movies.filter { $0.posterURL?.isEmpty ?? true }
        guard !needPoster.isEmpty else { return result }

        let semaphore = AsyncSemaphore(limit: 5)
        await withTaskGroup(of: (String, String?).self) { group in
            for movie in needPoster {
                group.addTask { [weak self] in
                    guard let self = self else { return (movie.id, nil) }
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }
                    let poster = try? await self.fetchPoster(movieId: movie.id)
                    return (movie.id, poster)
                }
            }

            var posterMap: [String: String] = [:]
            for await (id, poster) in group {
                if let poster = poster {
                    posterMap[id] = poster
                }
            }

            for index in result.indices {
                if let poster = posterMap[result[index].id] {
                    result[index].posterURL = poster
                }
            }
        }
        return result
    }

    private func fetchPoster(movieId: String) async throws -> String? {
        guard let url = URL(string: "\(baseURL)?ac=detail&ids=\(movieId)") else { return nil }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSearchResponse.self, from: data)
        return resp.list.first?.vod_pic
    }

    private func parsePlaySources(from playURL: String?, playFrom: String?) -> [PlaySource] {
        guard let playURL = playURL, !playURL.isEmpty else { return [] }

        let sourceNames = playFrom?.components(separatedBy: "$$$") ?? []
        let sourceGroups = playURL.components(separatedBy: "$$$")

        var results: [PlaySource] = []

        for (index, group) in sourceGroups.enumerated() {
            let sourceName = index < sourceNames.count ? sourceNames[index] : "源 \(index + 1)"
            let episodeParts = group.components(separatedBy: "#")

            if episodeParts.count > 1 {
                var episodes: [PlaySource] = []
                for (epIndex, part) in episodeParts.enumerated() {
                    let segments = part.components(separatedBy: "$")
                    if segments.count >= 2 {
                        episodes.append(
                            PlaySource(
                                id: "\(index)-ep\(epIndex + 1)",
                                name: segments[0],
                                url: segments[1],
                                format: "m3u8"
                            )
                        )
                    }
                }
                results.append(
                    PlaySource(
                        id: "\(index)",
                        name: sourceName,
                        url: "",
                        format: "m3u8",
                        episodes: episodes
                    )
                )
            } else if let singleURL = group.components(separatedBy: "$").last, !singleURL.isEmpty {
                results.append(
                    PlaySource(
                        id: "\(index)",
                        name: sourceName,
                        url: singleURL,
                        format: "m3u8"
                    )
                )
            }
        }

        return results
    }
}


actor AsyncSemaphore {
    private var count: Int

    init(limit: Int) {
        self.count = limit
    }

    func wait() async {
        while count <= 0 {
            await Task.yield()
        }
        count -= 1
    }

    func signal() {
        count += 1
    }
}
private struct CMSSearchResponse: Codable {
    let list: [CMSMovieItem]
}

private struct CMSMovieItem: Codable {
    let vod_id: String
    let vod_name: String
    let type_name: String?
    let vod_year: String?
    let vod_score: String?
    let vod_pic: String?
    let vod_play_url: String?
    let vod_play_from: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        vod_name = try container.decode(String.self, forKey: .vod_name)
        type_name = try container.decodeIfPresent(String.self, forKey: .type_name)
        vod_year = try container.decodeIfPresent(String.self, forKey: .vod_year)
        vod_score = try container.decodeIfPresent(String.self, forKey: .vod_score)
        vod_pic = try container.decodeIfPresent(String.self, forKey: .vod_pic)
        vod_play_url = try container.decodeIfPresent(String.self, forKey: .vod_play_url)
        vod_play_from = try container.decodeIfPresent(String.self, forKey: .vod_play_from)
        if let str = try? container.decode(String.self, forKey: .vod_id) {
            vod_id = str
        } else {
            vod_id = String(try container.decode(Int.self, forKey: .vod_id))
        }
    }

    enum CodingKeys: String, CodingKey {
        case vod_id, vod_name, type_name, vod_year, vod_score, vod_pic, vod_play_url, vod_play_from
    }
}

private struct CMSCategoryResponse: Codable {
    let `class`: [MovieCategory]
}
