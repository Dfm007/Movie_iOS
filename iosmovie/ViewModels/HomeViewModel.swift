import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var movies: [MovieItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

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
}
