import SwiftUI
import UIKit

@main
struct iosmovieApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("appearance_mode") private var appearanceMode = "system"

    init() {
        // 启动本地媒体服务器，供已下载的 HLS(m3u8) 通过 http://127.0.0.1 播放，
        // 绕过 iOS “不支持本地 HLS” 的限制（CoreMediaErrorDomain -12865）
        LocalMediaServer.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // 普通页面固定竖屏；只有播放器全屏时才允许横屏。
        PlayerOrientationState.shared.isFullScreen ? .landscapeRight : .portrait
    }
}
