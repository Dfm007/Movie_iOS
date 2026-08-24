import Foundation
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var movies: [MovieItem] = []
    @Published var categories: [MovieCategory] = []
    @Published var selectedCategoryID: Int? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""

    private var source: MovieSourceProtocol
    private var sourceID: String
    private var homeCacheKey: String
    private var categoryCacheKey: String

    var currentSite: CMSSite {
        CMSSite.all.first(where: { $0.id == sourceID }) ?? CMSSite.selectedDefaultSite
    }

    init() {
        let site = CMSSite.selectedDefaultSite
        self.source = AppleCMSSource(site: site)
        self.sourceID = site.id
        self.homeCacheKey = "home_movies_\(site.id)"
        self.categoryCacheKey = "movie_categories_\(site.id)"
    }

    func loadInitial() async {
        await loadCategories()
        await loadHome()
    }

    func refreshDefaultSourceIfNeeded() async {
        let current = CMSSite.selectedDefaultSite
        guard current.id != sourceID else { return }
        await updateDefaultSource(to: current)
    }

    func updateDefaultSource(to site: CMSSite) async {
        guard site.id != sourceID else { return }

        CacheManager.shared.removeMovies(forKey: homeCacheKey)
        CacheManager.shared.removeCategories(forKey: categoryCacheKey)

        source = AppleCMSSource(site: site)
        sourceID = site.id
        homeCacheKey = "home_movies_\(site.id)"
        categoryCacheKey = "movie_categories_\(site.id)"

        selectedCategoryID = nil
        movies = []
        categories = []
        isLoading = true
        errorMessage = nil

        await loadCategories()
        await loadHome()

        isLoading = false
    }

    func loadCategories() async {
        if let cached = CacheManager.shared.loadCategories(forKey: categoryCacheKey), !cached.isEmpty {
            categories = cached
        }
        do {
            let fresh = try await source.fetchCategories()
            categories = fresh
            CacheManager.shared.saveCategories(fresh, forKey: categoryCacheKey)
        } catch {
            if categories.isEmpty {
                categories = [MovieCategory(id: 1, pid: 0, name: "电影片")]
            }
        }
    }

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

    func selectCategory(_ category: MovieCategory) async {
        selectedCategoryID = category.id
        isLoading = true
        errorMessage = nil
        do {
            let fresh = try await source.fetchMoviesByCategory(id: category.id)
            movies = fresh
            let key = categoryCacheKey(for: category.id)
            CacheManager.shared.saveMovies(fresh, forKey: key)
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
            if let selectedID = selectedCategoryID,
               let category = categories.first(where: { $0.id == selectedID }) {
                await selectCategory(category)
            } else {
                await loadHome()
            }
            return
        }
        selectedCategoryID = nil
        isLoading = true
        errorMessage = nil
        do {
            movies = try await source.searchMovies(keyword: keyword)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func categoryCacheKey(for id: Int) -> String {
        "\(categoryCacheKey)_\(id)"
    }
}