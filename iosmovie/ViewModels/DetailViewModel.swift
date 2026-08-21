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

        let source = makeSource(for: targetSite)

        if site != nil {
            await loadDetailBySearch(on: source, site: targetSite)
        } else {
            await loadDetailDirect(on: source, path: path)
        }

        isLoading = false
    }

    private func loadDetailDirect(on source: MovieSourceProtocol, path: String) async {
        do {
            let detail = try await source.fetchMovieDetail(path: path)
            movieTitle = detail.title
            sources = detail.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDetailBySearch(on source: MovieSourceProtocol, site: CMSSite) async {
        guard !movieTitle.isEmpty else {
            sources = []
            errorMessage = "无法搜索，缺少影视标题"
            return
        }
        do {
            let results = try await source.searchMovies(keyword: movieTitle)
            guard let matched = results.first(where: { $0.title == movieTitle }) ?? results.first else {
                sources = []
                errorMessage = "该站无此资源"
                return
            }
            let detail = try await source.fetchMovieDetail(path: matched.id)
            movieTitle = detail.title
            sources = detail.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}