import Foundation

protocol MovieSourceProtocol {
    var sourceName: String { get }
    var baseURL: String { get }

    func fetchHomeMovies() async throws -> [MovieItem]
    func searchMovies(keyword: String) async throws -> [MovieItem]
    func fetchMovieDetail(path: String) async throws -> MovieDetail
}
