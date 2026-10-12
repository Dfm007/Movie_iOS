import Foundation

struct DownloadedMovie: Identifiable, Codable {
    let id: String
    let title: String
    let episodeName: String
    let fileURL: String
    let fileSize: Int64
    let downloadDate: Date
    /// 所属下载目录名，删除/去重都依赖它
    var folderID: String
    /// "ts" 或 "mp4"
    var format: String

    init(
        id: String,
        title: String,
        episodeName: String,
        fileURL: String,
        fileSize: Int64,
        downloadDate: Date,
        folderID: String = "",
        format: String = "mp4"
    ) {
        self.id = id
        self.title = title
        self.episodeName = episodeName
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.downloadDate = downloadDate
        self.folderID = folderID
        self.format = format
    }

    /// 兼容旧版元数据（没有 folderID / format 字段）
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        episodeName = try container.decode(String.self, forKey: .episodeName)
        fileURL = try container.decode(String.self, forKey: .fileURL)
        fileSize = try container.decode(Int64.self, forKey: .fileSize)
        downloadDate = try container.decode(Date.self, forKey: .downloadDate)
        folderID = try container.decodeIfPresent(String.self, forKey: .folderID) ?? ""
        format = try container.decodeIfPresent(String.self, forKey: .format) ?? "mp4"
    }
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
    var folderID: String
    var progress: Double
    var status: DownloadStatus
    var completedSegments: Int = 0
    var totalSegments: Int = 0
    var totalBytes: Int64 = 0
    var downloadedBytes: Int64 = 0
    var errorMessage: String? = nil
}
