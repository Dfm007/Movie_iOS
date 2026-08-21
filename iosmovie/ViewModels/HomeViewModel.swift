import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var movies: [MovieItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private let source: MovieSourceProtocol

    init(source: MovieSourceProtocol = AppleCMSSource()) {
        self.source = source
    }

    private let homeCacheKey = "home_movies"

    func loadHome() async {
        if let cached = CacheManager.shared.loadMovies(forKey: homeCacheKey), !cached.isEmpty {
            movies = cached
        } else {
            isLoading = true
        }
        errorMessage = nil
        do {
            let fresh = try await source.fetchHomeMovies()
            movies = fresh
            CacheManager.shared.saveMovies(fresh, forKey: homeCacheKey)
        } catch {
            if movies.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func search() async {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            await loadHome()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            movies = try await source.searchMovies(keyword: keyword)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
