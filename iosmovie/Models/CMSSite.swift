import Foundation

struct CMSSite: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let baseURL: String

    private static let storageKey = "custom_cms_sites"

    static let builtInSites: [CMSSite] = [
        CMSSite(id: "lzm3u8", name: "lzm3u8", baseURL: "http://cj.lziapi.com/api.php/provide/vod/from/lzm3u8"),
        CMSSite(id: "hnm3u8", name: "hnm3u8", baseURL: "https://hongniuzy2.com/api.php/provide/vod/from/hnm3u8")
    ]

    static var all: [CMSSite] {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let sites = try? JSONDecoder().decode([CMSSite].self, from: data),
           !sites.isEmpty {
            return sites
        }
        return builtInSites
    }

    static var defaultSite: CMSSite {
        all[0]
    }

    static func saveSites(_ sites: [CMSSite]) {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func resetToBuiltIn() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
