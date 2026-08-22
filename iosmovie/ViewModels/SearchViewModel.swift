import Foundation

struct SourceDetail: Identifiable, Hashable {
    let id: String
    let site: CMSSite
    let detailURL: String
}

struct SearchResultItem: Identifiable, Hashable {
    let id: String
    let title: String
    let year: String
    let type: String
    let rating: String
    let posterURL: String?
    var sourceDetails: [SourceDetail]
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var results: [SearchResultItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let sites: [CMSSite] = CMSSite.all
    private var lastKeyword: String?

    func search(keyword: String) async {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if lastKeyword == text && !results.isEmpty { return }
        lastKeyword = text

        isLoading = true
        errorMessage = nil

        var allMovies: [(site: CMSSite, movie: MovieItem)] = []

        await withTaskGroup(of: (CMSSite, [MovieItem])?.self) { group in
            for site in sites {
                group.addTask {
                    let source = AppleCMSSource(site: site)
                    do {
                        let movies = try await source.searchMovies(keyword: text)
                        return (site, movies)
                    } catch {
                        return nil
                    }
                }
            }
            for await case let (site, movies)? in group {
                allMovies.append(contentsOf: movies.map { (site, $0) })
            }
        }

        results = Self.merge(allMovies)
        isLoading = false

        if results.isEmpty {
            errorMessage = "未找到相关影视"
        }
    }

    private static func merge(_ items: [(site: CMSSite, movie: MovieItem)]) -> [SearchResultItem] {
        var dict: [String: SearchResultItem] = [:]

        for item in items {
            let normalizedTitle = normalize(item.movie.title)
            let sourceDetail = SourceDetail(
                id: "\(item.site.id)_\(item.movie.id)",
                site: item.site,
                detailURL: item.movie.id
            )

            if var existing = dict[normalizedTitle] {
                if !existing.sourceDetails.contains(where: { $0.site.id == item.site.id }) {
                    existing.sourceDetails.append(sourceDetail)
                    dict[normalizedTitle] = existing
                }
            } else {
                dict[normalizedTitle] = SearchResultItem(
                    id: normalizedTitle,
                    title: item.movie.title,
                    year: item.movie.year,
                    type: item.movie.type,
                    rating: item.movie.rating,
                    posterURL: item.movie.posterURL,
                    sourceDetails: [sourceDetail]
                )
            }
        }

        return dict.values.sorted { $0.title < $1.title }
    }

    private static func normalize(_ text: String) -> String {
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
}
