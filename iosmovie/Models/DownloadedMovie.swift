import Foundation

struct DownloadedMovie: Identifiable, Codable {
    let id: String
    let title: String
    let episodeName: String
    let fileURL: String
    let fileSize: Int64
    let downloadDate: Date
}