import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var movies: [MovieItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private let source: MovieSourceProtocol

    init(source: MovieSourceProtocol = DDYSSource()) {
        self.source = source
    }

    func loadHome() async {
        isLoading = true
        errorMessage = nil
        do {
            movies = try await source.fetchHomeMovies()
        } catch {
            errorMessage = error.localizedDescription
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
