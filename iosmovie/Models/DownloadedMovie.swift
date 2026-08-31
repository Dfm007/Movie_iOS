import Foundation

struct DownloadedMovie: Identifiable, Codable {
    let id: String
    let title: String
    let episodeName: String
    let fileURL: String
    let fileSize: Int64
    let downloadDate: Date
}

enum DownloadStatus: String, Codable, Equatable {
    case downloading
    case paused
    case completed
    case failed

    var displayText: String {
        switch self {
        case .downloading: return "下载中"
        case .paused:      return "已暂停"
        case .completed:   return "已完成"
        case .failed:      return "失败"
        }
    }
}

struct DownloadTask: Identifiable, Equatable {
    let id: String
    let title: String
    let episodeName: String
    let sourceURL: String
    var progress: Double
    var status: DownloadStatus
    var completedSegments: Int = 0
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
}