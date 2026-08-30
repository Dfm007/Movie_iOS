import Foundation

struct DownloadedMovie: Identifiable, Codable {
    let id: String
    let title: String
    let episodeName: String
    let fileURL: String
    let fileSize: Int64
    let downloadDate: Date
}

enum DownloadStatus {
    case downloading
    case paused
    case completed
    case failed
}

struct DownloadTask: Identifiable {
    let id: String
    let title: String
    let episodeName: String
    let sourceURL: String
    var progress: Double
    var status: DownloadStatus
}