import Foundation
import SwiftUI

struct NoticeTextSegment: Equatable {
    let text: String
    let color: Color?
    let isLineBreak: Bool

    init(text: String, color: Color? = nil, isLineBreak: Bool = false) {
        self.text = text
        self.color = color
        self.isLineBreak = isLineBreak
    }

    static func lineBreak() -> NoticeTextSegment {
        NoticeTextSegment(text: "", color: nil, isLineBreak: true)
    }
}

struct Notice: Equatable {
    let title: String
    let titleSegments: [NoticeTextSegment]
    let messageSegments: [NoticeTextSegment]
}

final class NoticeManager: ObservableObject {
    @Published var notice: Notice?

    /// 公告地址：优先取远程配置（配置页），其次 Info.plist 默认值
    private var endpoint: URL? {
        AppConfig.shared.noticeEndpoint
    }

    func fetch() {
        guard let endpoint else { return }

        // 公告接口按 app_id 区分应用，并与发信接口共用同一个 token
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return }
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "app_id" }
        queryItems.append(URLQueryItem(name: "app_id", value: AppConfig.shared.appID))
        components.queryItems = queryItems
        guard let requestURL = components.url else { return }

        // 公告要实时生效：禁止读本地缓存，否则服务器把 enabled 改成 false 了，客户端还会弹旧公告
        var request = URLRequest(url: requestURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        if let token = AppConfig.shared.token {
            request.setValue(token, forHTTPHeaderField: "X-Feedback-Token")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let data,
                  let payload = Self.decodePayload(from: data) else {
                return
            }

            // 服务端开关：enabled 为 true 时每次打开都弹，false 时不弹
            guard payload.enabled ?? true,
                  let notice = Self.makeNotice(from: payload) else {
                DispatchQueue.main.async { self?.notice = nil }
                return
            }

            DispatchQueue.main.async {
                self?.notice = notice
            }
        }.resume()
    }

    /// 解析公告 JSON。手改配置文件时容易写上 `//` 注释（标准 JSON 不支持），
    /// 这里先按标准解析，失败再剥掉行注释重试一次。
    private static func decodePayload(from data: Data) -> NoticePayload? {
        if let payload = try? JSONDecoder().decode(NoticePayload.self, from: data) {
            return payload
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let withoutComments = strippingJSONComments(text)
        if let payload = try? JSONDecoder().decode(NoticePayload.self, from: Data(withoutComments.utf8)) {
            return payload
        }

        // 再宽容一点：去掉对象 / 数组结尾多余的逗号（手写配置时很常见）
        let relaxed = cleaningTrailingCommas(withoutComments)
        return try? JSONDecoder().decode(NoticePayload.self, from: Data(relaxed.utf8))
    }

    /// 去掉对象 / 数组结尾多余的逗号（JSON 标准不允许，但手写配置时容易多写）。
    private static func cleaningTrailingCommas(_ text: String) -> String {
        var result = text.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
        result = result.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        return result
    }

    /// 去掉 JSON 里的 `//` 行注释；字符串内部的 `//`（例如 URL）不会被误删。
    private static func strippingJSONComments(_ text: String) -> String {
        var result = ""
        var inString = false
        var escaped = false
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if inString {
                result.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                index = next
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
                index = next
                continue
            }

            if character == "/", next < text.endIndex, text[next] == "/" {
                while index < text.endIndex, text[index] != "\n" {
                    index = text.index(after: index)
                }
                continue
            }

            result.append(character)
            index = next
        }
        return result
    }

    static func makeNotice(from payload: NoticePayload) -> Notice? {
        let title = preprocessHTML(payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let message = preprocessHTML(payload.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !message.isEmpty else { return nil }
        return Notice(
            title: title,
            titleSegments: parseSegments(from: title),
            messageSegments: parseSegments(from: message)
        )
    }

    private static func preprocessHTML(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<br />", with: "[br]")
        result = result.replacingOccurrences(of: "<br/>", with: "[br]")
        result = result.replacingOccurrences(of: "<br>", with: "[br]")
        result = result.replacingOccurrences(of: "\r\n", with: "[br]")
        result = result.replacingOccurrences(of: "\n", with: "[br]")
        result = result.replacingOccurrences(of: "\r", with: "[br]")
        return result
    }

    static func parseSegments(from text: String) -> [NoticeTextSegment] {
        var segments: [NoticeTextSegment] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let remainingRange = currentIndex..<text.endIndex

            let brRange = text.range(of: "[br]", range: remainingRange)
            let colorRange = text.range(of: "[color=", range: remainingRange)

            if brRange == nil && colorRange == nil {
                let remaining = String(text[currentIndex..<text.endIndex])
                if !remaining.isEmpty {
                    segments.append(NoticeTextSegment(text: remaining))
                }
                break
            }

            if let br = brRange, colorRange == nil || br.lowerBound < colorRange!.lowerBound {
                if br.lowerBound > currentIndex {
                    let plainText = String(text[currentIndex..<br.lowerBound])
                    segments.append(NoticeTextSegment(text: plainText))
                }
                segments.append(.lineBreak())
                currentIndex = br.upperBound
                continue
            }

            guard let colorStartRange = colorRange else {
                let remaining = String(text[currentIndex..<text.endIndex])
                if !remaining.isEmpty {
                    segments.append(NoticeTextSegment(text: remaining))
                }
                break
            }

            if colorStartRange.lowerBound > currentIndex {
                let plainText = String(text[currentIndex..<colorStartRange.lowerBound])
                segments.append(NoticeTextSegment(text: plainText))
            }

            let afterColorTag = colorStartRange.upperBound
            guard let colorEndBracket = text.range(of: "]", range: afterColorTag..<text.endIndex) else {
                let remaining = String(text[currentIndex..<text.endIndex])
                segments.append(NoticeTextSegment(text: remaining))
                break
            }

            let hexString = String(text[afterColorTag..<colorEndBracket.lowerBound])
            let color = colorFromHex(hexString)

            guard let contentStart = text.index(colorEndBracket.upperBound, offsetBy: 0, limitedBy: text.endIndex),
                  let closeRange = text.range(of: "[/color]", range: contentStart..<text.endIndex) else {
                let remaining = String(text[currentIndex..<text.endIndex])
                segments.append(NoticeTextSegment(text: remaining))
                break
            }

            let coloredText = String(text[contentStart..<closeRange.lowerBound])
            if !coloredText.isEmpty {
                segments.append(NoticeTextSegment(text: coloredText, color: color))
            }

            currentIndex = closeRange.upperBound
        }

        return segments
    }

    private static func colorFromHex(_ hex: String) -> Color? {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") {
            cleaned.removeFirst()
        }
        guard cleaned.count == 6,
              let rgb = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }
}

/// 服务端公告 JSON 结构。
struct NoticePayload: Decodable {
    /// 总开关：true 时每次打开都弹，false 时不弹
    let enabled: Bool?
    let title: String?
    let message: String?
}
