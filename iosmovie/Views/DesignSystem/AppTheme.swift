import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 0.96, green: 0.62, blue: 0.16)
    static let accentSoft = accent.opacity(0.16)
    static let accentSecondary = Color(red: 0.18, green: 0.78, blue: 0.70)
    static let accentSecondarySoft = accentSecondary.opacity(0.16)
    static let danger = Color(red: 0.94, green: 0.30, blue: 0.32)
    static let warning = Color(red: 0.96, green: 0.60, blue: 0.16)
    static let success = Color(red: 0.25, green: 0.78, blue: 0.48)

    static let background = dynamic(
        light: UIColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    )
    static let surface = dynamic(
        light: UIColor.white,
        dark: UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
    )
    static let surfaceElevated = dynamic(
        light: UIColor.white,
        dark: UIColor(red: 0.11, green: 0.13, blue: 0.17, alpha: 1)
    )
    static let textPrimary = dynamic(
        light: UIColor(red: 0.07, green: 0.08, blue: 0.10, alpha: 1),
        dark: UIColor(red: 0.96, green: 0.97, blue: 0.99, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1),
        dark: UIColor(red: 0.61, green: 0.64, blue: 0.70, alpha: 1)
    )
    static let border = dynamic(
        light: UIColor(red: 0.89, green: 0.90, blue: 0.92, alpha: 1),
        dark: UIColor(red: 0.16, green: 0.18, blue: 0.24, alpha: 1)
    )
    static let mutedFill = dynamic(
        light: UIColor(red: 0.93, green: 0.94, blue: 0.95, alpha: 1),
        dark: UIColor(red: 0.13, green: 0.15, blue: 0.20, alpha: 1)
    )

    static let radiusSmall: CGFloat = 10
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 22
    static let pagePadding: CGFloat = 16

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct AppScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.background.ignoresSafeArea())
    }
}

extension View {
    func appScreenBackground() -> some View {
        modifier(AppScreenBackground())
    }
}
