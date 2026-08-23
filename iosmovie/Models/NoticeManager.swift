import Foundation
import SwiftUI

struct NoticeTextSegment: Equatable {
    let text: String
    let color: Color?
}

struct Notice: Equatable {
    let title: String
    let titleSegments: [NoticeTextSegment]
    let messageSegments: [NoticeTextSegment]
}

final class NoticeManager: ObservableObject {
    @Published var notice: Notice?

    private let noticeURL = URL(string: "https://dfm.lanzoub.com/b06lks1yb")!

    func fetch() {
        URLSession.shared.dataTask(with: noticeURL) { [weak self] data, _, _ in
            guard let data = data,
                  let html = String(data: data, encoding: .utf8) else {
                return
            }
            let notice = Self.parse(html: html)
            DispatchQueue.main.async {
                self?.notice = notice
            }
        }.resume()
    }

    static func parse(html: String) -> Notice? {
        guard let title = extract(html, tag: "title"),
              let message = extract(html, tag: "message") else {
            return nil
        }
        return Notice(
            title: title,
            titleSegments: parseSegments(from: title),
            messageSegments: parseSegments(from: message)
        )
    }

    private static func extract(_ text: String, tag: String) -> String? {
        let startTag = "[\(tag)]"
        let endTag = "[/\(tag)]"
        guard let startRange = text.range(of: startTag),
              let endRange = text.range(of: endTag, range: startRange.upperBound..<text.endIndex) else {
            return nil
        }
        let value = String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func parseSegments(from text: String) -> [NoticeTextSegment] {
        var segments: [NoticeTextSegment] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            guard let colorStartRange = text.range(of: "[color=", range: currentIndex..<text.endIndex) else {
                let remaining = String(text[currentIndex..<text.endIndex])
                if !remaining.isEmpty {
                    segments.append(NoticeTextSegment(text: remaining, color: nil))
                }
                break
            }

            if colorStartRange.lowerBound > currentIndex {
                let plainText = String(text[currentIndex..<colorStartRange.lowerBound])
                segments.append(NoticeTextSegment(text: plainText, color: nil))
            }

            let afterColorTag = colorStartRange.upperBound
            guard let colorEndBracket = text.range(of: "]", range: afterColorTag..<text.endIndex) else {
                let remaining = String(text[currentIndex..<text.endIndex])
                segments.append(NoticeTextSegment(text: remaining, color: nil))
                break
            }

            let hexString = String(text[afterColorTag..<colorEndBracket.lowerBound])
            let color = colorFromHex(hexString)

            guard let contentStart = text.index(colorEndBracket.upperBound, offsetBy: 0, limitedBy: text.endIndex),
                  let closeRange = text.range(of: "[/color]", range: contentStart..<text.endIndex) else {
                let remaining = String(text[currentIndex..<text.endIndex])
                segments.append(NoticeTextSegment(text: remaining, color: nil))
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