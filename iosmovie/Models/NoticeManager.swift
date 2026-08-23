import Foundation

struct Notice: Equatable {
    let title: String
    let message: String
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
        return Notice(title: title, message: message)
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
}