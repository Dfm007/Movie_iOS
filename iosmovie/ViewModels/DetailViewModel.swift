import Foundation

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var movieTitle = ""
    @Published var sources: [PlaySource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSite: CMSSite = .defaultSite

    let sites: [CMSSite] = CMSSite.all

    private func makeSource(for site: CMSSite) -> MovieSourceProtocol {
        AppleCMSSource(site: site)
    }

    func loadDetail(path: String, site: CMSSite? = nil) async {
        let targetSite = site ?? selectedSite
        selectedSite = targetSite
        isLoading = true
        errorMessage = nil
        do {
            let source = makeSource(for: targetSite)
            let detail = try await source.fetchMovieDetail(path: path)
            movieTitle = detail.title
            sources = detail.sources
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}