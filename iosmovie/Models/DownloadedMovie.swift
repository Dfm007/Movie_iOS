import Foundation

struct DownloadedMovie: Identifiable, Codable {
    let id: String
    let title: String
    let episodeName: String
    let fileURL: String
    /// 真实内容体积；TS 为分片总和（不是 movie.m3u8 入口文件的大小）。
    /// 扫描目录重建或旧元数据自愈时会就地修正，故为 var。
    var fileSize: Int64
    let downloadDate: Date
    /// 所属下载目录名，删除/去重都依赖它
    var folderID: String
    /// "ts" 或 "mp4"
    var format: String
    /// 网络海报地址（下载时从详情页带过来，仅作兜底）
    var posterURL: String?
    /// 本地海报文件路径（下载时缓存，离线也能显示）
    var posterPath: String?

    init(
        id: String,
        title: String,
        episodeName: String,
        fileURL: String,
        fileSize: Int64,
        downloadDate: Date,
        folderID: String = "",
        format: String = "mp4",
        posterURL: String? = nil,
        posterPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.episodeName = episodeName
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.downloadDate = downloadDate
        self.folderID = folderID
        self.format = format
        self.posterURL = posterURL
        self.posterPath = posterPath
    }

    /// 兼容旧版元数据（没有 folderID / format / posterURL / posterPath 字段）
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
        posterURL = try container.decodeIfPresent(String.self, forKey: .posterURL)
        posterPath = try container.decodeIfPresent(String.self, forKey: .posterPath)
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
        case .failed:      return "下载失败"
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
    /// 网络海报地址
    var posterURL: String? = nil
    /// 本地海报路径（任务开始时就已缓存，供下载中卡片显示）
    var posterPath: String? = nil
    /// 实时速度（字节/秒），仅运行中有效，不持久化
    var speed: Double = 0
    /// 预计剩余秒数，仅运行中有效，不持久化
    var remainingSeconds: Double = 0
}

/// 创建下载任务的入参（替代裸元组，方便把海报一路带下来）
struct DownloadRequest {
    let title: String
    let episodeName: String
    let sourceURL: String
    let posterURL: String?
}
