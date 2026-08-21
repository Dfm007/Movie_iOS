import Foundation

struct MovieItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let type: String
    let year: String
    let rating: String
    let detailURL: String
}

struct PlaySource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let format: String
}

struct MovieDetail {
    let movieId: String
    let title: String
    let sources: [PlaySource]
}
