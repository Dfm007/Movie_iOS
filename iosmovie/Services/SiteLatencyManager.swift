import SwiftUI
import Foundation

@MainActor
final class SiteLatencyManager: ObservableObject {
    static let shared = SiteLatencyManager()

    @Published private(set) var latencies: [String: Int] = [:]  // siteID -> ms
    @Published private(set) var unreachable: Set<String> = []
    @Published private(set) var isMeasuring = false

    private init() {}

    func latency(for site: CMSSite) -> Int? {
        latencies[site.id]
    }

    func isUnreachable(_ site: CMSSite) -> Bool {
        unreachable.contains(site.id)
    }

    func color(for site: CMSSite) -> Color {
        if unreachable.contains(site.id) {
            return .red
        }
        guard let ms = latencies[site.id] else {
            return .secondary
        }
        switch ms {
        case ..<60:
            return .green
        case 60...150:
            return .orange
        default:
            return .red
        }
    }

    func latencyText(for site: CMSSite) -> String {
        if unreachable.contains(site.id) {
            return "超时"
        }
        guard let ms = latencies[site.id] else {
            return "测速中..."
        }
        return "\(ms)ms"
    }

    func measureAll(sites: [CMSSite]) async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }

        await withTaskGroup(of: (String, Int?).self) { group in
            for site in sites {
                group.addTask {
                    let ms = await Self.measureLatency(baseURL: site.baseURL)
                    return (site.id, ms)
                }
            }

            for await (siteID, ms) in group {
                if let ms {
                    latencies[siteID] = ms
                    unreachable.remove(siteID)
                } else {
                    latencies[siteID] = nil
                    unreachable.insert(siteID)
                }
            }
        }
    }

    private static func measureLatency(baseURL: String) async -> Int? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        var queryItems = components.queryItems ?? []
        queryItems.append(URLQueryItem(name: "ac", value: "list"))
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  !data.isEmpty else {
                return nil
            }
            let elapsed = Date().timeIntervalSince(start)
            return Int(elapsed * 1000)
        } catch {
            return nil
        }
    }
}