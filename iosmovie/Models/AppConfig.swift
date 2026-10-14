import Foundation

/// 远程配置：从一个「配置页」（例如蓝奏云分享页）里解析出真实的接口地址。
///
/// 目的：换服务器时只改配置页内容，App 不需要重新构建。
/// 取值优先级：远程配置 → 上次成功的缓存 → Info.plist 默认值。
final class AppConfig {
    static let shared = AppConfig()

    /// 配置页里解析出来的字段
    struct Remote: Codable {
        var feedbackEndpoint: String?
        var noticeEndpoint: String?

        var hasAnyEndpoint: Bool {
            let feedback = feedbackEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let notice = noticeEndpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !feedback.isEmpty || !notice.isEmpty
        }
    }

    private static let cacheKey = "remote_config_cache"
    private let queue = DispatchQueue(label: "com.iosmovie.app-config")
    private var remote: Remote?

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

    // MARK: - 拉取远程配置

    /// 请求配置页并解析；失败时静默保留上次成功的缓存
    func refresh() async {
        guard let url = Self.plistURL(forKey: "RemoteConfigURL") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) else { return }
            let parsed = Self.parse(html: html)
            // 解析不到任何接口时保留现状，避免配置页写错导致 App 用不了
            guard parsed.hasAnyEndpoint else { return }

            queue.sync { self.remote = parsed }
            Self.saveCache(parsed)
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
