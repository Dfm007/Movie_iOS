import Foundation

extension Notification.Name {
    static let defaultSourceDidChange = Notification.Name("defaultSourceDidChange")
}

struct CMSSite: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let baseURL: String

    private static let storageKey = "custom_cms_sites"
    private static let defaultSiteKey = "default_cms_site_id"

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

    static var selectedDefaultSite: CMSSite {
        let savedID = UserDefaults.standard.string(forKey: defaultSiteKey)
        return all.first(where: { $0.id == savedID }) ?? all[0]
    }

    static func saveDefaultSiteID(_ id: String) {
        UserDefaults.standard.set(id, forKey: defaultSiteKey)
    }

    static func saveSites(_ sites: [CMSSite]) {
        if let data = try? JSONEncoder().encode(sites) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func resetToBuiltIn() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: defaultSiteKey)
    }
}