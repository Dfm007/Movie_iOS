import Foundation

/// 单集的播放进度记录
struct PlaybackRecord: Codable {
    /// 上次播放位置（秒）
    var position: Double
    /// 总时长（秒）；本地 HLS 可能拿不到，为 0 时不做"看完"判断
    var duration: Double
    var updatedAt: Date
}

/// 已下载内容的续播进度存储。
///
/// 键必须用 `folderID`：`DownloadedMovie.id` 是每次启动/扫描时新生成的 UUID，
/// 重启后同一个文件会换 id，拿它当键会导致续播丢失。
final class PlaybackProgressStore {
    static let shared = PlaybackProgressStore()

    /// 短于该秒数视为"刚点开就退出"，不覆盖已有进度
    private let minimumPosition: Double = 5
    /// 观看比例超过该值视为看完，自动清除进度
    private let finishedRatio: Double = 0.95

    private let storageKey = "downloaded_playback_records"
    private var records: [String: PlaybackRecord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: PlaybackRecord].self, from: data) {
            records = decoded
        } else {
            records = [:]
        }
    }

    // MARK: - 读写

    func record(for folderID: String) -> PlaybackRecord? {
        guard !folderID.isEmpty else { return nil }
        return records[folderID]
    }

    /// 保存进度。已看完则清除；位置太短则保留原记录不动。
    func save(folderID: String, position: Double, duration: Double) {
        guard !folderID.isEmpty else { return }

        if duration > 0, position / duration >= finishedRatio {
            clear(folderID: folderID)
            return
        }
        guard position >= minimumPosition else { return }

        records[folderID] = PlaybackRecord(position: position, duration: duration, updatedAt: Date())
        persist()
    }

    func clear(folderID: String) {
        guard records.removeValue(forKey: folderID) != nil else { return }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - 展示

    /// 秒 → "12:34" / "1:02:03"
    static func displayTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
