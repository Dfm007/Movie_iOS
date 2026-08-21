import Foundation

struct CMSSite: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String

    static let all: [CMSSite] = [
        CMSSite(id: "lzm3u8", name: "lzm3u8", baseURL: "http://cj.lziapi.com/api.php/provide/vod/from/lzm3u8"),
        CMSSite(id: "hnm3u8", name: "hnm3u8", baseURL: "https://hongniuzy2.com/api.php/provide/vod/from/hnm3u8")
    ]

    static var defaultSite: CMSSite {
        all[0]
    }
}