import Foundation

// MARK: - 请求头

enum MovieRequestHeaders {
    /// 与 AppleCMSSource 保持一致，采集站普遍校验 UA
    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    /// 分片 CDN 常校验 Referer，取播放列表所在站点 origin
    static func headers(for url: URL) -> [String: String] {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.path = "/"
        comps?.query = nil
        comps?.fragment = nil
        let referer = comps?.url?.absoluteString ?? url.absoluteString
        return [
            "User-Agent": userAgent,
            "Referer": referer,
            "Accept": "*/*"
        ]
    }
}

// MARK: - 错误

enum M3U8Error: Error, LocalizedError {
    case fetchFailed(String)
    case notAPlaylist
    case emptySegments
    case tooManyRedirects
    case invalidURI

    var errorDescription: String? {
        switch self {
        case .fetchFailed(let message): return "获取播放列表失败：\(message)"
        case .notAPlaylist: return "不是有效的 m3u8 播放列表"
        case .emptySegments: return "播放列表中没有视频分片"
        case .tooManyRedirects: return "m3u8 嵌套层级过深"
        case .invalidURI: return "播放列表中的地址无效"
        }
    }
}

// MARK: - 模型

/// 单个媒体分片；加密信息按分片绑定，支持滚动密钥
struct M3U8Segment {
    let index: Int
    let url: URL
    let duration: Double
    /// AES-128 密钥地址（已解析为绝对地址）；nil = 明文
    let keyURL: String?
    /// 显式 IV；nil 时按规范使用分片序号
    let iv: [UInt8]?
    let byteRangeLength: Int64?
    let byteRangeOffset: Int64?
    /// 播放列表序号（#EXT-X-MEDIA-SEQUENCE + index），用于计算缺省 IV
    let sequenceNumber: Int
}

/// fMP4 初始化段（#EXT-X-MAP）
struct M3U8InitSegment {
    let url: URL
    let keyURL: String?
    let iv: [UInt8]?
    let byteRangeLength: Int64?
    let byteRangeOffset: Int64?
}

struct M3U8Playlist {
    let segments: [M3U8Segment]
    let initSegment: M3U8InitSegment?
    /// true = fragmented MP4（存在 #EXT-X-MAP），合并产物应为 .mp4
    let isFragmentedMP4: Bool
    let targetDuration: Double
}

// MARK: - 网络获取

protocol M3U8Fetching {
    func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse)
}

struct M3U8HTTPFetcher: M3U8Fetching {
    let session: URLSession

    func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (field, value) in MovieRequestHeaders.headers(for: url) {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw M3U8Error.fetchFailed("响应格式不正确")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw M3U8Error.fetchFailed("HTTP \(http.statusCode)")
        }
        return (data, http)
    }
}

// MARK: - 解析器

enum M3U8Parser {

    /// 递归解析：自动下钻多码率主列表，返回最终 media playlist
    static func resolve(from url: URL, depth: Int = 0, fetcher: M3U8Fetching) async throws -> M3U8Playlist {
        guard depth < 5 else { throw M3U8Error.tooManyRedirects }
        let (data, _) = try await fetcher.fetch(url)
        guard let text = String(data: data, encoding: .utf8) else { throw M3U8Error.notAPlaylist }
        let lines = Self.lines(of: text)

        if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF:") }) {
            guard let variantURL = Self.bestVariantURL(from: lines, baseURL: url) else {
                throw M3U8Error.notAPlaylist
            }
            return try await resolve(from: variantURL, depth: depth + 1, fetcher: fetcher)
        }
        return try Self.parse(text: text, baseURL: url)
    }

    /// 解析 media playlist
    static func parse(text: String, baseURL: URL) throws -> M3U8Playlist {
        let lines = Self.lines(of: text)

        var segments: [M3U8Segment] = []
        var initSegment: M3U8InitSegment?
        var isFragmentedMP4 = false
        var targetDuration = 0.0
        var mediaSequence = 0

        // 跟随 #EXT-X-KEY 切换的加密上下文
        var keyMethod = "NONE"
        var keyURL: String?
        var keyIV: [UInt8]?

        var pendingDuration = 0.0
        var pendingLength: Int64?
        var pendingOffset: Int64?
        var byteRangeCursor: Int64 = 0
        var mapCursor: Int64 = 0

        var mapURI: String?
        var mapLength: Int64?
        var mapOffset: Int64?

        for line in lines {
            if line.hasPrefix("#") {
                if line.hasPrefix("#EXTINF:") {
                    let value = String(line.dropFirst("#EXTINF:".count))
                    pendingDuration = Double(value.split(separator: ",").first.map(String.init) ?? "") ?? 0
                } else if line.hasPrefix("#EXT-X-TARGETDURATION:") {
                    let value = String(line.dropFirst("#EXT-X-TARGETDURATION:".count))
                    targetDuration = Double(value.trimmingCharacters(in: .whitespaces)) ?? targetDuration
                } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                    let value = String(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count))
                    mediaSequence = Int(value.trimmingCharacters(in: .whitespaces)) ?? 0
                } else if line.hasPrefix("#EXT-X-MAP:") {
                    let attrs = Self.attributes(from: line)
                    mapURI = attrs["URI"]
                    let (length, offset) = Self.byteRange(attrs["BYTERANGE"], cursor: &mapCursor)
                    mapLength = length
                    mapOffset = offset
                    isFragmentedMP4 = true
                } else if line.hasPrefix("#EXT-X-KEY:") {
                    let attrs = Self.attributes(from: line)
                    let method = (attrs["METHOD"] ?? "NONE").uppercased()
                    if method == "NONE" {
                        keyMethod = "NONE"
                        keyURL = nil
                        keyIV = nil
                    } else if method == "AES-128" {
                        // 密钥地址解析失败必须报错，否则会把密文当明文写出
                        guard let resolvedKey = Self.url(from: attrs["URI"] ?? "", baseURL: baseURL) else {
                            throw M3U8Error.invalidURI
                        }
                        keyMethod = method
                        keyURL = resolvedKey.absoluteString
                        keyIV = Self.iv(from: attrs["IV"])
                    } else {
                        throw M3U8Error.fetchFailed("不支持的加密方式：\(method)")
                    }
                } else if line.hasPrefix("#EXT-X-BYTERANGE:") {
                    let value = String(line.dropFirst("#EXT-X-BYTERANGE:".count))
                    let (length, offset) = Self.byteRange(value, cursor: &byteRangeCursor)
                    pendingLength = length
                    pendingOffset = offset
                }
                continue
            }

            guard let url = Self.url(from: line, baseURL: baseURL) else { continue }

            // fMP4 初始化段只记录一次
            if let uri = mapURI, initSegment == nil {
                initSegment = M3U8InitSegment(
                    url: Self.url(from: uri, baseURL: baseURL) ?? url,
                    keyURL: keyURL,
                    iv: keyIV,
                    byteRangeLength: mapLength,
                    byteRangeOffset: mapOffset
                )
            }

            segments.append(M3U8Segment(
                index: segments.count,
                url: url,
                duration: pendingDuration,
                keyURL: keyMethod == "NONE" ? nil : keyURL,
                iv: keyIV,
                byteRangeLength: pendingLength,
                byteRangeOffset: pendingOffset,
                sequenceNumber: mediaSequence + segments.count
            ))

            pendingDuration = 0
            pendingLength = nil
            pendingOffset = nil
        }

        guard !segments.isEmpty else { throw M3U8Error.emptySegments }
        return M3U8Playlist(
            segments: segments,
            initSegment: initSegment,
            isFragmentedMP4: isFragmentedMP4,
            targetDuration: targetDuration
        )
    }

    /// 缺省 IV：分片序号的 128 位大端表示
    static func defaultIV(for sequenceNumber: Int) -> [UInt8] {
        var bytes = Array(repeating: UInt8(0), count: 16)
        var value = UInt64(max(sequenceNumber, 0))
        var index = 15
        while value > 0 && index >= 0 {
            bytes[index] = UInt8(value & 0xFF)
            value >>= 8
            index -= 1
        }
        return bytes
    }

    // MARK: - 主列表选流

    private static func bestVariantURL(from lines: [String], baseURL: URL) -> URL? {
        struct Variant {
            let bandwidth: Int
            let width: Int
            let url: URL
        }
        var variants: [Variant] = []
        var bandwidth = 0
        var width = 0
        var sawStreamInf = false

        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attrs = Self.attributes(from: line)
                bandwidth = Int(attrs["BANDWIDTH"] ?? "") ?? 0
                let resolution = attrs["RESOLUTION"] ?? ""
                width = Int(resolution.split(separator: "x").first.map(String.init) ?? "") ?? 0
                sawStreamInf = true
                continue
            }
            guard sawStreamInf, !line.hasPrefix("#") else { continue }
            sawStreamInf = false
            if let url = Self.url(from: line, baseURL: baseURL) {
                variants.append(Variant(bandwidth: bandwidth, width: width, url: url))
            }
        }

        // 优先高分辨率，其次高码率
        return variants.max { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width < rhs.width }
            return lhs.bandwidth < rhs.bandwidth
        }?.url
    }

    // MARK: - 行与属性解析

    static func lines(of text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 解析 `KEY=VALUE,KEY="VALUE, VALUE"` 形式属性
    static func attributes(from line: String) -> [String: String] {
        guard let colon = line.firstIndex(of: ":") else { return [:] }
        let body = line[line.index(after: colon)...]

        var result: [String: String] = [:]
        var key = ""
        var value = ""
        var inQuotes = false
        var readingKey = true

        for character in body {
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if !inQuotes && character == "=" {
                readingKey = false
                continue
            }
            if !inQuotes && character == "," {
                let trimmedKey = key.trimmingCharacters(in: .whitespaces)
                if !trimmedKey.isEmpty {
                    result[trimmedKey] = value.trimmingCharacters(in: .whitespaces)
                }
                key = ""
                value = ""
                readingKey = true
                continue
            }
            if readingKey {
                key.append(character)
            } else {
                value.append(character)
            }
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespaces)
        if !trimmedKey.isEmpty {
            result[trimmedKey] = value.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// URI 解析：绝对地址直通，其余基于播放列表地址解析
    static func url(from uri: String, baseURL: URL) -> URL? {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
                ?? URL(string: trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)
        }
        if trimmed.hasPrefix("//") {
            let scheme = baseURL.scheme ?? "http"
            return URL(string: "\(scheme):\(trimmed)")
        }
        if let url = URL(string: trimmed, relativeTo: baseURL) { return url }
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            return URL(string: encoded, relativeTo: baseURL)
        }
        return nil
    }

    /// `n[@o]`；o 缺省时接上一条的结束位置
    private static func byteRange(_ value: String?, cursor: inout Int64) -> (Int64?, Int64?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        let parts = value.split(separator: "@", maxSplits: 1).map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard let length = Int64(parts[0]) else { return (nil, nil) }

        var offset: Int64
        if parts.count > 1, let explicit = Int64(parts[1]) {
            offset = explicit
        } else {
            offset = cursor
        }
        cursor = offset + length
        return (length, offset)
    }

    /// `IV=0x` + 32 位十六进制
    private static func iv(from value: String?) -> [UInt8]? {
        guard let value, value.hasPrefix("0x") else { return nil }
        let hex = String(value.dropFirst(2))
        guard hex.count == 32 else { return nil }

        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        return bytes.count == 16 ? bytes : nil
    }
}
