import Foundation
import SwiftUI

/// 按剧名聚合后的已下载分组
struct DownloadGroup: Identifiable {
    /// 组 id = 剧名
    let id: String
    let title: String
    let episodes: [DownloadedMovie]
    let totalSize: Int64
    /// 组内最新一次下载时间，用于组间排序
    let latestDate: Date

    var episodeCount: Int { episodes.count }

    /// 同一部剧各集海报相同，取组内任意一张即可（有些旧条目没有海报）
    var posterPath: String? {
        episodes.first(where: { !($0.posterPath ?? "").isEmpty })?.posterPath
    }

    var posterURL: String? {
        episodes.first(where: { !($0.posterURL ?? "").isEmpty })?.posterURL
    }
}

@MainActor
final class DownloadsViewModel: ObservableObject {
    /// 用户手动折叠/展开过的组（组 id → 是否展开）；没记录过的组走默认策略
    @Published private var expansionOverrides: [String: Bool] = [:]

    // MARK: - 分组

    /// 按剧名分组：组间按最新下载时间倒序；组内按集名自然排序（第 2 集排在第 10 集前）
    func groups(from movies: [DownloadedMovie]) -> [DownloadGroup] {
        Dictionary(grouping: movies) { $0.title }
            .map { title, items in
                DownloadGroup(
                    id: title,
                    title: title,
                    episodes: items.sorted(by: Self.episodeOrder),
                    totalSize: items.reduce(0) { $0 + $1.fileSize },
                    latestDate: items.map(\.downloadDate).max() ?? Date.distantPast
                )
            }
            .sorted { $0.latestDate > $1.latestDate }
    }

    private static func episodeOrder(_ lhs: DownloadedMovie, _ rhs: DownloadedMovie) -> Bool {
        let order = lhs.episodeName.compare(
            rhs.episodeName,
            options: [.numeric, .caseInsensitive, .widthInsensitive]
        )
        if order == .orderedSame { return lhs.downloadDate < rhs.downloadDate }
        return order == .orderedAscending
    }

    // MARK: - 折叠状态

    /// 默认策略：只有一部剧时展开（省一次点击），多部时全部折叠
    func isExpanded(_ group: DownloadGroup, groupCount: Int) -> Bool {
        if let override = expansionOverrides[group.id] { return override }
        return groupCount == 1
    }

    func toggle(_ group: DownloadGroup, groupCount: Int) {
        expansionOverrides[group.id] = !isExpanded(group, groupCount: groupCount)
    }

    func expandAll(_ groups: [DownloadGroup]) {
        for group in groups { expansionOverrides[group.id] = true }
    }

    func collapseAll(_ groups: [DownloadGroup]) {
        for group in groups { expansionOverrides[group.id] = false }
    }

    /// 整组被删掉后清掉残留状态
    func forget(_ groupID: String) {
        expansionOverrides.removeValue(forKey: groupID)
    }
}
