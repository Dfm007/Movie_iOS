import Combine
import Foundation
import Network

/// 下载偏好（持久化在 UserDefaults）。
enum DownloadPreferences {
    private static let wifiOnlyKey = "download_wifi_only"

    /// 仅 Wi-Fi 下载：开启后移动网络下不开始新下载，下载中的任务会自动暂停。
    static var wifiOnly: Bool {
        get { UserDefaults.standard.bool(forKey: wifiOnlyKey) }
        set { UserDefaults.standard.set(newValue, forKey: wifiOnlyKey) }
    }
}

/// 网络类型监控：判断当前是否走蜂窝网络，供「仅 Wi-Fi 下载」判断使用。
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    /// 当前是否在使用蜂窝网络（个人热点按 Wi-Fi 处理）
    @Published private(set) var isCellular = false
    /// 当前是否已联网
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.iosmovie.network-monitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            let cellular = connected && path.usesInterfaceType(.cellular)
            Task { @MainActor in
                guard let self else { return }
                if self.isConnected != connected { self.isConnected = connected }
                if self.isCellular != cellular { self.isCellular = cellular }
            }
        }
        monitor.start(queue: queue)
    }

    /// 当前网络是否允许开始 / 继续下载
    var allowsDownloading: Bool {
        !(DownloadPreferences.wifiOnly && isCellular)
    }
}
