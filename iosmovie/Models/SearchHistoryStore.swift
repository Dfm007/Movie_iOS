import Foundation

struct SearchHistoryStore {
    private static let key = "search_history"
    private static let maxCount = 20

    static func all() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func add(_ keyword: String) {
        let text = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var items = all()
        items.removeAll { $0 == text }
        items.insert(text, at: 0)

        if items.count > maxCount {
            items = Array(items.prefix(maxCount))
        }

        UserDefaults.standard.set(items, forKey: key)
    }

    static func remove(_ keyword: String) {
        var items = all()
        items.removeAll { $0 == keyword }
        UserDefaults.standard.set(items, forKey: key)
    }

    static func removeAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}