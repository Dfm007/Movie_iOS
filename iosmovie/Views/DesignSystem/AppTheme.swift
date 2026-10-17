import SwiftUI
import UIKit

enum AppTheme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.00)
    static let accentSoft = accent.opacity(0.12)
    static let accentSecondary = Color(red: 0.39, green: 0.82, blue: 1.00)
    static let accentSecondarySoft = accentSecondary.opacity(0.14)
    static let danger = Color(red: 1.00, green: 0.23, blue: 0.19)
    static let warning = Color(red: 1.00, green: 0.62, blue: 0.04)
    static let success = Color(red: 0.20, green: 0.78, blue: 0.35)

    static let background = dynamic(
        light: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1),
        dark: UIColor(red: 0.04, green: 0.05, blue: 0.07, alpha: 1)
    )
    static let surface = dynamic(
        light: UIColor.white,
        dark: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    )
    static let surfaceElevated = dynamic(
        light: UIColor.white,
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    static let textPrimary = dynamic(
        light: UIColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1),
        dark: UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    )
    static let textSecondary = dynamic(
        light: UIColor(red: 0.42, green: 0.45, blue: 0.50, alpha: 1),
        dark: UIColor(red: 0.56, green: 0.56, blue: 0.58, alpha: 1)
    )
    static let border = dynamic(
        light: UIColor(red: 0.85, green: 0.85, blue: 0.87, alpha: 1),
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )
    static let mutedFill = dynamic(
        light: UIColor(red: 0.91, green: 0.91, blue: 0.93, alpha: 1),
        dark: UIColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    )

    static let radiusSmall: CGFloat = 12
    static let radiusMedium: CGFloat = 16
    static let radiusLarge: CGFloat = 24
    static let pagePadding: CGFloat = 20
    static let cardShadow = Color.black.opacity(0.055)

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

struct AppScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    AppTheme.background

                    RadialGradient(
                        colors: [AppTheme.accent.opacity(0.08), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 320
                    )

                    LinearGradient(
                        colors: [AppTheme.surface.opacity(0.22), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func appScreenBackground() -> some View {
        modifier(AppScreenBackground())
    }
}
