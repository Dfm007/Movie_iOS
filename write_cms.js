const fs = require('fs');
const p = 'C:/Users/DUAN/Desktop/iosmovie/iosmovie/Sources/AppleCMSSource.swift';

const content = String.raw`import Foundation

final class AppleCMSSource: MovieSourceProtocol {
    let sourceName: String
    let baseURL: String

    private let session: URLSession

    init(name: String = "苹果CMS", baseURL: String = "https://cj.lziapi.com/api.php/provide/vod/from/lzm3u8") {
        self.sourceName = name
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*"
        ]
        self.session = URLSession(configuration: config)
    }

    func fetchHomeMovies() async throws -> [MovieItem] {
        guard let url = URL(string: baseURL + "?ac=list") else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSResponse.self, from: data)
        return resp.list.map { item in
            MovieItem(
                id: String(item.vod_id),
                title: item.vod_name,
                type: item.type_name,
                year: "",
                rating: "",
                detailURL: String(item.vod_id),
                posterURL: item.vod_pic?.replacingOccurrences(of: "\\/", with: "/")
            )
        }
    }

    func searchMovies(keyword: String) async throws -> [MovieItem] {
        guard let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: baseURL + "?ac=list&wd=" + encoded) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSResponse.self, from: data)
        return resp.list.map { item in
            MovieItem(
                id: String(item.vod_id),
                title: item.vod_name,
                type: item.type_name,
                year: "",
                rating: "",
                detailURL: String(item.vod_id),
                posterURL: item.vod_pic?.replacingOccurrences(of: "\\/", with: "/")
            )
        }
    }

    func fetchMovieDetail(path: String) async throws -> MovieDetail {
        guard let url = URL(string: baseURL + "?ac=detail&ids=" + path) else { throw URLError(.badURL) }
        let (data, _) = try await session.data(from: url)
        let resp = try JSONDecoder().decode(CMSSResponse.self, from: data)
        guard let detail = resp.list.first else { throw URLError(.cannotDecodeContentData) }

        let sources = parsePlaySources(from: detail.vod_play_url)
        return MovieDetail(movieId: String(detail.vod_id), title: detail.vod_name, sources: sources)
    }

    private func parsePlaySources(from raw: String?) -> [PlaySource] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let clean = raw.replacingOccurrences(of: "\\/", with: "/")
        if clean.contains("#") && clean.contains("$") {
            let parts = clean.components(separatedBy: "#")
            var episodes: [PlaySource] = []
            for (index, part) in parts.enumerated() {
                let segments = part.components(separatedBy: "$")
                if segments.count >= 2 {
                    episodes.append(PlaySource(id: "ep-\(index + 1)", name: segments[0], url: segments[1], format: "m3u8"))
                }
            }
            return [PlaySource(id: "1", name: "源 1", url: "", format: "m3u8", episodes: episodes)]
        } else {
            return [PlaySource(id: "1", name: "源 1", url: clean, format: "m3u8")]
        }
    }
}

private struct CMSSResponse: Codable {
    let code: Int
    let msg: String
    let list: [CMSItem]
}

private struct CMSItem: Codable {
    let vod_id: Int
    let vod_name: String
    let type_name: String
    let vod_pic: String?
    let vod_play_url: String?

    enum CodingKeys: String, CodingKey {
        case vod_id
        case vod_name
        case type_name
        case vod_pic
        case vod_play_url
    }
}
`;

fs.writeFileSync(p, content, 'utf8');
console.log('written');
