import Foundation

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var movieTitle = ""
    @Published var sources: [PlaySource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let source: MovieSourceProtocol

    init(source: MovieSourceProtocol = AppleCMSSource()) {
        self.source = source
    }

    func loadDetail(path: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let detail = try await source.fetchMovieDetail(path: path)
            movieTitle = detail.title
            sources = detail.sources
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}