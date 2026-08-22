import Foundation

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var movieTitle = ""
    @Published var posterURL: String?
    @Published var year = ""
    @Published var area = ""
    @Published var className = ""
    @Published var actors = ""
    @Published var director = ""
    @Published var remarks = ""
    @Published var intro = ""
    @Published var sources: [PlaySource] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSite: CMSSite = .defaultSite

    var sites: [CMSSite] = CMSSite.all

    private var siteDetailMap: [String: String] = [:]

    func configure(availableSites: [CMSSite], detailMap: [String: String]) {
        sites = availableSites.isEmpty ? CMSSite.all : availableSites
        selectedSite = sites.first ?? .defaultSite
        siteDetailMap = detailMap
    }

    private func makeSource(for site: CMSSite) -> MovieSourceProtocol {
        AppleCMSSource(site: site)
    }

    func loadDetail(path: String, site: CMSSite? = nil) async {
        let targetSite = site ?? selectedSite
        selectedSite = targetSite
        isLoading = true
        errorMessage = nil

        let source = makeSource(for: targetSite)
        let actualPath: String
        if !path.isEmpty && (path.hasPrefix("http") || !siteDetailMap.isEmpty) {
            actualPath = siteDetailMap[targetSite.id] ?? path
        } else {
            actualPath = path
        }

        await loadDetailDirect(on: source, path: actualPath)
        isLoading = false
    }

    private func loadDetailDirect(on source: MovieSourceProtocol, path: String) async {
        do {
            let detail = try await source.fetchMovieDetail(path: path)
            movieTitle = detail.title
            posterURL = detail.posterURL
            year = detail.year
            area = detail.area
            className = detail.className
            actors = detail.actors
            director = detail.director
            remarks = detail.remarks
            intro = detail.intro
            sources = detail.sources
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
