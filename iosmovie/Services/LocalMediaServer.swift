import Foundation
import Network

/// 极简本地 HTTP 服务器：把已下载的 Downloads 目录通过 http://127.0.0.1 提供给
/// AVPlayer，绕过 iOS “不支持本地 HLS(m3u8)” 的系统限制（CoreMediaErrorDomain -12865）。
///
/// 说明：
/// - 苹果明确不支持从本地文件系统直接播放 .m3u8（HLS 协议本身为 HTTP 流媒体设计）。
/// - 因此本地缓存的 movie.m3u8 + seg_* 分片必须以 http(s) 形式暴露给播放器，
///   本服务器在 App 内监听 127.0.0.1 完成这件事，无需任何第三方依赖。
/// - 仅服务 Downloads 目录，且做了目录穿越防护；分片为本地 file:// 直读，不走外网。
final class LocalMediaServer: @unchecked Sendable {

    static let shared = LocalMediaServer()

    private let baseDir: URL
    private let lock = NSLock()
    private var listener: NWListener?
    private var port: UInt16 = 0
    private var started = false

    private init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.baseDir = docs.appendingPathComponent("Downloads", isDirectory: true)
    }

    /// 本地服务基址，例如 http://127.0.0.1:18080 ；未就绪时为 nil
    var baseURL: URL? {
        lock.lock(); defer { lock.unlock() }
        guard port > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(port)")
    }

    /// 启动本地服务器（幂等，可重复调用）
    func start() {
        lock.lock()
        if started { lock.unlock(); return }
        started = true
        lock.unlock()

        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port.any)
        } catch {
            lock.lock(); started = false; lock.unlock()
            return
        }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let p = listener.port?.rawValue {
                    self?.lock.lock()
                    self?.port = p
                    self?.lock.unlock()
                }
            case .failed, .cancelled:
                self?.lock.lock()
                self?.started = false
                self?.port = 0
                self?.listener = nil
                self?.lock.unlock()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: .global(qos: .utility))
        lock.lock(); self.listener = listener; lock.unlock()
    }

    // MARK: - 连接与请求处理

    private func handle(connection: NWConnection) {
        connection.stateUpdateHandler = { _ in }
        connection.start(queue: .global(qos: .utility))
        receive(connection: connection)
    }

    private func receive(connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.respond(to: data, connection: connection)
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self?.receive(connection: connection)
        }
    }

    private func respond(to requestData: Data, connection: NWConnection) {
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, mime: "text/plain",
                         fileSize: 0, rangeStart: 0, rangeEnd: -1, isRange: false, body: nil)
            return
        }
        let lines = requestString.components(separatedBy: "\n")
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
              !firstLine.isEmpty else {
            sendResponse(connection: connection, status: 400, mime: "text/plain",
                         fileSize: 0, rangeStart: 0, rangeEnd: -1, isRange: false, body: nil)
            return
        }
        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, mime: "text/plain",
                         fileSize: 0, rangeStart: 0, rangeEnd: -1, isRange: false, body: nil)
            return
        }
        let method = String(parts[0])
        var path = String(parts[1])
        guard method == "GET" || method == "HEAD" else {
            sendResponse(connection: connection, status: 405, mime: "text/plain",
                         fileSize: 0, rangeStart: 0, rangeEnd: -1, isRange: false, body: nil)
            return
        }
        if let q = path.firstIndex(of: "?") { path = String(path[..<q]) }
        guard let decoded = path.removingPercentEncoding else {
            sendResponse(connection: connection, status: 400, mime: "text/plain",
                         fileSize: 0, rangeStart: 0, rangeEnd: -1, isRange: false, body: nil)
            return
        }

        guard let fileURL = resolve(decoded),
              FileManager.default.fileExists(atPath: fileURL.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attrs[.size] as? Int64 else {
            sendResponse(connection: connection, status: 404, mime: "text/plain",
                         fileSize: 0, rangeStart: 0, rangeEnd: -1, isRange: false, body: nil)
            return
        }

        // 解析 Range（用于拖动进度）
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = fileSize - 1
        var isRange = false
        if let rangeLine = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let raw = rangeLine.split(separator: ":", omittingEmptySubsequences: true).last,
           let parsed = parseRange(String(raw).trimmingCharacters(in: .whitespaces), total: fileSize) {
            isRange = true
            rangeStart = parsed.lowerBound
            rangeEnd = parsed.upperBound - 1
        }

        let mime = Self.mimeType(for: fileURL)
        let body: Data? = (method == "HEAD")
            ? nil
            : readFile(fileURL, from: rangeStart, to: rangeEnd)

        sendResponse(connection: connection,
                     status: isRange ? 206 : 200,
                     mime: mime,
                     fileSize: fileSize,
                     rangeStart: rangeStart,
                     rangeEnd: rangeEnd,
                     isRange: isRange,
                     body: body)
    }

    // MARK: - 路径解析（防目录穿越）

    private func resolve(_ decodedPath: String) -> URL? {
        let trimmed = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return nil }
        let comps = trimmed.split(separator: "/").map(String.init)
        let url = comps.reduce(baseDir) { $0.appendingPathComponent($1) }
        let resolved = url.standardizedFileURL
        let base = baseDir.standardizedFileURL
        guard resolved.path.hasPrefix(base.path) else { return nil }
        return url
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts":   return "video/mp2t"
        case "mp4":  return "video/mp4"
        case "key":  return "application/octet-stream"
        case "m4s", "init": return "video/mp4"
        default:     return "application/octet-stream"
        }
    }

    /// 解析 HTTP Range 头：bytes=0-1023 / bytes=1024- / bytes=-512
    private func parseRange(_ value: String, total: Int64) -> Range<Int64>? {
        let body = value.trimmingCharacters(in: .whitespaces)
        guard body.lowercased().hasPrefix("bytes=") else { return nil }
        let spec = String(body.dropFirst(6))
        guard let dash = spec.range(of: "-") else { return nil }
        let startStr = String(spec[..<dash.lowerBound])
        let endStr = String(spec[dash.upperBound...])
        if startStr.isEmpty {
            guard let n = Int64(endStr), n > 0 else { return nil }
            let start = max(0, total - n)
            return start..<total
        } else {
            guard let start = Int64(startStr) else { return nil }
            let end = endStr.isEmpty ? total - 1 : (Int64(endStr) ?? total - 1)
            let clampedEnd = min(end, total - 1)
            guard start <= clampedEnd else { return nil }
            return start..<(clampedEnd + 1)
        }
    }

    private func readFile(_ url: URL, from: Int64, to: Int64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let clampedFrom = max(0, from)
        try? handle.seek(toOffset: UInt64(clampedFrom))
        let length = to - from + 1
        guard length > 0 else { return Data() }
        return try? handle.read(upToCount: Int(length))
    }

    // MARK: - 响应发送

    private func sendResponse(connection: NWConnection, status: Int, mime: String,
                               fileSize: Int64, rangeStart: Int64, rangeEnd: Int64,
                               isRange: Bool, body: Data?) {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 206: reason = "Partial Content"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        default:  reason = "OK"
        }

        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Server: iosmovie-local\r\n"
        header += "Content-Type: \(mime)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        if isRange {
            header += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(fileSize)\r\n"
        }
        header += "Content-Length: \(body?.count ?? 0)\r\n"
        header += "Connection: close\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "\r\n"

        guard let headerData = header.data(using: .utf8) else {
            connection.cancel()
            return
        }

        connection.send(content: headerData, completion: .contentProcessed { [weak connection] _ in
            guard let connection = connection else { return }
            if let body = body, !body.isEmpty {
                connection.send(content: body, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            } else {
                connection.cancel()
            }
        })
    }
}
