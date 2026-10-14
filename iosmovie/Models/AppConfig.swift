import Foundation

/// 远程配置：从配置页（例如蓝奏云）解析反馈和公告接口地址。
/// 版本号和更新地址由公告接口 `/api/v1/notice` 返回。
final class AppConfig {
    static let shared = AppConfig()

    /// 配置页里解析出来的接口地址字段。
    struct Remote: Codable {
        var feedbackEndpoint: String?
        var noticeEndpoint: String?

        /// 任一字段有值即视为有效配置（配置页写错时不会清空缓存）。
        var hasAnyContent: Bool {
            [feedbackEndpoint, noticeEndpoint].contains { value in
                guard let value else { return false }
                return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private static let cacheKey = "remote_config_cache"
    private let queue = DispatchQueue(label: "com.iosmovie.app-config")
    private var remote: Remote?
    private var latestVersionValue: String?
    private var updateURLValue: URL?

    private init() {
        remote = Self.loadCache()
    }

    // MARK: - 对外取值

    /// 反馈发信接口（来自配置页；未拉到且无缓存时为 nil）
    var feedbackEndpoint: URL? {
        queue.sync { Self.validURL(remote?.feedbackEndpoint) }
    }

    /// 公告接口（来自配置页；未拉到且无缓存时为 nil）
    var noticeEndpoint: URL? {
        queue.sync { Self.validURL(remote?.noticeEndpoint) }
    }

    /// 公告接口返回的最新版本号（用于更新检查）
    var latestVersion: String? {
        queue.sync { latestVersionValue }
    }

    /// 公告接口返回的新版本下载 / 说明页地址
    var updateURL: URL? {
        queue.sync { updateURLValue }
    }

    /// 用公告接口返回的版本信息更新运行时状态
    func updateVersionInfo(latestVersion: String?, updateURL: String?) {
        let version = latestVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = Self.validURL(updateURL)

        queue.sync {
            latestVersionValue = (version?.isEmpty ?? true) ? nil : version
            updateURLValue = url
        }
    }

    /// App 标识：发信与公告接口共用（Info.plist 的 RemoteConfigAppID）
    var appID: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "RemoteConfigAppID") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "movie_ios" : value
    }

    /// 接口 token：发信与公告接口共用（Info.plist 的 RemoteConfigToken）
    var token: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "RemoteConfigToken") as? String else {
            return nil
        }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    // MARK: - 拉取远程配置

    /// 请求配置页并解析接口地址；失败时静默保留上次成功的缓存。
    func refresh() async {
        guard let url = Self.plistURL(forKey: "RemoteConfigURL") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return }
            let parsed = Self.parse(html: html)
            // 解析不到任何内容时保留现状，避免配置页写错导致 App 用不了
            guard parsed.hasAnyContent else { return }

            // 与现有配置合并：配置页里没写的标签继续沿用缓存值，不会被清空
            queue.sync {
                let merged = Remote(
                    feedbackEndpoint: parsed.feedbackEndpoint ?? self.remote?.feedbackEndpoint,
                    noticeEndpoint: parsed.noticeEndpoint ?? self.remote?.noticeEndpoint
                )
                self.remote = merged
                Self.saveCache(merged)
            }
        } catch {
            // 拉取失败：保留上次成功的缓存
        }
    }

    // MARK: - 解析

    /// 配置页格式：
    /// `[feedback]接口地址[/feedback]`
    /// `[notice]接口地址[/notice]`
    static func parse(html: String) -> Remote {
        Remote(
            feedbackEndpoint: extract(html, tag: "feedback"),
            noticeEndpoint: extract(html, tag: "notice")
        )
    }

    private static func extract(_ text: String, tag: String) -> String? {
        let startTag = "[\(tag)]"
        let endTag = "[/\(tag)]"
        guard let startRange = text.range(of: startTag),
              let endRange = text.range(of: endTag, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        let raw = String(text[startRange.upperBound..<endRange.lowerBound])
        let value = stripHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// 平台（例如蓝奏云）会把页面里的 URL 自动包成 `<span style="...">` 之类的标签，
    /// 这里去掉标签、还原常见 HTML 实体，保证拿到的是能直接使用的纯地址。
    private static func stripHTML(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        return result
    }

    // MARK: - 辅助

    private static func validURL(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "https" || scheme == "http"),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }

    private static func plistURL(forKey key: String) -> URL? {
        validURL(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }

    private static func loadCache() -> Remote? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Remote.self, from: data)
    }

    private static func saveCache(_ remote: Remote) {
        guard let data = try? JSONEncoder().encode(remote) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}

// MARK: - 版本更新检查

extension AppConfig {
    /// 当前 App 版本号（Info.plist 的 CFBundleShortVersionString）
    var currentVersion: String {
        let value = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "1.0" : value
    }

    /// 公告接口下发的版本号是否比本地新
    var hasUpdate: Bool {
        guard let latest = latestVersion else { return false }
        return Self.isVersion(latest, newerThan: currentVersion)
    }

    /// 按段比较版本号（1.10 比 1.9 新，字符串直接比较做不到这点）
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let left = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let right = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }
        return false
    }
}
