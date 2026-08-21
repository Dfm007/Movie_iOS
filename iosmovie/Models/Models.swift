import Foundation

struct MovieItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let type: String
    let year: String
    let rating: String
    let detailURL: String
    var posterURL: String?
}

struct PlaySource: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let format: String
    var episodes: [PlaySource] = []
}

struct MovieDetail {
    let movieId: String
    let title: String
    let posterURL: String?
    let sources: [PlaySource]
}

struct MovieCategory: Identifiable, Codable, Hashable {
    let id: Int
    let pid: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "type_id"
        case pid = "type_pid"
        case name = "type_name"
    }
}