import SwiftUI

@main
struct iosmovieApp: App {
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