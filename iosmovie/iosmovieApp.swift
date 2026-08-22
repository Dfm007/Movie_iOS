import SwiftUI
import UIKit

class LandscapeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .landscape
    }
}

@main
struct iosmovieApp: App {
    @UIApplicationDelegateAdaptor(LandscapeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}